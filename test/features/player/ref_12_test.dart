// test/features/player/ref_12_test.dart
// REF-12: player/domain/media_control.dart — extracted pure functions
//
// Verifies that extractTitleFromPath, mapHeadphoneAction, and formatDuration
// work correctly as extracted domain functions.
//
// REF-12-T01: extractTitleFromPath various path formats
// REF-12-T02: mapHeadphoneAction 3 mappings
// REF-12-T03: formatDuration MM:SS and H:MM:SS

import 'package:flutter_test/flutter_test.dart';
import 'package:nas_audio_player/features/player/domain/media_control.dart';

void main() {
  // ── REF-12-T01: extractTitleFromPath various path formats ──────────────

  group('REF-12-T01: extractTitleFromPath', () {
    test('strips extension from simple path', () {
      expect(
        extractTitleFromPath('/music/01 - Song.mp3'),
        equals('01 - Song'),
      );
    });

    test('strips extension from Chinese filename', () {
      expect(
        extractTitleFromPath('/music/有声书.m4b'),
        equals('有声书'),
      );
    });

    test('no extension returns name as-is', () {
      expect(extractTitleFromPath('README'), equals('README'));
    });

    test('double extension strips only last segment', () {
      expect(extractTitleFromPath('/a/b/c.tar.gz'), equals('c.tar'));
    });

    test('empty string returns empty string', () {
      expect(extractTitleFromPath(''), equals(''));
    });

    test('hidden file with extension (dotIndex == 0) returns as-is', () {
      expect(extractTitleFromPath('/tmp/.hidden.mp3'), equals('.hidden'));
    });

    test('dotfile without extension returns as-is', () {
      expect(extractTitleFromPath('.gitignore'), equals('.gitignore'));
    });

    test('strips .flac extension', () {
      expect(extractTitleFromPath('song.flac'), equals('song'));
    });

    test('nested Chinese path', () {
      expect(
        extractTitleFromPath('/音乐/有声书/第一章.m4b'),
        equals('第一章'),
      );
    });

    test('nested path without extension', () {
      expect(
        extractTitleFromPath('/音乐/有声书/序言'),
        equals('序言'),
      );
    });

    test('Japanese characters', () {
      expect(
        extractTitleFromPath('/music/僕の歌.mp3'),
        equals('僕の歌'),
      );
    });

    test('Korean characters', () {
      expect(
        extractTitleFromPath('/music/노래.ogg'),
        equals('노래'),
      );
    });

    test('complex title with brackets', () {
      expect(
        extractTitleFromPath('/music/Artist - Title (Remix) [2024].opus'),
        equals('Artist - Title (Remix) [2024]'),
      );
    });

    test('preserves leading/trailing spaces', () {
      expect(
        extractTitleFromPath('/music/   track   .wav'),
        equals('   track   '),
      );
    });

    test('.aac extension', () {
      expect(extractTitleFromPath('song.aac'), equals('song'));
    });
  });

  // ── REF-12-T02: mapHeadphoneAction 3 mappings ─────────────────────────

  group('REF-12-T02: mapHeadphoneAction', () {
    test('single click → togglePlayPause', () {
      expect(
        mapHeadphoneAction(HeadphoneAction.singleClick),
        equals(MediaAction.togglePlayPause),
      );
    });

    test('double click → skipToNext', () {
      expect(
        mapHeadphoneAction(HeadphoneAction.doubleClick),
        equals(MediaAction.skipToNext),
      );
    });

    test('triple click → skipToPrevious', () {
      expect(
        mapHeadphoneAction(HeadphoneAction.tripleClick),
        equals(MediaAction.skipToPrevious),
      );
    });
  });

  // ── REF-12-T03: formatDuration MM:SS and H:MM:SS ──────────────────────

  group('REF-12-T03: formatDuration', () {
    test('zero duration → 00:00', () {
      expect(formatDuration(Duration.zero), equals('00:00'));
    });

    test('seconds only', () {
      expect(formatDuration(const Duration(seconds: 30)), equals('00:30'));
    });

    test('minutes and seconds', () {
      expect(
        formatDuration(const Duration(minutes: 5, seconds: 5)),
        equals('05:05'),
      );
    });

    test('59:59 boundary', () {
      expect(
        formatDuration(const Duration(minutes: 59, seconds: 59)),
        equals('59:59'),
      );
    });

    test('exactly 1 hour → 1:00:00', () {
      expect(formatDuration(const Duration(hours: 1)), equals('1:00:00'));
    });

    test('hours, minutes, seconds', () {
      expect(
        formatDuration(const Duration(hours: 1, minutes: 23, seconds: 45)),
        equals('1:23:45'),
      );
    });

    test('double-digit hours', () {
      expect(
        formatDuration(const Duration(hours: 10, minutes: 5, seconds: 5)),
        equals('10:05:05'),
      );
    });

    test('null → --:--', () {
      expect(formatDuration(null), equals('--:--'));
    });
  });
}
