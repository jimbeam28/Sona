// test/features/playlist/bug_bug02_fixed_test.dart
// BUG-02 §3.2 修复后行为 + §4 不变量 + §6 算法样例
// dev-exe: dev-plan §5.3 测试覆盖盲点 — S2/S3 + INV1/INV2 + ALG 全部样例

import 'package:flutter_test/flutter_test.dart';
import 'package:nas_audio_player/features/playlist/domain/playlist_service.dart';
import 'package:nas_audio_player/shared/models/nas_file.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../helpers/test_database.dart';

NasFile _f(String name, {String? path}) => NasFile(
      name: name,
      path: path ?? '/music/$name',
      isDirectory: false,
      audioType: NasFile.classifyType(name),
    );

void main() {
  setUpAll(() {
    sqfliteFfiInit();
  });

  group('BUG-02 §3.2 修复后行为', () {
    test('BUG-02-S2: 内存内去重——同批次 N≥2 同 path 仅插入 1 条', () async {
      final db = await openTestDatabase(TestSchema.playlist);
      addTearDown(() => db.close());
      final service = PlaylistService();
      final playlistId = await service.createPlaylist('S2');
      final f = _f('a.mp3');
      await service.addTracksToPlaylist(playlistId, [f, f, f, f]);
      final tracks = await service.findTracksForPlaylist(playlistId);
      expect(tracks.length, 1, reason: 'S2 否定: 同 path 项不应多次插入 DB');
      expect(tracks.where((t) => t.filePath == f.path).length, 1);
    });

    test('BUG-02-S2 否定: 不应跳过同批次首次以外不同 path 文件', () async {
      final db = await openTestDatabase(TestSchema.playlist);
      addTearDown(() => db.close());
      final service = PlaylistService();
      final playlistId = await service.createPlaylist('S2-neg');
      final a = _f('a.mp3');
      final b = _f('b.mp3');
      final c = _f('c.mp3');
      await service.addTracksToPlaylist(playlistId, [a, b, a, c, b]);
      final tracks = await service.findTracksForPlaylist(playlistId);
      expect(tracks.length, 3, reason: 'a/b/c 三首应各 1 条');
      expect(tracks.where((t) => t.filePath == a.path).length, 1);
      expect(tracks.where((t) => t.filePath == b.path).length, 1);
      expect(tracks.where((t) => t.filePath == c.path).length, 1);
    });

    test('BUG-02-S2 否定: DB 已有 path 应被跳过（trackExists=true 保留）', () async {
      final db = await openTestDatabase(TestSchema.playlist);
      addTearDown(() => db.close());
      final service = PlaylistService();
      final playlistId = await service.createPlaylist('S2-db');
      final a = _f('a.mp3');
      await service.addTracksToPlaylist(playlistId, [a]);
      final tracks1 = await service.findTracksForPlaylist(playlistId);
      expect(tracks1.length, 1);
      await service.addTracksToPlaylist(playlistId, [a]);
      final tracks2 = await service.findTracksForPlaylist(playlistId);
      expect(tracks2.length, 1, reason: 'DB 已存在同 path，再次同批次调用应跳过');
    });

    test('BUG-02-S3: importPlaylist 与 addTracksToPlaylist 内存去重一致', () async {
      final db = await openTestDatabase(TestSchema.playlist);
      addTearDown(() => db.close());
      final service = PlaylistService();
      final a = _f('a.mp3');
      final b = _f('b.mp3');

      final pidAdd = await service.createPlaylist('add');
      await service.addTracksToPlaylist(pidAdd, [a, b, a, b, a]);
      final addTracks = await service.findTracksForPlaylist(pidAdd);

      final json = '{"name":"imp","tracks":['
          '{"filePath":"/music/a.mp3","fileName":"a.mp3"},'
          '{"filePath":"/music/a.mp3","fileName":"a.mp3"},'
          '{"filePath":"/music/b.mp3","fileName":"b.mp3"}]}';
      final pidImp = await service.importPlaylist(json);
      final impTracks = await service.findTracksForPlaylist(pidImp);

      expect(addTracks.length, 2, reason: 'addTracksToPlaylist 去重后剩 2 条');
      expect(impTracks.length, 2,
          reason: 'S3: importPlaylist 同 path 去重 → 2 条（一致性）');
    });

    test('BUG-02-S3 否定: 空 path 处理对齐 importPlaylist——空 path 被跳过', () async {
      final db = await openTestDatabase(TestSchema.playlist);
      addTearDown(() => db.close());
      final service = PlaylistService();
      final pid = await service.createPlaylist('S3-empty');

      final emptyP = _f('x.mp3', path: '');
      final valid = _f('y.mp3');
      await service.addTracksToPlaylist(pid, [emptyP, valid, emptyP]);
      final tracks = await service.findTracksForPlaylist(pid);
      expect(tracks.length, 1,
          reason: '空 path 与 importPlaylist 一致被跳过；只 1 条 y.mp3');
    });
  });

  group('BUG-02 §4 不变量', () {
    test('BUG-02-INV1: 调用后每 playlistId 下每 filePath 至多 1 行', () async {
      final db = await openTestDatabase(TestSchema.playlist);
      addTearDown(() => db.close());
      final service = PlaylistService();
      final pid = await service.createPlaylist('INV1');
      final a = _f('a.mp3');
      final b = _f('b.mp3');
      final c = _f('c.mp3');
      await service.addTracksToPlaylist(pid, [a, a, b, c, c, b, a]);
      final tracks = await service.findTracksForPlaylist(pid);
      final byPath = <String, int>{};
      for (final t in tracks)
        byPath[t.filePath] = (byPath[t.filePath] ?? 0) + 1;
      for (final cnt in byPath.values) {
        expect(cnt, equals(1), reason: 'INV1: 每 filePath 至多 1 行');
      }
      expect(byPath.length, 3);
    });

    test('BUG-02-INV2: 跨批次 + 同批次去重规则一致', () async {
      final db = await openTestDatabase(TestSchema.playlist);
      addTearDown(() => db.close());
      final service = PlaylistService();
      final pid = await service.createPlaylist('INV2');
      final a = _f('a.mp3');
      final g = _f('g.mp3');
      await service.addTracksToPlaylist(pid, [a]);
      await service.addTracksToPlaylist(pid, [a, g]);
      final tracks = await service.findTracksForPlaylist(pid);
      expect(tracks.length, 2, reason: 'INV2: 跨批次已写 a 后再次送 [a,g]，仅 g 新增；共 2 行');
      expect(tracks.where((t) => t.filePath == a.path).length, 1);
      expect(tracks.where((t) => t.filePath == g.path).length, 1);
    });
  });

  group('BUG-02 §6 算法样例', () {
    test('ALG [f, f] → 1 row 插入', () async {
      final db = await openTestDatabase(TestSchema.playlist);
      addTearDown(() => db.close());
      final service = PlaylistService();
      final pid = await service.createPlaylist('alg1');
      final f = _f('a.mp3');
      await service.addTracksToPlaylist(pid, [f, f]);
      final tracks = await service.findTracksForPlaylist(pid);
      expect(tracks.length, 1);
    });

    test('ALG [f, f, f, g] → 2 rows 插入', () async {
      final db = await openTestDatabase(TestSchema.playlist);
      addTearDown(() => db.close());
      final service = PlaylistService();
      final pid = await service.createPlaylist('alg2');
      final f = _f('a.mp3');
      final g = _f('b.mp3');
      await service.addTracksToPlaylist(pid, [f, f, f, g]);
      final tracks = await service.findTracksForPlaylist(pid);
      expect(tracks.length, 2);
    });

    test('ALG [f] DB 已有 f → 0 rows 插入', () async {
      final db = await openTestDatabase(TestSchema.playlist);
      addTearDown(() => db.close());
      final service = PlaylistService();
      final pid = await service.createPlaylist('alg3');
      final f = _f('a.mp3');
      await service.addTracksToPlaylist(pid, [f]);
      final before = await service.findTracksForPlaylist(pid);
      expect(before.length, 1);
      await service.addTracksToPlaylist(pid, [f]);
      final after = await service.findTracksForPlaylist(pid);
      expect(after.length, 1, reason: 'DB 已有 f 再 add [f] → 0 增量');
    });

    test('ALG [f, f] 且 DB 已有 f → 0 rows 插入', () async {
      final db = await openTestDatabase(TestSchema.playlist);
      addTearDown(() => db.close());
      final service = PlaylistService();
      final pid = await service.createPlaylist('alg4');
      final f = _f('a.mp3');
      await service.addTracksToPlaylist(pid, [f]);
      await service.addTracksToPlaylist(pid, [f, f]);
      final tracks = await service.findTracksForPlaylist(pid);
      expect(tracks.length, 1, reason: 'DB 已有 f 再 add [f,f] → 0 增量');
    });

    test('ALG [] → 0 rows 不触发 addTracks', () async {
      final db = await openTestDatabase(TestSchema.playlist);
      addTearDown(() => db.close());
      final service = PlaylistService();
      final pid = await service.createPlaylist('alg5');
      await service.addTracksToPlaylist(pid, []);
      final tracks = await service.findTracksForPlaylist(pid);
      expect(tracks, isEmpty);
    });
  });
}
