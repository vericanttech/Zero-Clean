// ─────────────────────────────────────────────
//  ZERO-CLEAN  ·  Annotation Session State
// ─────────────────────────────────────────────

import '../models/models.dart';
import 'package:flutter/material.dart'; // This includes Offset, Size, and Rect

enum HandleType {
  body,
  topLeft,
  top,
  topRight,
  right,
  bottomRight,
  bottom,
  bottomLeft,
  left,
}

class AnnotationSession extends ChangeNotifier {
  final List<Annotation> annotations;
  int selectedIndex = -1;
  bool saved = false;

  final List<List<BBox>> _undoStack = [];
  static const int _maxUndo = 20;

  // Active drag state
  HandleType? activeDrag;
  Offset? _lastDragPos; // last known position (NOT origin delta math)

  AnnotationSession({required List<Annotation> initial})
      : annotations = initial.map((a) => a.copyWith()).toList();

  // ── Accessors ──────────────────────────────

  Annotation? get selected =>
      selectedIndex >= 0 && selectedIndex < annotations.length
          ? annotations[selectedIndex]
          : null;

  bool get isDragging => activeDrag != null;

  // ── Selection ──────────────────────────────

  void select(int index) {
    selectedIndex = index;
    notifyListeners();
  }

  void deselect() {
    selectedIndex = -1;
    notifyListeners();
  }

  // ── Add / Remove ───────────────────────────

  void addAnnotation(Annotation ann) {
    _pushUndo();
    annotations.add(ann);
    selectedIndex = annotations.length - 1;
    notifyListeners();
  }

  void removeSelected() {
    if (selectedIndex < 0) return;
    _pushUndo();
    annotations.removeAt(selectedIndex);
    selectedIndex = annotations.isEmpty ? -1 : 0;
    notifyListeners();
  }

  // ── Verify ─────────────────────────────────

  void verifySelected() {
    if (selected == null) return;
    _pushUndo();
    selected!.verified = true;
    notifyListeners();
  }

  void verifyAll() {
    _pushUndo();
    for (final a in annotations) {
      a.verified = true;
    }
    notifyListeners();
  }

  bool get allVerified =>
      annotations.isNotEmpty && annotations.every((a) => a.verified);

  int get verifiedCount => annotations.where((a) => a.verified).length;

  // ── Drag API ────────────────────────────────
  //
  // KEY DESIGN: we use incremental deltas (pos - lastPos)
  // NOT cumulative deltas (pos - dragStart).
  // This means each update moves the box exactly as far as
  // the finger moved since the last frame — no jumping.

  /// Returns true if a drag target was found (box or handle).
  /// [pixelPos] is in canvas space. When [fittedRect] is non-null, bbox is
  /// in image space (0–1) and we use [fittedRect] for pixel conversion.
  bool startDrag(Offset pixelPos, Size canvasSize, Rect? fittedRect) {
    final rectForBBox = (BBox b) => fittedRect != null
        ? b.toPixelRectInFitted(fittedRect)
        : b.toPixelRect(canvasSize.width, canvasSize.height);

    // 1. Handles on selected box take priority
    if (selectedIndex >= 0) {
      final h = _hitHandle(
          pixelPos, annotations[selectedIndex].bbox, canvasSize, fittedRect);
      if (h != null) {
        _pushUndo();
        activeDrag = h;
        _lastDragPos = pixelPos;
        return true;
      }
    }

    // 2. Any box body
    for (int i = annotations.length - 1; i >= 0; i--) {
      final rect = rectForBBox(annotations[i].bbox);
      if (rect.inflate(4).contains(pixelPos)) {
        _pushUndo();
        selectedIndex = i;
        activeDrag = HandleType.body;
        _lastDragPos = pixelPos;
        notifyListeners();
        return true;
      }
    }

    return false;
  }

  /// Call on every pan update with the CURRENT position.
  /// When [fittedRect] is non-null, deltas are in image-normalized space.
  void updateDrag(Offset currentPos, Size canvasSize, Rect? fittedRect) {
    if (activeDrag == null || _lastDragPos == null || selectedIndex < 0) return;

    final double denomW =
        fittedRect != null ? fittedRect.width : canvasSize.width;
    final double denomH =
        fittedRect != null ? fittedRect.height : canvasSize.height;
    final dx = (currentPos.dx - _lastDragPos!.dx) / denomW;
    final dy = (currentPos.dy - _lastDragPos!.dy) / denomH;
    _lastDragPos = currentPos;

    final b = annotations[selectedIndex].bbox;

    switch (activeDrag!) {
      case HandleType.body:
        b.x = (b.x + dx).clamp(0.0, 1.0 - b.w);
        b.y = (b.y + dy).clamp(0.0, 1.0 - b.h);
        break;

      case HandleType.topLeft:
        final newX = (b.x + dx).clamp(0.0, b.x + b.w - 0.02);
        final newY = (b.y + dy).clamp(0.0, b.y + b.h - 0.02);
        b.w += b.x - newX;
        b.h += b.y - newY;
        b.x = newX;
        b.y = newY;
        break;

      case HandleType.top:
        final newY = (b.y + dy).clamp(0.0, b.y + b.h - 0.02);
        b.h += b.y - newY;
        b.y = newY;
        break;

      case HandleType.topRight:
        final newY = (b.y + dy).clamp(0.0, b.y + b.h - 0.02);
        b.h += b.y - newY;
        b.y = newY;
        b.w = (b.w + dx).clamp(0.02, 1.0 - b.x);
        break;

      case HandleType.right:
        b.w = (b.w + dx).clamp(0.02, 1.0 - b.x);
        break;

      case HandleType.bottomRight:
        b.w = (b.w + dx).clamp(0.02, 1.0 - b.x);
        b.h = (b.h + dy).clamp(0.02, 1.0 - b.y);
        break;

      case HandleType.bottom:
        b.h = (b.h + dy).clamp(0.02, 1.0 - b.y);
        break;

      case HandleType.bottomLeft:
        final newX = (b.x + dx).clamp(0.0, b.x + b.w - 0.02);
        b.w += b.x - newX;
        b.x = newX;
        b.h = (b.h + dy).clamp(0.02, 1.0 - b.y);
        break;

      case HandleType.left:
        final newX = (b.x + dx).clamp(0.0, b.x + b.w - 0.02);
        b.w += b.x - newX;
        b.x = newX;
        break;
    }

    notifyListeners();
  }

  void endDrag() {
    activeDrag = null;
    _lastDragPos = null;
  }

  // ── Tap (select only, no drag) ─────────────

  /// Returns true if a box was hit and selected.
  bool tapSelect(Offset pixelPos, Size canvasSize, Rect? fittedRect) {
    final rectForBBox = (BBox b) => fittedRect != null
        ? b.toPixelRectInFitted(fittedRect)
        : b.toPixelRect(canvasSize.width, canvasSize.height);
    for (int i = annotations.length - 1; i >= 0; i--) {
      final rect = rectForBBox(annotations[i].bbox);
      if (rect.inflate(8).contains(pixelPos)) {
        selectedIndex = i;
        notifyListeners();
        return true;
      }
    }
    return false;
  }

  // ── Undo ───────────────────────────────────

  void _pushUndo() {
    if (_undoStack.length >= _maxUndo) _undoStack.removeAt(0);
    _undoStack.add(annotations.map((a) => a.bbox.copy()).toList());
  }

  bool get canUndo => _undoStack.isNotEmpty;

  void undo() {
    if (!canUndo) return;
    final snap = _undoStack.removeLast();
    for (int i = 0; i < snap.length && i < annotations.length; i++) {
      annotations[i].bbox = snap[i];
    }
    notifyListeners();
  }

  // ── Handle hit-testing ────────────────────

  static const double _handleR = 22.0; // px — generous for touch

  HandleType? _hitHandle(
      Offset pos, BBox bbox, Size canvas, Rect? fittedRect) {
    final r = fittedRect != null
        ? bbox.toPixelRectInFitted(fittedRect)
        : bbox.toPixelRect(canvas.width, canvas.height);
    final cx = r.left + r.width / 2;
    final cy = r.top + r.height / 2;

    final pts = {
      HandleType.topLeft: Offset(r.left, r.top),
      HandleType.top: Offset(cx, r.top),
      HandleType.topRight: Offset(r.right, r.top),
      HandleType.right: Offset(r.right, cy),
      HandleType.bottomRight: Offset(r.right, r.bottom),
      HandleType.bottom: Offset(cx, r.bottom),
      HandleType.bottomLeft: Offset(r.left, r.bottom),
      HandleType.left: Offset(r.left, cy),
    };

    HandleType? best;
    double bestDist = _handleR;
    for (final e in pts.entries) {
      final d = (pos - e.value).distance;
      if (d < bestDist) {
        bestDist = d;
        best = e.key;
      }
    }
    return best;
  }

  List<Map<String, dynamic>> toMapList() =>
      annotations.map((a) => a.toMap()).toList();
}
