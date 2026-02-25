// ─────────────────────────────────────────────
//  ZERO-CLEAN  ·  File System Service
//  Unprocessed: app internal storage. Processed: upload to Firebase, then move to
//  reference cache (72h retention, 2 GB cap) so user can check last angle next day.
// ─────────────────────────────────────────────

import 'dart:io';
import 'dart:convert';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import '../models/models.dart';
import '../utils/device_utils.dart';
import 'firestore_service.dart';
import 'firebase_storage_service.dart';

class FileSystemService {
  static final FileSystemService instance = FileSystemService._internal();
  FileSystemService._internal();

  /// Reference cache: 72h retention, 2 GB cap. Processed images kept for angle reference.
  static const int _retentionHours = 72;
  static const int _storageCapBytes = 2 * 1024 * 1024 * 1024; // 2 GB

  /// App internal storage for Unprocessed captures only.
  Future<Directory> get _unprocessedRoot async {
    final dir = await getApplicationDocumentsDirectory();
    final root = Directory(p.join(dir.path, 'ZeroClean_Unprocessed'));
    if (!await root.exists()) await root.create(recursive: true);
    return root;
  }

  /// Processed images kept for reference (angle check). Subject to retention + cap.
  Future<Directory> get _referenceRoot async {
    final dir = await getApplicationDocumentsDirectory();
    final root = Directory(p.join(dir.path, 'ZeroClean_Reference'));
    if (!await root.exists()) await root.create(recursive: true);
    return root;
  }

  /// Returns the unprocessed folder for a shop (app internal storage).
  Future<String> getUnprocessedPath({required String shopName}) async {
    final root = await _unprocessedRoot;
    return p.join(root.path, _sanitize(shopName), 'Unprocessed');
  }

  /// List processed images in the reference cache (72h retention). Optionally filter by [shopContext] (e.g. 'single', 'shelf', 'checkout').
  /// Returns list of maps: { 'imagePath': path, 'jsonPath': path, 'meta': decoded json }.
  Future<List<Map<String, dynamic>>> listReferenceCacheImages({String? shopContext}) async {
    final root = await _referenceRoot;
    if (!await root.exists()) return [];

    final results = <Map<String, dynamic>>[];
    await for (final entity in root.list()) {
      if (entity is! File || !entity.path.toLowerCase().endsWith('.jpg')) continue;
      final imagePath = entity.path;
      final baseName = p.withoutExtension(p.basename(imagePath));
      final jsonPath = p.join(root.path, '$baseName.json');
      final jsonFile = File(jsonPath);
      if (!await jsonFile.exists()) continue;

      Map<String, dynamic> meta;
      try {
        meta = jsonDecode(await jsonFile.readAsString()) as Map<String, dynamic>;
      } catch (_) {
        continue;
      }

      if (shopContext != null) {
        final ctx = meta['context'] as String? ?? meta['shop_context'] as String?;
        final matches = ctx == shopContext;
        final legacy = (ctx == null || ctx == 'unprocessed') && shopContext == 'single';
        if (!matches && !legacy) continue;
      }

      results.add({
        'imagePath': imagePath,
        'jsonPath': jsonPath,
        'meta': meta,
      });
    }

    // Sort by modification time newest first (same as unprocessed reversed)
    final withMtime = <({Map<String, dynamic> r, DateTime m})>[];
    for (final r in results) {
      try {
        final m = await File(r['imagePath'] as String).stat();
        withMtime.add((r: r, m: m.modified));
      } catch (_) {}
    }
    withMtime.sort((a, b) => b.m.compareTo(a.m));
    return withMtime.map((e) => e.r).toList();
  }

  static String _sanitize(String s) => s.replaceAll(RegExp(r'[^\w\-.]'), '_');

  /// Creates directory if it doesn't exist. Returns the Directory.
  Future<Directory> prepareDirectory(String fullPath) async {
    final dir = Directory(fullPath);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// Saves image + ID-based JSON sidecar to unprocessed folder. Does not increment DB count.
  /// [shopId] and [context] stored in JSON; folder path still uses [shopName] for compatibility.
  Future<String> captureToUnprocessed({
    required String unprocessedPath,
    required String tempImagePath,
    required String shopId,
    required String shopName,
    required CaptureContext context,
    required List<Annotation> annotations,
    int imageWidth = 1080,
    int imageHeight = 2400,
  }) async {
    await prepareDirectory(unprocessedPath);

    final ts = DateTime.now().millisecondsSinceEpoch;
    final fileName = 'IMG_$ts';

    final destImagePath = p.join(unprocessedPath, '$fileName.jpg');
    await File(tempImagePath).copy(destImagePath);

    final deviceModel = await getDeviceModel();
    final record = ImageRecord(
      imageId: '$fileName.jpg',
      shopId: shopId,
      context: context.name,
      width: imageWidth,
      height: imageHeight,
      annotations: annotations,
      deviceModel: deviceModel,
    );

    final jsonPath = p.join(unprocessedPath, '$fileName.json');
    await File(jsonPath).writeAsString(
      const JsonEncoder.withIndent('  ').convert(record.toJson()),
    );

    return destImagePath;
  }

  /// Validates JSON has annotations and context (shop_context or context). Returns true if valid.
  bool validateProcessedJson(Map<String, dynamic> fullJson) {
    final annotations = fullJson['annotations'] as List?;
    final contextStr = fullJson['context'] as String? ?? fullJson['shop_context'] as String?;
    return annotations != null &&
        annotations.isNotEmpty &&
        contextStr != null &&
        contextStr.isNotEmpty &&
        contextStr != 'unprocessed';
  }

  /// Process unprocessed capture locally only: validate JSON, move to reference cache. No Firebase.
  /// Returns a payload map to queue for Sync (processed_image). Caller should recordCaptureFor locally and add pending.
  /// Supports ID-based JSON (annotations[].variant_id) and legacy (full_label resolved via variantsByFullLabel).
  Future<Map<String, dynamic>> processLocallyOnly({
    required String currentImagePath,
    required String currentJsonPath,
    required Map<String, dynamic> fullJson,
    required String shopId,
    required String userId,
    required CaptureContext context,
    required Map<String, Variant> variantsByFullLabel,
  }) async {
    if (!validateProcessedJson(fullJson)) {
      throw StateError('Invalid JSON: need non-empty annotations and context');
    }
    final imageFile = File(currentImagePath);
    if (!await imageFile.exists()) throw StateError('Image file not found');

    final imageId = p.basename(currentImagePath);
    final baseName = p.withoutExtension(imageId);

    final refRoot = await _referenceRoot;
    final refImagePath = p.join(refRoot.path, imageId);
    final refJsonPath = p.join(refRoot.path, '$baseName.json');
    await imageFile.rename(refImagePath);
    final jsonForCache = Map<String, dynamic>.from(fullJson);
    jsonForCache['context'] = context.name;
    jsonForCache['shop_context'] = context.name;
    await File(refJsonPath).writeAsString(
      const JsonEncoder.withIndent('  ').convert(jsonForCache),
    );
    final jsonFile = File(currentJsonPath);
    if (await jsonFile.exists()) await jsonFile.delete();

    final fullMetadata = Map<String, dynamic>.from(fullJson);
    fullMetadata['context'] = context.name;
    fullMetadata['shop_context'] = context.name;
    fullMetadata.remove('shop_name');
    fullMetadata.remove('category');
    fullMetadata.remove('variant_label');
    fullMetadata['image_id'] = imageId;
    fullMetadata['shop_id'] = shopId;

    final annotations = fullJson['annotations'] as List;
    final variantIds = <String>[];
    String? firstVariantId;
    for (final a in annotations) {
      final m = a as Map;
      final vid = m['variant_id']?.toString() ?? m['variantId']?.toString();
      if (vid != null && vid.isNotEmpty) {
        if (!variantIds.contains(vid)) variantIds.add(vid);
        firstVariantId ??= vid;
      } else {
        final fullLabel = m['full_label'] as String?;
        final v = fullLabel != null ? variantsByFullLabel[fullLabel] : null;
        if (v?.id != null && !variantIds.contains(v!.id)) {
          variantIds.add(v.id!);
          firstVariantId ??= v.id;
        }
      }
    }

    await runRetentionCleanup();

    return {
      'ref_image_path': refImagePath,
      'ref_json_path': refJsonPath,
      'image_id': imageId,
      'base_name': baseName,
      'shop_id': shopId,
      'user_id': userId,
      'context': context.name,
      'full_metadata': fullMetadata,
      'variant_ids': variantIds,
      'first_variant_id': firstVariantId ?? '',
    };
  }

  /// Process unprocessed capture: validate JSON, upload to Storage (simple path), write image doc, update progress.
  /// Local image+JSON are moved to reference cache (72h retention, 2 GB cap).
  /// Supports ID-based annotations (variant_id) and legacy (full_label via variantsByFullLabel).
  Future<void> processAndUploadToFirebase({
    required String currentImagePath,
    required String currentJsonPath,
    required Map<String, dynamic> fullJson,
    required String shopId,
    required String userId,
    required CaptureContext context,
    required Map<String, Variant> variantsByFullLabel,
  }) async {
    if (!validateProcessedJson(fullJson)) {
      throw StateError('Invalid JSON: need non-empty annotations and context');
    }
    final annotations = fullJson['annotations'] as List;
    final imageFile = File(currentImagePath);
    if (!await imageFile.exists()) throw StateError('Image file not found');

    final imageId = p.basename(currentImagePath);
    final baseName = p.withoutExtension(imageId);

    final storagePath = await FirebaseStorageService.instance.uploadProcessedImage(
      imageFile: imageFile,
      userId: userId,
      shopId: shopId,
      imageId: imageId,
    );

    final variantIds = <String>[];
    String? firstVariantId;
    for (final a in annotations) {
      final m = a as Map;
      final vid = m['variant_id']?.toString() ?? m['variantId']?.toString();
      if (vid != null && vid.isNotEmpty) {
        if (!variantIds.contains(vid)) variantIds.add(vid);
        firstVariantId ??= vid;
      } else {
        final fullLabel = m['full_label'] as String?;
        final v = fullLabel != null ? variantsByFullLabel[fullLabel] : null;
        if (v?.id != null && !variantIds.contains(v!.id)) {
          variantIds.add(v.id!);
          firstVariantId ??= v.id;
        }
      }
    }

    final fs = FirestoreService.instance;
    final fullMetadata = Map<String, dynamic>.from(fullJson);
    fullMetadata['context'] = context.name;
    fullMetadata['shop_context'] = context.name;
    fullMetadata.remove('shop_name');
    fullMetadata.remove('category');
    fullMetadata.remove('variant_label');
    fullMetadata['image_id'] = imageId;
    fullMetadata['shop_id'] = shopId;

    await fs.addImageDoc(
      imageId: baseName,
      storagePath: storagePath,
      userId: userId,
      shopId: shopId,
      variantId: firstVariantId ?? '',
      context: context.name,
      fullMetadata: fullMetadata,
    );

    for (final variantId in variantIds) {
      await fs.ensureProgressRow(variantId, shopId, context);
      await fs.incrementCount(variantId, shopId, context);
    }
    await fs.incrementStatsTotal(shopId);

    final refRoot = await _referenceRoot;
    final refImagePath = p.join(refRoot.path, imageId);
    final refJsonPath = p.join(refRoot.path, '$baseName.json');
    await imageFile.rename(refImagePath);
    final jsonFile = File(currentJsonPath);
    if (await jsonFile.exists()) {
      await jsonFile.rename(refJsonPath);
    }

    await runRetentionCleanup();
  }

  /// Enforces 72h retention and 2 GB cap on reference cache. Removes oldest files when over cap.
  Future<void> runRetentionCleanup() async {
    final root = await _referenceRoot;
    if (!await root.exists()) return;

    final now = DateTime.now();
    final cutoff = now.subtract(const Duration(hours: _retentionHours));
    final List<FileSystemEntity> imageFiles = [];
    await for (final entity in root.list()) {
      if (entity is File && entity.path.toLowerCase().endsWith('.jpg')) {
        imageFiles.add(entity);
      }
    }

    // (path, lastModified) for each .jpg
    final List<({String path, DateTime modified})> entries = [];
    for (final f in imageFiles) {
      final file = f as File;
      try {
        final stat = await file.stat();
        entries.add((path: file.path, modified: stat.modified));
      } catch (_) {}
    }

    // 1) Delete older than 72h
    for (final e in entries) {
      if (e.modified.isBefore(cutoff)) {
        try {
          await File(e.path).delete();
          final jsonPath = p.join(p.dirname(e.path), '${p.basenameWithoutExtension(e.path)}.json');
          final jsonFile = File(jsonPath);
          if (await jsonFile.exists()) await jsonFile.delete();
        } catch (_) {}
      }
    }

    // 2) Re-list remaining and enforce 2 GB cap (delete oldest first)
    int totalBytes = 0;
    final List<({String path, DateTime modified, int size})> remaining = [];
    await for (final entity in root.list()) {
      if (entity is File && entity.path.toLowerCase().endsWith('.jpg')) {
        try {
          final stat = await entity.stat();
          totalBytes += stat.size;
          remaining.add((path: entity.path, modified: stat.modified, size: stat.size));
        } catch (_) {}
      }
    }
    // Also count .json sizes for accurate total
    for (final r in remaining) {
      final jsonPath = p.join(p.dirname(r.path), '${p.basenameWithoutExtension(r.path)}.json');
      final j = File(jsonPath);
      if (await j.exists()) totalBytes += await j.length();
    }

    if (totalBytes <= _storageCapBytes) return;

    remaining.sort((a, b) => a.modified.compareTo(b.modified));
    for (final r in remaining) {
      if (totalBytes <= _storageCapBytes) break;
      try {
        final imgFile = File(r.path);
        if (await imgFile.exists()) {
          totalBytes -= r.size;
          await imgFile.delete();
        }
        final jsonPath = p.join(p.dirname(r.path), '${p.basenameWithoutExtension(r.path)}.json');
        final jsonFile = File(jsonPath);
        if (await jsonFile.exists()) {
          totalBytes -= await jsonFile.length();
          await jsonFile.delete();
        }
      } catch (_) {}
    }
  }

  /// Returns the root dataset path as a string (for display — unprocessed only).
  Future<String> getDatasetRootPath() async {
    final root = await _unprocessedRoot;
    return root.path;
  }

  /// Returns total size of unprocessed dataset in bytes.
  Future<int> getDatasetSize() async {
    final root = await _unprocessedRoot;
    if (!await root.exists()) return 0;
    int total = 0;
    await for (final entity in root.list(recursive: true)) {
      if (entity is File) total += await entity.length();
    }
    return total;
  }

  String formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  /// Write verified annotations back to an existing JSON sidecar.
  Future<void> updateAnnotations({
    required String jsonPath,
    required List<Map<String, dynamic>> annotations,
  }) async {
    final file = File(jsonPath);
    if (!await file.exists()) return;
    final raw = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    raw['annotations'] = annotations;
    await file.writeAsString(const JsonEncoder.withIndent('  ').convert(raw));
  }
}
