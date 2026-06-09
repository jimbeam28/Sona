// lib/core/database/dao/playlist_dao.dart
// Data-access object for the `playlists` and `playlist_tracks` tables.

import 'package:sqflite/sqflite.dart';
import '../../contracts/database_contract.dart';
import '../../database/database_helper.dart';
import '../../../shared/models/playlist.dart';

class PlaylistDao implements IPlaylistDao {
  final DatabaseHelper _helper;

  PlaylistDao({DatabaseHelper? helper})
      : _helper = helper ?? DatabaseHelper.instance;

  Future<Database> get _db async => _helper.database;

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
    map['updated_at'] = DateTime.now().millisecondsSinceEpoch;
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

  Future<List<PlaylistTrack>> findTracksForPlaylist(int playlistId) async {
    final db = await _db;
    final rows = await db.query(
      'playlist_tracks',
      where: 'playlist_id = ?',
      whereArgs: [playlistId],
      orderBy: 'added_at ASC',
    );
    return rows.map(PlaylistTrack.fromMap).toList();
  }

  Future<void> removeTracks(List<int> trackIds) async {
    final db = await _db;
    final placeholders = List.filled(trackIds.length, '?').join(',');
    await db.delete(
      'playlist_tracks',
      where: 'id IN ($placeholders)',
      whereArgs: trackIds,
    );
  }

  Future<bool> trackExists(int playlistId, String filePath) async {
    final db = await _db;
    final result = await db.rawQuery(
      'SELECT COUNT(*) as cnt FROM playlist_tracks '
      'WHERE playlist_id = ? AND file_path = ?',
      [playlistId, filePath],
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

    final moved = List<Map<String, dynamic>>.from(tracks);
    moved.removeAt(oldIndex);
    moved.insert(newIndex, tracks[oldIndex]);

    final base = DateTime.now().millisecondsSinceEpoch;
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
