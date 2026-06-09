// test/features/browser/ref_19_test.dart
// REF-19: DirectoryService — directory loading, caching, sorting.
//
// Tests verify:
// - REF-19-T01: directory load -> cache -> sort
// - REF-19-T02: cache hit -> no network request
// - REF-19-T03: cache expired -> re-request
// - REF-19-T04: sort change -> re-sort (no network request)

import 'package:flutter_test/flutter_test.dart';
import 'package:nas_audio_player/core/network/webdav_client.dart';
import 'package:nas_audio_player/features/browser/domain/cache_policy.dart';
import 'package:nas_audio_player/features/browser/domain/directory_service.dart';
import 'package:nas_audio_player/shared/models/nas_file.dart';

// ── Mock WebDAV client ──────────────────────────────────────────────────────

class MockWebDavClient implements WebDavClientInterface {
  /// Number of times [listDirectory] was called.
  int listDirectoryCallCount = 0;

  /// The entries to return from [listDirectory].
  List<NasFile> entriesToReturn = [];

  @override
  Future<List<NasFile>> listDirectory({
    required String url,
    required String username,
    required String password,
    required String path,
  }) async {
    listDirectoryCallCount++;
    return entriesToReturn;
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

// ── Mock secure password reader ─────────────────────────────────────────────

class MockSecurePasswordReader implements ISecurePasswordReader {
  String? passwordToReturn = 'test-password';

  @override
  Future<String?> read({required String key}) async {
    return passwordToReturn;
  }
}

// ── Helpers ─────────────────────────────────────────────────────────────────

NasFile _dir(String name, {String? path, DateTime? modifiedAt}) {
  return NasFile(
    name: name,
    path: path ?? '/$name',
    isDirectory: true,
    modifiedAt: modifiedAt,
  );
}

NasFile _audio(String name, {String? path, DateTime? modifiedAt}) {
  return NasFile(
    name: name,
    path: path ?? '/$name',
    isDirectory: false,
    size: 1024,
    modifiedAt: modifiedAt,
    audioType: AudioFileType.music,
  );
}

NasFile _txt(String name, {String? path}) {
  return NasFile(
    name: name,
    path: path ?? '/$name',
    isDirectory: false,
    size: 100,
  );
}

void main() {
  late MockWebDavClient mockClient;
  late MockSecurePasswordReader mockStorage;

  setUp(() {
    mockClient = MockWebDavClient();
    mockStorage = MockSecurePasswordReader();
  });

  group('REF-19: DirectoryService', () {
    // ── REF-19-T01: directory load -> cache -> sort ──────────────────────────

    test('REF-19-T01: loads directory, caches, and sorts', () async {
      // Setup: mixed list of dirs + audio + non-audio files
      mockClient.entriesToReturn = [
        _dir('subdir'),
        _txt('readme.txt'), // should be filtered out
        _audio('b_song.mp3', path: '/b_song.mp3'),
        _audio('a_song.flac', path: '/a_song.flac'),
      ];

      final service = DirectoryService(
        client: mockClient,
        storage: mockStorage,
      );

      final result = await service.loadDirectory(
        connectionId: 1,
        url: 'http://nas.example.com',
        username: 'user',
        path: '/music',
        sortOption: SortOption.nameAsc,
      );

      expect(result.fromCache, isFalse, reason: 'first load is not from cache');
      expect(mockClient.listDirectoryCallCount, 1);

      // Verify filtering: readme.txt excluded, dirs kept, audio kept
      expect(result.files.length, 3, reason: '2 audio + 1 dir after filtering');

      // Verify sorting: dirs first, then alphabetical
      expect(result.files[0].name, 'subdir');
      expect(result.files[1].name, 'a_song.flac');
      expect(result.files[2].name, 'b_song.mp3');
    });

    // ── REF-19-T02: cache hit -> no network request ──────────────────────────

    test('REF-19-T02: cache hit returns cached data without network call',
        () async {
      mockClient.entriesToReturn = [
        _dir('subdir'),
        _audio('song.mp3', path: '/song.mp3'),
      ];

      final service = DirectoryService(
        client: mockClient,
        storage: mockStorage,
      );

      // First call — populates cache
      await service.loadDirectory(
        connectionId: 1,
        url: 'http://nas.example.com',
        username: 'user',
        path: '/music',
        sortOption: SortOption.nameAsc,
      );
      expect(mockClient.listDirectoryCallCount, 1);

      // Second call — should hit cache
      final result = await service.loadDirectory(
        connectionId: 1,
        url: 'http://nas.example.com',
        username: 'user',
        path: '/music',
        sortOption: SortOption.nameAsc,
      );

      expect(result.fromCache, isTrue, reason: 'second load should be from cache');
      expect(mockClient.listDirectoryCallCount, 1,
          reason: 'should not make a second network call');
      expect(result.files.length, 2);
    });

    // ── REF-19-T03: cache expired -> re-request ──────────────────────────────

    test('REF-19-T03: expired cache triggers a new network request', () async {
      // Use a very short TTL to force expiry
      const shortPolicy = CachePolicy<List<NasFile>>(
        ttl: Duration(milliseconds: 1),
        maxSize: 50,
      );

      mockClient.entriesToReturn = [
        _audio('song.mp3', path: '/song.mp3'),
      ];

      final service = DirectoryService(
        client: mockClient,
        storage: mockStorage,
        cachePolicy: shortPolicy,
      );

      // First call
      await service.loadDirectory(
        connectionId: 1,
        url: 'http://nas.example.com',
        username: 'user',
        path: '/music',
        sortOption: SortOption.nameAsc,
      );
      expect(mockClient.listDirectoryCallCount, 1);

      // Wait for cache to expire
      await Future<void>.delayed(const Duration(milliseconds: 50));

      // Update mock to return different data
      mockClient.entriesToReturn = [
        _audio('new_song.mp3', path: '/new_song.mp3'),
      ];

      // Second call — cache should be expired
      final result = await service.loadDirectory(
        connectionId: 1,
        url: 'http://nas.example.com',
        username: 'user',
        path: '/music',
        sortOption: SortOption.nameAsc,
      );

      expect(result.fromCache, isFalse,
          reason: 'expired cache should trigger network request');
      expect(mockClient.listDirectoryCallCount, 2,
          reason: 'should make a second network call');
      expect(result.files.length, 1);
      expect(result.files[0].name, 'new_song.mp3');
    });

    // ── REF-19-T04: sort change -> re-sort (no network request) ──────────────

    test('REF-19-T04: changing sort option re-sorts without network request',
        () async {
      mockClient.entriesToReturn = [
        _dir('subdir'),
        _audio('b_song.mp3', path: '/b_song.mp3'),
        _audio('a_song.flac', path: '/a_song.flac'),
      ];

      final service = DirectoryService(
        client: mockClient,
        storage: mockStorage,
      );

      // Load with nameAsc sort
      await service.loadDirectory(
        connectionId: 1,
        url: 'http://nas.example.com',
        username: 'user',
        path: '/music',
        sortOption: SortOption.nameAsc,
      );

      // Re-sort cached data with nameDesc
      final resortResult = service.resortCached(
        connectionId: 1,
        path: '/music',
        sortOption: SortOption.nameDesc,
      );

      expect(resortResult, isNotNull, reason: 'cache should be alive');
      expect(resortResult!.length, 3);

      // Verify reverse alphabetical within each group
      expect(resortResult[0].name, 'subdir', reason: 'dirs still first');
      expect(resortResult[1].name, 'b_song.mp3', reason: 'b before a in desc');
      expect(resortResult[2].name, 'a_song.flac');

      // No additional network calls
      expect(mockClient.listDirectoryCallCount, 1,
          reason: 're-sort should not trigger network request');
    });

    // ── Additional: sort helper always puts dirs first ────────────────────────

    test('sortFiles: directories always appear before files', () {
      final files = [
        _audio('z_song.mp3', path: '/z_song.mp3'),
        _dir('aaa_dir'),
        _audio('a_song.mp3', path: '/a_song.mp3'),
      ];

      final sorted = DirectoryService.sortFiles(files, SortOption.nameAsc);

      expect(sorted[0].isDirectory, isTrue);
      expect(sorted[0].name, 'aaa_dir');
      expect(sorted[1].name, 'a_song.mp3');
      expect(sorted[2].name, 'z_song.mp3');
    });

    // ── Additional: different connections don't share cache ───────────────────

    test('different connections use separate cache entries', () async {
      mockClient.entriesToReturn = [_audio('song.mp3', path: '/song.mp3')];

      final service = DirectoryService(
        client: mockClient,
        storage: mockStorage,
      );

      // Load for connection 1
      await service.loadDirectory(
        connectionId: 1,
        url: 'http://nas.example.com',
        username: 'user',
        path: '/music',
        sortOption: SortOption.nameAsc,
      );

      // Load for connection 2 — different cache key
      final result = await service.loadDirectory(
        connectionId: 2,
        url: 'http://nas2.example.com',
        username: 'user',
        path: '/music',
        sortOption: SortOption.nameAsc,
      );

      expect(result.fromCache, isFalse,
          reason: 'different connection should not share cache');
      expect(mockClient.listDirectoryCallCount, 2);
    });

    // ── Additional: clearCache works ─────────────────────────────────────────

    test('clearCache removes specific entry', () async {
      mockClient.entriesToReturn = [_audio('song.mp3', path: '/song.mp3')];

      final service = DirectoryService(
        client: mockClient,
        storage: mockStorage,
      );

      await service.loadDirectory(
        connectionId: 1,
        url: 'http://nas.example.com',
        username: 'user',
        path: '/music',
        sortOption: SortOption.nameAsc,
      );

      // Clear cache for this path
      service.clearCache(connectionId: 1, path: '/music');

      // Next load should be a cache miss
      final result = await service.loadDirectory(
        connectionId: 1,
        url: 'http://nas.example.com',
        username: 'user',
        path: '/music',
        sortOption: SortOption.nameAsc,
      );

      expect(result.fromCache, isFalse);
      expect(mockClient.listDirectoryCallCount, 2);
    });

    // ── Additional: missing password throws ──────────────────────────────────

    test('missing password throws WebDavException', () async {
      mockStorage.passwordToReturn = null;

      final service = DirectoryService(
        client: mockClient,
        storage: mockStorage,
      );

      expect(
        () => service.loadDirectory(
          connectionId: 1,
          url: 'http://nas.example.com',
          username: 'user',
          path: '/music',
          sortOption: SortOption.nameAsc,
        ),
        throwsA(isA<WebDavException>()),
      );
    });

    // ── Additional: modifiedDesc sort ────────────────────────────────────────

    test('sortFiles: modifiedDesc sorts newest first', () {
      final files = [
        _audio('old.mp3', path: '/old.mp3',
            modifiedAt: DateTime(2024, 1, 1)),
        _audio('new.mp3', path: '/new.mp3',
            modifiedAt: DateTime(2024, 6, 1)),
        _audio('mid.mp3', path: '/mid.mp3',
            modifiedAt: DateTime(2024, 3, 1)),
      ];

      final sorted =
          DirectoryService.sortFiles(files, SortOption.modifiedDesc);

      expect(sorted[0].name, 'new.mp3');
      expect(sorted[1].name, 'mid.mp3');
      expect(sorted[2].name, 'old.mp3');
    });
  });
}
