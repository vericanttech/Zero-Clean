// ─────────────────────────────────────────────
//  ZERO-CLEAN  ·  BBox Painter
// ─────────────────────────────────────────────

import 'package:flutter/material.dart';
import '../models/models.dart';
import '../theme.dart';

class BBoxPainter extends CustomPainter {
  final List<Annotation> annotations;
  final int selectedIndex;
  final Map<int, double> confidences; // index → confidence from YOLO
  /// When non-null, bbox is in image space and we draw using this rect (BoxFit.contain area).
  final Rect? fittedRect;

  BBoxPainter({
    required this.annotations,
    required this.selectedIndex,
    this.confidences = const {},
    this.fittedRect,
  });

  @override
  void paint(Canvas canvas, Size size) {
    for (int i = 0; i < annotations.length; i++) {
      final ann = annotations[i];
      final isSelected = i == selectedIndex;
      _drawBox(canvas, size, ann, isSelected, i);
    }
  }

  void _drawBox(
      Canvas canvas, Size size, Annotation ann, bool isSelected, int index) {
    final rect = fittedRect != null
        ? ann.bbox.toPixelRectInFitted(fittedRect!)
        : ann.bbox.toPixelRect(size.width, size.height);

    // During data collection no boxes are verified (UI commented out); when training, verify UI returns
    final effectiveVerified = ann.verified;

    // ── Box stroke ─────────────────────────
    final Color strokeColor;
    if (effectiveVerified) {
      strokeColor = ZCTheme.saturated;
    } else if (isSelected) {
      strokeColor = ZCTheme.accent;
    } else {
      strokeColor = ZCTheme.gold;
    }

    // Shadow / glow for selected
    if (isSelected) {
      canvas.drawRect(
        rect.inflate(2),
        Paint()
          ..color = strokeColor.withOpacity(0.25)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 6,
      );
    }

    // Fill (semi-transparent)
    canvas.drawRect(
      rect,
      Paint()
        ..color = strokeColor.withOpacity(isSelected ? 0.12 : 0.06)
        ..style = PaintingStyle.fill,
    );

    // Border
    canvas.drawRect(
      rect,
      Paint()
        ..color = strokeColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = isSelected ? 2.0 : 1.5,
    );

    // ── Corner ticks for unverified (cleaner than dashes) ──
    if (!effectiveVerified && !isSelected) {
      _drawCornerTicks(canvas, rect, strokeColor);
    }

    // ── Handles (selected only) ───────────
    if (isSelected && !effectiveVerified) {
      _drawHandles(canvas, rect, strokeColor);
    }

    // ── Label chip ────────────────────────
    _drawLabel(canvas, size, rect, ann, index, strokeColor, isSelected);
  }

  void _drawCornerTicks(Canvas canvas, Rect rect, Color color) {
    const tick = 10.0;
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;

    final corners = [
      // Top-left
      [Offset(rect.left, rect.top + tick), Offset(rect.left, rect.top),
       Offset(rect.left, rect.top), Offset(rect.left + tick, rect.top)],
      // Top-right
      [Offset(rect.right - tick, rect.top), Offset(rect.right, rect.top),
       Offset(rect.right, rect.top), Offset(rect.right, rect.top + tick)],
      // Bottom-right
      [Offset(rect.right, rect.bottom - tick), Offset(rect.right, rect.bottom),
       Offset(rect.right, rect.bottom), Offset(rect.right - tick, rect.bottom)],
      // Bottom-left
      [Offset(rect.left + tick, rect.bottom), Offset(rect.left, rect.bottom),
       Offset(rect.left, rect.bottom), Offset(rect.left, rect.bottom - tick)],
    ];
    for (final c in corners) {
      canvas.drawLine(c[0], c[1], paint);
      canvas.drawLine(c[2], c[3], paint);
    }
  }

  void _drawHandles(Canvas canvas, Rect rect, Color color) {
    final cx = rect.left + rect.width / 2;
    final cy = rect.top + rect.height / 2;

    final positions = [
      Offset(rect.left, rect.top),
      Offset(cx, rect.top),
      Offset(rect.right, rect.top),
      Offset(rect.right, cy),
      Offset(rect.right, rect.bottom),
      Offset(cx, rect.bottom),
      Offset(rect.left, rect.bottom),
      Offset(rect.left, cy),
    ];

    for (final pos in positions) {
      // White fill
      canvas.drawCircle(pos, 7, Paint()..color = Colors.white);
      // Colored ring
      canvas.drawCircle(
          pos,
          7,
          Paint()
            ..color = color
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2);
    }
  }

  void _drawLabel(Canvas canvas, Size size, Rect rect, Annotation ann,
      int index, Color color, bool isSelected) {
    // DATA-COLLECTION: hide confidence on canvas — uncomment when model ready
    // final conf = confidences[index];
    // final confStr = conf != null ? ' ${(conf * 100).toInt()}%' : '';
    final labelText = ann.verified
        ? '✓ ${ann.fullLabel}'
        : ann.fullLabel; // was: '${ann.fullLabel}$confStr'

    final tp = TextPainter(
      text: TextSpan(
        text: labelText,
        style: TextStyle(
          color: Colors.white,
          fontSize: isSelected ? 12 : 10,
          fontWeight: FontWeight.w700,
          fontFamily: 'monospace',
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: size.width - 8);

    const padH = 6.0;
    const padV = 3.0;
    final chipW = tp.width + padH * 2;
    final chipH = tp.height + padV * 2;

    // Position chip above box, clamp to canvas
    double chipX = rect.left;
    double chipY = rect.top - chipH - 4;
    if (chipY < 0) chipY = rect.top + 4;
    chipX = chipX.clamp(0, size.width - chipW);

    final chipRect =
        Rect.fromLTWH(chipX, chipY, chipW, chipH);

    // Background
    canvas.drawRRect(
      RRect.fromRectAndRadius(chipRect, const Radius.circular(4)),
      Paint()..color = color.withOpacity(0.9),
    );

    // Text
    tp.paint(canvas, Offset(chipX + padH, chipY + padV));
  }

  @override
  bool shouldRepaint(BBoxPainter old) =>
      old.annotations != annotations ||
      old.selectedIndex != selectedIndex ||
      old.fittedRect != fittedRect ||
      old.confidences != confidences;
}

// ── Crosshair painter (shown during tap-to-snap) ──

class CrosshairPainter extends CustomPainter {
  /// Normalized position [0,1] in image space (or canvas space if fittedRect is null).
  final Offset? position;
  /// When non-null, position is in image space; we draw at fittedRect.left + position.dx * fittedRect.width, etc.
  final Rect? fittedRect;

  CrosshairPainter({this.position, this.fittedRect});

  @override
  void paint(Canvas canvas, Size size) {
    if (position == null) return;
    final Offset px = fittedRect != null
        ? Offset(
            fittedRect!.left + position!.dx * fittedRect!.width,
            fittedRect!.top + position!.dy * fittedRect!.height,
          )
        : Offset(position!.dx * size.width, position!.dy * size.height);
    const r = 24.0;
    final paint = Paint()
      ..color = ZCTheme.accent
      ..strokeWidth = 1.5;

    canvas.drawCircle(px, r, paint..style = PaintingStyle.stroke);
    canvas.drawLine(Offset(px.dx - r - 8, px.dy), Offset(px.dx + r + 8, px.dy), paint);
    canvas.drawLine(Offset(px.dx, px.dy - r - 8), Offset(px.dx, px.dy + r + 8), paint);

    // Dot
    canvas.drawCircle(px, 3, Paint()..color = ZCTheme.accent);
  }

  @override
  bool shouldRepaint(CrosshairPainter old) =>
      old.position != position || old.fittedRect != fittedRect;
}
