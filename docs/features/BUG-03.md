# BUG-03 — TimerService.resume() 用 ceil() 转分钟精度损失

> 来源：`docs/cr/cr-2026-06-28.md` 第 2.6 BUG-03 / §9.1 B3
> dev-plan 流程：Bug 修复模式（已先写复现测试并确认 FAIL）

---

## §0 头部元数据

```yaml
id: BUG-03
name: TimerService.resume() 用 ceil() 转分钟精度损失
priority: P0
status: active
created_at: 2026-06-28
last_updated: 2026-06-28
spec_anchored_files:
  - lib/features/timer/domain/timer_service.dart
cross_module_impacts: [PRG]
manual_qa_required: false
```

---

## §1 用户视角（你来扫这一节就够）

### 1.1 这一功能干什么（一句话）

修一个定时器每次暂停/恢复后会**多出最多 30-59 秒**的缺陷。

### 1.2 用户期望的场景

| ID | 你看到的样子 | 期望行为 |
|----|----|----|
| U1 | 设置 1 分钟定时器，30 秒时点暂停后再点恢复 | 剩余 30 秒应继续按时倒计时 |
| U2 | 多次点暂停/恢复 | 倒计时不应越累越多 |

---

## §2 已实现的功能骨架（代码锚点）

### 2.1 文件与分层

| 层 | 文件 | 行数 | 角色 |
|---|---|---|---|
| Domain | `lib/features/timer/domain/timer_service.dart` | 276 | 纯 Dart 定时器状态机 |
| 测试 | `test/features/timer/timer_test.dart` | 1136 | TST 测试套件，含 pause/resume |
| 测试 | `test/features/timer/bug_bug03_repro_test.dart` | — | 本 bug 复现测试（FAIL 状态） |

### 2.2 关键 Provider 表

| Provider 名 | 类型 | 实现位置 | 用途 |
|---|---|---|---|
| `timerServiceProvider` | `Provider<TimerService>` | `lib/features/timer/timer_provider.dart` | UI / 定时到期联动入口 |

### 2.3 状态机图

```
[idle] --startDuration(minutes)--> [duration, endTime=now+minutes]
[idle] --startAfterCurrent()-->    [afterCurrent]
[duration] --pause()-->  [paused, remainingMs=endTime-now]
[paused]   --resume()--> [duration, endTime=now+<remainingMs反推>]  ← BUG 在这一步
[*]       --cancel()-->   [idle]
[duration] --checkExpired() if endTime<=now--> [idle]
```

---

## §3 行为规约（Given-When-Then）

### 3.1 现有行为（BUG 行为）

- **[BUG-03-S1]** resume 用 ceil(minutes) 把非整分钟 remainingMs 多算
  ```
  Given paused 状态且 remainingMs = 30000ms
  When  调用 resume()
  Then  当前实现 minutes = (30000/60000).ceil() = 1
    And endTime = now + Duration(minutes: 1) = now + 60s
    And 剩余 60s —— 比 saved remainingMs 多 30s
  ```
  Code evidence: `lib/features/timer/domain/timer_service.dart:212-222`

- **[BUG-03-S2]** 多次 pause/resume 循环累积上取整
  ```
  Given startDuration(1) → elapsed 30s → pause → resume → elapsed 25s → pause → resume
  Then  bug 累积剩余时间会变成 60s（每轮都从 ceil 回 1 分钟）
  ```
  Code evidence: 同上

### 3.2 修复后行为

- **[BUG-03-S3]** resume 直接使用 remainingMs 毫秒精度 (status: new)
  ```
  Given paused 状态且 remainingMs = N 毫秒
  When  调用 resume()
  Then  endTime = now + Duration(milliseconds: N)
  否定断言:
    - 不调用 ceil() / floor() 进行分钟换算
    - 不引入"分钟"作为中间单位
    - 不改变状态中的 startedAt（所有权由 _state.startedAt 决定）
    - 不调用 startDuration（必须走 paused → duration 直接切换）
  ```
  Code evidence: `lib/features/timer/domain/timer_service.dart:212-223`

- **[BUG-03-S4]** 多次 pause/resume 循环不累积误差 (status: new)
  ```
  Given startDuration(60) → elapsed 30s → pause → resume → elapsed 25s → pause → resume
  When  对比 resume 前后剩余时间
  Then  最终剩余应 ≈ 5s（55s 已用）
  否定断言:
    - 剩余时间不应超过原始 duration
    - 多次循环不应使 endTime 漂移到原始 startedAt + duration 之前
  ```
  Code evidence: 同上

- **[BUG-03-S5]** resume 在 paused 模式以外 (mode != paused) 仍返回 false (status: modified)
  ```
  Given mode == duration 或 afterCurrent
  When  调用 resume()
  Then  返回 false，state 不变
  否定断言:
    - 不重新计算 endTime
    - 不清理 startedAt
    - 不影响 _state.mode == duration 的现存 timer
  ```
  Code evidence: `lib/features/timer/domain/timer_service.dart:212-213`（恢复前的 mode 守卫保留）

---

## §4 不变量

- **[BUG-03-INV1]** resume 后 endTime - now == saved remainingMs（误差 ≤ 1ms）
  证据：`lib/features/timer/domain/timer_service.dart:212-223`

- **[BUG-03-INV2]** pause→resume 循环对总时长守恒：startedAt + initialDuration 不依赖 pause 次数
  证据：`lib/features/timer/domain/timer_service.dart:198-223`

- **[BUG-03-INV3]** resume 在非 paused 模式下是 no-op
  证据：`lib/features/timer/domain/timer_service.dart:212-213`

---

## §5 测试规约

### 5.1 现有测试清单

| 测试文件 | 覆盖的 Scenario / INV | 备注 |
|---|---|---|
| `test/features/timer/timer_test.dart` | TST-T26~T29 pause/resume 单次 | T27 用 `<= 5min 整除场景` 未触发 ceil 失真 |
| `test/features/timer/bug_bug03_repro_test.dart` | BUG-03-S1/S2/S3 | 复现测试 |

### 5.2 测试 ID 派生清单

```
BUG-03-S1 S2     # BUG 行为（修复前 FAIL）
BUG-03-S3 S4 S5  # 新规约断言
BUG-03-INV1 INV2 INV3
```

### 5.3 测试覆盖盲点

| 未覆盖 ID | 现状 | 应补偿方式 |
|---|---|---|
| BUG-03-S3 | 复现测试有，修复后 PASS | — |
| BUG-03-S4 | 复现测试有，修复后 PASS | — |
| BUG-03-S5 | 既有 TST-T31 覆盖不变量 | 标 ref |
| BUG-03-INV1 | 无 | 在 timer_test 加 `pause @ 30s → resume → endTime-now ≈ 30000ms ±10ms` |
| BUG-03-INV2 | 无 | 加 `pause→resume→pause→resume @ elapsed 25s/30s → 剩余 5s` |
| BUG-03-INV3 | TST-T31 部分覆盖 | — |

---

## §6 算法样例

```
ALG resume:
  输入: remainingMs = 30000             → 期望: endTime = now + 30s
  输入: remainingMs = 1                 → 期望: endTime = now + 1ms
  输入: remainingMs = 60000             → 期望: endTime = now + 60s
  输入: remainingMs = 60001             → 期望: endTime = now + 60.001s（不再被丢到 120s）
  输入: remainingMs = 0                  → 期望: endTime = now + 0ms（立即过期）
  输入: state != paused                  → 期望: 返回 false, state 不变
```

---

## §7 跨模块影响

| 其它 feature | 影响点 | 影响条件 | 需要补的回归断言 |
|---|---|---|---|
| PRG | 定时器到期 → player pause 与进度保存期间存在联动 | resume 时间变化可能改变 expiry wall clock | 在 prg_test 加 `timer 到期触发 saveProgress @ 30s 应按预期落库` 端到端用例 |

---

## §8 平台特性与手动 QA

本功能不涉及平台原生特性，全部可在 `flutter test` 中验证，无需手动 QA。

---

## §9 dev-status.json 条目对照

见统一更新：`docs/dev/dev-status.json`。

---

## §10 changelog

- 2026-06-28: 创建 BUG-03 spec（基于 cr.md B3 + 复现测试已写且 FAIL） (status: new)