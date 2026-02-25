// ─────────────────────────────────────────────
//  ZERO-CLEAN  ·  Firestore Service (remote DB)
//  Single shop per user; shops, variants, progress, images.
// ─────────────────────────────────────────────

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/models.dart';

class FirestoreService {
  static final FirestoreService instance = FirestoreService._internal();
  FirestoreService._internal();

  final _db = FirebaseFirestore.instance;

  static const String _shops = 'shops';
  static const String _progress = 'progress';
  static const String _images = 'images';
  static const String _stats = 'stats';

  String? get _userId => FirebaseAuth.instance.currentUser?.uid;
  bool get _signedIn => _userId != null;

  // ── Shops (one per user; created on first login with name = UID if none exists) ───────────

  /// Shops for the current user (userId == auth.uid).
  Future<List<Shop>> getShops() async {
    if (!_signedIn) return [];
    final uid = _userId!;
    final snap = await _db.collection(_shops).where('userId', isEqualTo: uid).get();
    return snap.docs.map((d) => Shop.fromMap({...d.data(), 'id': d.id})).toList();
  }

  /// If the current user has no shop, create one with name = UID and return it. Otherwise return existing. Use on login so every user always has a shop.
  Future<Shop?> ensureShopForCurrentUser() async {
    if (!_signedIn) return null;
    final uid = _userId!;
    return getOrCreateUserShop(name: uid);
  }

  /// Only for admin / backend: create a shop.
  Future<Shop?> getOrCreateUserShop({required String name, String locationNote = '', double? latitude, double? longitude}) async {
    if (!_signedIn) return null;
    final uid = _userId!;
    final existing = await _db.collection(_shops).where('userId', isEqualTo: uid).limit(1).get();
    if (existing.docs.isNotEmpty) {
      final d = existing.docs.first;
      return Shop.fromMap({...d.data(), 'id': d.id});
    }
    final ref = await _db.collection(_shops).add({
      'name': name,
      'location_note': locationNote,
      'userId': uid,
      if (latitude != null) 'latitude': latitude,
      if (longitude != null) 'longitude': longitude,
      'createdAt': FieldValue.serverTimestamp(),
    });
    return Shop(
      id: ref.id,
      name: name,
      locationNote: locationNote,
      latitude: latitude,
      longitude: longitude,
    );
  }

  Future<String> insertShop(Shop shop) async {
    if (!_signedIn) throw StateError('Not signed in');
    final uid = _userId!;
    final ref = await _db.collection(_shops).add({
      'name': shop.name,
      'location_note': shop.locationNote,
      'userId': uid,
      if (shop.latitude != null) 'latitude': shop.latitude,
      if (shop.longitude != null) 'longitude': shop.longitude,
      'createdAt': FieldValue.serverTimestamp(),
    });
    return ref.id;
  }

  /// Update current user's shop with optional name, location_note, GPS. Only provided fields are updated.
  Future<void> updateShop(String shopId, {String? name, String? locationNote, double? latitude, double? longitude}) async {
    if (!_signedIn || shopId.isEmpty) return;
    final ref = _db.collection(_shops).doc(shopId);
    final Map<String, dynamic> updates = {};
    if (name != null) updates['name'] = name;
    if (locationNote != null) updates['location_note'] = locationNote;
    if (latitude != null) updates['latitude'] = latitude;
    if (longitude != null) updates['longitude'] = longitude;
    if (updates.isEmpty) return;
    await ref.update(updates);
  }

  // ── Variants (per-shop subcollection: shops/{shopId}/variants) ───

  /// Variants for this shop only. Enables per-shop normalization later.
  Future<List<Variant>> getVariants(String shopId) async {
    if (!_signedIn || shopId.isEmpty) return [];
    final snap = await _db
        .collection(_shops)
        .doc(shopId)
        .collection('variants')
        .orderBy('brand')
        .get();
    return snap.docs.map((d) => Variant.fromMap({...d.data(), 'id': d.id})).toList();
  }

  Future<List<Variant>> getVariantsByCategory(String shopId, String category) async {
    if (!_signedIn || shopId.isEmpty) return [];
    final snap = await _db
        .collection(_shops)
        .doc(shopId)
        .collection('variants')
        .where('category', isEqualTo: category)
        .orderBy('brand')
        .get();
    return snap.docs.map((d) => Variant.fromMap({...d.data(), 'id': d.id})).toList();
  }

  Future<List<String>> getCategories(String shopId) async {
    if (!_signedIn || shopId.isEmpty) return [];
    final snap = await _db
        .collection(_shops)
        .doc(shopId)
        .collection('variants')
        .get();
    final set = <String>{};
    for (final d in snap.docs) {
      final c = d.data()['category'] as String?;
      if (c != null && c.isNotEmpty) set.add(c);
    }
    return set.toList()..sort();
  }

  /// Add a variant with a specific doc id (e.g. local_xxx for offline-created). Use this when pushing pending so id stays consistent.
  Future<void> setVariantWithId(String shopId, String variantId, Variant variant) async {
    if (!_signedIn || shopId.isEmpty) throw StateError('Not signed in or no shop');
    await _db
        .collection(_shops)
        .doc(shopId)
        .collection('variants')
        .doc(variantId)
        .set({
      'category': variant.category,
      'brand': variant.brand,
      'sub_brand': variant.subBrand,
      'volume': variant.volume,
      'material': variant.material,
    });
  }

  /// Add a variant to the shop's catalog. Variant is tied to this shop. Returns new doc id.
  Future<String> insertVariant(String shopId, Variant variant) async {
    if (!_signedIn || shopId.isEmpty) throw StateError('Not signed in or no shop');
    final ref = await _db
        .collection(_shops)
        .doc(shopId)
        .collection('variants')
        .add({
      'category': variant.category,
      'brand': variant.brand,
      'sub_brand': variant.subBrand,
      'volume': variant.volume,
      'material': variant.material,
    });
    return ref.id;
  }

  // ── Progress ───────────────────────────────

  Future<List<Progress>> getProgressForShop(String shopId) async {
    final snap = await _db.collection(_progress).where('shop_id', isEqualTo: shopId).get();
    return snap.docs.map((d) => Progress.fromMap({...d.data(), 'id': d.id})).toList();
  }

  Future<Progress?> getProgress(String variantId, String shopId, CaptureContext ctx) async {
    final snap = await _db
        .collection(_progress)
        .where('variant_id', isEqualTo: variantId)
        .where('shop_id', isEqualTo: shopId)
        .where('context', isEqualTo: ctx.name)
        .limit(1)
        .get();
    if (snap.docs.isEmpty) return null;
    final d = snap.docs.first;
    return Progress.fromMap({...d.data(), 'id': d.id});
  }

  Future<void> incrementCount(String variantId, String shopId, CaptureContext ctx) async {
    final now = FieldValue.serverTimestamp();
    final snap = await _db
        .collection(_progress)
        .where('variant_id', isEqualTo: variantId)
        .where('shop_id', isEqualTo: shopId)
        .where('context', isEqualTo: ctx.name)
        .limit(1)
        .get();
    if (snap.docs.isEmpty) {
      await _db.collection(_progress).add({
        'variant_id': variantId,
        'shop_id': shopId,
        'context': ctx.name,
        'current_count': 1,
        'target_cap': ctx.targetCap,
        'last_updated_at': now,
      });
    } else {
      await snap.docs.first.reference.update({
        'current_count': FieldValue.increment(1),
        'last_updated_at': now,
      });
    }
  }

  Future<void> ensureProgressRow(String variantId, String shopId, CaptureContext ctx) async {
    final snap = await _db
        .collection(_progress)
        .where('variant_id', isEqualTo: variantId)
        .where('shop_id', isEqualTo: shopId)
        .where('context', isEqualTo: ctx.name)
        .limit(1)
        .get();
    if (snap.docs.isEmpty) {
      await _db.collection(_progress).add({
        'variant_id': variantId,
        'shop_id': shopId,
        'context': ctx.name,
        'current_count': 0,
        'target_cap': ctx.targetCap,
        'last_updated_at': FieldValue.serverTimestamp(),
      });
    }
  }

  Future<Map<String, int>> getTotalStats() async {
    if (!_signedIn) return {'total_images': 0, 'total_variants': 0};
    final userShops = await getShops();
    final shopIds = userShops.map((s) => s.id).whereType<String>().toList();
    if (shopIds.isEmpty) return {'total_images': 0, 'total_variants': 0};
    int totalImages = 0;
    int totalVariants = 0;
    for (final shopId in shopIds) {
      final progressSnap = await _db.collection(_progress).where('shop_id', isEqualTo: shopId).get();
      for (final d in progressSnap.docs) {
        totalImages += (d.data()['current_count'] as num?)?.toInt() ?? 0;
      }
      final variantsSnap = await _db.collection(_shops).doc(shopId).collection('variants').get();
      totalVariants += variantsSnap.docs.length;
    }
    return {'total_images': totalImages, 'total_variants': totalVariants};
  }

  // ── Images (metadata doc per processed image) ──

  Future<void> addImageDoc({
    required String imageId,
    required String storagePath,
    required String userId,
    required String shopId,
    required String variantId,
    required String context,
    required Map<String, dynamic> fullMetadata,
  }) async {
    final now = FieldValue.serverTimestamp();
    await _db.collection(_images).doc(imageId).set({
      'storage_path': storagePath,
      'user_id': userId,
      'shop_id': shopId,
      'variant_id': variantId,
      'context': context,
      'created_at': now,
      'processed_at': now,
      ...fullMetadata,
    });
  }

  // ── Stats (optional: one doc per shop for dashboard) ──

  Future<void> incrementStatsTotal(String shopId) async {
    final ref = _db.collection(_stats).doc(shopId);
    await _db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      if (snap.exists) {
        tx.update(ref, {
          'total_images': FieldValue.increment(1),
          'last_updated_at': FieldValue.serverTimestamp(),
        });
      } else {
        tx.set(ref, {
          'total_images': 1,
          'last_updated_at': FieldValue.serverTimestamp(),
        });
      }
    });
  }
}
