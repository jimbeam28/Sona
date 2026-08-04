// lib/core/database/dao/playlist_dao.dart
// Data-access object for the `playlists` and `playlist_tracks` tables.

import 'package:sqflite/sqflite.dart';
import '../../contracts/database_contract.dart';
import '../../database/database_helper.dart';
import '../../../shared/models/playlist.dart';
import '../../../shared/webdav_paths.dart';

class PlaylistDao implements IPlaylistDao {
  final DatabaseHelper _helper;

  /// Injectable "now" provider (BUG-26-S4). Defaults to [DateTime.now] so
  /// production behaviour is unchanged; tests may inject a fixed clock.
  final DateTime Function() _clock;

  PlaylistDao({DatabaseHelper? helper, DateTime Function()? clock})
      : _helper = helper ?? DatabaseHelper.instance,
        _clock = clock ?? DateTime.now;

  Future<Database> get _db async => _helper.database;

  // ── NET1 legacy stored-path normalisation (cr-20260804-1922 O1) ──────────────
  //
  // Pre-NET1 builds stored server-ABSOLUTE file paths (connection root
  // prefixed) in `playlist_tracks.file_path`. `playlists` / `playlist_tracks`
  // carry NO connection attribution (no connection_id column), so the
  // read-time normalisation context is the ACTIVE connection; when it cannot
  // be resolved the paths are returned unchanged (never throw).

  /// Returns the server-absolute connection root of the active connection, or
  /// `null` when there is no active connection or the `connections` table is
  /// unavailable (e.g. a playlist-only test schema).
  Future<String?> _activeConnectionRoot() async {
    final db = await _db;
    List<Map<String, dynamic>> rows;
    try {
      rows = await db.query(
        'connections',
        columns: ['url', 'base_path'],
        where: 'is_active = 1',
        limit: 1,
      );
    } on DatabaseException catch (e) {
      // Playlist-only schema (no connections table) — nothing to normalise
      // by. Same narrow-guard pattern as ConnectionDao.delete (BUG-26-S4).
      if (!e.isNoSuchTableError()) rethrow;
      return null;
    }
    if (rows.isEmpty) return null;
    return webDavConnectionRoot(
      rows.first['url'] as String,
      (rows.first['base_path'] as String?) ?? '/',
    );
  }

  // ── Playlist CRUD ─────────────────────────────────────────────────────────

  Future<int> insertPlaylist(Playlist playlist) async {
    final db = await _db;
    final map = playlist.toMap();
    map.remove('id');
    return db.insert('playlists', map);
  }

  Future<List<Playlist>> findAllPlaylists() async {
    final db = await _db;
    final rows = await db.rawQuery('''
      SELECT p.*, COUNT(pt.id) as track_count
      FROM playlists p
      LEFT JOIN playlist_tracks pt ON pt.playlist_id = p.id
      GROUP BY p.id
      ORDER BY p.created_at ASC
    ''');
    return rows.map(Playlist.fromMap).toList();
  }

  Future<void> updatePlaylist(Playlist playlist) async {
    final db = await _db;
    final map = playlist.toMap();
    map['updated_at'] = _clock().millisecondsSinceEpoch;
    await db
        .update('playlists', map, where: 'id = ?', whereArgs: [playlist.id]);
  }

  Future<void> deletePlaylist(int id) async {
    final db = await _db;
    await db.delete('playlists', where: 'id = ?', whereArgs: [id]);
  }

  // ── Track CRUD ────────────────────────────────────────────────────────────

  Future<void> addTracks(List<PlaylistTrack> tracks) async {
    final db = await _db;
    await db.transaction((txn) async {
      for (final track in tracks) {
        final map = track.toMap();
        map.remove('id');
        await txn.insert('playlist_tracks', map);
      }
    });
  }

  /// Returns the tracks of a playlist ordered by `added_at ASC, id ASC`.
  ///
  /// The `id ASC` tiebreak matches [reorderTrack]'s baseline order so rows
  /// sharing one `added_at` (legacy pre-BUG-08 batches) read back in the
  /// same relative order both DAO paths agree on (BUG-08-INV1, O5-D2).
  ///
  /// Each track's `filePath` is normalised to the connection-root-relative
  /// form (O1) using the active connection's root, so rows persisted by
  /// pre-NET1 builds feed queue building / playback without a double base
  /// prefix. There is no natural rewrite point for `playlist_tracks`, so this
  /// is a pure read-time normalisation (no write-back).
  Future<List<PlaylistTrack>> findTracksForPlaylist(int playlistId) async {
    final db = await _db;
    final root = await _activeConnectionRoot();
    final rows = await db.query(
      'playlist_tracks',
      where: 'playlist_id = ?',
      whereArgs: [playlistId],
      orderBy: 'added_at ASC, id ASC',
    );
    final tracks = rows.map(PlaylistTrack.fromMap).toList();
    if (root == null || root == '/') return tracks;
    return tracks.map((t) {
      final normalized = normalizeStoredPath(t.filePath, basePath: root);
      if (normalized == t.filePath) return t;
      return PlaylistTrack(
        id: t.id,
        playlistId: t.playlistId,
        filePath: normalized,
        fileName: t.fileName,
        addedAt: t.addedAt,
      );
    }).toList();
  }

  Future<void> removeTracks(List<int> trackIds) async {
    if (trackIds.isEmpty) return;
    final db = await _db;
    final placeholders = List.filled(trackIds.length, '?').join(',');
    await db.delete(
      'playlist_tracks',
      where: 'id IN ($placeholders)',
      whereArgs: trackIds,
    );
  }

  /// Returns whether [filePath] is already present in the playlist.
  ///
  /// Matches both the canonical and the NET1-legacy server-absolute stored
  /// form (O1), so dedup still recognises a file whose row was persisted by
  /// a pre-NET1 build even though the caller now passes the canonical path.
  Future<bool> trackExists(int playlistId, String filePath) async {
    final db = await _db;
    final root = await _activeConnectionRoot();
    final variants = <String>{filePath};
    if (root != null && root != '/') {
      final canonical = normalizeStoredPath(filePath, basePath: root);
      variants
        ..add(canonical)
        ..add('$root$canonical');
    }
    final placeholders = List.filled(variants.length, '?').join(', ');
    final result = await db.rawQuery(
      'SELECT COUNT(*) as cnt FROM playlist_tracks '
      'WHERE playlist_id = ? AND file_path IN ($placeholders)',
      [playlistId, ...variants],
    );
    return (result.first['cnt'] as int) > 0;
  }

  /// Reorders a track within a playlist by updating `added_at` timestamps
  /// to reflect the new positional order (PLS-03).
  Future<void> reorderTrack(int playlistId, int oldIndex, int newIndex) async {
    final db = await _db;
    final tracks = await db.query(
      'playlist_tracks',
      where: 'playlist_id = ?',
      whereArgs: [playlistId],
      orderBy: 'added_at ASC, id ASC',
    );
    if (tracks.length < 2) return;
    if (oldIndex == newIndex) return;
    if (oldIndex < 0 || oldIndex >= tracks.length) return;
    if (newIndex < 0 || newIndex >= tracks.length) return;

    final moved = List<Map<String, dynamic>>.from(tracks);
    moved.removeAt(oldIndex);
    moved.insert(newIndex, tracks[oldIndex]);

    final base = _clock().millisecondsSinceEpoch;
    final batch = db.batch();
    for (int i = 0; i < moved.length; i++) {
      batch.update(
        'playlist_tracks',
        {'added_at': base + i},
        where: 'id = ?',
        whereArgs: [moved[i]['id']],
      );
    }
    await batch.commit(noResult: true);
  }
}
