# REF-03 — 后台播放状态机去镜像：删除 BackgroundPlaybackNotifier 死面，handler 唯一状态机

## §0 头部元数据

```yaml
id: REF-03
name: 后台播放状态机去镜像（handler 唯一状态机，notifier 缩为只读镜像）
priority: P2
status: active
created_at: 2026-08-16
last_updated: 2026-08-16
spec_anchored_files:
  - lib/features/player/background_playback_notifier.dart
  - lib/features/player/player_provider.dart
  - lib/core/services/audio_handler.dart
  - lib/features/home/home_screen.dart
  - lib/shared/di/providers.dart
  - lib/features/player/domain/background_playback.dart
cross_module_impacts: [PLY, HOME]
manual_qa_required: true        # 涉后台播放 / 通知栏 / 锁屏真实行为
```

---

## §1 用户视角

### 1.0 原始需求（用户原话逐字记录）

来源：`docs/cr/cr-20260816-0802-player.md` D1（cr 复核分流，用户裁决"修"→ 转 REF 需求流程）：

> #### D1. 后台播放状态机双实现：NasAudioHandler._config 是真身，BackgroundPlaybackNotifier 是无驱动方/无消费者的镜像
> - 类型 / 严重度 / 维度：DESIGN / Major / 状态机 + 内部一致性
> - 证据：
>
> `lib/core/services/audio_handler.dart:63`（生产真身）：
> ```dart
> BackgroundPlaybackConfig _config = BackgroundPlaybackConfig.initial;
> ```
> `lib/features/player/background_playback_notifier.dart:36-90`（驱动方法全部无调用方）：
> ```dart
> void onAppLifecycleChange(AppLifecycleState lifecycleState) {...}   // 零调用
> void onMediaControl(MediaControlAction action) {...}                 // 零调用
> void onAudioFocusChange(AudioFocusState focus) {...}                 // 零调用
> void startPlayback() / pausePlayback() / stopPlayback() / setBackgroundEnabled()  // 零调用
> void syncFromHandler(BackgroundPlaybackConfig config) { state = config; } // 唯一被调用的入口
> ```
> `lib/features/home/home_screen.dart:80`（唯一接线是单向镜像）；`grep backgroundPlaybackProvider` 除 re-export 外无 UI 消费者；`backgroundPlaybackEnabledProvider`（`player_provider.dart:219`）定义后无人读写；domain 纯函数 `computePlaybackStateAfterLifecycle`/`shouldContinueInBackground` 仅测试（ply_03）在消费。且 notifier 的 `onAppLifecycleChange` 实现（只切 foreground 标志）与 domain 纯函数语义（含 background continue 判断）不一致——同状态两套实现，漂移风险。
> - 取舍分析：`_config` 真身 + `onConfigChanged` 单向镜像可自洽（handler 单点驱动），但 8 个 public 驱动方法 + 1 个 StateProvider + 2 个纯函数是死面；要么删死代码让 handler 成为唯一状态机，要么把 lifecycle/focus 事件真正接到 notifier 并让 UI 消费。
> - 修复建议：交用户裁决：A) 删除未接线面（notifier 缩为只读镜像，删除 backgroundPlaybackEnabledProvider 及未用方法），保留 ply_03 对纯函数的测试；B) 补齐接线使 notifier 成为真状态机（work量大）。不修代码。

用户裁决：**选方案 A**——删除未接线死面（notifier 缩为只读镜像），handler `_config` 保持唯一生产状态机；domain 纯函数与 ply_03 对其的测试保留。

### 1.1 这一功能干什么（一句话）

消除后台播放状态的"双实现"：生产行为全部由 `NasAudioHandler._config` 状态机驱动（现状不变），删除 `BackgroundPlaybackNotifier` 上没有任何生产调用方的 7 个驱动方法、`mapLifecycleState` 函数与 `backgroundPlaybackEnabledProvider`，只保留被生产接线使用的只读镜像入口（`syncFromHandler` + `backgroundPlaybackProvider`）——后台播放、通知栏、锁屏行为与修复前逐字节一致。

### 1.2 用户期望的场景

| ID | 你看到的样子 | 期望行为 |
|----|----|----|
| U1 | 播放中下拉通知栏，暂停/播放/切歌/停止按钮 | 与修复前完全一致，按钮行为不变（后台播放状态机真身在 handler，未动） |
| U2 | 来电打断播放（音频焦点被抢） | 与修复前一致：暂停；挂断后行为不变 |
| U3 | 播放中退到桌面 / 锁屏，音乐继续播 | 与修复前一致，后台继续播放 |
| U4 | 更新应用后（修复完成） | 看不到任何界面变化（纯内部清理，无新功能、无新 UI） |
| U5 | 修复同时部署通知栏切歌修复（BUG-02） | 两者共存互不冲突：通知栏"下一首/上一首"仍有效 |

---

## §2 已实现的功能骨架（代码锚点）

### 2.1 文件与分层

| 层 | 文件 | 行数 | 角色 |
|---|---|---|---|
| Core | `lib/core/services/audio_handler.dart` | 346 | **生产真身**：`_config`（63）驱动点 = playerStateStream 订阅（96）→ `_syncConfigFromPlayerState`（184-193）/ `_updateConfig`（195-199，含 onConfigChanged 回调 198）/ interruption 流（105-124）→ `onAudioFocusChange`（243-254）/ play/pause/stop/onTaskRemoved（259-334，handleMediaControl 驱动）/ `_buildControls` 消费 `_config.showPauseAction`（203-209） |
| Provider | `lib/features/player/background_playback_notifier.dart` | 97 | 镜像：`mapLifecycleState`（14-20 零调用）/ `BackgroundPlaybackNotifier`（28-91，8 个驱动方法零调用 + `syncFromHandler` 88-90 唯一被调）+ `backgroundPlaybackProvider`（94-96） |
| Provider | `lib/features/player/player_provider.dart` | 401 | export 桥接（24-37 含 mapLifecycleState）/ `backgroundPlaybackEnabledProvider`（219 零生产读写）/ `backgroundPlaybackSyncProvider`（241-246 唯一接线） |
| UI | `lib/features/home/home_screen.dart` | 202 | 80 行 eager-read `backgroundPlaybackSyncProvider`（接线触发点） |
| 契约 | `lib/core/contracts/background_playback_contract.dart` | 221 | `BackgroundPlaybackConfig` 值对象 + 状态转移（updateForeground 108-119 / handleMediaControl 125-138 / updateAudioFocus 143-159）——handler 真身与纯函数共用 |
| Domain | `lib/features/player/domain/background_playback.dart` | 102 | 纯函数 `shouldContinueInBackground`（43-50）/ `computePlaybackStateAfterLifecycle`（58-101）——仅测试消费（ply_03） |
| 桥接 | `lib/shared/di/providers.dart` | 250 | 109-110 re-export `backgroundPlaybackEnabledProvider` / `backgroundPlaybackSyncProvider`；129-134 re-export `BackgroundPlaybackNotifier` / `backgroundPlaybackProvider` / 纯函数 |
| 测试 | `test/features/player/ply_03_test.dart` | 1270 | notifier 驱动方法测试（529-662 组内 7 个）+ `backgroundPlaybackEnabledProvider` 组（666-682）+ 纯函数测试（保留） |
| 测试 | `test/features/player/ref_13_test.dart` | 759 | Notifier onMediaControl 3 个测试（116-165） |
| 测试 | `test/core/services/audio_handler_test.dart` | — | handler.config 真身锚定（71/100-118/152-234 等）——本 REF 不动 |

### 2.2 关键 Provider 表

| Provider 名 | 类型 | 实现位置 | 用途 |
|---|---|---|---|
| backgroundPlaybackProvider | StateNotifierProvider\<BackgroundPlaybackNotifier, BackgroundPlaybackConfig\> | background_playback_notifier.dart:94-96 | 镜像状态容器；**BUG-02-S5 修复方案依赖**（`ref.read(backgroundPlaybackProvider.notifier)` 取 syncFromHandler） |
| backgroundPlaybackSyncProvider | Provider\<void\> | player_provider.dart:241-246 | 唯一生产接线：`h?.onConfigChanged = n.syncFromHandler`；**BUG-02-S5 扩展接线载体** |
| backgroundPlaybackEnabledProvider | StateProvider\<bool\> | player_provider.dart:219 | 死面：定义后零生产读写（仅 shared/di re-export + ply_03 测试）——**删除** |

### 2.3 状态机图

```
                    ┌─────────────────────────────────────────────┐
                    │  NasAudioHandler._config（唯一真身）          │
                    │  驱动：playerStateStream(96)                │
                    │       interruption/becomingNoisy(105-124)   │
                    │       play/pause/stop/onTaskRemoved(259-334)│
                    └──────────────────┬──────────────────────────┘
                                       │ _updateConfig (195-199)
                                       ▼
                            onConfigChanged?.call(_config)  (198)
                                       │
                                       ▼
              ┌──────────────────────────────────────────────┐
              │  BackgroundPlaybackNotifier.syncFromHandler    │ ← 唯一被调入口（player_provider.dart:244）
              │  state = config（只读镜像）                     │
              │  ── 死面（零生产调用，本次删除）：                │
              │     onAppLifecycleChange / onMediaControl /     │
              │     onAudioFocusChange / startPlayback /        │
              │     pausePlayback / stopPlayback /              │
              │     setBackgroundEnabled / mapLifecycleState     │
              └──────────────────────────────────────────────┘
```

---

## §3 行为规约（Given-When-Then）

### 3.1 现有行为（逆抽）

- **[REF-03-S1]** handler `_config` 是生产唯一驱动者：播放状态、焦点、媒体控制全部经 `_updateConfig` 更新
  ```
  Given NasAudioHandler 存活（main.dart AudioService.init 创建）
  When playerStateStream 推送 playing=true / interruption 流推送 focus lost /
      play()/pause()/stop()/onTaskRemoved() 被系统媒体会话调用
  Then _syncConfigFromPlayerState / updateAudioFocus / handleMediaControl
      产出 next → _updateConfig（相等去重 196）→ _config = next
  And 每次 _config 变化 → onConfigChanged?.call(_config)（198）
  ```
  Code evidence:
  - `lib/core/services/audio_handler.dart:96`（`_player.playerStateStream.listen(_onPlayerStateChanged)`）
  - `lib/core/services/audio_handler.dart:184-193`（_syncConfigFromPlayerState）
  - `lib/core/services/audio_handler.dart:105-124`（interruption/becomingNoisy → onAudioFocusChange）
  - `lib/core/services/audio_handler.dart:259-334`（play/pause/stop/onTaskRemoved → handleMediaControl）
  - `lib/core/services/audio_handler.dart:195-199`（_updateConfig：相等去重 + 赋值 + 回调）

- **[REF-03-S2]** onConfigChanged 单向镜像接线：home eager-read 触发，provider 内接线
  ```
  Given HomeScreen build 执行（home_screen.dart:80 ref.read(backgroundPlaybackSyncProvider)）
  When backgroundPlaybackSyncProvider 初始化（player_provider.dart:241-246）
  Then h?.onConfigChanged = n.syncFromHandler（n = backgroundPlaybackProvider.notifier）
  And ref.onDispose 时置 null（245-246）
  ```
  Code evidence: `lib/features/player/player_provider.dart:241-246`；`lib/features/home/home_screen.dart:80`。

- **[REF-03-S3]** notifier 8 个驱动方法 + mapLifecycleState + backgroundPlaybackEnabledProvider 生产零调用（死面）
  ```
  Given grep lib/ 全量（2026-08-16）
  Then onAppLifecycleChange / onMediaControl / onAudioFocusChange / startPlayback /
      pausePlayback / stopPlayback / setBackgroundEnabled 仅定义于
      background_playback_notifier.dart（36-84），无任何生产调用方
  And mapLifecycleState（14-20）无生产调用方
  And backgroundPlaybackEnabledProvider（player_provider.dart:219）无生产读写方
      （shared/di/providers.dart:109 仅 re-export，不构成读写）
  And syncFromHandler（88-90）唯一生产调用点 = player_provider.dart:244
  ```
  Code evidence:
  - `lib/features/player/background_playback_notifier.dart:36-84`（7 个驱动方法）+ `14-20`（mapLifecycleState）+ `88-90`（syncFromHandler）
  - `lib/features/player/player_provider.dart:219`（backgroundPlaybackEnabledProvider 定义）、`:244`（syncFromHandler 唯一生产调用）
  - `lib/` grep 核实（2026-08-16，无其它调用方）

- **[REF-03-S4]** domain 纯函数仅测试消费；contract 状态转移方法被 handler 真身生产消费
  ```
  Given 全库 grep computePlaybackStateAfterLifecycle / shouldContinueInBackground
  Then 生产（lib/）零调用方；唯一消费 = test/features/player/ply_03_test.dart（43-205 等）
  And BackgroundPlaybackConfig.updateForeground / handleMediaControl / updateAudioFocus
      （contract 层）被 handler 生产消费（audio_handler.dart:260/278/289/327/244）
  ```
  Code evidence: `lib/features/player/domain/background_playback.dart:43-50、58-101`；`test/features/player/ply_03_test.dart`（纯函数测试组）；`lib/core/services/audio_handler.dart:244、260、278、289、327`。

### 3.2 修改方案（status: new）

设计裁决（用户裁决方案 A）与 BUG-02 边界（显式，先读 `docs/features/BUG-02.md` §3.2）：

| 裁决项 | 结论 |
|---|---|
| BUG-02-S5 修改点（player_provider.dart:241-246 扩展 skip 接线）依赖 `ref.read(backgroundPlaybackProvider.notifier)` 与 `n.syncFromHandler` | **REF-03 保留 `backgroundPlaybackProvider` 与 `syncFromHandler`**——二者是被生产消费的镜像入口，不在删除面内，与 BUG-02 无冲突 |
| BUG-02-S5 在 backgroundPlaybackSyncProvider 内新增 onSkipToNext/PreviousRequested 接线 | 与 REF-03 删除的 notifier 驱动方法无关（不同符号），互不干扰 |
| 执行顺序 | **无依赖，可并行/任意顺序**。若 BUG-02 先落地，REF-03 不得触碰 BUG-02-S5 新增的 skip 接线行；若 REF-03 先落地，BUG-02 照 spec 实施不受影响 |
| REF-03 删除面 | 仅：notifier 7 个驱动方法（onAppLifecycleChange / onMediaControl / onAudioFocusChange / startPlayback / pausePlayback / stopPlayback / setBackgroundEnabled）+ `mapLifecycleState` + `backgroundPlaybackEnabledProvider` + 对应测试 |
| 保留面 | `BackgroundPlaybackNotifier` 类本身（只含 syncFromHandler）、`backgroundPlaybackProvider`、`backgroundPlaybackSyncProvider`、`onConfigChanged` 镜像链路、domain 纯函数（ply_03 锚定）、handler `_config` 真身全不动 |

- **[REF-03-S5]** 删除 notifier 7 个驱动方法与 mapLifecycleState（修改点 1） （status: new）
  ```
  Given lib/features/player/background_playback_notifier.dart
  When dev-exe 实施本 REF
  Then 删除 mapLifecycleState（14-20）整块
  And 删除 onAppLifecycleChange（36-52）、onMediaControl（56-58）、onAudioFocusChange（62-64）、
      startPlayback（67-69）、pausePlayback（72-74）、stopPlayback（77-79）、setBackgroundEnabled（82-84）
  And 保留 BackgroundPlaybackNotifier 类 + syncFromHandler（88-90）+ backgroundPlaybackProvider（94-96）
  And 类注释（22-27）同步改为"read-only mirror"语义（不得再声称 UI/lifecycle 可驱动转移）
  And import 'package:flutter/material.dart'（8）在 AppLifecycleState 无引用后删除
      （flutter_riverpod 保留；import 'domain/background_playback.dart' 保留——syncFromHandler 参数类型）
  否定断言:
    - 不得删除 syncFromHandler 与 backgroundPlaybackProvider（BUG-02-S5 依赖，player_provider.dart:243-244）
    - 不得改动 handler（audio_handler.dart）的 _config 状态机任何一行
    - 不得删除 domain 纯函数（computePlaybackStateAfterLifecycle / shouldContinueInBackground）
    - 删除后文件不得残留对 AppLifecycleState / AppLifecyclePhase 的引用（material import 清理干净）
  ```
  Code evidence（修改点）: `lib/features/player/background_playback_notifier.dart:14-20、36-84`（删除面）；`:88-96`（保留面）；BUG-02 依赖见 `docs/features/BUG-02.md` §3.2 S5 修改点代码片段（`ref.read(backgroundPlaybackProvider.notifier)` / `n.syncFromHandler`）。

- **[REF-03-S6]** 删除 backgroundPlaybackEnabledProvider 及两处 export 行（修改点 2/3/4） （status: new）
  ```
  Given player_provider.dart:219 与 shared/di/providers.dart:109
  When dev-exe 实施本 REF
  Then 删除 player_provider.dart:219 的 backgroundPlaybackEnabledProvider 定义行
  And 删除 shared/di/providers.dart:109 的 backgroundPlaybackEnabledProvider re-export 行
      （110 行 backgroundPlaybackSyncProvider 保留）
  And 删除 player_provider.dart:28 export show 清单中的 mapLifecycleState
  And player_provider.dart export 清单中 BackgroundPlaybackNotifier / backgroundPlaybackProvider
      （24-27）与 computePlaybackStateAfterLifecycle / shouldContinueInBackground（36-37）保留
  否定断言:
    - 不得删除 backgroundPlaybackSyncProvider（110 行保留；home_screen.dart:80 仍依赖）
    - 不得删除 shared/di/providers.dart:129-134 的 BackgroundPlaybackNotifier /
      backgroundPlaybackProvider / 纯函数 re-export（生产符号仍存在）
  ```
  Code evidence（修改点）: `lib/features/player/player_provider.dart:24-28、36-37、219`；`lib/shared/di/providers.dart:109-110、129-134`。

- **[REF-03-S7]** 同步删除测试中的死面锚定，保留纯函数测试与镜像链路测试（修改点 5/6 + 新测试） （status: new）
  ```
  Given test/features/player/ply_03_test.dart 与 ref_13_test.dart
  When dev-exe 实施本 REF
  Then ply_03_test.dart：删除 group('BackgroundPlaybackNotifier')（529-662）内除
      'initial state is correct'（530-541）外的 7 个驱动方法测试（543-661）
  And ply_03_test.dart：删除 group('backgroundPlaybackEnabledProvider')（666-682）整组
  And ref_13_test.dart：删除 Notifier 3 个 onMediaControl 测试（116-165）
  And 保留 ply_03_test.dart 全部纯函数测试（computePlaybackStateAfterLifecycle /
      shouldContinueInBackground / BackgroundPlaybackConfig 值对象组）
  否定断言:
    - 不得删除 ply_03_test.dart 纯函数测试（用户裁决"保留 ply_03 对纯函数的测试"）
    - 删除后 test/ 不得引用已删符号（mapLifecycleState / onAppLifecycleChange /
      onMediaControl / onAudioFocusChange / startPlayback / pausePlayback /
      stopPlayback / setBackgroundEnabled / backgroundPlaybackEnabledProvider）——
      flutter analyze 0 warning 门禁兜底
  ```
  Code evidence（修改点）: `test/features/player/ply_03_test.dart:529-682`；`test/features/player/ref_13_test.dart:116-165`。

- **[REF-03-S8]** 镜像链路保持可用：onConfigChanged → syncFromHandler 链路测试（门禁） （status: new）
  ```
  Given ProviderContainer + 一个真实 NasAudioHandler 实例（或按 audio_handler_test.dart
      既有装配风格）+ audioHandlerProvider override
  When 触发 handler 状态变化（如 handler.pause() 或播放状态同步）
  Then backgroundPlaybackSyncProvider 初始化后（手动 read 触发接线）
      backgroundPlaybackProvider 的状态 == handler.config（镜像一致）
  否定断言:
    - 删除死面后 onConfigChanged 回调不得被置 null（backgroundPlaybackSyncProvider 的
      onDispose 才清，容器存活期间持续镜像）
    - handler.config 变化不产生未捕获异常（镜像链路吞错面为零）
  ```
  Code evidence（修改点）: 新测试文件（§5.4）；链路锚点 `lib/features/player/player_provider.dart:241-246` + `lib/core/services/audio_handler.dart:195-199`。

**边界裁决汇总（弱模型照此实现，无需二次判断）**：

| 边界情况 | 裁决 |
|---|---|
| 删除方法后 ply_03_test.dart 编译失败 | 属预期——S7 已规定同步删除对应测试；dev-exe 按 S7 执行后全量 `flutter analyze` 0 warning 为门禁 |
| syncFromHandler 与 BUG-02 skip 接线在同一个 provider（241-246） | 两符号不同名不同行，互不影响；REF-03 不写该函数体，只保留 |
| background_playback_notifier.dart 删除 material import 后 flutter_riverpod 是否仍需要 | StateNotifier/StateNotifierProvider 来自 flutter_riverpod → 保留；由 analyze 的 unused_import 提示复核 |
| background_playback.dart（player 层 re-export 壳，10 行） | 保留不动（对外兼容壳，shared/di 与旧引用方依赖） |
| audio_handler_contract.dart:20 注释提到 BackgroundPlaybackNotifier | 纯注释，允许 dev-exe 顺手措辞更新（可选），严禁动契约签名 |

---

## §4 不变量

- **[REF-03-INV1]** handler `_config` 是后台播放状态的唯一生产驱动者；notifier 只读镜像，不得反向驱动 handler，也不被任何 UI 消费
  证据：`lib/core/services/audio_handler.dart:63`（_config 唯一真身）+ 184-199（唯一更新路径）；`lib/features/player/background_playback_notifier.dart:88-90`（修复后 syncFromHandler 为类内唯一方法）；`lib/` grep（2026-08-16，无其它生产驱动/消费）。

- **[REF-03-INV2]** 容器存活期间，`backgroundPlaybackProvider` 的状态恒等于最近一次 `onConfigChanged` 推送的 `handler._config`（相等去重后仍镜像）
  证据：`lib/core/services/audio_handler.dart:198`（`onConfigChanged?.call(_config)`）+ `lib/features/player/player_provider.dart:244`（`h?.onConfigChanged = n.syncFromHandler`）+ `background_playback_notifier.dart:88-90`（`state = config`）。

---

## §5 测试规约

### 5.1 现有测试清单

| 测试文件 | 覆盖的 Scenario / INV | 备注 |
|---|---|---|
| test/features/player/ply_03_test.dart | REF-03-S4（纯函数部分） | 纯函数测试保留；notifier 驱动方法测试（543-661）与 backgroundPlaybackEnabledProvider 组（666-682）删除（S7） |
| test/features/player/ref_13_test.dart | — | Notifier onMediaControl 3 测试（116-165）删除（S7）；值对象/纯函数组保留 |
| test/core/services/audio_handler_test.dart | REF-03-S1（handler.config 真身锚定：71/100-118/152-234） | 既有文件不动，修复后保持绿（回归护栏） |
| test/features/home/home_screen_test.dart 等 | REF-03-S2（home eager-read 接线点） | 既有 home 测试不动 |

### 5.2 测试 ID 派生清单（dev-exe 派发测试 Agent 用）

```
REF-03-S1 … S8        # Scenario（S1~S4 现状锚定，S5~S8 修复目标）
REF-03-INV1 … INV2    # 不变量
REF-03-MAN1 … MAN4    # 手动 QA 步骤（见 §8）
```

dev-exe 要求：S1 由 audio_handler_test.dart 既有锚定覆盖；S5~S8 由 §5.4 门禁测试文件 + 既有测试改造覆盖。

### 5.3 测试覆盖盲点（dev-plan 写本文档时识别）

| 未覆盖 ID | 现状 | 应补偿方式 |
|---|---|---|
| REF-03-S2/S8（onConfigChanged → syncFromHandler 镜像链路） | 零锚定（grep test/ 无 onConfigChanged/syncFromHandler 断言） | §5.4 门禁文件补镜像链路测试 |
| REF-03-INV1（notifier 无驱动能力） | 修复前不适用 | §5.4 门禁文件断言 notifier 只暴露 syncFromHandler（编译期符号面） |
| REF-03-MAN1~MAN4 | 通知栏/锁屏/后台为平台通道行为 | 进 mqa-backlog（§8） |

### 5.4 测试文件位置（spec-scan --gate 硬校验）

新建：`test/features/player/ref_03_mirror_test.dart`（命名已 grep 核实与既有文件无冲突；ProviderContainer + handler 装配风格仿 `test/features/player/bug_01_test.dart` / `test/core/services/audio_handler_test.dart`）。

| 测试文件 | 覆盖 ID | 说明 |
|---|---|---|
| test/features/player/ref_03_mirror_test.dart | REF-03-S2、S5、S8、REF-03-INV1、REF-03-INV2 | 门禁：dev-exe 修复后必须 PASS（cov-gate 内）。S5 的编译期符号面由全量 analyze 覆盖 |
| test/features/player/ply_03_test.dart | REF-03-S4（纯函数保留部分） | 既有文件，按 S7 删除死面测试后保持绿 |
| test/features/player/ref_13_test.dart | — | 按 S7 删除 Notifier 测试后保持绿 |
| test/core/services/audio_handler_test.dart | REF-03-S1 | 既有文件，断言不变，修复后保持绿 |
| test/features/home/home_screen_test.dart 等 | REF-03-S2 | 既有文件，断言不变 |

---

## §6 算法样例

本 REF 不涉纯函数算法（纯函数保留面行为不变，ply_03 已锚定），跳过。

---

## §7 跨模块影响

`bash cross-imports.sh impact lib/features/player/background_playback_notifier.dart lib/features/player/player_provider.dart lib/core/services/audio_handler.dart lib/features/home/home_screen.dart lib/shared/di/providers.dart lib/features/player/domain/background_playback.dart`（2026-08-16）→ 引用方：

| 其它 feature | 影响点 | 影响条件 | 需要补的回归断言 |
|---|---|---|---|
| HOME（home_screen.dart:80） | eager-read `backgroundPlaybackSyncProvider` | provider 保留、接线不变 | home 既有测试（home_screen_test / bug_07_tab_sort_test 等）全绿 |
| 入口（main.dart） | audioHandlerProvider override | handler 类签名不变 | 编译 + analyze 0 warning |
| Player（player_provider.dart） | 删 backgroundPlaybackEnabledProvider + export mapLifecycleState | BUG-02 接线载体（241-246）保留 | ply_01~14 全绿；BUG-02 门禁测试（bug_02_repro_test.dart）PASS |
| Player 测试侧（ply_03 / ref_13） | 删除死面测试 | 删除符号后测试同步删除 | 删除后全量 flutter test 绿 + analyze 0 warning |
| 通知栏链路（audio_handler.dart） | _config 真身不动 | 无 | audio_handler_test.dart 全绿（TEST-08-S1~S5 等 config 断言） |
| 跨 feature 桥接（shared/di/providers.dart:109-110、129-134） | 删 109 行 re-export | 110/129-134 保留 | cross-imports.sh all 零基线外违规 |

---

## §8 平台特性与手动 QA

设计前已逐条核对 `docs/dev/platform-pitfalls.md`：

- **P5/P6**（AudioServiceConfig / engine 缓存）：本次只删 provider 层死代码，不触碰 main.dart 与 handler 初始化——无交集。
- **P3**（playing 状态传播）：真身 `_syncConfigFromPlayerState`（audio_handler.dart:184-193）未动，镜像侧不参与生产行为——无交集。
- **P8**（监听器生命周期）：handler 内订阅（96-99）与接线 provider 生命周期均未动；BUG-02 的 skip 接线迁移是另一条独立改动——无交集。
- **P9**（defunct setState）：本次无 UI setState 改动——无交集。
- **P1/P2/P4/P7/P14/P17**：不触及。

**真机风险列**（fake 测不到、只有真机会出问题的）：

| 风险 | 近似测试方案 | 测不了 → 进 mqa-backlog |
|---|---|---|
| 删除死代码后通知栏播放/暂停/停止按钮行为回归 | handler 六方法测试（audio_handler_test.dart）+ ref_03_mirror_test.dart 镜像链路 | REF-03-MAN1：真机播放 → 通知栏依次点暂停/播放/停止 → 期望与修复前一致 |
| 锁屏/耳机媒体控制行为回归 | 同上（handler 单点驱动，未动） | REF-03-MAN2：真机锁屏状态下上一首/下一首/播放/暂停 → 期望正常 |
| 来电打断（audio focus lost）行为回归 | handler onAudioFocusChange 测试（TEST-08-S5）+ 真身未动 | REF-03-MAN3：真机播放中来电 → 期望暂停；挂断后行为与修复前一致 |
| 后台继续播放 / 退桌面不中断 | handler _config 真身锚定（ply_03 纯函数保留） | REF-03-MAN4：真机播放中退到桌面 → 音乐继续；回前台状态正常 |

涉及 audio_service 通知栏、锁屏控件、后台播放 → `manual_qa_required = true`。

---

## §9 dev-status.json 条目对照

```json
"REF-03": {
  "spec_file": "docs/features/REF-03.md",
  "spec_anchored_files": [
    "lib/features/player/background_playback_notifier.dart",
    "lib/features/player/player_provider.dart",
    "lib/core/services/audio_handler.dart",
    "lib/features/home/home_screen.dart",
    "lib/shared/di/providers.dart",
    "lib/features/player/domain/background_playback.dart"
  ],
  "scenarios": ["REF-03-S1", "REF-03-S2", "REF-03-S3", "REF-03-S4", "REF-03-S5", "REF-03-S6", "REF-03-S7", "REF-03-S8"],
  "invariants": ["REF-03-INV1", "REF-03-INV2"],
  "algorithms": [],
  "manual_qa_required": true,
  "user_acceptance_text": "见 §1.2"
}
```
