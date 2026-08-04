// test/features/player/bug_bug22_repro_test.dart
// BUG-22 门禁测试（spec: docs/features/BUG-22.md；来源 SVC2 + SVC3，
// cr-20260724-0110.md §12.1；用户裁决：接入 audio_session 焦点流）
//
// 缺陷：onAudioFocusChange 全库零调用（焦点处理死代码）；焦点回调内直调
// _player.play()/_player.pause() 绕过 BUG-06 的 5s 超时。
// 修复：NasAudioHandler 构造时订阅 audio_session interruptionEventStream /
// becomingNoisyEventStream 转发到 onAudioFocusChange（S1）；焦点处理内改用
// 带超时的 this.play()/this.pause()（S2）。
//
// 平台流本身在 flutter test 中不可达（AudioSession 无 Android/iOS 平台
// channel，spec §8 已裁决 manual_qa_required），本测试按 spec §8 的自动化
// 覆盖方案执行：行为测试（onAudioFocusChange 的转发目标行为）+ 源码静态
// 分析（映射规则 / INV1 无 _player 直调 / INV2 dispose 清理）。
//
// 用例：
//   BUG-22-INV3:  audio_session 初始化失败不阻塞核心播放（测试环境冒烟）
//   BUG-22-S2a:   焦点 lost → 走带超时的 pause() 路径（SVC3）
//   BUG-22-S2b:   焦点 transient → 不触发任何 play/pause
//   BUG-22-S2c:   焦点 gained → 仅状态机更新，无 play/pause 副作用
//                 （cr-20260728-1700 D1 裁决删除 gained 死分支后的否定锚）
//   BUG-22-S1:    中断事件映射 pause/duck→transient、unknown→lost（源码守卫）
//   BUG-22-INV1:  onAudioFocusChange 内无 _player.play/_player.pause 直调，
//                 且不得含 play()（gained 死分支不得复活）
//   BUG-22-INV2:  dispose 取消 audio_session 两个订阅
//
// 修复前 FAIL：SVC3 直调版本在 S2a/S2b 的 config 同步与超时断言失败；
// ee7d1e0 的映射偏差（pause→lost）在 S1 映射守卫下 FAIL。
//
// 事件流级测试（interruption 事件 → 映射 → config/暂停链路）见
// bug_bug22_interruption_stream_test.dart（cr-20260728-1700 T1 补齐）。

import 'dart:async';
import 'dart:io';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:mockito/mockito.dart';
import 'package:nas_audio_player/core/services/audio_handler.dart';
import 'package:nas_audio_player/features/player/domain/background_playback.dart';

void main() {
  // ── BUG-22-INV3: audio_session 不可用不阻塞核心播放 ──

  group('BUG-22-INV3: audio_session 初始化失败降级', () {
    test('测试环境无平台 channel，handler 构造不抛错且播放链路正常', () {
      FakeAsync().run((async) {
        final player = _MockPlayer();
        when(player.play()).thenAnswer((_) async {});

        // flutter test 中 AudioSession.instance 的平台 channel 缺失，
        // _initAudioSession 必须 catch 并记录日志后降级
        // （spec 边界裁决；项目判据「catch 必有日志」）。
        final handler = NasAudioHandler(player);

        var completed = false;
        handler.play().then((_) {
          completed = true;
        });
        async.elapse(Duration.zero);
        expect(completed, isTrue,
            reason: 'BUG-22-INV3：audio_session 订阅失败不得阻塞核心播放');
        verify(player.play()).called(1);

        handler.dispose();
      });
    });
  });

  // ── BUG-22-S2: 焦点处理走带超时的 this.play()/this.pause() ──

  group('BUG-22-S2: 焦点回调经带超时的 handler 方法', () {
    test('焦点 lost → pause() 被调用且状态机同步置 paused', () {
      FakeAsync().run((async) {
        final player = _MockPlayer();
        when(player.pause()).thenAnswer((_) async {});
        when(player.playing).thenReturn(true);

        final handler = NasAudioHandler(player);
        // 先置为播放中，使焦点变化前状态机处于 playing。
        when(player.play()).thenAnswer((_) async {});
        handler.play();
        async.elapse(Duration.zero);
        expect(handler.config.playbackState, BackgroundPlaybackState.playing);

        handler.onAudioFocusChange(AudioFocusState.lost);

        // 状态机同步转移：audioFocus=lost 且 playbackState=paused
        // （updateAudioFocus(lost) 语义，spec 不改变状态机转移逻辑）。
        // "必须经 pause() override 而非直调 _player" 由下方 INV1 源码守卫保证。
        expect(handler.config.audioFocus, AudioFocusState.lost);
        expect(handler.config.playbackState, BackgroundPlaybackState.paused);
        verify(player.pause()).called(1);

        handler.dispose();
      });
    });

    test('焦点 lost 且 _player.pause() 挂起 → 5s 超时兜底不挂死（U5）', () {
      FakeAsync().run((async) {
        final player = _MockPlayer();
        // 模拟 P4：平台 pause() Future 永不完成。
        when(player.pause()).thenAnswer((_) => Completer<void>().future);
        when(player.play()).thenAnswer((_) async {});

        final handler = NasAudioHandler(player);
        handler.play();
        async.elapse(Duration.zero);

        // 焦点回调是 fire-and-forget：不得抛错、不得阻塞后续控制。
        handler.onAudioFocusChange(AudioFocusState.lost);
        async.elapse(const Duration(seconds: 6));

        // 超时保护后 handler 仍可继续工作（下一次 pause 仍能完成其超时周期）。
        var completed = false;
        handler.pause().then((_) {
          completed = true;
        });
        async.elapse(const Duration(seconds: 6));
        expect(completed, isTrue,
            reason: 'BUG-22 U5：焦点触发的 pause 走 5s 超时保护，'
                '挂起的平台调用不得拖死 handler');

        handler.dispose();
      });
    });

    test('焦点 transient → 不触发任何 play/pause（ducking 归平台层）', () {
      FakeAsync().run((async) {
        final player = _MockPlayer();
        when(player.play()).thenAnswer((_) async {});

        final handler = NasAudioHandler(player);
        handler.play();
        async.elapse(Duration.zero);

        handler.onAudioFocusChange(AudioFocusState.transient);
        async.elapse(Duration.zero);

        expect(handler.config.audioFocus, AudioFocusState.transient);
        // play() 只应来自前面的 handler.play()（1 次），pause 零次。
        verify(player.play()).called(1);
        verifyNever(player.pause());

        handler.dispose();
      });
    });

    test('焦点 gained → 仅更新状态机，不触发任何 play/pause（D1 删死分支）', () {
      FakeAsync().run((async) {
        final player = _MockPlayer();
        when(player.play()).thenAnswer((_) async {});
        when(player.pause()).thenAnswer((_) async {});
        when(player.playing).thenReturn(false);

        final handler = NasAudioHandler(player);
        handler.play(); // 状态机置 playing
        async.elapse(Duration.zero);
        expect(handler.config.isAudioActive, isTrue);

        // 焦点 lost → paused，随后 gained 恢复（模拟焦点失去-恢复全周期）。
        handler.onAudioFocusChange(AudioFocusState.lost);
        async.elapse(Duration.zero);
        handler.onAudioFocusChange(AudioFocusState.gained);
        async.elapse(Duration.zero);

        // gained 只转移状态机 audioFocus；playbackState 保持 paused，
        // 不产生任何播放器副作用（cr-20260728-1700 D1：gained 全库无投递方，
        // 自动恢复分支已删除——恢复由 transient 语义 + just_audio 自身
        // 中断处理覆盖，U2 通话结束恢复语义不变）。
        expect(handler.config.audioFocus, AudioFocusState.gained);
        expect(handler.config.playbackState, BackgroundPlaybackState.paused);
        verify(player.play()).called(1); // 仅前面的 handler.play()
        verify(player.pause()).called(1); // 仅 lost 触发的一次

        handler.dispose();
      });
    });
  });

  // ── BUG-22-S1 / INV1 / INV2: 源码静态守卫（spec §8 自动化方案） ──

  group('BUG-22-S1/INV1/INV2: audio_session 接线静态守卫', () {
    late String src;
    setUpAll(() {
      src = File('lib/core/services/audio_handler.dart').readAsStringSync();
    });

    /// 截取 [start] 标记之后、[end] 标记之前的片段。
    String between(String start, String end) {
      final s = src.indexOf(start);
      expect(s, isNot(-1), reason: '未找到片段起点标记: $start');
      final e = src.indexOf(end, s + start.length);
      expect(e, isNot(-1), reason: '未找到片段终点标记: $end');
      return src.substring(s, e);
    }

    test('BUG-22-S1: 构造时订阅 interruption/becomingNoisy 两条焦点流', () {
      // 构造签名含可注入 audioSessionProvider 参数（T1 测试性注入），
      // 标记只锚定构造函数起点。
      final ctor = between(
          'NasAudioHandler(this._player', 'Future<void> _initAudioSession');
      expect(ctor, contains('_initAudioSession();'),
          reason: 'S1：构造函数必须发起 audio_session 订阅（启动时接入焦点流）');
      expect(src, contains('interruptionEventStream.listen'),
          reason: 'S1：订阅 interruptionEventStream 并转发 onAudioFocusChange');
      expect(src, contains('becomingNoisyEventStream.listen'),
          reason: 'S1：订阅 becomingNoisyEventStream（拔耳机）');
      // becomingNoisy → lost（暂停），与 spec 修改指令一致。
      final noisy =
          between('becomingNoisyEventStream.listen', '// ── State sync');
      expect(noisy, contains('AudioFocusState.lost'),
          reason: 'S1 U3：拔耳机事件必须转发为焦点 lost → 暂停');
    });

    test('BUG-22-S1: 中断类型映射 pause/duck→transient、unknown→lost', () {
      final listener =
          between('interruptionEventStream.listen', 'becomingNoisyEventStream');
      expect(
          RegExp(r'case AudioInterruptionType\.pause:\s*'
                  r'case AudioInterruptionType\.duck:\s*'
                  r'onAudioFocusChange\(AudioFocusState\.transient\);')
              .hasMatch(listener),
          isTrue,
          reason: 'S1 映射（spec §3.1）：pause/duck 是瞬态中断——来电等 '
              'AUDIOFOCUS_LOSS_TRANSIENT 映射为 transient；映射为 lost 会把'
              '通话结束后的焦点恢复事件（begin:false, type:pause）当永久丢失'
              '再次 pause，破坏 U2 通话结束恢复');
      expect(
          RegExp(r'case AudioInterruptionType\.unknown:\s*'
                  r'onAudioFocusChange\(AudioFocusState\.lost\);')
              .hasMatch(listener),
          isTrue,
          reason: 'S1 映射：unknown（AUDIOFOCUS_LOSS）才是永久丢失');
    });

    test('BUG-22-INV1: onAudioFocusChange 内无 _player.play/pause 直调', () {
      final body = between(
          'void onAudioFocusChange', '// ── BaseAudioHandler overrides');
      expect(body.contains('_player.play('), isFalse,
          reason: '否定断言（INV1/SVC3）：不得直调 _player.play()，'
              '必须走带 5s 超时的 this.play()');
      expect(body.contains('_player.pause('), isFalse,
          reason: '否定断言（INV1/SVC3）：不得直调 _player.pause()，'
              '必须走带 5s 超时的 this.pause()');
      expect(body, contains('pause();'), reason: '焦点 lost 必须经 this.pause()');
      expect(body.contains('play();'), isFalse,
          reason: '否定断言（D1）：gained 无投递方，焦点路径不得含 play()——'
              '死分支已删除，防止自动恢复分支复活');
    });

    test('BUG-22-INV2: dispose 取消全部 audio_session 订阅', () {
      final dispose = src.substring(src.indexOf('void dispose()'));
      expect(dispose, contains('_interruptionSub?.cancel()'),
          reason: 'INV2：dispose 必须取消 interruptionEventStream 订阅');
      expect(dispose, contains('_becomingNoisySub?.cancel()'),
          reason: 'INV2：dispose 必须取消 becomingNoisyEventStream 订阅');
      expect(dispose, contains('_stateSub?.cancel()'),
          reason: 'INV2 回归：player 订阅清理不得丢失');
    });
  });
}

// ═══════════════════════════════════════════════════════════════════════════
// Helpers
// ═══════════════════════════════════════════════════════════════════════════

/// 宽松 AudioPlayer mock：未打桩的调用返回默认值（同 aud_02 模式）。
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
