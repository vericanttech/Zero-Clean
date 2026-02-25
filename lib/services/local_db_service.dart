// ─────────────────────────────────────────────
//  ZERO-CLEAN  ·  Local DB Service (SQLite)
//  Primary read source for catalog + progress. Syncs with Firestore when online.
// ─────────────────────────────────────────────

import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../models/models.dart';

class LocalDbService {
  static final LocalDbService instance = LocalDbService._internal();
  LocalDbService._internal();

  static const int _version = 1;
  Database? _db;

  Future<Database> get _database async {
    if (_db != null && _db!.isOpen) return _db!;
    final dir = await getApplicationDocumentsDirectory();
    final path = p.join(dir.path, 'zero_clean_local.db');
    _db = await openDatabase(
      path,
      version: _version,
      onCreate: _onCreate,
    );
    return _db!;
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE shops (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        location_note TEXT,
        latitude REAL,
        longitude REAL
      )
    ''');
    await db.execute('''
      CREATE TABLE variants (
        id TEXT PRIMARY KEY,
        shop_id TEXT NOT NULL,
        category TEXT NOT NULL,
        brand TEXT NOT NULL,
        sub_brand TEXT NOT NULL,
        volume TEXT NOT NULL,
        material TEXT NOT NULL,
        FOREIGN KEY (shop_id) REFERENCES shops (id)
      )
    ''');
    await db.execute('CREATE INDEX idx_variants_shop ON variants(shop_id)');
    await db.execute('''
      CREATE TABLE progress (
        variant_id TEXT NOT NULL,
        shop_id TEXT NOT NULL,
        context TEXT NOT NULL,
        current_count INTEGER NOT NULL DEFAULT 0,
        target_cap INTEGER NOT NULL,
        last_updated_at TEXT,
        PRIMARY KEY (variant_id, shop_id, context)
      )
    ''');
    await db.execute('CREATE INDEX idx_progress_shop ON progress(shop_id)');
    await db.execute('''
      CREATE TABLE pending_sync (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        kind TEXT NOT NULL,
        payload TEXT NOT NULL,
        created_at TEXT NOT NULL
      )
    ''');
  }

  /// Clear all data for this user (e.g. on sign out). Call after clearing by user.
  Future<void> clearAll() async {
    final db = await _database;
    await db.delete('pending_sync');
    await db.delete('progress');
    await db.delete('variants');
    await db.delete('shops');
  }

  // ── Shops ───────────────────────────────────

  /// Atomic replace: pull all from Firestore then replace local in one transaction. Avoids partial state.
  Future<void> saveAllFromRemote(
    List<Shop> shops,
    Map<String, List<Variant>> variantsByShop,
    Map<String, List<Progress>> progressByShop,
  ) async {
    final db = await _database;
    await db.transaction((tx) async {
      await tx.delete('progress');
      await tx.delete('variants');
      await tx.delete('shops');
      for (final s in shops) {
        if (s.id == null) continue;
        await tx.insert('shops', {
          'id': s.id!,
          'name': s.name,
          'location_note': s.locationNote,
          'latitude': s.latitude,
          'longitude': s.longitude,
        });
      }
      for (final entry in variantsByShop.entries) {
        final shopId = entry.key;
        for (final v in entry.value) {
          if (v.id == null) continue;
          await tx.insert('variants', {
            'id': v.id!,
            'shop_id': shopId,
            'category': v.category,
            'brand': v.brand,
            'sub_brand': v.subBrand,
            'volume': v.volume,
            'material': v.material,
          });
        }
      }
      for (final entry in progressByShop.entries) {
        for (final p in entry.value) {
          await tx.insert('progress', {
            'variant_id': p.variantId,
            'shop_id': p.shopId,
            'context': p.context.name,
            'current_count': p.currentCount,
            'target_cap': p.targetCap,
            'last_updated_at': p.lastUpdatedAt?.toIso8601String(),
          });
        }
      }
    });
  }

  Future<void> saveShops(List<Shop> shops) async {
    final db = await _database;
    await db.delete('shops');
    for (final s in shops) {
      await db.insert('shops', {
        'id': s.id!,
        'name': s.name,
        'location_note': s.locationNote,
        'latitude': s.latitude,
        'longitude': s.longitude,
      });
    }
  }

  Future<List<Shop>> getShops() async {
    final db = await _database;
    final rows = await db.query('shops');
    return rows.map((r) => Shop.fromMap({
      'id': r['id'],
      'name': r['name'],
      'location_note': r['location_note'],
      'latitude': r['latitude'],
      'longitude': r['longitude'],
    })).toList();
  }

  Future<void> insertShop(Shop shop) async {
    if (shop.id == null) return;
    final db = await _database;
    await db.insert('shops', {
      'id': shop.id!,
      'name': shop.name,
      'location_note': shop.locationNote,
      'latitude': shop.latitude,
      'longitude': shop.longitude,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// Update shop by id. Replaces row so pass full shop with updated fields.
  Future<void> updateShop(Shop shop) async {
    if (shop.id == null) return;
    final db = await _database;
    await db.insert('shops', {
      'id': shop.id!,
      'name': shop.name,
      'location_note': shop.locationNote,
      'latitude': shop.latitude,
      'longitude': shop.longitude,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  // ── Variants ─────────────────────────────────

  Future<void> saveVariants(String shopId, List<Variant> variants) async {
    final db = await _database;
    await db.delete('variants', where: 'shop_id = ?', whereArgs: [shopId]);
    for (final v in variants) {
      if (v.id == null) continue;
      await db.insert('variants', {
        'id': v.id!,
        'shop_id': shopId,
        'category': v.category,
        'brand': v.brand,
        'sub_brand': v.subBrand,
        'volume': v.volume,
        'material': v.material,
      });
    }
  }

  Future<List<Variant>> getVariants(String shopId) async {
    final db = await _database;
    final rows = await db.query(
      'variants',
      where: 'shop_id = ?',
      whereArgs: [shopId],
      orderBy: 'brand',
    );
    return rows.map((r) => Variant.fromMap({
      'id': r['id'],
      'category': r['category'],
      'brand': r['brand'],
      'sub_brand': r['sub_brand'],
      'volume': r['volume'],
      'material': r['material'],
    })).toList();
  }

  Future<List<String>> getCategories(String shopId) async {
    final db = await _database;
    final rows = await db.query(
      'variants',
      columns: ['category'],
      where: 'shop_id = ?',
      whereArgs: [shopId],
    );
    final set = <String>{};
    for (final r in rows) {
      final c = r['category'] as String?;
      if (c != null && c.isNotEmpty) set.add(c);
    }
    return set.toList()..sort();
  }

  /// Insert one variant; returns id. Use Firestore doc id when synced, or a local id when offline.
  Future<String> insertVariant(String shopId, Variant variant) async {
    final db = await _database;
    final id = variant.id ?? 'local_${DateTime.now().millisecondsSinceEpoch}';
    await db.insert('variants', {
      'id': id,
      'shop_id': shopId,
      'category': variant.category,
      'brand': variant.brand,
      'sub_brand': variant.subBrand,
      'volume': variant.volume,
      'material': variant.material,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    return id;
  }

  /// Replace variant id (e.g. after offline create was pushed and got Firestore id).
  Future<void> replaceVariantId(String shopId, String oldId, String newId) async {
    final db = await _database;
    await db.update(
      'variants',
      {'id': newId},
      where: 'shop_id = ? AND id = ?',
      whereArgs: [shopId, oldId],
    );
    await db.update(
      'progress',
      {'variant_id': newId},
      where: 'shop_id = ? AND variant_id = ?',
      whereArgs: [shopId, oldId],
    );
  }

  // ── Progress ─────────────────────────────────

  Future<void> saveProgress(String shopId, List<Progress> list) async {
    final db = await _database;
    await db.delete('progress', where: 'shop_id = ?', whereArgs: [shopId]);
    for (final p in list) {
      await db.insert('progress', {
        'variant_id': p.variantId,
        'shop_id': p.shopId,
        'context': p.context.name,
        'current_count': p.currentCount,
        'target_cap': p.targetCap,
        'last_updated_at': p.lastUpdatedAt?.toIso8601String(),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
  }

  Future<List<Progress>> getProgressForShop(String shopId) async {
    final db = await _database;
    final rows = await db.query(
      'progress',
      where: 'shop_id = ?',
      whereArgs: [shopId],
    );
    return rows.map((r) => Progress.fromMap({
      'variant_id': r['variant_id'],
      'shop_id': r['shop_id'],
      'context': r['context'],
      'current_count': r['current_count'],
      'target_cap': r['target_cap'],
      'last_updated_at': r['last_updated_at'],
    })).toList();
  }

  Future<void> ensureProgressRow(String variantId, String shopId, CaptureContext ctx) async {
    final db = await _database;
    final existing = await db.query(
      'progress',
      where: 'variant_id = ? AND shop_id = ? AND context = ?',
      whereArgs: [variantId, shopId, ctx.name],
    );
    if (existing.isEmpty) {
      await db.insert('progress', {
        'variant_id': variantId,
        'shop_id': shopId,
        'context': ctx.name,
        'current_count': 0,
        'target_cap': ctx.targetCap,
        'last_updated_at': DateTime.now().toIso8601String(),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
  }

  Future<void> incrementProgressCount(String variantId, String shopId, CaptureContext ctx) async {
    final db = await _database;
    await ensureProgressRow(variantId, shopId, ctx);
    final rows = await db.query(
      'progress',
      where: 'variant_id = ? AND shop_id = ? AND context = ?',
      whereArgs: [variantId, shopId, ctx.name],
    );
    if (rows.isNotEmpty) {
      final count = (rows.first['current_count'] as int? ?? 0) + 1;
      await db.update(
        'progress',
        {
          'current_count': count,
          'last_updated_at': DateTime.now().toIso8601String(),
        },
        where: 'variant_id = ? AND shop_id = ? AND context = ?',
        whereArgs: [variantId, shopId, ctx.name],
      );
    }
  }

  Future<Map<String, int>> getTotalStats() async {
    final db = await _database;
    final shops = await getShops();
    final shopIds = shops.map((s) => s.id).whereType<String>().toList();
    if (shopIds.isEmpty) return {'total_images': 0, 'total_variants': 0};
    int totalImages = 0;
    int totalVariants = 0;
    for (final shopId in shopIds) {
      final progRows = await db.query(
        'progress',
        where: 'shop_id = ?',
        whereArgs: [shopId],
      );
      for (final r in progRows) {
        totalImages += (r['current_count'] as int? ?? 0);
      }
      final count = Sqflite.firstIntValue(
        await db.rawQuery(
          'SELECT COUNT(*) FROM variants WHERE shop_id = ?',
          [shopId],
        ),
      ) ?? 0;
      totalVariants += count;
    }
    return {'total_images': totalImages, 'total_variants': totalVariants};
  }

  // ── Pending sync (offline queue) ────────────

  Future<void> addPendingSync(String kind, Map<String, dynamic> payload) async {
    final db = await _database;
    await db.insert('pending_sync', {
      'kind': kind,
      'payload': jsonEncode(payload),
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  Future<List<Map<String, dynamic>>> getPendingSync() async {
    final db = await _database;
    final rows = await db.query('pending_sync', orderBy: 'id ASC');
    return rows.map((r) {
      final payload = r['payload'] as String?;
      return {
        'id': r['id'] as int,
        'kind': r['kind'] as String,
        'payload': payload != null ? jsonDecode(payload) as Map<String, dynamic> : <String, dynamic>{},
      };
    }).toList();
  }

  /// Ids of variants that are still in the pending_sync queue (push failed or offline). Used to show "sync first" only for these.
  Future<Set<String>> getPendingVariantIds() async {
    final list = await getPendingSync();
    final ids = <String>{};
    for (final item in list) {
      if (item['kind'] == 'variant') {
        final localId = item['payload']?['local_id'] as String?;
        if (localId != null) ids.add(localId);
      }
    }
    return ids;
  }

  Future<void> removePendingSync(int id) async {
    final db = await _database;
    await db.delete('pending_sync', where: 'id = ?', whereArgs: [id]);
  }
}
