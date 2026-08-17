// test/features/settings/ref_10_unify_test.dart
// REF-10 门禁测试（spec docs/features/REF-10.md §5.4 指定文件）。
//
// 锚定 settings_service 顶层函数与实例方法双份实现统一：
//   - S5 迁移后的 REF-01-S1 组转实例断言（settings_test.dart 内完成）
//   - S6 删除顶层后仍绿 + 死符号静态断言
//   - INV1 settings_service.dart 主题三件语义只允许实例方法单份
//   - INV3 settings_provider 顶层 getThemeMode（String→ThemeMode 映射）仍在

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('REF-10: settings_service 统一为实例方法单份', () {
    test('REF-10-S6: 顶层函数形态零命中', () {
      final content = File(
              '${Directory.current.path}/lib/features/settings/domain/settings_service.dart')
          .readAsStringSync();

      // 顶层形态：行首 String/void + 函数名（不在 class 内缩进）
      expect(
          RegExp(r'^String getThemeMode\(SharedPreferences\? prefs\)',
                  multiLine: true)
              .hasMatch(content),
          isFalse,
          reason: '顶层 getThemeMode 必须删除');
      expect(
          RegExp(r'^void setThemeMode\(SharedPreferences\? prefs',
                  multiLine: true)
              .hasMatch(content),
          isFalse,
          reason: '顶层 setThemeMode 必须删除');
      expect(
          RegExp(r'^String labelForThemeMode\(String mode\)', multiLine: true)
              .hasMatch(content),
          isFalse,
          reason: '顶层 labelForThemeMode 必须删除');
    });

    test('REF-10-S6 否定: 实例方法形态仍在（class 内成员）', () {
      final content = File(
              '${Directory.current.path}/lib/features/settings/domain/settings_service.dart')
          .readAsStringSync();

      expect(content,
          contains('  String getThemeMode(SharedPreferences? prefs) {'),
          reason: '实例方法 getThemeMode 必须保留');
      expect(
          content,
          contains(
              '  void setThemeMode(SharedPreferences? prefs, String mode)'),
          reason: '实例方法 setThemeMode 必须保留');
      expect(content, contains('  String labelForThemeMode(String mode) {'),
          reason: '实例方法 labelForThemeMode 必须保留');
      expect(content, contains('class SettingsService'),
          reason: 'SettingsService 类必须保留');
    });

    test('REF-10-INV1 REF-10-INV2: 主题三件语义只允许一份实现（实例方法）', () {
      final content = File(
              '${Directory.current.path}/lib/features/settings/domain/settings_service.dart')
          .readAsStringSync();

      // 全文件 getThemeMode 出现次数 = 1（实例方法定义 1 次 + 注释引用若干）
      final defCount = RegExp(r'getThemeMode\(SharedPreferences\? prefs\)')
          .allMatches(content)
          .length;
      expect(defCount, 1, reason: 'INV1: getThemeMode 只能有一份实现');

      final setCount =
          RegExp(r'setThemeMode\(SharedPreferences\? prefs, String mode\)')
              .allMatches(content)
              .length;
      expect(setCount, 1, reason: 'INV1: setThemeMode 只能有一份实现');

      final labelCount = RegExp(r'labelForThemeMode\(String mode\)')
          .allMatches(content)
          .length;
      expect(labelCount, 1, reason: 'INV1: labelForThemeMode 只能有一份实现');
    });

    test('REF-10-S6 否定 REF-10-INV3: settings_provider.dart 映射函数仍在', () {
      final content = File(
              '${Directory.current.path}/lib/features/settings/settings_provider.dart')
          .readAsStringSync();

      expect(content, contains('ThemeMode getThemeMode'),
          reason:
              'INV3: settings_provider 顶层 getThemeMode（String→ThemeMode 映射）必须保留');
      expect(content, contains('void setThemeMode'),
          reason: 'INV3: settings_provider setThemeMode 必须保留');
      expect(content, contains('String labelForThemeMode'),
          reason: 'INV3: settings_provider labelForThemeMode 必须保留');
    });

    test('REF-10-S5: settings_test REF-01-S1 组已迁移为实例方法调用', () {
      final content = File(
              '${Directory.current.path}/test/features/settings/settings_test.dart')
          .readAsStringSync();

      expect(
          content,
          contains(
              'const settings_service = settings_domain.SettingsService();'),
          reason: 'REF-01-S1 组必须先实例化 SettingsService');
      expect(content, isNot(contains('settings_domain.getThemeMode(')),
          reason: '不得再直接调用顶层 getThemeMode');
      expect(content, isNot(contains('settings_domain.setThemeMode(')),
          reason: '不得再直接调用顶层 setThemeMode');
      expect(content, isNot(contains('settings_domain.labelForThemeMode(')),
          reason: '不得再直接调用顶层 labelForThemeMode');
      expect(content, contains('settings_service.getThemeMode('),
          reason: 'REF-01-S1 组应经实例方法调用 getThemeMode');
      expect(content, contains('settings_service.labelForThemeMode('),
          reason: 'REF-01-S1 组应经实例方法调用 labelForThemeMode');
    });
  });
}
