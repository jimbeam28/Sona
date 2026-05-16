// lib/core/database/dao/progress_dao.dart
// Data-access object for the `play_progress` table.
//
// Provides CRUD + UPSERT semantics for playback progress records.
// UPSERT ensures one row per (connection_id, file_path) pair:
// inserting an existing pair updates the existing row instead of creating
// a duplicate (PRG-T02).

import 'package:sqflite/sqflite.dart';
import '../../database/database_helper.dart';
import '../../../shared/models/play_progress.dart';

class ProgressDao {
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

  // ── Static helpers ───────────────────────────────────────────────────────────

  /// Returns `true` when [positionMs] is >= 5 000 ms.
  ///
  /// Positions under 5 seconds are considered "not started" and should not
  /// be saved (PRG-T03, PRG-T05).
  static bool shouldSave(int positionMs) => positionMs >= 5000;

  /// Returns `true` when the position is past the "finished" threshold.
  ///
  /// A file is considered finished when its position exceeds
  /// `duration - 10 000` ms (10 seconds before the end).
  /// In this case the progress record should be cleared rather than saved
  /// (PRG-T04, PRG-T06).
  ///
  /// Returns `false` when [durationMs] is null (unknown duration).
  static bool shouldClear(int positionMs, int? durationMs) {
    if (durationMs == null) return false;
    // G-3: files shorter than 10 s should never auto-clear — the 10-second
    // window is meaningless when the file itself is shorter than that.
    if (durationMs <= 10000) return false;
    return positionMs > durationMs - 10000;
  }
}
