// lib/features/browser/domain/cache_policy.dart
// Pure-Dart cache policy: TTL expiration + LRU eviction.
// Extracted from browser_provider.dart (REF-18).
// Zero Flutter dependencies.

/// Default cache TTL: entries older than 5 minutes are considered stale.
const defaultCacheTtl = Duration(minutes: 5);

/// Default maximum number of entries in the cache before LRU eviction kicks in.
const defaultMaxCacheSize = 50;

/// A cached entry with timestamps for TTL checking and LRU eviction.
///
/// [lastAccessedAt] defaults to [createdAt] when not explicitly provided,
/// which is the common case for freshly-inserted entries.
class CacheEntry<V> {
  /// The cached value (e.g. a list of files).
  final V value;

  /// When this entry was first created.
  final DateTime createdAt;

  /// When this entry was last accessed (read from cache).
  /// Used by LRU eviction to determine which entry to drop.
  final DateTime lastAccessedAt;

  CacheEntry({
    required this.value,
    required this.createdAt,
    DateTime? lastAccessedAt,
  }) : lastAccessedAt = lastAccessedAt ?? createdAt;

  /// Returns a copy of this entry with [lastAccessedAt] set to [now].
  CacheEntry<V> accessedAt(DateTime now) {
    return CacheEntry<V>(
      value: value,
      createdAt: createdAt,
      lastAccessedAt: now,
    );
  }
}

/// Pure-Dart cache policy providing TTL expiration and LRU eviction.
///
/// This class holds no state — it operates on the cache map passed to its
/// methods, making it easy to test and integrate with any state management
/// approach.
class CachePolicy<V> {
  /// Time-to-live for cache entries.
  final Duration ttl;

  /// Maximum number of entries before LRU eviction.
  final int maxSize;

  const CachePolicy({
    this.ttl = defaultCacheTtl,
    this.maxSize = defaultMaxCacheSize,
  });

  /// Returns `true` if [entry] has not yet exceeded the TTL relative to [now].
  bool isAlive(CacheEntry<V> entry, DateTime now) {
    return now.difference(entry.createdAt) < ttl;
  }

  /// Inserts [entry] into [cache] under [key], then evicts the least-recently
  /// used entries if the cache exceeds [maxSize].
  ///
  /// Returns the updated cache map (a new map, leaving [cache] untouched).
  Map<String, CacheEntry<V>> put(
    Map<String, CacheEntry<V>> cache,
    String key,
    CacheEntry<V> entry,
  ) {
    final updated = Map<String, CacheEntry<V>>.from(cache);
    updated[key] = entry;
    return evict(updated);
  }

  /// Evicts the least-recently used entries from [cache] until its size is
  /// at most [maxSize].
  ///
  /// Entries are sorted by [CacheEntry.lastAccessedAt] ascending; the oldest
  /// entries are removed first.
  ///
  /// Returns the updated cache map.
  Map<String, CacheEntry<V>> evict(Map<String, CacheEntry<V>> cache) {
    if (cache.length <= maxSize) return cache;

    final sortedEntries = cache.entries.toList()
      ..sort(
          (a, b) => a.value.lastAccessedAt.compareTo(b.value.lastAccessedAt));

    final keysToRemove =
        sortedEntries.take(cache.length - maxSize).map((e) => e.key).toList();

    final result = Map<String, CacheEntry<V>>.from(cache);
    for (final k in keysToRemove) {
      result.remove(k);
    }
    return result;
  }
}
