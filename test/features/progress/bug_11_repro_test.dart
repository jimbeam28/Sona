// test/features/progress/bug_11_repro_test.dart
// BUG-11 复现测试（来源：docs/cr/cr-20260724-0110.md PRG2 = DB1 = CTR1）
//
// 缺陷：findLatest()（progress_dao.dart:168-173）每次查询先调
// migrateLegacyToLatest()（:75-91）按 last_played_at DESC 保留一条、
// 物理 DELETE 其余全部。启动链 onboarding.dart:65 → player_provider.dart:168
// → progress_provider.dart:59-62 → dao.findLatest()，每次重启销毁所有
// 非最近一首的进度记录。而写入路径是按文件多行模型（upsert，键
// UNIQUE(connection_id,file_path)）——两套模型混用。
//
// 用户裁决（2026-07-24）：play_progress 归属【按文件多记录模型】。
// 修复方向：findLatest 改纯查询（无删除副作用）；
// migrateLegacyToLatest / upsertLatest / clearLatest 死代码删除。
//
// 修复前：本测试 FAIL（A 的进度被 findLatest 物理删除）。
// 修复后：本测试 PASS（多文件进度共存，findLatest 是纯查询）。

import 'package:flutter_test/flutter_test.dart';
import 'package:nas_audio_player/core/database/dao/progress_dao.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../helpers/test_database.dart';

void main() {
  late Database db;
  late ProgressDao dao;

  setUpAll(initSqfliteFfi);

  setUp(() async {
    db = await openTestDatabase(TestSchema.progress);
    dao = ProgressDao();
  });

  tearDown(() async {
    await db.close();
  });

  group('BUG-11: findLatest 不得删除其它文件的进度（PRG2/DB1 复现）', () {
    test('多文件进度写入 → 启动恢复 findLatest → 历史文件进度存活', () async {
      // 有声书典型场景：两本书各播一段，两条按文件记录并存
      await dao.upsert(
        connectionId: 1,
        filePath: '/audiobooks/book_A/chapter_01.mp3',
        positionMs: 30000,
        durationMs: 600000,
      );
      await dao.upsert(
        connectionId: 1,
        filePath: '/audiobooks/book_B/chapter_07.mp3',
        positionMs: 60000,
        durationMs: 900000,
      );
      expect(await dao.count(), 2, reason: '前置条件：两条按文件记录并存');

      // 模拟启动恢复路径（onboarding → restoreStartupProgressProvider
      // → latestPlayedProgressProvider → dao.findLatest()）
      final latest = await dao.findLatest();
      expect(latest, isNotNull, reason: '应返回最近播放记录');

      // 按文件多记录模型（用户裁决）：查询不得有删除副作用
      final a = await dao.find(1, '/audiobooks/book_A/chapter_01.mp3');
      expect(a, isNotNull,
          reason: '启动恢复后 book_A 的进度必须存活——'
              'BUG-11：migrateLegacyToLatest 把除最近一首外的记录全部物理删除');
      expect(a!.positionMs, 30000);
      expect(await dao.count(), 2, reason: 'findLatest 应为纯查询，不得产生删除副作用');
    });

    test('会话内保存后 read latest 不销毁其它记录（次级销毁路径）', () async {
      await dao.upsert(
        connectionId: 1,
        filePath: '/music/a.mp3',
        positionMs: 30000,
        durationMs: 300000,
      );
      await dao.upsert(
        connectionId: 1,
        filePath: '/music/b.mp3',
        positionMs: 45000,
        durationMs: 300000,
      );

      // upsertProgressProvider 每次保存 invalidate latestPlayedProgressProvider
      // （progress_provider.dart:102），会话内后续 read 同样触发 findLatest
      await dao.findLatest();
      await dao.findLatest();

      expect(await dao.find(1, '/music/a.mp3'), isNotNull,
          reason: '反复 read findLatest 不得累积删除（次级销毁路径）');
      expect(await dao.count(), 2);
    });
  });
}
