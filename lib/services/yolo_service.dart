// ─────────────────────────────────────────────
//  ZERO-CLEAN  ·  YOLO Inference Service
//
//  Current state: STUB — returns a plausible
//  bounding box from a tap point so the full
//  Snap→Nudge→Verify flow works end-to-end.
//
//  To swap in a real model:
//  1. Add tflite_flutter to pubspec.yaml
//  2. Place your yolo11n.tflite in assets/models/
//  3. Replace _stubPropose() with _tflitePropose()
//  4. The rest of the app needs zero changes.
// ─────────────────────────────────────────────

import 'dart:math' as math;
import '../models/models.dart';
import 'dart:ui'; // CRITICAL: This defines 'Offset'

// ── Detection result ───────────────────────────

class Detection {
  final BBox bbox; // normalized [0,1]
  final double confidence; // 0.0–1.0
  final String label; // matched variant label

  const Detection({
    required this.bbox,
    required this.confidence,
    required this.label,
  });
}

// ── Service ────────────────────────────────────

class YoloService {
  static final YoloService instance = YoloService._internal();
  YoloService._internal();

  bool _modelLoaded = false;
  // ignore: unused_field
  dynamic _interpreter; // will be tflite_flutter Interpreter

  /// Call once at app start (or lazily before first inference).
  /// With the stub this is a no-op but the call site is already wired.
  Future<void> loadModel() async {
    if (_modelLoaded) return;

    // ── REAL MODEL (uncomment when ready) ──────
    // _interpreter = await Interpreter.fromAsset('assets/models/yolo11n.tflite');
    // ──────────────────────────────────────────

    _modelLoaded = true;
  }

  /// Given a tap point (normalized [0,1]) and the current variant label,
  /// returns a proposed [Detection].
  ///
  /// The stub centres a box on the tap and adds a small random variation
  /// so repeated taps feel alive. Confidence is randomised 0.70–0.95.
  Future<Detection> propose({
    required Offset tapNorm, // tap position in normalized [0,1] coords
    required String label,
    List<int>?
        imageBytes, // raw JPEG bytes — used by real model, ignored by stub
  }) async {
    await loadModel();

    // ── REAL MODEL (uncomment when ready) ──────
    // return _tflitePropose(tapNorm, label, imageBytes!);
    // ──────────────────────────────────────────

    return _stubPropose(tapNorm, label);
  }

  // ── Stub implementation ────────────────────

  Detection _stubPropose(Offset tapNorm, String label) {
    final rng = math.Random();

    // Box size: 30–45% of image dimension, with slight random variance
    final bw = 0.30 + rng.nextDouble() * 0.15;
    final bh = 0.35 + rng.nextDouble() * 0.15;

    // Centre on tap, clamp to stay within image
    var bx = (tapNorm.dx - bw / 2).clamp(0.0, 1.0 - bw);
    var by = (tapNorm.dy - bh / 2).clamp(0.0, 1.0 - bh);

    // Micro-jitter so it doesn't feel too perfectly centred
    bx = (bx + (rng.nextDouble() - 0.5) * 0.03).clamp(0.0, 1.0 - bw);
    by = (by + (rng.nextDouble() - 0.5) * 0.03).clamp(0.0, 1.0 - bh);

    final confidence = 0.70 + rng.nextDouble() * 0.25;

    return Detection(
      bbox: BBox(bx, by, bw, bh),
      confidence: confidence,
      label: label,
    );
  }

  // ── Real TFLite implementation (template) ──

  // Future<Detection> _tflitePropose(
  //   Offset tapNorm,
  //   String label,
  //   List<int> imageBytes,
  // ) async {
  //   // 1. Decode + resize image to 640×640
  //   // 2. Normalise pixel values to 0–1
  //   // 3. Run inference: _interpreter.run(input, output)
  //   // 4. Parse YOLO output: [batch, num_det, 6] → [cx,cy,w,h,conf,cls]
  //   // 5. Filter by confidence threshold (e.g. 0.5)
  //   // 6. Pick detection closest to tapNorm
  //   // 7. Convert cx/cy/w/h → BBox x/y/w/h (top-left origin)
  //   // 8. Return Detection(bbox, confidence, label)
  //   throw UnimplementedError('Swap stub for real model');
  // }

  void dispose() {
    // _interpreter?.close();
    _modelLoaded = false;
  }
}
