// test/core/services/audio_handler_test.dart
// TEST-08-S3~S6（SVC9）：NasAudioHandler 核心逻辑测试
// （spec: docs/features/TEST-08.md §3.1/§5.4，依赖 REF-02 启用 IAudioHandler）
//
// SVC9: audio_handler.dart 大部分逻辑零覆盖——仅 play/pause/stop 超时覆盖
// （bug_06_test.dart / bug_17_repro_test.dart）。本文件补：
//
//   TEST-08-S3  seek 转发到 AudioPlayer
//   TEST-08-S4  onTaskRemoved → stop + config stopped
//   TEST-08-S5  onAudioFocusChange(lost) → pause + config.audioFocus lost
//               （否定断言：transient 不暂停）
//   TEST-08-S6  onAudioFocusChange(gained) → 仅状态机更新，不自动恢复播放
//               （注意：TEST-08 spec §3.1 S6 的正向断言「gained → play()」
//               已被 BUG-22 D1（cr-20260728-1700）删除——gained 无投递方，
//               自动恢复分支已删，见 bug_bug22_repro_test.dart INV1。本文件
//               按生产行为写：gained 只更新 config.audioFocus，否定断言
//               isAudioActive=false → verifyNever play() 保留）
//   顺带覆盖（SVC9 未列成员，普通命名，不占 TEST-08-S{n} 编号）：
//     setSpeed 转发 / skipToNext·skipToPrevious（callback + super 冒烟）/
//     setMediaItemFromPath（构建 MediaItem）/ _onPlayerStateChanged（状态
//     同步到 playbackStateStream）/ dispose（取消订阅）
//
// 装配模式同 bug_05_handler_play_test.dart：MockAudioPlayer + 真实
// NasAudioHandler，StreamController 驱动 playerStateStream；异步用
// fake_async 处理。

import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:mockito/mockito.dart';
import 'package:nas_audio_player/core/services/audio_handler.dart';
import 'package:nas_audio_player/features/player/domain/background_playback.dart';

import '../../helpers/mock_audio_player.dart';

void main() {
  /// Stubs the handler's stream dependencies and returns a fresh handler.
  /// 与 bug_05_handler_play_test.dart makeHandler 相同的装配。
  NasAudioHandler makeHandler(
      MockAudioPlayer player, StreamController<PlayerState>? stateController) {
    when(player.playerStateStream).thenAnswer(
        (_) => stateController?.stream ?? const Stream<PlayerState>.empty());
    when(player.positionStream)
        .thenAnswer((_) => const Stream<Duration>.empty());
    when(player.durationStream)
        .thenAnswer((_) => const Stream<Duration?>.empty());
    // _onPlayerStateChanged reads these when emitting playbackState.
    when(player.position).thenReturn(Duration.zero);
    when(player.bufferedPosition).thenReturn(Duration.zero);
    when(player.speed).thenReturn(1.0);
    return NasAudioHandler(player);
  }

  /// Pushes [state] through the player-state stream and flushes delivery so
  /// the handler's mirrored processing state has caught up.
  void emitState(FakeAsync async, StreamController<PlayerState> controller,
      PlayerState state) {
    controller.add(state);
    async.flushMicrotasks();
  }

  /// 置 handler 为播放中（焦点/任务移除用例的基线状态）。
  void startPlaying(
      FakeAsync async, MockAudioPlayer player, NasAudioHandler handler) {
    when(player.play()).thenAnswer((_) async {});
    handler.play();
    async.elapse(Duration.zero);
    expect(handler.config.playbackState, BackgroundPlaybackState.playing);
  }

  // ── TEST-08-S3: seek 转发 ──────────────────────────────────────────────────

  group('TEST-08-S3: IAudioHandler seek 转发到 AudioPlayer', () {
    test('TEST-08-S3: handler.seek(30s) → player.seek(30s)', () {
      FakeAsync().run((async) {
        final player = MockAudioPlayer();
        when(player.seek(any)).thenAnswer((_) async {});
        final handler = makeHandler(player, null);

        var completed = false;
        handler.seek(const Duration(seconds: 30)).then((_) {
          completed = true;
        });
        async.flushMicrotasks();

        expect(completed, isTrue, reason: '正常 seek 不得被 5s 超时保护拖住');
        // 否定断言：seek 不得被忽略（verify 未命中等价于静默失败）。
        verify(player.seek(const Duration(seconds: 30))).called(1);
        handler.dispose();
      });
    });
  });

  // ── TEST-08-S4: onTaskRemoved → 停止播放 ──────────────────────────────────

  group('TEST-08-S4: IAudioHandler onTaskRemoved 停止播放', () {
    test('TEST-08-S4: onTaskRemoved → player.stop() + config stopped', () {
      FakeAsync().run((async) {
        final player = MockAudioPlayer();
        when(player.stop()).thenAnswer((_) async {});
        final handler = makeHandler(player, null);
        startPlaying(async, player, handler);

        var completed = false;
        handler.onTaskRemoved().then((_) {
          completed = true;
        });
        async.elapse(Duration.zero);

        expect(completed, isTrue, reason: '正常 stop 路径不得触发 5s 超时');
        verify(player.stop()).called(1);
        // 否定断言：任务移除后不得继续播放（play 仅来自 setup 的一次）。
        verify(player.play()).called(1);
        expect(handler.config.playbackState, BackgroundPlaybackState.stopped,
            reason: 'onTaskRemoved 后 config 应同步为 stopped');
        handler.dispose();
      });
    });

    test('TEST-08-S4(否定): stop 挂起时 5s 超时兜底，不抛错', () {
      FakeAsync().run((async) {
        final player = MockAudioPlayer();
        when(player.stop()).thenAnswer((_) => Completer<void>().future);
        final handler = makeHandler(player, null);
        startPlaying(async, player, handler);

        var completed = false;
        Object? error;
        handler.onTaskRemoved().then((_) {
          completed = true;
        }).catchError((Object e) {
          error = e;
          completed = true;
        });

        async.elapse(const Duration(seconds: 4));
        expect(completed, isFalse, reason: 'stop 挂起时不得在 5s 前完成');
        async.elapse(const Duration(seconds: 2));
        expect(completed, isTrue, reason: 'stop 超时后 onTaskRemoved 必须返回（不挂死）');
        expect(error, isNull, reason: '否定断言：stop 超时不得抛异常');
        handler.dispose();
      });
    });
  });

  // ── TEST-08-S5: onAudioFocusChange lost → 暂停 ─────────────────────────────

  group('TEST-08-S5: IAudioHandler onAudioFocusChange lost → 暂停', () {
    test('TEST-08-S5: focus lost → player.pause() + config.audioFocus lost',
        () {
      FakeAsync().run((async) {
        final player = MockAudioPlayer();
        when(player.pause()).thenAnswer((_) async {});
        final handler = makeHandler(player, null);
        startPlaying(async, player, handler);

        handler.onAudioFocusChange(AudioFocusState.lost);
        async.elapse(Duration.zero);

        verify(player.pause()).called(1);
        expect(handler.config.audioFocus, AudioFocusState.lost,
            reason: 'config 必须反映焦点丢失');
        expect(handler.config.playbackState, BackgroundPlaybackState.paused,
            reason: 'focus lost 后状态机必须同步为 paused');
        handler.dispose();
      });
    });

    test('TEST-08-S5(否定): transient focus 不触发暂停（仅 lost）', () {
      FakeAsync().run((async) {
        final player = MockAudioPlayer();
        when(player.pause()).thenAnswer((_) async {});
        final handler = makeHandler(player, null);
        startPlaying(async, player, handler);

        handler.onAudioFocusChange(AudioFocusState.transient);
        async.elapse(Duration.zero);

        // 否定断言：瞬态焦点丢失（来电/ducking）不得暂停播放。
        verifyNever(player.pause());
        expect(handler.config.audioFocus, AudioFocusState.transient);
        expect(handler.config.playbackState, BackgroundPlaybackState.playing);
        handler.dispose();
      });
    });
  });

  // ── TEST-08-S6: onAudioFocusChange gained ──────────────────────────────────

  group('TEST-08-S6: IAudioHandler onAudioFocusChange gained', () {
    test(
        'TEST-08-S6: gained 仅更新焦点状态，不自动恢复播放'
        '（BUG-22 D1 删除自动恢复分支后的生产行为）', () {
      FakeAsync().run((async) {
        final player = MockAudioPlayer();
        when(player.play()).thenAnswer((_) async {});
        when(player.pause()).thenAnswer((_) async {});
        final handler = makeHandler(player, null);
        startPlaying(async, player, handler);

        // 完整焦点失去-恢复周期：lost → paused → gained。
        handler.onAudioFocusChange(AudioFocusState.lost);
        async.elapse(Duration.zero);
        expect(handler.config.playbackState, BackgroundPlaybackState.paused);

        handler.onAudioFocusChange(AudioFocusState.gained);
        async.elapse(Duration.zero);

        expect(handler.config.audioFocus, AudioFocusState.gained);
        // 否定断言：gained 不触发 play()（BUG-22 D1：gained 无投递方，
        // 自动恢复由 transient 语义 + just_audio 自身中断处理覆盖）。
        verify(player.play()).called(1); // 仅前面的 startPlaying 的 play()
        verify(player.pause()).called(1); // 仅前面的 lost 触发的一次
        expect(handler.config.playbackState, BackgroundPlaybackState.paused,
            reason: 'gained 不得改变 playbackState（保持 paused）');
        handler.dispose();
      });
    });

    test('TEST-08-S6(否定): isAudioActive=false 时 gained → verifyNever play()',
        () {
      FakeAsync().run((async) {
        final player = MockAudioPlayer();
        final handler = makeHandler(player, null);
        // 从未播放过 → config.isAudioActive == false。
        expect(handler.config.isAudioActive, isFalse);

        handler.onAudioFocusChange(AudioFocusState.gained);
        async.elapse(Duration.zero);

        expect(handler.config.audioFocus, AudioFocusState.gained);
        // 否定断言：非活动状态下焦点恢复不得触发播放。
        verifyNever(player.play());
        handler.dispose();
      });
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  // 顺带覆盖（SVC9 未列成员，普通命名，不占 TEST-08-S{n} 编号）
  // ═════════════════════════════════════════════════════════════════════════

  group('audio_handler: 顺带覆盖（SVC9 其余零覆盖成员）', () {
    test('audio_handler: setSpeed 转发到 player', () {
      FakeAsync().run((async) {
        final player = MockAudioPlayer();
        when(player.setSpeed(1.5)).thenAnswer((_) async {});
        final handler = makeHandler(player, null);

        var completed = false;
        handler.setSpeed(1.5).then((_) {
          completed = true;
        });
        async.elapse(Duration.zero);

        expect(completed, isTrue);
        verify(player.setSpeed(1.5)).called(1);
        handler.dispose();
      });
    });

    test(
        'audio_handler: skipToNext / skipToPrevious 触发 callback 并完成'
        '（callback + super，队列已配置的正常路径）', () {
      FakeAsync().run((async) {
        final player = MockAudioPlayer();
        final handler = makeHandler(player, null);

        // onSkipToNextRequested / onSkipToPreviousRequested 是 handler 的
        // callback 字段（void Function()?），由上层接线注入；skipToNext/
        // skipToPrevious 先触发 callback，再走 super（audio_service
        // QueueHandler 队列推进，需要 queue + queueIndex 已配置）。
        var nextCb = 0;
        var prevCb = 0;
        handler.onSkipToNextRequested = () {
          nextCb++;
        };
        handler.onSkipToPreviousRequested = () {
          prevCb++;
        };
        handler.updateQueue(const [
          MediaItem(id: '1', title: 'A'),
          MediaItem(id: '2', title: 'B'),
        ]);
        handler.playbackState
            .add(handler.playbackState.value.copyWith(queueIndex: 0));

        var nextDone = false;
        Object? nextError;
        handler.skipToNext().then((_) {
          nextDone = true;
        }).catchError((Object e) {
          nextError = e;
          nextDone = true;
        });

        var prevDone = false;
        Object? prevError;
        handler.skipToPrevious().then((_) {
          prevDone = true;
        }).catchError((Object e) {
          prevError = e;
          prevDone = true;
        });
        async.elapse(const Duration(seconds: 7));

        // callback 部分：skipToNext/skipToPrevious 必须触发对应 callback。
        expect(nextCb, 1,
            reason: 'skipToNext 必须先触发 onSkipToNextRequested callback');
        expect(prevCb, 1,
            reason: 'skipToPrevious 必须先触发 onSkipToPreviousRequested '
                'callback');
        // super 部分：队列已配置时不得抛错（audio_service QueueHandler
        // 推进依赖 playbackState.queueIndex 非空——未配置队列的裸 handler
        // 会抛 TypeError，属 audio_service 内部语义，本测试只测正常路径）。
        expect(nextDone, isTrue, reason: 'skipToNext 必须正常完成');
        expect(nextError, isNull);
        expect(prevDone, isTrue, reason: 'skipToPrevious 必须正常完成');
        expect(prevError, isNull);
        handler.dispose();
      });
    });

    test('audio_handler: setMediaItemFromPath 构建 MediaItem 并广播', () {
      FakeAsync().run((async) {
        final player = MockAudioPlayer();
        final handler = makeHandler(player, null);

        MediaItem? latest;
        final sub = handler.mediaItemStream.listen((item) {
          latest = item;
        });

        handler.setMediaItemFromPath('/music/song.mp3');
        async.flushMicrotasks();

        expect(latest, isNotNull,
            reason: 'setMediaItemFromPath 必须把 MediaItem 广播到 mediaItemStream');
        expect(latest!.id, '/music/song.mp3', reason: 'MediaItem.id 应为文件路径');
        expect(latest!.title, isNotEmpty,
            reason: 'MediaItem.title 应包含从路径提取的标题');
        unawaited(sub.cancel());
        handler.dispose();
      });
    });

    test('audio_handler: _onPlayerStateChanged 同步状态到 playbackStateStream', () {
      FakeAsync().run((async) {
        final player = MockAudioPlayer();
        final controller = StreamController<PlayerState>();
        final handler = makeHandler(player, controller);

        PlaybackState? latest;
        handler.playbackStateStream.listen((s) {
          latest = s;
        });
        // 播种后的初始值先经过 listener。
        async.flushMicrotasks();

        emitState(async, controller, PlayerState(true, ProcessingState.ready));
        expect(latest, isNotNull);
        expect(latest!.playing, isTrue,
            reason: '_onPlayerStateChanged 必须把 playing 状态同步到 '
                'playbackState（通知栏/锁屏展示）');

        emitState(async, controller, PlayerState(false, ProcessingState.ready));
        expect(latest!.playing, isFalse, reason: '暂停状态同样需要同步');

        handler.dispose();
        controller.close();
      });
    });

    test('audio_handler: dispose 取消 playerState 订阅（事件静默丢弃）', () {
      FakeAsync().run((async) {
        final player = MockAudioPlayer();
        final controller = StreamController<PlayerState>();
        final handler = makeHandler(player, controller);
        async.elapse(Duration.zero); // 让 _initAudioSession 订阅先落地

        // BehaviorSubject 播种后新 listener 先收到种子值（1 次）。
        var events = 0;
        handler.playbackStateStream.listen((_) {
          events++;
        });
        async.flushMicrotasks();
        expect(events, 1, reason: '种子值应被收到');

        // dispose 前：playerState 事件 → _onPlayerStateChanged → 广播。
        controller.add(PlayerState(true, ProcessingState.ready));
        async.flushMicrotasks();
        expect(events, 2, reason: 'dispose 前状态事件必须被广播');

        handler.dispose();
        controller.add(PlayerState(false, ProcessingState.ready));
        async.flushMicrotasks();

        // 否定断言：dispose 后事件不得再被广播（订阅已取消）。
        expect(events, 2, reason: 'dispose 后播放状态事件不得再被广播');
        controller.close();
      });
    });
  });
}
