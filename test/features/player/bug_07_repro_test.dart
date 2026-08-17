// test/features/player/bug_07_repro_test.dart
// BUG-07（cr-20260816-0802 F3）：removeTrack(当前曲) 后监听器按
// player.playing 条件启动：加载期间暂停则自动切歌/自动保存永久缺失
// （spec: docs/features/BUG-07.md §5.4）
//
// 缺陷：player_provider.dart:375-384 removeTrackFromQueueProvider 在
// orchestrator.removeTrack 返回后以 `if (player.playing)` 条件启动监听器。
// orchestrator 内 removeTrack 调 loadAndPlay()（playback_orchestrator.dart:365）
// 不走 provider 包装，_startPlaybackListeners 只能靠这行补救。加载期间用户
// 暂停（P3：playing 不传播）→ 加载成功但 playing==false → 监听器不启动 →
// 之后曲目播完无自动切歌、无自动保存、无 pause-save，停在 completed（P2）。
//
// 门禁（修复前必须 FAIL）：
//   1. wasCurrent 删除 + 加载成功（哪怕当前 playing==false）→ 监听器必须启动
//   2. 启动后收到 completed → 必须自动切歌（queue 前进 + 触发 loadAndPlay）

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

/// 手写 fake：playing 恒 false（模拟"加载期间用户暂停"，P3 场景）；
/// playerStateStream 由测试手动发 playing 事件（让加载成功）。
class _PausedDuringLoadPlayer extends Fake
    implements AudioPlayer, IAudioPlayer {
  final processingController = StreamController<ProcessingState>.broadcast();
  final playerStateController = StreamController<PlayerState>.broadcast();

  @override
  Stream<ProcessingState> get processingStateStream =>
      processingController.stream;

  @override
  Stream<PlayerState> get playerStateStream => playerStateController.stream;

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
      {bool preload = true,
      int? initialIndex,
      Duration? initialPosition}) async {
    return Duration.zero;
  }

  @override
  Future<void> play() async {}

  @override
  Future<void> pause() async {}

  @override
  Future<void> stop() async {}

  @override
  Future<void> seek(Duration? position, {int? index}) async {}

  @override
  Future<void> setSpeed(double speed) async {}

  @override
  Future<void> dispose() async {}
}

void main() {
  test('BUG-07: wasCurrent 删除 + 加载成功（playing==false）监听器必须启动', () {
    FakeAsync().run((async) {
      final player = _PausedDuringLoadPlayer();

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
          testAudio('Song 3.m4b', '/music/Song 3.m4b'),
        ],
        currentIndex: 0,
      );

      // 删除当前曲（index 0）→ orchestrator.removeTrack → 内部 loadAndPlay
      //（playback_orchestrator.dart:365，不走 provider 包装）。
      container.read(removeTrackFromQueueProvider)(0);
      async.flushMicrotasks();
      // 加载等待 playing 事件：发出 → 加载成功。
      player.playerStateController
          .add(PlayerState(true, ProcessingState.ready));
      async.flushMicrotasks();
      async.flushMicrotasks();

      expect(container.read(currentPlayQueueProvider)!.currentIndex, 0,
          reason: '前置：删除后新队列当前曲是 Song 2（index 0，2 首）');
      expect(container.read(currentPlayQueueProvider)!.length, 2);

      // 用户恢复播放、该曲自然播完 → completed。
      // 修复前：_startPlaybackListeners 未启动（player.playing==false 条件
      // 跳过，player_provider.dart:383）→ 无监听器 → 无自动切歌。
      // 修复后：监听器已启动 → computeNextQueue → 切到 Song 3（index 1）。
      player.processingController.add(ProcessingState.completed);
      async.flushMicrotasks();
      async.flushMicrotasks();

      expect(container.read(currentPlayQueueProvider)!.currentIndex, 1,
          reason: 'BUG-07（cr-20260816-0802 F3）：removeTrack(当前曲) 且加载'
              '成功时，即使 player.playing==false 也必须启动播放监听器'
              '（player_provider.dart:383 的 `if (player.playing)` 条件判定是'
              '缺陷根源，P3 场景下自动切歌/自动保存永久缺失）');
      expect(container.read(currentPlayQueueProvider)!.current.path,
          '/music/Song 3.m4b',
          reason: '自动切歌必须落到下一曲 Song 3');

      player.processingController.close();
      player.playerStateController.close();
    });
  });
}
