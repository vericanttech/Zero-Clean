// ─────────────────────────────────────────────
//  ZERO-CLEAN  ·  User-friendly sync error messages
// ─────────────────────────────────────────────

import 'dart:async';
import 'dart:io';

/// Returns a short, user-friendly message for sync/network errors (e.g. connectivity loss mid-sync).
String userFriendlySyncError(Object error) {
  final msg = error.toString().toLowerCase();
  if (error is SocketException) {
    return 'Connexion impossible. Vérifiez votre réseau et réessayez.';
  }
  if (error is TimeoutException) {
    return 'Délai dépassé. Vérifiez votre connexion et réessayez.';
  }
  if (msg.contains('socket') ||
      msg.contains('connection') ||
      msg.contains('network') ||
      msg.contains('unavailable') ||
      msg.contains('failed to host lookup') ||
      msg.contains('connection refused') ||
      msg.contains('connection reset')) {
    return 'Problème de connexion. Vérifiez votre réseau et réessayez.';
  }
  if (msg.contains('timeout') || msg.contains('timed out')) {
    return 'Délai dépassé. Vérifiez votre connexion et réessayez.';
  }
  // Fallback: keep original but truncate if very long
  final raw = error.toString();
  if (raw.length > 80) return '${raw.substring(0, 77)}…';
  return raw;
}
