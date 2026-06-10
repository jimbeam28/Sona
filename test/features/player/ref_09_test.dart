// test/features/player/ref_09_test.dart
// REF-09: player/domain/play_mode.dart — extracted play mode domain tests
//
// Verifies that PlayMode enum, nextPlayMode, labelForPlayMode, nextIndex,
// and previousIndex behave correctly as pure Dart functions with zero
// Flutter dependencies.
//
// Test cases:
//   REF-09-T01: 4 modes' nextIndex behavior
//   REF-09-T02: 4 modes' previousIndex behavior
//   REF-09-T03: boundary conditions (empty queue, single track, out-of-bounds)
//   REF-09-T04: mode cycling

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:nas_audio_player/features/player/domain/play_mode.dart';

void main() {
  // ── REF-09-T01: nextIndex behavior for all 4 modes ─────────────────────

  group('REF-09-T01: nextIndex for all 4 modes', () {
    const length = 5;

    // sequential: advances by 1, null at end
    group('sequential', () {
      test('returns next index within range', () {
        expect(nextIndex(0, length, PlayMode.sequential), equals(1));
        expect(nextIndex(1, length, PlayMode.sequential), equals(2));
        expect(nextIndex(2, length, PlayMode.sequential), equals(3));
        expect(nextIndex(3, length, PlayMode.sequential), equals(4));
      });

      test('returns null at end of queue', () {
        expect(nextIndex(4, length, PlayMode.sequential), isNull);
      });
    });

    // repeatOne: always returns the same index
    group('repeatOne', () {
      test('returns same index for all positions', () {
        for (int i = 0; i < length; i++) {
          expect(nextIndex(i, length, PlayMode.repeatOne), equals(i),
              reason: 'repeatOne nextIndex($i) should return $i');
        }
      });
    });

    // repeatAll: advances by 1, wraps at end
    group('repeatAll', () {
      test('advances normally within range', () {
        expect(nextIndex(0, length, PlayMode.repeatAll), equals(1));
        expect(nextIndex(1, length, PlayMode.repeatAll), equals(2));
        expect(nextIndex(2, length, PlayMode.repeatAll), equals(3));
        expect(nextIndex(3, length, PlayMode.repeatAll), equals(4));
      });

      test('wraps from last to first', () {
        expect(nextIndex(4, length, PlayMode.repeatAll), equals(0));
      });
    });

    // shuffle: returns a different valid index
    group('shuffle', () {
      test('returns a valid different index', () {
        const current = 2;
        final rng = Random(42);
        for (int i = 0; i < 20; i++) {
          final result =
              nextIndex(current, length, PlayMode.shuffle, random: rng);
          expect(result, isNotNull);
          expect(result! >= 0 && result < length, isTrue,
              reason: 'shuffle result $result should be in [0, $length)');
          expect(result, isNot(equals(current)),
              reason: 'shuffle should not return current index');
        }
      });

      test('produces varied results over many calls', () {
        final rng = Random(123);
        final results = <int>{};
        for (int i = 0; i < 50; i++) {
          results.add(nextIndex(5, 100, PlayMode.shuffle, random: rng)!);
        }
        expect(results.length, greaterThan(1),
            reason: 'shuffle should produce varied indices');
      });
    });
  });

  // ── REF-09-T02: previousIndex behavior for all 4 modes ─────────────────

  group('REF-09-T02: previousIndex for all 4 modes', () {
    const length = 5;

    // sequential: goes back by 1, null at start
    group('sequential', () {
      test('returns previous index within range', () {
        expect(previousIndex(4, length, PlayMode.sequential), equals(3));
        expect(previousIndex(3, length, PlayMode.sequential), equals(2));
        expect(previousIndex(2, length, PlayMode.sequential), equals(1));
        expect(previousIndex(1, length, PlayMode.sequential), equals(0));
      });

      test('returns null at start of queue', () {
        expect(previousIndex(0, length, PlayMode.sequential), isNull);
      });
    });

    // repeatOne: always returns the same index
    group('repeatOne', () {
      test('returns same index for all positions', () {
        for (int i = 0; i < length; i++) {
          expect(previousIndex(i, length, PlayMode.repeatOne), equals(i),
              reason: 'repeatOne previousIndex($i) should return $i');
        }
      });
    });

    // repeatAll: goes back by 1, wraps at start
    group('repeatAll', () {
      test('goes back normally within range', () {
        expect(previousIndex(4, length, PlayMode.repeatAll), equals(3));
        expect(previousIndex(3, length, PlayMode.repeatAll), equals(2));
        expect(previousIndex(2, length, PlayMode.repeatAll), equals(1));
        expect(previousIndex(1, length, PlayMode.repeatAll), equals(0));
      });

      test('wraps from first to last', () {
        expect(previousIndex(0, length, PlayMode.repeatAll), equals(4));
      });
    });

    // shuffle: returns a different valid index
    group('shuffle', () {
      test('returns a valid different index', () {
        const current = 2;
        final rng = Random(99);
        for (int i = 0; i < 20; i++) {
          final result =
              previousIndex(current, length, PlayMode.shuffle, random: rng);
          expect(result, isNotNull);
          expect(result! >= 0 && result < length, isTrue,
              reason: 'shuffle result $result should be in [0, $length)');
          expect(result, isNot(equals(current)),
              reason: 'shuffle should not return current index');
        }
      });
    });
  });

  // ── REF-09-T03: boundary conditions ────────────────────────────────────

  group('REF-09-T03: boundary conditions', () {
    // Empty queue
    group('empty queue (length == 0)', () {
      test('nextIndex returns null for all modes', () {
        for (final mode in PlayMode.values) {
          expect(nextIndex(0, 0, mode), isNull,
              reason: 'empty queue nextIndex with $mode should be null');
        }
      });

      test('previousIndex returns null for all modes', () {
        for (final mode in PlayMode.values) {
          expect(previousIndex(0, 0, mode), isNull,
              reason: 'empty queue previousIndex with $mode should be null');
        }
      });
    });

    // Single-track queue
    group('single-track queue (length == 1)', () {
      test('sequential next returns null', () {
        expect(nextIndex(0, 1, PlayMode.sequential), isNull);
      });

      test('sequential previous returns null', () {
        expect(previousIndex(0, 1, PlayMode.sequential), isNull);
      });

      test('repeatOne next returns same index', () {
        expect(nextIndex(0, 1, PlayMode.repeatOne), equals(0));
      });

      test('repeatOne previous returns same index', () {
        expect(previousIndex(0, 1, PlayMode.repeatOne), equals(0));
      });

      test('repeatAll next returns same index (wraps)', () {
        expect(nextIndex(0, 1, PlayMode.repeatAll), equals(0));
      });

      test('repeatAll previous returns same index (wraps)', () {
        expect(previousIndex(0, 1, PlayMode.repeatAll), equals(0));
      });

      test('shuffle next returns null (no different index)', () {
        expect(nextIndex(0, 1, PlayMode.shuffle, random: Random(1)), isNull);
      });

      test('shuffle previous returns null (no different index)', () {
        expect(
            previousIndex(0, 1, PlayMode.shuffle, random: Random(1)), isNull);
      });
    });

    // Out-of-bounds current index
    group('out-of-bounds current index', () {
      test('negative current returns null for all modes (nextIndex)', () {
        for (final mode in PlayMode.values) {
          expect(nextIndex(-1, 5, mode), isNull,
              reason: 'negative current nextIndex with $mode should be null');
        }
      });

      test('negative current returns null for all modes (previousIndex)', () {
        for (final mode in PlayMode.values) {
          expect(previousIndex(-1, 5, mode), isNull,
              reason:
                  'negative current previousIndex with $mode should be null');
        }
      });

      test('current >= length returns null for all modes (nextIndex)', () {
        for (final mode in PlayMode.values) {
          expect(nextIndex(5, 5, mode), isNull,
              reason: 'current == length nextIndex with $mode should be null');
          expect(nextIndex(10, 5, mode), isNull,
              reason: 'current > length nextIndex with $mode should be null');
        }
      });

      test('current >= length returns null for all modes (previousIndex)', () {
        for (final mode in PlayMode.values) {
          expect(previousIndex(5, 5, mode), isNull,
              reason:
                  'current == length previousIndex with $mode should be null');
          expect(previousIndex(10, 5, mode), isNull,
              reason:
                  'current > length previousIndex with $mode should be null');
        }
      });
    });

    // Two-item queue shuffle
    group('two-item queue shuffle', () {
      test('nextIndex always picks the other one', () {
        final rng = Random(7);
        for (int i = 0; i < 10; i++) {
          expect(nextIndex(0, 2, PlayMode.shuffle, random: rng), equals(1));
          expect(nextIndex(1, 2, PlayMode.shuffle, random: rng), equals(0));
        }
      });

      test('previousIndex always picks the other one', () {
        final rng = Random(7);
        for (int i = 0; i < 10; i++) {
          expect(previousIndex(0, 2, PlayMode.shuffle, random: rng), equals(1));
          expect(previousIndex(1, 2, PlayMode.shuffle, random: rng), equals(0));
        }
      });
    });
  });

  // ── REF-09-T04: mode cycling ───────────────────────────────────────────

  group('REF-09-T04: mode cycling', () {
    test('cycle: sequential -> repeatOne -> repeatAll -> shuffle -> sequential',
        () {
      expect(nextPlayMode(PlayMode.sequential), equals(PlayMode.repeatOne));
      expect(nextPlayMode(PlayMode.repeatOne), equals(PlayMode.repeatAll));
      expect(nextPlayMode(PlayMode.repeatAll), equals(PlayMode.shuffle));
      expect(nextPlayMode(PlayMode.shuffle), equals(PlayMode.sequential));
    });

    test('full cycle returns to starting mode', () {
      var mode = PlayMode.sequential;
      for (int i = 0; i < 4; i++) {
        mode = nextPlayMode(mode);
      }
      expect(mode, equals(PlayMode.sequential),
          reason: '4 cycles should return to sequential');
    });

    test('two full cycles also return to starting mode', () {
      var mode = PlayMode.repeatAll;
      for (int i = 0; i < 8; i++) {
        mode = nextPlayMode(mode);
      }
      expect(mode, equals(PlayMode.repeatAll),
          reason: '8 cycles from repeatAll should return to repeatAll');
    });

    test('labelForPlayMode returns distinct labels', () {
      final labels = PlayMode.values.map(labelForPlayMode).toSet();
      expect(labels.length, equals(4),
          reason: 'each mode should have a distinct label');
    });

    test('labelForPlayMode returns expected Chinese labels', () {
      expect(labelForPlayMode(PlayMode.sequential), equals('顺序播放'));
      expect(labelForPlayMode(PlayMode.repeatOne), equals('单曲循环'));
      expect(labelForPlayMode(PlayMode.repeatAll), equals('列表循环'));
      expect(labelForPlayMode(PlayMode.shuffle), equals('随机播放'));
    });
  });
}
