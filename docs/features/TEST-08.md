# TEST-08 — 服务层测试缺口（SVC8+SVC9+SVC10）

> 来源：`docs/cr/cr-20260724-0110.md` SVC8 (line 816-818) + SVC9 (line 820-823) + SVC10 (line 825-828)
> dev-plan 流程：TEST-GAP 补测模式

---

## §0 头部元数据

```yaml
id: TEST-08
name: 服务层测试缺口（SVC8+SVC9+SVC10）
priority: P1
status: draft
created_at: 2026-07-27
last_updated: 2026-07-27
spec_anchored_files:
  - lib/core/services/background_service.dart
  - lib/core/services/audio_handler.dart
  - lib/core/services/storage_utils.dart
  - lib/core/contracts/audio_handler_contract.dart
cross_module_impacts: [PLY, BRW, CON]
parent_feature: null
manual_qa_required: true
```

---

## §1 用户视角

### 1.0 原始需求

> cr-20260724-0110.md SVC8：`background_service.dart` 零测试覆盖。
> cr-20260724-0110.md SVC9：`audio_handler.dart` 大部分逻辑未测——仅 play/pause/stop 超时覆盖。seek/setSpeed（SVC1 原因）、setMediaItemFromPath、onAudioFocusChange、skipToNext/Previous、onTaskRemoved、_onPlayerStateChanged、dispose 全部零覆盖。根因：IAudioHandler 契约是死接口 → 无 fake 可注入。
> cr-20260724-0110.md SVC10：`storage_utils.dart:38-48` safeStorageDelete 未测。bug_10_test header 声称覆盖 delete 但仅有 read/write 用例。

### 1.1 这一功能干什么（一句话）

补齐服务层三类测试缺口：MethodChannel 调用测试、AudioHandler 核心逻辑测试（依赖 REF-02 启用 IAudioHandler）、safeStorageDelete 测试。

### 1.2 用户期望的场景

| ID | 你看到的样子 | 期望行为 |
|----|----|----|
| U1 | Android 按返回键 | moveTaskToBack 成功调用 MethodChannel |
| U2 | MethodChannel 抛 PlatformException | 不崩溃（BUG-32 修复后） |
| U3 | 非 Android 平台按返回键 | no-op |
| U4 | 音频焦点丢失 | 播放暂停 |
| U5 | 音频焦点恢复 | 按配置恢复播放 |
| U6 | 用户滑动移除通知 | 播放停止 |
| U7 | seek/setSpeed 调用 | 转发到 AudioPlayer |
| U8 | safeStorageDelete 超时 | 抛出 TimeoutException |
| U9 | safeStorageDelete 正常 | 删除成功 |

---

## §2 已实现的功能骨架

### 2.1 文件与分层

| 层 | 文件 | 行数 | 角色 |
|---|---|---|---|
| Service | `lib/core/services/background_service.dart` | 11 | moveTaskToBack MethodChannel |
| Service | `lib/core/services/audio_handler.dart` | 265 | NasAudioHandler（BaseAudioHandler） |
| Service | `lib/core/services/storage_utils.dart` | 48 | safeStorageRead/Write/Delete |
| Contract | `lib/core/contracts/audio_handler_contract.dart` | 84 | IAudioHandler 抽象接口 |
| 测试 | `test/features/coverage/` | — | 覆盖率相关测试 |

### 2.2 关键代码段

| 区域 | 行号 | 说明 |
|---|---|---|
| moveTaskToBack | `background_service.dart:9-10` | `_channel.invokeMethod('moveTaskToBack')` |
| seek 无超时 | `audio_handler.dart:229` | `_player.seek(position)` |
| setSpeed 无超时 | `audio_handler.dart:232` | `_player.setSpeed(speed)` |
| setMediaItemFromPath | `audio_handler.dart:109-117` | 构建 MediaItem |
| onAudioFocusChange | `audio_handler.dart:174-191` | focus lost → pause, gained → resume |
| skipToNext | `audio_handler.dart:235-238` | callback + super |
| onTaskRemoved | `audio_handler.dart:247-256` | stop + 5s timeout |
| _onPlayerStateChanged | `audio_handler.dart:75-93` | sync config + build controls |
| dispose | `audio_handler.dart:260-264` | cancel 3 subscriptions |
| safeStorageDelete | `storage_utils.dart:38-48` | delete + 5s timeout + rethrow |

---

## §3 行为规约

### 3.1 补测行为

- **[TEST-08-S1]** moveTaskToBack 成功调用 (`status: new`)
  ```
  Given Android 平台，MethodChannel 已注册
  When  moveTaskToBack() 被调用
  Then  MethodChannel 收到 'moveTaskToBack' 方法调用
  否定断言:
    - 不在非 Android 平台调用 MethodChannel（当前为 no-op）
    - 不在调用时抛未处理异常
  ```
  Code evidence: `lib/core/services/background_service.dart:9-10`

- **[TEST-08-S2]** moveTaskToBack PlatformException 不崩溃 (`status: new`)
  ```
  Given MethodChannel 抛 PlatformException（Activity 已销毁）
  When  moveTaskToBack() 被调用
  Then  不抛未处理异步错误（BUG-32 修复验证）
  否定断言:
    - 不在 PlatformException 时产生 unhandled async error
    - 不改变正常路径行为
  ```
  Code evidence: `background_service.dart:10`（BUG-32 修复后 `catchError`）

- **[TEST-08-S3]** IAudioHandler seek 转发 (`status: new`)
  ```
  Given FakeAudioHandler implements IAudioHandler
  When  seek(Duration(seconds: 30)) 被调用
  Then  底层 AudioPlayer.seek(Duration(seconds: 30)) 被调用
  否定断言:
    - 不在 seek 时阻塞超过超时时间（SVC1：seek 无超时保护待 REF-02 后补）
    - 不忽略 seek 调用
  ```
  Code evidence: `lib/core/services/audio_handler.dart:229`; `lib/core/contracts/audio_handler_contract.dart:48`

- **[TEST-08-S4]** IAudioHandler onTaskRemoved → 停止播放 (`status: new`)
  ```
  Given NasAudioHandler 正在播放
  When  onTaskRemoved() 被调用（用户滑动移除通知）
  Then  AudioPlayer.stop() 被调用
  And   config 更新为 stopped 状态
  否定断言:
    - 不在 onTaskRemoved 后继续播放
    - 不在 stop 超时时抛异常（5s timeout 保护）
  ```
  Code evidence: `audio_handler.dart:247-256`

- **[TEST-08-S5]** IAudioHandler onAudioFocusChange lost → 暂停 (`status: new`)
  ```
  Given NasAudioHandler 正在播放
  When  onAudioFocusChange(AudioFocusState.lost) 被调用
  Then  AudioPlayer.pause() 被调用
  And   config 更新反映 focus lost
  否定断言:
    - 不在 focus lost 后继续播放
    - 不在 transient focus 时暂停（仅 lost 触发暂停）
  ```
  Code evidence: `audio_handler.dart:174-191`（`AudioFocusState.lost → _player.pause()`）

- **[TEST-08-S6]** IAudioHandler onAudioFocusChange gained → 仅更新 config，不自动恢复播放（`status: new`）
  ```
  Given NasAudioHandler 处于 paused 状态，config.isAudioActive == true
  When  onAudioFocusChange(AudioFocusState.gained) 被调用
  Then  AudioPlayer.play() 不被调用（gained 分支已由 BUG-22 D1 删除恢复逻辑——2026-08-09 审计锚定，audio_handler.dart gained → break 无副作用）
  And   isAudioActive 状态仍为 true
  否定断言:
    - 不在 config.isAudioActive == false 时触发任何播放动作
    - 不在任何 gained 场景下重复调用 play()（验证 play 恰一次 = setup 装配次数）
  ```
  Code evidence: `audio_handler.dart:243-254`（`gained → break`，恢复分支被 BUG-22 D1 移除；原 :185-189 `if (isAudioActive && !playing) play()` 已不存在）
  Test anchoring: `test/core/services/audio_handler_test.dart` TEST-08-S6 用例（verify play 恰一次 = setup 的，isAudioActive=false 时 verifyNever(play)）

- **[TEST-08-S7]** safeStorageDelete 正常删除 (`status: new`)
  ```
  Given FakeSecureStorage 中存有 key "test_key"
  When  safeStorageDelete(storage, key: "test_key") 被调用
  Then  storage 中 "test_key" 被移除
  否定断言:
    - 不在正常删除时抛异常（当前 SVC10 问题：零测试覆盖）
    - 不改变 safeStorageRead / safeStorageWrite 行为
  ```
  Code evidence: `lib/core/services/storage_utils.dart:38-48`

- **[TEST-08-S8]** safeStorageDelete 超时 → TimeoutException (`status: new`)
  ```
  Given FakeSecureStorage.delete 挂起超过 5s
  When  safeStorageDelete(storage, key: "test_key") 被调用
  Then  抛出 TimeoutException
  否定断言:
    - 不在超时时返回 void 静默成功
    - 不在超时时返回 null（delete 为 void 返回类型）
  ```
  Code evidence: `storage_utils.dart:42-47`（`.timeout(const Duration(seconds: 5))` + rethrow）

---

## §4 不变量

- **[TEST-08-INV1]** moveTaskToBack 不产生未处理异步错误
  证据：`background_service.dart:10`（BUG-32 修复 `catchError`）

- **[TEST-08-INV2]** safeStorageDelete 超时 rethrow（与 safeStorageWrite 一致）
  证据：`storage_utils.dart:46`（`rethrow`）

---

## §5 测试规约

### 5.1 现有测试清单

| 测试文件 | 覆盖 | 备注 |
|---|---|---|
| 无 | background_service.dart | 零测试覆盖（SVC8） |
| 无 | audio_handler.dart seek/setSpeed/focus/skip/dispose | 仅 play/pause/stop 超时覆盖（SVC9） |
| 无 | storage_utils.dart safeStorageDelete | 零测试覆盖（SVC10） |

### 5.2 测试 ID 派生清单

```
TEST-08-S1          # moveTaskToBack 成功
TEST-08-S2          # moveTaskToBack PlatformException
TEST-08-S3          # IAudioHandler seek
TEST-08-S4          # onTaskRemoved
TEST-08-S5          # onAudioFocusChange lost
TEST-08-S6          # onAudioFocusChange gained
TEST-08-S7          # safeStorageDelete 正常
TEST-08-S8          # safeStorageDelete 超时
TEST-08-INV1        # moveTaskToBack 无 unhandled error
TEST-08-INV2        # safeStorageDelete 超时 rethrow
```

### 5.3 测试覆盖盲点

| 未覆盖 ID | 现状 | 应补偿方式 |
|---|---|---|
| TEST-08-S1~S2 | 零测试 | Mock MethodChannel → 验证成功 + PlatformException 处理 |
| TEST-08-S3~S6 | IAudioHandler 为死契约 | REF-02 启用后创建 FakeAudioHandler → 测试核心逻辑 |
| TEST-08-S7~S8 | safeStorageDelete 零测试 | FakeSecureStorage + 模拟挂起 → 断言正常删除 + 超时 |

### 5.4 测试文件位置

| 测试 ID | 文件路径 |
|---|---|
| TEST-08-S1~S2 | `test/core/services/background_service_test.dart`（新建） |
| TEST-08-S3~S6 | `test/core/services/audio_handler_test.dart`（新建，依赖 REF-02） |
| TEST-08-S7~S8 | `test/features/coverage/svc_storage_utils_test.dart` 或 `test/core/services/storage_utils_test.dart`（新建） |

### 5.5 依赖

| 依赖 spec | 原因 |
|---|---|
| REF-02 | IAudioHandler 死契约需启用后才能创建 FakeAudioHandler |

---

## §6 算法样例

不适用——本 spec 为补测，无新算法。

---

## §7 跨模块影响

| 其它 feature | 影响点 | 需要补的回归断言 |
|---|---|---|
| PLY | NasAudioHandler 被 player_provider 使用 | 补测不改变现有 play/pause/stop 超时行为 |
| CON | safeStorageRead/Write/Delete 被 connection_provider 使用 | 补测不改变现有超时语义 |
| BRW | safeStorageRead 被 browser_provider 使用 | 同上 |

---

## §8 平台特性与手动 QA

| 风险 | 近似测试方案 | 测不了 → 进 mqa-backlog |
|---|---|---|
| MethodChannel 原生层行为（moveTaskToBack） | Mock MethodChannel 验证调用 | 真机验证：Activity 销毁后 moveTaskToBack 是否导致 crash |
| audio_service 通知栏控件 | IAudioHandler 单元测试验证逻辑 | 真机验证：通知栏 play/pause/seek 实际响应 |
| AudioFocus 状态机 | 单元测试 onAudioFocusChange 分支 | 真机验证：电话/其他 app 播放时是否正确暂停/恢复 |

---

## §9 dev-status.json 条目对照

见统一更新：`docs/dev/dev-status.json`。

---

## §10 changelog

- 2026-07-27: 创建 TEST-08 spec（基于 cr-20260724-0110.md SVC8 + SVC9 + SVC10）
- 2026-08-09: 审计同步 §3 S6——gained 恢复分支已被 BUG-22 D1 删除（生产 audio_handler.dart:243-254 `gained → break`），spec 断言改为"仅更新 config 不恢复播放"，与测试锚定一致（同 TEST-07-S5 617e874 先例）
