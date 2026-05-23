// test/features/browser/brw_05_test.dart
// BRW-05: 目录内容缓存 — automated test suite
//
// Unit tests (BRW-T29~T33): in-memory cache behaviour for directory contents

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nas_audio_player/core/network/webdav_client.dart';
import 'package:nas_audio_player/features/browser/browser_provider.dart';
import 'package:nas_audio_player/features/connection/connection_provider.dart';
import 'package:nas_audio_player/shared/models/connection_config.dart';
import 'package:nas_audio_player/shared/models/nas_file.dart';

// ── Manual mocks ────────────────────────────────────────────────────────────────

/// Tracks [listDirectory] invocations so tests can assert cache behaviour.
class _MockWebDavClient implements WebDavClientInterface {
  int listDirectoryCallCount = 0;
  List<String> calledPaths = <String>[];
  List<NasFile> _result = const [];

  void returnResult(List<NasFile> result) {
    _result = result;
  }

  @override
  Future<List<NasFile>> listDirectory({
    required String url,
    required String username,
    required String password,
    required String path,
  }) async {
    listDirectoryCallCount++;
    calledPaths.add(path);
    return _result;
  }

  @override
  Future<WebDavValidationResult> validate({
    required String url,
    required String username,
    required String password,
    String basePath = '/',
  }) async {
    throw UnimplementedError('validate not needed for BRW-05 tests');
  }
}

/// Fake secure storage that returns a canned password from an in-memory map.
class _FakeSecureStorage extends FlutterSecureStorage {
  final Map<String, String> _data = {};

  void setPassword(int connectionId, String password) {
    _data['connection_password_$connectionId'] = password;
  }

  @override
  Future<String?> read({
    required String key,
    IOSOptions? iOptions = IOSOptions.defaultOptions,
    AndroidOptions? aOptions = AndroidOptions.defaultOptions,
    LinuxOptions? lOptions = LinuxOptions.defaultOptions,
    WindowsOptions? wOptions = WindowsOptions.defaultOptions,
    MacOsOptions? mOptions = MacOsOptions.defaultOptions,
    WebOptions? webOptions = WebOptions.defaultOptions,
  }) async {
    return _data[key];
  }
}

// ── Test helpers ────────────────────────────────────────────────────────────────

/// Builds a directory [NasFile] for test assertions.
NasFile _dir(String name, String path) {
  return NasFile(name: name, path: path, isDirectory: true);
}

/// Builds an audio [NasFile] for test assertions.
NasFile _audio(String name, String path) {
  return NasFile(
    name: name,
    path: path,
    isDirectory: false,
    audioType: AudioFileType.music,
  );
}

/// Creates a [ConnectionConfig] for test use.
ConnectionConfig _connection({int id = 1, String name = 'Test'}) {
  return ConnectionConfig(
    id: id,
    name: name,
    url: 'http://192.168.1.1:8080',
    username: 'admin',
    basePath: '/',
    isActive: true,
    createdAt: DateTime(2024),
    updatedAt: DateTime(2024),
  );
}

/// Raw entries returned by the mock WebDAV client for the /music directory.
/// Provider logic will filter out the self-reference and keep only audio files.
List<NasFile> _musicRawEntries() {
  return [
    _dir('music', '/music'), // self-reference — filtered out by provider
    _audio('song.mp3', '/music/song.mp3'),
    _audio('track.flac', '/music/track.flac'),
  ];
}

// ═════════════════════════════════════════════════════════════════════════════
// Unit tests — BRW-T29~T33
// ═════════════════════════════════════════════════════════════════════════════

void main() {
  group('BRW-T29~T33: directory cache', () {
    // ── BRW-T29: First load makes one PROPFIND request ─────────────────────────

    test('BRW-T29: first load of /music makes one PROPFIND request', () async {
      final mockClient = _MockWebDavClient();
      mockClient.returnResult(_musicRawEntries());

      final fakeStorage = _FakeSecureStorage();
      fakeStorage.setPassword(1, 'test-password');

      final container = ProviderContainer(
        overrides: [
          webDavClientProvider.overrideWith((ref) => mockClient),
          activeConnectionProvider
              .overrideWith((ref) async => _connection(id: 1)),
          secureStorageProvider.overrideWith((ref) => fakeStorage),
        ],
      );
      addTearDown(container.dispose);

      // Load /music for the first time
      final result =
          await container.read(directoryContentsProvider('/music').future);

      // Provider filters out the self-ref dir, keeps 2 audio files.
      expect(result.length, equals(2),
          reason: '应返回除自引用外的 2 个音频文件');
      expect(result[0].name, equals('song.mp3'));
      expect(result[1].name, equals('track.flac'));

      // listDirectory should have been called exactly once
      expect(mockClient.listDirectoryCallCount, equals(1),
          reason: '首次加载应触发一次 listDirectory 调用');
      expect(mockClient.calledPaths, contains('/music'),
          reason: '应请求 /music 路径');

      // Verify the cache now contains the entry
      final cache = container.read(directoryCacheProvider);
      expect(cache.containsKey('1:/music'), isTrue,
          reason: '缓存中应有 key 1:/music');
      expect(cache['1:/music']!.files.length, equals(2),
          reason: '缓存条目应包含 2 个过滤后的文件');
    });

    // ── BRW-T30: Second load uses cache ────────────────────────────────────────

    test('BRW-T30: return to /music uses cache (no new request)', () async {
      final mockClient = _MockWebDavClient();
      mockClient.returnResult(_musicRawEntries());

      final fakeStorage = _FakeSecureStorage();
      fakeStorage.setPassword(1, 'test-password');

      final container = ProviderContainer(
        overrides: [
          webDavClientProvider.overrideWith((ref) => mockClient),
          activeConnectionProvider
              .overrideWith((ref) async => _connection(id: 1)),
          secureStorageProvider.overrideWith((ref) => fakeStorage),
        ],
      );
      addTearDown(container.dispose);

      // First load
      final result1 =
          await container.read(directoryContentsProvider('/music').future);
      expect(result1.length, equals(2));
      expect(mockClient.listDirectoryCallCount, equals(1));

      // Second load — same path, should use cache
      final result2 =
          await container.read(directoryContentsProvider('/music').future);

      expect(result2.length, equals(2),
          reason: '缓存返回结果应与首次加载一致');
      expect(result2[0].name, equals('song.mp3'));
      expect(result2[1].name, equals('track.flac'));
      expect(mockClient.listDirectoryCallCount, equals(1),
          reason: '第二次加载同一路径不应再触发 listDirectory');
    });

    // ── BRW-T31: Different connections, independent caches ─────────────────────

    test('BRW-T31: different connections have independent caches', () async {
      final mockClientA = _MockWebDavClient();
      final mockClientB = _MockWebDavClient();

      final fakeStorageA = _FakeSecureStorage();
      fakeStorageA.setPassword(1, 'pw-a');
      final fakeStorageB = _FakeSecureStorage();
      fakeStorageB.setPassword(2, 'pw-b');

      // Different results per connection to verify independence
      final filesA = [
        _dir('music', '/music'),
        _audio('song_a.mp3', '/music/song_a.mp3'),
      ];
      final filesB = [
        _dir('music', '/music'),
        _audio('song_b.flac', '/music/song_b.flac'),
      ];
      mockClientA.returnResult(filesA);
      mockClientB.returnResult(filesB);

      // Container for connection A
      final containerA = ProviderContainer(
        overrides: [
          webDavClientProvider.overrideWith((ref) => mockClientA),
          activeConnectionProvider
              .overrideWith((ref) async => _connection(id: 1, name: 'ConnA')),
          secureStorageProvider.overrideWith((ref) => fakeStorageA),
        ],
      );
      addTearDown(containerA.dispose);

      // Container for connection B
      final containerB = ProviderContainer(
        overrides: [
          webDavClientProvider.overrideWith((ref) => mockClientB),
          activeConnectionProvider
              .overrideWith((ref) async => _connection(id: 2, name: 'ConnB')),
          secureStorageProvider.overrideWith((ref) => fakeStorageB),
        ],
      );
      addTearDown(containerB.dispose);

      // Load /music with connection A
      final resultA =
          await containerA.read(directoryContentsProvider('/music').future);
      expect(resultA.length, equals(1),
          reason: '连接 A 应返回 1 个音频文件（滤除自引用后）');
      expect(resultA[0].name, equals('song_a.mp3'),
          reason: '连接 A 应返回 A 的结果');

      // Load /music with connection B
      final resultB =
          await containerB.read(directoryContentsProvider('/music').future);
      expect(resultB.length, equals(1),
          reason: '连接 B 应返回 1 个音频文件');
      expect(resultB[0].name, equals('song_b.flac'),
          reason: '连接 B 应返回 B 的结果');

      // Both clients were called once each
      expect(mockClientA.listDirectoryCallCount, equals(1),
          reason: '连接 A 的 client 只应被调用一次');
      expect(mockClientB.listDirectoryCallCount, equals(1),
          reason: '连接 B 的 client 只应被调用一次');

      // Cache keys are different per connection
      final cacheA = containerA.read(directoryCacheProvider);
      final cacheB = containerB.read(directoryCacheProvider);
      expect(cacheA.containsKey('1:/music'), isTrue,
          reason: '容器 A 的缓存 key 应为 1:/music');
      expect(cacheB.containsKey('2:/music'), isTrue,
          reason: '容器 B 的缓存 key 应为 2:/music');
      expect(cacheA.containsKey('2:/music'), isFalse,
          reason: '容器 A 的缓存中不应有连接 B 的条目');
      expect(cacheB.containsKey('1:/music'), isFalse,
          reason: '容器 B 的缓存中不应有连接 A 的条目');
    });

    // ── BRW-T32: Refresh clears cache ──────────────────────────────────────────

    test('BRW-T32: pull-to-refresh clears cache then makes new request',
        () async {
      final mockClient = _MockWebDavClient();
      mockClient.returnResult(_musicRawEntries());

      final fakeStorage = _FakeSecureStorage();
      fakeStorage.setPassword(1, 'test-password');

      final container = ProviderContainer(
        overrides: [
          webDavClientProvider.overrideWith((ref) => mockClient),
          activeConnectionProvider
              .overrideWith((ref) async => _connection(id: 1)),
          secureStorageProvider.overrideWith((ref) => fakeStorage),
        ],
      );
      addTearDown(container.dispose);

      // First load populates the cache
      await container.read(directoryContentsProvider('/music').future);
      expect(mockClient.listDirectoryCallCount, equals(1));

      // Verify cache has the entry before clearing
      final cacheBefore = container.read(directoryCacheProvider);
      expect(cacheBefore.containsKey('1:/music'), isTrue,
          reason: '加载后缓存应包含条目');

      // Simulate pull-to-refresh: clear the cache for /music
      final clearCache = container.read(clearDirectoryCacheProvider);
      clearCache('/music');

      // Verify cache is cleared for this entry
      final cacheAfterClear = container.read(directoryCacheProvider);
      expect(cacheAfterClear.containsKey('1:/music'), isFalse,
          reason: '刷新后缓存 key 1:/music 应被清除');

      // Reload /music — should trigger a new request
      await container.read(directoryContentsProvider('/music').future);
      expect(mockClient.listDirectoryCallCount, equals(2),
          reason: '清除缓存后重新加载应再次触发 listDirectory');
    });

    // ── BRW-T33: Switch connection doesn't pollute cache ────────────────────────

    test('BRW-T33: switching connection does not pollute results', () async {
      final fakeStorage = _FakeSecureStorage();
      fakeStorage.setPassword(1, 'pw-1');
      fakeStorage.setPassword(2, 'pw-2');

      // Connection 1: has files
      final mockClient1 = _MockWebDavClient();
      mockClient1.returnResult([
        _dir('music', '/music'),
        _audio('conn1_song.mp3', '/music/conn1_song.mp3'),
      ]);

      // Connection 2: empty directory
      final mockClient2 = _MockWebDavClient();
      mockClient2.returnResult([
        _dir('music', '/music'), // self-ref only
      ]);

      // Load with connection 1
      final container1 = ProviderContainer(
        overrides: [
          webDavClientProvider.overrideWith((ref) => mockClient1),
          activeConnectionProvider
              .overrideWith((ref) async => _connection(id: 1)),
          secureStorageProvider.overrideWith((ref) => fakeStorage),
        ],
      );
      addTearDown(container1.dispose);

      final result1 =
          await container1.read(directoryContentsProvider('/music').future);
      expect(result1.length, equals(1),
          reason: '连接 1 应返回 1 个文件');
      expect(result1[0].name, equals('conn1_song.mp3'));

      // Now switch to connection 2 — separate container simulates switch
      final container2 = ProviderContainer(
        overrides: [
          webDavClientProvider.overrideWith((ref) => mockClient2),
          activeConnectionProvider
              .overrideWith((ref) async => _connection(id: 2)),
          secureStorageProvider.overrideWith((ref) => fakeStorage),
        ],
      );
      addTearDown(container2.dispose);

      // Connection 2 loads /music — should make a fresh call and get empty result
      final result2 =
          await container2.read(directoryContentsProvider('/music').future);
      expect(result2.length, equals(0),
          reason: '连接 2 的空目录应返回 0 个条目（自引用已滤除）');

      // Connection 2's cache should NOT contain connection 1's data
      final cache2 = container2.read(directoryCacheProvider);
      expect(cache2.containsKey('2:/music'), isTrue,
          reason: '连接 2 应有自己的缓存条目');
      expect(cache2.containsKey('1:/music'), isFalse,
          reason: '连接 1 的缓存不应出现在容器 2 中');

      // Connection 2's cached result should be empty, not conn1's data
      expect(cache2['2:/music']!.files.length, equals(0),
          reason: '连接 2 的缓存条目应为空列表');

      // Connection 1's cache is independent
      final cache1 = container1.read(directoryCacheProvider);
      expect(cache1['1:/music']!.files.length, equals(1),
          reason: '连接 1 的缓存应保持不变');
    });
  });

  // ═════════════════════════════════════════════════════════════════════════════
  // Unit tests — TST-09: TST-T64~TST-T71 (cache TTL + capacity)
  // ═════════════════════════════════════════════════════════════════════════════

  group('TST-09: TST-T64~TST-T71 — cache TTL and capacity', () {
    // ── TST-T64: Cache within 3min → cache hit, no new request ──────────────

    test('TST-T64: cache in 3min → reuse cache, no new request', () async {
      final mockClient = _MockWebDavClient();
      mockClient.returnResult(_musicRawEntries());
      final fakeStorage = _FakeSecureStorage();
      fakeStorage.setPassword(1, 'test-password');

      final container = ProviderContainer(
        overrides: [
          webDavClientProvider.overrideWith((ref) => mockClient),
          activeConnectionProvider
              .overrideWith((ref) async => _connection(id: 1)),
          secureStorageProvider.overrideWith((ref) => fakeStorage),
        ],
      );
      addTearDown(container.dispose);

      // First load populates cache
      await container.read(directoryContentsProvider('/music').future);
      expect(mockClient.listDirectoryCallCount, equals(1),
          reason: '首次加载应触发一次 listDirectory');

      // Re-set the cache entry createdAt to 3 minutes ago (within TTL)
      container.read(directoryCacheProvider.notifier).update((state) {
        final updated = Map<String, CacheEntry>.from(state);
        updated['1:/music'] = CacheEntry(
          files: updated['1:/music']!.files,
          createdAt: DateTime.now().subtract(const Duration(minutes: 3)),
        );
        return updated;
      });

      // Invalidate so FutureProvider re-executes on next read
      container.invalidate(directoryContentsProvider('/music'));
      await container.read(directoryContentsProvider('/music').future);

      // Must be a cache hit (age ≈ 3 min < 5 min TTL)
      expect(mockClient.listDirectoryCallCount, equals(1),
          reason: '3min 内缓存未过期，不应发起新网络请求');

      // Verify the cache entry is still present
      final cache = container.read(directoryCacheProvider);
      expect(cache.containsKey('1:/music'), isTrue,
          reason: '3min 内缓存条目应仍然存在');
    });

    // ── TST-T65: Cache older than 5min → auto-refetch ─────────────────────

    test('TST-T65: cache expired (6min > 5min TTL) → triggers new request',
        () async {
      final mockClient = _MockWebDavClient();
      mockClient.returnResult(_musicRawEntries());
      final fakeStorage = _FakeSecureStorage();
      fakeStorage.setPassword(1, 'test-password');

      final container = ProviderContainer(
        overrides: [
          webDavClientProvider.overrideWith((ref) => mockClient),
          activeConnectionProvider
              .overrideWith((ref) async => _connection(id: 1)),
          secureStorageProvider.overrideWith((ref) => fakeStorage),
        ],
      );
      addTearDown(container.dispose);

      // First load populates cache
      await container.read(directoryContentsProvider('/music').future);
      expect(mockClient.listDirectoryCallCount, equals(1));

      // Re-set the cache entry createdAt to 6 minutes ago (past TTL)
      container.read(directoryCacheProvider.notifier).update((state) {
        final updated = Map<String, CacheEntry>.from(state);
        updated['1:/music'] = CacheEntry(
          files: updated['1:/music']!.files,
          createdAt: DateTime.now().subtract(const Duration(minutes: 6)),
        );
        return updated;
      });

      // Invalidate and re-read — cache should be expired
      container.invalidate(directoryContentsProvider('/music'));
      await container.read(directoryContentsProvider('/music').future);

      expect(mockClient.listDirectoryCallCount, equals(2),
          reason: '超过 5min TTL 后缓存过期，应发起新的 listDirectory');
    });

    // ── TST-T66: TTL boundary (exactly 5min) ──────────────────────────────

    test('TST-T66: at exactly 5min boundary → cache expired, refetches',
        () async {
      final mockClient = _MockWebDavClient();
      mockClient.returnResult(_musicRawEntries());
      final fakeStorage = _FakeSecureStorage();
      fakeStorage.setPassword(1, 'test-password');

      final container = ProviderContainer(
        overrides: [
          webDavClientProvider.overrideWith((ref) => mockClient),
          activeConnectionProvider
              .overrideWith((ref) async => _connection(id: 1)),
          secureStorageProvider.overrideWith((ref) => fakeStorage),
        ],
      );
      addTearDown(container.dispose);

      // First load populates cache
      await container.read(directoryContentsProvider('/music').future);
      expect(mockClient.listDirectoryCallCount, equals(1));

      // Re-set the cache entry createdAt to exactly 5 minutes ago (boundary)
      container.read(directoryCacheProvider.notifier).update((state) {
        final updated = Map<String, CacheEntry>.from(state);
        updated['1:/music'] = CacheEntry(
          files: updated['1:/music']!.files,
          createdAt: DateTime.now().subtract(const Duration(minutes: 5)),
        );
        return updated;
      });

      // Invalidate and re-read
      container.invalidate(directoryContentsProvider('/music'));
      await container.read(directoryContentsProvider('/music').future);

      // Implementation uses `age < _cacheTtl` (strict less-than, not <=).
      // At exactly 5 min, age == TTL, so the condition is false → cache expired.
      expect(mockClient.listDirectoryCallCount, equals(2),
          reason:
              '恰好 5min 时 age < TTL 为 false，cache expired → 触发重取');
    });

    // ── TST-T67: Pull-to-refresh → clear → refetch regardless of TTL ──────

    test('TST-T67: pull-to-refresh clears cache, refetches regardless of TTL',
        () async {
      final mockClient = _MockWebDavClient();
      mockClient.returnResult(_musicRawEntries());
      final fakeStorage = _FakeSecureStorage();
      fakeStorage.setPassword(1, 'test-password');

      final container = ProviderContainer(
        overrides: [
          webDavClientProvider.overrideWith((ref) => mockClient),
          activeConnectionProvider
              .overrideWith((ref) async => _connection(id: 1)),
          secureStorageProvider.overrideWith((ref) => fakeStorage),
        ],
      );
      addTearDown(container.dispose);

      // First load populates the cache
      await container.read(directoryContentsProvider('/music').future);
      expect(mockClient.listDirectoryCallCount, equals(1));

      // Cache is populated
      final cacheBefore = container.read(directoryCacheProvider);
      expect(cacheBefore.containsKey('1:/music'), isTrue,
          reason: '加载后缓存应包含条目');

      // Pull-to-refresh: clear the cache for /music
      final clearCache = container.read(clearDirectoryCacheProvider);
      clearCache('/music');

      // Verify cache is cleared
      final cacheAfterClear = container.read(directoryCacheProvider);
      expect(cacheAfterClear.containsKey('1:/music'), isFalse,
          reason: '下拉刷新后缓存 key 应被清除');

      // Re-read — should trigger a new request even though TTL hasn't elapsed
      await container.read(directoryContentsProvider('/music').future);
      expect(mockClient.listDirectoryCallCount, equals(2),
          reason: '清除缓存后应立即重取，无视 TTL');
    });

    // ── TST-T68: Capacity at 50 → all entries retained ─────────────────────

    test('TST-T68: 50 cache entries → all retained', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      // Directly populate the cache with 50 entries keyed by connection 1
      container.read(directoryCacheProvider.notifier).update((state) {
        final updated = Map<String, CacheEntry>.from(state);
        for (int i = 1; i <= 50; i++) {
          updated['1:/music$i'] = CacheEntry(
            files: [_audio('song$i.mp3', '/music$i/song$i.mp3')],
            createdAt: DateTime.now(),
          );
        }
        return updated;
      });

      final cache = container.read(directoryCacheProvider);
      expect(cache.length, equals(50),
          reason: '恰好 50 条时所有条目应保留');
      for (int i = 1; i <= 50; i++) {
        expect(cache.containsKey('1:/music$i'), isTrue,
            reason: '1:/music$i 应存在于缓存中');
      }
    });

    // ── TST-T69: Capacity at 51 → oldest entry evicted ─────────────────────

    test('TST-T69: 51st entry triggers eviction of oldest', () async {
      final mockClient = _MockWebDavClient();
      mockClient.returnResult(_musicRawEntries());
      final fakeStorage = _FakeSecureStorage();
      fakeStorage.setPassword(1, 'test-password');

      final container = ProviderContainer(
        overrides: [
          webDavClientProvider.overrideWith((ref) => mockClient),
          activeConnectionProvider
              .overrideWith((ref) async => _connection(id: 1)),
          secureStorageProvider.overrideWith((ref) => fakeStorage),
        ],
      );
      addTearDown(container.dispose);

      // Pre-populate 50 cache entries (music1 is oldest in insertion order)
      container.read(directoryCacheProvider.notifier).update((state) {
        final updated = Map<String, CacheEntry>.from(state);
        for (int i = 1; i <= 50; i++) {
          updated['1:/music$i'] = CacheEntry(
            files: [_audio('song$i.mp3', '/music$i/song$i.mp3')],
            createdAt:
                DateTime.now().subtract(Duration(minutes: 51 - i)),
          );
        }
        return updated;
      });
      expect(container.read(directoryCacheProvider).length, equals(50));

      // Load a 51st path through the provider — this triggers eviction
      await container.read(directoryContentsProvider('/music51').future);

      final cache = container.read(directoryCacheProvider);
      expect(cache.length, equals(50),
          reason: '缓存容量上限 50 条，第 51 条触发淘汰后仍为 50 条');
      expect(cache.containsKey('1:/music1'), isFalse,
          reason: 'music1 是最早插入的条目，应被淘汰');
      expect(cache.containsKey('1:/music2'), isTrue,
          reason: 'music2 是第二早插入的条目，应保留');
      expect(cache.containsKey('1:/music50'), isTrue,
          reason: 'music50 是第 50 个插入的条目，应保留');
      expect(cache.containsKey('1:/music51'), isTrue,
          reason: '新条目 music51 应被写入缓存');
    });

    // ── TST-T70: After overflow → new entry is readable ────────────────────

    test('TST-T70: after overflow, new entry is readable', () async {
      final mockClient = _MockWebDavClient();
      mockClient.returnResult(_musicRawEntries());
      final fakeStorage = _FakeSecureStorage();
      fakeStorage.setPassword(1, 'test-password');

      final container = ProviderContainer(
        overrides: [
          webDavClientProvider.overrideWith((ref) => mockClient),
          activeConnectionProvider
              .overrideWith((ref) async => _connection(id: 1)),
          secureStorageProvider.overrideWith((ref) => fakeStorage),
        ],
      );
      addTearDown(container.dispose);

      // Pre-populate 50 entries
      container.read(directoryCacheProvider.notifier).update((state) {
        final updated = Map<String, CacheEntry>.from(state);
        for (int i = 1; i <= 50; i++) {
          updated['1:/music$i'] = CacheEntry(
            files: [_audio('song$i.mp3', '/music$i/song$i.mp3')],
            createdAt:
                DateTime.now().subtract(Duration(minutes: 51 - i)),
          );
        }
        return updated;
      });

      // Load 51st — triggers eviction of oldest
      await container.read(directoryContentsProvider('/music51').future);

      // The new entry is in the cache
      final cache = container.read(directoryCacheProvider);
      expect(cache.containsKey('1:/music51'), isTrue,
          reason: 'music51 应已写入缓存');
      expect(cache['1:/music51']!.files, isNotEmpty,
          reason: 'music51 的缓存数据应非空');

      // Reading /music51 again uses the cache (no new network request)
      final previousCallCount = mockClient.listDirectoryCallCount;
      await container.read(directoryContentsProvider('/music51').future);
      expect(mockClient.listDirectoryCallCount, equals(previousCallCount),
          reason: '再次读取同一路径应使用缓存，不发起新请求');
    });

    // ── TST-T71: Evicted entry re-accessed → triggers new request ──────────

    test('TST-T71: evicted entry re-accessed → new network request', () async {
      final mockClient = _MockWebDavClient();
      mockClient.returnResult(_musicRawEntries());
      final fakeStorage = _FakeSecureStorage();
      fakeStorage.setPassword(1, 'test-password');

      final container = ProviderContainer(
        overrides: [
          webDavClientProvider.overrideWith((ref) => mockClient),
          activeConnectionProvider
              .overrideWith((ref) async => _connection(id: 1)),
          secureStorageProvider.overrideWith((ref) => fakeStorage),
        ],
      );
      addTearDown(container.dispose);

      // Pre-populate 50 entries (music1 is oldest)
      container.read(directoryCacheProvider.notifier).update((state) {
        final updated = Map<String, CacheEntry>.from(state);
        for (int i = 1; i <= 50; i++) {
          updated['1:/music$i'] = CacheEntry(
            files: [_audio('song$i.mp3', '/music$i/song$i.mp3')],
            createdAt:
                DateTime.now().subtract(Duration(minutes: 51 - i)),
          );
        }
        return updated;
      });

      // Load 51st — evicts music1
      await container.read(directoryContentsProvider('/music51').future);
      final cacheAfterEviction = container.read(directoryCacheProvider);
      expect(cacheAfterEviction.containsKey('1:/music1'), isFalse,
          reason: 'music1 已被淘汰');

      final callsBeforeRefetch = mockClient.listDirectoryCallCount;

      // Access the evicted entry — cache miss, triggers new network request
      await container.read(directoryContentsProvider('/music1').future);

      expect(
        mockClient.listDirectoryCallCount,
        equals(callsBeforeRefetch + 1),
        reason: '被淘汰的 music1 不在缓存中，重新访问应触发新 listDirectory',
      );

      // Verify music1 is now back in the cache
      final cache = container.read(directoryCacheProvider);
      expect(cache.containsKey('1:/music1'), isTrue,
          reason: '重取后 music1 应重新出现在缓存中');
    });
  });
}
