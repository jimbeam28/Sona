// test/features/player/ply_01_test.dart
// PLY-01: 音频流式播放 — automated test suite
//
// Unit tests (PLY-T01~T07): auth header building, AudioSource construction,
// URL encoding, error handling, and format support.
//
// Tests focus on the logic layer (AudioSourceBuilder, PlayerLoadState,
// WebDavException) which is fully testable without AudioPlayer or
// platform channels.  AudioPlayer-dependent behaviours (actual loading,
// playing state transitions) are verified at the AudioSource / URI level.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:nas_audio_player/core/network/webdav_client.dart';
import 'package:nas_audio_player/core/services/audio_source_builder.dart';
import 'package:nas_audio_player/features/player/player_provider.dart';

// ── Helpers ────────────────────────────────────────────────────────────────────

/// Extracts the [UriAudioSource] from a generic [AudioSource].
/// Returns null when the source is not a [UriAudioSource].
UriAudioSource? _asUriSource(AudioSource source) {
  try {
    return source as UriAudioSource;
  } catch (_) {
    return null;
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Unit tests — PLY-T01~T07
// ═════════════════════════════════════════════════════════════════════════════

void main() {
  // ── PLY-T01: Build AudioSource with Basic Auth header ─────────────────────────

  group('PLY-T01: Auth header construction', () {
    test('buildAuthHeader returns correct base64 for simple credentials', () {
      final header = AudioSourceBuilder.buildAuthHeader(
        username: 'admin',
        password: 'secret',
      );

      // admin:secret base64 = YWRtaW46c2VjcmV0
      expect(header, equals('Basic YWRtaW46c2VjcmV0'),
          reason: '应返回正确的 Basic Auth 头值（base64(admin:secret)）');
      expect(header.startsWith('Basic '), isTrue,
          reason: 'Auth header 应以 "Basic " 开头');
    });

    test('buildAuthHeader with special characters in password', () {
      final header = AudioSourceBuilder.buildAuthHeader(
        username: 'user@nas',
        password: 'p@ss:word!',
      );

      // Verify it decodes correctly
      final encodedPart = header.substring(6); // strip 'Basic '
      final decoded = utf8.decode(base64.decode(encodedPart));
      expect(decoded, equals('user@nas:p@ss:word!'),
          reason: '解码后应恢复原始 username:password');
      expect(header.startsWith('Basic '), isTrue);
    });

    test('buildAuthHeader with empty credentials', () {
      final header = AudioSourceBuilder.buildAuthHeader(
        username: '',
        password: '',
      );

      expect(header.startsWith('Basic '), isTrue);

      // empty:empty base64 = Og==
      final encodedPart = header.substring(6);
      final decoded = utf8.decode(base64.decode(encodedPart));
      expect(decoded, equals(':'),
          reason: '空凭据应产生 ":" 格式');
    });

    test('buildAuthHeader with Chinese username and password', () {
      final header = AudioSourceBuilder.buildAuthHeader(
        username: '管理员',
        password: '密码123',
      );

      final encodedPart = header.substring(6);
      final decoded = utf8.decode(base64.decode(encodedPart));
      expect(decoded, equals('管理员:密码123'),
          reason: 'UTF-8 编码的中文凭据应正确编解码');
    });
  });

  // ── PLY-T02: Load WebDAV URL and build AudioSource ────────────────────────────

  group('PLY-T02: AudioSource construction', () {
    test('build creates UriAudioSource with correct URI and auth header', () {
      final source = AudioSourceBuilder.build(
        baseUrl: 'http://192.168.1.1:8080',
        filePath: '/music/song.mp3',
        username: 'admin',
        password: 'secret',
      );

      final uriSource = _asUriSource(source);
      expect(uriSource, isNotNull,
          reason: 'build() 应返回 UriAudioSource 实例');

      // Verify URI
      expect(uriSource!.uri.toString(),
          equals('http://192.168.1.1:8080/music/song.mp3'),
          reason: 'URL 应正确拼接 baseUrl + filePath');

      // Verify auth header in headers map
      expect(uriSource.headers, isNotNull);
      expect(
          uriSource.headers!['Authorization'],
          equals('Basic YWRtaW46c2VjcmV0'),
          reason: 'Authorization header 应为正确的 Basic Auth 值');
    });

    test('build creates AudioSource with non-default port', () {
      final source = AudioSourceBuilder.build(
        baseUrl: 'https://nas.local:8443',
        filePath: '/audiobooks/book.m4b',
        username: 'user',
        password: 'pass',
      );

      final uriSource = _asUriSource(source);
      expect(uriSource, isNotNull);

      expect(uriSource!.uri.toString(),
          equals('https://nas.local:8443/audiobooks/book.m4b'),
          reason: '非默认端口应保留在 URL 中');

      final authHeader = uriSource.headers!['Authorization'];
      // user:pass base64 = dXNlcjpwYXNz
      expect(authHeader, equals('Basic dXNlcjpwYXNz'));
    });

    test('buildWithBasePath preserves connection base path', () {
      final source = AudioSourceBuilder.buildWithBasePath(
        baseUrl: 'http://192.168.1.1:8080/dav/',
        filePath: '/music/song.mp3',
        username: 'admin',
        password: 'secret',
      );

      final uriSource = _asUriSource(source);
      expect(uriSource, isNotNull);

      // The base path /dav/ should be preserved, joined with /music/song.mp3
      final uriStr = uriSource!.uri.toString();
      expect(uriStr, contains('/dav/'),
          reason: 'buildWithBasePath 应保留连接 URL 的基础路径');
      expect(uriStr, contains('/music/song.mp3'),
          reason: '文件路径应拼接在基础路径之后');
    });

    test('AudioSource headers map contains only Authorization', () {
      final source = AudioSourceBuilder.build(
        baseUrl: 'http://192.168.1.1:8080',
        filePath: '/music/song.mp3',
        username: 'admin',
        password: 'secret',
      );

      final uriSource = _asUriSource(source);
      expect(uriSource, isNotNull);

      // The headers map should contain exactly the Authorization header
      expect(uriSource!.headers?.length, equals(1),
          reason: 'headers 应只包含一个 Authorization 条目');
      expect(uriSource.headers!.containsKey('Authorization'), isTrue);
    });
  });

  // ── PLY-T03: Network error handling ───────────────────────────────────────────

  group('PLY-T03: Error handling', () {
    test('WebDavException for network error has correct properties', () {
      const ex = WebDavException('无法连接到服务器');
      expect(ex.message, equals('无法连接到服务器'));
      expect(ex.statusCode, isNull);
      expect(ex.isAuthError, isFalse,
          reason: '无状态码的网络错误不应标记为认证错误');
      expect(ex, isA<Exception>(),
          reason: 'WebDavException 应是 Exception 的子类型');
    });

    test('PlayerLoadState.error creates correct error state', () {
      final state = PlayerLoadState.error('加载失败: 网络错误');
      expect(state.status, equals(PlayerLoadStatus.error));
      expect(state.errorMessage, equals('加载失败: 网络错误'));
      expect(state.isAuthError, isFalse,
          reason: '普通错误 isAuthError 应为 false');
    });

    test('PlayerLoadState idle / loading / ready states', () {
      // Idle
      expect(PlayerLoadState.idle.status, equals(PlayerLoadStatus.idle));
      expect(PlayerLoadState.idle.errorMessage, isNull);
      expect(PlayerLoadState.idle.isAuthError, isFalse);

      // Loading
      expect(PlayerLoadState.loading.status, equals(PlayerLoadStatus.loading));
      expect(PlayerLoadState.loading.errorMessage, isNull);

      // Ready
      expect(PlayerLoadState.ready.status, equals(PlayerLoadStatus.ready));
      expect(PlayerLoadState.ready.errorMessage, isNull);
      expect(PlayerLoadState.ready.isAuthError, isFalse);
    });

    test('PlayerLoadState equality', () {
      final a = PlayerLoadState.error('网络错误', isAuthError: false);
      final b = PlayerLoadState.error('网络错误', isAuthError: false);
      final c = PlayerLoadState.error('认证失败', isAuthError: true);

      expect(a, equals(b), reason: '相同属性值的状态应相等');
      expect(a, isNot(equals(c)),
          reason: '不同 errorMessage 的状态应不相等');
    });
  });

  // ── PLY-T04: MP3 format support ───────────────────────────────────────────────

  group('PLY-T04: MP3 format', () {
    test('AudioSource for mp3 file has correct URL', () {
      final source = AudioSourceBuilder.build(
        baseUrl: 'http://192.168.1.1:8080',
        filePath: '/music/song.mp3',
        username: 'admin',
        password: 'secret',
      );

      final uriSource = _asUriSource(source);
      expect(uriSource, isNotNull);

      final uri = uriSource!.uri.toString();
      expect(uri.endsWith('.mp3'), isTrue,
          reason: 'URL 应以 .mp3 结尾');
      expect(uri, equals('http://192.168.1.1:8080/music/song.mp3'),
          reason: 'MP3 文件 URL 应正确构建');
    });

    test('AudioSource for mp3 has auth headers', () {
      final source = AudioSourceBuilder.build(
        baseUrl: 'http://nas.local:8080',
        filePath: '/media/track.mp3',
        username: 'user',
        password: 'pass123',
      );

      final uriSource = _asUriSource(source);
      expect(uriSource, isNotNull);

      // Headers should contain Authorization
      expect(uriSource!.headers?.containsKey('Authorization'), isTrue,
          reason: 'MP3 AudioSource 应包含 Authorization header');
    });
  });

  // ── PLY-T05: FLAC format support ──────────────────────────────────────────────

  group('PLY-T05: FLAC format', () {
    test('AudioSource for flac file has correct URL', () {
      final source = AudioSourceBuilder.build(
        baseUrl: 'http://192.168.1.1:8080',
        filePath: '/music/hires.flac',
        username: 'admin',
        password: 'secret',
      );

      final uriSource = _asUriSource(source);
      expect(uriSource, isNotNull);

      final uri = uriSource!.uri.toString();
      expect(uri.endsWith('.flac'), isTrue,
          reason: 'URL 应以 .flac 结尾');
      expect(uri, equals('http://192.168.1.1:8080/music/hires.flac'),
          reason: 'FLAC 文件 URL 应正确构建');
    });

    test('AudioSource for flac has auth headers', () {
      final source = AudioSourceBuilder.build(
        baseUrl: 'http://nas.local:8080',
        filePath: '/music/audio.flac',
        username: 'user',
        password: 'pass123',
      );

      final uriSource = _asUriSource(source);
      expect(uriSource, isNotNull);

      expect(uriSource!.headers?.containsKey('Authorization'), isTrue,
          reason: 'FLAC AudioSource 应包含 Authorization header');
    });
  });

  // ── PLY-T06: 401 auth error handling ──────────────────────────────────────────

  group('PLY-T06: Auth error (401) handling', () {
    test('WebDavException with 401 has isAuthError true', () {
      const ex =
          WebDavException('用户名或密码错误', statusCode: 401);
      expect(ex.isAuthError, isTrue,
          reason: '状态码 401 的异常 isAuthError 应为 true');
      expect(ex.statusCode, equals(401));
      expect(ex.message, contains('用户名或密码'));
    });

    test('WebDavException with 403 has isAuthError true', () {
      const ex = WebDavException('禁止访问', statusCode: 403);
      expect(ex.isAuthError, isTrue,
          reason: '状态码 403 的异常也应标记为认证错误');
    });

    test('PlayerLoadState.error with isAuthError true', () {
      final state =
          PlayerLoadState.error('用户名或密码错误', isAuthError: true);
      expect(state.status, equals(PlayerLoadStatus.error));
      expect(state.isAuthError, isTrue,
          reason: '认证错误状态 isAuthError 应为 true');
      expect(state.errorMessage, contains('用户名或密码'));
    });

    test('PlayerLoadState.error for non-auth error does not flag auth', () {
      final state = PlayerLoadState.error('连接超时');
      expect(state.isAuthError, isFalse,
          reason: '非认证错误的 isAuthError 应为 false');
    });
  });

  // ── PLY-T07: URL encoding for special characters ──────────────────────────────

  group('PLY-T07: URL encoding for special characters', () {
    test('spaces in file path are percent-encoded', () {
      final uri = AudioSourceBuilder.buildUri(
        baseUrl: 'http://192.168.1.1:8080',
        filePath: '/music/my song.mp3',
      );

      expect(uri.toString(), equals('http://192.168.1.1:8080/music/my%20song.mp3'),
          reason: '空格应被编码为 %20');
      expect(uri.toString(), isNot(contains(' ')),
          reason: '最终 URL 不应包含未编码的空格');
    });

    test('Chinese characters in file path are percent-encoded', () {
      final uri = AudioSourceBuilder.buildUri(
        baseUrl: 'http://192.168.1.1:8080',
        filePath: '/music/中文歌.mp3',
      );

      // Chinese characters should be percent-encoded
      final uriStr = uri.toString();
      // 中文歌 in UTF-8: E4 B8 AD E6 96 87 E6 AD 8C
      expect(uriStr,
          equals('http://192.168.1.1:8080/music/%E4%B8%AD%E6%96%87%E6%AD%8C.mp3'),
          reason: '中文字符应被正确 percent-encode');
      expect(uriStr, isNot(contains('中文')),
          reason: '最终 URL 不应包含未编码的中文字符');
    });

    test('brackets in file path are percent-encoded', () {
      final uri = AudioSourceBuilder.buildUri(
        baseUrl: 'http://192.168.1.1:8080',
        filePath: '/music/test [bracket].mp3',
      );

      final uriStr = uri.toString();
      expect(uriStr, isNot(contains('[')),
          reason: '左方括号应被编码');
      expect(uriStr, isNot(contains(']')),
          reason: '右方括号应被编码');
      expect(uriStr, contains('%5B'),
          reason: '左方括号应编码为 %5B');
      expect(uriStr, contains('%5D'),
          reason: '右方括号应编码为 %5D');
    });

    test('mixed special characters in file path', () {
      final uri = AudioSourceBuilder.buildUri(
        baseUrl: 'http://nas.local:8080',
        filePath: '/music/01 - 中文歌曲 (feat. Artist).flac',
      );

      final uriStr = uri.toString();

      // Spaces and Chinese characters should be encoded
      expect(uriStr, isNot(contains(' ')), reason: '空格应被编码');
      expect(uriStr, isNot(contains('中文')), reason: '中文应被编码');

      // Parentheses are RFC 3986 "sub-delims" — Uri.encodeComponent
      // intentionally leaves them unencoded because they are valid in
      // path segments without percent-encoding.  This is correct per spec.
      // The URI contains the parentheses in their literal form.

      // But safe chars remain
      expect(uriStr, contains('.flac'), reason: '扩展名应保留原样');
      expect(uriStr, contains('01'), reason: '数字应保留原样');

      // The URI should be parseable
      final reparsed = Uri.parse(uriStr);
      expect(reparsed.scheme, equals('http'));
      expect(reparsed.host, equals('nas.local'));
    });

    test('baseUrl with trailing slash is normalised', () {
      final uri = AudioSourceBuilder.buildUri(
        baseUrl: 'http://192.168.1.1:8080/',
        filePath: '/music/song.mp3',
      );

      expect(uri.toString(), equals('http://192.168.1.1:8080/music/song.mp3'),
          reason: 'baseUrl 尾部斜杠应被去除，避免双斜杠');
    });

    test('filePath without leading slash is normalised', () {
      final uri = AudioSourceBuilder.buildUri(
        baseUrl: 'http://192.168.1.1:8080',
        filePath: 'music/song.mp3',
      );

      expect(uri.toString(), equals('http://192.168.1.1:8080/music/song.mp3'),
          reason: 'filePath 缺少前导斜杠时应自动添加');
    });
  });

  // ── TST-15: URL encoding boundary characters ──────────────────────────────────

  group('TST-15: URL encoding boundary characters', () {
    test('TST-T114: emoji in file path is percent-encoded', () {
      final uri = AudioSourceBuilder.buildUri(
        baseUrl: 'http://192.168.1.1:8080',
        filePath: '/music/song🎵.mp3',
      );
      final uriStr = uri.toString();
      // 🎵 = U+1F3B5, UTF-8: F0 9F 8E B5
      expect(uriStr, contains('%F0%9F%8E%B5'),
          reason: 'emoji 应被正确 UTF-8 编码');
      // Verify URI can be re-parsed
      final reparsed = Uri.parse(uriStr);
      expect(reparsed.scheme, equals('http'));
    });

    test('TST-T115: # in file path encoded as %23', () {
      final uri = AudioSourceBuilder.buildUri(
        baseUrl: 'http://192.168.1.1:8080',
        filePath: '/music/song#1.mp3',
      );
      final uriStr = uri.toString();
      expect(uriStr, contains('%23'),
          reason: '# 应编码为 %23 避免被解析为 fragment');
      expect(uriStr, isNot(contains('#')),
          reason: '最终 URL 不应包含未编码的 #');
    });

    test('TST-T116: ? in file path encoded as %3F', () {
      final uri = AudioSourceBuilder.buildUri(
        baseUrl: 'http://192.168.1.1:8080',
        filePath: '/music/whats that?.mp3',
      );
      final uriStr = uri.toString();
      expect(uriStr, contains('%3F'),
          reason: '? 应编码为 %3F 避免被解析为 query');
      expect(uriStr, isNot(contains('?')),
          reason: '最终 URL 不应包含未编码的 ?');
    });

    test('TST-T117: & + % in file path are each correctly encoded', () {
      final uri = AudioSourceBuilder.buildUri(
        baseUrl: 'http://192.168.1.1:8080',
        filePath: '/music/a&b+c%d.mp3',
      );
      final uriStr = uri.toString();
      // & → %26, + → %2B, % → %25
      expect(uriStr, contains('%26'), reason: '& 应编码为 %26');
      expect(uriStr, contains('%2B'), reason: '+ 应编码为 %2B');
      expect(uriStr, contains('%25'), reason: '% 应编码为 %25');
      // The %25d part: % → %25, then 'd' remains as-is
      expect(uriStr, contains('%25d'), reason: '%d 中的 % 应编码为 %25');
    });

    test('TST-T118: single and double quotes in file path are encoded', () {
      final uri = AudioSourceBuilder.buildUri(
        baseUrl: 'http://192.168.1.1:8080',
        filePath: '/music/it\'s "great".mp3',
      );
      final uriStr = uri.toString();
      // Double-quote is NOT a valid URI path character → must be encoded
      expect(uriStr, contains('%22'), reason: '双引号应编码为 %22');
      expect(uriStr, isNot(contains('"')), reason: 'URL 不应含未编码的双引号');
      // Single-quote (apostrophe) is an RFC 3986 sub-delims character and
      // Uri.encodeComponent intentionally leaves it unencoded in path segments.
      // This is correct per spec — only verify it does not crash or produce
      // invalid output.
      expect(uriStr, isNot(contains('%27')),
          reason: '单引号是合法 path 字符，Uri.encodeComponent 不会编码它');
      // URI must remain parseable
      final reparsed = Uri.parse(uriStr);
      expect(reparsed.scheme, equals('http'));
      expect(reparsed.path, contains("it's"));
    });
  });

  // ── Duration formatting ───────────────────────────────────────────────────────

  group('formatDuration helper', () {
    test('formats seconds as MM:SS', () {
      expect(formatDuration(const Duration(seconds: 0)), equals('00:00'));
      expect(formatDuration(const Duration(seconds: 30)), equals('00:30'));
      expect(formatDuration(const Duration(seconds: 90)), equals('01:30'));
      expect(formatDuration(const Duration(minutes: 5, seconds: 5)),
          equals('05:05'));
    });

    test('formats hours as H:MM:SS', () {
      expect(formatDuration(const Duration(hours: 1)), equals('1:00:00'));
      expect(formatDuration(const Duration(hours: 1, minutes: 23, seconds: 45)),
          equals('1:23:45'));
      expect(formatDuration(const Duration(hours: 10, minutes: 5, seconds: 5)),
          equals('10:05:05'));
    });

    test('formats null as placeholder', () {
      expect(formatDuration(null), equals('--:--'));
    });
  });
}
