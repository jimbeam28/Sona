// test/features/coverage/db_migration_test.dart
// TREF-06: DatabaseHelper migration specialist test suite
//
// Tests schema creation and migration using sqflite_ffi. v1 schema is
// rebuilt locally (historical input); v2 schema and the v1→v2 upgrade are
// driven through the real DatabaseHelper open path (BUG-19).

import 'package:flutter_test/flutter_test.dart';
import 'package:nas_audio_player/core/database/database_helper.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../helpers/test_database.dart';

// ── SQL fragments ─────────────────────────────────────────────────────────────

// v1 是历史遗留形态（迁移输入），重建它是迁移测试的必要输入，
// 不构成漂移面（BUG-19：生产迁移逻辑才是权威，v1 无生产锚点可循）。

const _v1Connections = '''
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

const _v1PlayProgress = '''
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

const _v1ProgressIndex = '''
  CREATE INDEX idx_progress_lookup
  ON play_progress(connection_id, file_path)
''';

// ── Helpers ───────────────────────────────────────────────────────────────────

/// Build a v1 schema (connections + play_progress only, no playlists).
Future<Database> _openV1Database() async {
  final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
  await db.execute('PRAGMA foreign_keys = ON');
  await db.execute(_v1Connections);
  await db.execute(_v1PlayProgress);
  await db.execute(_v1ProgressIndex);
  await db.setVersion(1);
  return db;
}

/// 建一个 version=1 的磁盘库（connections + play_progress + 索引），并插入
/// 一行连接作为"升级后数据必须保留"的哨兵。返回插入行 id（DB-MIG-03 断言用）。
Future<int> _createV1DatabaseWithSentinel(String path) async {
  final db = await databaseFactoryFfi.openDatabase(path);
  await db.execute('PRAGMA foreign_keys = ON');
  await db.execute(_v1Connections);
  await db.execute(_v1PlayProgress);
  await db.execute(_v1ProgressIndex);
  await db.setVersion(1);

  final now = DateTime.now().millisecondsSinceEpoch;
  final connId = await db.insert('connections', {
    'name': 'Test NAS',
    'url': 'https://nas.example.com/dav',
    'username': 'admin',
    'password': 'secret',
    'base_path': '/music',
    'is_active': 1,
    'created_at': now,
    'updated_at': now,
  });

  await db.close();
  return connId;
}

/// Return table names from sqlite_master.
Future<List<String>> _tableNames(Database db) async {
  final rows = await db.rawQuery(
    "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'",
  );
  return rows.map((r) => r['name'] as String).toList();
}

/// Return index names from sqlite_master.
Future<List<String>> _indexNames(Database db) async {
  final rows = await db.rawQuery(
    "SELECT name FROM sqlite_master WHERE type='index'",
  );
  return rows.map((r) => r['name'] as String).toList();
}

/// 经 DatabaseHelper 真实 open 路径触发生产 _onUpgrade（BUG-19）：
/// 以 version:2 打开一个 user_version=1 的库文件 → sqflite 调
/// _onUpgrade(1, 2) → _createPlaylistTables。
///
/// 返回迁移完成的库句柄；调用方负责 addTearDown(db.close)。
Future<Database> _runRealV1ToV2Migration() async {
  // 镜像 DatabaseHelper._dbName（私有常量）。
  const dbFileName = 'nas_audio_player.db';
  DatabaseHelper.instance.resetForTest();
  final dbPath = p.join(await getDatabasesPath(), dbFileName);
  await deleteDatabase(dbPath);
  final v1 = await databaseFactoryFfi.openDatabase(dbPath);
  await v1.execute('PRAGMA foreign_keys = ON');
  await v1.execute(_v1Connections);
  await v1.execute(_v1PlayProgress);
  await v1.execute(_v1ProgressIndex);
  await v1.setVersion(1);
  await v1.close();
  DatabaseHelper.instance.resetForTest();
  return DatabaseHelper.instance.database;
}

// ══════════════════════════════════════════════════════════════════════════════
// TREF-06: DatabaseHelper migration tests
// ══════════════════════════════════════════════════════════════════════════════

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    // 磁盘 open 路径（getDatabasesPath / deleteDatabase / DatabaseHelper
    // ._openDatabase）用全局 databaseFactory（同 bug_19_repro_test.dart）。
    databaseFactory = databaseFactoryFfi;
  });

  group('TREF-06 DatabaseHelper migration', () {
    // ── TREF-06-T01 (DB-MIG-01): v1 schema has connections and play_progress,
    //    no playlists tables ──────────────────────────────────────────────────

    test('DB-MIG-01: v1 schema has connections and play_progress, no playlists',
        () async {
      final db = await _openV1Database();
      addTearDown(db.close);

      final tables = await _tableNames(db);

      expect(tables, contains('connections'));
      expect(tables, contains('play_progress'));
      expect(tables, isNot(contains('playlists')));
      expect(tables, isNot(contains('playlist_tracks')));
    });

    // ── TREF-06-T02 (DB-MIG-02): v2 schema has all 4 tables ────────────────

    test('DB-MIG-02: v2 schema has all 4 tables', () async {
      // BUG-19：经生产 DatabaseHelper.createSchema（_onCreate）建库，
      // 不再有内联 v2 DDL 副本。
      final db = await openTestDatabase(TestSchema.full);
      addTearDown(db.close);

      final tables = await _tableNames(db);

      expect(tables, contains('connections'));
      expect(tables, contains('play_progress'));
      expect(tables, contains('playlists'));
      expect(tables, contains('playlist_tracks'));
    });

    // ── TREF-06-T03 (DB-MIG-03): v1->v2 upgrade preserves connections data ─

    test('DB-MIG-03: v1-to-v2 upgrade preserves connections data', () async {
      // BUG-19 内联三步：v1 建库+插哨兵 → resetForTest → 真实 open 触发
      // 生产 _onUpgrade（不再有 _runV1ToV2Upgrade 副本）。
      const dbFileName = 'nas_audio_player.db';
      DatabaseHelper.instance.resetForTest();
      final dbPath = p.join(await getDatabasesPath(), dbFileName);
      await deleteDatabase(dbPath); // 卫生：确保裸建 v1 库是干净的

      final connId = await _createV1DatabaseWithSentinel(dbPath);

      DatabaseHelper.instance.resetForTest();
      final db = await DatabaseHelper.instance.database;
      addTearDown(db.close);

      // Verify data survived the migration.
      final rows = await db.query('connections');
      expect(rows.length, 1);
      expect(rows.first['id'], connId);
      expect(rows.first['name'], 'Test NAS');
      expect(rows.first['url'], 'https://nas.example.com/dav');
      expect(rows.first['username'], 'admin');
      expect(rows.first['password'], 'secret');
      expect(rows.first['base_path'], '/music');
      expect(rows.first['is_active'], 1);
    });

    // ── TREF-06-T04 (DB-MIG-04): v1->v2 upgrade creates playlist index ─────

    test('DB-MIG-04: v1-to-v2 upgrade creates playlist index', () async {
      // BUG-19：真实 open 路径触发生产 _onUpgrade → _createPlaylistTables。
      final db = await _runRealV1ToV2Migration();
      addTearDown(db.close);

      final indexes = await _indexNames(db);
      expect(indexes, contains('idx_playlist_tracks_playlist_id'));
    });

    // ── TREF-06-T05 (DB-MIG-05): v2 fresh install contains all indexes ─────

    test('DB-MIG-05: v2 fresh install contains all indexes', () async {
      // BUG-19：经生产 DatabaseHelper.createSchema（_onCreate）建库。
      final db = await openTestDatabase(TestSchema.full);
      addTearDown(db.close);

      final indexes = await _indexNames(db);

      expect(indexes, contains('idx_progress_lookup'));
      expect(indexes, contains('idx_playlist_tracks_playlist_id'));
    });

    // ── TREF-06-T06 (DB-MIG-06): foreign_keys is enabled on creation ────────

    test('DB-MIG-06: foreign_keys is enabled on creation', () async {
      // PRAGMA 断言与 schema 来源无关；openTestDatabase 的 onConfigure 与
      // 生产 onConfigure 均为 FK=ON（BUG-19）。
      final db = await openTestDatabase(TestSchema.full);
      addTearDown(db.close);

      final result = await db.rawQuery('PRAGMA foreign_keys');
      final fkValue = result.first.values.first;
      // PRAGMA foreign_keys returns 1 when enabled.
      expect(fkValue, 1);
    });
  });
}
