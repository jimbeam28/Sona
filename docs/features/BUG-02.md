# BUG-02 — skip 回调绑定 PlayerScreen dispose：退出播放页后通知栏切歌按钮永久失效（P8 违规）

## §0 头部元数据

```yaml
id: BUG-02
name: skip 回调绑定 PlayerScreen dispose，退出播放页后通知栏按钮失效（P8）
priority: P1
status: active
created_at: 2026-08-16
last_updated: 2026-08-16
spec_anchored_files:
  - lib/features/player/player_screen.dart
  - lib/features/player/player_provider.dart
  - lib/core/services/audio_handler.dart
  - lib/features/home/home_screen.dart
cross_module_impacts: [PLY, HOME]
parent_feature: Player（音频播放/Player 模块）
manual_qa_required: true        # 涉 audio_service 通知栏/后台播放
```

---

## §1 用户视角

### 1.0 原始需求（用户原话逐字记录）

来源：`docs/cr/cr-20260816-0801-core-shared.md` F1（cr 复核已确认仍存在）：

> #### F1. skip 回调绑定 PlayerScreen dispose——退出播放页后通知栏切歌按钮永久失效（P8 违规）
> - 类型 / 严重度 / 维度：FRAGILE / Major / 功能-踩坑(P8) + 并发时序
> - 证据：`lib/features/player/player_screen.dart:74-79`（initState：`handler.onSkipToNextRequested = _playNext;`）与 `player_screen.dart:112-116`（dispose：`handler.onSkipToNextRequested = null;`）。全库 grep 确认此回调仅此一处接线。P8 踩坑库明文："播放生命周期监听器归编排层持有，严禁绑定任何页面的 dispose；'跳过加载'的快路径必须同时重连监听器"——skip 回调与 P8 所述监听器属同类生命周期资源。
> - 条件化复现路径：
>   1. 播放曲目并打开播放器页（回调接线）→ 返回浏览页（PlayerScreen dispose，回调置空）。
>   2. 通知栏按"下一首" → 期望：切到下一曲；实际：回调为 null，`onSkipToNextRequested?.call()` 是空操作，按钮无响应（叠加 B1 的 TypeError，双重失效）。
>   3. 触发条件：任何使 PlayerScreen 离开导航栈的路径（系统返回、路由 pop、切换连接等），播放仍在后台继续时。
>   注：即使 B1 修复（不再抛 TypeError），本条仍独立成立——callback 为 null 时按钮依然无任何动作。
> - 自检答案：**该分支零覆盖**——所有 audio_handler 测试（audio_handler_test.dart、bug_05/bug_17 系列）都在 handler 存活且回调已注入的状态下构造，没有用例走过 "PlayerScreen dispose → handler.skipToNext()（callback=null）" 路径；PlayerScreen 的 widget 测试也不驱动通知栏按钮。
> - 修复建议：skip 回调接线提升到编排层/应用级生命周期（如 player_provider 或 orchestrator provider 内随 handler 一次性 wire，参照 onConfigChanged 在 home_screen 的 eager-wire 模式），随 handler 存在而存在，不随任何页面 dispose 失效。

### 1.1 这一功能干什么（一句话）

把通知栏 / 耳机"上一首 / 下一首"的驱动回调从播放器页面的生命周期（initState 接线、dispose 置空）提升到应用级接线——只要应用在跑、播放在进行，通知栏切歌按钮就始终有效，退出播放器页面不再使其失效。

### 1.2 用户期望的场景

| ID | 你看到的样子 | 期望行为 |
|----|----|----|
| U1 | 播放中退出播放器页面，回到浏览页，音乐继续在后台播 | 下拉通知栏点"下一首"→ 切到下一曲（修复前按钮完全无响应） |
| U2 | 播放中按系统返回键一路退到首页，音乐继续在后台播 | 通知栏"上一首 / 下一首"仍有效 |
| U3 | 播放中切换到其它连接、或经路由跳到任意页面后播放仍在继续 | 通知栏切歌按钮始终有效 |
| U4 | 播放器页面开着时点通知栏"下一首" | 切歌成功，行为不变 |
| U5 | 应用刚启动、还没有开始播放时 | 通知栏不存在/无按钮，不产生任何副作用（接线时机安全） |

---

## §2 已实现的功能骨架（代码锚点）

### 2.1 文件与分层

| 层 | 文件 | 行数 | 角色 |
|---|---|---|---|
| UI | `lib/features/player/player_screen.dart` | 432 | 播放页：74-79 接线 skip 回调（缺陷点）、112-116 dispose 置空（缺陷点）、229-235 页面内 _playNext/_playPrevious |
| Provider | `lib/features/player/player_provider.dart` | 401 | skipToNextProvider/skipToPreviousProvider（349-364）、backgroundPlaybackSyncProvider（241-246，onConfigChanged eager-wire 参照模式） |
| UI | `lib/features/home/home_screen.dart` | 202 | 79-80 build 中 `ref.read(backgroundPlaybackSyncProvider)` eager-wire 触发点 |
| Core | `lib/core/services/audio_handler.dart` | 346 | 312-322 skipToNext/skipToPrevious（callback 字段 53-55） |
| 契约 | `lib/core/contracts/audio_handler_contract.dart` | 94 | IAudioHandler skip 回调 setter（79-88） |

### 2.2 关键 Provider 表

| Provider 名 | 类型 | 实现位置 | 用途 |
|---|---|---|---|
| backgroundPlaybackSyncProvider | Provider<void> | player_provider.dart:241-246 | onConfigChanged eager-wire（home_screen.dart:80 读取触发）——本 Bug 修复的接线载体 |
| skipToNextProvider / skipToPreviousProvider | Provider<Future<TrackLoadResult> Function()> | player_provider.dart:349-364 | 编排层 skip 入口（orchestrator → gate 20s） |

### 2.3 状态机图

本 Bug 不涉状态机，跳过（接线生命周期见 §3）。

---

## §3 行为规约（Given-When-Then）

### 3.1 现有行为（逆抽，缺陷态）

- **[BUG-02-S1]** PlayerScreen initState 接线两个 skip 回调
  ```
  Given PlayerScreen 挂载（initState 执行）且 audioHandlerProvider 非 null
  When initState 运行
  Then handler.onSkipToNextRequested = _playNext、onSkipToPreviousRequested = _playPrevious
  ```
  Code evidence: `lib/features/player/player_screen.dart:74-79`。

- **[BUG-02-S2]** PlayerScreen dispose 把两个 skip 回调置 null（缺陷根源）
  ```
  Given PlayerScreen 挂载过（回调已接线）
  When PlayerScreen 离开导航栈（系统返回 / 路由 pop / 切换连接 → dispose）
  Then handler.onSkipToNextRequested = null、onSkipToPreviousRequested = null
  And 播放仍可能在后台继续（dispose 不停止播放）
  And 此后通知栏 skip → `?.call()` 空操作，按钮无动作
  ```
  Code evidence: `lib/features/player/player_screen.dart:112-116`；`audio_handler.dart:314`（`?.call()` 空操作）。

- **[BUG-02-S3]** 全库仅 PlayerScreen 一处接线 skip 回调
  ```
  Given grep lib/ onSkipToNextRequested / onSkipToPreviousRequested 赋值点
  Then 唯一接线点为 player_screen.dart:77-78，唯一置空点为 114-115
  ```
  Code evidence: `lib/` grep 核实（2026-08-16）。

- **[BUG-02-S4]** onConfigChanged 的 eager-wire 模式（修复参照）：接线在非 autoDispose Provider，随容器生命周期
  ```
  Given backgroundPlaybackSyncProvider 被 home_screen build 读取
  Then onConfigChanged 接线执行一次，ref.onDispose 仅在容器销毁时置 null
  ```
  Code evidence: `lib/features/player/player_provider.dart:241-246`（`ref.onDispose(() => h?.onConfigChanged = null)`）；`lib/features/home/home_screen.dart:79-80`（eager-read）。

### 3.2 修复方案（status: new）

- **[BUG-02-S5]** skip 回调接线迁移到 backgroundPlaybackSyncProvider（修改点 1） （status: new）
  ```
  Given backgroundPlaybackSyncProvider 被读取（home_screen.dart:80 eager-read，应用启动必经 home 路由）
  When provider 初始化
  Then onSkipToNextRequested 接线为 `ref.read(skipToNextProvider)()`
  And onSkipToPreviousRequested 接线为 `ref.read(skipToPreviousProvider)()`
  And ref.onDispose 统一清 onConfigChanged / onSkipToNextRequested / onSkipToPreviousRequested
  否定断言:
    - 接线不发生在任何页面 State 的 initState/dispose 内（页面销毁不得触碰回调）
    - handler 为 null（AudioService.init 失败，main.dart:49）时全部接线为空操作，不抛错
  ```
  **修改点**：`lib/features/player/player_provider.dart:241-246` 扩展 `backgroundPlaybackSyncProvider`：
  ```dart
  final backgroundPlaybackSyncProvider = Provider<void>((ref) {
    final h = ref.read(audioHandlerProvider);
    final n = ref.read(backgroundPlaybackProvider.notifier);
    h?.onConfigChanged = n.syncFromHandler;
    // BUG-02: skip 回调归应用级接线（P8 踩坑：播放生命周期资源严禁绑定
    // 页面 dispose）。通知栏/耳机 skip → 编排层推进队列；空队列下
    // orchestrator 安全返回 failed（playback_orchestrator.dart:253-255），
    // 无副作用。接线时机 = home_screen.dart:80 的 eager-read。
    h?.onSkipToNextRequested = () {
      unawaited(ref.read(skipToNextProvider)());
    };
    h?.onSkipToPreviousRequested = () {
      unawaited(ref.read(skipToPreviousProvider)());
    };
    ref.onDispose(() {
      h?.onConfigChanged = null;
      h?.onSkipToNextRequested = null;
      h?.onSkipToPreviousRequested = null;
    });
  });
  ```
  **可行性依据（铁律 6）**：接线载体与 fire-and-forget 均复用现有已实证模式——`ref.onDispose` 清回调 = 现有 `backgroundPlaybackSyncProvider` 自身模式（player_provider.dart:245-246）；`unawaited(ref.read(...))` = 现有 `startProcessingListenerProvider` 内用法（player_provider.dart:324 `unawaited(ref.read(loadAndPlayProvider)())`）。`dart:async` 已在 player_provider.dart:5 import。非 autoDispose Provider 生命周期 = ProviderScope 容器生命周期（Riverpod 2.6 标准语义，本文件 playbackOrchestratorProvider 同款）。

- **[BUG-02-S6]** 删除 PlayerScreen 的接线块与置空块（修改点 2） （status: new）
  ```
  Given PlayerScreen 挂载 / 销毁
  When initState / dispose 执行
  Then 不再读取 audioHandlerProvider、不再触碰 handler 回调
  And PlayerScreen 的其它 dispose 逻辑（_saveProgressWithContainer /
      _timerExpiryChecker.cancel / cancelPlaybackSubscriptions /
      removeObserver）保持不变
  否定断言:
    - PlayerScreen dispose 后 handler.onSkipToNextRequested 仍非 null
      （本 Bug 门禁断言，bug_02_repro_test.dart）
    - dispose 后调用 handler.skipToNext() 不抛错且回调仍执行（依赖 BUG-01 修复）
  ```
  **修改点**：`lib/features/player/player_screen.dart:74-79`（initState 内整块删除，含 75 行 `final handler = ref.read(audioHandlerProvider);` 与 76-79 行 if 块）与 `player_screen.dart:112-116`（dispose 内整块删除，含 112 行 `final handler = _container.read(audioHandlerProvider);` 与 113-116 行 if 块）。删除后 `audioHandlerProvider` 在 player_screen.dart 不再被引用（import 保留与否由 flutter analyze unused_import 提示决定——dev-exe 按 analyze 0 warning 要求处理，若 handler 类型不再出现则删对应 import 行，不得动其它 import）。
  注意：`_playNext`/`_playPrevious`（229-235）与 `PlaybackControls` 的 onNext/onPrevious（364-367）**保留不动**——页面内按钮仍走 `_runSerializedLoad`（UI loadState + 15s 超时）。

- **[BUG-02-S7]** 空队列 / 未开始播放时接线已存在但无副作用（边界裁决） （status: new）
  ```
  Given home build 已 eager-read backgroundPlaybackSyncProvider（接线早于任何播放），
        且当前无播放队列（currentPlayQueueProvider == null）
  When 通知栏 skip 回调被触发（理论上按钮不应出现，防御路径）
  Then skipToNextProvider → orchestrator.skipToNext() → queue==null → TrackLoadResult.failed()
  And 无异常、无队列状态变化
  否定断言:
    - currentPlayQueueProvider 状态不得改变（不新建队列）
    - 不触发任何 player.play/pause 调用
    - 不抛任何异常（fire-and-forget 路径不得有 unhandled async error）
  ```
  Code evidence: `lib/features/player/domain/playback_orchestrator.dart:253-255`（`if (q == null) return const TrackLoadResult.failed();`）。

- **[BUG-02-S8]** 页面内按钮路径行为不变（防 dev-exe 误删） （status: new）
  ```
  Given PlayerScreen 存活（ready 态）
  When 点击页面内"下一首/上一首"按钮（PlaybackControls onNext/onPrevious）
  Then 仍走 _playNext/_playPrevious → _runSerializedLoad → skipToNextProvider/
      skipToPreviousProvider（UI loadState 更新 + 15s UI 超时 + token 串行化）
  And 页面内路径不经 handler 回调（与通知栏路径解耦）
  否定断言:
    - 页面按钮不得改为直接读 handler 回调（保持 _runSerializedLoad 封装）
    - UI loadState 与 15s 超时（player_screen.dart:148-176）逻辑不得被改动
  ```
  Code evidence: `lib/features/player/player_screen.dart:229-235`、`364-367`、`148-176`。

**边界裁决汇总（弱模型照此实现，无需二次判断）**：

| 边界情况 | 裁决 |
|---|---|
| handler 为 null（AudioService.init 失败） | `h?.` 空安全，全部接线/清线为空操作（S5 否定断言） |
| 接线早于任何播放（home build 即接线） | 允许；空队列 skip 安全无副作用（S7） |
| PlayerScreen 反复进出 | 不再触碰回调；接线唯一在 provider 层，无重复接线 |
| 通知栏 skip 与页面内按钮同时触发（竞态） | 串行化由 orchestrator 的 SerializedRequestGate 20s 兜底（P14/P17），本 Bug 不改动该层 |
| backgroundPlaybackSyncProvider 被多次读取 | 普通 Provider（非 autoDispose）只初始化一次（Riverpod 2.6 语义），无重复接线 |
| dispose 后 PlayerScreen 内部 _container 仍被读取（_saveProgressWithContainer） | 保留现状不动（player_screen.dart:104/261-263 既有行为，本 Bug 不涉及） |

---

## §4 不变量

- **[BUG-02-INV1]** skip 回调生命周期 = 应用容器生命周期：接线在非 autoDispose Provider（backgroundPlaybackSyncProvider），仅容器销毁时经 ref.onDispose 清空，任何页面 dispose 不得触碰
  证据：`lib/features/player/player_provider.dart:241-246`（修复后）+ `audio_handler.dart:53-55` 回调字段；参照现有同款模式（onConfigChanged 接线 245-246）。

- **[BUG-02-INV2]** 通知栏/耳机 skip 路径无 UI 层 15s 超时参与，兜底为 orchestrator 加载 gate 20s（P17 分层表语义）
  证据：`docs/dev/platform-pitfalls.md` P17（加载请求 gate 20s：`lib/features/player/domain/request_gate.dart`）；修复接线直接调 skipToNextProvider（player_provider.dart:349-355，内部 orchestrator 经 gate）。

---

## §5 测试规约

### 5.1 现有测试清单

| 测试文件 | 覆盖的 Scenario / INV | 备注 |
|---|---|---|
| test/features/player/bug_02_repro_test.dart | BUG-02-S5 / BUG-02-S6 | 本 Bug 门禁（修复前 FAIL，已用 repro-test.sh fail 确认） |
| test/features/player/ply_14_test.dart | BUG-02-S8（页面按钮路径） | 既有 PlayerScreen widget 测试（TST-T46 上一首/下一首按钮） |
| test/features/home/home_screen_test.dart 等 | BUG-02-S5（eager-read 触发点） | 既有 home 测试（home_screen.dart:80 行为不变） |

### 5.2 测试 ID 派生清单（dev-exe 派发测试 Agent 用）

```
BUG-02-S1 … S8        # Scenario（S1~S4 现状锚定，S5~S8 修复目标）
BUG-02-INV1 … INV2    # 不变量
BUG-02-MAN1 …         # 手动 QA 步骤（见 §8）
```

dev-exe 要求：S5/S6 由 §5.4 门禁覆盖；S7（空队列）建议在 provider 层补一条（构造 backgroundPlaybackSyncProvider 场景或直接驱动 orchestrator 空队列——后者已有 orchestrator 测试基础，可复用 bug_bug19_repro_test.dart 的 fake 装配风格）；S8 由 ply_14 既有用例锚定（不变即可）。

### 5.3 测试覆盖盲点（dev-plan 写本文档时识别）

| 未覆盖 ID | 现状 | 应补偿方式 |
|---|---|---|
| BUG-02-S7 空队列接线副作用 | 无现成 provider 级测试覆盖 backgroundPlaybackSyncProvider 内 skip 接线 | dev-exe 补 provider 级测试（fake handler + 空 currentPlayQueueProvider） |
| BUG-02-MAN1~MAN3 | 通知栏/后台为平台通道行为，fake 测不到 | 进 mqa-backlog（§8） |

### 5.4 测试文件位置（spec-scan --gate 硬校验）

| 测试文件 | 覆盖 ID | 说明 |
|---|---|---|
| test/features/player/bug_02_repro_test.dart | BUG-02-S5、BUG-02-S6、BUG-02-INV1 | 门禁：dev-exe 修复后必须 PASS（repro-test.sh pass） |
| test/features/player/ply_14_test.dart | BUG-02-S8 | 既有文件，不变 |

---

## §6 算法样例

本 Bug 不涉纯函数算法，跳过。

---

## §7 跨模块影响

`bash cross-imports.sh impact lib/core/services/audio_handler.dart lib/features/player/player_screen.dart lib/features/player/player_provider.dart lib/features/home/home_screen.dart`（2026-08-16）→ 引用方：

| 其它 feature | 影响点 | 影响条件 | 需要补的回归断言 |
|---|---|---|---|
| HOME（home_screen.dart:79-80） | eager-read backgroundPlaybackSyncProvider 成为 skip 接线的唯一触发点 | 接线 provider 被扩展（home 侧无代码改动） | home 既有测试（home_screen_test / test_03_home* / bug_07_tab_sort_test）全绿 |
| 入口（main.dart:65） | audioHandlerProvider override 提供真实 handler | 无（provider 接口不变） | 编译 + analyze 0 warning |
| Player（player_screen.dart → app/router.dart） | 删除接线/置空块；页面按钮路径不变 | 页面行为不变 | ply_01~14 全绿；bug_02_repro_test.dart PASS |
| Player（player_provider.dart → main.dart:20 / onboarding.dart） | backgroundPlaybackSyncProvider 扩展（skip 接线） | 接线在 home build 触发；onboarding 早于 home 读取其它 provider 不受影响 | onboarding 既有测试全绿；restoreStartupProgressProvider 相关测试（o3_*/test_01_*）全绿 |
| 通知栏链路（BUG-01） | handler.skip 不再抛错后，回调可被正常消费 | BUG-01 先/后修复均不影响本接线（回调为 null 时 `?.call()` 空操作） | bug_01_repro_test.dart PASS |
| 测试侧 | 构造 NasAudioHandler 的 8 个测试文件 | 类签名不变 | 全部保持绿 |

---

## §8 平台特性与手动 QA

设计前已逐条核对 `docs/dev/platform-pitfalls.md`：本 Bug 即 **P8**（播放生命周期监听器严禁绑定页面 dispose）的直接违规处置；接线时间点与 P6（AudioService 后台 engine 缓存）无交集；P14（加载并发串行化）由 orchestrator gate 兜底（S7/S8 裁决）。

**真机风险列**（fake 测不到、只有真机会出问题的）：

| 风险 | 近似测试方案 | 测不了 → 进 mqa-backlog |
|---|---|---|
| 退出播放页后通知栏"下一首/上一首"按钮无响应 | bug_02_repro_test.dart 断言 dispose 后回调非 null（修复后 PASS） | BUG-02-MAN1：真机播放 → 返回键退出播放页 → 通知栏按下一首 → 期望切歌成功 |
| 系统返回一路退出到桌面（AppLifecycleState.paused）后通知栏按钮 | 同上（回调已应用级接线） | BUG-02-MAN2：真机播放中退到桌面，锁屏/通知栏按上一首、下一首各 2 次 → 期望均正常切歌 |
| 切换连接 / 任意路由跳转后通知栏按钮 | 同上 | BUG-02-MAN3：真机播放中进设置再返回（不经播放页）→ 通知栏下一首仍有效 |
| 应用刚启动未播放时接线已存在 | bug_02 门禁 + provider 级空队列测试（S7） | BUG-02-MAN4：真机冷启动后未播放，无崩溃/无异常日志 |

涉及 audio_service 通知栏、锁屏控件、后台播放 → `manual_qa_required = true`。

---

## §9 dev-status.json 条目对照

```json
"BUG-02": {
  "spec_file": "docs/features/BUG-02.md",
  "spec_anchored_files": [
    "lib/features/player/player_screen.dart",
    "lib/features/player/player_provider.dart",
    "lib/core/services/audio_handler.dart",
    "lib/features/home/home_screen.dart"
  ],
  "scenarios": ["BUG-02-S1", "BUG-02-S2", "BUG-02-S3", "BUG-02-S4", "BUG-02-S5", "BUG-02-S6", "BUG-02-S7", "BUG-02-S8"],
  "invariants": ["BUG-02-INV1", "BUG-02-INV2"],
  "algorithms": [],
  "manual_qa_required": true,
  "user_acceptance_text": "见 §1.2"
}
```
