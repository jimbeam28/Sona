# BUG-01 — PlayQueue == / hashCode 漏比 shuffle 字段

> 来源：`docs/cr/cr-2026-06-28.md` 第 2.1 BUG-01 / §9.1 B1
> dev-plan 流程：Bug 修复模式（已先写复现测试并确认 FAIL）

---

## §0 头部元数据

```yaml
id: BUG-01
name: PlayQueue == / hashCode 漏比 shuffle 字段
priority: P0
status: active
created_at: 2026-06-28
last_updated: 2026-06-28
spec_anchored_files:
  - lib/shared/models/play_queue.dart
cross_module_impacts: [PLY, PRG]
parent_feature: null  # 跨模块 bug：锚点为共享模型 PlayQueue，影响 PLY + PRG + BRW-09，无单一归属
manual_qa_required: false
```

---

## §1 用户视角（你来扫这一节就够）

### 1.1 这一功能干什么（一句话）

修一个导致 shuffle 模式下切换播放顺序后**界面元素不更新**的缺陷。

### 1.2 用户期望的场景

| ID | 你看到的样子 | 期望行为 |
|----|----|----|
| U1 | 在随机播放模式下，用"下一曲"切换几次曲目，队列面板应跟随刷新显示当前正在播的曲目 | 切歌后队列面板高亮应实时切换到当前曲目；不刷新即违反 |
| U2 | 同样 shuffle 模式下，外部对 `currentPlayQueueProvider` 写入一个已调换 shuffle 顺序的新队列实例，应触发依赖者重建 | 任何对 shuffle 序列 / 当前 shuffle 位置的变更都应触发 UI 重建；若被 == 视为相等 UI 不变 |

---

## §2 已实现的功能骨架（代码锚点）

### 2.1 文件与分层

| 层 | 文件 | 行数 | 角色 |
|---|---|---|---|
| Shared Model | `lib/shared/models/play_queue.dart` | 309 | PlayQueue 值对象 + shuffle 排列 + 导航 + 持久化 |
| 测试 | `test/features/player/ply_05_test.dart` | 1325 | PLY-05 既有覆盖（57 测试，未含 == shuffle） |
| 测试 | `test/features/player/bug_bug01_repro_test.dart` | — | 本 bug 复现测试（FAIL 状态） |

### 2.2 关键 Provider 表

| Provider 名 | 类型 | 实现位置 | 用途 |
|---|---|---|---|
| `currentPlayQueueProvider` | `StateProvider<PlayQueue?>` | `lib/features/browser/browser_provider.dart:100` | 全 app 唯一 PlayQueue 实例，依赖 `==` 判定 state 是否变化以决定 listener 通知 |

### 2.3 状态机图

N/A — 纯值对象缺陷。

---

## §3 行为规约（Given-When-Then）

### 3.1 现有行为（BUG 行为，修复目标）

- **[BUG-01-S1]** shuffle 序列不同的两个 PlayQueue 被判为相等
  ```
  Given files / currentIndex / startPositionMs / playMode 均相同
    And 两个 PlayQueue 的 shuffleOrder 列表不同
  When  比较 q1 == q2
  Then  当前实现返回 true（BUG：应返回 false）
  否定断言: 无（这是 BUG 行为）
  ```
  Code evidence: `lib/shared/models/play_queue.dart:288-294`

- **[BUG-01-S2]** shufflePosition 不同也被判为相等
  ```
  Given shuffleOrder 列表相同
    And shufflePosition 取不同值
  When  比较 q1 == q2
  Then  当前实现返回 true（BUG：应返回 false）
  ```
  Code evidence: `lib/shared/models/play_queue.dart:288-294`

- **[BUG-01-S3]** hashCode 也漏纳入 shuffle 字段
  ```
  Given shuffle 序列不同的两个 PlayQueue
  When  对比 q1.hashCode == q2.hashCode
  Then  返回 true（BUG：应返回 false）
  ```
  Code evidence: `lib/shared/models/play_queue.dart:297-298`

### 3.2 修复后行为（新增，dev-exe 须实现）

- **[BUG-01-S4]** shuffle 字段纳入 == 比对 (status: new)
  ```
  Given files / currentIndex / startPositionMs / playMode 均相同
    And 任一 shuffleOrder / shufflePosition 字段不同
  When  比较 q1 == q2
  Then  返回 false
  否定断言:
    - 不漏比对 _shuffleOrder（须出现在 == 与 hashCode 中）
    - 不漏比对 _shufflePosition（须出现在 == 与 hashCode 中）
    - shuffleOrder 与 shufflePosition 同为 null（非 shuffle 模式）时不受影响，仍按其它字段相等返回 true
  ```
  Code evidence: `lib/shared/models/play_queue.dart:288-298`（修复位置）

- **[BUG-01-S5]** shuffle 字段进入 hashCode (status: new)
  ```
  Given q1 与 q2 仅 shuffle 序列 / position 不同
  When  对比 hashCode
  Then  返回不同值
  否定断言:
    - hashCode 不重用未纳入 shuffle 字段的旧实现，避免 Set/Map 去重碰撞回归
  ```
  Code evidence: `lib/shared/models/play_queue.dart:297-298`

- **[BUG-01-S6]** 非 shuffle 模式回归不变 (status: new)
  ```
  Given playMode != shuffle
    And shuffleOrder 与 shufflePosition 同为 null
  When  按 §3.1 路径比较两个 PlayQueue
  Then  与历史行为一致（仅 files/currentIndex/startPositionMs/playMode 决定相等）
  否定断言:
    - 不引入新不等比较 → 既有 PLY-05 测试不应回归失败
    - 不修改 shuffle 字段为 null 时的 toMap / fromMap 行为
  ```
  Code evidence: `lib/shared/models/play_queue.dart:54-62`（构造时 shuffle 字段为 null 的语义）

---

## §4 不变量

- **[BUG-01-INV1]** `==` 必须比较所有 final 字段
  证据：`lib/shared/models/play_queue.dart:38-43`（_shuffleOrder / _shufflePosition 是 final 字段）

- **[BUG-01-INV2]** hashCode 必须与 == 同步覆盖所有 final 字段
  证据：`lib/shared/models/play_queue.dart:297-298`

- **[BUG-01-INV3]** 非空 shuffle 字段相同时视为 shuffle 状态相同
  证据：`lib/shared/models/play_queue.dart:184-214`（advanceShuffle/retreatShuffle 通过字段定位）

---

## §5 测试规约

### 5.1 现有测试清单

| 测试文件 | 覆盖的 Scenario / INV | 备注 |
|---|---|---|
| `test/features/player/ply_05_test.dart` | 非 shuffle 等价类、shuffle 排列生成、roundtrip | 57 测试，未覆盖 == 的 shuffle 比较 |
| `test/features/player/bug_bug01_repro_test.dart` | BUG-01-S1/S2/S3 | 复现测试，FAIL 状态 |

### 5.2 测试 ID 派生清单

```
BUG-01-S1 S2 S3        # 现有 BUG 行为，修复后应 PASS
BUG-01-S4 S5 S6        # 修复后行为新增断言
BUG-01-INV1 INV2 INV3  # 不变量断言
```

### 5.3 测试覆盖盲点

| 未覆盖 ID | 现状 | 应补偿方式 |
|---|---|---|
| BUG-01-S4 | 复现测试同路径可补 | 修复后 `expect(q1 == q2, isFalse)` 须 PASS |
| BUG-01-S5 | 复现测试同路径可补 | 修复后 `expect(q1.hashCode == q2.hashCode, isFalse)` 须 PASS |
| BUG-01-S6 | 无 | 在 ply_05 既有非 shuffle 等价用例上加一条 shuffle 字段为 null 的相等 才路径回归 |
| BUG-01-INV1/2 | 无 | 在 ply_05 加一组"_shuffleOrder / _shufflePosition 演化全部进入 ==" 综合断言 |
| BUG-01-INV3 | 无 | 补 `advanceShuffle` 后 == 判不同 的端到端断言 |

---

## §6 算法样例

```
ALG PlayQueue.== / hashCode 字段:
  输入: q1.shuffleOrder != q2.shuffleOrder                  → 期望: == false, hashCode != 
  输入: q1.shufflePosition != q2.shufflePosition               → 期望: == false, hashCode !=
  输入: q1.shuffleOrder == q2.shuffleOrder == null (non-shuffle) → 期望: == 按 files/currentIndex/... 判
  输入: q1.files == q2.files && 所有字段相等                     → 期望: == true, hashCode 相等
```

---

## §7 跨模块影响

| 其它 feature | 影响点 | 影响条件 | 需要补的回归断言 |
|---|---|---|---|
| PLY | `player_provider.dart:111-113` `ref.listen(currentPlayQueueProvider)` 依赖 `==` 触发同步 | 任何写入 shuffle 变化的场景 | 切 shuffle 序列后 `o.queue` 应同步到 orchestrator |
| PRG | 持久化 `persistQueueOnChangeProvider` 依赖 ref.listen 比较 | 队列 shuffle 变化时是否仍正确写 prefs（不应重复写或不写） | `toMap` 已纳入 shuffle 字段（play_queue.dart:247-254）；新增 == 后须确认 persist 不短路 |
| BRW-09 | 未来 `insertAfterCurrent` 不操作 shuffle 字段 | 由 BUG-01 修复后才能安全依赖 `==` 检测队列改变 | BRW-09 spec 已经列此依赖 |

---

## §8 平台特性与手动 QA

本功能不涉及平台原生特性，全部可在 `flutter test` 中验证，无需手动 QA。

---

## §9 dev-status.json 条目对照

见统一更新：`docs/dev/dev-status.json`。

---

## §10 changelog

- 2026-06-28: 创建 BUG-01 spec（基于 cr.md B1 + 复现测试已写且 FAIL） (status: new)
- 2026-07-05: §0 加 `parent_feature: null` 字段（配合 _TEMPLATE.md 新字段 + dev-plan hybrid bug fold 策略；BUG-01 锚点为共享模型，跨模块无单一归属）