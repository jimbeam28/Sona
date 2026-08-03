// test/features/browser/bug_11_test.dart
// BUG-11 门禁测试（来源：docs/cr/cr-20260724-0110.md NET2；spec：docs/features/BUG-11.md）
//
// 缺陷：_extractXmlContent 直接返回 match.group(1) 无任何反转义。合规服务器
// 必须把 XML 文本中的 & < > 等写成 &amp; &lt; &gt;——含这些字符的文件名在浏览器
// 显示成实体乱码（spec U1/U2），href 中的 &amp; 经 Uri.decodeFull 后残留字面
// "amp;" → 导航/播放 404。
//
// 修复：_unescapeXmlEntities 统一反转义五个预定义实体（&amp; 最后替换，避免
// 二次解码），在 _extractXmlContent 返回前统一调用。
//
// 本测试直接驱动生产解析入口 WebDavClient.parsePropfindResponse，锚定服务器
// 原始转义形态的 XML（spec §5.3：BRW-T06 只覆盖百分号编码、零 XML 实体用例，
// 此处补 &amp;/&lt;/&gt;/&apos;/&quot; 各一条 + 混合/否定断言）。
// 修复前 FAIL（name/path 残留实体），修复后 PASS。

import 'package:flutter_test/flutter_test.dart';
import 'package:nas_audio_player/core/network/webdav_client.dart';
import 'package:nas_audio_player/shared/models/nas_file.dart';

// ── XML 构造（与 brw_01 同源：服务器原始转义形态） ─────────────────────────────

String _wrapInMultiStatus(String responseBlocks) {
  return '<?xml version="1.0" encoding="utf-8"?>\n'
      '<d:multistatus xmlns:d="DAV:">\n'
      '$responseBlocks'
      '</d:multistatus>';
}

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

String _fileResponse(String href, String displayName) {
  return '  <d:response>\n'
      '    <d:href>$href</d:href>\n'
      '    <d:propstat>\n'
      '      <d:prop>\n'
      '        <d:displayname>$displayName</d:displayname>\n'
      '        <d:getcontentlength>1000</d:getcontentlength>\n'
      '      </d:prop>\n'
      '      <d:status>HTTP/1.1 200 OK</d:status>\n'
      '    </d:propstat>\n'
      '  </d:response>\n';
}

void main() {
  group('BUG-11-S1: 五个预定义 XML 实体反转义', () {
    test('&amp; → &（spec U1：Simon & Garfunkel 正常显示）', () {
      final xml = _wrapInMultiStatus(_fileResponse(
          '/music/Simon%20%26%20Garfunkel%20-%20Live.mp3',
          'Simon &amp; Garfunkel - Live.mp3'));

      final file = WebDavClient.parsePropfindResponse(xml).single;

      expect(file.name, equals('Simon & Garfunkel - Live.mp3'));
      expect(file.name, isNot(contains('&amp;')),
          reason: '否定断言：不得返回含 XML 实体的原始文本（修复前 BUG 行为）');
      expect(file.path, equals('/music/Simon & Garfunkel - Live.mp3'),
          reason: 'href 走 Uri.decodeFull（%26 → &），与 displayname 反转义结论一致');
    });

    test('&lt;/&gt; → </>（spec U2：目录 Rock < Classics 可正常进入）', () {
      final xml = _wrapInMultiStatus(
          _dirResponse('/Rock%20%3C%20Classics/', 'Rock &lt; Classics'));

      final dir = WebDavClient.parsePropfindResponse(xml).single;

      expect(dir.name, equals('Rock < Classics'));
      expect(dir.name, isNot(contains('&lt;')), reason: '否定断言：不残留实体');
      expect(dir.isDirectory, isTrue);
      expect(dir.path, equals('/Rock < Classics'),
          reason: '导航路径来自解码后 href，与显示名一致，点击进入不得 404');
    });

    test('&apos; → 单引号', () {
      final xml = _wrapInMultiStatus(
          _fileResponse('/music/It%27s.mp3', 'It&apos;s.mp3'));

      expect(WebDavClient.parsePropfindResponse(xml).single.name,
          equals("It's.mp3"));
    });

    test('&quot; → 双引号', () {
      final xml = _wrapInMultiStatus(
          _fileResponse('/music/%22Quoted%22.mp3', '&quot;Quoted&quot;.mp3'));

      expect(WebDavClient.parsePropfindResponse(xml).single.name,
          equals('"Quoted".mp3'));
    });

    test('混合实体一次解净（spec 边界裁决：&amp; 最后替换不二次解码）', () {
      final xml = _wrapInMultiStatus(_fileResponse(
          '/music/live.mp3', 'Simon &amp; Garfunkel &lt;Live&gt;'));

      expect(WebDavClient.parsePropfindResponse(xml).single.name,
          equals('Simon & Garfunkel <Live>'));
    });

    test('无实体文本原样返回', () {
      final xml =
          _wrapInMultiStatus(_fileResponse('/music/plain.mp3', 'plain.mp3'));

      expect(WebDavClient.parsePropfindResponse(xml).single.name,
          equals('plain.mp3'));
    });

    test('否定断言：displayname 不做 URL 解码（XML 反转义 ≠ URL 解码）', () {
      final xml = _wrapInMultiStatus(
          _fileResponse('/music/a.mp3', 'Best%20Of &amp; More'));

      final file = WebDavClient.parsePropfindResponse(xml).single;

      expect(file.name, equals('Best%20Of & More'),
          reason: 'displayname 只反转义 XML 实体；%20 必须保留字面，'
              '不得被当成 URL 编码额外解码（spec S1 否定断言 2）');
    });
  });

  group('BUG-11-S1: href 侧——XML 反转义与 URL 解码互不干扰', () {
    test('href 中的 &amp;（查询参数）→ &，不得残留字面 amp;', () {
      final xml = _wrapInMultiStatus(
          _fileResponse('/music/song.mp3?x=1&amp;y=2', 'song.mp3'));

      final file = WebDavClient.parsePropfindResponse(xml).single;

      expect(file.path, equals('/music/song.mp3?x=1&y=2'));
      expect(file.path, isNot(contains('amp;')),
          reason: '修复前 Uri.decodeFull 不解 XML 实体，path 残留 amp; → 导航 404');
    });

    test('否定断言：href 的百分号编码不受 XML 反转义影响（BRW-T06 回归）', () {
      final xml = _wrapInMultiStatus(_fileResponse(
          '/music/Simon%20%26%20Garfunkel.mp3', 'Simon &amp; Garfunkel'));

      final file = WebDavClient.parsePropfindResponse(xml).single;

      expect(file.path, equals('/music/Simon & Garfunkel.mp3'),
          reason: 'href 走 Uri.decodeFull（%20/%26 → 空格/&），'
              'XML 反转义通道不得干扰 URL 编码处理（spec S1 否定断言 3）');
    });
  });

  group('BUG-11-INV1: displayname 反转义后进 NasFile.name', () {
    test('同一 displayname 含全部五个实体 → NasFile.name 完整反转义', () {
      final xml = _wrapInMultiStatus(_fileResponse(
          '/music/a.mp3', 'A &amp; B &lt;C&gt; &quot;D&quot; E&apos;s'));

      final NasFile file = WebDavClient.parsePropfindResponse(xml).single;

      expect(file.name, equals('A & B <C> "D" E\'s'),
          reason: 'displayname 提取 → 反转义 → NasFile.name 全链路（INV1 证据链）');
    });
  });
}
