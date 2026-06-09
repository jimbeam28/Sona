// test/features/browser/brw_03_test.dart
// BRW-03: 音频文件过滤（格式图标区分）— automated test suite
//
// Unit tests  (BRW-T18~T22): classifyType audio detection, fromProps wiring
// Widget tests (BRW-T47, T49): progress bar visibility, icon distinction

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nas_audio_player/features/browser/widgets/file_list_item.dart';
import 'package:nas_audio_player/shared/models/nas_file.dart';

// ── Helper: build an audio NasFile for widget tests ───────────────────────────

NasFile _audioFile(String name,
    {String path = '/test.mp3',
    AudioFileType type = AudioFileType.music,
    int size = 1024}) {
  return NasFile(
    name: name,
    path: path,
    isDirectory: false,
    size: size,
    audioType: type,
  );
}

// ═════════════════════════════════════════════════════════════════════════════
// Unit tests — BRW-T18~T22
// ═════════════════════════════════════════════════════════════════════════════

void main() {
  group('BRW-T18~T22 unit tests', () {
    // ── BRW-T18: .m4b extension → audiobook ───────────────────────────────────

    test('BRW-T18: .m4b extension classified as audiobook', () {
      final result = NasFile.classifyType('book.m4b');
      expect(result, equals(AudioFileType.audiobook),
          reason: '.m4b 扩展名应归类为有声书');

      // Also verify through fromProps-style factory
      final file = NasFile.fromProps(
        href: '/books/book.m4b',
        props: {
          'displayname': 'book.m4b',
          'resourcetype': '',
          'getcontentlength': '1000',
          'getlastmodified': 'Mon, 01 Jan 2024 00:00:00 GMT',
        },
      );
      expect(file.audioType, equals(AudioFileType.audiobook),
          reason: 'fromProps 解析 .m4b 文件的 audioType 应为 audiobook');
    });

    // ── BRW-T19: Filename contains "有声书" keyword → audiobook ───────────────

    test('BRW-T19: "有声书" keyword in filename → audiobook', () {
      expect(
          NasFile.classifyType('第一章有声书.mp3'), equals(AudioFileType.audiobook),
          reason: '含"有声书"关键字的文件应归类为有声书');
      expect(NasFile.classifyType('有声书.flac'), equals(AudioFileType.audiobook),
          reason: '文件名为"有声书"开头的也应归类为有声书');
      expect(NasFile.classifyType('my_有声书_collection.aac'),
          equals(AudioFileType.audiobook),
          reason: '关键字在文件名中间也应识别');

      // Test arbitrary extension with the keyword
      final file = NasFile.fromProps(
        href: '/audio/第一章有声书.mp3',
        props: {
          'displayname': '第一章有声书.mp3',
          'resourcetype': '',
          'getcontentlength': '5000',
          'getlastmodified': 'Mon, 01 Jan 2024 00:00:00 GMT',
        },
      );
      expect(file.audioType, equals(AudioFileType.audiobook),
          reason: 'fromProps 解析含"有声书"文件应为 audiobook');
    });

    // ── BRW-T20: "audiobook" keyword (case insensitive) → audiobook ──────────

    test('BRW-T20: "audiobook" keyword case-insensitive → audiobook', () {
      // Lowercase
      expect(NasFile.classifyType('chapter1_audiobook.flac'),
          equals(AudioFileType.audiobook),
          reason: '含小写 "audiobook" 应归类为有声书');
      // Uppercase
      expect(NasFile.classifyType('Chapter1_AUDIOBOOK.flac'),
          equals(AudioFileType.audiobook),
          reason: '含大写 "AUDIOBOOK" 应归类为有声书（不区分大小写）');
      // Mixed case
      expect(NasFile.classifyType('my_AudioBook_vol1.mp3'),
          equals(AudioFileType.audiobook),
          reason: '含混合大小写 "AudioBook" 应归类为有声书');

      // Verify through fromProps
      final file = NasFile.fromProps(
        href: '/books/CHAPTER1_AUDIOBOOK.flac',
        props: {
          'displayname': 'CHAPTER1_AUDIOBOOK.flac',
          'resourcetype': '',
          'getcontentlength': '8000',
          'getlastmodified': 'Mon, 01 Jan 2024 00:00:00 GMT',
        },
      );
      expect(file.audioType, equals(AudioFileType.audiobook),
          reason: 'fromProps 大写的 AUDIOBOOK 也应识别');
    });

    // ── BRW-T21: Regular audio files → music ──────────────────────────────────

    test('BRW-T21: regular audio formats classified as music', () {
      const regularFormats = {
        'song.mp3': '.mp3',
        'song.flac': '.flac',
        'song.aac': '.aac',
        'song.m4a': '.m4a',
        'song.ogg': '.ogg',
        'song.opus': '.opus',
        'song.wav': '.wav',
      };

      for (final entry in regularFormats.entries) {
        expect(NasFile.isAudioFile(entry.key), isTrue,
            reason: '${entry.value} 应被识别为支持的音频格式');
        expect(NasFile.classifyType(entry.key), equals(AudioFileType.music),
            reason: '${entry.value} 普通音频应归类为 music');
      }

      // Verify fromProps wires audioType correctly for a music file
      final file = NasFile.fromProps(
        href: '/music/song.mp3',
        props: {
          'displayname': 'song.mp3',
          'resourcetype': '',
          'getcontentlength': '12345',
          'getlastmodified': 'Mon, 01 Jan 2024 00:00:00 GMT',
        },
      );
      expect(file.audioType, equals(AudioFileType.music),
          reason: 'fromProps 普通 .mp3 文件的 audioType 应为 music');
    });

    // ── BRW-T22: Directory → no audioType ─────────────────────────────────────

    test('BRW-T22: directory type NasFile has audioType null', () {
      // Directly constructed directory
      const dir = NasFile(
        name: 'music',
        path: '/music',
        isDirectory: true,
        audioType: null,
      );
      expect(dir.audioType, isNull, reason: '目录的 audioType 应为 null');
      expect(dir.isDirectory, isTrue, reason: '目录的 isDirectory 应为 true');

      // Constructed via fromProps
      final dirFromProps = NasFile.fromProps(
        href: '/music/',
        props: {
          'displayname': 'music',
          'resourcetype': '<collection/>',
        },
      );
      expect(dirFromProps.audioType, isNull,
          reason: 'fromProps 解析目录的 audioType 应为 null');
      expect(dirFromProps.isDirectory, isTrue, reason: '解析的条目应为目录');

      // A directory named like an audiobook should still NOT have audioType
      final audioBookDir = NasFile.fromProps(
        href: '/有声书/',
        props: {
          'displayname': '有声书',
          'resourcetype': '<collection/>',
        },
      );
      expect(audioBookDir.audioType, isNull,
          reason: '即使目录名叫"有声书"，audioType 也应为 null');
      expect(audioBookDir.isDirectory, isTrue);

      // A directory with .m4b-like name should not be classified as audio
      final m4bDir = NasFile.fromProps(
        href: '/books.m4b/',
        props: {
          'displayname': 'books.m4b',
          'resourcetype': '<collection/>',
        },
      );
      expect(m4bDir.audioType, isNull,
          reason: '目录即使名含 .m4b，audioType 也应为 null');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // Widget tests — BRW-T47, BRW-T49
  // ═══════════════════════════════════════════════════════════════════════════

  group('BRW-T47, BRW-T49 widget tests', () {
    // ── BRW-T47: Progress bar visibility ──────────────────────────────────────
    //
    // When progressPercentage is non-null a thin LinearProgressIndicator is
    // rendered below the tile.  When null no progress bar appears.

    testWidgets('BRW-T47: progress bar shown when progressPercentage is set',
        (WidgetTester tester) async {
      final file = _audioFile('song.mp3');

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AudioFileListTile(
              file: file,
              progressPercentage: 0.4,
            ),
          ),
        ),
      );

      // Progress bar should be rendered when percentage is non-null
      expect(find.byType(LinearProgressIndicator), findsOneWidget,
          reason: 'progressPercentage 非 null 时应显示进度条');

      // Verify the value was passed through
      final indicator = tester.widget<LinearProgressIndicator>(
          find.byType(LinearProgressIndicator));
      expect(indicator.value, equals(0.4),
          reason: '进度条 value 应等于传入的 progressPercentage');
    });

    testWidgets(
        'BRW-T47: no progress bar when progressPercentage is null (default)',
        (WidgetTester tester) async {
      final file = _audioFile('song.mp3');

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AudioFileListTile(file: file),
          ),
        ),
      );

      // No progress bar rendered when percentage is not provided (null)
      expect(find.byType(LinearProgressIndicator), findsNothing,
          reason: 'progressPercentage 为 null（默认值）时不应显示进度条');
    });

    // ── BRW-T49: Audiobook icon vs music icon distinction ─────────────────────

    testWidgets(
        'BRW-T49: audiobook shows headphones icon, music shows music note',
        (WidgetTester tester) async {
      final audiobookFile = _audioFile('book.m4b',
          path: '/books/book.m4b', type: AudioFileType.audiobook);
      final musicFile = _audioFile('song.mp3',
          path: '/music/song.mp3', type: AudioFileType.music);

      // Render audiobook tile
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AudioFileListTile(file: audiobookFile),
          ),
        ),
      );

      // Audiobook should use headphones icon
      expect(find.byIcon(Icons.headphones), findsOneWidget,
          reason: '有声书文件应显示 headphones 图标');

      // Render music tile
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AudioFileListTile(file: musicFile),
          ),
        ),
      );

      // Music should use music_note_outlined icon
      expect(find.byIcon(Icons.music_note_outlined), findsOneWidget,
          reason: '音乐文件应显示 music_note_outlined 图标');
    });

    testWidgets('BRW-T49: audiobook icon shown for file with "有声书" keyword',
        (WidgetTester tester) async {
      final file = _audioFile('第一章有声书.mp3',
          path: '/books/第一章有声书.mp3', type: AudioFileType.audiobook);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AudioFileListTile(file: file),
          ),
        ),
      );

      // Should show audiobook icon (headphones), not music icon
      expect(find.byIcon(Icons.headphones), findsOneWidget,
          reason: '含"有声书"关键字的文件应显示有声书图标');
      expect(find.byIcon(Icons.music_note_outlined), findsNothing,
          reason: '有声书文件不应显示普通音乐图标');
    });
  });
}
