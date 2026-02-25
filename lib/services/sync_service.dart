// ─────────────────────────────────────────────
//  ZERO-CLEAN  ·  Sync Service
//  Pull: Firestore → SQLite. Push: flush pending_sync to Firestore when online.
//  Firebase SDK does not sync SQLite; we do one-way pull and queued push.
// ─────────────────────────────────────────────

import 'dart:io';
import 'package:flutter/foundation.dart';
import '../models/models.dart';
import 'firebase_storage_service.dart';
import 'firestore_service.dart';
import 'local_db_service.dart';

class SyncService {
  static final SyncService instance = SyncService._internal();
  SyncService._internal();

  final _fs = FirestoreService.instance;
  final _local = LocalDbService.instance;
  final _storage = FirebaseStorageService.instance;

  /// Pull from Firestore into SQLite, then push any pending local changes to Firestore.
  /// Call when online (e.g. manual "Sync" or after login). Safe to call when offline — Firestore calls will fail and we catch.
  Future<void> syncFromRemote() async {
    try {
      await _pullFromFirestore();
      await _pushPendingToFirestore();
    } catch (e, st) {
      if (kDebugMode) {
        print('SyncService.syncFromRemote error: $e');
        print(st);
      }
      rethrow;
    }
  }

  /// Firestore → SQLite. Fetches all then replaces local in one transaction (avoids partial pull).
  Future<void> _pullFromFirestore() async {
    final shops = await _fs.getShops();
    final variantsByShop = <String, List<Variant>>{};
    final progressByShop = <String, List<Progress>>{};
    for (final shop in shops) {
      final id = shop.id;
      if (id == null) continue;
      variantsByShop[id] = await _fs.getVariants(id);
      progressByShop[id] = await _fs.getProgressForShop(id);
    }
    await _local.saveAllFromRemote(shops, variantsByShop, progressByShop);
  }

  /// Process pending_sync queue: push each to Firestore, remove on success.
  Future<void> _pushPendingToFirestore() async {
    final pending = await _local.getPendingSync();
    for (final item in pending) {
      try {
        await _applyPending(item);
        await _local.removePendingSync(item['id'] as int);
      } catch (e) {
        if (kDebugMode) print('Push pending ${item['kind']} failed: $e');
        // Leave in queue for next sync
      }
    }
  }

  Future<void> _applyPending(Map<String, dynamic> item) async {
    final kind = item['kind'] as String?;
    final payload = item['payload'] as Map<String, dynamic>? ?? {};
    switch (kind) {
      case 'variant':
        final shopId = payload['shop_id'] as String?;
        final localId = payload['local_id'] as String?;
        if (shopId == null || localId == null) return;
        final v = Variant.fromMap(payload['variant'] as Map<String, dynamic>? ?? {});
        await _fs.setVariantWithId(shopId, localId, v);
        for (final ctx in CaptureContext.values) {
          await _fs.ensureProgressRow(localId, shopId, ctx);
          await _local.ensureProgressRow(localId, shopId, ctx);
        }
        break;
      case 'shop_profile':
        final shopId = payload['shop_id'] as String?;
        if (shopId == null) return;
        await _fs.updateShop(
          shopId,
          name: payload['name'] as String?,
          locationNote: payload['location_note'] as String?,
          latitude: (payload['latitude'] as num?)?.toDouble(),
          longitude: (payload['longitude'] as num?)?.toDouble(),
        );
        break;
      case 'processed_image':
        final refImagePath = payload['ref_image_path'] as String?;
        final shopId = payload['shop_id'] as String?;
        final userId = payload['user_id'] as String?;
        final contextStr = payload['context'] as String?;
        final fullMetadata = payload['full_metadata'] as Map<String, dynamic>?;
        final variantIds = (payload['variant_ids'] as List?)?.cast<String>() ?? [];
        final baseName = payload['base_name'] as String? ?? '';
        final imageId = payload['image_id'] as String? ?? '';
        final firstVariantId = payload['first_variant_id'] as String? ?? '';
        if (refImagePath == null || shopId == null || userId == null || contextStr == null || fullMetadata == null) return;
        final ctx = CaptureContext.values.firstWhere(
          (c) => c.name == contextStr,
          orElse: () => CaptureContext.single,
        );
        final imageFile = File(refImagePath);
        if (!await imageFile.exists()) {
          if (kDebugMode) print('Processed image file missing: $refImagePath');
          return;
        }
        final storagePath = await _storage.uploadProcessedImage(
          imageFile: imageFile,
          userId: userId,
          shopId: shopId,
          imageId: imageId,
        );
        await _fs.addImageDoc(
          imageId: baseName,
          storagePath: storagePath,
          userId: userId,
          shopId: shopId,
          variantId: firstVariantId,
          context: contextStr,
          fullMetadata: fullMetadata,
        );
        for (final variantId in variantIds) {
          await _fs.ensureProgressRow(variantId, shopId, ctx);
          await _fs.incrementCount(variantId, shopId, ctx);
        }
        await _fs.incrementStatsTotal(shopId);
        break;
      default:
        if (kDebugMode) print('Unknown pending kind: $kind');
    }
  }

  /// Queue a shop profile update for later push (Sync).
  Future<void> queueShopProfile(String shopId, {String? name, String? locationNote, double? latitude, double? longitude}) async {
    await _local.addPendingSync('shop_profile', {
      'shop_id': shopId,
      if (name != null) 'name': name,
      if (locationNote != null) 'location_note': locationNote,
      if (latitude != null) 'latitude': latitude,
      if (longitude != null) 'longitude': longitude,
    });
  }

  /// Queue a variant add for later push (when offline).
  Future<void> queueVariant(String shopId, Variant variant, String localId) async {
    await _local.addPendingSync('variant', {
      'shop_id': shopId,
      'local_id': localId,
      'variant': variant.toMap(),
    });
  }

  /// Queue a processed image for later upload + Firestore (when user saves on nudge screen). Applied when user taps Sync.
  Future<void> queueProcessedImage(Map<String, dynamic> payload) async {
    await _local.addPendingSync('processed_image', payload);
  }

  /// Pull from Firestore into SQLite only (no push). Use when user has no local data and taps "Récupérer".
  Future<void> pullFromRemote() async {
    try {
      await _pullFromFirestore();
    } catch (e, st) {
      if (kDebugMode) {
        print('SyncService.pullFromRemote error: $e');
        print(st);
      }
      rethrow;
    }
  }

  /// Push pending_sync queue to Firestore only (no pull). Use when user taps "Synchroniser".
  Future<void> pushPendingOnly() async {
    await _pushPendingToFirestore();
  }
}
