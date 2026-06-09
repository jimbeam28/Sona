// lib/features/playlist/domain/playlist_service.dart
// Domain service for the Playlist feature.
//
// Encapsulates CRUD, deduplication, and import/export logic for playlists.
// Pure Dart — no Flutter/Riverpod dependencies — so it can be unit-tested
// with plain constructors.
//
// REF-26: Extracted from playlist_provider.dart
//   - CRUD: create, update, delete playlist
//   - Track management: add tracks with dedup, remove tracks
//   - Import / Export: JSON serialization and deserialization

import 'dart:convert';

import '../../../core/database/dao/playlist_dao.dart';
import '../../../shared/models/nas_file.dart';
import '../../../shared/models/playlist.dart';

/// Pure-logic service that coordinates playlist CRUD, track deduplication,
/// and import/export.
///
/// All dependencies are injected through the constructor so the class
/// has zero service-locator / Flutter dependencies.
class PlaylistService {
  final PlaylistDao _dao;

  PlaylistService({PlaylistDao? dao}) : _dao = dao ?? PlaylistDao();

  // ── Playlist CRUD ─────────────────────────────────────────────────────────

  /// Creates a new playlist with the given [name].
  ///
  /// Returns the new playlist's database ID.
  Future<int> createPlaylist(String name) {
    final now = DateTime.now();
    return _dao.insertPlaylist(Playlist(
      name: name,
      createdAt: now,
      updatedAt: now,
    ));
  }

  /// Updates an existing [playlist] (e.g. rename).
  Future<void> updatePlaylist(Playlist playlist) {
    return _dao.updatePlaylist(playlist);
  }

  /// Deletes a playlist by [id], cascading to its tracks.
  Future<void> deletePlaylist(int id) {
    return _dao.deletePlaylist(id);
  }

  /// Returns all playlists.
  Future<List<Playlist>> findAllPlaylists() {
    return _dao.findAllPlaylists();
  }

  // ── Track management ──────────────────────────────────────────────────────

  /// Adds tracks from [files] to the playlist identified by [playlistId].
  ///
  /// Deduplicates by checking [PlaylistDao.trackExists] for each file's path
  /// before inserting.  Only files not already present are added.
  Future<void> addTracksToPlaylist(int playlistId, List<NasFile> files) async {
    final now = DateTime.now();
    final tracks = <PlaylistTrack>[];
    for (final file in files) {
      final exists = await _dao.trackExists(playlistId, file.path);
      if (!exists) {
        tracks.add(PlaylistTrack(
          playlistId: playlistId,
          filePath: file.path,
          fileName: file.name,
          addedAt: now,
        ));
      }
    }
    if (tracks.isNotEmpty) {
      await _dao.addTracks(tracks);
    }
  }

  /// Returns all tracks for the playlist identified by [playlistId].
  Future<List<PlaylistTrack>> findTracksForPlaylist(int playlistId) {
    return _dao.findTracksForPlaylist(playlistId);
  }

  /// Removes tracks by their database [trackIds].
  Future<void> removeTracks(List<int> trackIds) {
    return _dao.removeTracks(trackIds);
  }

  /// Reorders a track within a playlist.
  Future<void> reorderTrack(int playlistId, int oldIndex, int newIndex) {
    return _dao.reorderTrack(playlistId, oldIndex, newIndex);
  }

  // ── Export / Import ───────────────────────────────────────────────────────

  /// Exports a playlist to a pretty-printed JSON string.
  ///
  /// The JSON structure is:
  /// ```json
  /// {
  ///   "name": "playlist name",
  ///   "tracks": [
  ///     {"filePath": "/path/to/file.mp3", "fileName": "file.mp3"},
  ///     ...
  ///   ]
  /// }
  /// ```
  ///
  /// Throws [Exception] if the playlist does not exist.
  Future<String> exportPlaylist(int playlistId) async {
    final playlists = await _dao.findAllPlaylists();
    final playlist = playlists.where((p) => p.id == playlistId).firstOrNull;
    if (playlist == null) throw Exception('播放单不存在');

    final tracks = await _dao.findTracksForPlaylist(playlistId);
    final json = {
      'name': playlist.name,
      'tracks': tracks
          .map((t) => {'filePath': t.filePath, 'fileName': t.fileName})
          .toList(),
    };
    return const JsonEncoder.withIndent('  ').convert(json);
  }

  /// Imports a playlist from a JSON string.
  ///
  /// Returns the created playlist's database ID.
  ///
  /// Handles the following edge cases:
  /// - Missing `name` field defaults to `'导入的播放单'`
  /// - Missing `tracks` field defaults to empty list
  /// - Duplicate `filePath` values within the same import are deduplicated
  /// - Tracks with empty `filePath` are skipped
  ///
  /// Throws [FormatException] if [jsonString] is not valid JSON.
  Future<int> importPlaylist(String jsonString) async {
    final data = jsonDecode(jsonString) as Map<String, dynamic>;
    final name = (data['name'] as String?) ?? '导入的播放单';
    final trackList = (data['tracks'] as List<dynamic>?) ?? [];

    final now = DateTime.now();
    final playlistId = await _dao.insertPlaylist(Playlist(
      name: name,
      createdAt: now,
      updatedAt: now,
    ));

    final seen = <String>{};
    final tracks = trackList
        .map((t) => PlaylistTrack(
              playlistId: playlistId,
              filePath: t['filePath'] as String? ?? '',
              fileName: t['fileName'] as String? ?? '',
              addedAt: now,
            ))
        .where((t) => t.filePath.isNotEmpty && seen.add(t.filePath))
        .toList();

    if (tracks.isNotEmpty) {
      await _dao.addTracks(tracks);
    }

    return playlistId;
  }
}
