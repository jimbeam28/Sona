// test/features/settings/set_01_test.dart
//
// SET-01 — 设置页"清除目录缓存" 测试先行（dev-exe Agent A 产出）。
//
// 覆盖 spec docs/features/SET-01.md §3（Scenario S1~S7）与 §4（不变量 INV1~INV3）。
// 每条 status: new 的否定断言都有对应 expect 落地（见各 test 内注释）。
//
// ── 工具约定 ─────────────────────────────────────────────────────────────────
//   Provider 层测试（S1/S2/S3/S6/S7/INV1/INV2）：ProviderContainer + SpyWebDavClient。
//   Widget 层测试（S4/S5）：ProviderScope overrides pump SettingsScreen
//     （参考 settings_test.dart 的 pumpSettingsScreen；只测清除 tile，不触发导航项）。
//   架构不变量（INV3）：读源码断言 settings 不直接 import browser（运行时读 lib，
//     非分析期读 lib）。
//
// ── 按 spec §2 给出的公开路径写 import（不读 lib/）────────────────────────────
//   directoryCacheProvider / clearDirectoryCacheProvider / directoryContentsProvider
//     ← package:nas_audio_player/features/browser/browser_provider.dart
//   CacheEntry(value:, createdAt:)（及 .value / .createdAt / .lastAccessedAt）
//     ← package:nas_audio_player/features/browser/domain/cache_policy.dart
//
// ── 预置缓存手法（spec §2.2）──────────────────────────────────────────────────
//   directoryCacheProvider 是 StateProvider<Map<String, CacheEntry<List<NasFile>>>>，
//   通过 container.read(directoryCacheProvider.notifier).state = {...} 预置。
//
// 说明：本文件按 spec 编写，针对尚未落地的实现（clearDirectoryCacheProvider 现为
// void，spec 要求改为 int），故部分用例会编译失败或 FAIL——这是测试先行的预期结果。

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nas_audio_player/features/browser/browser_provider.dart';
import 'package:nas_audio_player/features/browser/domain/cache_policy.dart';
import 'package:nas_audio_player/features/settings/settings_screen.dart';
import 'package:nas_audio_player/features/connection/connection_provider.dart';
import 'package:nas_audio_player/shared/models/nas_file.dart';

import '../../helpers/fake_secure_storage.dart';
import '../../helpers/fake_webdav_client.dart';
import '../../helpers/test_factories.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// 小工具
// ═══════════════════════════════════════════════════════════════════════════════

/// 构造一条目录缓存条目。createdAt 默认取"1 秒前"，保证：
///   - 未过期（TTL 远大于 1 秒）→ S6/S7 能命中；
///   - lastAccessedAt 初值落后于"现在"→ S6 断言刷新时有明确时间差，避免同微秒抖动。
CacheEntry<List<NasFile>> _entry(List<NasFile> value, {DateTime? createdAt}) {
  return CacheEntry(
    value: value,
    createdAt: createdAt ?? DateTime.now().subtract(const Duration(seconds: 1)),
  );
}

/// pump SettingsScreen，预置 SharedPreferences 与目录缓存（S4/S5 用）。
Future<ProviderContainer> _pumpSettings(
  WidgetTester tester, {
  required Map<String, CacheEntry<List<NasFile>>> cache,
}) async {
  // 默认测试表面 800×600@3x 逻辑视口仅 ~200px 高，"存储" section 位于
  // ListView 下方 ~510px 处，懒加载不会构建它。放大视口至整页高度
  // （同 ply_14_test.dart 手法），保证清除缓存项进入构建范围。
  tester.view.physicalSize = const Size(800, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() => tester.view.resetPhysicalSize());
  addTearDown(() => tester.view.resetDevicePixelRatio());
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWith((ref) => prefs),
        directoryCacheProvider.overrideWith((ref) => cache),
      ],
      child: const MaterialApp(home: SettingsScreen()),
    ),
  );
  await tester.pumpAndSettle();
  return ProviderScope.containerOf(tester.element(find.byType(SettingsScreen)));
}

void main() {
  // ═════════════════════════════════════════════════════════════════════════════
  // §3.1 清除全部缓存 — S1 / S2 / S3（provider 层）
  // ═════════════════════════════════════════════════════════════════════════════

  group('SET-01-S1/S2/S3: 清除缓存 provider 层', () {
    // ── SET-01-S1 ─────────────────────────────────────────────────────────────
    test('SET-01-S1 (REF-06-S2): 全量清除返回条数并使缓存清空', () {
      // 否定断言"不发起网络请求"的落地：把 SpyWebDavClient 接线为 WebDAV client，
      // 清除后断言 listDirectory 调用次数为 0。
      final spy = SpyWebDavClient();
      final container = ProviderContainer(overrides: [
        webDavClientProvider.overrideWith((ref) => spy),
      ]);
      addTearDown(container.dispose);

      // Given directoryCacheProvider 中有 N 条缓存（N=3，N ≥ 1）
      container.read(directoryCacheProvider.notifier).state = {
        '1:/a': _entry([testDir('a', '/a')]),
        '1:/b': _entry([testDir('b', '/b')]),
        '1:/c': _entry([testDir('c', '/c')]),
      };

      // 否定断言"队列/连接/导航不变"的前置快照：清除前 read，清除后比较 unchanged。
      final queueBefore = container.read(currentPlayQueueProvider);
      final connBefore = container.read(activeConnectionProvider);
      final navBefore = container.read(navigationStackProvider);

      // When 调用 ref.read(clearDirectoryCacheProvider)(null)
      final removed = container.read(clearDirectoryCacheProvider)(null, null);

      // Then 调用返回 N（int）
      expect(removed, equals(3), reason: '全量清除应返回被清除的缓存条数 N=3');
      // And directoryCacheProvider.state 变为 {}
      expect(container.read(directoryCacheProvider), isEmpty,
          reason: '全量清除后 directoryCacheProvider.state 应为 {}');
      // 否定断言：不发起任何网络请求（WebDavClient.listDirectory 不被调用）
      expect(spy.listDirectoryCallCount, equals(0), reason: '清除缓存不得发起任何网络请求');
      // 否定断言：currentPlayQueueProvider / activeConnectionProvider /
      // navigationStackProvider 均不变
      expect(container.read(currentPlayQueueProvider), equals(queueBefore),
          reason: '清除缓存不得改动播放队列 currentPlayQueueProvider');
      expect(container.read(activeConnectionProvider), equals(connBefore),
          reason: '清除缓存不得改动活跃连接 activeConnectionProvider');
      expect(container.read(navigationStackProvider), equals(navBefore),
          reason: '清除缓存不得改动导航位置 navigationStackProvider');
    });

    // ── SET-01-S2 ─────────────────────────────────────────────────────────────
    test('SET-01-S2: 按路径清除返回命中条数且未命中键 CacheEntry 不变', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      // Given 缓存含键 "1:/music" 与 "1:/audiobook"
      final audiobookBefore =
          _entry([testAudio('book.m4b', '/audiobook/book.m4b')]);
      container.read(directoryCacheProvider.notifier).state = {
        '1:/music': _entry([testDir('music', '/music')]),
        '1:/audiobook': audiobookBefore,
      };

      // When 调用 clearDirectoryCacheProvider('/music')
      final removed = container.read(clearDirectoryCacheProvider)(1, '/music');

      // Then 返回 1（仅 "1:/music" 被删）
      expect(removed, equals(1), reason: '按路径 /music 清除应只命中并返回 1 条');
      // And "1:/audiobook" 仍在缓存中
      final cacheAfter = container.read(directoryCacheProvider);
      expect(cacheAfter.containsKey('1:/music'), isFalse,
          reason: '"1:/music" 应被删除');
      expect(cacheAfter.containsKey('1:/audiobook'), isTrue,
          reason: '"1:/audiobook" 不应被删除（后缀不匹配 /music）');
      // 否定断言：未命中键 "1:/audiobook" 的 CacheEntry 不变（value 与 createdAt 原值）
      final audiobookAfter = cacheAfter['1:/audiobook']!;
      expect(audiobookAfter.value, equals(audiobookBefore.value),
          reason: '未命中键的 CacheEntry.value 应保持原值');
      expect(audiobookAfter.createdAt, equals(audiobookBefore.createdAt),
          reason: '未命中键的 CacheEntry.createdAt 应保持原值');
    });

    // ── SET-01-S3 ─────────────────────────────────────────────────────────────
    test('SET-01-S3: 空缓存清除返回 0、保持空、不抛异常、不发网络', () {
      final spy = SpyWebDavClient();
      final container = ProviderContainer(overrides: [
        webDavClientProvider.overrideWith((ref) => spy),
      ]);
      addTearDown(container.dispose);

      // Given directoryCacheProvider.state == {}
      container.read(directoryCacheProvider.notifier).state = {};

      // When 调用 clearDirectoryCacheProvider(null)
      // 否定断言"不抛异常"：调用正常完成即满足（若抛异常本用例会直接失败）。
      final removed = container.read(clearDirectoryCacheProvider)(null, null);

      // Then 返回 0
      expect(removed, equals(0), reason: '空缓存清除应返回 0');
      // And state 保持 {}
      expect(container.read(directoryCacheProvider), isEmpty,
          reason: '空缓存清除后 state 应保持 {}');
      // 否定断言：不发起网络请求
      expect(spy.listDirectoryCallCount, equals(0), reason: '空缓存清除不得发起任何网络请求');
    });
  });

  // ═════════════════════════════════════════════════════════════════════════════
  // §3.2 设置页入口 — S4 / S5（widget 层）
  // ═════════════════════════════════════════════════════════════════════════════

  group('SET-01-S4/S5: 设置页清除目录缓存入口', () {
    // ── SET-01-S4 ─────────────────────────────────────────────────────────────
    testWidgets('SET-01-S4 (REF-06-S9): 设置页"清除目录缓存"项显示条数并执行清除', (tester) async {
      // Given directoryCacheProvider 有 3 条缓存
      final container = await _pumpSettings(tester, cache: {
        '1:/a': _entry([testDir('a', '/a')]),
        '1:/b': _entry([testDir('b', '/b')]),
        '1:/c': _entry([testDir('c', '/c')]),
      });

      // Then 存在 title="清除目录缓存" 的 ListTile，subtitle 显示"当前缓存 3 条目录"
      expect(find.text('清除目录缓存'), findsOneWidget,
          reason: '设置页应显示 title="清除目录缓存" 的入口');
      expect(find.text('当前缓存 3 条目录'), findsOneWidget,
          reason: 'subtitle 应显示当前缓存条数"当前缓存 3 条目录"');

      // When 点击该 ListTile
      await tester.tap(find.text('清除目录缓存'));
      await tester.pumpAndSettle();

      // Then SnackBar 文案为"已清除 3 条目录缓存"
      expect(find.text('已清除 3 条目录缓存'), findsOneWidget,
          reason: 'SnackBar 文案应为"已清除 3 条目录缓存"');
      // And directoryCacheProvider.state == {}
      expect(container.read(directoryCacheProvider), isEmpty,
          reason: '点击清除后 directoryCacheProvider.state 应为 {}');
      // 否定断言：不弹出任何确认 Dialog（直接执行）
      expect(find.byType(AlertDialog), findsNothing,
          reason: '清除缓存应直接执行，不弹出任何确认 Dialog');
      // 否定断言：页面不跳转（仍停留在设置页，无新路由压栈）
      expect(find.byType(SettingsScreen), findsOneWidget,
          reason: '清除缓存后应仍停留在设置页，不发生页面跳转');
    });

    // ── SET-01-S5 ─────────────────────────────────────────────────────────────
    testWidgets('SET-01-S5: 空缓存时点击提示"没有可清除的缓存"', (tester) async {
      // Given directoryCacheProvider.state == {}
      final container = await _pumpSettings(
        tester,
        cache: <String, CacheEntry<List<NasFile>>>{},
      );
      expect(find.text('清除目录缓存'), findsOneWidget, reason: '空缓存时入口仍应显示');

      // When 点击"清除目录缓存"
      await tester.tap(find.text('清除目录缓存'));
      await tester.pumpAndSettle();

      // Then SnackBar 文案为"没有可清除的缓存"
      expect(find.text('没有可清除的缓存'), findsOneWidget,
          reason: '空缓存清除时 SnackBar 文案应为"没有可清除的缓存"');
      // 否定断言：directoryCacheProvider.state 保持 {}（不写入任何键）
      expect(container.read(directoryCacheProvider), isEmpty,
          reason: '空缓存清除后 state 应保持 {}，不写入任何键');
    });
  });

  // ═════════════════════════════════════════════════════════════════════════════
  // §3.3 现有行为逆抽 — S6 / S7（回归守护）
  // ═════════════════════════════════════════════════════════════════════════════

  group('SET-01-S6/S7: 目录缓存命中与键格式（回归守护）', () {
    // ── SET-01-S6 ─────────────────────────────────────────────────────────────
    test('SET-01-S6: 目录加载缓存命中不发网络请求且刷新 lastAccessedAt', () async {
      // spy 返回一份与缓存不同的"网络结果"，用于区分命中 vs 走网络。
      final spy = SpyWebDavClient()
        ..returnResult(
            [testAudio('from_network.mp3', '/music/from_network.mp3')]);
      final container = ProviderContainer(overrides: [
        webDavClientProvider.overrideWith((ref) => spy),
        activeConnectionProvider.overrideWith((ref) => testConnection(id: 1)),
      ]);
      addTearDown(container.dispose);

      // Given "1:/music" 有未过期缓存
      final cached = [testAudio('song.mp3', '/music/song.mp3')];
      container.read(directoryCacheProvider.notifier).state = {
        '1:/music': _entry(cached), // createdAt = 1 秒前，未过期
      };
      final before = container.read(directoryCacheProvider)['1:/music']!;

      // When read directoryContentsProvider('/music')
      final result =
          await container.read(directoryContentsProvider('/music').future);

      // Then 返回缓存列表（fromCache 语义，不是 spy 的网络结果）
      expect(result, equals(cached), reason: '缓存命中应返回缓存列表，而非网络结果');
      // And WebDavClient 不被调用
      expect(spy.listDirectoryCallCount, equals(0),
          reason: '缓存命中不得调用 WebDavClient.listDirectory');
      // And 该键 lastAccessedAt 被刷新
      final after = container.read(directoryCacheProvider)['1:/music']!;
      expect(after.lastAccessedAt.isAfter(before.lastAccessedAt), isTrue,
          reason: '缓存命中读取应刷新该键 lastAccessedAt（LRU 访问语义）');
    });

    // ── SET-01-S7 ─────────────────────────────────────────────────────────────
    test('SET-01-S7: 缓存键格式恒为 connectionId:path', () async {
      final spy = SpyWebDavClient()
        ..returnResult([testAudio('x.mp3', '/music/x.mp3')]);
      final container = ProviderContainer(overrides: [
        webDavClientProvider.overrideWith((ref) => spy),
        activeConnectionProvider.overrideWith((ref) => testConnection(id: 1)),
      ]);
      addTearDown(container.dispose);

      // Given connectionId=1, path='/music'，预置键 "1:/music"
      container.read(directoryCacheProvider.notifier).state = {
        '1:/music': _entry([testAudio('song.mp3', '/music/song.mp3')]),
      };

      // When 目录加载 '/music'（活跃连接 id=1）
      await container.read(directoryContentsProvider('/music').future);

      // Then 命中预置键 "1:/music" → 不发网络。若键格式不是 connectionId:path，
      // 预置键不会被命中，必然走网络（spy 计数 > 0），故计数为 0 即证明键格式正确。
      expect(spy.listDirectoryCallCount, equals(0),
          reason: '缓存键应为 connectionId:path="1:/music"，命中预置键则不发网络');
      expect(container.read(directoryCacheProvider).containsKey('1:/music'),
          isTrue,
          reason: '缓存键应包含 "1:/music"');
    });
  });

  // ═════════════════════════════════════════════════════════════════════════════
  // §4 不变量 — INV1 / INV2 / INV3
  // ═════════════════════════════════════════════════════════════════════════════

  group('SET-01-INV1/INV2/INV3: 不变量', () {
    // ── SET-01-INV1 ───────────────────────────────────────────────────────────
    test('SET-01-INV1: 清除缓存任何分支都不改队列/连接/导航/排序', () {
      final spy = SpyWebDavClient();
      final container = ProviderContainer(overrides: [
        webDavClientProvider.overrideWith((ref) => spy),
      ]);
      addTearDown(container.dispose);

      container.read(directoryCacheProvider.notifier).state = {
        '1:/a': _entry([testDir('a', '/a')]),
        '1:/b': _entry([testDir('b', '/b')]),
      };

      // 清除前快照
      final queueBefore = container.read(currentPlayQueueProvider);
      final connBefore = container.read(activeConnectionProvider);
      final navBefore = container.read(navigationStackProvider);
      final sortBefore = container.read(sortOptionProvider);

      // 走两个分支：path==null 全量清 + path 非空按后缀清
      container.read(clearDirectoryCacheProvider)(null, null);
      container.read(directoryCacheProvider.notifier).state = {
        '1:/a': _entry([testDir('a', '/a')]),
      };
      container.read(clearDirectoryCacheProvider)(1, '/a');

      // 四个 provider 均不变
      expect(container.read(currentPlayQueueProvider), equals(queueBefore),
          reason:
              'INV1: clearDirectoryCacheProvider 不得修改 currentPlayQueueProvider');
      expect(container.read(activeConnectionProvider), equals(connBefore),
          reason:
              'INV1: clearDirectoryCacheProvider 不得修改 activeConnectionProvider');
      expect(container.read(navigationStackProvider), equals(navBefore),
          reason:
              'INV1: clearDirectoryCacheProvider 不得修改 navigationStackProvider');
      expect(container.read(sortOptionProvider), equals(sortBefore),
          reason: 'INV1: clearDirectoryCacheProvider 不得修改 sortOptionProvider');
    });

    // ── SET-01-INV2 ───────────────────────────────────────────────────────────
    test('SET-01-INV2: path==null 清除后目录内容下一次读取触发重新加载', () async {
      final spy = SpyWebDavClient()
        ..returnResult([testAudio('reload.mp3', '/a/reload.mp3')]);
      // 重新加载路径（缓存未命中）会读 secureStorageProvider 取密码
      // （browser_provider.dart:80-83）；真实 FlutterSecureStorage 在测试环境
      // 无平台实现 → MissingPluginException。按 brw_05 惯例注入 FakeSecureStorage。
      final fakeStorage = FakeSecureStorage()..setPassword(1, 'test-password');
      final container = ProviderContainer(overrides: [
        webDavClientProvider.overrideWith((ref) => spy),
        activeConnectionProvider.overrideWith((ref) => testConnection(id: 1)),
        secureStorageProvider.overrideWith((ref) => fakeStorage),
      ]);
      addTearDown(container.dispose);

      // 预置 "1:/a" 未过期缓存
      container.read(directoryCacheProvider.notifier).state = {
        '1:/a': _entry([testAudio('cached.mp3', '/a/cached.mp3')]),
      };

      // 首次读取命中缓存：返回缓存内容，不发网络，family 进入已加载态
      final first =
          await container.read(directoryContentsProvider('/a').future);
      expect(first.single.path, equals('/a/cached.mp3'), reason: '首次读取应命中缓存');
      expect(spy.listDirectoryCallCount, equals(0), reason: '命中缓存不发网络');

      // path==null 清除 → 缓存清空 + family 全量 invalidate
      final removed = container.read(clearDirectoryCacheProvider)(null, null);
      expect(removed, equals(1));
      expect(container.read(directoryCacheProvider), isEmpty);

      // 下一次读取必须触发重新加载：缓存已空 → 走网络（spy 计数 0→1）
      final second =
          await container.read(directoryContentsProvider('/a').future);
      expect(spy.listDirectoryCallCount, equals(1),
          reason: 'INV2: 清除后下一次读取应重新加载（family 已被 invalidate），而非返回陈旧缓存');
      expect(second.single.path, equals('/a/reload.mp3'),
          reason: 'INV2: 重新加载应取回网络新数据，证明无陈旧目录内容');
    });

    // ── SET-01-INV3 ───────────────────────────────────────────────────────────
    test('SET-01-INV3: settings feature 不得直接 import browser feature', () {
      // 架构不变量：settings_screen.dart 只能经 shared/di/providers.dart 引用缓存
      // provider，严禁出现 features/browser/ 的直接 import。
      // （运行时读源码，非分析期读 lib。）
      final file = File('lib/features/settings/settings_screen.dart');
      expect(file.existsSync(), isTrue, reason: 'settings_screen.dart 应存在');
      final content = file.readAsStringSync();
      expect(content.contains('features/browser/'), isFalse,
          reason: 'INV3: settings_screen.dart 不得直接 import features/browser/，'
              '须经 shared/di/providers.dart 桥接');
    });
  });
}
