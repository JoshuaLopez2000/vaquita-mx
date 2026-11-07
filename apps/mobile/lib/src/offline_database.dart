import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:vaquita_mx/src/models.dart';

class OfflineDatabase {
  OfflineDatabase(this._database);

  final Database _database;

  static Future<OfflineDatabase> open({String? databasePath}) async {
    final path =
        databasePath ?? p.join(await getDatabasesPath(), 'vaquita_mx.db');
    final database = await openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE groups (
            id TEXT PRIMARY KEY,
            remote_id TEXT,
            payload TEXT NOT NULL,
            revision INTEGER NOT NULL DEFAULT 1,
            synced_revision INTEGER NOT NULL DEFAULT 0
          )
        ''');
        await db.execute('''
          CREATE TABLE settings (
            key TEXT PRIMARY KEY,
            value TEXT NOT NULL
          )
        ''');
      },
    );
    return OfflineDatabase(database);
  }

  Future<List<ExpenseGroup>> loadGroups() async {
    final rows = await _database.query('groups', orderBy: 'rowid DESC');
    return rows
        .map((row) => ExpenseGroup.fromJson(
            jsonDecode(row['payload']! as String) as Map<String, dynamic>))
        .toList();
  }

  Future<void> saveGroup(ExpenseGroup group, {bool needsSync = true}) async {
    await _database.transaction((txn) async {
      final existing = await txn.query(
        'groups',
        columns: ['revision', 'synced_revision', 'remote_id'],
        where: 'id = ?',
        whereArgs: [group.id],
        limit: 1,
      );
      final old = existing.isEmpty ? null : existing.single;
      final revision = (old?['revision'] as int? ?? 0) + (needsSync ? 1 : 0);
      final storedRevision = revision == 0 ? 1 : revision;
      await txn.insert(
        'groups',
        {
          'id': group.id,
          'remote_id': old?['remote_id'],
          'payload': jsonEncode(group.toJson()),
          'revision': storedRevision,
          'synced_revision': needsSync
              ? (old?['synced_revision'] as int? ?? 0)
              : storedRevision,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    });
  }

  Future<List<ExpenseGroup>> groupsPendingSync() async {
    final rows = await _database.query(
      'groups',
      where: 'revision > synced_revision',
      orderBy: 'rowid',
    );
    return rows
        .map((row) => ExpenseGroup.fromJson(
            jsonDecode(row['payload']! as String) as Map<String, dynamic>))
        .toList();
  }

  Future<bool> isPending(String groupId) async {
    final rows = await _database.query(
      'groups',
      columns: ['revision', 'synced_revision'],
      where: 'id = ?',
      whereArgs: [groupId],
      limit: 1,
    );
    if (rows.isEmpty) return false;
    return (rows.single['revision']! as int) >
        (rows.single['synced_revision']! as int);
  }

  Future<int> revision(String groupId) async {
    final rows = await _database.query(
      'groups',
      columns: ['revision'],
      where: 'id = ?',
      whereArgs: [groupId],
      limit: 1,
    );
    if (rows.isEmpty) throw StateError('Local group disappeared during sync');
    return rows.single['revision']! as int;
  }

  Future<bool> syncEnabled(String accountId) async {
    final rows = await _database.query(
      'settings',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: ['sync_enabled:$accountId'],
      limit: 1,
    );
    return rows.isNotEmpty && rows.single['value'] == 'true';
  }

  Future<void> setSyncEnabled(String accountId, bool enabled) async {
    await _database.insert(
      'settings',
      {'key': 'sync_enabled:$accountId', 'value': '$enabled'},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> markSynced(
      String localGroupId, String remoteGroupId, int revision) async {
    final changed = await _database.rawUpdate(
      'UPDATE groups SET remote_id = ?, synced_revision = MAX(synced_revision, ?) WHERE id = ?',
      [remoteGroupId, revision, localGroupId],
    );
    if (changed != 1) throw StateError('Local group disappeared during sync');
  }

  Future<bool> hasPendingGroups() async {
    final rows = await _database.rawQuery(
      'SELECT EXISTS(SELECT 1 FROM groups WHERE revision > synced_revision) AS pending',
    );
    return rows.single['pending'] == 1;
  }

  Future<void> close() => _database.close();
}
