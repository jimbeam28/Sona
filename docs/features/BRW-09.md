# BRW-09 文件列表"下一曲播放"图标

> 文档类型：功能详细设计（行为规约锚到代码 + 新需求 Scenario 锚到目标实现文件）
> 维护策略：仅在该功能下次需要新增/修改时由 dev-plan 流程更新
> 创建日期：2026-06-28（首批逆抽 + 增量加新需求）

---

## §0 头部元数据

```yaml
id: BRW-09
name: 文件列表"下一曲播放"图标
priority: P1
status: draft
created_at: 2026-06-28
last_updated: 2026-06-28
spec_anchored_files:
  - lib/features/browser/widgets/file_list_item.dart
  - lib/features/browser/browser_screen.dart
  - lib/features/browser/browser_provider.dart
  - lib/features/player/player_provider.dart
  - lib/features/player/domain/playback_orchestrator.dart
  - lib/shared/models/play_queue.dart
cross_module_impacts: [PLY]
manual_qa_required: false
```

---

## §1 用户视角（你来扫这一节就够）

### 1.1 这一功能干什么（一句话）

在文件浏览列表中，每首音乐右侧加一个"下一曲播放"小图标，点击后**把这首歌插入到当前播放队列中正在播放的曲目的后一个位置**——这样当前这首播完，下一首就是你刚点的这首。

### 1.2 用户期望的场景（你来扫这一节就够）

| ID | 你看到的样子 | 期望行为 | 决策记录 |
|----|----|----|---|
| U1 | 正在播放音乐 X，点歌 Y 的"下一曲"图标 | 队列：[...X, **Y**, 原下一曲, ...]；X 播完 Y 立刻播；Snack"已加入下一曲：Y" | — |
| U2 | 没在播放任何音乐时看列表 | 所有"下一曲"小图标都灰禁点不动，hover/长按提示"请先开始播放后再用此功能" | 你 ack：按钮灰禁 |
| U3 | shuffle 随机模式下正在播 X，点 Y 的"下一曲"图标 | 队列仍按 files 顺序在 currentIndex+1 处插入 Y；shuffle 序列后续是否调到它由 shuffle 自身决定 | 你 ack：按 files 顺序插入 |
| U4 | 队列中已有 Y（不是当前），再点 Y 的"下一曲"图标 | 队列多一份 Y 副本插到 currentIndex+1；不去重、不移动原位 | 你 ack：队列中多一份 |
| U5 | 点的是当前正在播放的 X 的"下一曲"图标 | 队列下一首位置再加一份 X（X 会重复播两遍）；不报错 | 你 ack：允许下一首再来一份 |
| U6 | 同一首 Y 连点"下一曲"图标 3 次 | 队列 currentIndex+1..+3 位置依次插入 3 份 Y；4 份相同 Y 在队列里 | 你 ack：插多份 |
| U7 | 点击成功 | 弹底部 SnackBar"已加入下一曲：Y"（2 秒消失） | — |
| U8 | 当前在播但队列已只剩这首（无下一首位置） | 在 currentIndex+1 = files.length 处追加 Y，Y 即下一首；正常工作 | — |

---

## §2 已实现的功能骨架（代码锚点）

### 2.1 文件与分层（涉及本功能的）

| 层 | 文件 | 角色 |
|---|---|---|
| UI（文件列表项） | `lib/features/browser/widgets/file_list_item.dart` (127 行) | `AudioFileListTile` widget —— 当前 ListTile 已含 `onTap`、`onLongPress`、`progressPercentage`，**缺 trailing action** |
| UI（文件浏览页） | `lib/features/browser/browser_screen.dart` (347 行) | `BrowserScreen._FileList` 渲染 tile，`onFileTap` 在 `:87-129` 已实现"点歌→建新 PlayQueue→跳 player"，**无"加入已有队列"分支** |
| Provider | `lib/features/player/player_provider.dart` (331 行) | `currentPlayQueueProvider`、`playbackOrchestratorProvider`。`:308-319` 有 `removeTrackFromQueueProvider` 协议，**无 "insert" 对等 provider** |
| Domain（编排器） | `lib/features/player/domain/playback_orchestrator.dart` (447 行) | `removeTrack(index)`、`skipToNext`、`selectQueueIndex`。`:322-342` 是 removeTrack 范本，本需求参考它产出 `insertAfterCurrent(NasFile)` |
| Shared Model | `lib/shared/models/play_queue.dart` (309 行) | `PlayQueue.withIndex`、`withMode`、`withoutIndex`、`withStartPosition`。**无 "insertAfterCurrent" 方法** |
| 测试 | 现有 `test/features/browser/brw_07_test.dart` 等 12 份 | 测 BRW-01~08 集合，本功能新增 `brw_09_test.dart` |

### 2.2 关键 Provider 表

| Provider 名 | 类型 | 实现位置 | 用途 / 本功能关系 |
|---|---|---|---|
| `currentPlayQueueProvider` | `StateProvider<PlayQueue?>` | `shared/di/providers.dart`（外部） | 队列状态的单一真相源，insert 后将被刷新 |
| `playbackOrchestratorProvider` | `Provider<PlaybackOrchestrator>` | `player_provider.dart:89` | 已通过 `onQueueChanged` 写回 `currentPlayQueueProvider`——所以 insert 走 orchestrator 就会自动 sync UI |
| `audioPlayerProvider` | `Provider<AudioPlayer>` | `player_provider.dart:45` | 判断 `player.playing` 决定图标是否启用 |

### 2.3 状态机

本功能不引入新状态机，是在 Browser UI 上新增一个动作。队列管理本身也没有 PlayQueue 状态机——它是值类型 + 操作方法。

现状描述：
- PlayQueue 当前只能 `withIndex / withMode / withoutIndex / withStartPosition / advanceShuffle / retreatShuffle` —— 都是返回**新队列**的纯函数。
- 本需求将新增 `insertAfterCurrent(NasFile)` 同类型纯函数。

---

## §3 行为规约（Given-When-Then）

### 3.1 Browser UI 入口

- **[BRW-09-S1] `status: new`** 音乐文件 tile 右侧出现"下一曲"图标
  ```
  Given 用户在文件浏览页，列表中显示若干音频文件
  Then 每个 AudioFileListTile 右侧（大小估算标签之后）出现"下一曲"图标（Icons.queue_music 或 Icons.playlist_add）
  ```
  实现目标：`lib/features/browser/widgets/file_list_item.dart` `AudioFileListTile` 增强 trailing 行为
  依赖文件：`lib/features/browser/widgets/file_list_item.dart`

- **[BRW-09-S2] `status: new`** 没正在播任何音乐时图标灰禁
  ```
  Given audioPlayerProvider.playing == false 或 currentPlayQueueProvider == null
  Then 所有 AudioFileListTile 的"下一曲"图标 disabled（灰色）
  And 长按/hover tooltip 显示"请先开始播放后再用此功能"
  ```
  实现目标：`browser_screen.dart` 在构建 tile 时 watch `audioPlayerProvider.playing` 与 `currentPlayQueueProvider`，传入 `playNextEnabled: bool`
  依赖文件：`lib/features/browser/browser_screen.dart`、`lib/features/browser/widgets/file_list_item.dart`

- **[BRW-09-S3] `status: new`** shuffle 模式下图标仍可用，按 files 顺序插入
  ```
  Given PlayMode.shuffle 且正在播放 X
  When 点击 Y 的"下一曲"图标
  Then 队列调用 insertAfterCurrent(Y) 在 files[currentIndex+1] 插入 Y
  And shuffle 序列不专门调整（自然后续可能拍中）
  ```
  实现目标：`lib/shared/models/play_queue.dart` `insertAfterCurrent` 方法不感知 playMode；按 files 索引插入

### 3.2 队列插入行为

- **[BRW-09-S4] `status: new`** 队列插入操作完整动作
  ```
  Given currentPlayQueueProvider 含队列 Q 长度 N，正播 files[ci]，audioPlayerProvider.playing == true
  When 用户点 Y 的"下一曲"图标
  Then 1) PlaybackOrchestrator.insertAfterCurrent(Y) 被调用
       2) queue = Q.copyWith files = [..., files[ci], Y, files[ci+1], ..., files[N-1]]，currentIndex 不变（仍指原 X）
       3) onQueueChanged 触发 currentPlayQueueProvider 刷新为新 queue
       4) 弹 SnackBar "已加入下一曲：Y"
  ```
  目标锚点（新增代码位置参考）：`playback_orchestrator.dart:322-342 removeTrack` 的对称实现
  依赖文件：`lib/features/player/domain/playback_orchestrator.dart`、`lib/features/player/player_provider.dart`、`lib/shared/models/play_queue.dart`、`lib/features/browser/browser_screen.dart`

- **[BRW-09-S5] `status: new`** Y 与队列中已有的某首重复——不 dedup
  ```
  Given 队列中已含 Y（不是当前播的）
  When 点击 Y 的"下一曲"图标
  Then 在 currentIndex+1 处插入新副本；原位 Y 不动；队列出现两份 Y
  ```
  实现目标：`PlayQueue.insertAfterCurrent` **不去重**

- **[BRW-09-S6] `status: new`** Y 就是当前在播放曲——下一曲再来一份
  ```
  Given 当前播放 X
  When 点击 X 的"下一曲"图标
  Then 队列在 currentIndex+1 处插入 X 副本；下一首将再播一遍 X
  ```
  实现目标：`PlayQueue.insertAfterCurrent` 不做"Y == current"特判

- **[BRW-09-S7] `status: new`** 连点同一首 Y 多次
  ```
  Given 连续点 Y 的"下一曲"图标 3 次
  Then 队列依次变成：[..., X, Y, ...] → [..., X, Y, Y, ...] → [..., X, Y, Y, Y, ...]
  And 弹 3 次 SnackBar
  ```
  实现目标：每次点都 insertAfterCurrent 一次

- **[BRW-09-S8] `status: new`** 当前在播是队列尾——插入位置为 files.length
  ```
  Given currentIndex == files.length - 1（队尾）
  When 点击 Y 的"下一曲"图标
  Then 队列变成 [..., files[N-1], Y]，currentIndex 不变仍指 N-1
  And 下一首播放就是 Y
  ```
  实现目标：`insertAfterCurrent` 插入位置 = `currentIndex + 1`，不越界

- **[BRW-09-S9] `status: new`** 队列为空（极端：未在播）不允许——由 UI 层提前禁用
  ```
  Given audioPlayerProvider.playing == false
  Then "下一曲"图标 disabled，点击不触发任何 provider 调用
  ```
  实现目标：`browser_screen.dart` 仅在 `playing == true` 时传入 `onPlayNext` 回调；否则传 null

---

## §4 不变量

- **[BRW-09-INV1] `status: new`** `insertAfterCurrent` 不改变 `currentIndex`，只改 `files` 列表。
  实现目标：`lib/shared/models/play_queue.dart` `insertAfterCurrent` 返回的新队列 currentIndex 与入参相同

- **[BRW-09-INV2] `status: new`** `insertAfterCurrent` 不感知 playMode（不挑 shuffle/repeatOne/repeatAll）——它只改 `files`，不改 `_shuffleOrder`。
  实现目标：`insertAfterCurrent` 实现保持与 `withoutIndex` 同样的"洗牌序列不重新构造"原则；shuffle 模式下序列后续拍中由原 shuffle 逻辑负责

- **[BRW-09-INV3] `status: new`** 一次"下一曲"操作一次插入——不去重、不移动、不替换原位元素。
  实现目标：`insertAfterCurrent` `List.insert(currentIndex+1, file)`

- **[BRW-09-INV4] `status: new`** "下一曲"图标 disabled 状态 by `player.playing == false || currentPlayQueue == null`，是 `play` 的纯函数——不允许 race（用户连点不会因为时序不同结果不同）。
  实现目标：`browser_screen.dart` `build` 用 `ref.watch(audioPlayerProvider).playing` + `ref.watch(currentPlayQueueProvider) != null` 决定 enabled 状态

---

## §5 测试规约

### 5.1 现有测试清单

无与本需求直接相关的现有测试文件——新功能，新建测试。

### 5.2 测试 ID 派生清单（dev-exe）

```
BRW-09-S1 ~ S9       # 9 个 Scenario
BRW-09-INV1 ~ INV4   # 4 个不变量
```

按 dev-exe skill：每个未覆盖 ID 必须产出一条 test 或一项手动 QA。本功能因不涉及平台原生，全部为自动化测试。

测试文件结构建议：
```
test/features/browser/brw_09_test.dart                 # S1, S2, S9, INV4（widget test）
test/features/player/ply_insert_after_current_test.dart # S4~S8, INV1~INV3（domain 单元测试）
test/shared/play_queue_insert_test.dart                 # PlayQueue.insertAfterCurrent 纯函数单元测试
```

### 5.3 测试覆盖盲点（dev-plan 标识后 dev-exe 必补）

| 未覆盖 ID | 现状 | 应补偿方式 |
|---|---|---|
| BRW-09-S1~S9 | 全部新增 | 全部新建测试 |
| BRW-09-INV1~INV4 | 全部新增 | 全部新建测试 |

### 5.4 关键测试要点

- **S2 player.playing=false 时图标灰禁**：用 widget test，mock `AudioPlayer` 让 `playing=false`，assert `find.byIcon(Icons.queue_music)` 找到的 IconButton `onPressed == null`
- **S3 shuffle 下仍按 files 顺序插入**：domain 单元测试，构造 shuffle 模式 PlayQueue，调 `insertAfterCurrent(Y)`，断言新 files 顺序满足 ci+1 位置是 Y
- **S8 当前是队尾时插入位置 = files.length**：domain 单元测试，ci=N-1，插入后 files.length = N+1，新元素在 index N
- **S9 player 不在播时点击不调用 provider**：widget test，断言 `playbackOrchestratorProvider` 上的 insertAfterCurrent 方法被调用 0 次
- **INV1/INV2/INV3**：domain 单元测试，直接断言 PlayQueue 状态字段
- **INV4**：widget test + 多次 click 同一首要有 3 次 SnackBar

---

## §6 算法样例

`PlayQueue.insertAfterCurrent(NasFile file)`：

```
ALG insertAfterCurrent:
  入参与现状：
    Q = PlayQueue(files: F, currentIndex: ci)
    file = 待插入的 NasFile
  implement:
    newFiles = F.toList()..insert(ci + 1, file)
    return PlayQueue(files: newFiles, currentIndex: ci, startPositionMs: startPositionMs, playMode: playMode, shuffleOrder: _shuffleOrder, shufflePosition: _shufflePosition)

边界：
  ci == F.length - 1（队尾） → newFiles = F + [file]，新 file 在 index F.length
  playing = false → 由 UI 层禁用调用方，insertAfterCurrent 不被调
  shuffleMode → 不重算 _shuffleOrder
异常：
  Q == null → orchestrator.insertAfterCurrent 返回 false / SnackBar 弹失败
```

---

## §7 跨模块影响

| 其它 feature | 影响点 | 影响条件 | 需要补的回归断言 |
|---|---|---|---|
| PLY | `PlayQueue` 新增方法，`PlaybackOrchestrator` 新增方法，`player_provider` 新增 provider | 总是 | `removeTrackFromQueueProvider` 仍正常工作（同一 file 多副本应该删到第一个匹配即停）；`skipToNext` 在 ci 后插入了 Y 仍按 ci=N 跳到 Y；`selectQueueIndex` 在插入后 index mapping 应重新对齐 |

回归测试项需新增：
- PLY-REG-1 插入后 skipToNext 跳到正确位置
- PLY-REG-2 队列含重复元素时 removeTrack(0) 只删第一个副本
- PLY-REG-3 PlayerQueue.toMap / fromMap 与含插入副本的 queue 互通（持久化不丢重复元素）

---

## §8 平台特性与手动 QA

本功能**不涉及** `audio_service` / `AudioFocus` / `MethodChannel` / 通知栏——全部可在 `flutter test` 中验证，无需手动 QA。

`§0 manual_qa_required = false`。

若未来 snackbar 选择`ScaffoldMessenger.showSnackBar` 之外的方式（如 NotificationBar）+ 涉及平台原生 → 升 `manual_qa_required = true` 且产出 `docs/dev/mqa-BRW-09.md`。

---

## §9 dev-status.json 条目对照

```json
"BRW-09": {
  "name": "文件列表下一曲播放图标",
  "spec_file": "docs/features/BRW-09.md",
  "spec_anchored_files": [
    "lib/features/browser/widgets/file_list_item.dart",
    "lib/features/browser/browser_screen.dart",
    "lib/features/browser/browser_provider.dart",
    "lib/features/player/player_provider.dart",
    "lib/features/player/domain/playback_orchestrator.dart",
    "lib/shared/models/play_queue.dart"
  ],
  "scenarios": ["BRW-09-S1", "BRW-09-S2", "BRW-09-S3", "BRW-09-S4", "BRW-09-S5", "BRW-09-S6", "BRW-09-S7", "BRW-09-S8", "BRW-09-S9"],
  "invariants": ["BRW-09-INV1", "BRW-09-INV2", "BRW-09-INV3", "BRW-09-INV4"],
  "algorithms": ["BRW-09-ALG1-insertAfterCurrent"],
  "test_files": [
    "test/features/browser/brw_09_test.dart",
    "test/features/player/ply_insert_after_current_test.dart",
    "test/shared/play_queue_insert_test.dart"
  ],
  "test_coverage_gaps": [
    "BRW-09-S1", "BRW-09-S2", "BRW-09-S3", "BRW-09-S4", "BRW-09-S5",
    "BRW-09-S6", "BRW-09-S7", "BRW-09-S8", "BRW-09-S9",
    "BRW-09-INV1", "BRW-09-INV2", "BRW-09-INV3", "BRW-09-INV4"
  ],
  "cross_module_impacts": ["PLY"],
  "manual_qa_required": false,
  "manual_qa_file": null,
  "user_acceptance_text": "见 docs/features/BRW-09.md §1.2",
  "impl_status": "pending",
  "test_status": "pending",
  "dependencies": [],
  "retry_count": 0,
  "last_error": "",
  "last_updated": "2026-06-28"
}
```

---

## §10 changelog

- 2026-06-28: 创建本份首版文档（基于现有代码逆抽 Browser/Player 结构 + 增量加新需求"下一曲播放"图标的 S1~S9, INV1~INV4）。所有 Scenario/INV 标 `status: new`。