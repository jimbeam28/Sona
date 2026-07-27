# BUG-31 — 浏览器 UI 与可测性（BRW5+BRW8）

> 来源：`docs/cr/cr-20260724-0110.md` BRW5 (line 99-104) + BRW8 (line 84-88)
> dev-plan 流程：Bug 修复模式

---

## §0 头部元数据

```yaml
id: BUG-31
name: 浏览器 UI 与可测性（BRW5+BRW8）
priority: P2
status: draft
created_at: 2026-07-27
last_updated: 2026-07-27
spec_anchored_files:
  - lib/features/browser/browser_screen.dart
  - lib/features/browser/browser_provider.dart
  - lib/features/browser/domain/directory_service.dart
cross_module_impacts: [BRW]
parent_feature: Browser
manual_qa_required: false
```

---

## §1 用户视角

### 1.0 原始需求

> cr-20260724-0110.md BRW5：`browser_screen.dart:342-363` — `DirectoryListTile`/`AudioFileListTile` 支持 `super.key` 但调用方从未传入。违反 P13（始终使用业务 ID 的 ValueKey）。列表替换（下拉刷新）或进度条接线时，按位置复用元素导致动画/状态错配。
> cr-20260724-0110.md BRW8：`directory_service.dart:103,171`、`browser_provider.dart:72,75,95` — 硬编码 `DateTime.now()`。`CachePolicy.isAlive(entry, now)` 接受注入时钟但上游硬编码。`ref_19_test` 使用 1ms TTL + 真实 `Future.delayed(50ms)` 测试过期（CI 抖动风险）。

### 1.1 这一功能干什么（一句话）

为文件列表项添加 `ValueKey` 并注入可测试时钟，消除 UI 复用错配和测试中的真实时间依赖。

### 1.2 用户期望的场景

| ID | 你看到的样子 | 期望行为 |
|----|----|----|
| U1 | 下拉刷新后列表重建 | 每个 tile 按 path 匹配复用（非按位置），动画正确 |
| U2 | 进度条显示在同一文件上 | 进度条不因列表重建错位到其他文件 |
| U3 | 测试缓存过期 | 使用注入时钟，不依赖真实时间流逝（消除 CI 抖动） |

---

## §2 已实现的功能骨架

### 2.1 文件与分层

| 层 | 文件 | 行数 | 角色 |
|---|---|---|---|
| UI | `lib/features/browser/browser_screen.dart` | 376 | 文件列表 + tile 渲染 |
| UI Widget | `lib/features/browser/widgets/file_list_item.dart` | 145 | DirectoryListTile / AudioFileListTile |
| Provider | `lib/features/browser/browser_provider.dart` | 195 | directoryContentsProvider + 缓存逻辑 |
| Domain | `lib/features/browser/domain/directory_service.dart` | 213 | 目录加载/缓存/排序 |
| Domain | `lib/features/browser/domain/cache_policy.dart` | 102 | TTL + LRU（`isAlive` 接受注入时钟） |

### 2.2 关键代码段

| 区域 | 行号 | 说明 |
|---|---|---|
| _FileList 构建 DirectoryListTile | `browser_screen.dart:355` | `DirectoryListTile(file: file, ...)` — 无 key |
| _FileList 构建 AudioFileListTile | `browser_screen.dart:362` | `AudioFileListTile(file: file, ...)` — 无 key |
| DirectoryListTile 支持 super.key | `file_list_item.dart:22` | `const DirectoryListTile({super.key, ...})` |
| AudioFileListTile 支持 super.key | `file_list_item.dart:61` | `const AudioFileListTile({super.key, ...})` |
| directoryContentsProvider 硬编码 now | `browser_provider.dart:72` | `CachePolicy.isAlive(cached, DateTime.now())` |
| directoryContentsProvider 硬编码 now | `browser_provider.dart:75` | `cached.accessedAt(DateTime.now())` |
| directoryContentsProvider 硬编码 now | `browser_provider.dart:100` | `CacheEntry(..., createdAt: DateTime.now())` |
| DirectoryService.loadDirectory 硬编码 now | `directory_service.dart:103` | `final now = DateTime.now()` |
| DirectoryService.resortCached 硬编码 now | `directory_service.dart:171` | `_cachePolicy.isAlive(entry, DateTime.now())` |
| CachePolicy.isAlive 接受注入 now | `cache_policy.dart:61` | `bool isAlive(CacheEntry<V> entry, DateTime now)` — 可注入 |

---

## §3 行为规约

### 3.1 修复后行为

- **[BUG-31-S1]** 文件列表项使用 `ValueKey(file.path)` (`status: new`)
  ```
  Given _FileList 渲染包含 NasFile(path:'/music/a.mp3') 的列表
  When  ListView.separated 构建 DirectoryListTile 和 AudioFileListTile
  Then  每个 tile 的 key 为 ValueKey(file.path)
  否定断言:
    - 不在无 key 的情况下构建 tile（当前 BUG：按位置复用）
    - 不改变 tile 的视觉外观和功能行为（仅添加 key）
    - 不在下拉刷新后导致进度条错位到其他文件
  ```
  Code evidence: `lib/features/browser/browser_screen.dart:355,362`（无 key 传入）
  对照：`lib/features/browser/widgets/file_list_item.dart:22,61`（已支持 `super.key`）

  **修改指令 — `lib/features/browser/browser_screen.dart`（_FileList.build）**

  位置：`:352-373`

  当前代码（:354-361）：
  ```dart
        if (file.isDirectory) {
          return DirectoryListTile(
            file: file,
            onTap: onDirectoryTap != null
                ? (_) => onDirectoryTap!(file.path)
                : null,
          );
        }
  ```

  改为：
  ```dart
        if (file.isDirectory) {
          return DirectoryListTile(
            key: ValueKey(file.path),
            file: file,
            onTap: onDirectoryTap != null
                ? (_) => onDirectoryTap!(file.path)
                : null,
          );
        }
  ```

  当前代码（:362-373）：
  ```dart
        return AudioFileListTile(
          file: file,
          onTap: (_) {
            // ignore: discarded_futures
            onFileTap(file);
          },
          onLongPress:
              onFileLongPress != null ? () => onFileLongPress!(file) : null,
          onPlayNext: onPlayNext != null ? (_) => onPlayNext!(file) : null,
          playNextEnabled: playNextEnabled,
        );
  ```

  改为：
  ```dart
        return AudioFileListTile(
          key: ValueKey(file.path),
          file: file,
          onTap: (_) {
            // ignore: discarded_futures
            onFileTap(file);
          },
          onLongPress:
              onFileLongPress != null ? () => onFileLongPress!(file) : null,
          onPlayNext: onPlayNext != null ? (_) => onPlayNext!(file) : null,
          playNextEnabled: playNextEnabled,
        );
  ```

  边界裁决：
  - `file.path` 是唯一的（同一连接下每个文件/目录有唯一路径）
  - 跨连接 path 可能相同 → 但 `_FileList` 只在单个目录上下文中渲染，不会混合不同连接的文件
  - `ValueKey` 是 const-constructible → 不影响 ListView.separated 性能
  - 下拉刷新 → 列表替换 → Flutter 按 ValueKey 匹配 → 正确复用动画状态

- **[BUG-31-S2]** `DirectoryService` 接受注入时钟 (`status: new`)
  ```
  Given DirectoryService 使用注入时钟 `() => DateTime(2026, 1, 1, 12, 0, 0)`
  When  loadDirectory 检查缓存存活
  Then  使用注入时钟的当前时间（非 DateTime.now()）
  否定断言:
    - 不在 loadDirectory/resortCached 中硬编码 DateTime.now()（当前 BUG 行为）
    - 不改变默认行为（未注入时使用 DateTime.now）
    - 不改变 CachePolicy.isAlive 的 TTL 语义
  ```
  Code evidence: `lib/features/browser/domain/directory_service.dart:103,171`（硬编码 `DateTime.now()`）
  对照：`lib/features/browser/domain/cache_policy.dart:61`（`isAlive` 接受 `DateTime now` 参数）

  **修改指令 — `lib/features/browser/domain/directory_service.dart`（DirectoryService 构造函数）**

  位置：`:69-83`

  当前代码（:69-83）：
  ```dart
  class DirectoryService {
    final WebDavClientInterface _client;
    final ISecurePasswordReader _storage;
    final CachePolicy<List<NasFile>> _cachePolicy;

    final Map<String, CacheEntry<List<NasFile>>> _cache = {};

    DirectoryService({
      required WebDavClientInterface client,
      required ISecurePasswordReader storage,
      CachePolicy<List<NasFile>>? cachePolicy,
    })  : _client = client,
          _storage = storage,
          _cachePolicy = cachePolicy ?? const CachePolicy<List<NasFile>>();
  ```

  改为：
  ```dart
  class DirectoryService {
    final WebDavClientInterface _client;
    final ISecurePasswordReader _storage;
    final CachePolicy<List<NasFile>> _cachePolicy;
    final DateTime Function() _clock;

    final Map<String, CacheEntry<List<NasFile>>> _cache = {};

    DirectoryService({
      required WebDavClientInterface client,
      required ISecurePasswordReader storage,
      CachePolicy<List<NasFile>>? cachePolicy,
      DateTime Function()? clock,
    })  : _client = client,
          _storage = storage,
          _cachePolicy = cachePolicy ?? const CachePolicy<List<NasFile>>(),
          _clock = clock ?? DateTime.now;
  ```

  位置：`:103`
  当前代码：
  ```dart
    final now = DateTime.now();
  ```
  改为：
  ```dart
    final now = _clock();
  ```

  位置：`:171`
  当前代码：
  ```dart
    if (!_cachePolicy.isAlive(entry, DateTime.now())) return null;
  ```
  改为：
  ```dart
    if (!_cachePolicy.isAlive(entry, _clock())) return null;
  ```

  边界裁决：
  - 未注入 `clock` → 默认 `DateTime.now`（与修改前行为完全一致）
  - 注入固定时钟 → 所有 `isAlive` 检查使用固定时间 → 测试可确定性验证 TTL 过期
  - `_clock` 仅在 `_cachePolicy.isAlive` 和 `CacheEntry.createdAt` 中使用 → 不影响其他逻辑

- **[BUG-31-S3]** `directoryContentsProvider` 接受注入时钟 (`status: new`)
  ```
  Given directoryContentsProvider 在测试中使用注入时钟
  When  检查缓存存活和创建 CacheEntry
  Then  使用注入时钟而非 DateTime.now()
  否定断言:
    - 不在 provider 中硬编码 DateTime.now()（当前 BUG 行为）
    - 不改变生产环境默认行为（注入 null 时使用 DateTime.now）
    - 不改变缓存 TTL 语义
  ```
  Code evidence: `lib/features/browser/browser_provider.dart:72,75,100`（硬编码 `DateTime.now()`）

  **修改指令 — `lib/features/browser/browser_provider.dart`（directoryContentsProvider）**

  位置：`:64-101`

  当前代码（:71-75）：
  ```dart
    if (cached != null &&
        const CachePolicy<List<NasFile>>().isAlive(cached, DateTime.now())) {
      ref.read(directoryCacheProvider.notifier).update((s) {
        final u = Map<String, CacheEntry<List<NasFile>>>.from(s);
        u[cacheKey] = cached.accessedAt(DateTime.now());
  ```

  改为：
  ```dart
    final clock = ref.read(browserClockProvider);
    if (cached != null &&
        const CachePolicy<List<NasFile>>().isAlive(cached, clock())) {
      ref.read(directoryCacheProvider.notifier).update((s) {
        final u = Map<String, CacheEntry<List<NasFile>>>.from(s);
        u[cacheKey] = cached.accessedAt(clock());
  ```

  位置：`:100`
  当前代码：
  ```dart
          CacheEntry<List<NasFile>>(value: sorted, createdAt: DateTime.now())));
  ```
  改为：
  ```dart
          CacheEntry<List<NasFile>>(value: sorted, createdAt: clock())));
  ```

  新增 provider：
  ```dart
  final browserClockProvider = Provider<DateTime Function()>((ref) => DateTime.now);
  ```

  边界裁决：
  - 生产环境 `browserClockProvider` 返回 `DateTime.now` → 行为不变
  - 测试环境覆盖 `browserClockProvider` → 注入固定时钟 → 确定性验证
  - `clock()` 在同一 provider 内多次调用 → 可能得到不同时间（若注入真实 `DateTime.now`）→ 可接受（误差微秒级）
  - 若需严格一致性，可在 provider 开头调用一次 `final now = clock()` 后复用 → 当前代码已是单线程 FutureProvider，`clock()` 微秒级误差对 5min TTL 无影响

  **测试文件位置：`test/features/browser/bug_bug31_repro_test.dart`**

---

## §4 不变量

- **[BUG-31-INV1]** 文件列表项始终使用 `ValueKey(file.path)` 作为 widget key
  证据：修复后 `browser_screen.dart:355,362` 传入 `ValueKey(file.path)`

- **[BUG-31-INV2]** `DirectoryService` 和 `directoryContentsProvider` 的时钟来源可注入，默认 `DateTime.now`
  证据：修复后 `directory_service.dart` 新增 `_clock` 字段（`:69-83`）；`browser_provider.dart` 新增 `browserClockProvider`

---

## §5 测试规约

### 5.1 现有测试清单

| 测试文件 | 覆盖 | 备注 |
|---|---|---|
| `test/features/browser/ref_19_test.dart` | 缓存过期 | 使用 1ms TTL + `Future.delayed(50ms)` — CI 抖动风险 |

### 5.2 测试 ID 派生清单

```
BUG-31-S1           # ValueKey 注入
BUG-31-S2           # DirectoryService 时钟注入
BUG-31-S3           # directoryContentsProvider 时钟注入
BUG-31-INV1         # ValueKey 一致性
BUG-31-INV2         # 时钟可注入
```

### 5.3 测试覆盖盲点

| 未覆盖 ID | 现状 | 应补偿方式 |
|---|---|---|
| BUG-31-S1 | 现有测试未验证 tile key | Widget test：构建 _FileList → 查找 DirectoryListTile/AudioFileListTile → 断言 key 为 ValueKey |
| BUG-31-S2 | ref_19_test 使用真实时间 | 注入固定时钟 → 验证 TTL 过期无需真实等待 |
| BUG-31-S3 | provider 时钟未注入 | 覆盖 browserClockProvider → 验证缓存过期确定性 |

### 5.4 测试文件位置

| 测试 ID | 文件路径 |
|---|---|
| BUG-31-S1 | `test/features/browser/bug_bug31_repro_test.dart` |
| BUG-31-S2 | `test/features/browser/bug_bug31_repro_test.dart` |
| BUG-31-S3 | `test/features/browser/bug_bug31_repro_test.dart` |
| BUG-31-INV1 | `test/features/browser/bug_bug31_repro_test.dart` |
| BUG-31-INV2 | `test/features/browser/bug_bug31_repro_test.dart` |

---

## §6 算法样例

不适用——本修复为 UI key 注入 + 时钟参数注入，无新算法。

---

## §7 跨模块影响

| 其它 feature | 影响点 | 需要补的回归断言 |
|---|---|---|
| BRW | `_FileList` 重构 | 现有 widget test 可能需更新 key 断言 |
| BRW | `ref_19_test.dart` | 可迁移到注入时钟（非强制，现有测试仍可工作） |
| BRW | `DirectoryService` 构造函数 | 现有测试构造 `DirectoryService(client:..., storage:...)` 不受影响（clock 可选参数） |

---

## §8 平台特性与手动 QA

本功能不涉及平台原生特性，全部可在 `flutter test` 中验证。

---

## §9 dev-status.json 条目对照

见统一更新：`docs/dev/dev-status.json`。

---

## §10 changelog

- 2026-07-27: 创建 BUG-31 spec（基于 cr-20260724-0110.md BRW5 + BRW8）
