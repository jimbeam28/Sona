# BUG-21 — 末曲播完缺 seek(0)，播放器滞留 completed 态（P2 部分合规）

```yaml
id: BUG-21
name: nextIndex==null 分支缺显式 seek(0)，Android completed 态进度条拖动无响应
priority: P2
status: active
created_at: 2026-08-22
last_updated: 2026-08-22
spec_anchored_files:
  - lib/features/player/player_provider.dart
cross_module_impacts: []
parent_feature: Player
manual_qa_required: true
```

---

## §1 用户视角

### 1.0 原始需求（来源逐字记录）

> 来源：docs/cr/cr-20260822-2051.md F2（走查发现，复核确认仍存在）。
>
> "复现路径：单曲队列播完自然结束（completed 态）→ 直接拖动进度条。期望：seek 生效；实际：Android just_audio 在 completed 态忽略 seek（P2 实测行为），滑条冻结，必须先按播放键（且会从头播放）。"
>
> 处置裁决（2026-08-22 cr 复核）：FRAGILE/Minor，用户选定进入 dev-plan Bug 流程第一批。
> P2 规避条款原文："nextIndex == null 分支必须显式 seek(0) + pause()"——现状仅落实 pause()。

### 1.1 一句话

最后一首播完后，不按播放键也能直接拖动进度条回看。

### 1.2 用户期望的场景

| ID | 你看到的样子 | 期望行为 |
|----|----|----|
| U1 | 一章听完（或单曲播完），想拖回去重听中间某段 | 直接拖进度条就到位，不需要先点一下播放从头开始 |
| U2 | 末曲播完后的播放按钮 | 行为不变：点了仍从零开始播 |

---

## §2 已实现骨架（逆抽锚点）

| 层 | 文件 | 角色 |
|---|---|---|
| Provider | lib/features/player/player_provider.dart | :316-335 completed 监听器；nq==null 分支 :327-331 仅调用 player.pause()，无 seek(0)（缺陷点）；守卫复位三分支齐全（P1 合规） |
| 平台恢复路径 | lib/core/services/audio_handler.dart | :275-281 通知栏 play() 已有 completed→seek(0) 恢复（不受本 Bug 影响） |
| UI 恢复路径 | widgets/playback_controls.dart:76-79、widgets/mini_player_bar.dart:229-232 | 播放按钮已有 seek(0)+play 恢复（不受影响） |
| 门禁测试 | test/features/player/bug_bug21_completed_seek_test.dart | 容器级驱动 completed 监听器，修复前 FAIL |

---

## §3 行为规约

### 3.1 现状锚定（逆抽）

- **[BUG-21-S0]** 无下一曲时末曲结束的处理：guard 置位 → computeNextQueue 返回 null → 显式 pause → guard 复位
  Code evidence: `lib/features/player/player_provider.dart:327-331`

### 3.2 修复目标

- **[BUG-21-S1]** 无下一曲的 completed 处理必须先 seek(Duration.zero) 再 pause （`status: new`）
  ```
  Given 单曲队列或队列末曲，processingStateStream 发出 completed
  When 监听器处理该事件且 computeNextQueue()==null
  Then 先调用 player.seek(Duration.zero) 使播放器退出 completed 态，
       随后调用 player.pause()（既有顺序不变：seek 在 pause 之前）
  否定断言:
    - 队列状态不得变化（currentPlayQueueProvider 保持同一对象）
    - 不触发 setAudioSource / play（不得重新加载）
    - _completingProvider 守卫照常复位（内联复位分支保留）
    - 有下一曲 / afterCurrent 定时器两条既有分支的行为不得变化
  ```
  Code evidence: 修改点 `lib/features/player/player_provider.dart:327-331`
- **[BUG-21-S2]** completed 处理不推进队列、不触发加载（否定面锚定，现状已合规）
  ```
  Given 同 S1
  When completed 事件处理完成
  Then 无任何加载请求进入 SerializedRequestGate
  ```

---

## §4 不变量

- **[BUG-21-INV1]** P2 三项规避措施完整在位：nq==null 分支 seek(0)+pause ✓、UI/通知栏三处"先 seek(0) 再 play"恢复路径 ✓、末曲结束显式 pause ✓
  证据：player_provider.dart:327-331（修复后）、playback_controls.dart:76-79、mini_player_bar.dart:229-232、audio_handler.dart:275-281

---

## §5 测试规约

### 5.1 现有测试清单

| 测试文件 | 覆盖 | 备注 |
|---|---|---|
| test/features/player/ply_06_test.dart 等 | completed 自动切歌（有下一曲分支） | 不得回归 |
| test/features/player/ply_05_test.dart TST-T02/TST-T142 | 队尾停止分支（即本 Bug 修改点） | **dev-exe round-1 补登记（2026-08-23）**：两用例原以 `verifyNever(seek(Duration.zero))` 锚定旧行为，与 S1 新契约直接冲突；已按新契约机械更新为 `verify(seek(0)).called(1)`，其余断言（saveProgress/loadAndPlay 不触发、队列不变）逐字保留。属 §7 跨模块影响漏识 |

### 5.2 测试 ID 派生清单

```
BUG-21-S1, BUG-21-S2, BUG-21-INV1
```

### 5.3 测试覆盖盲点

| 未覆盖 ID | 现状 | 应补偿方式 |
|---|---|---|
| 无 | S1/S2 由门禁文件覆盖；INV1 的三处 UI 路径为既有 ply 用例锚定 | — |

### 5.4 门禁测试文件（spec-scan --gate 硬校验）

| 测试文件 | 覆盖 ID | 说明 |
|---|---|---|
| test/features/player/bug_bug21_completed_seek_test.dart | BUG-21-S1、BUG-21-S2 | 修复前 FAIL 已由 repro-test.sh fail 确认（2026-08-22）；修复后必须 PASS。文件名带描述后缀避开既有 bug_bug21_repro_test.dart（SCHEMA §1.3） |

---

## §6 算法样例

不涉及纯函数算法，跳过。

---

## §7 跨模块影响

impact 反查（2026-08-22）：player_provider.dart ← main.dart、app/onboarding.dart。

| 其它 feature | 影响点 | 影响条件 | 回归断言要求 |
|---|---|---|---|
| HOME | mini 栏进度条显示位置 | seek(0) 后 position 归零即正常表现 | ply/home 既有测试全绿 |
| TMR | afterCurrent 分支在 S1 之前 return，不经修改点 | 无交集 | timer 既有测试全绿 |
| PLY（round-1 补登记 2026-08-23） | ply_05_test.dart TST-T02/TST-T142 锚定队尾停止旧行为 | seek(0) 引入后 `verifyNever` 失效 | 两断言机械更新为 `verify(seek(0)).called(1)`；其余 ply_05 断言不变、全绿 |

**修改点（弱模型照单执行）**：
1. `lib/features/player/player_provider.dart` nq==null 分支（现 :327-331）改为：
   ```dart
   if (nq == null) {
     // P2: Android completed 态忽略后续 seek/play —— 必须显式 seek(0) 退出该态
     unawaited(player.seek(Duration.zero));
     player.pause();
     ref.read(_completingProvider.notifier).state = false;
     return;
   }
   ```
   即在 `player.pause();` 之前插入一行 `unawaited(player.seek(Duration.zero));`，其余行不动。dart:async 已 import（player_provider.dart:5）。unawaited+超时兜底模式与 loadAndPlay 内 :209 一致（seek 的平台层 5s 超时由 AudioPlayerAdapter 提供，audio_player_adapter.dart:64-88，P17 分层表）。
2. 全量回归：`flutter analyze --no-fatal-infos` 0 warning + `flutter test` 全绿。

---

## §8 平台特性与手动 QA

核对踩坑库：P2 直接相关（本 Bug 即其第一项规避措施的缺失部分）；P4/P17 无新增风险（复用既有超时分层）。

| 风险 | 近似测试 | 测不了 → mqa-backlog |
|---|---|---|
| 真机 Android：末曲播完后直接拖进度条应立即生效 | 门禁断言 seek(0) 被调用的行为等价性 | BUG-21-MAN1：真机单曲播完→不按播放→拖进度条→松手后位置生效且可暂停 |

涉及真机 completed 态平台行为 → manual_qa_required = true。

---

## §9 dev-status.json 条目对照

```json
"BUG-21": {
  "spec_file": "docs/features/BUG-21.md",
  "spec_anchored_files": [
    "lib/features/player/player_provider.dart"
  ],
  "scenarios": ["BUG-21-S1", "BUG-21-S2"],
  "invariants": ["BUG-21-INV1"],
  "algorithms": [],
  "manual_qa_required": true,
  "user_acceptance_text": "见 §1.2"
}
```
