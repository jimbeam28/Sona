# REF-05 — 定时器死代码清理（TMR2+TMR4+TMR5）

> 来源：`docs/cr/cr-20260724-0110.md` TMR2 + TMR4 + TMR5
> 用户裁决：delete timer notifier pause/resume；TimerButton 无引用需删；lastCustomTimerMinutes 仅自定义路径写入
> dev-plan 流程：Refactoring 模式

---

## §0 头部元数据

```yaml
id: REF-05
name: 定时器死代码清理（TMR2+TMR4+TMR5）
priority: P2
status: draft
created_at: 2026-07-27
last_updated: 2026-07-27
spec_anchored_files:
  - lib/features/timer/timer_provider.dart
  - lib/features/timer/widgets/timer_button.dart
  - lib/features/timer/domain/timer_service.dart
  - lib/shared/di/providers.dart
cross_module_impacts: [PLY]
parent_feature: Timer
manual_qa_required: false
```

---

## §1 用户视角

### 1.0 原始需求

> cr-20260724-0110.md TMR2：`timer_provider.dart:89-97` — pause()/resume() methods have zero callers. No UI entry point. BUG-03's millisecond-precision resume guards a path users can't reach.
> cr-20260724-0110.md TMR4：`timer_button.dart:30` — TimerButton widget has zero references in lib/ (only in tests). Player uses timer_control.dart instead. timer_service.dart:85-97 copyWith also zero callers.
> cr-20260724-0110.md TMR5：`timer_provider.dart:52` — lastCustomTimerMinutes written on every duration start (including presets). Preset "5 minutes" overwrites custom value. Dual write point with timer_button.dart:233.

### 1.1 这一功能干什么（一句话）

删除定时器模块中无调用者的死代码，修复 lastCustomTimerMinutes 被预设值覆盖的问题。

### 1.2 用户期望的场景

| ID | 你看到的样子 | 期望行为 |
|----|----|----|
| U1 | 选择预设 "5 分钟" 定时 | 不覆盖之前自定义的时长记忆 |
| U2 | 选择自定义 30 分钟定时后，再选预设 "10 分钟" | "上次时长"仍显示 30 分钟 |
| U3 | 定时器正常运行 | 功能不受影响（无 pause/resume UI 入口，删除不影响） |

---

## §2 已实现的功能骨架

### 2.1 文件与分层

| 层 | 文件 | 行数 | 角色 |
|---|---|---|---|
| Provider | `lib/features/timer/timer_provider.dart` | 239 | TimerStateNotifier + providers |
| UI (死代码) | `lib/features/timer/widgets/timer_button.dart` | 360 | TimerButton + TimerBottomSheet |
| UI (在用) | `lib/features/player/widgets/timer_control.dart` | 61 | TimerControl（实际使用的定时器按钮） |
| Domain | `lib/features/timer/domain/timer_service.dart` | 306 | TimerService + TimerState |
| Bridge | `lib/shared/di/providers.dart:179-180` | — | re-export TimerButton, TimerBottomSheet |

### 2.2 关键代码段

| 区域 | 行号 | 说明 |
|---|---|---|
| Notifier pause()/resume() 死代码 | `timer_provider.dart:88-97` | 零调用者 |
| startDuration 错误写入 lastCustom | `timer_provider.dart:52` | 每次 startDuration 都写，包括预设 |
| TimerButton 类 | `timer_button.dart:29-66` | 零生产引用 |
| TimerBottomSheet 类 | `timer_button.dart:72-169` | TimerControl 在用 |
| TimerState.copyWith | `timer_service.dart:85-97` | 零外部调用者 |
| 自定义确认写入 | `timer_button.dart:233` | setLastCustomTimerMinutesProvider 正确写入点 |
| providers.dart re-export | `providers.dart:179-180` | 导出 TimerButton + TimerBottomSheet |

---

## §3 行为规约

### 3.1 删除 Notifier pause/resume（TMR2）

- **[REF-05-S1]** 删除 TimerStateNotifier 的 pause()/resume() 方法 (`status: new`)
  ```
  Given TimerStateNotifier 存在 pause()/resume() 方法
  When  lib/ 中无任何调用者
  Then  删除 timer_provider.dart:88-97 的 pause() 和 resume() 方法
  否定断言:
    - 不删除 TimerService.pause()/resume()（服务层能力保留）
    - 不删除 TimerMode.paused 枚举值（TimerState 仍支持 paused 状态）
    - 不删除 TimerState.remainingMs 字段（序列化/反序列化兼容）
    - 不改变 TimerStateNotifier 的其它方法（startDuration/startAfterCurrent/cancel/checkExpired/onTrackCompleted）
  ```
  Code evidence: `lib/features/timer/timer_provider.dart:88-97`（pause/resume 定义）；grep 确认 lib/ 零调用

  **修改指令 — `lib/features/timer/timer_provider.dart`**

  位置：`:88-97`

  删除：
  ```dart
    // TMR-03: pause/resume support
    void pause() {
      _service.pause();
      state = _service.state;
    }

    void resume() {
      _service.resume();
      state = _service.state;
    }
  ```

### 3.2 删除 TimerButton widget（TMR4）

- **[REF-05-S2]** 删除 TimerButton 类并修正 re-export (`status: new`)
  ```
  Given TimerButton 在 lib/ 中零生产引用（player 用 TimerControl）
  When  删除 TimerButton 类
  Then  timer_button.dart 中 TimerButton 类被删除
  And   providers.dart:179-180 re-export 仅保留 TimerBottomSheet
  否定断言:
    - 不删除 TimerBottomSheet（TimerControl 依赖）
    - 不删除 _CustomTimerPickerSheet / _TimerOptionTile（TimerBottomSheet 依赖）
    - 不删除 _formatMinutesLabel（TimerBottomSheet 依赖）
    - 不改变 TimerControl 的行为（player/widgets/timer_control.dart 不变）
  ```
  Code evidence: `lib/features/timer/widgets/timer_button.dart:29-66`（TimerButton 定义）；`lib/shared/di/providers.dart:179-180`（re-export）；grep 确认 lib/ 零引用

  **修改指令 — `lib/features/timer/widgets/timer_button.dart`**

  位置：`:1-66`（文件头注释 + TimerButton 类）

  删除整个 `TimerButton` 类（:29-66）及其文件头注释中 TimerButton 相关描述（:4, :19-28）。保留 TimerBottomSheet 及后续所有代码。

  **修改指令 — `lib/shared/di/providers.dart`**

  位置：`:179-180`

  当前代码：
  ```dart
  export '../../features/timer/widgets/timer_button.dart'
      show TimerButton, TimerBottomSheet;
  ```
  改为：
  ```dart
  export '../../features/timer/widgets/timer_button.dart'
      show TimerBottomSheet;
  ```

### 3.3 删除 TimerState.copyWith（TMR4 延伸）

- **[REF-05-S3]** 删除 TimerState.copyWith (`status: new`)
  ```
  Given TimerState.copyWith 在 lib/ 中零外部调用者
  When  删除 copyWith 方法
  Then  timer_service.dart 中 TimerState.copyWith 被删除
  否定断言:
    - 不删除 TimerState 的 == / hashCode（仍被 TimerStateNotifier 状态比较使用）
    - 不删除 TimerState.remainingTime / isExpired（仍被 checkExpired/formatRemaining 使用）
    - 不删除 TimerState.toString()（日志使用）
  ```
  Code evidence: `lib/features/timer/domain/timer_service.dart:85-97`（copyWith 定义）；grep 确认 lib/ 零外部调用

  **修改指令 — `lib/features/timer/domain/timer_service.dart`**

  位置：`:83-97`

  删除：
  ```dart
    /// Creates a copy of this state with optional field changes. Returns
    /// a state preserving the [now] provider.
    TimerState copyWith({
      TimerMode? mode,
      DateTime? endTime,
      DateTime? startedAt,
      int? remainingMs,
    }) =>
        TimerState(
          mode: mode ?? this.mode,
          endTime: endTime ?? this.endTime,
          startedAt: startedAt ?? this.startedAt,
          remainingMs: remainingMs ?? this.remainingMs,
          now: _now,
        );
  ```

### 3.4 修复 lastCustomTimerMinutes 写入时机（TMR5）

- **[REF-05-S4]** lastCustomTimerMinutes 仅在自定义确认路径写入 (`status: new`)
  ```
  Given 用户通过自定义选择器确认 30 分钟
  When  之后选择预设 "5 分钟"
  Then  lastCustomTimerMinutes 仍为 30（不被预设覆盖）
  否定断言:
    - 不在 startDuration 被预设调用时写入 lastCustomTimerMinutes（当前 BUG：timer_provider.dart:52 所有 startDuration 都写）
    - 不改变自定义确认路径的写入行为（timer_button.dart:233 保持写入）
    - 不改变 startDuration 的其它行为（TimerState 正常创建）
  ```
  Code evidence: `lib/features/timer/timer_provider.dart:49-53`（startDuration 中 :52 写入）；`lib/features/timer/widgets/timer_button.dart:233`（自定义确认写入）

  **修改指令 — `lib/features/timer/timer_provider.dart`**

  位置：`:49-54`

  当前代码：
  ```dart
    void startDuration(int minutes) {
      debugPrint('[Timer] startDuration: ${minutes}min');
      _service.startDuration(minutes);
      ref.read(setLastCustomTimerMinutesProvider)(minutes);
      state = _service.state;
    }
  ```
  改为：
  ```dart
    void startDuration(int minutes) {
      debugPrint('[Timer] startDuration: ${minutes}min');
      _service.startDuration(minutes);
      state = _service.state;
    }
  ```

  说明：自定义确认路径 `timer_button.dart:233` 已独立调用 `setLastCustomTimerMinutesProvider`，无需 startDuration 重复写入。

---

## §4 不变量

- **[REF-05-INV1]** TimerStateNotifier 无 pause/resume 方法
  证据：删除后 `timer_provider.dart` 中 TimerStateNotifier 仅含 startDuration/startAfterCurrent/cancel/checkExpired/onTrackCompleted

- **[REF-05-INV2]** TimerButton 类不存在于代码库
  证据：删除后 `timer_button.dart` 中无 TimerButton 类定义；`providers.dart` re-export 不含 TimerButton

- **[REF-05-INV3]** lastCustomTimerMinutes 唯一写入点为自定义确认路径
  证据：`timer_button.dart:233`（唯一 setLastCustomTimerMinutesProvider 调用）；`timer_provider.dart` 不再调用

---

## §5 测试规约

### 5.1 现有测试清单

| 测试文件 | 覆盖 | 备注 |
|---|---|---|
| `test/features/timer/` | Timer 功能测试 | 需检查是否有测试引用 pause/resume/TimerButton/copyWith |

### 5.2 测试 ID 派生清单

```
REF-05-S1           # 删除 Notifier pause/resume
REF-05-S2           # 删除 TimerButton + 修正 re-export
REF-05-S3           # 删除 TimerState.copyWith
REF-05-S4           # lastCustomTimerMinutes 仅自定义写入
REF-05-INV1         # 无 pause/resume 方法
REF-05-INV2         # 无 TimerButton 类
REF-05-INV3         # 唯一写入点
```

### 5.3 测试覆盖盲点

| 未覆盖 ID | 现状 | 应补偿方式 |
|---|---|---|
| REF-05-S4 | 需验证预设不覆盖自定义值 | 启动预设 5 分钟 → 检查 lastCustomTimerMinutes 未变；启动自定义 30 分钟 → 检查值为 30 |

---

## §6 算法样例

不适用——本重构为删除死代码，无新算法。

---

## §7 跨模块影响

| 其它 feature | 影响点 | 需要补的回归断言 |
|---|---|---|
| PLY | `player_screen.dart` import TimerControl | TimerControl 不受影响（不依赖 TimerButton） |
| Timer | 现有 timer 测试若引用 pause/resume/TimerButton/copyWith | 需删除或更新对应测试 |

---

## §8 平台特性与手动 QA

本功能不涉及平台原生特性，全部可在 `flutter test` 中验证。

---

## §9 dev-status.json 条目对照

见统一更新：`docs/dev/dev-status.json`。

---

## §10 changelog

- 2026-07-27: 创建 REF-05 spec（基于 cr-20260724-0110.md TMR2 + TMR4 + TMR5）
