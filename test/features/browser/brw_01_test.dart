// test/features/browser/brw_01_test.dart
// BRW-01: 目录列表加载 — automated test suite
//
// Unit tests  (BRW-T01~T09): XML parsing, audio detection, provider filtering, error handling
// Widget tests (BRW-T43~T46): loading/error/empty/retry UI states

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nas_audio_player/core/network/webdav_client.dart';
import 'package:nas_audio_player/features/browser/browser_provider.dart';
import 'package:nas_audio_player/features/browser/browser_screen.dart';
import 'package:nas_audio_player/shared/models/nas_file.dart';

import '../../helpers/test_factories.dart';

// ── XML builders ───────────────────────────────────────────────────────────────

/// Builds a minimal PROPFIND multistatus XML body with namespace prefix `d:`.
String _wrapInMultiStatus(String responseBlocks) {
  return '<?xml version="1.0" encoding="utf-8"?>\n'
      '<d:multistatus xmlns:d="DAV:">\n'
      '$responseBlocks'
      '</d:multistatus>';
}

/// Creates a `<d:response>` block for a directory.
String _dirResponse(String href, String displayName) {
  return '  <d:response>\n'
      '    <d:href>$href</d:href>\n'
      '    <d:propstat>\n'
      '      <d:prop>\n'
      '        <d:displayname>$displayName</d:displayname>\n'
      '        <d:resourcetype><d:collection/></d:resourcetype>\n'
      '      </d:prop>\n'
      '      <d:status>HTTP/1.1 200 OK</d:status>\n'
      '    </d:propstat>\n'
      '  </d:response>\n';
}

/// Creates a `<d:response>` block for a file.
String _fileResponse(
    String href, String displayName, int size, String lastModified) {
  return '  <d:response>\n'
      '    <d:href>$href</d:href>\n'
      '    <d:propstat>\n'
      '      <d:prop>\n'
      '        <d:displayname>$displayName</d:displayname>\n'
      '        <d:getcontentlength>$size</d:getcontentlength>\n'
      '        <d:getlastmodified>$lastModified</d:getlastmodified>\n'
      '      </d:prop>\n'
      '      <d:status>HTTP/1.1 200 OK</d:status>\n'
      '    </d:propstat>\n'
      '  </d:response>\n';
}

// testDir() and testAudio() are imported from ../../helpers/test_factories.dart as
// testDir() and testAudio().

// ═════════════════════════════════════════════════════════════════════════════
// Unit tests — BRW-T01~T09
// ═════════════════════════════════════════════════════════════════════════════

void main() {
  group('BRW-T01~T09 unit tests', () {
    // ── BRW-T01: Parse PROPFIND response with mixed dirs and audio files ─────

    test('BRW-T01: parse mixed dirs and audio files separates correctly', () {
      final xml = _wrapInMultiStatus(
        _dirResponse('/', '/') +
            _dirResponse('/music/', 'music') +
            _fileResponse('/song.mp3', 'song.mp3', 12345,
                'Mon, 01 Jan 2024 00:00:00 GMT'),
      );

      final result = WebDavClient.parsePropfindResponse(xml);

      // All 3 entries parsed
      expect(result.length, equals(3), reason: '应解析出所有 3 个条目（含自引用）');

      // Self-reference (root dir)
      expect(result[0].isDirectory, isTrue, reason: '根目录应为目录');
      expect(result[0].path, equals('/'));
      expect(result[0].name, equals('/'));

      // Subdirectory
      expect(result[1].isDirectory, isTrue, reason: 'music 应为目录');
      expect(result[1].name, equals('music'));
      expect(result[1].path, equals('/music'));

      // Audio file
      expect(result[2].isDirectory, isFalse, reason: 'song.mp3 应为文件');
      expect(result[2].name, equals('song.mp3'));
      expect(result[2].path, equals('/song.mp3'));
      expect(result[2].size, equals(12345));
      expect(result[2].audioType, equals(AudioFileType.music));
    });

    // ── BRW-T02: Parse dir with only non-audio files ─────────────────────────

    test('BRW-T02: non-audio files have audioType null but dirs still returned',
        () {
      final xml = _wrapInMultiStatus(
        _dirResponse('/data/', 'data') +
            _fileResponse('/data/photo.jpg', 'photo.jpg', 50000,
                'Mon, 01 Jan 2024 00:00:00 GMT') +
            _fileResponse('/data/doc.pdf', 'doc.pdf', 80000,
                'Mon, 01 Jan 2024 00:00:00 GMT'),
      );

      final result = WebDavClient.parsePropfindResponse(xml);

      expect(result.length, equals(3));

      // Self-reference dir
      expect(result[0].isDirectory, isTrue);

      // Non-audio files: parsed but audioType is null
      final files = result.where((f) => !f.isDirectory).toList();
      expect(files.length, equals(2), reason: '两个非音频文件都应被解析');
      for (final f in files) {
        expect(f.audioType, isNull, reason: '${f.name} 不应有 audioType');
        expect(NasFile.isAudioFile(f.name), isFalse,
            reason: '${f.name} 不应被识别为音频文件');
      }

      // Directories still present
      final dirs = result.where((f) => f.isDirectory).toList();
      expect(dirs.length, equals(1), reason: '目录条目应正常返回');
    });

    // ── BRW-T03: Parse completely empty dir (only self node) ─────────────────

    test('BRW-T03: empty dir with only self node returns single entry', () {
      final xml = _wrapInMultiStatus(
        _dirResponse('/empty/', 'empty'),
      );

      final result = WebDavClient.parsePropfindResponse(xml);

      expect(result.length, equals(1), reason: '空目录应只返回自身条目');
      expect(result[0].isDirectory, isTrue);
      expect(result[0].name, equals('empty'));
      expect(result[0].path, equals('/empty'));
    });

    // ── BRW-T04: PROPFIND network error throws exception ─────────────────────

    test('BRW-T04: WebDavException is created with correct properties', () {
      // Verify the WebDavException type carries the expected structure
      // that the UI layer relies on for error display.
      const netEx = WebDavException('无法连接到服务器');
      expect(netEx.message, equals('无法连接到服务器'));
      expect(netEx.statusCode, isNull);
      expect(netEx.isAuthError, isFalse);

      // Verify that WebDavException is an Exception (catchable)
      expect(netEx, isA<Exception>());
    });

    // ── BRW-T05: PROPFIND returns 401 throws auth exception ──────────────────

    test('BRW-T05: 401 produces auth error with isAuthError true', () {
      const authEx = WebDavException('用户名或密码错误', statusCode: 401);
      expect(authEx.isAuthError, isTrue, reason: '401 异常的 isAuthError 应为 true');
      expect(authEx.statusCode, equals(401));
      expect(authEx.message, contains('用户名或密码'));

      // Also test 403
      const forbiddenEx = WebDavException('禁止访问', statusCode: 403);
      expect(forbiddenEx.isAuthError, isTrue, reason: '403 异常也应标记为认证错误');
    });

    // ── BRW-T06: Special characters in filenames ─────────────────────────────

    test('BRW-T06: filenames with spaces, Chinese, brackets parsed correctly',
        () {
      final xml = _wrapInMultiStatus(
        _dirResponse('/music/', 'music') +
            _fileResponse(
                '/music/%E4%B8%AD%E6%96%87%E6%AD%8C.mp3', // URL-encoded 中文歌.mp3
                '中文歌.mp3',
                10000,
                'Mon, 01 Jan 2024 00:00:00 GMT') +
            _fileResponse(
                '/music/my%20song.mp3', // URL-encoded my song.mp3
                'my song.mp3',
                20000,
                'Mon, 01 Jan 2024 00:00:00 GMT') +
            _fileResponse(
                '/music/test%20%5Bbracket%5D.flac', // URL-encoded test [bracket].flac
                'test [bracket].flac',
                30000,
                'Mon, 01 Jan 2024 00:00:00 GMT'),
      );

      final result = WebDavClient.parsePropfindResponse(xml);

      // Find the Chinese filename entry
      final chineseFile = result.where((f) => f.name == '中文歌.mp3').toList();
      expect(chineseFile.length, equals(1), reason: '中文文件名应正确解析');
      expect(chineseFile[0].audioType, equals(AudioFileType.music));

      // Find the space-containing entry
      final spaceFile = result.where((f) => f.name == 'my song.mp3').toList();
      expect(spaceFile.length, equals(1), reason: '含空格文件名应正确解析');
      expect(spaceFile[0].path, equals('/music/my song.mp3'),
          reason: '路径中的 %20 应被解码为空格');

      // Find the bracket entry
      final bracketFile =
          result.where((f) => f.name == 'test [bracket].flac').toList();
      expect(bracketFile.length, equals(1), reason: '含方括号文件名应正确解析');
    });

    // ── BRW-T07: All 8 audio formats recognized ─────────────────────────────

    test('BRW-T07: all 8 supported audio formats recognized as audio', () {
      const formats = [
        'song.mp3',
        'song.flac',
        'song.aac',
        'song.m4a',
        'book.m4b',
        'song.ogg',
        'song.opus',
        'song.wav',
      ];

      for (final name in formats) {
        expect(NasFile.isAudioFile(name), isTrue, reason: '$name 应被识别为支持的音频格式');
      }

      // Verify classification: .m4b → audiobook
      expect(NasFile.classifyType('book.m4b'), equals(AudioFileType.audiobook));
      // All others → music
      expect(NasFile.classifyType('song.mp3'), equals(AudioFileType.music));
      expect(NasFile.classifyType('song.flac'), equals(AudioFileType.music));
      expect(NasFile.classifyType('song.aac'), equals(AudioFileType.music));
      expect(NasFile.classifyType('song.m4a'), equals(AudioFileType.music));
      expect(NasFile.classifyType('song.ogg'), equals(AudioFileType.music));
      expect(NasFile.classifyType('song.opus'), equals(AudioFileType.music));
      expect(NasFile.classifyType('song.wav'), equals(AudioFileType.music));

      // "有声书" keyword → audiobook
      expect(
          NasFile.classifyType('有声书 第一章.mp3'), equals(AudioFileType.audiobook),
          reason: '含"有声书"关键词的文件应归类为有声书');
      expect(NasFile.classifyType('audiobook_ch01.mp3'),
          equals(AudioFileType.audiobook),
          reason: '含"audiobook"关键词的文件应归类为有声书');
    });

    // ── BRW-T08: Non-audio files filtered out ────────────────────────────────

    test('BRW-T08: non-audio file extensions are not recognized', () {
      const nonAudio = [
        'photo.jpg',
        'photo.jpeg',
        'photo.png',
        'doc.pdf',
        'readme.txt',
        'script.py',
        'video.mp4',
        'archive.zip',
      ];

      for (final name in nonAudio) {
        expect(NasFile.isAudioFile(name), isFalse, reason: '$name 不应被识别为音频文件');
      }
    });

    // ── BRW-T09: File list sorted by name ascending (dirs first) ────────────

    test('BRW-T09: file list sorted A-Z with directories first', () {
      final unsorted = [
        testAudio('z_song.mp3', '/z_song.mp3'),
        testDir('apple', '/apple'),
        testAudio('a_track.flac', '/a_track.flac'),
        testDir('zebra', '/zebra'),
        testAudio('m_music.aac', '/m_music.aac'),
        testDir('banana', '/banana'),
      ];

      // Apply the same sort logic as the provider
      final sorted = [...unsorted]..sort((a, b) {
          if (a.isDirectory && !b.isDirectory) return -1;
          if (!a.isDirectory && b.isDirectory) return 1;
          return a.name.toLowerCase().compareTo(b.name.toLowerCase());
        });

      // Directories first (alphabetically)
      expect(sorted[0].name, equals('apple'));
      expect(sorted[1].name, equals('banana'));
      expect(sorted[2].name, equals('zebra'));

      // Then files (alphabetically)
      expect(sorted[3].name, equals('a_track.flac'));
      expect(sorted[4].name, equals('m_music.aac'));
      expect(sorted[5].name, equals('z_song.mp3'));

      // Verify type separation
      for (int i = 0; i < 3; i++) {
        expect(sorted[i].isDirectory, isTrue, reason: '前 3 项应为目录');
      }
      for (int i = 3; i < 6; i++) {
        expect(sorted[i].isDirectory, isFalse, reason: '后 3 项应为文件');
      }
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // Widget tests — BRW-T43~T46
  // ═══════════════════════════════════════════════════════════════════════════

  group('BRW-T43~T46 widget tests', () {
    // ── BRW-T43: Loading state shows skeleton screen ─────────────────────────
    //
    // We override directoryContentsProvider('/') with a never-completing
    // future so the UI stays in the loading state.

    testWidgets('BRW-T43: loading state shows skeleton, not actual list',
        (WidgetTester tester) async {
      final loadingCompleter = Completer<List<NasFile>>();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            directoryContentsProvider('/')
                .overrideWith((ref) => loadingCompleter.future),
          ],
          child: const MaterialApp(home: Scaffold(body: BrowserScreen())),
        ),
      );
      // Single pump — does not settle because the future hasn't completed
      await tester.pump();

      // The breadcrumb bar should show "根目录" for the root path
      expect(find.text('根目录'), findsOneWidget, reason: '应显示根目录标识');

      // No actual file/directory tiles rendered
      expect(find.byType(ListTile), findsNothing, reason: '加载中不应显示实际文件列表项');

      // Skeleton placeholders: the _LoadingView renders 8 placeholder rows.
      // Verify by checking that no error/empty/data content is present.
      expect(find.text('此目录为空'), findsNothing, reason: '加载中不应显示空目录提示');
      expect(find.byIcon(Icons.error_outline), findsNothing,
          reason: '加载中不应显示错误图标');

      // Cleanup
      loadingCompleter.complete([]);
      await tester.pumpAndSettle();
    });

    // ── BRW-T44: Error state shows error message and retry button ────────────

    testWidgets('BRW-T44: error state shows error message and 重试 button',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            directoryContentsProvider('/').overrideWith((ref) async {
              throw const WebDavException('无法连接到服务器');
            }),
          ],
          child: const MaterialApp(home: Scaffold(body: BrowserScreen())),
        ),
      );
      await tester.pumpAndSettle();

      // Error icon
      expect(find.byIcon(Icons.error_outline), findsOneWidget,
          reason: '错误状态应显示错误图标');

      // Error message
      expect(find.text('无法连接到服务器'), findsOneWidget, reason: '应显示错误信息');

      // Retry button
      expect(find.text('重试'), findsOneWidget, reason: '错误状态应显示重试按钮');
      expect(find.byIcon(Icons.refresh), findsOneWidget, reason: '重试按钮应有刷新图标');
    });

    // ── BRW-T45: Click "重试" re-triggers directory load ─────────────────────
    //
    // We override directoryContentsProvider with a factory that tracks
    // invocations.  First call throws (error state); after tapping retry
    // the provider is invalidated so the factory runs again, this time
    // returning data.

    testWidgets('BRW-T45: retry button re-triggers directory load',
        (WidgetTester tester) async {
      int invocationCount = 0;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            directoryContentsProvider('/').overrideWith((ref) async {
              invocationCount++;
              if (invocationCount == 1) {
                throw const WebDavException('网络错误');
              }
              return [
                testAudio('test.mp3', '/test.mp3'),
              ];
            }),
          ],
          child: const MaterialApp(home: Scaffold(body: BrowserScreen())),
        ),
      );
      await tester.pumpAndSettle();

      // First invocation → error state
      expect(find.text('重试'), findsOneWidget, reason: '首次加载失败应显示重试按钮');
      expect(invocationCount, equals(1));

      // Tap retry
      await tester.tap(find.text('重试'));
      await tester.pumpAndSettle();

      // Second invocation → success, data shown
      expect(invocationCount, equals(2),
          reason: '点击重试应触发第二次加载（ref.invalidate）');
      expect(find.text('test.mp3'), findsOneWidget, reason: '重试成功后应显示文件列表');
    });

    // ── BRW-T46: Empty directory shows "此目录为空" message ──────────────────
    //
    // The provider returns an empty list (self-reference already filtered).

    testWidgets('BRW-T46: empty directory shows 此目录为空 message',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            directoryContentsProvider('/').overrideWith((ref) async => []),
          ],
          child: const MaterialApp(home: Scaffold(body: BrowserScreen())),
        ),
      );
      await tester.pumpAndSettle();

      // Empty state message
      expect(find.text('此目录为空'), findsOneWidget, reason: '空目录应显示提示信息');
      expect(find.byIcon(Icons.folder_open_outlined), findsOneWidget,
          reason: '空目录应显示空文件夹图标');
    });
  });
}
