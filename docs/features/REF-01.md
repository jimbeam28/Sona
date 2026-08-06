# REF-01 — Domain 层 Flutter 依赖清理（A1-A6）

> 来源：`docs/cr/cr-2026-06-28.md` §1.1 + `docs/dev/arch-baseline.txt`
> dev-plan 流程：REF 重构模式

---

## §0 头部元数据

```yaml
id: REF-01
name: Domain 层 Flutter 依赖清理（A1-A6）
priority: P1
status: draft
created_at: 2026-07-27
last_updated: 2026-07-27
spec_anchored_files:
  - lib/features/settings/domain/settings_service.dart
  - lib/features/connection/domain/connection_service.dart
  - lib/features/player/domain/request_gate.dart
  - lib/features/player/domain/playback_orchestrator.dart
  - lib/features/player/domain/speed_manager.dart
  - lib/features/browser/domain/directory_service.dart
  - lib/core/contracts/storage_contract.dart
  - lib/core/contracts/audio_player_contract.dart
cross_module_impacts: [SET, CON, PLY, BRW]
parent_feature: null
manual_qa_required: false
```

---

## §1 用户视角

### 1.0 原始需求

> cr-2026-06-28 §1.1 + arch-baseline.txt：6 个 `lib/features/*/domain/` 文件 import 了 Flutter 或平台插件包，违反 "Domain 层零 Flutter 依赖" 架构规则。这些文件声称 "Pure Dart" 但实际上依赖 `flutter/material.dart`、`flutter_secure_storage`、`just_audio`、`shared_preferences`。arch-baseline.txt 已登记全部 6 条为 legacy debt。

### 1.1 这一功能干什么（一句话）

消除 Domain 层对 Flutter 框架和平台插件的直接依赖，通过 contract 抽象或类型迁移使 Domain 层成为可独立单元测试的纯 Dart 代码。

### 1.2 用户期望的场景

| ID | 你看到的样子 | 期望行为 |
|----|----|----|
| U1 | Domain 层文件 import 检查 | 6 个 domain 文件不再 import flutter/flutter_secure_storage/just_audio/shared_preferences |
| U2 | 测试运行 | 全部现有测试仍通过（接口等价变换，行为不变） |
| U3 | arch-baseline.txt 扫描 | 对应 6 条 domain-flutter 记录可删除 |

---

## §2 已实现的功能骨架

### 2.1 文件与分层

| 层 | 文件 | 行数 | 违规 import | 角色 |
|---|---|---|---|---|
| Domain | `lib/features/settings/domain/settings_service.dart` | 124 | `:10` flutter/material.dart (ThemeMode) | 设置读写 |
| Domain | `lib/features/connection/domain/connection_service.dart` | 111 | `:12` flutter_secure_storage | 连接 CRUD |
| Domain | `lib/features/player/domain/request_gate.dart` | 203 | `:15` just_audio (AudioPlayer, TrackLoadResult) | 请求序列化 |
| Domain | `lib/features/player/domain/playback_orchestrator.dart` | 468 | `:24` just_audio (AudioPlayer, ProcessingState) | 播放编排 |
| Domain | `lib/features/player/domain/speed_manager.dart` | 52 | `:15` shared_preferences | 速度/步长读取 |
| Domain | `lib/features/browser/domain/directory_service.dart` | 213 | `:6` shared_preferences | 目录加载/缓存 |
| Contract | `lib/core/contracts/storage_contract.dart` | 25 | — | ISecureStorage 已存在 |
| Contract | `lib/core/contracts/audio_player_contract.dart` | 74 | — | IAudioPlayer 已存在 |

### 2.2 违规详情

| 编号 | 文件:行 | import | 使用的类型 | 修复策略 |
|---|---|---|---|---|
| A1 | `settings_service.dart:10` | `flutter/material.dart` | `ThemeMode` 枚举 | Domain 用 `String` 表示 theme mode，boundary 映射到 `ThemeMode` |
| A2 | `connection_service.dart:12` | `flutter_secure_storage` | `FlutterSecureStorage` 具体类 | 注入已有的 `ISecureStorage`（`storage_contract.dart:13`） |
| A3 | `request_gate.dart:15` | `just_audio` | `AudioPlayer`（在 TrackLoadResult:95） | TrackLoadResult 移除 AudioPlayer 字段，改用泛型或 contract 类型 |
| A4 | `playback_orchestrator.dart:24` | `just_audio` | `AudioPlayer`、`ProcessingState` | 构造函数接受 `IAudioPlayer`；`ProcessingState` 用 domain 枚举替代或从 contract 重导出 |
| A5 | `speed_manager.dart:15` | `shared_preferences` | `SharedPreferences` 参数 | 注入 `ISettingsReader` 抽象接口，或让调用方传入已解析的值 |
| A6 | `directory_service.dart:6` | `shared_preferences` | `SharedPreferences`（在 SortOptionNotifier:27） | SortOptionNotifier 接受一个 settings reader 抽象，或把持久化移出 domain |

---

## §3 行为规约

### 3.1 A1 — settings_service ThemeMode 解耦

- **[REF-01-S1]** settings_service 不再 import flutter/material.dart (`status: new`)
  ```
  Given settings_service.dart 的 import 列表
  When  静态分析
  Then  不包含 package:flutter/material.dart
  否定断言:
    - 不在 domain 层出现 ThemeMode 枚举的直接引用（改为 String 表示）
    - 不改变 getThemeMode/setThemeMode 的外部行为（存储 key 不变、默认值不变）
    - 不改变 labelForThemeMode 的输出（'跟随系统'/'亮色'/'暗色'）
  ```
  Code evidence: `lib/features/settings/domain/settings_service.dart:10`（import flutter/material.dart）、`:38-46`（getThemeMode 使用 ThemeMode.values）、`:51-53`（setThemeMode 使用 ThemeMode.name）、`:96-105`（labelForThemeMode 使用 ThemeMode 枚举）

  **修改指令 — `lib/features/settings/domain/settings_service.dart`**

  策略：Domain 层用 `String` 表示 theme mode（`'system'`/`'light'`/`'dark'`），`labelForThemeMode` 改为接受 `String`。boundary 映射（`settings_provider.dart`、`settings_screen.dart`）负责 `String ↔ ThemeMode` 转换。

  位置：`:1-11`（imports）

  当前代码（:10）：
  ```dart
  import 'package:flutter/material.dart';
  ```
  删除此行。

  位置：`:37-46`（getThemeMode）
  改为返回 `String`：
  ```dart
  String getThemeMode(SharedPreferences? prefs) {
    if (prefs == null) return 'system';
    return prefs.getString(_themeModeKey) ?? 'system';
  }
  ```

  位置：`:51-53`（setThemeMode）
  改为接受 `String`：
  ```dart
  void setThemeMode(SharedPreferences? prefs, String mode) {
    prefs?.setString(_themeModeKey, mode);
  }
  ```

  位置：`:96-105`（labelForThemeMode）
  改为接受 `String`：
  ```dart
  String labelForThemeMode(String mode) {
    switch (mode) {
      case 'light': return '亮色';
      case 'dark':  return '暗色';
      default:      return '跟随系统';
    }
  }
  ```

  **调用方适配（boundary 映射）：**

  `settings_provider.dart:29-36` — 添加 `String ↔ ThemeMode` 映射函数：
  ```dart
  ThemeMode getThemeMode(SharedPreferences? prefs) {
    final raw = _service.getThemeMode(prefs);
    return ThemeMode.values.cast<ThemeMode?>().firstWhere(
      (e) => e!.name == raw, orElse: () => ThemeMode.system)!;
  }
  void setThemeMode(SharedPreferences? prefs, ThemeMode mode) =>
      _service.setThemeMode(prefs, mode.name);
  String labelForThemeMode(ThemeMode mode) => _service.labelForThemeMode(mode.name);
  ```

- **[REF-01-S2]** settings_provider ThemeMode 映射正确性 (`status: new`)
  ```
  Given settings_service 存储了 'dark'
  When  settings_provider.getThemeMode(prefs) 被调用
  Then  返回 ThemeMode.dark
  否定断言:
    - 不在 domain 层保留 ThemeMode 类型引用
    - 不丢失已存储的 theme mode（存储 key 和值格式不变）
    - 不改变 themeModeProvider 的默认值（ThemeMode.system）
  ```
  Code evidence: `lib/features/settings/settings_provider.dart:29-30`、`:44-47`

### 3.2 A2 — connection_service FlutterSecureStorage → ISecureStorage

- **[REF-01-S3]** connection_service 不再 import flutter_secure_storage (`status: new`)
  ```
  Given connection_service.dart 的 import 列表
  When  静态分析
  Then  不包含 package:flutter_secure_storage/flutter_secure_storage.dart
  And   ConnectionService 构造函数接受 ISecureStorage（而非 FlutterSecureStorage）
  否定断言:
    - 不在 domain 层出现 FlutterSecureStorage 具体类型引用
    - 不改变 save/update/delete/setActive 的外部行为
    - 不改变密码存储 key 格式（connection_password_{id}）
  ```
  Code evidence: `lib/features/connection/domain/connection_service.dart:12`（import）、`:24`（`final FlutterSecureStorage _storage`）、`:26`（构造函数参数）

  **修改指令 — `lib/features/connection/domain/connection_service.dart`**

  位置：`:12`
  删除 `import 'package:flutter_secure_storage/flutter_secure_storage.dart';`
  添加 `import '../../../core/contracts/storage_contract.dart';`

  位置：`:24`
  当前：`final FlutterSecureStorage _storage;`
  改为：`final ISecureStorage _storage;`

  位置：`:26`
  当前：`ConnectionService(this._dao, this._storage);`
  签名不变（参数类型已改为 ISecureStorage）。

  注意：`safeStorageWrite`/`safeStorageDelete`（`storage_utils.dart`）接受 `FlutterSecureStorage`，需改为接受 `ISecureStorage` 或调用 `_storage.write()`/`_storage.delete()` 直接。

  **调用方适配：**

  `connection_provider.dart:29` — `secureStorageProvider` 返回类型改为 `ISecureStorage`：
  ```dart
  final secureStorageProvider = Provider<ISecureStorage>((ref) => const FlutterSecureStorageAdapter());
  ```
  需新增 `FlutterSecureStorageAdapter implements ISecureStorage`（在 `connection_provider.dart` 或 `core/services/`）。

- **[REF-01-S4]** secureStorageProvider 返回 ISecureStorage (`status: new`)
  ```
  Given secureStorageProvider 在 Riverpod 容器中
  When  ref.read(secureStorageProvider)
  Then  返回类型为 ISecureStorage
  And   运行时实例为 FlutterSecureStorage 的适配器
  否定断言:
    - 不在 provider 层暴露 FlutterSecureStorage 具体类型（除适配器构造处）
    - 不改变 safeStorageRead/safeStorageWrite/safeStorageDelete 的行为
  ```
  Code evidence: `lib/features/connection/connection_provider.dart:28-29`

### 3.3 A3 — request_gate just_audio 解耦

- **[REF-01-S5]** request_gate 不再 import just_audio (`status: new`)
  ```
  Given request_gate.dart 的 import 列表
  When  静态分析
  Then  不包含 package:just_audio/just_audio.dart
  否定断言:
    - 不在 TrackLoadResult 中持有 AudioPlayer 引用（当前 :95 `final AudioPlayer? player`）
    - 不改变 PlayerLoadState / PlayerLoadStatus / TrackLoadStatus 的语义
    - 不改变 SerializedRequestGate 的调度逻辑
  ```
  Code evidence: `lib/features/player/domain/request_gate.dart:15`（import）、`:95`（`final AudioPlayer? player`）、`:99-100`（`TrackLoadResult.loaded(AudioPlayer player)`）

  **修改指令 — `lib/features/player/domain/request_gate.dart`**

  策略：TrackLoadResult 移除 `AudioPlayer` 字段。loaded 状态只需标记成功（player 引用由调用方持有）。

  位置：`:15`
  删除 `import 'package:just_audio/just_audio.dart';`

  位置：`:93-108`（TrackLoadResult）
  当前代码：
  ```dart
  class TrackLoadResult {
    final TrackLoadStatus status;
    final AudioPlayer? player;
    const TrackLoadResult._(this.status, this.player);
    const TrackLoadResult.loaded(AudioPlayer player) : this._(TrackLoadStatus.loaded, player);
    const TrackLoadResult.failed() : this._(TrackLoadStatus.failed, null);
    const TrackLoadResult.superseded() : this._(TrackLoadStatus.superseded, null);
    bool get isLoaded => status == TrackLoadStatus.loaded && player != null;
    bool get isSuperseded => status == TrackLoadStatus.superseded;
  }
  ```
  改为：
  ```dart
  class TrackLoadResult {
    final TrackLoadStatus status;
    const TrackLoadResult._(this.status);
    const TrackLoadResult.loaded() : this._(TrackLoadStatus.loaded);
    const TrackLoadResult.failed() : this._(TrackLoadStatus.failed);
    const TrackLoadResult.superseded() : this._(TrackLoadStatus.superseded);
    bool get isLoaded => status == TrackLoadStatus.loaded;
    bool get isSuperseded => status == TrackLoadStatus.superseded;
  }
  ```

  **调用方适配：**

  `playback_orchestrator.dart:237` — `TrackLoadResult.loaded(player)` → `const TrackLoadResult.loaded()`
  `player_provider.dart` 等消费方 — 移除对 `TrackLoadResult.player` 的访问（如有）。

### 3.4 A4 — playback_orchestrator just_audio 解耦

- **[REF-01-S6]** playback_orchestrator 不再直接 import just_audio (`status: new`)
  ```
  Given playback_orchestrator.dart 的 import 列表
  When  静态分析
  Then  不包含 package:just_audio/just_audio.dart
  And   构造函数 player 参数类型为 IAudioPlayer（来自 audio_player_contract.dart）
  否定断言:
    - 不在 domain 层使用 AudioPlayer 具体类型（当前 :83 `final AudioPlayer player`）
    - 不在 domain 层使用 ProcessingState 枚举（当前 :393 `ProcessingState.completed`）
    - 不改变 loadAndPlay/skipToNext/skipToPrevious/saveProgress 的外部行为
  ```
  Code evidence: `lib/features/player/domain/playback_orchestrator.dart:24`（import）、`:83`（`final AudioPlayer player`）、`:114`（`StreamSubscription<ProcessingState>`）、`:393`（`ProcessingState.completed`）

  **修改指令 — `lib/features/player/domain/playback_orchestrator.dart`**

  策略：
  1. 构造函数 `player` 类型改为 `IAudioPlayer`（`core/contracts/audio_player_contract.dart`）
  2. `ProcessingState` 引用改为 domain 层等价处理——`IAudioPlayer.processingStateStream` 返回 just_audio 的 `ProcessingState`，需要在 contract 层定义 domain 枚举或在 contract 中重导出。

  位置：`:24`
  当前：`import 'package:just_audio/just_audio.dart';`
  改为：`import '../../../core/contracts/audio_player_contract.dart';`

  位置：`:83`
  当前：`final AudioPlayer player;`
  改为：`final IAudioPlayer player;`

  位置：`:114`
  当前：`StreamSubscription<ProcessingState>? _processingSub;`
  — `IAudioPlayer.processingStateStream` 类型由 contract 决定。若 contract 保留 just_audio 的 `ProcessingState`（`audio_player_contract.dart:30`），则此处仍需 import。

  裁决：`IAudioPlayer` contract 自身仍 import just_audio（`audio_player_contract.dart:10`），这是 contract 层的合理依赖。Domain 层通过 contract 间接依赖是可接受的——关键是 domain 不直接 import just_audio。若需彻底清除，需在 contract 层定义 domain 枚举 `DomainProcessingState` 并在 adapter 映射。

  保守方案：`playback_orchestrator` 通过 `IAudioPlayer.processingStateStream` 获取流，但比较值时使用 `IAudioPlayer` 暴露的 contract 类型。由于 `audio_player_contract.dart` 已 import just_audio，`playback_orchestrator` import contract 即可（不直接 import just_audio）。

  位置：`:393`
  当前：`if (state == ProcessingState.completed)`
  若 contract 仍使用 just_audio 的 ProcessingState，此行不变但来源从 `just_audio` 变为 `audio_player_contract.dart` 的重导出。

- **[REF-01-S7]** IAudioPlayer contract 保持 just_audio 桥接 (`status: new`)
  ```
  Given audio_player_contract.dart 是 contract 层
  When  静态分析
  Then  允许 import just_audio（contract 层是 platform 桥接的合法位置）
  And   playback_orchestrator.dart 不直接 import just_audio
  否定断言:
    - 不在 playback_orchestrator.dart 出现 `import 'package:just_audio` 字符串
    - 不改变 IAudioPlayer 接口的方法签名
  ```
  Code evidence: `lib/core/contracts/audio_player_contract.dart:10`（contract 层允许依赖 just_audio）

### 3.5 A5 — speed_manager SharedPreferences 解耦

- **[REF-01-S8]** speed_manager 不再 import shared_preferences (`status: new`)
  ```
  Given speed_manager.dart 的 import 列表
  When  静态分析
  Then  不包含 package:shared_preferences/shared_preferences.dart
  否定断言:
    - 不在 domain 层函数签名中出现 SharedPreferences 参数（当前 :40 `getDefaultSpeed(SharedPreferences? prefs)`、`:49` `readSeekStep(SharedPreferences? prefs)`）
    - 不改变 speedOptions / isValidSpeed 的纯函数行为
    - 不改变 getDefaultSpeed 和 readSeekStep 的返回值语义
  ```
  Code evidence: `lib/features/player/domain/speed_manager.dart:15`（import）、`:40-44`（getDefaultSpeed 参数）、`:49-52`（readSeekStep 参数）

  **修改指令 — `lib/features/player/domain/speed_manager.dart`**

  策略：引入 `ISettingsReader` 抽象（或在调用方解析后传入原始值）。最小改动：把 `getDefaultSpeed` 和 `readSeekStep` 改为接受 domain 层抽象的 reader。

  方案 A（推荐）：函数改为接受 `Map<String, dynamic>?` 或 domain 层 `SettingsReader` 接口。
  方案 B（最小改动）：删除这两个函数，由调用方直接从 SharedPreferences 读取——speed_manager 只保留纯函数 `isValidSpeed` 和常量 `speedOptions`/`defaultSpeedKey`/`seekStepPrefsKey`/`defaultSeekStep`。

  采用方案 B：speed_manager 只导出纯函数和常量，读取逻辑上移到 provider 层（`player_provider.dart:122-123`、`:137-138` 已在做这个读取）。

  位置：`:15`
  删除 `import 'package:shared_preferences/shared_preferences.dart';`

  位置：`:40-44`（getDefaultSpeed）和 `:49-52`（readSeekStep）
  删除这两个函数。调用方已在 `player_provider.dart` 和 `settings_provider.dart` 直接读取。

### 3.6 A6 — directory_service SharedPreferences 解耦

- **[REF-01-S9]** directory_service 不再 import shared_preferences (`status: new`)
  ```
  Given directory_service.dart 的 import 列表
  When  静态分析
  Then  不包含 package:shared_preferences/shared_preferences.dart
  否定断言:
    - 不在 SortOptionNotifier 构造函数中接受 SharedPreferences 参数（当前 :27 `final SharedPreferences? _prefs`）
    - 不改变 SortOption 枚举的语义和 sortFiles 的排序行为
    - 不改变 DirectoryService 的 loadDirectory/resortCached/clearCache 行为
  ```
  Code evidence: `lib/features/browser/domain/directory_service.dart:6`（import）、`:27`（`final SharedPreferences? _prefs`）、`:28-43`（SortOptionNotifier 使用 SharedPreferences 持久化 sort option）

  **修改指令 — `lib/features/browser/domain/directory_service.dart`**

  策略：SortOptionNotifier 的持久化职责移到 provider 层。domain 层 SortOptionNotifier 只管理当前值，不接受 SharedPreferences。provider 层 watch SortOptionNotifier 变化并持久化。

  替代方案：引入 `ISettingsWriter` 接口注入。

  采用替代方案（保持当前架构风格）：

  位置：`:6`
  删除 `import 'package:shared_preferences/shared_preferences.dart';`

  定义一个 domain 层的抽象：
  ```dart
  abstract class ISortOptionPersist {
    String? readSortOption();
    void writeSortOption(String name);
  }
  ```

  位置：`:26-44`（SortOptionNotifier）
  改为接受 `ISortOptionPersist?` 替代 `SharedPreferences?`。

---

## §4 不变量

- **[REF-01-INV1]** Domain 层 6 个文件无 Flutter/平台插件 import
  证据：`settings_service.dart`、`connection_service.dart`、`request_gate.dart`、`playback_orchestrator.dart`、`speed_manager.dart`、`directory_service.dart` 的 import 列表均不含 flutter/flutter_secure_storage/just_audio/shared_preferences

- **[REF-01-INV2]** arch-baseline.txt 6 条 domain-flutter 记录已删除
  证据：`docs/dev/arch-baseline.txt` 不再包含这 6 个文件的条目

- **[REF-01-INV3]** 全部现有测试通过
  证据：`flutter test` 退出码 0

---

## §5 测试规约

### 5.1 现有测试清单

| 测试文件 | 覆盖 | 备注 |
|---|---|---|
| `test/features/settings/` | settings 功能 | 可能需要适配 ThemeMode 类型变更 |
| `test/features/connection/` | connection 功能 | 可能需要适配 ISecureStorage 注入 |
| `test/features/player/` | player 功能 | 可能需要适配 TrackLoadResult 签名 |
| `test/features/browser/` | browser 功能 | 可能需要适配 SortOptionNotifier 参数 |
| `test/helpers/fake_secure_storage.dart` | fake | 需改为 implements ISecureStorage |
| `test/helpers/mock_audio_player.dart` | mock | 已 extends Mock implements AudioPlayer，需额外 implements IAudioPlayer |

### 5.2 测试 ID 派生清单

```
REF-01-S1 … S9        # Scenario
REF-01-INV1 … INV3    # 不变量
```

### 5.3 测试覆盖盲点

| 未覆盖 ID | 现状 | 应补偿方式 |
|---|---|---|
| REF-01-S1 | 无静态检查验证 domain 层无 flutter import | `flutter analyze` + grep import 列表 |
| REF-01-S3 | ConnectionService 构造函数签名变更 | 现有 connection 测试用 FakeSecureStorage 需适配 ISecureStorage |
| REF-01-S5 | TrackLoadResult 移除 player 字段 | 检查所有消费 `TrackLoadResult.player` 的测试 |

### 5.4 测试文件位置

| 测试 ID | 文件路径 |
|---|---|
| REF-01-S1/S2 | `test/features/settings/settings_test.dart`（ThemeMode→String 适配 + provider 映射用例） |
| REF-01-S3/S4 | `test/features/connection/ref_22_test.dart`（ISecureStorage 注入适配） |
| REF-01-S5/S6/S7 | `test/features/player/ply_02_test.dart`（TrackLoadResult 去 player 字段 + IAudioPlayer 适配） |
| REF-01-S8 | `test/features/settings/settings_test.dart`（speed 直读 prefs 适配） |
| REF-01-S9 | `test/features/browser/brw_07_test.dart`（SortOptionNotifier 参数适配） |
| helpers | `test/helpers/fake_secure_storage.dart`（implements ISecureStorage） |
| helpers | `test/helpers/mock_audio_player.dart`（额外 implements IAudioPlayer） |
| REF-01-INV1/INV2 | `test/features/coverage/ref_01_domain_pure_test.dart`（新建：静态断言 6 个 domain 文件无违规 import） |

---

## §6 算法样例

不适用——本重构为依赖解耦，无新算法。

---

## §7 跨模块影响

| 其它 feature | 影响点 | 需要补的回归断言 |
|---|---|---|
| SET | `settings_service.dart` ThemeMode→String | settings_screen 显示主题标签不变 |
| CON | `connection_service.dart` ISecureStorage 注入 | save/update/delete 密码读写不变 |
| PLY | `request_gate.dart` TrackLoadResult 无 player | loadAndPlay 返回值语义不变 |
| PLY | `playback_orchestrator.dart` IAudioPlayer | 播放/暂停/seek 行为不变 |
| PLY | `speed_manager.dart` 删除 getDefaultSpeed/readSeekStep | player_provider 直接读 prefs 行为不变 |
| BRW | `directory_service.dart` SortOptionNotifier 参数变更 | 排序持久化行为不变 |

---

## §8 平台特性与手动 QA

本功能不涉及平台原生特性，全部可在 `flutter test` 中验证。

---

## §9 dev-status.json 条目对照

见统一更新：`docs/dev/dev-status.json`。

---

## §10 changelog

- 2026-07-27: 创建 REF-01 spec（基于 cr-2026-06-28 §1.1 + arch-baseline.txt A1-A6）
- 2026-08-06: dev-plan 修订——补 §5.4「测试文件位置」门禁节（spec-scan --gate 硬门禁前置，af084af 引入）；§5.4 测试文件与现有引用面核对：ref_22_test（ConnectionService 注入）、ply_02_test（RequestGate/播放编排）、brw_07_test（SortOption）、settings_test（ThemeMode/speed）
