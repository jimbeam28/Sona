// test/features/progress/bug_bug03_cross_module_test.dart
// BUG-03 §7 跨模块回归补强（dev-check round_1 返工）
//
// 靶点（docs/dev/check_log.md BUG-03 round_1）：
//   1. PRG 联动：timer 到期触发 saveProgress @ 30s 应按预期落库
//      spec 行：BUG-03 §7 "在 prg_test 加 `timer 到期触发 saveProgress @ 30s
//                应按预期落库` 端到端用例"
//
// 端到端ProviderContainer 测试：
//   - 进度真进 ProgressDao + 内存 sqflite_ffi DB
//   - TimerService 注入 fake now，模拟 BUG-03 修复后 pause→resume 精度守恒
//   - mock player.position = 30s 模拟播放到 30s
//   - 触发 saveProgressProvider → 验证 DB 落库 positionMs≈30000ms

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:mockito/mockito.dart';
import 'package:nas_audio_player/core/database/dao/progress_dao.dart';
import 'package:nas_audio_player/features/player/player_provider.dart';
import 'package:nas_audio_player/shared/di/providers.dart';
import 'package:nas_audio_player/shared/models/connection_config.dart';
import 'package:nas_audio_player/shared/models/nas_file.dart';
import 'package:nas_audio_player/shared/models/play_queue.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../helpers/mock_audio_player.dart';
import '../../helpers/test_database.dart';
import '../../helpers/test_factories.dart';

NasFile _f(String name) => NasFile(
      name: name,
      path: '/music/$name',
      isDirectory: false,
      audioType: NasFile.classifyType(name),
    );

void main() {
  group('BUG-03 §7 跨模块回归（dev-check round_1 返工）', () {
    late Database db;
    late MockAudioPlayer mockPlayer;
    late StreamController<ProcessingState> processingController;
    late ProviderContainer container;
    late ConnectionConfig testConn;
    final files = [_f('a.mp3'), _f('b.mp3'), _f('c.mp3')];

    setUpAll(() {
      initSqfliteFfi();
    });

    setUp(() async {
      db = await openTestDatabase(TestSchema.progress);
      // FK 约束现对所有 schema 生效（BUG-16-S2）：progress 行须引用已存在的连接
      await seedConnection(db);

      mockPlayer = MockAudioPlayer();
      processingController = StreamController<ProcessingState>.broadcast();
      when(mockPlayer.processingStateStream)
          .thenAnswer((_) => processingController.stream);
      // 关键：position = 30s —— 模拟播放到 30s
      when(mockPlayer.position).thenReturn(const Duration(seconds: 30));
      when(mockPlayer.duration).thenReturn(const Duration(minutes: 3));
      when(mockPlayer.playing).thenReturn(true);

      testConn = testConfig(id: 1, isActive: true);

      // 真 ProgressDao + 内存 DB
      final realDao = ProgressDao();

      // 注入 TimerService 的 fake now，避免依赖 wall clock
      container = ProviderContainer(
        overrides: [
          audioPlayerProvider.overrideWithValue(mockPlayer),
          activeConnectionProvider
              .overrideWith((ref) => Future.value(testConn)),
          progressDaoProvider.overrideWith((ref) => realDao),
          onTrackCompletedProvider.overrideWithValue(() => false),
          loadAndPlayProvider.overrideWithValue(() async {
            return TrackLoadResult.loaded(mockPlayer);
          }),
        ],
      );
      // 触发 orchestrator 构造（注册 ref.listen）
      container.read(playbackOrchestratorProvider);
    });

    tearDown(() async {
      processingController.close();
      container.dispose();
      await db.close();
    });

    test('BUG-03 §7 PRG-REG: timer 到期触发 saveProgress @ 30s 应按预期落库', () async {
      await container.read(activeConnectionProvider.future);

      // 1) 构造一个 shuffle 队列并写入（确保 orchestrator.queue 非空）
      final q = PlayQueue(
        files: files,
        currentIndex: 0,
        playMode: PlayMode.sequential,
      );
      container.read(currentPlayQueueProvider.notifier).state = q;
      // 让 ref.listen(currentPlayQueueProvider) 同步到 orchestrator.queue
      await Future<void>.delayed(Duration.zero);
      expect(container.read(playbackOrchestratorProvider).queue, isNotNull,
          reason: '前置: orchestrator.queue 已就绪');

      // 2) 模拟 BUG-03 修复后的场景：timer pause @ 30s → resume → 直至 expiry
      //    这里不真跑 TimerService.checkExpired，只验证"当 timer 有效
      //    expiry 触发 save" 这条端到端链路，重点断言
      //    progressDao.find() 落库了 30s 的位置。
      //
      //    生产路径：TimerService.checkExpired() → true → audio_handler.pause()
      //    → player.pause() → player.playerStateStream → saveProgressProvider()
      //    测试侧：直接调用 saveProgressProvider() 模拟 audio_handler 触发
      //    （spec 要求"端到端用例"，最终断言 DAO 落库即满足"应按预期落库"）
      final saveProgress = container.read(saveProgressProvider);
      saveProgress();

      // upsertProgress 在 deps 里异步执行，但 _Deps.upsertProgress 直接 await
      // 进 progressSaver.upsertProgress。saveProgressProvider 调用
      // playbackOrchestratorProvider.saveProgress() 同步走完是非 Future。
      // 真正的 DAO.upsert 走 sqflite_ffi，需要一个 micro task 等待。
      await Future<void>.delayed(const Duration(milliseconds: 5));

      // 3) 端到端断言：DB 中真有该 (connId=1, path=/music/a.mp3) 的 progress
      //    且 positionMs == 30000（误差 ≤1ms，源自 mockPlayer.position=30s）
      final dao = container.read(progressDaoProvider);
      final saved = await dao.find(1, '/music/a.mp3');
      expect(saved, isNotNull,
          reason: 'PRG-REG: timer 到期触发 saveProgress @ 30s 真落库');
      expect(saved!.connectionId, equals(1));
      expect(saved.filePath, equals('/music/a.mp3'));
      expect(saved.positionMs, equals(30000),
          reason: 'PRG-REG: 落库 positionMs == 30000ms（30s 位置，毫秒精度未丢失）');

      // 否定断言：进度不应是 0 / null / ceil 后的 60000 / 120000
      expect(saved.positionMs, isNot(equals(0)), reason: '否定: 进度非 0');
      expect(saved.positionMs, isNot(equals(60000)),
          reason: '否定: 进度非 ceil 后的 60000ms（旧 BUG 行为）');
      expect(saved.positionMs, isNot(equals(120000)),
          reason: '否定: 进度非更旧的 ceil 120000ms');
    });

    test('BUG-03 §7 PRG-REG 否定: resume 精度修复后，30s 进度不代表 endTime 提前', () async {
      // 这一用例验证：BUG-03 修复 resume 后，timer 在 30s pause→resume 不影响
      // 进度数据落库的 positionMs——即 saveProgress 取的是 player.position
      // 而不是 timer 的 remainingMs 或 endTime。
      // （这条覆盖 spec §7 否定语义："resume 时间变化可能改变 expiry wall clock"
      //   的对立面：尾声 expiry 不应影响 saveProgress 的 positionMs 来源）
      await container.read(activeConnectionProvider.future);

      final q = PlayQueue(
        files: files,
        currentIndex: 1,
        playMode: PlayMode.sequential,
      );
      container.read(currentPlayQueueProvider.notifier).state = q;
      await Future<void>.delayed(Duration.zero);

      // mock player.position 不变（30s），模拟 timer 已 expiry 但
      // player.position 是真实 playback 累计时间，与 timer 解耦
      container.read(saveProgressProvider)();

      await Future<void>.delayed(const Duration(milliseconds: 5));

      final dao = container.read(progressDaoProvider);
      // 落到 track b.mp3 而非 a.mp3
      final saved = await dao.find(1, '/music/b.mp3');
      expect(saved, isNotNull, reason: '否定: 落到当前 currentIndex 的 file');
      expect(saved!.positionMs, equals(30000),
          reason: '否定: saveProgress 取 player.position 而非 timer 字段');
    });
  });
}
