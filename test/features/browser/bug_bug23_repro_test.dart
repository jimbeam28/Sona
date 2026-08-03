// test/features/browser/bug_bug23_repro_test.dart
// BUG-23 (NET4 + NET5 + NET6 + NET8, docs/cr/cr-20260724-0110) 门禁测试:
//
//   S1/INV2 — listDirectory 的 body 读取包进整体 deadline：响应头到达后
//             body 停滞/慢速时必须在超时内抛 WebDavException('连接超时')，
//             不得永久挂起（NET4 复现路径①）。
//   S2/INV3 — validate 的 drain 为 fire-and-forget：body 挂起或抛错都不得
//             阻塞返回、不得把已判定的 207 成功翻转为 networkError
//             （NET4 复现路径②）。
//   S3      — responseRegex 大小写不敏感 + _extractXmlContent 词边界：
//             <D:RESPONSE>/<D:HREF> 等大写前缀正常解析；<xhref> 等包含
//             tagName 子串的标签不得误匹配（NET5）。
//   S4      — 3xx/5xx 与"不可达"分离：validate 301 → "服务器重定向…"、
//             500 → "服务器内部错误…"；listDirectory 同款文案，其他非 207
//             保留裸状态码兜底；207/401/404 既有映射不变（NET6）。
//   S5/INV1 — listDirectory 兜底异常固定文案"无法连接到服务器，请检查地址
//             和网络"，原始异常文本（errno/address 等）不进用户可见消息，
//             仅经 debugPrint 进 LogBuffer 保留可追溯性（NET8）。
//
// 审计时 HEAD（193ef56）FAIL 证据：S3 标签词边界与 S4 3xx/5xx 分支未实现
// （301/500 仍报"无法连接"/裸状态码，<xhref> 子串误匹配），且本门禁文件
// 缺失——S1/S2/S5 虽已实现但真实 client HTTP 层零测试锚定（NET9 同型）。
// 全部用例经 package:http/testing 注入真实 WebDavClient，非 fake 自证。

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nas_audio_player/core/network/webdav_client.dart';

/// Runs [body] while capturing everything written through [debugPrint].
///
/// Production mirrors debugPrint into LogBuffer (installLogBufferHook in
/// main.dart), so whatever lands in [logs] is exactly what a debug build
/// exposes at /logs.
Future<T> captureDebugPrint<T>(
  Future<T> Function(List<String> logs) body,
) async {
  final logs = <String>[];
  final original = debugPrint;
  debugPrint = (String? message, {int? wrapWidth}) {
    if (message != null) logs.add(message);
  };
  try {
    return await body(logs);
  } finally {
    debugPrint = original;
  }
}

void main() {
  const validUrl = 'http://nas.example.com';

  /// Standard lowercase single-propstat 207 body — the shape every existing
  /// fixture uses; must keep parsing unchanged (S1 否定断言).
  const standard207Body = '''<?xml version="1.0" encoding="utf-8"?>
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
  <d:response>
    <d:href>/music/a.mp3</d:href>
    <d:propstat>
      <d:prop>
        <d:displayname>a.mp3</d:displayname>
        <d:getcontentlength>1234</d:getcontentlength>
        <d:resourcetype/>
      </d:prop>
      <d:status>HTTP/1.1 200 OK</d:status>
    </d:propstat>
  </d:response>
</d:multistatus>''';

  // ═══════════════════════════════════════════════════════════════════════════
  // BUG-23-S1 / INV2: body 读取包进整体 deadline（NET4）
  // ═══════════════════════════════════════════════════════════════════════════

  group('BUG-23-S1: listDirectory body read timeout', () {
    test('body stalls after headers → 连接超时 instead of hanging forever',
        () async {
      final bodyController = StreamController<List<int>>();
      addTearDown(bodyController.close);
      final client = WebDavClient(
        httpClient: MockClient.streaming(
          (request, bodyStream) async =>
              http.StreamedResponse(bodyController.stream, 207),
        ),
        timeout: const Duration(milliseconds: 100),
      );

      final stopwatch = Stopwatch()..start();
      await expectLater(
        client.listDirectory(
            url: validUrl, username: 'u', password: 'p', path: '/'),
        throwsA(
            isA<WebDavException>().having((e) => e.message, 'message', '连接超时')),
      );
      stopwatch.stop();
      expect(stopwatch.elapsed, lessThan(const Duration(seconds: 5)),
          reason: 'body 停滞必须在 deadline 内报错，不得永久挂起（NET4 复现路径①）');
    });

    test('slow-drip body (partial bytes then stall) also times out', () async {
      final bodyController = StreamController<List<int>>();
      addTearDown(bodyController.close);
      // Server starts sending the XML then goes silent mid-body.
      bodyController.add(utf8.encode('<d:multistatus>'));

      final client = WebDavClient(
        httpClient: MockClient.streaming(
          (request, bodyStream) async =>
              http.StreamedResponse(bodyController.stream, 207),
        ),
        timeout: const Duration(milliseconds: 100),
      );

      await expectLater(
        client.listDirectory(
            url: validUrl, username: 'u', password: 'p', path: '/'),
        throwsA(
            isA<WebDavException>().having((e) => e.message, 'message', '连接超时')),
      );
    });

    test('headers never arrive (send stalls) → 连接超时 too', () async {
      final client = WebDavClient(
        httpClient: MockClient.streaming(
          (request, bodyStream) async {
            await Completer<void>().future; // never resolves, no timer leaked
            throw StateError('unreachable');
          },
        ),
        timeout: const Duration(milliseconds: 100),
      );

      await expectLater(
        client.listDirectory(
            url: validUrl, username: 'u', password: 'p', path: '/'),
        throwsA(
            isA<WebDavException>().having((e) => e.message, 'message', '连接超时')),
      );
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // BUG-23-S2 / INV3: validate drain fire-and-forget，不翻转已判定结果（NET4）
  // ═══════════════════════════════════════════════════════════════════════════

  group('BUG-23-S2: validate drain fire-and-forget', () {
    test('207 + hanging body → returns success without waiting for drain',
        () async {
      final bodyController = StreamController<List<int>>();
      addTearDown(bodyController.close);
      final client = WebDavClient(
        httpClient: MockClient.streaming(
          (request, bodyStream) async =>
              http.StreamedResponse(bodyController.stream, 207),
        ),
        timeout: const Duration(milliseconds: 100),
      );

      final result = await client
          .validate(url: validUrl, username: 'u', password: 'p')
          .timeout(
            const Duration(seconds: 2),
            onTimeout: () =>
                throw StateError('validate 被 drain 阻塞——fire-and-forget 失效'),
          );
      expect(result.isSuccess, isTrue,
          reason: 'body 未排空不得阻塞返回或翻转成功（NET4 复现路径②）');
    });

    test('207 + body stream error → success is not flipped to networkError',
        () async {
      final client = WebDavClient(
        httpClient: MockClient.streaming(
          (request, bodyStream) async => http.StreamedResponse(
            Stream<List<int>>.error(
                const SocketException('Connection reset by peer')),
            207,
          ),
        ),
        timeout: const Duration(seconds: 1),
      );

      final result = await client
          .validate(url: validUrl, username: 'u', password: 'p')
          .timeout(
            const Duration(seconds: 2),
            onTimeout: () =>
                throw StateError('validate 被 drain 阻塞——fire-and-forget 失效'),
          );
      expect(result.status, WebDavValidationStatus.success,
          reason: '207 头后 RST（drain 抛错）不得把已成功的验证翻转为 networkError');
      expect(result.message, isNull);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // BUG-23-S3: responseRegex 大小写不敏感 + 标签词边界（NET5）
  // ═══════════════════════════════════════════════════════════════════════════

  group('BUG-23-S3: case-insensitive response blocks + tag boundaries', () {
    test('uppercase namespace tags (<D:RESPONSE>/<D:HREF>) parse entries', () {
      const xml = '''<?xml version="1.0" encoding="utf-8"?>
<D:multistatus xmlns:D="DAV:">
  <D:RESPONSE>
    <D:HREF>/music/song%20one.mp3</D:HREF>
    <D:PROPSTAT>
      <D:PROP>
        <D:DISPLAYNAME>song one.mp3</D:DISPLAYNAME>
        <D:GETCONTENTLENGTH>1234</D:GETCONTENTLENGTH>
        <D:RESOURCETYPE/>
      </D:PROP>
      <D:STATUS>HTTP/1.1 200 OK</D:STATUS>
    </D:PROPSTAT>
  </D:RESPONSE>
  <D:Response>
    <D:hReF>/music/song%20two.mp3</D:hReF>
    <D:pRoPsTaT>
      <D:pRoP>
        <D:dIsPlAyNaMe>song two.mp3</D:dIsPlAyNaMe>
      </D:pRoP>
    </D:pRoPsTaT>
  </D:Response>
</D:multistatus>''';

      final files = WebDavClient.parsePropfindResponse(xml);
      expect(files, hasLength(2),
          reason: '大写前缀 <D:RESPONSE> 块不得被遗漏（U2：不得静默显示空目录）');
      expect(files[0].path, '/music/song one.mp3');
      expect(files[0].name, 'song one.mp3');
      expect(files[0].size, 1234);
      expect(files[0].isDirectory, isFalse);
      expect(files[1].path, '/music/song two.mp3');
      expect(files[1].name, 'song two.mp3');
    });

    test('tag substring must not false-match: <xhref> cannot shadow <href>',
        () {
      const xml = '<multistatus><response>'
          '<xhref>/wrong.mp3</xhref>'
          '<href>/right.mp3</href>'
          '</response></multistatus>';

      final files = WebDavClient.parsePropfindResponse(xml);
      expect(files, hasLength(1));
      expect(files.single.path, '/right.mp3',
          reason: 'href 提取不得命中含 tagName 子串的其他标签（NET5 标签边界）');
      expect(files.single.path, isNot('/wrong.mp3'));
    });

    test('prop inside propstat still extracts props (nested-tag regression)',
        () {
      final files = WebDavClient.parsePropfindResponse(standard207Body);
      expect(files, hasLength(2), reason: 'propstat 包裹的 prop 块解析不得回归');
      expect(files[0].isDirectory, isTrue);
      expect(files[1].name, 'a.mp3');
      expect(files[1].size, 1234);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // BUG-23-S4: 3xx/5xx 与"不可达"分离（NET6）
  // ═══════════════════════════════════════════════════════════════════════════

  group('BUG-23-S4: validate status mapping', () {
    test('301/302 → redirect message, not "无法连接"', () async {
      for (final code in [301, 302]) {
        final client = WebDavClient(
          httpClient: MockClient((request) async => http.Response('', code)),
        );
        final result =
            await client.validate(url: validUrl, username: 'u', password: 'p');
        expect(result.status, WebDavValidationStatus.networkError,
            reason: '$code 仍归 networkError 状态');
        expect(result.message, '服务器重定向，请检查地址是否应为 https');
        expect(result.message, isNot('无法连接到服务器，请检查地址和网络'),
            reason: '$code 不得报为"无法连接"（NET6 复现路径①）');
      }
    });

    test('500/503 → server error message, not "无法连接"', () async {
      for (final code in [500, 503]) {
        final client = WebDavClient(
          httpClient: MockClient((request) async => http.Response('', code)),
        );
        final result =
            await client.validate(url: validUrl, username: 'u', password: 'p');
        expect(result.status, WebDavValidationStatus.networkError);
        expect(result.message, '服务器内部错误，请稍后重试',
            reason: '$code 不得报为"无法连接"（NET6 复现路径②）');
      }
    });

    test('207/401/404/其他4xx 既有映射不变', () async {
      Future<WebDavValidationResult> validateWith(int code) {
        final client = WebDavClient(
          httpClient: MockClient((request) async => http.Response('', code)),
        );
        return client.validate(url: validUrl, username: 'u', password: 'p');
      }

      expect((await validateWith(207)).isSuccess, isTrue,
          reason: '207 成功路径不得改变');

      final auth = await validateWith(401);
      expect(auth.status, WebDavValidationStatus.authError);
      expect(auth.message, '用户名或密码错误');

      final notFound = await validateWith(404);
      expect(notFound.status, WebDavValidationStatus.pathNotFound);
      expect(notFound.message, '基础路径不存在，请检查路径设置');

      final teapot = await validateWith(418);
      expect(teapot.status, WebDavValidationStatus.networkError);
      expect(teapot.message, '无法连接到服务器，请检查地址和网络',
          reason: '其余 4xx 保留默认 networkError 文案');
    });
  });

  group('BUG-23-S4: listDirectory status mapping', () {
    test('301 → redirect message + statusCode', () async {
      final client = WebDavClient(
        httpClient: MockClient((request) async => http.Response('', 301)),
      );
      await expectLater(
        client.listDirectory(
            url: validUrl, username: 'u', password: 'p', path: '/'),
        throwsA(isA<WebDavException>()
            .having((e) => e.message, 'message', '服务器重定向，请检查地址是否应为 https')
            .having((e) => e.statusCode, 'statusCode', 301)),
      );
    });

    test('500 → server error message + statusCode', () async {
      final client = WebDavClient(
        httpClient: MockClient((request) async => http.Response('', 500)),
      );
      await expectLater(
        client.listDirectory(
            url: validUrl, username: 'u', password: 'p', path: '/'),
        throwsA(isA<WebDavException>()
            .having((e) => e.message, 'message', '服务器内部错误，请稍后重试')
            .having((e) => e.statusCode, 'statusCode', 500)),
      );
    });

    test('404 keeps the bare-code fallback (spec boundary ruling)', () async {
      final client = WebDavClient(
        httpClient: MockClient((request) async => http.Response('', 404)),
      );
      await expectLater(
        client.listDirectory(
            url: validUrl, username: 'u', password: 'p', path: '/'),
        throwsA(isA<WebDavException>()
            .having((e) => e.message, 'message', '服务器返回异常状态码 404')
            .having((e) => e.statusCode, 'statusCode', 404)),
      );
    });

    test('401 → 用户名或密码错误 + isAuthError (unchanged)', () async {
      final client = WebDavClient(
        httpClient: MockClient((request) async => http.Response('', 401)),
      );
      await expectLater(
        client.listDirectory(
            url: validUrl, username: 'u', password: 'p', path: '/'),
        throwsA(isA<WebDavException>()
            .having((e) => e.message, 'message', '用户名或密码错误')
            .having((e) => e.isAuthError, 'isAuthError', isTrue)),
      );
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // BUG-23-S5 / INV1: 兜底异常固定文案，原始异常仅进日志（NET8）
  // ═══════════════════════════════════════════════════════════════════════════

  group('BUG-23-S5: fallback exception sanitized message', () {
    WebDavClient throwingClient() => WebDavClient(
          httpClient: MockClient((request) async => throw const SocketException(
              'OS Error: Connection refused, errno = 111')),
        );

    test('user-visible message is the fixed text, raw internals never leak',
        () async {
      await expectLater(
        throwingClient().listDirectory(
            url: validUrl, username: 'u', password: 'p', path: '/'),
        throwsA(isA<WebDavException>()
            .having((e) => e.message, 'message', '无法连接到服务器，请检查地址和网络')
            .having((e) => e.statusCode, 'statusCode', isNull)
            .having((e) => e.message, 'no errno leak', isNot(contains('errno')))
            .having((e) => e.message, 'no OS error leak',
                isNot(contains('Connection refused')))
            .having((e) => e.message, 'no exception type leak',
                isNot(contains('SocketException')))),
      );
    });

    test('raw exception is still traceable in debugPrint/LogBuffer', () async {
      await captureDebugPrint((logs) async {
        try {
          await throwingClient().listDirectory(
              url: validUrl, username: 'u', password: 'p', path: '/');
          fail('listDirectory 应抛出 WebDavException');
        } on WebDavException catch (e) {
          expect(e.message, '无法连接到服务器，请检查地址和网络');
        }
        expect(logs.join('\n'), contains('Connection refused'),
            reason: '原始异常须经 debugPrint 进 LogBuffer 保留可追溯性（U4）');
      });
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // 正常路径回归：207 标准响应经真实 client 端到端解析不变（S1 否定断言）
  // ═══════════════════════════════════════════════════════════════════════════

  group('BUG-23 normal-path regression', () {
    test('207 standard lowercase body parses end-to-end through real client',
        () async {
      http.BaseRequest? seenRequest;
      final client = WebDavClient(
        httpClient: MockClient.streaming((request, bodyStream) async {
          seenRequest = request;
          return http.StreamedResponse(
              Stream.value(utf8.encode(standard207Body)), 207);
        }),
      );

      final files = await client.listDirectory(
          url: validUrl, username: 'u', password: 'p', path: '/');

      expect(seenRequest, isNotNull);
      expect(seenRequest!.method, 'PROPFIND');
      expect(seenRequest!.headers['Depth'], '1');
      expect(files, hasLength(2));
      expect(files[0].path, '/', reason: '目录自引用应保留为 /');
      expect(files[0].isDirectory, isTrue);
      expect(files[1].name, 'a.mp3');
      expect(files[1].path, '/music/a.mp3');
      expect(files[1].size, 1234);
      expect(files[1].isDirectory, isFalse);
    });
  });
}
