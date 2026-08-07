// test/features/progress/test_09_integration_test.dart
// TEST-09 TG-DB1: 数据库集成测试缺口（docs/features/TEST-09.md）
//
//   S1 多文件 upsert → findLatest → 所有记录存活
//      （桥接 prg_test.dart:284 per-file 与 :516 findLatest 纯查询为端到端流）
//   S2 latestPlayedProgressProvider 端到端：rawInsert 播种 → Provider 返回最新
//      → 其它文件存活（补 bug_bug03_cross_module 未走的 startup restore 路径）
//   S3 测试 helper schema 与生产 schema 一致性（表/列/索引/UNIQUE 约束）

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nas_audio_player/core/database/dao/progress_dao.dart';
import 'package:nas_audio_player/shared/di/providers.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../helpers/test_database.dart';
import '../../helpers/test_factories.dart';

const _pathA = '/music/a.mp3';
const _pathB = '/music/b.mp3';

void main() {
  group('TEST-09 TG-DB1: 数据库集成测试', () {
    late Database db;
    late ProgressDao dao;

    setUpAll(() {
      initSqfliteFfi();
    });

    setUp(() async {
      db = await openTestDatabase(TestSchema.progress);
      dao = ProgressDao();
      // FK 约束现对所有 schema 生效（BUG-16-S2）：progress 行须引用已存在的连接
      await seedConnection(db);
    });

    tearDown(() async {
      await db.close();
    });

    test('TEST-09-S1: 多文件 upsert → findLatest → 所有记录存活', () async {
      // When: 顺序 upsert A 与 B（upsert 内部 lastPlayedAt 取当前时间，
      //       B 晚于 A → 最近播放）
      await dao.upsert(
        connectionId: 1,
        filePath: _pathA,
        positionMs: 15000,
        durationMs: 180000,
      );
      await dao.upsert(
        connectionId: 1,
        filePath: _pathB,
        positionMs: 30000,
        durationMs: 300000,
      );

      // Then: findLatest 返回 B（模拟 startup restore 入口）
      final latest = await dao.findLatest();
      expect(latest, isNotNull, reason: 'findLatest 应返回最近播放的记录');
      expect(latest!.filePath, equals(_pathB));
      expect(latest.positionMs, equals(30000));

      // 前置条件显式断言：B 的 lastPlayedAt 确实晚于 A
      final a = await dao.find(1, _pathA);
      final b = await dao.find(1, _pathB);
      expect(a, isNotNull, reason: 'upsert A 后记录应存在');
      expect(b, isNotNull, reason: 'upsert B 后记录应存在');
      expect(b!.lastPlayedAt.isAfter(a!.lastPlayedAt), isTrue,
          reason: '前置: upsert B 的 lastPlayedAt 应晚于 A（否则 findLatest 无法判定最近）');

      // And: 两文件进度各自存活，findLatest 不剪枝
      expect(a.positionMs, equals(15000));
      expect(b.positionMs, equals(30000));
      expect(await dao.count(), equals(2),
          reason: 'count 不减少（不被 findLatest 或其他查询副作用删除）');

      // 否定断言: upsert B 不覆盖 A 的记录（UPSERT 按 (connection_id, file_path) UNIQUE）
      expect(a.positionMs, isNot(equals(30000)), reason: '否定: B 的写入不得覆盖 A 的进度');
      expect(a.filePath, isNot(equals(_pathB)));
    });

    test('TEST-09-S2: latestPlayedProgressProvider 端到端返回最新且其它文件存活', () async {
      // Given: 通过 DAO rawInsert 写入 A（较早）与 B（较晚）
      await dao.rawInsertForTest(
        testProgress(
          connectionId: 1,
          filePath: _pathA,
          positionMs: 15000,
          durationMs: 180000,
          lastPlayedAt: DateTime(2026, 5, 17, 9, 0),
        ),
      );
      await dao.rawInsertForTest(
        testProgress(
          connectionId: 1,
          filePath: _pathB,
          positionMs: 30000,
          durationMs: 300000,
          lastPlayedAt: DateTime(2026, 5, 17, 10, 0),
        ),
      );

      // 真实 ProgressDao 注入 progressDaoProvider（startup restore 链路）
      final container = ProviderContainer(
        overrides: [
          progressDaoProvider.overrideWithValue(dao),
        ],
      );
      addTearDown(container.dispose);

      // When: 读取 latestPlayedProgressProvider.future
      final latest = await container.read(latestPlayedProgressProvider.future);

      // Then: Provider 返回 B 的进度
      expect(latest, isNotNull,
          reason: '有历史记录时 latestPlayedProgressProvider 应返回非 null');
      expect(latest!.filePath, equals(_pathB));
      expect(latest.positionMs, equals(30000));
      expect(latest.durationMs, equals(300000));

      // And: 读取纯查询无副作用（BUG-11 裁决）——A/B 记录均存活，count 不减少
      expect(await dao.find(1, _pathA), isNotNull,
          reason: '否定断言: Provider 读取不得删除 A 的记录');
      expect(await dao.find(1, _pathB), isNotNull);
      expect(await dao.count(), equals(2),
          reason: '否定断言: Provider 读取不得产生删除副作用');
    });

    test('TEST-09-S3: 测试 helper schema 与生产 schema 一致（表/列/索引/UNIQUE）', () async {
      // Given: 全 schema 测试数据库
      // 注意：sqflite factory 对 ':memory:' 路径在旧连接未关时会复用同一
      // 实例（databaseOpenHelpers 按 path 去重），必须先关掉 setUp 打开的
      // progress-schema DB 再开 full schema，否则 CREATE TABLE 报
      // "table connections already exists"。
      await db.close();
      db = await openTestDatabase(TestSchema.full);

      // Then: 四张表齐全，无多余表
      final tables = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%'",
      );
      final tableNames = tables.map((r) => r['name']).toSet();
      expect(
        tableNames,
        containsAll([
          'connections',
          'play_progress',
          'playlists',
          'playlist_tracks',
        ]),
        reason: '测试 DB 应包含生产 schema 全部四张表',
      );
      expect(tableNames.length, equals(4), reason: '否定断言: 不应有多余的表');

      // Then: play_progress 六列齐全，无多余列
      final cols = await db.rawQuery('PRAGMA table_info(play_progress)');
      final colNames = cols.map((r) => r['name']).toSet();
      expect(
        colNames,
        containsAll([
          'id',
          'connection_id',
          'file_path',
          'position_ms',
          'duration_ms',
          'last_played_at',
        ]),
        reason: 'play_progress 应包含生产 schema 全部 6 列',
      );
      expect(colNames.length, equals(6), reason: '否定断言: 不应有多余的列');

      // Then: idx_progress_lookup 索引存在
      final indexes = await db.rawQuery('PRAGMA index_list(play_progress)');
      expect(
        indexes.map((r) => r['name']),
        contains('idx_progress_lookup'),
        reason: 'play_progress 应包含 idx_progress_lookup 索引',
      );

      // Then: UNIQUE(connection_id, file_path) 约束实际验证
      // （FK 开启，需先有 connection 行）
      await seedConnection(db);
      await dao.rawInsertForTest(
        testProgress(
          connectionId: 1,
          filePath: _pathA,
          positionMs: 15000,
          durationMs: 180000,
        ),
      );
      // 直接重复插入同 (connection_id, file_path) → UNIQUE 约束异常
      await expectLater(
        dao.rawInsertForTest(
          testProgress(
            connectionId: 1,
            filePath: _pathA,
            positionMs: 30000,
            durationMs: 300000,
          ),
        ),
        throwsA(isA<DatabaseException>()),
        reason: 'UNIQUE(connection_id, file_path) 约束应拒绝第二行',
      );
      expect(await dao.count(), equals(1));

      // 重复 upsert 走 ConflictAlgorithm.replace → 仍只一行
      await dao.upsert(
        connectionId: 1,
        filePath: _pathA,
        positionMs: 45000,
        durationMs: 180000,
      );
      expect(await dao.count(), equals(1),
          reason: '重复 upsert 不产生第二行（UPSERT 按 UNIQUE 键替换）');
    });
  });
}
