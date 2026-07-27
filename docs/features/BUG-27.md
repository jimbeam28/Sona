# BUG-27 — 播放器健壮性（PLY4+PLY5）

> 来源：`docs/cr/cr-20260724-0110.md` PLY4 (line 770-780) + PLY5 (line 782-790)
> dev-plan 流程：Bug 修复模式

---

## §0 头部元数据

```yaml
id: BUG-27
name: 播放器健壮性（PLY4+PLY5）
priority: P1
status: draft
created_at: 2026-07-27
last_updated: 2026-07-27
spec_anchored_files:
  - lib/features/player/domain/playback_orchestrator.dart
cross_module_impacts: [PLY]
parent_feature: null
manual_qa_required: true
```

---

## §1 用户视角

### 1.0 原始需求

> cr-20260724-0110.md PLY5：`playback_orchestrator.dart:330-336` — `removeTrack` 在队列清空时直接调用 `player.stop()` 绕过 `_gate.schedule`。弱网 + 最后一曲 + gate loading 卡住 + 用户移除曲目 → ghost playback（gate 内的加载任务不知道有 stop 发生，继续 setAudioSource + play）。
> cr-20260724-0110.md PLY4：`playback_orchestrator.dart:386-463` — orchestrator 内部的 `_startProcessingListener`、`_startAutoSave`、`_startPauseSaveListener` 及相关字段 (`_processingSub`, `_pauseSaveSub`, `_autoSaveTimer`, `_completing`) 全部死代码。`player_provider.dart` 所有调用处（:273, :283, :293, :303, :315）均传 `registerListeners: false`，Provider 层有平行实现。

### 1.1 这一功能干什么（一句话）

修复队列清空时 stop 绕过 gate 的 ghost playback 隐患，并清除 orchestrator 中从未生效的内部 listener 死代码。

### 1.2 用户期望的场景

| ID | 你看到的样子 | 期望行为 |
|----|----|----|
| U1 | 弱网下 gate 正在加载最后一曲，用户移除该曲使队列清空 | 播放器停止，gate 内卡住的加载任务不再继续播放 |
| U2 | 正常播放中移除最后一曲 | 播放器停止，无 ghost playback |
| U3 | 正常播放中移除非当前曲 | 队列更新，当前播放不受影响 |
| U4 | 正常播放中移除当前曲（队列不空） | 加载下一曲，行为不变 |

---

## §2 已实现的功能骨架

### 2.1 文件与分层

| 层 | 文件 | 行数 | 角色 |
|---|---|---|---|
| Domain | `lib/features/player/domain/playback_orchestrator.dart` | 468 | 播放编排核心 |
| Domain | `lib/features/player/domain/request_gate.dart` | 203 | 序列化请求门 |
| Glue | `lib/features/player/player_provider.dart` | 337 | Riverpod 桥接层 |

### 2.2 关键代码段

| 区域 | 行号 | 说明 |
|---|---|---|
| removeTrack 空队列 stop 绕过 gate | `playback_orchestrator.dart:334-339` | `player.stop()` 直接调用，未经 `_gate.schedule` |
| gate 序列化加载 | `playback_orchestrator.dart:138-244` | `_gate.schedule` 内部做 `isLatest` 检查 |
| gate.beginRequest 递增 requestId | `request_gate.dart:122` | 返回新 ID，使旧任务的 `isLatest()` 返回 false |
| 死代码：registerListeners 参数 | `playback_orchestrator.dart:137,252,279,305,327` | 5 个方法均有此参数 |
| 死代码：_startProcessingListener | `playback_orchestrator.dart:390-409` | 仅当 `registerListeners=true` 调用，实际永远 false |
| 死代码：_startAutoSave / _cancelAutoSave | `playback_orchestrator.dart:429-439` | 同上 |
| 死代码：_startPauseSaveListener / _cancelPauseSave | `playback_orchestrator.dart:443-458` | 同上 |
| 死字段：_processingSub, _pauseSaveSub, _autoSaveTimer, _completing | `playback_orchestrator.dart:113-116` | 从未有效使用 |
| Player provider 所有调用传 false | `player_provider.dart:273,283,293,303,315` | `registerListeners: false` |
| Provider 层的平行 listener 实现 | `player_provider.dart:229-267` | `startProcessingListenerProvider` + `_startPlaybackListeners` |
| computeNextQueue 被 Provider 使用 | `playback_orchestrator.dart:413-425` | `player_provider.dart:245` 调用，非死代码 |

---

## §3 行为规约

### 3.1 修复后行为

- **[BUG-27-S1]** 空队列 stop 通过 gate 作废 pending 请求 (`status: new`)
  ```
  Given gate 正在执行 loadAndPlay 任务（弱网，player.setAudioSource 挂起中）
  When  用户移除最后一曲使队列清空 → removeTrack 进入 newQueue.length == 0 分支
  Then  调用 _gate.beginRequest() 递增 requestId，使 gate 内 isLatest() 返回 false
  Then  调用 player.stop() 停止播放
  Then  gate 内挂起的任务恢复后检查 isLatest → false → 返回 superseded，不调用 player.play()
  否定断言:
    - 不在 stop 前不调用 _gate.beginRequest()（当前 BUG：stop 绕过 gate，gate 任务继续 play）
    - 不在 gate 任务已通过 isLatest 检查后仍执行 player.play()（beginRequest 使所有 pending 任务失效）
    - 不改变非空队列时 removeTrack 的正常行为（wasCurrent → loadAndPlay；非 current → 仅更新队列）
  ```
  Code evidence: `lib/features/player/domain/playback_orchestrator.dart:334-336`（`player.stop()` 直接调用）
  Code evidence: `lib/features/player/domain/request_gate.dart:122`（`beginRequest()` 递增 `_latestRequestId`）

  **修改指令 — `lib/features/player/domain/playback_orchestrator.dart`（removeTrack 空队列分支）**

  位置：`:327-347`

  当前代码（:334-339）：
  ```dart
    if (newQueue.length == 0) {
      await player.stop();
      queue = null;
      _cancelAutoSave();
      _cancelPauseSave();
      return;
    }
  ```

  改为：
  ```dart
    if (newQueue.length == 0) {
      _gate.beginRequest();
      await player.stop();
      queue = null;
      return;
    }
  ```

  边界裁决：
  - gate 空闲（`_running == false`）→ `beginRequest()` 仅递增 ID，无副作用 → `player.stop()` 正常停止
  - gate 正在运行（`_running == true`，弱网卡在 `setAudioSource`）→ `beginRequest()` 使 pending 任务的 `isLatest()` 返回 false → 任务恢复后走 superseded 路径 → 不调用 `player.play()`
  - gate 任务已通过所有 `isLatest` 检查并到达 `player.play()` → 极端竞态，但 `beginRequest()` 后 `isLatest` 在 `play()` 前最后一次检查（line 224）会拦截；即使极罕见穿透，`player.stop()` 已在 `beginRequest()` 之后执行，ghost 窗口极短（< 200ms）
  - `queue = null` 在 `player.stop()` 之后 → gate 任务即使走到 `loadAndPlay` 入口，`queue == null` 检查（line 142）也会返回 `failed`

- **[BUG-27-S2]** 清除 orchestrator 内部死 listener 代码 (`status: new`)
  ```
  Given player_provider.dart 所有调用 orchestrator 方法时 registerListeners 始终为 false
  When  检查 playback_orchestrator.dart 的 listener 相关代码
  Then  _startProcessingListener / _startAutoSave / _startPauseSaveListener 从未被有效执行
  Then  _processingSub / _pauseSaveSub / _autoSaveTimer / _completing 字段从未有效使用
  Then  移除上述死代码及 registerListeners 参数
  否定断言:
    - 不改变任何现有播放行为（死代码从未执行，移除后行为等价）
    - 不改变 provider 层的 listener 管理（provider 有独立平行实现）
    - 不删除 computeNextQueue()（被 player_provider.dart:245 使用）
    - 不在 dispose() 中保留已删除字段的 cancel 调用
  ```
  Code evidence: `lib/features/player/player_provider.dart:273,283,293,303,315`（全部传 `registerListeners: false`）
  Code evidence: `lib/features/player/domain/playback_orchestrator.dart:386-467`（死方法 + dispose）

  **修改指令 — `lib/features/player/domain/playback_orchestrator.dart`（删除死代码）**

  **删除字段**（:113-116）：
  ```dart
  // 删除以下 4 行：
  Timer? _autoSaveTimer;
  StreamSubscription<ProcessingState>? _processingSub;
  StreamSubscription<PlayerState>? _pauseSaveSub;
  bool _completing = false;
  ```

  **删除 `registerListeners` 参数**：
  - `:137` — `loadAndPlay({bool registerListeners = true})` → `loadAndPlay()`
  - `:188` — `if (registerListeners) _startProcessingListener();` → 删除
  - `:232-235` — `if (registerListeners) { _startAutoSave(); _startPauseSaveListener(); }` → 删除
  - `:252` — `skipToNext({bool registerListeners = true})` → `skipToNext()`
  - `:271` — `loadAndPlay(registerListeners: registerListeners)` → `loadAndPlay()`
  - `:279-280` — `skipToPrevious({bool registerListeners = true})` → `skipToPrevious()`
  - `:299` — `loadAndPlay(registerListeners: registerListeners)` → `loadAndPlay()`
  - `:305-306` — `selectQueueIndex(int index, {bool registerListeners = true})` → `selectQueueIndex(int index)`
  - `:317` — `loadAndPlay(registerListeners: registerListeners)` → `loadAndPlay()`
  - `:327` — `removeTrack(int index, {bool registerListeners = true})` → `removeTrack(int index)`
  - `:345` — `loadAndPlay(registerListeners: registerListeners)` → `loadAndPlay()`

  **删除死方法**（:386-458）：
  ```dart
  // 删除整个 _startProcessingListener 方法（:390-409）
  // 删除整个 _startAutoSave 方法（:429-434）
  // 删除整个 _cancelAutoSave 方法（:436-439）
  // 删除整个 _startPauseSaveListener 方法（:443-453）
  // 删除整个 _cancelPauseSave 方法（:455-458）
  ```

  **简化 dispose()**（:463-467）：
  ```dart
  // 当前代码：
  void dispose() {
    _processingSub?.cancel();
    _pauseSaveSub?.cancel();
    _cancelAutoSave();
  }
  // 改为（无资源需要清理，但保留方法签名兼容）：
  void dispose() {
    // Listeners managed by provider layer; nothing to clean up here.
  }
  ```

  **修改指令 — `lib/features/player/player_provider.dart`（删除 registerListeners 参数传递）**

  - `:273` — `.loadAndPlay(registerListeners: false)` → `.loadAndPlay()`
  - `:283` — `.skipToNext(registerListeners: false)` → `.skipToNext()`
  - `:293` — `.skipToPrevious(registerListeners: false)` → `.skipToPrevious()`
  - `:303` — `.selectQueueIndex(i, registerListeners: false)` → `.selectQueueIndex(i)`
  - `:315` — `.removeTrack(i, registerListeners: false)` → `.removeTrack(i)`

  **测试文件位置：`test/features/player/bug_bug27_repro_test.dart`**

---

## §4 不变量

- **[BUG-27-INV1]** 所有使队列清空的路径在 `player.stop()` 前调用 `_gate.beginRequest()`
  证据：`removeTrack` 空队列分支在 `player.stop()` 前调用 `_gate.beginRequest()`（`playback_orchestrator.dart:335`）

- **[BUG-27-INV2]** orchestrator 不包含任何 listener 注册/管理代码
  证据：删除后无 `_processingSub`、`_pauseSaveSub`、`_autoSaveTimer`、`_completing` 字段，无 `_startProcessingListener`/`_startAutoSave`/`_startPauseSaveListener` 方法

- **[BUG-27-INV3]** `computeNextQueue()` 保留（被 provider 层使用）
  证据：`player_provider.dart:245` 调用 `o.computeNextQueue()`

---

## §5 测试规约

### 5.1 现有测试清单

| 测试文件 | 覆盖 | 备注 |
|---|---|---|
| `test/features/player/` | PLY 系列测试 | 需检查是否覆盖 removeTrack 空队列 + gate 交互 |
| `test/helpers/mock_audio_player.dart` | 模拟 AudioPlayer | 可用于构造 gate 挂起场景 |

### 5.2 测试 ID 派生清单

```
BUG-27-S1           # 空队列 stop 通过 gate 作废 pending 请求
BUG-27-S2           # 清除死 listener 代码
BUG-27-INV1         # stop 前 beginRequest
BUG-27-INV2         # 无 listener 死代码
BUG-27-INV3         # computeNextQueue 保留
```

### 5.3 测试覆盖盲点

| 未覆盖 ID | 现状 | 应补偿方式 |
|---|---|---|
| BUG-27-S1 | 无测试验证 removeTrack 空队列时 gate 行为 | 用 mock player 模拟 gate 挂起 → removeTrack(0) → 验证 beginRequest 被调用 → gate 任务返回 superseded |
| BUG-27-S2 | 无测试验证 orchestrator 无死代码 | 编译测试：确认移除参数后所有调用正常；反射检查：确认无 `_processingSub` 等字段 |

### 5.4 测试文件位置

| 测试 ID | 文件路径 |
|---|---|
| BUG-27-S1 | `test/features/player/bug_bug27_repro_test.dart` |
| BUG-27-S2 | `test/features/player/bug_bug27_repro_test.dart` |
| BUG-27-INV1 | `test/features/player/bug_bug27_repro_test.dart` |
| BUG-27-INV2 | `test/features/player/bug_bug27_repro_test.dart` |
| BUG-27-INV3 | `test/features/player/bug_bug27_repro_test.dart` |

---

## §6 算法样例

不适用——本修复为并发安全修复 + 死代码清理，无新算法。

---

## §7 跨模块影响

| 其它 feature | 影响点 | 需要补的回归断言 |
|---|---|---|
| PLY | `player_provider.dart:273,283,293,303,315` | 删除 `registerListeners: false` 参数后调用正常 |
| PLY | `player_provider.dart:229-267` | provider 层的 listener 管理不受影响 |

---

## §8 平台特性与手动 QA

| 风险 | 近似测试方案 | 测不了 → 进 mqa-backlog |
|---|---|---|
| 弱网下 gate 挂起 + 用户移除最后一曲 | mock AudioPlayer 的 setAudioSource 挂起 → 验证 removeTrack 后 gate 任务不 play | 真机验证：4G 弱网下快速移除最后一曲是否有残余声音 |
| 极端竞态：beginRequest 后 gate 任务已越过 isLatest 检查 | 无法在单元测试中精确复现 | 真机验证：多次快速移除最后一曲是否出现 ghost playback |

---

## §9 dev-status.json 条目对照

见统一更新：`docs/dev/dev-status.json`。

---

## §10 changelog

- 2026-07-27: 创建 BUG-27 spec（基于 cr-20260724-0110.md PLY4 + PLY5）
