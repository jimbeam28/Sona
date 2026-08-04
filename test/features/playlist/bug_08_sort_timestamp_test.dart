// test/features/playlist/bug_08_sort_timestamp_test.dart
// BUG-08 (spec 2026-07-27): 播放单批添加 ≥40 曲目显示乱序 + 拖拽移错
//
// Spec: docs/features/BUG-08.md（门禁文件见 §5.4，避免与旧 BUG-08
// 空指针测试 bug_08_test.dart 冲突）
//
//   BUG-08-S1   — provider 排序比较器 id tiebreak（全 switch 分支）
//   BUG-08-S2   — 批添加时间戳单调递增（baseTime + n 毫秒）
//   BUG-08-INV1 — 展示序 == DAO reorder 基准序（added_at ASC, id ASC）

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nas_audio_player/core/database/dao/playlist_dao.dart';
import 'package:nas_audio_player/core/database/database_helper.dart';
import 'package:nas_audio_player/features/playlist/domain/playlist_service.dart';
import 'package:nas_audio_player/features/playlist/playlist_provider.dart';
import 'package:nas_audio_player/shared/models/nas_file.dart';
import 'package:nas_audio_player/shared/models/playlist.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../helpers/test_database.dart';

// ── Helpers ───────────────────────────────────────────────────────────────────

/// DAO stub that serves a fixed in-memory track list so comparator edge cases
/// (null ids, equal addedAt, equal fileName) can be exercised without a
/// database round-trip.
class _StubTrackDao extends PlaylistDao {
  _StubTrackDao(this._tracks);

  final List<PlaylistTrack> _tracks;

  @override
  Future<List<PlaylistTrack>> findTracksForPlaylist(int playlistId) async =>
      List<PlaylistTrack>.of(_tracks);
}

PlaylistTrack _track({
  int? id,
  required DateTime addedAt,
  String fileName = 't.mp3',
  String? path,
}) {
  return PlaylistTrack(
    id: id,
    playlistId: 1,
    filePath: path ?? '/music/${id ?? 'null'}_$fileName',
    fileName: fileName,
    addedAt: addedAt,
  );
}

/// Reads the provider-sorted track list through a container whose DAO is the
/// given stub.
Future<List<PlaylistTrack>> _sortedViaProvider(
  List<PlaylistTrack> tracks,
  TrackSortOption sort,
) async {
  final container = ProviderContainer(overrides: [
    playlistDaoProvider.overrideWithValue(_StubTrackDao(tracks)),
    trackSortProvider.overrideWith((ref) => sort),
  ]);
  addTearDown(container.dispose);
  return container.read(playlistTracksProvider(1).future);
}

/// Creates a [ProviderContainer] whose DAO uses the test database injected
/// via [DatabaseHelper] (same pattern as ply_11_test.dart).
ProviderContainer _makeDbContainer() {
  return ProviderContainer(overrides: [
    playlistDaoProvider.overrideWith((ref) => PlaylistDao()),
  ]);
}

List<NasFile> _chapterFiles(int count) {
  return List.generate(
    count,
    (i) => NasFile(
      name: 'chapter_${(i + 1).toString().padLeft(2, '0')}.mp3',
      path: '/books/chapter_${(i + 1).toString().padLeft(2, '0')}.mp3',
      isDirectory: false,
    ),
  );
}

// ═════════════════════════════════════════════════════════════════════════════

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

  // ═══════════════════════════════════════════════════════════════════════
  // BUG-08-S1: 排序比较器 id tiebreak
  // ═══════════════════════════════════════════════════════════════════════

  group('BUG-08-S1 tiebreak by id', () {
    final t = DateTime(2026, 8, 1, 12);

    test('BUG-08-S1: addedAsc — equal addedAt ties broken by id ASC', () async {
      // Input deliberately out of id order.
      final sorted = await _sortedViaProvider([
        _track(id: 3, addedAt: t),
        _track(id: 1, addedAt: t),
        _track(id: 2, addedAt: t),
      ], TrackSortOption.addedAsc);

      expect(sorted.map((e) => e.id).toList(), [1, 2, 3]);
    });

    test(
        'BUG-08-S1: addedAsc — different addedAt keeps primary result '
        '(tiebreak must not override)', () async {
      final early = _track(id: 99, addedAt: t);
      final late = _track(id: 1, addedAt: t.add(const Duration(seconds: 1)));

      // Primary key (addedAt) decides despite the inverted ids.
      final sorted =
          await _sortedViaProvider([late, early], TrackSortOption.addedAsc);

      expect(sorted.map((e) => e.id).toList(), [99, 1]);
    });

    test('BUG-08-S1: addedAsc — null id sorts AFTER non-null on equal addedAt',
        () async {
      final nullId = _track(id: null, addedAt: t);
      final withId = _track(id: 5, addedAt: t);

      final sorted =
          await _sortedViaProvider([nullId, withId], TrackSortOption.addedAsc);

      expect(sorted.map((e) => e.id).toList(), [5, null]);
    });

    test('BUG-08-S1: addedAsc — both ids null returns 0 (no crash)', () async {
      final a = _track(id: null, addedAt: t, path: '/music/a.mp3');
      final b = _track(id: null, addedAt: t, path: '/music/b.mp3');
      final anchor = _track(id: 1, addedAt: t.add(const Duration(seconds: 1)));

      final sorted =
          await _sortedViaProvider([a, b, anchor], TrackSortOption.addedAsc);

      expect(sorted, hasLength(3));
      // The two equivalent null-id tracks occupy the first two slots in
      // unspecified relative order; the later-added anchor stays last.
      expect(sorted[2].id, 1);
      expect(sorted.sublist(0, 2).map((e) => e.id), everyElement(isNull));
    });

    test('BUG-08-S1: nameAsc — equal fileName ties broken by id ASC', () async {
      final dup2 = _track(id: 2, addedAt: t, fileName: 'dup.mp3');
      final dup1 = _track(id: 1, addedAt: t, fileName: 'dup.mp3');
      final other = _track(id: 3, addedAt: t, fileName: 'zzz.mp3');

      final sorted = await _sortedViaProvider(
          [dup2, dup1, other], TrackSortOption.nameAsc);

      expect(sorted.map((e) => e.fileName).toList(),
          ['dup.mp3', 'dup.mp3', 'zzz.mp3']);
      expect(sorted.map((e) => e.id).toList(), [1, 2, 3]);
    });

    test('BUG-08-S1: nameDesc — equal fileName ties broken by id ASC',
        () async {
      final dup2 = _track(id: 2, addedAt: t, fileName: 'dup.mp3');
      final dup1 = _track(id: 1, addedAt: t, fileName: 'dup.mp3');
      final other = _track(id: 3, addedAt: t, fileName: 'aaa.mp3');

      final sorted = await _sortedViaProvider(
          [dup2, dup1, other], TrackSortOption.nameDesc);

      expect(sorted.map((e) => e.fileName).toList(),
          ['dup.mp3', 'dup.mp3', 'aaa.mp3']);
      expect(sorted.map((e) => e.id).toList(), [1, 2, 3]);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // BUG-08-S2: 批添加时间戳单调递增
  // ═══════════════════════════════════════════════════════════════════════

  group('BUG-08-S2 monotonic batch timestamps', () {
    late PlaylistService service;
    late int playlistId;

    setUp(() async {
      service = PlaylistService(dao: PlaylistDao());
      playlistId = await service.createPlaylist('batch');
    });

    test(
        'BUG-08-S2: batch add 50 tracks → display order == insertion order, '
        'timestamps strictly monotonic (no shared DateTime.now())', () async {
      final files = _chapterFiles(50);
      await service.addTracksToPlaylist(playlistId, files);

      final tracks = await service.findTracksForPlaylist(playlistId);
      expect(tracks, hasLength(50));

      // 展示序 == 插入序（U1）
      expect(
        tracks.map((e) => e.fileName).toList(),
        files.map((f) => f.name).toList(),
      );

      // 单调 +1ms；否定断言：不全部共享同一时间戳
      final ms = tracks.map((e) => e.addedAt.millisecondsSinceEpoch).toList();
      expect(ms.toSet(), hasLength(50), reason: 'no two tracks share a stamp');
      for (var i = 1; i < ms.length; i++) {
        expect(ms[i] - ms[i - 1], 1,
            reason: 'track $i must be exactly 1ms after track ${i - 1}');
      }
    });

    test('BUG-08-S2: in-batch duplicate (seen set) does not consume an index',
        () async {
      final files = [
        const NasFile(name: 'a.mp3', path: '/music/a.mp3', isDirectory: false),
        const NasFile(name: 'b.mp3', path: '/music/b.mp3', isDirectory: false),
        const NasFile(name: 'b.mp3', path: '/music/b.mp3', isDirectory: false),
        const NasFile(name: 'c.mp3', path: '/music/c.mp3', isDirectory: false),
      ];
      await service.addTracksToPlaylist(playlistId, files);

      final tracks = await service.findTracksForPlaylist(playlistId);
      // 否定断言：去重逻辑不变 — b.mp3 仅插入一次
      expect(
          tracks.map((e) => e.fileName).toList(), ['a.mp3', 'b.mp3', 'c.mp3']);

      final ms = tracks.map((e) => e.addedAt.millisecondsSinceEpoch).toList();
      // 被跳过的重复不占 index → 时间戳连续（1ms 步进，无空洞）
      expect(ms[1] - ms[0], 1);
      expect(ms[2] - ms[1], 1);
    });

    test(
        'BUG-08-S2: already-present track (trackExists dedup) does not '
        'consume an index', () async {
      await service.addTracksToPlaylist(playlistId, [
        const NasFile(name: 'b.mp3', path: '/music/b.mp3', isDirectory: false),
      ]);

      await service.addTracksToPlaylist(playlistId, [
        const NasFile(name: 'a.mp3', path: '/music/a.mp3', isDirectory: false),
        const NasFile(name: 'b.mp3', path: '/music/b.mp3', isDirectory: false),
        const NasFile(name: 'c.mp3', path: '/music/c.mp3', isDirectory: false),
      ]);

      final tracks = await service.findTracksForPlaylist(playlistId);
      expect(
          tracks.map((e) => e.fileName).toList(), ['b.mp3', 'a.mp3', 'c.mp3']);

      final a = tracks[1].addedAt.millisecondsSinceEpoch;
      final c = tracks[2].addedAt.millisecondsSinceEpoch;
      // 跳过的 b 不占 index → c = a + 1ms（而非 +2ms）
      expect(c - a, 1);
    });

    test('BUG-08-S2: empty files list inserts nothing (behaviour unchanged)',
        () async {
      await service.addTracksToPlaylist(playlistId, const []);

      final tracks = await service.findTracksForPlaylist(playlistId);
      expect(tracks, isEmpty);
    });

    test('BUG-08-S2: single track keeps bare-timestamp behaviour', () async {
      final before = DateTime.now().millisecondsSinceEpoch;
      await service.addTracksToPlaylist(playlistId, [
        const NasFile(
            name: 'only.mp3', path: '/music/only.mp3', isDirectory: false),
      ]);
      final after = DateTime.now().millisecondsSinceEpoch;

      final tracks = await service.findTracksForPlaylist(playlistId);
      expect(tracks, hasLength(1));
      final stamp = tracks.single.addedAt.millisecondsSinceEpoch;
      expect(stamp, inInclusiveRange(before, after));
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // BUG-08-INV1: 展示序 == DAO reorder 基准序（added_at ASC, id ASC）
  // ═══════════════════════════════════════════════════════════════════════

  group('BUG-08-INV1 display order == DAO baseline order', () {
    Future<List<int>> _baselineIds(int playlistId) async {
      final rows = await db.rawQuery(
        'SELECT id FROM playlist_tracks '
        'WHERE playlist_id = ? ORDER BY added_at ASC, id ASC',
        [playlistId],
      );
      return rows.map((r) => r['id'] as int).toList();
    }

    test(
        'BUG-08-INV1: batch of 45 — UI sorted sequence == '
        'ORDER BY added_at ASC, id ASC', () async {
      final container = _makeDbContainer();
      addTearDown(container.dispose);

      final service = PlaylistService(dao: PlaylistDao());
      final playlistId = await service.createPlaylist('inv1');
      await service.addTracksToPlaylist(playlistId, _chapterFiles(45));

      final displayed =
          await container.read(playlistTracksProvider(playlistId).future);
      expect(
        displayed.map((e) => e.id).toList(),
        await _baselineIds(playlistId),
      );
      expect(displayed.map((e) => e.fileName).toList(),
          _chapterFiles(45).map((f) => f.name).toList());
    });

    test(
        'BUG-08-INV1: legacy rows sharing one added_at — UI tie order == '
        'id ASC baseline', () async {
      final container = _makeDbContainer();
      addTearDown(container.dispose);

      final dao = PlaylistDao();
      final playlistId = await dao.insertPlaylist(Playlist(
        name: 'legacy',
        createdAt: DateTime(2026, 8, 1),
        updatedAt: DateTime(2026, 8, 1),
      ));
      final shared = DateTime(2026, 8, 2, 9);
      await dao.addTracks([
        for (var i = 0; i < 5; i++)
          PlaylistTrack(
            playlistId: playlistId,
            filePath: '/legacy/f$i.mp3',
            fileName: 'f$i.mp3',
            addedAt: shared,
          ),
      ]);

      final displayed =
          await container.read(playlistTracksProvider(playlistId).future);
      expect(
        displayed.map((e) => e.id).toList(),
        await _baselineIds(playlistId),
      );
    });

    test(
        'BUG-08-INV1: reorder operates on the displayed order (U2 drag '
        'first → third)', () async {
      final container = _makeDbContainer();
      addTearDown(container.dispose);

      final service = PlaylistService(dao: PlaylistDao());
      final playlistId = await service.createPlaylist('drag');
      await service.addTracksToPlaylist(playlistId, _chapterFiles(5));

      var displayed =
          await container.read(playlistTracksProvider(playlistId).future);
      expect(displayed.map((e) => e.fileName).toList(),
          _chapterFiles(5).map((f) => f.name).toList());

      // Drag displayed first item (chapter_01) to position 3.
      await service.reorderTrack(playlistId, 0, 2);
      container.invalidate(playlistTracksProvider(playlistId));

      displayed =
          await container.read(playlistTracksProvider(playlistId).future);
      expect(displayed.map((e) => e.fileName).toList(), [
        'chapter_02.mp3',
        'chapter_03.mp3',
        'chapter_01.mp3',
        'chapter_04.mp3',
        'chapter_05.mp3',
      ]);
      // Post-reorder display still matches the DAO baseline order.
      expect(
        displayed.map((e) => e.id).toList(),
        await _baselineIds(playlistId),
      );
    });
  });
}
