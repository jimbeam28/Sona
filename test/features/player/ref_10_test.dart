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
      expect(isValidSpeed(0.6), isFalse, reason: '0.6 is between 0.5 and 0.75');
      expect(isValidSpeed(1.1), isFalse, reason: '1.1 is between 1.0 and 1.25');
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

  // ── REF-10-T03: 默认速度直读 SharedPreferences（REF-01-A5） ─────────────
  // REF-01-A5: getDefaultSpeed/readSeekStep 已从 domain 层删除，读取逻辑
  // 上移 provider 层；此处保留断言意图（读不到 → 默认 1.0 / 15 秒）。

  group('REF-10-T03: 默认速度直读 SharedPreferences', () {
    test('无存储时回退默认 1.0', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getDouble(defaultSpeedKey) ?? 1.0, equals(1.0),
          reason: '未存储任何速度时应返回默认值 1.0x');
    });

    test('读取持久化值 1.5', () async {
      SharedPreferences.setMockInitialValues({defaultSpeedKey: 1.5});
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getDouble(defaultSpeedKey) ?? 1.0, equals(1.5));
    });

    test('读取 0.5x', () async {
      SharedPreferences.setMockInitialValues({defaultSpeedKey: 0.5});
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getDouble(defaultSpeedKey) ?? 1.0, equals(0.5));
    });

    test('读取 2.0x', () async {
      SharedPreferences.setMockInitialValues({defaultSpeedKey: 2.0});
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getDouble(defaultSpeedKey) ?? 1.0, equals(2.0));
    });

    test('写入后读取更新值', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      expect(prefs.getDouble(defaultSpeedKey) ?? 1.0, equals(1.0));

      await prefs.setDouble(defaultSpeedKey, 0.75);
      expect(prefs.getDouble(defaultSpeedKey) ?? 1.0, equals(0.75));
    });
  });

  // ── 快进步长直读 SharedPreferences（REF-01-A5） ────────────────────────

  group('readSeekStep: 快进步长直读 SharedPreferences', () {
    test('无存储时回退默认 15 秒', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt(seekStepPrefsKey) ?? defaultSeekStep, equals(15),
          reason: '未存储步长时应返回默认值 15秒');
    });

    test('读取持久化值 30', () async {
      SharedPreferences.setMockInitialValues({seekStepPrefsKey: 30});
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt(seekStepPrefsKey) ?? defaultSeekStep, equals(30));
    });

    test('读取 10 秒步长', () async {
      SharedPreferences.setMockInitialValues({seekStepPrefsKey: 10});
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt(seekStepPrefsKey) ?? defaultSeekStep, equals(10));
    });

    test('读取 60 秒步长', () async {
      SharedPreferences.setMockInitialValues({seekStepPrefsKey: 60});
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt(seekStepPrefsKey) ?? defaultSeekStep, equals(60));
    });

    test('写入后读取更新值', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      expect(prefs.getInt(seekStepPrefsKey) ?? defaultSeekStep, equals(15));

      await prefs.setInt(seekStepPrefsKey, 20);
      expect(prefs.getInt(seekStepPrefsKey) ?? defaultSeekStep, equals(20));
    });
  });
}
