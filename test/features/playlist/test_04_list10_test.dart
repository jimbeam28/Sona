// test/features/playlist/test_04_list10_test.dart
// TEST-04-S4~S6: 播放单重命名校验（LIST10）— spec: docs/features/TEST-04.md §3.2
//
// 真实 PlaylistDetailScreen + 记录型 fake playlistDao：打开重命名对话框
// （edit_outlined），验证空串/纯空白被拦截（rename 不调、名称不变），
// 合法名称触发 updatePlaylist 且 UI 刷新。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nas_audio_player/core/contracts/database_contract.dart';
import 'package:nas_audio_player/features/playlist/playlist_detail_screen.dart';
import 'package:nas_audio_player/features/playlist/playlist_provider.dart';
import 'package:nas_audio_player/shared/models/playlist.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../helpers/widget_helpers.dart';

// ── Recording fake playlist DAO ───────────────────────────────────────────────

/// Records [updatePlaylist] invocations and keeps an in-memory playlist list
/// so the playlistListProvider override can re-read the current name after
/// a rename (mirrors production DB-backed refresh).
class _RecordingPlaylistDao implements IPlaylistDao {
  _RecordingPlaylistDao(List<Playlist> initial) : playlists = List.of(initial);

  final List<Playlist> playlists;
  final List<Playlist> updateCalls = [];

  @override
  Future<int> insertPlaylist(Playlist? playlist) async {
    playlists.add(playlist!);
    return playlists.length;
  }

  @override
  Future<List<Playlist>> findAllPlaylists() async => List.of(playlists);

  @override
  Future<void> updatePlaylist(Playlist? playlist) async {
    updateCalls.add(playlist!);
    final i = playlists.indexWhere((p) => p.id == playlist.id);
    if (i >= 0) playlists[i] = playlist;
  }

  @override
  Future<void> deletePlaylist(int? id) async {}

  @override
  Future<void> addTracks(List<PlaylistTrack>? tracks) async {}

  @override
  Future<List<PlaylistTrack>> findTracksForPlaylist(int? playlistId) async =>
      <PlaylistTrack>[];

  @override
  Future<void> removeTracks(List<int>? trackIds) async {}

  @override
  Future<bool> trackExists(int? playlistId, String? filePath) async => false;

  @override
  Future<void> reorderTrack(
      int? playlistId, int? oldIndex, int? newIndex) async {}
}

// ── Test fixtures ─────────────────────────────────────────────────────────────

final _now = DateTime(2026, 7, 27);

Playlist _playlist(String name) => Playlist(
      id: 1,
      name: name,
      trackCount: 0,
      createdAt: _now,
      updatedAt: _now,
    );

/// Renders the real [PlaylistDetailScreen] against the recording fake DAO.
Future<WidgetTester> _pumpDetail(
  WidgetTester tester,
  _RecordingPlaylistDao dao,
) async {
  await tester.pumpWidget(buildTestAppWithPlayerRoute(
    const PlaylistDetailScreen(playlistId: 1),
    overrides: [
      playlistTracksProvider(1)
          .overrideWith((ref) => Future.value(<PlaylistTrack>[])),
      playlistListProvider.overrideWith((ref) => dao.findAllPlaylists()),
      playlistDaoProvider.overrideWithValue(dao),
    ],
  ));
  await tester.pumpAndSettle();
  return tester;
}

/// Opens the rename dialog via the AppBar edit action.
Future<void> _openRenameDialog(WidgetTester tester) async {
  await tester.tap(find.byIcon(Icons.edit_outlined));
  await tester.pumpAndSettle();
  expect(find.text('重命名播放单'), findsOneWidget, reason: '前置——重命名对话框应已打开');
}

/// Submits [newName] through the rename dialog's 保存 button.
Future<void> _submitRename(WidgetTester tester, String newName) async {
  await tester.enterText(find.byType(TextField).first, newName);
  await tester.pump();
  await tester.tap(find.text('保存'));
  await tester.pumpAndSettle();
}

// ═════════════════════════════════════════════════════════════════════════════
// TEST-04-S4~S6 — 重命名空名/空白校验
// ═════════════════════════════════════════════════════════════════════════════

void main() {
  setUpAll(() {
    sqfliteFfiInit();
  });

  group('TEST-04-S4: 重命名输入空串被拦截', () {
    testWidgets('TEST-04-S4: 输入空串点保存 → rename 未调、名称不变',
        (WidgetTester tester) async {
      final dao = _RecordingPlaylistDao([_playlist('My Playlist')]);
      await _pumpDetail(tester, dao);

      expect(find.text('My Playlist'), findsOneWidget, reason: '前置——播放单名称应显示');

      await _openRenameDialog(tester);
      await _submitRename(tester, '');

      // 否定：空串不得调用 updatePlaylist（rename）
      expect(dao.updateCalls, isEmpty,
          reason: 'TEST-04-S4: 空串必须被校验拦截，不得调用 rename');
      // 播放单名称不变（否定：不得改名成功）
      expect(find.text('My Playlist'), findsOneWidget,
          reason: 'TEST-04-S4: 空串提交后播放单名称必须保持 "My Playlist"');
      expect(dao.playlists.single.name, equals('My Playlist'),
          reason: 'TEST-04-S4: DAO 中名称不得被改写');
    });
  });

  group('TEST-04-S5: 重命名输入纯空白被拦截', () {
    testWidgets('TEST-04-S5: 输入纯空白点保存 → rename 未调、名称不变',
        (WidgetTester tester) async {
      final dao = _RecordingPlaylistDao([_playlist('My Playlist')]);
      await _pumpDetail(tester, dao);

      expect(find.text('My Playlist'), findsOneWidget, reason: '前置——播放单名称应显示');

      await _openRenameDialog(tester);
      await _submitRename(tester, '   ');

      // 否定：trim 后为空不得调用 updatePlaylist（rename）
      expect(dao.updateCalls, isEmpty,
          reason: 'TEST-04-S5: 纯空白必须被 trim 校验拦截，不得调用 rename');
      // 播放单名称不变
      expect(find.text('My Playlist'), findsOneWidget,
          reason: 'TEST-04-S5: 纯空白提交后播放单名称必须保持 "My Playlist"');
      expect(dao.playlists.single.name, equals('My Playlist'),
          reason: 'TEST-04-S5: DAO 中名称不得被改写');
    });
  });

  group('TEST-04-S6: 重命名输入合法名称成功保存', () {
    testWidgets('TEST-04-S6: 输入 "New Name" 点保存 → rename 被调 + UI 更新',
        (WidgetTester tester) async {
      final dao = _RecordingPlaylistDao([_playlist('My Playlist')]);
      await _pumpDetail(tester, dao);

      expect(find.text('My Playlist'), findsOneWidget, reason: '前置——播放单名称应显示');

      await _openRenameDialog(tester);
      await _submitRename(tester, 'New Name');

      // 合法名称必须调用 updatePlaylist（rename），目标播放单 id + 新名称
      expect(dao.updateCalls, hasLength(1),
          reason: 'TEST-04-S6: 合法名称必须调用一次 rename');
      expect(dao.updateCalls.single.id, equals(1),
          reason: 'TEST-04-S6: rename 应作用于播放单 id=1');
      expect(dao.updateCalls.single.name, equals('New Name'),
          reason: 'TEST-04-S6: rename 应传入新名称 "New Name"');
      // UI 刷新：名称显示更新
      expect(find.text('New Name'), findsOneWidget,
          reason: 'TEST-04-S6: 保存后 UI 应显示新名称');
      // 否定：旧名称不得残留
      expect(find.text('My Playlist'), findsNothing,
          reason: 'TEST-04-S6: 保存后旧名称不得残留');
    });
  });
}
