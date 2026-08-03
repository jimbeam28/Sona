// test/features/playlist/bug_09_test.dart
// BUG-09: 添加曲目弹窗跨目录累积选择后"全选/取消全选"判定错误
// （cr-20260724-0110.md LIST2，spec docs/features/BUG-09.md）
//
// BUG-09-S1   全选判定改为当前目录集合语义
//             （allPaths.every(_selectedPaths.contains)，不受跨目录累积计数影响）
// BUG-09-INV1 全选/取消全选操作仅影响当前目录的音频
//
// 复现路径（cr LIST2）：
//   ① 目录 A（2 首）勾 1 首 → 进目录 B（1 首）→ 修复前 header 显示"取消全选"
//     （1==1 但 B 中 0 首被选）→ 点击清空 A 的已选
//   ② A 全选 3 首 → 进同为 3 首的 B → 修复前显示"取消全选" → 点击把 A 的 3 首全清
// 期望均为按当前目录集合语义操作，他目录已选保留。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nas_audio_player/features/browser/browser_provider.dart';
import 'package:nas_audio_player/features/playlist/playlist_detail_screen.dart';
import 'package:nas_audio_player/features/playlist/playlist_provider.dart';
import 'package:nas_audio_player/shared/models/nas_file.dart';
import 'package:nas_audio_player/shared/models/playlist.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../helpers/widget_helpers.dart';

// ── Helpers ───────────────────────────────────────────────────────────────────

final _now = DateTime.now();

final _testPlaylists = [
  Playlist(
      id: 1,
      name: 'Test Playlist',
      trackCount: 0,
      createdAt: _now,
      updatedAt: _now),
];

NasFile _file(String name, String path) => NasFile(
      name: name,
      path: path,
      isDirectory: false,
      audioType: AudioFileType.music,
    );

NasFile _dir(String name, String path) =>
    NasFile(name: name, path: path, isDirectory: true);

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

void main() {
  setUpAll(() {
    sqfliteFfiInit();
  });

  /// Builds the PlaylistDetailScreen with per-path directory overrides.
  Future<void> pumpApp(
    WidgetTester tester, {
    required Map<String, List<NasFile>> contents,
    void Function(int playlistId, List<NasFile> files)? onAddTracks,
  }) async {
    await tester.pumpWidget(buildTestAppWithRouter(
      const PlaylistDetailScreen(playlistId: 1),
      overrides: [
        playlistTracksProvider(1)
            .overrideWith((ref) => Future.value(<PlaylistTrack>[])),
        playlistListProvider
            .overrideWith((ref) => Future.value(_testPlaylists)),
        directoryContentsProvider.overrideWith(
            (ref, path) => Future.value(contents[path] ?? <NasFile>[])),
        if (onAddTracks != null)
          addTracksToPlaylistProvider
              .overrideWith((ref) => (playlistId, files) {
                    onAddTracks(playlistId, files);
                    return Future.value();
                  }),
      ],
    ));
    await _pumpSheet(tester);
    await _openSheet(tester);
  }

  // ── BUG-09-S1 / U1: A 勾 1 首 → 进 B（1 首）→ 标签"全选"，点击选中 B 且 A 保留 ──

  group('BUG-09-S1 cross-directory select-all judgment (set-containment)', () {
    testWidgets(
        'U1: 1 selected in A, enter B (1 track) → label 全选; tap selects B, A kept',
        (WidgetTester tester) async {
      await pumpApp(tester, contents: {
        '/': [
          _dir('sub', '/sub'),
          _file('a1.mp3', '/a1.mp3'),
          _file('a2.mp3', '/a2.mp3'),
        ],
        '/sub': [_file('b1.mp3', '/sub/b1.mp3')],
      });

      // Select a1.mp3 in root (directory A).
      await tester.tap(find.text('a1.mp3'));
      await _pumpSheet(tester);
      expect(find.text('确认 (1)'), findsOneWidget);

      // Enter directory B.
      await tester.tap(find.text('sub'));
      await _pumpSheet(tester);
      expect(find.text('b1.mp3'), findsOneWidget);

      // 判定用当前目录集合语义：B 中 0 首被选 → 标签必须是"全选"。
      // 否定断言：修复前 _selectedPaths.length(1) == allPaths.length(1) → 误显"取消全选"。
      expect(find.text('取消全选'), findsNothing);
      expect(find.text('全选'), findsOneWidget);

      // Tap 全选 → selects B's only track; A's selection must be kept.
      await tester.tap(find.text('全选'));
      await _pumpSheet(tester);

      // 跨目录累积：确认计数 = A1 + B1 = 2。
      expect(find.text('确认 (2)'), findsOneWidget);
      // 否定断言：修复前点击会 _selectedPaths.clear() → 计数归零。
      expect(find.text('确认 (0)'), findsNothing);
      expect(_checkedCount(tester), equals(1)); // B 中 b1 被勾选
      expect(find.text('取消全选'), findsOneWidget); // B 现已全选
    });

    // ── BUG-09-S1 / U2: A 全选 3 首 → 进同为 3 首的 B → 标签"全选" ──────────────

    testWidgets(
        'U2: select-all 3 in A, enter B with 3 tracks → label 全选; tap adds B, total 6',
        (WidgetTester tester) async {
      await pumpApp(tester, contents: {
        '/': [
          _dir('sub', '/sub'),
          _file('a1.mp3', '/a1.mp3'),
          _file('a2.mp3', '/a2.mp3'),
          _file('a3.mp3', '/a3.mp3'),
        ],
        '/sub': [
          _file('b1.mp3', '/sub/b1.mp3'),
          _file('b2.mp3', '/sub/b2.mp3'),
          _file('b3.mp3', '/sub/b3.mp3'),
        ],
      });

      // Select all in root (directory A).
      await tester.tap(find.text('全选'));
      await _pumpSheet(tester);
      expect(find.text('确认 (3)'), findsOneWidget);
      expect(find.text('取消全选'), findsOneWidget);

      // Enter directory B (also 3 tracks).
      await tester.tap(find.text('sub'));
      await _pumpSheet(tester);

      // B 中 0 首被选 → 标签必须是"全选"。
      // 否定断言：修复前 3 == 3 → 误显"取消全选"，点击会把 A 的 3 首全清。
      expect(find.text('取消全选'), findsNothing);
      expect(find.text('全选'), findsOneWidget);

      await tester.tap(find.text('全选'));
      await _pumpSheet(tester);

      // 跨目录累积总数 = 3 + 3 = 6（修复前为 0）。
      expect(find.text('确认 (6)'), findsOneWidget);
      expect(_checkedCount(tester), equals(3));
    });

    // ── BUG-09-S1 边界裁决：当前目录无音频 → 标签"全选"，点击无效果 ─────────────

    testWidgets('empty current directory → label 全选, tap is a no-op',
        (WidgetTester tester) async {
      await pumpApp(tester, contents: {
        '/': [
          _dir('empty', '/empty'),
          _file('a1.mp3', '/a1.mp3'),
        ],
        '/empty': [_dir('deep', '/empty/deep')],
        '/empty/deep': [],
      });

      // Carry a selection from root into an audio-less directory.
      await tester.tap(find.text('a1.mp3'));
      await _pumpSheet(tester);
      await tester.tap(find.text('empty'));
      await _pumpSheet(tester);

      // allPaths 为空 → 集合包含判定必须落到"全选"（无 isNotEmpty 守卫时
      // [].every(...) 空真会误显"取消全选"）。
      expect(find.text('取消全选'), findsNothing);
      expect(find.text('全选'), findsOneWidget);

      // 点击无效果：跨目录已选不受影响。
      await tester.tap(find.text('全选'));
      await _pumpSheet(tester);
      expect(find.text('确认 (1)'), findsOneWidget);
      expect(find.text('全选'), findsOneWidget);
    });
  });

  // ── BUG-09-INV1: 取消全选仅影响当前目录，他目录已选保留 ──────────────────────

  group('BUG-09-INV1 deselect-all only affects current directory', () {
    testWidgets(
        'U3: B fully selected + A kept → 取消全选 removes only B paths; '
        'navigating back shows A still selected', (WidgetTester tester) async {
      await pumpApp(tester, contents: {
        '/': [
          _dir('sub', '/sub'),
          _file('a1.mp3', '/a1.mp3'),
          _file('a2.mp3', '/a2.mp3'),
          _file('a3.mp3', '/a3.mp3'),
        ],
        '/sub': [
          _file('b1.mp3', '/sub/b1.mp3'),
          _file('b2.mp3', '/sub/b2.mp3'),
          _file('b3.mp3', '/sub/b3.mp3'),
        ],
      });

      // A 全选 3 首 → 进 B 全选 → 累积 6 首。
      await tester.tap(find.text('全选'));
      await _pumpSheet(tester);
      await tester.tap(find.text('sub'));
      await _pumpSheet(tester);
      await tester.tap(find.text('全选'));
      await _pumpSheet(tester);
      expect(find.text('确认 (6)'), findsOneWidget);
      expect(find.text('取消全选'), findsOneWidget);

      // 取消全选：仅移除当前目录（B）的 3 首。
      await tester.tap(find.text('取消全选'));
      await _pumpSheet(tester);

      // 否定断言：修复前 _selectedPaths.clear() → A 的 3 首一并被清（确认 (0)）。
      expect(find.text('确认 (0)'), findsNothing);
      expect(find.text('确认 (3)'), findsOneWidget); // 仅剩 A 的 3 首
      expect(_checkedCount(tester), equals(0)); // B 的勾选全部移除
      expect(find.text('全选'), findsOneWidget); // B 不再是全选态

      // 返回 A：已选项必须仍然在。
      await tester.tap(find.text('根目录'));
      await _pumpSheet(tester);
      expect(_checkedCount(tester), equals(3));
      expect(find.text('确认 (3)'), findsOneWidget);
      expect(find.text('取消全选'), findsOneWidget); // A 仍是全选态
    });

    testWidgets(
        'confirm submits full cross-directory accumulation without loss or dupes',
        (WidgetTester tester) async {
      int? capturedPlaylistId;
      List<NasFile>? capturedFiles;

      await pumpApp(
        tester,
        contents: {
          '/': [
            _dir('sub', '/sub'),
            _file('a1.mp3', '/a1.mp3'),
            _file('a2.mp3', '/a2.mp3'),
          ],
          '/sub': [
            _file('b1.mp3', '/sub/b1.mp3'),
            _file('b2.mp3', '/sub/b2.mp3'),
            _file('b3.mp3', '/sub/b3.mp3'),
          ],
        },
        onAddTracks: (playlistId, files) {
          capturedPlaylistId = playlistId;
          capturedFiles = files;
        },
      );

      // A 勾 1 首 → B 全选 3 首 → 确认提交全部 4 首。
      await tester.tap(find.text('a1.mp3'));
      await _pumpSheet(tester);
      await tester.tap(find.text('sub'));
      await _pumpSheet(tester);
      await tester.tap(find.text('全选'));
      await _pumpSheet(tester);
      expect(find.text('确认 (4)'), findsOneWidget);

      await tester.tap(find.text('确认 (4)'));
      await _pumpSheet(tester);

      expect(capturedPlaylistId, equals(1));
      expect(capturedFiles, isNotNull);
      final paths = capturedFiles!.map((f) => f.path).toList();
      // 无丢失：A 的 a1 与 B 的全部 3 首都在。
      expect(
          paths.toSet(),
          equals({
            '/a1.mp3',
            '/sub/b1.mp3',
            '/sub/b2.mp3',
            '/sub/b3.mp3',
          }));
      // 无重复：列表长度 == 集合大小。
      expect(paths.length, equals(4));
    });
  });
}
