// ─────────────────────────────────────────────
//  ZERO-CLEAN  ·  Firebase Storage Service
//  Upload processed images only. Path: datasets/{userId}/{shopId}/{imageId}
//  (ID-based; labels live in Firestore metadata, not path.)
// ─────────────────────────────────────────────

import 'dart:io';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';

class FirebaseStorageService {
  static final FirebaseStorageService instance = FirebaseStorageService._internal();
  FirebaseStorageService._internal();

  final _storage = FirebaseStorage.instance;

  String? get _userId => FirebaseAuth.instance.currentUser?.uid;

  /// Uploads image file to Storage. Returns the full storage path (for Firestore image doc).
  /// Path: datasets/{userId}/{shopId}/{imageId} (e.g. datasets/U12/S4/IMG_123.jpg)
  Future<String> uploadProcessedImage({
    required File imageFile,
    required String userId,
    required String shopId,
    required String imageId,
  }) async {
    final path = 'datasets/$userId/$shopId/$imageId';
    final ref = _storage.ref().child(path);
    await ref.putFile(imageFile, SettableMetadata(contentType: 'image/jpeg'));
    return path;
  }
}
