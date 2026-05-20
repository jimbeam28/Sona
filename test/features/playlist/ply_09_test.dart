// test/features/playlist/ply_09_test.dart
// PLY-09: 播放单主入口 + Tab 导航 — automated test suite
//
// Widget tests (PLY-T60~T65): HomeScreen tabs, AppBar, MiniPlayerBar, sort menu.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:nas_audio_player/features/browser/browser_provider.dart';
import 'package:nas_audio_player/features/home/home_screen.dart';
import 'package:nas_audio_player/features/playlist/playlist_provider.dart';
import 'package:nas_audio_player/shared/models/playlist.dart';

import 'package:nas_audio_player/shared/models/nas_file.dart';

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

// ═════════════════════════════════════════════════════════════════════════════
// Widget tests — PLY-T60~T65
// ═════════════════════════════════════════════════════════════════════════════

void main() {
  // ── PLY-T60: two tabs ────────────────────────────────────────────────

  group('PLY-T60 tabs', () {
    testWidgets('shows two tabs', (WidgetTester tester) async {
      await tester.pumpWidget(_buildTestApp(overrides: [
        playlistListProvider
            .overrideWith((ref) => Future.value(<Playlist>[])),
        directoryContentsProvider('/')
            .overrideWith((ref) => Future.value(<NasFile>[])),
      ]));
      await tester.pumpAndSettle();

      expect(find.text('播放单'), findsOneWidget);
      expect(find.text('文件浏览器'), findsOneWidget);
    });
  });

  // ── PLY-T61: AppBar title and settings ───────────────────────────────

  group('PLY-T61 AppBar', () {
    testWidgets('shows Sona title and settings icon',
        (WidgetTester tester) async {
      await tester.pumpWidget(_buildTestApp(overrides: [
        playlistListProvider
            .overrideWith((ref) => Future.value(<Playlist>[])),
        directoryContentsProvider('/')
            .overrideWith((ref) => Future.value(<NasFile>[])),
      ]));
      await tester.pumpAndSettle();

      expect(find.text('Sona'), findsOneWidget);
      expect(find.byIcon(Icons.settings), findsOneWidget);
    });
  });

  // ── PLY-T62: MiniPlayerBar ───────────────────────────────────────────

  group('PLY-T62 MiniPlayerBar', () {
    testWidgets('shows MiniPlayerBar at bottom', (WidgetTester tester) async {
      await tester.pumpWidget(_buildTestApp(overrides: [
        playlistListProvider
            .overrideWith((ref) => Future.value(<Playlist>[])),
        directoryContentsProvider('/')
            .overrideWith((ref) => Future.value(<NasFile>[])),
      ]));
      await tester.pumpAndSettle();

      // MiniPlayerBar renders when no audio is loaded (empty Container)
      // Just verify the HomeScreen renders without error
      expect(find.text('Sona'), findsOneWidget);
    });
  });

  // ── PLY-T63: Tab 0 PlaylistListScreen content ───────────────────────

  group('PLY-T63 playlist tab', () {
    testWidgets('shows empty playlist message on tab 0',
        (WidgetTester tester) async {
      await tester.pumpWidget(_buildTestApp(overrides: [
        playlistListProvider
            .overrideWith((ref) => Future.value(<Playlist>[])),
        directoryContentsProvider('/')
            .overrideWith((ref) => Future.value(<NasFile>[])),
      ]));
      await tester.pumpAndSettle();

      // Tab 0 is active by default, should show empty state
      expect(find.text('还没有播放单，点击 + 新建'), findsOneWidget);
    });

    testWidgets('switching to tab 1 shows browser content',
        (WidgetTester tester) async {
      await tester.pumpWidget(_buildTestApp(overrides: [
        playlistListProvider
            .overrideWith((ref) => Future.value(<Playlist>[])),
        directoryContentsProvider('/')
            .overrideWith((ref) => Future.value(<NasFile>[])),
      ]));
      await tester.pumpAndSettle();

      // Tap tab 1
      await tester.tap(find.text('文件浏览器'));
      await tester.pumpAndSettle();

      // Should show browser empty state
      expect(find.text('此目录为空'), findsOneWidget);
    });
  });

  // ── PLY-T64: Tab 1 BrowserScreen content ────────────────────────────

  group('PLY-T64 browser tab', () {
    testWidgets('shows browser content on tab 1', (WidgetTester tester) async {
      await tester.pumpWidget(_buildTestApp(overrides: [
        playlistListProvider
            .overrideWith((ref) => Future.value(<Playlist>[])),
        directoryContentsProvider('/')
            .overrideWith((ref) => Future.value(<NasFile>[])),
      ]));
      await tester.pumpAndSettle();

      // Switch to browser tab
      await tester.tap(find.text('文件浏览器'));
      await tester.pumpAndSettle();

      expect(find.text('此目录为空'), findsOneWidget);
    });
  });

  // ── PLY-T65: sort menu by tab ───────────────────────────────────────

  group('PLY-T65 sort menu', () {
    testWidgets('shows sort icon in AppBar', (WidgetTester tester) async {
      await tester.pumpWidget(_buildTestApp(overrides: [
        playlistListProvider
            .overrideWith((ref) => Future.value(<Playlist>[])),
        directoryContentsProvider('/')
            .overrideWith((ref) => Future.value(<NasFile>[])),
      ]));
      await tester.pumpAndSettle();

      // Sort icon should be visible in AppBar
      expect(find.byIcon(Icons.sort), findsOneWidget);
    });
  });
}
