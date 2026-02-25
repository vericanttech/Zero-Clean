// ─────────────────────────────────────────────
//  ZERO-CLEAN  ·  App State Provider
//  Reads from SQLite (no network). Sync with Firestore on explicit refresh or when pushing changes.
// ─────────────────────────────────────────────

import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/models.dart';
import '../services/firestore_service.dart';
import '../services/filesystem_service.dart';
import '../services/local_db_service.dart';
import '../services/sync_service.dart';
import '../utils/variant_duplicate_check.dart';

const String _kCurrentShopIdKey = 'zero_clean_current_shop_id';
const String _kCurrentUserIdKey = 'zero_clean_current_user_id';

class AppState extends ChangeNotifier {
  final _fs = FirestoreService.instance;
  final _fileSys = FileSystemService.instance;
  final _local = LocalDbService.instance;
  final _sync = SyncService.instance;

  Shop? selectedShop;
  String? selectedCategory;
  Variant? selectedVariant;
  CaptureContext selectedContext = CaptureContext.single;

  List<Shop> shops = [];
  List<String> categories = [];
  List<Variant> variants = [];
  List<Progress> shopProgress = [];
  Map<String, int> totalStats = {};

  bool showUnderCollectedOnly = false;
  bool isLoading = false;
  String? loadError;

  /// Set when addVariant finds a fuzzy duplicate; UI shows this as the matched name. Cleared on next add attempt.
  String? duplicateOfFullLabel;

  /// True while a write or sync is in progress.
  bool _isSyncingOrWriting = false;
  bool get isSyncingOrWriting => _isSyncingOrWriting;

  /// Variant ids still in the pending_sync queue (not yet pushed). Only these show "sync first".
  Set<String> _pendingVariantIds = {};

  /// True after init when this user has at least one shop in Firestore (so we show app; Pull is for loading local copy).
  bool hasAssignedShop = false;

  void toggleShowUnderCollectedOnly() {
    showUnderCollectedOnly = !showUnderCollectedOnly;
    notifyListeners();
  }

  /// Load from local SQLite only (no network). Firebase is only used when user taps Sync or Pull.
  Future<void> init() async {
    isLoading = true;
    loadError = null;
    hasAssignedShop = false;
    notifyListeners();
    try {
      if (FirebaseAuth.instance.currentUser == null) {
        await _local.clearAll();
        await _clearPersistedShopId();
        shops = [];
        categories = [];
        variants = [];
        shopProgress = [];
        totalStats = {'total_images': 0, 'total_variants': 0};
        selectedShop = null;
        selectedVariant = null;
        _pendingVariantIds = {};
        loadError = null;
        isLoading = false;
        notifyListeners();
        return;
      }
      hasAssignedShop = true;
      await _loadFromLocal();
      final prefs = await SharedPreferences.getInstance();
      final storedShopId = prefs.getString(_kCurrentShopIdKey);
      final storedUserId = prefs.getString(_kCurrentUserIdKey);
      final currentUid = FirebaseAuth.instance.currentUser?.uid;
      final isDifferentUser = currentUid != null && storedUserId != null && storedUserId != currentUid;
      if (isDifferentUser && shops.isNotEmpty) {
        await _local.clearAll();
        await _clearPersistedShopId();
        await _loadFromLocal();
      } else if (shops.isNotEmpty && storedShopId != null) {
        final firstId = shops.first.id;
        if (firstId != null && firstId != storedShopId) {
          await _local.clearAll();
          await _clearPersistedShopId();
          await _loadFromLocal();
        }
      }
      if (shops.isNotEmpty && selectedShop?.id != null) {
        await _setPersistedShopId(selectedShop!.id);
      }
      loadError = null;
    } catch (e, stackTrace) {
      loadError = e.toString();
      if (kDebugMode) {
        print('AppState.init error: $e');
        print(stackTrace);
      }
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<void> _clearPersistedShopId() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kCurrentShopIdKey);
    await prefs.remove(_kCurrentUserIdKey);
  }

  Future<void> _setPersistedShopId(String? shopId) async {
    final prefs = await SharedPreferences.getInstance();
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (shopId == null || uid == null) {
      await prefs.remove(_kCurrentShopIdKey);
      await prefs.remove(_kCurrentUserIdKey);
    } else {
      await prefs.setString(_kCurrentShopIdKey, shopId);
      await prefs.setString(_kCurrentUserIdKey, uid);
    }
  }

  Future<String?> _getPersistedShopId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kCurrentShopIdKey);
  }

  /// Reload state from SQLite only (no network). Use after Sync/Pull or to refresh UI.
  Future<void> refreshFromLocal() async {
    loadError = null;
    try {
      if (FirebaseAuth.instance.currentUser == null) return;
      await _loadFromLocal();
      if (shops.isNotEmpty && selectedShop?.id != null) {
        try {
          selectedShop = shops.firstWhere((s) => s.id == selectedShop!.id);
        } catch (_) {
          selectedShop = shops.first;
        }
      } else if (shops.isNotEmpty) {
        selectedShop = shops.first;
      }
    } catch (e, stackTrace) {
      loadError = e.toString();
      if (kDebugMode) {
        print('AppState.refreshFromLocal error: $e');
        print(stackTrace);
      }
    }
    notifyListeners();
  }

  /// Push pending data to Firestore (user-triggered Sync). No pull.
  Future<void> syncNow() async {
    if (_isSyncingOrWriting) return;
    loadError = null;
    _isSyncingOrWriting = true;
    notifyListeners();
    try {
      if (FirebaseAuth.instance.currentUser == null) return;
      await _sync.pushPendingOnly();
      await _loadFromLocal();
      _pendingVariantIds = await _local.getPendingVariantIds();
    } catch (e, stackTrace) {
      loadError = e.toString();
      if (kDebugMode) {
        print('AppState.syncNow error: $e');
        print(stackTrace);
      }
      rethrow;
    } finally {
      _isSyncingOrWriting = false;
      notifyListeners();
    }
  }

  /// Pull from Firestore into SQLite (user-triggered). Only use when there is no local data (shops.isEmpty).
  /// Ensures user has a shop in Firestore (creates with UID if needed) before pulling.
  Future<void> pullNow() async {
    if (_isSyncingOrWriting) return;
    if (shops.isNotEmpty) return;
    loadError = null;
    _isSyncingOrWriting = true;
    notifyListeners();
    try {
      if (FirebaseAuth.instance.currentUser == null) return;
      List<Shop> assigned = await _fs.getShops();
      if (assigned.isEmpty) {
        await _fs.ensureShopForCurrentUser();
        assigned = await _fs.getShops();
      }
      if (assigned.isEmpty) {
        loadError = 'Aucun magasin attribué.';
        return;
      }
      final currentShopId = assigned.first.id!;
      final storedShopId = await _getPersistedShopId();
      if (shops.isNotEmpty && storedShopId != null && storedShopId != currentShopId) {
        await _local.clearAll();
        await _clearPersistedShopId();
      }
      await _sync.pullFromRemote();
      await _setPersistedShopId(currentShopId);
      await _loadFromLocal();
    } catch (e, stackTrace) {
      loadError = e.toString();
      if (kDebugMode) {
        print('AppState.pullNow error: $e');
        print(stackTrace);
      }
      rethrow;
    } finally {
      _isSyncingOrWriting = false;
      notifyListeners();
    }
  }

  Future<void> _loadFromLocal() async {
    shops = await _local.getShops();
    _pendingVariantIds = await _local.getPendingVariantIds();
    if (shops.isEmpty) {
      categories = [];
      variants = [];
      shopProgress = [];
      totalStats = {'total_images': 0, 'total_variants': 0};
      selectedShop = null;
      selectedVariant = null;
      return;
    }
    selectedShop ??= shops.first;
    final shopId = selectedShop!.id!;
    categories = await _local.getCategories(shopId);
    variants = await _local.getVariants(shopId);
    shopProgress = await _local.getProgressForShop(shopId);
    totalStats = await _local.getTotalStats();
  }

  /// Progress: read from local only (no network).
  Future<void> refreshProgress() async {
    if (selectedShop == null || selectedShop!.id == null) return;
    shopProgress = await _local.getProgressForShop(selectedShop!.id!);
    totalStats = await _local.getTotalStats();
    notifyListeners();
  }

  /// Reload from local SQLite only (no network). Replaces old refreshFromDatabase for manual sync model.
  Future<void> refreshFromDatabase() async {
    await refreshFromLocal();
  }

  Future<void> selectShop(Shop shop) async {
    selectedShop = shop;
    selectedVariant = null;
    selectedCategory = null;
    categories = await _local.getCategories(shop.id!);
    variants = await _local.getVariants(shop.id!);
    shopProgress = await _local.getProgressForShop(shop.id!);
    totalStats = await _local.getTotalStats();
    notifyListeners();
  }

  Future<void> selectCategory(String cat) async {
    selectedCategory = cat;
    selectedVariant = null;
    notifyListeners();
  }

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

  /// True when the selected variant is in the pending queue (not yet pushed to Firestore). Used for optional UI hint only; capture is allowed.
  bool get isSelectedVariantUnsynced =>
      selectedVariant != null && _isVariantUnsynced(selectedVariant!);

  bool _isVariantUnsynced(Variant v) =>
      v.id != null &&
      v.id!.startsWith('local_') &&
      _pendingVariantIds.contains(v.id);

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

  /// Update local progress after a capture is processed. Firestore is updated by processAndUploadToFirebase.
  /// Does not notifyListeners; caller should call refreshProgress() once if batching.
  Future<void> recordCaptureFor(
    String variantId,
    String shopId,
    CaptureContext context,
  ) async {
    await _local.incrementProgressCount(variantId, shopId, context);
  }

  Future<String> buildUnprocessedPath() async {
    if (selectedShop == null) throw StateError('No shop selected');
    return _fileSys.getUnprocessedPath(shopName: selectedShop!.name);
  }

  /// Update current shop profile (name, location_note, GPS). Local only; pushed to Firestore when user taps Sync.
  Future<void> updateShopProfile({String? name, String? locationNote, double? latitude, double? longitude}) async {
    if (selectedShop == null || selectedShop!.id == null) return;
    final shopId = selectedShop!.id!;
    final current = selectedShop!;
    final hasUpdates = name != null || locationNote != null || latitude != null || longitude != null;
    if (!hasUpdates) return;
    final updated = Shop(
      id: shopId,
      name: name ?? current.name,
      locationNote: locationNote ?? current.locationNote,
      latitude: latitude ?? current.latitude,
      longitude: longitude ?? current.longitude,
    );
    await _local.updateShop(updated);
    await _sync.queueShopProfile(shopId, name: updated.name, locationNote: updated.locationNote, latitude: updated.latitude, longitude: updated.longitude);
    final idx = shops.indexWhere((s) => s.id == shopId);
    if (idx >= 0) shops[idx] = updated;
    selectedShop = updated;
    notifyListeners();
  }

  /// Admin/backend only: create a shop (not used by normal login flow).
  Future<void> addShop(String name, String locationNote, {double? latitude, double? longitude}) async {
    final shop = await _fs.getOrCreateUserShop(
      name: name,
      locationNote: locationNote,
      latitude: latitude,
      longitude: longitude,
    );
    if (shop != null) {
      await _local.insertShop(shop);
      shops = await _local.getShops();
      selectedShop = shop;
      await refreshProgress();
    }
    notifyListeners();
  }

  Future<void> addVariant(Variant v) async {
    if (selectedShop == null || selectedShop!.id == null) return;
    duplicateOfFullLabel = null;
    final shopId = selectedShop!.id!;
    final existing = await _local.getVariants(shopId);
    final duplicate = findFuzzyDuplicateVariant(v, existing);
    if (duplicate != null) {
      duplicateOfFullLabel = duplicate.fullLabel;
      notifyListeners();
      return;
    }
    _isSyncingOrWriting = true;
    notifyListeners();
    try {
      final localId = await _local.insertVariant(shopId, v);
      for (final ctx in CaptureContext.values) {
        await _local.ensureProgressRow(localId, shopId, ctx);
      }
      await _sync.queueVariant(shopId, v, localId);
      _pendingVariantIds.add(localId);
      variants = await _local.getVariants(shopId);
      categories = await _local.getCategories(shopId);
      shopProgress = await _local.getProgressForShop(shopId);
      totalStats = await _local.getTotalStats();
    } finally {
      _isSyncingOrWriting = false;
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
