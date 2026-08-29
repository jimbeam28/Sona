// lib/core/database/dao/download_dao.dart
// Data-access object for the `downloads` table (DL-01).
//
// Upsert semantics: UNIQUE(connection_id, file_path) conflicts update ONLY
// status / bytes_downloaded / updated_at — the identity columns (file_name,
// remote_size, local_path, created_at) keep their first-insert values
// (DL-01-S2 否定断言).

import 'package:sqflite/sqflite.dart';

import '../../contracts/database_contract.dart';
import '../../database/database_helper.dart';

class DownloadDao implements IDownloadDao {
  final DatabaseHelper _helper;

  /// Injectable "now" provider (same pattern as ProgressDao). Defaults to
  /// [DateTime.now]; tests may inject a fixed clock.
  final DateTime Function() _clock;

  DownloadDao({DatabaseHelper? helper, DateTime Function()? clock})
      : _helper = helper ?? DatabaseHelper.instance,
        _clock = clock ?? DateTime.now;

  Future<Database> get _db => _helper.database;

  // ── Upsert ─────────────────────────────────────────────────────────────────

  @override
  Future<void> upsert(DownloadRecord record) async {
    final db = await _db;
    // created_at 落库取 record.updatedAt：调用方以 updatedAt 表达「首插时间」
    // （S2 冲突用例依赖首插 created_at == 首插 updatedAt）；UNIQUE 命中时本列
    // 与 file_name/remote_size/local_path 一同保持首插值不被覆盖。
    await db.rawInsert(
      '''
      INSERT INTO downloads (
        connection_id, file_path, file_name, remote_size, local_path,
        status, bytes_downloaded, created_at, updated_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(connection_id, file_path) DO UPDATE SET
        status = excluded.status,
        bytes_downloaded = excluded.bytes_downloaded,
        updated_at = excluded.updated_at
      ''',
      [
        record.connectionId,
        record.filePath,
        record.fileName,
        record.remoteSize,
        record.localPath,
        record.status,
        record.bytesDownloaded,
        record.updatedAt,
        record.updatedAt,
      ],
    );
  }

  // ── Query ───────────────────────────────────────────────────────────────────

  @override
  Future<DownloadRecord?> findById(int id) async {
    final db = await _db;
    final rows = await db.query(
      'downloads',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return DownloadRecord.fromMap(rows.first);
  }

  @override
  Future<DownloadRecord?> findByLocation(
      int connectionId, String filePath) async {
    final db = await _db;
    final rows = await db.query(
      'downloads',
      where: 'connection_id = ? AND file_path = ?',
      whereArgs: [connectionId, filePath],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return DownloadRecord.fromMap(rows.first);
  }

  @override
  Future<String?> findDoneLocalPath(int connectionId, String filePath) async {
    final db = await _db;
    final rows = await db.query(
      'downloads',
      columns: ['local_path'],
      where: "connection_id = ? AND file_path = ? AND status = ?",
      whereArgs: [connectionId, filePath, DownloadStatus.done],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first['local_path'] as String?;
  }

  @override
  Future<List<DownloadRecord>> listByConnection(int connectionId) async {
    final db = await _db;
    final rows = await db.query(
      'downloads',
      where: 'connection_id = ?',
      whereArgs: [connectionId],
      orderBy: 'updated_at DESC',
    );
    return rows.map(DownloadRecord.fromMap).toList();
  }

  @override
  Future<List<DownloadRecord>> listPending() async {
    final db = await _db;
    final rows = await db.query(
      'downloads',
      where: 'status = ?',
      whereArgs: [DownloadStatus.pending],
      orderBy: 'updated_at ASC, id ASC',
    );
    return rows.map(DownloadRecord.fromMap).toList();
  }

  // ── Mutation ────────────────────────────────────────────────────────────────

  @override
  Future<void> updateProgress(int id, int bytes) async {
    final db = await _db;
    await db.update(
      'downloads',
      {'bytes_downloaded': bytes},
      where: 'id = ? AND status = ?',
      whereArgs: [id, DownloadStatus.downloading],
    );
  }

  @override
  Future<void> setStatus(int id, String status,
      {int? bytes, String? localPath}) async {
    final db = await _db;
    var sql = 'UPDATE downloads SET status = ?';
    final args = <Object?>[status];
    if (bytes != null) {
      sql += ', bytes_downloaded = ?';
      args.add(bytes);
    }
    if (localPath != null) {
      sql += ', local_path = ?';
      args.add(localPath);
    }
    sql += ', updated_at = ? WHERE id = ?';
    args.addAll([_clock().millisecondsSinceEpoch, id]);
    await db.execute(sql, args);
  }

  @override
  Future<void> deleteById(int id) async {
    final db = await _db;
    await db.delete('downloads', where: 'id = ?', whereArgs: [id]);
  }

  @override
  Future<void> deleteByConnection(int connectionId) async {
    final db = await _db;
    await db.delete('downloads',
        where: 'connection_id = ?', whereArgs: [connectionId]);
  }

  // ── Aggregate ───────────────────────────────────────────────────────────────

  @override
  Future<int> totalBytesByConnection(int connectionId) async {
    final db = await _db;
    final rows = await db.rawQuery(
      '''
      SELECT COALESCE(SUM(remote_size), 0) AS total
      FROM downloads
      WHERE connection_id = ? AND status = ?
      ''',
      [connectionId, DownloadStatus.done],
    );
    return (rows.first['total'] as int?) ?? 0;
  }

  @override
  Future<void> markAllNonDoneFailed(int connectionId) async {
    final db = await _db;
    await db.execute(
      '''
      UPDATE downloads
      SET status = ?, updated_at = ?
      WHERE connection_id = ? AND status IN (?, ?)
      ''',
      [
        DownloadStatus.failed,
        _clock().millisecondsSinceEpoch,
        connectionId,
        DownloadStatus.pending,
        DownloadStatus.downloading,
      ],
    );
  }

  @override
  Future<List<int>> listDistinctConnections() async {
    final db = await _db;
    final rows =
        await db.rawQuery('SELECT DISTINCT connection_id FROM downloads');
    return rows
        .map((r) => r['connection_id'])
        .whereType<int>()
        .toList(growable: false);
  }
}
