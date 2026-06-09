// test/features/browser/bug_03_test.dart
// BUG-03: 目录缓存淘汰不是 LRU — automated test suite
//
// Tests verify that the directory cache eviction uses LRU (least-recently-used)
// ordering based on lastAccessedAt, not Map insertion order.

import 'package:flutter_test/flutter_test.dart';
import 'package:nas_audio_player/features/browser/domain/cache_policy.dart';
import 'package:nas_audio_player/shared/models/nas_file.dart';

/// Helper: creates a [CacheEntry] with explicit [lastAccessedAt].
CacheEntry<List<NasFile>> _entry({
  required DateTime createdAt,
  DateTime? lastAccessedAt,
}) {
  return CacheEntry<List<NasFile>>(
    value: [NasFile(name: 'test.mp3', path: '/test.mp3', isDirectory: false)],
    createdAt: createdAt,
    lastAccessedAt: lastAccessedAt,
  );
}

/// Helper: simulates the LRU eviction logic from CachePolicy.
///
/// Takes a map of cache entries and returns a new map with at most [maxSize]
/// entries, evicting the entries with the oldest [lastAccessedAt] first.
Map<String, CacheEntry<List<NasFile>>> _evict(
    Map<String, CacheEntry<List<NasFile>>> cache,
    {int maxSize = 50}) {
  return const CachePolicy<List<NasFile>>(maxSize: 50).evict(cache);
}

void main() {
  group('BUG-03: LRU cache eviction', () {
    // ── BUG-03-T01: Accessing entry 1 prevents its eviction when entry 51 arrives
    //
    // 50 entries in cache → access entry 1 (updates its lastAccessedAt) →
    // insert entry 51 → entry 1 should survive, and the entry with the
    // oldest lastAccessedAt should be evicted instead.

    test('BUG-03-T01: accessed entry survives when cache exceeds 50', () {
      final baseTime = DateTime(2024, 1, 1, 0, 0, 0);

      // Build 50 entries with sequential timestamps
      final cache = <String, CacheEntry<List<NasFile>>>{};
      for (int i = 1; i <= 50; i++) {
        cache['conn:/dir$i'] = _entry(
          createdAt: baseTime.add(Duration(minutes: i)),
        );
      }

      // Simulate cache hit on entry 1: update lastAccessedAt to "now"
      final now = baseTime.add(const Duration(hours: 1));
      cache['conn:/dir1'] = cache['conn:/dir1']!.accessedAt(now);

      // Insert entry 51 (the 51st entry triggers eviction)
      cache['conn:/dir51'] = _entry(
        createdAt: now,
        lastAccessedAt: now,
      );

      // Evict
      final result = _evict(cache);

      expect(result.length, equals(50), reason: '缓存应保持 50 条');
      expect(result.containsKey('conn:/dir1'), isTrue,
          reason: '访问过的第 1 条不应被淘汰');
      expect(result.containsKey('conn:/dir51'), isTrue,
          reason: '新插入的第 51 条不应被淘汰');
      // Entry 2 has the oldest lastAccessedAt (only createdAt, never accessed)
      expect(result.containsKey('conn:/dir2'), isFalse,
          reason: '未访问且 lastAccessedAt 最旧的第 2 条应被淘汰');
    });

    // ── BUG-03-T02: Unaccessed entry 1 gets evicted when entry 51 arrives
    //
    // 50 entries in cache → do NOT access entry 1 → insert entry 51 →
    // entry 1 (oldest lastAccessedAt) should be evicted.

    test('BUG-03-T02: unaccessed entry evicted when cache exceeds 50', () {
      final baseTime = DateTime(2024, 1, 1, 0, 0, 0);

      // Build 50 entries with sequential timestamps
      final cache = <String, CacheEntry<List<NasFile>>>{};
      for (int i = 1; i <= 50; i++) {
        cache['conn:/dir$i'] = _entry(
          createdAt: baseTime.add(Duration(minutes: i)),
        );
      }

      // Insert entry 51 without touching entry 1
      final now = baseTime.add(const Duration(hours: 1));
      cache['conn:/dir51'] = _entry(
        createdAt: now,
        lastAccessedAt: now,
      );

      // Evict
      final result = _evict(cache);

      expect(result.length, equals(50), reason: '缓存应保持 50 条');
      expect(result.containsKey('conn:/dir1'), isFalse,
          reason: '未访问的第 1 条应被淘汰（lastAccessedAt 最旧）');
      expect(result.containsKey('conn:/dir51'), isTrue,
          reason: '新插入的第 51 条不应被淘汰');
    });

    // ── BUG-03-T03: Cache hit updates lastAccessedAt
    //
    // Verify that the CacheEntry constructor correctly sets lastAccessedAt,
    // and that creating a new entry with an explicit lastAccessedAt value
    // updates it properly.

    test('BUG-03-T03: cache hit updates lastAccessedAt', () {
      final createdAt = DateTime(2024, 1, 1, 0, 0, 0);
      final accessedAt = DateTime(2024, 1, 1, 0, 10, 0);

      // Original entry: lastAccessedAt defaults to createdAt
      final original = _entry(createdAt: createdAt);
      expect(original.lastAccessedAt, equals(createdAt),
          reason: '未设置 lastAccessedAt 时应默认等于 createdAt');

      // Simulate cache hit: create new entry with updated lastAccessedAt
      final updated = original.accessedAt(accessedAt);

      expect(updated.lastAccessedAt, equals(accessedAt),
          reason: '缓存命中后 lastAccessedAt 应更新');
      expect(updated.createdAt, equals(createdAt),
          reason: 'createdAt 应保持不变');
    });

    // ── BUG-03-T04: Repeatedly accessed old entry is never evicted
    //
    // Build 50 entries → repeatedly access entry 1 (simulating multiple
    // cache hits) → insert 10 more entries → entry 1 always survives.

    test('BUG-03-T04: repeatedly accessed entry always survives eviction', () {
      final baseTime = DateTime(2024, 1, 1, 0, 0, 0);

      // Build 50 entries
      final cache = <String, CacheEntry<List<NasFile>>>{};
      for (int i = 1; i <= 50; i++) {
        cache['conn:/dir$i'] = _entry(
          createdAt: baseTime.add(Duration(minutes: i)),
        );
      }

      // Simulate 10 separate cache hits on entry 1 over time
      for (int hit = 1; hit <= 10; hit++) {
        final hitTime = baseTime.add(Duration(hours: hit));
        cache['conn:/dir1'] = cache['conn:/dir1']!.accessedAt(hitTime);

        // Insert a new entry each time, triggering eviction
        cache['conn:/new$hit'] = _entry(
          createdAt: hitTime,
          lastAccessedAt: hitTime,
        );

        // Evict
        final result = _evict(cache);

        expect(result.containsKey('conn:/dir1'), isTrue,
            reason: '第 $hit 次访问后，entry 1 应仍然存活');

        // Update cache for next iteration
        cache
          ..clear()
          ..addAll(result);
      }

      // Final check: entry 1 survived all 10 evictions
      expect(cache.containsKey('conn:/dir1'), isTrue,
          reason: '多次访问后 entry 1 始终不应被淘汰');
      expect(cache.length, equals(50), reason: '最终缓存应保持 50 条');
    });
  });
}
