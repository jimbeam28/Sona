// test/features/progress/bug_10_repro_test.dart
// BUG-10 复现测试（来源：docs/cr/cr-20260724-0110.md PRG1）
//
// 缺陷：恢复对话框每次关闭都 double-pop，误弹下层路由。
// 机理：progress_dialog.dart:38-42 — showDialog future 完成后无条件 dismiss()；
// Flutter TransitionRoute.didPop 同步 complete future（不等退场动画）→
// state=null → 对话框 element 退场动画期仍 mounted → 重建命中 null 分支
// （:58-64）→ postFrame Navigator.pop(null) → 对话框路由已在 popping 被
// lastWhere(isPresent) 跳过 → 命中下层 present 路由并将其弹掉。
// expired 分支（:67-71）每次 build 注册 postFrame pop 无幂等守卫，同病。
//
// 修复前：本测试 FAIL（下层 TOP PAGE 被弹掉）。
// 修复后：本测试 PASS（关闭对话框不影响下层路由）。

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nas_audio_player/features/progress/progress_dialog.dart';
import 'package:nas_audio_player/shared/models/play_progress.dart';

final _progress = PlayProgress(
  connectionId: 1,
  filePath: '/audiobooks/chapter_01.mp3',
  positionMs: 30000,
  durationMs: 600000,
  lastPlayedAt: DateTime(2026, 7, 24),
);

/// 双层路由宿主：底层 BOTTOM PAGE，上层 TOP PAGE 带"打开对话框"按钮。
/// 对话框从 TOP PAGE 弹出——若关闭对话框后 TOP PAGE 消失，即 double-pop 命中下层。
Widget _twoRouteHost() {
  return ProviderScope(
    child: MaterialApp(
      home: const Scaffold(body: Center(child: Text('BOTTOM PAGE'))),
    ),
  );
}

Future<void> _pushTopPageWithDialogTrigger(WidgetTester tester) async {
  final navigator = tester.state<NavigatorState>(find.byType(Navigator));
  navigator.push(MaterialPageRoute<void>(
    builder: (context) => Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 下层路由标识：double-pop 命中下层时此文本消失
            const Text('TOP PAGE'),
            ElevatedButton(
              onPressed: () {
                final container = ProviderScope.containerOf(context);
                // 与生产调用方一致（browser_screen.dart:119 /
                // playlist_detail_screen.dart:52）：fire-and-forget 弹出对话框。
                showProgressResumeDialog(context, container, _progress);
              },
              child: const Text('OPEN DIALOG'),
            ),
          ],
        ),
      ),
    ),
  ));
  await tester.pumpAndSettle();
  await tester.tap(find.text('OPEN DIALOG'));
  // 不用 pumpAndSettle：对话框有 5s 倒计时 Timer.periodic，
  // 推进到对话框可见即可（100ms < 1s 不触发 tick）。
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
  expect(find.text('恢复播放进度'), findsOneWidget, reason: '前置条件：对话框应已弹出');
}

void main() {
  group('BUG-10: 恢复对话框关闭不得弹掉下层路由（PRG1 复现）', () {
    testWidgets('点"继续播放"关闭 → 下层路由仍在', (tester) async {
      await tester.pumpWidget(_twoRouteHost());
      await _pushTopPageWithDialogTrigger(tester);

      await tester.tap(find.textContaining('继续播放 ('));
      await tester.pump(); // pop 触发：future 完成 → dismiss → null 分支重建
      await tester.pump(); // bug：null 分支 postFrame pop 命中 TOP PAGE
      await tester.pumpAndSettle();

      expect(find.text('恢复播放进度'), findsNothing, reason: '对话框应已关闭');
      expect(find.text('TOP PAGE'), findsOneWidget,
          reason: '关闭对话框不得弹掉下层路由（BUG-10：double-pop 把 TOP PAGE 弹掉）');
    });

    testWidgets('点"从头播放"关闭 → 下层路由仍在', (tester) async {
      await tester.pumpWidget(_twoRouteHost());
      await _pushTopPageWithDialogTrigger(tester);

      await tester.tap(find.text('从头播放'));
      await tester.pump();
      await tester.pump();
      await tester.pumpAndSettle();

      expect(find.text('恢复播放进度'), findsNothing);
      expect(find.text('TOP PAGE'), findsOneWidget,
          reason: '关闭对话框不得弹掉下层路由（BUG-10）');
    });

    testWidgets('倒计时 5s 自动过期关闭 → 下层路由仍在', (tester) async {
      await tester.pumpWidget(_twoRouteHost());
      await _pushTopPageWithDialogTrigger(tester);

      // 驱动 5 次 1s tick 使倒计时过期（expired 分支 postFrame pop(true)）
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(seconds: 1));
      }
      await tester.pump(); // expired 分支 postFrame pop → dismiss → null 分支
      await tester.pump(); // bug：null 分支二次 postFrame pop 命中 TOP PAGE
      await tester.pumpAndSettle();

      expect(find.text('恢复播放进度'), findsNothing, reason: '对话框应已自动关闭');
      expect(find.text('TOP PAGE'), findsOneWidget,
          reason: '过期自动关闭不得弹掉下层路由（BUG-10 expired 分支）');
    });
  });
}
