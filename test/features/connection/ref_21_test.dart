// test/features/connection/ref_21_test.dart
// REF-21: Unit tests for lib/features/connection/domain/connection_validator.dart
//
// Pure Dart tests — no Flutter dependency.

import 'package:flutter_test/flutter_test.dart';
import 'package:nas_audio_player/features/connection/domain/connection_validator.dart';

void main() {
  // ═══════════════════════════════════════════════════════════════════════════
  // REF-21-T01: URL validation
  // ═══════════════════════════════════════════════════════════════════════════

  group('REF-21-T01: validateUrl', () {
    test('null value returns required error', () {
      expect(validateUrl(null), equals('请输入服务器地址'));
    });

    test('empty string returns required error', () {
      expect(validateUrl(''), equals('请输入服务器地址'));
    });

    test('whitespace-only string returns required error', () {
      expect(validateUrl('   '), equals('请输入服务器地址'));
    });

    test('invalid format returns format error', () {
      // Just a bare word without dots or scheme is not a valid URL.
      // "not-a-url" normalises to "http://not-a-url:5005" which IS a valid
      // URL per isValidWebDavUrl (has scheme + non-empty host).
      // Use something truly unparseable instead.
      expect(validateUrl('://bad'), isNotNull,
          reason: '无效格式应返回错误');
    });

    test('valid http URL with port passes', () {
      expect(validateUrl('http://192.168.1.100:5005'), isNull,
          reason: '带端口的有效 http 地址应通过验证');
    });

    test('valid https URL passes', () {
      expect(validateUrl('https://nas.example.com'), isNull,
          reason: '有效 https 地址应通过验证');
    });

    test('bare IP address passes (auto-prepends http://)', () {
      expect(validateUrl('192.168.1.100'), isNull,
          reason: '裸 IP 应自动补全 http:// 后通过验证');
    });

    test('DDNS hostname passes', () {
      expect(validateUrl('my-nas.ddns.net'), isNull,
          reason: 'DDNS 域名应通过验证');
    });

    test('URL with port passes', () {
      expect(validateUrl('http://nas.local:8080'), isNull,
          reason: '带自定义端口的有效地址应通过验证');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // REF-21-T02: Username / password required validation
  // ═══════════════════════════════════════════════════════════════════════════

  group('REF-21-T02: validateRequired', () {
    test('null value returns error with field name', () {
      expect(validateRequired(null, '用户名'), equals('请输入用户名'));
    });

    test('empty string returns error with field name', () {
      expect(validateRequired('', '密码'), equals('请输入密码'));
    });

    test('whitespace-only returns error with field name', () {
      expect(validateRequired('   ', '用户名'), equals('请输入用户名'));
    });

    test('non-empty value passes (null = no error)', () {
      expect(validateRequired('admin', '用户名'), isNull);
    });

    test('value with leading/trailing spaces passes', () {
      expect(validateRequired(' mypass ', '密码'), isNull,
          reason: '有内容的值应通过验证（空格不影响）');
    });

    test('error message uses the provided field name', () {
      expect(validateRequired('', '自定义字段'), equals('请输入自定义字段'));
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // REF-21-T03: basePath default value and format validation
  // ═══════════════════════════════════════════════════════════════════════════

  group('REF-21-T03: validateBasePath', () {
    test('null value defaults to /', () {
      final result = validateBasePath(null);
      expect(result.normalised, equals('/'));
      expect(result.isValid, isTrue);
    });

    test('empty string defaults to /', () {
      final result = validateBasePath('');
      expect(result.normalised, equals('/'));
      expect(result.isValid, isTrue);
    });

    test('whitespace-only defaults to /', () {
      final result = validateBasePath('   ');
      expect(result.normalised, equals('/'));
      expect(result.isValid, isTrue);
    });

    test('valid path starting with / passes', () {
      final result = validateBasePath('/dav/music');
      expect(result.normalised, equals('/dav/music'));
      expect(result.isValid, isTrue);
    });

    test('root path / passes', () {
      final result = validateBasePath('/');
      expect(result.normalised, equals('/'));
      expect(result.isValid, isTrue);
    });

    test('path without leading / gets auto-prepended with error', () {
      final result = validateBasePath('dav/music');
      expect(result.normalised, equals('/dav/music'));
      expect(result.error, equals('基础路径必须以 / 开头'));
    });

    test('path with .. traversal is rejected', () {
      final result = validateBasePath('/dav/../etc');
      expect(result.normalised, equals('/dav/../etc'));
      expect(result.error, equals('基础路径不能包含 ..'));
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // REF-21-T04: DDNS hostname validation
  // ═══════════════════════════════════════════════════════════════════════════

  group('REF-21-T04: validateDdnsHostname', () {
    test('null value returns error', () {
      expect(validateDdnsHostname(null), isNotNull);
    });

    test('empty string returns error', () {
      expect(validateDdnsHostname(''), isNotNull);
    });

    test('whitespace-only returns error', () {
      expect(validateDdnsHostname('   '), isNotNull);
    });

    test('simple hostname passes', () {
      expect(validateDdnsHostname('nas'), isNull);
    });

    test('DDNS domain passes', () {
      expect(validateDdnsHostname('my-nas.ddns.net'), isNull);
    });

    test('multi-level domain passes', () {
      expect(validateDdnsHostname('music.home.example.com'), isNull);
    });

    test('IPv4 address passes', () {
      expect(validateDdnsHostname('192.168.1.100'), isNull);
    });

    test('IPv4 with leading zeros passes', () {
      expect(validateDdnsHostname('10.0.0.1'), isNull);
    });

    test('hostname with http:// prefix is rejected', () {
      expect(validateDdnsHostname('http://nas.example.com'), isNotNull,
          reason: '不应包含协议前缀');
    });

    test('hostname with https:// prefix is rejected', () {
      expect(validateDdnsHostname('https://nas.example.com'), isNotNull,
          reason: '不应包含协议前缀');
    });

    test('hostname with spaces is rejected', () {
      expect(validateDdnsHostname('nas home'), isNotNull,
          reason: '不应包含空格');
    });

    test('hostname starting with hyphen is rejected', () {
      expect(validateDdnsHostname('-nas.example.com'), isNotNull,
          reason: '标签不能以连字符开头');
    });

    test('hostname ending with hyphen is rejected', () {
      expect(validateDdnsHostname('nas-.example.com'), isNotNull,
          reason: '标签不能以连字符结尾');
    });

    test('empty label (consecutive dots) is rejected', () {
      expect(validateDdnsHostname('nas..com'), isNotNull,
          reason: '连续的点号产生空标签，应被拒绝');
    });

    test('overly long hostname is rejected', () {
      final longHostname = '${'a' * 250}.com';
      expect(validateDdnsHostname(longHostname), isNotNull,
          reason: '超过 253 个字符的域名应被拒绝');
    });

    test('valid edge-case: single-char labels', () {
      expect(validateDdnsHostname('a.b.c'), isNull);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // BasePathResult helper class
  // ═══════════════════════════════════════════════════════════════════════════

  group('BasePathResult', () {
    test('isValid returns true when error is null', () {
      const result = BasePathResult(normalised: '/');
      expect(result.isValid, isTrue);
    });

    test('isValid returns false when error is present', () {
      const result = BasePathResult(normalised: '/foo', error: 'bad');
      expect(result.isValid, isFalse);
    });

    test('toString includes normalised and error', () {
      const result = BasePathResult(normalised: '/foo', error: 'bad');
      expect(result.toString(), contains('/foo'));
      expect(result.toString(), contains('bad'));
    });
  });
}
