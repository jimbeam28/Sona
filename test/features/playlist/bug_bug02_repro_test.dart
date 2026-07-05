// test/features/playlist/bug_bug02_repro_test.dart
// BUG-02 (cr-B2): addTracksToPlaylist 缺内存内去重
//
// 复现：同一文件路径在输入 List 中重复出现两次时，两次 trackExists 都
// 返回 false（DB 还没写入），结果两次都加入 tracks 列表，最后一次性
// 插入 → 播放单中出现重复曲目。修复前必须 FAIL；修复后必须 PASS。

import 'package:flutter_test/flutter_test.dart';
import 'package:nas_audio_player/core/database/dao/playlist_dao.dart';
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

  test('bug_BUG-02: 同一文件在输入中出现两次应只插入一次', () async {
    final db = await openTestDatabase(TestSchema.playlist);
    addTearDown(() => db.close());

    final service = PlaylistService();
    final playlistId = await service.createPlaylist('test');

    // 同一个文件路径出现两次（模拟 UI 快速双击或批量勾选的去重失败场景）
    final sameFile = _f('a.mp3');
    await service.addTracksToPlaylist(playlistId, [sameFile, sameFile]);

    final tracks = await service.findTracksForPlaylist(playlistId);
    expect(tracks.length, 1,
        reason: '同一文件路径在同一批输入中重复出现时，应被内存去重'
            '—— 只保留一条记录，跟踪 filePath 不应在 DB 出现两次');
  });

  test('bug_BUG-02: 三次相同文件 + 一个新文件 → 2 条不重复记录', () async {
    final db = await openTestDatabase(TestSchema.playlist);
    addTearDown(() => db.close());

    final service = PlaylistService();
    final playlistId = await service.createPlaylist('test');

    final dup = _f('a.mp3');
    final other = _f('b.mp3');
    await service.addTracksToPlaylist(playlistId, [dup, dup, dup, other]);

    final tracks = await service.findTracksForPlaylist(playlistId);
    expect(tracks.length, 2,
        reason: '重复 3 次的 a.mp3 应只 1 条，b.mp3 1 条，共 2 条');
    expect(tracks.where((t) => t.filePath == '/music/a.mp3').length, 1);
    expect(tracks.where((t) => t.filePath == '/music/b.mp3').length, 1);
  });
}