# REF-04 — 架构整合（SET2 + DI1 + DI2 + DI3）

> 来源：`docs/cr/cr-20260724-0110.md` SET2 + DI1 + DI2 + DI3

---

## §0 头部元数据

```yaml
id: REF-04
name: 架构整合（SET2 + DI1 + DI2 + DI3）
priority: P1
status: draft
created_at: 2026-07-27
last_updated: 2026-07-27
spec_anchored_files:
  - lib/features/settings/domain/settings_service.dart
  - lib/features/player/domain/speed_manager.dart
  - lib/features/settings/settings_provider.dart
  - lib/features/player/player_provider.dart
  - lib/features/browser/browser_provider.dart
  - lib/shared/di/providers.dart
cross_module_impacts: [SET, PLY, BRW]
parent_feature: null
manual_qa_required: false
```

---

## §1 用户视角

### 1.0 原始需求

> cr-20260724-0110.md SET2：`settings_service.dart:14-26,58-93` 和 `speed_manager.dart:18-52` 重复定义了相同的 SharedPreferences keys、speedOptions、seekStepOptions、isValidSpeed 函数。第三份拷贝在 `settings_provider.dart:63`（seekStepOptions）。settings_service 的 speed/step 函数是死代码（仅 ref_27_test 调用）。
> DI1：`player_provider.dart:122` seekStepProvider（StateProvider 读 SharedPreferences）和 `settings_provider.dart:105` seekStepSettingProvider（直接读 SharedPreferences）是同一数据的手动同步副本。
> DI2：`browser_provider.dart:26` sharedPreferencesProvider 是全局基础设施却定义在 leaf feature 中，被 4+ feature 消费。
> DI3：`di/providers.dart:4-5` header 声称 "ONLY file that is allowed to import from multiple features" 但实际上是双向宽门面（re-export 所有 feature 的所有 provider）。

### 1.1 这一功能干什么（一句话）

消除 settings/speed 的三份重复定义，统一 seek step 为单一数据源，将 sharedPreferencesProvider 迁移到 shared 层，修正 di/providers.dart 文档。

### 1.2 用户期望的场景

| ID | 你看到的样子 | 期望行为 |
|----|----|----|
| U1 | speed/step keys 定义 | 只在 speed_manager.dart 定义一次 |
| U2 | speedOptions / seekStepOptions | 只在 speed_manager.dart 定义一次 |
| U3 | isValidSpeed 函数 | 只在 speed_manager.dart 定义一次 |
| U4 | seekStep 数据 | player 直接 watch seekStepSettingProvider，无 seekStepProvider 副本 |
| U5 | sharedPreferencesProvider | 定义在 shared/di/ 或 core/ 下，非 browser_provider.dart |
| U6 | di/providers.dart 文档 | 准确描述其角色（re-export facade，非唯一跨 feature 文件） |

---

## §2 已实现的功能骨架

### 2.1 重复定义一览

| 符号 | settings_service.dart | speed_manager.dart | settings_provider.dart | 说明 |
|---|---|---|---|---|
| `_defaultSpeedKey` / `defaultSpeedKey` | `:15` `'default_playback_speed'` | `:18` `'default_playback_speed'` | — | 重复 key |
| `_seekStepKey` / `seekStepPrefsKey` | `:16` `'seek_step_seconds'` | `:21` `'seek_step_seconds'` | — | 重复 key |
| `_defaultSeekStep` / `defaultSeekStep` | `:20` `15` | `:24` `15` | — | 重复默认值 |
| `seekStepOptions` | `:23` `[10, 15, 30, 60]` | — | `:63` `[10, 15, 30, 60]` | 三份重复 |
| `speedOptions` | `:26` `[0.5, 0.75, 1.0, 1.25, 1.5, 2.0]` | `:27` 同 | — | 重复 |
| `isValidSpeed` | `:74-76` | `:33-35` | — | 重复函数 |
| `getDefaultSpeed` | `:58-62` | `:40-44` | — | 重复函数 |
| `getSeekStep` / `readSeekStep` | `:81-84` | `:49-52` | — | 重复函数 |
| `setSeekStep` | `:89-93` | — | — | settings_service 独有（validates + writes） |

### 2.2 Seek step 双 provider

| Provider | 文件:行 | 类型 | 数据源 |
|---|---|---|---|
| `seekStepProvider` | `player_provider.dart:122-123` | `StateProvider<int>` | `sm.readSeekStep(prefs)` |
| `seekStepSettingProvider` | `settings_provider.dart:105-108` | `Provider<int>` | `readSeekStep(prefs)` |

`setSeekStepSettingProvider`（`settings_provider.dart:113-120`）手动同步两者：写 SharedPreferences 后同时更新 `seekStepProvider.notifier.state`。

### 2.3 sharedPreferencesProvider 位置

| 定义位置 | 消费方 |
|---|---|
| `browser_provider.dart:26` | `settings_provider.dart`（theme/speed/seek）、`player_provider.dart`（speed/seek）、`browser_provider.dart`（sort/queue persist/restore）、`di/providers.dart`（re-export 给全部 feature） |

---

## §3 行为规约

### 3.1 SET2 — 消除 speed/step 三份重复

- **[REF-04-S1]** speed/step keys 和选项只在 speed_manager.dart 定义 (`status: new`)
  ```
  Given 代码库中 speed/step 相关常量和函数
  When  搜索定义
  Then  speedOptions、seekStepOptions、isValidSpeed、defaultSpeedKey、seekStepPrefsKey、defaultSeekStep、getDefaultSpeed、readSeekStep 只在 speed_manager.dart 定义
  否定断言:
    - 不在 settings_service.dart 中定义 speedOptions（当前 :26）、seekStepOptions（当前 :23）、isValidSpeed（当前 :74-76）、getDefaultSpeed（当前 :58-62）、getSeekStep（当前 :81-84）
    - 不在 settings_provider.dart 中定义 seekStepOptions（当前 :63）
    - 不改变运行时 key 值（'default_playback_speed'、'seek_step_seconds' 不变）
    - 不改变 speedOptions 和 seekStepOptions 的内容
  ```
  Code evidence: `lib/features/settings/domain/settings_service.dart:14-26`（重复 keys/options）、`:58-93`（重复函数）、`lib/features/player/domain/speed_manager.dart:18-52`（规范定义）、`lib/features/settings/settings_provider.dart:63`（第三份 seekStepOptions）

  **修改指令 — `lib/features/settings/domain/settings_service.dart`**

  策略：settings_service 保留 theme 和 remember-speed 相关逻辑（这些不重复），删除 speed/step 相关的重复定义。settings_service 的 `getDefaultSpeed`、`setDefaultSpeed`、`isValidSpeed`、`getSeekStep`、`setSeekStep`、`labelForSeekStep`、`speedOptions`、`seekStepOptions` 全部删除。

  位置：`:15-16`（`_defaultSpeedKey`、`_seekStepKey`）
  删除。

  位置：`:20`（`_defaultSeekStep`）
  删除。

  位置：`:23`（`seekStepOptions`）
  删除。

  位置：`:26`（`speedOptions`）
  删除。

  位置：`:55-93`（speed/step 相关方法）
  删除 `getDefaultSpeed`、`setDefaultSpeed`、`isValidSpeed`、`getSeekStep`、`setSeekStep`、`labelForSeekStep`。

  **settings_service 保留的方法：**
  - `getThemeMode` / `setThemeMode` / `labelForThemeMode`（theme）
  - `getRememberSpeed` / `setRememberSpeed`（remember speed）

  **修改指令 — `lib/features/settings/settings_provider.dart`**

  位置：`:63`（`seekStepOptions`）
  删除此重复定义。改为从 speed_manager 重导出：
  ```dart
  // 在 import 区域添加
  import '../player/domain/speed_manager.dart' show seekStepOptions;
  // 或从 di/providers.dart 获取
  ```
  但更好的方式：settings_provider 中引用 speed_manager 的常量。由于跨 feature import 走 di/providers.dart，可改为在 settings_provider 中 `import '../../shared/di/providers.dart' show seekStepOptions;`（但 di/providers.dart 从 player 重导出）。

  最简洁方案：settings_provider.dart 直接 `import '../player/domain/speed_manager.dart'`（speed_manager 是纯 domain 文件，非 feature provider，直接 import 不违反 feature 隔离规则）。

  **`setSeekStep` 和 `setDefaultSpeed` 迁移：**

  settings_service 的 `setSeekStep`（:89-93）和 `setDefaultSpeed`（:67-71）包含验证逻辑（检查是否为有效选项后写入）。这些逻辑应迁移到 speed_manager.dart 或保留在调用方（settings_provider.dart）。

  迁移到 speed_manager.dart：
  ```dart
  bool setDefaultSpeed(SharedPreferences? prefs, double speed) {
    if (!isValidSpeed(speed)) return false;
    prefs?.setDouble(defaultSpeedKey, speed);
    return true;
  }
  bool setSeekStep(SharedPreferences? prefs, int seconds) {
    if (!seekStepOptions.contains(seconds)) return false;
    prefs?.setInt(seekStepPrefsKey, seconds);
    return true;
  }
  ```

- **[REF-04-S2]** settings_service speed/step 方法不存在 (`status: new`)
  ```
  Given settings_service.dart 的公开 API
  When  静态分析
  Then  不包含 getDefaultSpeed / setDefaultSpeed / isValidSpeed / getSeekStep / setSeekStep / labelForSeekStep / speedOptions / seekStepOptions
  否定断言:
    - 不在 settings_service.dart 中出现上述符号定义
    - 不改变 settings_provider.dart 的外部行为（theme/speed/seek 读写功能不变）
    - 不改变 ref_27_test 之外的测试行为（ref_27_test 需适配）
  ```
  Code evidence: `lib/features/settings/domain/settings_service.dart:55-110`（待删除的方法）

### 3.2 DI1 — 消除 seekStepProvider 双数据源

- **[REF-04-S3]** seek step 为单一数据源 (`status: new`)
  ```
  Given seek step 在 Riverpod 容器中
  When  查询当前 seek step 值
  Then  只有一个 provider 暴露此数据（seekStepSettingProvider）
  And   player 直接 watch seekStepSettingProvider
  否定断言:
    - 不在 player_provider.dart 中定义 seekStepProvider（当前 :122-123）
    - 不在 setSeekStepSettingProvider 中手动同步两个 provider（当前 settings_provider.dart:119 `ref.read(seekStepProvider.notifier).state = seconds`）
    - 不改变 seek step 的读取和写入行为
  ```
  Code evidence: `lib/features/player/player_provider.dart:122-123`（`seekStepProvider`）、`lib/features/settings/settings_provider.dart:105-120`（`seekStepSettingProvider` + 手动同步）

  **修改指令**

  1. 删除 `player_provider.dart:122-123`（`seekStepProvider`）。
  2. player 消费方改为 `ref.watch(seekStepSettingProvider)`（从 `shared/di/providers.dart` 获取）。
  3. 删除 `settings_provider.dart:119`（`ref.read(seekStepProvider.notifier).state = seconds`）。
  4. 更新 `di/providers.dart` 中 re-export：删除 `seekStepProvider`，确保 `seekStepSettingProvider` 已导出（`:193` 已有）。

  **调用方适配：**

  搜索所有 `seekStepProvider` 消费方（`player_provider.dart` 内部 + 可能的 screen），改为 `seekStepSettingProvider`。

### 3.3 DI2 — sharedPreferencesProvider 迁移到 shared 层

- **[REF-04-S4]** sharedPreferencesProvider 定义在 shared/di/ (`status: new`)
  ```
  Given sharedPreferencesProvider 的定义位置
  When  搜索定义
  Then  在 shared/di/providers.dart 或 core/ 中定义
  否定断言:
    - 不在 browser_provider.dart 中定义 sharedPreferencesProvider（当前 :26）
    - 不改变 provider 的类型签名（`Provider<SharedPreferences?>`）
    - 不改变所有消费方的行为
  ```
  Code evidence: `lib/features/browser/browser_provider.dart:26`（`final sharedPreferencesProvider = Provider<SharedPreferences?>((ref) => null);`）

  **修改指令**

  1. 将 `sharedPreferencesProvider` 定义从 `browser_provider.dart:26` 移到 `shared/di/providers.dart`（作为基础设施 provider）。
  2. `browser_provider.dart` 改为从 `shared/di/providers.dart` import。
  3. `di/providers.dart` 不再需要 re-export `sharedPreferencesProvider`（因为它现在定义在此文件中）。

  位置：`lib/shared/di/providers.dart`
  在文件顶部添加：
  ```dart
  import 'package:shared_preferences/shared_preferences.dart';
  import 'package:flutter_riverpod/flutter_riverpod.dart';

  final sharedPreferencesProvider = Provider<SharedPreferences?>((ref) => null);
  ```

  位置：`lib/features/browser/browser_provider.dart:26`
  删除此行。

  位置：`lib/shared/di/providers.dart` re-export 区段（`:24-44` Browser 区域）
  删除 `sharedPreferencesProvider` 的 re-export（因为它现在直接定义在此文件中）。

### 3.4 DI3 — di/providers.dart 文档修正

- **[REF-04-S5]** di/providers.dart header 准确描述角色 (`status: new`)
  ```
  Given di/providers.dart 的文件头注释
  When  阅读文档
  Then  准确描述其角色：跨 feature re-export facade
  And   不声称 "ONLY file that is allowed to import from multiple features"
  否定断言:
    - 不在注释中声称自己是唯一允许跨 feature import 的文件（当前 :4-5 "ONLY file that is allowed to import from multiple features"）
    - 不改变 re-export 列表
  ```
  Code evidence: `lib/shared/di/providers.dart:4-5`

  **修改指令 — `lib/shared/di/providers.dart`**

  位置：`:1-20`（文件头注释）
  当前：
  ```dart
  // This is the ONLY file that is allowed to import from multiple features.
  // It re-exports providers that are consumed across feature boundaries so that
  // feature modules can import from a single canonical source instead of
  // reaching into each other's internals.
  ```
  改为：
  ```dart
  // Cross-feature provider re-export facade.
  //
  // This file re-exports providers from multiple features so that consumers
  // can import from a single canonical source instead of reaching into each
  // other's internals.  It does NOT own any business logic — all providers
  // are defined in their respective feature modules.
  //
  // Feature modules MAY import pure-domain symbols directly from other
  // features' domain/ directories (no feature-isolation violation), but
  // should prefer this facade for provider access to keep import graphs
  // shallow and auditable.
  ```

---

## §4 不变量

- **[REF-04-INV1]** speed/step keys/options/验证函数只在一处定义
  证据：`speed_manager.dart` 是唯一包含 `speedOptions`、`seekStepOptions`、`isValidSpeed`、`defaultSpeedKey`、`seekStepPrefsKey` 定义的文件

- **[REF-04-INV2]** seek step 为单一 Provider 数据源
  证据：`seekStepSettingProvider` 是唯一暴露 seek step 的 provider；`seekStepProvider` 已删除

- **[REF-04-INV3]** sharedPreferencesProvider 定义在 shared 层
  证据：`shared/di/providers.dart` 包含 `sharedPreferencesProvider` 定义；`browser_provider.dart` 不再定义此 provider

- **[REF-04-INV4]** di/providers.dart 文档准确
  证据：文件头注释描述为 "re-export facade"，不声称 "ONLY file"

---

## §5 测试规约

### 5.1 现有测试清单

| 测试文件 | 覆盖 | 备注 |
|---|---|---|
| `test/features/settings/ref_27_test.dart` | settings_service 方法 | 需删除 speed/step 相关测试（settings_service 不再有此功能） |
| `test/features/player/` | player 功能 | seekStepProvider → seekStepSettingProvider 适配 |
| `test/features/settings/` | settings 功能 | seekStepOptions 引用适配 |

### 5.2 测试 ID 派生清单

```
REF-04-S1 … S5        # Scenario
REF-04-INV1 … INV4    # 不变量
```

### 5.3 测试覆盖盲点

| 未覆盖 ID | 现状 | 应补偿方式 |
|---|---|---|
| REF-04-S1 | settings_service 删除 speed/step 方法 | 验证 settings_provider 外部行为不变 |
| REF-04-S3 | seekStepProvider 删除 | 验证 player 使用 seekStepSettingProvider |
| REF-04-S4 | sharedPreferencesProvider 迁移 | 验证所有消费方通过 di/providers.dart 获取 |

---

## §6 算法样例

不适用——本重构为重复消除和位置迁移，无新算法。

---

## §7 跨模块影响

| 其它 feature | 影响点 | 需要补的回归断言 |
|---|---|---|
| SET | settings_service 删除 speed/step 方法 | settings_screen 显示和设置功能不变 |
| PLY | seekStepProvider 删除，改用 seekStepSettingProvider | player seek 步长功能不变 |
| BRW | sharedPreferencesProvider 移出 browser_provider.dart | browser 排序/缓存/队列持久化不变 |

---

## §8 平台特性与手动 QA

本功能不涉及平台原生特性，全部可在 `flutter test` 中验证。

---

## §9 dev-status.json 条目对照

见统一更新：`docs/dev/dev-status.json`。

---

## §10 changelog

- 2026-07-27: 创建 REF-04 spec（基于 cr-20260724-0110.md SET2 + DI1 + DI2 + DI3）
