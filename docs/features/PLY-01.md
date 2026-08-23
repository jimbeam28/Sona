# 功能详细设计文档：PLY-01 播放队列拖动重排

```yaml
id: PLY-01
name: 播放队列拖动重排
priority: P1
status: active
created_at: 2026-08-23
last_updated: 2026-08-23
spec_anchored_files:
  - lib/features/player/widgets/queue_sheet.dart
  - lib/features/player/player_screen.dart
  - lib/features/player/widgets/mini_player_bar.dart
  - lib/shared/models/play_queue.dart
  - lib/features/player/domain/playback_orchestrator.dart
  - lib/features/browser/browser_provider.dart
cross_module_impacts: [BRW]
manual_qa_required: false
```

---

## §1 用户视角

### 1.0 原始需求（用户原话逐字记录）

> 采纳 A 的 1~4（A2 = 队列编辑）。讨论裁决记录（2026-08-23 访谈）：
> "queue_sheet 已确认：单曲删除已存在（REF-05 改造时加了 close 按钮），A2 实际缺口是**拖动重排**。"
> 用户对 A2 无异议，按推荐执行："ReorderableListView.builder，默认长按拖动；不加拖动手柄"、"shuffle 模式禁用拖动"、"新增 PlayQueue.move(from,to)：当前曲被拖动时 currentIndex 跟着走"、"close 按钮已够用，不加 Dismissible"。

### 1.1 这一功能干什么（一句话）

在播放队列面板里长按任意一首歌并拖动，改变它在本队列中的播放顺序。

### 1.2 用户期望的场景

| ID | 你看到的样子 | 期望行为 |
|----|----|----|
| U1 | 播放器或迷你播放栏打开队列面板，队列是顺序/单曲循环/列表循环模式 | 长按任意一行可以拖起来，上下移动放下后列表顺序立即变化 |
| U2 | 拖动的是正在播放的那首 | 松手后它还是当前曲（"当前"标记跟着走），音乐不间断 |
| U3 | 拖动的是其它行，且跨越了当前曲的位置 | 当前曲高亮仍指向原来那首歌，只是它的行号变了 |
| U4 | 队列处于随机播放模式 | 行不能长按拖动（面板与顺序模式长得一样，但拖不动） |
| U5 | 重排完关掉面板再打开 | 顺序保持重排后的样子（下次冷启动也保持） |
| U6 | 正在缓冲另一首网速慢的歌时去重排 | 重排成功，正在缓冲的那首照常加载，互不干扰 |

---

## §2 已实现的功能骨架（代码锚点）

### 2.1 文件与分层

| 层 | 文件 | 关键位置 | 角色 |
|---|---|---|---|
| UI | lib/features/player/widgets/queue_sheet.dart | :14-27 QueueSheet 构造（onSelectIndex/onRemoveIndex/errorMessage 三参）；:28 watch currentPlayQueueProvider；:50-51 ListView.builder；:60 `ValueKey('$index:${file.path}')`（BUG-25 复合键）；:92-100 单曲删除按钮；:103-113 onTap 切歌 | 队列面板本体，双入口共享 |
| UI | lib/features/player/player_screen.dart | :243-260 _showQueueSheet 接线 | 全屏播放器入口 |
| UI | lib/features/player/widgets/mini_player_bar.dart | :141-156 _showQueueSheet 接线 | 迷你播放栏入口 |
| Provider | lib/features/player/player_provider.dart | :407 selectQueueIndexProvider；:413 removeTrackFromQueueProvider | 面板动作的 provider 封装 |
| Domain | lib/features/player/domain/playback_orchestrator.dart | :86 player；:97 onQueueChanged 回调；:102-106 queue setter 写回并触发同步；:353-383 removeTrack（删除语义参照系） | 队列变更编排 |
| Model | lib/shared/models/play_queue.dart | :55-62 构造（files/currentIndex/startPositionMs/playMode/shuffleOrder/shufflePosition）；:79 current getter；:94 length；:193-232 withoutIndex（index 平移规则参照系）；:246 insertAfterCurrent（BUG-04-S1 排列 remap 参照系） | 队列值对象 |
| Bridge | lib/features/browser/browser_provider.dart | :159-172 persistQueueOnChangeProvider——ref.listen(currentPlayQueueProvider) 每次变化全量写 SharedPreferences `_qKey` | 队列持久化 |

### 2.2 现有行为逆抽（本功能触及面）

- **队列数据源**：QueueSheet 内部 `ref.watch(currentPlayQueueProvider)` 取实时队列（queue_sheet.dart:28），无构造参数快照（REF-05）。
- **删除路径**：`onRemoveIndex → removeTrackFromQueueProvider → orchestrator.removeTrack(index)`（player_screen.dart:255-257 / mini_player_bar.dart:151-153 / playback_orchestrator.dart:353）。删除**当前曲**会触发 loadAndPlay 换曲；删除非当前曲只改状态不触碰播放器。
- **写回链路**：orchestrator 内部 `queue = newQueue`（:104-106 setter）→ `onQueueChanged` → Riverpod 层同步 currentPlayQueueProvider → persistQueueOnChange 自动落盘。
- **shuffle 结构**：PlayMode.shuffle 时 PlayQueue 持有独立排列 shuffleOrder + 指针 shufflePosition（play_queue.dart:55-62），显示顺序 files 数组与排列是两套坐标（BUG-24 刚修过指针锚定）。
- **键唯一性**：列表项 key 为 `'$index:${file.path}'` 复合键，静态时刻全列表唯一（queue_sheet.dart:56-59 注释 INV）。

---

## §3 行为规约（Given-When-Then）

### 3.1 模型层：PlayQueue.move

- **[PLY-01-S1] move 基础重排**
  ```
  Given 队列 [A,B,C,D]，currentIndex=2（C 为当前曲）
  When move(0, 3)（把 A 移到队尾）
  Then 返回新队列 files=[B,C,D,A]，currentIndex=1（C 跟随平移）
  And 原 queue 对象不变（值对象语义，返回新实例）
  否定断言:
    - files.length 不变（4）
    - playMode / shuffleOrder / shufflePosition / startPositionMs 字段不变
    - 不触发任何 IAudioPlayer 方法调用（纯模型函数）
  ```
  Code evidence: play_queue.dart:193-232 withoutIndex 同款值对象返回模式

- **[PLY-01-S2] move 当前曲自身**
  ```
  Given 队列 [A,B,C,D]，currentIndex=1（B）
  When move(1, 3)
  Then files=[A,C,D,B]，currentIndex=3（指针跟随 B）
  否定断言:
    - currentIndex 不指向移动前位置 1
  ```
  Code evidence: 本条为新增行为，映射规则见 §6 ALG1

- **[PLY-01-S3] move 幂等与防御**
  ```
  Given 合法队列
  When move(from==to) 或 from/to 越界（<0 或 >=length）或 length<=1
  Then 返回与输入 identical 的 this（零拷贝短路）
  否定断言:
    - 不新建 PlayQueue 实例
    - 不抛异常
  ```
  Code evidence: 新增方法；幂等风格参照 timer_service.dart:197-201 cancel 的 hadActive 短路先例

- **[PLY-01-S4] shuffle 队列模型级拒绝**
  ```
  Given playMode == PlayMode.shuffle 的队列（无论 shuffleOrder 是否非空）
  When move(任意合法 from,to)
  Then 返回 identical(this)，顺序不变
  否定断言:
    - 不修改 shuffleOrder / shufflePosition
    - 不修改 files 顺序
  ```
  Code evidence: 调用方 UI 层已禁用拖动（S8），此为模型级第二道闸；shuffle 双坐标体系见 play_queue.dart:55-62 与 BUG-24 修复（INDEX.md changelog 2026-08-23 条目）

### 3.2 编排层：PlaybackOrchestrator.moveTrack

- **[PLY-01-S5] moveTrack 纯顺序变更**
  ```
  Given orchestrator 持有活跃队列（顺序/repeatOne/repeatAll 任一模式）
  When moveTrack(from, to)（from!=to 且均合法）
  Then queue = q.move(from,to)（经 :104-106 setter 触发 onQueueChanged → provider 状态更新）
  And 返回 true
  否定断言:
    - 不调用 saveProgress()（无换曲，进度归属不变）
    - 不调用 loadAndPlay() / _gate.beginRequest()（不打断任何 in-flight 加载）
    - 不调用 player.setAudioSource / play / pause / stop / seek 中任何一个
  ```
  Code evidence: 对照组 playback_orchestrator.dart:353-383 removeTrack——wasCurrent 才 load+save；move 永远等价于"非当前曲变更"，但**不删行**。setter 写回链 :104-106

- **[PLY-01-S6] moveTrack 边界返回 false**
  ```
  Given 队列为 null，或 from/to 越界，或 queue.playMode == shuffle
  When moveTrack(...)
  Then 返回 false，queue 字段不变
  否定断言:
    - onQueueChanged 回调不被触发
  ```

### 3.3 UI 层：QueueSheet 拖动

- **[PLY-01-S7] 顺序类模式启用拖动**
  ```
  Given queue.playMode != shuffle 且 queue.length > 1
  When 渲染队列面板
  Then 使用 ReorderableListView.builder（buildDefaultDragHandles 默认 true = 移动端整行长按拖起）
  And onReorder 先做 Flutter 语义校正（newIndex > oldIndex 时 newIndex -= 1，见 §6 ALG2）再调 onReorderIndex(oldIndex, newIndex)
  And proxyDecorator 给拖动中的行加视觉高亮（Material 卡片阴影）
  否定断言:
    - 列表项 key 仍是 '$index:${file.path}' 复合形态（不回归 BUG-25 duplicate-key）
    - 现有 onTap 切歌、trailing 删除按钮、'当前' 高亮行为不变
  ```
  Code evidence: 可行性依据见 §8 平台特性表 R1（ReorderableListView API 引用）

- **[PLY-01-S8] shuffle 模式禁用拖动**
  ```
  Given queue.playMode == PlayMode.shuffle
  When 渲染队列面板
  Then 保持现有 ListView.builder 分支（不可拖动）
  And 标题区追加灰色小字提示 '随机模式下不可排序'
  否定断言:
    - onReorderIndex 回调不会被触发
    - moveTrackFromQueueProvider 不被调用
  ```

- **[PLY-01-S9] 双入口接线**
  ```
  Given player_screen.dart 与 mini_player_bar.dart 两处 showModalBottomSheet
  When 打开队列面板并完成一次合法拖动
  Then 两处都通过新参数 onReorderIndex 调用 ref.read(moveTrackFromQueueProvider)(oldIndex, newIndex)
  否定断言:
    - QueueSheet 既有三参数（onSelectIndex/onRemoveIndex/errorMessage）签名不变（仅追加可选参数，默认 null = 不启用拖动）
  ```
  Code evidence: player_screen.dart:247-258、mini_player_bar.dart:145-154 现有接线点

### 3.4 持久化与并发

- **[PLY-01-S10] 重排结果自动落盘**
  ```
  Given persistQueueOnChangeProvider 已接线（应用启动即监听）
  When moveTrack 成功改写 currentPlayQueueProvider
  Then SharedPreferences _qKey 快照更新为重排后的 filePaths/currentIndex（下次冷启动恢复该顺序）
  否定断言:
    - 不需要新增任何持久化代码（既有 ref.listen 全量写覆盖，browser_provider.dart:159-172）
  ```
  Code evidence: browser_provider.dart:159-172

- **[PLY-01-S11] in-flight 加载期间重排安全**
  ```
  Given 用户点选了慢速网络曲目 X（selectQueueIndex 已发出，SerializedRequestGate 排队中）
  When 此时拖动重排（不含 X 换位到当前曲以外的语义变化）
  Then 重排立即生效；X 的加载继续以 X 为目标完成（gate 按 request 时效判定 isLatest，moveTrack 不 bump gate）
  否定断言:
    - moveTrack 不调用 _gate.beginRequest()
    - 重排不导致 X 的加载被 superseded 或重复发起
  ```
  Code evidence: gate 时效机制 playback_orchestrator.dart:365-369 注释（removeTrack 停止前才 beginRequest）；move 无停止语义故无需 bump

---

## §4 不变量

- **[PLY-01-INV1]** move 是纯重排：files 集合（元素与数量）、playMode、startPositionMs、shuffleOrder、shufflePosition 五者恒不变，仅元素顺序与 currentIndex 导出值可变。
  证据：§3.1 S1/S4 否定断言；字段定义 play_queue.dart:55-62
- **[PLY-01-INV2]** 生产代码中 PlayQueue.move 仅被 PlaybackOrchestrator.moveTrack 一处调用；UI 层不得绕过编排层直接改 currentPlayQueueProvider 来实现重排（P10 单一写源纪律）。
  证据：orchestrator 写回链 playback_orchestrator.dart:104-106；对照 insertAfterCurrent 同款约束（play_queue.dart:246 注释块）
- **[PLY-01-INV3]** 随机模式下队列顺序不可通过任何 UI 入口改变。
  证据：S4（模型闸）+ S8（UI 闸）双保险

---

## §5 测试规约

### 5.1 现有测试清单

| 测试文件 | 覆盖 | 备注 |
|---|---|---|
| test/features/player/ref_05_queue_sheet_live_test.dart | QueueSheet live 数据源/空态/删除刷新 | 重排改造不得破坏 |
| test/features/player/bug_bug25_queue_sheet_dup_key_test.dart | 复合键唯一性（BUG-25） | 键方案不变的回归锚 |

### 5.2 测试 ID 派生清单

```
PLY-01-S1 ~ S11
PLY-01-INV1 ~ INV3
PLY-01-ALG1（move 映射）、PLY-01-ALG2（onReorder 校正）
```

### 5.3 测试覆盖盲点

| 未覆盖 ID | 现状 | 应补偿方式 |
|---|---|---|
| S11 | 现有测试无"in-flight 加载中重排"场景 | MockAudioPlayer + 手动控制 Completer 的 setAudioSource 挂起 → 期间 moveTrack → 断言 X 最终加载完成 |
| S8 | shuffle 渲染分支无 widget 断言 | widget 测试：shuffle 队列渲染 ListView 无拖动 + 提示文案存在 |

### 5.4 门禁测试文件位置

```
test/features/player/ply_01_queue_reorder_test.dart   # S1~S11 + INV1~3 + ALG1/ALG2
```
（命名核查 2026-08-23：test/features/player/ 下已有 ply_01_test.dart，本文件用描述性后缀避撞；ref_05/bug_bug25 两份既有文件名不冲突。）

---

## §6 算法样例

```
ALG [PLY-01-ALG1-move]:
  # 前置: playMode != shuffle; 0 <= from < n; 0 <= to < n; from != to
  # 步骤: newList = files..removeAt(from)..insert(to, f); 
  #       若 from == currentIndex -> newCurrent = to
  #       否则 tempC = currentIndex - (from < currentIndex ? 1 : 0)
  #            newCurrent = tempC + (tempC >= to ? 1 : 0)
  输入: [A,B,C,D] c=2 move(0,3) → files=[B,C,D,A] c=1   # C 前移一格
  输入: [A,B,C,D] c=2 move(3,0) → files=[D,A,B,C] c=3   # C 后移一格
  输入: [A,B,C,D] c=1 move(1,3) → files=[A,C,D,B] c=3   # 当前曲自身跟随 (S2)
  输入: [A,B,C,D] c=0 move(0,2) → files=[B,C,A,D] c=2   # 当前曲自身向前
  输入: [A,B]     c=1 move(0,1) → files=[B,A]     c=0
  输入: [A,B,C]   c=1 move(1,1) → identical(this)        # 幂等 (S3)
  输入: [A]       c=0 move(0,0) → identical(this)        # 单曲短路 (S3)

ALG [PLY-01-ALG2-onReorder-correction]:
  # Flutter ReorderableListView.onReorder 语义：向下拖时 newIndex 多算 1，
  # 必须先校正再进模型层（官方文档明确语义，见 §8 R1）
  输入: old=0, new=3（下拖）→ 校正后调 move(0, 2)
  输入: old=3, new=0（上拖）→ 校正后调 move(3, 0)        # 上拖不变
  输入: old==new → 不调用 moveTrack（no-op）
```

---

## §7 跨模块影响

`bash cross-imports.sh impact lib/features/player/widgets/queue_sheet.dart lib/shared/models/play_queue.dart` 结果：queue_sheet 被 player_screen.dart、mini_player_bar.dart 引用；PlayQueue 被 orchestrator、browser_provider、playlist 域引用。

| 其它 feature | 影响点 | 影响条件 | 需要补的回归断言 |
|---|---|---|---|
| BRW | persistQueueOnChange 会把重排后的队列写进 `_qKey`，冷启动恢复读同一 key | 重排后杀进程重启 | 恢复出的队列 filePaths 顺序 == 重排后顺序（复用 net1_legacy_queue_restore_test 的读取路径断言一次即可） |
| BRW | lastQueueConnectionIdProvider 不因重排变化 | 任意重排 | S10 落盘内容中 connection id 不变（否定断言） |
| PLY 既有 | REF-05 删除刷新 / BUG-25 复合键 | QueueSheet 改造 | 5.1 两份现有测试不改一字全绿 |

---

## §8 平台特性与手动 QA

逐条核对 docs/dev/platform-pitfalls.md：

| 踩坑条目 | 是否触及 | 处置 |
|---|---|---|
| P10 多处订阅单一数据源 | 是 | INV2：重排唯一写入口 = orchestrator.moveTrack，UI 不直接写 provider |
| P13 async gap 后 UI 状态被旧数据重建 | 是 | QueueSheet 经 watch(currentPlayQueueProvider) 实时重建（queue_sheet.dart:28），拖动落下后列表自动反映新序，无需本地缓存 index |
| P14 并发请求状态机错乱 | 是 | S11 显式处置：moveTrack 不碰 gate |
| P12 值对象 == 漏字段 | 是 | move 返回的新实例若加新字段必须同步 == /hashCode；本功能不加字段，PlayQueue 既有相等性（play_queue.dart:412-423）不受影响 |

**可行性依据（铁律 6）：**

- R1 ReorderableListView：Flutter Material 官方组件（api.flutter.dev/flutter/material/ReorderableListView-class.html，Flutter stable ≥3.3 长期稳定 API）。关键语义：① `buildDefaultDragHandles` 默认 true，移动平台默认交互为**整行长按拖动**；② `onReorder(int oldIndex, int newIndex)` 在向下拖动时 newIndex 比"目标插入位"大 1，官方文档要求 `if (newIndex > oldIndex) newIndex -= 1`；③ itemBuilder 每项必须有唯一 Key。仓库此前未用过该组件（grep 无匹配），故按铁律 6 登记依据。

**真机风险列：**

| 风险 | 近似测试方案 | 测不了 → 进 mqa-backlog |
|---|---|---|
| 长按拖动手势与列表滚动边缘自动翻页的手感 | 无法模拟 | MQA：真机上拖到面板顶/底时自动滚动是否可用 |
| 拖动代理（proxyDecorator）在深色主题下的视觉 | widget 测试断言装饰存在，不断言观感 | 低风险，不进 backlog |

本功能不涉平台原生通道（audio_service/MethodChannel 均未触碰），manual_qa_required=false；MQA 仅手势体验一条。

---

## §9 dev-status.json 条目对照

```json
"PLY-01": {
  "spec_file": "docs/features/PLY-01.md",
  "spec_anchored_files": [
    "lib/features/player/widgets/queue_sheet.dart",
    "lib/features/player/player_screen.dart",
    "lib/features/player/widgets/mini_player_bar.dart",
    "lib/shared/models/play_queue.dart",
    "lib/features/player/domain/playback_orchestrator.dart",
    "lib/features/browser/browser_provider.dart"
  ],
  "scenarios": ["PLY-01-S1","PLY-01-S2","PLY-01-S3","PLY-01-S4","PLY-01-S5","PLY-01-S6","PLY-01-S7","PLY-01-S8","PLY-01-S9","PLY-01-S10","PLY-01-S11"],
  "invariants": ["PLY-01-INV1","PLY-01-INV2","PLY-01-INV3"],
  "algorithms": ["PLY-01-ALG1-move","PLY-01-ALG2-onReorder-correction"],
  "test_files": ["test/features/player/ply_01_queue_reorder_test.dart"],
  "test_coverage_gaps": [],
  "cross_module_impacts": ["BRW"],
  "manual_qa_required": false,
  "dependencies": [],
  "impl_status": "pending",
  "test_status": "pending",
  "check_status": "pending"
}
```
