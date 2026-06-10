// test/features/home/onboarding_test.dart
// TREF-05: OnboardingPage redirect logic — automated test suite
//
// Widget tests (TREF-05-T01~T05): covers the 3 redirect paths + loading + error
// scenarios for the OnboardingPage ConsumerWidget.
//
// Source: lib/app/onboarding.dart:13-77
//
// Provider overrides used:
//   - connectionListProvider  → AsyncData / AsyncLoading / AsyncError
//   - startupValidationProvider → AsyncData / AsyncLoading / AsyncError
//   - restoreStartupProgressProvider → no-op override (prevent real side effects)

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:nas_audio_player/app/onboarding.dart';
import 'package:nas_audio_player/core/network/webdav_client.dart';
import 'package:nas_audio_player/features/connection/connection_provider.dart';
import 'package:nas_audio_player/features/player/player_provider.dart';
import 'package:nas_audio_player/shared/models/connection_config.dart';

// ── Helpers ───────────────────────────────────────────────────────────────────

/// Sample connection config used in tests where connections are non-empty.
final _sampleConfig = ConnectionConfig(
  id: 1,
  name: 'Test NAS',
  url: 'http://192.168.1.100:5005',
  username: 'admin',
  createdAt: DateTime(2025, 1, 1),
  updatedAt: DateTime(2025, 1, 1),
);

/// Builds a [GoRouter] that has routes for `/`, `/browser`, and `/connection`,
/// with the [OnboardingPage] at the root route.
GoRouter _buildRouter({
  required GlobalKey<NavigatorState> navigatorKey,
  Listenable? refreshListenable,
}) {
  return GoRouter(
    navigatorKey: navigatorKey,
    initialLocation: '/',
    refreshListenable: refreshListenable,
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
/// and a [GoRouter] that includes `/browser` and `/connection` routes.
///
/// Returns the [GoRouter] so the caller can inspect the current location.
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

/// Standard overrides that silence `restoreStartupProgressProvider` so it
/// doesn't try to read real SharedPreferences or audio player state.
Override _noopRestoreOverride() {
  return restoreStartupProgressProvider.overrideWith((ref) async {});
}

// ═════════════════════════════════════════════════════════════════════════════
// TREF-05: OnboardingPage redirect logic
// ═════════════════════════════════════════════════════════════════════════════

void main() {
  // ── TREF-05-T01 (ONB-01): empty connections → CTA scaffold ────────────────

  group('TREF-05: OnboardingPage redirect logic', () {
    testWidgets('ONB-01: empty connection list shows CTA "添加第一个 NAS 连接"',
        (WidgetTester tester) async {
      await _pumpOnboarding(
        tester,
        overrides: [
          connectionListProvider
              .overrideWith((ref) async => <ConnectionConfig>[]),
          _noopRestoreOverride(),
        ],
      );
      await tester.pumpAndSettle();

      // The CTA scaffold should be visible with the title and button.
      expect(find.text('添加第一个 NAS 连接'), findsOneWidget,
          reason: 'ONB-01: 空连接列表时应显示引导页标题');
      expect(find.text('添加连接'), findsOneWidget,
          reason: 'ONB-01: 空连接列表时应显示"添加连接"按钮');
      expect(find.byIcon(Icons.storage_outlined), findsOneWidget,
          reason: 'ONB-01: 应显示存储图标');

      // Should NOT redirect — still on the onboarding page.
      expect(find.text('Browser Page'), findsNothing);
      expect(find.text('Connection Page'), findsNothing);
    });

    // ── TREF-05-T02 (ONB-02): connections exist + validation success → /browser

    testWidgets(
        'ONB-02: connections exist + validation success redirects to /browser',
        (WidgetTester tester) async {
      final router = await _pumpOnboarding(
        tester,
        overrides: [
          connectionListProvider
              .overrideWith((ref) async => <ConnectionConfig>[_sampleConfig]),
          startupValidationProvider
              .overrideWith((ref) async => WebDavValidationResult.success()),
          _noopRestoreOverride(),
        ],
      );
      await tester.pumpAndSettle();

      // The addPostFrameCallback should have fired and navigated to /browser.
      expect(find.text('Browser Page'), findsOneWidget,
          reason: 'ONB-02: 验证成功后应跳转到 /browser');
      expect(
          router.routerDelegate.currentConfiguration.uri.toString(), '/browser',
          reason: 'ONB-02: 路由位置应为 /browser');
    });

    // ── TREF-05-T03 (ONB-03): connections exist + validation failure → /connection

    testWidgets(
        'ONB-03: connections exist + validation failure redirects to /connection',
        (WidgetTester tester) async {
      final router = await _pumpOnboarding(
        tester,
        overrides: [
          connectionListProvider
              .overrideWith((ref) async => <ConnectionConfig>[_sampleConfig]),
          startupValidationProvider
              .overrideWith((ref) async => WebDavValidationResult.authError()),
          _noopRestoreOverride(),
        ],
      );
      await tester.pumpAndSettle();

      // The addPostFrameCallback should have fired and navigated to /connection.
      expect(find.text('Connection Page'), findsOneWidget,
          reason: 'ONB-03: 验证失败后应跳转到 /connection');
      expect(router.routerDelegate.currentConfiguration.uri.toString(),
          '/connection',
          reason: 'ONB-03: 路由位置应为 /connection');
    });

    // ── TREF-05-T04 (ONB-04): connectionListProvider loading → CircularProgressIndicator

    testWidgets(
        'ONB-04: connectionListProvider loading shows CircularProgressIndicator',
        (WidgetTester tester) async {
      await _pumpOnboarding(
        tester,
        overrides: [
          // Use a Future that never completes to keep the loading state.
          connectionListProvider.overrideWith((ref) {
            final c = Completer<List<ConnectionConfig>>();
            // Don't complete — keep loading forever.
            return c.future;
          }),
          _noopRestoreOverride(),
        ],
      );
      // Single pump to trigger build, but don't settle (future never completes).
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget,
          reason:
              'ONB-04: connectionListProvider 加载中时应显示 CircularProgressIndicator');
      // No CTA or redirect.
      expect(find.text('添加第一个 NAS 连接'), findsNothing);
      expect(find.text('Browser Page'), findsNothing);
      expect(find.text('Connection Page'), findsNothing);
    });

    // ── TREF-05-T05 (ONB-05): connectionListProvider error → OnboardingErrorView

    testWidgets(
        'ONB-05: connectionListProvider error shows OnboardingErrorView',
        (WidgetTester tester) async {
      await _pumpOnboarding(
        tester,
        overrides: [
          connectionListProvider.overrideWith((ref) {
            throw Exception('DB corrupted');
          }),
          _noopRestoreOverride(),
        ],
      );
      await tester.pumpAndSettle();

      // OnboardingErrorView should be displayed with the error message.
      expect(find.byType(OnboardingErrorView), findsOneWidget,
          reason: 'ONB-05: connectionListProvider 错误时应显示 OnboardingErrorView');
      expect(find.text('数据加载失败'), findsOneWidget, reason: 'ONB-05: 应显示错误标题');
      expect(find.textContaining('无法读取连接列表'), findsOneWidget,
          reason: 'ONB-05: 应包含错误详情');
      expect(find.text('重试'), findsOneWidget, reason: 'ONB-05: 应显示重试按钮');
    });
  });
}
