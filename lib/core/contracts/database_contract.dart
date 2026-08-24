// lib/core/contracts/database_contract.dart
// Abstract interfaces for the DAO (Data Access Object) layer.
//
// These contracts decouple the domain/presentation layers from the concrete
// SQLite implementations, enabling fakes/mocks for testing without sqflite
// platform channels.

import '../../shared/models/connection_config.dart';
import '../../shared/models/download_record.dart';
import '../../shared/models/play_progress.dart';
import '../../shared/models/playlist.dart';

// DL-01: the download record/status types are re-exported here (same pattern
// as LastConnectionException below) so feature code and tests can resolve
// them through this contract file alone.
export '../../shared/models/download_record.dart'
    show DownloadRecord, DownloadStatus;

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
  ///
  /// Throws [LastConnectionException] when only one connection remains.
  Future<bool> delete(int id);

  /// Deletes the connection row with [id] WITHOUT the CON-T32 last-connection
  /// guard. Compensation-only method: MUST NOT be used for user-facing
  /// deletes (only for service-layer rollback of a row just inserted by
  /// the same call).
  Future<bool> deleteWithoutGuard(int id);

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

  /// Finds the saved progress for a file on a connection.
  Future<PlayProgress?> find(int connectionId, String filePath);

  /// Returns recently played files ordered by lastPlayedAt descending.
  Future<List<PlayProgress>> getRecentlyPlayed({int limit = 20});

  /// Returns the most recently played progress record.
  /// Pure query — no side effects (per-file multi-record model, BUG-11).
  Future<PlayProgress?> findLatest();

  /// Returns all progress records for a specific connection.
  Future<List<PlayProgress>> findByConnection(int connectionId);

  /// Deletes a single progress record.
  Future<void> delete(int connectionId, String filePath);

  /// Deletes all progress records for a given connection.
  Future<void> deleteByConnection(int connectionId);

  /// Returns the total number of progress records.
  Future<int> count();
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

// ── DownloadDao ────────────────────────────────────────────────────────────

/// Abstract interface for the `downloads` table DAO (DL-01-S2).
///
/// Mirrors the ten spec-listed methods plus [findById], which the download
/// manager needs to resolve an entry id (cancel/retry/deleteEntry receive
/// bare ids) back to its stored paths.
abstract class IDownloadDao {
  /// Inserts [record]; on a UNIQUE(connection_id, file_path) hit updates ONLY
  /// status / bytes_downloaded / updated_at (file_name, remote_size,
  /// local_path and created_at keep their first-insert values).
  Future<void> upsert(DownloadRecord record);

  /// Returns the record with [id], or `null` if not found.
  Future<DownloadRecord?> findById(int id);

  /// Returns the record for (connectionId, filePath), or `null`.
  Future<DownloadRecord?> findByLocation(int connectionId, String filePath);

  /// Returns every pending record across all connections, oldest first
  /// (updated_at ASC, id ASC tie-break) — the download pump's discovery
  /// query (DL-01-S5 DB 扫描型泵).
  Future<List<DownloadRecord>> listPending();

  /// Returns local_path when the record is in the done state, else `null`
  /// (INV5: partial downloads never reach the player).
  Future<String?> findDoneLocalPath(int connectionId, String filePath);

  /// Returns all records for [connectionId] ordered by updated_at DESC.
  Future<List<DownloadRecord>> listByConnection(int connectionId);

  /// Writes [bytes] into bytes_downloaded; no-op unless status is downloading.
  Future<void> updateProgress(int id, int bytes);

  /// Generic state transition. When [bytes] is non-null bytes_downloaded is
  /// updated too; when [localPath] is non-null it overwrites local_path.
  /// updated_at is always refreshed.
  Future<void> setStatus(int id, String status,
      {int? bytes, String? localPath});

  /// Deletes the record with [id].
  Future<void> deleteById(int id);

  /// Deletes every record for [connectionId].
  Future<void> deleteByConnection(int connectionId);

  /// Sum of remote_size over done records; empty table yields 0.
  Future<int> totalBytesByConnection(int connectionId);

  /// Moves every pending/downloading record of [connectionId] to failed
  /// (startup orphan recovery, B5-8). done/failed rows are untouched.
  Future<void> markAllNonDoneFailed(int connectionId);
}

/// Thrown when attempting to delete the last remaining connection (CON-T32).
///
/// REF-17-S2 (cr-20260822-2051 D1): definition lifted from
/// `core/database/dao/connection_dao.dart` so feature-layer code catches it via
/// this contract file instead of importing a data-layer implementation file.
/// The DAO re-exports the symbol, so existing imports keep resolving.
class LastConnectionException implements Exception {
  final String message;
  const LastConnectionException(this.message);

  @override
  String toString() => message;
}
