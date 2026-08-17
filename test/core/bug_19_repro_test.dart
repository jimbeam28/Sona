// test/core/bug_19_repro_test.dart
// BUG-19 复现测试（来源：docs/cr/cr-20260816-0806-test-helpers.md F1）
//
// 缺陷：生产 DB 迁移逻辑（database_helper.dart _onUpgrade → _createPlaylistTables）
// 零锚定——
//   * db_migration_test.dart:113-120 内联重实现 _runV1ToV2Upgrade，
//     6 个"迁移用例"断言的其实是内联副本；
//   * test_database.dart:30-78 内联整份 schema（所有 DAO 测试的底座），
//     其中 _createPlaylistTables（:62-78）用裸 CREATE TABLE，
//     而生产 _createPlaylistTables（database_helper.dart:79-102）用
//     CREATE TABLE/INDEX IF NOT EXISTS —— 幂等语义不一致；
//   * 生产 v1→v2 迁移从未经真实 open 路径触发过（BUG-16-S1 走的是版本已为
//     2 的首次安装 onCreate，不触发 onUpgrade）。
// 改坏生产迁移逻辑（如漏建 playlist_tracks 索引、改错 CASCADE），
// 没有任何测试变红。
//
// 本测试修复前 FAIL / 修复后 PASS：
//   Part A（当前 PASS，修复后保留为生产迁移锚定）：经 DatabaseHelper 公开
//   入口（database getter → _openDatabase → openDatabase onUpgrade）驱动
//   真实 v1→v2 迁移，断言 v2 表结构 / 索引 / 数据搬迁 / user_version 推进 /
//   FK+CASCADE / 升级重跑幂等（表已存在时重复 onUpgrade 不抛错）。
//   Part B（当前 FAIL）：openTestDatabase(TestSchema.playlist) 产出的建表 SQL
//   与生产 _createPlaylistTables 的 IF NOT EXISTS 幂等语义不一致——
//   裸 CREATE 在表已存在时重跑抛 DatabaseException。修复（test_database
//   删除内联副本，改经生产 createSchema 建库）后 PASS。
//
//   注：sqlite_master.sql 存储 SQLite 规范化后的 DDL 文本，会剥掉
//   "IF NOT EXISTS" 字面量（sqflite_ffi 实证），故 Part B1 以行为断言
//   （表已存在时 createSchema 重跑不抛错 + FK 文本单源）承载同一意图。

import 'package:flutter_test/flutter_test.dart';
import 'package:nas_audio_player/core/database/database_helper.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../helpers/test_database.dart';

// ── v1 历史 schema（迁移输入，与 db_migration_test.dart:13-43 同构）──────────
// v1 是历史遗留形态，无生产锚点可循；迁移测试重建它是必要输入，不构成漂移面。

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

/// 建一个 version=1 的磁盘库（connections + play_progress + 索引），
/// 并插入一行连接数据作为"升级后数据必须保留"的哨兵。
Future<void> _createV1Database(String path) async {
  final db = await databaseFactoryFfi.openDatabase(path);
  await db.execute('PRAGMA foreign_keys = ON');
  await db.execute(_v1Connections);
  await db.execute(_v1PlayProgress);
  await db.execute(_v1ProgressIndex);
  await db.setVersion(1);
  await db.insert('connections', {
    'name': 'Test NAS',
    'url': 'https://nas.example.com/dav',
    'username': 'admin',
    'password': 'secret',
    'base_path': '/music',
    'is_active': 1,
    'created_at': 0,
    'updated_at': 0,
  });
  await db.close();
}

Future<List<String>> _tableNames(Database db) async {
  final rows = await db.rawQuery(
    "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'",
  );
  return rows.map((r) => r['name'] as String).toList();
}

Future<List<String>> _indexNames(Database db) async {
  final rows = await db.rawQuery(
    "SELECT name FROM sqlite_master WHERE type='index'",
  );
  return rows.map((r) => r['name'] as String).toList();
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    // 生产 DatabaseHelper._openDatabase 用全局 databaseFactory（sqflite 顶层
    // openDatabase / getDatabasesPath），设成 ffi 让真实 open 路径在测试内可跑
    // （同 BUG-16-S1 模式）。
    databaseFactory = databaseFactoryFfi;
  });

  tearDown(() {
    DatabaseHelper.instance.resetForTest();
  });

  // ═════════════════════════════════════════════════════════════════════════
  // Part A：生产真实 v1→v2 迁移（经 DatabaseHelper 公开入口驱动 _onUpgrade）
  // 当前 PASS；修复后保留，作为生产迁移逻辑的锚定测试。
  // ═════════════════════════════════════════════════════════════════════════

  group('BUG-19 Part A: 生产真实 v1→v2 迁移', () {
    test('A1: onUpgrade 真实触发——v2 表/索引/数据搬迁/版本推进/FK+CASCADE 全断言', () async {
      // 镜像 DatabaseHelper._dbName（私有常量）。
      const dbFileName = 'nas_audio_player.db';
      DatabaseHelper.instance.resetForTest();
      final dbPath = p.join(await getDatabasesPath(), dbFileName);
      await deleteDatabase(dbPath); // 卫生：确保裸建 v1 库是干净的

      await _createV1Database(dbPath);

      // 生产 open 路径：v1 文件 + version:2 → sqflite 触发 _onUpgrade(1, 2)
      DatabaseHelper.instance.resetForTest();
      final db = await DatabaseHelper.instance.database;
      addTearDown(db.close);

      // v2 表结构：四表全在
      final tables = await _tableNames(db);
      expect(
          tables,
          containsAll(
              ['connections', 'play_progress', 'playlists', 'playlist_tracks']),
          reason:
              '生产 _onUpgrade → _createPlaylistTables 必须补建 playlists/playlist_tracks');

      // v2 索引：playlist_tracks 依赖索引 + v1 既有索引保留
      final indexes = await _indexNames(db);
      expect(indexes, contains('idx_playlist_tracks_playlist_id'),
          reason: '生产迁移必须创建 playlist_tracks 查询索引（db_migration_test 副本有，生产零锚定）');
      expect(indexes, contains('idx_progress_lookup'),
          reason: 'v1 既有索引不得被迁移破坏');

      // 数据搬迁：v1 连接数据原样保留
      final conns = await db.query('connections');
      expect(conns, hasLength(1), reason: '升级后 connections 数据必须保留');
      expect(conns.first['name'], 'Test NAS');
      expect(conns.first['url'], 'https://nas.example.com/dav');

      // 版本推进：onUpgrade 成功后 sqflite 自动把 user_version 推到 2
      expect(await db.getVersion(), 2,
          reason:
              '生产迁移完成后 user_version 必须为 2（副本 _runV1ToV2Upgrade 手动 setVersion(2) 是同一语义，生产侧由 sqflite 完成）');

      // FK + CASCADE：生产迁移建的 playlist_tracks 必须响应级联删除
      final fk = await db.rawQuery('PRAGMA foreign_keys');
      expect(fk.first.values.first, 1, reason: '生产 open 的 onConfigure 必须置位 FK');
      final pid = await db.insert('playlists', {
        'name': 'BUG-19',
        'created_at': 0,
        'updated_at': 0,
      });
      await db.insert('playlist_tracks', {
        'playlist_id': pid,
        'file_path': '/music/a.mp3',
        'file_name': 'a.mp3',
        'added_at': 0,
      });
      await db.insert('playlist_tracks', {
        'playlist_id': pid,
        'file_path': '/music/b.mp3',
        'file_name': 'b.mp3',
        'added_at': 0,
      });
      await db.delete('playlists', where: 'id = ?', whereArgs: [pid]);
      final orphans =
          await db.rawQuery('SELECT COUNT(*) AS cnt FROM playlist_tracks');
      expect(orphans.first['cnt'], 0,
          reason:
              '生产迁移建的 playlist_tracks 必须带 FK ON DELETE CASCADE（生产 DDL database_helper.dart:95）');
    });

    test('A2: 升级重跑幂等——表已存在时第二次 onUpgrade 不抛错、版本仍推进到 2', () async {
      // 场景：升级中断后重跑（或异常重试），playlists 已存在时 onUpgrade 再执行
      const dbFileName = 'nas_audio_player.db';
      DatabaseHelper.instance.resetForTest();
      final dbPath = p.join(await getDatabasesPath(), dbFileName);
      await deleteDatabase(dbPath);

      await _createV1Database(dbPath);
      DatabaseHelper.instance.resetForTest();
      final db = await DatabaseHelper.instance.database;
      addTearDown(db.close);

      // 把版本回拨到 1，模拟"迁移已建表但版本未提交"的中断现场
      await db.setVersion(1);
      await db.close();
      DatabaseHelper.instance.resetForTest();

      // 第二次生产 open → 再次触发 _onUpgrade → _createPlaylistTables 对已存在
      // 的表重跑。生产 DDL 用 CREATE TABLE IF NOT EXISTS（database_helper.dart:
      // 81/89/99），此处不得抛 DatabaseException。
      final db2 = await DatabaseHelper.instance.database;
      addTearDown(db2.close);

      expect(await db2.getVersion(), 2, reason: '重跑后版本必须仍推进到 2');
      final tables = await _tableNames(db2);
      expect(tables, containsAll(['playlists', 'playlist_tracks']),
          reason: '重跑后两张播放单表仍存在');
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  // Part B：test_database 内联副本与生产迁移不一致（当前 FAIL 项）
  // 修复（test_database.dart 删除内联 DDL 副本、改经生产 createSchema 建库）
  // 后 PASS。
  // ═════════════════════════════════════════════════════════════════════════

  group('BUG-19 Part B: test_database 副本须与生产迁移幂等语义一致', () {
    test(
        'B1: openTestDatabase(playlist) 经生产 createSchema 建库——表已存在重跑幂等'
        '（IF NOT EXISTS 语义，不再内联 DDL 副本）', () async {
      final db = await openTestDatabase(TestSchema.playlist);
      addTearDown(db.close);

      // 幂等语义：生产 _createPlaylistTables 为 CREATE TABLE/INDEX IF NOT
      // EXISTS —— 表已存在时重跑不抛错；test_database.dart 原内联副本是裸
      // CREATE，二次执行抛 DatabaseException（cr-20260816-0806 F1）。
      // sqlite_master.sql 存规范化文本、不保留 IF NOT EXISTS（sqflite_ffi
      // 实证），故 3 处文本断言改行为断言承接同一意图。
      await expectLater(DatabaseHelper.instance.createSchema(db), completes,
          reason: '表已存在时重跑 createSchema 不得抛错——生产 IF NOT EXISTS '
              '幂等语义；裸 CREATE 内联副本会在第二次执行时抛 '
              'DatabaseException（schema 双份手工同步的漂移面）');

      // 单一权威：表结构 SQL 文本带生产 DDL 的 FK+CASCADE 子句，证明建表
      // 来源是生产 database_helper.dart:89-97 的原文而非测试内联副本。
      final tracks = await db.rawQuery(
          "SELECT sql FROM sqlite_master WHERE type='table' AND name='playlist_tracks'");
      expect(tracks, isNotEmpty);
      expect(
          tracks.first['sql'] as String,
          contains('FOREIGN KEY(playlist_id) REFERENCES playlists(id) '
              'ON DELETE CASCADE'),
          reason: 'playlist_tracks 必须由生产 DDL 原文建出（FK + CASCADE 是'
              'playlist 删除级联的关键约束，测试底座不得漂移）');
    });
  });
}
