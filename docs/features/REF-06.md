# REF-06 — 浏览器死代码（BRW6+BRW7）

> 来源：`docs/cr/cr-20260724-0110.md` BRW6 + BRW7
> dev-plan 流程：Refactoring 模式

---

## §0 头部元数据

```yaml
id: REF-06
name: 浏览器死代码（BRW6+BRW7）
priority: P2
status: draft
created_at: 2026-07-27
last_updated: 2026-07-27
spec_anchored_files:
  - lib/features/browser/browser_provider.dart
  - lib/features/browser/domain/directory_service.dart
  - lib/features/browser/widgets/file_list_item.dart
cross_module_impacts: []
parent_feature: Browser
manual_qa_required: false
```

---

## §1 用户视角

### 1.0 原始需求

> cr-20260724-0110.md BRW6：`browser_provider.dart:64-97` inlines directory loading/filtering/caching logic that duplicates `domain/directory_service.dart:95-157`. DirectoryService has zero production callers (only ref_19_test). Two copies currently identical but drifting risk.
> cr-20260724-0110.md BRW7：`file_list_item.dart:56,128-143` — progressPercentage parameter renders LinearProgressIndicator when non-null, but no production caller passes a value. Dead wire.

### 1.1 这一功能干什么（一句话）

消除浏览器模块中重复的目录加载逻辑和未接线的进度条参数。

### 1.2 用户期望的场景

| ID | 你看到的样子 | 期望行为 |
|----|----|----|
| U1 | 浏览文件目录 | 功能不变（目录加载、缓存、排序正常） |
| U2 | 文件列表项 | 无进度条显示（当前行为不变，因为 progressPercentage 从未传入） |

---

## §2 已实现的功能骨架

### 2.1 文件与分层

| 层 | 文件 | 行数 | 角色 |
|---|---|---|---|
| Provider | `lib/features/browser/browser_provider.dart` | 195 | directoryContentsProvider 内联加载/过滤/缓存 |
| Domain | `lib/features/browser/domain/directory_service.dart` | 213 | DirectoryService 类（零生产调用者） |
| UI | `lib/features/browser/widgets/file_list_item.dart` | 145 | AudioFileListTile + progressPercentage 死参数 |
| Caller | `lib/features/browser/browser_screen.dart:362` | — | 唯一 AudioFileListTile 生产调用点 |
| 测试 | `test/features/browser/ref_19_test.dart` | — | DirectoryService 唯一测试用户 |

### 2.2 关键代码段

| 区域 | 行号 | 说明 |
|---|---|---|
| provider 内联加载 | `browser_provider.dart:64-102` | directoryContentsProvider 完整逻辑 |
| DirectoryService.loadDirectory | `directory_service.dart:95-157` | 与 provider 重复的逻辑 |
| DirectoryService.sortFiles | `directory_service.dart:192-212` | 静态方法，provider :23-24 仍调用 |
| progressPercentage 参数 | `file_list_item.dart:56` | double? 字段声明 |
| progressPercentage 渲染分支 | `file_list_item.dart:128-143` | LinearProgressIndicator |
| 唯一生产调用点 | `browser_screen.dart:362-372` | 未传 progressPercentage |

---

## §3 行为规约

### 3.1 BRW6 — DirectoryService 去留裁决

- **[REF-06-S1]** 删除 DirectoryService 类，保留 SortOption / SortOptionNotifier / sortFiles (`status: new`)
  ```
  Given DirectoryService 在 lib/ 中零生产调用者（仅 ref_19_test 使用）
  And   browser_provider.dart:64-102 内联了完全相同的加载/过滤/缓存逻辑
  When  删除 DirectoryService 类
  Then  directory_service.dart 仅保留 SortOption、SortOptionNotifier、ISecurePasswordReader、DirectoryResult、sortFiles 静态方法
  And   ref_19_test 中测试 DirectoryService 实例的用例需删除
  And   ref_19_test 中测试 sortFiles 的用例保留（静态方法仍存在）
  否定断言:
    - 不删除 SortOption 枚举（provider.dart:28-30 + browser_provider 使用）
    - 不删除 SortOptionNotifier（browser_provider.dart:28-30 使用）
    - 不删除 DirectoryService.sortFiles 静态方法（browser_provider.dart:23-24 调用）
    - 不删除 ISecurePasswordReader（sortFiles 独立，无外部依赖变化）
    - 不改变 directoryContentsProvider 的行为（保持内联实现不变）
    - 不改变 CachePolicy / directoryCacheProvider / clearDirectoryCacheProvider 的行为
  ```
  Code evidence: `lib/features/browser/domain/directory_service.dart:69-183`（DirectoryService 类）；`lib/features/browser/browser_provider.dart:64-102`（内联重复）；grep 确认 lib/ 零生产调用

  **修改指令 — `lib/features/browser/domain/directory_service.dart`**

  位置：`:46-183`

  删除以下类/定义：
  - `ISecurePasswordReader` 抽象类（:46-51）— 仅被 DirectoryService 使用
  - `DirectoryResult` 类（:53-63）— 仅被 DirectoryService 使用
  - `DirectoryService` 类（:65-213）整个类 — 但保留 `sortFiles` 静态方法

  具体操作：删除 :46-63（ISecurePasswordReader + DirectoryResult）和 :65-183（DirectoryService 类含 loadDirectory / resortCached / clearCache）。保留 :14-44（SortOption + SortOptionNotifier）和 :185-213（sortFiles 静态方法，从 DirectoryService 中提取为顶层函数或保留为独立工具类）。

  将 `sortFiles` 提取为顶层函数：
  ```dart
  /// Returns a new list sorted according to [option].
  ///
  /// Directories always appear before files regardless of the sort option
  /// (BRW-T42).  Within each group entries are ordered by the selected
  /// criterion.
  List<NasFile> sortFiles(List<NasFile> files, SortOption option) {
    // ... (same body as DirectoryService.sortFiles)
  }
  ```

  **修改指令 — `lib/features/browser/browser_provider.dart`**

  位置：`:23-24`

  当前代码：
  ```dart
  List<NasFile> sortFiles(List<NasFile> files, SortOption option) =>
      DirectoryService.sortFiles(files, option);
  ```
  改为：
  ```dart
  // sortFiles is now a top-level function in directory_service.dart
  ```
  并删除此 wrapper。`browser_provider.dart:97` 处对 `sortFiles` 的调用直接引用同名顶层函数即可（已 import directory_service.dart）。

  **修改指令 — `lib/features/browser/browser_provider.dart`**

  位置：`:19`

  当前代码：
  ```dart
  export 'domain/directory_service.dart' show SortOption, SortOptionNotifier;
  ```
  改为：
  ```dart
  export 'domain/directory_service.dart' show SortOption, SortOptionNotifier, sortFiles;
  ```

### 3.2 BRW7 — progressPercentage 死参数

- **[REF-06-S2]** 删除 AudioFileListTile 的 progressPercentage 参数及渲染分支 (`status: new`)
  ```
  Given progressPercentage 在 lib/ 中无生产调用者传入值
  And   BUG-12 (2026-07-24) 已移除 progressRegistry
  When  删除 progressPercentage 参数
  Then  AudioFileListTile 构造函数不再接受 progressPercentage
  And   LinearProgressIndicator 渲染分支被删除
  否定断言:
    - 不改变 AudioFileListTile 的其它参数（file / onTap / onLongPress / onPlayNext / playNextEnabled）
    - 不改变 DirectoryListTile 的行为
    - 不改变 browser_screen.dart:362-372 的调用（本身未传 progressPercentage，无需改）
  ```
  Code evidence: `lib/features/browser/widgets/file_list_item.dart:56`（参数声明）；`:128-143`（渲染分支）；`browser_screen.dart:362-372`（唯一生产调用，未传 progressPercentage）

  **修改指令 — `lib/features/browser/widgets/file_list_item.dart`**

  位置：`:50-68`（构造函数参数区）

  当前代码（:56, :65）：
  ```dart
    final double? progressPercentage;
  ```
  和：
  ```dart
    this.progressPercentage,
  ```
  删除以上两行。

  位置：`:128-143`（渲染分支）

  当前代码：
  ```dart
      if (progressPercentage == null) return tile;

      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          tile,
          Padding(
            padding: const EdgeInsets.only(left: 72, right: 16),
            child: LinearProgressIndicator(
              value: progressPercentage,
              minHeight: 2,
              backgroundColor: Colors.grey.shade200,
            ),
          ),
        ],
      );
  ```
  改为：
  ```dart
      return tile;
  ```

  同时删除 :49-51 的文档注释中 progressPercentage 相关描述：
  ```dart
  /// When [progressPercentage] is non-null, a thin progress bar is shown
  /// at the bottom of the tile to indicate playback progress (BRW-T47).
  ```

---

## §4 不变量

- **[REF-06-INV1]** 目录加载逻辑仅存在于 browser_provider.dart
  证据：DirectoryService 类删除后，`browser_provider.dart:64-102` 是唯一实现

- **[REF-06-INV2]** AudioFileListTile 无 progressPercentage 参数
  证据：删除后 `file_list_item.dart` 中无 progressPercentage 字段

- **[REF-06-INV3]** SortOption / SortOptionNotifier / sortFiles 仍可正常导出
  证据：`browser_provider.dart:19` export 包含 SortOption, SortOptionNotifier, sortFiles

---

## §5 测试规约

### 5.1 现有测试清单

| 测试文件 | 覆盖 | 备注 |
|---|---|---|
| `test/features/browser/ref_19_test.dart` | DirectoryService 类测试 | 删除 DirectoryService 实例相关用例；保留 sortFiles 用例 |
| `test/features/browser/brw_03_test.dart:201-245` | progressPercentage 测试 | 需删除 BRW-T47 相关用例 |
| `test/features/browser/brw_07_test.dart:280` | progressPercentage null 测试 | 需删除对应用例 |

### 5.2 测试 ID 派生清单

```
REF-06-S1           # 删除 DirectoryService 类
REF-06-S2           # 删除 progressPercentage
REF-06-INV1         # 目录加载唯一实现
REF-06-INV2         # 无 progressPercentage
REF-06-INV3         # SortOption 导出完整
```

### 5.3 测试覆盖盲点

| 未覆盖 ID | 现状 | 应补偿方式 |
|---|---|---|
| REF-06-S1 | ref_19_test 中 sortFiles 用例需迁移到测试顶层函数 | 修改 ref_19_test：删除 DirectoryService 实例用例，保留 sortFiles 用例并改为调用顶层函数 |
| REF-06-S2 | brw_03_test 中 BRW-T47 用例需删除 | 删除 progressPercentage 相关测试用例 |

### 5.4 测试文件位置

| 测试 ID | 文件路径 |
|---|---|
| REF-06-S1 | `test/features/browser/ref_19_test.dart`（删除 DirectoryService 实例用例，sortFiles 用例改调顶层函数） |
| REF-06-S2 | `test/features/browser/brw_03_test.dart`（删除 BRW-T47 :201-245） |
| REF-06-S2 | `test/features/browser/brw_07_test.dart`（删除 progressPercentage null 用例 :280） |

---

## §6 算法样例

不适用——本重构为删除死代码，无新算法。`sortFiles` 算法不变。

---

## §7 跨模块影响

| 其它 feature | 影响点 | 需要补的回归断言 |
|---|---|---|
| 无 | — | 仅影响 Browser 模块内部 |

---

## §8 平台特性与手动 QA

本功能不涉及平台原生特性，全部可在 `flutter test` 中验证。

---

## §9 dev-status.json 条目对照

见统一更新：`docs/dev/dev-status.json`。

---

## §10 changelog

- 2026-07-27: 创建 REF-06 spec（基于 cr-20260724-0110.md BRW6 + BRW7）
- 2026-08-06: dev-plan 修订——补 §5.4「测试文件位置」门禁节（spec-scan --gate 硬门禁前置，af084af 引入）；门禁文件按 §5.1 现状表映射：ref_19_test / brw_03_test / brw_07_test
