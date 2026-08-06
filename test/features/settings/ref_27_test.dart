// test/features/settings/ref_27_test.dart
// REF-27: SettingsService unit tests.
//
// REF-04-S1/S2: settings_service 的 speed/step 方法与常量（getDefaultSpeed /
// setDefaultSpeed / isValidSpeed / getSeekStep / setSeekStep /
// labelForSeekStep / speedOptions / seekStepOptions）已全部删除，规范定义
// 迁移到 speed_manager.dart（REF-04-S1）。本文件只保留 theme + remember-speed
// 测试（REF-27-T01），并新增 REF-04-S1/S2 静态断言锚定 API 收缩。

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nas_audio_player/features/settings/domain/settings_service.dart';

void main() {
  const service = SettingsService();

  // ═══════════════════════════════════════════════════════════════════════════
  // REF-27-T01: 主题读写持久化
  // ═══════════════════════════════════════════════════════════════════════════

  group('REF-27-T01: 主题读写持久化', () {
    // REF-01-A1: domain 层用 String 表示 theme mode（'system'/'light'/'dark'），
    // String ↔ ThemeMode 映射在 provider 层。

    test('getThemeMode with null prefs returns system', () {
      expect(service.getThemeMode(null), equals('system'));
    });

    test('getThemeMode with empty prefs returns system', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      expect(service.getThemeMode(prefs), equals('system'));
    });

    test('setThemeMode persists to SharedPreferences', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      service.setThemeMode(prefs, 'dark');

      expect(prefs.getString('theme_mode'), equals('dark'));
      expect(service.getThemeMode(prefs), equals('dark'));
    });

    test('setThemeMode with null prefs does not throw', () {
      expect(() => service.setThemeMode(null, 'light'), returnsNormally);
    });

    test('getThemeMode reads all three modes correctly', () async {
      for (final mode in ['system', 'light', 'dark']) {
        SharedPreferences.setMockInitialValues({'theme_mode': mode});
        final prefs = await SharedPreferences.getInstance();
        expect(service.getThemeMode(prefs), equals(mode),
            reason: 'Should read $mode correctly');
      }
    });

    test('getThemeMode with invalid string returns system', () async {
      SharedPreferences.setMockInitialValues({'theme_mode': 'invalid'});
      final prefs = await SharedPreferences.getInstance();
      expect(service.getThemeMode(prefs), equals('system'));
    });

    test('theme mode round-trip: write then read', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      service.setThemeMode(prefs, 'light');
      expect(service.getThemeMode(prefs), equals('light'));

      service.setThemeMode(prefs, 'dark');
      expect(service.getThemeMode(prefs), equals('dark'));

      service.setThemeMode(prefs, 'system');
      expect(service.getThemeMode(prefs), equals('system'));
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // REF-04-S1/S2: settings_service speed/step 方法与常量已删除
  // ═══════════════════════════════════════════════════════════════════════════
  //
  // 编译期断言：本文件不再调用 service.getDefaultSpeed / service.getSeekStep 等
  // —— 若 settings_service 仍暴露这些方法，本文件可编译通过但下面的静态断言
  // 会失败；若实现正确删除，静态断言通过。原 REF-27-T02/T03 的行为语义
  // （校验后写入、key 值不变）迁移到 speed_manager 的 setDefaultSpeed /
  // setSeekStep，由 settings_test.dart 的 REF-04-S1 迁移测试覆盖。

  group('REF-04-S1/S2: settings_service speed/step 方法已删除', () {
    test('REF-04-S2: settings_service.dart 不含已删除的 8 个符号', () {
      final source = File('lib/features/settings/domain/settings_service.dart');
      expect(source.existsSync(), isTrue,
          reason: 'settings_service.dart 应存在（REF-04 实现未落地时预期失败）');

      final text = source.readAsStringSync();
      const forbiddenSymbols = [
        'getDefaultSpeed',
        'setDefaultSpeed',
        'getSeekStep',
        'setSeekStep',
        'labelForSeekStep',
        'speedOptions',
        'seekStepOptions',
        'isValidSpeed',
      ];
      for (final symbol in forbiddenSymbols) {
        expect(text, isNot(contains(symbol)),
            reason: 'REF-04-S1/S2: settings_service.dart 不得再定义 $symbol');
      }
    });

    test('REF-04-S1: speed_manager.dart 是 speed/step 唯一规范定义处', () {
      final source = File('lib/features/player/domain/speed_manager.dart');
      expect(source.existsSync(), isTrue,
          reason: 'speed_manager.dart 应存在（REF-04 实现未落地时预期失败）');

      final text = source.readAsStringSync();
      const canonicalSymbols = [
        'defaultSpeedKey',
        'seekStepPrefsKey',
        'defaultSeekStep',
        'speedOptions',
        'seekStepOptions',
        'isValidSpeed',
        'setDefaultSpeed',
        'setSeekStep',
      ];
      for (final symbol in canonicalSymbols) {
        expect(text, contains(symbol),
            reason: 'REF-04-S1: speed_manager.dart 应定义 $symbol');
      }

      // 否定断言：不改变运行时 key 值。
      expect(text, contains("'default_playback_speed'"),
          reason: 'REF-04-S1: defaultSpeedKey 值必须保持 default_playback_speed');
      expect(text, contains("'seek_step_seconds'"),
          reason: 'REF-04-S1: seekStepPrefsKey 值必须保持 seek_step_seconds');
    });

    test('REF-04-S2: settings_service 保留 theme + remember-speed 方法', () {
      final text = File('lib/features/settings/domain/settings_service.dart')
          .readAsStringSync();
      const retainedSymbols = [
        'getThemeMode',
        'setThemeMode',
        'labelForThemeMode',
        'getRememberSpeed',
        'setRememberSpeed',
      ];
      for (final symbol in retainedSymbols) {
        expect(text, contains(symbol),
            reason: 'REF-04-S2: settings_service 应保留 $symbol');
      }
    });
  });
}
