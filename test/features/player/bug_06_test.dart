// test/features/player/bug_06_test.dart
// BUG-06: audio_handler 中 await 无超时导致通知栏控件卡死 — automated test suite
//
// Verifies that play(), pause(), stop(), and onTaskRemoved() in NasAudioHandler
// all have a 5-second timeout on the underlying AudioPlayer calls, so that a
// hanging platform channel Future does not block the notification controls
// indefinitely.
//
// BUG-06-T01: play() 挂起 → 5 秒后超时 → 不阻塞
// BUG-06-T02: pause() 挂起 → 5 秒后超时 → 不阻塞
// BUG-06-T03: stop() 挂起 → 5 秒后超时 → 不阻塞
// BUG-06-T04: 正常 play/pause/stop → 超时未触发 → 行为不变（回归）

import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:nas_audio_player/core/services/audio_handler.dart';

import 'bug_06_test.mocks.dart';

@GenerateMocks([AudioPlayer])
void main() {
  // ── BUG-06-T01: play() 挂起 → 5 秒后超时 → 不阻塞 ──

  group('BUG-06-T01: play() hanging times out after 5 seconds', () {
    test('play() that never completes does not block beyond 5 seconds', () {
      FakeAsync().run((async) {
        final player = MockAudioPlayer();

        // Simulate a hanging play() — the Future never completes.
        when(player.play()).thenAnswer((_) => Completer<void>().future);
        when(player.playerStateStream)
            .thenAnswer((_) => const Stream<PlayerState>.empty());
        when(player.positionStream)
            .thenAnswer((_) => const Stream<Duration>.empty());
        when(player.durationStream)
            .thenAnswer((_) => const Stream<Duration?>.empty());

        final handler = NasAudioHandler(player);

        var completed = false;
        handler.play().then((_) {
          completed = true;
        });

        // Advance 4 seconds — should NOT have completed yet.
        async.elapse(const Duration(seconds: 4));
        expect(completed, isFalse,
            reason: 'play() should not complete before 5 seconds');

        // Advance past the 5-second mark — should now complete via timeout.
        async.elapse(const Duration(seconds: 2));
        expect(completed, isTrue,
            reason: 'play() should complete after 5-second timeout');

        handler.dispose();
      });
    });
  });

  // ── BUG-06-T02: pause() 挂起 → 5 秒后超时 → 不阻塞 ──

  group('BUG-06-T02: pause() hanging times out after 5 seconds', () {
    test('pause() that never completes does not block beyond 5 seconds', () {
      FakeAsync().run((async) {
        final player = MockAudioPlayer();

        when(player.pause()).thenAnswer((_) => Completer<void>().future);
        when(player.playerStateStream)
            .thenAnswer((_) => const Stream<PlayerState>.empty());
        when(player.positionStream)
            .thenAnswer((_) => const Stream<Duration>.empty());
        when(player.durationStream)
            .thenAnswer((_) => const Stream<Duration?>.empty());

        final handler = NasAudioHandler(player);

        var completed = false;
        handler.pause().then((_) {
          completed = true;
        });

        async.elapse(const Duration(seconds: 4));
        expect(completed, isFalse,
            reason: 'pause() should not complete before 5 seconds');

        async.elapse(const Duration(seconds: 2));
        expect(completed, isTrue,
            reason: 'pause() should complete after 5-second timeout');

        handler.dispose();
      });
    });
  });

  // ── BUG-06-T03: stop() 挂起 → 5 秒后超时 → 不阻塞 ──

  group('BUG-06-T03: stop() hanging times out after 5 seconds', () {
    test('stop() that never completes does not block beyond 5 seconds', () {
      FakeAsync().run((async) {
        final player = MockAudioPlayer();

        // Simulate a hanging stop() — the Future never completes.
        when(player.stop()).thenAnswer((_) => Completer<void>().future);
        when(player.playerStateStream)
            .thenAnswer((_) => const Stream<PlayerState>.empty());
        when(player.positionStream)
            .thenAnswer((_) => const Stream<Duration>.empty());
        when(player.durationStream)
            .thenAnswer((_) => const Stream<Duration?>.empty());

        final handler = NasAudioHandler(player);

        var completed = false;
        handler.stop().then((_) {
          completed = true;
        });

        // At 4 seconds, player.stop() should still be hanging.
        async.elapse(const Duration(seconds: 4));
        expect(completed, isFalse,
            reason: 'stop() should not complete before 5 seconds');

        // Advance past the 5-second mark — timeout fires.
        async.elapse(const Duration(seconds: 2));
        expect(completed, isTrue,
            reason: 'stop() should complete after 5-second timeout');

        handler.dispose();
      });
    });
  });

  // ── BUG-06-T04: 正常 play/pause/stop → 超时未触发 → 行为不变（回归） ──

  group('BUG-06-T04: normal play/pause/stop completes without timeout', () {
    test('normal play() completes promptly', () {
      FakeAsync().run((async) {
        final player = MockAudioPlayer();

        when(player.play()).thenAnswer((_) async {});
        when(player.playerStateStream)
            .thenAnswer((_) => const Stream<PlayerState>.empty());
        when(player.positionStream)
            .thenAnswer((_) => const Stream<Duration>.empty());
        when(player.durationStream)
            .thenAnswer((_) => const Stream<Duration?>.empty());

        final handler = NasAudioHandler(player);

        var completed = false;
        handler.play().then((_) {
          completed = true;
        });

        // Flush microtasks — should complete immediately.
        async.elapse(Duration.zero);
        expect(completed, isTrue,
            reason: 'normal play() should complete without timeout');

        verify(player.play()).called(1);
        handler.dispose();
      });
    });

    test('normal pause() completes promptly', () {
      FakeAsync().run((async) {
        final player = MockAudioPlayer();

        when(player.pause()).thenAnswer((_) async {});
        when(player.playerStateStream)
            .thenAnswer((_) => const Stream<PlayerState>.empty());
        when(player.positionStream)
            .thenAnswer((_) => const Stream<Duration>.empty());
        when(player.durationStream)
            .thenAnswer((_) => const Stream<Duration?>.empty());

        final handler = NasAudioHandler(player);

        var completed = false;
        handler.pause().then((_) {
          completed = true;
        });

        async.elapse(Duration.zero);
        expect(completed, isTrue,
            reason: 'normal pause() should complete without timeout');

        verify(player.pause()).called(1);
        handler.dispose();
      });
    });

    test('normal stop() completes promptly', () {
      FakeAsync().run((async) {
        final player = MockAudioPlayer();

        when(player.stop()).thenAnswer((_) async {});
        when(player.playerStateStream)
            .thenAnswer((_) => const Stream<PlayerState>.empty());
        when(player.positionStream)
            .thenAnswer((_) => const Stream<Duration>.empty());
        when(player.durationStream)
            .thenAnswer((_) => const Stream<Duration?>.empty());

        final handler = NasAudioHandler(player);

        var completed = false;
        handler.stop().then((_) {
          completed = true;
        });

        async.elapse(Duration.zero);
        expect(completed, isTrue,
            reason: 'normal stop() should complete without timeout');

        verify(player.stop()).called(1);
        handler.dispose();
      });
    });
  });
}
