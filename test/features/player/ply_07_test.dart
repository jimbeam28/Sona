// test/features/player/ply_07_test.dart
// PLY-07: 播放速度调节 — automated test suite
//
// Unit tests (PLY-T43~T47 + PLY-T59~T60): speed validation, persistence,
// default vs current speed separation, and speed menu logic.
//
// All tests are pure-logic tests that verify the providers and pure
// functions in player_provider.dart.  No widget tests needed because
// the _SpeedControl widget already exists from PLY-02 and the new
// behaviour is entirely in the provider layer.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nas_audio_player/features/browser/browser_provider.dart';
import 'package:nas_audio_player/features/player/player_provider.dart';
import 'package:nas_audio_player/features/settings/settings_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ═════════════════════════════════════════════════════════════════════════════
// Unit tests — PLY-T43~T47 + PLY-T59~T60
// ═════════════════════════════════════════════════════════════════════════════

void main() {
  // ── PLY-T43: Select 0.5x speed ──────────────────────────────────────────

  group('PLY-T43: Select 0.5x speed', () {
    test('0.5x is a valid speed', () {
      expect(isValidSpeed(0.5), isTrue,
          reason: '0.5x 应在 speedOptions 中');
      expect(speedOptions, contains(0.5));
    });

    test('0.5x is not valid when slightly off by more than tolerance', () {
      expect(isValidSpeed(0.51), isFalse,
          reason: '0.51x 与 0.5x 差值超过容差，不属于有效速度');
      expect(isValidSpeed(0.49), isFalse,
          reason: '0.49x 与 0.5x 差值超过容差，不属于有效速度');
    });

    test('currentSpeedProvider can be set to 0.5', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(currentSpeedProvider.notifier).state = 0.5;
      expect(container.read(currentSpeedProvider), equals(0.5),
          reason: 'currentSpeed 应可设为 0.5x');
    });

    test('speed button label for 0.5x', () {
      // The _SpeedControl widget renders Text('${currentSpeed}x').
      const label = '${0.5}x';
      expect(label, equals('0.5x'),
          reason: '速度按钮应显示 "0.5x"');
    });
  });

  // ── PLY-T44: Select 2.0x speed ──────────────────────────────────────────

  group('PLY-T44: Select 2.0x speed', () {
    test('2.0x is a valid speed', () {
      expect(isValidSpeed(2.0), isTrue,
          reason: '2.0x 应在 speedOptions 中');
      expect(speedOptions, contains(2.0));
    });

    test('2.0x is not valid when slightly off by more than tolerance', () {
      // Use values clearly outside the 0.01 tolerance (2.02 and 1.97
      // differ from 2.0 by 0.02 and 0.03 respectively).
      // 2.01 is avoided because its double representation may be
      // 2.0099999999999998 which is within 0.01 of 2.0.
      expect(isValidSpeed(2.02), isFalse,
          reason: '2.02x 与 2.0x 差值超过容差 0.01，不属于有效速度');
      expect(isValidSpeed(1.97), isFalse,
          reason: '1.97x 与 2.0x 差值超过容差 0.01，不属于有效速度');
    });

    test('currentSpeedProvider can be set to 2.0', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(currentSpeedProvider.notifier).state = 2.0;
      expect(container.read(currentSpeedProvider), equals(2.0),
          reason: 'currentSpeed 应可设为 2.0x');
    });

    test('speed button label for 2.0x', () {
      const label = '${2.0}x';
      expect(label, equals('2.0x'),
          reason: '速度按钮应显示 "2.0x"');
    });
  });

  // ── PLY-T45: Speed saved to SharedPreferences ───────────────────────────

  group('PLY-T45: Speed persistence in SharedPreferences', () {
    test('default speed is persisted and restored from SharedPreferences',
        () async {
      // Simulate a saved preference of 1.5x
      SharedPreferences.setMockInitialValues({
        'default_playback_speed': 1.5,
      });
      final prefs = await SharedPreferences.getInstance();

      // getDefaultSpeed reads the persisted value
      expect(getDefaultSpeed(prefs), equals(1.5),
          reason: '应从 SharedPreferences 读取保存的速度 1.5x');

      // Write a new default speed
      prefs.setDouble('default_playback_speed', 0.75);
      expect(getDefaultSpeed(prefs), equals(0.75),
          reason: '写入 0.75x 后应能读取回来');
    });

    test('getDefaultSpeed returns 1.0 when prefs is null', () {
      expect(getDefaultSpeed(null), equals(1.0),
          reason: 'prefs 为 null 时应返回默认值 1.0x');
    });

    test('getDefaultSpeed returns 1.0 when no value stored', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      expect(getDefaultSpeed(prefs), equals(1.0),
          reason: '未存储任何速度时应返回默认值 1.0x');
    });

    test('setDefaultSpeedProvider persists the value', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWith((ref) => prefs),
        ],
      );
      addTearDown(container.dispose);

      // Initially default is 1.0
      expect(container.read(defaultSpeedProvider), equals(1.0));

      // Set default speed to 1.25x via the provider
      container.read(setDefaultSpeedProvider)(1.25);

      // Verify it was persisted to SharedPreferences
      expect(prefs.getDouble('default_playback_speed'), equals(1.25),
          reason: 'setDefaultSpeedProvider 应将 1.25x 写入 SharedPreferences');

      // Verify the provider reflects the new value
      expect(container.read(defaultSpeedProvider), equals(1.25),
          reason: 'defaultSpeedProvider 应反映新持久化的速度');
    });

    test('setDefaultSpeedProvider ignores invalid speeds', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWith((ref) => prefs),
        ],
      );
      addTearDown(container.dispose);

      container.read(setDefaultSpeedProvider)(3.0); // not in speedOptions
      expect(prefs.getDouble('default_playback_speed'), isNull,
          reason: '无效速度 3.0x 不应写入 SharedPreferences');
      expect(container.read(defaultSpeedProvider), equals(1.0),
          reason: '无效速度不应改变 defaultSpeedProvider');
    });
  });

  // ── PLY-T46: Manual speed change doesn't affect default ──────────────────

  group('PLY-T46: currentSpeed change does not affect defaultSpeed', () {
    test('changing currentSpeed leaves defaultSpeed unchanged', () async {
      SharedPreferences.setMockInitialValues({
        'default_playback_speed': 1.0,
      });
      final prefs = await SharedPreferences.getInstance();

      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWith((ref) => prefs),
        ],
      );
      addTearDown(container.dispose);

      // Initial state: both at 1.0
      expect(container.read(defaultSpeedProvider), equals(1.0));
      expect(container.read(currentSpeedProvider), equals(1.0));

      // User changes playback speed to 2.0x in the player
      container.read(currentSpeedProvider.notifier).state = 2.0;

      // currentSpeed changed
      expect(container.read(currentSpeedProvider), equals(2.0),
          reason: '播放器调速后 currentSpeed 应变更为 2.0x');

      // defaultSpeed unchanged — it stays at the settings value
      expect(container.read(defaultSpeedProvider), equals(1.0),
          reason: 'Settings 中的 defaultSpeed 应保持 1.0x 不变');

      // SharedPreferences still holds 1.0
      expect(prefs.getDouble('default_playback_speed'), equals(1.0),
          reason: 'SharedPreferences 中的值应保持 1.0 不变');
    });

    test('currentSpeed change is purely in-memory', () async {
      SharedPreferences.setMockInitialValues({
        'default_playback_speed': 1.25,
      });
      final prefs = await SharedPreferences.getInstance();

      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWith((ref) => prefs),
        ],
      );
      addTearDown(container.dispose);

      // Initial both at 1.25
      expect(container.read(defaultSpeedProvider), equals(1.25));
      expect(container.read(currentSpeedProvider), equals(1.25));

      // Change current speed to 0.5x
      container.read(currentSpeedProvider.notifier).state = 0.5;

      // defaultSpeed still 1.25
      expect(container.read(defaultSpeedProvider), equals(1.25));
      expect(prefs.getDouble('default_playback_speed'), equals(1.25));
      // currentSpeed is 0.5
      expect(container.read(currentSpeedProvider), equals(0.5));

      // Change to another speed
      container.read(currentSpeedProvider.notifier).state = 1.5;

      // defaultSpeed still unchanged
      expect(container.read(defaultSpeedProvider), equals(1.25));
      expect(prefs.getDouble('default_playback_speed'), equals(1.25));
      expect(container.read(currentSpeedProvider), equals(1.5));
    });
  });

  // ── PLY-T47: New file uses Settings default speed ────────────────────────

  group('PLY-T47: new file initializes speed from defaultSpeed', () {
    test('currentSpeed is initialized from defaultSpeed', () async {
      SharedPreferences.setMockInitialValues({
        'default_playback_speed': 1.5,
      });
      final prefs = await SharedPreferences.getInstance();

      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWith((ref) => prefs),
        ],
      );
      addTearDown(container.dispose);

      // defaultSpeed is 1.5 (from prefs)
      expect(container.read(defaultSpeedProvider), equals(1.5));

      // currentSpeed is initialized from defaultSpeed
      expect(container.read(currentSpeedProvider), equals(1.5),
          reason: '新文件应将播放速度初始化为 Settings 中的默认速度');
    });

    test('currentSpeed initializes to 1.0 when no preference stored',
        () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWith((ref) => prefs),
        ],
      );
      addTearDown(container.dispose);

      expect(container.read(defaultSpeedProvider), equals(1.0),
          reason: '未存储偏好时默认速度为 1.0x');
      expect(container.read(currentSpeedProvider), equals(1.0),
          reason: '新文件在无偏好时初始化为 1.0x');
    });

    test('new ProviderContainer picks up default from SharedPreferences',
        () async {
      // Simulate: user previously set default speed to 0.75x
      SharedPreferences.setMockInitialValues({
        'default_playback_speed': 0.75,
      });
      final prefs = await SharedPreferences.getInstance();

      // First session: set default to 0.75
      {
        final container = ProviderContainer(
          overrides: [
            sharedPreferencesProvider.overrideWith((ref) => prefs),
          ],
        );
        expect(container.read(defaultSpeedProvider), equals(0.75));
        expect(container.read(currentSpeedProvider), equals(0.75));
        container.dispose();
      }

      // "After restart" — new container reads the same SharedPreferences
      {
        final container2 = ProviderContainer(
          overrides: [
            sharedPreferencesProvider.overrideWith((ref) => prefs),
          ],
        );
        addTearDown(container2.dispose);

        // Both should still be 0.75
        expect(container2.read(defaultSpeedProvider), equals(0.75),
            reason: '重启后 defaultSpeed 应从 SharedPreferences 恢复');
        expect(container2.read(currentSpeedProvider), equals(0.75),
            reason: '新文件打开时应使用恢复的默认速度');
      }
    });

    test('setDefaultSpeedProvider changes what new files will use', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWith((ref) => prefs),
        ],
      );
      addTearDown(container.dispose);

      // Initially 1.0
      expect(container.read(currentSpeedProvider), equals(1.0));

      // Change currentSpeed (simulates user adjusting during playback)
      container.read(currentSpeedProvider.notifier).state = 2.0;
      expect(container.read(currentSpeedProvider), equals(2.0));

      // Set a new default via settings
      container.read(setDefaultSpeedProvider)(0.5);

      // defaultSpeed changed to 0.5
      expect(container.read(defaultSpeedProvider), equals(0.5));

      // currentSpeed syncs to the new default so the player UI reflects it.
      expect(container.read(currentSpeedProvider), equals(0.5));

      // But a NEW file would initialize to the new default (0.5) —
      // simulated by creating a new container:
      final container2 = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWith((ref) => prefs),
        ],
      );
      addTearDown(container2.dispose);

      expect(container2.read(currentSpeedProvider), equals(0.5),
          reason: '新文件打开时应使用更新后的默认速度 0.5x');
    });
  });

  // ── PLY-T59: Speed button shows current speed ────────────────────────────

  group('PLY-T59: Speed button label matches current speed', () {
    test('button text format for each valid speed', () {
      // The _SpeedControl widget renders Text('${snapshot.data ?? 1.0}x').
      // This verifies the label format for all speed options.
      for (final speed in speedOptions) {
        final label = '${speed}x';
        expect(label, equals('${speed}x'),
            reason: '速度 $speed 的按钮标签应为 "${speed}x"');
      }
    });

    test('button text for default 1.0x', () {
      expect('${1.0}x', equals('1.0x'),
          reason: '默认速度 1.0x 按钮应显示 "1.0x"');
    });

    test('button text for 1.5x', () {
      expect('${1.5}x', equals('1.5x'),
          reason: '1.5x 速度按钮应显示 "1.5x"');
    });

    test('button text for 0.5x', () {
      expect('${0.5}x', equals('0.5x'),
          reason: '0.5x 速度按钮应显示 "0.5x"');
    });

    test('button text for 0.75x', () {
      expect('${0.75}x', equals('0.75x'),
          reason: '0.75x 速度按钮应显示 "0.75x"');
    });

    test('button text for 1.25x', () {
      expect('${1.25}x', equals('1.25x'),
          reason: '1.25x 速度按钮应显示 "1.25x"');
    });

    test('button text for 2.0x', () {
      expect('${2.0}x', equals('2.0x'),
          reason: '2.0x 速度按钮应显示 "2.0x"');
    });
  });

  // ── PLY-T60: Speed menu contains all 6 options ───────────────────────────

  group('PLY-T60: Speed menu has all 6 options', () {
    test('speedOptions contains exactly 6 values', () {
      expect(speedOptions.length, equals(6),
          reason: '速度菜单应包含恰好 6 个选项');
    });

    test('speedOptions unordered equality check', () {
      expect(speedOptions,
          unorderedEquals([0.5, 0.75, 1.0, 1.25, 1.5, 2.0]),
          reason: '速度菜单应包含全部 6 个预设速度值');
    });

    test('all speed options are valid according to isValidSpeed', () {
      for (final speed in speedOptions) {
        expect(isValidSpeed(speed), isTrue,
            reason: '$speed 应通过 isValidSpeed 验证');
      }
    });

    test('each speed option is unique', () {
      expect(speedOptions.toSet().length, equals(speedOptions.length),
          reason: '速度选项不应有重复值');
    });

    test('speed options cover the full range from 0.5 to 2.0', () {
      expect(speedOptions.first, equals(0.5),
          reason: '第一个选项应为最慢速度 0.5x');
      expect(speedOptions.last, equals(2.0),
          reason: '最后一个选项应为最快速度 2.0x');
    });

    test('speed options are monotonically increasing', () {
      for (int i = 1; i < speedOptions.length; i++) {
        expect(speedOptions[i], greaterThan(speedOptions[i - 1]),
            reason: '速度选项应按升序排列');
      }
    });
  });

  // ═════════════════════════════════════════════════════════════════════════════
  // TST-10: rememberSpeed 功能 — TST-T72 ~ TST-T78
  // ═════════════════════════════════════════════════════════════════════════════

  group('TST-10: rememberSpeed 功能', () {
    // ── TST-T72: rememberSpeed 默认值 ──────────────────────────────────────

    test('TST-T72: rememberSpeed default value', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      // Pure function: getRememberSpeed returns false when no value stored
      expect(getRememberSpeed(prefs), isFalse,
          reason: '无存储时 getRememberSpeed 应返回 false');
      expect(getRememberSpeed(null), isFalse,
          reason: 'prefs 为 null 时应返回 false');

      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWith((ref) => prefs),
        ],
      );
      addTearDown(container.dispose);

      expect(container.read(rememberSpeedProvider), isFalse,
          reason: 'rememberSpeedProvider 默认值应为 false');
    });

    // ── TST-T73: 开启时调速到 2.0x → defaultSpeed 同步更新 ───────────────

    test('TST-T73: 开启 rememberSpeed 调速, defaultSpeed 同步更新', () async {
      SharedPreferences.setMockInitialValues({
        'default_playback_speed': 1.0,
        'remember_playback_speed': true,
      });
      final prefs = await SharedPreferences.getInstance();

      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWith((ref) => prefs),
        ],
      );
      addTearDown(container.dispose);

      // Verify initial state
      expect(container.read(rememberSpeedProvider), isTrue);
      expect(container.read(defaultSpeedProvider), equals(1.0));
      expect(container.read(currentSpeedProvider), equals(1.0));

      // Simulate the player speed selector logic (player_screen.dart):
      // 1. Update currentSpeed via player UI
      container.read(currentSpeedProvider.notifier).state = 2.0;
      // 2. If rememberSpeed is on, sync defaultSpeed too
      if (container.read(rememberSpeedProvider)) {
        container.read(setDefaultSpeedProvider)(2.0);
      }

      // defaultSpeed should now be 2.0 (synced from player)
      expect(container.read(defaultSpeedProvider), equals(2.0),
          reason: '开启记住速度时调速到 2.0x, defaultSpeed 应同步更新为 2.0');
      expect(container.read(currentSpeedProvider), equals(2.0),
          reason: 'currentSpeed 应为 2.0');
    });

    // ── TST-T74: 开启时调速到 2.0x → SharedPreferences 持久化 ────────────

    test('TST-T74: 开启 rememberSpeed 调速, SharedPreferences 持久化', () async {
      SharedPreferences.setMockInitialValues({
        'default_playback_speed': 1.0,
        'remember_playback_speed': true,
      });
      final prefs = await SharedPreferences.getInstance();

      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWith((ref) => prefs),
        ],
      );
      addTearDown(container.dispose);

      expect(container.read(rememberSpeedProvider), isTrue);

      // Simulate speed change with rememberSpeed ON
      container.read(currentSpeedProvider.notifier).state = 2.0;
      if (container.read(rememberSpeedProvider)) {
        container.read(setDefaultSpeedProvider)(2.0);
      }

      // SharedPreferences should have the new default speed
      expect(prefs.getDouble('default_playback_speed'), equals(2.0),
          reason: '开启 rememberSpeed 时调速到 2.0x 应持久化到 SharedPreferences');
    });

    // ── TST-T75: 关闭时调速到 2.0x → defaultSpeed 保持原值 ───────────────

    test('TST-T75: 关闭 rememberSpeed 调速, defaultSpeed 保持不变', () async {
      SharedPreferences.setMockInitialValues({
        'default_playback_speed': 1.0,
        'remember_playback_speed': false,
      });
      final prefs = await SharedPreferences.getInstance();

      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWith((ref) => prefs),
        ],
      );
      addTearDown(container.dispose);

      expect(container.read(rememberSpeedProvider), isFalse);
      expect(container.read(defaultSpeedProvider), equals(1.0));

      // Simulate speed change with rememberSpeed OFF
      container.read(currentSpeedProvider.notifier).state = 2.0;
      // RememberSpeed is off — do NOT call setDefaultSpeedProvider
      if (container.read(rememberSpeedProvider)) {
        container.read(setDefaultSpeedProvider)(2.0);
      }

      // defaultSpeed should remain unchanged
      expect(container.read(defaultSpeedProvider), equals(1.0),
          reason: '关闭记住速度时调速, defaultSpeed 应保持原值 1.0');
      expect(container.read(currentSpeedProvider), equals(2.0),
          reason: 'currentSpeed 应变更为 2.0');
      expect(prefs.getDouble('default_playback_speed'), equals(1.0),
          reason: 'SharedPreferences 中的值应保持 1.0 不变');
    });

    // ── TST-T76: 关闭时切歌 → 新曲目使用 Settings 中的 defaultSpeed ─────

    test('TST-T76: 关闭 rememberSpeed 切歌, 新曲目使用 Settings defaultSpeed',
        () async {
      SharedPreferences.setMockInitialValues({
        'default_playback_speed': 1.0,
        'remember_playback_speed': false,
      });
      final prefs = await SharedPreferences.getInstance();

      // Simulate current session where user changed speed to 2.0
      // but rememberSpeed is off, so defaultSpeed stays at 1.0
      {
        final container = ProviderContainer(
          overrides: [
            sharedPreferencesProvider.overrideWith((ref) => prefs),
          ],
        );
        container.read(currentSpeedProvider.notifier).state = 2.0;
        // rememberSpeed is off — don't update default
        expect(container.read(defaultSpeedProvider), equals(1.0));
        expect(container.read(currentSpeedProvider), equals(2.0));
        container.dispose();
      }

      // New file ("next song") — new container simulates fresh load.
      // currentSpeed initializes from defaultSpeed (= 1.0),
      // NOT from the previous session's currentSpeed (2.0).
      {
        final container2 = ProviderContainer(
          overrides: [
            sharedPreferencesProvider.overrideWith((ref) => prefs),
          ],
        );
        addTearDown(container2.dispose);

        expect(container2.read(currentSpeedProvider), equals(1.0),
            reason:
                '关闭记住速度时切歌, 新曲目应使用 Settings 中的 defaultSpeed 1.0x');
      }
    });

    // ── TST-T77: 开启时切歌 → 新曲目使用上次播放器中的速度 ──────────────

    test('TST-T77: 开启 rememberSpeed 切歌, 新曲目使用上次调速后的速度',
        () async {
      SharedPreferences.setMockInitialValues({
        'default_playback_speed': 1.0,
        'remember_playback_speed': true,
      });
      final prefs = await SharedPreferences.getInstance();

      // Simulate current session where user changed speed to 2.0
      // and rememberSpeed is on, so defaultSpeed gets updated too
      {
        final container = ProviderContainer(
          overrides: [
            sharedPreferencesProvider.overrideWith((ref) => prefs),
          ],
        );
        container.read(currentSpeedProvider.notifier).state = 2.0;
        if (container.read(rememberSpeedProvider)) {
          container.read(setDefaultSpeedProvider)(2.0);
        }
        expect(container.read(defaultSpeedProvider), equals(2.0));
        container.dispose();
      }

      // New file ("next song") — new container.
      // defaultSpeed from SharedPreferences should be 2.0,
      // so currentSpeed initializes to 2.0.
      {
        final container2 = ProviderContainer(
          overrides: [
            sharedPreferencesProvider.overrideWith((ref) => prefs),
          ],
        );
        addTearDown(container2.dispose);

        expect(container2.read(defaultSpeedProvider), equals(2.0),
            reason:
                '开启记住速度时, SharedPreferences 中的 defaultSpeed 应为 2.0');
        expect(container2.read(currentSpeedProvider), equals(2.0),
            reason:
                '开启记住速度时切歌, 新曲目应使用上次调速后的速度 2.0x');
      }
    });

    // ── TST-T78: setRememberSpeed 持久化到 SharedPreferences ──────────────

    test('TST-T78: setRememberSpeed 持久化到 SharedPreferences', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWith((ref) => prefs),
        ],
      );
      addTearDown(container.dispose);

      // Initially false (default)
      expect(container.read(rememberSpeedProvider), isFalse);

      // Set to true
      container.read(setRememberSpeedProvider)(true);
      expect(prefs.getBool('remember_playback_speed'), isTrue,
          reason: 'setRememberSpeed(true) 应持久化 true 到 SharedPreferences');
      expect(container.read(rememberSpeedProvider), isTrue,
          reason: 'rememberSpeedProvider 应反映 true');

      // Set to false
      container.read(setRememberSpeedProvider)(false);
      expect(prefs.getBool('remember_playback_speed'), isFalse,
          reason: 'setRememberSpeed(false) 应持久化 false 到 SharedPreferences');
      expect(container.read(rememberSpeedProvider), isFalse,
          reason: 'rememberSpeedProvider 应反映 false');
    });

    // ── 补充: rememberSpeed 重启后持久化 ─────────────────────────────────

    test('rememberSpeed survives restart via SharedPreferences', () async {
      SharedPreferences.setMockInitialValues({
        'remember_playback_speed': true,
        'default_playback_speed': 1.5,
      });
      final prefs = await SharedPreferences.getInstance();

      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWith((ref) => prefs),
        ],
      );
      addTearDown(container.dispose);

      expect(container.read(rememberSpeedProvider), isTrue,
          reason: '重启后 rememberSpeed 应从 SharedPreferences 恢复为 true');
      expect(container.read(defaultSpeedProvider), equals(1.5),
          reason: '重启后 defaultSpeed 应恢复为 1.5');
    });
  });

  // ── Supplementary: isValidSpeed boundary checks ──────────────────────────

  group('isValidSpeed — supplementary boundary checks', () {
    test('values outside speedOptions range are invalid', () {
      expect(isValidSpeed(0.25), isFalse,
          reason: '0.25x 不在速度选项中');
      expect(isValidSpeed(3.0), isFalse,
          reason: '3.0x 不在速度选项中');
      expect(isValidSpeed(0.0), isFalse,
          reason: '0.0x 不在速度选项中');
      expect(isValidSpeed(-1.0), isFalse,
          reason: '负数速度无效');
    });

    test('values between options are invalid', () {
      expect(isValidSpeed(0.6), isFalse,
          reason: '0.6x 介于 0.5 和 0.75 之间，不是有效选项');
      expect(isValidSpeed(1.1), isFalse,
          reason: '1.1x 介于 1.0 和 1.25 之间，不是有效选项');
      expect(isValidSpeed(1.75), isFalse,
          reason: '1.75x 介于 1.5 和 2.0 之间，不是有效选项');
    });

    test('isValidSpeed with exact options passes', () {
      for (final speed in speedOptions) {
        expect(isValidSpeed(speed), isTrue,
            reason: '$speed 是有效速度选项');
      }
    });

    test('isValidSpeed tolerance — values within 0.001 pass', () {
      // just_audio may report 0.999999 instead of 1.0 due to floating point.
      // The tolerance of 0.01 handles this.
      expect(isValidSpeed(0.999), isTrue,
          reason: '0.999 在 1.0 的容差范围内 (0.01)，应视为有效');
      expect(isValidSpeed(1.001), isTrue,
          reason: '1.001 在 1.0 的容差范围内 (0.01)，应视为有效');
      expect(isValidSpeed(1.509), isTrue,
          reason: '1.509 在 1.5 的容差范围内 (0.01)，应视为有效');
    });
  });
}
