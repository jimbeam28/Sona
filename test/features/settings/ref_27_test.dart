// test/features/settings/ref_27_test.dart
// REF-27: SettingsService unit tests.
//
// Tests the pure Dart domain service for theme, speed, and seek step
// read/write persistence via SharedPreferences.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nas_audio_player/features/settings/domain/settings_service.dart';

void main() {
  const service = SettingsService();

  // ═══════════════════════════════════════════════════════════════════════════
  // REF-27-T01: 主题读写持久化
  // ═══════════════════════════════════════════════════════════════════════════

  group('REF-27-T01: 主题读写持久化', () {
    test('getThemeMode with null prefs returns system', () {
      expect(service.getThemeMode(null), equals(ThemeMode.system));
    });

    test('getThemeMode with empty prefs returns system', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      expect(service.getThemeMode(prefs), equals(ThemeMode.system));
    });

    test('setThemeMode persists to SharedPreferences', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      service.setThemeMode(prefs, ThemeMode.dark);

      expect(prefs.getString('theme_mode'), equals('dark'));
      expect(service.getThemeMode(prefs), equals(ThemeMode.dark));
    });

    test('setThemeMode with null prefs does not throw', () {
      expect(() => service.setThemeMode(null, ThemeMode.light), returnsNormally);
    });

    test('getThemeMode reads all three modes correctly', () async {
      for (final mode in ThemeMode.values) {
        SharedPreferences.setMockInitialValues({'theme_mode': mode.name});
        final prefs = await SharedPreferences.getInstance();
        expect(service.getThemeMode(prefs), equals(mode),
            reason: 'Should read ${mode.name} correctly');
      }
    });

    test('getThemeMode with invalid string returns system', () async {
      SharedPreferences.setMockInitialValues({'theme_mode': 'invalid'});
      final prefs = await SharedPreferences.getInstance();
      expect(service.getThemeMode(prefs), equals(ThemeMode.system));
    });

    test('theme mode round-trip: write then read', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      service.setThemeMode(prefs, ThemeMode.light);
      expect(service.getThemeMode(prefs), equals(ThemeMode.light));

      service.setThemeMode(prefs, ThemeMode.dark);
      expect(service.getThemeMode(prefs), equals(ThemeMode.dark));

      service.setThemeMode(prefs, ThemeMode.system);
      expect(service.getThemeMode(prefs), equals(ThemeMode.system));
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // REF-27-T02: 默认速度读写
  // ═══════════════════════════════════════════════════════════════════════════

  group('REF-27-T02: 默认速度读写', () {
    test('getDefaultSpeed with null prefs returns 1.0', () {
      expect(service.getDefaultSpeed(null), equals(1.0));
    });

    test('getDefaultSpeed with empty prefs returns 1.0', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      expect(service.getDefaultSpeed(prefs), equals(1.0));
    });

    test('setDefaultSpeed persists to SharedPreferences', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      final result = service.setDefaultSpeed(prefs, 1.5);

      expect(result, isTrue);
      expect(prefs.getDouble('default_playback_speed'), equals(1.5));
      expect(service.getDefaultSpeed(prefs), equals(1.5));
    });

    test('setDefaultSpeed with null prefs returns true (no-op)', () {
      final result = service.setDefaultSpeed(null, 1.5);
      expect(result, isTrue);
    });

    test('setDefaultSpeed rejects invalid speeds', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      for (final speed in [0.3, 0.6, 1.1, 3.0]) {
        final result = service.setDefaultSpeed(prefs, speed);
        expect(result, isFalse,
            reason: '$speed is not a valid speed option');
      }

      expect(prefs.getDouble('default_playback_speed'), isNull,
          reason: 'No valid speed should have been written');
    });

    test('getDefaultSpeed reads persisted value after restart', () async {
      SharedPreferences.setMockInitialValues({
        'default_playback_speed': 2.0,
      });
      final prefs = await SharedPreferences.getInstance();
      expect(service.getDefaultSpeed(prefs), equals(2.0));
    });

    test('speed round-trip: write multiple values', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      for (final speed in speedOptions) {
        final result = service.setDefaultSpeed(prefs, speed);
        expect(result, isTrue);
        expect(service.getDefaultSpeed(prefs), equals(speed),
            reason: 'Should read back $speed');
      }
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // REF-27-T03: 快进步长读写
  // ═══════════════════════════════════════════════════════════════════════════

  group('REF-27-T03: 快进步长读写', () {
    test('getSeekStep with null prefs returns default 15', () {
      expect(service.getSeekStep(null), equals(15));
    });

    test('getSeekStep with empty prefs returns default 15', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      expect(service.getSeekStep(prefs), equals(15));
    });

    test('setSeekStep persists to SharedPreferences', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      final result = service.setSeekStep(prefs, 30);

      expect(result, isTrue);
      expect(prefs.getInt('seek_step_seconds'), equals(30));
      expect(service.getSeekStep(prefs), equals(30));
    });

    test('setSeekStep with null prefs returns true (no-op)', () {
      final result = service.setSeekStep(null, 10);
      expect(result, isTrue);
    });

    test('setSeekStep rejects invalid values', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      for (final step in [5, 20, 45, 90, 0, -1]) {
        final result = service.setSeekStep(prefs, step);
        expect(result, isFalse, reason: '$step is not a valid seek step');
      }

      expect(prefs.getInt('seek_step_seconds'), isNull,
          reason: 'No valid step should have been written');
    });

    test('getSeekStep reads persisted value after restart', () async {
      SharedPreferences.setMockInitialValues({
        'seek_step_seconds': 60,
      });
      final prefs = await SharedPreferences.getInstance();
      expect(service.getSeekStep(prefs), equals(60));
    });

    test('seek step round-trip: write all valid options', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      for (final step in seekStepOptions) {
        final result = service.setSeekStep(prefs, step);
        expect(result, isTrue);
        expect(service.getSeekStep(prefs), equals(step),
            reason: 'Should read back $step');
      }
    });
  });
}
