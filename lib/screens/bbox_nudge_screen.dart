// ─────────────────────────────────────────────
//  ZERO-CLEAN  ·  BBox Nudge Screen
//
//  Snap → Nudge → Verify
//
//  Gesture design:
//  • Single unified RawGestureDetector on the canvas
//  • Pan  = move box / resize handle
//  • Tap  = select existing box OR snap new box (YOLO)
//  • No competing tap + pan detectors
// ─────────────────────────────────────────────

import 'dart:io';
import 'dart:convert';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import '../models/models.dart';
import '../providers/annotation_state.dart';
import '../providers/app_state.dart';
import '../services/filesystem_service.dart';
import '../services/yolo_service.dart';
import '../widgets/bbox_painter.dart';
import '../widgets/widgets.dart';
import '../theme.dart';

class BBoxNudgeScreen extends StatefulWidget {
  final String imagePath;
  final String jsonPath;
  final List<Annotation> initialAnnotations;
  final Variant? variant;
  final List<Variant> allVariants;
  /// When true, save will move file to context folder and increment DB count.
  final bool isUnprocessed;
  final String? shopName;
  final String? category;
  final String? variantLabel;

  const BBoxNudgeScreen({
    super.key,
    required this.imagePath,
    required this.jsonPath,
    required this.initialAnnotations,
    this.variant,
    this.allVariants = const [],
    this.isUnprocessed = false,
    this.shopName,
    this.category,
    this.variantLabel,
  });

  @override
  State<BBoxNudgeScreen> createState() => _BBoxNudgeScreenState();
}

class _BBoxNudgeScreenState extends State<BBoxNudgeScreen> {
  late AnnotationSession _session;
  final Map<int, double> _confidences = {};

  Size _canvasSize = Size.zero;
  Size? _imageSize; // actual image dimensions (for BoxFit.contain → image-space coords)
  bool _snapping = false;
  Offset? _pendingTapNorm;
  bool _showInstructions = true;
  static const double _tapMoveThreshold = 8.0;
  Offset? _panStartPos;
  bool _panWasDrag = false;

  // Metadata (set from JSON on load, editable on nudge)
  late String _lighting;
  late String _angle;
  late bool _isEdgeCase;
  String? _edgeType;
  late CaptureContext _context;
  late String _condition;
  late String _occlusion;
  /// Preserved from JSON so we don't drop it when saving (set at capture time).
  String? _deviceModel;

  @override
  void initState() {
    super.initState();
    _session = AnnotationSession(initial: widget.initialAnnotations);
    _setMetadataDefaults();
    _loadMetadataFromJson();
    _loadImageSize();
    Future.delayed(const Duration(seconds: 4),
        () { if (mounted) setState(() => _showInstructions = false); });
  }

  Future<void> _loadImageSize() async {
    try {
      final bytes = await File(widget.imagePath).readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final image = frame.image;
      if (mounted) {
        setState(() {
          _imageSize = Size(image.width.toDouble(), image.height.toDouble());
        });
      }
      image.dispose();
      codec.dispose();
    } catch (_) {
      // Keep _imageSize null → fall back to canvas-space coords (old behavior)
    }
  }

  Future<void> _loadMetadataFromJson() async {
    final file = File(widget.jsonPath);
    if (!await file.exists()) {
      _setMetadataDefaults();
      return;
    }
    try {
      final raw = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      final meta = raw['metadata'] as Map<String, dynamic>? ?? {};
      setState(() {
        _lighting = meta['lighting'] as String? ?? 'natural';
        _angle = meta['angle'] as String? ?? 'front';
        _isEdgeCase = meta['is_edge_case'] as bool? ?? false;
        _edgeType = meta['edge_type'] as String?;
        _condition = meta['condition'] as String? ?? 'good';
        _occlusion = meta['occlusion'] as String? ?? 'none';
        _deviceModel = meta['device_model'] as String?;
        final ctxStr = raw['shop_context'] as String? ?? 'single';
        _context = CaptureContext.values
            .firstWhere(
              (c) => c.name == ctxStr,
              orElse: () => CaptureContext.single,
            );
      });
    } catch (_) {
      _setMetadataDefaults();
    }
  }

  void _setMetadataDefaults() {
    _lighting = 'natural';
    _angle = 'front';
    _isEdgeCase = false;
    _edgeType = null;
    _context = CaptureContext.single;
    _condition = 'good';
    _occlusion = 'none';
  }

  // ── Gesture handlers ───────────────────────

  Rect? get _fittedRect {
    if (_imageSize == null ||
        _canvasSize == Size.zero ||
        _imageSize!.width <= 0 ||
        _imageSize!.height <= 0) return null;
    final scaleW = _canvasSize.width / _imageSize!.width;
    final scaleH = _canvasSize.height / _imageSize!.height;
    final scale = scaleW < scaleH ? scaleW : scaleH;
    final fitW = _imageSize!.width * scale;
    final fitH = _imageSize!.height * scale;
    final left = (_canvasSize.width - fitW) / 2;
    final top = (_canvasSize.height - fitH) / 2;
    return Rect.fromLTWH(left, top, fitW, fitH);
  }

  void _onPanStart(DragStartDetails d) {
    if (_snapping) return;
    _panStartPos = d.localPosition;
    _panWasDrag = false;

    final hit = _session.startDrag(d.localPosition, _canvasSize, _fittedRect);
    if (hit) _panWasDrag = true;
  }

  void _onPanUpdate(DragUpdateDetails d) {
    if (_snapping) return;

    // Check if this is now clearly a drag (finger moved enough)
    if (!_panWasDrag && _panStartPos != null) {
      final moved = (d.localPosition - _panStartPos!).distance;
      if (moved > _tapMoveThreshold) {
        // Try to start drag now if not already started
        if (!_session.isDragging) {
          _session.startDrag(d.localPosition, _canvasSize, _fittedRect);
        }
        _panWasDrag = true;
      }
    }

    if (_session.isDragging) {
      _session.updateDrag(d.localPosition, _canvasSize, _fittedRect);
    }
  }

  void _onPanEnd(DragEndDetails d) {
    if (_session.isDragging) {
      _session.endDrag();
    }

    // If barely moved → treat as tap
    if (!_panWasDrag && _panStartPos != null) {
      _handleTap(_panStartPos!);
    }

    _panStartPos = null;
    _panWasDrag = false;
  }

  Future<void> _handleTap(Offset localPos) async {
    if (_snapping || _canvasSize == Size.zero) return;

    final selected = _session.tapSelect(localPos, _canvasSize, _fittedRect);
    if (selected) return;

    _session.deselect();
    // Tap in image space (0–1) so YOLO and saved bbox match the actual image
    final Rect? fit = _fittedRect;
    final tapNorm = fit != null
        ? Offset(
            (localPos.dx - fit.left) / fit.width,
            (localPos.dy - fit.top) / fit.height,
          )
        : Offset(
            localPos.dx / _canvasSize.width,
            localPos.dy / _canvasSize.height,
          );

    setState(() {
      _snapping = true;
      _pendingTapNorm = tapNorm;
      _showInstructions = false;
    });

    try {
      // Run YOLO first (fast, even stub) — box appears while picker is open
      final detection = await YoloService.instance.propose(
        tapNorm: tapNorm,
        label: widget.variant?.fullLabel ?? 'Product',
      );

      // ── Label picker ──────────────────────────────────────────────────
      // In checkout mode (multiple products per shot) always ask which
      // product this box belongs to.
      // In single/shelf mode skip the picker and use the selected variant.
      Variant? pickedVariant = widget.variant;

      final hasMultipleVariants = widget.allVariants.length > 1;
      // We always show the picker in checkout context OR when allVariants
      // has more than one option — so the user can always choose.
      if (hasMultipleVariants && mounted) {
        setState(() => _snapping = false); // hide spinner while picker is open
        pickedVariant = await showModalBottomSheet<Variant>(
          context: context,
          isScrollControlled: true,
          backgroundColor: ZCTheme.surface,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          builder: (_) => _LabelPickerSheet(
            variants: widget.allVariants,
            current: widget.variant,
          ),
        );
        if (!mounted) return;
        if (pickedVariant == null) return; // user dismissed — cancel the snap
        setState(() => _snapping = true);
      }

      final v = pickedVariant ?? widget.variant;
      final label = v?.fullLabel ?? 'Product';

      final ann = Annotation(
        brand: v?.brand ?? label.split('_').first,
        subBrand: v?.subBrand ?? '',
        volume: v?.volume ?? '',
        material: v?.material ?? '',
        fullLabel: label,
        bbox: detection.bbox,
        verified: false,
      );

      final idx = _session.annotations.length;
      _session.addAnnotation(ann);
      _confidences[idx] = detection.confidence;
    } catch (e) {
      _showSnack('YOLO error: $e');
    } finally {
      if (mounted) {
        setState(() {
          _snapping = false;
          _pendingTapNorm = null;
        });
      }
    }
  }

  // ── Actions ────────────────────────────────

  Future<void> _save() async {
    final file = File(widget.jsonPath);
    try {
      Map<String, dynamic> raw = {};
      if (await file.exists()) {
        raw = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      }
      raw['annotations'] = _session.toMapList();
      raw['metadata'] = {
        'lighting': _lighting,
        'angle': _angle,
        'is_edge_case': _isEdgeCase,
        if (_edgeType != null) 'edge_type': _edgeType,
        'condition': _condition,
        'occlusion': _occlusion,
        if (_deviceModel != null) 'device_model': _deviceModel,
      };
      raw['shop_context'] = _context.name;

      if (widget.isUnprocessed &&
          widget.shopName != null &&
          widget.category != null &&
          widget.variantLabel != null) {
        final fs = FileSystemService.instance;
        // File goes to initial/intended variant's folder
        await fs.moveToContextFolder(
          currentImagePath: widget.imagePath,
          currentJsonPath: widget.jsonPath,
          shopName: widget.shopName!,
          category: widget.category!,
          variantLabel: widget.variantLabel!,
          context: _context,
          fullJson: raw,
        );
        final appState = context.read<AppState>();
        final shop = appState.shops
            .where((s) => s.name == widget.shopName)
            .firstOrNull;
        if (shop?.id != null) {
          // Count each distinct product in the annotations (one increment per variant in this image)
          final distinctLabels = _session.annotations
              .map((a) => a.fullLabel)
              .toSet();
          for (final fullLabel in distinctLabels) {
            final v = widget.allVariants
                .where((v) => v.fullLabel == fullLabel)
                .firstOrNull;
            if (v?.id != null) {
              await appState.recordCaptureFor(v!.id!, shop!.id!, _context);
            }
          }
        }
        _session.saved = true;
        if (mounted) {
          _showSnack('💾 Processed · moved to ${_context.name}');
          Navigator.of(context).pop(true);
        }
        return;
      }

      await file.writeAsString(const JsonEncoder.withIndent('  ').convert(raw));
      _session.saved = true;
      _showSnack('💾 Saved · ${_session.annotations.length} box${_session.annotations.length == 1 ? '' : 'es'}');
    } catch (e) {
      _showSnack('Save error: $e');
    }
  }

  /// True if the user has made changes since open (or since last save).
  bool _hasUnsavedChanges() {
    if (_session.saved) return false;
    final initial = widget.initialAnnotations;
    if (_session.annotations.length != initial.length) return true;
    for (int i = 0; i < _session.annotations.length; i++) {
      final a = _session.annotations[i];
      final b = initial[i];
      if (a.fullLabel != b.fullLabel ||
          a.verified != b.verified ||
          a.bbox.toList() != b.bbox.toList()) {
        return true;
      }
    }
    return false;
  }

  Future<bool> _onWillPop() async {
    if (!_hasUnsavedChanges()) return true;
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: ZCTheme.surface,
        title: const Text('Unsaved changes',
            style: TextStyle(color: ZCTheme.textPrimary)),
        content: const Text('Save before leaving?',
            style: TextStyle(color: ZCTheme.textSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Discard', style: TextStyle(color: ZCTheme.critical)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (result == true) await _save();
    return true;
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(
        content: Text(msg, style: const TextStyle(color: ZCTheme.textPrimary)),
        backgroundColor: ZCTheme.surfaceAlt,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ));
  }

  // ── Build ──────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: _onWillPop,
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: _buildAppBar(),
        body: Column(
          children: [
            Expanded(child: _buildCanvas()),
            _BottomPanel(
              session: _session,
              confidences: _confidences,
              onDelete: _session.removeSelected,
              onUndo: _session.undo,
              onSave: _save,
            ),
          ],
        ),
      ),
    );
  }

  void _showMetadataSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: ZCTheme.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => DraggableScrollableSheet(
        initialChildSize: 0.5,
        minChildSize: 0.35,
        maxChildSize: 0.9,
        expand: false,
        builder: (_, scrollController) => StatefulBuilder(
          builder: (_, setSheetState) => SingleChildScrollView(
            controller: scrollController,
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Context, lighting, angle, condition',
                    style: TextStyle(
                        color: ZCTheme.textMuted,
                        fontSize: 12,
                        fontWeight: FontWeight.w600)),
                const SizedBox(height: 12),
                _MetadataSection(
              isUnprocessed: widget.isUnprocessed,
              selectedContext: _context,
              onContextChanged: (c) {
                setState(() => _context = c);
                setSheetState(() {});
              },
              lighting: _lighting,
              onLightingChanged: (v) {
                setState(() => _lighting = v);
                setSheetState(() {});
              },
              angle: _angle,
              onAngleChanged: (v) {
                setState(() => _angle = v);
                setSheetState(() {});
              },
              isEdgeCase: _isEdgeCase,
              onEdgeCaseChanged: () {
                setState(() {
                  _isEdgeCase = !_isEdgeCase;
                  if (!_isEdgeCase) _edgeType = null;
                });
                setSheetState(() {});
              },
              condition: _condition,
              onConditionChanged: (v) {
                setState(() => _condition = v);
                setSheetState(() {});
              },
              occlusion: _occlusion,
              onOcclusionChanged: (v) {
                setState(() => _occlusion = v);
                setSheetState(() {});
              },
            ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Close'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  AppBar _buildAppBar() {
    return AppBar(
      backgroundColor: Colors.black,
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('NUDGE',
              style: TextStyle(
                  color: ZCTheme.accent,
                  fontWeight: FontWeight.w900,
                  fontSize: 14,
                  letterSpacing: 1.5)),
          Text(p.basename(widget.imagePath),
              style: const TextStyle(
                  color: ZCTheme.textMuted, fontSize: 10, fontFamily: 'monospace')),
        ],
      ),
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: 4),
          child: TextButton.icon(
            onPressed: _showMetadataSheet,
            icon: const Icon(Icons.tune_rounded, size: 20, color: ZCTheme.accent),
            label: const Text('OPTIONS', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 0.5, color: ZCTheme.accent)),
          ),
        ),
        ListenableBuilder(
          listenable: _session,
          builder: (_, __) => IconButton(
            icon: Icon(Icons.undo,
                color: _session.canUndo ? ZCTheme.textPrimary : ZCTheme.textMuted),
            onPressed: _session.canUndo ? _session.undo : null,
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(right: 8),
          child: TextButton.icon(
            onPressed: _save,
            icon: const Icon(Icons.save_outlined, size: 16),
            label: const Text('SAVE',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12)),
            style: TextButton.styleFrom(foregroundColor: ZCTheme.accent),
          ),
        ),
      ],
    );
  }

  Widget _buildCanvas() {
    return LayoutBuilder(builder: (context, constraints) {
      // Track canvas size here — single source of truth
      // The image uses BoxFit.contain so it may be smaller than constraints.
      // We use the full constraint size for coordinate math; BBoxPainter
      // is Positioned.fill so it always matches this size.
      _canvasSize = Size(constraints.maxWidth, constraints.maxHeight);

      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanStart: _onPanStart,
        onPanUpdate: _onPanUpdate,
        onPanEnd: _onPanEnd,
        child: Stack(
          children: [
            // ── Image ──────────────────
            Positioned.fill(
              child: Image.file(
                File(widget.imagePath),
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => const Center(
                    child: Icon(Icons.broken_image,
                        color: ZCTheme.textMuted, size: 64)),
              ),
            ),

            // ── BBox overlay ───────────
            Positioned.fill(
              child: ListenableBuilder(
                listenable: _session,
                builder: (_, __) => CustomPaint(
                  painter: BBoxPainter(
                    annotations: _session.annotations,
                    selectedIndex: _session.selectedIndex,
                    confidences: _confidences,
                    fittedRect: _fittedRect,
                  ),
                ),
              ),
            ),

            // ── Crosshair during snap ──
            if (_snapping && _pendingTapNorm != null)
              Positioned.fill(
                child: CustomPaint(
                  painter: CrosshairPainter(
                    position: _pendingTapNorm,
                    fittedRect: _fittedRect,
                  ),
                ),
              ),

            // ── Snapping indicator ─────
            if (_snapping)
              Positioned(
                top: 12, left: 0, right: 0,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.80),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: ZCTheme.accent.withOpacity(0.6)),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 14, height: 14,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: ZCTheme.accent),
                        ),
                        SizedBox(width: 8),
                        Text('SNAPPING…',
                            style: TextStyle(
                                color: ZCTheme.accent,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 1)),
                      ],
                    ),
                  ),
                ),
              ),

            // ── Instructions ───────────
            if (_showInstructions && _session.annotations.isEmpty)
              Positioned.fill(
                child: IgnorePointer(
                  child: Center(
                    child: Container(
                      margin: const EdgeInsets.all(32),
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.78),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: ZCTheme.border),
                      ),
                      child: const Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _HintRow('👆  TAP', 'empty area → add box'),
                          SizedBox(height: 10),
                          _HintRow('✋  DRAG', 'inside box → move it'),
                          SizedBox(height: 10),
                          _HintRow('⬜  HANDLES', 'drag white dots → resize'),
                          // DATA-COLLECTION: verify hint hidden — uncomment when training
                          // SizedBox(height: 10),
                          // _HintRow('✓  VERIFY', 'lock box when aligned'),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      );
    });
  }
}

// ── Metadata section (context, lighting, angle, edge case, condition, occlusion) ──

class _MetadataSection extends StatelessWidget {
  final bool isUnprocessed;
  final CaptureContext selectedContext;
  final ValueChanged<CaptureContext> onContextChanged;
  final String lighting;
  final ValueChanged<String> onLightingChanged;
  final String angle;
  final ValueChanged<String> onAngleChanged;
  final bool isEdgeCase;
  final VoidCallback onEdgeCaseChanged;
  final String condition;
  final ValueChanged<String> onConditionChanged;
  final String occlusion;
  final ValueChanged<String> onOcclusionChanged;

  const _MetadataSection({
    required this.isUnprocessed,
    required this.selectedContext,
    required this.onContextChanged,
    required this.lighting,
    required this.onLightingChanged,
    required this.angle,
    required this.onAngleChanged,
    required this.isEdgeCase,
    required this.onEdgeCaseChanged,
    required this.condition,
    required this.onConditionChanged,
    required this.occlusion,
    required this.onOcclusionChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: ZCTheme.surfaceAlt,
        border: Border(top: BorderSide(color: ZCTheme.border)),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (isUnprocessed) ...[
              const Text('CONTEXT',
                  style: TextStyle(
                      color: ZCTheme.textMuted,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5)),
              const SizedBox(height: 6),
              ContextSelector(selected: selectedContext, onChanged: onContextChanged),
              const SizedBox(height: 12),
            ],
            _ChipRow(
              label: 'LIGHTING',
              options: const ['natural', 'dim_yellow', 'bright_white', 'neon'],
              selected: lighting,
              onSelected: onLightingChanged,
            ),
            const SizedBox(height: 8),
            _ChipRow(
              label: 'ANGLE',
              options: const ['front', 'top_down', 'angled_45', 'side'],
              selected: angle,
              onSelected: onAngleChanged,
            ),
            const SizedBox(height: 8),
            _ChipRow(
              label: 'CONDITION',
              options: const ['good', 'damaged', 'faded', 'counterfeit'],
              selected: condition,
              onSelected: onConditionChanged,
            ),
            const SizedBox(height: 8),
            _ChipRow(
              label: 'OCCLUSION',
              options: const ['none', 'partial', 'heavy'],
              selected: occlusion,
              onSelected: onOcclusionChanged,
            ),
            const SizedBox(height: 8),
            GestureDetector(
              onTap: onEdgeCaseChanged,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: isEdgeCase
                      ? ZCTheme.gold.withOpacity(0.15)
                      : ZCTheme.surface,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color: isEdgeCase ? ZCTheme.gold : ZCTheme.border),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.warning_amber_rounded,
                        size: 16,
                        color: isEdgeCase ? ZCTheme.gold : ZCTheme.textMuted),
                    const SizedBox(width: 8),
                    Text(
                      isEdgeCase ? 'EDGE CASE' : 'MARK AS EDGE CASE',
                      style: TextStyle(
                          color: isEdgeCase ? ZCTheme.gold : ZCTheme.textMuted,
                          fontSize: 11,
                          fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChipRow extends StatelessWidget {
  final String label;
  final List<String> options;
  final String selected;
  final ValueChanged<String> onSelected;

  const _ChipRow({
    required this.label,
    required this.options,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(
                color: ZCTheme.textMuted,
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5)),
        const SizedBox(height: 4),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: options.map((o) {
              final sel = o == selected;
              return Padding(
                padding: const EdgeInsets.only(right: 6),
                child: ChoiceChip(
                  label: Text(o, style: const TextStyle(fontSize: 10)),
                  selected: sel,
                  selectedColor: ZCTheme.accent,
                  backgroundColor: ZCTheme.surface,
                  side: BorderSide(
                      color: sel ? ZCTheme.accent : ZCTheme.border),
                  onSelected: (_) => onSelected(o),
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }
}

// ── Hint row ──────────────────────────────────

class _HintRow extends StatelessWidget {
  final String label;
  final String desc;
  const _HintRow(this.label, this.desc);

  @override
  Widget build(BuildContext context) => Row(
        children: [
          SizedBox(
            width: 96,
            child: Text(label,
                style: const TextStyle(
                    color: ZCTheme.accent,
                    fontWeight: FontWeight.w800,
                    fontSize: 12)),
          ),
          Expanded(
            child: Text(desc,
                style: const TextStyle(
                    color: ZCTheme.textSecondary, fontSize: 12)),
          ),
        ],
      );
}

// ── Bottom panel ──────────────────────────────

class _BottomPanel extends StatelessWidget {
  final AnnotationSession session;
  final Map<int, double> confidences;
  // DATA-COLLECTION: verify disabled until model ready
  // final VoidCallback onVerify;
  // final VoidCallback onVerifyAll;
  final VoidCallback onDelete;
  final VoidCallback onUndo;
  final VoidCallback onSave;

  const _BottomPanel({
    required this.session,
    required this.confidences,
    // required this.onVerify,
    // required this.onVerifyAll,
    required this.onDelete,
    required this.onUndo,
    required this.onSave,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: session,
      builder: (_, __) {
        final sel = session.selected;
        return Container(
          decoration: const BoxDecoration(
            color: ZCTheme.surface,
            border: Border(top: BorderSide(color: ZCTheme.border)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Box chips
              if (session.annotations.isNotEmpty)
                SizedBox(
                  height: 58,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    itemCount: session.annotations.length,
                    itemBuilder: (_, i) {
                      final ann = session.annotations[i];
                      final isSelected = i == session.selectedIndex;
                      // conf used when showing confidence (commented for DATA-COLLECTION)
                      return GestureDetector(
                        onTap: () => session.select(i),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 160),
                          margin: const EdgeInsets.only(right: 8),
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? ZCTheme.accent.withOpacity(0.15)
                                : ZCTheme.surfaceAlt,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              // DATA-COLLECTION: no verified styling — uncomment when training
                              // color: ann.verified ? ZCTheme.saturated : isSelected ? ...
                              color: isSelected
                                  ? ZCTheme.accent
                                  : ZCTheme.border,
                              width: isSelected ? 1.5 : 1,
                            ),
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  // DATA-COLLECTION: no lock icon — uncomment when training
                                  // Icon(
                                  //   ann.verified ? Icons.lock : Icons.crop_square_rounded,
                                  //   size: 10,
                                  //   color: ann.verified ? ZCTheme.saturated : ZCTheme.gold,
                                  // ),
                                  Icon(Icons.crop_square_rounded,
                                      size: 10, color: ZCTheme.gold),
                                  const SizedBox(width: 4),
                                  Text(ann.fullLabel,
                                      style: TextStyle(
                                        color: isSelected
                                            ? ZCTheme.textPrimary
                                            : ZCTheme.textSecondary,
                                        fontSize: 10,
                                        fontFamily: 'monospace',
                                        fontWeight: FontWeight.w600,
                                      )),
                                ],
                              ),
                              // DATA-COLLECTION: hide fake confidence — uncomment when model ready
                              // if (conf != null)
                              //   Text('${(conf * 100).toInt()}% conf',
                              //       style: const TextStyle(
                              //           color: ZCTheme.textMuted, fontSize: 9)),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),

              // Action row
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
                child: Row(
                  children: [
                    // Stats
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${session.annotations.length} box${session.annotations.length == 1 ? '' : 'es'}',
                            style: const TextStyle(
                                color: ZCTheme.textSecondary, fontSize: 11)),
                        // DATA-COLLECTION: hide verified count — uncomment when training
                        // Text('${session.verifiedCount} verified',
                        //     style: TextStyle(
                        //       color: session.allVerified
                        //           ? ZCTheme.saturated
                        //           : ZCTheme.gold,
                        //       fontSize: 11,
                        //       fontWeight: FontWeight.w700,
                        //     )),
                      ],
                    ),
                    const Spacer(),

                    if (sel != null) ...[
                      _Btn(icon: Icons.delete_outline, color: ZCTheme.critical,
                          label: 'DEL', onTap: onDelete),
                      const SizedBox(width: 8),
                    ],
                    // DATA-COLLECTION: verify buttons disabled until model ready
                    // if (sel != null && !sel.verified) ...[
                    //   _Btn(icon: Icons.check_circle_outline, color: ZCTheme.accent,
                    //       label: 'VERIFY', onTap: onVerify),
                    //   const SizedBox(width: 8),
                    // ],
                    // if (!session.allVerified && session.annotations.isNotEmpty) ...[
                    //   _Btn(icon: Icons.verified_outlined, color: ZCTheme.saturated,
                    //       label: 'ALL ✓', onTap: onVerifyAll),
                    //   const SizedBox(width: 8),
                    // ],

                    ElevatedButton.icon(
                      onPressed: onSave,
                      icon: const Icon(Icons.save_alt, size: 15),
                      label: Text(
                        session.saved ? 'SAVED ✓' : 'SAVE',
                        style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 12,
                            letterSpacing: 0.5),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: session.saved
                            ? ZCTheme.saturated.withOpacity(0.25)
                            : ZCTheme.accent,
                        foregroundColor:
                            session.saved ? ZCTheme.saturated : ZCTheme.bg,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 10),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Btn extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final VoidCallback onTap;
  const _Btn({required this.icon, required this.color,
      required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: color.withOpacity(0.12),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: color.withOpacity(0.4)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: color, size: 14),
              const SizedBox(width: 4),
              Text(label,
                  style: TextStyle(
                      color: color,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5)),
            ],
          ),
        ),
      );
}

// ── Label Picker Sheet ────────────────────────
// Shown after YOLO snaps a box so the user can assign
// any product in the database to that box — not just
// the one selected on the capture screen.

class _LabelPickerSheet extends StatefulWidget {
  final List<Variant> variants;
  final Variant? current;

  const _LabelPickerSheet({required this.variants, this.current});

  @override
  State<_LabelPickerSheet> createState() => _LabelPickerSheetState();
}

class _LabelPickerSheetState extends State<_LabelPickerSheet> {
  late List<Variant> _filtered;
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _filtered = widget.variants;
    _searchCtrl.addListener(_onSearch);
  }

  void _onSearch() {
    final q = _searchCtrl.text.toLowerCase();
    setState(() {
      _filtered = q.isEmpty
          ? widget.variants
          : widget.variants
              .where((v) => v.fullLabel.toLowerCase().contains(q) ||
                  v.brand.toLowerCase().contains(q))
              .toList();
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final viewInsets = MediaQuery.of(context).viewInsets;
    final screenHeight = MediaQuery.of(context).size.height;
    // When keyboard is open, limit list height so the whole sheet fits above the keyboard
    final availableHeight = screenHeight - viewInsets.bottom;
    const fixedHeaderHeight = 140.0; // handle + title + search + padding
    final maxListHeight = (availableHeight - fixedHeaderHeight).clamp(80.0, screenHeight * 0.45);

    return Padding(
      padding: EdgeInsets.only(bottom: viewInsets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 12),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: ZCTheme.border,
              borderRadius: BorderRadius.circular(100),
            ),
          ),
          const SizedBox(height: 16),

          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Text('Which product is this?',
                    style: TextStyle(
                      color: ZCTheme.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    )),
              ],
            ),
          ),
          const SizedBox(height: 12),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              controller: _searchCtrl,
              autofocus: false,
              style: const TextStyle(color: ZCTheme.textPrimary, fontSize: 13),
              decoration: InputDecoration(
                hintText: 'Search brand or label…',
                prefixIcon: const Icon(Icons.search, color: ZCTheme.textMuted, size: 18),
                isDense: true,
                filled: true,
                fillColor: ZCTheme.surfaceAlt,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide.none),
              ),
            ),
          ),
          const SizedBox(height: 8),

          ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxListHeight),
            child: _filtered.isEmpty
                ? const Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('No matches',
                        style: TextStyle(color: ZCTheme.textMuted)),
                  )
                : ListView.builder(
                    shrinkWrap: true,
                    itemCount: _filtered.length,
                    itemBuilder: (_, i) {
                      final v = _filtered[i];
                      final isCurrent = v.id == widget.current?.id;
                      return InkWell(
                        onTap: () => Navigator.pop(context, v),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 20, vertical: 14),
                          decoration: BoxDecoration(
                            color: isCurrent
                                ? ZCTheme.accent.withOpacity(0.08)
                                : Colors.transparent,
                            border: Border(
                              bottom: BorderSide(color: ZCTheme.border.withOpacity(0.5)),
                            ),
                          ),
                          child: Row(
                            children: [
                              // Category pill
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: ZCTheme.surfaceAlt,
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(color: ZCTheme.border),
                                ),
                                child: Text(
                                  v.category,
                                  style: const TextStyle(
                                    color: ZCTheme.textMuted,
                                    fontSize: 9,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              // Label
                              Expanded(
                                child: Text(
                                  v.fullLabel,
                                  style: TextStyle(
                                    color: isCurrent
                                        ? ZCTheme.accent
                                        : ZCTheme.textPrimary,
                                    fontSize: 13,
                                    fontFamily: 'monospace',
                                    fontWeight: isCurrent
                                        ? FontWeight.w700
                                        : FontWeight.w500,
                                  ),
                                ),
                              ),
                              // Selected indicator
                              if (isCurrent)
                                const Icon(Icons.check_circle,
                                    color: ZCTheme.accent, size: 16),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}
