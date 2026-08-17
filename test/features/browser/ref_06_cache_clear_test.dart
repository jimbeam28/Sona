// test/features/browser/ref_06_cache_clear_test.dart
// REF-06 门禁测试（spec docs/features/REF-06.md §5.4 指定文件）。
//
// 锚定 clearDirectoryCacheProvider 连接级精确匹配：
//   - S1 缺陷态：跨连接同名路径此前被后缀匹配误清（修复前全清 → 修复后保留）
//   - S3 子目录不被父路径清除命中
//   - S4 精确匹配只命中 '$connectionId:$path'，其它连接/其它路径保留
//   - S5 同连接子目录语义保持（清父不动子）
//   - S6 全量清除（path==null）行为与修复前一致
//   - S7 连接 id 为空 + path 非空 → 旧后缀匹配回退（不抛异常）
//   - S8 browser_screen 下拉刷新传活跃连接 id（通过浏览器 provider 直接断言）
//   - INV1 缓存 key 恒为 '${conn.id}:$path'；INV2 清父不删子

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nas_audio_player/features/browser/browser_provider.dart';
import 'package:nas_audio_player/features/browser/domain/cache_policy.dart';
import 'package:nas_audio_player/features/connection/connection_provider.dart';
import 'package:nas_audio_player/shared/models/nas_file.dart';

import '../../helpers/fake_webdav_client.dart';
import '../../helpers/fake_secure_storage.dart';
import '../../helpers/test_factories.dart';

CacheEntry<List<NasFile>> _entry(List<NasFile> files) {
  final t = DateTime(2026, 1, 1);
  return CacheEntry<List<NasFile>>(
      value: files, createdAt: t, lastAccessedAt: t);
}

void main() {
  group('REF-06: clearDirectoryCacheProvider 连接级精确匹配', () {
    test('REF-06-S1: 跨连接同名路径不再被误清（修复前缺陷态断言）', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(directoryCacheProvider.notifier).state = {
        '1:/music': _entry([testDir('music', '/music')]),
        '11:/music': _entry([testDir('music', '/music')]),
      };

      // 精确匹配：连接 1 下拉刷新只清连接 1 的 /music
      final removed = container.read(clearDirectoryCacheProvider)(1, '/music');

      expect(removed, equals(1), reason: '应精确命中 1 条（连接 1 的 /music）');
      expect(container.read(directoryCacheProvider).containsKey('1:/music'),
          isFalse,
          reason: '连接 1 的 /music 缓存应被清除');
      expect(container.read(directoryCacheProvider).containsKey('11:/music'),
          isTrue,
          reason: '连接 11 的同名路径缓存必须保留（修复前被误清）');
    });

    test('REF-06-S3: 子目录不被父路径清除命中', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(directoryCacheProvider.notifier).state = {
        '1:/music': _entry([testDir('music', '/music')]),
        '1:/music/sub': _entry([testDir('sub', '/music/sub')]),
      };

      final removed = container.read(clearDirectoryCacheProvider)(1, '/music');

      expect(removed, equals(1), reason: '只命中父路径 1 条');
      expect(container.read(directoryCacheProvider).containsKey('1:/music'),
          isFalse);
      expect(container.read(directoryCacheProvider).containsKey('1:/music/sub'),
          isTrue,
          reason: '子目录缓存不得被父路径清除命中');
    });

    test('REF-06-S4: 精确匹配只命中 连接id:path 组合', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(directoryCacheProvider.notifier).state = {
        '1:/music': _entry([testDir('music', '/music')]),
        '11:/music': _entry([testDir('music', '/music')]),
        '1:/books': _entry([testDir('books', '/books')]),
      };

      final removed = container.read(clearDirectoryCacheProvider)(1, '/music');

      expect(removed, equals(1));
      expect(container.read(directoryCacheProvider).containsKey('1:/music'),
          isFalse);
      expect(container.read(directoryCacheProvider).containsKey('11:/music'),
          isTrue,
          reason: '其它连接同路径必须保留');
      expect(container.read(directoryCacheProvider).containsKey('1:/books'),
          isTrue,
          reason: '同连接其它路径必须保留');
    });

    test('REF-06-S4 否定: 未命中时不发生任何 state 变更（返回 0）', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final before = <String, CacheEntry<List<NasFile>>>{
        '1:/music': _entry([testDir('music', '/music')]),
      };
      container.read(directoryCacheProvider.notifier).state = before;

      final removed =
          container.read(clearDirectoryCacheProvider)(1, '/missing');

      expect(removed, equals(0), reason: '未命中返回 0');
      expect(container.read(directoryCacheProvider).keys,
          equals(before.keys.toSet()));
    });

    test('REF-06-S5: 清除父路径不动子目录缓存、不重新拉取', () {
      final spy = SpyWebDavClient();
      final container = ProviderContainer(overrides: [
        webDavClientProvider.overrideWith((ref) => spy),
      ]);
      addTearDown(container.dispose);

      container.read(directoryCacheProvider.notifier).state = {
        '1:/music': _entry([testDir('music', '/music')]),
        '1:/music/sub': _entry([testDir('sub', '/music/sub')]),
        '1:/music/sub/deep': _entry([testDir('deep', '/music/sub/deep')]),
      };

      final removed = container.read(clearDirectoryCacheProvider)(1, '/music');

      expect(removed, equals(1));
      expect(container.read(directoryCacheProvider).containsKey('1:/music'),
          isFalse);
      expect(container.read(directoryCacheProvider).containsKey('1:/music/sub'),
          isTrue,
          reason: '子目录缓存必须保留');
      expect(
          container
              .read(directoryCacheProvider)
              .containsKey('1:/music/sub/deep'),
          isTrue,
          reason: '深层子目录缓存必须保留');
      expect(spy.listDirectoryCallCount, equals(0), reason: '清除缓存不得触发任何重新拉取');
    });

    test('REF-06-S6: 全量清除（path==null）跨连接全清、返回清除条数（S2 同语义）', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(directoryCacheProvider.notifier).state = {
        '1:/a': _entry([testDir('a', '/a')]),
        '11:/b': _entry([testDir('b', '/b')]),
        '2:/c': _entry([testDir('c', '/c')]),
      };

      final removed = container.read(clearDirectoryCacheProvider)(null, null);

      expect(removed, equals(3), reason: '全量清除返回原条数');
      expect(container.read(directoryCacheProvider), isEmpty,
          reason: '全量清除后 state 应为空（跨连接一并清空）');
    });

    test('REF-06-S7: 连接 id 为空 + path 非空 → 旧后缀匹配回退（不抛异常）', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(directoryCacheProvider.notifier).state = {
        '1:/music': _entry([testDir('music', '/music')]),
        '11:/music': _entry([testDir('music', '/music')]),
      };

      final removed =
          container.read(clearDirectoryCacheProvider)(null, '/music');

      expect(removed, equals(2), reason: '后缀回退清掉两条同名路径缓存');
      expect(container.read(directoryCacheProvider), isEmpty);
    });

    test('REF-06-S8: 下拉刷新传活跃连接 id，清除只命中本连接', () async {
      final spy = SpyWebDavClient()
        ..returnResult([
          testDir('music', '/music'),
          testAudio('song.mp3', '/music/song.mp3'),
        ]);
      final fakeStorage = FakeSecureStorage()..setPassword(1, 'test-password');

      final container = ProviderContainer(overrides: [
        webDavClientProvider.overrideWith((ref) => spy),
        activeConnectionProvider
            .overrideWith((ref) async => testConnection(id: 1)),
        secureStorageProvider.overrideWith((ref) => fakeStorage),
      ]);
      addTearDown(container.dispose);

      // 预置两条缓存：连接 1 与连接 2 的 /music
      container.read(directoryCacheProvider.notifier).state = {
        '1:/music': _entry([testDir('music', '/music')]),
        '2:/music': _entry([testDir('music', '/music')]),
      };

      // 模拟 browser_screen 下拉刷新（onRefresh 路径）：
      // connId = activeConnectionProvider.valueOrNull?.id → 1
      final conn = await container.read(activeConnectionProvider.future);
      final connId = conn?.id;
      expect(connId, equals(1), reason: '活跃连接 id 应为 1');

      final removed =
          container.read(clearDirectoryCacheProvider)(connId, '/music');
      expect(removed, equals(1));

      // 清除后不得残留当前连接的 /music 缓存条目；其它连接保留
      final cache = container.read(directoryCacheProvider);
      expect(cache.containsKey('1:/music'), isFalse);
      expect(cache.containsKey('2:/music'), isTrue);

      // 重新拉取当前连接 /music（spy 返回过滤后 1 个音频文件）
      final result =
          await container.read(directoryContentsProvider('/music').future);
      expect(result.length, equals(1), reason: '下拉刷新后重新拉取目录内容');
    });

    test('REF-06-INV1: 缓存 key 恒为 连接id:path 形态', () async {
      final spy = SpyWebDavClient()
        ..returnResult([
          testDir('music', '/music'),
          testAudio('song.mp3', '/music/song.mp3'),
        ]);
      final fakeStorage = FakeSecureStorage()..setPassword(1, 'test-password');

      final container = ProviderContainer(overrides: [
        webDavClientProvider.overrideWith((ref) => spy),
        activeConnectionProvider
            .overrideWith((ref) async => testConnection(id: 1)),
        secureStorageProvider.overrideWith((ref) => fakeStorage),
      ]);
      addTearDown(container.dispose);

      await container.read(directoryContentsProvider('/music').future);

      final cache = container.read(directoryCacheProvider);
      expect(cache.containsKey('1:/music'), isTrue,
          reason: '写入路径 key 为 \'1:/music\'');
      expect(cache.containsKey('1:/other'), isFalse);
    });

    test('REF-06-INV2: 清除父路径永不删除其子目录缓存条目', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(directoryCacheProvider.notifier).state = {
        '1:/root': _entry([testDir('root', '/root')]),
        '1:/root/child': _entry([testDir('child', '/root/child')]),
      };

      container.read(clearDirectoryCacheProvider)(1, '/root');

      expect(container.read(directoryCacheProvider).containsKey('1:/root'),
          isFalse);
      expect(
          container.read(directoryCacheProvider).containsKey('1:/root/child'),
          isTrue,
          reason: 'INV2: 子目录条目必须保留');
    });

    test('REF-06-ALG1-resolveRemoveKeys: 各形态', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      // 精确全等主流程：connectionId=1, path=/music
      container.read(directoryCacheProvider.notifier).state = {
        '1:/music': _entry([testDir('music', '/music')]),
        '11:/music': _entry([testDir('music', '/music')]),
        '1:/music/sub': _entry([testDir('sub', '/music/sub')]),
      };
      expect(container.read(clearDirectoryCacheProvider)(1, '/music'), 1);
      expect(container.read(directoryCacheProvider).containsKey('1:/music'),
          isFalse);
      expect(container.read(directoryCacheProvider).containsKey('11:/music'),
          isTrue);
      expect(container.read(directoryCacheProvider).containsKey('1:/music/sub'),
          isTrue);

      // 后缀回退边界：connectionId=null
      container.read(directoryCacheProvider.notifier).state = {
        '1:/music': _entry([testDir('music', '/music')]),
        '11:/music': _entry([testDir('music', '/music')]),
      };
      expect(container.read(clearDirectoryCacheProvider)(null, '/music'), 2);
      expect(container.read(directoryCacheProvider), isEmpty);

      // 未命中边界：connectionId=1, path=/missing
      container.read(directoryCacheProvider.notifier).state = {
        '1:/music': _entry([testDir('music', '/music')]),
      };
      expect(container.read(clearDirectoryCacheProvider)(1, '/missing'), 0);
      expect(container.read(directoryCacheProvider).containsKey('1:/music'),
          isTrue,
          reason: '未命中时 state 不变');

      // 子目录路径精确命中自身边界
      container.read(directoryCacheProvider.notifier).state = {
        '1:/music': _entry([testDir('music', '/music')]),
        '1:/music/sub': _entry([testDir('sub', '/music/sub')]),
      };
      expect(container.read(clearDirectoryCacheProvider)(1, '/music/sub'), 1);
      expect(container.read(directoryCacheProvider).containsKey('1:/music'),
          isTrue,
          reason: '父条目保留');
      expect(container.read(directoryCacheProvider).containsKey('1:/music/sub'),
          isFalse);
    });
  });
}
