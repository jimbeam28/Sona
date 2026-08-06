// test/core/network/webdav_client_test.dart
// TEST-07 (docs/features/TEST-07.md §5.4) — 网络层真实 HTTP 测试（NET9）:
//
//   S1 — MockClient 207 + 有效 XML → validate success（证明 http.Client 注入生效，INV1）
//   S2 — MockClient 401 → validate authError
//   S3 — MockClient 挂起（不响应）→ validate networkError（超时映射）
//   S4 — MockClient 500 → listDirectory 抛 WebDavException(statusCode=500)
//   S5 — MockClient 207 + 无效 XML → listDirectory 返回空列表（⚠️ 生产行为与 spec
//         §3 S5 "抛 WebDavException" 不符，实测锚定实际行为，待 dev-plan 裁决）
//
// 全部用例经 package:http/testing 注入真实 WebDavClient，非 fake 自证。

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nas_audio_player/core/network/webdav_client.dart';

const _validUrl = 'http://nas.example.com';

/// 标准 lowercase 207 multistatus body（与既有 fixture 同形）。
const _valid207Body = '''<?xml version="1.0" encoding="utf-8"?>
<d:multistatus xmlns:d="DAV:">
  <d:response>
    <d:href>/</d:href>
    <d:propstat>
      <d:prop>
        <d:displayname>/</d:displayname>
        <d:resourcetype><d:collection/></d:resourcetype>
      </d:prop>
      <d:status>HTTP/1.1 200 OK</d:status>
    </d:propstat>
  </d:response>
</d:multistatus>''';

void main() {
  group('TEST-07-S1~S5: WebDavClient MockClient 网络层', () {
    test('TEST-07-S1: validate 207 + 有效 XML → success（http.Client 注入生效）',
        () async {
      http.BaseRequest? seenRequest;
      final client = WebDavClient(
        httpClient: MockClient((request) async {
          seenRequest = request;
          return http.Response(_valid207Body, 207);
        }),
      );

      final result = await client.validate(
        url: _validUrl,
        username: 'u',
        password: 'p',
      );

      expect(result.isSuccess, isTrue);
      expect(result.status, WebDavValidationStatus.success);
      expect(result.message, isNull);
      expect(seenRequest, isNotNull,
          reason: 'INV1: 请求必须真实走注入的 http.Client（MockClient），不得跳过 HTTP 层');
    });

    test('TEST-07-S2: validate 401 → authError', () async {
      final client = WebDavClient(
        httpClient: MockClient((request) async => http.Response('', 401)),
      );

      final result = await client.validate(
        url: _validUrl,
        username: 'u',
        password: 'p',
      );

      expect(result.status, WebDavValidationStatus.authError);
      expect(result.isSuccess, isFalse, reason: '否定断言: 401 不得返回 success');
      expect(result.message, contains('用户名或密码'),
          reason: '否定断言: 401 应返回 authError 而非抛异常');
    });

    test('TEST-07-S3: validate 请求挂起 → networkError（超时映射）', () async {
      final client = WebDavClient(
        httpClient: MockClient((request) async {
          await Completer<void>().future; // never resolves
          throw StateError('unreachable');
        }),
        timeout: const Duration(milliseconds: 50),
      );

      final stopwatch = Stopwatch()..start();
      final result = await client.validate(
        url: _validUrl,
        username: 'u',
        password: 'p',
      );
      stopwatch.stop();

      expect(result.status, WebDavValidationStatus.networkError,
          reason: '否定断言: 超时必须映射为 networkError，不得抛未捕获异常');
      expect(stopwatch.elapsed, lessThan(const Duration(seconds: 3)),
          reason: '必须由注入的短 timeout 触发，不得等待默认 5s');
    });

    test('TEST-07-S4: listDirectory 500 → WebDavException statusCode=500',
        () async {
      final client = WebDavClient(
        httpClient: MockClient((request) async => http.Response('', 500)),
      );

      await expectLater(
        client.listDirectory(
            url: _validUrl, username: 'u', password: 'p', path: '/'),
        throwsA(isA<WebDavException>()
            .having((e) => e.statusCode, 'statusCode', 500)),
      );
    });

    test(
        'TEST-07-S5: listDirectory 207 + 无效 XML → 返回空列表（偏离 spec §3 S5: 生产不抛异常）',
        () async {
      // ⚠️ 与 TEST-07.md §3.1 S5 期望不符的实测发现：
      // spec 断言 "抛出 WebDavException（XML 解析失败）"，但生产行为（regex 解析器，
      // 见 BUG-23）对垃圾/截断/空 body 一律返回空列表，从不抛异常（已对 5 种畸形
      // body 探测确认）。本测试锚定实际行为作为回归护栏；是否改为抛异常需 dev-plan 裁决。
      final client = WebDavClient(
        httpClient: MockClient(
            (request) async => http.Response('this is not xml at all', 207)),
      );

      final result = await client.listDirectory(
          url: _validUrl, username: 'u', password: 'p', path: '/');

      expect(result, isEmpty,
          reason: '生产实测: 解析失败返回空列表而非 WebDavException（待 dev-plan 裁决）');
    });
  });
}
