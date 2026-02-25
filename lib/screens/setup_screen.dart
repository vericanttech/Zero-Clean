// ─────────────────────────────────────────────
//  ZERO-CLEAN  ·  Setup Screen
// ─────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:geolocator/geolocator.dart';
import '../providers/app_state.dart';
import '../widgets/widgets.dart';
import '../theme.dart';
import '../models/models.dart';
import '../utils/sync_error_message.dart';
import '../utils/text_normalization.dart';

class SetupScreen extends StatelessWidget {
  const SetupScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('CONFIG')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: const [
          _MagasinSectionExpansion(),
          SizedBox(height: 24),
          _SyncPullSectionExpansion(),
          SizedBox(height: 24),
          SectionHeader(title: 'Variantes de produits'),
          _VariantList(),
          SizedBox(height: 24),
          SectionHeader(title: 'Compte'),
          _SignOutTile(),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'add_variant',
        onPressed: () => showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          backgroundColor: ZCTheme.surface,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          builder: (_) => const _AddVariantSheet(),
        ),
        icon: const Icon(Icons.add, color: ZCTheme.bg),
        label: const Text('Ajouter une variante',
            style: TextStyle(color: ZCTheme.bg, fontWeight: FontWeight.w700)),
        backgroundColor: ZCTheme.accent,
      ),
    );
  }
}

// ── Magasin (optional name + GPS) ─────────────────────

/// Wraps [_MagasinSection] in a collapsible expansion tile.
class _MagasinSectionExpansion extends StatelessWidget {
  const _MagasinSectionExpansion();

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        initiallyExpanded: false,
        tilePadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
        childrenPadding: const EdgeInsets.only(top: 8, bottom: 4),
        title: Text(
          'MAGASIN',
          style: TextStyle(
            color: ZCTheme.textMuted,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.2,
          ),
        ),
        children: const [_MagasinSection()],
      ),
    );
  }
}

class _MagasinSection extends StatefulWidget {
  const _MagasinSection();

  @override
  State<_MagasinSection> createState() => _MagasinSectionState();
}

class _MagasinSectionState extends State<_MagasinSection> {
  late TextEditingController _nameCtrl;
  double? _latitude;
  double? _longitude;
  bool _locationLoading = false;
  String? _locationError;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController();
    _nameCtrl.addListener(() => setState(() {}));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final shop = context.read<AppState>().selectedShop;
    if (shop == null) return;
    if (_nameCtrl.text.isEmpty && shop.name.isNotEmpty) _nameCtrl.text = shop.name;
    if (_latitude == null && shop.latitude != null) _latitude = shop.latitude;
    if (_longitude == null && shop.longitude != null) _longitude = shop.longitude;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _useMyLocation() async {
    setState(() {
      _locationError = null;
      _locationLoading = true;
    });
    try {
      final permission = await Permission.location.request();
      if (!permission.isGranted) {
        if (mounted) setState(() {
          _locationError = 'Autorisation de localisation refusée';
          _locationLoading = false;
        });
        return;
      }
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (mounted) setState(() {
          _locationError = 'Activez la localisation dans les paramètres';
          _locationLoading = false;
        });
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.medium),
      );
      if (mounted) setState(() {
        _latitude = pos.latitude;
        _longitude = pos.longitude;
        _locationError = null;
        _locationLoading = false;
      });
    } catch (e) {
      if (mounted) setState(() {
        _locationError = 'Impossible d\'obtenir la position';
        _locationLoading = false;
      });
    }
  }

  Future<void> _save() async {
    final appState = context.read<AppState>();
    if (appState.selectedShop == null) return;
    setState(() => _saving = true);
    try {
      final name = _nameCtrl.text.trim();
      await appState.updateShopProfile(
        name: name.isEmpty ? null : name,
        latitude: _latitude,
        longitude: _longitude,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Magasin mis à jour'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erreur: $e'),
            backgroundColor: ZCTheme.critical,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final shop = state.selectedShop;
    if (shop == null) return const SizedBox.shrink();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _nameCtrl,
              style: const TextStyle(color: ZCTheme.textPrimary),
              decoration: InputDecoration(
                labelText: _nameCtrl.text.trim().isEmpty ? 'Nom du magasin (optionnel)' : null,
                hintText: 'ex. Boutique Moussa',
                prefixIcon: const Icon(Icons.store_outlined),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                OutlinedButton.icon(
                  onPressed: _locationLoading ? null : _useMyLocation,
                  icon: _locationLoading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.my_location, size: 18),
                  label: Text(_locationLoading ? 'Chargement…' : 'Ma position (optionnel)'),
                ),
                if (_latitude != null && _longitude != null) ...[
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      '${_latitude!.toStringAsFixed(5)}, ${_longitude!.toStringAsFixed(5)}',
                      style: const TextStyle(
                        color: ZCTheme.textMuted,
                        fontSize: 11,
                        fontFamily: 'monospace',
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ],
            ),
            if (_locationError != null) ...[
              const SizedBox(height: 8),
              Text(
                _locationError!,
                style: const TextStyle(color: ZCTheme.critical, fontSize: 12),
              ),
            ],
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _saving ? null : _save,
                style: ElevatedButton.styleFrom(
                  backgroundColor: ZCTheme.accent,
                  foregroundColor: ZCTheme.bg,
                ),
                child: _saving
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: ZCTheme.bg),
                      )
                    : const Text('Enregistrer'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Synchronisation (manual Sync / Pull) ─────────────────────

/// Wraps [_SyncPullSection] in a collapsible expansion tile.
class _SyncPullSectionExpansion extends StatelessWidget {
  const _SyncPullSectionExpansion();

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        initiallyExpanded: false,
        tilePadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
        childrenPadding: const EdgeInsets.only(top: 8, bottom: 4),
        title: Text(
          'SYNCHRONISATION',
          style: TextStyle(
            color: ZCTheme.textMuted,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.2,
          ),
        ),
        children: const [_SyncPullSection()],
      ),
    );
  }
}

class _SyncPullSection extends StatelessWidget {
  const _SyncPullSection();

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final hasLocalData = state.shops.isNotEmpty;
    final syncing = state.isSyncingOrWriting;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Sync envoie les données locales vers Firebase. Récupérer charge les données depuis Firebase (uniquement quand il n\'y a pas de données locales).',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: ZCTheme.textMuted),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: ElevatedButton(
                    onPressed: syncing ? null : () => _sync(context),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: ZCTheme.accent,
                      foregroundColor: ZCTheme.bg,
                      minimumSize: const Size(140, 48),
                    ),
                    child: syncing
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: ZCTheme.bg),
                          )
                        : const Text('Synchroniser'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: OutlinedButton(
                    onPressed: (!syncing && !hasLocalData) ? () => _pull(context) : null,
                    child: const Text('Récupérer'),
                  ),
                ),
              ],
            ),
            if (hasLocalData)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Récupérer désactivé : données locales présentes.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: ZCTheme.textMuted, fontSize: 11),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _sync(BuildContext context) async {
    final state = context.read<AppState>();
    try {
      await state.syncNow();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Synchronisation terminée'), behavior: SnackBarBehavior.floating),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(userFriendlySyncError(e)),
            backgroundColor: ZCTheme.critical,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _pull(BuildContext context) async {
    final state = context.read<AppState>();
    if (state.shops.isNotEmpty) return;
    try {
      await state.pullNow();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Données récupérées'), behavior: SnackBarBehavior.floating),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(userFriendlySyncError(e)),
            backgroundColor: ZCTheme.critical,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }
}

class _VariantList extends StatelessWidget {
  const _VariantList();

  @override
  Widget build(BuildContext context) {
    final variants = context.watch<AppState>().variants;
    if (variants.isEmpty) {
      return const EmptyState(message: 'Aucune variante. Ajoutez des produits.');
    }

    // Group by category
    final grouped = <String, List<Variant>>{};
    for (final v in variants) {
      grouped.putIfAbsent(v.category, () => []).add(v);
    }

    return Column(
      children: grouped.entries.map((entry) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Text(
                entry.key.toUpperCase(),
                style: const TextStyle(
                  color: ZCTheme.accent,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2,
                ),
              ),
            ),
            ...entry.value.map((v) => Card(
                  child: ListTile(
                    leading: const Icon(Icons.inventory_2_outlined,
                        color: ZCTheme.textSecondary),
                    title: Text(v.fullLabel,
                        style: const TextStyle(
                            color: ZCTheme.textPrimary,
                            fontFamily: 'monospace',
                            fontSize: 13)),
                    subtitle: Text('${v.brand} · ${v.volume} · ${v.material}',
                        style: const TextStyle(color: ZCTheme.textMuted)),
                  ),
                )),
          ],
        );
      }).toList(),
    );
  }
}

// ── Sign out ───────────────────────────────────

class _SignOutTile extends StatelessWidget {
  const _SignOutTile();

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: const Icon(Icons.logout, color: ZCTheme.textSecondary),
        title: const Text('Se déconnecter',
            style: TextStyle(color: ZCTheme.textPrimary)),
        onTap: () => FirebaseAuth.instance.signOut(),
      ),
    );
  }
}

// ── Add Variant Sheet ─────────────────────────

class _AddVariantSheet extends StatefulWidget {
  const _AddVariantSheet();

  @override
  State<_AddVariantSheet> createState() => _AddVariantSheetState();
}

class _AddVariantSheetState extends State<_AddVariantSheet> {
  final _brandCtrl = TextEditingController();
  final _subBrandCtrl = TextEditingController();
  final _volumeCustomCtrl = TextEditingController();
  final _materialCustomCtrl = TextEditingController();
  final _categoryCustomCtrl = TextEditingController();
  String _category = 'Boissons';
  String _volume = '500ml';
  String _material = 'PET';
  bool _saving = false;

  // Catégories typiques boutique / épicerie locale (Sénégal)
  static const _categories = [
    'Boissons',
    'Fruits',
    'Légumes',
    'Épicerie',
    'Laitier',
    'Snacks',
    'Hygiène',
    'Petit-déjeuner',
    'Conserves',
    'Entretien',
    'Boulangerie',
    'Autre',
  ];
  // Volumes courants (Sénégal / FMCG) — "Unité" for single items (apple, onion, etc.)
  static const _volumes = [
    'Unité', '25cl', '33cl', '35cl', '50cl', '250ml', '330ml', '500ml', '750ml',
    '1L', '1.5L', '2L', '5L', 'Autre',
  ];
  // Matériaux — PRODUCE/UNPACKAGED = descriptive for training (avoid N/A in class names)
  static const _materials = [
    'PRODUCE', 'UNPACKAGED', 'PET', 'CAN', 'GLASS', 'TIN', 'SACHET', 'DOY_PACK', 'BOX', 'WRAP',
    'CARTON', 'BAG', 'POUCH', 'BIDON', 'Autre',
  ];

  @override
  void dispose() {
    _volumeCustomCtrl.dispose();
    _materialCustomCtrl.dispose();
    _categoryCustomCtrl.dispose();
    super.dispose();
  }

  String get _categoryValue =>
      _category == 'Autre' ? normalizeCategory(_categoryCustomCtrl.text) : _category;
  String get _volumeValue =>
      _volume == 'Autre' ? normalizeVariantName(_volumeCustomCtrl.text) : _volume;
  String get _materialValue =>
      _material == 'Autre' ? normalizeVariantName(_materialCustomCtrl.text) : _material;

  @override
  Widget build(BuildContext context) {
    final brand = normalizeVariantName(_brandCtrl.text);
    final subBrand = normalizeVariantName(_subBrandCtrl.text);
    final parts = subBrand.isEmpty
        ? [brand, _volumeValue, _materialValue]
        : [brand, subBrand, _volumeValue, _materialValue];
    final preview = collapseUnderscores(
        parts.where((s) => s.isNotEmpty).join('_'));

    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Ajouter une variante',
                style: TextStyle(
                    color: ZCTheme.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: ZCTheme.surfaceAlt,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: ZCTheme.accent.withOpacity(0.4)),
              ),
              child: Text(
                preview.isEmpty ? 'Marque_SousMarque_Volume_Matériau' : preview,
                style: const TextStyle(
                  color: ZCTheme.accent,
                  fontFamily: 'monospace',
                  fontSize: 12,
                ),
              ),
            ),
            const SizedBox(height: 16),
            _tagSection('Catégorie', _categories, _category, (c) => setState(() => _category = c)),
            if (_category == 'Autre') ...[
              const SizedBox(height: 6),
              _field(_categoryCustomCtrl, 'Catégorie (autre)', 'ex. Surgelés', onChanged: (_) => setState(() {})),
            ],
            const SizedBox(height: 10),
            _field(_brandCtrl, 'Marque', 'ex. Coke ou Pomme', onChanged: (_) => setState(() {})),
            const SizedBox(height: 10),
            _field(_subBrandCtrl, 'Sous-marque', 'ex. Zero (laisser vide si pas de sous-marque)', onChanged: (_) => setState(() {})),
            const SizedBox(height: 12),
            // Volume (tags) — Unité = one item (apple, onion, etc.)
            _tagSection('Volume', _volumes, _volume, (v) => setState(() => _volume = v)),
            if (_volume == 'Autre') ...[
              const SizedBox(height: 6),
              _field(_volumeCustomCtrl, 'Volume (autre)', 'ex. 400ml', onChanged: (_) => setState(() {})),
            ],
            const SizedBox(height: 12),
            // Matériau (tags) — PRODUCE / UNPACKAGED pour produits sans emballage (pomme, oignon…)
            _tagSection('Matériau', _materials, _material, (m) => setState(() => _material = m)),
            if (_material == 'Autre') ...[
              const SizedBox(height: 6),
              _field(_materialCustomCtrl, 'Matériau (autre)', 'ex. Métal', onChanged: (_) => setState(() {})),
            ],
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _saving
                    ? null
                    : () async {
                        if (_brandCtrl.text.trim().isEmpty) return;
                        if (_volumeValue.isEmpty || _materialValue.isEmpty) return;
                        setState(() => _saving = true);
                        final category = _categoryValue.isEmpty
                            ? 'Non catégorisé'
                            : _categoryValue;
                        final brand = normalizeVariantName(_brandCtrl.text);
                        final subBrand = normalizeVariantName(_subBrandCtrl.text);
                        final appState = context.read<AppState>();
                        appState.duplicateOfFullLabel = null;
                        await appState.addVariant(
                              Variant(
                                category: category,
                                brand: brand,
                                subBrand: subBrand,
                        volume: _volumeValue,
                        material: _materialValue,
                              ),
                            );
                        if (!mounted) return;
                        setState(() => _saving = false);
                        final dup = appState.duplicateOfFullLabel;
                        if (dup != null) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                'Très similaire à : $dup\nUtilisez un autre nom ou synchronisez.',
                                style: const TextStyle(color: ZCTheme.textPrimary),
                              ),
                              backgroundColor: ZCTheme.gold,
                              duration: const Duration(seconds: 4),
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                          return;
                        }
                        Navigator.pop(context);
                      },
                child: _saving
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: ZCTheme.bg))
                    : const Text('Enregistrer la variante'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tagSection(String label, List<String> options, String selected, ValueChanged<String> onSelected) {
    const twoRowHeight = 72.0;
    const chipSpacing = 8.0;
    const chipRunSpacing = 6.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(
                color: ZCTheme.textSecondary,
                fontSize: 11,
                letterSpacing: 0.5)),
        const SizedBox(height: 6),
        SizedBox(
          height: twoRowHeight,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minWidth: MediaQuery.of(context).size.width * 1.2,
                minHeight: twoRowHeight,
              ),
              child: Wrap(
                spacing: chipSpacing,
                runSpacing: chipRunSpacing,
                children: options.map((o) {
                  final sel = o == selected;
                  return ChoiceChip(
                    label: Text(o,
                        style: TextStyle(
                            color: sel ? ZCTheme.bg : ZCTheme.textSecondary,
                            fontSize: 11)),
                    selected: sel,
                    selectedColor: ZCTheme.accent,
                    backgroundColor: ZCTheme.surfaceAlt,
                    side: BorderSide(
                        color: sel ? ZCTheme.accent : ZCTheme.border),
                    onSelected: (_) => onSelected(o),
                  );
                }).toList(),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _field(TextEditingController ctrl, String label, String hint,
      {ValueChanged<String>? onChanged}) {
    return TextField(
      controller: ctrl,
      onChanged: onChanged,
      style: const TextStyle(color: ZCTheme.textPrimary),
      decoration: InputDecoration(labelText: label, hintText: hint),
    );
  }
}
