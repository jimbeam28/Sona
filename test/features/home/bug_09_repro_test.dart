// test/features/home/bug_09_repro_test.dart
// BUG-09 复现测试（来源：docs/cr/cr-20260816-0803-browser-home.md B1）
//
// 缺陷：HomeScreen（home_screen.dart:81-87）与 BrowserScreen
// （browser_screen.dart:40-46）的嵌套 PopScope 在浏览器子目录按系统返回键时
// 双重动作——目录回退（期望）的同时应用退到后台（moveTaskToBack，不该发生）。
// 框架行为：navigator.dart:5559-5561 + routes.dart:2048-2053 —— doNotPop 时
// 同一路由上注册的全部 PopScope 都以 didPop=false 收到回调。
//
// 修复前：本测试 FAIL —— MethodChannel 收到 moveTaskToBack。
// 修复后：本测试 PASS —— 仅回退一级目录，channel 无调用。
//
// 已用可运行测试实证（走查期 scratch，已删除）：pump 真实 HomeScreen +
// 子目录 navStack，handlePopRoute 后 channel 收到 ['moveTaskToBack'] 且
// navStack 2→1。

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:nas_audio_player/features/browser/browser_provider.dart';
import 'package:nas_audio_player/features/home/home_screen.dart';
import 'package:nas_audio_player/features/playlist/playlist_provider.dart';
import 'package:nas_audio_player/shared/models/nas_file.dart';
import 'package:nas_audio_player/shared/models/playlist.dart';

import '../../helpers/test_factories.dart';

/// moveTaskToBack 的 MethodChannel（background_service.dart:6）。
const _backgroundChannel =
    MethodChannel('com.example.nas_audio_player/background');

// ── Helpers ───────────────────────────────────────────────────────────────────

Widget _buildTestApp({List<Override>? overrides}) {
  final router = GoRouter(
    initialLocation: '/home',
    routes: [
      GoRoute(
        path: '/home',
        builder: (_, __) => const HomeScreen(),
      ),
      GoRoute(
        path: '/settings',
        builder: (_, __) =>
            const Scaffold(body: Center(child: Text('Settings'))),
      ),
    ],
  );
  return ProviderScope(
    overrides: overrides ?? [],
    child: MaterialApp.router(routerConfig: router),
  );
}

List<Override> _defaultOverrides() => [
      playlistListProvider.overrideWith((ref) => Future.value(<Playlist>[])),
      directoryContentsProvider('/')
          .overrideWith((ref) => Future.value(<NasFile>[
                testDir('MusicDir', '/music'),
              ])),
      directoryContentsProvider('/music').overrideWith(
          (ref) => Future.value(<NasFile>[testAudio('a.mp3', '/music/a.mp3')])),
    ];

/// 注册 moveTaskToBack 的 mock handler 并记录调用；tearDown 时清理。
void _mockBackgroundChannel(List<MethodCall> calls) {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_backgroundChannel, (call) async {
    calls.add(call);
    return null;
  });
  addTearDown(() => TestDefaultBinaryMessengerBinding
      .instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_backgroundChannel, null));
}

/// 模拟 Android 系统返回键（同 test_03_home2_test.dart:77-80 模式：
/// pumpEventQueue 在 testWidgets FakeAsync 区会挂起，只 pump 一次让帧重建）。
Future<void> _pressSystemBack(WidgetTester tester) async {
  await tester.binding.handlePopRoute();
  await tester.pump();
}

/// 切到"文件浏览器"Tab 并等切换动画结束。
Future<void> _switchToBrowserTab(WidgetTester tester) async {
  await tester.tap(find.text('文件浏览器'));
  await tester.pumpAndSettle();
}

/// 前置断言：浏览器 Tab 已渲染（文件列表或错误视图在树上）。
Future<void> _expectBrowserTabVisible(WidgetTester tester) async {
  expect(find.byType(HomeScreen), findsOneWidget);
  expect(find.text('根目录'), findsOneWidget, reason: '前置：面包屑可见 = 浏览器 Tab 已渲染');
}

// ═════════════════════════════════════════════════════════════════════════════
// BUG-09-S4: 子目录深度按返回 → 仅目录回退，不得 moveTaskToBack（修复目标）
// ═════════════════════════════════════════════════════════════════════════════

void main() {
  group('BUG-09: 浏览器子目录返回键不得双重动作（目录回退 + 后台化）', () {
    testWidgets('子目录深度 + 浏览器 Tab 可见 → 返回键只回退目录，channel 无调用',
        (WidgetTester tester) async {
      final calls = <MethodCall>[];
      _mockBackgroundChannel(calls);

      final nav = NavigationStackNotifier()..push('/music');

      await tester.pumpWidget(_buildTestApp(
        overrides: [
          ..._defaultOverrides(),
          navigationStackProvider.overrideWith((ref) => nav)
        ],
      ));
      await tester.pumpAndSettle();
      await _switchToBrowserTab(tester);
      _expectBrowserTabVisible(tester);

      expect(nav.state, ['/', '/music'], reason: '前置：navStack 处于子目录深度');

      await _pressSystemBack(tester);

      // 期望行为：仅回退一级目录
      expect(nav.state, ['/'], reason: '返回键应使 navStack 从 2 层回退到 1 层（根目录）');
      // 否定断言（修复目标）：应用不得退到后台
      expect(calls, isEmpty,
          reason: '否定断言：子目录深度按返回键不得触发 moveTaskToBack'
              '（修复前：HomeScreen 的 PopScope 也收到 didPop=false 并后台化应用）');
      // 否定断言：路由不得被 pop 退出 HomeScreen
      expect(find.byType(HomeScreen), findsOneWidget,
          reason: '否定断言：返回键不得 pop 退出 HomeScreen 路由');
    });

    // ═════════════════════════════════════════════════════════════════════════
    // BUG-09-S5: 根目录按返回 → moveTaskToBack（现有行为锚定，不得回归）
    // ═════════════════════════════════════════════════════════════════════════

    testWidgets('浏览器 Tab 根目录 → 返回键仍 moveTaskToBack（TEST-03-S1 回归）',
        (WidgetTester tester) async {
      final calls = <MethodCall>[];
      _mockBackgroundChannel(calls);

      await tester.pumpWidget(_buildTestApp(overrides: _defaultOverrides()));
      await tester.pumpAndSettle();
      await _switchToBrowserTab(tester);
      _expectBrowserTabVisible(tester);

      await _pressSystemBack(tester);

      expect(calls, hasLength(1),
          reason: '根目录返回键必须 moveTaskToBack（退到后台，TEST-03-S1 语义）');
      expect(calls.single.method, 'moveTaskToBack');
      expect(find.byType(HomeScreen), findsOneWidget,
          reason: '根目录返回不得 pop 退出 HomeScreen 路由');
    });

    // ═════════════════════════════════════════════════════════════════════════
    // BUG-09-S6: 播放单 Tab（浏览器栈深）→ moveTaskToBack 且栈不被静默回退
    // ═════════════════════════════════════════════════════════════════════════

    testWidgets('播放单 Tab + 浏览器栈深 → 返回键 moveTaskToBack，navStack 不变',
        (WidgetTester tester) async {
      final calls = <MethodCall>[];
      _mockBackgroundChannel(calls);

      final nav = NavigationStackNotifier()..push('/music');

      await tester.pumpWidget(_buildTestApp(
        overrides: [
          ..._defaultOverrides(),
          navigationStackProvider.overrideWith((ref) => nav)
        ],
      ));
      await tester.pumpAndSettle();
      // 不切 Tab：停在播放单 Tab（index 0）
      expect(find.text('播放单'), findsOneWidget, reason: '前置：播放单 Tab 可见');

      await _pressSystemBack(tester);

      expect(calls, hasLength(1), reason: '播放单 Tab 返回键必须 moveTaskToBack（退到后台）');
      expect(calls.single.method, 'moveTaskToBack');
      // 否定断言：隐藏中的浏览器栈不得被静默回退
      expect(nav.state, ['/', '/music'],
          reason: '否定断言：播放单 Tab 下按返回不得静默回退浏览器目录栈');
      expect(find.byType(HomeScreen), findsOneWidget);
    });
  });
}
