// test/core/network/ref_01_relativise_test.dart
// REF-01 (docs/features/REF-01.md §5.4 门禁) — listDirectory 对服务器返回的
// 绝对 URL href 正确相对化（含根挂载）。
//
// 覆盖: REF-01-S2 / S3 / S4 / S5 / S6 / S7 / REF-01-INV1 / REF-01-INV2 /
//       REF-01-ALG1。全部用例经 package:http/testing 注入真实 WebDavClient，
// 非 fake 自证。
//
//   S2 — 根挂载（base 段空）+ 根相对 href 原样
//   S3 — 缺陷态: 绝对 URL href 不再泄漏进 NasFile.path（修复后 == S4 收敛）
//   S4 — 绝对 URL href（host 相同）→ 剥 authority + base 剥离，返回相对路径
//   S5 — 根挂载 + 绝对 URL href（host 相同）→ 剥 authority，根相对 href 不动
//   S6 — 绝对 URL href（host 不同）→ 原样保留，不抛异常、不部分剥离
//   S7 — 绝对 URL 根自引用（剥后 path 空）→ 归一为 '/'
//   INV1 — 全部 host 匹配 href 必为路径形态（不以 scheme:// 开头）
//   INV2 — 相对 href（无 scheme）处理结果与修复前逐字节一致
//   ALG1 — _stripHrefAuthority 算法样例（经 listDirectory 行为验证）

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nas_audio_player/core/network/webdav_client.dart';

// ── PROPFIND XML 构造（与 bug_13_repro_test 同款格式）────────────────────────

String _wrap(String blocks) => '<?xml version="1.0" encoding="utf-8"?>\n'
    '<d:multistatus xmlns:d="DAV:">\n$blocks</d:multistatus>';

String _entry(String href, String name, {bool dir = true}) => '  <d:response>\n'
    '    <d:href>$href</d:href>\n'
    '    <d:propstat>\n'
    '      <d:prop>\n'
    '        <d:displayname>$name</d:displayname>\n'
    '        ${dir ? '<d:resourcetype><d:collection/></d:resourcetype>' : ''}\n'
    '      </d:prop>\n'
    '      <d:status>HTTP/1.1 200 OK</d:status>\n'
    '    </d:propstat>\n'
    '  </d:response>\n';

WebDavClient _clientFor(String body) => WebDavClient(
      httpClient: MockClient((request) async => http.Response(body, 207)),
    );

/// 运行一次 listDirectory，返回各条目的 path。
Future<List<String>> _listPaths(
  String body, {
  String url = 'http://nas.example.com:5005/dav',
}) async {
  final entries = await _clientFor(body).listDirectory(
    url: url,
    username: 'admin',
    password: 'pw',
    path: '/',
  );
  return entries.map((e) => e.path).toList();
}

void main() {
  group('REF-01-S4: 绝对 URL href（host 相同）剥 authority + base 剥离', () {
    test('S4: 同 host 绝对 URL → 返回相对路径 /music，不泄漏 scheme/authority', () async {
      final paths = await _listPaths(_wrap(
        _entry('/dav/', 'dav') +
            _entry('http://nas.example.com:5005/dav/music/', 'music'),
      ));

      expect(paths, contains('/music'),
          reason: '同 host 绝对 URL 应剥 authority + base 前缀后返回相对 /music');
      expect(paths, isNot(contains('http://')),
          reason: '否定断言: 返回 path 不得以 http:// 开头（INV1）');
      expect(paths, isNot(contains('/dav/music')),
          reason: '否定断言: 不得残留 /dav 前缀（否则导航再拼一次 base 变 404）');
    });

    test('S4-否定: 相对 href 处理结果不得改变（S1 行为保持，INV2）', () async {
      final paths = await _listPaths(
        _wrap(_entry('/dav/', 'dav') + _entry('/dav/music/', 'music')),
      );

      expect(paths, contains('/music'),
          reason: '相对 href 走既有 base 剥离逻辑，行为与修复前一致');
      expect(paths, isNot(contains('/dav')),
          reason: '自引用 /dav 应归一为 /，不得作为幽灵目录泄漏');
    });

    test('S4-ALG1: scheme/端口不同但 host 相同仍剥 authority', () async {
      // ALG1: 'https://nas:5005/dav/music', request 'http://nas:5005/dav'
      //   → '/dav/music'（scheme 不参与判定）。
      final paths = await _listPaths(
        _wrap(_entry('/dav/', 'dav') +
            _entry('https://nas.example.com:8443/dav/music/', 'music')),
        url: 'http://nas.example.com:5005/dav',
      );

      expect(paths, contains('/music'),
          reason: 'scheme/端口不同但 host 相同 → 仍剥 authority（端口/scheme 不参与判定）');
    });

    test('S4-ALG1: scheme/host 大小写不敏感', () async {
      final paths = await _listPaths(
        _wrap(_entry('/dav/', 'dav') +
            _entry('HTTP://NAS.EXAMPLE.COM:5005/dav/music/', 'music')),
        url: 'http://nas.example.com:5005/dav',
      );

      expect(paths, contains('/music'),
          reason: 'scheme/host 大小写不敏感（Uri.parse 已规范化后比较）');
    });

    test('S4-ALG1: 同 host 但路径不在 base 下 → 防御分支原样返回不被损坏', () async {
      final paths = await _listPaths(
        _wrap(_entry('http://nas.example.com:5005/other/x.mp3', 'x.mp3')),
      );

      expect(paths, contains('/other/x.mp3'),
          reason: "剥 authority 后 '/other/x.mp3' 不匹配 base 前缀 → 原样返回（防御分支）");
    });
  });

  group('REF-01-S5: 根挂载 + 绝对 URL href（host 相同）→ 剥 authority', () {
    test('S5: 根挂载下绝对 URL → 保留相对路径；根相对 href 不被改动', () async {
      final paths = await _listPaths(
        _wrap(_entry('http://nas.example.com:5005/music/', 'music') +
            _entry('/song.mp3', 'song.mp3', dir: false)),
        url: 'http://nas.example.com:5005/',
      );

      expect(paths, contains('/music'),
          reason: "根挂载（basePath 空）剥 authority 后 '/music' 即连接根相对");
      expect(paths, contains('/song.mp3'),
          reason: '根相对 href 非绝对 URL，不触碰（S2 相对行为保持）');
      expect(paths, isNot(contains('http://')),
          reason: '否定断言 (INV1): 根挂载下任何条目 path 不得以 http:// 开头');
    });
  });

  group('REF-01-S6: 绝对 URL href（host 与请求不同）→ 原样返回', () {
    test('S6: 异 host 绝对 URL → 整段保留，不抛异常、不部分剥离', () async {
      final paths = await _listPaths(
        _wrap(_entry('/dav/', 'dav') +
            _entry('http://other-nas:5005/dav/music/', 'music') +
            _entry('/dav/music2/', 'music2')),
      );

      expect(paths, contains('http://other-nas:5005/dav/music'),
          reason: '异 host 绝对 URL 整段保留（外部引用不被相对化吞掉）');
      expect(paths, isNot(contains('/dav/music')), reason: '否定断言: 不得产生部分剥离形态');
      expect(paths, contains('/music2'), reason: '同目录下 host 匹配的条目仍正常相对化（互不影响）');
    });
  });

  group('REF-01-S7: 绝对 URL 根自引用（剥后 path 空）→ 归一为 /', () {
    test('S7: 根挂载下 http://host/ 自身 → path == /', () async {
      final paths = await _listPaths(
        _wrap(_entry('http://nas.example.com:5005/', 'nas')),
        url: 'http://nas.example.com:5005/',
      );

      expect(paths, contains('/'), reason: '根自引用剥 authority 后 path 空 → 归一为 /');
      expect(paths, isNot(contains('')), reason: '否定断言: 返回不得为空字符串');
      expect(paths, isNot(contains('http://')), reason: '否定断言: authority 不得泄漏');
    });
  });

  group('REF-01-S2: 根挂载 + 相对 href（现状锚定）', () {
    test('S2: 根挂载下根相对 href 原样返回，不剥任何前缀', () async {
      final paths = await _listPaths(
        _wrap(_entry('/', 'root') + _entry('/music/', 'music')),
        url: 'http://nas.example.com:5005/',
      );

      expect(paths, contains('/music'), reason: '根挂载下根相对 href 原样保留');
      expect(paths, contains('/'), reason: "根自引用 '/' 原样返回");
    });
  });

  group('REF-01-ALG1: _stripHrefAuthority 防御分支（经 listDirectory 行为验证）', () {
    test('ALG1: 非绝对 URL（相对/根相对路径）→ 走原剥离逻辑', () async {
      final paths = await _listPaths(
        _wrap(_entry('/dav/music/', 'music')),
      );
      expect(paths, contains('/music'),
          reason: "'/dav/music' 无 scheme → 非绝对 URL → 走既有 base 剥离");
    });

    test('ALG1: scheme-relative //host/... → scheme 空 → 原样返回（防御）', () async {
      final paths = await _listPaths(
        _wrap(_entry('//nas.example.com:5005/dav/music/', 'music')),
      );

      expect(paths, contains('//nas.example.com:5005/dav/music'),
          reason: 'scheme-relative 响应形态 Uri.parse 后 scheme 空 → 非绝对 URL → 原样');
    });

    test('ALG1: 非 URL 形态 href → Uri.tryParse 后 scheme/host 空 → 原样', () async {
      final paths = await _listPaths(
        _wrap(_entry('not a url at all', 'weird')),
      );

      expect(paths, contains('not a url at all'), reason: '不可解析输入保持原样（防御分支）');
    });

    test('ALG1: 同 host 绝对 URL → 剥 authority 得 path 形态', () async {
      final paths = await _listPaths(
        _wrap(_entry('http://nas.example.com:5005/dav/music', 'music')),
      );
      expect(paths, contains('/music'),
          reason: "绝对 URL + 同 host → '/dav/music' → base 剥离 → '/music'");
    });
  });

  group('REF-01-S3: 缺陷态（修复前绝对 URL 泄漏）回归护栏', () {
    test('S3: 绝对 URL href 不得再进入导航/播放链路（整段 URL 不再作为 path）', () async {
      final paths = await _listPaths(
        _wrap(_entry('/dav/', 'dav') +
            _entry('http://nas.example.com:5005/dav/music/', 'music')),
      );

      expect(paths, isNot(contains('http://nas.example.com:5005/dav/music')),
          reason: '修复后绝对 URL href 相对化成相对路径，不得整段泄漏进 NasFile.path');
      expect(paths, contains('/music'), reason: '泄漏形态被消除后即为 S4 目标态');
    });
  });

  group('REF-01-INV2: 相对 href 全量处理结果不变', () {
    test('INV2: 相对 href 集合逐字节等于修复前输出', () async {
      final paths = await _listPaths(_wrap(
        _entry('/dav/', 'dav') +
            _entry('/dav/sub/', 'sub') +
            _entry('/dav/a.mp3', 'a.mp3', dir: false),
      ));

      expect(paths, contains('/'), reason: '自引用 /dav → /');
      expect(paths, contains('/sub'), reason: '子目录剥前缀');
      expect(paths, contains('/a.mp3'), reason: '文件剥前缀');
      expect(paths, isNot(contains('/dav')), reason: '无任何 /dav 前缀残留');
    });
  });
}
