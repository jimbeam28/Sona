// test/features/timer/bug_bug29_repro_test.dart
// BUG-29: 定时器显示一致性（TMR1+TMR3）— spec §5.4 门禁测试
//（docs/features/BUG-29.md）。
//
// CR 来源: docs/cr/cr-20260724-0110.md TMR1 (line 516) + TMR3 (line 523)
//
// 覆盖:
// BUG-29-S1:   paused 模式 formattedRemainingProvider 返回冻结剩余时间的
//              格式化结果（如 "04:35"），否定断言：不返回 null、不降级
//              inactive 图标、不改 duration/afterCurrent 行为
// BUG-29-S2:   duration 启动后首帧即显示倒计时，否定断言：首秒不返回 null、
//              不改变后续每秒更新
// BUG-29-INV1: remainingTimeProvider 与 TimerService.displayString 对
//              paused/duration 语义一致
// BUG-29-INV2: 已激活状态首帧发出非 null 值
//
// 全部用例走真实 remainingTimeProvider（不用 noopRemainingTimeOverride），
// 用 FakeAsync 锚定首发时刻与每秒节拍，时钟经 TimerService(now:) 注入与
// fake 时间轴逐秒同步（P16）——正是 cr TMR6 指出的零覆盖真实流路径。
//
// 说明：Riverpod 对 watch 链的脏元素重建是惰性的（读取时才重建），流初值
// 经 microtask 送达；因此每次状态变更后用 _settle 先读一次触发重建、再冲
// microtask、再读观察值。

import 'package:fake_async/fake_async.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nas_audio_player/features/player/widgets/timer_control.dart';
import 'package:nas_audio_player/features/timer/domain/timer_service.dart';
import 'package:nas_audio_player/features/timer/timer_provider.dart';

// ── 注入时钟（P16：DateTime.now 不受 FakeAsync 控制，now 全程经注入）──────

DateTime _fakeNow = DateTime(2026, 8, 4);

DateTime _now() => _fakeNow;

void _reset() => _fakeNow = DateTime(2026, 8, 4);

void _advance(Duration d) => _fakeNow = _fakeNow.add(d);

/// 时钟与 fake 时间轴逐秒同步推进：每秒先拨注入时钟再 elapse 1s，
/// 保证 periodic 回调在整点触发时读到的 remainingTime 与时间轴一致。
void _tick(FakeAsync async, Duration d) {
  expect(d.inMilliseconds % 1000, 0, reason: '仅支持整秒步进');
  for (var i = 0; i < d.inSeconds; i++) {
    _advance(const Duration(seconds: 1));
    async.elapse(const Duration(seconds: 1));
  }
}

/// 真实 remainingTimeProvider 的测试容器（不做 noop 覆盖）。
ProviderContainer _container() => ProviderContainer(
      overrides: [
        timerServiceProvider.overrideWith((ref) => TimerService(now: _now)),
      ],
    );

/// 状态变更后 settles 显示链：读一次触发惰性重建、冲 microtask 送达流事件、
/// 再读返回显示值。
String? _settle(ProviderContainer container, FakeAsync async) {
  container.read(remainingTimeProvider);
  async.flushMicrotasks();
  return container.read(formattedRemainingProvider);
}

void main() {
  // ═══════════════════════════════════════════════════════════════════════
  // BUG-29-S1: paused 模式发射冻结剩余时间
  // ═══════════════════════════════════════════════════════════════════════

  group('BUG-29-S1: paused 模式 formattedRemainingProvider 返回冻结值', () {
    test('paused → 返回冻结格式化值 "04:35"（spec 样例 remainingMs=275000）', () {
      _reset();
      FakeAsync().run((async) {
        final container = _container();

        // 无定时 → null（预读同时建链，等价 UI 从一开始就 watch 显示链）
        expect(_settle(container, async), isNull);

        container.read(startDurationTimerProvider)(5);
        expect(_settle(container, async), '05:00');

        _tick(async, const Duration(seconds: 25)); // 倒计时至剩余 275s
        expect(_settle(container, async), '04:35');

        container.read(timerStateProvider.notifier).pause();
        final state = container.read(timerStateProvider);
        expect(state, isNotNull);
        expect(state!.mode, TimerMode.paused);
        expect(state.remainingMs, 275000, reason: '暂停时保存的毫秒余量');

        final formatted = _settle(container, async);
        expect(formatted, '04:35', reason: 'paused 显示冻结剩余时间（U1）');
        // 否定断言：不返回 null（修复前 Stream.value(null) 导致 displayText=null）
        expect(formatted, isNotNull);

        container.dispose();
      });
    });

    test('否定断言：冻结值不随时间流逝继续跳动', () {
      _reset();
      FakeAsync().run((async) {
        final container = _container();
        container.read(formattedRemainingProvider); // 预读建链

        container.read(startDurationTimerProvider)(5);
        _settle(container, async);
        _tick(async, const Duration(seconds: 25));
        expect(_settle(container, async), '04:35');

        container.read(timerStateProvider.notifier).pause();
        expect(_settle(container, async), '04:35');

        // 暂停后再过 30s：冻结值不变，而非继续倒计时
        _tick(async, const Duration(seconds: 30));
        expect(_settle(container, async), '04:35',
            reason: 'paused 后余量冻结，不得继续倒计时');
        expect(container.read(formattedRemainingProvider), isNot('04:05'));

        container.dispose();
      });
    });

    test('BUG-29-INV1: paused 下 provider 链与 displayString 语义一致', () {
      _reset();
      FakeAsync().run((async) {
        final container = _container();
        final service = container.read(timerServiceProvider);
        container.read(formattedRemainingProvider); // 预读建链

        container.read(startDurationTimerProvider)(5);
        _settle(container, async);
        _tick(async, const Duration(seconds: 25));
        container.read(timerStateProvider.notifier).pause();

        final formatted = _settle(container, async);
        expect(formatted, service.displayString,
            reason: 'INV1: 两条显示链路对 paused 均返回同一冻结值');
        expect(service.displayString, '04:35');

        container.dispose();
      });
    });

    test('BUG-29-S1 边界：remainingTimeProvider 本体发射冻结 Duration 且停流', () {
      _reset();
      FakeAsync().run((async) {
        final container = _container();
        final emitted = <Duration?>[];
        container.listen<AsyncValue<Duration?>>(
          remainingTimeProvider,
          (_, next) {
            if (next is AsyncData) emitted.add(next.value);
          },
        );

        container.read(startDurationTimerProvider)(5);
        container.read(remainingTimeProvider); // 触发惰性重建
        async.flushMicrotasks();
        expect(emitted, isNotEmpty);
        expect(emitted.last, const Duration(minutes: 5), reason: 't=0 首发初值');

        _tick(async, const Duration(seconds: 25));
        expect(emitted.last, const Duration(seconds: 275),
            reason: 'duration 分支每秒倒计时');

        container.read(timerStateProvider.notifier).pause();
        container.read(remainingTimeProvider); // 触发惰性重建到 paused 分支
        async.flushMicrotasks();
        expect(emitted.last, const Duration(milliseconds: 275000),
            reason: 'paused 分支发射冻结 Duration 而非 null');

        // 否定断言：paused 后流不再发射（区别于 duration 的每秒节拍）
        final countAfterPause = emitted.length;
        _tick(async, const Duration(seconds: 5));
        expect(emitted, hasLength(countAfterPause),
            reason: 'paused 后不得再有倒计时事件');

        container.dispose();
      });
    });

    test('否定断言：afterCurrent / 无定时行为不变', () {
      _reset();
      FakeAsync().run((async) {
        final container = _container();

        // state == null → null
        expect(_settle(container, async), isNull);

        // afterCurrent → null（UI 用 afterCurrentLabel，不经此链）
        container.read(startAfterCurrentProvider)();
        expect(_settle(container, async), isNull);
        expect(
            container.read(timerStateProvider)!.mode, TimerMode.afterCurrent);

        container.dispose();
      });
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // BUG-29-S2: duration 启动后首帧即显示倒计时
  // ═══════════════════════════════════════════════════════════════════════

  group('BUG-29-S2: duration 启动首帧即有显示值', () {
    test('BUG-29-INV2: 启动后未经任何 elapse 即发出非 null 初值', () {
      _reset();
      FakeAsync().run((async) {
        final container = _container();

        // 无定时 → null（预读同时建链）
        expect(_settle(container, async), isNull);

        container.read(startDurationTimerProvider)(5);
        // 只冲 microtask，不 elapse —— 修复前首个周期事件要 1s 后才到
        expect(_settle(container, async), '05:00',
            reason: 'INV2: 首帧即完整时长，不得为空窗');

        container.dispose();
      });
    });

    test('首发时刻锚定：t=0.5s（< 首个周期）已有显示值', () {
      _reset();
      FakeAsync().run((async) {
        final container = _container();
        container.read(formattedRemainingProvider); // 预读建链

        container.read(startDurationTimerProvider)(5);
        expect(_settle(container, async), '05:00');

        // 修复前：Stream.periodic 首事件 t=1s，此刻 valueOrNull == null
        _advance(const Duration(milliseconds: 500));
        async.elapse(const Duration(milliseconds: 500));
        expect(container.read(formattedRemainingProvider), '05:00',
            reason: '首秒内（t<1s）不得为 null');

        container.dispose();
      });
    });

    test('首发序列锚定：t=0 初值 + 每秒一拍', () {
      _reset();
      FakeAsync().run((async) {
        final container = _container();
        final emitted = <Duration?>[];
        container.listen<AsyncValue<Duration?>>(
          remainingTimeProvider,
          (_, next) {
            if (next is AsyncData) emitted.add(next.value);
          },
        );

        container.read(startDurationTimerProvider)(5);
        container.read(remainingTimeProvider); // 触发惰性重建
        async.flushMicrotasks();
        expect(emitted, hasLength(1), reason: 't=0 同步首发一帧');
        expect(emitted.first, const Duration(minutes: 5));

        _tick(async, const Duration(seconds: 1));
        expect(emitted, hasLength(2), reason: 't=1s 首个周期事件');
        expect(emitted[1], const Duration(seconds: 299));

        // 否定断言：不改变后续每秒更新行为
        _tick(async, const Duration(seconds: 1));
        expect(emitted, hasLength(3));
        expect(emitted[2], const Duration(seconds: 298));
        expect(container.read(formattedRemainingProvider), '04:58');

        container.dispose();
      });
    });

    test('否定断言：启动→取消后显示归位，无残留冻结值', () {
      _reset();
      FakeAsync().run((async) {
        final container = _container();
        container.read(formattedRemainingProvider); // 预读建链

        container.read(startDurationTimerProvider)(5);
        expect(_settle(container, async), '05:00');

        container.read(cancelTimerProvider)();
        expect(_settle(container, async), isNull, reason: '取消后不得残留倒计时显示');
        expect(container.read(timerActiveProvider), isFalse);

        container.dispose();
      });
    });

    test('到期后 checkExpired 清态，显示归位无残留', () {
      _reset();
      FakeAsync().run((async) {
        final container = _container();
        container.read(formattedRemainingProvider); // 预读建链

        container.read(startDurationTimerProvider)(5);
        expect(_settle(container, async), '05:00');

        _tick(async, const Duration(minutes: 5));

        // 到期未 checkExpired 前显示 00:00（remainingTime 钳到 zero）
        expect(_settle(container, async), '00:00');

        // UI tick 驱动的到期检查（home/player screen 每秒调用）
        final expired = container.read(checkTimerExpiryProvider)();
        expect(expired, isTrue);
        expect(_settle(container, async), isNull,
            reason: '到期清态后不得残留 00:00 冻结显示');

        container.dispose();
      });
    });

    test('BUG-29-INV1: duration 下 provider 链与 displayString 一致', () {
      _reset();
      FakeAsync().run((async) {
        final container = _container();
        final service = container.read(timerServiceProvider);
        container.read(formattedRemainingProvider); // 预读建链

        container.read(startDurationTimerProvider)(5);
        final formatted = _settle(container, async);
        expect(formatted, service.displayString,
            reason: 'INV1: duration 模式两链路同值');
        expect(service.displayString, '05:00');

        container.dispose();
      });
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // Widget 层（U1/U2）：TimerControl 消费链
  // ═══════════════════════════════════════════════════════════════════════

  group('BUG-29 widget: TimerControl 显示链', () {
    Widget wrapTimerControl() => ProviderScope(
          overrides: [
            timerServiceProvider.overrideWith((ref) => TimerService(now: _now)),
          ],
          child: const MaterialApp(
            home: Scaffold(body: TimerControl()),
          ),
        );

    testWidgets('U2: 启动后首帧即显倒计时，不降级 inactive 图标', (tester) async {
      _reset();
      await tester.pumpWidget(wrapTimerControl());
      final container =
          ProviderScope.containerOf(tester.element(find.byType(TimerControl)));

      expect(find.byType(TextButton), findsNothing,
          reason: '启动前为 inactive 裸图标');
      expect(find.text('05:00'), findsNothing);

      container.read(startDurationTimerProvider)(5);
      await tester.pump(); // 状态变更重建
      await tester.pump(); // 流初值送达（microtask）+ 重建

      // 否定断言：首秒内不得停留在 inactive 图标（TMR3 空窗）
      expect(find.text('05:00'), findsOneWidget, reason: 'U2: 启动后立即显示完整时长倒计时');
      expect(find.byType(TextButton), findsOneWidget, reason: 'active 图标分支');

      // 否定断言：每秒更新行为不变
      _advance(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('04:59'), findsOneWidget);

      // teardown：卸载以取消 periodic 订阅，避免 pending timer
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('U1: paused 显示冻结剩余时间，不降级 inactive 图标', (tester) async {
      _reset();
      await tester.pumpWidget(wrapTimerControl());
      final container =
          ProviderScope.containerOf(tester.element(find.byType(TimerControl)));

      container.read(startDurationTimerProvider)(5);
      await tester.pump();
      await tester.pump();
      expect(find.text('05:00'), findsOneWidget);

      // 推进到剩余 04:35（spec 样例 remainingMs=275000）
      _advance(const Duration(seconds: 25));
      await tester.pump(const Duration(seconds: 25));
      expect(find.text('04:35'), findsOneWidget);

      container.read(timerStateProvider.notifier).pause();
      await tester.pump();
      await tester.pump();
      expect(find.text('04:35'), findsOneWidget, reason: 'U1: paused 显示冻结剩余时间');
      expect(find.byType(TextButton), findsOneWidget,
          reason: '否定断言：不降级为 inactive 裸图标');

      // 否定断言：冻结值不随时间继续跳动
      _advance(const Duration(seconds: 30));
      await tester.pump(const Duration(seconds: 30));
      expect(find.text('04:35'), findsOneWidget, reason: 'paused 后显示冻结');
      expect(find.text('04:05'), findsNothing);

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('否定断言：afterCurrent 仍显示"播完停止"标签', (tester) async {
      _reset();
      await tester.pumpWidget(wrapTimerControl());
      final container =
          ProviderScope.containerOf(tester.element(find.byType(TimerControl)));

      container.read(startAfterCurrentProvider)();
      await tester.pump();
      await tester.pump();

      expect(find.text(TimerService.afterCurrentLabel), findsOneWidget);
      expect(find.byType(TextButton), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
    });
  });
}
