// test/core/bug_13_repro_test.dart
// BUG-13 复现测试（来源：docs/cr/cr-20260724-0110.md NET1）
//
// 缺陷：WebDavClient.validate() 与 listDirectory() 对 base path 的约定自相矛盾——
//   * validate **替换** URL 自带 path（base.replace(path: basePath)），只探测 basePath；
//   * listDirectory **拼接** URL 自带 path 且无 basePath 参数，完全忽略 ConnectionConfig.basePath；
//   * 调用方只把 basePath 传给 validate（connection_provider），浏览/播放链路不传。
// 于是用户把挂载点填进 URL 字段（模式 A）或"基础路径"字段（模式 B）都会在
// 浏览/播放链路解析到与 validate 不同的位置：幽灵目录 + /dav/dav 双重前缀 404，
// 或 basePath 被静默忽略从服务器根开始浏览。
//
// 修复：统一两方法的 base path 来源约定——
//   * validate 探测 url.path 与 basePath 的拼接（连接根），与 listDirectory 落点一致；
//   * 调用方（browser_provider / playback_orchestrator）改传 webDavEffectiveBaseUrl
//     （path 已含连接根）给 listDirectory / buildWithBasePath，base 恰好作用一次；
//   * listDirectory 把服务端绝对 href 去掉连接根前缀，返回相对连接根的路径，
//     消除自引用幽灵目录与导航/播放的双重前缀。
//
// 本测试只用既有公开 API（WebDavClient / directoryContentsProvider /
// ConnectionConfig），不依赖任何新增符号，因此修复前可编译且 FAIL，修复后 PASS。

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:nas_audio_player/core/network/webdav_client.dart';
import 'package:nas_audio_player/features/browser/browser_provider.dart';
import 'package:nas_audio_player/features/connection/connection_provider.dart';
import 'package:nas_audio_player/shared/models/connection_config.dart';
import 'package:nas_audio_player/shared/models/nas_file.dart';

import '../helpers/fake_secure_storage.dart';

// ── 捕获请求 URL 的 mock http.Client ─────────────────────────────────────────

/// 记录最近一次请求的 URL，并返回可配置的 status / body（PROPFIND 响应）。
class _CapturingHttpClient extends http.BaseClient {
  Uri? lastUrl;
  String body;

  _CapturingHttpClient({this.body = ''});

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    lastUrl = request.url;
    // 207 Multi-Status — validate 与 listDirectory 都视为成功响应。
    return http.StreamedResponse(
      Stream.value(utf8.encode(body)),
      207,
      request: request,
    );
  }
}

// ── 记录 listDirectory 传参的 fake（用于 provider 接线断言）──────────────────

class _RecordingWebDavClient implements WebDavClientInterface {
  String? lastListUrl;
  String? lastListPath;
  List<NasFile> result = const [];

  @override
  // DL-01：接口新增 downloadFile 后补齐 override（机械适配，不参与本文件断言）。
  @override
  Future<void> downloadFile({
    required String url,
    required String filePath,
    required String username,
    required String password,
    required String saveTo,
    void Function(int received, int? total)? onProgress,
  }) =>
      throw UnimplementedError('downloadFile not needed for this test');

  Future<List<NasFile>> listDirectory({
    required String url,
    required String username,
    required String password,
    required String path,
  }) async {
    lastListUrl = url;
    lastListPath = path;
    return result;
  }

  @override
  Future<WebDavValidationResult> validate({
    required String url,
    required String username,
    required String password,
    String basePath = '/',
  }) async {
    return WebDavValidationResult.success();
  }
}

// ── PROPFIND XML 构造（与 brw_01 同款格式）──────────────────────────────────

String _wrap(String blocks) => '<?xml version="1.0" encoding="utf-8"?>\n'
    '<d:multistatus xmlns:d="DAV:">\n$blocks</d:multistatus>';

String _dir(String href, String name) => '  <d:response>\n'
    '    <d:href>$href</d:href>\n'
    '    <d:propstat>\n'
    '      <d:prop>\n'
    '        <d:displayname>$name</d:displayname>\n'
    '        <d:resourcetype><d:collection/></d:resourcetype>\n'
    '      </d:prop>\n'
    '      <d:status>HTTP/1.1 200 OK</d:status>\n'
    '    </d:propstat>\n'
    '  </d:response>\n';

/// 去掉尾部斜杠（根保留为 /），便于比较落点。
String _norm(String p) =>
    (p.length > 1 && p.endsWith('/')) ? p.substring(0, p.length - 1) : p;

ConnectionConfig _conn({required String url, String basePath = '/'}) =>
    ConnectionConfig(
      id: 1,
      name: 'NAS',
      url: url,
      username: 'admin',
      basePath: basePath,
      isActive: true,
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
    );

void main() {
  // ═══════════════════════════════════════════════════════════════════════════
  // Group 1: validate 与 listDirectory 对 base path 落点一致（真实 WebDavClient）
  // ═══════════════════════════════════════════════════════════════════════════

  group('NET1-1 validate/listDirectory base 落点一致', () {
    test('模式 A：路径在 URL 字段，validate 应探测 /dav 而非 /', () async {
      final http_ = _CapturingHttpClient();
      final client = WebDavClient(httpClient: http_);

      await client.validate(
        url: 'http://nas.example.com:5005/dav',
        username: 'admin',
        password: 'pw',
        basePath: '/',
      );

      expect(http_.lastUrl, isNotNull);
      expect(_norm(http_.lastUrl!.path), equals('/dav'),
          reason: 'URL 自带 /dav 时 validate 应探测连接根 /dav，'
              '而非把 URL path 替换成 basePath=/ 后探测 /');
    });

    test('模式 B：路径在 basePath 字段，validate 仍探测 /dav（回归守护）', () async {
      final http_ = _CapturingHttpClient();
      final client = WebDavClient(httpClient: http_);

      await client.validate(
        url: 'http://nas.example.com:5005',
        username: 'admin',
        password: 'pw',
        basePath: '/dav',
      );

      expect(_norm(http_.lastUrl!.path), equals('/dav'),
          reason: 'basePath=/dav 时 validate 应探测 /dav');
    });

    test('validate 与 listDirectory 根目录落点必须相同（模式 A）', () async {
      // validate 的落点
      final vHttp = _CapturingHttpClient();
      await WebDavClient(httpClient: vHttp).validate(
        url: 'http://nas.example.com:5005/dav',
        username: 'admin',
        password: 'pw',
        basePath: '/',
      );
      final validatePath = _norm(vHttp.lastUrl!.path);

      // listDirectory 根目录的落点（浏览链路传入的 base 与 validate 同源）
      final lHttp = _CapturingHttpClient(body: _wrap(_dir('/dav/', 'dav')));
      await WebDavClient(httpClient: lHttp).listDirectory(
        url: 'http://nas.example.com:5005/dav',
        username: 'admin',
        password: 'pw',
        path: '/',
      );
      final listPath = _norm(lHttp.lastUrl!.path);

      expect(validatePath, equals(listPath),
          reason: 'validate 探测的根 ($validatePath) 必须与 listDirectory '
              '列出的根 ($listPath) 相同，否则验证通过却浏览 404');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // Group 2: listDirectory 返回相对连接根的路径（消除幽灵目录 + 双重前缀）
  // ═══════════════════════════════════════════════════════════════════════════

  group('NET1-2 listDirectory 返回相对路径', () {
    test('模式 A：列出 /dav 根应返回相对路径 /music，且不泄漏自引用 /dav', () async {
      final http_ = _CapturingHttpClient(
        body: _wrap(_dir('/dav/', 'dav') + _dir('/dav/music/', 'music')),
      );
      final client = WebDavClient(httpClient: http_);

      final entries = await client.listDirectory(
        url: 'http://nas.example.com:5005/dav',
        username: 'admin',
        password: 'pw',
        path: '/',
      );

      final paths = entries.map((e) => e.path).toList();
      expect(paths, contains('/music'), reason: '子目录应返回相对连接根的路径 /music');
      expect(paths, isNot(contains('/dav/music')),
          reason: '不应返回服务端绝对路径 /dav/music（否则导航再拼一次 base '
              '变成 /dav/dav/music 404）');
      expect(paths, isNot(contains('/dav')),
          reason: '自引用 /dav 应归一为 / ，不得作为幽灵目录泄漏');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // Group 3: browser_provider 接线——basePath 被真正用于浏览（模式 B）+ 无幽灵（模式 A）
  // ═══════════════════════════════════════════════════════════════════════════

  group('NET1-3 browser_provider basePath 接线', () {
    test('模式 B：basePath=/dav 必须下传到 listDirectory 的 base（不得从服务器根开始）', () async {
      final rec = _RecordingWebDavClient()
        ..result = [
          const NasFile(
              name: 'song.mp3',
              path: '/song.mp3',
              isDirectory: false,
              audioType: AudioFileType.music),
        ];
      final storage = FakeSecureStorage()..setPassword(1, 'pw');

      final container = ProviderContainer(overrides: [
        webDavClientProvider.overrideWith((ref) => rec),
        activeConnectionProvider.overrideWith((ref) async =>
            _conn(url: 'http://nas.example.com:5005', basePath: '/dav')),
        secureStorageProvider.overrideWith((ref) => storage),
      ]);
      addTearDown(container.dispose);

      await container.read(directoryContentsProvider('/').future);

      expect(rec.lastListUrl, isNotNull);
      expect(_norm(Uri.parse(rec.lastListUrl!).path), equals('/dav'),
          reason: '浏览链路必须把 basePath=/dav 折进传给 listDirectory 的 base，'
              '否则从服务器根 / 开始浏览，basePath 被静默忽略');
    });

    test('模式 A：浏览 /dav 根不得出现幽灵目录 dav，子目录路径应为相对 /music', () async {
      final http_ = _CapturingHttpClient(
        body: _wrap(_dir('/dav/', 'dav') + _dir('/dav/music/', 'music')),
      );
      final storage = FakeSecureStorage()..setPassword(1, 'pw');

      final container = ProviderContainer(overrides: [
        webDavClientProvider
            .overrideWith((ref) => WebDavClient(httpClient: http_)),
        activeConnectionProvider.overrideWith((ref) async =>
            _conn(url: 'http://nas.example.com:5005/dav', basePath: '/')),
        secureStorageProvider.overrideWith((ref) => storage),
      ]);
      addTearDown(container.dispose);

      final entries =
          await container.read(directoryContentsProvider('/').future);

      final names = entries.map((e) => e.name).toList();
      final paths = entries.map((e) => e.path).toList();
      expect(names, isNot(contains('dav')), reason: '自引用 dav 不得作为幽灵目录出现在根列表');
      expect(paths, contains('/music'),
          reason: '子目录应以相对路径 /music 返回，供后续导航/播放正确拼 base');
    });
  });
}
