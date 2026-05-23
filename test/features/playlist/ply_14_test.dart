// test/features/playlist/ply_14_test.dart
// TST-11: AddTracksBrowser bottom sheet — automated test suite
//
// Widget tests (TST-T83~TST-T90): bottom sheet appearance, file selection,
// select all/deselect, dedup, navigation isolation, cancel.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:nas_audio_player/core/database/dao/playlist_dao.dart';
import 'package:nas_audio_player/core/database/database_helper.dart';
import 'package:nas_audio_player/features/browser/browser_provider.dart';
import 'package:nas_audio_player/features/playlist/playlist_detail_screen.dart';
import 'package:nas_audio_player/features/playlist/playlist_provider.dart';
import 'package:nas_audio_player/shared/models/nas_file.dart';
import 'package:nas_audio_player/shared/models/playlist.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

// ── Helpers ───────────────────────────────────────────────────────────────────

final _now = DateTime.now();

final _testPlaylist = Playlist(
  id: 1,
  name: 'Test Playlist',
  trackCount: 0,
  createdAt: _now,
  updatedAt: _now,
);

final _testPlaylists = [_testPlaylist];

NasFile _testNasFile({
  String name = 'song.mp3',
  String path = '/song.mp3',
  bool isDirectory = false,
}) {
  return NasFile(
    name: name,
    path: path,
    isDirectory: isDirectory,
    audioType: isDirectory ? null : AudioFileType.music,
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
    ],
  );
  return ProviderScope(
    overrides: overrides ?? [],
    child: MaterialApp.router(
      routerConfig: router,
    ),
  );
}

/// Counts how many Checkbox widgets have value == true.
int _checkedCount(WidgetTester tester) {
  return tester
      .widgetList<Checkbox>(find.byType(Checkbox))
      .where((cb) => cb.value == true)
      .length;
}

/// Pumps enough frames for bottom-sheet animations to settle.
Future<void> _pumpSheet(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
}

/// Opens the add-tracks bottom sheet by tapping the + button.
Future<void> _openSheet(WidgetTester tester) async {
  await tester.tap(find.byIcon(Icons.add));
  await _pumpSheet(tester);
}

/// Helper: find navigator and pop top route (used to dismiss bottom sheets).
Future<void> _dismissModal(WidgetTester tester) async {
  final navigator = tester.state<NavigatorState>(find.byType(Navigator));
  navigator.pop();
  await _pumpSheet(tester);
}

// ═════════════════════════════════════════════════════════════════════════════
// Widget tests — TST-T83~TST-T90
// ═════════════════════════════════════════════════════════════════════════════

void main() {
  setUpAll(() {
    sqfliteFfiInit();
  });

  // ── TST-T83: bottom sheet appears with directory file list ────────────

  group('TST-T83 AddTracksBrowser appearance', () {
    testWidgets('bottom sheet shows directory file list',
        (WidgetTester tester) async {
      final testFiles = [
        _testNasFile(name: 'subdir', path: '/subdir', isDirectory: true),
        _testNasFile(name: 'song1.mp3', path: '/song1.mp3'),
        _testNasFile(name: 'song2.flac', path: '/song2.flac'),
      ];

      await tester.pumpWidget(_buildTestApp(
        const PlaylistDetailScreen(playlistId: 1),
        overrides: [
          playlistTracksProvider(1)
              .overrideWith((ref) => Future.value(<PlaylistTrack>[])),
          playlistListProvider
              .overrideWith((ref) => Future.value(_testPlaylists)),
          directoryContentsProvider
              .overrideWith((ref, path) => Future.value(testFiles)),
        ],
      ));
      await _pumpSheet(tester);

      // Open bottom sheet
      await _openSheet(tester);

      // Verify bottom sheet elements
      expect(find.text('添加曲目'), findsOneWidget);
      expect(find.text('song1.mp3'), findsOneWidget);
      expect(find.text('song2.flac'), findsOneWidget);
      // Directory should appear with folder icon
      expect(find.text('subdir'), findsOneWidget);
      expect(find.byIcon(Icons.folder), findsOneWidget);

      // Verify breadcrumb shows root
      expect(find.text('根目录'), findsOneWidget);

      // Verify select all / confirm button area
      expect(find.text('全选'), findsOneWidget);
      expect(find.text('确认 (0)'), findsOneWidget);
    });
  });

  // ── TST-T84: select files and confirm → addTracks called ──────────────

  group('TST-T84 select files and confirm', () {
    testWidgets('selecting 3 files and confirming calls addTracks',
        (WidgetTester tester) async {
      final testFiles = [
        _testNasFile(name: 'A.mp3', path: '/A.mp3'),
        _testNasFile(name: 'B.mp3', path: '/B.mp3'),
        _testNasFile(name: 'C.mp3', path: '/C.mp3'),
        _testNasFile(name: 'D.mp3', path: '/D.mp3'),
      ];

      int? capturedPlaylistId;
      List<NasFile>? capturedFiles;

      await tester.pumpWidget(_buildTestApp(
        const PlaylistDetailScreen(playlistId: 1),
        overrides: [
          playlistTracksProvider(1)
              .overrideWith((ref) => Future.value(<PlaylistTrack>[])),
          playlistListProvider
              .overrideWith((ref) => Future.value(_testPlaylists)),
          directoryContentsProvider
              .overrideWith((ref, path) => Future.value(testFiles)),
          addTracksToPlaylistProvider
              .overrideWith((ref) => (playlistId, files) {
                    capturedPlaylistId = playlistId;
                    capturedFiles = files;
                    return Future.value();
                  }),
        ],
      ));
      await _pumpSheet(tester);

      // Open bottom sheet
      await _openSheet(tester);

      // Tap checkboxes for first 3 files (all 4 are audio files)
      final checkboxes = find.byType(Checkbox);
      expect(checkboxes, findsNWidgets(4)); // 4 audio file checkboxes

      await tester.tap(checkboxes.at(0)); // A.mp3
      await _pumpSheet(tester);
      await tester.tap(checkboxes.at(1)); // B.mp3
      await _pumpSheet(tester);
      await tester.tap(checkboxes.at(2)); // C.mp3
      await _pumpSheet(tester);

      // Verify 3 checkboxes are checked
      expect(_checkedCount(tester), equals(3));

      // Verify confirm button shows count
      expect(find.text('确认 (3)'), findsOneWidget);

      // Tap confirm button
      await tester.tap(find.text('确认 (3)'));
      await _pumpSheet(tester);

      // Verify addTracksToPlaylistProvider was called with correct params
      expect(capturedPlaylistId, equals(1));
      expect(capturedFiles, isNotNull);
      expect(capturedFiles!.length, equals(3));
      expect(
        capturedFiles!.map((f) => f.name).toList(),
        ['A.mp3', 'B.mp3', 'C.mp3'],
      );
    });
  });

  // ── TST-T85: select all button ────────────────────────────────────────

  group('TST-T85 select all', () {
    testWidgets('select all button selects all audio files',
        (WidgetTester tester) async {
      final testFiles = [
        _testNasFile(name: 'subdir', path: '/subdir', isDirectory: true),
        _testNasFile(name: 'track1.mp3', path: '/track1.mp3'),
        _testNasFile(name: 'track2.mp3', path: '/track2.mp3'),
        _testNasFile(name: 'track3.mp3', path: '/track3.mp3'),
      ];

      await tester.pumpWidget(_buildTestApp(
        const PlaylistDetailScreen(playlistId: 1),
        overrides: [
          playlistTracksProvider(1)
              .overrideWith((ref) => Future.value(<PlaylistTrack>[])),
          playlistListProvider
              .overrideWith((ref) => Future.value(_testPlaylists)),
          directoryContentsProvider
              .overrideWith((ref, path) => Future.value(testFiles)),
        ],
      ));
      await _pumpSheet(tester);

      // Open bottom sheet
      await _openSheet(tester);

      // Tap "全选" button
      await tester.tap(find.text('全选'));
      await _pumpSheet(tester);

      // All 3 audio files should now be selected (confirmed via confirm count)
      expect(find.text('确认 (3)'), findsOneWidget);
      // Select-all label should change to "取消全选"
      expect(find.text('取消全选'), findsOneWidget);

      // Verify 3 checkboxes are checked
      expect(_checkedCount(tester), equals(3));
    });
  });

  // ── TST-T86: deselect all ─────────────────────────────────────────────

  group('TST-T86 deselect all', () {
    testWidgets('deselect all clears all selections',
        (WidgetTester tester) async {
      final testFiles = [
        _testNasFile(name: 'track1.mp3', path: '/track1.mp3'),
        _testNasFile(name: 'track2.mp3', path: '/track2.mp3'),
      ];

      await tester.pumpWidget(_buildTestApp(
        const PlaylistDetailScreen(playlistId: 1),
        overrides: [
          playlistTracksProvider(1)
              .overrideWith((ref) => Future.value(<PlaylistTrack>[])),
          playlistListProvider
              .overrideWith((ref) => Future.value(_testPlaylists)),
          directoryContentsProvider
              .overrideWith((ref, path) => Future.value(testFiles)),
        ],
      ));
      await _pumpSheet(tester);

      // Open bottom sheet
      await _openSheet(tester);

      // Select all
      await tester.tap(find.text('全选'));
      await _pumpSheet(tester);
      expect(find.text('确认 (2)'), findsOneWidget);
      expect(_checkedCount(tester), equals(2));

      // Tap "取消全选"
      await tester.tap(find.text('取消全选'));
      await _pumpSheet(tester);

      // All selections cleared
      expect(find.text('确认 (0)'), findsOneWidget);
      expect(find.text('全选'), findsOneWidget);
      expect(_checkedCount(tester), equals(0));
    });
  });

  // ── TST-T87: existing tracks dedup ────────────────────────────────────

  const tst87CreateTables = '''
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

  group('TST-T87 existing tracks dedup', () {
    late Database db;
    late ProviderContainer container;

    setUp(() async {
      db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
      await db.execute('PRAGMA foreign_keys = ON');
      await db.execute(tst87CreateTables);
      DatabaseHelper.instance.overrideDatabase(db);

      container = ProviderContainer(overrides: [
        playlistDaoProvider.overrideWith((ref) => PlaylistDao()),
      ]);
    });

    tearDown(() async {
      container.dispose();
      await db.close();
    });

    test('addTracksToPlaylistProvider skips existing tracks', () async {
      final dao = PlaylistDao();

      // Create playlist
      final playlistId = await dao.insertPlaylist(Playlist(
        name: 'Dedup Test',
        createdAt: _now,
        updatedAt: _now,
      ));

      // Pre-add tracks A and B
      await dao.addTracks([
        PlaylistTrack(
          playlistId: playlistId,
          filePath: '/existing/A.mp3',
          fileName: 'A.mp3',
          addedAt: _now,
        ),
        PlaylistTrack(
          playlistId: playlistId,
          filePath: '/existing/B.mp3',
          fileName: 'B.mp3',
          addedAt: _now,
        ),
      ]);

      // Now try to add tracks A (existing), C (new), B (existing), D (new)
      final addTracks = container.read(addTracksToPlaylistProvider);
      await addTracks(playlistId, [
        const NasFile(name: 'A.mp3', path: '/existing/A.mp3', isDirectory: false),
        const NasFile(name: 'C.mp3', path: '/new/C.mp3', isDirectory: false),
        const NasFile(name: 'B.mp3', path: '/existing/B.mp3', isDirectory: false),
        const NasFile(name: 'D.mp3', path: '/new/D.mp3', isDirectory: false),
      ]);

      // Read final track list
      final tracks =
          await container.read(playlistTracksProvider(playlistId).future);

      // Should have 4 tracks total (2 original + 2 new, no duplicates)
      expect(tracks.length, equals(4));
      final fileNames = tracks.map((t) => t.fileName).toSet();
      expect(fileNames, contains('A.mp3'));
      expect(fileNames, contains('B.mp3'));
      expect(fileNames, contains('C.mp3'));
      expect(fileNames, contains('D.mp3'));
    });
  });

  // ── TST-T88: bottom sheet navigation isolated from main browser ───────

  group('TST-T88 navigation isolation', () {
    testWidgets('bottom sheet directory nav does not affect outer nav stack',
        (WidgetTester tester) async {
      final rootFiles = [
        _testNasFile(name: 'music', path: '/music', isDirectory: true),
        _testNasFile(name: 'root_song.mp3', path: '/root_song.mp3'),
      ];

      final musicFiles = [
        _testNasFile(name: 'nested.mp3', path: '/music/nested.mp3'),
      ];

      await tester.pumpWidget(_buildTestApp(
        const PlaylistDetailScreen(playlistId: 1),
        overrides: [
          playlistTracksProvider(1)
              .overrideWith((ref) => Future.value(<PlaylistTrack>[])),
          playlistListProvider
              .overrideWith((ref) => Future.value(_testPlaylists)),
          directoryContentsProvider
              .overrideWith((ref, path) {
            if (path == '/') return Future.value(rootFiles);
            if (path == '/music') return Future.value(musicFiles);
            return Future.value(<NasFile>[]);
          }),
        ],
      ));
      await _pumpSheet(tester);

      // Get outer container and push a path to outer navigation stack
      final outerContainer = ProviderScope.containerOf(
        tester.element(find.byType(PlaylistDetailScreen)),
      );
      final outerNav = outerContainer.read(navigationStackProvider.notifier);
      outerNav.push('/outer-browser-path');
      expect(outerContainer.read(navigationStackProvider).last,
          '/outer-browser-path');

      // Open bottom sheet
      await _openSheet(tester);

      // In bottom sheet: breadcrumb should show root (independent of outer stack)
      expect(find.text('根目录'), findsOneWidget);

      // Navigate into /music directory within bottom sheet
      await tester.tap(find.text('music'));
      await _pumpSheet(tester);

      // Should now show nested contents
      expect(find.text('nested.mp3'), findsOneWidget);

      // Close bottom sheet by popping the modal route
      await _dismissModal(tester);

      // Outer navigation stack should be unchanged
      expect(outerContainer.read(navigationStackProvider).last,
          '/outer-browser-path');
    });
  });

  // ── TST-T89: close bottom sheet preserves browser state ───────────────

  group('TST-T89 close preserves browser state', () {
    testWidgets('closing bottom sheet does not change browser providers',
        (WidgetTester tester) async {
      final testFiles = [
        _testNasFile(name: 'track.mp3', path: '/track.mp3'),
      ];

      await tester.pumpWidget(_buildTestApp(
        const PlaylistDetailScreen(playlistId: 1),
        overrides: [
          playlistTracksProvider(1)
              .overrideWith((ref) => Future.value(<PlaylistTrack>[])),
          playlistListProvider
              .overrideWith((ref) => Future.value(_testPlaylists)),
          directoryContentsProvider
              .overrideWith((ref, path) => Future.value(testFiles)),
        ],
      ));
      await _pumpSheet(tester);

      // Get outer container and set known browser state
      final outerContainer = ProviderScope.containerOf(
        tester.element(find.byType(PlaylistDetailScreen)),
      );
      final outerNav = outerContainer.read(navigationStackProvider.notifier);
      outerNav.push('/browser-state');
      final initialStack = List<String>.from(
          outerContainer.read(navigationStackProvider));

      // Open bottom sheet
      await _openSheet(tester);

      // Select a file via checkbox tap
      final checkboxes = find.byType(Checkbox);
      await tester.tap(checkboxes.at(0)); // track.mp3
      await _pumpSheet(tester);
      expect(_checkedCount(tester), equals(1));

      // Dismiss the bottom sheet
      await _dismissModal(tester);

      // Verify outer browser navigation stack unchanged
      final finalStack =
          List<String>.from(outerContainer.read(navigationStackProvider));
      expect(finalStack, equals(initialStack));

      // Verify playlist tracks provider still accessible
      final tracks =
          await outerContainer.read(playlistTracksProvider(1).future);
      expect(tracks, isEmpty);
    });
  });

  // ── TST-T90: cancel bottom sheet → no tracks added ────────────────────

  group('TST-T90 cancel does not add tracks', () {
    testWidgets('dismissing bottom sheet without confirm does not add tracks',
        (WidgetTester tester) async {
      final testFiles = [
        _testNasFile(name: 'track1.mp3', path: '/track1.mp3'),
        _testNasFile(name: 'track2.mp3', path: '/track2.mp3'),
      ];

      bool addTracksCalled = false;

      await tester.pumpWidget(_buildTestApp(
        const PlaylistDetailScreen(playlistId: 1),
        overrides: [
          playlistTracksProvider(1)
              .overrideWith((ref) => Future.value(<PlaylistTrack>[])),
          playlistListProvider
              .overrideWith((ref) => Future.value(_testPlaylists)),
          directoryContentsProvider
              .overrideWith((ref, path) => Future.value(testFiles)),
          addTracksToPlaylistProvider.overrideWith((ref) => (_, __) {
                addTracksCalled = true;
                return Future.value();
              }),
        ],
      ));
      await _pumpSheet(tester);

      // Open bottom sheet
      await _openSheet(tester);

      // Select a file via checkbox tap
      final checkboxes = find.byType(Checkbox);
      await tester.tap(checkboxes.at(0)); // track1.mp3
      await _pumpSheet(tester);
      expect(_checkedCount(tester), equals(1));

      // Dismiss without confirming (cancel)
      await _dismissModal(tester);

      // Verify addTracksToPlaylistProvider was NOT called
      expect(addTracksCalled, isFalse);
    });
  });
}
