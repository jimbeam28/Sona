# REF-05 — 队列面板改 live 数据源：删除即时刷新、高亮跟随、空态兜底

## §0 头部元数据

```yaml
id: REF-05
name: 队列面板 live 数据源（watch currentPlayQueueProvider + ValueKey + 空态）
priority: P2
status: active
created_at: 2026-08-16
last_updated: 2026-08-16
spec_anchored_files:
  - lib/features/player/widgets/queue_sheet.dart
  - lib/features/player/player_screen.dart
  - lib/features/player/widgets/mini_player_bar.dart
  - lib/features/player/domain/playback_orchestrator.dart
  - lib/features/browser/browser_provider.dart
cross_module_impacts: [PLY, BRW, HOME]
manual_qa_required: false       # 纯 widget/状态层，flutter test 全可验证
```

---

## §1 用户视角

### 1.0 原始需求（用户原话逐字记录）

来源：`docs/cr/cr-20260816-0802-player.md` D3（cr 复核分流，用户裁决"修"→ 转 REF 需求流程）：

> #### D3. 队列面板是快照数据：删除后不刷新，陈旧条目点击落空
> - 类型 / 严重度 / 维度：DESIGN / Minor / 正确性（UX）
> - 证据：
>
> `lib/features/player/widgets/queue_sheet.dart:24-107`：QueueSheet 收构造参数 `queue`（快照），`onRemoveIndex`（:76-85）删除成功后 modal 内列表不重建；`ListTile` 无 ValueKey（P13 要求列表项业务 ID）。删除当前曲后：'当前' 高亮停在旧位置、已删条目仍在、点它 → `selectQueueIndexProvider` 越界校验（`playback_orchestrator.dart:320`）→ failed → snackbar 报错。
> - 取舍分析：快照式 sheet 简洁但陈旧；可接受（下次打开即正确），也可 watch provider 驱动重建。
> - 修复建议：sheet 内容改为 watch `currentPlayQueueProvider`（经 ref），或删除后自动收起。

用户裁决：**队列面板改为 live 数据源**——sheet 内部 `watch currentPlayQueueProvider` 驱动重建（含"队列被删空"的空态展示），列表项按业务 ID 加 Key；点击兜底（越界校验 → snackbar）保留。

### 1.1 这一功能干什么（一句话）

打开播放队列面板后，面板内容与当前播放队列实时一致：删除任意曲目列表立即消失该条目、"当前"高亮自动移动到新位置、面板开着时自动切歌高亮跟随、队列被删空时面板显示"队列为空"而不是显示陈旧条目。

### 1.2 用户期望的场景

| ID | 你看到的样子 | 期望行为 |
|----|----|----|
| U1 | 打开队列面板，删除其中一首（非当前曲） | 列表立即刷新，被删曲目消失，其余曲目顺序正确 |
| U2 | 打开队列面板，删除正在播放的曲目 | '当前' 标记立即移到新的当前曲目上（而不是停在旧位置） |
| U3 | 面板开着时删掉最后一首（队列变空） | 面板显示"队列为空"，没有列表、没有删除按钮；关闭面板回到播放器页面，页面自动退出（既有行为） |
| U4 | 面板开着时曲目自然播完自动切歌 | '当前' 高亮自动跟随新的当前曲目 |
| U5 | 删除曲目后立刻点列表里的另一首 | 正常切歌，不报错 |
| U6 | 打开面板直接点某一首播放 | 与修复前一致：面板收起、播放所选曲目 |

---

## §2 已实现的功能骨架（代码锚点）

### 2.1 文件与分层

| 层 | 文件 | 行数 | 角色 |
|---|---|---|---|
| UI | `lib/features/player/widgets/queue_sheet.dart` | 108 | `QueueSheet`（9-107）StatelessWidget：构造参数 `queue` 快照（10/17）+ 标题（33-38 '播放队列 (${queue.length})'）+ ListView.builder（41-100）无 ValueKey + 删除按钮（76-85 调 onRemoveIndex）+ 点击（87-97 收起 → onSelectIndex → 失败 snackbar） |
| UI | `lib/features/player/player_screen.dart` | 432 | `_showQueueSheet`（237-255）：传 watch 到的 playQueue 快照（241-242）+ onSelectIndex/onRemoveIndex 接线（244-252）；调用点 356 |
| UI | `lib/features/player/widgets/mini_player_bar.dart` | 245 | `_showQueueSheet`（142-158）：同构快照传参（147）；调用点 121 |
| Domain | `lib/features/player/domain/playback_orchestrator.dart` | 479 | `selectQueueIndex` 越界校验（318-325：`index < 0 || index >= q.length` → failed）/ `removeTrack`（339-369：wasCurrent 时先 saveProgress 再换队列再 loadAndPlay；空队列 → gate begin + stop + queue=null 346-355） |
| Provider | `lib/features/browser/browser_provider.dart` | — | `currentPlayQueueProvider` 定义（StateProvider\<PlayQueue?\>，经 shared/di re-export：providers.dart:40）——live 数据源 |
| 测试 | `test/features/player/ply_08_test.dart` | 514 | `_wrapQueueSheetLauncher`（38-64 构造参数快照）+ `QueueSheet widget` 组（419-475 2 个用例）——改造对象 |
| 测试 | `test/features/player/ply_14_test.dart` | 634 | TST-T54（599-633）全屏 PlayerScreen 点队列按钮弹 sheet；`currentPlayQueueProvider.overrideWith`（49）既有 override 机制 |

### 2.2 关键 Provider 表

| Provider 名 | 类型 | 实现位置 | 用途 |
|---|---|---|---|
| currentPlayQueueProvider | StateProvider\<PlayQueue?\> | browser_provider.dart（经 shared/di/providers.dart:40 桥接） | 播放队列唯一 live 源：orchestrator.onQueueChanged（player_provider.dart:121-132）写入；QueueSheet 改为 watch 此 provider |
| selectQueueIndexProvider | Provider\<Future\<TrackLoadResult\> Function(int)\> | player_provider.dart:366-373 | 点击条目切歌；越界经 orchestrator:320 failed → sheet snackbar（兜底，保持） |
| removeTrackFromQueueProvider | Provider\<Future\<void\> Function(int)\> | player_provider.dart:375-384 | 删除条目；orchestrator.removeTrack 更新队列 → onQueueChanged → live 刷新 |

### 2.3 状态机图

本 REF 无新增状态机（数据流：orchestrator 队列变更 → onQueueChanged → currentPlayQueueProvider 更新 → sheet watch 重建）。跳过。

---

## §3 行为规约（Given-When-Then）

### 3.1 现有行为（逆抽）

- **[REF-05-S1]** QueueSheet 是构造参数快照：列表内容在 modal 打开时定格
  ```
  Given 两个调用方都传入打开瞬间的队列（player_screen.dart:241-242 / mini_player_bar.dart:147）
  When modal 打开后队列变化（删除/切歌/自动前进）
  Then ListView.builder 用快照 queue 渲染：删除的条目仍在、'当前' 高亮停在旧 index、
      标题长度不变
  ```
  Code evidence: `lib/features/player/widgets/queue_sheet.dart:10`（`final PlayQueue queue;` 构造参数）+ `:41-100`（列表消费该字段）；`lib/features/player/player_screen.dart:241-242`、`lib/features/player/widgets/mini_player_bar.dart:147`（快照传参）。

- **[REF-05-S2]** 列表项无 ValueKey：删除/重排后按 index 位置匹配（P13 违规）
  ```
  Given ListView.builder itemBuilder 直接返回 ListTile（无 key 参数）
  When 队列内容变化导致重建
  Then 条目按 position 匹配，widget 复用/错位（'当前' 标记显示在错误行）
  ```
  Code evidence: `lib/features/player/widgets/queue_sheet.dart:46`（`return ListTile(` 无 key）；对照 P13 踩坑库 `docs/dev/platform-pitfalls.md` P13（"列表项一律 ValueKey(业务 ID)"）。

- **[REF-05-S3]** 删除后陈旧条目点击落空：orchestrator 越界校验 → failed → snackbar
  ```
  Given 快照中 index=2 的条目已从队列删除（删除按钮 76-85 已触发 onRemoveIndex）
  When 用户点击该陈旧条目（onTap 87-97 → onSelectIndex(index) → selectQueueIndexProvider）
  Then orchestrator.selectQueueIndex 越界校验（index >= q.length）→ TrackLoadResult.failed
  And sheet onTap 收到 !loaded → SnackBar(errorMessage)（90-96）
  ```
  Code evidence: `lib/features/player/domain/playback_orchestrator.dart:318-325`（越界 → failed）；`lib/features/player/widgets/queue_sheet.dart:76-98`（删除/点击/失败提示）。

### 3.2 修改方案（status: new）

设计裁决（用户裁决"watch provider 驱动重建"）：

| 边界情况 | 裁决 |
|---|---|
| sheet 打开期间队列变化（删除/切歌/自动前进/插入） | watch 驱动整表重建，内容恒等于 live 队列（S4 修改点 1） |
| watch 到 queue == null（队列被删空） | **显示空态**：标题 '播放队列' + 居中文本 '队列为空'，无列表、无删除/点击交互；**不自动 pop**（避免 build 期间导航副作用，P11 纪律），用户下滑关闭 |
| 打开瞬间队列已空（理论上调用方前置检查已挡，防御路径） | 同空态渲染，不崩溃 |
| 点击条目与队列变化的窗口期竞态（点完队列又变） | index 基于 live 队列通常一致；极端竞态由 orchestrator:320 越界校验兜底 → snackbar（S7，行为保持） |
| 列表项 Key | `ValueKey(file.path)`（业务 ID，P13） |
| onSelectIndex / onRemoveIndex / errorMessage 构造参数 | 保留（回调仍由调用方注入）；**仅删 `queue` 参数** |
| 两个调用方 | `player_screen.dart:237-255` 与 `mini_player_bar.dart:142-158` 的 `_showQueueSheet` 删 queue 参数（内部不再读快照） |
| 跨 feature import 规则 | queue_sheet.dart（player feature）watch `currentPlayQueueProvider` 必须经 `shared/di/providers.dart` 桥接（browser_provider.dart:40 re-export），**禁止**直接 import browser_provider.dart（feature-isolation 门禁） |

- **[REF-05-S4]** QueueSheet 改 ConsumerWidget + live watch + 空态 + ValueKey（修改点 1） （status: new）

  ```
  Given lib/features/player/widgets/queue_sheet.dart
  When dev-exe 实施本 REF
  Then QueueSheet 从 StatelessWidget 改为 ConsumerWidget
  And 删除 `final PlayQueue queue;` 字段与构造参数（10、17）
  And build 内 `final queue = ref.watch(currentPlayQueueProvider);`
  And queue == null || queue.length == 0 → 空态渲染（标题 '播放队列' + '队列为空'）
  And 列表 ListTile 加 `key: ValueKey(file.path)`
  And 标题/列表/高亮全部基于 live queue
  否定断言:
    - 不得自动 Navigator.pop（build 期间无导航副作用）
    - 不得删除 onSelectIndex / onRemoveIndex / errorMessage 构造参数（调用方接线点）
    - 不得直接 import browser_provider.dart（必须经 shared/di/providers.dart 桥接，
      cross-imports feature-isolation 门禁）
    - 空态下不得渲染移除按钮（Icons.close）与可点 ListTile
  ```
  **修改点 1 代码片段**（`lib/features/player/widgets/queue_sheet.dart` 全量改写示意，dev-exe 照此实现）：
  ```dart
  import 'package:flutter/material.dart';
  import 'package:flutter_riverpod/flutter_riverpod.dart';

  import '../../../shared/di/providers.dart'; // REF-05: live 数据源经桥接取
  import '../../../shared/models/play_queue.dart';

  typedef QueueItemSelect = Future<bool> Function(int index);
  typedef QueueItemRemove = void Function(int index);

  /// Shared queue sheet used by both the full player and the mini player.
  /// REF-05 (cr-20260816-0802 D3): live data source — watches
  /// [currentPlayQueueProvider] instead of a constructor snapshot, so deletes
  /// refresh the list in place, the '当前' highlight follows the queue, and an
  /// emptied queue renders an empty state.
  class QueueSheet extends ConsumerWidget {
    final QueueItemSelect onSelectIndex;
    final QueueItemRemove onRemoveIndex;
    final String errorMessage;

    const QueueSheet({
      super.key,
      required this.onSelectIndex,
      required this.onRemoveIndex,
      required this.errorMessage,
    });

    @override
    Widget build(BuildContext context, WidgetRef ref) {
      final queue = ref.watch(currentPlayQueueProvider);
      final maxHeight = MediaQuery.of(context).size.height * 0.7;
      return SafeArea(
        child: SizedBox(
          height: maxHeight,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  queue == null ? '播放队列' : '播放队列 (${queue.length})',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              const Divider(height: 1),
              if (queue == null || queue.length == 0)
                const Expanded(
                  child: Center(child: Text('队列为空')),
                )
              else
                Expanded(
                  child: ListView.builder(
                    itemCount: queue.length,
                    itemBuilder: (context, index) {
                      final file = queue.files[index];
                      final isCurrent = index == queue.currentIndex;
                      return ListTile(
                        key: ValueKey(file.path),
                        // …（leading/title/trailing/onTap 与现状 46-98 行逐字一致，
                        // 仅新增 key 行）
                      );
                    },
                  ),
                ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      );
    }
  }
  ```
  前提（既有符号）：`currentPlayQueueProvider` 经 `shared/di/providers.dart:40` re-export（已核实）。

- **[REF-05-S5]** 两个调用方去掉快照参数（修改点 2/3） （status: new）
  ```
  Given player_screen.dart:237-255 与 mini_player_bar.dart:142-158
  When dev-exe 实施本 REF
  Then _showQueueSheet 签名删除 queue 参数（player_screen: `_showQueueSheet(BuildContext context)`
      与 356 调用点；mini_player_bar: `_showQueueSheet(BuildContext context, WidgetRef ref)`
      与 121 调用点）
  And QueueSheet 构造不再传 queue（player_screen.dart:241-242 / mini_player_bar.dart:147 删 queue: 行）
  And onSelectIndex / onRemoveIndex / errorMessage 接线逐字保留
  否定断言:
    - 不得改动 onSelectIndex / onRemoveIndex 的回调实现（player_screen.dart:244-252 /
      mini_player_bar.dart:149-155）
    - 删除参数后两个文件不得残留对快照 queue 的 sheet 传参（analyze unused 兜底）
  ```
  Code evidence（修改点）: `lib/features/player/player_screen.dart:237-255、356`；`lib/features/player/widgets/mini_player_bar.dart:121、142-158`。

- **[REF-05-S6]** 点击与删除行为保持：live 数据下 index 有效；窗口期竞态由 orchestrator 越界校验兜底（status: new）
  ```
  Given live 数据源 + 点击/删除回调不变（orchestrator:318-325 / :339-369）
  When 用户点击非当前条目 / 点删除按钮
  Then onTap 收起面板 → onSelectIndex(index)（live index，正常有效）
  And 删除 → onRemoveIndex(index) → removeTrackFromQueueProvider → 队列更新 → sheet 重建
  And 极端窗口期（点后队列又变）→ orchestrator:320 failed → sheet onTap 的
      !loaded → SnackBar(errorMessage)（90-96 既有兜底保持）
  否定断言:
    - 不新增任何额外越界检查（既有兜底足够，P14 串行化由 gate 保证）
    - 点击当前条目仍为 no-op（onTap: isCurrent ? null : …，87-88 保持）
  ```
  Code evidence: `lib/features/player/widgets/queue_sheet.dart:87-97`（点击路径保持）；`lib/features/player/domain/playback_orchestrator.dart:318-325`（越界兜底）、`:339-369`（removeTrack）。

- **[REF-05-S7]** 测试改造：ply_08 构造器与 QueueSheet 用例改 live override（修改点 4） （status: new）
  ```
  Given test/features/player/ply_08_test.dart:38-64、419-475
  When dev-exe 实施本 REF
  Then _wrapQueueSheetLauncher 改为 ProviderScope + currentPlayQueueProvider.overrideWith
      （仿 ply_14_test.dart:45-49 既有 override 机制），不再传 queue 构造参数
  And 'queue sheet scrolls through long queue contents' / 'queue sheet taps a later
      item' 两个用例断言保持（行为语义不变，仅装配方式改）
  And ply_14_test.dart TST-T54（599-633）零改动（全屏 UI 路径 + 既有 override 49 行
      ——sheet watch 到同一 provider）
  否定断言:
    - 不得修改 TST-T54 断言（'播放队列 (2)' 等——live 源下标题语义不变）
    - 不得改动既有 QueueSheet 用例的业务断言（滚动/点击 index 转发）
  ```
  Code evidence（修改点）: `test/features/player/ply_08_test.dart:38-64、419-475`；`test/features/player/ply_14_test.dart:45-49、599-633`。

**边界裁决汇总（弱模型照此实现，无需二次判断）**：见上表。实现后全量 `flutter analyze` 0 warning 为门禁。

---

## §4 不变量

- **[REF-05-INV1]** 面板打开期间，列表内容恒等于 `currentPlayQueueProvider` 的当前值（live 非快照）：条目集合、顺序、'当前' 高亮、标题长度全部由 watch 重建
  证据：`lib/features/player/widgets/queue_sheet.dart`（修改点 1 `ref.watch(currentPlayQueueProvider)`）；数据写入侧 `lib/features/player/player_provider.dart:121-132`（onQueueChanged → provider.state）。

- **[REF-05-INV2]** 每条 ListTile 的 Key == 对应 NasFile.path（业务 ID，P13）
  证据：`lib/features/player/widgets/queue_sheet.dart`（修改点 1 `key: ValueKey(file.path)`）；对照 `docs/dev/platform-pitfalls.md` P13。

---

## §5 测试规约

### 5.1 现有测试清单

| 测试文件 | 覆盖的 Scenario / INV | 备注 |
|---|---|---|
| test/features/player/ply_08_test.dart | REF-05-S1（快照装配现状，改造对象） | _wrapQueueSheetLauncher（38-64）+ QueueSheet 组（419-475）按 S7 改造 |
| test/features/player/ply_14_test.dart | REF-05-S6（点击路径）/ 标题断言 | TST-T54（599-633）零改动，修复后保持绿 |
| test/features/player/bug_remove_track_progress_test.dart 等 | REF-05-S3（removeTrack 行为） | orchestrator 层既有测试，不动 |

### 5.2 测试 ID 派生清单（dev-exe 派发测试 Agent 用）

```
REF-05-S1 … S7        # Scenario（S1~S3 现状锚定，S4~S7 修复目标）
REF-05-INV1 … INV2    # 不变量
```

dev-exe 要求：S1/S2/S3 现状由改造前 ply_08 装配锚定（S7 改造后语义断言保持）；S4~S7 与 INV1/2 由 §5.4 门禁测试文件覆盖。

### 5.3 测试覆盖盲点（dev-plan 写本文档时识别）

| 未覆盖 ID | 现状 | 应补偿方式 |
|---|---|---|
| REF-05-S4/S5/S6（live 刷新/高亮跟随/空态） | 零锚定（现有测试只验快照语义） | §5.4 门禁文件补：删除后条目消失、'当前'移动、空态、ValueKey |
| REF-05-INV1（live 一致性） | 零锚定 | §5.4 门禁文件断言 watch 重建 |

### 5.4 测试文件位置（spec-scan --gate 硬校验）

新建：`test/features/player/ref_05_queue_sheet_live_test.dart`（命名已 grep 核实与既有文件无冲突；widget 测试装配：ProviderScope + `currentPlayQueueProvider.overrideWith` 动态值 + 可变的队列状态，仿 ply_08/ply_14 装配风格）。

| 测试文件 | 覆盖 ID | 说明 |
|---|---|---|
| test/features/player/ref_05_queue_sheet_live_test.dart | REF-05-S4、S5、S6、REF-05-INV1、REF-05-INV2 | 门禁：dev-exe 修复后必须 PASS（cov-gate 内）。建议用例：① 打开 sheet → 变更 provider 队列（删一条）→ 断言被删条目文本消失、标题长度更新；② 删除当前曲 → 断言 '当前' 高亮文本移至新当前行（新曲名旁）；③ 队列置 null → 断言 '队列为空' 出现且无 Icons.close；④ 断言每条 ListTile key == ValueKey(path)（find.byWidgetPredicate 或 tester.widget 提取 key） |
| test/features/player/ply_08_test.dart | REF-05-S1、S2、S6（装配改造后语义保持） | 既有文件按 S7 改造，改造后保持绿 |
| test/features/player/ply_14_test.dart | REF-05-S6 | 既有文件，断言不变，修复后保持绿 |

---

## §6 算法样例

本 REF 不涉纯函数算法，跳过。

---

## §7 跨模块影响

`bash cross-imports.sh impact lib/features/player/widgets/queue_sheet.dart lib/features/player/player_screen.dart lib/features/player/widgets/mini_player_bar.dart lib/features/player/domain/playback_orchestrator.dart lib/features/browser/browser_provider.dart`（2026-08-16）→ 引用方：

| 其它 feature | 影响点 | 影响条件 | 需要补的回归断言 |
|---|---|---|---|
| Player（player_screen.dart:237-255） | _showQueueSheet 签名删 queue 参数 + QueueSheet 构造改 | 页面内按钮/回调不变 | ply_14_test TST-T54 全绿 |
| HOME（mini_player_bar.dart:142-158） | _showQueueSheet 签名删 queue 参数 | mini bar 布局/按钮不变 | ply_08 既有 mini bar 测试全绿 |
| BRW（browser_provider.dart currentPlayQueueProvider） | 新增一个 watch 订阅方（sheet） | provider 语义不变 | P10 纪律：订阅方写入路径已全（onQueueChanged 单一写入点 player_provider.dart:121-132）——回归断言：删除/切歌/插入后 provider 更新的既有测试全绿（play_mode_queue_writeback_test 等） |
| Player（playback_orchestrator.dart:318-325） | 越界兜底消费方不变 | 零改动 | orchestrator 既有测试（ref_14_test 等）全绿 |
| 测试侧 | ply_08 装配改造 | — | cross-imports.sh all 零基线外违规；analyze 0 warning |

---

## §8 平台特性与手动 QA

设计前已逐条核对 `docs/dev/platform-pitfalls.md`：

- **P13**（async gap 中 UI 状态被旧数据重建 / 列表项缺 Key 按位置匹配错乱）：本 REF 直接处置——列表项一律 `ValueKey(file.path)`（INV2），数据源改 live watch 消除快照陈旧。
- **P10**（多处订阅的数据源，写一个漏一个）：currentPlayQueueProvider 写入点单一（orchestrator.onQueueChanged → player_provider.dart:121-132），sheet 只新增订阅不新增写入——无"写一个漏一个"风险。
- **P11**（Riverpod build 期间禁止修改其它 provider）：空态裁决"不自动 pop"即为此（build 期间无导航副作用）；删除/切歌副作用全部在用户事件回调与既有 provider 更新链内。
- 其余 P1~P17 不触及（无平台通道、无超时层改动）。

**真机风险列**（fake 测不到、只有真机会出问题的）：

| 风险 | 近似测试方案 | 测不了 → 进 mqa-backlog |
|---|---|---|
| 真机上 modal bottom sheet 打开时队列被外部（通知栏切歌）更新的重建视觉 | ref_05_queue_sheet_live_test.dart 用例①④（watch 重建 + key 稳定） | 无（重建逻辑全在 widget 层，平台通道不参与） |
| 快速连点删除多个条目时的 widget 复用错位 | 用例④ ValueKey 断言 + 多删场景用例 | 无（ValueKey 修复即 P13 处置） |

本功能不涉及平台原生特性，全部可在 `flutter test` 中验证 → `manual_qa_required = false`。

---

## §9 dev-status.json 条目对照

```json
"REF-05": {
  "spec_file": "docs/features/REF-05.md",
  "spec_anchored_files": [
    "lib/features/player/widgets/queue_sheet.dart",
    "lib/features/player/player_screen.dart",
    "lib/features/player/widgets/mini_player_bar.dart",
    "lib/features/player/domain/playback_orchestrator.dart",
    "lib/features/browser/browser_provider.dart"
  ],
  "scenarios": ["REF-05-S1", "REF-05-S2", "REF-05-S3", "REF-05-S4", "REF-05-S5", "REF-05-S6", "REF-05-S7"],
  "invariants": ["REF-05-INV1", "REF-05-INV2"],
  "algorithms": [],
  "manual_qa_required": false,
  "user_acceptance_text": "见 §1.2"
}
```
