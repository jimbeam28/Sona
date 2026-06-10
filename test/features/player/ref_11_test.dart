// test/features/player/ref_11_test.dart
// REF-11: player/domain/request_gate.dart — extracted SerializedRequestGate tests
//
// Verifies that SerializedRequestGate, PlayerLoadStatus, TrackLoadStatus,
// and TrackLoadResult behave correctly as extracted domain classes.
//
// REF-11-T01: single request executes normally
// REF-11-T02: concurrent requests → latest request wins
// REF-11-T03: queued request is superseded → returns superseded
// REF-11-T04: queued request auto-starts after current completes

import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nas_audio_player/features/player/domain/request_gate.dart';

void main() {
  // ── REF-11-T01: single request executes normally ────────────────────────

  group('REF-11-T01: single request executes normally', () {
    test('single immediate task returns its result', () {
      FakeAsync().run((async) {
        final gate = SerializedRequestGate();
        var result = -1;

        gate
            .schedule<int>(
              task: (_) async => 42,
              onSuperseded: () => -1,
            )
            .then((v) => result = v);

        async.elapse(Duration.zero);
        expect(result, equals(42));
      });
    });

    test('single delayed task returns its result after delay', () {
      FakeAsync().run((async) {
        final gate = SerializedRequestGate();
        var result = -1;

        gate
            .schedule<int>(
              task: (_) async {
                await Future<void>.delayed(const Duration(seconds: 2));
                return 99;
              },
              onSuperseded: () => -1,
            )
            .then((v) => result = v);

        async.elapse(const Duration(seconds: 3));
        expect(result, equals(99));
      });
    });

    test('single failing task propagates the error', () {
      FakeAsync().run((async) {
        final gate = SerializedRequestGate();
        var errorCaught = false;

        gate
            .schedule<String>(
          task: (_) async => throw Exception('boom'),
          onSuperseded: () => 'superseded',
        )
            .catchError((_) {
          errorCaught = true;
          return 'superseded';
        });

        async.elapse(Duration.zero);
        expect(errorCaught, isTrue);
      });
    });

    test('isLatest returns true for the current request', () {
      final gate = SerializedRequestGate();
      final id = gate.beginRequest();
      expect(gate.isLatest(id), isTrue);
    });

    test('isLatest returns false after a newer request', () {
      final gate = SerializedRequestGate();
      final id1 = gate.beginRequest();
      gate.beginRequest(); // newer
      expect(gate.isLatest(id1), isFalse);
    });
  });

  // ── REF-11-T02: concurrent requests → latest request wins ───────────────

  group('REF-11-T02: concurrent requests → latest request wins', () {
    test('second request supersedes first when first is still running', () {
      FakeAsync().run((async) {
        final gate = SerializedRequestGate();
        var firstResult = 'pending';
        var secondResult = 'pending';

        // First request — takes 5 seconds.
        gate
            .schedule<String>(
              task: (_) async {
                await Future<void>.delayed(const Duration(seconds: 5));
                return 'first';
              },
              onSuperseded: () => 'superseded',
            )
            .then((v) => firstResult = v);

        // Second request — arrives while first is running, queued as pending.
        gate
            .schedule<String>(
              task: (_) async => 'second',
              onSuperseded: () => 'superseded',
            )
            .then((v) => secondResult = v);

        // At 5 seconds: first completes, second auto-starts and finishes.
        async.elapse(const Duration(seconds: 6));

        expect(secondResult, equals('second'),
            reason: 'latest request should complete with its result');
        expect(firstResult, equals('superseded'),
            reason: 'first request should be superseded');
      });
    });

    test('third request supersedes second which supersedes first', () {
      FakeAsync().run((async) {
        final gate = SerializedRequestGate();
        var r1 = 'pending', r2 = 'pending', r3 = 'pending';

        // First — takes 10 seconds.
        gate
            .schedule<String>(
              task: (_) async {
                await Future<void>.delayed(const Duration(seconds: 10));
                return 'first';
              },
              onSuperseded: () => 'superseded',
            )
            .then((v) => r1 = v);

        // Second — arrives while first is running, queued as pending.
        gate
            .schedule<String>(
              task: (_) async {
                await Future<void>.delayed(const Duration(seconds: 5));
                return 'second';
              },
              onSuperseded: () => 'superseded',
            )
            .then((v) => r2 = v);

        // Third — arrives while second is queued, replaces second.
        gate
            .schedule<String>(
              task: (_) async => 'third',
              onSuperseded: () => 'superseded',
            )
            .then((v) => r3 = v);

        // At 10s: first completes. Third (the pending) auto-starts and
        // completes immediately.
        async.elapse(const Duration(seconds: 11));

        expect(r3, equals('third'),
            reason:
                'third (latest pending) should complete after first finishes');
        expect(r2, equals('superseded'),
            reason: 'second should be superseded by third');
        expect(r1, equals('superseded'),
            reason:
                'first should be superseded (third was latest when first ran)');
      });
    });
  });

  // ── REF-11-T03: queued request is superseded → returns superseded ───────

  group('REF-11-T03: queued request is superseded → returns superseded', () {
    test('pending request receives superseded result when replaced', () {
      FakeAsync().run((async) {
        final gate = SerializedRequestGate();
        var pendingResult = 'pending';

        // First request — long-running.
        gate.schedule<String>(
          task: (_) async {
            await Future<void>.delayed(const Duration(seconds: 5));
            return 'first';
          },
          onSuperseded: () => 'superseded',
        );

        // Second request — replaces the pending one.
        gate
            .schedule<String>(
              task: (_) async => 'second',
              onSuperseded: () => 'superseded',
            )
            .then((v) => pendingResult = v);

        // Third request — replaces the second pending one.
        gate.schedule<String>(
          task: (_) async => 'third',
          onSuperseded: () => 'superseded',
        );

        // Third runs immediately.
        async.elapse(Duration.zero);

        // Second was superseded by third.
        async.elapse(Duration.zero);
        expect(pendingResult, equals('superseded'),
            reason: 'second request should be superseded by third');
      });
    });

    test('superseded callback is called with correct value', () {
      FakeAsync().run((async) {
        final gate = SerializedRequestGate();
        var result = 'pending';

        // First — long-running.
        gate.schedule<String>(
          task: (_) async {
            await Future<void>.delayed(const Duration(seconds: 5));
            return 'first';
          },
          onSuperseded: () => 'dropped',
        );

        // Second — replaces first's pending spot.
        gate
            .schedule<String>(
              task: (_) async => 'second',
              onSuperseded: () => 'dropped',
            )
            .then((v) => result = v);

        // Third — replaces second.
        gate.schedule<String>(
          task: (_) async => 'third',
          onSuperseded: () => 'dropped',
        );

        async.elapse(Duration.zero);
        async.elapse(Duration.zero);

        expect(result, equals('dropped'),
            reason: 'onSuperseded callback value should be returned');
      });
    });
  });

  // ── REF-11-T04: queued request auto-starts after current completes ──────

  group('REF-11-T04: queued request auto-starts after current completes', () {
    test('queued request starts automatically when running request finishes',
        () {
      FakeAsync().run((async) {
        final gate = SerializedRequestGate();
        var result = 'pending';

        // First request — takes 3 seconds.
        gate.schedule<String>(
          task: (_) async {
            await Future<void>.delayed(const Duration(seconds: 3));
            return 'first';
          },
          onSuperseded: () => 'superseded',
        );

        // Second request — queued while first runs, and it is the latest
        // so it should NOT be superseded.  But it should wait for the first
        // to finish before executing.
        //
        // To avoid the second being superseded, we don't schedule a third.
        // Instead we schedule only two: first is running, second is queued.
        final secondFuture = gate.schedule<String>(
          task: (_) async => 'second',
          onSuperseded: () => 'superseded',
        );
        secondFuture.then((v) => result = v);

        // After 3 seconds, first completes and second auto-starts.
        async.elapse(const Duration(seconds: 4));

        expect(result, equals('second'),
            reason: 'queued request should auto-start after first completes');
      });
    });

    test('queued request with delay starts after current completes', () {
      FakeAsync().run((async) {
        final gate = SerializedRequestGate();
        var firstDone = false;
        var secondDone = false;

        // First — takes 2 seconds.
        gate.schedule<String>(
          task: (_) async {
            await Future<void>.delayed(const Duration(seconds: 2));
            firstDone = true;
            return 'first';
          },
          onSuperseded: () => 'superseded',
        );

        // Second — queued, takes 1 second once it starts.
        gate.schedule<String>(
          task: (_) async {
            await Future<void>.delayed(const Duration(seconds: 1));
            secondDone = true;
            return 'second';
          },
          onSuperseded: () => 'superseded',
        );

        // After 2 seconds: first done, second starts.
        async.elapse(const Duration(seconds: 2));
        expect(firstDone, isTrue, reason: 'first should be done at 2s');
        expect(secondDone, isFalse,
            reason: 'second should not be done yet at 2s');

        // After 3 seconds: second also done.
        async.elapse(const Duration(seconds: 1));
        expect(secondDone, isTrue, reason: 'second should be done at 3s');
      });
    });

    test('queue drains in order: only the latest pending runs', () {
      FakeAsync().run((async) {
        final gate = SerializedRequestGate();
        var executionOrder = <String>[];

        // First — takes 3 seconds.
        gate.schedule<String>(
          task: (_) async {
            await Future<void>.delayed(const Duration(seconds: 3));
            executionOrder.add('first');
            return 'first';
          },
          onSuperseded: () => 'superseded',
        );

        // Second — queued, will be replaced by third.
        gate.schedule<String>(
          task: (_) async {
            executionOrder.add('second');
            return 'second';
          },
          onSuperseded: () => 'superseded',
        );

        // Third — replaces second in the queue.
        final thirdFuture = gate.schedule<String>(
          task: (_) async {
            executionOrder.add('third');
            return 'third';
          },
          onSuperseded: () => 'superseded',
        );

        var thirdResult = 'pending';
        thirdFuture.then((v) => thirdResult = v);

        // At 3s: first completes, third (the pending one) auto-starts.
        async.elapse(const Duration(seconds: 4));

        expect(executionOrder, equals(['first', 'third']),
            reason: 'only first and third should execute; second was replaced');
        expect(thirdResult, equals('third'));
      });
    });
  });

  // ── Extra: PlayerLoadStatus and TrackLoadStatus enums ────────────────────

  group('REF-11: extracted enums are accessible', () {
    test('PlayerLoadStatus has all expected values', () {
      expect(PlayerLoadStatus.values.length, equals(4));
      expect(PlayerLoadStatus.idle, isNotNull);
      expect(PlayerLoadStatus.loading, isNotNull);
      expect(PlayerLoadStatus.ready, isNotNull);
      expect(PlayerLoadStatus.error, isNotNull);
    });

    test('TrackLoadStatus has all expected values', () {
      expect(TrackLoadStatus.values.length, equals(3));
      expect(TrackLoadStatus.loaded, isNotNull);
      expect(TrackLoadStatus.failed, isNotNull);
      expect(TrackLoadStatus.superseded, isNotNull);
    });
  });
}
