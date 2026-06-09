// lib/features/browser/domain/directory_service.dart
// Directory loading + caching + sorting service.
// Extracted from browser_provider.dart (REF-19).
// Zero Flutter dependencies — pure Dart.

import '../../../core/network/webdav_client.dart';
import '../../../shared/models/nas_file.dart';
import 'cache_policy.dart';

/// Sort orders for the file/directory list.
enum SortOption {
  /// Sort by name in ascending alphabetical order (A-Z).
  nameAsc,

  /// Sort by name in descending alphabetical order (Z-A).
  nameDesc,

  /// Sort by last-modified time, newest first.
  modifiedDesc,
}

/// Abstraction over secure storage reads so [DirectoryService] has no
/// Flutter plugin dependencies.
abstract class ISecurePasswordReader {
  /// Reads the stored password for [key]. Returns null when not found.
  Future<String?> read({required String key});
}

/// Result returned by [DirectoryService.loadDirectory].
class DirectoryResult {
  /// The filtered and sorted file list.
  final List<NasFile> files;

  /// Whether the data was served from cache (true) or fetched over the
  /// network (false).
  final bool fromCache;

  const DirectoryResult({required this.files, required this.fromCache});
}

/// Encapsulates directory loading, in-memory caching and sorting.
///
/// All dependencies are injected through the constructor so the class is
/// fully testable without Flutter infrastructure.
class DirectoryService {
  final WebDavClientInterface _client;
  final ISecurePasswordReader _storage;
  final CachePolicy<List<NasFile>> _cachePolicy;

  /// In-memory cache keyed by `connectionId:path`.
  final Map<String, CacheEntry<List<NasFile>>> _cache = {};

  DirectoryService({
    required WebDavClientInterface client,
    required ISecurePasswordReader storage,
    CachePolicy<List<NasFile>>? cachePolicy,
  })  : _client = client,
        _storage = storage,
        _cachePolicy = cachePolicy ?? const CachePolicy<List<NasFile>>();

  // ── Public API ─────────────────────────────────────────────────────────────

  /// Loads directory contents for [path] on the given connection.
  ///
  /// Returns a [DirectoryResult] containing the filtered, sorted file list
  /// and a flag indicating whether it came from cache.
  ///
  /// [sortOption] controls the sort order applied to the result.
  /// When the data is already cached and alive, the list is re-sorted
  /// according to [sortOption] without a network round-trip.
  Future<DirectoryResult> loadDirectory({
    required int connectionId,
    required String url,
    required String username,
    required String path,
    required SortOption sortOption,
  }) async {
    final cacheKey = '$connectionId:$path';
    final now = DateTime.now();

    // 1. Check cache
    final cachedEntry = _cache[cacheKey];
    if (cachedEntry != null && _cachePolicy.isAlive(cachedEntry, now)) {
      // Cache hit — update LRU timestamp and re-sort
      _cache[cacheKey] = cachedEntry.accessedAt(now);
      return DirectoryResult(
        files: sortFiles(cachedEntry.value, sortOption),
        fromCache: true,
      );
    }

    // 2. Cache miss or expired — fetch from network
    final passwordKey = 'connection_password_$connectionId';
    final password = await _storage.read(key: passwordKey);
    if (password == null || password.isEmpty) {
      throw const WebDavException('密码未保存');
    }

    final allEntries = await _client.listDirectory(
      url: url,
      username: username,
      password: password,
      path: path,
    );

    // 3. Filter: exclude self-reference and non-audio files; keep all dirs
    final requestPath = path.endsWith('/') ? path : '$path/';
    final filtered = allEntries.where((entry) {
      final entryPath = entry.path;
      if (entryPath == path ||
          entryPath == requestPath ||
          '$entryPath/' == requestPath) {
        return false;
      }
      if (entry.isDirectory) return true;
      return entry.audioType != null;
    }).toList();

    // 4. Sort
    final sorted = sortFiles(filtered, sortOption);

    // 5. Write to cache (with LRU eviction via CachePolicy.put)
    final entry = CacheEntry<List<NasFile>>(
      value: sorted,
      createdAt: now,
    );
    final updated = _cachePolicy.put(_cache, cacheKey, entry);
    _cache
      ..clear()
      ..addAll(updated);

    return DirectoryResult(files: sorted, fromCache: false);
  }

  /// Returns a re-sorted view of the cached data for [connectionId] and
  /// [path] without any network request.
  ///
  /// Returns `null` when no alive cache entry exists.
  List<NasFile>? resortCached({
    required int connectionId,
    required String path,
    required SortOption sortOption,
  }) {
    final cacheKey = '$connectionId:$path';
    final entry = _cache[cacheKey];
    if (entry == null) return null;
    if (!_cachePolicy.isAlive(entry, DateTime.now())) return null;
    return sortFiles(entry.value, sortOption);
  }

  /// Clears the cache entry for a specific [connectionId]:[path] pair,
  /// or the entire cache when [path] is null.
  void clearCache({required int connectionId, String? path}) {
    if (path == null) {
      _cache.clear();
    } else {
      _cache.remove('$connectionId:$path');
    }
  }

  // ── Sort helper ────────────────────────────────────────────────────────────

  /// Returns a new list sorted according to [option].
  ///
  /// Directories always appear before files regardless of the sort option
  /// (BRW-T42).  Within each group entries are ordered by the selected
  /// criterion.
  static List<NasFile> sortFiles(List<NasFile> files, SortOption option) {
    final sorted = files.toList();
    sorted.sort((a, b) {
      // Directories always first
      if (a.isDirectory && !b.isDirectory) return -1;
      if (!a.isDirectory && b.isDirectory) return 1;

      // Within the same category, apply the selected sort
      switch (option) {
        case SortOption.nameAsc:
          return a.name.toLowerCase().compareTo(b.name.toLowerCase());
        case SortOption.nameDesc:
          return b.name.toLowerCase().compareTo(a.name.toLowerCase());
        case SortOption.modifiedDesc:
          final aTime = a.modifiedAt?.millisecondsSinceEpoch ?? 0;
          final bTime = b.modifiedAt?.millisecondsSinceEpoch ?? 0;
          return bTime.compareTo(aTime); // newest first
      }
    });
    return sorted;
  }
}
