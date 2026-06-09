// test/features/playlist/bug_02_test.dart
// BUG-02: 播放单"取消全选"不退出选择模式
//
// "取消全选"按钮只调用 setState(() => _selectedIds.clear())，未调用
// _exitSelectionMode()，导致 selectionMode 仍为 true，AppBar 不恢复。
//
// 修复：将 onPressed 改为 _exitSelectionMode()。
//
// 测试用例:
//   BUG-02-T01: 长按进入选择 -> 全选 -> 取消全选 -> selectionMode 恢复为 false
//   BUG-02-T02: 取消全选后 AppBar 恢复为普通模式
//   BUG-02-T03: 取消全选后可正常点击曲目播放（回归）

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nas_audio_player/features/playlist/playlist_detail_screen.dart';
import 'package:nas_audio_player/features/playlist/playlist_provider.dart';
import 'package:nas_audio_player/shared/models/playlist.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../helpers/widget_helpers.dart';

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

// buildTestAppWithPlayerRoute() is imported from widget_helpers.dart.

List<PlaylistTrack> _threeTracks() => [
      _testTrack(id: 1, fileName: 'A.mp3', filePath: '/music/A.mp3'),
      _testTrack(id: 2, fileName: 'B.mp3', filePath: '/music/B.mp3'),
      _testTrack(id: 3, fileName: 'C.mp3', filePath: '/music/C.mp3'),
    ];

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  setUpAll(() {
    sqfliteFfiInit();
  });

  // BUG-02-T01: 长按进入选择 -> 全选 -> 取消全选 -> selectionMode 恢复为 false
  //
  // 验证方式：取消全选后 AppBar 不再显示 "已选 N 首"（即 selectionAppBar 已消失），
  // 且 select_all / deselect / delete_outline 图标不再出现。
  group('BUG-02-T01 deselect all exits selection mode', () {
    testWidgets(
        'long press -> select all -> deselect all -> no longer in selection mode',
        (WidgetTester tester) async {
      await tester.pumpWidget(buildTestAppWithPlayerRoute(
        const PlaylistDetailScreen(playlistId: 1),
        overrides: [
          playlistTracksProvider(1)
              .overrideWith((ref) => Future.value(_threeTracks())),
          playlistListProvider
              .overrideWith((ref) => Future.value([_testPlaylist])),
        ],
      ));
      await tester.pumpAndSettle();

      // Long press A to enter selection mode
      await tester.longPress(find.text('A.mp3'));
      await tester.pumpAndSettle();
      expect(find.text('已选 1 首'), findsOneWidget);

      // Select all
      await tester.tap(find.byIcon(Icons.select_all));
      await tester.pumpAndSettle();
      expect(find.text('已选 3 首'), findsOneWidget);

      // Deselect all (BUG-02 fix: should exit selection mode)
      await tester.tap(find.byIcon(Icons.deselect));
      await tester.pumpAndSettle();

      // selectionMode should be false — no "已选" text, no selection AppBar icons
      expect(find.text('已选 3 首'), findsNothing);
      expect(find.text('已选 0 首'), findsNothing);
      expect(find.byIcon(Icons.select_all), findsNothing);
      expect(find.byIcon(Icons.deselect), findsNothing);
      expect(find.byIcon(Icons.delete_outline), findsNothing);
    });
  });

  // BUG-02-T02: 取消全选后 AppBar 恢复为普通模式
  //
  // 验证方式：取消全选后 normalAppBar 出现（playlist 名称 + add + sort）。
  group('BUG-02-T02 AppBar restores to normal after deselect all', () {
    testWidgets(
        'deselect all shows normal AppBar with playlist name and actions',
        (WidgetTester tester) async {
      await tester.pumpWidget(buildTestAppWithPlayerRoute(
        const PlaylistDetailScreen(playlistId: 1),
        overrides: [
          playlistTracksProvider(1)
              .overrideWith((ref) => Future.value(_threeTracks())),
          playlistListProvider
              .overrideWith((ref) => Future.value([_testPlaylist])),
        ],
      ));
      await tester.pumpAndSettle();

      // Enter selection mode via long press
      await tester.longPress(find.text('A.mp3'));
      await tester.pumpAndSettle();
      expect(find.text('已选 1 首'), findsOneWidget);

      // Select all, then deselect all
      await tester.tap(find.byIcon(Icons.select_all));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.deselect));
      await tester.pumpAndSettle();

      // Normal AppBar should be restored
      expect(find.text('Test Playlist'), findsOneWidget);
      expect(find.byIcon(Icons.add), findsOneWidget);
      expect(find.byIcon(Icons.sort), findsOneWidget);
      expect(find.byIcon(Icons.edit_outlined), findsOneWidget);
    });
  });

  // BUG-02-T03: 取消全选后可正常点击曲目播放（回归）
  //
  // 验证方式：取消全选后点击曲目，应触发播放（导航到 /player）而非切换选择。
  group('BUG-02-T03 tapping track plays after deselect all', () {
    testWidgets('tapping track navigates to player after deselect all',
        (WidgetTester tester) async {
      await tester.pumpWidget(buildTestAppWithPlayerRoute(
        const PlaylistDetailScreen(playlistId: 1),
        overrides: [
          playlistTracksProvider(1)
              .overrideWith((ref) => Future.value(_threeTracks())),
          playlistListProvider
              .overrideWith((ref) => Future.value([_testPlaylist])),
        ],
      ));
      await tester.pumpAndSettle();

      // Enter selection mode
      await tester.longPress(find.text('A.mp3'));
      await tester.pumpAndSettle();

      // Select all, then deselect all
      await tester.tap(find.byIcon(Icons.select_all));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.deselect));
      await tester.pumpAndSettle();

      // Verify we're out of selection mode
      expect(find.text('Test Playlist'), findsOneWidget);

      // Tap a track — should trigger playback (navigate to /player)
      await tester.tap(find.text('B.mp3'));
      await tester.pumpAndSettle();

      expect(find.text('Player'), findsOneWidget);
    });
  });
}
