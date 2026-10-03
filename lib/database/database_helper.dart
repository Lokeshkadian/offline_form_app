import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

import '../models/form_record.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper();

  DatabaseHelper({this.dbFactory, this.dbPath});

  final DatabaseFactory? dbFactory;
  final String? dbPath;

  static const String table = 'records';

  Database? _db;

  Future<Database> get database async {
    _db ??= await _open();
    return _db!;
  }

  Future<Database> _open() async {
    final factory = dbFactory ?? databaseFactory;
    final path =
        dbPath ?? join(await factory.getDatabasesPath(), 'offline_form.db');

    return factory.openDatabase(
      path,
      options: OpenDatabaseOptions(version: 1, onCreate: _onCreate),
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE $table (
        local_id TEXT PRIMARY KEY,
        server_id TEXT,
        full_name TEXT NOT NULL,
        mobile TEXT NOT NULL,
        email TEXT NOT NULL,
        category TEXT NOT NULL,
        description TEXT NOT NULL,
        visit_date TEXT NOT NULL,
        image_path TEXT,
        image_url TEXT,
        image_uploaded INTEGER NOT NULL DEFAULT 0,
        sync_status TEXT NOT NULL,
        sync_error TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
  }

  Future<void> insertRecord(FormRecord record) async {
    final db = await database;
    await db.insert(table, record.toMap());
  }

  Future<void> updateRecord(FormRecord record) async {
    final db = await database;
    await db.update(
      table,
      record.toMap(),
      where: 'local_id = ?',
      whereArgs: [record.localId],
    );
  }

  Future<void> deleteRecord(String localId) async {
    final db = await database;
    await db.delete(table, where: 'local_id = ?', whereArgs: [localId]);
  }

  Future<List<FormRecord>> getAllRecords() async {
    final db = await database;
    final rows = await db.query(table, orderBy: 'created_at DESC');
    return rows.map((row) => FormRecord.fromMap(row)).toList();
  }

  Future<List<FormRecord>> getPendingRecords() async {
    return _getByStatus(SyncStatus.pending);
  }

  Future<List<FormRecord>> getFailedRecords() async {
    return _getByStatus(SyncStatus.failed);
  }

  Future<List<FormRecord>> _getByStatus(SyncStatus status) async {
    final db = await database;
    final rows = await db.query(
      table,
      where: 'sync_status = ?',
      whereArgs: [status.name],
      orderBy: 'created_at ASC',
    );
    return rows.map((row) => FormRecord.fromMap(row)).toList();
  }

  Future<FormRecord?> getRecordByLocalId(String localId) async {
    final db = await database;
    final rows = await db.query(
      table,
      where: 'local_id = ?',
      whereArgs: [localId],
    );
    if (rows.isEmpty) return null;
    return FormRecord.fromMap(rows.first);
  }

  Future<FormRecord?> getRecordByServerId(String serverId) async {
    final db = await database;
    final rows = await db.query(
      table,
      where: 'server_id = ?',
      whereArgs: [serverId],
    );
    if (rows.isEmpty) return null;
    return FormRecord.fromMap(rows.first);
  }

  Future<void> markAsSyncing(String localId) async {
    final db = await database;
    await db.update(
      table,
      {'sync_status': SyncStatus.syncing.name},
      where: 'local_id = ?',
      whereArgs: [localId],
    );
  }

  Future<void> markAsSynced(String localId, String serverId) async {
    final db = await database;
    await db.update(
      table,
      {
        'sync_status': SyncStatus.synced.name,
        'server_id': serverId,
        'sync_error': null,
      },
      where: 'local_id = ?',
      whereArgs: [localId],
    );
  }

  Future<void> markAsFailed(String localId, String error) async {
    final db = await database;
    await db.update(
      table,
      {'sync_status': SyncStatus.failed.name, 'sync_error': error},
      where: 'local_id = ?',
      whereArgs: [localId],
    );
  }

  Future<void> resetStuckSyncing() async {
    final db = await database;
    await db.update(
      table,
      {'sync_status': SyncStatus.pending.name},
      where: 'sync_status = ?',
      whereArgs: [SyncStatus.syncing.name],
    );
  }

  Future<void> close() async {
    final db = _db;
    if (db != null) {
      await db.close();
      _db = null;
    }
  }
}
