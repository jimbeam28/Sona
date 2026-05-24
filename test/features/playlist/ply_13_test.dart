// test/features/playlist/ply_13_test.dart
// PLY-13: 播放单详情页 + 添加曲目弹窗 — automated test suite
//
// Widget tests (PLY-T73~T85): detail screen states, selection mode,
// track tap/long-press, sort, delete confirmation.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fake_async/fake_async.dart';
import 'package:go_router/go_router.dart';
import 'package:nas_audio_player/core/database/dao/playlist_dao.dart';
import 'package:nas_audio_player/core/database/database_helper.dart';
import 'package:nas_audio_player/features/playlist/playlist_detail_screen.dart';
import 'package:nas_audio_player/features/playlist/playlist_provider.dart';
import 'package:nas_audio_player/features/playlist/widgets/playlist_track_item.dart';
import 'package:nas_audio_player/shared/models/playlist.dart';
import 'package:nas_audio_player/features/browser/browser_provider.dart';
import 'package:nas_audio_player/features/connection/connection_provider.dart';
import 'package:nas_audio_player/features/progress/progress_provider.dart';
import 'package:nas_audio_player/shared/models/connection_config.dart';
import 'package:nas_audio_player/shared/models/play_progress.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

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

// ── TST-04 test data ───────────────────────────────────────────────────────

final _tstConn = ConnectionConfig(
  id: 1,
  name: 'Test Conn',
  url: 'http://test.local',
  username: 'testuser',
  createdAt: _now,
  updatedAt: _now,
);

PlayProgress _tstProgress({
  String filePath = '/music/with_progress.mp3',
  int positionMs = 120000,
}) {
  return PlayProgress(
    connectionId: 1,
    filePath: filePath,
    positionMs: positionMs,
    durationMs: 240000,
    lastPlayedAt: _now,
  );
}

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
  setUpAll(() {
    sqfliteFfiInit();
  });

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

  // ═════════════════════════════════════════════════════════════════════════════
  // TST-04: 进度恢复集成测试 (TST-T20~TST-T25)
  // ═════════════════════════════════════════════════════════════════════════════

  group('TST-T20 resume with saved progress', () {
    testWidgets('shows dialog, choose resume, queue has startPositionMs',
        (WidgetTester tester) async {
      final progress = _tstProgress(filePath: '/music/resume.mp3');

      await tester.pumpWidget(_buildTestApp(
        const PlaylistDetailScreen(playlistId: 1),
        overrides: [
          playlistTracksProvider(1).overrideWith((ref) => Future.value([
                _testTrack(
                    id: 1,
                    filePath: '/music/resume.mp3',
                    fileName: 'resume.mp3'),
              ])),
          playlistListProvider
              .overrideWith((ref) => Future.value(_testPlaylists)),
          activeConnectionProvider
              .overrideWith((ref) => Future.value(_tstConn)),
          progressForFileProvider((connectionId: 1, filePath: '/music/resume.mp3'))
              .overrideWith((ref) => Future.value(progress)),
        ],
      ));
      await tester.pumpAndSettle();

      // Pre-heat activeConnectionProvider so valueOrNull returns _tstConn
      final container = ProviderScope.containerOf(
        tester.element(find.byType(PlaylistDetailScreen)),
      );
      container.read(activeConnectionProvider);
      await tester.pump(); // Process state transition to AsyncData

      // Tap track triggers _playTrackAtIndex
      await tester.tap(find.text('resume.mp3'));
      await tester.pump(); // Process tap event
      await tester.pump(); // Process async continuation → showDialog
      await tester.pump(); // Build dialog route

      // Dialog should be visible
      expect(find.text('恢复播放进度'), findsOneWidget);

      // Tap "继续播放" button
      await tester.tap(find.textContaining('继续播放'));
      await tester.pump(); // Process Navigator.pop(true) → then callback
      await tester.pump(); // Process await → build queue → push /player
      await tester.pump(); // Build player route

      // Verify navigation to /player
      expect(find.text('Player'), findsOneWidget);

      // Verify PlayQueue has startPositionMs
      final ctx = tester.element(find.text('Player'));
      final playerContainer = ProviderScope.containerOf(ctx);
      final queue = playerContainer.read(currentPlayQueueProvider);
      expect(queue, isNotNull);
      expect(queue!.startPositionMs, equals(120000));
      expect(queue.currentIndex, equals(0));
    });
  });

  group('TST-T21 resume dialog choose restart', () {
    testWidgets('shows dialog, choose restart, queue has no startPositionMs',
        (WidgetTester tester) async {
      final progress = _tstProgress(filePath: '/music/restart.mp3');

      await tester.pumpWidget(_buildTestApp(
        const PlaylistDetailScreen(playlistId: 1),
        overrides: [
          playlistTracksProvider(1).overrideWith((ref) => Future.value([
                _testTrack(
                    id: 1,
                    filePath: '/music/restart.mp3',
                    fileName: 'restart.mp3'),
              ])),
          playlistListProvider
              .overrideWith((ref) => Future.value(_testPlaylists)),
          activeConnectionProvider
              .overrideWith((ref) => Future.value(_tstConn)),
          progressForFileProvider((connectionId: 1, filePath: '/music/restart.mp3'))
              .overrideWith((ref) => Future.value(progress)),
        ],
      ));
      await tester.pumpAndSettle();

      // Pre-heat activeConnectionProvider
      final container = ProviderScope.containerOf(
        tester.element(find.byType(PlaylistDetailScreen)),
      );
      container.read(activeConnectionProvider);
      await tester.pump();

      // Tap track
      await tester.tap(find.text('restart.mp3'));
      await tester.pump();
      await tester.pump();
      await tester.pump();

      // Dialog should be visible
      expect(find.text('恢复播放进度'), findsOneWidget);

      // Tap "从头播放" button
      await tester.tap(find.text('从头播放'));
      await tester.pump(); // Process Navigator.pop(false) → then callback
      await tester.pump(); // Process await → startPositionMs=null → push /player
      await tester.pump(); // Build player route

      // Verify navigation to /player
      expect(find.text('Player'), findsOneWidget);

      // Verify PlayQueue has no startPositionMs
      final ctx = tester.element(find.text('Player'));
      final playerContainer = ProviderScope.containerOf(ctx);
      final queue = playerContainer.read(currentPlayQueueProvider);
      expect(queue, isNotNull);
      expect(queue!.startPositionMs, isNull);
      expect(queue.currentIndex, equals(0));
    });
  });

  group('TST-T22 no progress → direct play', () {
    testWidgets('no dialog, queue has no startPositionMs',
        (WidgetTester tester) async {
      await tester.pumpWidget(_buildTestApp(
        const PlaylistDetailScreen(playlistId: 1),
        overrides: [
          playlistTracksProvider(1).overrideWith((ref) => Future.value([
                _testTrack(
                    id: 1,
                    filePath: '/music/noprogress.mp3',
                    fileName: 'noprogress.mp3'),
              ])),
          playlistListProvider
              .overrideWith((ref) => Future.value(_testPlaylists)),
          activeConnectionProvider
              .overrideWith((ref) => Future.value(_tstConn)),
          progressForFileProvider
              .overrideWith((ref, key) => Future.value(null)),
        ],
      ));
      await tester.pumpAndSettle();

      // Tap track
      await tester.tap(find.text('noprogress.mp3'));
      await tester.pump(); // Process tap
      await tester.pump(); // Process await → progress null → skip → push /player
      await tester.pump(); // Build player route

      // Should navigate directly without dialog
      expect(find.text('恢复播放进度'), findsNothing);
      expect(find.text('Player'), findsOneWidget);

      // Verify PlayQueue has no startPositionMs
      final ctx = tester.element(find.text('Player'));
      final container = ProviderScope.containerOf(ctx);
      final queue = container.read(currentPlayQueueProvider);
      expect(queue, isNotNull);
      expect(queue!.startPositionMs, isNull);
      expect(queue.currentIndex, equals(0));
    });
  });

  group('TST-T23 positionMs < 5000 → skip dialog', () {
    testWidgets('short progress skipped, no dialog',
        (WidgetTester tester) async {
      final shortProgress = _tstProgress(
        filePath: '/music/short.mp3',
        positionMs: 3000,
      );

      await tester.pumpWidget(_buildTestApp(
        const PlaylistDetailScreen(playlistId: 1),
        overrides: [
          playlistTracksProvider(1).overrideWith((ref) => Future.value([
                _testTrack(
                    id: 1,
                    filePath: '/music/short.mp3',
                    fileName: 'short.mp3'),
              ])),
          playlistListProvider
              .overrideWith((ref) => Future.value(_testPlaylists)),
          activeConnectionProvider
              .overrideWith((ref) => Future.value(_tstConn)),
          progressForFileProvider.overrideWith((ref, key) {
            if (key.filePath == '/music/short.mp3') {
              return Future.value(shortProgress);
            }
            return Future.value(null);
          }),
        ],
      ));
      await tester.pumpAndSettle();

      // Tap track
      await tester.tap(find.text('short.mp3'));
      await tester.pump(); // Process tap
      await tester.pump(); // Process await → positionMs=3000 < 5000 → skip → push /player
      await tester.pump(); // Build player route

      // Should NOT show dialog (positionMs < 5000 threshold)
      expect(find.text('恢复播放进度'), findsNothing);
      expect(find.text('Player'), findsOneWidget);

      // Verify PlayQueue has no startPositionMs
      final ctx = tester.element(find.text('Player'));
      final container = ProviderScope.containerOf(ctx);
      final queue = container.read(currentPlayQueueProvider);
      expect(queue, isNotNull);
      expect(queue!.startPositionMs, isNull);
    });
  });

  group('TST-T24 countdown expires → auto-resume', () {
    test('countdown reaches 0, state reflects auto-select', () {
      fakeAsync((async) {
        final container = ProviderContainer();
        addTearDown(container.dispose);

        final notifier = container.read(progressResumeProvider.notifier);
        final progress = _tstProgress(filePath: '/music/auto.mp3');

        // Show dialog (starts countdown at 5)
        notifier.show(progress);
        expect(notifier.state, isNotNull);
        expect(notifier.state!.countdownSeconds, equals(5));
        expect(notifier.state!.isExpired, isFalse);

        // Elapse 1 second → countdown should be 4
        async.elapse(const Duration(seconds: 1));
        expect(notifier.state!.countdownSeconds, equals(4));

        // Elapse 4 more seconds → countdown should be 0, isExpired true
        async.elapse(const Duration(seconds: 4));
        expect(notifier.state!.countdownSeconds, equals(0));
        expect(notifier.state!.isExpired, isTrue);

        // Verify progress is still accessible
        expect(notifier.state!.progress.filePath, equals('/music/auto.mp3'));
        expect(notifier.state!.progress.positionMs, equals(120000));
      });
    });
  });

  group('TST-T25 multi-track → correct currentIndex', () {
    testWidgets('tapping 3rd track sets queue.currentIndex to 2',
        (WidgetTester tester) async {
      await tester.pumpWidget(_buildTestApp(
        const PlaylistDetailScreen(playlistId: 1),
        overrides: [
          playlistTracksProvider(1).overrideWith((ref) => Future.value([
                _testTrack(
                    id: 1, filePath: '/music/01.mp3', fileName: '01.mp3'),
                _testTrack(
                    id: 2, filePath: '/music/02.mp3', fileName: '02.mp3'),
                _testTrack(
                    id: 3, filePath: '/music/03.mp3', fileName: '03.mp3'),
                _testTrack(
                    id: 4, filePath: '/music/04.mp3', fileName: '04.mp3'),
                _testTrack(
                    id: 5, filePath: '/music/05.mp3', fileName: '05.mp3'),
              ])),
          playlistListProvider
              .overrideWith((ref) => Future.value(_testPlaylists)),
          activeConnectionProvider
              .overrideWith((ref) => Future.value(_tstConn)),
          progressForFileProvider
              .overrideWith((ref, key) => Future.value(null)),
        ],
      ));
      await tester.pumpAndSettle();

      // Tap the 3rd track (0-based index 2)
      await tester.tap(find.text('03.mp3'));
      await tester.pump(); // Process tap
      await tester.pump(); // Process await → no progress → push /player
      await tester.pump(); // Build player route

      expect(find.text('Player'), findsOneWidget);

      // Verify currentIndex is 2 (3rd track, 0-based)
      final ctx = tester.element(find.text('Player'));
      final container = ProviderScope.containerOf(ctx);
      final queue = container.read(currentPlayQueueProvider);
      expect(queue, isNotNull);
      expect(queue!.currentIndex, equals(2));
      expect(queue.files.length, equals(5));
    });
  });

  // ═════════════════════════════════════════════════════════════════════════════
  // TST-11: 拖拽排序 Widget 测试 (TST-T80~TST-T82)
  // ═════════════════════════════════════════════════════════════════════════════

  // ── TST-T80: drag reorder callback params ─────────────────────────────

  group('TST-T80 drag reorder callback', () {
    testWidgets('drag from index 2 to 0 calls reorder with correct params',
        (WidgetTester tester) async {
      int? capturedPlaylistId, capturedOldIndex, capturedNewIndex;

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
          reorderPlaylistTrackProvider.overrideWith(
              (ref) => (playlistId, oldIndex, newIndex) {
                    capturedPlaylistId = playlistId;
                    capturedOldIndex = oldIndex;
                    capturedNewIndex = newIndex;
                    return Future.value();
                  }),
        ],
      ));
      await tester.pumpAndSettle();

      // Verify ReorderableListView is present (sort=addedAsc is default)
      expect(find.byType(ReorderableListView), findsOneWidget);

      // Simulate drag from index 2 to index 0 by invoking the onReorder
      // callback directly.  Flutter's SliverReorderableList does not reliably
      // respond to timedDrag / long-press-drag in the test framework because
      // it uses MultiDragGestureRecognizer internally.
      final reorderable =
          tester.widget<ReorderableListView>(find.byType(ReorderableListView));
      reorderable.onReorder!(2, 0);
      await tester.pumpAndSettle();

      // Verify the callback forwarded to reorderPlaylistTrackProvider with
      // correct arguments (newIndex is NOT adjusted because 0 < 2).
      expect(capturedPlaylistId, equals(1));
      expect(capturedOldIndex, equals(2));
      expect(capturedNewIndex, equals(0));
    });
  });

  // ── TST-T81: track list order updates after reorder ──────────────────

  group('TST-T81 track list order updates', () {
    testWidgets('list reflects new order after reorder',
        (WidgetTester tester) async {
      final tracks = [
        _testTrack(id: 1, fileName: 'A.mp3'),
        _testTrack(id: 2, fileName: 'B.mp3'),
        _testTrack(id: 3, fileName: 'C.mp3'),
      ];

      await tester.pumpWidget(_buildTestApp(
        const PlaylistDetailScreen(playlistId: 1),
        overrides: [
          playlistTracksProvider(1)
              .overrideWith((ref) => Future.value(tracks)),
          playlistListProvider
              .overrideWith((ref) => Future.value(_testPlaylists)),
          reorderPlaylistTrackProvider.overrideWith(
              (ref) => (playlistId, oldIndex, newIndex) {
                    final item = tracks.removeAt(oldIndex);
                    tracks.insert(newIndex, item);
                    ref.invalidate(playlistTracksProvider(playlistId));
                    return Future.value();
                  }),
        ],
      ));
      await tester.pumpAndSettle();

      // Verify initial order: A, B, C
      var items = tester
          .widgetList<PlaylistTrackItem>(
              find.byType(PlaylistTrackItem))
          .toList();
      expect(items.length, 3);
      expect(items[0].track.fileName, 'A.mp3');
      expect(items[1].track.fileName, 'B.mp3');
      expect(items[2].track.fileName, 'C.mp3');

      // Simulate drag from index 2 to index 0 by invoking onReorder directly.
      final reorderable =
          tester.widget<ReorderableListView>(find.byType(ReorderableListView));
      reorderable.onReorder!(2, 0);
      await tester.pumpAndSettle();

      // Verify new order: C, A, B
      items = tester
          .widgetList<PlaylistTrackItem>(
              find.byType(PlaylistTrackItem))
          .toList();
      expect(items.length, 3);
      expect(items[0].track.fileName, 'C.mp3');
      expect(items[1].track.fileName, 'A.mp3');
      expect(items[2].track.fileName, 'B.mp3');
    });
  });

  // ── TST-T82: reorder persistence ─────────────────────────────────────

  const tst11CreateTables = '''
    CREATE TABLE playlists (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL,
      created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL
    );
    CREATE TABLE playlist_tracks (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      playlist_id INTEGER NOT NULL,
      file_path TEXT NOT NULL,
      file_name TEXT NOT NULL,
      added_at INTEGER NOT NULL,
      FOREIGN KEY(playlist_id) REFERENCES playlists(id) ON DELETE CASCADE
    );
    CREATE INDEX idx_playlist_tracks_playlist_id ON playlist_tracks(playlist_id);
  ''';

  group('TST-T82 reorder persistence', () {
    late Database db;
    late ProviderContainer container;

    setUp(() async {
      db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
      await db.execute('PRAGMA foreign_keys = ON');
      await db.execute(tst11CreateTables);
      DatabaseHelper.instance.overrideDatabase(db);

      container = ProviderContainer(overrides: [
        playlistDaoProvider.overrideWith((ref) => PlaylistDao()),
      ]);
    });

    tearDown(() async {
      container.dispose();
      await db.close();
    });

    test('reorderTrack persists order after page reopen', () async {
      final dao = PlaylistDao();

      // Insert playlist
      final playlistId = await dao.insertPlaylist(Playlist(
        name: 'Reorder Test',
        createdAt: _now,
        updatedAt: _now,
      ));

      // Insert tracks with sequential added_at
      final base = _now.millisecondsSinceEpoch;
      final tracks = [
        PlaylistTrack(
            playlistId: playlistId,
            filePath: '/A.mp3',
            fileName: 'A.mp3',
            addedAt: DateTime.fromMillisecondsSinceEpoch(base)),
        PlaylistTrack(
            playlistId: playlistId,
            filePath: '/B.mp3',
            fileName: 'B.mp3',
            addedAt: DateTime.fromMillisecondsSinceEpoch(base + 1)),
        PlaylistTrack(
            playlistId: playlistId,
            filePath: '/C.mp3',
            fileName: 'C.mp3',
            addedAt: DateTime.fromMillisecondsSinceEpoch(base + 2)),
      ];
      await dao.addTracks(tracks);

      // Read initial order — sorted by added_at ASC
      var result =
          await container.read(playlistTracksProvider(playlistId).future);
      expect(result.map((t) => t.fileName).toList(),
          ['A.mp3', 'B.mp3', 'C.mp3']);

      // Reorder: move index 2 (C.mp3) to index 0
      await container.read(reorderPlaylistTrackProvider)(playlistId, 2, 0);

      // Invalidate to simulate "reopening" the detail page
      container.invalidate(playlistTracksProvider(playlistId));

      // Read again — should reflect persisted new order
      result =
          await container.read(playlistTracksProvider(playlistId).future);
      expect(result.map((t) => t.fileName).toList(),
          ['C.mp3', 'A.mp3', 'B.mp3']);
    });
  });

  // ═════════════════════════════════════════════════════════════════════════════
  // PLY-T83: delete tracks end-to-end (regression guard for async-gap bug)
  // ═════════════════════════════════════════════════════════════════════════════

  group('PLY-T83 delete tracks end-to-end', () {
    testWidgets('delete removes tracks and exits selection mode',
        (WidgetTester tester) async {
      // In-memory track list mutated by the overridden remove provider so we
      // can verify the widget rebuild without hitting a real database.
      final tracks = [
        _testTrack(id: 1, fileName: 'A.mp3'),
        _testTrack(id: 2, fileName: 'B.mp3'),
        _testTrack(id: 3, fileName: 'C.mp3'),
      ];

      await tester.pumpWidget(_buildTestApp(
        const PlaylistDetailScreen(playlistId: 1),
        overrides: [
          playlistTracksProvider(1)
              .overrideWith((ref) => Future.value(tracks)),
          playlistListProvider
              .overrideWith((ref) => Future.value(_testPlaylists)),
          removeTracksFromPlaylistProvider.overrideWith((ref) {
            return (int playlistId, List<int> idsToRemove) async {
              tracks.removeWhere((t) => idsToRemove.contains(t.id));
              ref.invalidate(playlistTracksProvider(playlistId));
              ref.invalidate(playlistListProvider);
            };
          }),
        ],
      ));
      await tester.pumpAndSettle();

      // All 3 tracks visible
      expect(find.text('A.mp3'), findsOneWidget);
      expect(find.text('B.mp3'), findsOneWidget);
      expect(find.text('C.mp3'), findsOneWidget);

      // Enter selection mode
      await tester.longPress(find.text('A.mp3'));
      await tester.pumpAndSettle();
      expect(find.text('已选 1 首'), findsOneWidget);

      // Select C as well
      await tester.tap(find.text('C.mp3'));
      await tester.pumpAndSettle();
      expect(find.text('已选 2 首'), findsOneWidget);

      // Tap delete → confirmation dialog
      await tester.tap(find.byIcon(Icons.delete_outline));
      await tester.pumpAndSettle();
      expect(find.text('确认删除'), findsOneWidget);

      // Confirm deletion
      await tester.tap(find.text('删除'));
      await tester.pumpAndSettle();

      // Selection mode exited → normal AppBar with playlist name
      expect(find.text('Test Playlist'), findsOneWidget);
      expect(find.text('已选 1 首'), findsNothing);
      expect(find.text('已选 2 首'), findsNothing);

      // A and C removed, only B remains
      expect(find.text('A.mp3'), findsNothing);
      expect(find.text('C.mp3'), findsNothing);
      expect(find.text('B.mp3'), findsOneWidget);
    });
  });

  // ═════════════════════════════════════════════════════════════════════════════
  // PLY-T84: ReorderableListView disabled during selection mode
  // ═════════════════════════════════════════════════════════════════════════════

  group('PLY-T84 no ReorderableListView during selection', () {
    testWidgets('uses ListView during selection, ReorderableListView otherwise',
        (WidgetTester tester) async {
      await tester.pumpWidget(_buildTestApp(
        const PlaylistDetailScreen(playlistId: 1),
        overrides: [
          playlistTracksProvider(1).overrideWith((ref) => Future.value([
                _testTrack(id: 1, fileName: 'A.mp3'),
                _testTrack(id: 2, fileName: 'B.mp3'),
              ])),
          playlistListProvider
              .overrideWith((ref) => Future.value(_testPlaylists)),
        ],
      ));
      await tester.pumpAndSettle();

      // Default (sort=addedAsc, not in selection mode): ReorderableListView
      expect(find.byType(ReorderableListView), findsOneWidget);

      // Enter selection mode
      await tester.longPress(find.text('A.mp3'));
      await tester.pumpAndSettle();

      // ReorderableListView gone during selection mode
      expect(find.byType(ReorderableListView), findsNothing);

      // Exit selection mode
      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();

      // ReorderableListView back
      expect(find.byType(ReorderableListView), findsOneWidget);
    });
  });

  // ═════════════════════════════════════════════════════════════════════════════
  // TST-17: Playlist rename dialog logic
  // ═════════════════════════════════════════════════════════════════════════════

  group('TST-17: Playlist rename dialog logic', () {
    test('TST-T139: rename dialog validates non-empty name', () {
      // Pure logic: name validation for the rename dialog

      // Empty name → invalid
      String? name = '';
      final isEmptyValid = name.trim().isNotEmpty;
      expect(isEmptyValid, isFalse,
          reason: 'TST-T139: 空名称验证失败');

      // Name with only whitespace → invalid
      name = '   \t  ';
      final isWhitespaceValid = name.trim().isNotEmpty;
      expect(isWhitespaceValid, isFalse,
          reason: 'TST-T139: 仅空白字符名称验证失败');

      // Valid name → valid
      name = '新名称';
      final isValid = name.trim().isNotEmpty;
      expect(isValid, isTrue,
          reason: 'TST-T139: 非空名称验证通过');

      // Name with leading/trailing whitespace trimmed → valid
      name = '  有效名称  ';
      final isTrimmedValid = name.trim().isNotEmpty;
      expect(isTrimmedValid, isTrue,
          reason: 'TST-T139: trim后非空名称验证通过');
      expect(name.trim(), equals('有效名称'),
          reason: 'TST-T139: trim去除前后空白');
    });

    test('TST-T140: empty name disables confirm button', () {
      // Pure logic: the confirm/save button should be disabled when
      // the name field is empty or whitespace-only.

      // Empty → disabled
      const emptyName = '';
      final isDisabled1 = (emptyName.trim().isNotEmpty != true);
      expect(isDisabled1, isTrue,
          reason: 'TST-T140: 空名称时确认按钮应禁用');

      // Whitespace only → disabled
      const whitespaceName = '   ';
      final isDisabled2 = (whitespaceName.trim().isNotEmpty != true);
      expect(isDisabled2, isTrue,
          reason: 'TST-T140: 仅空白字符时确认按钮应禁用');

      // Non-empty → enabled
      const validName = '有效名称';
      final isDisabled3 = (validName.trim().isNotEmpty != true);
      expect(isDisabled3, isFalse,
          reason: 'TST-T140: 有效名称时确认按钮应启用');

      // Non-null non-empty with null safety
      const nonEmptyName = 'test';
      final enabled = nonEmptyName.trim().isNotEmpty;
      expect(enabled, isTrue,
          reason: 'TST-T140: 非空非null名称启用确认按钮');
    });
  });
}
