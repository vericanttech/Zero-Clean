// ─────────────────────────────────────────────
//  ZERO-CLEAN  ·  App State Provider
// ─────────────────────────────────────────────

import 'package:flutter/foundation.dart';
import '../models/models.dart';
import '../services/database_service.dart';
import '../services/filesystem_service.dart';

class AppState extends ChangeNotifier {
  final _db = DatabaseService.instance;
  final _fs = FileSystemService.instance;

  // ── Selection state ────────────────────────
  Shop? selectedShop;
  String? selectedCategory;
  Variant? selectedVariant;
  CaptureContext selectedContext = CaptureContext.single;

  // ── Data ──────────────────────────────────
  List<Shop> shops = [];
  List<String> categories = [];
  List<Variant> variants = [];
  List<Progress> shopProgress = [];
  Map<String, int> totalStats = {};

  bool showUnderCollectedOnly = false;
  bool isLoading = false;

  /// Set when init() or refreshFromDatabase() fails; cleared on success.
  String? loadError;

  void toggleShowUnderCollectedOnly() {
    showUnderCollectedOnly = !showUnderCollectedOnly;
    notifyListeners();
  }

  Future<void> init() async {
    isLoading = true;
    loadError = null;
    notifyListeners();
    try {
      shops = await _db.getShops();
      categories = await _db.getCategories();
      variants = await _db.getVariants();
      totalStats = await _db.getTotalStats();

      if (shops.isNotEmpty) {
        selectedShop = shops.first;
        await refreshProgress();
      }
      loadError = null;
    } catch (e, stackTrace) {
      loadError = e.toString();
      if (kDebugMode) {
        // ignore: avoid_print
        print('AppState.init error: $e');
        // ignore: avoid_print
        print(stackTrace);
      }
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<void> refreshProgress() async {
    if (selectedShop == null) return;
    shopProgress = await _db.getProgressForShop(selectedShop!.id!);
    totalStats = await _db.getTotalStats();
    notifyListeners();
  }

  /// Reload shops, variants, categories and progress from DB. Call when
  /// switching to Dashboard/Setup/Review so they always show latest data.
  Future<void> refreshFromDatabase() async {
    loadError = null;
    try {
      shops = await _db.getShops();
      categories = await _db.getCategories();
      variants = await _db.getVariants();
      // Re-bind selection to the new list instances so dropdowns find value in items
      final prevShopId = selectedShop?.id;
      final prevVariantId = selectedVariant?.id;
      if (prevShopId != null && shops.isNotEmpty) {
        try {
          selectedShop = shops.firstWhere((s) => s.id == prevShopId);
        } catch (_) {
          selectedShop = shops.first;
        }
      } else if (shops.isNotEmpty) {
        selectedShop = shops.first;
      } else {
        selectedShop = null;
      }
      if (prevVariantId != null && variants.isNotEmpty) {
        try {
          selectedVariant = variants.firstWhere((v) => v.id == prevVariantId);
        } catch (_) {
          selectedVariant = null;
        }
      } else {
        selectedVariant = null;
      }
      if (selectedShop != null) {
        await refreshProgress();
      } else {
        totalStats = await _db.getTotalStats();
      }
      loadError = null;
    } catch (e, stackTrace) {
      loadError = e.toString();
      if (kDebugMode) {
        // ignore: avoid_print
        print('AppState.refreshFromDatabase error: $e');
        // ignore: avoid_print
        print(stackTrace);
      }
    }
    notifyListeners();
  }

  Future<void> selectShop(Shop shop) async {
    selectedShop = shop;
    selectedVariant = null;
    selectedCategory = null;
    await refreshProgress();
  }

  Future<void> selectCategory(String cat) async {
    selectedCategory = cat;
    selectedVariant = null;
    notifyListeners();
  }

  /// Variants in the currently selected category (for Capture screen only).
  /// [variants] stays the full list so Dashboard, Setup, Review always see all.
  List<Variant> get variantsInSelectedCategory {
    if (selectedCategory == null) return [];
    return variants.where((v) => v.category == selectedCategory).toList();
  }

  void selectVariant(Variant v) {
    selectedVariant = v;
    notifyListeners();
  }

  void selectContext(CaptureContext ctx) {
    selectedContext = ctx;
    notifyListeners();
  }

  bool get canOpenCamera =>
      selectedShop != null &&
      selectedCategory != null &&
      selectedVariant != null;

  Progress? get currentProgress {
    if (selectedVariant == null || selectedShop == null) return null;
    try {
      return shopProgress.firstWhere(
        (p) =>
            p.variantId == selectedVariant!.id &&
            p.shopId == selectedShop!.id &&
            p.context == selectedContext,
      );
    } catch (_) {
      return null;
    }
  }

  bool get isCurrentSaturated {
    final prog = currentProgress;
    return prog != null && prog.pct >= 1.0;
  }

  List<VariantSummary> get variantSummaries {
    final all = <VariantSummary>[];
    for (final v in variants) {
      final progList = shopProgress.where((p) => p.variantId == v.id).toList();
      if (showUnderCollectedOnly &&
          progList.every((p) => p.status != ProgressStatus.critical)) {
        continue;
      }
      all.add(VariantSummary(variant: v, progress: progList));
    }
    return all;
  }

  /// Called when a capture is moved from Unprocessed to a context folder (from nudge save).
  Future<void> recordCaptureFor(
    int variantId,
    int shopId,
    CaptureContext context,
  ) async {
    await _db.ensureProgressRow(variantId, shopId, context);
    await _db.incrementCount(variantId, shopId, context);
    await refreshProgress();
  }

  Future<String> buildUnprocessedPath() async {
    if (selectedShop == null) throw StateError('No shop selected');
    return _fs.getUnprocessedPath(shopName: selectedShop!.name);
  }

  Future<void> addShop(String name, String locationNote) async {
    final id = await _db.insertShop(Shop(name: name, locationNote: locationNote));
    shops = await _db.getShops();
    selectedShop = shops.firstWhere((s) => s.id == id);
    await refreshProgress();
    notifyListeners();
  }

  Future<void> addVariant(Variant v) async {
    final id = await _db.insertVariant(v);
    variants = await _db.getVariants();
    categories = await _db.getCategories();
    // Ensure progress rows exist for current shop
    if (selectedShop != null) {
      for (final ctx in CaptureContext.values) {
        await _db.ensureProgressRow(id, selectedShop!.id!, ctx);
      }
      await refreshProgress();
    }
    notifyListeners();
  }
}

class VariantSummary {
  final Variant variant;
  final List<Progress> progress;
  VariantSummary({required this.variant, required this.progress});

  double get overallPct {
    if (progress.isEmpty) return 0;
    return progress.map((p) => p.pct).reduce((a, b) => a + b) /
        progress.length;
  }

  ProgressStatus get overallStatus {
    if (overallPct < 0.30) return ProgressStatus.critical;
    if (overallPct < 1.00) return ProgressStatus.building;
    return ProgressStatus.saturated;
  }
}
