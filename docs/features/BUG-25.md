# BUG-25 — 队列可含重复曲目而 QueueSheet 以 path 作键，重复即键冲突

```yaml
id: BUG-25
name: QueueSheet ValueKey(file.path) 与 insertAfterCurrent 允许重复曲目冲突
priority: P3
status: active
created_at: 2026-08-23
last_updated: 2026-08-23
spec_anchored_files:
  - lib/features/player/widgets/queue_sheet.dart
cross_module_impacts:
  - lib/features/player/player_screen.dart
  - lib/features/player/widgets/mini_player_bar.dart
parent_feature: Player
manual_qa_required: false
```

---

## §1 用户视角

### 1.0 原始需求（来源逐字记录）

> 来源：docs/cr/cr-20260823-1421.md F3（走查发现，复核确认仍存在，2026-08-23 分流）。
>
> "insertAfterCurrent 明确允许队列持有重复 path（play_queue.dart:226-227 'No de-duplication is performed'），而 QueueSheet 以 ValueKey(file.path) 作为同层列表键（queue_sheet.dart:56）→ 队列含重复曲目时打开面板，debug 构建抛 duplicate-key 断言、release 构建元素匹配错乱。复现（3 步）：播放曲目 A → 浏览器对同一 A 点'加入下一曲' → 打开队列面板。"
> 自检答案："ref_05_queue_sheet_live_test 等用例曲目 path 均互异；模型层已承认重复元素合法（play_queue_insert_test.dart:249），UI 层无对应渲染用例。"
> 复核裁决（2026-08-23）：FRAGILE/Major → dev-plan Bug 流程；TEST-GAP T3 并入本规格。

### 1.1 一句话

把同一首歌"加入下一曲"之后再打开播放队列，列表必须正常显示所有条目——不能因为路径相同就崩溃或显示错乱。

### 1.2 用户期望的场景

| ID | 你看到的样子 | 期望行为 |
|----|----|----|
| U1 | 队列里有重复的同一首歌，打开队列面板 | 面板正常打开，每个条目各占一行 |
| U2 | 删除其中一行重复曲目 | 只删被点的那一行，另一行保留 |

---

## §2 已实现骨架（逆抽锚点）

| 层 | 文件 | 角色 |
|---|---|---|
| Model | lib/shared/models/play_queue.dart:226-227 | insertAfterCurrent 文档明示不去重——重复 path 是合法模型状态 |
| UI | lib/features/player/widgets/queue_sheet.dart:50-56 | ListView.builder + `ValueKey(file.path)`（缺陷点） |
| 入口 | lib/features/browser/browser_screen.dart:95-105 | onPlayNext → insertAfterCurrentProvider，不排除与当前曲相同文件 |
| 对照 | lib/features/playlist/playlist_detail_screen.dart:167 | 曲目列表以 ValueKey(track.id)（DB 主键唯一）；path 作键仅 queue_sheet 一处 |
| 门禁测试 | test/features/player/bug_bug25_queue_sheet_dup_key_test.dart | 含重复 path 的队列 pump QueueSheet，修复前 FAIL（repro-test.sh fail 确认 2026-08-23） |

---

## §3 行为规约

### 3.1 现状锚定（逆抽）

- **[BUG-25-S0]** QueueSheet 渲染契约（REF-05）：watch currentPlayQueueProvider 实时数据、空态文本、isCurrent 标记、onSelectIndex/onRemoveIndex 回调、越界由 orchestrator 兜底
  Code evidence: `lib/features/player/widgets/queue_sheet.dart:27-119`

### 3.2 修复目标

- **[BUG-25-S1]** 含重复 path 的队列必须可完整渲染且删除按位置命中（`status: new`）
  ```
  Given 队列 files 含两条及以上相同 path 的条目（insertAfterCurrent 合法产物）
  When 打开 QueueSheet
  Then 全部条目各渲染一行，无 duplicate-key 异常
       且删除第 N 行只移除该位置条目（removeTrackFromQueueProvider 按索引语义不变）
  否定断言:
    - 不改变 insertAfterCurrent 的不去重语义（play_queue.dart:226-227 保持）
    - 不改变 removeTrackFromQueueProvider / orchestrator.removeTrack 的按索引删除契约
    - 不给 PlayQueue 引入去重逻辑
  ```
  Code evidence: 修改点 `lib/features/player/widgets/queue_sheet.dart:56`

---

## §4 不变量

- **[BUG-25-INV1]** 同层列表键在其父列表生命周期内必须唯一：凡数据源允许重复业务 ID 的列表，键必须复合位置信息
  证据：queue_sheet.dart:56（修改点）对照 playlist_detail_screen.dart:167（主键唯一场景）

---

## §5 测试规约

### 5.1 现有测试清单

| 测试文件 | 覆盖 | 备注 |
|---|---|---|
| test/features/player/ref_05_queue_sheet_live_test.dart | live 数据源/空态/当前标记 | 全绿即可 |

### 5.2 测试 ID 派生清单

```
BUG-25-S1, BUG-25-INV1
```

### 5.3 测试覆盖盲点

release 构建下 duplicate key 的具体错配表现不可单测——以 debug 断言为门禁信号。

### 5.4 门禁测试文件（spec-scan --gate 硬校验）

| 测试文件 | 覆盖 ID | 说明 |
|---|---|---|
| test/features/player/bug_bug25_queue_sheet_dup_key_test.dart | BUG-25-S1 | 修复前 FAIL 已由 repro-test.sh fail 确认（2026-08-23）；修复后必须 PASS |

---

## §6 算法样例

不涉及纯函数算法，跳过。

---

## §7 跨模块影响

impact 反查（2026-08-23）：queue_sheet ← player_screen（onSelectIndex/onRemoveIndex 装配）、mini_player_bar（同）。

| 其它模块 | 影响点 | 影响条件 | 回归断言要求 |
|---|---|---|---|
| player_screen | _showQueueSheet 回调传 index | 键变化不影响回调参数（仍是 index） | ply/ref_05 既有测试全绿 |
| mini_player_bar | _showQueueSheet 同上 | 同上 | ref_05 全绿 |

**修改点（弱模型照单执行）**：
1. `lib/features/player/widgets/queue_sheet.dart` :56 的 `key: ValueKey(file.path)` 改为：
   ```dart
   key: ValueKey('$index:${file.path}'),
   ```
2. 全量回归：cov-gate --skip-test + flutter test 全绿（重点 ref_05_queue_sheet_live_test）。

---

## §8 平台特性与手动 QA

核对踩坑库：P13 直接相关（列表项 Key 与 async gap 重建——本修复强化键唯一性，手势/选中态纪律不变）。纯 widget 层改动，flutter test 可验证，manual_qa_required=false。

---

## §9 dev-status.json 条目对照

```json
"BUG-25": {
  "spec_file": "docs/features/BUG-25.md",
  "spec_anchored_files": ["lib/features/player/widgets/queue_sheet.dart"],
  "scenarios": ["BUG-25-S1"],
  "invariants": ["BUG-25-INV1"],
  "algorithms": [],
  "manual_qa_required": false,
  "user_acceptance_text": "见 §1.2"
}
```
