# BUG-17 — seek/setSpeed 无超时保护

> 来源：`docs/cr/cr-20260724-0110.md` SVC1
> dev-plan 流程：Bug 修复模式

---

## §0 头部元数据

```yaml
id: BUG-17
name: seek/setSpeed 无超时保护
priority: P1
status: draft
created_at: 2026-07-27
last_updated: 2026-07-27
spec_anchored_files:
  - lib/core/services/audio_handler.dart
cross_module_impacts: []
parent_feature: Player
manual_qa_required: true
```

---

## §1 用户视角

### 1.0 原始需求

> cr-20260724-0110.md SVC1：audio_handler.dart seek/setSpeed 直通 _player 无 .timeout()，而 play/pause/stop 均有 5s 超时+catch。Android platform-channel 竞争时 seek 挂起 → 通知栏进度条拖动卡死。

### 1.1 这一功能干什么（一句话）

修复通知栏/锁屏 seek 和 setSpeed 操作可能永久挂起的缺陷。

### 1.2 用户期望的场景

| ID | 你看到的样子 | 期望行为 |
|----|----|----|
| U1 | 通知栏拖动进度条 | seek 操作 5s 内完成或静默失败，不卡死 |
| U2 | 锁屏/Android Auto 切换播放速度 | setSpeed 操作 5s 内完成或静默失败 |

---

## §2 已实现的功能骨架

### 2.1 文件与分层

| 层 | 文件 | 行数 | 角色 |
|---|---|---|---|
| Core Services | `lib/core/services/audio_handler.dart` | ~260 | NasAudioHandler |

---

## §3 行为规约

### 3.1 修复后行为

- **[BUG-17-S1]** seek 补 .timeout(5s) + catch (`status: new`)
  ```
  Given NasAudioHandler.seek() 被调用
  When  _player.seek() Future 挂起超过 5 秒
  Then  timeout 触发，catch 静默处理（与 play/pause/stop 同模式）
  否定断言:
    - 不裸调 _player.seek() 无超时（当前 BUG 行为）
    - 不抛未处理异常
  ```
   Code evidence: `lib/core/services/audio_handler.dart:229`（seek 直通无超时）
   对照：`audio_handler.dart:200`（play 有 .timeout(5s) + catch）

   **修改指令 — `lib/core/services/audio_handler.dart`（seek）**

   位置：`:228-229`

   当前代码（:228-229）：
   ```dart
     @override
     Future<void> seek(Duration position) => _player.seek(position);
   ```

   改为：
   ```dart
     @override
     Future<void> seek(Duration position) async {
       try {
         await _player.seek(position).timeout(const Duration(seconds: 5));
       } catch (_) {
         // Timeout or platform error — silently ignore
       }
     }
   ```

   边界裁决：
   - timeout 触发 → catch 静默处理，与 play/pause/stop 行为一致（`:200-203`）
   - seek 不涉及 `_config.handleMediaControl` 状态转换 → 不需要 `_updateConfig` 调用（与 play/pause/stop 不同）
   - 超时后 _player 内部状态可能不一致 → 由 just_audio 内部管理，下次 seek/play 会恢复
   - 5 秒超时常量与 play/pause/stop 保持一致（`const Duration(seconds: 5)`）

   **测试文件位置：`test/features/player/bug_17_repro_test.dart`**

- **[BUG-17-S2]** setSpeed 补 .timeout(5s) + catch (`status: new`)
  ```
  Given NasAudioHandler.setSpeed() 被调用
  When  _player.setSpeed() Future 挂起超过 5 秒
  Then  timeout 触发，catch 静默处理
  否定断言:
    - 不裸调 _player.setSpeed() 无超时（当前 BUG 行为）
  ```
   Code evidence: `lib/core/services/audio_handler.dart:232`（setSpeed 直通无超时）

   **修改指令 — `lib/core/services/audio_handler.dart`（setSpeed）**

   位置：`:231-232`

   当前代码（:231-232）：
   ```dart
     @override
     Future<void> setSpeed(double speed) => _player.setSpeed(speed);
   ```

   改为：
   ```dart
     @override
     Future<void> setSpeed(double speed) async {
       try {
         await _player.setSpeed(speed).timeout(const Duration(seconds: 5));
       } catch (_) {
         // Timeout or platform error — silently ignore
       }
     }
   ```

   边界裁决：
   - timeout 触发 → catch 静默处理，与 play/pause/stop 行为一致
   - setSpeed 不涉及 `_config.handleMediaControl` 状态转换 → 不需要 `_updateConfig` 调用
   - speed 参数为 double（如 0.5, 1.0, 2.0）→ 不影响 timeout/catch 逻辑
   - 超时后 _player 速度可能停留在中间状态 → 由 just_audio 内部管理，下次 setSpeed 会覆盖

   **测试文件位置：`test/features/player/bug_17_repro_test.dart`**

---

## §4 不变量

- **[BUG-17-INV1]** 所有 NasAudioHandler 平台调用均有超时保护
  证据：`audio_handler.dart:200`（play）, `:211`（pause）, `:222`（stop）, `:252`（onTaskRemoved）→ `:229,:232`（seek/setSpeed，修复目标）

---

## §5 测试规约

### 5.2 测试 ID 派生清单

```
BUG-17-S1 S2          # seek/setSpeed 超时
BUG-17-INV1           # 全平台调用超时保护
```

### 5.4 测试文件位置

| 测试 ID | 文件路径 |
|---------|----------|
| BUG-17-S1 | `test/features/player/bug_17_repro_test.dart` |
| BUG-17-S2 | `test/features/player/bug_17_repro_test.dart` |
| BUG-17-INV1 | `test/features/player/bug_17_repro_test.dart`（全方法超时扫描用例） |

---

## §7 跨模块影响

无跨模块影响。修复局限在 audio_handler.dart。

---

## §8 平台特性与手动 QA

| 风险 | 近似测试方案 | 测不了 → 进 mqa-backlog |
|---|---|---|
| Android platform-channel 竞争导致 seek 挂起 | mock player seek 返回永不完成的 Future → 验证 5s 后 timeout | 真机验证：弱网/高负载下拖动通知栏进度条 |

---

## §9 dev-status.json 条目对照

见统一更新：`docs/dev/dev-status.json`。

---

## §10 changelog

- 2026-07-27: 创建 BUG-17 spec（基于 cr-20260724-0110.md SVC1）
