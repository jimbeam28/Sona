// test/features/browser/bug_15_repro_test.dart
// BUG-15 (docs/cr/cr-20260724-0110 MDL2) repro + regression guards:
//
//   NasFile.fromProps 曾用 displayname 做 isAudioFile/classifyType 判定。
//   部分 NAS 对 href `/music/song.mp3` 返回去扩展名的 displayname `song` →
//   isAudioFile('song')=false → audioType=null → directory_service.dart 的
//   `entry.audioType != null` 过滤器把文件整条排除出浏览列表（静默数据丢失）；
//   href `/books/book.m4b` 返回 displayname `My Book` → classifyType 判成
//   music，违反 ".m4b → audiobook" 分类规则。
//
// Fix under test (commit 8d71b72):
//   audioType 改用 href 解码后的末段文件名（hrefFilename）判定；name 字段仍
//   取 displayname 作显示标签；isDirectory 判定逻辑不变。
//
// Pre-fix FAIL evidence: S1 组用例（displayname 无扩展名 + href 有扩展名）在
// 旧实现下 audioType 为 null；S1-T4（displayname 带扩展名 + href 无扩展名）
// 在旧实现下反而误判为 music —— 两类用例在修复前均 FAIL，修复后 PASS。

import 'package:flutter_test/flutter_test.dart';
import 'package:nas_audio_player/core/network/webdav_client.dart';
import 'package:nas_audio_player/features/browser/browser_provider.dart';
import 'package:nas_audio_player/features/connection/connection_provider.dart';
import 'package:nas_audio_player/shared/models/nas_file.dart';

import '../../helpers/fake_secure_storage.dart';
import '../../helpers/fake_webdav_client.dart';
import '../../helpers/test_factories.dart';
import '../../helpers/widget_helpers.dart';

// ── XML builders（端到端解析路径锚定） ────────────────────────────────────────

String _wrapInMultiStatus(String responseBlocks) {
  return '<?xml version="1.0" encoding="utf-8"?>\n'
      '<d:multistatus xmlns:d="DAV:">\n'
      '$responseBlocks'
      '</d:multistatus>';
}

String _fileResponse(String href, String displayName) {
  return '  <d:response>\n'
      '    <d:href>$href</d:href>\n'
      '    <d:propstat>\n'
      '      <d:prop>\n'
      '        <d:displayname>$displayName</d:displayname>\n'
      '        <d:getcontentlength>1000</d:getcontentlength>\n'
      '        <d:getlastmodified>Mon, 01 Jan 2024 00:00:00 GMT</d:getlastmodified>\n'
      '      </d:prop>\n'
      '      <d:status>HTTP/1.1 200 OK</d:status>\n'
      '    </d:propstat>\n'
      '  </d:response>\n';
}

void main() {
  // ═══════════════════════════════════════════════════════════════════════════
  // BUG-15-S1: 音频识别/分类基于 href 末段，不基于 displayname
  // ═══════════════════════════════════════════════════════════════════════════

  group('BUG-15-S1: href 末段判定音频', () {
    test('S1-T1 (U1): displayname 无扩展名 + href 带 .mp3 → 识别为音频', () {
      // spec §3.1 Given：href="/music/Simon & Garfunkel.mp3"（真实 PROPFIND
      // 中 href 为百分号编码形态），displayname 不含扩展名也不含 ".mp3"。
      final file = NasFile.fromProps(
        href: '/music/Simon%20%26%20Garfunkel.mp3',
        props: {
          'displayname': 'Simon & Garfunkel',
          'resourcetype': '',
          'getcontentlength': '1000',
        },
      );

      expect(file.audioType, equals(AudioFileType.music),
          reason: 'href 末段 "Simon & Garfunkel.mp3" 应判定为音频'
              '（修复前用 displayname 判定 → null → 文件从列表消失）');
      // 否定断言：name 仍取 displayname（显示标签），不改成 href 末段
      expect(file.name, equals('Simon & Garfunkel'),
          reason: 'name 字段必须仍来自 displayname，不得改用 href 末段');
      expect(file.path, equals('/music/Simon & Garfunkel.mp3'),
          reason: 'path 应为解码后的完整 href');
    });

    test('S1-T2 (U2): displayname "My Book" + href .m4b → 分类为 audiobook', () {
      final file = NasFile.fromProps(
        href: '/books/book.m4b',
        props: {
          'displayname': 'My Book',
          'resourcetype': '',
          'getcontentlength': '2000',
        },
      );

      expect(file.audioType, equals(AudioFileType.audiobook),
          reason: '.m4b 判定必须基于 href 末段 "book.m4b"'
              '（修复前基于 displayname "My Book" → 误判为 music）');
      expect(file.name, equals('My Book'), reason: '显示标签仍为 displayname');
    });

    test('S1-T3: 去扩展名 displayname + 常见音频 href → music 且显示名保留', () {
      final file = NasFile.fromProps(
        href: '/music/song.mp3',
        props: {
          'displayname': 'song',
          'resourcetype': '',
          'getcontentlength': '3000',
        },
      );

      expect(file.audioType, equals(AudioFileType.music),
          reason: 'BUG 核心场景：displayname 无扩展名不得导致音频识别失败');
      expect(file.name, equals('song'), reason: '显示标签保留去扩展名的 displayname');
    });

    test('S1-T4 (否定): displayname 带扩展名但 href 无扩展名 → 不得识别为音频', () {
      // 识别源必须是 href：把 displayname 误当识别源时此用例会返回 music。
      final file = NasFile.fromProps(
        href: '/music/song',
        props: {
          'displayname': 'song.mp3',
          'resourcetype': '',
          'getcontentlength': '4000',
        },
      );

      expect(file.audioType, isNull,
          reason: 'href 末段 "song" 无音频扩展名 → audioType 必须为 null'
              '（若仍用 displayname 判定会误判为 music）');
      expect(file.name, equals('song.mp3'),
          reason: 'name 仍取 displayname，与识别结论解耦');
    });

    test('S1-T5 (否定): 非音频扩展名 href + 无扩展名 displayname → 不误收', () {
      final file = NasFile.fromProps(
        href: '/files/readme.txt',
        props: {
          'displayname': 'readme',
          'resourcetype': '',
        },
      );

      expect(file.audioType, isNull,
          reason: 'href 末段非音频扩展名，不得因改用 href 判定而放宽收录');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // BUG-15-S1 边界：URL 编码 / 大小写 / 多段扩展名 / 相对路径 / 退化 href
  // ═══════════════════════════════════════════════════════════════════════════

  group('BUG-15-S1 边界情况', () {
    test('大写扩展名 .MP3 + 无扩展名 displayname → music', () {
      final file = NasFile.fromProps(
        href: '/music/SONG.MP3',
        props: {'displayname': 'TITLE', 'resourcetype': ''},
      );
      expect(file.audioType, equals(AudioFileType.music),
          reason: '扩展名大小写不敏感（isAudioFile 内部 lowercase）');
    });

    test('多段扩展名 archive.tar.mp3 → 按末段 .mp3 识别', () {
      final file = NasFile.fromProps(
        href: '/music/archive.tar.mp3',
        props: {'displayname': 'archive', 'resourcetype': ''},
      );
      expect(file.audioType, equals(AudioFileType.music),
          reason: 'endsWith 语义下 file.tar.mp3 仍是 .mp3');
    });

    test('URL 编码中文文件名 → 解码后识别为音频', () {
      final file = NasFile.fromProps(
        href: '/music/%E4%B8%AD%E6%96%87%E6%AD%8C%E6%9B%B2.mp3',
        props: {'displayname': '中文歌曲', 'resourcetype': ''},
      );
      expect(file.audioType, equals(AudioFileType.music),
          reason: '百分号编码的中文 href 解码后应正常识别');
      expect(file.path, equals('/music/中文歌曲.mp3'));
    });

    test('URL 编码保留字符 %40 → 解码为 @ 后识别为音频', () {
      final file = NasFile.fromProps(
        href: '/music/live%40bbc.flac',
        props: {'displayname': 'live at bbc', 'resourcetype': ''},
      );
      expect(file.audioType, equals(AudioFileType.music),
          reason: '%40 解码为 @ 不影响扩展名判定');
      expect(file.path, equals('/music/live@bbc.flac'));
    });

    test('非法百分号序列 → 解码失败回退原 href，仍按末段判定', () {
      final file = NasFile.fromProps(
        href: '/music/100% pure.mp3',
        props: {'displayname': '100% pure', 'resourcetype': ''},
      );
      expect(file.audioType, equals(AudioFileType.music),
          reason: 'Uri.decodeFull 抛错时回退原始 href，不得影响音频识别');
    });

    test('相对 href（无前导斜杠）→ 末段判定一致', () {
      final file = NasFile.fromProps(
        href: 'music/song.mp3',
        props: {'displayname': 'song', 'resourcetype': ''},
      );
      expect(file.audioType, equals(AudioFileType.music),
          reason: 'split("/").last 对相对/绝对 href 行为一致');
    });

    test('空 href / 仅斜杠 href → audioType 安全降级为 null', () {
      final emptyHref = NasFile.fromProps(
        href: '',
        props: {'displayname': 'ghost', 'resourcetype': ''},
      );
      expect(emptyHref.audioType, isNull,
          reason: '空 href 末段为空串 → isAudioFile=false，不误判');

      final rootHref = NasFile.fromProps(
        href: '/',
        props: {'displayname': 'root', 'resourcetype': ''},
      );
      expect(rootHref.audioType, isNull, reason: '"/" 无文件名段，不得误判');
    });

    test('目录判定逻辑不变：带音频扩展名/关键词的目录仍不是音频', () {
      final m4bDir = NasFile.fromProps(
        href: '/books.m4b/',
        props: {'displayname': 'books.m4b', 'resourcetype': '<collection/>'},
      );
      expect(m4bDir.isDirectory, isTrue);
      expect(m4bDir.audioType, isNull,
          reason: '!isDirectory guard 必须继续阻止目录被分类');

      final keywordDir = NasFile.fromProps(
        href: '/audiobooks/',
        props: {'displayname': '有声书', 'resourcetype': '<collection/>'},
      );
      expect(keywordDir.isDirectory, isTrue);
      expect(keywordDir.audioType, isNull, reason: '目录名含"有声书"关键词也不得被分类为音频');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // BUG-15-INV1: 识别只依赖 href 末段——与 displayname 形态无关
  // ═══════════════════════════════════════════════════════════════════════════

  group('BUG-15-INV1: 识别一致性（displayname 无关）', () {
    test('同一 .mp3 href：displayname 去扩展名/带扩展名/缺失/空串 → 分类一致', () {
      NasFile build(Map<String, String?> props) => NasFile.fromProps(
            href: '/music/song.mp3',
            props: {'resourcetype': '', ...props},
          );

      final stripped = build({'displayname': 'song'});
      final full = build({'displayname': 'song.mp3'});
      final missing = build({});
      final empty = build({'displayname': ''});

      for (final f in [stripped, full, missing, empty]) {
        expect(f.audioType, equals(AudioFileType.music),
            reason: '分类只依赖 href 末段，displayname 形态不得影响结论');
      }

      // displayname 缺失/空串时 name 回退 href 末段（既有行为不变）
      expect(missing.name, equals('song.mp3'));
      expect(empty.name, equals('song.mp3'));
      // displayname 存在时 name 不受 href 影响
      expect(stripped.name, equals('song'));
    });

    test('同一 .m4b href：displayname 任意形态 → 一律 audiobook', () {
      NasFile build(Map<String, String?> props) => NasFile.fromProps(
            href: '/books/book.m4b',
            props: {'resourcetype': '', ...props},
          );

      expect(build({'displayname': 'My Book'}).audioType,
          equals(AudioFileType.audiobook));
      expect(build({}).audioType, equals(AudioFileType.audiobook),
          reason: 'displayname 缺失时同样按 href 末段分类');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // 端到端：原始 PROPFIND XML（转义 displayname + 编码 href）→ 识别正确
  // ═══════════════════════════════════════════════════════════════════════════

  group('端到端 XML 解析路径', () {
    test('spec U1 原始报文形态：&amp; 转义 displayname + %20/%26 编码 href', () {
      final xml = _wrapInMultiStatus(_fileResponse(
          '/music/Simon%20%26%20Garfunkel.mp3', 'Simon &amp; Garfunkel'));

      final result = WebDavClient.parsePropfindResponse(xml);

      expect(result, hasLength(1));
      final file = result.single;
      expect(file.audioType, equals(AudioFileType.music),
          reason: 'XML 反转义 + URL 解码后的 href 末段应判定为音频');
      expect(file.name, equals('Simon & Garfunkel'),
          reason: '显示标签为反转义后的 displayname，不得出现 &amp; 或编码字符');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // BRW 跨模块回归（spec §7）：directoryContentsProvider 过滤 — 文件不消失、分类正确
  // ═══════════════════════════════════════════════════════════════════════════

  group('BRW 回归: directoryContentsProvider 列表过滤', () {
    test('无扩展名 displayname 的音频文件不消失，非音频仍被排除', () async {
      final client = MockWebDavClient()
        ..returnListResult([
          // BUG 场景：displayname 去扩展名，href 有 .mp3
          NasFile.fromProps(
            href: '/music/song.mp3',
            props: {
              'displayname': 'song',
              'resourcetype': '',
              'getcontentlength': '1000',
            },
          ),
          // U2 场景：displayname "My Book"，href .m4b
          NasFile.fromProps(
            href: '/music/book.m4b',
            props: {
              'displayname': 'My Book',
              'resourcetype': '',
              'getcontentlength': '2000',
            },
          ),
          // 目录：保留
          NasFile.fromProps(
            href: '/music/subdir/',
            props: {'displayname': 'subdir', 'resourcetype': '<collection/>'},
          ),
          // 非音频：必须仍被排除（不得因修复放宽过滤）
          NasFile.fromProps(
            href: '/music/cover.jpg',
            props: {'displayname': 'cover', 'resourcetype': ''},
          ),
        ]);

      final container = makeContainer([
        activeConnectionProvider.overrideWith((ref) async => testConnection()),
        webDavClientProvider.overrideWithValue(client),
        secureStorageProvider
            .overrideWithValue(FakeSecureStorage()..setPassword(1, 'secret')),
      ]);
      addTearDown(container.dispose);

      final result =
          await container.read(directoryContentsProvider('/music').future);

      final names = result.map((f) => f.name).toList();
      expect(names, containsAll(<String>['song', 'My Book', 'subdir']),
          reason: '修复前 "song" 与 "My Book" 因 audioType=null 被过滤，整条消失');
      expect(names, isNot(contains('cover')), reason: '非音频文件仍须被过滤，不得放宽');

      final song = result.firstWhere((f) => f.name == 'song');
      expect(song.audioType, equals(AudioFileType.music));
      final book = result.firstWhere((f) => f.name == 'My Book');
      expect(book.audioType, equals(AudioFileType.audiobook),
          reason: '.m4b 应分类为 audiobook（修复前误判为 music）');
    });
  });
}
