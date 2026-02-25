// ─────────────────────────────────────────────
//  ZERO-CLEAN  ·  Review Screen
// ─────────────────────────────────────────────

import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:path/path.dart' as p;
import '../providers/app_state.dart';
import '../widgets/widgets.dart';
import '../theme.dart';
import '../models/models.dart';
import '../services/filesystem_service.dart';
import 'bbox_nudge_screen.dart';

class ReviewScreen extends StatefulWidget {
  const ReviewScreen({super.key});

  @override
  State<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends State<ReviewScreen> {
  List<_CaptureEntry> _entries = [];
  bool _loading = false;
  /// 'unprocessed' | 'single' | 'shelf' | 'checkout'
  String _reviewFilter = 'unprocessed';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final state = context.read<AppState>();
    if (state.selectedShop == null) {
      setState(() {
        _entries = [];
        _loading = false;
      });
      return;
    }

    setState(() => _loading = true);
    try {
      final fs = FileSystemService.instance;
      final entries = <_CaptureEntry>[];

      if (_reviewFilter == 'unprocessed') {
        final dirPath = await fs.getUnprocessedPath(shopName: state.selectedShop!.name);
        final dir = Directory(dirPath);

        if (await dir.exists()) {
          final files = await dir.list().toList();
          final images = files.where((f) => f.path.endsWith('.jpg')).toList();
          for (final img in images) {
            final base = p.withoutExtension(img.path);
            final jsonPath = '$base.json';
            final jsonFile = File(jsonPath);
            Map<String, dynamic>? meta;
            List<Annotation> annotations = [];
            String? shopId;
            String? shopName;
            String? category;
            String? variantLabel;

            if (await jsonFile.exists()) {
              try {
                meta = jsonDecode(await jsonFile.readAsString()) as Map<String, dynamic>;
                final annList = meta['annotations'] as List?;
                if (annList != null) {
                  annotations = annList
                      .map((a) => Annotation.fromMap(a as Map<String, dynamic>))
                      .toList();
                }
                shopId = meta['shop_id'] as String?;
                shopName = meta['shop_name'] as String?;
                category = meta['category'] as String?;
                variantLabel = meta['variant_label'] as String?;
              } catch (_) {}
            }

            entries.add(_CaptureEntry(
              imagePath: img.path,
              jsonPath: jsonPath,
              meta: meta,
              annotations: annotations,
              isUnprocessed: true,
              shopId: shopId ?? state.selectedShop?.id,
              shopName: shopName,
              category: category,
              variantLabel: variantLabel,
            ));
          }
        }
        entries.sort((a, b) => b.imagePath.compareTo(a.imagePath));
      } else {
        // Processed (single / shelf / checkout): reference cache, 72h retention
        final list = await fs.listReferenceCacheImages(shopContext: _reviewFilter);
        for (final item in list) {
          final meta = item['meta'] as Map<String, dynamic>? ?? {};
          List<Annotation> annotations = [];
          final annList = meta['annotations'] as List?;
          if (annList != null) {
            for (final a in annList) {
              try {
                if (a is Map<String, dynamic>) {
                  annotations.add(Annotation.fromMap(a));
                }
              } catch (_) {}
            }
          }
          entries.add(_CaptureEntry(
            imagePath: item['imagePath'] as String,
            jsonPath: item['jsonPath'] as String,
            meta: meta,
            annotations: annotations,
            isUnprocessed: false,
            shopId: meta['shop_id'] as String?,
            shopName: meta['shop_name'] as String?,
            category: meta['category'] as String?,
            variantLabel: meta['variant_label'] as String?,
          ));
        }
      }

      if (mounted) {
        setState(() {
          _entries = entries;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _entries = [];
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('REVUE'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _load,
          ),
        ],
      ),
      body: Column(
        children: [
          // Top section (shop, selectors, stats) — flexible and scrollable when keyboard opens
          Flexible(
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (state.selectedShop != null)
                    Container(
                      width: double.infinity,
                      color: ZCTheme.surfaceAlt,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: Row(
                        children: [
                          Icon(Icons.store_rounded, size: 18, color: ZCTheme.textMuted),
                          const SizedBox(width: 8),
                          Text(
                            state.selectedShop!.name,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: ZCTheme.textPrimary,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  Container(
                    color: ZCTheme.surface,
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: ZCDropdown<String>(
                                label: 'FILTRE',
                                value: _reviewFilter,
                                items: const [
                                  DropdownMenuItem(value: 'unprocessed', child: Text('Non traités')),
                                  DropdownMenuItem(value: 'single', child: Text('Unité')),
                                  DropdownMenuItem(value: 'shelf', child: Text('Rayon')),
                                  DropdownMenuItem(value: 'checkout', child: Text('Caisse')),
                                ],
                                onChanged: (v) async {
                                  if (v != null) {
                                    setState(() => _reviewFilter = v);
                                    await _load();
                                  }
                                },
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  if (_entries.isNotEmpty) _StatsBar(entries: _entries),
                ],
              ),
            ),
          ),

          // Image grid
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _entries.isEmpty
                    ? EmptyState(
                        message: _reviewFilter == 'unprocessed'
                            ? 'Aucune capture non traitée. Allez dans Capture pour en ajouter.'
                            : 'Les images traitées sont enregistrées dans le cloud. Pas de liste locale.',
                        actionLabel: _reviewFilter == 'unprocessed' ? 'Aller à Capture' : null,
                        onAction: () {},
                      )
                    : GridView.builder(
                        padding: const EdgeInsets.all(8),
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          crossAxisSpacing: 4,
                          mainAxisSpacing: 4,
                          childAspectRatio: 1,
                        ),
                        cacheExtent: 400,
                        itemCount: _entries.length,
                        itemBuilder: (ctx, i) => _ImageTile(
                          entry: _entries[i],
                          onTap: () => _openNudge(_entries[i]),
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  Future<void> _openNudge(_CaptureEntry entry) async {
    final state = context.read<AppState>();
    final variant = entry.variantLabel != null
        ? state.variants.where((v) => v.fullLabel == entry.variantLabel).firstOrNull
        : (entry.annotations.isNotEmpty && entry.annotations.first.variantId != null)
            ? state.variants.where((v) => v.id == entry.annotations.first.variantId).firstOrNull
            : null;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => BBoxNudgeScreen(
          imagePath: entry.imagePath,
          jsonPath: entry.jsonPath,
          initialAnnotations: entry.annotations,
          variant: variant ?? state.selectedVariant,
          allVariants: state.variants,
          isUnprocessed: entry.isUnprocessed,
          shopId: entry.shopId,
          shopName: entry.shopName,
          category: entry.category,
          variantLabel: entry.variantLabel ?? state.selectedVariant?.fullLabel,
        ),
      ),
    );
    await _load();
  }
}

// ── Stats bar ──────────────────────────────────

class _StatsBar extends StatelessWidget {
  final List<_CaptureEntry> entries;
  const _StatsBar({required this.entries});

  @override
  Widget build(BuildContext context) {
    final total = entries.length;
    final annotated = entries.where((e) => e.annotations.isNotEmpty).length;

    return Container(
      color: ZCTheme.surfaceAlt,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          _Stat('$total', 'total', ZCTheme.textSecondary),
          const SizedBox(width: 20),
          _Stat('$annotated', 'annotés', ZCTheme.accent),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final String value;
  final String label;
  final Color color;
  const _Stat(this.value, this.label, this.color);

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(value,
            style: TextStyle(
                color: color,
                fontWeight: FontWeight.w800,
                fontSize: 14,
                fontFamily: 'monospace')),
        const SizedBox(width: 4),
        Text(label,
            style: const TextStyle(color: ZCTheme.textMuted, fontSize: 11)),
      ],
    );
  }
}

// ── Data class ─────────────────────────────────

class _CaptureEntry {
  final String imagePath;
  final String jsonPath;
  final Map<String, dynamic>? meta;
  final List<Annotation> annotations;
  final bool isUnprocessed;
  final String? shopId;
  final String? shopName;
  final String? category;
  final String? variantLabel;

  _CaptureEntry({
    required this.imagePath,
    required this.jsonPath,
    this.meta,
    this.annotations = const [],
    this.isUnprocessed = false,
    this.shopId,
    this.shopName,
    this.category,
    this.variantLabel,
  });

  bool get isFullyVerified =>
      annotations.isNotEmpty && annotations.every((a) => a.verified);

  bool get hasPendingBoxes =>
      annotations.isNotEmpty && annotations.any((a) => !a.verified);

  bool get hasNoBoxes => annotations.isEmpty;
}

// ── Image tile ────────────────────────────────
// Uses cacheWidth/cacheHeight to decode thumbnails and avoid OOM with many photos.

class _ImageTile extends StatelessWidget {
  final _CaptureEntry entry;
  final VoidCallback onTap;

  const _ImageTile({required this.entry, required this.onTap});

  /// Thumbnail size for grid; decoding at this size avoids OOM with many images.
  static const int _cacheWidth = 300;
  static const int _cacheHeight = 300;

  @override
  Widget build(BuildContext context) {
    final hasAnnotations = entry.annotations.isNotEmpty;
    final showAnnoterChip = entry.isUnprocessed && !hasAnnotations;

    return GestureDetector(
      onTap: onTap,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.file(
            File(entry.imagePath),
            fit: BoxFit.cover,
            cacheWidth: _cacheWidth,
            cacheHeight: _cacheHeight,
            errorBuilder: (_, __, ___) => Container(
              color: ZCTheme.surfaceAlt,
              child: const Icon(Icons.broken_image, color: ZCTheme.textMuted),
            ),
          ),
          // Slight dim when unprocessed and not annotated
          if (showAnnoterChip)
            Container(color: Colors.black.withOpacity(0.2)),
          // Box count when annotated
          if (hasAnnotations)
            Positioned(
              bottom: 4,
              left: 4,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.7),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  '${entry.annotations.length}',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 9,
                      fontWeight: FontWeight.w700),
                ),
              ),
            ),
          // ANNOTER: unprocessed images that still need annotation
          if (showAnnoterChip)
            const Positioned(
              bottom: 4,
              right: 4,
              child: Text(
                'ANNOTER',
                style: TextStyle(
                  color: ZCTheme.gold,
                  fontSize: 8,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          // TRAITÉ: processed images (already saved, in reference cache)
          if (!entry.isUnprocessed)
            Positioned(
              bottom: 4,
              right: 4,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.7),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text(
                  'TRAITÉ',
                  style: TextStyle(
                    color: ZCTheme.accent,
                    fontSize: 8,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
