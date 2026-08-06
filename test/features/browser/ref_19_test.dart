// test/features/browser/ref_19_test.dart
// REF-19 → REF-06: sortFiles 顶层函数测试（DirectoryService 类已删除，
// 实例用例移除，仅保留 sortFiles 静态行为锚定）。

import 'package:flutter_test/flutter_test.dart';
import 'package:nas_audio_player/features/browser/domain/directory_service.dart';
import 'package:nas_audio_player/shared/models/nas_file.dart';

// ── Helpers ─────────────────────────────────────────────────────────────────

NasFile _dir(String name, {String? path, DateTime? modifiedAt}) {
  return NasFile(
    name: name,
    path: path ?? '/$name',
    isDirectory: true,
    modifiedAt: modifiedAt,
  );
}

NasFile _audio(String name, {String? path, DateTime? modifiedAt}) {
  return NasFile(
    name: name,
    path: path ?? '/$name',
    isDirectory: false,
    size: 1024,
    modifiedAt: modifiedAt,
    audioType: AudioFileType.music,
  );
}

void main() {
  group('REF-19: sortFiles', () {
    test('sortFiles: directories always appear before files', () {
      final files = [
        _audio('z_song.mp3', path: '/z_song.mp3'),
        _dir('aaa_dir'),
        _audio('a_song.mp3', path: '/a_song.mp3'),
      ];

      final sorted = sortFiles(files, SortOption.nameAsc);

      expect(sorted[0].isDirectory, isTrue);
      expect(sorted[0].name, 'aaa_dir');
      expect(sorted[1].name, 'a_song.mp3');
      expect(sorted[2].name, 'z_song.mp3');
    });

    test('sortFiles: modifiedDesc sorts newest first', () {
      final files = [
        _audio('old.mp3', path: '/old.mp3', modifiedAt: DateTime(2024, 1, 1)),
        _audio('new.mp3', path: '/new.mp3', modifiedAt: DateTime(2024, 6, 1)),
        _audio('mid.mp3', path: '/mid.mp3', modifiedAt: DateTime(2024, 3, 1)),
      ];

      final sorted = sortFiles(files, SortOption.modifiedDesc);

      expect(sorted[0].name, 'new.mp3');
      expect(sorted[1].name, 'mid.mp3');
      expect(sorted[2].name, 'old.mp3');
    });
  });
}
