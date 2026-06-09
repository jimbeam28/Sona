// lib/core/contracts/database_contract.dart
// Abstract interfaces for the DAO (Data Access Object) layer.
//
// These contracts decouple the domain/presentation layers from the concrete
// SQLite implementations, enabling fakes/mocks for testing without sqflite
// platform channels.

import '../../shared/models/connection_config.dart';
import '../../shared/models/play_progress.dart';
import '../../shared/models/playlist.dart';

// ── ConnectionDao ──────────────────────────────────────────────────────────

/// Abstract interface for the `connections` table DAO.
///
/// Mirrors the subset of [ConnectionDao] methods used by the application.
abstract class IConnectionDao {
  /// Inserts a new connection row. Returns the new row id.
  /// [passwordKey] is the flutter_secure_storage reference key.
  Future<int> insert(ConnectionConfig config, {required String passwordKey});

  /// Returns all connections ordered by creation time.
  Future<List<ConnectionConfig>> findAll();

  /// Returns the connection with [id], or `null` if not found.
  Future<ConnectionConfig?> findById(int id);

  /// Returns the currently active connection, or `null`.
  Future<ConnectionConfig?> findActive();

  /// Returns the password reference key stored for [id].
  Future<String?> findPasswordKey(int id);

  /// Updates the connection row for [config].
  Future<int> update(ConnectionConfig config, {required String passwordKey});

  /// Sets [id] as the only active connection (clears all others).
  Future<void> setActive(int id);

  /// Deletes the connection with [id] and cascades to related records.
  ///
  /// Returns `true` if the deleted connection was the active one.
  Future<bool> delete(int id);

  /// Returns the total number of connections.
  Future<int> count();
}

// ── ProgressDao ────────────────────────────────────────────────────────────

/// Abstract interface for the `play_progress` table DAO.
///
/// Mirrors the subset of [ProgressDao] methods used by the application.
abstract class IProgressDao {
  /// Saves playback progress using UPSERT semantics.
  ///
  /// Returns `true` if a record was created or updated, `false` if skipped
  /// (position too short), `null` if the record was cleared (playback finished).
  Future<bool?> upsert({
    required int connectionId,
    required String filePath,
    required int positionMs,
    int? durationMs,
  });

  /// Saves only the currently active playback progress, replacing older records.
  Future<bool?> upsertLatest({
    required int connectionId,
    required String filePath,
    required int positionMs,
    int? durationMs,
  });

  /// Inserts a progress record directly without policy checks.
  Future<void> rawInsert(PlayProgress progress);

  /// Finds the saved progress for a file on a connection.
  Future<PlayProgress?> find(int connectionId, String filePath);

  /// Returns recently played files ordered by lastPlayedAt descending.
  Future<List<PlayProgress>> getRecentlyPlayed({int limit = 20});

  /// Returns the single active progress record after pruning legacy rows.
  Future<PlayProgress?> findLatest();

  /// Returns all progress records for a specific connection.
  Future<List<PlayProgress>> findByConnection(int connectionId);

  /// Deletes a single progress record.
  Future<void> delete(int connectionId, String filePath);

  /// Deletes all progress records for a given connection.
  Future<void> deleteByConnection(int connectionId);

  /// Returns the total number of progress records.
  Future<int> count();

  /// Clears the current active progress record.
  Future<void> clearLatest();
}

// ── PlaylistDao ────────────────────────────────────────────────────────────

/// Abstract interface for the `playlists` and `playlist_tracks` tables DAO.
///
/// Mirrors the subset of [PlaylistDao] methods used by the application.
abstract class IPlaylistDao {
  /// Inserts a new playlist. Returns the new row id.
  Future<int> insertPlaylist(Playlist playlist);

  /// Returns all playlists with track counts, ordered by creation time.
  Future<List<Playlist>> findAllPlaylists();

  /// Updates the playlist metadata.
  Future<void> updatePlaylist(Playlist playlist);

  /// Deletes the playlist with [id] (CASCADE deletes tracks).
  Future<void> deletePlaylist(int id);

  /// Adds tracks to a playlist (bulk insert in a transaction).
  Future<void> addTracks(List<PlaylistTrack> tracks);

  /// Returns all tracks for [playlistId] ordered by added time.
  Future<List<PlaylistTrack>> findTracksForPlaylist(int playlistId);

  /// Removes tracks by their IDs.
  Future<void> removeTracks(List<int> trackIds);

  /// Returns `true` if [filePath] already exists in [playlistId].
  Future<bool> trackExists(int playlistId, String filePath);

  /// Reorders a track within a playlist.
  Future<void> reorderTrack(int playlistId, int oldIndex, int newIndex);
}
