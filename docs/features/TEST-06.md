# TEST-06 — 定时器测试缺口（TMR6+TMR7）

> 来源：`docs/cr/cr-20260724-0110.md` TMR6 (line 549-552) + TMR7 (line 554-557)
> dev-plan 流程：TEST-GAP 补测模式

---

## §0 头部元数据

```yaml
id: TEST-06
name: 定时器测试缺口（TMR6+TMR7）
priority: P1
status: draft
created_at: 2026-07-27
last_updated: 2026-07-27
spec_anchored_files:
  - lib/features/timer/domain/timer_service.dart
  - lib/features/timer/timer_provider.dart
cross_module_impacts: [TMR, PLY]
parent_feature: Timer
manual_qa_required: false
```

---

## §1 用户视角

### 1.0 原始需求

> cr-20260724-0110.md TMR6：`timer_test.dart:13-17` 自述所有 widget 测试用 noopRemainingTimeOverride 替换真实流；TMR-T15 名为"每秒更新"实为单次读取断言 >0；TMR-T09 对 formatRemaining(90s) 仅断言 isNotNull。把周期 1s 改 60s、删 didEmitZero 守卫、改 paused 分支，全部测试仍绿。
> cr-20260724-0110.md TMR7：lcov DA:155,0 负数 ArgumentError 守卫未测；DA:103-110 ==/hashCode 字段比较路径全部 0 覆盖。

### 1.1 这一功能干什么（一句话）

补齐定时器模块两类测试缺口：remainingTimeProvider 逐秒发射行为真实验证、TimerState 负数守卫和等值比较覆盖。

### 1.2 用户期望的场景

| ID | 你看到的样子 | 期望行为 |
|----|----|----|
| U1 | 定时器激活后倒计时 | 每秒更新一次剩余时间（真实 Stream.periodic 发射） |
| U2 | 定时器取消或暂停 | 剩余时间流终止或返回 paused 值 |
| U3 | 定时器到零 | 发射一次 zero 后流关闭 |
| U4 | 首帧读取 | 立即获得初始剩余时间 |
| U5 | startDuration(-1) | 抛出 ArgumentError |
| U6 | 两 TimerState 字段不同 | == 返回 false |

---

## §2 已实现的功能骨架

### 2.1 文件与分层

| 层 | 文件 | 行数 | 角色 |
|---|---|---|---|
| Domain | `lib/features/timer/domain/timer_service.dart` | 306 | TimerState + TimerService 纯逻辑状态机 |
| Provider | `lib/features/timer/timer_provider.dart` | 239 | remainingTimeProvider (Stream.periodic) |
| 测试 | `test/features/timer/timer_test.dart` | 1137 | TMR 系列测试 |
| Helper | `test/helpers/widget_helpers.dart` | 220 | noopRemainingTimeOverride |

### 2.2 关键代码段

| 区域 | 行号 | 说明 |
|---|---|---|
| noopRemainingTimeOverride | `widget_helpers.dart:161-163` | 用 `Stream.value(null)` 替换真实流 |
| remainingTimeProvider | `timer_provider.dart:152-178` | Stream.periodic 1s + takeWhile |
| didEmitZero 守卫 | `timer_provider.dart:162,171-173` | 确保 zero 只发射一次 |
| formatRemaining(90s) 弱断言 | `timer_test.dart:170-174` | `expect(formatted, isNotNull)` |
| startDuration 负数守卫 | `timer_service.dart:153-155` | `minutes < 0 → throw ArgumentError` |
| TimerState == 字段比较 | `timer_service.dart:101-107` | mode/endTime/startedAt/remainingMs |
| TimerState hashCode | `timer_service.dart:109-110` | `Object.hash(mode, endTime, startedAt, remainingMs)` |

---

## §3 行为规约

### 3.1 补测行为

- **[TEST-06-S1]** remainingTimeProvider 逐秒发射 (`status: new`)
  ```
  Given TimerService 启动 1 分钟定时器（endTime = now + 60s）
  When  remainingTimeProvider 订阅后使用 fake_async 推进 3 秒
  Then  第 1 秒发射约 59s 剩余
  And   第 2 秒发射约 58s 剩余
  And   第 3 秒发射约 57s 剩余
  否定断言:
    - 不使用 noopRemainingTimeOverride 替换真实流（当前 TMR6 问题）
    - 不做单次读取 >0 断言冒充"每秒更新"（当前 TMR-T15 问题）
    - 不在 formatRemaining 上仅断言 isNotNull（当前 TMR-T09 问题）
  ```
  Code evidence: `lib/features/timer/timer_provider.dart:152-178`; `test/features/timer/timer_test.dart:13-17`（自述用 noop override）

- **[TEST-06-S2]** 定时器取消 → 流终止 (`status: new`)
  ```
  Given remainingTimeProvider 已订阅，定时器激活
  When  TimerService.cancel() 被调用
  Then  流发射 null 后关闭（takeWhile 返回 false）
  否定断言:
    - 不在取消后继续发射非 null 值
    - 不在取消后保持流挂起
  ```
  Code evidence: `timer_provider.dart:165-166`（state null → return null → takeWhile false）

- **[TEST-06-S3]** 定时器暂停 → 流发射 paused 值 (`status: new`)
  ```
  Given 定时器处于 duration 模式，remainingTime > 0
  When  TimerService.pause() 切换为 paused 模式
  Then  remainingTime 返回 saved remainingMs（非 endTime - now 计算值）
  And   后续发射反映 paused 状态的剩余时间
  否定断言:
    - 不在 paused 模式下仍按 endTime 差值计算（paused 应返回 fixed remainingMs）
    - 不在 paused 模式下流终止
  ```
  Code evidence: `timer_service.dart:62-66`（paused mode → return Duration(milliseconds: remainingMs!)）

- **[TEST-06-S4]** 定时器到零 → 发射一次 zero 后流关闭 (`status: new`)
  ```
  Given remainingTimeProvider 已订阅，定时器剩余 2 秒
  When  fake_async 推进到剩余 0 秒
  Then  流发射 Duration.zero 恰好一次
  And   下一次 takeWhile 返回 false → 流关闭
  否定断言:
    - 不发射两次 Duration.zero（didEmitZero 守卫当前存在但未被测试验证）
    - 不在 zero 后继续发射负值
  ```
  Code evidence: `timer_provider.dart:162,171-174`（didEmitZero 守卫）

- **[TEST-06-S5]** startDuration(-1) 抛出 ArgumentError (`status: new`)
  ```
  Given TimerService 实例
  When  startDuration(-1) 被调用
  Then  抛出 ArgumentError.value(-1, 'minutes', 'must not be negative')
  否定断言:
    - 不在负数输入时设置 state（当前 DA:155,0 未覆盖：守卫抛异常前的状态不变）
    - 不在零或正数时抛异常（仅负数触发）
  ```
  Code evidence: `lib/features/timer/domain/timer_service.dart:153-155`

- **[TEST-06-S6]** TimerState 字段差异 → == 返回 false (`status: new`)
  ```
  Given TimerState A(mode: duration, endTime: t1, startedAt: s1, remainingMs: null)
  And   TimerState B(mode: duration, endTime: t2, startedAt: s1, remainingMs: null)
  When  A == B
  Then  返回 false（endTime 不同）
  否定断言:
    - 不在字段不同时返回 true（DA:103-110 == 路径 0 覆盖）
    - 不忽略 startedAt 差异（I-1 要求包含 startedAt）
  ```
  Code evidence: `lib/features/timer/domain/timer_service.dart:101-107`

- **[TEST-06-S7]** TimerState hashCode 字段差异 → 不同 hash (`status: new`)
  ```
  Given TimerState A(mode: duration, endTime: t1, startedAt: s1, remainingMs: null)
  And   TimerState B(mode: afterCurrent, endTime: null, startedAt: s1, remainingMs: null)
  When  A.hashCode vs B.hashCode
  Then  不相等（mode 不同）
  否定断言:
    - 不在字段不同时产生相同 hashCode（DA:103-110 hashCode 路径 0 覆盖）
    - 不忽略 endTime 或 remainingMs 差异
  ```
  Code evidence: `lib/features/timer/domain/timer_service.dart:109-110`

---

## §4 不变量

- **[TEST-06-INV1]** remainingTimeProvider 使用真实 Stream.periodic 逐秒发射
  证据：`timer_provider.dart:163`（`Stream.periodic(const Duration(seconds: 1), ...)`）

- **[TEST-06-INV2]** startDuration 拒绝负数输入
  证据：`timer_service.dart:153-155`（`if (minutes < 0) throw ArgumentError`）

- **[TEST-06-INV3]** TimerState == 和 hashCode 覆盖所有 4 字段
  证据：`timer_service.dart:101-110`（mode, endTime, startedAt, remainingMs）

---

## §5 测试规约

### 5.1 现有测试清单

| 测试文件 | 覆盖 | 备注 |
|---|---|---|
| `test/features/timer/timer_test.dart:13-17` | Widget test 基础设施 | 自述用 noopRemainingTimeOverride 替换真实流 |
| `test/features/timer/timer_test.dart:170-174` | TMR-T09 | `expect(formatted, isNotNull)` — 弱断言 |
| `test/helpers/widget_helpers.dart:161-163` | noopRemainingTimeOverride | Stream.value(null) 替换 |

### 5.2 测试 ID 派生清单

```
TEST-06-S1          # 逐秒发射
TEST-06-S2          # 取消→流终止
TEST-06-S3          # 暂停→paused 值
TEST-06-S4          # 到零→发射一次 close
TEST-06-S5          # startDuration(-1) ArgumentError
TEST-06-S6          # == 字段差异
TEST-06-S7          # hashCode 字段差异
TEST-06-INV1        # 真实 Stream.periodic
TEST-06-INV2        # 负数守卫
TEST-06-INV3        # 等值比较覆盖
```

### 5.3 测试覆盖盲点

| 未覆盖 ID | 现状 | 应补偿方式 |
|---|---|---|
| TEST-06-S1 | noopRemainingTimeOverride 替换真实流 | 用 fake_async 手动推进，断言逐秒发射值 |
| TEST-06-S2 | 取消→流终止无测试 | fake_async + cancel → 断言流关闭 |
| TEST-06-S3 | paused 分支未验证 | pause() → 断言 remainingTime 返回 fixed value |
| TEST-06-S4 | didEmitZero 守卫未验证 | 推进到 zero → 断言只发射一次 |
| TEST-06-S5 | DA:155,0 负数守卫未覆盖 | startDuration(-1) → 断言 ArgumentError |
| TEST-06-S6 | DA:103-110 == 路径 0 覆盖 | 两 state 字段不同 → 断言 not equal |
| TEST-06-S7 | DA:103-110 hashCode 路径 0 覆盖 | 两 state 字段不同 → 断言 hash 不同 |

### 5.4 测试文件位置

| 测试 ID | 文件路径 |
|---|---|
| TEST-06-S1~S4 | `test/features/timer/timer_test.dart`（新增 group） |
| TEST-06-S5 | `test/features/timer/timer_test.dart`（新增 unit test） |
| TEST-06-S6~S7 | `test/features/timer/timer_test.dart`（新增 unit test） |

---

## §6 算法样例

不适用——本 spec 为补测，无新算法。

---

## §7 跨模块影响

| 其它 feature | 影响点 | 需要补的回归断言 |
|---|---|---|
| PLY | `remainingTimeProvider` 被 mini_player 消费 | 补测不影响现有播放 UI 倒计时显示 |
| TMR | `widget_helpers.dart:161` noopRemainingTimeOverride | 现有 widget test 仍可用 noop override（补测新增独立 test case） |

---

## §8 平台特性与手动 QA

本功能不涉及平台原生特性，全部可在 `flutter test` 中验证。

---

## §9 dev-status.json 条目对照

见统一更新：`docs/dev/dev-status.json`。

---

## §10 changelog

- 2026-07-27: 创建 TEST-06 spec（基于 cr-20260724-0110.md TMR6 + TMR7）
