// ─────────────────────────────────────────────
//  ZERO-CLEAN  ·  Dashboard Screen
// ─────────────────────────────────────────────

import 'package:flutter/material.dart';
import '../models/models.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import '../widgets/widgets.dart';
import '../theme.dart';
import '../services/filesystem_service.dart';
import 'add_shop_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  String _datasetSize = '—';
  String _datasetPath = '—';
  int _datasetBytes = 0;

  @override
  void initState() {
    super.initState();
    _loadStorageInfo();
    // Retry load when dashboard is first shown with empty data (e.g. if init failed)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final state = context.read<AppState>();
      if (!state.isLoading &&
          state.shops.isEmpty &&
          state.variants.isEmpty) {
        context.read<AppState>().refreshFromDatabase();
      }
    });
  }

  Future<void> _loadStorageInfo() async {
    final fs = FileSystemService.instance;
    final bytes = await fs.getDatasetSize();
    final path = await fs.getDatasetRootPath();
    setState(() {
      _datasetBytes = bytes;
      _datasetSize = fs.formatBytes(bytes);
      _datasetPath = path;
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();

    if (state.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            Text('ZERO',
                style: TextStyle(
                    color: ZCTheme.accent, fontWeight: FontWeight.w900)),
            Text('-CLEAN', style: TextStyle(color: ZCTheme.textPrimary)),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_business_outlined),
            onPressed: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const AddShopScreen())),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: RefreshIndicator(
        color: ZCTheme.accent,
        onRefresh: () async {
          await context.read<AppState>().refreshFromDatabase();
          await _loadStorageInfo();
        },
        child: CustomScrollView(
          slivers: [
            if (state.loadError != null)
              SliverToBoxAdapter(
                child: Container(
                  width: double.infinity,
                  margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: ZCTheme.critical.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: ZCTheme.critical),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'Impossible de charger les données',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: ZCTheme.critical,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        state.loadError!,
                        style: const TextStyle(
                          fontSize: 12,
                          color: ZCTheme.textPrimary,
                        ),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 8),
                      TextButton.icon(
                        onPressed: () =>
                            context.read<AppState>().refreshFromDatabase(),
                        icon: const Icon(Icons.refresh, size: 18),
                        label: const Text('Réessayer'),
                        style: TextButton.styleFrom(
                          foregroundColor: ZCTheme.critical,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            SliverPadding(
              padding: const EdgeInsets.all(16),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  // Shop selector (from DB)
                  _ShopSelector(),
                  const SizedBox(height: 20),

                  // Stats: two equal cards + size bar
                  Row(
                    children: [
                      Expanded(
                        child: StatTile(
                          label: 'IMAGES TOTALES',
                          value: '${state.totalStats['total_images'] ?? 0}',
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: StatTile(
                          label: 'VARIANTES',
                          value: '${state.totalStats['total_variants'] ?? 0}',
                          valueColor: ZCTheme.gold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _DatasetSizeBar(
                    label: 'TAILLE DU JEU',
                    sizeText: _datasetSize,
                    bytes: _datasetBytes,
                  ),
                  const SizedBox(height: 20),

                  // Filter toggle
                  SectionHeader(
                    title: 'Variantes',
                    trailing: GestureDetector(
                      onTap: () {
                        context.read<AppState>().toggleShowUnderCollectedOnly();
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: state.showUnderCollectedOnly
                              ? ZCTheme.critical.withOpacity(0.2)
                              : ZCTheme.surfaceAlt,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: state.showUnderCollectedOnly
                                ? ZCTheme.critical
                                : ZCTheme.border,
                          ),
                        ),
                        child: Text(
                          '🔴 Sous-collectés uniquement',
                          style: TextStyle(
                            color: state.showUnderCollectedOnly
                                ? ZCTheme.critical
                                : ZCTheme.textMuted,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),

                  // Variant cards
                  if (state.variantSummaries.isEmpty)
                    const EmptyState(
                      message:
                          'Aucune variante pour l\'instant.\nAjoutez des produits dans l\'onglet Config.',
                    )
                  else
                    ...state.variantSummaries.map(
                      (s) => VariantCard(summary: s),
                    ),

                  const SizedBox(height: 8),
                  // Dataset path
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: ZCTheme.surfaceAlt,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: ZCTheme.border),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.folder_outlined,
                            color: ZCTheme.textMuted, size: 16),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _datasetPath,
                            style: const TextStyle(
                              color: ZCTheme.textMuted,
                              fontSize: 10,
                              fontFamily: 'monospace',
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DatasetSizeBar extends StatelessWidget {
  final String label;
  final String sizeText;
  final int bytes;

  const _DatasetSizeBar({
    required this.label,
    required this.sizeText,
    required this.bytes,
  });

  @override
  Widget build(BuildContext context) {
    const int oneGb = 1024 * 1024 * 1024;
    final double barValue = bytes <= 0 ? 0.0 : (bytes / oneGb).clamp(0.0, 1.0);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: ZCTheme.surfaceAlt,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: ZCTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                label,
                style: const TextStyle(
                  color: ZCTheme.textMuted,
                  fontSize: 11,
                  letterSpacing: 0.5,
                ),
              ),
              Text(
                sizeText,
                style: const TextStyle(
                  color: ZCTheme.textSecondary,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  fontFamily: ZCTheme.fontMono,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: barValue,
              minHeight: 8,
              backgroundColor: ZCTheme.border,
              color: ZCTheme.accent,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '0 — 1 GB',
            style: TextStyle(
              color: ZCTheme.textMuted.withOpacity(0.8),
              fontSize: 9,
            ),
          ),
        ],
      ),
    );
  }
}

class _ShopSelector extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    if (state.shops.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
        decoration: BoxDecoration(
          color: ZCTheme.surfaceAlt,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: ZCTheme.border),
        ),
        child: Row(
          children: [
            const Icon(Icons.store_outlined, color: ZCTheme.textMuted, size: 20),
            const SizedBox(width: 8),
            Text(
              'Aucun magasin — ajoutez-en un dans Config',
              style: const TextStyle(
                color: ZCTheme.textMuted,
                fontSize: 13,
              ),
            ),
          ],
        ),
      );
    }
    // Value must be the same reference as an item in the list (DropdownButtonFormField requirement).
    // After refreshFromDatabase() the list is replaced so selectedShop can be a stale reference.
    final shopValue = state.selectedShop == null
        ? null
        : state.shops
            .where((s) => s.id == state.selectedShop!.id)
            .firstOrNull;

    return ZCDropdown<Shop>(
      label: 'MAGASIN ACTIF',
      value: shopValue,
      items: state.shops
          .map((s) => DropdownMenuItem(
                value: s,
                child: Text(s.name),
              ))
          .toList(),
      onChanged: (s) {
        if (s != null) state.selectShop(s);
      },
    );
  }
}
