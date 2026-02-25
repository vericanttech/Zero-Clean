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

  Future<Directory> get _root async {
    final base = await getExternalStorageDirectory() ??
        await getApplicationDocumentsDirectory();
    final root = Directory(p.join(base.path, 'ZeroClean_Dataset'));
    if (!await root.exists()) await root.create(recursive: true);
    return root;
  }

  /// Returns the full save path for a capture context
  Future<String> getSavePath({
    required String shopName,
    required String category,
    required String variantLabel,
    required CaptureContext context,
  }) async {
    final root = await _root;
    return p.join(root.path, shopName, category, variantLabel, context.name);
  }

  /// Creates directory if it doesn't exist. Returns the Directory.
  Future<Directory> prepareDirectory(String fullPath) async {
    final dir = Directory(fullPath);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// Saves image + JSON sidecar. Returns the saved image path.
  Future<String> captureData({
    required String savePath,
    required String tempImagePath,
    required String shopId,
    required Variant variant,
    required CaptureContext context,
    required List<Annotation> annotations,
    required Map<String, double> gyro,
    required String lighting,
    required String angle,
    required bool isEdgeCase,
    String? edgeType,
    int imageWidth = 1080,
    int imageHeight = 2400,
  }) async {
    await prepareDirectory(savePath);

    final ts = DateTime.now().millisecondsSinceEpoch;
    final fileName = 'IMG_$ts';

    // Copy image
    final destImagePath = p.join(savePath, '$fileName.jpg');
    await File(tempImagePath).copy(destImagePath);

    // Build JSON sidecar (ID-based: shopId, context)
    final deviceModel = await getDeviceModel();
    final record = ImageRecord(
      imageId: '$fileName.jpg',
      shopId: shopId,
      context: context.name,
      width: imageWidth,
      height: imageHeight,
      annotations: annotations,
      deviceModel: deviceModel,
      lighting: lighting,
      angle: angle,
      isEdgeCase: isEdgeCase,
      edgeType: edgeType,
    );

    final jsonPath = p.join(savePath, '$fileName.json');
    await File(jsonPath).writeAsString(
      const JsonEncoder.withIndent('  ').convert(record.toJson()),
    );

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
}

/// Write verified annotations back to an existing JSON sidecar.
/// Called by BBoxNudgeScreen on save.
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
