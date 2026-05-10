// test/features/browser/brw_06_test.dart
// BRW-06: 下拉刷新 — automated test suite
//
// Unit tests (BRW-T34~T36): pull-to-refresh clears cache, triggers new
// PROPFIND, and correctly handles both error and success outcomes.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nas_audio_player/core/network/webdav_client.dart';
import 'package:nas_audio_player/features/browser/browser_provider.dart';
import 'package:nas_audio_player/features/connection/connection_provider.dart';
import 'package:nas_audio_player/shared/models/connection_config.dart';
import 'package:nas_audio_player/shared/models/nas_file.dart';

// ── Manual mocks ────────────────────────────────────────────────────────────────

/// Tracks [listDirectory] invocations and can be reconfigured mid-test to
/// simulate pull-to-refresh scenarios (new data or errors).
class _MockWebDavClient implements WebDavClientInterface {
  int listDirectoryCallCount = 0;
  List<String> calledPaths = <String>[];
  List<NasFile> _result = const [];
  Object? _error; // non-null → throw this instead of returning _result

  void returnResult(List<NasFile> result) {
    _result = result;
    _error = null;
  }

  void throwError(Object error) {
    _error = error;
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
    if (_error != null) throw _error!;
    return _result;
  }

  @override
  Future<WebDavValidationResult> validate({
    required String url,
    required String username,
    required String password,
    String basePath = '/',
  }) async {
    throw UnimplementedError('validate not needed for BRW-06 tests');
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

NasFile _dir(String name, String path) {
  return NasFile(name: name, path: path, isDirectory: true);
}

NasFile _audio(String name, String path) {
  return NasFile(
    name: name,
    path: path,
    isDirectory: false,
    audioType: AudioFileType.music,
  );
}

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

/// Raw entries returned by the mock WebDAV client for the /music directory
/// (includes self-reference that the provider filters out).
List<NasFile> _musicRawEntries() {
  return [
    _dir('music', '/music'),
    _audio('song.mp3', '/music/song.mp3'),
    _audio('track.flac', '/music/track.flac'),
  ];
}

/// Different raw entries simulating updated server data.
List<NasFile> _musicRawEntriesUpdated() {
  return [
    _dir('music', '/music'),
    _audio('new_album.mp3', '/music/new_album.mp3'),
    _audio('song.mp3', '/music/song.mp3'),
    _audio('track.flac', '/music/track.flac'),
  ];
}

// ═════════════════════════════════════════════════════════════════════════════
// Unit tests — BRW-T34~T36
// ═════════════════════════════════════════════════════════════════════════════

void main() {
  group('BRW-T34~T36: pull-to-refresh', () {
    // ── BRW-T34: Cache cleared and new PROPFIND triggered on refresh ──────────

    test('BRW-T34: pull-to-refresh clears cache and triggers new PROPFIND',
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
      final firstResult =
          await container.read(directoryContentsProvider('/music').future);
      expect(firstResult.length, equals(2),
          reason: '首次加载应返回 2 个过滤后的音频文件');
      expect(mockClient.listDirectoryCallCount, equals(1),
          reason: '首次加载应触发一次 listDirectory');

      // Verify cache has the entry
      final cacheBefore = container.read(directoryCacheProvider);
      expect(cacheBefore.containsKey('1:/music'), isTrue,
          reason: '缓存中应有 key 1:/music');

      // Simulate pull-to-refresh: clear cache and refresh provider
      final clearCache = container.read(clearDirectoryCacheProvider);
      clearCache('/music');

      // Verify cache entry is removed
      final cacheAfterClear = container.read(directoryCacheProvider);
      expect(cacheAfterClear.containsKey('1:/music'), isFalse,
          reason: '下拉刷新后缓存 key 1:/music 应被清除');

      // Change the mock to return different data (simulating updated server)
      mockClient.returnResult(_musicRawEntriesUpdated());

      // Refresh the provider — should require a new listDirectory call
      final refreshedResult =
          await container.read(directoryContentsProvider('/music').future);

      expect(mockClient.listDirectoryCallCount, equals(2),
          reason: '刷新后重新加载应再次触发 listDirectory');
      expect(refreshedResult.length, equals(3),
          reason: '刷新后应返回更新后的数据（3 个文件，自引用已滤除）');
      expect(refreshedResult[0].name, equals('new_album.mp3'),
          reason: '更新数据中应包含新文件 new_album.mp3');

      // Cache should now hold the updated data
      final cacheAfterReload = container.read(directoryCacheProvider);
      expect(cacheAfterReload.containsKey('1:/music'), isTrue,
          reason: '重新加载后缓存应被重新填充');
      expect(cacheAfterReload['1:/music']!.length, equals(3),
          reason: '缓存应包含更新后的 3 个文件');
    });

    // ── BRW-T35: Pull-to-refresh during network error ──────────────────────────

    test('BRW-T35: pull-to-refresh during network error shows error state',
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

      // First load succeeds and populates the cache
      final firstResult =
          await container.read(directoryContentsProvider('/music').future);
      expect(firstResult.length, equals(2));
      expect(mockClient.listDirectoryCallCount, equals(1));

      // Simulate pull-to-refresh: clear cache
      final clearCache = container.read(clearDirectoryCacheProvider);
      clearCache('/music');

      // Now configure the mock to throw a network error
      mockClient.throwError(
        const WebDavException('连接超时'),
      );

      // Attempt to reload — should result in an error
      // We need to read via .future and catch the error
      Object? caughtError;
      try {
        await container.read(directoryContentsProvider('/music').future);
      } catch (e) {
        caughtError = e;
      }

      expect(caughtError, isNotNull,
          reason: '网络错误时刷新应抛出异常');
      expect(caughtError, isA<WebDavException>(),
          reason: '异常应为 WebDavException 类型');
      expect((caughtError as WebDavException).message, equals('连接超时'),
          reason: '错误消息应传递超时信息');

      // The cache should remain cleared (not re-populated on error)
      final cacheAfterError = container.read(directoryCacheProvider);
      expect(cacheAfterError.containsKey('1:/music'), isFalse,
          reason: '刷新失败后缓存不应被重新填充');
    });

    // ── BRW-T36: After refresh success, list shows latest server data ─────────

    test('BRW-T36: successful refresh updates list with latest server data',
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

      // First load returns original data
      final firstResult =
          await container.read(directoryContentsProvider('/music').future);
      expect(firstResult.length, equals(2));
      expect(firstResult.map((f) => f.name).toList(),
          equals(['song.mp3', 'track.flac']),
          reason: '首次加载应返回原始文件列表');

      // Simulate server-side changes: a file was deleted and a new one added
      final updatedEntries = [
        _dir('music', '/music'),
        _audio('track.flac', '/music/track.flac'),
        _audio('new_release.ogg', '/music/new_release.ogg'),
        _audio('latest.aac', '/music/latest.aac'),
      ];
      mockClient.returnResult(updatedEntries);

      // Simulate pull-to-refresh
      final clearCache = container.read(clearDirectoryCacheProvider);
      clearCache('/music');

      // Refresh the provider
      final refreshedResult =
          await container.read(directoryContentsProvider('/music').future);

      expect(mockClient.listDirectoryCallCount, equals(2),
          reason: '刷新应触发新的 PROPFIND 请求');

      // Verify the list reflects latest server data
      // Directories come first (sorted A-Z), then files (sorted A-Z)
      expect(refreshedResult.length, equals(3),
          reason: '刷新后应返回 3 个音频文件（song.mp3 已删除，新增 2 个）');
      expect(refreshedResult.map((f) => f.name).toList(),
          equals(['latest.aac', 'new_release.ogg', 'track.flac']),
          reason: '列表应按目录优先、名称排序，反映最新服务器数据');

      // song.mp3 should no longer be present
      final songMp3 = refreshedResult.where((f) => f.name == 'song.mp3');
      expect(songMp3.isEmpty, isTrue,
          reason: 'song.mp3 已从服务器删除，不应出现在刷新后的列表中');

      // Verify the cache reflects the new data
      final cacheAfterRefresh = container.read(directoryCacheProvider);
      expect(cacheAfterRefresh['1:/music']!.length, equals(3),
          reason: '缓存应包含 3 个更新后的文件');
    });
  });
}
