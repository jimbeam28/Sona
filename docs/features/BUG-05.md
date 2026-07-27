# BUG-05 — 通知/锁屏 play() 缺 completed 态 seek(0) 恢复

> 来源：`docs/cr/cr-20260724-0110.md` PLY2
> dev-plan 流程：Bug 修复模式

---

## §0 头部元数据

```yaml
id: BUG-05
name: 通知/锁屏 play() 缺 completed 态 seek(0) 恢复
priority: P1
status: draft
created_at: 2026-07-27
last_updated: 2026-07-27
spec_anchored_files:
  - lib/core/services/audio_handler.dart
  - lib/features/player/widgets/playback_controls.dart
  - lib/features/player/widgets/mini_player_bar.dart
cross_module_impacts: []
parent_feature: Player
manual_qa_required: true
```

---

## §1 用户视角

### 1.0 原始需求

> cr-20260724-0110.md PLY2：末曲播完后台/锁屏点通知"播放"，NasAudioHandler.play() 直调 _player.play() 无 seek(0)，Android just_audio completed 态不响应 play() → 后台播放卡死。

### 1.1 这一功能干什么（一句话）

修复通知/锁屏播放按钮在曲目播完后无法恢复播放的缺陷。

### 1.2 用户期望的场景

| ID | 你看到的样子 | 期望行为 |
|----|----|----|
| U1 | 末曲自然播完，锁屏/通知栏点"播放" | 从头开始播放当前曲目 |
| U2 | 曲目播完，耳机线控按播放 | 从头开始播放当前曲目 |

---

## §2 已实现的功能骨架

### 2.1 文件与分层

| 层 | 文件 | 行数 | 角色 |
|---|---|---|---|
| Core Services | `lib/core/services/audio_handler.dart` | ~260 | NasAudioHandler — audio_service BaseAudioHandler |
| UI | `lib/features/player/widgets/playback_controls.dart` | ~100 | 全屏播放控件（有 completed 恢复） |
| UI | `lib/features/player/widgets/mini_player_bar.dart` | ~250 | 迷你播放器（有 completed 恢复） |

---

## §3 行为规约

### 3.1 修复后行为

- **[BUG-05-S1]** NasAudioHandler.play() 在 completed 态先 seek(0) (`status: new`)
  ```
  Given _player.processingState == ProcessingState.completed
  When  play() 被调用（通知栏/锁屏/耳机线控）
  Then  先 seek(Duration.zero) 再 play()
  否定断言:
    - 不直接调 _player.play() 跳过 seek（当前 BUG 行为）
    - seek 失败不阻塞 play 调用（try/catch 包裹 seek）
  ```
  Code evidence: `lib/core/services/audio_handler.dart:196-204`（play() 方法无 completed 检查）
  对照：`lib/features/player/widgets/playback_controls.dart:77-80`（有 completed 检查 + seek(0)）
  对照：`lib/features/player/widgets/mini_player_bar.dart:231-234`（有 completed 检查 + seek(0)）

  **修改指令：**

  **文件：** `lib/core/services/audio_handler.dart:196-204`

  **当前代码：**
  ```dart
  @override
  Future<void> play() async {
    final next = _config.handleMediaControl(MediaControlAction.play);
    _updateConfig(next);
    try {
      await _player.play().timeout(const Duration(seconds: 5));
    } catch (_) {
      // Timeout or platform error — silently ignore
    }
  }
  ```

  **修改为：**
  ```dart
  @override
  Future<void> play() async {
    final next = _config.handleMediaControl(MediaControlAction.play);
    _updateConfig(next);
    try {
      if (_player.processingState == ProcessingState.completed) {
        try {
          await _player.seek(Duration.zero);
        } catch (_) {
          // seek failed — still attempt play
        }
      }
      await _player.play().timeout(const Duration(seconds: 5));
    } catch (_) {
      // Timeout or platform error — silently ignore
    }
  }
  ```

  **边界决策：**
  - seek 失败（如 platform channel 异常）→ 不阻塞 play 调用，内层 try/catch 吞掉 seek 异常后继续执行 play
  - processingState != completed → 跳过 seek，直接 play（保持原有行为）
  - processingState == completed 且 seek 成功 → seek(Duration.zero) 后再 play

  **测试文件：** `test/features/player/bug_05_handler_play_test.dart`（避免与旧 BUG-05 SerializedRequestGate 测试冲突）

---

## §4 不变量

- **[BUG-05-INV1]** 所有 play() 入口（in-app + handler）对 completed 态行为一致
  证据：`playback_controls.dart:77-80` + `mini_player_bar.dart:231-234`（已有）→ `audio_handler.dart:196-204`（待补）

---

## §5 测试规约

### 5.2 测试 ID 派生清单

```
BUG-05-S1           # completed 态 seek(0) 恢复
BUG-05-INV1         # 三入口一致性
```

### 5.3 测试覆盖盲点

| 未覆盖 ID | 现状 | 应补偿方式 |
|---|---|---|
| BUG-05-S1 | audio_handler 测试仅覆盖 play/pause/stop 超时 | 补 mock player completed 态 → handler.play() → verify seek(Duration.zero) 被调用 |

### 5.4 测试文件位置

| 测试 ID | 文件路径 |
|---|---|
| BUG-05-S1 | `test/features/player/bug_05_handler_play_test.dart` |
| BUG-05-INV1 | `test/features/player/bug_05_handler_play_test.dart` |

---

## §7 跨模块影响

无跨模块影响。修复局限在 audio_handler.dart 单文件。

---

## §8 平台特性与手动 QA

| 风险 | 近似测试方案 | 测不了 → 进 mqa-backlog |
|---|---|---|
| Android just_audio completed 态是否确实忽略 play() | mock 模拟 processingState=completed | 真机验证：末曲播完 → 锁屏播放 → 从头播放 |
| 耳机线控触发 handler.play() 路径 | 单元测试覆盖 handler.play() | 真机验证：耳机按键 → 恢复播放 |

---

## §9 dev-status.json 条目对照

见统一更新：`docs/dev/dev-status.json`。

---

## §10 changelog

- 2026-07-27: 创建 BUG-05 spec（基于 cr-20260724-0110.md PLY2）
