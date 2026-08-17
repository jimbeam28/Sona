# BUG-01 — 通知栏/耳机"下一首/上一首"每次必抛 TypeError（queueIndex 永为 null）

## §0 头部元数据

```yaml
id: BUG-01
name: 通知栏/耳机 skip 必抛 TypeError（QueueHandler.queueIndex! 解包）
priority: P1
status: active
created_at: 2026-08-16
last_updated: 2026-08-16
spec_anchored_files:
  - lib/core/services/audio_handler.dart
  - test/core/services/audio_handler_test.dart
cross_module_impacts: [PLY]
parent_feature: Player（音频播放/Player 模块）
manual_qa_required: true        # 涉 audio_service 通知栏/锁屏/耳机按键
```

---

## §1 用户视角

### 1.0 原始需求（用户原话逐字记录）

来源：`docs/cr/cr-20260816-0801-core-shared.md` B1（cr 复核已确认仍存在）：

> #### B1. 通知栏/耳机"下一首/上一首"每次必抛 TypeError（queueIndex 永远为 null），且退出播放页后按钮失效
> - 类型 / 严重度 / 维度：BUG / Major / 正确性 + 功能-踩坑(P8)
> - 证据：
>   - `lib/core/services/audio_handler.dart:312-322`：
>     ```dart
>     @override
>     Future<void> skipToNext() {
>       onSkipToNextRequested?.call();
>       return super.skipToNext();
>     }
>     ```
>   - `lib/` 全库 `queueIndex` 0 匹配（grep 确认），`updateQueue`/`skipToQueueItem` 也无任何调用——handler 的 `playbackState` 由 `BehaviorSubject.seeded(PlaybackState())` 播种后仅经 `_onPlayerStateChanged` 的 `copyWith(controls/playing/processingState/updatePosition/...)`（audio_handler.dart:140-153）更新，**queueIndex 从出生到永远都是 null**。
>   - audio_service 0.18.18 `QueueHandler._skip`（pub 缓存源码）：`final index = playbackState.nvalue!.queueIndex!;`——null 解包抛 `TypeError: Null check operator used on a null value`，先于任何边界检查。
>   - 回调生命周期绑定：`lib/features/player/player_screen.dart:77-79`（initState 接线 `onSkipToNextRequested = _playNext`）与 `player_screen.dart:112-116`（dispose 置 null）。
>   - 测试自证：`test/core/services/audio_handler_test.dart:275-289` 注释原文"QueueHandler 推进依赖 playbackState.queueIndex 非空——未配置队列的裸 handler 会抛 TypeError，属 audio_service 内部语义"——测试必须手动 `copyWith(queueIndex: 0)` 才能跑，而生产代码从无此播种。
> - 复现路径：
>   1. 播放任意曲目（PlayerScreen 存活，回调已接线）。
>   2. 按返回键退出播放器页回浏览页（PlayerScreen dispose，player_screen.dart:114 将 `onSkipToNextRequested = null`）。
>   3. 下拉通知栏按"下一首"按钮 → 期望：切到下一曲；实际：`onSkipToNextRequested?.call()` 为空不执行任何导航，`super.skipToNext()` → `QueueHandler._skip(1)` → `playbackState.nvalue!.queueIndex!`（null）→ TypeError → MethodChannel `com.ryanheise.audio_service.handler.methods` 的 `case 'skipToNext': await callbacks.skipToNext(...)`（audio_service_platform_interface 0.1.3 method_channel_audio_service.dart:148-150，无 try/catch）把错误回送平台侧，按钮无响应。
>   4. 即使 PlayerScreen 存活（步骤 2 改为仅按 Home 键）：回调先执行、切歌成功，但每次按键仍向平台侧抛一次 TypeError（MediaSession 侧记错误日志）。
> - 自检答案：**测试假设本身错误**——audio_handler_test.dart:284-289 为"正常路径"显式播种 `queueIndex: 0`，该假设生产环境永不成立（lib/ 无任何写入点）；且无任何测试驱动"PlayerScreen dispose 之后的通知栏 skip"。测试绿但生产路径（queueIndex=null）零覆盖。
> - 修复建议：本应用自管队列（audio_service 的 queue 永为空，QueueHandler 能力完全未用）——去掉 `QueueHandler` mixin 或重写 skipToNext/skipToPrevious 不再调 `super`（BaseAudioHandler 基类实现是无操作）；skip 回调接线从 PlayerScreen 生命周期提升到应用/编排层（见 F1）。

### 1.1 这一功能干什么（一句话）

修复通知栏 / 锁屏 / 耳机"下一首 / 上一首"每次按键必抛异常的问题——本应用自管播放队列，audio_service 的队列机制从未启用，skip 动作应只触发应用层回调而不触碰 audio_service 队列内部状态。

### 1.2 用户期望的场景

| ID | 你看到的样子 | 期望行为 |
|----|----|----|
| U1 | 正在听歌时下拉通知栏，点"下一首"按钮 | 切到下一曲；**每次按键都不再有任何异常**（修复前每次按键后台都抛一次 TypeError） |
| U2 | 正在听歌时按耳机线控"下一首"键 | 切到下一曲，无异常 |
| U3 | 歌曲在播时点锁屏上的"上一首"按钮 | 回到上一曲，无异常 |
| U4 | 播放器页面开着时点通知栏"下一首" | 切歌成功且行为与 U1 一致（不因修复而改变） |

---

## §2 已实现的功能骨架（代码锚点）

### 2.1 文件与分层

| 层 | 文件 | 行数 | 角色 |
|---|---|---|---|
| Core | `lib/core/services/audio_handler.dart` | 346 | NasAudioHandler：audio_service 通知栏状态同步 + 媒体控制入口 |
| Provider | `lib/features/player/player_provider.dart` | 401 | skipToNextProvider / skipToPreviousProvider（编排层入口） |
| 入口 | `lib/main.dart` | 70 | AudioService.init 创建 handler，audioHandlerProvider override（35-36/65） |
| 契约 | `lib/core/contracts/audio_handler_contract.dart` | 94 | IAudioHandler：skipToNext/skipToPrevious/skip 回调 setter |
| 测试 | `test/core/services/audio_handler_test.dart` | 407 | 含播种 queueIndex 的错误假设段（265-325） |
| 测试 | `test/features/player/bug_01_repro_test.dart` | 本 spec §5.4 | 本 Bug 门禁（生产常态驱动） |

### 2.2 关键 Provider 表

| Provider 名 | 类型 | 实现位置 | 用途 |
|---|---|---|---|
| audioHandlerProvider | Provider<IAudioHandler?> | player_provider.dart:69（main.dart:65 override 为真实 handler） | 通知栏控制入口 |

### 2.3 状态机图

本功能不涉状态机（skip 是无状态命令转发），跳过。

---

## §3 行为规约（Given-When-Then）

### 3.1 现有行为（逆抽，缺陷态）

- **[BUG-01-S1]** skipToNext/skipToPrevious 触发 callback 后调 super → 生产常态（queueIndex=null）必抛 TypeError
  ```
  Given 真实 NasAudioHandler（不播种 queueIndex、不调 updateQueue）——生产常态
  When handler.skipToNext()（或 skipToPrevious()）
  Then onSkipToNextRequested?.call() 先执行
  And super.skipToNext() → QueueHandler._skip → playbackState.nvalue!.queueIndex!
      （null 解包）→ Future 以 TypeError 失败
  ```
  Code evidence:
  - `lib/core/services/audio_handler.dart:312-322`（callback + super 顺序）
  - `lib/core/services/audio_handler.dart:43-45`（`with QueueHandler, SeekHandler`）
  - pub 缓存 audio_service 0.18.18 `lib/audio_service.dart:3374`（`final index = playbackState.nvalue!.queueIndex!;`——QueueHandler._skip）

- **[BUG-01-S2]** playbackState 更新路径从不触碰 queueIndex
  ```
  Given handler 播放状态变化（_onPlayerStateChanged）
  When 状态同步到 playbackState
  Then copyWith 仅更新 controls/systemActions/androidCompactActionIndices/
      playing/processingState/updatePosition/bufferedPosition/speed
  And queueIndex 保持播种值 null（lib/ 全库 0 命中 queueIndex 写入）
  ```
  Code evidence: `lib/core/services/audio_handler.dart:140-153`；`lib/` grep `queueIndex` 0 命中（2026-08-16 核实）。

- **[BUG-01-S3]** skip 回调为 null 时 skip 不执行导航、本身不抛错
  ```
  Given onSkipToNextRequested == null（PlayerScreen dispose 后，见 BUG-02）
  When handler.skipToNext()
  Then `?.call()` 为空操作
  And 异常仅来自 super（BUG-01-S1 的 TypeError，非 callback 路径）
  ```
  Code evidence: `lib/core/services/audio_handler.dart:314`（`onSkipToNextRequested?.call()`）。

### 3.2 修复方案（status: new）

- **[BUG-01-S4]** 移除 QueueHandler mixin —— 生产常态 skip 不再抛 TypeError （status: new）
  ```
  Given 真实 NasAudioHandler（不播种 queueIndex、不调 updateQueue）——生产常态
  When handler.skipToNext() / handler.skipToPrevious()
  Then onSkipToNextRequested?.call() 执行（顺序不变，先 callback）
  And super.skipToNext()/skipToPrevious() 落到 BaseAudioHandler no-op 实现
      （audio_service 0.18.18 lib/audio_service.dart:3142/3145，`async {}`）
  And Future 正常完成（不抛 TypeError、不等待任何队列推进）
  否定断言:
    - playbackState.queueIndex 不得被修改（恒 null —— 应用不维护 audio_service 队列）
    - 不调用 audio_service 的 updateQueue / skipToQueueItem（无队列语义）
    - skipToNext/skipToPrevious 不得触发 player.play/pause/seek 等播放动作
  ```
  **修改点（唯一生产代码改动）**：`lib/core/services/audio_handler.dart:44`
  ```dart
  // 修改前（44 行）:
  class NasAudioHandler extends BaseAudioHandler
      with QueueHandler, SeekHandler
      implements IAudioHandler {
  // 修改后:
  class NasAudioHandler extends BaseAudioHandler
      // BUG-01: 移除 QueueHandler —— 本应用自管队列，audio_service 队列
      // 能力完全未用；QueueHandler._skip 对 queueIndex 的 `!` 解包
      // （audio_service.dart:3374）在生产常态（queueIndex 恒 null）下
      // 每次 skip 都抛 TypeError（cr-20260816-0801 B1）。super 落到
      // BaseAudioHandler no-op（audio_service.dart:3142/3145）。
      with SeekHandler
      implements IAudioHandler {
  ```
  同步修改文件头注释 `lib/core/services/audio_handler.dart:3-6`：把 "with [QueueHandler] and [SeekHandler] mixins" 改为仅提 SeekHandler，并注明 BUG-01 移除 QueueHandler 的原因（一句即可）。
  **不需要改** `audio_handler.dart:312-322` 的 skipToNext/skipToPrevious 方法体——移除 mixin 后 `super.skipToNext()` 自动解析到 BaseAudioHandler no-op。
  **编译可行性依据**：移除 QueueHandler 后 `super.skipToNext/skipToPrevious` 解析到 BaseAudioHandler 基类实现（pub 缓存 audio_service 0.18.18 `lib/audio_service.dart:3142/3145` `async {}`）；`updateQueue` 在 BaseAudioHandler 同样存在 no-op（同文件 3132 行 `Future<void> updateQueue(List<MediaItem> queue) async {}`）——既有测试 audio_handler_test.dart:284 的 updateQueue 调用仍可编译。

- **[BUG-01-S5]** 修复后 skip 完成语义：callback 触发 + Future 正常完成，无任何 audio_service 队列副作用 （status: new）
  ```
  Given handler 已接线 skip 回调（任意非 null 实现）
  When handler.skipToNext()
  Then 回调恰好触发 1 次
  And skipToNext() 返回的 Future 正常完成
  否定断言:
    - playbackState.queueIndex 保持 null（INV1）
    - playbackState 的其它字段（controls/playing/processingState 等）不得被 skip 调用改动
  ```
  Code evidence（修改点）: `lib/core/services/audio_handler.dart:312-322` 方法体保留 + `audio_handler.dart:44` mixin 移除；no-op 基类 `audio_service.dart:3142/3145`。

**边界裁决（弱模型照此实现，无需二次判断）**：

| 边界情况 | 裁决 |
|---|---|
| 队列为空 / queueIndex 恒 null | 不抛错；callback 照常触发；super no-op 完成。本方案不读任何队列状态 |
| onSkipToNextRequested 为 null | `?.call()` 空操作，不抛错（S3 现有行为保持） |
| 既有测试 audio_handler_test.dart:265-325（播种 queueIndex:0 段） | 仍可编译、断言仍全绿（updateQueue 落到 BaseAudioHandler no-op，播种的 queueIndex 不再被消费）；该段 316-318 行注释（"audio_service 内部语义"前提）已过时，**允许 dev-exe 只更新注释文字、严禁改断言** |
| 测试文件里其余 updateQueue / skipToQueueItem 引用 | grep 核实：仅 audio_handler_test.dart:284 一处 updateQueue；无 skipToQueueItem（ply_05_test.dart:457 的 skipToQueueItem 是 PlayQueue 值对象方法，与 handler 无关） |
| IAudioHandler 契约 | 不改契约（audio_handler_contract.dart:64-67 签名不变），本方案零契约面变化 |
| 通知栏按钮仍显示 skip 控件 | 不变（_buildControls 固定返回三按钮，audio_handler.dart:203-209），skip 行为经回调 + no-op 完成 |

---

## §4 不变量

- **[BUG-01-INV1]** 应用不维护 audio_service 队列：`playbackState.queueIndex` 恒为 null
  证据：`lib/` 全库 grep `queueIndex` 0 命中；`lib/core/services/audio_handler.dart:140-153` copyWith 字段清单不含 queueIndex；修复不新增任何 queueIndex 写入点。

- **[BUG-01-INV2]** 通知栏/耳机的 skip 导航唯一入口是 `onSkipToNextRequested` / `onSkipToPreviousRequested` 回调（handler 自身不读队列）
  证据：`lib/core/services/audio_handler.dart:314/320`（callback 先于 super 执行）+ `lib/` grep 接线点唯一（见 BUG-02 修复后接线点）。

---

## §5 测试规约

### 5.1 现有测试清单

| 测试文件 | 覆盖的 Scenario / INV | 备注 |
|---|---|---|
| test/core/services/audio_handler_test.dart:265-325 | BUG-01-S1 的"播种态"变体 | 假设错误（播种 queueIndex 绕开异常），断言保持、注释过时 |
| test/features/player/bug_01_repro_test.dart | BUG-01-S4 / BUG-01-S5 / BUG-01-INV1 | 本 Bug 门禁（修复前 FAIL，已用 repro-test.sh fail 确认） |

### 5.2 测试 ID 派生清单（dev-exe 派发测试 Agent 用）

```
BUG-01-S1 … S5        # Scenario（S1~S3 为缺陷态/现状锚定，S4/S5 为修复目标）
BUG-01-INV1 … INV2    # 不变量
BUG-01-MAN1 …         # 手动 QA 步骤（见 §8）
```

dev-exe 要求：S4/S5/INV1 已由 §5.4 门禁测试覆盖；S1~S3 由既有测试文件或 §5.4 门禁顺带锚定（bug_01_repro_test.dart 的驱动态即 S1 生产常态）。

### 5.3 测试覆盖盲点（dev-plan 写本文档时识别）

| 未覆盖 ID | 现状 | 应补偿方式 |
|---|---|---|
| BUG-01-MAN1/MAN2 | 通知栏/耳机按键为平台通道行为，fake 测不到 | 进 mqa-backlog（§8） |

### 5.4 测试文件位置（spec-scan --gate 硬校验）

| 测试文件 | 覆盖 ID | 说明 |
|---|---|---|
| test/features/player/bug_01_repro_test.dart | BUG-01-S4、BUG-01-S5、BUG-01-INV1 | 门禁：dev-exe 修复后必须 PASS（repro-test.sh pass） |
| test/core/services/audio_handler_test.dart | BUG-01-S1（现状段） | 既有文件，断言保持不变；dev-exe 允许更新 265-325 段过时注释 |

---

## §6 算法样例

本 Bug 不涉纯函数算法，跳过。

---

## §7 跨模块影响

`bash cross-imports.sh impact lib/core/services/audio_handler.dart lib/features/player/player_screen.dart`（2026-08-16）→ 引用方：

| 其它 feature | 影响点 | 影响条件 | 需要补的回归断言 |
|---|---|---|---|
| Player（player_provider.dart） | audioHandlerProvider 消费方（player_provider.dart:130 强转 NasAudioHandler 清 mediaItem） | 修复不改类声明以外的任何面（类名/构造签名不变） | player 模块既有测试全绿；bug_01_repro_test.dart PASS |
| 入口（main.dart） | AudioService.init builder 创建 NasAudioHandler（main.dart:35-36） | 无（类名不变） | 编译 + analyze 0 warning |
| Player 通知栏链路（BUG-02） | skip 回调接线点与 handler 行为 | 修复后 skip 不再抛错，回调可被 BUG-02 的接线正常消费 | BUG-02 门禁测试（test/features/player/bug_02_repro_test.dart）PASS |
| 测试侧 | 构造 NasAudioHandler 的 8 个测试文件（audio_handler_test / bug_05 / bug_06 / bug_17 / bug_bug22×2 / bug_01 / bug_02 repro） | 类签名不变 | 全部保持绿 |

---

## §8 平台特性与手动 QA

设计前已逐条核对 `docs/dev/platform-pitfalls.md`：触及 **P8**（播放监听器不得绑定页面 dispose——本条 B1 的 skip 回调链路是 P8 同类生命周期资源，与 BUG-02 一起处置）与 **P4**（平台调用超时——skip 不涉播放调用，无新增超时面）。P17 分层表不涉及（skip 不经平台调用）。

**真机风险列**（fake 测不到、只有真机会出问题的）：

| 风险 | 近似测试方案 | 测不了 → 进 mqa-backlog |
|---|---|---|
| 通知栏"下一首/上一首"每次按键向平台侧抛 TypeError（MediaSession 记错误日志） | bug_01_repro_test.dart 断言 handler.skipToNext() 不抛错（修复后 PASS） | BUG-01-MAN1：真机播放后按通知栏下一首，`adb logcat` 无 `TypeError`/`Null check` 字样 |
| 耳机线控 ACTION_NEXT/ACTION_PREVIOUS 走同一 handler 方法 | 同上（同一入口 skipToNext） | BUG-01-MAN2：真机插耳机连按下一首/上一首各 3 次，切歌正常无卡顿 |
| 锁屏控件 skip 行为 | 同上 | BUG-01-MAN3：锁屏界面点上一首/下一首，切歌正常 |

涉及 audio_service 通知栏/锁屏控件/耳机按键 → `manual_qa_required = true`。

---

## §9 dev-status.json 条目对照

```json
"BUG-01": {
  "spec_file": "docs/features/BUG-01.md",
  "spec_anchored_files": ["lib/core/services/audio_handler.dart", "test/core/services/audio_handler_test.dart"],
  "scenarios": ["BUG-01-S1", "BUG-01-S2", "BUG-01-S3", "BUG-01-S4", "BUG-01-S5"],
  "invariants": ["BUG-01-INV1", "BUG-01-INV2"],
  "algorithms": [],
  "manual_qa_required": true,
  "user_acceptance_text": "见 §1.2"
}
```
