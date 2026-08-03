// test/features/player/bug_17_repro_test.dart
// BUG-17: seek/setSpeed 无超时保护 — automated repro & regression suite
//
// Verifies that NasAudioHandler.seek() and setSpeed() have the same
// 5-second timeout + silent-catch protection as play/pause/stop (BUG-06),
// so that a hanging platform-channel Future (P4) cannot freeze the
// notification progress slider or speed controls.
//
// BUG-17-S1-T01: seek 挂起 → 5s 超时静默返回，不阻塞不抛错
// BUG-17-S1-T02: seek 抛异常 → 静默吞掉，不抛未处理异常（否定断言）
// BUG-17-S1-T03: 正常 seek → 立即完成并透传位置（回归）
// BUG-17-S2-T01: setSpeed 挂起 → 5s 超时静默返回
// BUG-17-S2-T02: 正常 setSpeed → 立即完成并透传速度（回归）
// BUG-17-INV1:   全平台调用超时扫描 — play/pause/stop/seek/setSpeed/
//                onTaskRemoved 挂起时均在 5s 内返回且不抛错

import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:nas_audio_player/core/services/audio_handler.dart';

import 'bug_17_repro_test.mocks.dart';

@GenerateMocks([AudioPlayer])
void main() {
  /// Stubs the constructor streams so [NasAudioHandler] can be built.
  void stubStreams(MockAudioPlayer player) {
    when(player.playerStateStream)
        .thenAnswer((_) => const Stream<PlayerState>.empty());
    when(player.positionStream)
        .thenAnswer((_) => const Stream<Duration>.empty());
    when(player.durationStream)
        .thenAnswer((_) => const Stream<Duration?>.empty());
  }

  // ── BUG-17-S1-T01: seek 挂起 → 5s 超时静默返回 ──

  group('BUG-17-S1-T01: hanging seek times out after 5 seconds', () {
    test('seek() that never completes does not block beyond 5 seconds', () {
      FakeAsync().run((async) {
        final player = MockAudioPlayer();
        stubStreams(player);
        when(player.seek(any)).thenAnswer((_) => Completer<void>().future);

        final handler = NasAudioHandler(player);

        var completed = false;
        Object? error;
        handler.seek(const Duration(seconds: 30)).then((_) {
          completed = true;
        }).catchError((Object e) {
          error = e;
          completed = true;
        });

        async.elapse(const Duration(seconds: 4));
        expect(completed, isFalse,
            reason: 'seek() should not complete before 5 seconds');

        async.elapse(const Duration(seconds: 2));
        expect(completed, isTrue,
            reason: 'seek() should complete after the 5-second timeout');
        expect(error, isNull,
            reason: 'the timeout must be swallowed silently, like '
                'play/pause/stop');
        handler.dispose();
      });
    });
  });

  // ── BUG-17-S1-T02: seek 抛异常 → 静默吞掉（否定断言） ──

  group('BUG-17-S1-T02: throwing seek is swallowed', () {
    test('seek() platform error does not propagate', () {
      FakeAsync().run((async) {
        final player = MockAudioPlayer();
        stubStreams(player);
        when(player.seek(any)).thenThrow(Exception('platform channel error'));

        final handler = NasAudioHandler(player);

        var completed = false;
        Object? error;
        handler.seek(const Duration(seconds: 10)).then((_) {
          completed = true;
        }).catchError((Object e) {
          error = e;
          completed = true;
        });

        async.flushMicrotasks();
        expect(completed, isTrue);
        expect(error, isNull,
            reason: 'no unhandled exception may escape handler.seek()');
        handler.dispose();
      });
    });
  });

  // ── BUG-17-S1-T03: 正常 seek → 立即完成并透传位置（回归） ──

  group('BUG-17-S1-T03: normal seek completes promptly', () {
    test('seek() delegates the position and completes without timeout', () {
      FakeAsync().run((async) {
        final player = MockAudioPlayer();
        stubStreams(player);
        when(player.seek(any)).thenAnswer((_) async {});

        final handler = NasAudioHandler(player);

        var completed = false;
        handler.seek(const Duration(seconds: 42)).then((_) {
          completed = true;
        });

        async.elapse(Duration.zero);
        expect(completed, isTrue);
        verify(player.seek(const Duration(seconds: 42))).called(1);
        handler.dispose();
      });
    });
  });

  // ── BUG-17-S2-T01: setSpeed 挂起 → 5s 超时静默返回 ──

  group('BUG-17-S2-T01: hanging setSpeed times out after 5 seconds', () {
    test('setSpeed() that never completes does not block beyond 5 seconds', () {
      FakeAsync().run((async) {
        final player = MockAudioPlayer();
        stubStreams(player);
        when(player.setSpeed(any)).thenAnswer((_) => Completer<void>().future);

        final handler = NasAudioHandler(player);

        var completed = false;
        Object? error;
        handler.setSpeed(2.0).then((_) {
          completed = true;
        }).catchError((Object e) {
          error = e;
          completed = true;
        });

        async.elapse(const Duration(seconds: 4));
        expect(completed, isFalse,
            reason: 'setSpeed() should not complete before 5 seconds');

        async.elapse(const Duration(seconds: 2));
        expect(completed, isTrue,
            reason: 'setSpeed() should complete after the 5-second timeout');
        expect(error, isNull);
        handler.dispose();
      });
    });
  });

  // ── BUG-17-S2-T02: 正常 setSpeed → 立即完成并透传速度（回归） ──

  group('BUG-17-S2-T02: normal setSpeed completes promptly', () {
    test('setSpeed() delegates the speed and completes without timeout', () {
      FakeAsync().run((async) {
        final player = MockAudioPlayer();
        stubStreams(player);
        when(player.setSpeed(any)).thenAnswer((_) async {});

        final handler = NasAudioHandler(player);

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
  });

  // ── BUG-17-INV1: 全平台调用超时扫描 ──

  group('BUG-17-INV1: every handler platform call is timeout-protected', () {
    final scenarios = <(
      String,
      void Function(MockAudioPlayer),
      Future<void> Function(NasAudioHandler)
    )>[
      (
        'play',
        (p) => when(p.play()).thenAnswer((_) => Completer<void>().future),
        (h) => h.play()
      ),
      (
        'pause',
        (p) => when(p.pause()).thenAnswer((_) => Completer<void>().future),
        (h) => h.pause()
      ),
      (
        'stop',
        (p) => when(p.stop()).thenAnswer((_) => Completer<void>().future),
        (h) => h.stop()
      ),
      (
        'seek',
        (p) => when(p.seek(any)).thenAnswer((_) => Completer<void>().future),
        (h) => h.seek(const Duration(seconds: 1))
      ),
      (
        'setSpeed',
        (p) =>
            when(p.setSpeed(any)).thenAnswer((_) => Completer<void>().future),
        (h) => h.setSpeed(1.0)
      ),
      (
        'onTaskRemoved',
        (p) => when(p.stop()).thenAnswer((_) => Completer<void>().future),
        (h) => h.onTaskRemoved()
      ),
    ];

    for (final (name, stub, invoke) in scenarios) {
      test('hanging $name() returns within 5 seconds without throwing', () {
        FakeAsync().run((async) {
          final player = MockAudioPlayer();
          stubStreams(player);
          stub(player);

          final handler = NasAudioHandler(player);

          var completed = false;
          Object? error;
          invoke(handler).then((_) {
            completed = true;
          }).catchError((Object e) {
            error = e;
            completed = true;
          });

          async.elapse(const Duration(seconds: 4));
          expect(completed, isFalse,
              reason: '$name() must not complete before the 5s timeout');

          async.elapse(const Duration(seconds: 2));
          expect(completed, isTrue,
              reason: '$name() must complete after the 5s timeout');
          expect(error, isNull, reason: '$name() must not throw');
          handler.dispose();
        });
      });
    }
  });
}
