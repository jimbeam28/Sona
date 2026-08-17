// test/features/playlist/ref_07_import_name_test.dart
// REF-07 门禁测试（spec docs/features/REF-07.md §5.4 指定文件）。
//
// 锚定 importPlaylist 空名/纯空白名归默认名（服务层裁决）：
//   - S2 缺陷态：空串 name 此前原样透传产生无名播放单 → 修复后归默认名
//   - S3 缺陷态：空名单导出再导入往返保持空名 → 修复后再导入归默认名
//   - S4 空串名 → 归默认名 '导入的播放单'，tracks 正常导入
//   - S5 纯空白名（空格/制表符）→ 归默认名
//   - S6 trim 后非空名称原样保存（不做一般性 trim）
//   - S7 空名播放单导出再导入 → 导出内容不变，导入后为默认名
//   - S8 createPlaylist 服务层行为保持（空名原样透传，UI 门禁不归本修改）
//   - INV1 导入创建的播放单 name 必非空（trim 后）
//   - INV2 结构异常 JSON 不抛 TypeError/NoSuchMethodError

import 'package:flutter_test/flutter_test.dart';
import 'package:nas_audio_player/core/database/dao/playlist_dao.dart';
import 'package:nas_audio_player/features/playlist/domain/playlist_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../helpers/test_database.dart';

void main() {
  late Database db;
  late PlaylistDao dao;
  late PlaylistService service;

  setUpAll(() {
    initSqfliteFfi();
  });

  setUp(() async {
    db = await openTestDatabase(TestSchema.playlist);
    dao = PlaylistDao();
    service = PlaylistService(dao: dao);
  });

  tearDown(() async {
    await db.close();
  });

  group('REF-07-ALG1-normalizeImportName: 名称归一各形态', () {
    test('缺失/非String/空串/纯空白 → 默认名；trim后非空 → 原样', () async {
      for (final (input, expected) in [
        ('{"tracks":[]}', '导入的播放单'),
        ('{"name":123,"tracks":[]}', '导入的播放单'),
        ('{"name":"","tracks":[]}', '导入的播放单'),
        ('{"name":"   ","tracks":[]}', '导入的播放单'),
        ('{"name":"X","tracks":[]}', 'X'),
        ('{"name":"  X  ","tracks":[]}', '  X  '),
      ]) {
        final newId = await service.importPlaylist(input);
        final playlists = await service.findAllPlaylists();
        final imported = playlists.firstWhere((p) => p.id == newId);
        expect(imported.name, expected,
            reason: 'REF-07-ALG1: 输入 $input 应归一为 $expected');
      }
    });
  });

  group('REF-07: importPlaylist 空名归一默认名', () {
    test('REF-07-S2 缺陷态翻转: 空串名导入 → 归默认名（不再产生无名播放单）', () async {
      const jsonStr = '{"name":"","tracks":[{"filePath":"/a.mp3",'
          '"fileName":"a.mp3"}]}';

      final newId = await service.importPlaylist(jsonStr);
      expect(newId, greaterThan(0));

      final playlists = await service.findAllPlaylists();
      final imported = playlists.firstWhere((p) => p.id == newId);
      expect(imported.name, '导入的播放单', reason: '空串名必须归默认名，不得产生无名播放单');

      final tracks = await service.findTracksForPlaylist(newId);
      expect(tracks.length, 1, reason: '空名裁决不影响 tracks 导入');
    });

    test('REF-07-S3 缺陷态翻转: 空名单导出再导入 → 再导入归默认名', () async {
      // 服务层直建空名播放单（模拟修复前已产生的无名播放单）
      final emptyId = await service.createPlaylist('');
      expect(emptyId, greaterThan(0));

      // 导出内容原样：name 仍为空串（导出端零改写）
      final exported = await service.exportPlaylist(emptyId);
      expect(exported, contains('"name": ""'), reason: '导出端不得改写 name（保持空串）');

      // 再导入该 JSON → S4 裁决生效 → 新行归默认名
      final reimportedId = await service.importPlaylist(exported);
      final playlists = await service.findAllPlaylists();
      final imported = playlists.firstWhere((p) => p.id == reimportedId);
      expect(imported.name, '导入的播放单', reason: '空名 JSON 再导入后必须归默认名');

      // 已存在的空名行不得被追溯改名（export 无副作用）
      final original = playlists.firstWhere((p) => p.id == emptyId);
      expect(original.name, '', reason: '已存在的空名行不追溯改名');
    });

    test('REF-07-S4: 空串名 → 归默认名，tracks 正常导入', () async {
      const jsonStr = '{"name":"","tracks":[{"filePath":"/a.mp3",'
          '"fileName":"a.mp3"}]}';

      final newId = await service.importPlaylist(jsonStr);
      expect(newId, greaterThan(0));

      final playlists = await service.findAllPlaylists();
      final imported = playlists.firstWhere((p) => p.id == newId);
      expect(imported.name, '导入的播放单');

      final tracks = await service.findTracksForPlaylist(newId);
      expect(tracks.length, 1);
      expect(tracks.first.filePath, '/a.mp3');
    });

    test('REF-07-S5: 纯空白名（空格/制表符）→ 归默认名', () async {
      for (final blank in ['   ', '\\t', ' \\t ']) {
        final jsonStr = '{"name":"$blank","tracks":[]}';
        final newId = await service.importPlaylist(jsonStr);
        final playlists = await service.findAllPlaylists();
        final imported = playlists.firstWhere((p) => p.id == newId);
        expect(imported.name, '导入的播放单', reason: '纯空白名 $blank 应归默认名');
      }
    });

    test('REF-07-S6: trim 后非空名称原样保存（不做一般性 trim）', () async {
      const jsonStr = '{"name":"  My List  ","tracks":[]}';

      final newId = await service.importPlaylist(jsonStr);

      final playlists = await service.findAllPlaylists();
      final imported = playlists.firstWhere((p) => p.id == newId);
      expect(imported.name, '  My List  ', reason: 'trim 后非空的名称必须原样保存，不得修剪');
    });

    test('REF-07-S7: 空名播放单导出再导入 → 导入后为默认名', () async {
      final emptyId = await service.createPlaylist('');

      final exported = await service.exportPlaylist(emptyId);
      expect(exported, contains('"name": ""'));

      final reimportedId = await service.importPlaylist(exported);
      final playlists = await service.findAllPlaylists();
      final imported = playlists.firstWhere((p) => p.id == reimportedId);
      expect(imported.name, '导入的播放单');
    });

    test('REF-07-S8: createPlaylist 服务层行为保持（空名原样透传）', () async {
      final newId = await service.createPlaylist('');
      expect(newId, greaterThan(0));

      final playlists = await service.findAllPlaylists();
      final created = playlists.firstWhere((p) => p.id == newId);
      expect(created.name, '',
          reason: 'createPlaylist 不得新增 trim/默认名逻辑（本 REF 范围仅 importPlaylist）');
    });

    test('REF-07-INV1: importPlaylist 创建的播放单行 name 必非空（trim 后）', () async {
      for (final nameJson in [
        '{"name":"","tracks":[]}',
        '{"name":"   ","tracks":[]}',
        '{"tracks":[]}',
        '{"name":123,"tracks":[]}',
      ]) {
        final newId = await service.importPlaylist(nameJson);
        final playlists = await service.findAllPlaylists();
        final imported = playlists.firstWhere((p) => p.id == newId);
        expect(imported.name.trim().isNotEmpty, isTrue,
            reason: 'INV1: 导入创建的 name 必非空（trim 后），输入 $nameJson');
      }
    });

    test('REF-07-INV2: 结构异常 JSON 不抛 TypeError/NoSuchMethodError', () async {
      for (final bad in [
        '{"name":"","tracks":"not-an-array"}',
        '{"name":"","tracks":[123, "str"]}',
        '{"name":"","tracks":[{"filePath":123,"fileName":456}]}',
      ]) {
        final newId = await service.importPlaylist(bad);
        expect(newId, greaterThan(0),
            reason: 'INV2: 结构异常 JSON 不得抛 TypeError/NoSuchMethodError');
      }
    });
  });
}
