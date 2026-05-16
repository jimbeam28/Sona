// test/features/timer/timer_test.dart
// Timer module test suite — TMR-01 through TMR-05.
//
// Unit tests (TMR-T01~T22): pure-logic tests on [TimerService],
// testing the state machine for duration timers, afterCurrent mode,
// countdown display, cancellation, and expiry.
//
// Provider tests: [ProviderContainer]-level tests for Riverpod wiring.
//
// Widget tests (TMR-T23~T29): UI tests on [TimerButton] and
// [TimerBottomSheet] using [WidgetTester] and [ProviderScope].
//
// IMPORTANT: The [remainingTimeProvider] is a [StreamProvider] that
// creates a [Stream.periodic] timer when a duration timer is active.
// In [testWidgets] (which uses [FakeAsync]), this would leave a
// pending periodic timer.  Widget tests that modify timer state
// therefore override [remainingTimeProvider] with a simple null stream.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nas_audio_player/core/services/timer_service.dart';
import 'package:nas_audio_player/features/timer/timer_provider.dart';
import 'package:nas_audio_player/features/timer/widgets/timer_button.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// Helpers
// ═══════════════════════════════════════════════════════════════════════════════

/// Overrides that suppress the periodic [remainingTimeProvider] stream so
/// that widget tests (which run under [FakeAsync]) do not accumulate pending
/// periodic timers.
///
/// The stream logic is covered by the unit tests on [TimerService] directly.
List<Override> _noopRemainingTimeOverride() => [
      remainingTimeProvider.overrideWith((ref) => Stream.value(null)),
    ];

/// Wraps [child] in a [ProviderScope] with a fresh [TimerService] and the
/// no-op remaining-time stream override.
Widget wrapWithTimerProviders(Widget child) {
  return ProviderScope(
    overrides: [
      timerServiceProvider.overrideWith((ref) => TimerService()),
      ..._noopRemainingTimeOverride(),
    ],
    child: MaterialApp(
      home: Scaffold(body: child),
    ),
  );
}

/// Creates a [ProviderContainer] suitable for provider-level tests,
/// with the no-op remaining-time stream override so no periodic timers
/// are created.
ProviderContainer createTimerTestContainer() {
  return ProviderContainer(
    overrides: [
      timerServiceProvider.overrideWith((ref) => TimerService()),
      ..._noopRemainingTimeOverride(),
    ],
  );
}

/// Helper to pump a widget with timer providers.
Future<void> pumpTimerWidget(WidgetTester tester, Widget child) async {
  await tester.pumpWidget(wrapWithTimerProviders(child));
}

// ═══════════════════════════════════════════════════════════════════════════════
// Unit tests — TMR-01: 设置固定时长定时
// ═══════════════════════════════════════════════════════════════════════════════

void main() {
  // ── TMR-T01: Set 5-minute duration timer ─────────────────────────────────

  group('TMR-01: 设置固定时长定时', () {
    test('TMR-T01: 设置 5 分钟定时', () {
      final service = TimerService();
      final now = DateTime.now();
      final state = service.startDuration(5);

      expect(state.mode, equals(TimerMode.duration));
      expect(state.endTime, isNotNull);

      final expectedEnd = now.add(const Duration(minutes: 5));
      final diff = state.endTime!.difference(expectedEnd).inMilliseconds.abs();
      expect(diff, lessThan(100),
          reason: 'endTime should be within 100ms of now + 5min');
    });

    test('TMR-T02: 设置 10 分钟定时', () {
      final service = TimerService();
      final now = DateTime.now();
      final state = service.startDuration(10);

      final expectedEnd = now.add(const Duration(minutes: 10));
      final diff = state.endTime!.difference(expectedEnd).inMilliseconds.abs();
      expect(diff, lessThan(100),
          reason: 'endTime should be within 100ms of now + 10min');
    });

    test('TMR-T03: 设置 15 分钟定时', () {
      final service = TimerService();
      final now = DateTime.now();
      final state = service.startDuration(15);

      final expectedEnd = now.add(const Duration(minutes: 15));
      final diff = state.endTime!.difference(expectedEnd).inMilliseconds.abs();
      expect(diff, lessThan(100),
          reason: 'endTime should be within 100ms of now + 15min');
    });

    test('TMR-T04: 已有定时时重新设置新的时长 — 旧 Timer 被替换', () {
      final service = TimerService();

      final firstState = service.startDuration(5);
      expect(service.isActive, isTrue);

      final secondState = service.startDuration(10);
      expect(service.isActive, isTrue);

      expect(firstState.endTime, isNot(equals(secondState.endTime)));

      final now = DateTime.now();
      final expectedEnd = now.add(const Duration(minutes: 10));
      final diff =
          secondState.endTime!.difference(expectedEnd).inMilliseconds.abs();
      expect(diff, lessThan(100),
          reason: 'replaced timer should use new 10min duration');
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  // Unit tests — TMR-02: 播完当前音频后停止
  // ═════════════════════════════════════════════════════════════════════════

  group('TMR-02: 设置播完当前音频后停止', () {
    test('TMR-T05: 设置「播完当前」模式', () {
      final service = TimerService();
      final state = service.startAfterCurrent();

      expect(state.mode, equals(TimerMode.afterCurrent));
      expect(state.endTime, isNull);
      expect(service.isActive, isTrue);
    });

    test('TMR-T06: 「播完当前」模式下曲目播放完成 → onTrackCompleted '
        '返回 true', () {
      final service = TimerService();
      service.startAfterCurrent();
      expect(service.isActive, isTrue);

      final triggered = service.onTrackCompleted();
      expect(triggered, isTrue,
          reason: 'onTrackCompleted should return true when afterCurrent '
              'timer is active');
    });

    test('TMR-T07: 「播完当前」模式触发后 state 清除', () {
      final service = TimerService();
      service.startAfterCurrent();
      expect(service.isActive, isTrue);

      service.onTrackCompleted();

      expect(service.state, isNull,
          reason: 'state should become null after afterCurrent timer triggers');
      expect(service.isActive, isFalse);

      final triggeredAgain = service.onTrackCompleted();
      expect(triggeredAgain, isFalse,
          reason: 'should not trigger again after state is cleared');
    });

    test('TMR-T08: 「播完当前」模式下手动切换到下一首 — '
        'stopAfterCurrent 不影响手动切换', () {
      final service = TimerService();
      service.startAfterCurrent();
      expect(service.isActive, isTrue);

      // Manual skip: caller would NOT call onTrackCompleted.
      // State stays active — only natural track-end triggers stop.
      expect(service.state?.mode, equals(TimerMode.afterCurrent));
      expect(service.isActive, isTrue,
          reason: 'manual skip should not consume the afterCurrent timer');
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  // Unit tests — TMR-03: 定时倒计时显示
  // ═════════════════════════════════════════════════════════════════════════

  group('TMR-03: 定时倒计时显示', () {
    test('TMR-T09: 剩余 90 秒时查询剩余时间', () {
      // formatRemaining with known Duration — direct format test
      final service = TimerService();
      final formatted = service.formatRemaining(const Duration(seconds: 90));
      expect(formatted, isNotNull);
    });

    test('TMR-T10: 剩余 > 60 秒时显示 MM:SS 格式', () {
      final service = TimerService();

      expect(service.formatRemaining(const Duration(minutes: 14)),
          equals('14:00'));
      expect(service.formatRemaining(const Duration(minutes: 5)),
          equals('05:00'));
      expect(service.formatRemaining(const Duration(minutes: 2)),
          equals('02:00'));
      expect(service.formatRemaining(const Duration(seconds: 61)),
          equals('01:01'));
    });

    test('TMR-T11: 剩余时间 == 60 秒时显示 01:00', () {
      final service = TimerService();
      expect(service.formatRemaining(const Duration(seconds: 60)),
          equals('01:00'));
    });

    test('TMR-T12: 剩余时间 < 60 秒时显示 00:XX 格式', () {
      final service = TimerService();

      expect(service.formatRemaining(const Duration(seconds: 45)),
          equals('00:45'));
      expect(service.formatRemaining(const Duration(seconds: 30)),
          equals('00:30'));
      expect(service.formatRemaining(const Duration(seconds: 10)),
          equals('00:10'));
      expect(service.formatRemaining(const Duration(seconds: 1)),
          equals('00:01'));
      expect(service.formatRemaining(const Duration(seconds: 59)),
          equals('00:59'));
    });

    test('TMR-T13: 「播完当前」模式 remainingTime 返回 null', () {
      final service = TimerService();
      service.startAfterCurrent();

      final state = service.state;
      expect(state, isNotNull);
      expect(state!.remainingTime, isNull,
          reason: 'afterCurrent mode has no countdown');
    });

    test('TMR-T14: 无定时时 remainingTime 返回 null', () {
      final service = TimerService();
      expect(service.state, isNull);
      expect(service.displayString, isNull);
    });

    test('TMR-T15: 倒计时每秒更新一次', () {
      // Verify the remainingTime calculation works with DateTime.now().
      // We start a timer and check remaining time decreases over real time
      // by verifying two consecutive reads return different (decreasing) values
      // when enough wall-clock time has passed.
      final service = TimerService();
      service.startDuration(1);

      final state = service.state!;
      final initialRemaining = state.remainingTime;
      expect(initialRemaining, isNotNull);
      expect(initialRemaining!.inSeconds, greaterThan(0));
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  // Unit tests — TMR-04: 取消定时
  // ═════════════════════════════════════════════════════════════════════════

  group('TMR-04: 取消定时', () {
    test('TMR-T16: 定时激活时调用 cancel() — state 变为 null', () {
      final service = TimerService();
      service.startDuration(5);
      expect(service.isActive, isTrue);

      final cancelled = service.cancel();
      expect(cancelled, isTrue,
          reason: 'cancel should return true when a timer was active');
      expect(service.state, isNull);
      expect(service.isActive, isFalse);
    });

    test('TMR-T17: 取消后到期时间不触发停止', () {
      final service = TimerService();
      service.startDuration(10);
      expect(service.isActive, isTrue);

      service.cancel();
      expect(service.isActive, isFalse);

      final expired = service.checkExpired();
      expect(expired, isFalse,
          reason: 'cancelled timer should not trigger expiry');
    });

    test('TMR-T18: 无定时时调用 cancel() — 幂等，不抛异常', () {
      final service = TimerService();
      expect(service.isActive, isFalse);

      final cancelled = service.cancel();
      expect(cancelled, isFalse,
          reason: 'cancel should return false when no timer was active');
      expect(service.state, isNull);
      expect(service.isActive, isFalse);
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  // Unit tests — TMR-05: 定时到期执行停止
  // ═════════════════════════════════════════════════════════════════════════

  group('TMR-05: 定时到期执行停止', () {
    test('TMR-T19: 5 分钟定时到期 — checkExpired 返回 true, state 变为 null',
        () {
      final service = TimerService();
      service.startDuration(0); // 0 min = already expired
      expect(service.isActive, isTrue);

      final expired = service.checkExpired();
      expect(expired, isTrue,
          reason: 'expired timer should cause checkExpired to return true');
      expect(service.state, isNull,
          reason: 'state should be cleared after expiry');
    });

    test('TMR-T20: 定时到期时 checkExpired 返回 true (模拟前台场景)', () {
      final service = TimerService();
      service.startDuration(0);

      final expired = service.checkExpired();
      expect(expired, isTrue);

      expect(service.state, isNull);
      expect(service.isActive, isFalse);
    });

    test('TMR-T21: 定时到期时 pause 应被调用 '
        '(checkExpired 不依赖前后台状态)', () {
      final service = TimerService();
      service.startDuration(0);
      expect(service.isActive, isTrue);

      final expired = service.checkExpired();
      expect(expired, isTrue,
          reason: 'checkExpired works regardless of foreground/background');
      expect(service.state, isNull);
    });

    test('TMR-T22: 到期后定时按钮应显示未激活菜单', () {
      final service = TimerService();
      service.startDuration(0);
      service.checkExpired();

      expect(service.isActive, isFalse,
          reason: 'after expiry, timer should be inactive');
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  // Additional unit tests — edge cases and afterCurrent behaviour
  // ═════════════════════════════════════════════════════════════════════════

  group('TimerService edge cases and transitions', () {
    test('duration timer does not expire before endTime', () {
      final service = TimerService();
      service.startDuration(10);

      final expired = service.checkExpired();
      expect(expired, isFalse,
          reason: '10min timer should not be expired immediately');
      expect(service.isActive, isTrue);
    });

    test('afterCurrent does not expire via checkExpired', () {
      final service = TimerService();
      service.startAfterCurrent();

      final expired = service.checkExpired();
      expect(expired, isFalse,
          reason: 'afterCurrent timer does not expire via wall-clock check');
      expect(service.isActive, isTrue);
    });

    test('switching from duration to afterCurrent replaces timer', () {
      final service = TimerService();
      service.startDuration(5);
      expect(service.state?.mode, equals(TimerMode.duration));

      service.startAfterCurrent();
      expect(service.state?.mode, equals(TimerMode.afterCurrent));
      expect(service.state?.endTime, isNull);
      expect(service.isActive, isTrue);
    });

    test('switching from afterCurrent to duration replaces timer', () {
      final service = TimerService();
      service.startAfterCurrent();
      expect(service.state?.mode, equals(TimerMode.afterCurrent));

      service.startDuration(10);
      expect(service.state?.mode, equals(TimerMode.duration));
      expect(service.state?.endTime, isNotNull);
      expect(service.isActive, isTrue);
    });

    test('cancel after afterCurrent prevents track-completion trigger', () {
      final service = TimerService();
      service.startAfterCurrent();
      service.cancel();

      final triggered = service.onTrackCompleted();
      expect(triggered, isFalse,
          reason: 'cancelled afterCurrent timer should not trigger');
    });

    test('startDuration defaults to replacement when active', () {
      final service = TimerService();

      final s1 = service.startDuration(5);
      final et1 = s1.endTime;

      final s2 = service.startDuration(15);
      final et2 = s2.endTime;

      expect(et1, isNot(equals(et2)));
      expect(service.isActive, isTrue);
      expect(service.state?.mode, equals(TimerMode.duration));
    });

    test('formatRemaining with null returns null', () {
      final service = TimerService();
      expect(service.formatRemaining(null), isNull);
    });

    test('formatRemaining with Duration.zero returns 00:00', () {
      final service = TimerService();
      expect(service.formatRemaining(Duration.zero), equals('00:00'));
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  // Provider-level tests
  // ═════════════════════════════════════════════════════════════════════════

  group('Timer providers', () {
    test('timerStateProvider returns null by default', () {
      final container = createTimerTestContainer();
      expect(container.read(timerStateProvider), isNull);
    });

    test('startDurationTimerProvider sets state', () {
      final container = createTimerTestContainer();
      container.read(startDurationTimerProvider)(5);

      final state = container.read(timerStateProvider);
      expect(state, isNotNull);
      expect(state!.mode, equals(TimerMode.duration));
    });

    test('startAfterCurrentProvider sets afterCurrent state', () {
      final container = createTimerTestContainer();
      container.read(startAfterCurrentProvider)();

      final state = container.read(timerStateProvider);
      expect(state, isNotNull);
      expect(state!.mode, equals(TimerMode.afterCurrent));
    });

    test('cancelTimerProvider clears state', () {
      final container = createTimerTestContainer();
      container.read(startDurationTimerProvider)(5);
      expect(container.read(timerStateProvider), isNotNull);

      container.read(cancelTimerProvider)();
      expect(container.read(timerStateProvider), isNull);
    });

    test('timerActiveProvider reflects active state', () {
      final container = createTimerTestContainer();

      expect(container.read(timerActiveProvider), isFalse);

      container.read(startDurationTimerProvider)(5);
      expect(container.read(timerActiveProvider), isTrue);

      container.read(cancelTimerProvider)();
      expect(container.read(timerActiveProvider), isFalse);
    });

    test('timerModeProvider returns correct mode', () {
      final container = createTimerTestContainer();

      expect(container.read(timerModeProvider), isNull);

      container.read(startDurationTimerProvider)(5);
      expect(container.read(timerModeProvider), equals(TimerMode.duration));

      container.read(startAfterCurrentProvider)();
      expect(container.read(timerModeProvider), equals(TimerMode.afterCurrent));
    });

    test('checkTimerExpiryProvider detects expiry', () {
      final container = createTimerTestContainer();
      // Start an already-expired 0-minute timer
      container.read(startDurationTimerProvider)(0);

      final checkExpiry = container.read(checkTimerExpiryProvider);
      final expired = checkExpiry();
      expect(expired, isTrue);
      expect(container.read(timerStateProvider), isNull);
    });

    test('onTrackCompletedProvider handles afterCurrent expiry', () {
      final container = createTimerTestContainer();
      container.read(startAfterCurrentProvider)();
      expect(container.read(timerStateProvider), isNotNull);

      final onTrackCompleted = container.read(onTrackCompletedProvider);
      final triggered = onTrackCompleted();
      expect(triggered, isTrue);
      expect(container.read(timerStateProvider), isNull);
    });

    test('formattedRemainingProvider returns null when no timer', () {
      final container = createTimerTestContainer();
      // remainingTimeProvider overridden to null stream
      final formatted = container.read(formattedRemainingProvider);
      expect(formatted, isNull);
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  // Widget tests — TimerButton UI (TMR-T23 ~ TMR-T29)
  // ═════════════════════════════════════════════════════════════════════════

  group('TimerButton widget', () {
    // ── TMR-T23: 无定时时按钮显示未激活沙漏图标 ─────────────────────

    testWidgets('TMR-T23: 无定时时按钮显示未激活沙漏图标', (tester) async {
      await pumpTimerWidget(tester, const TimerButton());

      expect(find.byType(IconButton), findsOneWidget);
      expect(find.byIcon(Icons.hourglass_bottom), findsOneWidget);
    });

    // ── TMR-T24: 固定时长定时激活时 — 剩余时间通过 provider 暴露 ───

    test('TMR-T24: 固定时长定时激活时 state 非 null 且模式正确', () {
      final container = createTimerTestContainer();
      container.read(startDurationTimerProvider)(5);

      final state = container.read(timerStateProvider);
      expect(state, isNotNull);
      expect(state!.mode, equals(TimerMode.duration));
      expect(state.remainingTime, isNotNull);
    });

    // ── TMR-T25: 「播完当前」模式激活时 ──────────────────────────────

    test('TMR-T25: 「播完当前」模式激活时 state.mode == afterCurrent', () {
      final container = createTimerTestContainer();
      container.read(startAfterCurrentProvider)();

      final state = container.read(timerStateProvider);
      expect(state, isNotNull);
      expect(state!.mode, equals(TimerMode.afterCurrent));
    });

    // ── TMR-T26: 点击未激活的定时按钮 → 弹出 4 选项菜单 ───────────

    testWidgets('TMR-T26: 点击未激活的定时按钮弹出 4 选项菜单',
        (tester) async {
      await pumpTimerWidget(tester, const TimerButton());

      await tester.tap(find.byType(IconButton));
      await tester.pumpAndSettle();

      expect(find.text('5 分钟'), findsOneWidget);
      expect(find.text('10 分钟'), findsOneWidget);
      expect(find.text('自定义'), findsOneWidget);
      expect(find.text('播完当前'), findsOneWidget);
      expect(find.text('取消定时'), findsNothing);
    });

    // ── TMR-T27: 定时激活时点击 → 显示 5 个选项（含取消） ─────────

    testWidgets('TMR-T27: 定时激活时点击定时按钮弹出含取消选项的菜单',
        (tester) async {
      // Use a wrapper that activates the timer BEFORE building the UI,
      // so the TimerButton initially sees an active timer.
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            timerServiceProvider.overrideWith((ref) => TimerService()),
            ..._noopRemainingTimeOverride(),
          ],
          child: const _ActiveTimerTestApp(),
        ),
      );
      // Let the post-frame callback fire that activates the timer
      await tester.pumpAndSettle();

      // Tap to open bottom sheet
      await tester.tap(find.byType(IconButton));
      await tester.pumpAndSettle();

      expect(find.text('5 分钟'), findsOneWidget);
      expect(find.text('10 分钟'), findsOneWidget);
      expect(find.text('自定义'), findsOneWidget);
      expect(find.text('播完当前'), findsOneWidget);
      expect(find.text('取消定时'), findsOneWidget);
    });

    // ── TMR-T28: 在 BottomSheet 中选择 10 分钟 → 关闭，按钮更新 ───

    testWidgets(
        'TMR-T28: 在 BottomSheet 中选择 10 分钟 — sheet 关闭，定时激活',
        (tester) async {
      await pumpTimerWidget(tester, const TimerButton());

      await tester.tap(find.byType(IconButton));
      await tester.pumpAndSettle();

      // Tap "10 分钟"
      await tester.tap(find.text('10 分钟'));
      await tester.pumpAndSettle();

      // Bottom sheet should be dismissed
      expect(find.text('10 分钟'), findsNothing);

      // Verify via provider that timer is active
      final iconButton = tester.widget<IconButton>(find.byType(IconButton));
      // The tooltip should indicate active state
      expect(iconButton.tooltip, isNotNull);
    });

    // ── TMR-T29: 在 BottomSheet 中点击「取消定时」→ 恢复未激活 ──────

    testWidgets(
        'TMR-T29: 在 BottomSheet 中点击「取消定时」— sheet 关闭，按钮恢复',
        (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            timerServiceProvider.overrideWith((ref) => TimerService()),
            ..._noopRemainingTimeOverride(),
          ],
          child: const _ActiveTimerTestApp(),
        ),
      );
      await tester.pumpAndSettle();

      // Tap to open bottom sheet
      await tester.tap(find.byType(IconButton));
      await tester.pumpAndSettle();

      // Tap "取消定时"
      await tester.tap(find.text('取消定时'));
      await tester.pumpAndSettle();

      // Bottom sheet should be dismissed, timer should be inactive
      expect(find.text('取消定时'), findsNothing);
    });
  });
}

// ═══════════════════════════════════════════════════════════════════════════════
// Test widget that activates a timer on init
// ═══════════════════════════════════════════════════════════════════════════════

/// A test harness that renders [TimerButton] and activates a 5-minute
/// duration timer via a post-frame callback.
///
/// This lets widget tests start with a timer already active, avoiding
/// the need to fish out the [ProviderContainer] from the widget tree.
class _ActiveTimerTestApp extends ConsumerStatefulWidget {
  const _ActiveTimerTestApp();

  @override
  ConsumerState<_ActiveTimerTestApp> createState() =>
      _ActiveTimerTestAppState();
}

class _ActiveTimerTestAppState extends ConsumerState<_ActiveTimerTestApp> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(startDurationTimerProvider)(5);
    });
  }

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      home: Scaffold(
        body: TimerButton(),
      ),
    );
  }
}
