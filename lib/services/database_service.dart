// ─────────────────────────────────────────────
//  ZERO-CLEAN  ·  Database Service (SQLite)
// ─────────────────────────────────────────────

import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/models.dart';

class DatabaseService {
  static final DatabaseService instance = DatabaseService._internal();
  DatabaseService._internal();

  Database? _db;

  Future<Database> get db async {
    _db ??= await _initDb();
    return _db!;
  }

  Future<Database> _initDb() async {
    final dbPath = await getDatabasesPath();
    return openDatabase(
      join(dbPath, 'zero_clean.db'),
      version: 1,
      onCreate: _onCreate,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE shops (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        location_note TEXT DEFAULT ''
      )
    ''');

    await db.execute('''
      CREATE TABLE variants (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        category TEXT NOT NULL,
        brand TEXT NOT NULL,
        sub_brand TEXT NOT NULL,
        volume TEXT NOT NULL,
        material TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE progress (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        variant_id INTEGER NOT NULL,
        shop_id INTEGER NOT NULL,
        context TEXT NOT NULL,
        current_count INTEGER DEFAULT 0,
        target_cap INTEGER NOT NULL,
        FOREIGN KEY (variant_id) REFERENCES variants(id),
        FOREIGN KEY (shop_id) REFERENCES shops(id),
        UNIQUE(variant_id, shop_id, context)
      )
    ''');
  }

  // ── Shops ──────────────────────────────────

  Future<List<Shop>> getShops() async {
    final d = await db;
    final rows = await d.query('shops', orderBy: 'name ASC');
    return rows.map(Shop.fromMap).toList();
  }

  Future<int> insertShop(Shop shop) async {
    final d = await db;
    return d.insert('shops', shop.toMap()..remove('id'));
  }

  // ── Variants ───────────────────────────────

  Future<List<Variant>> getVariants() async {
    final d = await db;
    final rows = await d.query('variants', orderBy: 'brand ASC, sub_brand ASC');
    return rows.map(Variant.fromMap).toList();
  }

  Future<List<Variant>> getVariantsByCategory(String category) async {
    final d = await db;
    final rows = await d.query('variants',
        where: 'category = ?', whereArgs: [category], orderBy: 'brand ASC');
    return rows.map(Variant.fromMap).toList();
  }

  Future<List<String>> getCategories() async {
    final d = await db;
    final rows =
        await d.rawQuery('SELECT DISTINCT category FROM variants ORDER BY category ASC');
    return rows.map((r) => r['category'] as String).toList();
  }

  Future<int> insertVariant(Variant variant) async {
    final d = await db;
    return d.insert('variants', variant.toMap()..remove('id'));
  }

  // ── Progress ───────────────────────────────

  Future<List<Progress>> getProgressForShop(int shopId) async {
    final d = await db;
    final rows = await d.query('progress',
        where: 'shop_id = ?', whereArgs: [shopId]);
    return rows.map(Progress.fromMap).toList();
  }

  Future<Progress?> getProgress(
      int variantId, int shopId, CaptureContext ctx) async {
    final d = await db;
    final rows = await d.query('progress',
        where: 'variant_id = ? AND shop_id = ? AND context = ?',
        whereArgs: [variantId, shopId, ctx.name]);
    if (rows.isEmpty) return null;
    return Progress.fromMap(rows.first);
  }

  Future<void> incrementCount(
      int variantId, int shopId, CaptureContext ctx) async {
    final d = await db;
    await d.rawUpdate('''
      UPDATE progress
      SET current_count = current_count + 1
      WHERE variant_id = ? AND shop_id = ? AND context = ?
    ''', [variantId, shopId, ctx.name]);
  }

  Future<void> ensureProgressRow(
      int variantId, int shopId, CaptureContext ctx) async {
    final d = await db;
    await d.insert(
      'progress',
      {
        'variant_id': variantId,
        'shop_id': shopId,
        'context': ctx.name,
        'current_count': 0,
        'target_cap': ctx.targetCap,
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  Future<Map<String, int>> getTotalStats() async {
    final d = await db;
    final rows = await d
        .rawQuery('SELECT SUM(current_count) as total FROM progress');
    final total = (rows.first['total'] as int?) ?? 0;
    final variantRows =
        await d.rawQuery('SELECT COUNT(*) as cnt FROM variants');
    final variants = (variantRows.first['cnt'] as int?) ?? 0;
    return {'total_images': total, 'total_variants': variants};
  }
}
