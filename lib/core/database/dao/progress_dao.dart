// lib/core/database/dao/progress_dao.dart
// Data-access object for the `play_progress` table.
//
// Provides CRUD + UPSERT semantics for playback progress records.
// UPSERT ensures one row per (connection_id, file_path) pair:
// inserting an existing pair updates the existing row instead of creating
// a duplicate (PRG-T02).

import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import '../../contracts/database_contract.dart';
import '../../database/database_helper.dart';
import '../../../shared/models/play_progress.dart';
import '../../../shared/webdav_paths.dart';
import '../../../features/progress/domain/progress_policy.dart'
    as progress_policy;

class ProgressDao implements IProgressDao {
  final DatabaseHelper _helper;

  /// Injectable "now" provider (BUG-26-S4). Defaults to [DateTime.now] so
  /// production behaviour is unchanged; tests may inject a fixed clock.
  final DateTime Function() _clock;

  ProgressDao({DatabaseHelper? helper, DateTime Function()? clock})
      : _helper = helper ?? DatabaseHelper.instance,
        _clock = clock ?? DateTime.now;

  Future<Database> get _db async => _helper.database;

  // ── NET1 legacy stored-path normalisation (cr-20260804-1922 O1) ──────────────
  //
  // Pre-NET1 builds stored server-ABSOLUTE file paths (connection root
  // prefixed, e.g. `/dav/music/a.mp3`); NET1 made every read/write consumer
  // use connection-root-relative paths (`/music/a.mp3`). Rows persisted by
  // old builds therefore miss exact-match lookups and double-prefix playback
  // URLs. The connection root is recoverable from the owning connection row
  // (`play_progress.connection_id`), so reads normalise here instead of a
  // one-shot data migration.

  /// Returns the server-absolute connection root for [connectionId], or
  /// `null` when it cannot be resolved (connection row missing, or a reduced
  /// test schema that omits `connections.base_path` / the table itself).
  /// `null` degrades reads to passthrough (no normalisation) — the legacy
  /// behaviour — which is safe because a row whose root is unknown cannot be
  /// distinguished from an already-canonical one. Mirrors the BUG-26-S4
  /// no-such-table guard in `ConnectionDao.delete`.
  Future<String?> _connectionRoot(int connectionId) async {
    final db = await _db;
    List<Map<String, dynamic>> rows;
    try {
      rows = await db.query(
        'connections',
        columns: ['url', 'base_path'],
        where: 'id = ?',
        whereArgs: [connectionId],
      );
    } on DatabaseException catch (e) {
      debugPrint('[ProgressDao] connectionRoot lookup skipped: $e');
      return null;
    }
    if (rows.isEmpty) return null;
    return webDavConnectionRoot(
      rows.first['url'] as String,
      (rows.first['base_path'] as String?) ?? '/',
    );
  }

  /// Returns the stored-path variants that can refer to [filePath] on the
  /// connection with root [root]: the canonical (connection-root-relative)
  /// form and the legacy server-absolute form. Reads/deletes match both so
  /// rows written by pre-NET1 and post-NET1 builds are hit alike.
  List<String> _storedPathVariants(String filePath, String? root) {
    if (root == null || root == '/') return [filePath];
    final canonical = normalizeStoredPath(filePath, basePath: root);
    final legacy = '$root$canonical';
    return [canonical, legacy];
  }

  /// Returns [row] with its stored `file_path` normalised to the
  /// connection-root-relative form using [root].
  PlayProgress _normalizeProgressRow(Map<String, dynamic> row, String? root) {
    final progress = PlayProgress.fromMap(row);
    if (root == null) return progress;
    return progress.copyWith(
      filePath: normalizeStoredPath(progress.filePath, basePath: root),
    );
  }

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
    final now = _clock().millisecondsSinceEpoch;

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
  ///
  /// Matches both the canonical and the NET1-legacy server-absolute stored
  /// form of [filePath] (O1), so rows persisted by pre-NET1 builds are still
  /// found. The returned record's `filePath` is normalised to the
  /// connection-root-relative form. When both forms exist the most recently
  /// played wins.
  Future<PlayProgress?> find(int connectionId, String filePath) async {
    final db = await _db;
    final root = await _connectionRoot(connectionId);
    final variants = _storedPathVariants(filePath, root);
    final placeholders = List.filled(variants.length, '?').join(', ');
    final rows = await db.query(
      'play_progress',
      where: 'connection_id = ? AND file_path IN ($placeholders)',
      whereArgs: [connectionId, ...variants],
      orderBy: 'last_played_at DESC',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return _normalizeProgressRow(rows.first, root);
  }

  /// Returns recently played files ordered by [lastPlayedAt] descending,
  /// capped at [limit] (PRG-T16).
  ///
  /// Records are returned with their stored `file_path` unchanged. The
  /// startup-resume alignment (O1) normalises at the comparison site
  /// (`applyLatestProgressToQueue`) rather than here, so list consumers see
  /// exactly what is stored.
  Future<List<PlayProgress>> getRecentlyPlayed({int limit = 20}) async {
    final db = await _db;
    final rows = await db.query(
      'play_progress',
      orderBy: 'last_played_at DESC',
      limit: limit,
    );
    return rows.map(PlayProgress.fromMap).toList();
  }

  /// Returns the most recently played progress record.
  ///
  /// Pure query — no side effects (BUG-11): the per-file multi-record model
  /// (user decision 2026-07-24) keeps one row per (connectionId, filePath);
  /// reading the latest record must never delete the others, otherwise every
  /// app restart destroys all but the most recently played file's progress.
  Future<PlayProgress?> findLatest() async {
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
  ///
  /// Targets both the canonical and the NET1-legacy server-absolute stored
  /// form of [filePath] (O1) so clearing a file's progress also removes a
  /// row persisted by a pre-NET1 build — otherwise the legacy row would keep
  /// resurfacing the resume dialog.
  Future<void> delete(int connectionId, String filePath) async {
    final db = await _db;
    final root = await _connectionRoot(connectionId);
    final variants = _storedPathVariants(filePath, root);
    final placeholders = List.filled(variants.length, '?').join(', ');
    await db.delete(
      'play_progress',
      where: 'connection_id = ? AND file_path IN ($placeholders)',
      whereArgs: [connectionId, ...variants],
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

  /// Delegates to [progress_policy.shouldSave].
  /// See [progress_policy] for full documentation.
  static bool shouldSave(int positionMs) =>
      progress_policy.shouldSave(positionMs);

  /// Delegates to [progress_policy.shouldClear].
  /// See [progress_policy] for full documentation.
  static bool shouldClear(int positionMs, int? durationMs) =>
      progress_policy.shouldClear(positionMs, durationMs);
}
