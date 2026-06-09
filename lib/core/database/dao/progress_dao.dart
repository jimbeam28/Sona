// lib/core/database/dao/progress_dao.dart
// Data-access object for the `play_progress` table.
//
// Provides CRUD + UPSERT semantics for playback progress records.
// UPSERT ensures one row per (connection_id, file_path) pair:
// inserting an existing pair updates the existing row instead of creating
// a duplicate (PRG-T02).

import 'package:sqflite/sqflite.dart';
import '../../contracts/database_contract.dart';
import '../../database/database_helper.dart';
import '../../../shared/models/play_progress.dart';
import '../../../features/progress/domain/progress_policy.dart'
    as progress_policy;

class ProgressDao implements IProgressDao {
  final DatabaseHelper _helper;

  ProgressDao({DatabaseHelper? helper})
      : _helper = helper ?? DatabaseHelper.instance;

  Future<Database> get _db async => _helper.database;

  // ── Upsert ───────────────────────────────────────────────────────────────────

  /// Saves playback progress for a file, using UPSERT semantics.
  ///
  /// If a record for (connectionId, filePath) already exists it is updated;
  /// otherwise a new row is inserted (PRG-T01, PRG-T02).
  ///
  /// Before persisting, [shouldSave] and [shouldClear] are checked:
  /// - Position < 5 s  → skip (don't save, PRG-T03)
  /// - Position > duration - 10 s  → delete the record (PRG-T04)
  ///
  /// Returns `true` if a record was created or updated, `false` if the
  /// save was skipped (position too short).
  /// Returns `null` if the record was cleared (playback finished).
  ///
  /// The [lastPlayedAt] timestamp is always set to now.
  Future<bool?> upsert({
    required int connectionId,
    required String filePath,
    required int positionMs,
    int? durationMs,
  }) async {
    // PRG-T03: don't save if position < 5 seconds
    if (!shouldSave(positionMs)) return false;

    // PRG-T04: clear record if position > duration - 10s
    if (shouldClear(positionMs, durationMs)) {
      await delete(connectionId, filePath);
      return null; // record was cleared
    }

    final db = await _db;
    final now = DateTime.now().millisecondsSinceEpoch;

    await db.insert(
      'play_progress',
      {
        'connection_id': connectionId,
        'file_path': filePath,
        'position_ms': positionMs,
        'duration_ms': durationMs,
        'last_played_at': now,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    return true;
  }

  /// Migrates legacy multi-row history into the new single-active model by
  /// keeping only the most recently played record.
  Future<void> migrateLegacyToLatest() async {
    final db = await _db;
    final rows = await db.query(
      'play_progress',
      columns: ['id'],
      orderBy: 'last_played_at DESC',
    );
    if (rows.length <= 1) return;

    final idsToDelete = rows.skip(1).map((row) => row['id'] as int).toList();
    final placeholders = List.filled(idsToDelete.length, '?').join(',');
    await db.delete(
      'play_progress',
      where: 'id IN ($placeholders)',
      whereArgs: idsToDelete,
    );
  }

  /// Saves only the currently active playback progress, replacing any older
  /// records kept by the legacy per-file model.
  Future<bool?> upsertLatest({
    required int connectionId,
    required String filePath,
    required int positionMs,
    int? durationMs,
  }) async {
    if (!shouldSave(positionMs)) return false;

    if (shouldClear(positionMs, durationMs)) {
      await clearLatest();
      return null;
    }

    final db = await _db;
    final now = DateTime.now().millisecondsSinceEpoch;

    await db.transaction((txn) async {
      await txn.delete('play_progress');
      await txn.insert(
        'play_progress',
        {
          'connection_id': connectionId,
          'file_path': filePath,
          'position_ms': positionMs,
          'duration_ms': durationMs,
          'last_played_at': now,
        },
      );
    });

    return true;
  }

  // ── Query ────────────────────────────────────────────────────────────────────

  /// Inserts a [progress] record directly without [shouldSave] / [shouldClear]
  /// checks.  Useful for testing when you need explicit control over
  /// timestamps (e.g. [getRecentlyPlayed] ordering tests).
  Future<void> rawInsert(PlayProgress progress) async {
    final db = await _db;
    final map = progress.toMap();
    map.remove('id'); // let AUTOINCREMENT assign it
    await db.insert('play_progress', map);
  }

  /// Finds the saved playback progress for a file on a connection.
  ///
  /// Returns `null` when no progress has been saved (PRG-T12).
  Future<PlayProgress?> find(int connectionId, String filePath) async {
    final db = await _db;
    final rows = await db.query(
      'play_progress',
      where: 'connection_id = ? AND file_path = ?',
      whereArgs: [connectionId, filePath],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return PlayProgress.fromMap(rows.first);
  }

  /// Returns recently played files ordered by [lastPlayedAt] descending,
  /// capped at [limit] (PRG-T16).
  Future<List<PlayProgress>> getRecentlyPlayed({int limit = 20}) async {
    final db = await _db;
    final rows = await db.query(
      'play_progress',
      orderBy: 'last_played_at DESC',
      limit: limit,
    );
    return rows.map(PlayProgress.fromMap).toList();
  }

  /// Returns the single active progress record after pruning legacy rows.
  Future<PlayProgress?> findLatest() async {
    await migrateLegacyToLatest();
    final records = await getRecentlyPlayed(limit: 1);
    if (records.isEmpty) return null;
    return records.first;
  }

  /// Returns all progress records for a specific connection.
  Future<List<PlayProgress>> findByConnection(int connectionId) async {
    final db = await _db;
    final rows = await db.query(
      'play_progress',
      where: 'connection_id = ?',
      whereArgs: [connectionId],
      orderBy: 'last_played_at DESC',
    );
    return rows.map(PlayProgress.fromMap).toList();
  }

  // ── Delete ───────────────────────────────────────────────────────────────────

  /// Deletes a single progress record (PRG-T28).
  Future<void> delete(int connectionId, String filePath) async {
    final db = await _db;
    await db.delete(
      'play_progress',
      where: 'connection_id = ? AND file_path = ?',
      whereArgs: [connectionId, filePath],
    );
  }

  /// Deletes all progress records for a given connection.
  ///
  /// Called as part of connection-deletion cascade (CON-T31).
  Future<void> deleteByConnection(int connectionId) async {
    final db = await _db;
    await db.delete(
      'play_progress',
      where: 'connection_id = ?',
      whereArgs: [connectionId],
    );
  }

  /// Returns the total number of progress records in the table.
  Future<int> count() async {
    final db = await _db;
    final result =
        await db.rawQuery('SELECT COUNT(*) as cnt FROM play_progress');
    return (result.first['cnt'] as int?) ?? 0;
  }

  /// Clears the current active progress record.
  Future<void> clearLatest() async {
    final db = await _db;
    await db.delete('play_progress');
  }

  // ── Static helpers ───────────────────────────────────────────────────────────

  /// Delegates to [progress_policy.shouldSave].
  /// See [progress_policy] for full documentation.
  static bool shouldSave(int positionMs) =>
      progress_policy.shouldSave(positionMs);

  /// Delegates to [progress_policy.shouldClear].
  /// See [progress_policy] for full documentation.
  static bool shouldClear(int positionMs, int? durationMs) =>
      progress_policy.shouldClear(positionMs, durationMs);
}
