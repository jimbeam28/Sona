// test/shared/webdav_paths_normalize_test.dart
// cr-20260804-1922 §5 O1: NET1 遗留持久化绝对路径 — 读取时归一化纯函数单测
//
// NET1（431d444）之后 listDirectory 返回相对连接根的路径（`/` = 根），
// 修复前持久化的数据存的是服务端绝对路径（含连接根前缀）。
// normalizeStoredPath 在读取时剥离连接根前缀，语义与
// WebDavClient._relativisePath 完全一致：
//   - 连接根为空（`/`，服务端根挂载）→ 原样返回（旧绝对路径 == 相对根路径）
//   - stored == 根 → `/`
//   - stored 以 `根/` 开头 → 剥成相对连接根形态（保留前导 `/`）
//   - 不匹配 → 原样返回（不得破坏本来正确的数据）
//   - 幂等：归一化两次 == 一次
//   - 前缀边界：`/mus` 不得误匹配 `/music/...`

import 'package:flutter_test/flutter_test.dart';
import 'package:nas_audio_player/shared/webdav_paths.dart';

void main() {
  group('normalizeStoredPath — 连接根为空/服务端根挂载', () {
    test('根为 `/` → 原样返回（旧绝对路径即相对根路径）', () {
      expect(
        normalizeStoredPath('/music/a.mp3', basePath: '/'),
        equals('/music/a.mp3'),
      );
    });

    test('根为空字符串 → 原样返回', () {
      expect(
        normalizeStoredPath('/music/a.mp3', basePath: ''),
        equals('/music/a.mp3'),
      );
    });
  });

  group('normalizeStoredPath — 匹配剥离', () {
    test('legacy 绝对路径剥成相对连接根（保留前导 /）', () {
      expect(
        normalizeStoredPath('/dav/music/a.mp3', basePath: '/dav'),
        equals('/music/a.mp3'),
      );
    });

    test('多级连接根同样剥离', () {
      expect(
        normalizeStoredPath('/dav/music/sub/a.mp3', basePath: '/dav/music'),
        equals('/sub/a.mp3'),
      );
    });

    test('stored == 连接根（目录自引用）→ `/`', () {
      expect(normalizeStoredPath('/dav', basePath: '/dav'), equals('/'));
    });

    test('根参数不带前导斜杠 → 归一后仍正确剥离', () {
      expect(
        normalizeStoredPath('/dav/music/a.mp3', basePath: 'dav'),
        equals('/music/a.mp3'),
      );
    });

    test('根参数带尾随斜杠 → 归一后仍正确剥离', () {
      expect(
        normalizeStoredPath('/dav/music/a.mp3', basePath: '/dav/'),
        equals('/music/a.mp3'),
      );
    });

    test('已是相对连接根形态的正确数据 → 原样（不得破坏）', () {
      expect(
        normalizeStoredPath('/music/a.mp3', basePath: '/dav'),
        equals('/music/a.mp3'),
      );
    });
  });

  group('normalizeStoredPath — 前缀边界不误伤', () {
    test('`/mus` 不得误匹配 `/music/...`', () {
      expect(
        normalizeStoredPath('/music/a.mp3', basePath: '/mus'),
        equals('/music/a.mp3'),
        reason: '边界: /music 不是 /mus 的子路径',
      );
    });

    test('根是 stored 的非边界前缀（无 / 衔接）→ 不剥离', () {
      expect(
        normalizeStoredPath('/davx/a.mp3', basePath: '/dav'),
        equals('/davx/a.mp3'),
      );
    });

    test('stored 比根更短 → 不剥离', () {
      expect(
        normalizeStoredPath('/da', basePath: '/dav'),
        equals('/da'),
      );
    });
  });

  group('normalizeStoredPath — 不匹配原样返回', () {
    test('完全不同前缀 → 原样', () {
      expect(
        normalizeStoredPath('/other/a.mp3', basePath: '/dav'),
        equals('/other/a.mp3'),
      );
    });

    test('空字符串 stored → 原样', () {
      expect(normalizeStoredPath('', basePath: '/dav'), equals(''));
    });
  });

  group('normalizeStoredPath — 幂等', () {
    test('归一化两次 == 一次（剥离场景）', () {
      final once = normalizeStoredPath('/dav/music/a.mp3', basePath: '/dav');
      final twice = normalizeStoredPath(once, basePath: '/dav');
      expect(twice, equals(once));
      expect(once, equals('/music/a.mp3'));
    });

    test('归一化两次 == 一次（原样场景）', () {
      final once = normalizeStoredPath('/music/a.mp3', basePath: '/dav');
      final twice = normalizeStoredPath(once, basePath: '/dav');
      expect(twice, equals(once));
    });

    test('归一化两次 == 一次（根为 `/` 场景）', () {
      final once = normalizeStoredPath('/music/a.mp3', basePath: '/');
      final twice = normalizeStoredPath(once, basePath: '/');
      expect(twice, equals(once));
    });
  });

  group('webDavConnectionRoot — 连接根计算（归一化入参来源）', () {
    test('挂载点在 basePath 字段', () {
      expect(
        webDavConnectionRoot('http://nas.local:5005', '/dav'),
        equals('/dav'),
      );
    });

    test('挂载点在 URL path', () {
      expect(
        webDavConnectionRoot('http://nas.local:5005/dav', '/'),
        equals('/dav'),
      );
    });

    test('两处拼接', () {
      expect(
        webDavConnectionRoot('http://nas.local:5005/dav', 'music'),
        equals('/dav/music'),
      );
    });

    test('服务端根挂载 → `/`', () {
      expect(
        webDavConnectionRoot('http://nas.local:5005', '/'),
        equals('/'),
      );
    });
  });
}
