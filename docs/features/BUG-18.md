# BUG-18 — Browser 读进度路径裸奔无 try/catch，DAO 抛错时点击静默失效且抛未处理异步异常

## §0 头部元数据

```yaml
id: BUG-18
name: Browser 读进度路径裸奔无 try/catch（恢复进度查询抛错无反馈无日志）
priority: P2
status: active
created_at: 2026-08-16
last_updated: 2026-08-16
spec_anchored_files:
  - lib/features/browser/browser_screen.dart
  - lib/features/playlist/playlist_detail_screen.dart
  - lib/features/progress/progress_provider.dart
  - test/features/browser/bug_18_repro_test.dart
cross_module_impacts: [BRW, PRG]
parent_feature: Browser
manual_qa_required: false       # 纯 Dart 异常路径加固，无平台原生面
```

---

## §1 用户视角

### 1.0 原始需求（用户原话逐字记录）

来源：`docs/cr/cr-20260816-0805-progress-timer-settings.md` F1（cr 复核已确认仍存在，D2 证据不符已剔除、其余条目逐条核对）：

> #### F1. Browser 读进度路径无 try/catch，DAO 异常时点击静默失效且抛未处理异步异常
>
> - 类型：FRAGILE / 严重度：Minor / 维度：正确性（异常路径）
> - 证据：`lib/features/browser/browser_screen.dart:116-120`
>   ```dart
>   final progress =
>       await ref.read(progressForFileProvider((
>     connectionId: conn.id!,
>     filePath: tappedFile.path,
>   )).future);
>   if (!context.mounted) return;
>   ```
>   对比同功能另一调用方 `lib/features/playlist/playlist_detail_screen.dart:48-75` 有 `try { ... } catch (e) { debugPrint('[Playlist] play: progress resume lookup failed, ...'); }` 且注明「catch-log criterion, same as CON1/BUG-19/LIST6」。且写路径（upsert/clear）已被 BUG-09 加固为 try-catch + debugPrint（`progress_provider.dart:86-96, 119-124`），读路径是唯一裸奔点。
> - 复现路径：条件——`progressForFileProvider` 的 Future 抛错（SQLite 读异常，如 DB 文件损坏/IO 错误）。序列：应用处于可用状态 → 点任意音频文件 → onFileTap 中 await 抛错 → 无 catch 承接 → 未处理异步异常上抛（debug 红屏/zone 错误）→ 队列不建、`/player` 不跳，点击无声失效。期望：如 playlist_detail 一样 catch 并记日志、按无进度继续播放。
> - 自检答案：**分支零覆盖**——所有 widget 测试（bug_13 / prg_test / brw 系）注入的叶子 fake DAO（`_RecordingProgressDao` 等）永不抛错，没有任何测试让 browser 点击路径的 progress 查询失败；playlist 侧的 catch 分支同样无注入失败测试（此点可随修复补锚定）。
> - 修复建议：给 `browser_screen.dart` onFileTap 的进度查询包 try/catch + debugPrint（对齐 playlist_detail 写法与 SCHEMA.md §5 catch-log 裁决），失败时按无进度播放；可顺带用一条「DAO 抛错 → 仍建队进播放页」的 widget 测试锚定。

### 1.1 这一功能干什么（一句话）

修复浏览器文件列表的"恢复进度查询"在数据库读取失败时无兜底的问题——查询抛错不得中断播放流程、不得冒未处理异常，应像播放单页一样捕获并记日志后按无进度播放。

### 1.2 用户期望的场景

| ID | 你看到的样子 | 期望行为 |
|----|----|----|
| U1 | 在浏览页点一个音频文件，此时读取保存的播放进度失败（数据库异常） | 音乐照常开始播放（从开头播起），页面不闪红屏、不报错、不出现"点了没反应" |
| U2 | 播放单页（对照面）在同样情况下点曲目 | 行为与 U1 一致——照常播放、无红屏（现状已加固，回归不破坏） |
| U3 | 在浏览页长按一个音频文件，读取进度失败（数据库异常） | 没有任何异常弹出或红屏；清除进度菜单不出现即可（长按没有可展示的进度） |
| U4 | 进度查询正常时（无异常） | 行为与修复前完全一致——有进度弹"恢复播放进度"对话框，无进度直接播放 |

---

## §2 已实现的功能骨架（代码锚点）

### 2.1 文件与分层

| 层 | 文件 | 行数 | 角色 |
|---|---|---|---|
| UI | `lib/features/browser/browser_screen.dart` | 393 | 文件浏览页：onFileTap（95-161）/ onFileLongPress（162-219）含恢复进度查询 |
| Provider | `lib/features/progress/progress_provider.dart` | 195 | progressForFileProvider（42-48）/ upsert（86-96 catch-log）/ clear（119-124 catch-log） |
| UI | `lib/features/playlist/playlist_detail_screen.dart` | 414 | 对照面：_playTrackAtIndex 查询已 catch-log 加固（48-75） |
| 契约 | `lib/core/contracts/database_contract.dart` | — | IProgressDao.find 可抛错（SQLite 层），契约无异常声明 |
| 测试 | `test/features/browser/bug_18_repro_test.dart` | 本 spec §5.4 | 本 Bug 门禁（修复前 FAIL，已用 repro-test.sh fail 确认） |

### 2.2 关键 Provider 表

| Provider 名 | 类型 | 实现位置 | 用途 |
|---|---|---|---|
| progressForFileProvider | FutureProvider.family<(int, String), PlayProgress?> | progress_provider.dart:42-48 | 恢复进度查询：service.getProgress → ProgressDao.find |
| progressDaoProvider | Provider<IProgressDao> | progress_provider.dart:26 | DAO 注入点（测试 override 用） |
| activeConnectionProvider | — | shared/di 桥接 | 当前活跃连接（browser_screen.dart:114 读 conn.id） |

### 2.3 状态机图

本 Bug 不涉状态机（异常路径加固），跳过。

---

## §3 行为规约（Given-When-Then）

### 3.1 现有行为（逆抽，缺陷态）

- **[BUG-18-S1]** onFileTap 恢复进度查询裸奔无 try/catch —— DAO 抛错 → 未处理异步异常 + 点击静默失效
  ```
  Given 活跃连接存在（conn.id != null）
  When 用户点击音频文件，progressForFileProvider 的 future 以 error 完成
      （ProgressDao.find 抛 SQLite 异常）
  Then await ref.read(...).future 抛错（无 catch 承接）
  And onFileTap 的 Future 以未处理异步异常上抛（debug 红屏 / zone 错误）
  And 建队（currentPlayQueueProvider 赋值）、goRouter.push('/player') 不执行
  ```
  Code evidence:
  - `lib/features/browser/browser_screen.dart:115-121`（查询裸奔段——`if (conn != null && conn.id != null) { final progress = await ref.read(progressForFileProvider(...).future); if (!context.mounted) return; ... }`，无 try/catch）
  - `lib/features/browser/browser_screen.dart:150-160`（建队 + push 位于查询之后，await 抛错则不可达）
  - `lib/features/progress/progress_provider.dart:42-48`（provider 透传 service.getProgress 异常，自身无 catch）
  - 对照：`lib/features/playlist/playlist_detail_screen.dart:48-75`（同查询已 try/catch + debugPrint「[Playlist] play: progress resume lookup failed...」）
  - 对照：`lib/features/progress/progress_provider.dart:86-96/119-124`（写路径 upsert/clear 均 try-catch + debugPrint，BUG-09 加固）

- **[BUG-18-S2]** onFileLongPress 恢复进度查询同样裸奔（勘察发现，cr F1 未列，同类缺陷）
  ```
  Given 活跃连接存在（conn.id != null）
  When 用户长按音频文件，progressForFileProvider 的 future 以 error 完成
  Then await ref.read(...).future 抛错（无 catch 承接，browser_screen.dart:167-170）
  And onFileLongPress 的 Future 以未处理异步异常上抛
  And showModalBottomSheet（清除进度菜单）不执行
  ```
  Code evidence: `lib/features/browser/browser_screen.dart:162-171`（`if (conn == null || conn.id == null) return; final progress = await ref.read(progressForFileProvider(...).future); if (progress == null || !context.mounted) return;`——查询无 try/catch；与 onFileTap 同源裸奔，cr F1「读路径是唯一裸奔点」的判断应含此点）。

### 3.2 修复方案（status: new）

- **[BUG-18-S3]** onFileTap 恢复进度查询包 try/catch + debugPrint，失败按无进度播放照常进播放页 （status: new）
  ```
  Given 活跃连接存在（conn.id != null），用户点击音频文件
  When progressForFileProvider 的 future 以 error 完成（DAO 抛错）
  Then catch 捕获异常并 debugPrint 记日志
      （文案与 playlist_detail_screen.dart:73-74 对齐、前缀换 [Browser]：
      '[Browser] play: progress resume lookup failed, playing from beginning: $e'）
  And startPositionMs 保持 null（按无进度播放）
  And 建队（currentPlayQueueProvider 赋值）+ goRouter.push('/player') 照常执行
  否定断言:
    - 不得作为未处理异步异常上抛（tester.takeException() 为 null）
    - 不得弹"恢复播放进度"对话框（进度未知 → 不提示恢复）
    - 不得调用 clearProgressProvider（查询失败不产生"清除进度"副作用）
    - 目录加载状态与导航栈不得被影响（navigationStackProvider 长度不变）
  ```
  修改点（对齐 playlist_detail_screen.dart:48-75 形态）：`lib/features/browser/browser_screen.dart:115-135`
  ```dart
  // 修改前（115-135）:
  int? startPositionMs;
  final conn = ref.read(activeConnectionProvider).valueOrNull;
  if (conn != null && conn.id != null) {
    final progress =
        await ref.read(progressForFileProvider((
      connectionId: conn.id!,
      filePath: tappedFile.path,
    )).future);
    if (!context.mounted) return;
    if (progress != null && progress.positionMs >= 5000) {
      final container = ProviderScope.containerOf(context);
      final resume = await showProgressResumeDialog(
          context, container, progress);
      if (resume == true) {
        startPositionMs = progress.positionMs;
      } else if (resume == false) {
        ref.read(clearProgressProvider)(
          connectionId: conn.id!,
          filePath: tappedFile.path,
        );
      }
    }
  }

  // 修改后:
  int? startPositionMs;
  final conn = ref.read(activeConnectionProvider).valueOrNull;
  if (conn != null && conn.id != null) {
    // BUG-18: progressForFileProvider 的 future 抛错（SQLite 读异常）时
    // 不得冒未处理异常中断播放流程——catch + 日志，按无进度播放
    // （对齐 playlist_detail_screen.dart:48-75；SCHEMA.md §5 catch-log 裁决）。
    try {
      final progress =
          await ref.read(progressForFileProvider((
        connectionId: conn.id!,
        filePath: tappedFile.path,
      )).future);
      if (!context.mounted) return;
      if (progress != null && progress.positionMs >= 5000) {
        final container = ProviderScope.containerOf(context);
        final resume = await showProgressResumeDialog(
            context, container, progress);
        if (resume == true) {
          startPositionMs = progress.positionMs;
        } else if (resume == false) {
          ref.read(clearProgressProvider)(
            connectionId: conn.id!,
            filePath: tappedFile.path,
          );
        }
      }
    } catch (e) {
      // On error, play from beginning — but do not swallow silently
      // (catch-log criterion, SCHEMA.md §5, same as playlist_detail).
      debugPrint('[Browser] play: progress resume lookup failed, '
          'playing from beginning: $e');
    }
  }
  ```
  **边界裁决（弱模型照此实现，无需二次判断）**：

  | 边界情况 | 裁决 |
  |---|---|
  | DAO 抛错（find 异常） | catch → debugPrint（文案见上）→ startPositionMs=null → 继续建队/push /player |
  | progress == null（无进度） | 不弹框，startPositionMs=null，建队播放（现有行为不变，try 内正常路径） |
  | progress.positionMs < 5000 | 不弹框（PRG-T03 shouldSave 门槛，现有行为不变） |
  | progress.positionMs >= 5000 且用户选"继续播放" | startPositionMs = progress.positionMs（现有行为不变） |
  | 用户选"从头播放" | clearProgressProvider 触发（现有行为不变，try 内） |
  | showProgressResumeDialog 自身抛错 | 同一 catch 承接 → debugPrint → 按无进度播放（与 DAO 抛错同语义） |
  | context 已卸载（await 后） | try 内 `if (!context.mounted) return;` 先行返回（现有守卫不变，121 行语义保留） |
  | 日志文本 | 可含异常 toString；本路径异常来自本地 SQLite（无凭证面），不触发 secret-logs（对照 playlist_detail_screen.dart:73-74 同款直拼 $e） |

- **[BUG-18-S4]** onFileLongPress 恢复进度查询包 try/catch + debugPrint，失败静默返回不弹菜单 （status: new）
  ```
  Given 活跃连接存在（conn.id != null），用户长按音频文件
  When progressForFileProvider 的 future 以 error 完成（DAO 抛错）
  Then catch 捕获异常并 debugPrint 记日志
      （'[Browser] long-press: progress resume lookup failed: $e'）
  And 直接返回——不弹"清除播放进度"底部菜单
  否定断言:
    - 不得作为未处理异步异常上抛（tester.takeException() 为 null）
    - 不弹 showModalBottomSheet（find.text('清除播放进度') findsNothing）
    - 不得调用 clearProgressProvider（无进度可清）
  ```
  修改点：`lib/features/browser/browser_screen.dart:162-171`
  ```dart
  // 修改前（162-171）:
  onFileLongPress: (tappedFile) async {
    // BUG-12: read progressForFileProvider directly.
    final conn = ref.read(activeConnectionProvider).valueOrNull;
    if (conn == null || conn.id == null) return;
    final progress = await ref.read(progressForFileProvider((
      connectionId: conn.id!,
      filePath: tappedFile.path,
    )).future);
    if (progress == null || !context.mounted) return;

  // 修改后:
  onFileLongPress: (tappedFile) async {
    // BUG-12: read progressForFileProvider directly.
    final conn = ref.read(activeConnectionProvider).valueOrNull;
    if (conn == null || conn.id == null) return;
    // BUG-18: 同类裸奔点加固（cr-0805 F1 勘察补充，browser_screen.dart:167-170）。
    PlayProgress? progress;
    try {
      progress = await ref.read(progressForFileProvider((
        connectionId: conn.id!,
        filePath: tappedFile.path,
      )).future);
    } catch (e) {
      // 查询失败 → 无进度可展示，静默返回（catch-log 裁决，日志照留）。
      debugPrint('[Browser] long-press: progress resume lookup failed: $e');
      return;
    }
    if (progress == null || !context.mounted) return;
  ```
  **边界裁决**：DAO 抛错 → catch + 日志 + return（长按菜单不弹）；progress == null → 原 return 守卫不变；progress != null → 弹菜单（现有行为不变）。日志文案含 `[Browser] long-press:` 前缀，与 S3 的 `[Browser] play:` 前缀区分路径。

---

## §4 不变量

- **[BUG-18-INV1]** 恢复进度查询的异常路径必须被显式捕获并记日志，不得作为未处理异步异常上抛
  证据：`browser_screen.dart:115-121`（现状裸奔，修复点）；`playlist_detail_screen.dart:70-75`（对照已固化形态）；SCHEMA.md §5 全局裁决（catch 必须有日志）；本 spec S3/S4 修复。
  异常（catch 可接受）前提是有日志——本 Bug 修复即把裸奔点对齐到该裁决。

- **[BUG-18-INV2]** 恢复进度查询失败不得影响播放主流程（建队 + push /player 照常）
  证据：`playlist_detail_screen.dart:81-93`（对照面 catch 后继续建队 + context.push('/player')）；cr F1 修复建议「失败时按无进度播放」；本 spec S3。
  本 Bug 修复保持「进度是播放的附属信息」语义——查询失败降级为从开头播。

---

## §5 测试规约

### 5.1 现有测试清单

| 测试文件 | 覆盖的 Scenario / INV | 备注 |
|---|---|---|
| test/features/browser/bug_12_repro_test.dart | BUG-18-S3 的正常路径面（查询成功 → 弹框/直接播放） | 走同一真实链路，修复不得回归 |
| test/features/browser/test_01_brw09_test.dart / brw_10 / brw_11 | BUG-18-S3/S4 正常路径面 | 点击/长按既有行为锚定 |
| test/features/playlist/bug_09_test.dart | 对照面（playlist catch-log 锚定） | 参照样式，不在本 Bug 修改范围 |

### 5.2 测试 ID 派生清单（dev-exe 派发测试 Agent 用）

```
BUG-18-S1 … S4        # Scenario（S1/S2 缺陷态逆抽，S3/S4 修复目标）
BUG-18-INV1 … INV2    # 不变量
```

dev-exe 要求：S3/S4/INV1/INV2 已由 §5.4 门禁测试覆盖；S1/S2 由门禁测试的修复前 FAIL 态 + takeException 断言顺带锚定；正常路径回归依赖既有 browser 测试（bug_12_repro / test_01_brw09~11 / brw 系）。

### 5.3 测试覆盖盲点（dev-plan 写本文档时识别）

| 未覆盖 ID | 现状 | 应补偿方式 |
|---|---|---|
| 无 | 门禁测试已覆盖异常路径（tap + longPress）；正常路径由既有测试锚定 | — |

### 5.4 测试文件位置（spec-scan --gate 硬校验）

| 测试文件 | 覆盖 ID | 说明 |
|---|---|---|
| test/features/browser/bug_18_repro_test.dart | BUG-18-S3、BUG-18-S4、BUG-18-INV1、BUG-18-INV2 | 门禁：dev-exe 修复后必须 PASS（repro-test.sh pass）；修复前已用 repro-test.sh fail 确认真实 FAIL |

---

## §6 算法样例

本 Bug 不涉纯函数算法，跳过。

---

## §7 跨模块影响

`bash cross-imports.sh impact lib/features/browser/browser_screen.dart lib/features/progress/progress_provider.dart`（2026-08-16）→ browser_screen / progress_provider 均无 feature 间直接 import（消费方经 shared/di 桥接）：

| 其它 feature | 影响点 | 影响条件 | 需要补的回归断言 |
|---|---|---|---|
| Browser（自身） | browser_screen.dart onFileTap/onFileLongPress 进度查询包裹 try/catch | 改动仅限方法体（签名/导出面不变）；shared/di/providers.dart:234 re-export BrowserScreen 不变 | test/features/browser/bug_18_repro_test.dart PASS；bug_12_repro_test.dart / test_01_brw09~11 / brw_01~09 全绿（正常路径不回归） |
| Progress | progressForFileProvider 消费方新增 catch（browser 侧），provider 自身不动 | 无（provider 语义不变，异常继续向消费方抛出） | progress 模块既有测试全绿（prg_test / bug_09 / test_01_brw10） |
| Playlist | playlist_detail_screen.dart:48-75 为对照样板，不改 | 无 | playlist 既有测试全绿（bug_09_test.dart 锚定 catch-log 形态） |
| Home | home_screen.dart 消费 BrowserScreen（Tab 内） | 无（行为不变，仅异常路径语义变化） | home 模块测试全绿 |

---

## §8 平台特性与手动 QA

设计前已逐条核对 `docs/dev/platform-pitfalls.md`：
- 触及 **SCHEMA.md §5 全局裁决（catch-log）**——本 Bug 即把裸奔读路径对齐到「catch 可接受前提是有日志」的裁决；日志文案不含凭证（本地 SQLite 异常，无 userinfo 面），secret-logs 门禁不受影响（对照 playlist_detail_screen.dart:73-74 同款直拼 $e）。
- 不触及 P17 超时分层表（progressForFileProvider → 本地 sqflite，非 WebDAV/secure_storage/播放平台调用面，无超时数值改动）。
- 不触及 P8/P9/P14（本 Bug 不动监听器生命周期、不新增 setState、不新增加载并发入口；现有 `context.mounted` 守卫保留）。

**真机风险列**（fake 测不到、只有真机会出的问题）：

| 风险 | 近似测试方案 | 测不了 → 进 mqa-backlog |
|---|---|---|
| SQLite 数据库文件损坏/IO 错误导致的真实 find 异常 | bug_18_repro_test.dart 以抛错 fake DAO 近似注入同类异常（leaf 注入是项目标准做法） | 无（catch-log 语义与 playlist_detail 同款、已在真机形态投产，风险低） |

不涉及平台原生特性 → `manual_qa_required = false`，全部可在 `flutter test` 中验证。

---

## §9 dev-status.json 条目对照

```json
"BUG-18": {
  "spec_file": "docs/features/BUG-18.md",
  "spec_anchored_files": [
    "lib/features/browser/browser_screen.dart",
    "lib/features/playlist/playlist_detail_screen.dart",
    "lib/features/progress/progress_provider.dart",
    "test/features/browser/bug_18_repro_test.dart"
  ],
  "scenarios": ["BUG-18-S1", "BUG-18-S2", "BUG-18-S3", "BUG-18-S4"],
  "invariants": ["BUG-18-INV1", "BUG-18-INV2"],
  "algorithms": [],
  "manual_qa_required": false,
  "user_acceptance_text": "见 §1.2"
}
```
