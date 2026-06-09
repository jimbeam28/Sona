// test/features/player/ref_10_test.dart
// REF-10: player/domain/speed_manager.dart — extracted speed manager tests
//
// Verifies that speedOptions, isValidSpeed, getDefaultSpeed, and readSeekStep
// behave correctly as pure Dart functions with zero Flutter dependencies.

import 'package:flutter_test/flutter_test.dart';
import 'package:nas_audio_player/features/player/domain/speed_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  // ── REF-10-T01: 6 speed options validation ─────────────────────────────

  group('REF-10-T01: speedOptions validation', () {
    test('speedOptions contains exactly 6 values', () {
      expect(speedOptions.length, equals(6));
    });

    test('speedOptions contains the expected values', () {
      expect(
        speedOptions,
        unorderedEquals([0.5, 0.75, 1.0, 1.25, 1.5, 2.0]),
      );
    });

    test('speedOptions are sorted in ascending order', () {
      for (int i = 1; i < speedOptions.length; i++) {
        expect(speedOptions[i], greaterThan(speedOptions[i - 1]),
            reason: 'speedOptions should be monotonically increasing');
      }
    });

    test('speedOptions covers range from 0.5 to 2.0', () {
      expect(speedOptions.first, equals(0.5));
      expect(speedOptions.last, equals(2.0));
    });

    test('all speedOptions are valid per isValidSpeed', () {
      for (final speed in speedOptions) {
        expect(isValidSpeed(speed), isTrue,
            reason: '$speed should be a valid speed');
      }
    });

    test('each speed option is unique', () {
      expect(speedOptions.toSet().length, equals(speedOptions.length));
    });
  });

  // ── REF-10-T02: isValidSpeed boundary tests ────────────────────────────

  group('REF-10-T02: isValidSpeed boundary tests', () {
    test('exact speed options are valid', () {
      expect(isValidSpeed(0.5), isTrue);
      expect(isValidSpeed(0.75), isTrue);
      expect(isValidSpeed(1.0), isTrue);
      expect(isValidSpeed(1.25), isTrue);
      expect(isValidSpeed(1.5), isTrue);
      expect(isValidSpeed(2.0), isTrue);
    });

    test('values within tolerance (0.001) are valid', () {
      expect(isValidSpeed(0.999), isTrue,
          reason: '0.999 is within 0.01 tolerance of 1.0');
      expect(isValidSpeed(1.001), isTrue,
          reason: '1.001 is within 0.01 tolerance of 1.0');
      expect(isValidSpeed(1.509), isTrue,
          reason: '1.509 is within 0.01 tolerance of 1.5');
    });

    test('values outside tolerance are invalid', () {
      // 0.51 differs from 0.5 by 0.01 — just outside tolerance
      expect(isValidSpeed(0.51), isFalse);
      expect(isValidSpeed(0.49), isFalse);
    });

    test('values outside speedOptions range are invalid', () {
      expect(isValidSpeed(0.25), isFalse);
      expect(isValidSpeed(3.0), isFalse);
      expect(isValidSpeed(0.0), isFalse);
      expect(isValidSpeed(-1.0), isFalse);
    });

    test('values between options are invalid', () {
      expect(isValidSpeed(0.6), isFalse,
          reason: '0.6 is between 0.5 and 0.75');
      expect(isValidSpeed(1.1), isFalse,
          reason: '1.1 is between 1.0 and 1.25');
      expect(isValidSpeed(1.75), isFalse,
          reason: '1.75 is between 1.5 and 2.0');
    });

    test('2.02 and 1.97 are outside tolerance of 2.0', () {
      expect(isValidSpeed(2.02), isFalse,
          reason: '2.02 differs from 2.0 by 0.02, outside tolerance');
      expect(isValidSpeed(1.97), isFalse,
          reason: '1.97 differs from 2.0 by 0.03, outside tolerance');
    });
  });

  // ── REF-10-T03: getDefaultSpeed from SharedPreferences ─────────────────

  group('REF-10-T03: getDefaultSpeed from SharedPreferences', () {
    test('returns 1.0 when prefs is null', () {
      expect(getDefaultSpeed(null), equals(1.0));
    });

    test('returns 1.0 when no value stored', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      expect(getDefaultSpeed(prefs), equals(1.0));
    });

    test('reads persisted value from SharedPreferences', () async {
      SharedPreferences.setMockInitialValues({
        'default_playback_speed': 1.5,
      });
      final prefs = await SharedPreferences.getInstance();
      expect(getDefaultSpeed(prefs), equals(1.5));
    });

    test('reads 0.5x from SharedPreferences', () async {
      SharedPreferences.setMockInitialValues({
        'default_playback_speed': 0.5,
      });
      final prefs = await SharedPreferences.getInstance();
      expect(getDefaultSpeed(prefs), equals(0.5));
    });

    test('reads 2.0x from SharedPreferences', () async {
      SharedPreferences.setMockInitialValues({
        'default_playback_speed': 2.0,
      });
      final prefs = await SharedPreferences.getInstance();
      expect(getDefaultSpeed(prefs), equals(2.0));
    });

    test('reads updated value after write', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      expect(getDefaultSpeed(prefs), equals(1.0));

      await prefs.setDouble('default_playback_speed', 0.75);
      expect(getDefaultSpeed(prefs), equals(0.75));
    });
  });

  // ── readSeekStep tests ─────────────────────────────────────────────────

  group('readSeekStep: seek step from SharedPreferences', () {
    test('returns defaultSeekStep (15) when prefs is null', () {
      expect(readSeekStep(null), equals(15));
    });

    test('returns 15 when no value stored', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      expect(readSeekStep(prefs), equals(15));
    });

    test('reads persisted value from SharedPreferences', () async {
      SharedPreferences.setMockInitialValues({
        'seek_step_seconds': 30,
      });
      final prefs = await SharedPreferences.getInstance();
      expect(readSeekStep(prefs), equals(30));
    });

    test('reads 10s step from SharedPreferences', () async {
      SharedPreferences.setMockInitialValues({
        'seek_step_seconds': 10,
      });
      final prefs = await SharedPreferences.getInstance();
      expect(readSeekStep(prefs), equals(10));
    });

    test('reads 60s step from SharedPreferences', () async {
      SharedPreferences.setMockInitialValues({
        'seek_step_seconds': 60,
      });
      final prefs = await SharedPreferences.getInstance();
      expect(readSeekStep(prefs), equals(60));
    });

    test('reads updated value after write', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      expect(readSeekStep(prefs), equals(15));

      await prefs.setInt('seek_step_seconds', 20);
      expect(readSeekStep(prefs), equals(20));
    });
  });
}
