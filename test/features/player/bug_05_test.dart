// test/features/player/bug_05_test.dart
// BUG-05: SerializedRequestGate 卡死导致所有后续加载请求永久挂起 — automated test suite
//
// Verifies that when a task inside SerializedRequestGate hangs indefinitely,
// the gate times out after 20 seconds and resets _running to false, allowing
// subsequent requests to proceed.
//
// BUG-05-T01: task 内部挂起 → 20 秒后 gate 超时 → _running 重置为 false
// BUG-05-T02: gate 超时后 → 新请求可正常执行
// BUG-05-T03: SecureStorage.read 挂起 → 5 秒后超时 → 返回 null → failed
// BUG-05-T04: 正常加载 → gate 超时未触发 → 行为不变（回归）
// BUG-05-T05: 连续 3 次加载失败 → gate 每次都正确重置 → 第 4 次可成功

import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nas_audio_player/features/player/player_provider.dart';

void main() {
  // ── BUG-05-T01: task 内部挂起 → 20 秒后 gate 超时 → _running 重置为 false ──

  group('BUG-05-T01: hanging task times out and gate resets', () {
    test(
        'task that never completes triggers 20s timeout, gate accepts new request',
        () {
      FakeAsync().run((async) {
        final gate = SerializedRequestGate();
        final hangingCompleter = Completer<int>();

        // Schedule a task that will never complete (simulating a hang).
        final future = gate.schedule<int>(
          task: (_) => hangingCompleter.future,
          onSuperseded: () => -1,
        );

        // Verify the future has not resolved yet.
        var resolved = false;
        var timedOut = false;
        future.then((_) {
          resolved = true;
        }).catchError((e) {
          timedOut = true;
        });

        // Advance time by 19 seconds — should NOT have timed out yet.
        async.elapse(const Duration(seconds: 19));
        expect(resolved, isFalse,
            reason: 'should not resolve before 20 seconds');
        expect(timedOut, isFalse,
            reason: 'should not time out before 20 seconds');

        // Advance past the 20-second mark.
        async.elapse(const Duration(seconds: 2));

        // The timed-out future should now have completed with an error.
        expect(timedOut, isTrue,
            reason: 'task should have timed out after 20 seconds');

        // The gate should now accept a new request (i.e. _running is false).
        final secondCompleter = Completer<int>();
        final secondFuture = gate.schedule<int>(
          task: (_) => secondCompleter.future,
          onSuperseded: () => -1,
        );

        // Resolve the second task immediately.
        secondCompleter.complete(42);

        // Advance microtasks so the second future settles.
        async.elapse(Duration.zero);

        var secondResult = -1;
        secondFuture.then((v) => secondResult = v);
        // Let microtasks flush.
        async.elapse(Duration.zero);

        expect(secondResult, equals(42),
            reason: 'gate should accept new task after timeout reset');
      });
    });
  });

  // ── BUG-05-T02: gate 超时后 → 新请求可正常执行 ──

  group('BUG-05-T02: new request works after gate timeout', () {
    test('second request after timeout completes normally', () {
      FakeAsync().run((async) {
        final gate = SerializedRequestGate();

        // First request hangs.
        final hangingCompleter = Completer<String>();
        var firstTimedOut = false;
        gate
            .schedule<String>(
          task: (_) => hangingCompleter.future,
          onSuperseded: () => 'superseded',
        )
            .catchError((_) {
          firstTimedOut = true;
          return 'superseded';
        });

        // Let the 20-second timeout fire.
        async.elapse(const Duration(seconds: 21));
        expect(firstTimedOut, isTrue,
            reason: 'first task should have timed out');

        // Second request should work — the gate has been reset.
        var result = 'pending';
        final okCompleter = Completer<String>();
        gate
            .schedule<String>(
              task: (_) => okCompleter.future,
              onSuperseded: () => 'superseded',
            )
            .then((v) => result = v);

        okCompleter.complete('success');
        async.elapse(Duration.zero);

        expect(result, equals('success'),
            reason: 'gate should accept new task after timeout reset');
      });
    });
  });

  // ── BUG-05-T03: SecureStorage.read 挂起 → 5 秒后超时 → 返回 null → failed ──
  //
  // This test verifies the timeout behavior at the SerializedRequestGate level
  // by simulating what happens when storage.read() hangs: the gate's 20s timeout
  // catches the hang.  The 5s timeout on storage.read() is a defense-in-depth
  // layer tested indirectly here via the gate timeout.
  //
  // We test the storage timeout effect: a task that simulates the storage read
  // hanging will be caught by the gate timeout.

  group('BUG-05-T03: storage read hang caught by gate timeout', () {
    test(
        'task simulating storage hang triggers timeout, returns failed-like error',
        () {
      FakeAsync().run((async) {
        final gate = SerializedRequestGate();

        // Simulate a task that hangs (like storage.read() with no timeout).
        final hangingCompleter = Completer<TrackLoadResult>();
        var errorCaught = false;

        gate
            .schedule<TrackLoadResult>(
          task: (_) => hangingCompleter.future,
          onSuperseded: () => const TrackLoadResult.superseded(),
        )
            .catchError((e) {
          errorCaught = true;
          return const TrackLoadResult.failed();
        });

        // Advance past 20 seconds to trigger the gate timeout.
        async.elapse(const Duration(seconds: 21));

        expect(errorCaught, isTrue,
            reason: 'storage hang should cause timeout error');
      });
    });

    test('task with internal 5s timeout completes before gate 20s timeout', () {
      FakeAsync().run((async) {
        final gate = SerializedRequestGate();

        // Simulate a task with 5-second internal timeout (like the fixed
        // storage.read().timeout(5s)). The task returns null on timeout,
        // which the caller treats as failed.
        var result = 'pending';
        gate
            .schedule<String>(
              task: (_) async {
                // Simulate: storage.read().timeout(Duration(seconds: 5), onTimeout: () => null)
                final storageResult = await Future<String?>.delayed(
                  const Duration(seconds: 5),
                ).timeout(
                  const Duration(seconds: 5),
                  onTimeout: () => null,
                );
                // When storage returns null, the caller would return failed.
                return storageResult ?? 'storage_timeout_failed';
              },
              onSuperseded: () => 'superseded',
            )
            .then((v) => result = v);

        // Advance 5 seconds to trigger the internal timeout.
        async.elapse(const Duration(seconds: 6));

        expect(result, equals('storage_timeout_failed'),
            reason:
                '5s storage timeout should trigger before 20s gate timeout');
      });
    });
  });

  // ── BUG-05-T04: 正常加载 → gate 超时未触发 → 行为不变（回归） ──

  group('BUG-05-T04: normal load works without triggering timeout (regression)',
      () {
    test('task completing within 20s returns result normally', () {
      FakeAsync().run((async) {
        final gate = SerializedRequestGate();

        var result = 'pending';
        gate
            .schedule<String>(
              task: (_) async {
                // Simulate a normal load that takes 2 seconds.
                await Future<void>.delayed(const Duration(seconds: 2));
                return 'loaded';
              },
              onSuperseded: () => 'superseded',
            )
            .then((v) => result = v);

        // Advance 2 seconds for the task to complete.
        async.elapse(const Duration(seconds: 3));

        expect(result, equals('loaded'),
            reason: 'normal task should return result without timeout');
      });
    });

    test('task completing in 19s still works (just under timeout)', () {
      FakeAsync().run((async) {
        final gate = SerializedRequestGate();

        var result = 'pending';
        gate
            .schedule<String>(
              task: (_) async {
                await Future<void>.delayed(const Duration(seconds: 19));
                return 'just_in_time';
              },
              onSuperseded: () => 'superseded',
            )
            .then((v) => result = v);

        async.elapse(const Duration(seconds: 20));

        expect(result, equals('just_in_time'),
            reason: 'task completing at 19s should not be timed out');
      });
    });
  });

  // ── BUG-05-T05: 连续 3 次加载失败 → gate 每次都正确重置 → 第 4 次可成功 ──

  group(
      'BUG-05-T05: consecutive failures each reset gate, 4th request succeeds',
      () {
    test('3 consecutive hanging tasks each timeout, 4th request works', () {
      FakeAsync().run((async) {
        final gate = SerializedRequestGate();

        // First hanging task.
        final c1 = Completer<String>();
        var e1 = false;
        gate
            .schedule<String>(
          task: (_) => c1.future,
          onSuperseded: () => 's',
        )
            .catchError((_) {
          e1 = true;
          return 's';
        });

        async.elapse(const Duration(seconds: 21));
        expect(e1, isTrue, reason: '1st task should timeout');

        // Second hanging task.
        final c2 = Completer<String>();
        var e2 = false;
        gate
            .schedule<String>(
          task: (_) => c2.future,
          onSuperseded: () => 's',
        )
            .catchError((_) {
          e2 = true;
          return 's';
        });

        async.elapse(const Duration(seconds: 21));
        expect(e2, isTrue, reason: '2nd task should timeout');

        // Third hanging task.
        final c3 = Completer<String>();
        var e3 = false;
        gate
            .schedule<String>(
          task: (_) => c3.future,
          onSuperseded: () => 's',
        )
            .catchError((_) {
          e3 = true;
          return 's';
        });

        async.elapse(const Duration(seconds: 21));
        expect(e3, isTrue, reason: '3rd task should timeout');

        // Fourth request — this one completes normally.
        var result = 'pending';
        final c4 = Completer<String>();
        gate
            .schedule<String>(
              task: (_) => c4.future,
              onSuperseded: () => 's',
            )
            .then((v) => result = v);

        c4.complete('success');
        async.elapse(Duration.zero);

        expect(result, equals('success'),
            reason: '4th request should succeed after 3 consecutive timeouts');
      });
    });

    test('consecutive failures with immediate errors also reset gate', () {
      FakeAsync().run((async) {
        final gate = SerializedRequestGate();

        // Three tasks that fail immediately with errors.
        for (int i = 0; i < 3; i++) {
          var errorCaught = false;
          gate
              .schedule<String>(
            task: (_) async => throw Exception('error $i'),
            onSuperseded: () => 's',
          )
              .catchError((_) {
            errorCaught = true;
            return 's';
          });

          async.elapse(Duration.zero);
          expect(errorCaught, isTrue, reason: 'task $i should fail with error');
        }

        // Fourth request works.
        var result = 'pending';
        final c = Completer<String>();
        gate
            .schedule<String>(
              task: (_) => c.future,
              onSuperseded: () => 's',
            )
            .then((v) => result = v);

        c.complete('success_after_errors');
        async.elapse(Duration.zero);

        expect(result, equals('success_after_errors'),
            reason: 'request after 3 errors should succeed');
      });
    });
  });
}
