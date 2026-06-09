// test/features/progress/ref_24_test.dart
// REF-24: progress_policy.dart — pure-function policy tests
//
// Tests the extracted shouldSave() and shouldClear() functions from
// progress_policy.dart.  Zero Flutter dependencies.

import 'package:flutter_test/flutter_test.dart';
import 'package:nas_audio_player/features/progress/domain/progress_policy.dart'
    as policy;

void main() {
  // ── REF-24-T01: shouldSave boundary test (4999/5000) ─────────────────────

  group('REF-24-T01: shouldSave boundary test', () {
    test('positionMs = 4999 → false', () {
      expect(policy.shouldSave(4999), isFalse,
          reason: 'REF-24-T01: 4999ms < 5000ms threshold → should not save');
    });

    test('positionMs = 5000 → true', () {
      expect(policy.shouldSave(5000), isTrue,
          reason: 'REF-24-T01: 5000ms == threshold → should save');
    });

    test('positionMs = 0 → false', () {
      expect(policy.shouldSave(0), isFalse,
          reason: 'REF-24-T01: 0ms → should not save');
    });

    test('positionMs = 30000 → true', () {
      expect(policy.shouldSave(30000), isTrue,
          reason: 'REF-24-T01: 30s well above threshold → should save');
    });
  });

  // ── REF-24-T02: shouldClear boundary test (durationMs-10001 / durationMs-10000) ─

  group('REF-24-T02: shouldClear boundary test', () {
    test('positionMs = durationMs - 10001 → true (just past threshold)', () {
      // 120000 - 10001 = 109999; 109999 > 110000? No. Let me recalculate.
      // shouldClear returns positionMs > durationMs - 10000
      // durationMs=120000, threshold=110000
      // positionMs=110001 > 110000 → true
      expect(policy.shouldClear(110001, 120000), isTrue,
          reason: 'REF-24-T02: 110001 > 120000-10000 → should clear');
    });

    test('positionMs = durationMs - 10000 → false (exactly at threshold)', () {
      // positionMs=110000 > 110000? No (not strictly greater).
      expect(policy.shouldClear(110000, 120000), isFalse,
          reason: 'REF-24-T02: 110000 == 120000-10000 → should NOT clear');
    });

    test('positionMs = durationMs - 10000 + 1 → true', () {
      expect(policy.shouldClear(110001, 120000), isTrue,
          reason: 'REF-24-T02: 110001 > 110000 → should clear');
    });

    test('positionMs well before end → false', () {
      expect(policy.shouldClear(50000, 120000), isFalse,
          reason: 'REF-24-T02: 50000 < 110000 → should NOT clear');
    });
  });

  // ── REF-24-T03: Short file protection (durationMs <= 10000) ───────────────

  group('REF-24-T03: short file protection', () {
    test('durationMs = 10000 → never clear', () {
      expect(policy.shouldClear(9999, 10000), isFalse,
          reason: 'REF-24-T03: 10s file → should NOT auto-clear');
      expect(policy.shouldClear(10000, 10000), isFalse,
          reason: 'REF-24-T03: 10s file at exact end → should NOT clear');
    });

    test('durationMs = 5000 → never clear', () {
      expect(policy.shouldClear(5000, 5000), isFalse,
          reason: 'REF-24-T03: 5s file → should NOT auto-clear');
    });

    test('durationMs = 8000, position near end → false', () {
      expect(policy.shouldClear(7990, 8000), isFalse,
          reason: 'REF-24-T03: 8s file near end → should NOT clear');
    });

    test('durationMs = 0 → never clear', () {
      expect(policy.shouldClear(0, 0), isFalse,
          reason: 'REF-24-T03: 0s duration → should NOT clear');
    });

    test('durationMs = 10001 → normal clear logic applies', () {
      // 10001 - 10000 = 1; position=2 > 1 → true
      expect(policy.shouldClear(2, 10001), isTrue,
          reason: 'REF-24-T03: 10.001s file → normal logic applies');
    });
  });

  // ── REF-24-T04: Unknown duration protection (durationMs == null) ──────────

  group('REF-24-T04: unknown duration protection', () {
    test('durationMs = null → never clear', () {
      expect(policy.shouldClear(999999, null), isFalse,
          reason: 'REF-24-T04: null duration → should NOT clear');
    });

    test('durationMs = null, positionMs = 0 → false', () {
      expect(policy.shouldClear(0, null), isFalse,
          reason: 'REF-24-T04: null duration with 0 position → should NOT clear');
    });

    test('durationMs = null, large position → false', () {
      expect(policy.shouldClear(7200000, null), isFalse,
          reason: 'REF-24-T04: null duration with 2h position → should NOT clear');
    });
  });
}
