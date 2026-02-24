// ─────────────────────────────────────────────
//  ZERO-CLEAN  ·  Setup Screen
// ─────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import '../widgets/widgets.dart';
import '../theme.dart';
import '../models/models.dart';

/// First letter of every word capital, rest lowercase (e.g. "fruits" → "Fruits").
String _titleCase(String s) {
  final t = s.trim();
  if (t.isEmpty) return t;
  return t.split(RegExp(r'\s+')).map((w) {
    if (w.isEmpty) return w;
    return w[0].toUpperCase() + w.substring(1).toLowerCase();
  }).join(' ');
}

class SetupScreen extends StatelessWidget {
  const SetupScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('CONFIG')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: const [
          SectionHeader(title: 'Magasins'),
          _ShopList(),
          SizedBox(height: 20),
          SectionHeader(title: 'Variantes de produits'),
          _VariantList(),
        ],
      ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FloatingActionButton.extended(
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
          const SizedBox(height: 10),
          FloatingActionButton.extended(
            heroTag: 'add_shop',
            onPressed: () => showModalBottomSheet(
              context: context,
              isScrollControlled: true,
              backgroundColor: ZCTheme.surface,
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              builder: (_) => const _AddShopSheet(),
            ),
            icon: const Icon(Icons.add_business_outlined, color: ZCTheme.bg),
            label: const Text('Ajouter un magasin',
                style: TextStyle(color: ZCTheme.bg, fontWeight: FontWeight.w700)),
            backgroundColor: ZCTheme.accentDim,
          ),
        ],
      ),
    );
  }
}

class _ShopList extends StatelessWidget {
  const _ShopList();

  @override
  Widget build(BuildContext context) {
    final shops = context.watch<AppState>().shops;
    if (shops.isEmpty) {
      return const EmptyState(message: 'Aucun magasin. Ajoutez votre premier magasin.');
    }
    return Column(
      children: shops
          .map((s) => Card(
                child: ListTile(
                  leading:
                      const Icon(Icons.store_outlined, color: ZCTheme.accent),
                  title: Text(s.name,
                      style: const TextStyle(color: ZCTheme.textPrimary)),
                  subtitle: s.locationNote.isNotEmpty
                      ? Text(s.locationNote,
                          style: const TextStyle(color: ZCTheme.textMuted))
                      : null,
                ),
              ))
          .toList(),
    );
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

// ── Add Shop Sheet ─────────────────────────────

class _AddShopSheet extends StatefulWidget {
  const _AddShopSheet();

  @override
  State<_AddShopSheet> createState() => _AddShopSheetState();
}

class _AddShopSheetState extends State<_AddShopSheet> {
  final _nameCtrl = TextEditingController();
  final _locationCtrl = TextEditingController();
  bool _saving = false;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Ajouter un magasin',
              style: TextStyle(
                  color: ZCTheme.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w800)),
          const SizedBox(height: 20),
          TextField(
            controller: _nameCtrl,
            style: const TextStyle(color: ZCTheme.textPrimary),
            decoration: const InputDecoration(
              labelText: 'Nom du magasin',
              hintText: 'ex. Boutique_Moussa',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _locationCtrl,
            style: const TextStyle(color: ZCTheme.textPrimary),
            decoration: const InputDecoration(
              labelText: 'Note d\'emplacement',
              hintText: 'ex. Dakar Centre',
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _saving
                  ? null
                  : () async {
                      if (_nameCtrl.text.trim().isEmpty) return;
                      setState(() => _saving = true);
                      await context.read<AppState>().addShop(
                            _nameCtrl.text
                                .trim()
                                .replaceAll(' ', '_'),
                            _locationCtrl.text.trim(),
                          );
                      if (mounted) Navigator.pop(context);
                    },
              child: _saving
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: ZCTheme.bg))
                  : const Text('Enregistrer le magasin'),
            ),
          ),
        ],
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
      _category == 'Autre' ? _titleCase(_categoryCustomCtrl.text.trim()) : _category;
  String get _volumeValue =>
      _volume == 'Autre' ? _volumeCustomCtrl.text.trim() : _volume;
  String get _materialValue =>
      _material == 'Autre' ? _materialCustomCtrl.text.trim() : _material;

  @override
  Widget build(BuildContext context) {
    final preview = '${_brandCtrl.text}_${_subBrandCtrl.text}_${_volumeValue}_${_materialValue}'
        .replaceAll(' ', '_');

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
                        final brand = _titleCase(_brandCtrl.text.trim()).replaceAll(' ', '_');
                        final subBrand = _titleCase(_subBrandCtrl.text.trim()).replaceAll(' ', '_');
                        await context.read<AppState>().addVariant(
                              Variant(
                                category: category,
                                brand: brand,
                                subBrand: subBrand,
                                volume: _volumeValue.replaceAll(' ', '_'),
                                material: _materialValue.replaceAll(' ', '_'),
                              ),
                            );
                        if (mounted) Navigator.pop(context);
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
