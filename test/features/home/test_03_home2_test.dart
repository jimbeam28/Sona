// test/features/home/test_03_home2_test.dart
// TEST-03-HOME2: PopScope canPop=false + moveTaskToBack（spec: docs/features/TEST-03.md）
//
// TEST-03-S1  真实 HomeScreen 的 PopScope 接线：系统返回键 → 路由不 pop +
//             MethodChannel 'com.example.nas_audio_player/background'
//             收到 'moveTaskToBack' 调用
// TEST-03-S2  非 Android 平台（测试环境无 mock handler）→ 返回仍被拦截、
//             无异常（MissingPluginException 吞掉 = graceful no-op）
//
// 与 TST-17（home_screen_test.dart 本地重实现闭包）的区别：本文件 pump 真实
// HomeScreen 并驱动真实系统返回事件（tester.binding.handlePopRoute），
// 验证生产接线而非回调副本自证。
//
// 生产代码出处（spec 锚定，禁读 lib/）：
//   lib/features/home/home_screen.dart:83-99  PopScope + onPopInvokedWithResult
//   lib/core/services/background_service.dart:9-10 非 Android no-op

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

/// moveTaskToBack 的 MethodChannel（background_service.dart）。
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
          .overrideWith((ref) => Future.value(<NasFile>[])),
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

/// 模拟 Android 系统返回键（WidgetsApp → Navigator.maybePop → PopScope）。
/// 注意：本 Flutter 版本 re-export 的 pumpEventQueue 来自 test_api（真实定时器），
/// 在 testWidgets 的 FakeAsync 区会挂起，故只 pump 一次让帧重建。
Future<void> _pressSystemBack(WidgetTester tester) async {
  await tester.binding.handlePopRoute();
  await tester.pump();
}

// ═════════════════════════════════════════════════════════════════════════════
// TEST-03-S1: 真实 HomeScreen PopScope 接线 + moveTaskToBack
// ═════════════════════════════════════════════════════════════════════════════

void main() {
  group('TEST-03-S1: PopScope 拦截系统返回并调用 moveTaskToBack', () {
    testWidgets('TEST-03-S1: 系统返回键 → 路由不 pop 且 MethodChannel 收到 moveTaskToBack',
        (WidgetTester tester) async {
      final calls = <MethodCall>[];
      _mockBackgroundChannel(calls);

      await tester.pumpWidget(_buildTestApp(overrides: _defaultOverrides()));
      await tester.pumpAndSettle();

      expect(find.byType(HomeScreen), findsOneWidget,
          reason: '前置：HomeScreen 应已渲染');

      await _pressSystemBack(tester);

      // 否定断言：返回键不得 pop 退出路由（应被 PopScope 拦截）
      expect(find.byType(HomeScreen), findsOneWidget,
          reason: '否定断言：canPop=false 时返回键不得 pop 退出 HomeScreen');

      // 拦截后应调用 moveTaskToBack 退到后台（channel 必须收到调用）
      expect(calls, hasLength(1), reason: '拦截后必须调用 moveTaskToBack（不得静默什么都不做）');
      expect(calls.single.method, 'moveTaskToBack',
          reason: 'MethodChannel 调用方法名应为 moveTaskToBack');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // TEST-03-S2: 非 Android 平台 graceful no-op
  // ═══════════════════════════════════════════════════════════════════════════

  group('TEST-03-S2: 非 Android 平台返回键拦截且无异常', () {
    testWidgets('TEST-03-S2: 无 channel handler（非 Android）→ 返回仍拦截、无异常',
        (WidgetTester tester) async {
      // 不注册 mock handler → invokeMethod 以 MissingPluginException 完成，
      // 生产代码应吞掉该错误（graceful no-op）。任何未处理异常都会使
      // 本 widget test 失败，无需显式断言。
      await tester.pumpWidget(_buildTestApp(overrides: _defaultOverrides()));
      await tester.pumpAndSettle();

      await _pressSystemBack(tester);

      // 否定断言：非 Android 平台仍 must 拦截返回（canPop=false 不随平台变化）
      expect(find.byType(HomeScreen), findsOneWidget,
          reason: '否定断言：非 Android 平台返回键仍应被拦截，不得 pop');
      // 否定断言：不抛异常 —— 走到这里即说明 moveTaskToBack no-op 未炸
    });
  });
}
