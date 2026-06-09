// test/features/playlist/ply_12_test.dart
// PLY-12: 播放单列表页 — automated test suite
//
// Widget tests (PLY-T66~T72): empty state, FAB create dialog,
// list item rendering, dismiss delete confirmation.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nas_audio_player/features/playlist/playlist_list_screen.dart';
import 'package:nas_audio_player/features/playlist/playlist_provider.dart';
import 'package:nas_audio_player/shared/models/playlist.dart';

// ── Helpers ───────────────────────────────────────────────────────────────────

Playlist _testPlaylist({int? id, String name = 'Test', int trackCount = 0}) {
  final now = DateTime.now();
  return Playlist(
    id: id ?? 1,
    name: name,
    trackCount: trackCount,
    createdAt: now,
    updatedAt: now,
  );
}

Widget _buildTestApp(Widget child, {List<Override>? overrides}) {
  return ProviderScope(
    overrides: overrides ?? [],
    child: MaterialApp(home: Scaffold(body: child)),
  );
}

// ═════════════════════════════════════════════════════════════════════════════
// Widget tests — PLY-T66~T72
// ═════════════════════════════════════════════════════════════════════════════

void main() {
  // ── PLY-T66: empty state shows icon and help text ──────────────────────

  group('PLY-T66 empty state', () {
    testWidgets('shows empty icon and help text when no playlists',
        (WidgetTester tester) async {
      await tester.pumpWidget(_buildTestApp(
        const PlaylistListScreen(),
        overrides: [
          playlistListProvider
              .overrideWith((ref) => Future.value(<Playlist>[])),
        ],
      ));
      await tester.pumpAndSettle();

      expect(find.text('还没有播放单，点击 + 新建'), findsOneWidget);
      expect(find.byIcon(Icons.queue_music_outlined), findsOneWidget);
    });
  });

  // ── PLY-T67: FAB opens create dialog ───────────────────────────────────

  group('PLY-T67 FAB create dialog', () {
    testWidgets('tapping FAB shows create dialog', (WidgetTester tester) async {
      await tester.pumpWidget(_buildTestApp(
        const PlaylistListScreen(),
        overrides: [
          playlistListProvider
              .overrideWith((ref) => Future.value(<Playlist>[])),
        ],
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();

      expect(find.text('新建播放单'), findsOneWidget);
      expect(find.text('播放单名称'), findsOneWidget);
      expect(find.text('创建'), findsOneWidget);
      expect(find.text('取消'), findsOneWidget);
    });
  });

  // ── PLY-T68: create dialog validates non-empty name ────────────────────

  group('PLY-T68 create validation', () {
    testWidgets('create with empty name does nothing',
        (WidgetTester tester) async {
      await tester.pumpWidget(_buildTestApp(
        const PlaylistListScreen(),
        overrides: [
          playlistListProvider
              .overrideWith((ref) => Future.value(<Playlist>[])),
        ],
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();

      // Tap "创建" without entering text
      await tester.tap(find.text('创建'));
      await tester.pumpAndSettle();

      // Dialog should still be visible (empty name rejected)
      expect(find.text('新建播放单'), findsOneWidget);
    });
  });

  // ── PLY-T69: PlaylistListItem shows name and track count ───────────────

  group('PLY-T69 list item rendering', () {
    testWidgets('shows playlist name and track count',
        (WidgetTester tester) async {
      await tester.pumpWidget(_buildTestApp(
        const PlaylistListScreen(),
        overrides: [
          playlistListProvider.overrideWith((ref) => Future.value([
                _testPlaylist(id: 1, name: 'My Playlist', trackCount: 12),
              ])),
        ],
      ));
      await tester.pumpAndSettle();

      expect(find.text('My Playlist'), findsOneWidget);
      expect(find.text('12 首'), findsOneWidget);
    });

    testWidgets('shows multiple playlists', (WidgetTester tester) async {
      await tester.pumpWidget(_buildTestApp(
        const PlaylistListScreen(),
        overrides: [
          playlistListProvider.overrideWith((ref) => Future.value([
                _testPlaylist(id: 1, name: 'Alpha', trackCount: 3),
                _testPlaylist(id: 2, name: 'Bravo', trackCount: 0),
              ])),
        ],
      ));
      await tester.pumpAndSettle();

      expect(find.text('Alpha'), findsOneWidget);
      expect(find.text('Bravo'), findsOneWidget);
      expect(find.text('3 首'), findsOneWidget);
      expect(find.text('0 首'), findsOneWidget);
    });
  });

  // ── PLY-T70: Slidable shows delete button ───────────────────────────────

  group('PLY-T70 swipe reveals delete button', () {
    testWidgets('swipe left reveals delete button on action pane',
        (WidgetTester tester) async {
      await tester.pumpWidget(_buildTestApp(
        const PlaylistListScreen(),
        overrides: [
          playlistListProvider.overrideWith((ref) => Future.value([
                _testPlaylist(id: 1, name: 'Delete Me', trackCount: 5),
              ])),
        ],
      ));
      await tester.pumpAndSettle();

      // Swipe left to reveal the action pane
      await tester.drag(find.text('Delete Me'), const Offset(-500, 0));
      await tester.pumpAndSettle();

      // Delete button should be visible (icon or label)
      expect(find.byIcon(Icons.delete_outline), findsOneWidget);
    });
  });

  // ── PLY-T71: delete confirmation dialog ─────────────────────────────────

  group('PLY-T71 delete confirmation dialog', () {
    testWidgets('tapping delete button shows confirmation dialog',
        (WidgetTester tester) async {
      await tester.pumpWidget(_buildTestApp(
        const PlaylistListScreen(),
        overrides: [
          playlistListProvider.overrideWith((ref) => Future.value([
                _testPlaylist(id: 1, name: 'Keep Me', trackCount: 5),
              ])),
        ],
      ));
      await tester.pumpAndSettle();

      // Swipe left
      await tester.drag(find.text('Keep Me'), const Offset(-500, 0));
      await tester.pumpAndSettle();

      // Tap the delete button (by icon)
      await tester.tap(find.byIcon(Icons.delete_outline));
      await tester.pumpAndSettle();

      // Confirm dialog should appear
      expect(find.text('确认删除'), findsOneWidget);
      expect(find.textContaining('确认删除播放单「Keep Me」？此操作不可撤销。'), findsOneWidget);

      // Tap cancel
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();

      // Dialog dismissed, item still visible
      expect(find.text('Keep Me'), findsOneWidget);
    });
  });

  // ── PLY-T72: loading state shows skeleton ──────────────────────────────

  group('PLY-T72 loading state', () {
    testWidgets('shows skeleton while loading', (WidgetTester tester) async {
      // Use a Completer so we can control when (and if) it completes
      final completer = Completer<List<Playlist>>();
      addTearDown(() => completer.complete(<Playlist>[]));

      await tester.pumpWidget(_buildTestApp(
        const PlaylistListScreen(),
        overrides: [
          playlistListProvider.overrideWith((ref) => completer.future),
        ],
      ));
      // Single pump (not settle) so loading state is visible
      await tester.pump();

      // Should show skeleton containers (grey boxes)
      final containers = tester
          .widgetList<Container>(find.byType(Container))
          .where((c) =>
              c.decoration is BoxDecoration &&
              (c.decoration as BoxDecoration).color != null)
          .toList();
      expect(containers.isNotEmpty, isTrue);
    });
  });
}
