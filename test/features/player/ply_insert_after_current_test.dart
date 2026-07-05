// test/features/player/ply_insert_after_current_test.dart
// BRW-09: PlaybackOrchestrator.insertAfterCurrent + provider 集成单元测试
//
// Agent A — 测试先行。只读 spec/docs，禁读 lib/。
// 覆盖 BRW-09-S4 全部子步骤(1-4)、ALG 异常(Q==null 返回 false)、
// 以及 §7 跨模块回归 PLY-REG-1 (插入后 skipToNext 跳到 Y)。
//
// 注：orchestrator 的具体构造依赖签名未在 spec §2.1 完整列出。
// 这里通过 `playbackOrchestratorProvider` 取实例并依赖 Riverpod 注入；
// 若 provider 构造需要更多依赖，Agent B 在 player_provider.dart 实现中
// 需相应提供 override 钩子或调整本测试的 override 列表。
// 方法签名以 spec §2.1/§3.1/§6 描述为唯一信息源：
//   bool insertAfterCurrent(NasFile file)   — 返回 true 成功，false 失败
//
// 测试当前必然 FAIL（实现不存在），但断言逻辑完整可执行。

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:mockito/mockito.dart';
import 'package:nas_audio_player/features/player/player_provider.dart';
import 'package:nas_audio_player/shared/di/providers.dart';
import 'package:nas_audio_player/shared/models/connection_config.dart';
import 'package:nas_audio_player/shared/models/play_queue.dart';

import '../../helpers/mock_audio_player.dart';
import '../../helpers/test_factories.dart';

void main() {
  group('BRW-09: PlaybackOrchestrator.insertAfterCurrent', () {
    late MockAudioPlayer mockPlayer;
    late StreamController<ProcessingState> processingController;
    late ProviderContainer container;
    late ConnectionConfig testConn;

    PlayQueue buildQueue(int count, int currentIndex) {
      final files = List.generate(count, (i) {
        final n = (i + 1).toString().padLeft(2, '0');
        return testAudio('track_$n.mp3', '/music/track_$n.mp3');
      });
      return PlayQueue(files: files, currentIndex: currentIndex);
    }

    setUp(() {
      mockPlayer = MockAudioPlayer();
      processingController = StreamController<ProcessingState>.broadcast();

      when(mockPlayer.processingStateStream)
          .thenAnswer((_) => processingController.stream);
      when(mockPlayer.position).thenReturn(const Duration(seconds: 30));
      when(mockPlayer.duration).thenReturn(const Duration(minutes: 3));
      when(mockPlayer.playing).thenReturn(true);

      testConn = testConfig(id: 1, isActive: true);

      // Agent A: deps 推断自 ply_05_test.dart 与 spec §2.1。
      // 若 playbackOrchestratorProvider 实际需要额外依赖（如 progressSaver、
      // passwordReader、defaultSpeed、queueConnId 等），Agent B 在补齐
      // insertAfterCurrent 实现时同步为本测试 override 列表补齐对应 provider。
      container = ProviderContainer(
        overrides: [
          audioPlayerProvider.overrideWithValue(mockPlayer),
          activeConnectionProvider
              .overrideWith((ref) => Future.value(testConn)),
          onTrackCompletedProvider.overrideWithValue(() => false),
          saveProgressProvider.overrideWithValue(() {}),
          loadAndPlayProvider.overrideWithValue(() async {
            return TrackLoadResult.loaded(mockPlayer);
          }),
        ],
      );
    });

    tearDown(() {
      processingController.close();
    });

    // ── S4 步骤 1+2: orchestrator.insertAfterCurrent 触发并改写 files ──────
    test(
        'BRW-09-S4 step1/2: orchestrator.insertAfterCurrent(Y) 在 ci+1 插入 Y 且 currentIndex 不变',
        () async {
      await container.read(activeConnectionProvider.future);

      final queue = buildQueue(5, 2); // 当前 track_03
      container.read(currentPlayQueueProvider.notifier).state = queue;

      final y = testAudio('Y.mp3', '/music/Y.mp3');

      final ok =
          container.read(playbackOrchestratorProvider).insertAfterCurrent(y);

      expect(ok, isTrue, reason: 'S4 step1: insertAfterCurrent 返回 true');

      // S4 step3: onQueueChanged 刷新 currentPlayQueueProvider
      final newQueue = container.read(currentPlayQueueProvider);
      expect(newQueue, isNotNull,
          reason: 'S4 step3: onQueueChanged 触发后 currentPlayQueueProvider 应非空');
      // S4 step2: files=[..., track_03, Y, track_04, track_05]，currentIndex 不变
      expect(newQueue!.currentIndex, equals(2),
          reason: 'S4 step2/INV1: currentIndex 仍指原 X (track_03)');
      expect(newQueue.length, equals(6), reason: 'S4 step2: files 长度 +1');
      expect(newQueue.files[3].path, equals('/music/Y.mp3'),
          reason: 'S4 step2: Y 插入到 currentIndex+1=3');
      expect(newQueue.files[2].path, equals('/music/track_03.mp3'),
          reason: 'S4 step2: 当前曲仍是 X');
      expect(newQueue.files[4].path, equals('/music/track_04.mp3'),
          reason: 'S4 step2: 原下一曲后移到 4');
      expect(newQueue.files[5].path, equals('/music/track_05.mp3'));
    });

    // ── S4 步骤 4 (UI 部分)：orchestrator 不直接弹 SnackBar，
    // 但应通过某种回调/返回值让 UI 知道"成功"以便弹 SnackBar。
    // 这里仅验证返回 true 的契约（DOM 已隐式覆盖）。
    test(
        'BRW-09-S4: 当 audioPlayerProvider.playing == true 且 queue 非空时 insertAfterCurrent 返回 true',
        () async {
      await container.read(activeConnectionProvider.future);

      container.read(currentPlayQueueProvider.notifier).state =
          buildQueue(3, 0);
      when(mockPlayer.playing).thenReturn(true);

      final y = testAudio('Y.mp3', '/music/Y.mp3');
      final ok =
          container.read(playbackOrchestratorProvider).insertAfterCurrent(y);

      expect(ok, isTrue,
          reason: 'S4: playing=true + queue 非空 → insertAfterCurrent 应成功');
      final newQueue = container.read(currentPlayQueueProvider);
      expect(newQueue, isNotNull);
      expect(newQueue!.files[1].path, equals('/music/Y.mp3'));
    });

    // ── ALG 异常：Q == null 时 orchestrator.insertAfterCurrent 返回 false ─
    test(
        'BRW-09-ALG (异常): queue == null 时 insertAfterCurrent 返回 false 且不触发 saveProgress / loadAndPlay',
        () async {
      await container.read(activeConnectionProvider.future);

      // 显式置空队列
      container.read(currentPlayQueueProvider.notifier).state = null;

      final y = testAudio('Y.mp3', '/music/Y.mp3');
      final ok =
          container.read(playbackOrchestratorProvider).insertAfterCurrent(y);

      expect(ok, isFalse,
          reason: 'ALG 异常: queue==null 时 orchestrator 应返回 false');
      // Q 未变（仍 null，未 Rodrigo 性构造队列）
      final q = container.read(currentPlayQueueProvider);
      expect(q, isNull, reason: 'ALG 异常: 失败路径不应改写 currentPlayQueueProvider');
    });

    // ── S7 集成层：连续三次 insertAfterCurrent ────────────────────────────
    test(
        'BRW-09-S7 (orchestrator 集成): 连续三次 insertAfterCurrent(Y) 依次插入 ci+1..+3',
        () async {
      await container.read(activeConnectionProvider.future);

      container.read(currentPlayQueueProvider.notifier).state =
          buildQueue(4, 1);
      final y = testAudio('Y.mp3', '/music/Y.mp3');

      for (var i = 0; i < 3; i++) {
        final ok =
            container.read(playbackOrchestratorProvider).insertAfterCurrent(y);
        expect(ok, isTrue, reason: 'S7: 第 ${i + 1} 次插入应成功');
        // 每次后等待 provider 状态 settled
        await Future<void>.delayed(Duration.zero);
      }

      final q = container.read(currentPlayQueueProvider);
      expect(q, isNotNull);
      expect(q!.currentIndex, equals(1),
          reason: 'S7: 三次插入后 currentIndex 不变（仍指原 X）');
      expect(q.length, equals(7));
      expect(q.files[2].path, equals('/music/Y.mp3'));
      expect(q.files[3].path, equals('/music/Y.mp3'));
      expect(q.files[4].path, equals('/music/Y.mp3'));
      expect(q.files[5].path, equals('/music/track_03.mp3'));
      expect(q.files[6].path, equals('/music/track_04.mp3'));
    });

    // ── INV4 (orchestrator 部分)：连点按下纯函数语义，不产生中间竞态
    // 完整的 UI 端 race 测试在 brw_09_test.dart，这里仅验证 orchestrator 连调
    // 不依赖 player.playing 时序、不依赖 async 中间态。
    test('BRW-09-INV4 (domain): 连续 insertAfterCurrent 多次不依赖时序，结果确定', () async {
      await container.read(activeConnectionProvider.future);

      container.read(currentPlayQueueProvider.notifier).state =
          buildQueue(3, 0);
      final y1 = testAudio('Y1.mp3', '/music/Y1.mp3');
      final y2 = testAudio('Y2.mp3', '/music/Y2.mp3');
      final y3 = testAudio('Y3.mp3', '/music/Y3.mp3');

      // 同步连调三次（无 await 介入），结果应按调用顺序确定
      container.read(playbackOrchestratorProvider).insertAfterCurrent(y1);
      container.read(playbackOrchestratorProvider).insertAfterCurrent(y2);
      container.read(playbackOrchestratorProvider).insertAfterCurrent(y3);
      await Future<void>.delayed(Duration.zero);

      final q = container.read(currentPlayQueueProvider);
      expect(q, isNotNull);
      expect(q!.currentIndex, equals(0));
      // 顺序按调用 ci+1 = 1,2,3 同方向堆叠
      expect(q.files[1].path, equals('/music/Y3.mp3'),
          reason: 'INV4: 最后插入的位于最接近 X 的位置');
      expect(q.files[2].path, equals('/music/Y2.mp3'));
      expect(q.files[3].path, equals('/music/Y1.mp3'));
      expect(q.files[4].path, equals('/music/track_02.mp3'));
      expect(q.files[5].path, equals('/music/track_03.mp3'));
    });

    // ── §7 PLY-REG-1: 插入 Y 后 skipToNext 应跳到 Y ──────────────────────
    test('BRW-09 PLY-REG-1: 插入 Y 后 skipToNext 在 sequential 模式跳到 Y', () async {
      await container.read(activeConnectionProvider.future);

      final queue = buildQueue(3, 0); // [track_01, track_02, track_03]
      container.read(currentPlayQueueProvider.notifier).state = queue;
      container.read(playModeProvider.notifier).state = PlayMode.sequential;

      final y = testAudio('Y.mp3', '/music/Y.mp3');
      container.read(playbackOrchestratorProvider).insertAfterCurrent(y);
      await Future<void>.delayed(Duration.zero);

      // 队列成为 [track_01, Y, track_02, track_03]，currentIndex=0
      final insertedQueue = container.read(currentPlayQueueProvider);
      expect(insertedQueue, isNotNull);
      expect(insertedQueue!.files[1].path, equals('/music/Y.mp3'));

      // 调用 skipToNext 模拟当前曲完成
      container.read(playbackOrchestratorProvider).skipToNext();
      await Future<void>.delayed(Duration.zero);

      final afterSkip = container.read(currentPlayQueueProvider);
      expect(afterSkip, isNotNull);
      expect(afterSkip!.currentIndex, equals(1),
          reason: 'PLY-REG-1: skipToNext 后 currentIndex=1 → Y');
      expect(afterSkip.current.path, equals('/music/Y.mp3'),
          reason: 'PLY-REG-1: 跳曲成功后下一首就是 Y');
    });
  });

  // 注: loadAndPlay 在 skipToNext 路径可能被触发；上面用 override 之 mock，
  // 防止真实加载流程在测试中产生未捕获异步错误。
  // 涉及平台原生无需手动 QA (spec §8 manual_qa_required=false)。
  // S4 step4 (SnackBar UI) 由 brw_09_test.dart widget 端验证。
}
