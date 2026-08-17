// test/features/player/bug_bug13_repro_test.dart
// BUG-13: player 错误态"检查连接"按钮用 Navigator.pushNamed 调未注册路由，
// 必抛 FlutterError
// （spec: docs/features/BUG-13.md §5.4，来源 cr-20260816-0804 B3）
//
// 缺陷：player_screen.dart:417-420 —
//   onPressed: () { Navigator.of(context).pop();
//                 Navigator.of(context).pushNamed('/connection'); }
// go_router 14.8.1 的 RouterDelegate 只用 Navigator(pages:... , onPopPage:...)
// 构建，无 onGenerateRoute —— pushNamed 解析失败抛
// FlutterError('Navigator.onGenerateRoute returned null for requested route')。
// 全项目导航均走 go_router 扩展（context.go/push），/connection 只存在于
// go_router 路由表（router.dart:27-31）。
//
// 装配（镜像生产形态）：PlayerScreen 经 context.push('/player') 推入
// 导航栈（生产里 /player 恒为 push 页面，pop 永远有效——go_router
// delegate.dart:98-105 对栈底 pop 抛 GoError('There is nothing to pop')，
// 若把 PlayerScreen 放根路由会误判修复态）。/connection 已注册为
// GoRoute —— 修复后的期望导航目标；缺陷态 pushNamed 绕过 go_router
// 直调裸 Navigator，与注册无关照样抛错。
//
// 门禁（修复前必须 FAIL）：
//   BUG-13-S1: 认证错误态点"检查连接"→ 必须无异常、进入 /connection 页面
//              —— 当前代码在 tap 回调内抛 FlutterError 使测试失败

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:just_audio/just_audio.dart';
import 'package:mockito/mockito.dart';
import 'package:nas_audio_player/features/player/player_provider.dart';
import 'package:nas_audio_player/features/player/player_screen.dart';
import 'package:nas_audio_player/features/player/domain/request_gate.dart';
import 'package:nas_audio_player/shared/di/providers.dart';
import 'package:nas_audio_player/shared/models/play_queue.dart';

import '../../helpers/mock_audio_player.dart';
import '../../helpers/test_factories.dart';

/// 装配：loadAndPlayProvider 返回 failed + activeConnectionProvider 为 null →
/// classifyLoadFailure → noConnection → isAuthError=true → 显示"检查连接"。
Widget _buildApp({
  required MockAudioPlayer player,
  required PlayQueue queue,
}) {
  final router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        builder: (_, __) => Scaffold(
          body: Center(
            child: Builder(
              builder: (context) => FilledButton(
                onPressed: () => context.push('/player'),
                child: const Text('GoPlayer'),
              ),
            ),
          ),
        ),
      ),
      GoRoute(
        path: '/player',
        builder: (_, __) => const PlayerScreen(),
      ),
      GoRoute(
        path: '/connection',
        builder: (_, __) =>
            const Scaffold(body: Center(child: Text('ConnectionStubPage'))),
      ),
    ],
  );
  return ProviderScope(
    overrides: [
      audioPlayerProvider.overrideWith((ref) => player),
      audioHandlerProvider.overrideWith((ref) => null),
      currentPlayQueueProvider.overrideWith((ref) => queue),
      seekStepSettingProvider.overrideWith((ref) => 15),
      activeConnectionProvider.overrideWith((ref) async => null),
      loadAndPlayProvider.overrideWith(
        (ref) => () async => const TrackLoadResult.failed(),
      ),
    ],
    child: MaterialApp.router(routerConfig: router),
  );
}

void main() {
  late MockAudioPlayer player;

  setUp(() {
    player = MockAudioPlayer();
    when(player.positionStream).thenAnswer(
        (_) => Stream.value(const Duration(minutes: 1, seconds: 30)));
    when(player.durationStream)
        .thenAnswer((_) => Stream.value(const Duration(minutes: 4)));
    when(player.playerStateStream).thenAnswer(
        (_) => Stream.value(PlayerState(true, ProcessingState.ready)));
    when(player.speedStream).thenAnswer((_) => Stream<double>.empty());
    when(player.processingStateStream)
        .thenAnswer((_) => const Stream<ProcessingState>.empty());
    when(player.playing).thenReturn(true);
    when(player.processingState).thenReturn(ProcessingState.ready);
    when(player.position).thenReturn(const Duration(minutes: 1, seconds: 30));
    when(player.duration).thenReturn(const Duration(minutes: 4));
    when(player.sequenceState).thenReturn(null);
  });

  testWidgets('BUG-13-S1: 认证错误态点"检查连接"→ 无异常且进入 /connection（当前抛错）',
      (tester) async {
    final queue = PlayQueue(
      files: [testAudio('Test Song.mp3', '/music/Test Song.mp3')],
      currentIndex: 0,
    );

    await tester.pumpWidget(_buildApp(player: player, queue: queue));
    await tester.pumpAndSettle();

    // 生产形态：/player 是 push 进入的页面（pop 永远有效）。
    await tester.tap(find.text('GoPlayer'));
    await tester.pumpAndSettle();
    await tester.pump(); // Post-frame callback fires → _loadAndPlay
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));

    // 前置：认证错误态已显示（含"检查连接"按钮）。
    expect(find.text('检查连接'), findsOneWidget,
        reason: '前置：noConnection 错误必须显示"检查连接"按钮'
            '（player_screen.dart:395-424 isAuth 分支）');

    // When: 点击"检查连接"。
    await tester.tap(find.text('检查连接'));
    await tester.pumpAndSettle();

    // Then: 无异常抛出，路由进入 /connection（连接配置页）。
    expect(find.text('ConnectionStubPage'), findsOneWidget,
        reason: 'BUG-13（cr-20260816-0804 B3）：player_screen.dart:417-420 用 '
            'Navigator.pushNamed(\'/connection\') —— go_router 14.8.1 的 '
            'Navigator 无 onGenerateRoute，点击必抛 '
            'FlutterError(\'Navigator.onGenerateRoute returned null for '
            'requested route\')，修复路径断掉（debug 红屏 / release 静默）。'
            '必须改用 go_router 扩展 context.pop() + context.push()');
  });
}
