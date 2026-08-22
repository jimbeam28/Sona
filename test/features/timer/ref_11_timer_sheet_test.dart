// test/features/timer/ref_11_timer_sheet_test.dart
// REF-11 门禁测试（spec docs/features/REF-11.md §5.4 指定文件）。
//
// 锚定定时弹窗 tile 集合（补回 15 分钟预设后）：
//   - S1 上次时长? → 5 分钟 → 10 分钟 → 15 分钟 → 播完当前 → 自定义 → [取消定时]
//   - S2 各 tile onTap 触发对应 provider + Navigator.pop
//   - S5 15 分钟 tile 出现且顺序正确、onTap 生效（startDuration(15)）
//   - S6 自定义 picker 与上一次时长逻辑回归
//   - INV1 预设档恒含 5/10/15 三档
//   - INV2 每个预设/操作档 onTap 必 ref.read(Provider)() + Navigator.pop
//   - INV3 取消定时仅 isActive 时显示

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nas_audio_player/features/timer/timer_provider.dart';
import 'package:nas_audio_player/features/timer/widgets/timer_button.dart';

import '../../helpers/widget_helpers.dart';

/// Spy notifier that records timer actions so the sheet's onTap can be
/// verified without real time progression.
class _SpyTimerStateNotifier extends TimerStateNotifier {
  final List<int> startDurations = <int>[];
  int startAfterCurrentCalls = 0;
  int cancelCalls = 0;

  @override
  void startDuration(int minutes) {
    startDurations.add(minutes);
  }

  @override
  void startAfterCurrent() {
    startAfterCurrentCalls++;
  }

  @override
  void cancel() {
    cancelCalls++;
  }
}

Widget _buildSheet({
  required bool isActive,
  required _SpyTimerStateNotifier spy,
  int? lastCustomMinutes,
}) {
  return ProviderScope(
    overrides: [
      timerStateProvider.overrideWith(() => spy),
      lastCustomTimerMinutesProvider.overrideWith((ref) => lastCustomMinutes),
      ...noopRemainingTimeOverride(),
    ],
    child: MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () {
              showModalBottomSheet<void>(
                context: context,
                builder: (_) => TimerBottomSheet(isActive: isActive),
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('REF-11-S1 REF-11-INV1: tile 集合完整且顺序正确', (tester) async {
    final spy = _SpyTimerStateNotifier();
    await tester.pumpWidget(_buildSheet(isActive: false, spy: spy));

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // 恒显档位
    expect(find.text('5 分钟'), findsOneWidget);
    expect(find.text('10 分钟'), findsOneWidget);
    expect(find.text('15 分钟'), findsOneWidget, reason: 'INV1: 15 分钟预设必须存在');
    expect(find.text('播完当前'), findsOneWidget);
    expect(find.text('自定义'), findsOneWidget);

    // 顺序：5 → 10 → 15 → 播完当前 → 自定义
    final y5 = tester.getTopLeft(find.text('5 分钟')).dy;
    final y10 = tester.getTopLeft(find.text('10 分钟')).dy;
    final y15 = tester.getTopLeft(find.text('15 分钟')).dy;
    final yPlay = tester.getTopLeft(find.text('播完当前')).dy;
    final yCustom = tester.getTopLeft(find.text('自定义')).dy;
    expect(y5 < y10 && y10 < y15 && y15 < yPlay && yPlay < yCustom, isTrue,
        reason: '档位顺序必须为 5→10→15→播完当前→自定义');

    // 否定断言：isActive=false 时不得出现取消定时
    expect(find.text('取消定时'), findsNothing,
        reason: 'INV3: isActive=false 时不得显示取消定时');
  });

  testWidgets('REF-11-S1 REF-11-INV3: 激活时显示取消定时', (tester) async {
    final spy = _SpyTimerStateNotifier();
    await tester.pumpWidget(_buildSheet(isActive: true, spy: spy));

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('取消定时'), findsOneWidget,
        reason: 'INV3: isActive=true 时显示取消定时');
    expect(find.text('15 分钟'), findsOneWidget, reason: '激活时 15 分钟仍显示');

    // 取消定时位于弹窗底部，滚动后点击
    await tester.scrollUntilVisible(find.text('取消定时'), 100);
    await tester.tap(find.text('取消定时'));
    await tester.pumpAndSettle();

    expect(spy.cancelCalls, 1);
    expect(find.text('定时停止播放'), findsNothing);
  });

  testWidgets('REF-11-S1: 上次时长条件显示', (tester) async {
    final spy = _SpyTimerStateNotifier();
    await tester.pumpWidget(
        _buildSheet(isActive: false, spy: spy, lastCustomMinutes: 25));

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('上次时长（25分钟）'), findsOneWidget,
        reason: 'lastCustomMinutes 非 null 时显示上次时长');
    expect(find.text('15 分钟'), findsOneWidget, reason: '15 分钟与上次时长并存');
  });

  testWidgets('REF-11-S5 REF-11-INV2: tap 15 分钟 → startDuration(15) + pop',
      (tester) async {
    final spy = _SpyTimerStateNotifier();
    await tester.pumpWidget(_buildSheet(isActive: false, spy: spy));

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('15 分钟'));
    await tester.pumpAndSettle();

    expect(spy.startDurations, [15], reason: 'tap 15 分钟应触发 startDuration(15)');
    expect(find.text('定时停止播放'), findsNothing,
        reason: 'INV2: onTap 后应 Navigator.pop 关闭弹窗');
  });

  testWidgets('REF-11-S2: tap 5/10 分钟 → startDuration(5/10) + pop',
      (tester) async {
    final spy = _SpyTimerStateNotifier();
    await tester.pumpWidget(_buildSheet(isActive: false, spy: spy));

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('5 分钟'));
    await tester.pumpAndSettle();
    expect(spy.startDurations, [5]);

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('10 分钟'));
    await tester.pumpAndSettle();
    expect(spy.startDurations, [5, 10]);
  });

  testWidgets('REF-11-S2 REF-11-INV2: tap 播完当前 → startAfterCurrent + pop',
      (tester) async {
    final spy = _SpyTimerStateNotifier();
    await tester.pumpWidget(_buildSheet(isActive: false, spy: spy));

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('播完当前'));
    await tester.pumpAndSettle();

    expect(spy.startAfterCurrentCalls, 1);
    expect(find.text('定时停止播放'), findsNothing, reason: 'onTap 后应关闭弹窗');
  });

  testWidgets('REF-11-S2: tap 取消定时 → cancel + pop', (tester) async {
    final spy = _SpyTimerStateNotifier();
    await tester.pumpWidget(_buildSheet(isActive: true, spy: spy));

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(find.text('取消定时'), 100);
    await tester.tap(find.text('取消定时'));
    await tester.pumpAndSettle();

    expect(spy.cancelCalls, 1);
    expect(find.text('定时停止播放'), findsNothing);
  });

  testWidgets('REF-11-S3 REF-11-S6: 自定义 picker 默认 0h5m、0 分钟禁用确认',
      (tester) async {
    final spy = _SpyTimerStateNotifier();
    await tester.pumpWidget(_buildSheet(isActive: false, spy: spy));

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('自定义'));
    await tester.pumpAndSettle();

    // 自定义 picker 弹出
    expect(find.text('自定义时长'), findsOneWidget);

    // 确认按钮存在（默认 0h5m → 5 分钟 → 可确认）
    final confirm = find.widgetWithText(TextButton, '确认');
    expect(confirm, findsOneWidget);
    expect(tester.widget<TextButton>(confirm).onPressed, isNotNull,
        reason: 'S3：默认 0h5m 共 5 分钟 > 0，确认必须可用');

    // S3/S6 靶点：分钟轮滚到 0 → 总时长 0 → 确认必须禁用（onPressed == null）。
    final wheels = find.byType(ListWheelScrollView);
    expect(wheels, findsNWidgets(2), reason: '前置：picker 含时/分两个滚轮');
    final minuteController = tester
        .widget<ListWheelScrollView>(wheels.at(1))
        .controller as FixedExtentScrollController;
    minuteController.jumpToItem(0);
    await tester.pumpAndSettle();

    expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, '确认'))
            .onPressed,
        isNull,
        reason: 'REF-11-S3/S6：0h0m 总时长为 0 时确认必须禁用'
            '（timer_button.dart `_totalMinutes == 0 ? null : ...` 分支——'
            '若该守卫被删，本断言失败）');

    // 恢复非零分钟 → 确认恢复可用。
    minuteController.jumpToItem(3);
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, '确认'))
            .onPressed,
        isNotNull,
        reason: 'S6 回归面：滚回非零后确认必须恢复可用');
  });

  testWidgets('REF-11-S4 REF-11-S5 否定: 15 分钟 tile 不重复（文档漂移收敛）', (tester) async {
    final spy = _SpyTimerStateNotifier();
    await tester.pumpWidget(_buildSheet(isActive: false, spy: spy));

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('15 分钟'), findsOneWidget, reason: '15 分钟 tile 不得重复出现');
  });
}
