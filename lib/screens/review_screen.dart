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
    if (_reviewFilter != 'unprocessed' && state.selectedVariant == null) {
      setState(() {
        _entries = [];
        _loading = false;
      });
      return;
    }

    setState(() => _loading = true);
    try {
      final fs = FileSystemService.instance;
      String dirPath;
      if (_reviewFilter == 'unprocessed') {
        dirPath = await fs.getUnprocessedPath(shopName: state.selectedShop!.name);
      } else {
        final ctx = CaptureContext.values
            .firstWhere((c) => c.name == _reviewFilter, orElse: () => CaptureContext.single);
        dirPath = await fs.getSavePath(
          shopName: state.selectedShop!.name,
          category: state.selectedVariant!.category,
          variantLabel: state.selectedVariant!.fullLabel,
          context: ctx,
        );
      }

      final dir = Directory(dirPath);
      final entries = <_CaptureEntry>[];

      if (await dir.exists()) {
        final files = await dir.list().toList();
        final images = files.where((f) => f.path.endsWith('.jpg')).toList();
        for (final img in images) {
          final base = p.withoutExtension(img.path);
          final jsonPath = '$base.json';
          final jsonFile = File(jsonPath);
          Map<String, dynamic>? meta;
          List<Annotation> annotations = [];
          bool isUnprocessed = _reviewFilter == 'unprocessed';
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
              if (isUnprocessed) {
                shopName = meta['shop_name'] as String?;
                category = meta['category'] as String?;
                variantLabel = meta['variant_label'] as String?;
              }
            } catch (_) {}
          }

          entries.add(_CaptureEntry(
            imagePath: img.path,
            jsonPath: jsonPath,
            meta: meta,
            annotations: annotations,
            isUnprocessed: isUnprocessed,
            shopName: shopName,
            category: category,
            variantLabel: variantLabel,
          ));
        }
      }

      if (mounted) {
        setState(() {
          _entries = entries.reversed.toList();
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
                              flex: 2,
                              child: ZCDropdown<Variant>(
                                label: 'VARIANTE',
                                value: state.selectedVariant == null
                                    ? null
                                    : state.variants
                                        .where((v) => v.id == state.selectedVariant!.id)
                                        .firstOrNull,
                                items: state.variants
                                    .map((v) => DropdownMenuItem(
                                        value: v,
                                        child: Text(v.fullLabel,
                                            overflow: TextOverflow.ellipsis)))
                                    .toList(),
                                onChanged: (v) async {
                                  if (v != null) {
                                    state.selectVariant(v);
                                    await _load();
                                  }
                                },
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              flex: 1,
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
                            : 'Aucune capture pour cette variante/contexte.',
                        actionLabel: 'Aller à Capture',
                        onAction: () {},
                      )
                    : GridView.builder(
                        padding: const EdgeInsets.all(8),
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          crossAxisSpacing: 4,
                          mainAxisSpacing: 4,
                        ),
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
    final variant = entry.isUnprocessed && entry.variantLabel != null
        ? state.variants
            .where((v) => v.fullLabel == entry.variantLabel)
            .firstOrNull
        : state.selectedVariant;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => BBoxNudgeScreen(
          imagePath: entry.imagePath,
          jsonPath: entry.jsonPath,
          initialAnnotations: entry.annotations,
          variant: variant,
          allVariants: state.variants,
          isUnprocessed: entry.isUnprocessed,
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
  final String? shopName;
  final String? category;
  final String? variantLabel;

  _CaptureEntry({
    required this.imagePath,
    required this.jsonPath,
    this.meta,
    this.annotations = const [],
    this.isUnprocessed = false,
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

class _ImageTile extends StatelessWidget {
  final _CaptureEntry entry;
  final VoidCallback onTap;

  const _ImageTile({required this.entry, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final hasAnnotations = entry.annotations.isNotEmpty;

    return GestureDetector(
      onTap: onTap,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.file(
            File(entry.imagePath),
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => Container(
              color: ZCTheme.surfaceAlt,
              child: const Icon(Icons.broken_image, color: ZCTheme.textMuted),
            ),
          ),
          // Slight dim when not annotated (needs check)
          if (!hasAnnotations)
            Container(color: Colors.black.withOpacity(0.2)),
          // Box count when annotated (checked)
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
          // Only show NUDGE when no annotations (needs to be checked)
          if (!hasAnnotations)
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
        ],
      ),
    );
  }
}
