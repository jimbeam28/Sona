// test/features/playlist/bug_08_test.dart
// BUG-08: track.id! 空指针闪退 — PlaylistTrack.id == null 不闪退
//
// Widget tests:
//   BUG-08-T03: PlaylistTrack.id == null → 选择/长按操作被忽略，不闪退
//   BUG-08-T04: PlaylistTrack.id != null → 正常操作（回归）

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
    id: id,
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
// Widget tests
// ═════════════════════════════════════════════════════════════════════════════

void main() {
  // ── BUG-08-T03: PlaylistTrack.id == null → 不闪退 → 忽略操作 ─────────

  group('BUG-08-T03 track.id == null does not crash', () {
    testWidgets('tap in selection mode with null track id does not crash',
        (WidgetTester tester) async {
      // First track has valid id (to enter selection mode), second has null id
      final validTrack = _testTrack(id: 1, fileName: 'valid.mp3');
      final nullIdTrack = _testTrack(id: null, fileName: 'null_id.mp3');

      await tester.pumpWidget(_buildTestApp(
        const PlaylistDetailScreen(playlistId: 1),
        overrides: [
          playlistTracksProvider(1).overrideWith(
              (ref) => Future.value([validTrack, nullIdTrack])),
          playlistListProvider.overrideWith(
              (ref) => Future.value([_testPlaylist])),
        ],
      ));
      await tester.pumpAndSettle();

      // Both tracks rendered
      expect(find.text('valid.mp3'), findsOneWidget);
      expect(find.text('null_id.mp3'), findsOneWidget);

      // Long press valid track to enter selection mode
      await tester.longPress(find.text('valid.mp3'));
      await tester.pumpAndSettle();
      expect(find.text('已选 1 首'), findsOneWidget);

      // Now tap the null-id track in selection mode — should not crash
      await tester.tap(find.text('null_id.mp3'));
      await tester.pumpAndSettle();

      // Selection count should remain 1 (null id track ignored)
      expect(find.text('已选 1 首'), findsOneWidget);
    });

    testWidgets('long press with null track id does not enter selection mode',
        (WidgetTester tester) async {
      final nullIdTrack = _testTrack(id: null, fileName: 'null_id.mp3');

      await tester.pumpWidget(_buildTestApp(
        const PlaylistDetailScreen(playlistId: 1),
        overrides: [
          playlistTracksProvider(1)
              .overrideWith((ref) => Future.value([nullIdTrack])),
          playlistListProvider.overrideWith(
              (ref) => Future.value([_testPlaylist])),
        ],
      ));
      await tester.pumpAndSettle();

      expect(find.text('null_id.mp3'), findsOneWidget);

      // Long press the null-id track — should NOT enter selection mode
      await tester.longPress(find.text('null_id.mp3'));
      await tester.pumpAndSettle();

      // Should NOT show "已选 1 首" because the null id guard prevents it
      expect(find.text('已选 1 首'), findsNothing);
      // Normal AppBar should still be showing
      expect(find.text('Test Playlist'), findsOneWidget);
    });
  });

  // ── BUG-08-T04: PlaylistTrack.id != null → 正常操作（回归） ──────────

  group('BUG-08-T04 track.id != null works normally (regression)', () {
    testWidgets('tap in selection mode with valid track id selects it',
        (WidgetTester tester) async {
      final track1 = _testTrack(id: 1, fileName: 'track1.mp3');
      final track2 = _testTrack(id: 2, fileName: 'track2.mp3');

      await tester.pumpWidget(_buildTestApp(
        const PlaylistDetailScreen(playlistId: 1),
        overrides: [
          playlistTracksProvider(1)
              .overrideWith((ref) => Future.value([track1, track2])),
          playlistListProvider.overrideWith(
              (ref) => Future.value([_testPlaylist])),
        ],
      ));
      await tester.pumpAndSettle();

      // Long press first track to enter selection mode
      await tester.longPress(find.text('track1.mp3'));
      await tester.pumpAndSettle();
      expect(find.text('已选 1 首'), findsOneWidget);

      // Tap second track to add to selection
      await tester.tap(find.text('track2.mp3'));
      await tester.pumpAndSettle();

      // Both should be selected
      expect(find.text('已选 2 首'), findsOneWidget);
    });

    testWidgets('long press with valid track id enters selection mode',
        (WidgetTester tester) async {
      final track = _testTrack(id: 1, fileName: 'track.mp3');

      await tester.pumpWidget(_buildTestApp(
        const PlaylistDetailScreen(playlistId: 1),
        overrides: [
          playlistTracksProvider(1)
              .overrideWith((ref) => Future.value([track])),
          playlistListProvider.overrideWith(
              (ref) => Future.value([_testPlaylist])),
        ],
      ));
      await tester.pumpAndSettle();

      // Long press to enter selection mode
      await tester.longPress(find.text('track.mp3'));
      await tester.pumpAndSettle();

      // Should enter selection mode
      expect(find.text('已选 1 首'), findsOneWidget);
      expect(find.byIcon(Icons.check_circle), findsOneWidget);
    });
  });
}
