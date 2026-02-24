// ─────────────────────────────────────────────
//  ZERO-CLEAN  ·  File System Service
// ─────────────────────────────────────────────

import 'dart:io';
import 'dart:convert';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import '../models/models.dart';
import '../utils/device_utils.dart';

class FileSystemService {
  static final FileSystemService instance = FileSystemService._internal();
  FileSystemService._internal();

  /// Public external storage: /storage/emulated/0/ZeroClean_Dataset/
  /// Visible in any file manager and via USB (MTP).
  ///
  /// getExternalStorageDirectory() returns the app-private sandbox
  /// at Android/data/<package>/files/ which file managers can't see.
  /// Instead we walk up from getExternalStorageDirectories() to reach
  /// the true public root /storage/emulated/0/.
  Future<Directory> get _root async {
    Directory? publicDir;

    try {
      final dirs = await getExternalStorageDirectories(
          type: StorageDirectory.documents);
      if (dirs != null && dirs.isNotEmpty) {
        // dirs[0] ≈ /storage/emulated/0/Android/data/<pkg>/files/Documents
        // Walk up 4 levels → /storage/emulated/0/
        Directory d = dirs[0];
        for (int i = 0; i < 4; i++) {
          d = d.parent;
        }
        publicDir = Directory(p.join(d.path, 'ZeroClean_Dataset'));
      }
    } catch (_) {}

    // Hard fallback — works on virtually all Android devices
    publicDir ??= Directory('/storage/emulated/0/ZeroClean_Dataset');

    if (!await publicDir.exists()) {
      await publicDir.create(recursive: true);
    }
    return publicDir;
  }

  /// Returns the full save path for a capture context (processed images).
  Future<String> getSavePath({
    required String shopName,
    required String category,
    required String variantLabel,
    required CaptureContext context,
  }) async {
    final root = await _root;
    return p.join(root.path, shopName, category, variantLabel, context.name);
  }

  /// Returns the unprocessed folder for a shop (new captures go here until nudge).
  Future<String> getUnprocessedPath({required String shopName}) async {
    final root = await _root;
    return p.join(root.path, shopName, 'Unprocessed');
  }

  /// Creates directory if it doesn't exist. Returns the Directory.
  Future<Directory> prepareDirectory(String fullPath) async {
    final dir = Directory(fullPath);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// Saves image + JSON sidecar to unprocessed folder. Does not increment DB count.
  /// [shopName], [category], [variantLabel] are stored in JSON so nudge can move to the right folder.
  Future<String> captureToUnprocessed({
    required String unprocessedPath,
    required String tempImagePath,
    required String shopName,
    required String category,
    required String variantLabel,
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
      shopContext: 'unprocessed',
      width: imageWidth,
      height: imageHeight,
      annotations: annotations,
      deviceModel: deviceModel,
      shopName: shopName,
      category: category,
      variantLabel: variantLabel,
    );

    final jsonPath = p.join(unprocessedPath, '$fileName.json');
    await File(jsonPath).writeAsString(
      const JsonEncoder.withIndent('  ').convert(record.toJson()),
    );

    return destImagePath;
  }

  /// Moves image + JSON from unprocessed to context folder and writes full metadata.
  /// Call after nudge save. Returns the new image path in the context folder.
  Future<String> moveToContextFolder({
    required String currentImagePath,
    required String currentJsonPath,
    required String shopName,
    required String category,
    required String variantLabel,
    required CaptureContext context,
    required Map<String, dynamic> fullJson,
  }) async {
    final destDir = await getSavePath(
      shopName: shopName,
      category: category,
      variantLabel: variantLabel,
      context: context,
    );
    await prepareDirectory(destDir);

    final fileName = p.basename(currentImagePath);
    final destImagePath = p.join(destDir, fileName);
    final destJsonPath = p.join(destDir, p.withoutExtension(fileName) + '.json');

    await File(currentImagePath).copy(destImagePath);
    fullJson['shop_context'] = context.name;
    fullJson.remove('shop_name');
    fullJson.remove('category');
    fullJson.remove('variant_label');
    await File(destJsonPath).writeAsString(
      const JsonEncoder.withIndent('  ').convert(fullJson),
    );

    await File(currentImagePath).delete();
    await File(currentJsonPath).delete();
    return destImagePath;
  }

  /// Returns how many .jpg files exist in a specific context folder
  Future<int> countImages(String savePath) async {
    final dir = Directory(savePath);
    if (!await dir.exists()) return 0;
    final files = await dir.list().toList();
    return files.where((f) => f.path.endsWith('.jpg')).length;
  }

  /// Returns the root dataset path as a string (for display)
  Future<String> getDatasetRootPath() async {
    final root = await _root;
    return root.path;
  }

  /// Returns total size of dataset in bytes
  Future<int> getDatasetSize() async {
    final root = await _root;
    if (!await root.exists()) return 0;
    int total = 0;
    await for (final entity in root.list(recursive: true)) {
      if (entity is File) {
        total += await entity.length();
      }
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
