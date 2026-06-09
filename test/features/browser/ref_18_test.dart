// test/features/browser/ref_18_test.dart
// REF-18: CacheEntry + CachePolicy extracted to domain/cache_policy.dart
//
// Tests verify:
// - TTL expiration (5 minutes)
// - LRU eviction (max 50 entries)
// - lastAccessedAt update on access

import 'package:flutter_test/flutter_test.dart';
import 'package:nas_audio_player/features/browser/domain/cache_policy.dart';

/// Helper: creates a [CacheEntry] with a string value.
CacheEntry<String> _entry({
  required DateTime createdAt,
  DateTime? lastAccessedAt,
}) {
  return CacheEntry<String>(
    value: 'data',
    createdAt: createdAt,
    lastAccessedAt: lastAccessedAt,
  );
}

void main() {
  group('REF-18: CachePolicy', () {
    const policy = CachePolicy<String>();

    // ── REF-18-T01: TTL 5 分钟内 → 命中 ──────────────────────────────────────

    test('REF-18-T01: entry within 5min TTL is alive', () {
      final createdAt = DateTime(2024, 1, 1, 0, 0, 0);
      final entry = _entry(createdAt: createdAt);

      // 4 minutes later — still within TTL
      final now = createdAt.add(const Duration(minutes: 4));
      expect(policy.isAlive(entry, now), isTrue,
          reason: '4 分钟内缓存条目应存活（TTL=5min）');
    });

    // ── REF-18-T02: TTL 超过 5 分钟 → 过期 ──────────────────────────────────

    test('REF-18-T02: entry past 5min TTL is expired', () {
      final createdAt = DateTime(2024, 1, 1, 0, 0, 0);
      final entry = _entry(createdAt: createdAt);

      // 6 minutes later — past TTL
      final now = createdAt.add(const Duration(minutes: 6));
      expect(policy.isAlive(entry, now), isFalse,
          reason: '超过 5 分钟后缓存条目应过期');
    });

    // ── REF-18-T03: 容量 50 条 → 不淘汰 ─────────────────────────────────────

    test('REF-18-T03: 50 entries → no eviction', () {
      final now = DateTime(2024, 1, 1, 0, 0, 0);
      final cache = <String, CacheEntry<String>>{};
      for (int i = 1; i <= 50; i++) {
        cache['key:$i'] = _entry(createdAt: now.add(Duration(minutes: i)));
      }

      final result = policy.evict(cache);
      expect(result.length, equals(50), reason: '50 条时不应淘汰');
    });

    // ── REF-18-T04: 容量 51 条 → LRU 淘汰 ───────────────────────────────────

    test('REF-18-T04: 51 entries → LRU eviction of oldest', () {
      final now = DateTime(2024, 1, 1, 0, 0, 0);
      final cache = <String, CacheEntry<String>>{};
      for (int i = 1; i <= 50; i++) {
        cache['key:$i'] = _entry(createdAt: now.add(Duration(minutes: i)));
      }

      // Insert 51st entry — triggers eviction
      final result = policy.put(
        cache,
        'key:51',
        _entry(createdAt: now.add(const Duration(minutes: 51))),
      );

      expect(result.length, equals(50), reason: '51 条触发淘汰后应为 50 条');
      expect(result.containsKey('key:1'), isFalse,
          reason: 'key:1 的 lastAccessedAt 最旧，应被淘汰');
      expect(result.containsKey('key:51'), isTrue,
          reason: '新插入的 key:51 应保留');
    });

    // ── REF-18-T05: 访问旧条目 → 更新 lastAccessedAt → 不被淘汰 ────────────

    test('REF-18-T05: accessed old entry survives eviction', () {
      final now = DateTime(2024, 1, 1, 0, 0, 0);
      final cache = <String, CacheEntry<String>>{};
      for (int i = 1; i <= 50; i++) {
        cache['key:$i'] = _entry(createdAt: now.add(Duration(minutes: i)));
      }

      // Simulate cache hit on key:1 — update lastAccessedAt to "now"
      final accessTime = now.add(const Duration(hours: 1));
      cache['key:1'] = cache['key:1']!.accessedAt(accessTime);

      // Insert 51st entry — triggers eviction
      final result = policy.put(
        cache,
        'key:51',
        _entry(createdAt: accessTime),
      );

      expect(result.length, equals(50), reason: '淘汰后应为 50 条');
      expect(result.containsKey('key:1'), isTrue,
          reason: '访问过的 key:1 不应被淘汰');
      expect(result.containsKey('key:2'), isFalse,
          reason: '未访问的 key:2（lastAccessedAt 最旧）应被淘汰');
      expect(result.containsKey('key:51'), isTrue,
          reason: '新插入的 key:51 应保留');
    });
  });
}
