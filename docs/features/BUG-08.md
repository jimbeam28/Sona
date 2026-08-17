# BUG-08 — IAudioPlayer 路径缺 5s 平台调用兜底：gate 超时后任务继续执行 → ghost 播放无收尾（P4/P17 缺口）

## §0 头部元数据

```yaml
id: BUG-08
name: AudioPlayerAdapter 六动作无 5s 超时兜底（P17 分层缺口 + ghost 播放）
priority: P1
status: active
created_at: 2026-08-16
last_updated: 2026-08-16
spec_anchored_files:
  - lib/core/services/audio_player_adapter.dart
  - lib/features/player/domain/playback_orchestrator.dart
cross_module_impacts: [PLY, BRW]
parent_feature: Player（音频播放/Player 模块）
manual_qa_required: true        # 涉真机慢 NAS 时序（P4/P17）
```

---

## §1 用户视角

### 1.0 原始需求（用户原话逐字记录）

来源：`docs/cr/cr-20260816-0802-player.md` F4（cr 复核已确认仍存在）：

> #### F4. IAudioPlayer 路径缺 5s 平台调用兜底：gate 超时后任务继续执行 → UI 报错的同时 ghost 播放且无内层收尾
> - 类型：FRAGILE / 严重度：Major / 维度：功能-踩坑（P4/P17 分层）
> - 证据：
>
> `lib/core/services/audio_player_adapter.dart:59-75`（六动作直传无 timeout）：
> ```dart
> Future<Duration?> setAudioSource(AudioSource source) => _impl.setAudioSource(source);
> Future<void> seek(Duration position) => _impl.seek(position);
> Future<void> setSpeed(double speed) => _impl.setSpeed(speed);
> ```
> `lib/features/player/domain/playback_orchestrator.dart:191-209`（setAudioSource/seek/setSpeed 无内层超时；gate 20s 到期后任务仍继续）：
> ```dart
> await player.setAudioSource(source);   // 可挂起 >20s
> ...
> if (!_gate.isLatest(requestId)) return const TrackLoadResult.superseded(); // 无新请求时仍 true
> unawaited(player.play());              // ← 晚到照样 play
> ```
> 对照 P17 分层表：5s 层只在 `audio_handler.dart`（IAudioHandler 六方法）存在；loadAndPlay 走 IAudioPlayer 通道，P17「每层都要有超时兜底」意图在 IAudioPlayer 路径缺失。30s 内层 stop 收尾（BUG-18-S1）只覆盖 stream 等待挂起，不覆盖 setAudioSource/seek/setSpeed 挂起。
> - 复现路径（条件：setAudioSource 挂起 20s+ 后恢复，慢 NAS）：UI 15s 已显示"加载超时"（`player_screen.dart:168-176`）→ gate 20s 抛错 → 任务在 t≈25s 完成 setAudioSource → isLatest 仍 true → play() → **音频在报错 UI 下开始播放**，且无任何 stop 收尾；此后无新请求时行为完全符合"已加载"（:238 还会写 `_activeConnectionId`）。
> - 自检答案：**该分支零覆盖**——`bug_18_stream_wait_test.dart` S1d 只模拟 stream 永不发 playing（内层 30s stop 生效），mock 的 setAudioSource 恒即时完成，挂起后恢复场景不存在。
> - 修复建议：给 AudioPlayerAdapter 的动作加与 audio_handler 同值的 5s `.timeout`（对齐 P17 表，改前回归分层门禁测试）；或在 gate 超时/任务结束时对仍在跑的任务显式 `player.stop()` 收尾。

### 1.1 这一功能干什么（一句话）

给 IAudioPlayer 通道（AudioPlayerAdapter）的平台调用补上 P17 分层的 5s 超时兜底：加载的 setAudioSource 挂起必须 5s 内失败收尾（杜绝 gate 超时后任务继续、晚到 play 的 ghost 播放），seek/setSpeed/play/pause/stop 挂起 5s 内静默返回不冒泡。

### 1.2 用户期望的场景

| ID | 你看到的样子 | 期望行为 |
|----|----|----|
| U1 | 慢 NAS 加载一首歌超过几秒 | 播放页在合理时间内显示加载失败（≤ 既有 UI 超时 15s 路径），可重试（修复前：报错后音频仍可能突然响起——ghost 播放） |
| U2 | 上述场景加载失败后 | 页面保持失败状态，**绝不会突然开始播放** |
| U3 | 加载失败后立即重试 / 点下一首 | 新请求正常进入加载流程（不受旧任务残留影响） |
| U4 | 正常网络下的播放（含 seek/变速/暂停/停止） | 行为完全不变 |

---

## §2 已实现的功能骨架（代码锚点）

### 2.1 文件与分层

| 层 | 文件 | 行数 | 角色 |
|---|---|---|---|
| Core | `lib/core/services/audio_player_adapter.dart` | 79 | IAudioPlayer 生产实现：六动作直传无超时（59-75，缺陷点） |
| Domain | `lib/features/player/domain/playback_orchestrator.dart` | 479 | loadAndPlay（141-246）：setAudioSource（191）/seek（195）/setSpeed（201）无内层超时；:204-209 isLatest + unawaited play（ghost 点） |
| Core | `lib/core/services/audio_handler.dart` | 346 | 六方法 5s 超时（P17 5s 层既有实证：play :270、pause :281、stop :292、seek :301、setSpeed :308、onTaskRemoved :330） |
| 测试 | `test/features/player/bug_08_repro_test.dart` | 本 spec §5.4 | 本 Bug 门禁（修复前 FAIL，已用 repro-test.sh fail 确认） |

### 2.2 关键 Provider 表

| Provider 名 | 类型 | 实现位置 | 用途 |
|---|---|---|---|
| playbackOrchestratorProvider | Provider<PlaybackOrchestrator> | player_provider.dart:108-142 | 以 `AudioPlayerAdapter(ref.read(audioPlayerProvider))` 装配（:111）——adapter 是 loadAndPlay 全链路的唯一平台桥 |

### 2.3 状态机图

```
loadAndPlay 任务体（gate 内）：
  setAudioSource ─5s 超时(修复后)→ catch → failed（收尾，无 ghost）
  ├─ 挂起 >20s（修复前）→ gate 20s 抛错（调用方已报错）→ 任务继续
  │    └─ 晚到完成 → isLatest true → play() ← ghost（修复前）
  └─ 正常完成 → seek/setSpeed → play → loaded
```

---

## §3 行为规约（Given-When-Then）

### 3.1 现有行为（逆抽，缺陷态）

- **[BUG-08-S1]** AudioPlayerAdapter 六动作直传无超时（缺陷根源）
  ```
  Given AudioPlayerAdapter 包装真实 AudioPlayer
  When setAudioSource/play/pause/stop/seek/setSpeed 任一挂起（平台层不返回）
  Then 调用 Future 永不完成（无 .timeout）
  ```
  Code evidence: `lib/core/services/audio_player_adapter.dart:59-75`。

- **[BUG-08-S2]** loadAndPlay 任务体平台调用无内层超时，gate 超时后任务继续
  ```
  Given setAudioSource 挂起 >20s
  When gate 20s 到期（request_gate.dart:154-167 completeError）
  Then 调用方收到 TimeoutException，但任务体仍在跑（setAudioSource await 未返回）
  ```
  Code evidence: `lib/features/player/domain/playback_orchestrator.dart:191`；`request_gate.dart:150-176`。

- **[BUG-08-S3]** 晚到完成 → isLatest 仍 true → unawaited play（ghost）
  ```
  Given gate 已超时抛错、无新请求入队
  When 挂起的 setAudioSource 最终完成
  Then :204 isLatest 为 true → :209 unawaited(player.play()) 执行 → ghost 播放
  And :238 仍会写 _activeConnectionId（状态完全按"已加载"推进）
  ```
  Code evidence: `lib/features/player/domain/playback_orchestrator.dart:204-209`、`:238`。

- **[BUG-08-S4]** 对照：audio_handler 六方法已有 5s 超时（P17 5s 层既有面）
  ```
  Given IAudioHandler.play/pause/stop/seek/setSpeed/onTaskRemoved
  When 平台调用挂起
  Then .timeout(5s) + 静默 catch（BUG-17 裁决：平台调用失败不向用户冒泡）
  ```
  Code evidence: `lib/core/services/audio_handler.dart:265/270/281/292/301/308/330`。

### 3.2 修复方案（status: new）

- **[BUG-08-S5]** AudioPlayerAdapter 六动作加 5s 超时兜底（修改点 1） （status: new）
  ```
  Given AudioPlayerAdapter 任一动作调用底层挂起
  When 5s 内平台层未返回
  Then setAudioSource → TimeoutException 抛给调用方（orchestrator catch → failed）
  And seek/setSpeed/play/pause/stop → 静默返回（swallow，BUG-17 同款裁决）
  否定断言:
    - setAudioSource 挂起不得无限期 pending（门禁 T1：6s 必须 error）
    - seek 挂起不得抛错（restoreStartupProgressProvider player_provider.dart:237
      的 seek 不在 try 内，抛错即 unhandled —— 门禁 T2）
    - 正常完成的平台调用（<5s）行为与修复前完全一致
  ```
  **修改点**：`lib/core/services/audio_player_adapter.dart:56-75` 动作区：
  ```dart
  // ── Actions ─────────────────────────────────────────────────────────────
  // BUG-08（cr-20260816-0802 F4）：P17 分层表 5s 平台层补齐到 IAudioPlayer
  // 通道。语义分层：
  //   setAudioSource —— 加载成败判定点，超时必须以 TimeoutException 结束
  //     （orchestrator catch → failed → 不 play，杜绝 ghost）；
  //   seek/setSpeed/play/pause/stop —— 超时静默返回（BUG-17 同款裁决，
  //     P4：平台调用失败不向用户冒泡；seek 另因 restore 路径
  //     player_provider.dart:237 无 try 包裹，抛错即 unhandled）。
  static const _platformTimeout = Duration(seconds: 5);

  @override
  Future<Duration?> setAudioSource(AudioSource source) =>
      _impl.setAudioSource(source).timeout(_platformTimeout);

  @override
  Future<void> play() =>
      _impl.play().timeout(_platformTimeout, onTimeout: () {});

  @override
  Future<void> pause() =>
      _impl.pause().timeout(_platformTimeout, onTimeout: () {});

  @override
  Future<void> stop() =>
      _impl.stop().timeout(_platformTimeout, onTimeout: () {});

  @override
  Future<void> seek(Duration position) =>
      _impl.seek(position).timeout(_platformTimeout, onTimeout: () {});

  @override
  Future<void> setSpeed(double speed) =>
      _impl.setSpeed(speed).timeout(_platformTimeout, onTimeout: () {});
  ```
  **注意**：`dart:async` 已 import（audio_player_adapter.dart:9）。setAudioSource 不带 onTimeout → 抛 TimeoutException（`Future.timeout` 默认行为）。swallow 面（play/pause/stop/seek/setSpeed）用 `onTimeout: () {}` 而非 catch——语义一致且不产生未处理错误。
  **与 BUG-17 豁免的关系**：audio_handler 六方法的静默 catch 属 SCHEMA.md §5 豁免清单；adapter 的 swallow 面是同一裁决的延伸（P4 平台调用失败不冒泡），本 spec 显式裁决。setAudioSource 的抛错面走 orchestrator catch（BUG-05 修复后带日志），不构成静默吞错。

- **[BUG-08-S6]** loadAndPlay 的 ghost 面根治：setAudioSource 超时失败后任务在 catch 收尾（修改点 2 说明） （status: new）
  ```
  Given loadAndPlay 任务体经 adapter 调 setAudioSource
  When setAudioSource 5s 超时抛 TimeoutException（S5）
  Then 任务体 :241 catch → failed → gate 正常完成（不等到 20s）
  And 晚到平台完成不再触发 play（任务已结束；unawaited play 行 :209 不执行）
  否定断言:
    - 加载失败后绝不调用 player.play()（门禁 T3）
    - gate 20s 超时（其它挂起源）路径仍存在且行为不变（BUG-03 管辖）
  ```
  **修改点**：`playback_orchestrator.dart:191-209` **无需改动**——S5 的 adapter 超时使 setAudioSource 在 5s 内失败，任务在 :241 catch 收尾，ghost 面自然消失。本 Scenario 是回归断言面（dev-exe 不得反向改动 orchestrator 的 isLatest/play 逻辑）。

**边界裁决（弱模型照此实现，无需二次判断）**：

| 边界情况 | 裁决 |
|---|---|
| setAudioSource 正常 <5s 完成 | 不变（返回 Duration?） |
| setAudioSource 挂起 >5s | TimeoutException 抛出；orchestrator catch → failed（BUG-05 日志） |
| seek/setSpeed 挂起 >5s | 静默返回（onTimeout: () {}）；加载继续（位置/速度保持旧值） |
| play 挂起 >5s（P4） | 静默返回；orchestrator 的 unawaited(play()) 无 unhandled |
| pause/stop 挂起 >5s（removeTrack :352 / loadAndPlay :230） | 静默返回；调用方照常继续 |
| restoreStartupProgressProvider seek（:237） | 5s 静默返回，不抛错（S5 否定断言 + 门禁 T2） |
| 与 gate 20s / 内层 30s 的层序 | 5s < 20s < 30s（P17 表不变；adapter 层为最短层） |
| dispose() | 不加超时（非播放动作） |

---

## §4 不变量

- **[BUG-08-INV1]** P17 平台调用 5s 层在 IAudioHandler 与 IAudioPlayer 两条通道都存在且同值（5s）
  证据：修复后 `audio_player_adapter.dart`（S5）+ `audio_handler.dart:265-330`；P17 分层表（docs/dev/platform-pitfalls.md:125）。

- **[BUG-08-INV2]** 加载失败路径不得触发 play（ghost 禁令）：setAudioSource 失败（超时/平台错误）后 loadAndPlay 内无任何 play 调用
  证据：修复后 orchestrator catch（:241-243，含 BUG-05 日志）在 :209 之前收尾。

- **[BUG-08-INV3]** 平台调用 5s 兜底不得改变正常路径语义：任何 <5s 完成的调用行为与修复前一致
  证据：S5 修改点仅包裹 `.timeout`，无参数/返回值改动（`Future.timeout` 在提前完成时原样透传——Dart SDK 标准语义）。

---

## §5 测试规约

### 5.1 现有测试清单

| 测试文件 | 覆盖的 Scenario / INV | 备注 |
|---|---|---|
| test/features/player/bug_18_stream_wait_test.dart S1d | BUG-08-S2 的 stream 等待面（30s 内层） | 不覆盖 setAudioSource 挂起（cr 自检答案） |
| test/features/player/bug_08_repro_test.dart | BUG-08-S5 / S6 / INV1 / INV2 / INV3 | 本 Bug 门禁（修复前 FAIL，已用 repro-test.sh fail 确认） |

### 5.2 测试 ID 派生清单（dev-exe 派发测试 Agent 用）

```
BUG-08-S1 … S6        # Scenario（S1~S4 现状锚定，S5/S6 修复目标）
BUG-08-INV1 … INV3    # 不变量
BUG-08-MAN1 …         # 手动 QA 步骤（见 §8）
```

dev-exe 要求：S5/S6/INV1~3 由 §5.4 门禁测试覆盖（T1→S5 setAudioSource 面、T2→S5 seek 面、T3→S6）；S1~S4 由门禁测试与既有测试锚定。

### 5.3 测试覆盖盲点（dev-plan 写本文档时识别）

| 未覆盖 ID | 现状 | 应补偿方式 |
|---|---|---|
| play/pause/stop/setSpeed 四个 swallow 面 | 门禁只测 setAudioSource + seek | dev-exe 可在门禁内补 play 挂起 → 5s 返回不抛错一条（同 T2 型） |
| P17 表更新 | adapter 层加入 5s 平台层 | dev-exe 修复后按平台踩坑库规则回写 `docs/dev/platform-pitfalls.md` P17 表（新增一行：adapter 六动作 5s） |
| BUG-08-MAN1~MAN2 | 真机慢 NAS ghost 时序 | 进 mqa-backlog（§8） |

### 5.4 测试文件位置（spec-scan --gate 硬校验）

| 测试文件 | 覆盖 ID | 说明 |
|---|---|---|
| test/features/player/bug_08_repro_test.dart | BUG-08-S5、BUG-08-S6、BUG-08-INV1、BUG-08-INV2、BUG-08-INV3 | 门禁：dev-exe 修复后必须 PASS（repro-test.sh pass） |

---

## §6 算法样例

本 Bug 不涉纯函数算法，跳过。

---

## §7 跨模块影响

`bash cross-imports.sh impact lib/core/services/audio_player_adapter.dart lib/features/player/domain/playback_orchestrator.dart`（2026-08-16）→ 引用方：

| 其它 feature | 影响点 | 影响条件 | 需要补的回归断言 |
|---|---|---|---|
| PLY（player_provider.dart:111 装配点） | adapter 六动作语义变化（超时面） | 调用方均 await 或 unawaited；setAudioSource 超时 → failed 结果（UI 走失败分支） | bug_08_repro_test.dart PASS；ply_01~14 / ref_14 全绿 |
| BRW（restoreStartupProgressProvider :237 seek） | seek 5s 静默返回 | 修复前挂起场景从"永久挂起"变"5s 返回"——恢复链路不再卡死 | o3_*/net1 恢复测试全绿 |
| BRW（restoreQueueFromPrefsProvider preload，直接调 player 不走 adapter） | 不受本修复影响（preload 直连 AudioPlayer，10s 超时在 audio_source_builder） | BUG-06 管辖 | bug_06_repro_test.dart PASS |
| PLY（audio_handler 六方法既有 5s 层） | 无交集（不同通道） | 数值一致性由 INV1 保证 | cbb3098 门禁（handler 六方法超时扫描）保持绿 |
| BUG-03（gate 超时 → 守卫卡死） | adapter 5s 兜底后 gate 20s 超时触发率下降，但 BUG-03 修复独立成立 | 互不依赖 | bug_03_repro_test.dart PASS |

---

## §8 平台特性与手动 QA

设计前已逐条核对 `docs/dev/platform-pitfalls.md`：本 Bug 即 **P4**（平台调用 Future 可能永不完成——play 一律 fire-and-forget + 所有平台调用加超时兜底）与 **P17**（分层表 5s 平台层在 IAudioPlayer 通道的缺口补全）的直接处置；**P7**（useProxyForRequestHeaders:false）不涉及（adapter 不建代理）。

**真机风险列**（fake 测不到、只有真机会出问题的）：

| 风险 | 近似测试方案 | 测不了 → 进 mqa-backlog |
|---|---|---|
| 慢 NAS 下"加载超时"后音频突然响起（ghost） | bug_08 T3（挂起 setAudioSource → 断言 5s failed 且无 play） | BUG-08-MAN1：真机限速播放长 FLAC，等播放页显示"加载超时"后观察 30s —— 不得出现音频播放；随后点重试必须正常 |
| seek/变速在极端慢场景挂起 → 卡 UI | bug_08 T2（seek 5s 静默返回） | BUG-08-MAN2：真机加载中快速拖动进度条/切速度，UI 不得永久卡死 |
| restore 链路 seek 挂起 | bug_08 T2 | BUG-08-MAN3：真机限速启动 App（有恢复进度），启动页不得无限 loading |

涉及真机慢 NAS 时序（P4/P17）→ `manual_qa_required = true`。

---

## §9 dev-status.json 条目对照

```json
"BUG-08": {
  "spec_file": "docs/features/BUG-08.md",
  "spec_anchored_files": [
    "lib/core/services/audio_player_adapter.dart",
    "lib/features/player/domain/playback_orchestrator.dart"
  ],
  "scenarios": ["BUG-08-S1", "BUG-08-S2", "BUG-08-S3", "BUG-08-S4", "BUG-08-S5", "BUG-08-S6"],
  "invariants": ["BUG-08-INV1", "BUG-08-INV2", "BUG-08-INV3"],
  "algorithms": [],
  "manual_qa_required": true,
  "user_acceptance_text": "见 §1.2"
}
```
