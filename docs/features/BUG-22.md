# BUG-22 — 音频焦点死代码 + 无超时（SVC2 + SVC3）

> 来源：`docs/cr/cr-20260724-0110.md` SVC2 (line 775-780) + SVC3 (line 782-786)
> dev-plan 流程：Bug 修复模式

---

## §0 头部元数据

```yaml
id: BUG-22
name: 音频焦点死代码 + 无超时（SVC2 + SVC3）
priority: P1
status: draft
created_at: 2026-07-27
last_updated: 2026-07-27
spec_anchored_files:
  - lib/core/services/audio_handler.dart
  - lib/features/player/domain/background_playback.dart
cross_module_impacts: [PLY]
parent_feature: Player
manual_qa_required: true
```

---

## §1 用户视角

### 1.0 原始需求

> cr-20260724-0110.md SVC2：`audio_handler.dart:174` 定义 `onAudioFocusChange` 但全库零调用——`BackgroundPlaybackConfig.updateAudioFocus()` 永远收不到焦点事件。SVC3：`:181,188` 内部直调 `_player.play()`/`_player.pause()` 绕过 BUG-06 超时修复。
> 用户裁决（2026-07-24）：接入 `audio_session` 的 `interruptionEventStream` / `becomingNoisyEventStream`，转发到 handler。

### 1.1 这一功能干什么（一句话）

修复音频焦点处理：将死代码的 `onAudioFocusChange` 接入 `audio_session` 真实焦点事件流，并在焦点处理内部改用带超时的 `this.play()`/`this.pause()`。

### 1.2 用户期望的场景

| ID | 你看到的样子 | 期望行为 |
|----|----|----|
| U1 | 来电时 | Sona 暂停播放 |
| U2 | 通话结束后 | Sona 恢复播放（若之前正在播放） |
| U3 | 耳机拔出时 | Sona 暂停播放 |
| U4 | 通知音效播放时 | Sona 短暂降低音量（duck）或暂停后恢复 |
| U5 | 平台调用超时（P4 场景） | 焦点触发的 play/pause 也有 5s 超时保护 |

---

## §2 已实现的功能骨架

### 2.1 文件与分层

| 层 | 文件 | 行数 | 角色 |
|---|---|---|---|
| Contract | `lib/core/contracts/audio_handler_contract.dart` | 84 | 抽象接口（含 `onAudioFocusChange`） |
| Service | `lib/core/services/audio_handler.dart` | 265 | 具体实现 |
| Domain | `lib/features/player/domain/background_playback.dart` | 306 | 焦点状态机 |

### 2.2 关键方法表

| 方法 | 位置 | 用途 |
|---|---|---|
| `onAudioFocusChange` | `audio_handler.dart:174-191` | 焦点变化处理（**死代码：零调用**） |
| `play` (override) | `audio_handler.dart:196-204` | 带 5s 超时的 play |
| `pause` (override) | `audio_handler.dart:207-215` | 带 5s 超时的 pause |
| `_player.play()` | `audio_handler.dart:188` | 焦点处理内**直调**无超时 |
| `_player.pause()` | `audio_handler.dart:181` | 焦点处理内**直调**无超时 |
| `updateAudioFocus` | `background_playback.dart:157-173` | 焦点状态机转移 |

---

## §3 行为规约

### 3.1 修复后行为

- **[BUG-22-S1]** 接入 `audio_session` 中断事件流 (`status: new`)
  ```
  Given NasAudioHandler 已创建
  When 系统触发音频中断事件（来电、通知音效等）
  Then audio_session interruptionEventStream 事件被转发到 onAudioFocusChange
  否定断言:
    - 不在无音频会话时创建订阅（handler 创建时获取 AudioSession）
    - 不在 dispose 后继续接收事件（订阅须被 cancel）
    - 不改变 play/pause/stop 等已有 media control 的行为
  ```
  Code evidence: `audio_handler.dart:174-191`（`onAudioFocusChange` 零调用）
  Code evidence: `audio_handler.dart:67-71`（构造函数只订阅 playerStateStream/positionStream/durationStream，无 audio_session）
  grep 证据: `lib/` 下 grep `interruptionEventStream` / `becomingNoisyEventStream` / `AudioSession.instance` 零命中
  依赖证据: `pubspec.yaml:38`（`audio_session: any` 已声明但未使用）

  **修改指令 — `lib/core/services/audio_handler.dart`（构造函数 + dispose + 新增字段）**

  位置：`:17` imports + `:63-71` subscriptions/constructor + `:260-264` dispose

  当前 imports（:17-23）：
  ```dart
  import 'dart:async';

  import 'package:audio_service/audio_service.dart';
  import 'package:just_audio/just_audio.dart';

  import '../../features/player/background_playback.dart';
  import '../../features/player/media_control_model.dart' hide MediaAction;
  ```

  改为：
  ```dart
  import 'dart:async';

  import 'package:audio_service/audio_service.dart';
  import 'package:audio_session/audio_session.dart';
  import 'package:just_audio/just_audio.dart';

  import '../../features/player/background_playback.dart';
  import '../../features/player/media_control_model.dart' hide MediaAction;
  ```

  当前 subscriptions（:63-71）：
  ```dart
  StreamSubscription<PlayerState>? _stateSub;
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<Duration?>? _durationSub;

  NasAudioHandler(this._player) {
    _stateSub = _player.playerStateStream.listen(_onPlayerStateChanged);
    _positionSub = _player.positionStream.listen(_onPositionChanged);
    _durationSub = _player.durationStream.listen(_onDurationChanged);
  }
  ```

  改为：
  ```dart
  StreamSubscription<PlayerState>? _stateSub;
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<Duration?>? _durationSub;
  StreamSubscription<AudioInterruptionEvent>? _interruptionSub;
  StreamSubscription<void>? _becomingNoisySub;

  NasAudioHandler(this._player) {
    _stateSub = _player.playerStateStream.listen(_onPlayerStateChanged);
    _positionSub = _player.positionStream.listen(_onPositionChanged);
    _durationSub = _player.durationStream.listen(_onDurationChanged);
    _initAudioSession();
  }

  Future<void> _initAudioSession() async {
    try {
      final session = await AudioSession.instance;
      _interruptionSub = session.interruptionEventStream.listen((event) {
        switch (event.type) {
          case AudioInterruptionType.pause:
          case AudioInterruptionType.duck:
            onAudioFocusChange(AudioFocusState.transient);
            break;
          case AudioInterruptionType.unknown:
            onAudioFocusChange(AudioFocusState.lost);
            break;
        }
      });
      _becomingNoisySub = session.becomingNoisyEventStream.listen((_) {
        onAudioFocusChange(AudioFocusState.lost);
      });
    } catch (_) {
    }
  }
  ```

  当前 dispose（:260-264）：
  ```dart
  void dispose() {
    _stateSub?.cancel();
    _positionSub?.cancel();
    _durationSub?.cancel();
  }
  ```

  改为：
  ```dart
  void dispose() {
    _stateSub?.cancel();
    _positionSub?.cancel();
    _durationSub?.cancel();
    _interruptionSub?.cancel();
    _becomingNoisySub?.cancel();
  }
  ```

  边界裁决：
  - `AudioSession.instance` 首次获取失败（PlatformException）→ catch 静默，焦点功能降级为不可用，不影响核心播放
  - 多个 handler 实例 → 每个独立订阅，dispose 各自 cancel
  - dispose 时 `_initAudioSession` 的 Future 未完成 → subscription 仍为 null，`?.cancel()` 是 no-op
  - interruptionEventStream 在 iOS/Android 上事件类型覆盖差异 → 按 `pause`/`duck` → transient, `unknown` → lost 映射

- **[BUG-22-S2]** 焦点处理内部改用 `this.play()`/`this.pause()`（带超时）(`status: new`)
  ```
  Given onAudioFocusChange 被调用
  When  焦点状态为 lost 或 gained
  Then  内部调用走带 5s 超时的 this.play()/this.pause() 而非直调 _player
  否定断言:
    - 不直调 _player.play() 或 _player.pause()
    - 不绕过 BUG-06 的超时保护
    - 不改变状态机 updateAudioFocus 的转移逻辑
  ```
  Code evidence: `audio_handler.dart:181`（`_player.pause()`）
  Code evidence: `audio_handler.dart:188`（`_player.play()`）
  对照：`audio_handler.dart:200`（`_player.play().timeout(...)` 在 `this.play()` 内）
  对照：`audio_handler.dart:211`（`_player.pause().timeout(...)` 在 `this.pause()` 内）

  **修改指令 — `lib/core/services/audio_handler.dart`（onAudioFocusChange）**

  位置：`:174-191`

  当前代码（:174-191）：
  ```dart
  void onAudioFocusChange(AudioFocusState focus) {
    final next = _config.updateAudioFocus(focus);
    _updateConfig(next);

    // Act on the focus change.
    switch (focus) {
      case AudioFocusState.lost:
        _player.pause();
      case AudioFocusState.transient:
        // Ducking handled by platform — no explicit action needed here.
        break;
      case AudioFocusState.gained:
        // Resume if the state machine says audio should be active.
        if (_config.isAudioActive && !_player.playing) {
          _player.play();
        }
    }
  }
  ```

  改为：
  ```dart
  void onAudioFocusChange(AudioFocusState focus) {
    final next = _config.updateAudioFocus(focus);
    _updateConfig(next);

    switch (focus) {
      case AudioFocusState.lost:
        pause();
      case AudioFocusState.transient:
        break;
      case AudioFocusState.gained:
        if (_config.isAudioActive && !_player.playing) {
          play();
        }
    }
  }
  ```

  边界裁决：
  - `this.pause()` 和 `this.play()` 是 async 返回 `Future<void>`，但此处 fire-and-forget 调用 — 内部已有 try/catch 兜底超时，不会产生 unhandled rejection
  - `_config.isAudioActive` 在 `updateAudioFocus(gained)` 之后检查 — 状态机先更新再判定，逻辑不变
  - transient 状态不触发动作 — ducking 由平台层处理（audio_session 默认行为）
  - 频繁焦点切换（gained → lost → gained）→ 每次走完整 pause/play 路径，超时保护确保不挂起

  **测试文件位置：`test/features/player/bug_bug22_repro_test.dart`**

---

## §4 不变量

- **[BUG-22-INV1]** `onAudioFocusChange` 的所有播放控制调用走带超时的 `this.play()`/`this.pause()`，不直调 `_player`
  证据：`audio_handler.dart:200,211`（play/pause override 带 5s timeout）→ `:181,188`（修复目标：替换为 this.play/this.pause）

- **[BUG-22-INV2]** NasAudioHandler 在 dispose 时取消所有 audio_session 订阅
  证据：`audio_handler.dart:260-264`（dispose 清理 player 订阅）→ 新增的 `_interruptionSub`/`_becomingNoisySub` 同样需 cancel

- **[BUG-22-INV3]** audio_session 订阅失败不阻塞核心播放功能
  证据：`audio_session: any` 已在 `pubspec.yaml:38` 声明；`AudioSession.instance` 可能在测试环境不可用，需 try/catch 降级

---

## §5 测试规约

### 5.2 测试 ID 派生清单

```
BUG-22-S1           # audio_session interruptionEventStream 接入
BUG-22-S2           # 焦点处理改用 this.play()/this.pause()
BUG-22-INV1         # onAudioFocusChange 无 _player 直调
BUG-22-INV2         # dispose 取消所有订阅
BUG-22-INV3         # audio_session 初始化失败不阻塞
```

### 5.4 测试文件位置

| 测试 ID | 文件路径 |
|---------|----------|
| BUG-22-S1 | `test/features/player/bug_bug22_repro_test.dart` |
| BUG-22-S2 | `test/features/player/bug_bug22_repro_test.dart` |
| BUG-22-INV1 | `test/features/player/bug_bug22_repro_test.dart` |
| BUG-22-INV2 | `test/features/player/bug_bug22_repro_test.dart` |
| BUG-22-INV3 | `test/features/player/bug_bug22_repro_test.dart` |

---

## §7 跨模块影响

| 模块 | 影响 | 说明 |
|------|------|------|
| PLY | 正面 | 音频焦点处理生效，通话/通知中断时正确暂停/恢复 |
| CON | 无 | 不涉及连接 |
| BRW | 无 | 不涉及浏览 |

`audio_session` 包已在 `pubspec.yaml` 声明（`:38`），无需新增依赖。

---

## §8 平台特性与手动 QA

**需要手动 QA**：
- `manual_qa_required: true` — `audio_session` 依赖平台 AudioFocusManager，`flutter test` 中 `AudioSession.instance` 不可用
- 手动验证场景：来电时暂停、通话结束恢复、耳机拔出暂停
- 自动化覆盖：INV1（grep `_player.play`/`_player.pause` 不在 onAudioFocusChange 内）、INV2（dispose 方法静态分析）

---

## §9 dev-status.json 条目对照

见统一更新：`docs/dev/dev-status.json`。

---

## §10 changelog

- 2026-07-27: 创建 BUG-22 spec（基于 cr-20260724-0110.md SVC2 + SVC3）
