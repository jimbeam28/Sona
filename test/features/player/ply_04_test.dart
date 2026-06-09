// test/features/player/ply_04_test.dart
// PLY-04: 锁屏/通知栏媒体控件 — automated test suite
//
// Unit tests (PLY-T24~T29): notification title extraction, headphone
// button click mapping, and cover-art display decisions.
//
// Tests focus on the pure-logic layer (HeadphoneAction, MediaAction,
// mapHeadphoneAction, extractTitleFromPath, TrackMetadata) which is
// fully testable without audio_service, platform channels, or native
// ID3 tag readers.

import 'package:flutter_test/flutter_test.dart';
import 'package:nas_audio_player/features/player/media_control_model.dart';

// ═════════════════════════════════════════════════════════════════════════════
// Unit tests — PLY-T24~T29
// ═════════════════════════════════════════════════════════════════════════════

void main() {
  // ── PLY-T24: Notification shows track name ──────────────────────────────────────
  //
  // The notification should display MediaItem.title, which is the filename
  // without its extension.  We test extractTitleFromPath against a variety
  // of real-world file paths.

  group('PLY-T24: Notification shows track name (extractTitleFromPath)', () {
    test('simple filename with extension', () {
      expect(
        extractTitleFromPath('/music/01 - Song.mp3'),
        equals('01 - Song'),
        reason: '应去掉 .mp3 扩展名，只保留文件名',
      );
    });

    test('filename without extension', () {
      expect(
        extractTitleFromPath('README'),
        equals('README'),
        reason: '无扩展名时返回原字符串',
      );
    });

    test('empty string', () {
      expect(
        extractTitleFromPath(''),
        equals(''),
        reason: '空字符串应返回空字符串',
      );
    });

    test('filename starting with dot (hidden file)', () {
      expect(
        extractTitleFromPath('/tmp/.hidden.mp3'),
        equals('.hidden'),
        reason: '隐藏文件应去掉 .mp3 扩展名',
      );
    });

    test('dotfile with no extension', () {
      expect(
        extractTitleFromPath('.gitignore'),
        equals('.gitignore'),
        reason: '以点开头的无扩展名文件应保持原样',
      );
    });

    test('double extension (tar.gz)', () {
      // lastIndexOf('.') finds the last dot, so "c.tar.gz" → "c.tar"
      expect(
        extractTitleFromPath('/backup/archive.tar.gz'),
        equals('archive.tar'),
        reason: '双重扩展名时只去掉最后一个扩展名',
      );
    });

    test('only filename, no directory path', () {
      expect(
        extractTitleFromPath('song.flac'),
        equals('song'),
        reason: '纯文件名应去掉扩展名',
      );
    });

    test('Chinese filename with extension', () {
      expect(
        extractTitleFromPath('/音乐/有声书/第一章.m4b'),
        equals('第一章'),
        reason: '中文文件名应正确去掉扩展名',
      );
    });

    test('Chinese filename without extension', () {
      expect(
        extractTitleFromPath('/音乐/有声书/序言'),
        equals('序言'),
        reason: '中文无扩展名文件应保持原样',
      );
    });

    test('filename with Japanese characters', () {
      expect(
        extractTitleFromPath('/music/僕の歌.mp3'),
        equals('僕の歌'),
        reason: '日文文件名应正确去掉扩展名',
      );
    });

    test('filename with Korean characters', () {
      expect(
        extractTitleFromPath('/music/노래.ogg'),
        equals('노래'),
        reason: '韩文文件名应正确去掉扩展名',
      );
    });

    test('filename with special characters', () {
      expect(
        extractTitleFromPath('/music/Artist - Title (Remix) [2024].opus'),
        equals('Artist - Title (Remix) [2024]'),
        reason: '包含括号和特殊字符的文件名应保留完整',
      );
    });

    test('filename with spaces only in name', () {
      expect(
        extractTitleFromPath('/music/   track   .wav'),
        equals('   track   '),
        reason: '文件名中的空格应保留',
      );
    });

    test('top-level file path (no directory)', () {
      expect(
        extractTitleFromPath('song.aac'),
        equals('song'),
        reason: '顶层路径应正确处理',
      );
    });
  });

  // ── PLY-T25: Headphone single click → togglePlayPause ───────────────────────────

  group('PLY-T25: Headphone single click toggles play/pause', () {
    test('singleClick maps to togglePlayPause', () {
      final result = mapHeadphoneAction(HeadphoneAction.singleClick);
      expect(
        result,
        equals(MediaAction.togglePlayPause),
        reason: '耳机单击应映射为播放/暂停切换 (PLY-T25)',
      );
    });

    test('singleClick maps to togglePlayPause — verification from all angles',
        () {
      // Verify that single click does NOT map to skip actions
      final result = mapHeadphoneAction(HeadphoneAction.singleClick);
      expect(result, isNot(equals(MediaAction.skipToNext)),
          reason: '单击不应映射为下一首');
      expect(result, isNot(equals(MediaAction.skipToPrevious)),
          reason: '单击不应映射为上一首');
    });
  });

  // ── PLY-T26: Headphone double click → skipToNext ────────────────────────────────

  group('PLY-T26: Headphone double click skips to next', () {
    test('doubleClick maps to skipToNext', () {
      final result = mapHeadphoneAction(HeadphoneAction.doubleClick);
      expect(
        result,
        equals(MediaAction.skipToNext),
        reason: '耳机双击应映射为跳转下一首 (PLY-T26)',
      );
    });

    test('doubleClick maps to skipToNext — verification from all angles', () {
      final result = mapHeadphoneAction(HeadphoneAction.doubleClick);
      expect(result, isNot(equals(MediaAction.togglePlayPause)),
          reason: '双击不应映射为播放/暂停切换');
      expect(result, isNot(equals(MediaAction.skipToPrevious)),
          reason: '双击不应映射为上一首');
    });
  });

  // ── PLY-T27: Headphone triple click → skipToPrevious ────────────────────────────

  group('PLY-T27: Headphone triple click skips to previous', () {
    test('tripleClick maps to skipToPrevious', () {
      final result = mapHeadphoneAction(HeadphoneAction.tripleClick);
      expect(
        result,
        equals(MediaAction.skipToPrevious),
        reason: '耳机三击应映射为跳转上一首 (PLY-T27)',
      );
    });

    test('tripleClick maps to skipToPrevious — verification from all angles',
        () {
      final result = mapHeadphoneAction(HeadphoneAction.tripleClick);
      expect(result, isNot(equals(MediaAction.togglePlayPause)),
          reason: '三击不应映射为播放/暂停切换');
      expect(result, isNot(equals(MediaAction.skipToNext)),
          reason: '三击不应映射为下一首');
    });
  });

  // ── HeadphoneAction completeness ────────────────────────────────────────────────

  group('HeadphoneAction enum completeness', () {
    test('all three click actions are defined', () {
      expect(HeadphoneAction.values.length, equals(3));
      expect(HeadphoneAction.values, contains(HeadphoneAction.singleClick));
      expect(HeadphoneAction.values, contains(HeadphoneAction.doubleClick));
      expect(HeadphoneAction.values, contains(HeadphoneAction.tripleClick));
    });
  });

  // ── MediaAction enum completeness ───────────────────────────────────────────────

  group('MediaAction enum completeness', () {
    test('all three media actions are defined', () {
      expect(MediaAction.values.length, equals(3));
      expect(MediaAction.values, contains(MediaAction.togglePlayPause));
      expect(MediaAction.values, contains(MediaAction.skipToNext));
      expect(MediaAction.values, contains(MediaAction.skipToPrevious));
    });
  });

  // ── PLY-T28: File has ID3 cover tag → notification shows cover ──────────────────

  group('PLY-T28: File with ID3 cover shows cover in notification', () {
    test('TrackMetadata with hasId3Cover=true shows cover', () {
      const metadata = TrackMetadata(
        filePath: '/music/album/01 - Track.mp3',
        hasId3Cover: true,
      );

      expect(metadata.showCover, isTrue,
          reason: '有 ID3 封面时通知栏应显示封面图 (PLY-T28)');
      expect(metadata.showDefaultIcon, isFalse, reason: '有封面时不应显示默认图标');
    });

    test('showCover and showDefaultIcon are mutually exclusive — cover case',
        () {
      const metadata = TrackMetadata(
        filePath: '/music/song.mp3',
        hasId3Cover: true,
      );

      // Exactly one of showCover / showDefaultIcon should be true.
      expect(metadata.showCover != metadata.showDefaultIcon, isTrue,
          reason: 'showCover 和 showDefaultIcon 应互斥');
      expect(metadata.showCover, isTrue);
    });

    test('title is still correctly extracted when cover exists', () {
      const metadata = TrackMetadata(
        filePath: '/music/First Track.flac',
        hasId3Cover: true,
      );

      expect(metadata.title, equals('First Track'),
          reason: '有封面时 title 仍应为去扩展名的文件名');
    });
  });

  // ── PLY-T29: File has no ID3 cover tag → notification shows default icon ───────

  group('PLY-T29: File without ID3 cover shows default app icon', () {
    test('TrackMetadata with hasId3Cover=false shows default icon', () {
      const metadata = TrackMetadata(
        filePath: '/music/02 - No Cover.mp3',
        hasId3Cover: false,
      );

      expect(metadata.showDefaultIcon, isTrue,
          reason: '无 ID3 封面时通知栏应显示默认应用图标 (PLY-T29)');
      expect(metadata.showCover, isFalse, reason: '无封面时不应显示封面图');
    });

    test('showCover and showDefaultIcon are mutually exclusive — no-cover case',
        () {
      const metadata = TrackMetadata(
        filePath: '/music/song.mp3',
        hasId3Cover: false,
      );

      expect(metadata.showCover != metadata.showDefaultIcon, isTrue,
          reason: 'showCover 和 showDefaultIcon 应互斥');
      expect(metadata.showDefaultIcon, isTrue);
    });

    test('title is still correctly extracted when cover is absent', () {
      const metadata = TrackMetadata(
        filePath: '/music/Second Track.ogg',
        hasId3Cover: false,
      );

      expect(metadata.title, equals('Second Track'),
          reason: '无封面时 title 仍应为去扩展名的文件名');
    });

    test('Chinese filename without cover', () {
      const metadata = TrackMetadata(
        filePath: '/音乐/有声书/第三章.m4b',
        hasId3Cover: false,
      );

      expect(metadata.title, equals('第三章'), reason: '中文文件名无封面时 title 应正确提取');
      expect(metadata.showDefaultIcon, isTrue, reason: '无封面时应显示默认图标');
    });
  });

  // ── TrackMetadata equality and immutability ─────────────────────────────────────

  group('TrackMetadata equality and immutability', () {
    test('identical values are equal', () {
      const a = TrackMetadata(
        filePath: '/music/song.mp3',
        hasId3Cover: true,
      );
      const b = TrackMetadata(
        filePath: '/music/song.mp3',
        hasId3Cover: true,
      );

      expect(a, equals(b), reason: '相同属性值的 TrackMetadata 应相等');
    });

    test('different filePath are not equal', () {
      const a = TrackMetadata(filePath: '/a.mp3', hasId3Cover: true);
      const b = TrackMetadata(filePath: '/b.mp3', hasId3Cover: true);

      expect(a, isNot(equals(b)), reason: '不同 filePath 的对象不应相等');
    });

    test('different hasId3Cover are not equal', () {
      const a = TrackMetadata(filePath: '/a.mp3', hasId3Cover: true);
      const b = TrackMetadata(filePath: '/a.mp3', hasId3Cover: false);

      expect(a, isNot(equals(b)), reason: '不同 hasId3Cover 的对象不应相等');
    });

    test('hashCode is consistent with equality', () {
      const a = TrackMetadata(filePath: '/x.mp3', hasId3Cover: false);
      const b = TrackMetadata(filePath: '/x.mp3', hasId3Cover: false);

      expect(a.hashCode, equals(b.hashCode), reason: '相等对象的 hashCode 应相同');
    });

    test('copyWith returns new instance with updated field', () {
      const original = TrackMetadata(
        filePath: '/music/song.mp3',
        hasId3Cover: false,
      );

      final updated = original.copyWith(hasId3Cover: true);

      expect(updated.hasId3Cover, isTrue);
      expect(updated.showCover, isTrue);
      expect(updated.filePath, equals('/music/song.mp3'));
      expect(original.hasId3Cover, isFalse, reason: '原对象不应改变（不可变）');
    });

    test('copyWith preserves unchanged fields', () {
      const original = TrackMetadata(
        filePath: '/music/song.mp3',
        hasId3Cover: true,
      );

      final updated = original.copyWith(filePath: '/other/track.flac');

      expect(updated.filePath, equals('/other/track.flac'));
      expect(updated.hasId3Cover, isTrue);
      expect(updated.title, equals('track'),
          reason: 'title 应随 filePath 更新自动变化');
    });
  });
}
