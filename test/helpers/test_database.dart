// test/helpers/test_database.dart
// Shared database initialization for tests (REF-03).
//
// Merged from con_03_test.dart, con_04_test.dart, con_05_test.dart,
// con_06_test.dart, con_09_test.dart, prg_test.dart, ply_10_test.dart,
// ply_11_test.dart.

import 'package:nas_audio_player/core/database/dao/progress_dao.dart';
import 'package:nas_audio_player/core/database/database_helper.dart';
import 'package:nas_audio_player/shared/models/play_progress.dart';
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
/// `PRAGMA foreign_keys = ON` runs in `onConfigure` on every open — the same
/// mechanism as the production [DatabaseHelper] open path (BUG-16-S2). FK
/// enforcement therefore applies to every schema, matching production.
///
/// [TestSchema.connections] — connections table only.
/// [TestSchema.progress] — connections + play_progress + index.
/// [TestSchema.playlist] — playlists + playlist_tracks + index.
/// [TestSchema.full] — all of the above.
Future<Database> openTestDatabase(TestSchema schema) async {
  final db = await databaseFactoryFfi.openDatabase(
    inMemoryDatabasePath,
    options: OpenDatabaseOptions(
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
    ),
  );

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
      await db.execute(_createPlaylistTables);
      break;

    case TestSchema.full:
      await db.execute(_createConnectionsTable);
      await db.execute(_createPlayProgressTable);
      await db.execute(_createProgressIndex);
      await db.execute(_createPlaylistTables);
      break;
  }

  DatabaseHelper.instance.overrideDatabase(db);
  return db;
}

/// Seeds a `connections` row (default id 1) so FK-enforcing schemas
/// (play_progress / playlist_tracks) accept child rows referencing it.
/// Required since BUG-16-S2: FK constraints are now ON in every test schema,
/// matching production.
Future<void> seedConnection(Database db, {int id = 1}) async {
  await db.insert('connections', {
    'id': id,
    'name': 'Test NAS',
    'url': 'http://nas.local:5005',
    'username': 'admin',
    'password': 'pw-ref-key',
    'base_path': '/',
    'is_active': 0,
    'created_at': 0,
    'updated_at': 0,
  });
}

/// 测试播种专用 extension（REF-02-S9 迁移自 IProgressDao.rawInsert）：
/// 直接 INSERT 一行 `play_progress`，使用 [PlayProgress.lastPlayedAt] 的
/// 显式时间戳，不经过 shouldSave/shouldClear 策略与 clock 注入。
extension ProgressDaoTestHelper on ProgressDao {
  Future<void> rawInsertForTest(PlayProgress progress) async {
    final db = await DatabaseHelper.instance.database;
    await db.insert('play_progress', {
      'connection_id': progress.connectionId,
      'file_path': progress.filePath,
      'position_ms': progress.positionMs,
      'duration_ms': progress.durationMs,
      'last_played_at': progress.lastPlayedAt.millisecondsSinceEpoch,
    });
  }
}
