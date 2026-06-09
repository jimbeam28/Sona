// test/helpers/test_database.dart
// Shared database initialization for tests (REF-03).
//
// Merged from con_03_test.dart, con_04_test.dart, con_05_test.dart,
// con_06_test.dart, con_09_test.dart, prg_test.dart, ply_10_test.dart,
// ply_11_test.dart.

import 'package:nas_audio_player/core/database/database_helper.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Schema subsets that tests may select when opening a test database.
enum TestSchema {
  /// Only the `connections` table.
  connections,

  /// Only the `play_progress` table (plus connections as FK target).
  progress,

  /// Only the `playlists` and `playlist_tracks` tables.
  playlist,

  /// All tables: connections, play_progress, playlists, playlist_tracks.
  full,
}

/// SQL fragments for each logical schema unit.

const _createConnectionsTable = '''
  CREATE TABLE connections (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    name        TEXT NOT NULL,
    url         TEXT NOT NULL,
    username    TEXT NOT NULL,
    password    TEXT NOT NULL,
    base_path   TEXT NOT NULL DEFAULT '/',
    is_active   INTEGER NOT NULL DEFAULT 0,
    created_at  INTEGER NOT NULL,
    updated_at  INTEGER NOT NULL
  )
''';

const _createPlayProgressTable = '''
  CREATE TABLE play_progress (
    id             INTEGER PRIMARY KEY AUTOINCREMENT,
    connection_id  INTEGER NOT NULL,
    file_path      TEXT NOT NULL,
    position_ms    INTEGER NOT NULL DEFAULT 0,
    duration_ms    INTEGER,
    last_played_at INTEGER NOT NULL,
    UNIQUE(connection_id, file_path),
    FOREIGN KEY(connection_id) REFERENCES connections(id) ON DELETE CASCADE
  )
''';

const _createProgressIndex = '''
  CREATE INDEX idx_progress_lookup
  ON play_progress(connection_id, file_path)
''';

const _createPlaylistTables = '''
  CREATE TABLE playlists (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL,
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL
  );
  CREATE TABLE playlist_tracks (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    playlist_id INTEGER NOT NULL,
    file_path TEXT NOT NULL,
    file_name TEXT NOT NULL,
    added_at INTEGER NOT NULL,
    FOREIGN KEY(playlist_id) REFERENCES playlists(id) ON DELETE CASCADE
  );
  CREATE INDEX idx_playlist_tracks_playlist_id ON playlist_tracks(playlist_id)
''';

/// Initializes `sqflite_ffi`. Call once in `setUpAll`.
void initSqfliteFfi() {
  sqfliteFfiInit();
}

/// Opens a fresh in-memory database with the requested [schema], injects it
/// into [DatabaseHelper], and returns the handle so the test can close it.
///
/// [TestSchema.connections] — connections table only.
/// [TestSchema.progress] — connections + play_progress + index.
/// [TestSchema.playlist] — playlists + playlist_tracks + index, with FK pragma.
/// [TestSchema.full] — all of the above.
Future<Database> openTestDatabase(TestSchema schema) async {
  final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);

  switch (schema) {
    case TestSchema.connections:
      await db.execute(_createConnectionsTable);
      break;

    case TestSchema.progress:
      await db.execute(_createConnectionsTable);
      await db.execute(_createPlayProgressTable);
      await db.execute(_createProgressIndex);
      break;

    case TestSchema.playlist:
      await db.execute('PRAGMA foreign_keys = ON');
      await db.execute(_createPlaylistTables);
      break;

    case TestSchema.full:
      await db.execute('PRAGMA foreign_keys = ON');
      await db.execute(_createConnectionsTable);
      await db.execute(_createPlayProgressTable);
      await db.execute(_createProgressIndex);
      await db.execute(_createPlaylistTables);
      break;
  }

  DatabaseHelper.instance.overrideDatabase(db);
  return db;
}
