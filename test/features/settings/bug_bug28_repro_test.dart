// test/features/settings/bug_bug28_repro_test.dart
// BUG-28 门禁测试（spec docs/features/BUG-28.md §5.4 指定文件）。
//
// 锚定 cr-20260724-0110 SET1 修复：修复前 setSeekStepSettingProvider 丢弃
// _service.setSeekStep(...) 的 bool 返回值，非法值也会无条件执行
// ref.invalidate(seekStepSettingProvider) 与
// ref.read(seekStepProvider.notifier).state = seconds——设置页显示值与播放器
// 实际快进步长背离，重启才"自愈"。
//
// 既有 settings_test.dart:344 'rejects invalid values' 只断言 prefs 与
// seekStepSettingProvider、从未读 seekStepProvider（cr SET1 自检答案指出的
// 零锚定分支：回退修复该用例照样绿），故本文件补核心否定断言：
// 非法值 → 运行时 seekStepProvider 不变。

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nas_audio_player/shared/di/providers.dart';

/// Creates a [ProviderContainer] with the given SharedPreferences override.
ProviderContainer createContainer({SharedPreferences? prefs}) {
  return ProviderContainer(
    overrides: [
      if (prefs != null) sharedPreferencesProvider.overrideWith((ref) => prefs),
    ],
  );
}

void main() {
  // ═══════════════════════════════════════════════════════════════════════════
  // BUG-28-S1: setSeekStepSettingProvider 检查校验返回值
  // ═══════════════════════════════════════════════════════════════════════════

  group('BUG-28-S1: setSeekStepSettingProvider 检查校验返回值', () {
    test('复现路径：先设合法值 60 再传非法值 7 → 运行时步长保持 60', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      final container = createContainer(prefs: prefs);
      addTearDown(container.dispose);

      container.read(setSeekStepSettingProvider)(60);
      expect(container.read(seekStepSettingProvider), equals(60));
      expect(container.read(seekStepProvider), equals(60));

      // 7 不在 [10, 15, 30, 60] 中 → setSeekStep 返回 false → 提前返回。
      container.read(setSeekStepSettingProvider)(7);

      // 核心否定断言：修复前此行 state 被写成 7（显示 60 / 实际 7 背离）。
      expect(container.read(seekStepProvider), equals(60),
          reason: '非法值 7 不得更新运行时 seekStepProvider');
      expect(container.read(seekStepSettingProvider), equals(60),
          reason: '非法值 7 不得改变设置页显示值');
      expect(prefs.getInt('seek_step_seconds'), equals(60),
          reason: '非法值 7 不得覆盖持久化值');
    });

    test('首次启动传非法值 7 → prefs 不写入, 显示/运行时均保持默认 15', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      final container = createContainer(prefs: prefs);
      addTearDown(container.dispose);

      container.read(setSeekStepSettingProvider)(7);

      expect(prefs.getInt('seek_step_seconds'), isNull,
          reason: '校验失败时 SharedPreferences 不得写入');
      expect(container.read(seekStepSettingProvider), equals(15),
          reason: 'seekStepSettingProvider 应保持默认 15');
      // 否定断言：修复前运行时被无条件写成 7。
      expect(container.read(seekStepProvider), equals(15),
          reason: '校验失败时运行时 seekStepProvider 不得更新');
    });

    test('非法值集合 0 / -1 / 20 / 45 / 999 全部被拒, 运行时不变', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      final container = createContainer(prefs: prefs);
      addTearDown(container.dispose);

      for (final invalid in [0, -1, 20, 45, 999]) {
        container.read(setSeekStepSettingProvider)(invalid);
        expect(container.read(seekStepProvider), equals(15),
            reason: '非法值 $invalid 不得更新运行时 seekStepProvider');
        expect(container.read(seekStepSettingProvider), equals(15),
            reason: '非法值 $invalid 不得更新 seekStepSettingProvider');
        expect(prefs.getInt('seek_step_seconds'), isNull,
            reason: '非法值 $invalid 不得写入 SharedPreferences');
      }
    });

    test('合法值 10/15/30/60 → prefs + 显示 + 运行时三方一致（正常行为不变）', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      final container = createContainer(prefs: prefs);
      addTearDown(container.dispose);

      for (final step in seekStepOptions) {
        container.read(setSeekStepSettingProvider)(step);
        expect(prefs.getInt('seek_step_seconds'), equals(step),
            reason: '合法值 $step 应持久化');
        expect(container.read(seekStepSettingProvider), equals(step),
            reason: '合法值 $step 应更新 seekStepSettingProvider');
        expect(container.read(seekStepProvider), equals(step),
            reason: '合法值 $step 应同步更新运行时 seekStepProvider');
      }
    });

    test('非法值拒绝后再设合法值, 行为正常恢复', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      final container = createContainer(prefs: prefs);
      addTearDown(container.dispose);

      container.read(setSeekStepSettingProvider)(999);
      container.read(setSeekStepSettingProvider)(30);

      expect(prefs.getInt('seek_step_seconds'), equals(30));
      expect(container.read(seekStepSettingProvider), equals(30));
      expect(container.read(seekStepProvider), equals(30));
    });

    test('U3: prefs 为 null（测试环境）时合法值仍更新运行时 provider', () {
      // sharedPreferencesProvider 默认实现即返回 null（browser_provider.dart:26）。
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(setSeekStepSettingProvider)(30);

      // setSeekStep(null, 30) 校验通过返回 true → 守卫放行 → 运行时更新,
      // 与 setDefaultSpeedProvider 接受 null prefs 的行为一致（spec §1.2 U3）。
      expect(container.read(seekStepProvider), equals(30),
          reason: 'prefs 为 null 时合法值仍应更新运行时 seekStepProvider');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // BUG-28-INV1 / INV2: 所有 provider 写入经域层校验, 守卫模式与 speed 一致
  // ═══════════════════════════════════════════════════════════════════════════

  group('BUG-28-INV1/INV2: seek step 与 speed 守卫模式一致', () {
    test('非法 speed 1.7 → defaultSpeed/currentSpeed 均不变', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      final container = createContainer(prefs: prefs);
      addTearDown(container.dispose);

      container.read(setDefaultSpeedProvider)(1.7);

      expect(prefs.getDouble('default_playback_speed'), isNull,
          reason: '非法速度不得写入 SharedPreferences');
      expect(container.read(defaultSpeedProvider), equals(1.0),
          reason: '非法速度不得更新 defaultSpeedProvider');
      expect(container.read(currentSpeedProvider), equals(1.0),
          reason: '非法速度不得更新运行时 currentSpeedProvider');
    });

    test('非法 seek step 20 → seekStepProvider 不变（与 speed 守卫对齐）', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      final container = createContainer(prefs: prefs);
      addTearDown(container.dispose);

      container.read(setSeekStepSettingProvider)(20);

      expect(prefs.getInt('seek_step_seconds'), isNull,
          reason: '非法步长不得写入 SharedPreferences');
      expect(container.read(seekStepSettingProvider), equals(15),
          reason: '非法步长不得更新 seekStepSettingProvider');
      expect(container.read(seekStepProvider), equals(15),
          reason: '非法步长不得更新运行时 seekStepProvider');
    });

    test('合法 speed 1.5 与合法步长 30 → 两者运行时均立即生效', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      final container = createContainer(prefs: prefs);
      addTearDown(container.dispose);

      container.read(setDefaultSpeedProvider)(1.5);
      container.read(setSeekStepSettingProvider)(30);

      expect(container.read(currentSpeedProvider), equals(1.5));
      expect(container.read(seekStepProvider), equals(30));
    });
  });
}
