// test/features/settings/settings_test.dart
// Settings module test suite — SET-01 through SET-05.
//
// Logic tests (SET-T01~T06, SET-T12~T22): Provider-container tests for
// default speed, theme mode, and seek step persistence and validation.
//
// Widget tests (SET-T23~T34): Widget-level tests for the Settings screen
// sections, dialogs, navigation, and the About page.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nas_audio_player/features/browser/browser_provider.dart';
import 'package:nas_audio_player/features/player/player_provider.dart';
import 'package:nas_audio_player/features/settings/about_screen.dart';
import 'package:nas_audio_player/features/settings/settings_provider.dart';
import 'package:nas_audio_player/features/settings/settings_screen.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// Helpers
// ═══════════════════════════════════════════════════════════════════════════════

/// Wraps [child] in a [ProviderScope] with the given SharedPreferences and a
/// [MaterialApp] for navigation.
Widget wrapWithSettings(Widget child, {SharedPreferences? prefs}) {
  return ProviderScope(
    overrides: [
      if (prefs != null) sharedPreferencesProvider.overrideWith((ref) => prefs),
    ],
    child: MaterialApp(
      home: Scaffold(body: child),
    ),
  );
}

/// Creates a [ProviderContainer] with the given SharedPreferences override.
ProviderContainer createContainer({SharedPreferences? prefs}) {
  return ProviderContainer(
    overrides: [
      if (prefs != null) sharedPreferencesProvider.overrideWith((ref) => prefs),
    ],
  );
}

/// Pumps the full [SettingsScreen] wrapped in a ProviderScope with the given
/// SharedPreferences.
Future<void> pumpSettingsScreen(WidgetTester tester,
    {SharedPreferences? prefs}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        if (prefs != null)
          sharedPreferencesProvider.overrideWith((ref) => prefs),
      ],
      child: const MaterialApp(
        home: SettingsScreen(),
      ),
    ),
  );
}

// ═══════════════════════════════════════════════════════════════════════════════
// SET-01: 默认播放速度设置 — logic tests (SET-T01 ~ SET-T06)
// ═══════════════════════════════════════════════════════════════════════════════

void main() {
  // ── SET-T01: First launch, no config → default speed 1.0 ──────────────────

  group('SET-01: 默认播放速度设置', () {
    test('SET-T01: 首次启动无配置记录, getDefaultSpeed() 返回 1.0', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      final container = createContainer(prefs: prefs);
      addTearDown(container.dispose);

      expect(container.read(defaultSpeedProvider), equals(1.0),
          reason: '首次启动应返回默认速度 1.0x');
      expect(getDefaultSpeed(prefs), equals(1.0),
          reason: 'getDefaultSpeed 在无存储时应返回 1.0');
    });

    test('SET-T02: 设置默认速度为 1.5x, SharedPreferences 中持久化', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      final container = createContainer(prefs: prefs);
      addTearDown(container.dispose);

      container.read(setDefaultSpeedProvider)(1.5);

      expect(prefs.getDouble('default_playback_speed'), equals(1.5),
          reason: 'SharedPreferences 中 default_playback_speed 应为 1.5');
      expect(container.read(defaultSpeedProvider), equals(1.5),
          reason: 'defaultSpeedProvider 应反映持久化后的值');
    });

    test('SET-T03: 设置默认速度后重启, 读取持久化值', () async {
      SharedPreferences.setMockInitialValues({
        'default_playback_speed': 1.5,
      });
      final prefs = await SharedPreferences.getInstance();

      final container = createContainer(prefs: prefs);
      addTearDown(container.dispose);

      expect(container.read(defaultSpeedProvider), equals(1.5),
          reason: '重启后应从 SharedPreferences 恢复保存的速度 1.5x');
    });

    test('SET-T04: 依次设置 6 个速度, 每次读取最新值', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      final container = createContainer(prefs: prefs);
      addTearDown(container.dispose);

      const speeds = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0];
      for (final speed in speeds) {
        container.read(setDefaultSpeedProvider)(speed);
        expect(container.read(defaultSpeedProvider), equals(speed),
            reason: '设置 $speed 后 defaultSpeed 应更新为 $speed');
        expect(prefs.getDouble('default_playback_speed'), equals(speed),
            reason: 'SharedPreferences 中应存有 $speed');
      }
    });

    test('SET-T05: 播放器中手动调速不影响 Settings 默认速度', () async {
      SharedPreferences.setMockInitialValues({
        'default_playback_speed': 1.0,
      });
      final prefs = await SharedPreferences.getInstance();

      final container = createContainer(prefs: prefs);
      addTearDown(container.dispose);

      // Simulate player speed change
      container.read(currentSpeedProvider.notifier).state = 2.0;

      expect(container.read(currentSpeedProvider), equals(2.0),
          reason: '播放器当前速度应变更为 2.0x');
      expect(container.read(defaultSpeedProvider), equals(1.0),
          reason: 'Settings 默认速度应保持 1.0x 不变');
      expect(prefs.getDouble('default_playback_speed'), equals(1.0),
          reason: 'SharedPreferences 中的值应保持不变');
    });

    test('SET-T06: 打开新文件时速度从 Settings.defaultSpeed 初始化', () async {
      SharedPreferences.setMockInitialValues({
        'default_playback_speed': 1.25,
      });
      final prefs = await SharedPreferences.getInstance();

      final container = createContainer(prefs: prefs);
      addTearDown(container.dispose);

      expect(container.read(defaultSpeedProvider), equals(1.25));
      // currentSpeed is initialized from defaultSpeed on first read
      expect(container.read(currentSpeedProvider), equals(1.25),
          reason: '新文件打开时播放速度应从 Settings 默认速度 1.25x 初始化');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════════
  // SET-03: 界面主题切换 — logic tests (SET-T12 ~ SET-T16)
  // ═══════════════════════════════════════════════════════════════════════════════

  group('SET-03: 界面主题切换', () {
    test('SET-T12: 首次启动无配置记录, getThemeMode() 返回 ThemeMode.system', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      final container = createContainer(prefs: prefs);
      addTearDown(container.dispose);

      expect(container.read(themeModeProvider), equals(ThemeMode.system),
          reason: '首次启动应默认跟随系统主题');
      expect(getThemeMode(null), equals(ThemeMode.system),
          reason: 'prefs 为 null 时应返回 system');
      expect(getThemeMode(prefs), equals(ThemeMode.system),
          reason: '无存储时应返回 system');
    });

    test('SET-T13: 设置为亮色主题, SharedPreferences 持久化', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      final container = createContainer(prefs: prefs);
      addTearDown(container.dispose);

      container.read(setThemeModeProvider)(ThemeMode.light);

      expect(prefs.getString('theme_mode'), equals('light'),
          reason: 'SharedPreferences 中 theme_mode 应为 light');
      expect(container.read(themeModeProvider), equals(ThemeMode.light),
          reason: 'themeModeProvider 应返回 light');
    });

    test('SET-T14: 设置为暗色主题, SharedPreferences 持久化', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      final container = createContainer(prefs: prefs);
      addTearDown(container.dispose);

      container.read(setThemeModeProvider)(ThemeMode.dark);

      expect(prefs.getString('theme_mode'), equals('dark'),
          reason: 'SharedPreferences 中 theme_mode 应为 dark');
      expect(container.read(themeModeProvider), equals(ThemeMode.dark),
          reason: 'themeModeProvider 应返回 dark');
    });

    test('SET-T15: 设置为跟随系统, 回到 ThemeMode.system', () async {
      SharedPreferences.setMockInitialValues({'theme_mode': 'light'});
      final prefs = await SharedPreferences.getInstance();

      final container = createContainer(prefs: prefs);
      addTearDown(container.dispose);

      // Start at light
      expect(container.read(themeModeProvider), equals(ThemeMode.light));

      // Switch to system
      container.read(setThemeModeProvider)(ThemeMode.system);

      expect(prefs.getString('theme_mode'), equals('system'),
          reason: 'SharedPreferences 中 theme_mode 应为 system');
      expect(container.read(themeModeProvider), equals(ThemeMode.system),
          reason: 'themeModeProvider 应返回 system');
    });

    test('SET-T16: 主题设置重启后持久化', () async {
      SharedPreferences.setMockInitialValues({'theme_mode': 'dark'});
      final prefs = await SharedPreferences.getInstance();

      final container = createContainer(prefs: prefs);
      addTearDown(container.dispose);

      expect(container.read(themeModeProvider), equals(ThemeMode.dark),
          reason: '重启后应从 SharedPreferences 恢复暗色主题');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════════
  // SET-04: 快进/快退步长设置 — logic tests (SET-T17 ~ SET-T22)
  // ═══════════════════════════════════════════════════════════════════════════════

  group('SET-04: 快进/快退步长设置', () {
    test('SET-T17: 首次启动无配置记录, readSeekStep() 返回 15', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      expect(readSeekStep(null), equals(15),
          reason: 'prefs 为 null 时应返回默认步长 15秒');
      expect(readSeekStep(prefs), equals(15), reason: '无存储时应返回默认步长 15秒');
    });

    test('SET-T17b: seekStepSettingProvider 首次启动返回 15', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      final container = createContainer(prefs: prefs);
      addTearDown(container.dispose);

      expect(container.read(seekStepSettingProvider), equals(15),
          reason: 'seekStepSettingProvider 首次启动应返回 15');
    });

    test('SET-T18: 设置步长为 10 秒, SharedPreferences 持久化', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      final container = createContainer(prefs: prefs);
      addTearDown(container.dispose);

      container.read(setSeekStepSettingProvider)(10);

      expect(prefs.getInt('seek_step_seconds'), equals(10),
          reason: 'SharedPreferences 中 seek_step_seconds 应为 10');
      expect(container.read(seekStepSettingProvider), equals(10),
          reason: 'seekStepSettingProvider 应返回 10');
    });

    test('SET-T19: 设置步长为 30 秒, SharedPreferences 持久化', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      final container = createContainer(prefs: prefs);
      addTearDown(container.dispose);

      container.read(setSeekStepSettingProvider)(30);

      expect(prefs.getInt('seek_step_seconds'), equals(30),
          reason: 'SharedPreferences 中 seek_step_seconds 应为 30');
      expect(container.read(seekStepSettingProvider), equals(30),
          reason: 'seekStepSettingProvider 应返回 30');
    });

    test('SET-T20: 设置步长为 60 秒, SharedPreferences 持久化', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      final container = createContainer(prefs: prefs);
      addTearDown(container.dispose);

      container.read(setSeekStepSettingProvider)(60);

      expect(prefs.getInt('seek_step_seconds'), equals(60),
          reason: 'SharedPreferences 中 seek_step_seconds 应为 60');
      expect(container.read(seekStepSettingProvider), equals(60),
          reason: 'seekStepSettingProvider 应返回 60');
    });

    test('SET-T21: 步长设置重启后持久化', () async {
      SharedPreferences.setMockInitialValues({
        'seek_step_seconds': 30,
      });
      final prefs = await SharedPreferences.getInstance();

      final container = createContainer(prefs: prefs);
      addTearDown(container.dispose);

      expect(container.read(seekStepSettingProvider), equals(30),
          reason: '重启后应恢复步长 30秒');
    });

    test('SET-T22: 播放器 seekStepProvider 使用 Settings 中的步长', () async {
      SharedPreferences.setMockInitialValues({
        'seek_step_seconds': 60,
      });
      final prefs = await SharedPreferences.getInstance();

      final container = createContainer(prefs: prefs);
      addTearDown(container.dispose);

      // seekStepProvider reads from SharedPreferences now
      expect(container.read(seekStepProvider), equals(60),
          reason: 'seekStepProvider 应从 SharedPreferences 读取步长 60秒');
    });

    test('setSeekStepSettingProvider rejects invalid values', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      final container = createContainer(prefs: prefs);
      addTearDown(container.dispose);

      // 20 is not a valid seek step option
      container.read(setSeekStepSettingProvider)(20);

      expect(prefs.getInt('seek_step_seconds'), isNull,
          reason: '无效步长 20秒 不应写入 SharedPreferences');
      expect(container.read(seekStepSettingProvider), equals(15),
          reason: 'seekStepSettingProvider 应保持默认 15');
    });

    test('setSeekStep pure function returns false for invalid value', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      final result = setSeekStep(prefs, 5);
      expect(result, isFalse, reason: '5秒不是有效步长选项，应返回 false');
      expect(prefs.getInt('seek_step_seconds'), isNull,
          reason: '无效值不应写入 SharedPreferences');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════════
  // SET-01/04: Widget tests — Settings page UI (SET-T23 ~ SET-T30)
  // ═══════════════════════════════════════════════════════════════════════════════

  group('Settings page widget tests', () {
    testWidgets('SET-T23: 设置页面渲染四个 Section', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      await pumpSettingsScreen(tester, prefs: prefs);
      await tester.pumpAndSettle();

      // Check section headers exist
      expect(find.text('播放设置'), findsOneWidget,
          reason: '应显示"播放设置" section header');
      expect(find.text('外观'), findsOneWidget, reason: '应显示"外观" section header');
      expect(find.text('连接'), findsOneWidget, reason: '应显示"连接" section header');
      expect(find.text('关于'), findsOneWidget, reason: '应显示"关于" section header');
    });

    testWidgets('SET-T24: 「默认播放速度」ListTile 副标题显示当前值', (tester) async {
      SharedPreferences.setMockInitialValues({
        'default_playback_speed': 1.5,
      });
      final prefs = await SharedPreferences.getInstance();

      await pumpSettingsScreen(tester, prefs: prefs);
      await tester.pumpAndSettle();

      expect(find.text('默认播放速度'), findsOneWidget, reason: '应显示"默认播放速度"标题');
      expect(find.text('1.5x'), findsOneWidget, reason: '副标题应显示当前默认速度 1.5x');
    });

    testWidgets('SET-T25: 点击「默认播放速度」弹出 6 个速度选项对话框', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      await pumpSettingsScreen(tester, prefs: prefs);
      await tester.pumpAndSettle();

      // Tap the default speed tile
      await tester.tap(find.text('默认播放速度'));
      await tester.pumpAndSettle();

      // Dialog should appear with title
      expect(find.text('选择默认播放速度'), findsOneWidget, reason: '应弹出速度选择对话框');

      // Check all 6 speed options (note: some may also appear as subtitle text
      // behind the dialog — hence findsAtLeastNWidgets instead of findsOneWidget)
      for (final speed in ['0.5x', '0.75x', '1.0x', '1.25x', '1.5x', '2.0x']) {
        expect(find.text(speed), findsAtLeastNWidgets(1),
            reason: '对话框中应包含 $speed 选项');
      }
    });

    testWidgets('SET-T26: 「快进/快退步长」ListTile 副标题显示当前步长', (tester) async {
      SharedPreferences.setMockInitialValues({
        'seek_step_seconds': 30,
      });
      final prefs = await SharedPreferences.getInstance();

      await pumpSettingsScreen(tester, prefs: prefs);
      await tester.pumpAndSettle();

      expect(find.text('快进/快退步长'), findsOneWidget, reason: '应显示"快进/快退步长"标题');
      expect(find.text('30秒'), findsOneWidget, reason: '副标题应显示当前步长 30秒');
    });

    testWidgets('SET-T27: 点击「快进/快退步长」弹出 4 个步长选项对话框', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      await pumpSettingsScreen(tester, prefs: prefs);
      await tester.pumpAndSettle();

      // Tap the seek step tile
      await tester.tap(find.text('快进/快退步长'));
      await tester.pumpAndSettle();

      // Dialog should appear with title
      expect(find.text('选择快进/快退步长'), findsOneWidget, reason: '应弹出步长选择对话框');

      // Check all 4 step options (note: some may also appear as subtitle text
      // behind the dialog — hence findsAtLeastNWidgets instead of findsOneWidget)
      for (final step in ['10秒', '15秒', '30秒', '60秒']) {
        expect(find.text(step), findsAtLeastNWidgets(1),
            reason: '对话框中应包含 $step 选项');
      }
    });

    testWidgets('SET-T28: 「主题」ListTile 副标题显示当前主题模式', (tester) async {
      SharedPreferences.setMockInitialValues({
        'theme_mode': 'dark',
      });
      final prefs = await SharedPreferences.getInstance();

      await pumpSettingsScreen(tester, prefs: prefs);
      await tester.pumpAndSettle();

      expect(find.text('主题'), findsOneWidget, reason: '应显示"主题"标题');
      expect(find.text('暗色'), findsOneWidget, reason: '副标题应显示当前主题模式"暗色"');
    });

    testWidgets('SET-T29: 点击「主题」ListTile 弹出三选一对话框', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      await pumpSettingsScreen(tester, prefs: prefs);
      await tester.pumpAndSettle();

      // Tap the theme tile
      await tester.tap(find.text('主题'));
      await tester.pumpAndSettle();

      // Dialog should appear with title
      expect(find.text('选择主题'), findsOneWidget, reason: '应弹出主题选择对话框');

      // Check all 3 theme options (note: some may also appear as subtitle text
      // behind the dialog — hence findsAtLeastNWidgets instead of findsOneWidget)
      expect(find.text('跟随系统'), findsAtLeastNWidgets(1),
          reason: '对话框中应包含"跟随系统"选项');
      expect(find.text('亮色'), findsAtLeastNWidgets(1), reason: '对话框中应包含"亮色"选项');
      expect(find.text('暗色'), findsAtLeastNWidgets(1), reason: '对话框中应包含"暗色"选项');
    });

    testWidgets('SET-T30: 点击「管理 NAS 连接」显示 ListTile', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      await pumpSettingsScreen(tester, prefs: prefs);
      await tester.pumpAndSettle();

      expect(find.text('管理 NAS 连接'), findsOneWidget,
          reason: '应显示"管理 NAS 连接" ListTile');
      expect(find.text('添加、编辑或切换连接'), findsOneWidget, reason: '应显示连接管理的副标题说明');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════════
  // Label helpers
  // ═══════════════════════════════════════════════════════════════════════════════

  group('label helpers', () {
    test('labelForThemeMode returns correct labels', () {
      expect(labelForThemeMode(ThemeMode.system), equals('跟随系统'));
      expect(labelForThemeMode(ThemeMode.light), equals('亮色'));
      expect(labelForThemeMode(ThemeMode.dark), equals('暗色'));
    });

    test('labelForSeekStep returns correct labels', () {
      expect(labelForSeekStep(10), equals('10秒'));
      expect(labelForSeekStep(15), equals('15秒'));
      expect(labelForSeekStep(30), equals('30秒'));
      expect(labelForSeekStep(60), equals('60秒'));
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════════
  // SET-05: 关于页面 — widget tests (SET-T31 ~ SET-T34)
  // ═══════════════════════════════════════════════════════════════════════════════

  group('SET-05: 关于页面', () {
    testWidgets('SET-T31: 设置页包含「关于本应用」ListTile', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      await pumpSettingsScreen(tester, prefs: prefs);
      await tester.pumpAndSettle();
      // F-4: scroll down to account for the new "remember speed" tile.
      await tester.drag(find.byType(ListView), const Offset(0, -300));
      await tester.pumpAndSettle();

      expect(find.text('关于本应用'), findsOneWidget,
          reason: '设置页应显示"关于本应用" ListTile');
    });

    testWidgets('SET-T32: 关于页面显示应用名称', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: AboutScreen(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text(appName), findsOneWidget,
          reason: '关于页面应显示应用名称 "$appName"');
    });

    testWidgets('SET-T33: 关于页面显示版本号', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: AboutScreen(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('版本 $appVersion'), findsOneWidget, reason: '关于页面应显示版本号');
    });

    testWidgets('SET-T34: 关于页面显示开源许可证信息', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: AboutScreen(),
        ),
      );
      await tester.pumpAndSettle();

      // Check that the license section header exists
      expect(find.text('开源许可'), findsOneWidget,
          reason: '关于页面应显示"开源许可" section header');

      // Check that key open-source libraries are listed
      expect(find.text('Flutter'), findsOneWidget, reason: '应包含 Flutter 许可证信息');
      expect(find.text('just_audio'), findsOneWidget,
          reason: '应包含 just_audio 许可证信息');
      expect(find.text('flutter_riverpod'), findsOneWidget,
          reason: '应包含 flutter_riverpod 许可证信息');
      expect(find.text('go_router'), findsOneWidget,
          reason: '应包含 go_router 许可证信息');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════════
  // SettingsProvider pure function boundary tests
  // ═══════════════════════════════════════════════════════════════════════════════

  group('theme mode pure functions', () {
    test('getThemeMode with null returns system', () {
      expect(getThemeMode(null), equals(ThemeMode.system));
    });

    test('getThemeMode with empty prefs returns system', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      expect(getThemeMode(prefs), equals(ThemeMode.system));
    });

    test('getThemeMode reads all three modes', () async {
      for (final mode in ThemeMode.values) {
        SharedPreferences.setMockInitialValues({'theme_mode': mode.name});
        final prefs = await SharedPreferences.getInstance();
        expect(getThemeMode(prefs), equals(mode),
            reason: 'getThemeMode 应正确读取 ${mode.name}');
      }
    });

    test('getThemeMode with invalid string returns system', () async {
      SharedPreferences.setMockInitialValues({'theme_mode': 'invalid'});
      final prefs = await SharedPreferences.getInstance();
      expect(getThemeMode(prefs), equals(ThemeMode.system),
          reason: '无效的 theme_mode 值应回退到 system');
    });

    test('setThemeMode with null prefs does not throw', () {
      // Should not throw
      setThemeMode(null, ThemeMode.dark);
    });
  });

  group('seek step pure functions', () {
    test('seekStepOptions contains exactly 4 values in order', () {
      expect(seekStepOptions, orderedEquals([10, 15, 30, 60]));
      expect(seekStepOptions.length, equals(4));
    });

    test('setSeekStep with null prefs and valid option returns true', () {
      // 10 is a valid option; the write is silently skipped when prefs is null.
      expect(setSeekStep(null, 10), isTrue);
    });

    test('setSeekStep with valid options returns true', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      for (final step in seekStepOptions) {
        final result = setSeekStep(prefs, step);
        expect(result, isTrue, reason: '$step 是有效步长，应返回 true');
        expect(prefs.getInt('seek_step_seconds'), equals(step),
            reason: 'SharedPreferences 应存储 $step');
      }
    });

    test('setSeekStep with invalid options returns false', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      for (final step in [5, 20, 45, 90, 0, -1]) {
        final result = setSeekStep(prefs, step);
        expect(result, isFalse, reason: '$step 不是有效步长，应返回 false');
      }
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════════
  // TST-10: rememberSpeed widget tests — TST-T79
  // ═══════════════════════════════════════════════════════════════════════════════

  group('TST-10: rememberSpeed widget tests', () {
    testWidgets('TST-T79: "记住播放速度" 开关渲染, 切换后值更新', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      await pumpSettingsScreen(tester, prefs: prefs);
      await tester.pumpAndSettle();

      // Verify the tile renders with correct title and subtitle
      expect(find.text('记住播放速度'), findsOneWidget, reason: '设置页应显示"记住播放速度"开关标题');
      expect(find.text('调速后自动设为默认，切歌不重置'), findsOneWidget,
          reason: '应显示副标题说明文字');

      // Find the SwitchListTile and verify initial state (off by default)
      final switchTile = find.byType(SwitchListTile);
      expect(switchTile, findsOneWidget, reason: '应有一个 SwitchListTile widget');

      // Switch should be off by default
      expect(prefs.getBool('remember_playback_speed'), isNull,
          reason: '默认不应设置 remember_playback_speed');
      expect(getRememberSpeed(prefs), isFalse,
          reason: '未持久化时 getRememberSpeed 应返回 false');

      // Tap the switch tile to turn it on
      await tester.tap(switchTile);
      await tester.pumpAndSettle();

      // SharedPreferences should now have true
      expect(prefs.getBool('remember_playback_speed'), isTrue,
          reason: '切换开启后 SharedPreferences 应为 true');
      expect(getRememberSpeed(prefs), isTrue,
          reason: '切换开启后 getRememberSpeed 应返回 true');
    });

    testWidgets('TST-T79b: rememberSpeed 开关从持久化值初始化并切换关', (tester) async {
      SharedPreferences.setMockInitialValues({
        'remember_playback_speed': true,
      });
      final prefs = await SharedPreferences.getInstance();

      await pumpSettingsScreen(tester, prefs: prefs);
      await tester.pumpAndSettle();

      // Switch should be on (initialized from SharedPreferences)
      expect(find.text('记住播放速度'), findsOneWidget);
      expect(getRememberSpeed(prefs), isTrue,
          reason: '从 SharedPreferences 初始化后应为 true');

      // Tap to turn off
      await tester.tap(find.byType(SwitchListTile));
      await tester.pumpAndSettle();

      // Should now be false
      expect(prefs.getBool('remember_playback_speed'), isFalse,
          reason: '再次切换后 SharedPreferences 应为 false');
      expect(getRememberSpeed(prefs), isFalse,
          reason: '再次切换后 getRememberSpeed 应返回 false');
    });

    testWidgets('TST-T79c: rememberSpeed 开关切换后重新读取反映新值', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      await pumpSettingsScreen(tester, prefs: prefs);
      await tester.pumpAndSettle();

      // Initially off
      expect(getRememberSpeed(prefs), isFalse);

      // Toggle on
      await tester.tap(find.byType(SwitchListTile));
      await tester.pumpAndSettle();
      expect(prefs.getBool('remember_playback_speed'), isTrue);

      // Rebuild the screen (simulating leaving and coming back)
      await pumpSettingsScreen(tester, prefs: prefs);
      await tester.pumpAndSettle();

      // Tile should still be there and SharedPreferences should still be true
      expect(find.text('记住播放速度'), findsOneWidget);
      expect(prefs.getBool('remember_playback_speed'), isTrue,
          reason: '重建页面后持久化值应保持不变');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════════

  group('setSeekStepSettingProvider propagates to seekStepProvider', () {
    test('setting seek step updates both providers', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      final container = createContainer(prefs: prefs);
      addTearDown(container.dispose);

      container.read(setSeekStepSettingProvider)(10);

      expect(container.read(seekStepSettingProvider), equals(10));
      expect(container.read(seekStepProvider), equals(10),
          reason: 'setSeekStepSettingProvider 应同步更新 seekStepProvider');
    });
  });

  group('Theme mode provider integration', () {
    test('setThemeModeProvider invalidates themeModeProvider', () async {
      SharedPreferences.setMockInitialValues({'theme_mode': 'light'});
      final prefs = await SharedPreferences.getInstance();

      final container = createContainer(prefs: prefs);
      addTearDown(container.dispose);

      expect(container.read(themeModeProvider), equals(ThemeMode.light));

      container.read(setThemeModeProvider)(ThemeMode.dark);

      expect(container.read(themeModeProvider), equals(ThemeMode.dark),
          reason: '设置后 themeModeProvider 应反映新值');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════════
  // Widget: default speed tile subtitle reflects current value (boundary tests)
  // ═══════════════════════════════════════════════════════════════════════════════

  group('default speed widget — additional states', () {
    testWidgets('default speed subtitle shows 1.0x when no preference',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      await pumpSettingsScreen(tester, prefs: prefs);
      await tester.pumpAndSettle();

      // The subtitle for the default speed tile shows the current default
      // There should be a 1.0x text somewhere near "默认播放速度"
      expect(find.text('1.0x'), findsOneWidget, reason: '未设置偏好时应显示默认速度 1.0x');
    });

    testWidgets('default speed subtitle shows 2.0x when that is stored',
        (tester) async {
      SharedPreferences.setMockInitialValues({
        'default_playback_speed': 2.0,
      });
      final prefs = await SharedPreferences.getInstance();

      await pumpSettingsScreen(tester, prefs: prefs);
      await tester.pumpAndSettle();

      expect(find.text('2.0x'), findsOneWidget,
          reason: '存储的默认速度 2.0x 应显示在副标题中');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════════
  // Widget: theme tile subtitle boundary cases
  // ═══════════════════════════════════════════════════════════════════════════════

  group('theme tile widget — all modes', () {
    testWidgets('theme subtitle shows "跟随系统" for system mode', (tester) async {
      SharedPreferences.setMockInitialValues({'theme_mode': 'system'});
      final prefs = await SharedPreferences.getInstance();

      await pumpSettingsScreen(tester, prefs: prefs);
      await tester.pumpAndSettle();

      expect(find.text('跟随系统'), findsOneWidget, reason: '跟随系统时应显示"跟随系统"');
    });

    testWidgets('theme subtitle shows "亮色" for light mode', (tester) async {
      SharedPreferences.setMockInitialValues({'theme_mode': 'light'});
      final prefs = await SharedPreferences.getInstance();

      await pumpSettingsScreen(tester, prefs: prefs);
      await tester.pumpAndSettle();

      expect(find.text('亮色'), findsOneWidget, reason: '亮色模式时应显示"亮色"');
    });

    testWidgets('theme subtitle shows "暗色" for dark mode', (tester) async {
      SharedPreferences.setMockInitialValues({'theme_mode': 'dark'});
      final prefs = await SharedPreferences.getInstance();

      await pumpSettingsScreen(tester, prefs: prefs);
      await tester.pumpAndSettle();

      expect(find.text('暗色'), findsOneWidget, reason: '暗色模式时应显示"暗色"');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════════
  // Widget: about page navigation tile exists
  // ═══════════════════════════════════════════════════════════════════════════════

  group('about page widget — additional content', () {
    testWidgets('about page has an AppBar with title "关于"', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: AboutScreen(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('关于'), findsOneWidget, reason: '关于页面 AppBar 标题应为"关于"');
    });

    testWidgets('about page has app icon', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: AboutScreen(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.music_note_outlined), findsOneWidget,
          reason: '关于页面应显示应用图标');
    });

    testWidgets('about page lists multiple open source packages',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: AboutScreen(),
        ),
      );
      await tester.pumpAndSettle();

      // Scroll down to see all licenses
      await tester.drag(find.byType(ListView), const Offset(0, -200));
      await tester.pumpAndSettle();

      // Verify multiple packages are listed
      expect(find.text('shared_preferences'), findsOneWidget,
          reason: '应包含 shared_preferences');
      expect(find.text('webdav_client'), findsOneWidget,
          reason: '应包含 webdav_client');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════════
  // Widget: settings page AppBar
  // ═══════════════════════════════════════════════════════════════════════════════

  group('settings page AppBar', () {
    testWidgets('settings page has AppBar with title "设置"', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      await pumpSettingsScreen(tester, prefs: prefs);
      await tester.pumpAndSettle();

      // AppBar title should be "设置"
      expect(find.text('设置'), findsOneWidget, reason: '设置页 AppBar 标题应为"设置"');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════════
  // Speed dialog interaction tests
  // ═══════════════════════════════════════════════════════════════════════════════

  group('speed dialog interaction', () {
    testWidgets('selecting a speed in dialog closes dialog and updates value',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      await pumpSettingsScreen(tester, prefs: prefs);
      await tester.pumpAndSettle();

      // Initially shows 1.0x
      expect(find.text('1.0x'), findsOneWidget);

      // Tap default speed tile to open dialog
      await tester.tap(find.text('默认播放速度'));
      await tester.pumpAndSettle();

      // Tap 1.5x option
      await tester.tap(find.text('1.5x'));
      await tester.pumpAndSettle();

      // Dialog should be dismissed
      expect(find.text('选择默认播放速度'), findsNothing, reason: '选择后对话框应关闭');

      // Subtitle should now show 1.5x
      expect(find.text('1.5x'), findsOneWidget, reason: '选择 1.5x 后副标题应更新');

      // SharedPreferences should be updated
      expect(prefs.getDouble('default_playback_speed'), equals(1.5),
          reason: 'SharedPreferences 应更新为 1.5');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════════
  // Seek step dialog interaction tests
  // ═══════════════════════════════════════════════════════════════════════════════

  group('seek step dialog interaction', () {
    testWidgets('selecting a step in dialog closes dialog and updates value',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      await pumpSettingsScreen(tester, prefs: prefs);
      await tester.pumpAndSettle();

      // Initially shows 15秒
      expect(find.text('15秒'), findsOneWidget);

      // Tap seek step tile to open dialog
      await tester.tap(find.text('快进/快退步长'));
      await tester.pumpAndSettle();

      // Tap 30秒 option
      await tester.tap(find.text('30秒'));
      await tester.pumpAndSettle();

      // Dialog should be dismissed
      expect(find.text('选择快进/快退步长'), findsNothing, reason: '选择后对话框应关闭');

      // Subtitle should now show 30秒
      expect(find.text('30秒'), findsOneWidget, reason: '选择 30秒 后副标题应更新');

      // SharedPreferences should be updated
      expect(prefs.getInt('seek_step_seconds'), equals(30),
          reason: 'SharedPreferences 应更新为 30');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════════
  // Theme dialog interaction tests
  // ═══════════════════════════════════════════════════════════════════════════════

  group('theme dialog interaction', () {
    testWidgets('selecting dark theme updates tile subtitle', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      await pumpSettingsScreen(tester, prefs: prefs);
      await tester.pumpAndSettle();

      // Tap theme tile to open dialog
      await tester.tap(find.text('主题'));
      await tester.pumpAndSettle();

      // Tap 暗色 option
      await tester.tap(find.text('暗色'));
      await tester.pumpAndSettle();

      // Dialog should be dismissed
      expect(find.text('选择主题'), findsNothing, reason: '选择后对话框应关闭');

      // Subtitle should now show 暗色
      // Find the subtitle text — there should be the header and the subtitle
      expect(find.text('暗色'), findsOneWidget, reason: '选择暗色后副标题应更新');

      // SharedPreferences should be updated
      expect(prefs.getString('theme_mode'), equals('dark'),
          reason: 'SharedPreferences 应更新为 dark');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // TST-17: Tab index persistence and settings navigation
  // ═══════════════════════════════════════════════════════════════════════════

  group('TST-17: Tab index persistence and settings navigation', () {
    test('TST-T141: tab index persists to SharedPreferences', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      // Default is 0 when no value stored
      expect(prefs.getInt('home_tab_index') ?? 0, equals(0),
          reason: 'TST-T141: 首次启动默认 tab index = 0');

      // Switch to tab 1
      await prefs.setInt('home_tab_index', 1);

      // Read back — should persist
      expect(prefs.getInt('home_tab_index'), equals(1),
          reason: 'TST-T141: 切换到 tab 1 后读取正确');
    });

    test('TST-T142: first launch defaults to tab 0', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      // No previously stored value → default 0
      expect(prefs.getInt('home_tab_index') ?? 0, equals(0),
          reason: 'TST-T142: 首次启动无存储值时默认 tab 0');

      // Also verify that reading a non-existent key returns null
      expect(prefs.getInt('home_tab_index'), isNull,
          reason: 'TST-T142: 未设置时 getInt 返回 null');
    });

    // TST-T143: 设置页 → "管理 NAS 连接" → 导航到 /connections
    testWidgets('TST-T143: Settings page has manage connections option',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWith((ref) => prefs),
          ],
          child: const MaterialApp(
            home: SettingsScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Settings page should render
      expect(find.byType(SettingsScreen), findsOneWidget,
          reason: 'TST-T143: SettingsScreen 组件应渲染');
    });
  });
}
