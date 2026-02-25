// ─────────────────────────────────────────────
//  ZERO-CLEAN  ·  Capture Screen (Final Polished UI)
// ─────────────────────────────────────────────

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:camera/camera.dart';
import 'package:provider/provider.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';
import 'dart:async';
import '../providers/app_state.dart';
import '../widgets/widgets.dart';
import '../theme.dart';
import '../models/models.dart';
import '../services/filesystem_service.dart';

class CaptureScreen extends StatefulWidget {
  const CaptureScreen({super.key});

  @override
  State<CaptureScreen> createState() => CaptureScreenState();
}

class CaptureScreenState extends State<CaptureScreen>
    with WidgetsBindingObserver, RouteAware {
  CameraController? _cameraController;
  List<CameraDescription> _cameras = [];
  bool _cameraReady = false;
  bool _isCapturing = false;

  String? _lastImagePath;
  bool _exposureLocked = false;
  int _sessionCaptureCount = 0;

  // ── CHANGE 1: Flash state — off by default, user-controlled ──
  FlashMode _flashMode = FlashMode.off;

  // ── CHANGE 1: Whether this tab is currently visible ──
  bool _isPageActive = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  // Called by the parent IndexedStack whenever this tab is shown
  // We use didChangeDependencies + RouteObserver alternative:
  // the simplest reliable approach for IndexedStack is WidgetsBindingObserver
  // combined with a visibility flag set from didUpdateWidget / the tab switch.
  // But the cleanest way with IndexedStack is to init/dispose camera based on
  // the app lifecycle AND whether this widget is the active index.
  // We expose activate() / deactivate() called from the tab controller.

  void activate() {
    super.activate();
    if (_isPageActive) return;
    _isPageActive = true;
    _initCamera();
  }

  void deactivate() {
    if (!_isPageActive) return;
    _isPageActive = false;
    _releaseCamera();
    super.deactivate();
  }

  Future<void> _initCamera() async {
    if (_cameraReady) return;
    _cameras = await availableCameras();
    if (_cameras.isEmpty) return;
    final ctrl = CameraController(
      _cameras.first,
      ResolutionPreset.high,
      enableAudio: false,
    );
    await ctrl.initialize();
    if (!mounted || !_isPageActive) {
      await ctrl.dispose();
      return;
    }
    // Apply the current flash mode right after init
    await ctrl.setFlashMode(_flashMode).catchError((_) {});
    setState(() {
      _cameraController = ctrl;
      _cameraReady = true;
    });
  }

  Future<void> _releaseCamera() async {
    final ctrl = _cameraController;
    if (ctrl == null) return;
    _cameraController = null;
    _cameraReady = false;
    _exposureLocked = false;
    _sessionCaptureCount = 0;
    if (mounted) setState(() {});
    await ctrl.dispose();
  }

  // ── CHANGE 1: Release camera when app goes to background ──
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      _releaseCamera();
    } else if (state == AppLifecycleState.resumed && _isPageActive) {
      _initCamera();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _releaseCamera();
    super.dispose();
  }

  // ── CHANGE 2: Flash toggle button ──────────────────────────
  Future<void> _toggleFlash() async {
    final nextMode = _flashMode == FlashMode.off
        ? FlashMode.torch   // torch = constant on (best for product shots)
        : FlashMode.off;
    setState(() => _flashMode = nextMode);
    await _cameraController?.setFlashMode(nextMode).catchError((_) {});
  }

  // ── Drag Menu ─────────────────────────────────────────────
  void _showSettingsSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: ZCTheme.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
      ),
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.6,
          minChildSize: 0.4,
          maxChildSize: 0.95,
          expand: false,
          builder: (context, scrollController) {
            return StatefulBuilder(
              builder: (context, setSheetState) {
                final state = context.watch<AppState>();
                return SingleChildScrollView(
                  controller: scrollController,
                  padding: const EdgeInsets.fromLTRB(24, 16, 24, 40),
                  child: Column(
                    children: [
                      // Pill-style Handle
                      Container(
                        width: 50,
                        height: 6,
                        decoration: BoxDecoration(
                          color: ZCTheme.border.withOpacity(0.5),
                          borderRadius: BorderRadius.circular(100),
                        ),
                      ),
                      const SizedBox(height: 32),

                      // Current shop (display only)
                      if (state.selectedShop != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 16),
                          child: Row(
                            children: [
                              Icon(Icons.store_rounded,
                                  size: 20, color: ZCTheme.textMuted),
                              const SizedBox(width: 10),
                              Text(
                                state.selectedShop!.name,
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: ZCTheme.textPrimary,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),

                      ZCDropdown<String>(
                        label: 'CATÉGORIE',
                        value: state.selectedCategory,
                        items: state.categories
                            .map((c) =>
                                DropdownMenuItem(value: c, child: Text(c)))
                            .toList(),
                        onChanged: (val) {
                          if (val != null) state.selectCategory(val);
                        },
                      ),
                      const SizedBox(height: 20),
                      ZCDropdown<Variant>(
                        label: 'VARIANTE',
                        value: state.selectedVariant == null
                            ? null
                            : state.variantsInSelectedCategory
                                .where((v) =>
                                    v.id == state.selectedVariant!.id)
                                .firstOrNull,
                        items: state.variantsInSelectedCategory
                            .map((v) => DropdownMenuItem(
                                value: v,
                                child: Text(v.fullLabel,
                                    overflow: TextOverflow.ellipsis)))
                            .toList(),
                        onChanged: (v) {
                          if (v != null) state.selectVariant(v);
                        },
                        enabled: state.selectedCategory != null,
                      ),
                      const SizedBox(height: 20),
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: Divider(color: ZCTheme.border, thickness: 1),
                      ),
                      _ProgressStatsSection(state: state),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  static const _guideAssetPath = 'assets/guide/product_photography_guide_fr.pdf';

  Future<void> _openCaptureGuide() async {
    try {
      final data = await rootBundle.load(_guideAssetPath);
      final tempDir = await getTemporaryDirectory();
      final file = File('${tempDir.path}/product_photography_guide_fr.pdf');
      await file.writeAsBytes(data.buffer.asUint8List());
      final result = await OpenFilex.open(file.path);
      if (result.type != ResultType.done && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result.message),
            backgroundColor: ZCTheme.surfaceAlt,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e, st) {
      debugPrint('Guide open error: $e');
      debugPrint('$st');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Guide indisponible. Réinstallez l\'app.'),
            backgroundColor: ZCTheme.critical,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  // ── Capture Logic ─────────────────────────────────────────
  Future<void> _capture() async {
    final state = context.read<AppState>();
    if (!state.canOpenCamera || _isCapturing || !_cameraReady) return;

    setState(() => _isCapturing = true);

    try {
      final xFile = await _cameraController!.takePicture();

      if (!_exposureLocked && _sessionCaptureCount == 0) {
        await _cameraController!
            .setExposureMode(ExposureMode.locked)
            .catchError((_) {});
        await _cameraController!
            .setFocusMode(FocusMode.locked)
            .catchError((_) {});
        setState(() => _exposureLocked = true);
      }

      final unprocessedPath = await state.buildUnprocessedPath();
      await FileSystemService.instance.captureToUnprocessed(
        unprocessedPath: unprocessedPath,
        tempImagePath: xFile.path,
        shopId: state.selectedShop!.id!,
        shopName: state.selectedShop!.name,
        context: state.selectedContext,
        annotations: [],
      );

      _sessionCaptureCount++;
      setState(() => _lastImagePath = xFile.path);
    } catch (e) {
      debugPrint("Capture error: $e");
    } finally {
      setState(() => _isCapturing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();

    final bottomPadding = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('CAPTURE',
            style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 2)),
        actions: [
          IconButton(
            icon: const Icon(Icons.menu_book_rounded, color: Colors.white70),
            onPressed: _openCaptureGuide,
            tooltip: 'Guide de prise de photos',
          ),
        ],
      ),
      body: Stack(
        children: [
          // 1. FULL SCREEN CAMERA
          Positioned.fill(
            child: _cameraReady && _cameraController != null
                ? CameraPreview(_cameraController!)
                : const Center(
                    child: CircularProgressIndicator(color: ZCTheme.accent)),
          ),

          // 2. LARGE THUMBNAIL PREVIEW
          if (_lastImagePath != null)
            Positioned(
              top: MediaQuery.of(context).padding.top + 70,
              left: 16,
              child: Container(
                width: 120,
                height: 160,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white, width: 3),
                  boxShadow: const [
                    BoxShadow(color: Colors.black54, blurRadius: 12)
                  ],
                  image: DecorationImage(
                      image: FileImage(File(_lastImagePath!)),
                      fit: BoxFit.cover),
                ),
              ),
            ),

          // 3. THUMB-LEVEL CONTROLS: Flash + Shutter + Options
          Positioned(
            left: 0,
            right: 0,
            bottom: bottomPadding + 24,
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (state.isSelectedVariantUnsynced)
                    Container(
                      margin: const EdgeInsets.only(left: 20, right: 20, bottom: 12),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: ZCTheme.textMuted.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.info_outline, size: 16, color: ZCTheme.textMuted),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Ce produit sera synchronisé lorsque vous appuierez sur Sync (Config).',
                              style: TextStyle(color: ZCTheme.textMuted, fontSize: 11),
                            ),
                          ),
                        ],
                      ),
                    ),
                  Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 56,
                    height: 56,
                    child: IconButton(
                      icon: Icon(
                        _flashMode == FlashMode.off
                            ? Icons.flash_off_rounded
                            : Icons.flash_on_rounded,
                        color: _flashMode == FlashMode.off
                            ? Colors.white70
                            : ZCTheme.gold,
                        size: 28,
                      ),
                      onPressed: _cameraReady ? _toggleFlash : null,
                      tooltip: _flashMode == FlashMode.off
                          ? 'Flash désactivé'
                          : 'Flash activé',
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.black.withOpacity(0.4),
                      ),
                    ),
                  ),
                  _ShutterButton(
                    isCapturing: _isCapturing,
                    canCapture: state.canOpenCamera && _cameraReady,
                    onCapture: _capture,
                  ),
                  SizedBox(
                    width: 56,
                    height: 56,
                    child: IconButton(
                      icon: const Icon(
                        Icons.tune_rounded,
                        color: Colors.white,
                        size: 28,
                      ),
                      onPressed: _showSettingsSheet,
                      tooltip: 'Paramètres',
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.black.withOpacity(0.4),
                      ),
                    ),
                  ),
                  ],
                ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
// UI COMPONENTS
// ─────────────────────────────────────────────

/// Progress per context for the selected variant (in bottom sheet).
class _ProgressStatsSection extends StatelessWidget {
  final AppState state;

  const _ProgressStatsSection({required this.state});

  @override
  Widget build(BuildContext context) {
    if (state.selectedVariant == null || state.selectedShop == null) {
      return const SizedBox();
    }
    final variantId = state.selectedVariant!.id!;
    final shopId = state.selectedShop!.id!;
    final progressList = state.shopProgress
        .where((p) => p.variantId == variantId && p.shopId == shopId)
        .toList();
    if (progressList.isEmpty) {
      return const Padding(
        padding: EdgeInsets.only(top: 8),
        child: Text(
          'Aucun progrès pour l\'instant — capturez puis annotez pour compter.',
          style: TextStyle(color: ZCTheme.textMuted, fontSize: 11),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            'PROGRÈS (cette variante)',
            style: TextStyle(
              color: ZCTheme.textMuted,
              fontSize: 11,
              letterSpacing: 0.5,
            ),
          ),
        ),
        Row(
          children: progressList.map((p) {
            final label = p.context == CaptureContext.single
                ? 'Unité'
                : p.context == CaptureContext.shelf
                    ? 'Rayon'
                    : 'Caisse';
            return Expanded(
              child: Container(
                margin: const EdgeInsets.only(right: 6),
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: ZCTheme.surfaceAlt,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: ZCTheme.progressColor(p.pct),
                    width: 1,
                  ),
                ),
                child: Column(
                  children: [
                    Text(
                      '$label',
                      style: const TextStyle(
                        color: ZCTheme.textMuted,
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${p.currentCount}/${p.targetCap}',
                      style: TextStyle(
                        color: ZCTheme.progressColor(p.pct),
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}

class _ShutterButton extends StatelessWidget {
  final bool isCapturing;
  final bool canCapture;
  final VoidCallback onCapture;

  const _ShutterButton(
      {required this.isCapturing,
      required this.canCapture,
      required this.onCapture});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: canCapture ? onCapture : null,
      child: Center(
        child: Container(
          width: 90,
          height: 90,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
                color: canCapture ? Colors.white : Colors.white24, width: 5),
          ),
          child: Center(
            child: isCapturing
                ? const CircularProgressIndicator(
                    color: Colors.white, strokeWidth: 4)
                : Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      color: canCapture ? Colors.white : Colors.white24,
                      shape: BoxShape.circle,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

