# BUG-04 — setMediaItemFromPath 零生产调用方：通知栏/锁屏永远无曲名、时长不更新

## §0 头部元数据

```yaml
id: BUG-04
name: 通知栏/锁屏 mediaItem 从不更新（setMediaItemFromPath 零生产调用方）
priority: P1
status: active
created_at: 2026-08-16
last_updated: 2026-08-16
spec_anchored_files:
  - lib/core/services/audio_handler.dart
  - lib/features/player/player_provider.dart
cross_module_impacts: [PLY]
parent_feature: Player（音频播放/Player 模块）
manual_qa_required: true        # 涉 audio_service 通知栏/锁屏曲目展示
```

---

## §1 用户视角

### 1.0 原始需求（用户原话逐字记录）

来源：`docs/cr/cr-20260816-0802-player.md` B2（cr 复核已确认仍存在）：

> #### B2. 通知栏/锁屏 mediaItem 从不更新：`setMediaItemFromPath` 自 D-1 重构后零生产调用方
> - 类型：BUG / 严重度：Major / 维度：正确性（功能缺失）
> - 证据：
>
> `lib/core/services/audio_handler.dart:170-178`（唯一 MediaItem 构造点，无生产调用）：
> ```dart
> void setMediaItemFromPath(String filePath, {Duration? duration}) {
>   final title = extractTitleFromPath(filePath);
>   mediaItem.add(MediaItem(id: filePath, title: title, duration: duration, artUri: null));
> }
> ```
> `lib/features/player/player_provider.dart:130`（生产代码唯一的 mediaItem 写操作——只写 null）：
> ```dart
> (ref.read(audioHandlerProvider) as NasAudioHandler?)?.mediaItem.add(null);
> ```
> `lib/core/services/audio_handler.dart:162-166`（时长更新依赖 mediaItem 非空，永不生效）：
> ```dart
> if (duration != null && mediaItem.value != null) { mediaItem.add(...); }
> ```
> git 证据：`git log -S "setMediaItemFromPath("` 显示调用曾存在于 `player_screen.dart`，commit `45919a9`（D-1 提取统一加载入口）删除后无替代。
> - 复现路径：播放任意曲目 → 下拉通知栏 / 锁屏 → 期望显示当前曲名；实际 mediaItem 恒为 null，通知无曲名（或空标题），`_onDurationChanged` 的时长更新同样失效。
> - 自检答案：**测试假设错（集成点零覆盖）**。`test/core/services/audio_handler_test.dart:327-341` 直接调 `handler.setMediaItemFromPath` 断言广播，锚定的是方法自身行为；没有任何测试断言"生产代码在加载成功后调用它"。
> - 修复建议：在 provider 层（与 `_startPlaybackListeners` 同处，P8 编排层语义）加载成功后调 `setMediaItemFromPath(queue.current.path)`；mini bar/queue 变更时同步更新。

### 1.1 这一功能干什么（一句话）

让通知栏/锁屏控件在播放和切歌时显示当前曲目名与时长——加载成功与队列变更时把当前曲目推送到 audio_service 的 mediaItem 流。

### 1.2 用户期望的场景

| ID | 你看到的样子 | 期望行为 |
|----|----|----|
| U1 | 正在播放一首歌，下拉通知栏 | 通知栏显示当前曲名（修复前：无曲名/空标题） |
| U2 | 歌曲自然播完自动切到下一首 | 通知栏曲名跟着变成新曲目名 |
| U3 | 在播放单里手动点另一首 | 通知栏曲名跟着变 |
| U4 | 队列被清空/停止播放 | 通知栏曲目信息被清空（保持现有行为） |
| U5 | 播放进度栏显示歌曲总时长 | 通知栏/锁屏上的时长信息与播放页一致（修复前 `_onDurationChanged` 因 mediaItem 为 null 永不生效） |

---

## §2 已实现的功能骨架（代码锚点）

### 2.1 文件与分层

| 层 | 文件 | 行数 | 角色 |
|---|---|---|---|
| Core | `lib/core/services/audio_handler.dart` | 346 | setMediaItemFromPath（170-178，唯一 MediaItem 构造点，零生产调用）；_onDurationChanged（162-166，依赖 mediaItem 非空）；mediaItem 流（83） |
| Provider | `lib/features/player/player_provider.dart` | 401 | onQueueChanged（121-131，唯一 mediaItem 写点 :130 只写 null）；_startPlaybackListeners（332-339）；loadAndPlay/skip/select 包装（341-373） |
| 契约 | `lib/core/contracts/audio_handler_contract.dart` | 94 | IAudioHandler.setMediaItemFromPath 声明 |
| 测试 | `test/core/services/audio_handler_test.dart` | 407 | :327-341 直接调 setMediaItemFromPath 断言广播（锚定方法自身，不锚定生产调用） |
| 测试 | `test/features/player/bug_04_repro_test.dart` | 本 spec §5.4 | 本 Bug 门禁（修复前 FAIL，已用 repro-test.sh fail 确认） |

### 2.2 关键 Provider 表

| Provider 名 | 类型 | 实现位置 | 用途 |
|---|---|---|---|
| audioHandlerProvider | Provider<IAudioHandler?> | player_provider.dart:69 | 通知栏控制入口（main.dart:65 override 为真实 handler） |
| loadAndPlayProvider / skipToNextProvider / skipToPreviousProvider / selectQueueIndexProvider | Provider<Future<TrackLoadResult> Function()> | player_provider.dart:341-373 | 加载成功统一走 `_startPlaybackListeners`（332-339） |

### 2.3 状态机图

本 Bug 不涉状态机（mediaItem 是命令式流推送），跳过。

---

## §3 行为规约（Given-When-Then）

### 3.1 现有行为（逆抽，缺陷态）

- **[BUG-04-S1]** setMediaItemFromPath 是唯一 MediaItem 构造点，但生产代码零调用
  ```
  Given lib/ 生产代码
  Then setMediaItemFromPath 仅存在于定义处（audio_handler.dart:170-178）
  And 无任何生产调用方（git 证据：45919a9 删除 player_screen 内调用后无替代）
  ```
  Code evidence: `lib/core/services/audio_handler.dart:170-178`；`git log -S "setMediaItemFromPath("`（cr 证据，2026-08-16 核实）。

- **[BUG-04-S2]** 生产唯一 mediaItem 写点只写 null（队列清空时）
  ```
  Given orchestrator 队列变为 null（removeTrack 清空 / 连接切换）
  When onQueueChanged(null) 触发
  Then (audioHandlerProvider as NasAudioHandler)?.mediaItem.add(null)
  ```
  Code evidence: `lib/features/player/player_provider.dart:121-131`（:130）。

- **[BUG-04-S3]** _onDurationChanged 的时长更新依赖 mediaItem 非空 → 永不生效
  ```
  Given 播放中 durationStream 发出时长
  When _onDurationChanged(duration) 执行
  Then duration != null 且 mediaItem.value != null 才 copyWith 时长
  And mediaItem.value 恒 null（S2）→ 时长更新分支永不执行
  ```
  Code evidence: `lib/core/services/audio_handler.dart:162-166`。

- **[BUG-04-S4]** 加载成功统一经 _startPlaybackListeners（修复接线的汇合点）
  ```
  Given loadAndPlay/skip/select 返回 loaded
  When 包装函数执行成功分支
  Then 一律调用 _startPlaybackListeners(ref)（:344/:352/:361/:370）
  ```
  Code evidence: `lib/features/player/player_provider.dart:332-339`、`:344`、`:352`、`:361`、`:370`。

### 3.2 修复方案（status: new）

- **[BUG-04-S5]** 加载成功（loaded）后同步 mediaItem 到当前曲目（修改点 1） （status: new）
  ```
  Given loadAndPlayProvider / skipToNextProvider / skipToPreviousProvider /
        selectQueueIndexProvider 任一返回 loaded
  When 成功分支执行
  Then handler.setMediaItemFromPath(queue.current.path) 被调用
        （handler 为 null 时空操作，不抛错）
  And mediaItem 携带曲名（extractTitleFromPath）与 id=queue.current.path
  否定断言:
    - 加载失败（failed/superseded）不得推送/变更 mediaItem
    - handler 为 null（AudioService.init 失败）时不得抛错
    - 不得改动 mediaItem 的 artUri（保持 null 默认图标）
  ```
  **修改点**：`lib/features/player/player_provider.dart` 新增私有辅助函数并在 `_startPlaybackListeners`（:332-339）内调用（四个 loaded 分支已统一汇聚于此，P8 编排层语义）：
  ```dart
  /// BUG-04（cr-20260816-0802 B2）：加载成功/队列变更时把当前曲目推送到
  /// audio_service mediaItem 流，通知栏/锁屏才能显示曲名与时长。
  /// handler 为 null（AudioService.init 失败）时空操作。
  void _syncMediaItemToHandler(Ref ref) {
    final h = ref.read(audioHandlerProvider);
    if (h == null) return;
    final q = ref.read(currentPlayQueueProvider);
    if (q == null || q.length == 0) return;
    h.setMediaItemFromPath(q.current.path);
  }
  ```
  在 `_startPlaybackListeners`（:332-339）函数体开头插入 `_syncMediaItemToHandler(ref);`。
  **可行性依据（铁律 6）**：`setMediaItemFromPath` 已是 IAudioHandler 契约方法（audio_handler_contract.dart 声明，audio_handler.dart:170-178 实现），调用方式与现有 `onQueueChanged` 内强转调用（player_provider.dart:130）同文件同风格；`ref.read(audioHandlerProvider)` 在 provider 层使用已有大量实证（:130、:242）。**注意**：契约方法签名是 `void setMediaItemFromPath(String filePath, {Duration? duration})`——直接调用即可，无需强转（:130 强转是访问 BehaviorSubject 特需，本处不需要）。

- **[BUG-04-S6]** 队列变更（非空）时同步 mediaItem（修改点 2） （status: new）
  ```
  Given orchestrator 队列变更（onQueueChanged 触发，含切歌/增删曲目/恢复队列）
  When 新队列非空
  Then mediaItem 同步为新队列 current 曲目（标题/id 跟随）
  And 队列为 null 时保持现有 null 推送（S2 不变）
  否定断言:
    - 队列非空时不得把 mediaItem 置 null
    - 队列为 null 时不得推送任何非 null MediaItem
  ```
  **修改点**：`lib/features/player/player_provider.dart:121-131` onQueueChanged 内，在现有 `if (q == null) { ...mediaItem.add(null) }` 之外补非空分支：`if (q != null) _syncMediaItemToHandler(ref);`。本修改点与 S5 叠加时，两处调用幂等（同曲目重复推送 MediaItem 值相同，BehaviorSubject 去重与否均无害）。
  **边界**：insertAfterCurrent（orchestrator.dart:380-385）只变队列不变 current——onQueueChanged 仍触发，mediaItem 值不变（同曲目同 path），幂等无副作用。

- **[BUG-04-S7]** 时长更新恢复生效（修复后的既有代码路径） （status: new）
  ```
  Given 加载成功后 mediaItem 非空（S5/S6）
  When durationStream 发出新时长（_onDurationChanged）
  Then mediaItem copyWith(duration) 执行 → 通知栏/锁屏时长正确
  否定断言:
    - mediaItem 为 null 时不抛错（保持 :162-166 的空判断）
    - 时长更新不得改 title/id/artUri
  ```
  Code evidence（修改点）: `lib/core/services/audio_handler.dart:162-166` 本身不动——mediaItem 非空后该分支自然生效。

**边界裁决（弱模型照此实现，无需二次判断）**：

| 边界情况 | 裁决 |
|---|---|
| handler 为 null（AudioService.init 失败，main.dart:49） | `_syncMediaItemToHandler` 先判空返回，不抛错 |
| 队列 null / 空队列 | 不推送（S5 守卫）；onQueueChanged 的 null 分支维持现状（S6） |
| 加载 failed / superseded | 不推送、不改动已有 mediaItem（S5 否定断言） |
| 同曲目重复推送（reconnect/快路径） | 幂等，允许重复 add（BehaviorSubject 无长度限制；值相同） |
| 通知栏在修复前已显示的陈旧标题（若曾有） | 下一次 loaded/队列变更即被新值覆盖，无需迁移逻辑 |
| PlayerScreen "跳过加载"快路径（player_screen.dart:55-59 → reconnectPlaybackListenersProvider） | reconnect 不调 _startPlaybackListeners —— 但快路径要求 source 匹配，mediaItem 已由上次 loaded 推送过；不新增接线（防重复副作用） |

---

## §4 不变量

- **[BUG-04-INV1]** mediaItem 内容恒等于"当前队列 current 曲目"的投影（或 null）
  证据：修复后 `_syncMediaItemToHandler`（S5/S6 修改点）读取 `currentPlayQueueProvider`；对照 `player_provider.dart:130` 的 null 语义（队列空 → null）。

- **[BUG-04-INV2]** 通知栏曲目信息只经 IAudioHandler.setMediaItemFromPath 与既有 null 推送两条路径写入，不得新增第三条
  证据：`audio_handler.dart:170-178`（唯一构造点）+ `player_provider.dart:130`（唯一 null 写点）+ 修复修改点。

- **[BUG-04-INV3]** mediaItem.artUri 恒为 null（默认图标，无封面机制）
  证据：`audio_handler.dart:176`（`artUri: null`）；修复不新增 artUri 写入。

---

## §5 测试规约

### 5.1 现有测试清单

| 测试文件 | 覆盖的 Scenario / INV | 备注 |
|---|---|---|
| test/core/services/audio_handler_test.dart:327-341 | BUG-04-S1 的方法自身行为 | 直接调 setMediaItemFromPath 断言广播——不锚定生产调用（cr 自检答案） |
| test/features/player/bug_04_repro_test.dart | BUG-04-S5 / S6 / S7 / INV1 / INV2 / INV3 | 本 Bug 门禁（修复前 FAIL，已用 repro-test.sh fail 确认） |

### 5.2 测试 ID 派生清单（dev-exe 派发测试 Agent 用）

```
BUG-04-S1 … S7        # Scenario（S1~S4 现状锚定，S5~S7 修复目标）
BUG-04-INV1 … INV3    # 不变量
BUG-04-MAN1 …         # 手动 QA 步骤（见 §8）
```

dev-exe 要求：S5/S6/S7/INV1~3 由 §5.4 门禁测试覆盖；S1~S4 由门禁测试与既有 audio_handler_test 锚定。

### 5.3 测试覆盖盲点（dev-plan 写本文档时识别）

| 未覆盖 ID | 现状 | 应补偿方式 |
|---|---|---|
| BUG-04-MAN1~MAN2 | 通知栏/锁屏展示为平台通道行为 | 进 mqa-backlog（§8） |
| 时长更新（S7）的流式驱动 | 门禁 T1 后 handler.mediaItem 已非空；时长断言可加：durationStream 发出后 mediaItem.duration 更新 | dev-exe 可在门禁测试内补一条 duration 断言（audio_handler_test.dart:327-341 已有方法级锚定） |

### 5.4 测试文件位置（spec-scan --gate 硬校验）

| 测试文件 | 覆盖 ID | 说明 |
|---|---|---|
| test/features/player/bug_04_repro_test.dart | BUG-04-S5、BUG-04-S6、BUG-04-S7、BUG-04-INV1、BUG-04-INV2、BUG-04-INV3 | 门禁：dev-exe 修复后必须 PASS（repro-test.sh pass） |

---

## §6 算法样例

本 Bug 不涉纯函数算法，跳过。

---

## §7 跨模块影响

`bash cross-imports.sh impact lib/core/services/audio_handler.dart lib/features/player/player_provider.dart`（2026-08-16）→ 引用方：

| 其它 feature | 影响点 | 影响条件 | 需要补的回归断言 |
|---|---|---|---|
| Player（player_provider.dart 各包装 :341-373） | _startPlaybackListeners 新增 mediaItem 同步 | 四个 loaded 分支统一汇聚，行为一致 | bug_04_repro_test.dart PASS；ply_01~14 全绿 |
| 入口（main.dart:65） | audioHandlerProvider override 提供真实 handler | 契约不变 | 编译 + analyze 0 warning |
| 通知栏链路（BUG-01/BUG-02） | skip 回调与 mediaItem 并行工作 | 无交互面（回调驱动切歌 → 切歌后 mediaItem 跟随） | bug_01/bug_02 repro PASS |
| 测试侧（audio_handler_test.dart:327-341） | 方法级断言不变 | 生产接线新增不破坏方法自身行为 | audio_handler_test 全绿 |
| BRW（browser_provider.dart restoreQueueFromPrefsProvider） | 恢复队列 → onQueueChanged → mediaItem 同步 | 修复前 mediaItem 恢复路径为 null；修复后恢复即有曲名 | o3_*/net1 队列恢复测试全绿（断言不涉及 mediaItem，不受影响） |

---

## §8 平台特性与手动 QA

设计前已逐条核对 `docs/dev/platform-pitfalls.md`：本 Bug 是 **P8**（播放生命周期资源归编排层持有）的应用面——mediaItem 同步放在 provider 层（_startPlaybackListeners / onQueueChanged），不绑定任何页面 dispose；与 P3（playing 状态不传播）无交集；P12（值对象同步）不涉及（MediaItem 非应用值对象）。

**真机风险列**（fake 测不到、只有真机会出问题的）：

| 风险 | 近似测试方案 | 测不了 → 进 mqa-backlog |
|---|---|---|
| 通知栏是否真的显示曲名 | bug_04_repro_test.dart 断言 mediaItem 内容（修复后 PASS） | BUG-04-MAN1：真机播放任意曲目 → 下拉通知栏 → 期望曲名与播放页一致；切下一首 → 曲名跟随 |
| 锁屏控件曲名/时长展示 | 同上 | BUG-04-MAN2：锁屏后查看曲名与进度时长 |
| 队列清空后通知栏清空 | bug_04 T3 | BUG-04-MAN3：清空队列/停止播放后通知栏无残留曲名 |

涉及 audio_service 通知栏/锁屏 → `manual_qa_required = true`。

---

## §9 dev-status.json 条目对照

```json
"BUG-04": {
  "spec_file": "docs/features/BUG-04.md",
  "spec_anchored_files": [
    "lib/core/services/audio_handler.dart",
    "lib/features/player/player_provider.dart"
  ],
  "scenarios": ["BUG-04-S1", "BUG-04-S2", "BUG-04-S3", "BUG-04-S4", "BUG-04-S5", "BUG-04-S6", "BUG-04-S7"],
  "invariants": ["BUG-04-INV1", "BUG-04-INV2", "BUG-04-INV3"],
  "algorithms": [],
  "manual_qa_required": true,
  "user_acceptance_text": "见 §1.2"
}
```
