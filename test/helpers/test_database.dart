// test/helpers/test_database.dart
// Shared database initialization for tests (REF-03).
//
// Merged from con_03_test.dart, con_04_test.dart, con_05_test.dart,
// con_06_test.dart, con_09_test.dart, prg_test.dart, ply_10_test.dart,
// ply_11_test.dart.
//
// Schema 由生产 DatabaseHelper.createSchema（database_helper.dart _onCreate）
// 单一来源构建（BUG-19），本文件不声明任何 CREATE 语句。

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
/// The full production v2 schema is built once via
/// [DatabaseHelper.instance.createSchema] (BUG-19: single authoritative DDL
/// source — no inline copy lives here), then tables outside the requested
/// subset are dropped. Drop order obeys FK dependencies (playlist_tracks
/// before playlists; play_progress before connections); indexes drop with
/// their tables automatically.
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

  // 生产 v2 schema（database_helper.dart _onCreate）——单一权威来源
  // （BUG-19：修复前内联 DDL 副本与生产双份手工同步，无比对机制）。
  await DatabaseHelper.instance.createSchema(db);

  // 子集语义：DROP 掉不属于本 schema 的表。顺序必须满足 FK 依赖
  // （playlist_tracks 先于 playlists；play_progress 先于 connections），
  // 索引随表自动删除。
  switch (schema) {
    case TestSchema.connections:
      await db.execute('DROP TABLE IF EXISTS playlist_tracks');
      await db.execute('DROP TABLE IF EXISTS playlists');
      await db.execute('DROP TABLE IF EXISTS play_progress');
      break;
    case TestSchema.progress:
      await db.execute('DROP TABLE IF EXISTS playlist_tracks');
      await db.execute('DROP TABLE IF EXISTS playlists');
      break;
    case TestSchema.playlist:
      await db.execute('DROP TABLE IF EXISTS play_progress');
      await db.execute('DROP TABLE IF EXISTS connections');
      break;
    case TestSchema.full:
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
