// test/features/connection/con_08_test.dart
// CON-08: 连接表单支持 DDNS 域名提示 — automated test suite
//
// Unit tests (CON-T35~T37): URL validation with domain names.

import 'package:flutter_test/flutter_test.dart';
import 'package:nas_audio_player/core/network/webdav_client.dart';

void main() {
  group('CON-T35~T37 DDNS domain validation', () {
    // ── CON-T35: DDNS domain with scheme ──────────────────────────────────

    test('test_CON_T35_ddnsDomain_isValid', () {
      const url = 'http://nas.example.com';
      final normalised = normaliseWebDavUrl(url);
      expect(normalised, equals('http://nas.example.com'),
          reason: '带 http:// 前缀的域名应保持不变');
      expect(isValidWebDavUrl(normalised), isTrue,
          reason: 'DDNS 域名应通过 URL 校验');
    });

    // ── CON-T36: DDNS domain with port ────────────────────────────────────

    test('test_CON_T36_ddnsDomainWithPort_isValid', () {
      const url = 'http://nas.example.com:5005';
      final normalised = normaliseWebDavUrl(url);
      expect(normalised, equals('http://nas.example.com:5005'),
          reason: '带端口的域名应保持不变');
      expect(isValidWebDavUrl(normalised), isTrue,
          reason: '带端口的 DDNS 域名应通过 URL 校验');
    });

    // ── CON-T37: bare domain, auto-prepend http:// ────────────────────────

    test('test_CON_T37_bareDomain_autoPrependsHttp', () {
      const url = 'nas.example.com';
      final normalised = normaliseWebDavUrl(url);
      expect(normalised, equals('http://nas.example.com'),
          reason: '裸域名应自动补全 http:// 前缀');
      expect(isValidWebDavUrl(normalised), isTrue,
          reason: '补全 http:// 后的域名应通过 URL 校验');
    });

    // Extra: bare domain with port
    test('test_CON_T37b_bareDomainWithPort_autoPrependsHttp', () {
      const url = 'nas.example.com:5005';
      final normalised = normaliseWebDavUrl(url);
      expect(normalised, equals('http://nas.example.com:5005'),
          reason: '带端口的裸域名应自动补全 http://');
      expect(isValidWebDavUrl(normalised), isTrue,
          reason: '补全后的域名应通过校验');
    });
  });
}
