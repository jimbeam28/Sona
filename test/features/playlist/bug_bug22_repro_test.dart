// test/features/playlist/bug_bug22_repro_test.dart
// BUG-22: deletePlaylist 后不 invalidate playlistTracksProvider(id)，
// 非 autoDispose family 缓存幽灵数据滞留。
// cr 来源: docs/cr/cr-20260822-2051.md F4
//
// 现状 playlist_provider.dart:101-107 删除后只刷 playlistListProvider；
// 对照组 addTracks/removeTracks（:118-126/:139-147）均双刷。
//
// 覆盖:
// BUG-22-S1-T01: 删除播放单后曲目 family 缓存必须失效并重新查询（修复前 FAIL）
// BUG-22-S2-T01: 否定断言 —— 未删除的播放单缓存不受影响

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nas_audio_player/features/playlist/playlist_provider.dart';
import 'package:nas_audio_player/shared/models/nas_file.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../helpers/test_database.dart';

NasFile _audio(String name, String path) =>
    NasFile(name: name, path: path, isDirectory: false);

Future<int> _createWithTracks(
    ProviderContainer container, String name, List<NasFile> files) async {
  final id = await container.read(playlistServiceProvider).createPlaylist(name);
  await container.read(addTracksToPlaylistProvider)(id, files);
  return id;
}

void main() {
  late Database db;

  setUpAll(() {
    initSqfliteFfi();
  });

  setUp(() async {
    db = await openTestDatabase(TestSchema.playlist);
  });

  tearDown(() async {
    await db.close();
  });

  group('BUG-22-S1 修复门禁（修复前 FAIL）', () {
    test('BUG-22-S1-T01: 删除播放单后曲目缓存不得滞留', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final id =
          await _createWithTracks(container, 'P1', [_audio('a.mp3', '/a.mp3')]);

      // 建立缓存
      final before = await container.read(playlistTracksProvider(id).future);
      expect(before, hasLength(1));

      await container.read(deletePlaylistProvider)(id);

      // 对照组（既有行为）：列表缓存正确刷新
      expect(await container.read(playlistListProvider.future), isEmpty,
          reason: '列表缓存应随删除刷新');

      // 修复点断言：曲目 family 缓存必须随删除失效并重新查询到空
      final after = await container.read(playlistTracksProvider(id).future);
      expect(after, isEmpty, reason: '已删播放单的曲目缓存不得滞留内存');
    });
  });

  group('BUG-22-S2 否定断言', () {
    test('BUG-22-S2-T01: 删除一个播放单不影响另一播放单的曲目缓存', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final idA = await _createWithTracks(
          container, 'P-A', [_audio('a.mp3', '/a.mp3')]);
      final idB = await _createWithTracks(
          container, 'P-B', [_audio('b.mp3', '/b.mp3')]);

      // 预热两个 family 元素
      expect(await container.read(playlistTracksProvider(idA).future),
          hasLength(1));
      expect(await container.read(playlistTracksProvider(idB).future),
          hasLength(1));

      await container.read(deletePlaylistProvider)(idB);

      // 否定: idA 的缓存语义不受删除 idB 影响（仍为一条且内容不变）
      final tracksA = await container.read(playlistTracksProvider(idA).future);
      expect(tracksA, hasLength(1));
      expect(tracksA.single.filePath, '/a.mp3');
    });
  });
}
