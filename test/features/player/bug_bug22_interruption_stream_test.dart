// test/features/player/bug_bug22_interruption_stream_test.dart
// [历史批次 BUG-22（音频会话中断），该 ID 已被新 spec 复用为 playlist 项
//  docs/features/BUG-22.md——本文件属已归档旧项，勿与新门禁混淆]
// BUG-22 后续 T1（cr-20260728-1700）：音频会话中断的事件流级测试。
//
// 背景：2f946ff 的原门禁（bug_bug22_repro_test.dart）只有源码静态守卫 +
// onAudioFocusChange 的行为级测试，从未 mock 过 AudioSession 事件流。
// 本文件经 NasAudioHandler(audioSessionProvider: ...) 测试性注入点
//（与 BUG-26/BUG-31 DAO clock 参数同风格的测试性注入；默认行为不变，
// 生产路径仍走 AudioSession.instance，见 BUG-22-INV3 冒烟）注入 fake
// AudioSession，直接驱动「interruption 事件 → handler 映射 → config
// 状态 / 暂停行为」链路。
//
// 用例：
//   T1-1  (begin:true, type:pause)   → transient，且不 pause（transient 语义）
//   T1-2  (begin:true, type:duck)    → transient，且不 pause
//   T1-3  (begin:true, type:unknown) → lost，且触发 pause
//   T1-4  becomingNoisy              → lost，且触发 pause
//   T1-5  BUG-22 回归锚：(begin:false, type:pause)（通话结束恢复事件）
//         → 不得再次 pause / 不得把 audioFocus 打成 lost
//         （ee7d1e0 原缺陷形态：pause→lost 不分 begin）
//   T1-6  dispose 后事件到达不抛错、状态机不再变化
//   否定断言：transient/duck 事件从不调用 _player.pause()
//   （T1-1/T1-2 内 verifyNever 直接断言 mock player 未被调）
//
// RED→GREEN：把映射临时改回原缺陷形态（pause→lost 不分 begin）后跑本文件，
// T1-1/T1-2/T1-5 FAIL；恢复映射后全绿（见提交说明）。

import 'dart:async';

import 'package:audio_session/audio_session.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:mockito/mockito.dart';
import 'package:nas_audio_player/core/services/audio_handler.dart';
import 'package:nas_audio_player/features/player/domain/background_playback.dart';

void main() {
  group('BUG-22 T1: 音频会话中断事件流级测试（注入 fake AudioSession）', () {
    /// 构造注入 fake 音频会话的 handler，并等 _initAudioSession 完成订阅。
    (
      NasAudioHandler,
      StreamController<AudioInterruptionEvent>,
      StreamController<void>
    ) makeHandler(FakeAsync async, _MockPlayer player) {
      final interruptions =
          StreamController<AudioInterruptionEvent>.broadcast();
      final noisy = StreamController<void>.broadcast();
      final session = _FakeAudioSession(interruptions.stream, noisy.stream);
      final handler = NasAudioHandler(
        player,
        audioSessionProvider: () => Future<AudioSession>.value(session),
      );
      // _initAudioSession 内 await provider() 在微任务完成后建立订阅。
      async.elapse(Duration.zero);
      return (handler, interruptions, noisy);
    }

    /// 置 handler 为播放中（后续中断事件的基线状态）。
    void startPlaying(FakeAsync async, NasAudioHandler handler) {
      handler.play();
      async.elapse(Duration.zero);
      expect(handler.config.playbackState, BackgroundPlaybackState.playing);
    }

    test('T1-1: (begin:true, type:pause) → transient，且不 pause', () {
      FakeAsync().run((async) {
        final player = _MockPlayer();
        when(player.play()).thenAnswer((_) async {});
        when(player.pause()).thenAnswer((_) async {});
        final (handler, interruptions, noisy) = makeHandler(async, player);
        startPlaying(async, handler);

        interruptions
            .add(AudioInterruptionEvent(true, AudioInterruptionType.pause));
        async.elapse(Duration.zero);

        expect(handler.config.audioFocus, AudioFocusState.transient,
            reason: 'pause 型中断是瞬态（BUG-22 spec §3.1）');
        expect(handler.config.playbackState, BackgroundPlaybackState.playing,
            reason: 'transient 不得改变 playbackState');
        // 否定断言：transient 事件不得触碰播放器。
        verifyNever(player.pause());
        verify(player.play()).called(1); // 仅前面的手动 play()

        handler.dispose();
        interruptions.close();
        noisy.close();
      });
    });

    test('T1-2: (begin:true, type:duck) → transient，且不 pause', () {
      FakeAsync().run((async) {
        final player = _MockPlayer();
        when(player.play()).thenAnswer((_) async {});
        when(player.pause()).thenAnswer((_) async {});
        final (handler, interruptions, noisy) = makeHandler(async, player);
        startPlaying(async, handler);

        interruptions
            .add(AudioInterruptionEvent(true, AudioInterruptionType.duck));
        async.elapse(Duration.zero);

        expect(handler.config.audioFocus, AudioFocusState.transient,
            reason: 'duck 型中断是瞬态（音量瞬降，归平台层处理）');
        expect(handler.config.playbackState, BackgroundPlaybackState.playing);
        // 否定断言：duck 事件不得触碰播放器。
        verifyNever(player.pause());
        verify(player.play()).called(1);

        handler.dispose();
        interruptions.close();
        noisy.close();
      });
    });

    test('T1-3: (begin:true, type:unknown) → lost，且触发 pause', () {
      FakeAsync().run((async) {
        final player = _MockPlayer();
        when(player.play()).thenAnswer((_) async {});
        when(player.pause()).thenAnswer((_) async {});
        final (handler, interruptions, noisy) = makeHandler(async, player);
        startPlaying(async, handler);

        interruptions
            .add(AudioInterruptionEvent(true, AudioInterruptionType.unknown));
        async.elapse(Duration.zero);

        expect(handler.config.audioFocus, AudioFocusState.lost,
            reason: 'unknown（AUDIOFOCUS_LOSS）才是永久丢失');
        expect(handler.config.playbackState, BackgroundPlaybackState.paused);
        verify(player.pause()).called(1);
        verify(player.play()).called(1); // 仅前面的手动 play()

        handler.dispose();
        interruptions.close();
        noisy.close();
      });
    });

    test('T1-4: becomingNoisy → lost，且触发 pause', () {
      FakeAsync().run((async) {
        final player = _MockPlayer();
        when(player.play()).thenAnswer((_) async {});
        when(player.pause()).thenAnswer((_) async {});
        final (handler, interruptions, noisy) = makeHandler(async, player);
        startPlaying(async, handler);

        noisy.add(null);
        async.elapse(Duration.zero);

        expect(handler.config.audioFocus, AudioFocusState.lost,
            reason: '拔耳机（becoming noisy）转发为焦点 lost（U3）');
        expect(handler.config.playbackState, BackgroundPlaybackState.paused);
        verify(player.pause()).called(1);

        handler.dispose();
        interruptions.close();
        noisy.close();
      });
    });

    test(
        'T1-5 BUG-22 回归锚: (begin:false, type:pause) 通话结束恢复事件'
        ' → 不得再次 pause / 不得打成 lost', () {
      FakeAsync().run((async) {
        final player = _MockPlayer();
        when(player.play()).thenAnswer((_) async {});
        when(player.pause()).thenAnswer((_) async {});
        final (handler, interruptions, noisy) = makeHandler(async, player);
        startPlaying(async, handler);

        // 来电开始。
        interruptions
            .add(AudioInterruptionEvent(true, AudioInterruptionType.pause));
        async.elapse(Duration.zero);
        expect(handler.config.audioFocus, AudioFocusState.transient);
        verifyNever(player.pause());

        // 通话结束（begin:false）。原缺陷形态 ee7d1e0 把 pause 一律映射为
        // lost，不区分 begin，此事件会被当永久丢失再次 pause（U2 破缺）。
        interruptions
            .add(AudioInterruptionEvent(false, AudioInterruptionType.pause));
        async.elapse(Duration.zero);

        expect(handler.config.audioFocus, isNot(AudioFocusState.lost),
            reason: 'BUG-22 回归锚：恢复事件不得被当作永久焦点丢失');
        expect(handler.config.audioFocus, AudioFocusState.transient);
        expect(handler.config.playbackState, BackgroundPlaybackState.playing,
            reason: '恢复事件不得再次 pause');
        verifyNever(player.pause());

        handler.dispose();
        interruptions.close();
        noisy.close();
      });
    });

    test('T1-6: dispose 后事件到达不抛错、状态机不再变化', () {
      FakeAsync().run((async) {
        final player = _MockPlayer();
        when(player.play()).thenAnswer((_) async {});
        when(player.pause()).thenAnswer((_) async {});
        final (handler, interruptions, noisy) = makeHandler(async, player);
        startPlaying(async, handler);

        handler.dispose();

        // 订阅已取消（INV2）：事件静默丢弃，不抛错、不改状态。
        interruptions
            .add(AudioInterruptionEvent(true, AudioInterruptionType.unknown));
        noisy.add(null);
        async.elapse(Duration.zero);

        expect(handler.config.audioFocus, AudioFocusState.gained);
        expect(handler.config.playbackState, BackgroundPlaybackState.playing);
        verifyNever(player.pause());
        verify(player.play()).called(1);

        interruptions.close();
        noisy.close();
      });
    });
  });
}

// ═══════════════════════════════════════════════════════════════════════════
// Helpers
// ═══════════════════════════════════════════════════════════════════════════

/// Fake 音频会话：只暴露两条可注入事件流，其余成员测试不触达。
class _FakeAudioSession extends Mock implements AudioSession {
  _FakeAudioSession(
      this.interruptionEventStream, this.becomingNoisyEventStream);

  @override
  final Stream<AudioInterruptionEvent> interruptionEventStream;

  @override
  final Stream<void> becomingNoisyEventStream;
}

/// 宽松 AudioPlayer mock：未打桩的调用返回默认值（同 bug_bug22_repro 模式）。
class _MockPlayer extends Mock implements AudioPlayer {
  @override
  Stream<PlayerState> get playerStateStream =>
      super.noSuchMethod(Invocation.getter(#playerStateStream),
              returnValue: Stream<PlayerState>.empty(),
              returnValueForMissingStub: Stream<PlayerState>.empty())
          as Stream<PlayerState>;

  @override
  Stream<Duration> get positionStream => super.noSuchMethod(
      Invocation.getter(#positionStream),
      returnValue: Stream<Duration>.empty(),
      returnValueForMissingStub: Stream<Duration>.empty()) as Stream<Duration>;

  @override
  Stream<Duration?> get durationStream =>
      super.noSuchMethod(Invocation.getter(#durationStream),
              returnValue: Stream<Duration?>.empty(),
              returnValueForMissingStub: Stream<Duration?>.empty())
          as Stream<Duration?>;

  @override
  bool get playing => super.noSuchMethod(Invocation.getter(#playing),
      returnValue: false, returnValueForMissingStub: false) as bool;

  @override
  Duration get position => super.noSuchMethod(Invocation.getter(#position),
      returnValue: Duration.zero,
      returnValueForMissingStub: Duration.zero) as Duration;

  @override
  Future<void> play() => super.noSuchMethod(Invocation.method(#play, []),
      returnValue: Future<void>.value(),
      returnValueForMissingStub: Future<void>.value()) as Future<void>;

  @override
  Future<void> pause() => super.noSuchMethod(Invocation.method(#pause, []),
      returnValue: Future<void>.value(),
      returnValueForMissingStub: Future<void>.value()) as Future<void>;

  @override
  Future<void> stop() => super.noSuchMethod(Invocation.method(#stop, []),
      returnValue: Future<void>.value(),
      returnValueForMissingStub: Future<void>.value()) as Future<void>;

  @override
  Future<void> seek(Duration? position, {int? index}) => super.noSuchMethod(
      Invocation.method(#seek, [position], {if (index != null) #index: index}),
      returnValue: Future<void>.value(),
      returnValueForMissingStub: Future<void>.value()) as Future<void>;

  @override
  Future<void> setSpeed(double speed) =>
      super.noSuchMethod(Invocation.method(#setSpeed, [speed]),
          returnValue: Future<void>.value(),
          returnValueForMissingStub: Future<void>.value()) as Future<void>;
}
