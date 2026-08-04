// test/features/playlist/o8_to_nas_file_audio_type_test.dart
// cr-20260804-1922 §5 O8: PlaylistTrack.toNasFile 的 audioType 同源残留
//（BUG-15 同根）
//
// BUG-15 只修了浏览链路：NasFile.fromProps 的 audioType 改由 href（真实路径）
// 末段判定，displayname 仅作显示标签。播放单链路 toNasFile() 仍用 fileName
//（显示名）派生 audioType——播放单导入曲目的显示名可能无扩展名或与真实文件
// 扩展名不一致 → 分类失真。
//
// 本文件验证：
//   S1 fileName 无扩展名、filePath 有 .mp3 → audioType 仍正确（核心 RED）
//   S2 fileName 扩展名与 filePath 不一致 → 按 filePath 末段判定
//   S3 两者一致 → 行为不变（否定断言，PLY-T53/T54 语义保持）
//   S4 filePath 也无扩展名 → audioType=null 兜底，与浏览链路一致
//   S5 显示字段不受影响：name 仍取 fileName，path 取 filePath（否定断言）
//   S6 与浏览链路单源一致：同路径下 toNasFile 与 fromProps 分类结果一致
//   S7 分类只看路径末段：目录段含 audiobook 关键词不影响判定（BUG-15 边界裁决）

import 'package:flutter_test/flutter_test.dart';
import 'package:nas_audio_player/shared/models/nas_file.dart';
import 'package:nas_audio_player/shared/models/playlist.dart';

PlaylistTrack _track({
  required String filePath,
  required String fileName,
}) {
  return PlaylistTrack(
    playlistId: 1,
    filePath: filePath,
    fileName: fileName,
    addedAt: DateTime.now(),
  );
}

void main() {
  group('O8 — toNasFile audioType 由 filePath（真实路径）派生', () {
    // ── S1 核心：显示名无扩展名，真实路径有 ────────────────────────────────

    test('S1 fileName 无扩展名 + filePath 有 .mp3 → music', () {
      final nasFile = _track(
        filePath: '/music/song.mp3',
        fileName: 'song', // NAS/导入曲目显示名去扩展名
      ).toNasFile();
      expect(nasFile.audioType, AudioFileType.music,
          reason: 'audioType 应按真实路径末段 song.mp3 判定，'
              '而非显示名 song');
    });

    test('S1b fileName 无扩展名 + filePath 有 .m4b → audiobook', () {
      final nasFile = _track(
        filePath: '/books/book.m4b',
        fileName: 'My Book',
      ).toNasFile();
      expect(nasFile.audioType, AudioFileType.audiobook);
    });

    // ── S2 扩展名不一致：以 filePath 为准 ──────────────────────────────────

    test('S2 fileName="第一章"、filePath=".../x.flac" → music（按 filePath）', () {
      final nasFile = _track(
        filePath: '/audiobooks/x.flac',
        fileName: '第一章',
      ).toNasFile();
      expect(nasFile.audioType, AudioFileType.music,
          reason: 'flac 为 music；判定依据是 filePath 末段，不是 fileName');
    });

    test('S2b fileName="x.m4b"、filePath=".../y.mp3" → music（按 filePath）', () {
      final nasFile = _track(
        filePath: '/music/y.mp3',
        fileName: 'x.m4b', // 显示名扩展名与真实文件不一致
      ).toNasFile();
      expect(nasFile.audioType, AudioFileType.music,
          reason: '真实文件是 .mp3 → music；不得按显示名 .m4b 误判 audiobook');
    });

    // ── S3 两者一致 → 行为不变（否定断言） ─────────────────────────────────

    test('S3 fileName/filePath 扩展名一致 → 分类结果与修复前相同', () {
      final mp3 = _track(
        filePath: '/music/song.mp3',
        fileName: 'song.mp3',
      ).toNasFile();
      expect(mp3.audioType, AudioFileType.music);

      final m4b = _track(
        filePath: '/books/book.m4b',
        fileName: 'book.m4b',
      ).toNasFile();
      expect(m4b.audioType, AudioFileType.audiobook);
    });

    // ── S4 filePath 也无扩展名 → null 兜底（与浏览链路一致） ───────────────

    test('S4 filePath 无扩展名 → audioType=null 安全降级', () {
      final nasFile = _track(
        filePath: '/music/song',
        fileName: 'song',
      ).toNasFile();
      expect(nasFile.audioType, isNull, reason: '真实路径无受支持扩展名 → 不分类，不误判');
    });

    test('S4b filePath 为空 → audioType=null 不抛错', () {
      final nasFile = _track(filePath: '', fileName: '').toNasFile();
      expect(nasFile.audioType, isNull);
    });

    // ── S5 显示字段不受影响（否定断言） ────────────────────────────────────

    test('S5 name 仍取 fileName，path 取 filePath，isDirectory=false', () {
      final nasFile = _track(
        filePath: '/music/song.mp3',
        fileName: '歌曲名（无扩展名）',
      ).toNasFile();
      expect(nasFile.name, '歌曲名（无扩展名）', reason: '显示名仍来自 fileName，不得改用路径末段');
      expect(nasFile.path, '/music/song.mp3');
      expect(nasFile.isDirectory, isFalse);
    });

    // ── S6 与浏览链路单源一致（同路径同分类） ──────────────────────────────

    test('S6 同路径下 toNasFile 与 fromProps 分类一致', () {
      const paths = [
        '/music/song.mp3',
        '/books/book.m4b',
        '/audiobooks/x.flac',
        '/music/song', // 无扩展名
      ];
      for (final path in paths) {
        final fromPlaylist =
            _track(filePath: path, fileName: '无扩展名显示名').toNasFile();
        final fromBrowse = NasFile.fromProps(
          href: path,
          props: const {'resourcetype': ''}, // 非目录
        );
        expect(fromPlaylist.audioType, fromBrowse.audioType,
            reason: '播放单链路与浏览链路必须单源一致: $path');
      }
    });

    // ── S7 分类只看路径末段（BUG-15 边界裁决） ─────────────────────────────

    test('S7 目录段含 audiobook 关键词不影响分类', () {
      final nasFile = _track(
        filePath: '/audiobooks/song.mp3',
        fileName: 'song.mp3',
      ).toNasFile();
      expect(nasFile.audioType, AudioFileType.music,
          reason: '关键词匹配只作用于路径末段文件名，与浏览链路一致');
    });
  });
}
