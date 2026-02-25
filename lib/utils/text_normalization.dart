// ─────────────────────────────────────────────
//  ZERO-CLEAN  ·  Text normalization for variant labels
//  Accent folding (French etc.) + consistent casing/underscores for training.
// ─────────────────────────────────────────────

/// Replaces common accented characters with ASCII equivalents (French and Latin).
String normalizeAccents(String s) {
  const accents = {
    'à': 'a', 'á': 'a', 'â': 'a', 'ã': 'a', 'ä': 'a', 'å': 'a', 'æ': 'ae',
    'ç': 'c',
    'è': 'e', 'é': 'e', 'ê': 'e', 'ë': 'e',
    'ì': 'i', 'í': 'i', 'î': 'i', 'ï': 'i',
    'ñ': 'n',
    'ò': 'o', 'ó': 'o', 'ô': 'o', 'õ': 'o', 'ö': 'o', 'ø': 'o',
    'ù': 'u', 'ú': 'u', 'û': 'u', 'ü': 'u',
    'ý': 'y', 'ÿ': 'y',
    'œ': 'oe', 'ß': 'ss',
  };
  String r = s.toLowerCase();
  for (final e in accents.entries) {
    r = r.replaceAll(e.key, e.value);
  }
  return r;
}

/// Title case: first letter of each word uppercase, rest lowercase.
String titleCase(String s) {
  final t = s.trim();
  if (t.isEmpty) return t;
  return t.split(RegExp(r'\s+')).map((w) {
    if (w.isEmpty) return w;
    return w[0].toUpperCase() + w.substring(1).toLowerCase();
  }).join(' ');
}

/// Normalizes marque/sous-marque for storage: trim → accent fold → title case → spaces to underscore.
String normalizeVariantName(String s) {
  final t = s.trim();
  if (t.isEmpty) return t;
  final noAccent = normalizeAccents(t);
  final titled = titleCase(noAccent);
  return titled.replaceAll(' ', '_');
}

/// Normalizes category (e.g. when "Autre"): same as variant name.
String normalizeCategory(String s) {
  return normalizeVariantName(s);
}

/// Collapses multiple underscores to one (e.g. Coke__500ml → Coke_500ml).
String collapseUnderscores(String s) {
  return s.replaceAll(RegExp(r'_+'), '_');
}
