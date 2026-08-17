# REF-04 — superseded 加载结果不再渲染为错误态：静默合并 + 自动收敛到最新请求

## §0 头部元数据

```yaml
id: REF-04
name: superseded 结果不渲染错误态（保持 loading / 对齐即 ready / 自动重发收敛）
priority: P2
status: active
created_at: 2026-08-16
last_updated: 2026-08-16
spec_anchored_files:
  - lib/features/player/player_screen.dart
  - lib/features/player/domain/request_gate.dart
  - lib/features/player/domain/player_screen_logic.dart
  - lib/features/player/player_provider.dart
cross_module_impacts: [PLY]
manual_qa_required: false       # 纯 UI 状态机逻辑，flutter test 全可验证
```

---

## §1 用户视角

### 1.0 原始需求（用户原话逐字记录）

来源：`docs/cr/cr-20260816-0802-player.md` D2（cr 复核分流，用户裁决"修"→ 转 REF 需求流程）：

> #### D2. superseded 结果渲染为错误态："加载已被新的播放请求替换" 一闪而过
> - 类型 / 严重度 / 维度：DESIGN / Minor / 正确性（UX）
> - 证据：
>
> `lib/features/player/player_screen.dart:186-190`：
> ```dart
> } else if (loaded.isSuperseded) {
>   _safeSetState(() { _loadState = PlayerLoadState.error('加载已被新的播放请求替换'); });
> }
> ```
> superseded 是串行化的**正常竞态结果**（快速连点下一首/双击队列项），渲染成 error 会让 UI 闪现错误画面/重试按钮，随后被新请求的 ready 覆盖。
> - 取舍分析：保留（告知用户）vs 改为忽略（保持 loading 等新请求落地）。倾向后者。
> - 修复建议：superseded 时不改 _loadState（或保持 loading）。

用户裁决：**superseded 不再渲染错误态**——保持 loading 直至新请求落地；若播放器已与队列对齐（外部请求已完成）则直接转 ready；否则自动重新发起加载使 UI 状态收敛到最新请求（补 cr 修复建议未覆盖的"外部请求落地后页面状态不更新"边界）。

### 1.1 这一功能干什么（一句话）

把"加载已被新的播放请求替换"从错误画面改为正常过渡：用户快速连点切歌、或在加载中经通知栏切歌/删除当前曲时，播放器页面保持"加载中"直到最新一次加载的结果落地（成功显示播放界面、失败显示真正的错误原因），不再闪现无意义的错误画面。

### 1.2 用户期望的场景

| ID | 你看到的样子 | 期望行为 |
|----|----|----|
| U1 | 快速连点"下一首"两次 | 不闪现"加载已被新的播放请求替换"错误画面；一直显示"正在加载"，最终显示最后那首歌的播放界面 |
| U2 | 加载较慢时点队列里的另一首 | 同上：不闪错误，最终显示所选曲目 |
| U3 | 页面加载中，从通知栏按"下一首"（应用级接线，BUG-02 修复后） | 最终界面显示通知栏切到的曲目，不一直转圈 |
| U4 | 加载中打开队列面板删除当前曲 | 最终显示新队列的当前曲（或真正的加载失败原因），不闪 superseded 错误 |
| U5 | 加载真的失败（断网/密码错） | 与修复前一致：显示对应错误画面与重试按钮（失败路径不受影响） |
| U6 | 快速切歌期间播放器正常出声 | 界面上最多短暂停留在"加载中"，音乐不中断、不闪错误（无额外加载请求打断播放） |

---

## §2 已实现的功能骨架（代码锚点）

### 2.1 文件与分层

| 层 | 文件 | 行数 | 角色 |
|---|---|---|---|
| UI | `lib/features/player/player_screen.dart` | 432 | `_runSerializedLoad`（148-225）：loading 置位（162）/ token 自增（163）/ 15s UI 超时（168-176）/ 结果分流（183-218：loaded→ready、superseded→error（缺陷点 186-190）、failed→分类错误 191-218）/ `_extractCurrentSourcePath`（125-133）/ 空队列前置检查（151-158）/ 页面空队列自动 pop（269-275） |
| Domain | `lib/features/player/domain/request_gate.dart` | 202 | `SerializedRequestGate`：排队即 superseded（138-140）/ 完成时非最新 → onSuperseded（160-167）/ `TrackLoadResult`（94-107：isLoaded / isSuperseded） |
| Domain | `lib/features/player/domain/playback_orchestrator.dart` | 479 | loadAndPlay 内部 4 处 isLatest 检查（163-165/176-178/204-206/233-235）→ superseded；空队列/无连接/无密码 → failed（146-147/157-158/160-162/173-175） |
| Domain | `lib/features/player/domain/player_screen_logic.dart` | 77 | `sourceMatchesQueue`（15-18）：source 解码路径与队列当前曲 endsWith 匹配（自检复用点） |
| Provider | `lib/features/player/player_provider.dart` | 401 | 外部加载驱动者：completed 监听器自动切歌（306-325，unawaited(loadAndPlayProvider) 324）/ skipToNextProvider（349-355）/ skipToPreviousProvider（357-364）/ selectQueueIndexProvider（366-373）/ removeTrackFromQueueProvider（375-384） |
| 测试 | `test/features/player/ply_14_test.dart` | 634 | PlayerScreen widget 测试（错误态/加载态断言见 5.1） |

### 2.2 关键 Provider 表

本 REF 修改不新增/删除 Provider。相关既有 Provider（外部加载驱动者）见 §2.1 表格。

### 2.3 状态机图

```
_runSerializedLoad（页面 token 序列化 + 15s 超时）
  │
  ├─ token 失效（181 行）→ return（状态不变，新请求的结果负责更新）
  │
  ├─ loaded → _loadState = ready
  │
  ├─ superseded（本次修改）──┬─ token 不匹配 → return（181 行既有的判定先拦截）
  │                         ├─ queue null/empty → 保持 loading（页面 build 层 pop 兜底）
  │                         ├─ 播放器已对齐（sequenceState!=null 且 sourceMatchesQueue
  │                         │   且 processingState!=idle）→ _loadState = ready
  │                         └─ 未对齐 → 保持 loading + 自动重发 _loadAndPlay()（token++
  │                              重新走 gate，收敛：loaded→ready / failed→错误）
  │
  └─ failed → 分类（classifyLoadFailure）→ _loadState = error（不变）
```

---

## §3 行为规约（Given-When-Then）

### 3.1 现有行为（逆抽）

- **[REF-04-S1]** gate 串行化产生 superseded：排队被替换或完成时已非最新
  ```
  Given gate 内已有请求在跑，新的加载请求进入（orchestrator 各入口都经 gate.schedule）
  When 新请求 beginRequest（requestId++）
  Then 旧请求要么在队列中被 completeSuperseded（request_gate.dart:138-140），
      要么在完成/出错时因 isLatest==false 被置为 onSuperseded（160-167）
  And orchestrator.loadAndPlay 任务内 4 处 isLatest 检查（163-165/176-178/204-206/233-235）
      也直接返回 superseded
  ```
  Code evidence: `lib/features/player/domain/request_gate.dart:116-177`（gate 机制）；`lib/features/player/domain/playback_orchestrator.dart:163-165、176-178、204-206、233-235`。

- **[REF-04-S2]** 现状缺陷态：superseded 渲染为错误画面（一闪而过）
  ```
  Given 页面 token 为最新（181 行未拦截）且 loaded.isSuperseded == true
  When _runSerializedLoad 结果分流
  Then _safeSetState(_loadState = PlayerLoadState.error('加载已被新的播放请求替换'))（186-190）
  And _buildBody 渲染 _buildError()（299-300、374-431）——错误图标 + 文案 + 重试按钮
  And 随后新请求 ready 到达时被 ready 覆盖（183-185）——"一闪而过"
  ```
  Code evidence: `lib/features/player/player_screen.dart:186-190`（缺陷点）；`:299-300`（error → _buildError）；`request_gate.dart:94-107`（TrackLoadResult.isSuperseded 定义）。

- **[REF-04-S3]** superseded 的两种产生时机：页面内请求被更新页面请求替换；或页面请求被**外部请求**替换（不经页面 token）
  ```
  Given 页面 _loadRequestToken 只在 _runSerializedLoad 内自增（163 行）
  When completed 监听器（player_provider.dart:324）unawaited(loadAndPlayProvider)() /
      通知栏 skip（BUG-02 修复后）/ removeTrack（orchestrator:365）发起 gate 请求
  Then 页面 token 不变化，但 gate 请求已更新 → 页面请求完成时 superseded 且 token 仍最新
      → 现行 186-190 会渲染 error；若改为"保持 loading"而不收敛，页面将永久 loading
      （外部请求完成不更新页面 _loadState）
  ```
  Code evidence: `lib/features/player/player_screen.dart:163、181`（token 仅页面内自增）；`lib/features/player/player_provider.dart:306-325`（completed → 324 unawaited(loadAndPlayProvider)）；`lib/features/player/domain/playback_orchestrator.dart:365`（removeTrack → loadAndPlay）。

### 3.2 修改方案（status: new）

设计裁决（用户裁决"superseded 不再渲染错误态"）：

| 边界情况 | 裁决 |
|---|---|
| superseded 且 token 不匹配（页面又发起过新请求） | **维持现状 return（player_screen.dart:181 行）**，不改动——新请求的结果负责更新状态 |
| superseded 且 token 匹配 + queue null/empty（队列被删空） | **保持 loading，不渲染 error、不重发**——页面 build 层对空队列自动 pop（269-275），无需处理 |
| superseded 且 token 匹配 + 播放器已对齐（`sequenceState != null` 且 `sourceMatchesQueue(src, queue.current)` 且 `processingState != idle`——外部请求已成功落地） | **直接置 ready，不重发**（避免对同一曲重复 setAudioSource 造成播放闪断，REF-04-S3） |
| superseded 且 token 匹配 + 播放器未对齐（外部请求仍在 gate 中 / 未成功） | **保持 loading + 自动重发 `_loadAndPlay()`**（token 自增重新走 gate，成为最新请求后必然收敛：loaded→ready / failed→错误 / 再次 superseded→递归本裁决） |
| 重发后仍被外部持续打断（无限 superseded） | 每次重发都成为 gate 最新请求；页面 15s UI 超时（168 行）兜底 → error('加载超时，请重试')，不会永久 loading |
| 外部请求成功但播放中用户立即暂停（playing=false、processingState==ready） | 对齐判定只看 `processingState != idle`，不看 playing → 直接 ready（REF-04-S3 否定断言：不因 paused 而重发） |

- **[REF-04-S4]** superseded 分支改写：对齐即 ready，未对齐保持 loading 并自动重发（修改点 1） （status: new）
  ```
  Given 页面 token 为最新且 loaded.isSuperseded == true 且 queue 非空
  When _runSerializedLoad 结果分流进入 superseded 分支
  Then 执行对齐自检：
      final p = ref.read(audioPlayerProvider);
      final cur = ref.read(currentPlayQueueProvider);
      final src = _extractCurrentSourcePath(p);
      final aligned = p.sequenceState != null &&
          sourceMatchesQueue(src, cur) &&
          p.processingState != ProcessingState.idle;
  And aligned == true → _safeSetState(() => _loadState = PlayerLoadState.ready)
  And aligned == false → 保持 _loadState = loading（162 行已置位），并
      unawaited(_loadAndPlay())（token 自增、重新经 gate，收敛）
  否定断言:
    - 不得设置 _loadState = PlayerLoadState.error（错误文案'加载已被新的播放请求替换'从代码库消失）
    - 不得调用 _retry / 不得渲染重试按钮路径（_buildError 不被 superseded 触发）
    - 不得调用 player.stop / pause / seek（对齐自检只读 player 状态）
    - aligned == true 时不得重发加载请求（避免同曲重复 setAudioSource 的播放闪断）
    - 重发路径不得绕过 _runSerializedLoad（15s UI 超时与 token 串行化必须保留）
    - queue == null || queue.length == 0 时不重发、不渲染错误（交由 build 层 pop）
  ```
  **修改点 1**：`lib/features/player/player_screen.dart:186-190` —— 删除现 error 分支，替换为：
  ```dart
  } else if (loaded.isSuperseded) {
    // REF-04 (cr-20260816-0802 D2): superseded 是 gate 串行化的正常竞态结果，
    // 不渲染错误态。若播放器已与当前队列对齐（外部请求已落地，如通知栏 skip/
    // 自动切歌/删除当前曲），直接转 ready 避免闪断；否则保持 loading 并自动
    // 重发加载，使页面状态收敛到 gate 的最新请求。
    debugPrint('[Player] _runSerializedLoad: → superseded');
    final p = ref.read(audioPlayerProvider);
    final cur = ref.read(currentPlayQueueProvider);
    if (cur != null && cur.length > 0) {
      final src = _extractCurrentSourcePath(p);
      final aligned = p.sequenceState != null &&
          sourceMatchesQueue(src, cur) &&
          p.processingState != ProcessingState.idle;
      if (aligned) {
        _safeSetState(() => _loadState = PlayerLoadState.ready);
      } else {
        debugPrint('[Player] superseded: player not aligned, re-running load');
        unawaited(_loadAndPlay());
      }
    }
    // queue null/empty: 保持 loading，页面 build 层自动 pop（269-275）。
  }
  ```
  前提（既有符号，无需新增 import）：`_extractCurrentSourcePath`（player_screen.dart:125-133）、`sourceMatchesQueue`（player_screen_logic.dart:15-18，已 import：`domain/player_screen_logic.dart` 14 行）、`ProcessingState`（just_audio，8 行已 import）、`unawaited`（dart:async，4 行已 import）。

- **[REF-04-S5]** failed 分支与 loaded 分支行为不变（防 dev-exe 误改） （status: new）
  ```
  Given superseded 分支改写后
  When loaded.isLoaded → 走 183-185 ready
  When loaded 为 failed → 走 191-218 分类错误（连接/密码/加载失败）
  Then 两分支代码与修复前逐字一致
  否定断言:
    - 不得把 failed 分支的 classifyLoadFailure / errorMessageForLoadFailure 逻辑
      并入 superseded 分支
    - 不得修改 15s UI 超时（168-176）与 token 校验（181）逻辑
  ```
  Code evidence: `lib/features/player/player_screen.dart:183-185、191-218`（不动）。

**边界裁决汇总（弱模型照此实现，无需二次判断）**：见上表。实现后全量 `flutter analyze` 0 warning 为门禁。

---

## §4 不变量

- **[REF-04-INV1]** superseded 结果永不渲染为 `PlayerLoadStatus.error`：代码库中不再存在"加载已被新的播放请求替换"文案，`_loadState.status` 在 superseded 路径下只能是 loading 或 ready
  证据：`lib/features/player/player_screen.dart:186-190`（修改点 1 删除 error 分支）；`lib/features/player/domain/request_gate.dart:94-107`（TrackLoadResult.isSuperseded 语义不变）。

- **[REF-04-INV2]** superseded 处理路径最终收敛：不出现永久 loading——未对齐时自动重发（重发成为 gate 最新请求 → loaded/failed/superseded 三态之一），持续打断由 15s UI 超时（player_screen.dart:168）兜底为 error
  证据：`lib/features/player/player_screen.dart:168-176`（15s timeout）+ 修改点 1 的重发分支；`lib/features/player/domain/request_gate.dart:154-167`（gate 20s 超时）。

---

## §5 测试规约

### 5.1 现有测试清单

| 测试文件 | 覆盖的 Scenario / INV | 备注 |
|---|---|---|
| test/features/player/ply_14_test.dart | REF-04-S1（串行化行为间接）/ REF-04-S5（loaded/failed 路径） | 既有 PlayerScreen widget 测试：加载成功/失败/超时路径断言；修复后保持绿 |
| test/features/player/bug_18_stream_wait_test.dart | REF-04-S1（gate 超时 → superseded 相关语义） | orchestrator 层既有测试，不动 |

### 5.2 测试 ID 派生清单（dev-exe 派发测试 Agent 用）

```
REF-04-S1 … S5        # Scenario（S1~S3 现状锚定，S4/S5 修复目标）
REF-04-INV1 … INV2    # 不变量
```

dev-exe 要求：S1 由既有 gate/orchestrator 测试锚定；S4（含 INV1/2）由 §5.4 门禁测试文件覆盖。

### 5.3 测试覆盖盲点（dev-plan 写本文档时识别）

| 未覆盖 ID | 现状 | 应补偿方式 |
|---|---|---|
| REF-04-S3（外部请求替换页面请求的 superseded，token 仍最新） | 零锚定（现有测试无"外部驱动 superseded 页面请求"路径） | §5.4 门禁文件补：notify superseded 且外部已播放对齐 → ready；未对齐 → 重发收敛 |
| REF-04-S2（缺陷态"错误文案闪现"） | 现有测试可能无 superseded 断言 | §5.4 门禁文件按负向断言锚定：错误文案不在任何路径出现 |
| REF-04-INV2（不永久 loading） | 零锚定 | §5.4 门禁文件断言 superseded 后重发直至状态收敛 |

### 5.4 测试文件位置（spec-scan --gate 硬校验）

新建：`test/features/player/ref_04_superseded_test.dart`（命名已 grep 核实与既有文件无冲突；widget 测试装配风格仿 `ply_14_test.dart` / `bug_02_repro_test.dart`）。

| 测试文件 | 覆盖 ID | 说明 |
|---|---|---|
| test/features/player/ref_04_superseded_test.dart | REF-04-S2、S3、S4、S5、REF-04-INV1、REF-04-INV2 | 门禁：dev-exe 修复后必须 PASS（cov-gate 内）。建议用例：① 桩 skipToNext 返回 superseded 且 player 无 source → 断言仍显示"正在加载音频..."且随后重发完成显示 ready（无错误文案）；② 桩 superseded 且 player 已对齐（sequenceState 非空 + sourceMatchesQueue + ready）→ 断言直接 ready 且不再触发第二次加载请求；③ 桩持续 superseded（每次重发都 superseded）→ 断言 15s 后 error('加载超时，请重试') |
| test/features/player/ply_14_test.dart | REF-04-S5 | 既有文件，断言不变，修复后保持绿 |

---

## §6 算法样例

本 REF 不涉纯函数算法（对齐判定逻辑内联在 player_screen.dart 修改点，S4 已给出完整代码片段），跳过。

---

## §7 跨模块影响

`bash cross-imports.sh impact lib/features/player/player_screen.dart lib/features/player/domain/request_gate.dart lib/features/player/domain/player_screen_logic.dart lib/features/player/player_provider.dart`（2026-08-16）→ 引用方：

| 其它 feature | 影响点 | 影响条件 | 需要补的回归断言 |
|---|---|---|---|
| Player（player_provider.dart 外部驱动者：completed 监听器 306-325 / skipToNext/Previous 349-364 / selectQueueIndex 366-373 / removeTrack 375-384） | 外部请求产生 superseded 的新路径（S3） | 本 REF 只改页面侧消费；外部驱动者零改动 | provider 既有测试（bug_01_test / bug_remove_track_progress_test / ref_14_test 等）全绿 |
| Player（request_gate.dart） | superseded 产生机制 | 零改动（只读语义） | request_gate 既有测试全绿（gate 串行化断言不变） |
| Player（player_screen_logic.dart） | sourceMatchesQueue 被 superseded 分支复用 | 零改动（只读复用） | player_screen_logic 既有测试全绿 |
| HOME（mini_player_bar / home_screen） | 不经页面 _runSerializedLoad，不受影响 | 无 | home 既有测试全绿 |
| Timer（onTrackCompletedProvider 相关） | completed 监听器行为不变 | 无 | timer 既有测试全绿 |

---

## §8 平台特性与手动 QA

设计前已逐条核对 `docs/dev/platform-pitfalls.md`：

- **P14**（加载请求并发 → 状态机错乱）：本 REF 不改 gate 串行化机制，只在 UI 层消费 superseded 语义；重发路径仍走 `_runSerializedLoad` → gate（S4 否定断言），不新增绕门路径。
- **P9**（defunct setState）：异步回调后一律 `_safeSetState`（既有封装），token 校验（181）保留。
- **P4/P17**（平台调用挂起）：15s UI 超时（168）与 gate 20s（request_gate.dart:154-167）兜底不变，未新增超时层。
- 其余 P1~P17 不触及。

**真机风险列**（fake 测不到、只有真机会出问题的）：

| 风险 | 近似测试方案 | 测不了 → 进 mqa-backlog |
|---|---|---|
| 慢 NAS 下 superseded 重发造成同曲重复缓冲（对齐判定在真实时序下误判） | ref_04_superseded_test.dart 对齐/未对齐两态 + aligned 时"不重发"负向断言 | 无（widget 层全可测，对齐判定输入为 player 状态快照，无平台通道参与） |
| 真实通知栏 skip 与页面加载并发（BUG-02 修复后才有该路径） | S4 用例②（外部已落地 → ready）覆盖页面侧 | 真机侧由 BUG-02-MAN1~3 覆盖（通知栏路径本体），本 REF 不重复登记 |

本功能不涉及平台原生特性，全部可在 `flutter test` 中验证 → `manual_qa_required = false`。

---

## §9 dev-status.json 条目对照

```json
"REF-04": {
  "spec_file": "docs/features/REF-04.md",
  "spec_anchored_files": [
    "lib/features/player/player_screen.dart",
    "lib/features/player/domain/request_gate.dart",
    "lib/features/player/domain/player_screen_logic.dart",
    "lib/features/player/player_provider.dart"
  ],
  "scenarios": ["REF-04-S1", "REF-04-S2", "REF-04-S3", "REF-04-S4", "REF-04-S5"],
  "invariants": ["REF-04-INV1", "REF-04-INV2"],
  "algorithms": [],
  "manual_qa_required": false,
  "user_acceptance_text": "见 §1.2"
}
```
