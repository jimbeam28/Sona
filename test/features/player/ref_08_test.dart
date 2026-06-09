// test/features/player/ref_08_test.dart
// REF-08: player/domain/seek_utils.dart — extracted seek utility tests
//
// Verifies that clampSeek, skipForward, and skipBackward behave correctly
// as pure Dart functions with zero Flutter dependencies.

import 'package:flutter_test/flutter_test.dart';
import 'package:nas_audio_player/features/player/domain/seek_utils.dart';

void main() {
  // ── REF-08-T01: clampSeek boundary tests ──────────────────────────────

  group('REF-08-T01: clampSeek boundaries', () {
    test('negative target is clamped to Duration.zero', () {
      expect(
        clampSeek(const Duration(seconds: -1), const Duration(seconds: 100)),
        Duration.zero,
      );
    });

    test('large negative target is clamped to Duration.zero', () {
      expect(
        clampSeek(const Duration(seconds: -100), const Duration(seconds: 100)),
        Duration.zero,
      );
    });

    test('target exceeding total is clamped to total', () {
      const total = Duration(seconds: 100);
      expect(
        clampSeek(const Duration(seconds: 200), total),
        total,
      );
    });

    test('target equal to total returns total', () {
      const total = Duration(seconds: 100);
      expect(clampSeek(total, total), total);
    });

    test('target equal to zero returns zero', () {
      expect(
        clampSeek(Duration.zero, const Duration(seconds: 100)),
        Duration.zero,
      );
    });

    test('target within range returns target unchanged', () {
      expect(
        clampSeek(const Duration(seconds: 30), const Duration(seconds: 100)),
        const Duration(seconds: 30),
      );
    });

    test('both zero returns zero', () {
      expect(clampSeek(Duration.zero, Duration.zero), Duration.zero);
    });

    test('positive target with zero total is clamped to total (zero)', () {
      expect(
        clampSeek(const Duration(seconds: 10), Duration.zero),
        Duration.zero,
      );
    });
  });

  // ── REF-08-T02: skipForward step tests ────────────────────────────────

  group('REF-08-T02: skipForward steps', () {
    test('default step (15s) from middle', () {
      final result = skipForward(
        const Duration(seconds: 30),
        const Duration(seconds: 100),
      );
      expect(result, const Duration(seconds: 45));
    });

    test('10s step', () {
      final result = skipForward(
        const Duration(seconds: 30),
        const Duration(seconds: 100),
        seconds: 10,
      );
      expect(result, const Duration(seconds: 40));
    });

    test('30s step', () {
      final result = skipForward(
        const Duration(seconds: 30),
        const Duration(seconds: 100),
        seconds: 30,
      );
      expect(result, const Duration(seconds: 60));
    });

    test('60s step', () {
      final result = skipForward(
        const Duration(seconds: 30),
        const Duration(seconds: 100),
        seconds: 60,
      );
      expect(result, const Duration(seconds: 90));
    });

    test('step beyond total is clamped', () {
      const total = Duration(seconds: 100);
      final result = skipForward(
        const Duration(seconds: 90),
        total,
        seconds: 60,
      );
      expect(result, total);
    });

    test('skip from zero with default step', () {
      final result = skipForward(Duration.zero, const Duration(seconds: 100));
      expect(result, const Duration(seconds: 15));
    });
  });

  // ── REF-08-T03: skipBackward step tests ───────────────────────────────

  group('REF-08-T03: skipBackward steps', () {
    test('default step (15s) from middle', () {
      final result = skipBackward(const Duration(seconds: 30));
      expect(result, const Duration(seconds: 15));
    });

    test('10s step', () {
      final result = skipBackward(
        const Duration(seconds: 30),
        seconds: 10,
      );
      expect(result, const Duration(seconds: 20));
    });

    test('30s step', () {
      final result = skipBackward(
        const Duration(seconds: 60),
        seconds: 30,
      );
      expect(result, const Duration(seconds: 30));
    });

    test('60s step', () {
      final result = skipBackward(
        const Duration(seconds: 100),
        seconds: 60,
      );
      expect(result, const Duration(seconds: 40));
    });

    test('step beyond zero is clamped to zero', () {
      final result = skipBackward(
        const Duration(seconds: 10),
        seconds: 15,
      );
      expect(result, Duration.zero);
    });

    test('skip from zero stays at zero', () {
      final result = skipBackward(Duration.zero);
      expect(result, Duration.zero);
    });
  });
}
