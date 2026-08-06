// test/features/playlist/test_04_list9_test.dart
// TEST-04-S1~S3: MiniPlayerBar 展示（LIST9）— spec: docs/features/TEST-04.md §3.1
//
// 真实 HomeScreen 装配：override currentPlayQueueProvider + audioPlayerProvider
// （MockAudioPlayer），验证 MiniPlayerBar 条件渲染与点击跳转，而非空壳自证。

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:just_audio/just_audio.dart';
import 'package:mockito/mockito.dart';
import 'package:nas_audio_player/features/browser/browser_provider.dart';
import 'package:nas_audio_player/features/home/home_screen.dart';
import 'package:nas_audio_player/features/player/player_provider.dart';
import 'package:nas_audio_player/features/player/widgets/mini_player_bar.dart';
import 'package:nas_audio_player/features/playlist/playlist_provider.dart';
import 'package:nas_audio_player/shared/models/nas_file.dart';
import 'package:nas_audio_player/shared/models/play_queue.dart';
import 'package:nas_audio_player/shared/models/playlist.dart';

import '../../helpers/mock_audio_player.dart';
import '../../helpers/test_factories.dart';

// ── Helpers ───────────────────────────────────────────────────────────────────

/// Builds a routed app with the real [HomeScreen] at /home, a /player
/// destination, and the queue/player/playlist/browser providers overridden.
Widget _buildHomeApp({required PlayQueue? queue}) {
  final player = MockAudioPlayer();
  when(player.positionStream).thenAnswer((_) => Stream.value(Duration.zero));
  when(player.durationStream)
      .thenAnswer((_) => Stream.value(const Duration(minutes: 3)));
  when(player.playerStateStream).thenAnswer(
      (_) => Stream.value(PlayerState(false, ProcessingState.ready)));

  final router = GoRouter(
    initialLocation: '/home',
    routes: [
      GoRoute(
        path: '/home',
        builder: (_, __) => const HomeScreen(),
      ),
      GoRoute(
        path: '/player',
        builder: (_, __) =>
            const Scaffold(body: Center(child: Text('Player Page'))),
      ),
    ],
  );
  return ProviderScope(
    overrides: [
      currentPlayQueueProvider.overrideWith((ref) => queue),
      audioPlayerProvider.overrideWith((ref) => player),
      playlistListProvider.overrideWith((ref) => Future.value(<Playlist>[])),
      directoryContentsProvider('/')
          .overrideWith((ref) => Future.value(<NasFile>[])),
    ],
    child: MaterialApp.router(routerConfig: router),
  );
}

// ═════════════════════════════════════════════════════════════════════════════
// TEST-04-S1~S3 — MiniPlayerBar 展示 / 隐藏 / 跳转
// ═════════════════════════════════════════════════════════════════════════════

void main() {
  group('TEST-04-S1: 有队列时 MiniPlayerBar 展示当前曲名', () {
    testWidgets('TEST-04-S1: 非空队列 → MiniPlayerBar 存在且显示当前曲名',
        (WidgetTester tester) async {
      final queue = PlayQueue(
        files: [
          testAudio('Song A.mp3', '/music/Song A.mp3'),
          testAudio('Song B.flac', '/music/Song B.flac'),
        ],
        currentIndex: 0,
      );

      await tester.pumpWidget(_buildHomeApp(queue: queue));
      await tester.pumpAndSettle();

      // 前置：有队列时必须渲染 MiniPlayerBar（否定：不得隐藏）
      expect(find.byType(MiniPlayerBar), findsOneWidget,
          reason: 'TEST-04-S1: 有队列时 HomeScreen 必须渲染 MiniPlayerBar');
      // 展示当前曲名（否定：不得缺失曲名）
      expect(find.text('Song A.mp3'), findsOneWidget,
          reason: 'TEST-04-S1: MiniPlayerBar 应展示当前曲目名称');
      // 否定：不得展示非当前曲目名称
      expect(find.text('Song B.flac'), findsNothing,
          reason: 'TEST-04-S1: 非当前曲目名称不得出现在 MiniPlayerBar');
    });
  });

  group('TEST-04-S2: 空队列时 MiniPlayerBar 不占可见内容', () {
    testWidgets('TEST-04-S2: 空队列 → MiniPlayerBar 高度为 0、无播放控件',
        (WidgetTester tester) async {
      final emptyQueue = PlayQueue(files: [], currentIndex: 0);

      await tester.pumpWidget(_buildHomeApp(queue: emptyQueue));
      await tester.pumpAndSettle();

      // 生产行为：空队列时仍存在 MiniPlayerBar widget，但渲染为
      // SizedBox.shrink()（高度 0）——不得占据布局空间。
      expect(find.byType(MiniPlayerBar), findsOneWidget,
          reason: 'TEST-04-S2: 前置——MiniPlayerBar widget 存在');
      expect(tester.getSize(find.byType(MiniPlayerBar)).height, equals(0),
          reason: 'TEST-04-S2: 空队列时 MiniPlayerBar 高度必须为 0（不占可见内容）');
      // 否定：空队列时不得渲染任何播放控件内容
      expect(find.byIcon(Icons.play_arrow), findsNothing,
          reason: 'TEST-04-S2: 空队列时不得显示播放按钮');
      expect(find.byIcon(Icons.queue_music), findsNothing,
          reason: 'TEST-04-S2: 空队列时不得显示队列按钮');
    });
  });

  group('TEST-04-S3: 点击 MiniPlayerBar 跳转播放器', () {
    testWidgets('TEST-04-S3: 有队列点击 MiniPlayerBar → 路由跳转 /player',
        (WidgetTester tester) async {
      final queue = PlayQueue(
        files: [testAudio('Song A.mp3', '/music/Song A.mp3')],
        currentIndex: 0,
      );

      await tester.pumpWidget(_buildHomeApp(queue: queue));
      await tester.pumpAndSettle();

      expect(find.byType(MiniPlayerBar), findsOneWidget,
          reason: 'TEST-04-S3: 前置——MiniPlayerBar 已渲染');

      await tester.tap(find.byType(MiniPlayerBar));
      await tester.pumpAndSettle();

      // 否定：点击后必须跳转播放器（不得无响应）
      expect(find.text('Player Page'), findsOneWidget,
          reason: 'TEST-04-S3: 点击 MiniPlayerBar 应跳转到 /player 页面');
    });
  });
}
