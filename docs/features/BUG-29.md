# BUG-29 — 定时器显示一致性（TMR1+TMR3）

> 来源：`docs/cr/cr-20260724-0110.md` TMR1 (line 516-521) + TMR3 (line 523-527)
> dev-plan 流程：Bug 修复模式

---

## §0 头部元数据

```yaml
id: BUG-29
name: 定时器显示一致性（TMR1+TMR3）
priority: P1
status: draft
created_at: 2026-07-27
last_updated: 2026-07-27
spec_anchored_files:
  - lib/features/timer/timer_provider.dart
  - lib/features/timer/domain/timer_service.dart
cross_module_impacts: [TMR]
parent_feature: Timer
manual_qa_required: false
```

---

## §1 用户视角

### 1.0 原始需求

> cr-20260724-0110.md TMR1：`timer_provider.dart:155` paused 模式下 `remainingTimeProvider` 返回 null stream（`Stream.value(null)`），而 `timer_service.dart:298-302` 的 `displayString` 返回冻结的 `remainingMs`。消费者 `timer_control.dart:23` 通过 `formattedRemainingProvider` 获取值，在 paused 时降级为 inactive 图标。两条显示路径语义不一致。
> cr-20260724-0110.md TMR3：`timer_provider.dart:163` `Stream.periodic(1s)` 首事件在 1 秒后才到达；`:190` `.valueOrNull` 在首秒为 null → `timer_control` 在定时器已激活的首秒内渲染 inactive 图标。

### 1.1 这一功能干什么（一句话）

统一定时器剩余时间的两条显示路径，并修复启动后首秒显示 inactive 图标的问题。

### 1.2 用户期望的场景

| ID | 你看到的样子 | 期望行为 |
|----|----|----|
| U1 | 定时器暂停后 | TimerControl 显示冻结的剩余时间（如 "04:35"），不降级为 inactive 图标 |
| U2 | 定时器刚启动（0~1s 内） | TimerControl 立即显示倒计时，不闪 inactive 图标 |
| U3 | 定时器正常运行中 | 每秒更新倒计时（行为不变） |
| U4 | afterCurrent 模式 | 显示"播完停止"标签（行为不变） |

---

## §2 已实现的功能骨架

### 2.1 文件与分层

| 层 | 文件 | 行数 | 角色 |
|---|---|---|---|
| Provider | `lib/features/timer/timer_provider.dart` | 239 | 定时器状态 + 剩余时间流 |
| Domain | `lib/features/timer/domain/timer_service.dart` | 306 | 纯逻辑状态机 + 格式化 |
| UI | `lib/features/player/widgets/timer_control.dart` | 61 | 定时器按钮 + 倒计时显示 |

### 2.2 关键代码段

| 区域 | 行号 | 说明 |
|---|---|---|
| remainingTimeProvider 主路径 | `timer_provider.dart:152-178` | StreamProvider：paused 模式返回 `Stream.value(null)` |
| remainingTimeProvider paused 分支 | `timer_provider.dart:155` | `state.mode != TimerMode.duration` → null stream |
| formattedRemainingProvider | `timer_provider.dart:189-193` | `remainingTimeProvider.valueOrNull` → `service.formatRemaining(remaining)` |
| Stream.periodic 首事件延迟 | `timer_provider.dart:163` | `Stream.periodic(1s)` 首事件 t=1s |
| TimerState.remainingTime (paused) | `timer_service.dart:62-66` | paused 模式返回 `Duration(remainingMs)` |
| TimerService.displayString | `timer_service.dart:298-302` | 直接调用 `formatRemaining(_state!.remainingTime)` |
| TimerControl 消费 | `timer_control.dart:22-26` | `isActive && displayText != null` → active icon; else → inactive icon |

---

## §3 行为规约

### 3.1 修复后行为

- **[BUG-29-S1]** paused 模式下 `remainingTimeProvider` 发出冻结值 (`status: new`)
  ```
  Given 定时器处于 TimerMode.paused 状态，remainingMs=275000
  When  UI 读取 formattedRemainingProvider
  Then  返回 "04:35"（冻结的剩余时间格式化结果）
  否定断言:
    - 不返回 null（当前 BUG：Stream.value(null) 导致 displayText=null）
    - 不降级为 inactive 图标（timer_control.dart:46-52 的 fallback 分支）
    - 不改变 duration 模式的每秒倒计时行为
    - 不改变 afterCurrent 模式的"播完停止"标签行为
  ```
  Code evidence: `lib/features/timer/timer_provider.dart:155`（`state.mode != TimerMode.duration` 对 paused 为 true → null stream）
  对照：`lib/features/timer/domain/timer_service.dart:62-66`（`remainingTime` getter 在 paused 模式返回冻结 Duration）

  **修改指令 — `lib/features/timer/timer_provider.dart`（remainingTimeProvider）**

  位置：`:152-178`

  当前代码（:152-157）：
  ```dart
  final remainingTimeProvider = StreamProvider<Duration?>((ref) {
    final state = ref.watch(timerStateProvider);

    if (state == null || state.mode != TimerMode.duration) {
      return Stream.value(null);
    }
  ```

  改为：
  ```dart
  final remainingTimeProvider = StreamProvider<Duration?>((ref) {
    final state = ref.watch(timerStateProvider);

    if (state == null || state.mode == TimerMode.afterCurrent) {
      return Stream.value(null);
    }

    if (state.mode == TimerMode.paused) {
      return Stream.value(state.remainingTime);
    }
  ```

  边界裁决：
  - `state == null` → 返回 null（不变）
  - `state.mode == TimerMode.afterCurrent` → 返回 null（不变，UI 用 `afterCurrentLabel`）
  - `state.mode == TimerMode.paused` → 返回冻结 `remainingTime`（新增分支）
  - `state.mode == TimerMode.duration` → 走 `Stream.periodic` 路径（不变）
  - paused → resume 后 `timerStateProvider` 变为 duration → `remainingTimeProvider` 自动重建（Riverpod watch 机制）

- **[BUG-29-S2]** duration 模式启动后首秒即显示倒计时 (`status: new`)
  ```
  Given 用户刚启动 duration 定时器（TimerMode.duration，endTime 已设置）
  When  remainingTimeProvider 在 t=0~1s 内被读取
  Then  formattedRemainingProvider 返回初始倒计时字符串（如 "05:00"）
  否定断言:
    - 不在首秒返回 null（当前 BUG：Stream.periodic 首事件 1s 后才到，valueOrNull=null）
    - 不在首秒降级为 inactive 图标
    - 不改变后续每秒更新的行为
  ```
  Code evidence: `lib/features/timer/timer_provider.dart:163`（`Stream.periodic(const Duration(seconds: 1), ...)` 首事件延迟 1s）

  **修改指令 — `lib/features/timer/timer_provider.dart`（remainingTimeProvider duration 分支）**

  位置：`:162-177`

  当前代码（:162-177）：
  ```dart
    var didEmitZero = false;
    return Stream.periodic(const Duration(seconds: 1), (_) {
      final currentState = ref.read(timerStateProvider);
      if (currentState == null || currentState.mode != TimerMode.duration) {
        return null;
      }
      return currentState.remainingTime;
    }).takeWhile((d) {
      if (d == null) return false;
      if (d == Duration.zero) {
        if (didEmitZero) return false;
        didEmitZero = true;
        return true;
      }
      return true;
    });
  ```

  改为：
  ```dart
    var didEmitZero = false;
    final initial = state.remainingTime;
    final periodic = Stream.periodic(const Duration(seconds: 1), (_) {
      final currentState = ref.read(timerStateProvider);
      if (currentState == null || currentState.mode != TimerMode.duration) {
        return null;
      }
      return currentState.remainingTime;
    }).takeWhile((d) {
      if (d == null) return false;
      if (d == Duration.zero) {
        if (didEmitZero) return false;
        didEmitZero = true;
        return true;
      }
      return true;
    });
    return Stream.value(initial).concatWith([periodic]);
  ```

  边界裁决：
  - `initial` 为 `endTime - now` 的 Duration，首秒即通过 `Stream.value(initial)` 发出
  - `periodic` 从 t=1s 开始，与首事件不冲突（首事件已被消费，periodic 首事件补上 1s 后的值）
  - 若 `initial == Duration.zero`（极短定时器恰好在创建时已过期）→ `didEmitZero` 机制在 periodic 端仍正常工作
  - `concatWith` 保证顺序：先 `Stream.value(initial)` 再 periodic 流
  - 若 state 在首事件前被 cancel → Riverpod 重建 provider → stream 被丢弃（`Stream.value(null)` from :155）

  **测试文件位置：`test/features/timer/bug_bug29_repro_test.dart`**

---

## §4 不变量

- **[BUG-29-INV1]** `remainingTimeProvider` 与 `TimerService.displayString` 语义一致
  证据：修复后两者对 paused 模式均返回冻结 Duration（`timer_provider.dart:155` 新增 paused 分支 + `timer_service.dart:62-66`）

- **[BUG-29-INV2]** `remainingTimeProvider` 对已激活状态始终在首帧发出非 null 值
  证据：修复后 `Stream.value(initial).concatWith([periodic])`（`timer_provider.dart:163-179`）确保首事件无延迟

---

## §5 测试规约

### 5.1 现有测试清单

| 测试文件 | 覆盖 | 备注 |
|---|---|---|
| `test/features/timer/` | TMR-01~05 定时器基本逻辑 | TimerService 纯逻辑测试 |

### 5.2 测试 ID 派生清单

```
BUG-29-S1           # paused 模式 frozen 值显示
BUG-29-S2           # duration 启动首秒显示
BUG-29-INV1         # remainingTimeProvider 与 displayString 语义一致
BUG-29-INV2         # 首帧非 null 值
```

### 5.3 测试覆盖盲点

| 未覆盖 ID | 现状 | 应补偿方式 |
|---|---|---|
| BUG-29-S1 | 现有测试未覆盖 paused 模式下 provider 行为 | 设置 paused 状态 → 读取 formattedRemainingProvider → 断言非 null 且等于冻结值格式化结果 |
| BUG-29-S2 | 现有测试未覆盖首秒显示 | 设置 duration 状态 → 立即读取 remainingTimeProvider → 断言非 null |

### 5.4 测试文件位置

| 测试 ID | 文件路径 |
|---|---|
| BUG-29-S1 | `test/features/timer/bug_bug29_repro_test.dart` |
| BUG-29-S2 | `test/features/timer/bug_bug29_repro_test.dart` |
| BUG-29-INV1 | `test/features/timer/bug_bug29_repro_test.dart` |
| BUG-29-INV2 | `test/features/timer/bug_bug29_repro_test.dart` |

---

## §6 算法样例

不适用——本修复为数据流修复（分支补全 + 首值注入），无新算法。

---

## §7 跨模块影响

| 其它 feature | 影响点 | 需要补的回归断言 |
|---|---|---|
| TMR | `remainingTimeProvider` 是 `formattedRemainingProvider` 的唯一数据源 | paused 模式不再返回 null，不影响 duration/afterCurrent 路径 |
| TMR | `timer_control.dart:22-26` 消费 `formattedRemainingProvider` | paused 时 `displayText` 非 null → 走 active icon 分支 |

---

## §8 平台特性与手动 QA

本功能不涉及平台原生特性，全部可在 `flutter test` 中验证。

---

## §9 dev-status.json 条目对照

见统一更新：`docs/dev/dev-status.json`。

---

## §10 changelog

- 2026-07-27: 创建 BUG-29 spec（基于 cr-20260724-0110.md TMR1 + TMR3）
