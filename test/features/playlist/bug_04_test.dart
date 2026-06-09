// test/features/playlist/bug_04_test.dart
// BUG-04: 播放单曲目排序缺少防御检查
//
// reorderPlaylistTrackProvider 没有检查当前排序模式，仅靠 UI 层阻止调用。
// 修复：在 Provider 中添加排序模式检查，如果当前排序不是 addedAsc，直接 return。
//
// 测试用例:
//   BUG-04-T01: 非 addedAsc 排序下调用 reorder → 操作被忽略
//   BUG-04-T02: addedAsc 排序下调用 reorder → 正常执行（回归）

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:nas_audio_player/core/database/dao/playlist_dao.dart';
import 'package:nas_audio_player/features/playlist/playlist_provider.dart';

import 'bug_04_test.mocks.dart';

@GenerateMocks([PlaylistDao])
void main() {
  // BUG-04-T01: 非 addedAsc 排序下调用 reorder → 操作被忽略
  group('BUG-04-T01 reorder ignored when sort is not addedAsc', () {
    test('nameAsc sort: reorderTrack is NOT called', () async {
      final mockDao = MockPlaylistDao();

      final container = ProviderContainer(overrides: [
        playlistDaoProvider.overrideWithValue(mockDao),
        trackSortProvider.overrideWith((ref) => TrackSortOption.nameAsc),
      ]);
      addTearDown(container.dispose);

      final reorder = container.read(reorderPlaylistTrackProvider);
      await reorder(1, 0, 2);

      verifyNever(mockDao.reorderTrack(any, any, any));
    });

    test('nameDesc sort: reorderTrack is NOT called', () async {
      final mockDao = MockPlaylistDao();

      final container = ProviderContainer(overrides: [
        playlistDaoProvider.overrideWithValue(mockDao),
        trackSortProvider.overrideWith((ref) => TrackSortOption.nameDesc),
      ]);
      addTearDown(container.dispose);

      final reorder = container.read(reorderPlaylistTrackProvider);
      await reorder(1, 0, 2);

      verifyNever(mockDao.reorderTrack(any, any, any));
    });
  });

  // BUG-04-T02: addedAsc 排序下调用 reorder → 正常执行（回归）
  group('BUG-04-T02 reorder executes when sort is addedAsc', () {
    test('addedAsc sort: reorderTrack IS called with correct args', () async {
      final mockDao = MockPlaylistDao();
      when(mockDao.reorderTrack(1, 0, 2)).thenAnswer((_) async {});

      final container = ProviderContainer(overrides: [
        playlistDaoProvider.overrideWithValue(mockDao),
        trackSortProvider.overrideWith((ref) => TrackSortOption.addedAsc),
      ]);
      addTearDown(container.dispose);

      final reorder = container.read(reorderPlaylistTrackProvider);
      await reorder(1, 0, 2);

      verify(mockDao.reorderTrack(1, 0, 2)).called(1);
    });
  });
}
