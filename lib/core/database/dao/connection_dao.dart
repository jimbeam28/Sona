// lib/core/database/dao/connection_dao.dart
// Data-access object for the `connections` table.
// The `password` column stores a flutter_secure_storage reference key.

import 'package:sqflite/sqflite.dart';
import '../../contracts/database_contract.dart';
import '../../database/database_helper.dart';
import '../../../shared/models/connection_config.dart';

// REF-17-S2: LastConnectionException 定义上提至 contracts；
// re-export 保证既有经本文件导入该异常的调用方零改动。
export '../../contracts/database_contract.dart' show LastConnectionException;

class ConnectionDao implements IConnectionDao {
  final DatabaseHelper _helper;

  /// Injectable "now" provider (BUG-26-S4). Defaults to [DateTime.now] so
  /// production behaviour is unchanged; tests may inject a fixed clock.
  final DateTime Function() _clock;

  ConnectionDao({DatabaseHelper? helper, DateTime Function()? clock})
      : _helper = helper ?? DatabaseHelper.instance,
        _clock = clock ?? DateTime.now;

  Future<Database> get _db async => _helper.database;

  // ── Insert ──────────────────────────────────────────────────────────────────

  /// Inserts a new connection row. Returns the new row id.
  /// [passwordKey] is the flutter_secure_storage reference key.
  Future<int> insert(ConnectionConfig config,
      {required String passwordKey}) async {
    final db = await _db;
    final map = config.toMap(passwordKey: passwordKey);
    map.remove('id'); // let AUTOINCREMENT assign it
    return db.insert('connections', map);
  }

  // ── Query ───────────────────────────────────────────────────────────────────

  Future<List<ConnectionConfig>> findAll() async {
    final db = await _db;
    final rows = await db.query('connections', orderBy: 'created_at ASC');
    return rows.map(ConnectionConfig.fromMap).toList();
  }

  Future<ConnectionConfig?> findById(int id) async {
    final db = await _db;
    final rows =
        await db.query('connections', where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return null;
    return ConnectionConfig.fromMap(rows.first);
  }

  Future<ConnectionConfig?> findActive() async {
    final db = await _db;
    final rows =
        await db.query('connections', where: 'is_active = 1', limit: 1);
    if (rows.isEmpty) return null;
    return ConnectionConfig.fromMap(rows.first);
  }

  /// Returns the password reference key stored for [id].
  Future<String?> findPasswordKey(int id) async {
    final db = await _db;
    final rows = await db.query(
      'connections',
      columns: ['password'],
      where: 'id = ?',
      whereArgs: [id],
    );
    if (rows.isEmpty) return null;
    return rows.first['password'] as String?;
  }

  // ── Update ──────────────────────────────────────────────────────────────────

  Future<int> update(ConnectionConfig config,
      {required String passwordKey}) async {
    final db = await _db;
    final map = config.toMap(passwordKey: passwordKey);
    map['updated_at'] = _clock().millisecondsSinceEpoch;
    return db
        .update('connections', map, where: 'id = ?', whereArgs: [config.id]);
  }

  /// Sets [id] as the only active connection (clears all others).
  Future<void> setActive(int id) async {
    final db = await _db;
    await db.transaction((txn) async {
      await txn.update('connections', {'is_active': 0});
      await txn.update(
        'connections',
        {'is_active': 1, 'updated_at': _clock().millisecondsSinceEpoch},
        where: 'id = ?',
        whereArgs: [id],
      );
    });
  }

  // ── Delete ──────────────────────────────────────────────────────────────────

  /// Deletes the connection with [id] and cascades to related records.
  ///
  /// Throws [LastConnectionException] if fewer than 2 connections remain
  /// (CON-T32 protection — "至少保留一个连接").
  ///
  /// Returns `true` if the deleted connection was the active one
  /// (CON-T34 — caller can notify the UI that the active connection changed).
  Future<bool> delete(int id) async {
    final db = await _db;

    // CON-T32: protect the last remaining connection
    final remaining = await count();
    if (remaining <= 1) {
      throw const LastConnectionException('至少保留一个连接');
    }

    // Check whether the connection being deleted is currently active
    final config = await findById(id);
    final wasActive = config?.isActive ?? false;

    await db.transaction((txn) async {
      // Cascade-delete any play_progress records (CON-T31).
      // I-2 note: the table is created in _onCreate, but test databases
      // may use a different version path.  Keep the guard.
      try {
        await txn.delete('play_progress',
            where: 'connection_id = ?', whereArgs: [id]);
      } on DatabaseException catch (e) {
        if (!e.isNoSuchTableError()) rethrow;
      }

      // Delete the connection row itself
      await txn.delete('connections', where: 'id = ?', whereArgs: [id]);
    });

    // CON-T34: if the deleted connection was active, auto-activate another
    if (wasActive) {
      final remainingConfigs = await findAll();
      if (remainingConfigs.isNotEmpty) {
        await setActive(remainingConfigs.first.id!);
      }
    }

    return wasActive;
  }

  /// Deletes the connection row with [id] WITHOUT the CON-T32 last-connection
  /// guard (BUG-17). Compensation-only method: used by the service layer to
  /// roll back a row just inserted by the same save() call — the count-guard
  /// must not block that rollback (a first-ever connection that fails to save
  /// has exactly 1 row and would trip the guard).
  ///
  /// Returns `true` if the deleted connection was the active one (BUG-17-S4
  /// keeps CON-T34 semantics for parity with [delete]).
  Future<bool> deleteWithoutGuard(int id) async {
    final db = await _db;
    final config = await findById(id);
    final wasActive = config?.isActive ?? false;
    await db.transaction((txn) async {
      try {
        await txn.delete('play_progress',
            where: 'connection_id = ?', whereArgs: [id]);
      } on DatabaseException catch (e) {
        if (!e.isNoSuchTableError()) rethrow;
      }
      await txn.delete('connections', where: 'id = ?', whereArgs: [id]);
    });
    if (wasActive) {
      final remainingConfigs = await findAll();
      if (remainingConfigs.isNotEmpty) {
        await setActive(remainingConfigs.first.id!);
      }
    }
    return wasActive;
  }

  Future<int> count() async {
    final db = await _db;
    final result = await db.rawQuery('SELECT COUNT(*) as cnt FROM connections');
    return (result.first['cnt'] as int?) ?? 0;
  }
}
