// test/features/player/bug_03_repro_test.dart
// BUG-03（cr-20260816-0802 B1）：gate 20s 超时异常路径使 _completingProvider
// 永久卡死 → 自动切歌永久失效 + unhandled async error
// （spec: docs/features/BUG-03.md §5.4）
//
// 缺陷链：
//   player_provider.dart:306-325 completed 监听器置 _completingProvider=true
//   后 unawaited(loadAndPlayProvider())（:324）；
//   loadAndPlayProvider（:341-347）在 loadAndPlay() 抛 TimeoutException
//   （request_gate.dart:154-167 的 gate 20s 任务超时）时：
//     - :345 的守卫复位语句被跳过 → 守卫永久 true → 之后的 completed 事件
//       全被 :308 拦截 → 无自动切歌、无 pause 收尾（P2 死锁）
//     - unawaited 无错误处理 → TimeoutException 成为 unhandled async error
//
// 门禁（修复前必须 FAIL）：
//   1. 慢 NAS：setAudioSource 挂起 >20s → gate 超时抛错后守卫必须复位
//   2. 复位后再次收到 completed → 必须正常自动切歌/队尾 pause 收尾
//   3. 全程不得有 unhandled async error（flutter_test 测试区内即失败）

import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:nas_audio_player/core/contracts/audio_player_contract.dart';
import 'package:nas_audio_player/features/browser/browser_provider.dart';
import 'package:nas_audio_player/features/connection/connection_provider.dart';
import 'package:nas_audio_player/features/player/player_provider.dart';
import 'package:nas_audio_player/features/progress/progress_provider.dart';
import 'package:nas_audio_player/features/timer/timer_provider.dart';
import 'package:nas_audio_player/shared/models/connection_config.dart';
import 'package:nas_audio_player/shared/models/play_queue.dart';

import '../../helpers/fake_secure_storage.dart';
import '../../helpers/test_factories.dart';

/// 手写录音 fake（bug_bug19_repro_test.dart 同型，避免 mockito `any` 对
/// 非空参数无法编译的问题）。未实现的成员经 [Fake] 直接抛错，暴露意外访问。
class _FakePlayer extends Fake implements AudioPlayer, IAudioPlayer {
  final processingController = StreamController<ProcessingState>.broadcast();
  Completer<Duration?>? hang;

  int pauseCalls = 0;
  int stopCalls = 0;

  @override
  Stream<ProcessingState> get processingStateStream =>
      processingController.stream;

  @override
  Stream<PlayerState> get playerStateStream => const Stream.empty();

  @override
  Stream<Duration> get positionStream => const Stream.empty();

  @override
  Stream<Duration?> get durationStream => const Stream.empty();

  @override
  bool get playing => false;

  @override
  Duration get position => const Duration(seconds: 30);

  @override
  Duration? get duration => const Duration(minutes: 3);

  @override
  Future<Duration?> setAudioSource(AudioSource source,
      {bool preload = true, int? initialIndex, Duration? initialPosition}) {
    final h = hang;
    if (h != null) return h.future;
    return Future.value(Duration.zero);
  }

  @override
  Future<void> play() async {}

  @override
  Future<void> pause() async {
    pauseCalls++;
  }

  @override
  Future<void> stop() async {
    stopCalls++;
  }

  @override
  Future<void> seek(Duration? position, {int? index}) async {}

  @override
  Future<void> setSpeed(double speed) async {}

  @override
  Future<void> dispose() async {}
}

void main() {
  test('BUG-03: gate 20s 超时后守卫必须复位，自动切歌能力不丢，无 unhandled error', () {
    FakeAsync().run((async) {
      final player = _FakePlayer();
      // 慢 NAS：setAudioSource 挂起 >20s（P17 分层：gate 20s 先到期）。
      player.hang = Completer<Duration?>();

      final container = ProviderContainer(overrides: [
        audioPlayerProvider.overrideWithValue(player),
        onTrackCompletedProvider.overrideWithValue(() => false),
        secureStorageProvider
            .overrideWithValue(FakeSecureStorage()..setPassword(1, 'secret')),
        activeConnectionProvider.overrideWith((ref) async => ConnectionConfig(
              id: 1,
              name: 'test',
              url: 'http://localhost:8080',
              username: 'user',
              createdAt: DateTime(2024),
              updatedAt: DateTime(2024),
            )),
        // 避免真实 DB 依赖：saveProgress 落库用桩。
        upsertProgressProvider.overrideWithValue((
            {required int connectionId,
            required String filePath,
            required int positionMs,
            int? durationMs}) async {}),
      ]);
      addTearDown(container.dispose);

      container.read(currentPlayQueueProvider.notifier).state = PlayQueue(
        files: [
          testAudio('Song 1.mp3', '/music/Song 1.mp3'),
          testAudio('Song 2.flac', '/music/Song 2.flac'),
        ],
        currentIndex: 0,
      );

      // 首曲自然播完 → completed → 守卫置 true → 自动切歌 load 挂起。
      container.read(startProcessingListenerProvider)();
      player.processingController.add(ProcessingState.completed);
      async.flushMicrotasks();

      expect(container.read(currentPlayQueueProvider)!.currentIndex, 1,
          reason: '前置：completed 必须先切到下一曲（queue 前进）');

      // t=21s：gate 20s 任务超时 → loadAndPlay() 抛 TimeoutException →
      // 修复前：unhandled async error + 守卫复位语句（player_provider.dart:345）
      // 被跳过 → 守卫永久 true。
      async.elapse(const Duration(seconds: 21));

      // 释放挂起的 setAudioSource（ghost 曲"终于"加载完成）。
      player.hang!.complete(Duration.zero);
      async.flushMicrotasks();

      // 第二次 completed（ghost 曲播完 / 用户再放完一首）→
      // 修复前：守卫仍 true（:308 拦截）→ 无 pause 收尾、无任何动作；
      // 修复后：守卫已复位 → computeNextQueue 到队尾 → player.pause() 收尾。
      player.processingController.add(ProcessingState.completed);
      async.flushMicrotasks();

      expect(player.pauseCalls, 1,
          reason: 'BUG-03（cr-20260816-0802 B1）：gate 20s 超时后守卫必须复位。'
              '修复前守卫卡死 → 队尾 completed 无 pause 收尾（P2 死锁）。'
              'ghost 播放面（晚到 setAudioSource 触发 play）由 BUG-08 门禁锚定，'
              '不在此断言');

      player.processingController.close();
    });
  });
}
