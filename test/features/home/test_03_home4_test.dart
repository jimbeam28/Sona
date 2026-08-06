// test/features/home/test_03_home4_test.dart
// TEST-03-HOME4: onboarding startupValidation 失败分支（spec: docs/features/TEST-03.md）
//
// TEST-03-S6  startupValidationProvider 抛异常（error 分支）→ 路由 /connection
// TEST-03-S7  startupValidationProvider authError 分支 → 路由 /connection
//             （等价确认：ONB-03 已覆盖同路径，见报告说明）
//
// 装配方式与 onboarding_test.dart（TREF-05）一致：真实 GoRouter +
// connectionListProvider（非空）触发 startupValidation 执行 + 重定向断言。
//
// 生产代码出处（spec 锚定，禁读 lib/）：
//   lib/features/onboarding/onboarding.dart:40-47  error/authError → /connection

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:nas_audio_player/app/onboarding.dart';
import 'package:nas_audio_player/core/network/webdav_client.dart';
import 'package:nas_audio_player/features/connection/connection_provider.dart';
import 'package:nas_audio_player/features/player/player_provider.dart';
import 'package:nas_audio_player/shared/models/connection_config.dart';

// ── Helpers（同 onboarding_test.dart 装配模式）─────────────────────────────

/// Sample connection config used in tests where connections are non-empty.
final _sampleConfig = ConnectionConfig(
  id: 1,
  name: 'Test NAS',
  url: 'http://192.168.1.100:5005',
  username: 'admin',
  createdAt: DateTime(2025, 1, 1),
  updatedAt: DateTime(2025, 1, 1),
);

/// Builds a [GoRouter] with `/`, `/browser`, and `/connection` routes,
/// with the [OnboardingPage] at the root route.
GoRouter _buildRouter({required GlobalKey<NavigatorState> navigatorKey}) {
  return GoRouter(
    navigatorKey: navigatorKey,
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        builder: (_, __) => const OnboardingPage(),
      ),
      GoRoute(
        path: '/browser',
        builder: (_, __) =>
            const Scaffold(body: Center(child: Text('Browser Page'))),
      ),
      GoRoute(
        path: '/connection',
        builder: (_, __) =>
            const Scaffold(body: Center(child: Text('Connection Page'))),
      ),
    ],
  );
}

/// Pumps the [OnboardingPage] inside a [ProviderScope] with given overrides
/// and a [GoRouter]. Returns the router to inspect the current location.
Future<GoRouter> _pumpOnboarding(
  WidgetTester tester, {
  required List<Override> overrides,
}) async {
  final navigatorKey = GlobalKey<NavigatorState>();
  final router = _buildRouter(navigatorKey: navigatorKey);

  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides,
      child: MaterialApp.router(routerConfig: router),
    ),
  );

  return router;
}

/// Standard overrides: non-empty connections（触发 startupValidation 执行）
/// + silence `restoreStartupProgressProvider`.
List<Override> _validationOverrides(
    Future<WebDavValidationResult> Function(Ref ref) validation) {
  return [
    connectionListProvider
        .overrideWith((ref) async => <ConnectionConfig>[_sampleConfig]),
    startupValidationProvider.overrideWith(validation),
    restoreStartupProgressProvider.overrideWith((ref) async {}),
  ];
}

// ═════════════════════════════════════════════════════════════════════════════
// TEST-03-S6: startupValidation 抛异常 → /connection
// ═════════════════════════════════════════════════════════════════════════════

void main() {
  group('TEST-03-S6: startupValidation 抛异常 → 路由 /connection', () {
    testWidgets('TEST-03-S6: error 分支跳转 /connection，非 /browser',
        (WidgetTester tester) async {
      final router = await _pumpOnboarding(
        tester,
        overrides: _validationOverrides(
          (ref) async => throw Exception('network down'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Connection Page'), findsOneWidget,
          reason: 'TEST-03-S6: startupValidation 抛异常后应跳转 /connection');
      expect(router.routerDelegate.currentConfiguration.uri.toString(),
          '/connection',
          reason: 'TEST-03-S6: 路由位置应为 /connection');
      // 否定断言：不得跳 /browser
      expect(find.text('Browser Page'), findsNothing,
          reason: '否定断言：error 分支不得重定向到 /browser');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // TEST-03-S7: authError → /connection（ONB-03 等价确认）
  // ═══════════════════════════════════════════════════════════════════════════

  group('TEST-03-S7: authError → 路由 /connection', () {
    testWidgets('TEST-03-S7: authError 分支跳转 /connection，非 /browser',
        (WidgetTester tester) async {
      final router = await _pumpOnboarding(
        tester,
        overrides: _validationOverrides(
          (ref) async => WebDavValidationResult.authError(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Connection Page'), findsOneWidget,
          reason: 'TEST-03-S7: authError 后应跳转 /connection');
      expect(router.routerDelegate.currentConfiguration.uri.toString(),
          '/connection',
          reason: 'TEST-03-S7: 路由位置应为 /connection');
      expect(find.text('Browser Page'), findsNothing,
          reason: '否定断言：authError 分支不得重定向到 /browser');
    });
  });
}
