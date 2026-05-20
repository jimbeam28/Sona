// lib/core/database/dao/playlist_dao.dart
// Data-access object for the `playlists` and `playlist_tracks` tables.

import 'package:sqflite/sqflite.dart';
import '../../database/database_helper.dart';
import '../../../shared/models/playlist.dart';

class PlaylistDao {
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
    await db.update('playlists', map, where: 'id = ?', whereArgs: [playlist.id]);
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
}
