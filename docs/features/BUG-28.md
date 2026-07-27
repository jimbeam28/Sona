# BUG-28 — setSeekStepSettingProvider 忽略校验返回值（SET1）

> 来源：`docs/cr/cr-20260724-0110.md` SET1 (line 810-820)
> dev-plan 流程：Bug 修复模式

---

## §0 头部元数据

```yaml
id: BUG-28
name: setSeekStepSettingProvider 忽略校验返回值（SET1）
priority: P2
status: draft
created_at: 2026-07-27
last_updated: 2026-07-27
spec_anchored_files:
  - lib/features/settings/settings_provider.dart
cross_module_impacts: [SET, PLY]
parent_feature: null
manual_qa_required: false
```

---

## §1 用户视角

### 1.0 原始需求

> cr-20260724-0110.md SET1：`settings_provider.dart:113-121` — `setSeekStepSettingProvider` 调用 `_service.setSeekStep(...)` 返回 `bool`（校验通过为 `true`，非法值为 `false`），但返回值被丢弃。无论校验是否通过都无条件执行 `ref.invalidate(seekStepSettingProvider)` 和 `ref.read(seekStepProvider.notifier).state = seconds`。对比 speed 的设置在 `player_provider.dart:139-140` 有 `if (!sm.isValidSpeed(s)) return;` 守卫。

### 1.1 这一功能干什么（一句话）

使 `setSeekStepSettingProvider` 在校验失败时不更新运行时 provider，与 speed 设置保持一致的守卫模式。

### 1.2 用户期望的场景

| ID | 你看到的样子 | 期望行为 |
|----|----|----|
| U1 | 设置页选择有效的快进步长（10/15/30/60 秒） | SharedPreferences 写入成功，运行时 provider 更新，UI 显示新值 |
| U2 | 程序内部以非法值（如 7）调用 setSeekStepSettingProvider | SharedPreferences 不写入，运行时 provider 不变，UI 保持旧值 |
| U3 | SharedPreferences 为 null（测试环境） | 运行时 provider 仍更新（与 speed 行为一致，因 setDefaultSpeed 也接受 null prefs） |

---

## §2 已实现的功能骨架

### 2.1 文件与分层

| 层 | 文件 | 行数 | 角色 |
|---|---|---|---|
| Domain | `lib/features/settings/domain/settings_service.dart` | 124 | 纯 Dart 设置读写 |
| Provider | `lib/features/settings/settings_provider.dart` | 121 | Riverpod 桥接 |
| Provider | `lib/features/player/player_provider.dart` | 337 | speed 设置有守卫（:139-140） |
| Provider | `lib/features/player/domain/speed_manager.dart` | 52 | readSeekStep 纯函数 |
| UI | `lib/features/settings/settings_screen.dart` | — | 设置页面调用方 |

### 2.2 关键代码段

| 区域 | 行号 | 说明 |
|---|---|---|
| setSeekStep 校验逻辑 | `settings_service.dart:89-93` | `seekStepOptions.contains(seconds)` → false 时 return false |
| setSeekStepSettingProvider 丢弃返回值 | `settings_provider.dart:113-121` | `_service.setSeekStep(...)` 返回值未检查 |
| 无条件更新 runtime provider | `settings_provider.dart:117-119` | `ref.invalidate` + `ref.read(...).state = seconds` |
| speed 设置有守卫 | `player_provider.dart:139-140` | `if (!sm.isValidSpeed(s)) return;` |
| seekStepOptions 合法值 | `settings_service.dart:23` | `[10, 15, 30, 60]` |
| seekStepSettingProvider 读取 | `settings_provider.dart:105-108` | 从 SharedPreferences 读取，默认 15 |

---

## §3 行为规约

### 3.1 修复后行为

- **[BUG-28-S1]** setSeekStepSettingProvider 检查校验返回值 (`status: new`)
  ```
  Given 程序以非法值（如 7）调用 setSeekStepSettingProvider
  When  _service.setSeekStep(prefs, 7) 返回 false（7 不在 [10,15,30,60] 中）
  Then  不执行 ref.invalidate(seekStepSettingProvider)
  Then  不执行 ref.read(seekStepProvider.notifier).state = 7
  否定断言:
    - 不在校验失败时更新 seekStepSettingProvider（当前 BUG：返回值被丢弃，无条件 invalidate）
    - 不在校验失败时更新 seekStepProvider 的 runtime state（当前 BUG：无条件 state = seconds）
    - 不改变校验通过时的正常行为（合法值 10/15/30/60 → SharedPreferences 写入 + provider 更新）
  ```
  Code evidence: `lib/features/settings/settings_provider.dart:116`（`_service.setSeekStep(...)` 返回值被丢弃）
  Code evidence: `lib/features/settings/domain/settings_service.dart:89-93`（`setSeekStep` 校验逻辑）
  Code evidence: `lib/features/player/player_provider.dart:139-140`（speed 的守卫模式对比）

  **修改指令 — `lib/features/settings/settings_provider.dart`（setSeekStepSettingProvider）**

  位置：`:113-121`

  当前代码（:113-121）：
  ```dart
  final setSeekStepSettingProvider = Provider<void Function(int)>((ref) {
    return (int seconds) {
      debugPrint('[Settings] seekStep: ${seconds}s');
      _service.setSeekStep(ref.read(sharedPreferencesProvider), seconds);
      ref.invalidate(seekStepSettingProvider);
      // Also update the runtime seek step used by the player.
      ref.read(seekStepProvider.notifier).state = seconds;
    };
  });
  ```

  改为：
  ```dart
  final setSeekStepSettingProvider = Provider<void Function(int)>((ref) {
    return (int seconds) {
      debugPrint('[Settings] seekStep: ${seconds}s');
      if (!_service.setSeekStep(ref.read(sharedPreferencesProvider), seconds)) return;
      ref.invalidate(seekStepSettingProvider);
      // Also update the runtime seek step used by the player.
      ref.read(seekStepProvider.notifier).state = seconds;
    };
  });
  ```

  边界裁决：
  - 合法值（10/15/30/60）→ `setSeekStep` 返回 true → 执行 invalidate + state 更新（行为不变）
  - 非法值（如 7, 0, -1, 999）→ `setSeekStep` 返回 false → 直接 return → SharedPreferences 不写入，runtime provider 不变
  - `prefs == null`（测试环境）→ `setSeekStep` 内部 `prefs?.setInt(...)` 不执行但返回 true（因为 `seekStepOptions.contains(seconds)` 通过）→ invalidate + state 更新（与 speed 行为一致：`player_provider.dart:140` 也是 prefs 操作 + invalidate）
  - 调用方 `settings_screen.dart` 无需修改（函数签名不变，仍为 `void Function(int)`）

---

## §4 不变量

- **[BUG-28-INV1]** 所有通过 provider 写入的设置值都经过域层校验
  证据：`setSeekStepSettingProvider` 检查 `_service.setSeekStep()` 返回值后才更新 runtime（`settings_provider.dart:116`）；`setDefaultSpeedProvider` 检查 `sm.isValidSpeed()` 后才更新（`player_provider.dart:140`）

- **[BUG-28-INV2]** `setSeekStepSettingProvider` 与 `setDefaultSpeedProvider` 守卫模式一致
  证据：两者都在域层校验失败时 early return，不更新 runtime provider

---

## §5 测试规约

### 5.1 现有测试清单

| 测试文件 | 覆盖 | 备注 |
|---|---|---|
| `test/features/settings/` | Ref-27, Settings 测试 | 需检查是否覆盖 setSeekStep 校验 |

### 5.2 测试 ID 派生清单

```
BUG-28-S1           # setSeekStepSettingProvider 检查校验返回值
BUG-28-INV1         # 所有设置值经过域层校验
BUG-28-INV2         # seek step 与 speed 守卫模式一致
```

### 5.3 测试覆盖盲点

| 未覆盖 ID | 现状 | 应补偿方式 |
|---|---|---|
| BUG-28-S1 合法值 | 无测试验证合法值正常通过 | ProviderContainer 测试：调用 set(15) → 断言 seekStepSettingProvider == 15 |
| BUG-28-S1 非法值 | 无测试验证非法值被拒绝 | ProviderContainer 测试：调用 set(7) → 断言 seekStepSettingProvider 保持默认 15，seekStepProvider 不变 |
| BUG-28-INV1 | 无测试对比 speed 与 seek step 守卫 | 分别测试非法 speed 和非法 seek step → 均不更新 runtime |

### 5.4 测试文件位置

| 测试 ID | 文件路径 |
|---|---|
| BUG-28-S1 | `test/features/settings/bug_bug28_repro_test.dart` |
| BUG-28-INV1 | `test/features/settings/bug_bug28_repro_test.dart` |
| BUG-28-INV2 | `test/features/settings/bug_bug28_repro_test.dart` |

---

## §6 算法样例

不适用——本修复为校验守卫补漏，无新算法。

---

## §7 跨模块影响

| 其它 feature | 影响点 | 需要补的回归断言 |
|---|---|---|
| PLY | `seekStepProvider` 运行时值 | 非法值不再更新 seekStepProvider，播放器快进步长不受非法值影响 |
| SET | `settings_screen.dart` | UI 调用方无需修改，但需验证 UI 不会传入非法值（`seekStepOptions` 列表已约束） |

---

## §8 平台特性与手动 QA

不适用——本修复为纯逻辑校验，无平台特性风险。

---

## §9 dev-status.json 条目对照

见统一更新：`docs/dev/dev-status.json`。

---

## §10 changelog

- 2026-07-27: 创建 BUG-28 spec（基于 cr-20260724-0110.md SET1）
