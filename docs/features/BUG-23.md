# BUG-23 — loadAndPlay 内层超时兜底 stop 无时效守卫，可打断后继请求

```yaml
id: BUG-23
name: loadAndPlay 30s 兜底 stop 缺 isLatest 守卫（可停掉后继请求的加载现场）
priority: P2
status: active
created_at: 2026-08-23
last_updated: 2026-08-23
spec_anchored_files:
  - lib/features/player/domain/playback_orchestrator.dart
cross_module_impacts:
  - lib/features/player/player_provider.dart
parent_feature: Player
manual_qa_required: false
```

---

## §1 用户视角

### 1.0 原始需求（来源逐字记录）

> 来源：docs/cr/cr-20260823-1421.md F1（走查发现，复核确认仍存在，2026-08-23 分流）。
>
> "内层 30s completer 超时后直接 `await player.stop()`，**无 `_gate.isLatest(requestId)` 时效守卫**。gate 20s 超时释放后任务仍在跑，若用户重试触发新请求 B，旧任务 A 在自身 30s 截止处的 stop() 会打断 B 的加载现场。对照同文件 removeTrack BUG-27-S1 确立的约定：'stop 前必须 beginRequest 使 in-flight 任务失效'。"
> 自检答案："bug_18_stream_wait_test 仅断言单请求序列，无'超时任务与新请求交错'用例 → 该分支零覆盖。"
> 复核裁决（2026-08-23）：FRAGILE/Major → dev-plan Bug 流程；TEST-GAP T2（并发交错门禁）并入本规格。

### 1.1 一句话

弱网下第一次加载卡住、用户重试之后，旧加载任务的"30 秒收尾"不允许把用户新点的歌停掉。

### 1.2 用户期望的场景

| ID | 你看到的样子 | 期望行为 |
|----|----|----|
| U1 | 第一首歌一直"正在加载"，20 秒后提示超时，用户点了重试 | 重试的歌正常加载播放，不被旧任务干扰 |
| U2 | 上述过程中后台旧任务到达自己的 30 秒期限 | 它静默退场（superseded），不发出任何停止/暂停动作 |

---

## §2 已实现骨架（逆抽锚点）

| 层 | 文件 | 角色 |
|---|---|---|
| Domain | lib/features/player/domain/request_gate.dart:125-177 | schedule/_start：20s gate 超时先结束请求（rc 抛给调用方），任务体在后台继续跑（P17 外层语义） |
| Domain | lib/features/player/domain/playback_orchestrator.dart:210-235 | loadAndPlay play-wait：playing=false 时挂 completer 等 playerStateStream，`.timeout(30s)`；成功路径 :233-235 有 isLatest 守卫，**失败路径 :229-231 无守卫直接 `await player.stop()`**（缺陷点） |
| Domain | lib/features/player/domain/playback_orchestrator.dart:354-363 | removeTrack BUG-27-S1 先例：自身 stop 前先 `_gate.beginRequest()` 使 in-flight 任务失效——本 Bug 即该约定未覆盖到兜底路径 |
| 门禁测试 | test/features/player/bug_bug23_timeout_stop_guard_test.dart | fakeAsync 驱动 A/B 两请求交错，修复前 FAIL（repro-test.sh fail 确认 2026-08-23） |

---

## §3 行为规约

### 3.1 现状锚定（逆抽）

- **[BUG-23-S0]** 成功路径时效守卫：play-wait 成功完成后 `!_gate.isLatest(requestId)` → 返回 superseded、无副作用
  Code evidence: `lib/features/player/domain/playback_orchestrator.dart:233-235`
- **[BUG-23-S0b]** P17 分层语义保留：gate 对 task 整体 `.timeout(20s)`，外层到期先把 TimeoutException 抛给调用方，内层等待继续负责收尾
  Code evidence: `lib/features/player/domain/request_gate.dart:152-159`

### 3.2 修复目标

- **[BUG-23-S1]** 被取代的超时任务不得对共享 player 做破坏性收尾（`status: new`）
  ```
  Given 请求 A 挂在 play-wait 且其 gate 已于 20s 到期释放
    And 请求 B 已成为 latest 并进入/完成自身加载
  When A 的内层 30s completer 超时（playStarted == false）
  Then 不调用 player.stop()，A 直接以 superseded 语义退场（公开 future 早已抛 TimeoutException，此处仅内部收尾）
       且 B 的 source 与后续 loaded 结果不受影响
  否定断言:
    - 整个交错窗口内 player.stop() 零调用
    - B 的 TrackLoadResult 仍为 loaded（不被降级 failed/superseded）
    - 不改变外层 gate 20s 抛 TimeoutException 的既有语义（BUG-18-INV2）
  ```
  Code evidence: 修改点 `lib/features/player/domain/playback_orchestrator.dart:229-231`
- **[BUG-23-S2]** 单请求场景行为零变更（回归锚定）：无新请求时 30s 兜底仍 stop 收尾并返回 failed
  Code evidence: `test/features/player/bug_18_stream_wait_test.dart:117`（既有断言保持全绿）

---

## §4 不变量

- **[BUG-23-INV1]** 共享 AudioPlayer 的任何 stop/seek/setAudioSource 收尾动作，执行前必须确认自己仍是 gate 的 latest 请求（或由调用方先行 beginRequest 失效他者）；对照 removeTrack :354-363 同款纪律
  证据：playback_orchestrator.dart:229-235（修改点）与 :354-363（先例）

---

## §5 测试规约

### 5.1 现有测试清单

| 测试文件 | 覆盖 | 备注 |
|---|---|---|
| test/features/player/bug_18_stream_wait_test.dart | 分层超时单请求序列 | 全绿即可（S2 回归） |

### 5.2 测试 ID 派生清单

```
BUG-23-S1, BUG-23-S2, BUG-23-INV1（S2 由既有 bug_18 门禁承担）
```

### 5.3 测试覆盖盲点

真机上 stop() 对 in-flight setAudioSource 的具体平台行为（中断 vs 完成后 idle）无法在本机验证——见 §8。

### 5.4 门禁测试文件（spec-scan --gate 硬校验）

| 测试文件 | 覆盖 ID | 说明 |
|---|---|---|
| test/features/player/bug_bug23_timeout_stop_guard_test.dart | BUG-23-S1 | 修复前 FAIL 已由 repro-test.sh fail 确认（2026-08-23）；修复后必须 PASS |

---

## §6 算法样例

不涉及纯函数算法，跳过。

---

## §7 跨模块影响

impact 反查（2026-08-23）：playback_orchestrator ← player_provider（唯一生产装配点）。

| 其它模块 | 影响点 | 影响条件 | 回归断言要求 |
|---|---|---|---|
| player provider 层 | _runLoadOrchestrated / completed 监听器消费 TrackLoadResult | A 公开 future 仍抛 TimeoutException（不变） | bug_18 既有断言全绿 |
| player UI | PlayerScreen._runSerializedLoad 15s UI 超时文案 | 无变化 | ply 既有测试全绿 |

**修改点（弱模型照单执行）**：
1. `lib/features/player/domain/playback_orchestrator.dart` loadAndPlay 内层超时分支（现 :229-231）改为：
   ```dart
   if (!playStarted) {
     // BUG-23: 被取代的任务不得停掉后继请求的加载现场
     // （removeTrack BUG-27-S1 同款时效纪律）。
     if (!_gate.isLatest(requestId)) {
       return const TrackLoadResult.superseded();
     }
     await player.stop();
     return const TrackLoadResult.failed();
   }
   ```
2. 全量回归：`bash ../../scripts/cov-gate.sh --skip-test` 0 warning + `flutter test` 全绿。

---

## §8 平台特性与手动 QA

核对踩坑库：P17 直接相关（超时分层——本修复不改任何数值，仅补收尾时效判定）；P14 相关（绕门/并发加载危害类）。其余条款无交集。

真机风险列（fake 测不到）：just_audio 在 setAudioSource 进行中收到 stop() 的实际平台行为（Android ExoPlayer 中断语义）未验证。本修复使该场景不再发生，无需 MQA；若未来改动加载链路需回归首曲加载耗时（P7）。

---

## §9 dev-status.json 条目对照

```json
"BUG-23": {
  "spec_file": "docs/features/BUG-23.md",
  "spec_anchored_files": ["lib/features/player/domain/playback_orchestrator.dart"],
  "scenarios": ["BUG-23-S1", "BUG-23-S2"],
  "invariants": ["BUG-23-INV1"],
  "algorithms": [],
  "manual_qa_required": false,
  "user_acceptance_text": "见 §1.2"
}
```
