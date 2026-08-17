// test/features/playlist/ref_08_clock_injection_test.dart
// REF-08 门禁测试（spec docs/features/REF-08.md §5.4 指定文件）。
//
// 锚定 PlaylistService 注入 now provider（createPlaylist/addTracksToPlaylist/
// importPlaylist 三处取时从 DateTime.now() 改为注入时钟）：
//   - S1 现状：DAO 注入时钟对 insert 路径无效（service 未注入时取真实时钟）
//   - S2 addTracksToPlaylist 批量单调时间戳语义（BUG-08-S2）
//   - S3 createPlaylist 用 _clock() 取时一次，落库精确等于 fixedClock
//   - S4 addTracksToPlaylist 用 _clock()，批量单调语义保持，去重不重复取时
//   - S5 importPlaylist 用 _clock()，播放单行与曲目时间戳精确等于 fixedClock
//   - S6 生产装配默认时钟不变（playlistServiceProvider 不传 clock）
//   - INV1 insert 路径时间戳由 service 注入时钟唯一决定（DAO insert 不覆盖）
//   - INV2 同一次批内 addedAt 严格单调

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nas_audio_player/core/database/dao/playlist_dao.dart';
import 'package:nas_audio_player/features/playlist/domain/playlist_service.dart';
import 'package:nas_audio_player/shared/models/nas_file.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../helpers/test_database.dart';

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

  NasFile file(String path) => NasFile(
        name: path.split('/').last,
        path: path,
        isDirectory: false,
        audioType: NasFile.isAudioFile(path.split('/').last)
            ? NasFile.classifyType(path.split('/').last)
            : null,
      );

  group('REF-08: PlaylistService 时钟注入', () {
    test('REF-08-S1: DAO 注入时钟对 insert 路径无效（service 未注入走真实时钟）', () async {
      final daoClock = DateTime(2026, 1, 1, 0, 0, 0);
      final dao = PlaylistDao(clock: () => daoClock);
      final service = PlaylistService(dao: dao);

      final id = await service.createPlaylist('X');
      final playlists = await service.findAllPlaylists();
      final p = playlists.firstWhere((e) => e.id == id);

      // service 未注入时钟 → createdAt 为真实时钟（远大于 2026-01-01）
      expect(p.createdAt.isAfter(daoClock), isTrue,
          reason: 'service 未注入时钟时 insert 路径取真实时钟，DAO 时钟被绕过');
    });

    test('REF-08-S2: addTracksToPlaylist 批量单调时间戳（去重不消耗序号）', () async {
      final dao = PlaylistDao(clock: () => DateTime(2026, 1, 1));
      final service = PlaylistService(dao: dao);

      final id = await service.createPlaylist('P');
      await service.addTracksToPlaylist(
          id, [file('/a.mp3'), file('/b.mp3'), file('/a.mp3')]);

      final tracks = await service.findTracksForPlaylist(id);
      expect(tracks.length, 2, reason: '重复 path 只插入 1 条');
      expect(tracks[0].addedAt,
          tracks[1].addedAt.subtract(const Duration(milliseconds: 1)),
          reason: '第 1 条 addedAt 为 baseTime.add(0ms)，第 2 条为 add(1ms)');
    });

    test('REF-08-S3: createPlaylist 用 _clock() 取时一次，落库精确等于 fixedClock',
        () async {
      final fixed = DateTime(2026, 1, 1, 0, 0, 0, 0);
      var calls = 0;
      final service = PlaylistService(
        dao: PlaylistDao(clock: () => DateTime(2026, 5, 5)),
        clock: () {
          calls++;
          return fixed;
        },
      );

      final id = await service.createPlaylist('X');
      expect(calls, equals(1), reason: '_clock() 不得被多次调用');

      final playlists = await service.findAllPlaylists();
      final p = playlists.firstWhere((e) => e.id == id);
      expect(p.createdAt, fixed, reason: 'createdAt 应精确等于注入时钟值');
      expect(p.updatedAt, fixed, reason: 'updatedAt 应精确等于注入时钟值');
      expect(id, greaterThan(0));
    });

    test('REF-08-S4: addTracksToPlaylist 用 _clock()，去重文件不多取时', () async {
      final fixed = DateTime(2026, 1, 2, 12, 0, 0, 0);
      var calls = 0;
      final service = PlaylistService(
        dao: PlaylistDao(clock: () => DateTime(2026, 5, 5)),
        clock: () {
          calls++;
          return fixed;
        },
      );

      final id = await service.createPlaylist('P');
      expect(calls, equals(1), reason: 'createPlaylist 取时一次');

      await service.addTracksToPlaylist(
          id, [file('/a.mp3'), file('/b.mp3'), file('/a.mp3')]);

      expect(calls, equals(2),
          reason: 'addTracksToPlaylist 再多取时一次（含去重文件也不多取时）');

      final tracks = await service.findTracksForPlaylist(id);
      expect(tracks.length, 2);
      expect(tracks[0].addedAt, fixed);
      expect(tracks[1].addedAt, fixed.add(const Duration(milliseconds: 1)));
    });

    test('REF-08-S4 边界: 空 files 列表 baseTime 在循环前仍取时一次（保持现状位置）', () async {
      var calls = 0;
      final service = PlaylistService(
        dao: PlaylistDao(clock: () => DateTime(2026, 5, 5)),
        clock: () {
          calls++;
          return DateTime(2026, 1, 2);
        },
      );

      final id = await service.createPlaylist('P');
      final before = calls;
      await service.addTracksToPlaylist(id, []);
      expect(calls, before + 1, reason: 'baseTime 在循环前读取，空列表仍取时一次（现状位置保持）');
      expect(await service.findTracksForPlaylist(id), isEmpty);
    });

    test('REF-08-S5: importPlaylist 用 _clock()，行与曲目时间戳精确', () async {
      final fixed = DateTime(2026, 1, 3, 8, 0, 0, 0);
      var calls = 0;
      final service = PlaylistService(
        dao: PlaylistDao(clock: () => DateTime(2026, 5, 5)),
        clock: () {
          calls++;
          return fixed;
        },
      );

      const json = '{"name":"Imported","tracks":['
          '{"filePath":"/a.mp3","fileName":"a.mp3"}]}';
      final id = await service.importPlaylist(json);

      expect(calls, equals(1), reason: '_clock() 在 tracks 解析前取时一次');

      final playlists = await service.findAllPlaylists();
      final p = playlists.firstWhere((e) => e.id == id);
      expect(p.createdAt, fixed);
      expect(p.updatedAt, fixed);

      final tracks = await service.findTracksForPlaylist(id);
      expect(tracks.length, 1);
      expect(tracks.first.addedAt, fixed.add(Duration.zero));
    });

    test('REF-08-S5 否定: 空 tracks 导入 _clock() 仍只调用一次', () async {
      var calls = 0;
      final service = PlaylistService(
        dao: PlaylistDao(clock: () => DateTime(2026, 5, 5)),
        clock: () {
          calls++;
          return DateTime(2026, 1, 3);
        },
      );

      await service.importPlaylist('{"name":"Empty","tracks":[]}');
      expect(calls, equals(1), reason: '空 tracks 导入仍只取时一次');
    });

    test('REF-08-S6: 默认构造 _clock 为 DateTime.now，生产行为不变', () async {
      final before = DateTime.now().millisecondsSinceEpoch;
      final service = PlaylistService(dao: PlaylistDao());
      final id = await service.createPlaylist('RealClock');
      final after = DateTime.now().millisecondsSinceEpoch;

      final playlists = await service.findAllPlaylists();
      final p = playlists.firstWhere((e) => e.id == id);
      final createdMs = p.createdAt.millisecondsSinceEpoch;
      expect(createdMs >= before, isTrue);
      expect(createdMs <= after, isTrue);
    });

    test('REF-08-S6 否定: 生产装配不传 clock（playlistServiceProvider 无 clock 实参）',
        () async {
      final src = await Future.value(
          '${Directory.current.path}/lib/features/playlist/playlist_provider.dart');
      final content = await File(src).readAsString();
      expect(
          content
              .contains('PlaylistService(dao: ref.read(playlistDaoProvider))'),
          isTrue,
          reason: '生产装配必须是 PlaylistService(dao: ...) 形态');
      expect(
          content
              .contains('PlaylistService(dao: ref.read(playlistDaoProvider), '
                  'clock:'),
          isFalse,
          reason: '生产装配不得注入 clock 实参');
    });

    test('REF-08-INV1: DAO insert 不覆盖 model 时间戳（insert 路径单一时钟权威）', () async {
      final daoClock = DateTime(2026, 9, 9);
      final service = PlaylistService(
        dao: PlaylistDao(clock: () => daoClock),
        clock: () => DateTime(2026, 1, 1),
      );

      final id = await service.createPlaylist('INV1');
      final playlists = await service.findAllPlaylists();
      final p = playlists.firstWhere((e) => e.id == id);
      expect(p.createdAt, DateTime(2026, 1, 1),
          reason: 'insert 路径时间戳由 service 时钟决定，DAO 时钟不覆盖');
      expect(p.updatedAt, DateTime(2026, 1, 1));
    });

    test('REF-08-INV2: 同一次批内 addedAt 严格单调', () async {
      final service = PlaylistService(
        dao: PlaylistDao(clock: () => DateTime(2026, 5, 5)),
        clock: () => DateTime(2026, 1, 4),
      );

      final id = await service.createPlaylist('P');
      await service.addTracksToPlaylist(
          id, [file('/a.mp3'), file('/b.mp3'), file('/c.mp3')]);

      final tracks = await service.findTracksForPlaylist(id);
      expect(tracks.length, 3);
      for (var i = 0; i < tracks.length - 1; i++) {
        expect(tracks[i].addedAt.isBefore(tracks[i + 1].addedAt), isTrue,
            reason: 'INV2: 批内 addedAt 严格单调');
      }
    });
  });
}
