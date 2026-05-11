# Timer 模块功能设计

## 1. 模块概述

Timer 模块提供定时停止播放功能，帮助用户在睡前或特定场景下自动停止音频播放。支持固定时长倒计时和播完当前音频两种模式。

---

## 2. 功能列表

| 功能编号 | 功能名称 | 优先级 |
|----------|----------|--------|
| TMR-01 | 设置固定时长定时（5/10/15分钟） | P0 |
| TMR-02 | 设置播完当前音频后停止 | P0 |
| TMR-03 | 定时倒计时显示 | P0 |
| TMR-04 | 取消定时 | P0 |
| TMR-05 | 定时到期执行停止 | P0 |

---

## 3. 功能详细设计

### TMR-01 设置固定时长定时

**入口：** 播放器页面 → 定时按钮（沙漏图标）→ 弹出选择菜单

**选项：**
- 5 分钟
- 10 分钟
- 15 分钟

**交互流程：**
```
用户点击定时按钮
    → 弹出 BottomSheet 选择菜单
    → 用户选择时长
    → 关闭菜单，开始倒计时
    → 定时按钮变为激活状态（显示剩余时间）
```

**实现：** 使用 Dart `Timer` 类，在 `audio_service` 的 `AudioHandler` 中管理，确保后台也能触发停止。

---

### TMR-02 播完当前音频后停止

**入口：** 同 TMR-01 弹出菜单，选项「播完当前」

**行为：** 监听 `just_audio` 的播放完成事件，当前曲目播放结束时停止播放，不自动切换下一首

**实现：**
```dart
// 在 AudioHandler 中监听播放状态
_player.processingStateStream.listen((state) {
  if (state == ProcessingState.completed && _stopAfterCurrent) {
    pause();
    _stopAfterCurrent = false;
  }
});
```

---

### TMR-03 定时倒计时显示

**显示位置：** 播放器页面定时按钮旁，显示剩余时间

**格式：**
- 剩余 > 60 秒：显示 `X分钟`（如 `14分钟`）
- 剩余 ≤ 60 秒：显示 `Xs`（如 `45s`）
- 播完当前模式：显示 `播完停止`

**更新频率：** 每秒更新一次（使用 Stream.periodic）

---

### TMR-04 取消定时

**入口：** 定时激活状态下，点击定时按钮 → 弹出菜单显示「取消定时」选项

**行为：** 取消 Timer，清除定时状态，按钮恢复未激活状态

---

### TMR-05 定时到期执行停止

**固定时长到期：**
1. 调用 `AudioHandler.pause()` 暂停播放
2. 清除定时状态
3. 若应用在前台，显示 Snackbar：「定时停止已触发」

**播完当前到期：**
1. 当前曲目播放完成时，调用 `pause()` 而非自动切换下一首
2. 清除定时状态

**后台触发：** 定时逻辑在 `AudioHandler`（前台服务）中运行，即使应用在后台也能正常触发

---

## 4. 数据模型

```dart
enum TimerMode { duration, afterCurrent }

class SleepTimer {
  final TimerMode mode;
  final DateTime? endTime;      // duration 模式下的结束时间
  final bool stopAfterCurrent;  // afterCurrent 模式标志
}
```

---

## 5. Provider 设计

```dart
@riverpod
class SleepTimerNotifier extends _$SleepTimerNotifier {
  Timer? _timer;

  // state: SleepTimer? (null 表示未设置)

  void setDurationTimer(Duration duration) {
    _cancelTimer();
    final endTime = DateTime.now().add(duration);
    state = SleepTimer(mode: TimerMode.duration, endTime: endTime);
    _timer = Timer(duration, _onTimerExpired);
  }

  void setAfterCurrentTimer() {
    _cancelTimer();
    state = SleepTimer(mode: TimerMode.afterCurrent, stopAfterCurrent: true);
    // 通知 AudioHandler 设置 stopAfterCurrent 标志
  }

  void cancel() {
    _cancelTimer();
    state = null;
  }

  void _onTimerExpired() {
    // 调用 AudioHandler.pause()
    state = null;
  }
}

// 剩余时间流（每秒更新）
@riverpod
Stream<Duration?> remainingTime(RemainingTimeRef ref) {
  // 基于 sleepTimerNotifier.state 计算剩余时间
}
```

---

## 6. UI 结构

```
TimerButton (播放器页面)
├── 图标：沙漏（未激活）/ 沙漏+剩余时间（激活中）
└── 点击 → TimerBottomSheet
    ├── 选项：5分钟
    ├── 选项：10分钟
    ├── 选项：15分钟
    ├── 选项：播完当前
    └── 选项：取消定时（仅激活时显示）
```

---

## 7. 关键文件

| 文件 | 职责 |
|------|------|
| `lib/core/services/audio_handler.dart` | 定时停止的实际执行（pause 调用） |
| `lib/features/player/timer_provider.dart` | 定时状态管理 |
| `lib/features/player/widgets/timer_button.dart` | 定时按钮 + 底部弹出菜单 |
