// test/features/player/bug_05_handler_play_test.dart
// BUG-05: 通知/锁屏 play() 缺 completed 态 seek(0) 恢复 — automated test suite
//
// Verifies that NasAudioHandler.play() — the notification / lock-screen /
// headphone entry point — recovers from ProcessingState.completed by seeking
// to Duration.zero before calling play(), aligning with the in-app recovery
// paths in playback_controls.dart / mini_player_bar.dart (BUG-05-INV1).
// Android just_audio ignores play() while in completed state (P2), and the
// recovery seek itself may hang on a contested platform channel (P4), so a
// failed/timed-out seek must never block the subsequent play() attempt.
//
// BUG-05-S1-T01: completed 态 → play() 先 seek(Duration.zero) 再 play()
// BUG-05-S1-T02: 非 completed 态 → 跳过 seek(0) 直接 play()（回归）
// BUG-05-S1-T03: seek(0) 抛异常 → 不阻塞 play() 调用（否定断言）
// BUG-05-S1-T04: seek(0) 挂起 5s 超时 → 仍不阻塞 play() 调用（P4 否定断言）
// BUG-05-S1-T05: completed 态 seek(0) 成功但 play() 挂起 → 5s 超时返回（BUG-06 回归）
// BUG-05-INV1-T01: completed 恢复路径 seek(0) 严格先于 play()（顺序不变量）

import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:nas_audio_player/core/services/audio_handler.dart';

import 'bug_05_handler_play_test.mocks.dart';

@GenerateMocks([AudioPlayer])
void main() {
  /// Stubs the handler's stream dependencies and returns a fresh handler.
  NasAudioHandler makeHandler(
      MockAudioPlayer player, StreamController<PlayerState> stateController) {
    when(player.playerStateStream).thenAnswer((_) => stateController.stream);
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

  // ── BUG-05-S1-T01: completed 态 → play() 先 seek(Duration.zero) 再 play() ──

  group('BUG-05-S1-T01: completed state triggers seek(0) recovery', () {
    test('completed state: play() calls seek(Duration.zero) then play()', () {
      FakeAsync().run((async) {
        final player = MockAudioPlayer();
        final controller = StreamController<PlayerState>();
        final handler = makeHandler(player, controller);

        emitState(
            async, controller, PlayerState(false, ProcessingState.completed));

        var seekCalls = 0;
        var playCalls = 0;
        when(player.seek(Duration.zero)).thenAnswer((_) async {
          seekCalls++;
        });
        when(player.play()).thenAnswer((_) async {
          playCalls++;
        });

        handler.play();
        async.flushMicrotasks();

        expect(seekCalls, 1,
            reason: 'completed state must recover with seek(Duration.zero)');
        expect(playCalls, 1, reason: 'play() must follow the recovery seek');
        handler.dispose();
        controller.close();
      });
    });
  });

  // ── BUG-05-S1-T02: 非 completed 态 → 跳过 seek(0) 直接 play()（回归） ──

  group('BUG-05-S1-T02: non-completed state skips recovery seek', () {
    test('ready state: play() does not seek', () {
      FakeAsync().run((async) {
        final player = MockAudioPlayer();
        final controller = StreamController<PlayerState>();
        final handler = makeHandler(player, controller);

        emitState(async, controller, PlayerState(false, ProcessingState.ready));

        var seekCalls = 0;
        var playCalls = 0;
        when(player.seek(any)).thenAnswer((_) async {
          seekCalls++;
        });
        when(player.play()).thenAnswer((_) async {
          playCalls++;
        });

        handler.play();
        async.flushMicrotasks();

        expect(seekCalls, 0,
            reason: 'non-completed state must not trigger recovery seek');
        expect(playCalls, 1);
        verifyNever(player.seek(any));
        handler.dispose();
        controller.close();
      });
    });

    test('no state emitted yet (idle): play() does not seek', () {
      FakeAsync().run((async) {
        final player = MockAudioPlayer();
        final controller = StreamController<PlayerState>();
        final handler = makeHandler(player, controller);

        var seekCalls = 0;
        when(player.seek(any)).thenAnswer((_) async {
          seekCalls++;
        });
        when(player.play()).thenAnswer((_) async {});

        handler.play();
        async.flushMicrotasks();

        expect(seekCalls, 0);
        handler.dispose();
        controller.close();
      });
    });
  });

  // ── BUG-05-S1-T03: seek(0) 抛异常 → 不阻塞 play() 调用（否定断言） ──

  group('BUG-05-S1-T03: seek failure does not block play()', () {
    test('seek(0) throwing still calls play()', () {
      FakeAsync().run((async) {
        final player = MockAudioPlayer();
        final controller = StreamController<PlayerState>();
        final handler = makeHandler(player, controller);

        emitState(
            async, controller, PlayerState(false, ProcessingState.completed));

        var playCalls = 0;
        when(player.seek(Duration.zero))
            .thenThrow(Exception('platform channel error'));
        when(player.play()).thenAnswer((_) async {
          playCalls++;
        });

        var completed = false;
        handler.play().then((_) {
          completed = true;
        });
        async.flushMicrotasks();

        expect(playCalls, 1,
            reason: 'seek failure must not block the play() attempt '
                '(BUG-05-S1 negative assertion)');
        expect(completed, isTrue,
            reason: 'handler.play() must swallow the seek failure');
        handler.dispose();
        controller.close();
      });
    });
  });

  // ── BUG-05-S1-T04: seek(0) 挂起 5s 超时 → 仍不阻塞 play() 调用（P4） ──

  group('BUG-05-S1-T04: hanging recovery seek does not block play()', () {
    test('seek(0) hanging past 5s still calls play()', () {
      FakeAsync().run((async) {
        final player = MockAudioPlayer();
        final controller = StreamController<PlayerState>();
        final handler = makeHandler(player, controller);

        emitState(
            async, controller, PlayerState(false, ProcessingState.completed));

        var playCalls = 0;
        // The recovery seek hangs forever — the P4 platform hazard that
        // BUG-17 documents for seek().
        when(player.seek(Duration.zero))
            .thenAnswer((_) => Completer<void>().future);
        when(player.play()).thenAnswer((_) async {
          playCalls++;
        });

        var completed = false;
        handler.play().then((_) {
          completed = true;
        });

        // At 4s the recovery seek is still hanging — play not yet attempted.
        async.elapse(const Duration(seconds: 4));
        expect(playCalls, 0);

        // At 5s the seek times out; play() must still be attempted.
        async.elapse(const Duration(seconds: 2));
        expect(playCalls, 1,
            reason: 'a timed-out recovery seek must not block play() — '
                'otherwise the completed-state deadlock reproduces (P2+P4)');
        expect(completed, isTrue);
        handler.dispose();
        controller.close();
      });
    });
  });

  // ── BUG-05-S1-T05: seek(0) 成功但 play() 挂起 → 5s 超时返回 ──

  group('BUG-05-S1-T05: hanging play() after recovery seek times out', () {
    test('recovery path completes within 5s when play() hangs', () {
      FakeAsync().run((async) {
        final player = MockAudioPlayer();
        final controller = StreamController<PlayerState>();
        final handler = makeHandler(player, controller);

        emitState(
            async, controller, PlayerState(false, ProcessingState.completed));

        when(player.seek(Duration.zero)).thenAnswer((_) async {});
        when(player.play()).thenAnswer((_) => Completer<void>().future);

        var completed = false;
        handler.play().then((_) {
          completed = true;
        });

        async.elapse(const Duration(seconds: 4));
        expect(completed, isFalse);

        async.elapse(const Duration(seconds: 2));
        expect(completed, isTrue,
            reason: 'hanging play() must still be bounded by the 5s timeout');
        handler.dispose();
        controller.close();
      });
    });
  });

  // ── BUG-05-INV1-T01: completed 恢复路径 seek(0) 严格先于 play() ──

  group('BUG-05-INV1-T01: recovery ordering invariant', () {
    test('seek(Duration.zero) is strictly ordered before play()', () {
      FakeAsync().run((async) {
        final player = MockAudioPlayer();
        final controller = StreamController<PlayerState>();
        final handler = makeHandler(player, controller);

        emitState(
            async, controller, PlayerState(false, ProcessingState.completed));

        when(player.seek(Duration.zero)).thenAnswer((_) async {});
        when(player.play()).thenAnswer((_) async {});

        handler.play();
        async.flushMicrotasks();

        // Matches the in-app recovery order in playback_controls.dart /
        // mini_player_bar.dart: seek(0) first, then play.
        verifyInOrder([player.seek(Duration.zero), player.play()]);
        handler.dispose();
        controller.close();
      });
    });
  });
}
