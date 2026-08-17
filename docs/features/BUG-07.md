# BUG-07 — removeTrack(当前曲) 后监听器按 player.playing 条件启动：加载期间暂停则自动切歌/自动保存永久缺失

## §0 头部元数据

```yaml
id: BUG-07
name: removeTrack 后监听器条件启动依赖旧播放状态（playing 判定）
priority: P1
status: active
created_at: 2026-08-16
last_updated: 2026-08-16
spec_anchored_files:
  - lib/features/player/player_provider.dart
  - lib/features/player/domain/playback_orchestrator.dart
cross_module_impacts: [PLY]
parent_feature: Player（音频播放/Player 模块）
manual_qa_required: true        # 涉 P3 真机 playing 状态传播
```

---

## §1 用户视角

### 1.0 原始需求（用户原话逐字记录）

来源：`docs/cr/cr-20260816-0802-player.md` F3（cr 复核已确认仍存在）：

> #### F3. removeTrack(当前曲) 后监听器按 `player.playing` 条件启动：加载期间暂停则自动切歌/自动保存永久缺失
> - 类型：FRAGILE / 严重度：Major / 维度：功能-踩坑（P8 同族）+ 并发时序
> - 证据：
>
> `lib/features/player/player_provider.dart:375-384`：
> ```dart
> await ref.read(playbackOrchestratorProvider).removeTrack(i);
> final player = ref.read(audioPlayerProvider);
> if (player.playing) _startPlaybackListeners(ref);   // ← 条件启动
> ```
> orchestrator 内 `removeTrack` 调 `loadAndPlay()`（`playback_orchestrator.dart:365`）不走 provider 包装，`_startPlaybackListeners` 只能靠这行补救。
> - 复现路径（条件：加载期间播放被打断）：队列 3 曲播第 1 曲 → 队列面板删除当前曲 → 新曲加载期间（首曲加载曾需 12s+，BUG-18 场景）用户点暂停 → 加载成功但 `player.playing` 为 false → 监听器不启动 → 之后恢复播放、曲目结束 → **无自动切歌、无自动保存、无 pause-save**，停在 completed（P2 死锁）。
> - 自检答案：**该分支零覆盖**——`bug_remove_track_progress_test.dart` / `ref_14_test.dart` 全部在 orchestrator 层测 removeTrack，provider 层"playing 判定"逻辑无任何测试。
> - 修复建议：与 loadAndPlayProvider 一致——wasCurrent 删除且加载成功（TrackLoadResult.loaded）即无条件 `_startPlaybackListeners`，不依赖同步读 `player.playing`（P3）。

### 1.1 这一功能干什么（一句话）

删除当前曲目后，只要新曲加载成功（无论播放器此刻是否在播放），播放监听器（自动切歌/自动保存/pause-save）就必须启动——不依赖同步读取 playing 状态（P3）。

### 1.2 用户期望的场景

| ID | 你看到的样子 | 期望行为 |
|----|----|----|
| U1 | 队列 3 首，播第 1 首时在队列面板删除它 | 自动切到第 2 首继续播（不变） |
| U2 | 删除后第 2 首加载很慢，期间点了暂停 | 第 2 首加载完成（暂停态），之后手动恢复播放，**播完仍自动切到第 3 首**（修复前：从此自动切歌永久失效） |
| U3 | 上述暂停场景下播放中途退出/切后台 | 进度照常自动保存（修复前：自动保存与 pause-save 均缺失） |
| U4 | 删除后新曲加载失败 | 不启动监听器，不产生副作用（保持现状） |

---

## §2 已实现的功能骨架（代码锚点）

### 2.1 文件与分层

| 层 | 文件 | 行数 | 角色 |
|---|---|---|---|
| Provider | `lib/features/player/player_provider.dart` | 401 | removeTrackFromQueueProvider（375-384，playing 条件启动缺陷点）；loadAndPlayProvider（341-347，正确参照）；_startPlaybackListeners（332-339） |
| Domain | `lib/features/player/domain/playback_orchestrator.dart` | 479 | removeTrack（339-369）：wasCurrent 分支 saveProgress + loadAndPlay（:357-365，不走 provider 包装） |
| 测试 | `test/features/player/bug_remove_track_progress_test.dart` | — | orchestrator 层 removeTrack 测试（不锚定 provider 层 playing 判定） |
| 测试 | `test/features/player/bug_07_repro_test.dart` | 本 spec §5.4 | 本 Bug 门禁（修复前 FAIL，已用 repro-test.sh fail 确认） |

### 2.2 关键 Provider 表

| Provider 名 | 类型 | 实现位置 | 用途 |
|---|---|---|---|
| removeTrackFromQueueProvider | Provider<Future<void> Function(int)> | player_provider.dart:375-384 | 队列删除入口（队列面板 onRemoveIndex） |
| _startPlaybackListeners | void Function(Ref) | player_provider.dart:332-339 | 加载成功后的监听器三件套（processing/autoSave/pauseSave） |

### 2.3 状态机图

本 Bug 不涉状态机（监听器启动条件修复），跳过。

---

## §3 行为规约（Given-When-Then）

### 3.1 现有行为（逆抽，缺陷态）

- **[BUG-07-S1]** removeTrack(当前曲) 后以同步读 player.playing 决定是否启动监听器（缺陷根源）
  ```
  Given removeTrackFromQueueProvider(i) 执行且 i == 当前曲
  When orchestrator.removeTrack 返回（内部已 loadAndPlay）
  Then if (player.playing) _startPlaybackListeners(ref) —— playing 为 false 则跳过
  ```
  Code evidence: `lib/features/player/player_provider.dart:379-383`（:383 条件启动）。

- **[BUG-07-S2]** orchestrator 内部 removeTrack → loadAndPlay 不走 provider 包装
  ```
  Given 队列面板删除当前曲
  When orchestrator.removeTrack(i) 执行
  Then wasCurrent → saveProgress + queue 重排 + await loadAndPlay()（:357-365）
  And loadAndPlayProvider 的"loaded → _startPlaybackListeners"路径不经过
  ```
  Code evidence: `lib/features/player/domain/playback_orchestrator.dart:357-365`；对照 provider 包装 `player_provider.dart:341-347`。

- **[BUG-07-S3]** 删除非当前曲时不重载、不涉及监听器
  ```
  Given 删除 i != 当前曲
  When orchestrator.removeTrack(i)
  Then queue = newQueue（:367-368），无 loadAndPlay
  ```
  Code evidence: `lib/features/player/domain/playback_orchestrator.dart:366-368`。

### 3.2 修复方案（status: new）

- **[BUG-07-S4]** removeTrack 删除当前曲且新曲加载成功 → 无条件启动监听器（修改点 1） （status: new）
  ```
  Given removeTrackFromQueueProvider(i) 执行且 i == 当前曲
  When orchestrator.removeTrack 返回
  Then 以加载结果判定：加载成功（loaded）→ 无条件 _startPlaybackListeners
       （不读 player.playing；P3）
  And 加载失败/被取代 → 不启动（现状保持）
  否定断言:
    - player.playing == false 不得阻止监听器启动（门禁主断言）
    - 删除非当前曲（无加载）时不得误启动监听器
    - 删除导致队列清空（orchestrator :346-355 stop 路径）时不得启动监听器
  ```
  **修改点**：`lib/features/player/player_provider.dart:375-384` — 把 orchestrator 调用改为获取加载结果并按结果判定：
  ```dart
  final removeTrackFromQueueProvider =
      Provider<Future<void> Function(int)>((ref) => (i) async {
            final q = ref.read(currentPlayQueueProvider);
            if (q == null || i < 0 || i >= q.length) return;
            final wasCurrent = i == q.currentIndex;
            final result = await ref.read(playbackOrchestratorProvider).removeTrack(i);
            // BUG-07（cr-20260816-0802 F3）：wasCurrent 删除 + 加载成功即
            // 无条件启动监听器，不依赖同步读 player.playing（P3：加载期间
            // 暂停/playing 不传播 → 旧条件判定漏启 → 自动切歌/自动保存缺失）。
            if (wasCurrent && result != null && result.isLoaded) {
              _startPlaybackListeners(ref);
            }
          });
  ```
  **orchestrator 返回值改造**：`lib/features/player/domain/playback_orchestrator.dart:339-369` — `removeTrack` 返回类型 `Future<void>` → `Future<TrackLoadResult?>`：
  - `newQueue.length == 0` 分支（:346-355）：`return null;`（清空路径，无加载）
  - `wasCurrent` 分支（:357-365）：`return await loadAndPlay();`（把加载结果回传）
  - 非 current 分支（:366-368）：`return null;`（无加载）
  - 前置校验 `q == null || i < 0 || i >= q.length`（:341）：`return null;`
  **注意**：`TrackLoadResult` 已 import（playback_orchestrator.dart:34 request_gate.dart）。
  **调用方兼容**：既有调用方 `removeTrackFromQueueProvider`（本修改点）忽略返回值改为消费返回值；其它调用方 grep 核实（见 §7 表）——`removeTrack` 的 Future<void> 调用点 await 语义不变（返回 Future<TrackLoadResult?> 仍可 await）。

**边界裁决（弱模型照此实现，无需二次判断）**：

| 边界情况 | 裁决 |
|---|---|
| wasCurrent 删除 + 加载 loaded | 无条件 _startPlaybackListeners（门禁主断言） |
| wasCurrent 删除 + 加载 failed/superseded | 不启动（与 loadAndPlayProvider :344 同判据） |
| 删除非当前曲 | 不启动（无加载） |
| 删除导致队列清空 | 不启动（stop 收尾路径，:346-355） |
| 删除当前曲且播放器此刻正在播（playing==true） | 启动（行为与修复前一致） |
| 删除当前曲、加载期间暂停（playing==false） | 启动（修复目标，P3） |
| 队列为 null / 越界 | provider 前置 return，orchestrator 返回 null，无副作用 |
| 自动保存 Timer 在删除后重复启动 | _startAutoSaveProvider 内部先 cancel 再建（:265）——幂等，无泄漏 |

---

## §4 不变量

- **[BUG-07-INV1]** 播放监听器（processing/autoSave/pauseSave）的启动判据 = "有曲目加载成功"，与 player.playing 无关
  证据：修复后 `player_provider.dart:375-384`（S4 修改点）；对照 `_startPlaybackListeners` 的四个既有调用点（:344/:352/:361/:370）均以 loaded 为判据——本修复使 removeTrack 路径与其对齐。

- **[BUG-07-INV2]** 队列清空（removeTrack 最后一项）时不得启动任何监听器
  证据：`playback_orchestrator.dart:346-355`（stop + queue=null）+ S4 裁决（null 不启动）。

---

## §5 测试规约

### 5.1 现有测试清单

| 测试文件 | 覆盖的 Scenario / INV | 备注 |
|---|---|---|
| test/features/player/bug_remove_track_progress_test.dart | BUG-07-S2 的 orchestrator 层行为 | 不锚定 provider 层 playing 判定（cr 自检答案） |
| test/features/player/ref_14_test.dart | BUG-07-S2/S3（orchestrator removeTrack 三分支） | 返回值改为 TrackLoadResult? 后断言需同步（dev-exe 注意：ref_14 对 removeTrack 的调用点若不读返回值则无需改） |
| test/features/player/bug_07_repro_test.dart | BUG-07-S4 / INV1 / INV2 | 本 Bug 门禁（修复前 FAIL，已用 repro-test.sh fail 确认） |

### 5.2 测试 ID 派生清单（dev-exe 派发测试 Agent 用）

```
BUG-07-S1 … S4        # Scenario（S1~S3 现状锚定，S4 修复目标）
BUG-07-INV1 … INV2    # 不变量
BUG-07-MAN1 …         # 手动 QA 步骤（见 §8）
```

dev-exe 要求：S4/INV1/INV2 由 §5.4 门禁测试覆盖；S1~S3 由门禁测试前置断言与既有 orchestrator 测试锚定。

### 5.3 测试覆盖盲点（dev-plan 写本文档时识别）

| 未覆盖 ID | 现状 | 应补偿方式 |
|---|---|---|
| 清空队列分支（INV2） | 门禁只覆盖 wasCurrent+loaded 与 completed；清空分支由既有 removeTrack orchestrator 测试锚定 | 既有测试全绿即可 |
| BUG-07-MAN1 | 真机暂停时序 | 进 mqa-backlog（§8） |

### 5.4 测试文件位置（spec-scan --gate 硬校验）

| 测试文件 | 覆盖 ID | 说明 |
|---|---|---|
| test/features/player/bug_07_repro_test.dart | BUG-07-S4、BUG-07-INV1、BUG-07-INV2 | 门禁：dev-exe 修复后必须 PASS（repro-test.sh pass） |

---

## §6 算法样例

本 Bug 不涉纯函数算法，跳过。

---

## §7 跨模块影响

`bash cross-imports.sh impact lib/features/player/player_provider.dart lib/features/player/domain/playback_orchestrator.dart`（2026-08-16）→ 引用方：

| 其它 feature | 影响点 | 影响条件 | 需要补的回归断言 |
|---|---|---|---|
| PLY（player_screen.dart:250-252 队列面板 onRemoveIndex） | 调 removeTrackFromQueueProvider（返回值忽略） | 函数签名不变（Future<void>） | ply_14 等队列面板测试全绿 |
| PLY（orchestrator.removeTrack 返回值 Future<void>→Future<TrackLoadResult?>） | 直接调用方：removeTrackFromQueueProvider（改）、测试 ref_14 / bug_remove_track_progress / bug_bug19（INV1-T01） | await 语义兼容（void await 与 TrackLoadResult? await 均可） | ref_14 全绿；bug_remove_track_progress_test 全绿；bug_bug19 全绿 |
| PLY（bug_bug27_repro_test.dart BUG-27-INV1 源码扫描） | 扫描字面量 `Future<void> removeTrack(`（:155）在签名变更后失配 → FAIL | 签名已按本 spec 变更，属**跨模块影响漏识**（2026-08-17 补记） | 扫描字面量同步为 `Future<TrackLoadResult?> removeTrack(`，测试意图（beginRequest 先于 player.stop）不变 |
| PLY（auto-save/pause-save 生命周期） | 监听器启动时机提前/补齐 | 幂等（_startAutoSaveProvider 先 cancel） | bug_19 相关测试全绿 |
| 队列面板 UX（queue_sheet.dart） | 删除后列表不刷新（D3，非本 Bug 范围） | 无 | 不涉及 |

---

## §8 平台特性与手动 QA

设计前已逐条核对 `docs/dev/platform-pitfalls.md`：本 Bug 即 **P3**（playing 状态在 Android 某些场景不传播——不依赖同步读 playing，显式以加载结果触发）的直接处置；**P8** 同族（监听器生命周期归编排层，removeTrack 后必须重连——与"跳过加载快路径必须重连监听器"同构）；**P2** 后果面（监听器缺失 → completed 死锁）在门禁断言。

**真机风险列**（fake 测不到、只有真机会出问题的）：

| 风险 | 近似测试方案 | 测不了 → 进 mqa-backlog |
|---|---|---|
| 删除当前曲 + 加载期间暂停 → 播完不自动切歌 | bug_07_repro_test.dart（playing 恒 false 桩 + completed → 断言进曲） | BUG-07-MAN1：真机 3 曲队列删当前曲，加载期间立刻暂停，等加载完成再点播放，播完必须自动切到下一曲 |
| 暂停场景下进度不自动保存 | 门禁锚定监听器启动（autoSave/pauseSave 随 _startPlaybackListeners） | BUG-07-MAN2：同上场景播 20s 后退出 App，重进期望续播位置正确 |
| 删除后新曲播放中 playing 状态真实传播 | 门禁（loaded 判定不依赖 playing） | BUG-07-MAN3：正常删除当前曲（不暂停），确认自动切歌/保存不受回归 |

涉及真机 P3 时序 → `manual_qa_required = true`。

---

## §9 dev-status.json 条目对照

```json
"BUG-07": {
  "spec_file": "docs/features/BUG-07.md",
  "spec_anchored_files": [
    "lib/features/player/player_provider.dart",
    "lib/features/player/domain/playback_orchestrator.dart"
  ],
  "scenarios": ["BUG-07-S1", "BUG-07-S2", "BUG-07-S3", "BUG-07-S4"],
  "invariants": ["BUG-07-INV1", "BUG-07-INV2"],
  "algorithms": [],
  "manual_qa_required": true,
  "user_acceptance_text": "见 §1.2"
}
```
