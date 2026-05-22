// test/features/playlist/ply_13_test.dart
// PLY-13: 播放单详情页 + 添加曲目弹窗 — automated test suite
//
// Widget tests (PLY-T73~T85): detail screen states, selection mode,
// track tap/long-press, sort, delete confirmation.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:nas_audio_player/features/playlist/playlist_detail_screen.dart';
import 'package:nas_audio_player/features/playlist/playlist_provider.dart';
import 'package:nas_audio_player/shared/models/playlist.dart';

// ── Helpers ───────────────────────────────────────────────────────────────────

PlaylistTrack _testTrack({
  int? id,
  int playlistId = 1,
  String filePath = '/music/song.mp3',
  String fileName = 'song.mp3',
  DateTime? addedAt,
}) {
  return PlaylistTrack(
    id: id ?? 1,
    playlistId: playlistId,
    filePath: filePath,
    fileName: fileName,
    addedAt: addedAt ?? DateTime.now(),
  );
}

final _now = DateTime.now();
final _testPlaylist = Playlist(
  id: 1,
  name: 'Test Playlist',
  trackCount: 0,
  createdAt: _now,
  updatedAt: _now,
);

final _testPlaylists = [_testPlaylist];

Widget _buildTestApp(Widget child, {List<Override>? overrides}) {
  final router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        builder: (_, __) => child,
      ),
      GoRoute(
        path: '/player',
        builder: (_, __) =>
            const Scaffold(body: Center(child: Text('Player'))),
      ),
    ],
  );
  return ProviderScope(
    overrides: overrides ?? [],
    child: MaterialApp.router(
      routerConfig: router,
    ),
  );
}

// ═════════════════════════════════════════════════════════════════════════════
// Widget tests — PLY-T73~T85
// ═════════════════════════════════════════════════════════════════════════════

void main() {
  // ── PLY-T73: loading state ───────────────────────────────────────────

  group('PLY-T73 loading state', () {
    testWidgets('shows loading spinner', (WidgetTester tester) async {
      final completer = Completer<List<PlaylistTrack>>();
      addTearDown(() => completer.complete(<PlaylistTrack>[]));

      await tester.pumpWidget(_buildTestApp(
        const PlaylistDetailScreen(playlistId: 1),
        overrides: [
          playlistTracksProvider(1)
              .overrideWith((ref) => completer.future),
          playlistListProvider
              .overrideWith((ref) => Future.value(_testPlaylists)),
        ],
      ));
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });
  });

  // ── PLY-T74: empty playlist ─────────────────────────────────────────

  group('PLY-T74 empty playlist', () {
    testWidgets('shows empty message', (WidgetTester tester) async {
      await tester.pumpWidget(_buildTestApp(
        const PlaylistDetailScreen(playlistId: 1),
        overrides: [
          playlistTracksProvider(1)
              .overrideWith((ref) => Future.value(<PlaylistTrack>[])),
          playlistListProvider
              .overrideWith((ref) => Future.value(_testPlaylists)),
        ],
      ));
      await tester.pumpAndSettle();

      expect(find.text('播放单为空'), findsOneWidget);
      expect(find.text('点击右上角 + 添加曲目'), findsOneWidget);
    });
  });

  // ── PLY-T75: track list renders ─────────────────────────────────────

  group('PLY-T75 track list', () {
    testWidgets('shows track file names', (WidgetTester tester) async {
      await tester.pumpWidget(_buildTestApp(
        const PlaylistDetailScreen(playlistId: 1),
        overrides: [
          playlistTracksProvider(1).overrideWith((ref) => Future.value([
                _testTrack(id: 1, fileName: 'Track A.mp3'),
                _testTrack(id: 2, fileName: 'Track B.flac'),
              ])),
          playlistListProvider
              .overrideWith((ref) => Future.value(_testPlaylists)),
        ],
      ));
      await tester.pumpAndSettle();

      expect(find.text('Track A.mp3'), findsOneWidget);
      expect(find.text('Track B.flac'), findsOneWidget);
    });
  });

  // ── PLY-T76: track tap builds queue ─────────────────────────────────

  group('PLY-T76 track tap', () {
    testWidgets('tapping track sets play queue', (WidgetTester tester) async {
      await tester.pumpWidget(_buildTestApp(
        const PlaylistDetailScreen(playlistId: 1),
        overrides: [
          playlistTracksProvider(1).overrideWith((ref) => Future.value([
                _testTrack(
                    id: 1,
                    filePath: '/music/a.mp3',
                    fileName: 'a.mp3'),
                _testTrack(
                    id: 2,
                    filePath: '/music/b.mp3',
                    fileName: 'b.mp3'),
              ])),
          playlistListProvider
              .overrideWith((ref) => Future.value(_testPlaylists)),
        ],
      ));
      await tester.pumpAndSettle();

      // Tap first track
      await tester.tap(find.text('a.mp3'));
      await tester.pumpAndSettle();

      // Should navigate to player
      expect(find.text('Player'), findsOneWidget);
    });
  });

  // ── PLY-T77: long press enters selection mode ───────────────────────

  group('PLY-T77 long press selection', () {
    testWidgets('long pressing track enters selection mode',
        (WidgetTester tester) async {
      await tester.pumpWidget(_buildTestApp(
        const PlaylistDetailScreen(playlistId: 1),
        overrides: [
          playlistTracksProvider(1).overrideWith((ref) => Future.value([
                _testTrack(id: 1, fileName: 'Track.mp3'),
              ])),
          playlistListProvider
              .overrideWith((ref) => Future.value(_testPlaylists)),
        ],
      ));
      await tester.pumpAndSettle();

      // Long press the track
      await tester.longPress(find.text('Track.mp3'));
      await tester.pumpAndSettle();

      // Should show "已选 1 首"
      expect(find.text('已选 1 首'), findsOneWidget);
      // Should show check circle icon for selected track
      expect(find.byIcon(Icons.check_circle), findsOneWidget);
    });
  });

  // ── PLY-T78: selection mode AppBar ──────────────────────────────────

  group('PLY-T78 selection mode AppBar', () {
    testWidgets('selection mode shows correct AppBar actions',
        (WidgetTester tester) async {
      await tester.pumpWidget(_buildTestApp(
        const PlaylistDetailScreen(playlistId: 1),
        overrides: [
          playlistTracksProvider(1).overrideWith((ref) => Future.value([
                _testTrack(id: 1, fileName: 'Track.mp3'),
              ])),
          playlistListProvider
              .overrideWith((ref) => Future.value(_testPlaylists)),
        ],
      ));
      await tester.pumpAndSettle();

      await tester.longPress(find.text('Track.mp3'));
      await tester.pumpAndSettle();

      expect(find.text('已选 1 首'), findsOneWidget);
      expect(find.byIcon(Icons.select_all), findsOneWidget);
      expect(find.byIcon(Icons.deselect), findsOneWidget);
      expect(find.byIcon(Icons.delete_outline), findsOneWidget);
      expect(find.byIcon(Icons.close), findsOneWidget);
    });
  });

  // ── PLY-T79: select all / deselect all ──────────────────────────────

  group('PLY-T79 select all / deselect all', () {
    testWidgets('select all selects all tracks', (WidgetTester tester) async {
      await tester.pumpWidget(_buildTestApp(
        const PlaylistDetailScreen(playlistId: 1),
        overrides: [
          playlistTracksProvider(1).overrideWith((ref) => Future.value([
                _testTrack(id: 1, fileName: 'A.mp3'),
                _testTrack(id: 2, fileName: 'B.mp3'),
                _testTrack(id: 3, fileName: 'C.mp3'),
              ])),
          playlistListProvider
              .overrideWith((ref) => Future.value(_testPlaylists)),
        ],
      ));
      await tester.pumpAndSettle();

      // Enter selection mode
      await tester.longPress(find.text('A.mp3'));
      await tester.pumpAndSettle();

      // Tap "select all"
      await tester.tap(find.byIcon(Icons.select_all));
      await tester.pumpAndSettle();

      expect(find.text('已选 3 首'), findsOneWidget);
    });

    testWidgets('deselect all clears selection', (WidgetTester tester) async {
      await tester.pumpWidget(_buildTestApp(
        const PlaylistDetailScreen(playlistId: 1),
        overrides: [
          playlistTracksProvider(1).overrideWith((ref) => Future.value([
                _testTrack(id: 1, fileName: 'A.mp3'),
              ])),
          playlistListProvider
              .overrideWith((ref) => Future.value(_testPlaylists)),
        ],
      ));
      await tester.pumpAndSettle();

      await tester.longPress(find.text('A.mp3'));
      await tester.pumpAndSettle();

      // Tap deselect all
      await tester.tap(find.byIcon(Icons.deselect));
      await tester.pumpAndSettle();

      expect(find.text('已选 0 首'), findsOneWidget);
    });
  });

  // ── PLY-T80: delete selected confirmation ───────────────────────────

  group('PLY-T80 delete confirmation', () {
    testWidgets('delete button shows confirmation dialog',
        (WidgetTester tester) async {
      await tester.pumpWidget(_buildTestApp(
        const PlaylistDetailScreen(playlistId: 1),
        overrides: [
          playlistTracksProvider(1).overrideWith((ref) => Future.value([
                _testTrack(id: 1, fileName: 'Delete.mp3'),
              ])),
          playlistListProvider
              .overrideWith((ref) => Future.value(_testPlaylists)),
        ],
      ));
      await tester.pumpAndSettle();

      // Enter selection mode
      await tester.longPress(find.text('Delete.mp3'));
      await tester.pumpAndSettle();

      // Tap delete
      await tester.tap(find.byIcon(Icons.delete_outline));
      await tester.pumpAndSettle();

      expect(find.text('确认删除'), findsOneWidget);
      expect(find.textContaining('确认删除选中的 1 首曲目？'), findsOneWidget);
    });
  });

  // ── PLY-T81: normal AppBar has sort and add ────────────────────────

  group('PLY-T81 normal AppBar', () {
    testWidgets('normal AppBar shows playlist name, add and sort buttons',
        (WidgetTester tester) async {
      await tester.pumpWidget(_buildTestApp(
        const PlaylistDetailScreen(playlistId: 1),
        overrides: [
          playlistTracksProvider(1)
              .overrideWith((ref) => Future.value(<PlaylistTrack>[])),
          playlistListProvider
              .overrideWith((ref) => Future.value(_testPlaylists)),
        ],
      ));
      await tester.pumpAndSettle();

      expect(find.text('Test Playlist'), findsOneWidget);
      expect(find.byIcon(Icons.add), findsOneWidget);
      expect(find.byIcon(Icons.sort), findsOneWidget);
    });
  });

  // ── PLY-T82: exit selection via close button ───────────────────────

  group('PLY-T82 exit selection mode', () {
    testWidgets('close button exits selection mode',
        (WidgetTester tester) async {
      await tester.pumpWidget(_buildTestApp(
        const PlaylistDetailScreen(playlistId: 1),
        overrides: [
          playlistTracksProvider(1).overrideWith((ref) => Future.value([
                _testTrack(id: 1, fileName: 'Track.mp3'),
              ])),
          playlistListProvider
              .overrideWith((ref) => Future.value(_testPlaylists)),
        ],
      ));
      await tester.pumpAndSettle();

      await tester.longPress(find.text('Track.mp3'));
      await tester.pumpAndSettle();
      expect(find.text('已选 1 首'), findsOneWidget);

      // Tap close
      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();

      // Should be back to normal mode
      expect(find.text('Test Playlist'), findsOneWidget);
      expect(find.byIcon(Icons.add), findsOneWidget);
    });
  });
}
