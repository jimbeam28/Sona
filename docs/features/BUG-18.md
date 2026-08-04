# BUG-18 — loadAndPlay 12s 轮询等待播放开始

> 来源：`docs/cr/cr-2026-06-28.md` FRAGILE-02 (F2)
> dev-plan 流程：Bug 修复模式

---

## §0 头部元数据

```yaml
id: BUG-18
name: loadAndPlay 12s 轮询等待播放开始
priority: P1
status: draft
created_at: 2026-07-27
last_updated: 2026-08-05
spec_anchored_files:
  - lib/features/player/domain/playback_orchestrator.dart
cross_module_impacts: [PLY]
parent_feature: null
manual_qa_required: false
```

---

## §1 用户视角

### 1.0 原始需求

> cr-2026-06-28.md FRAGILE-02: loadAndPlay 轮询等待 player.playing，每 200ms 检查一次，最多 60 次（12 秒）。大 FLAC 文件通过慢速 NAS 缓冲可能超时，即使播放恰好在超时后 1 秒开始。

### 1.1 这一功能干什么（一句话）

替换 12s 固定轮询为 `playerStateStream` 流式等待，消除固定超时窗口，播放开始时立即响应。

### 1.2 用户期望的场景

| ID | 你看到的样子 | 期望行为 |
|----|----|----|
| U1 | 大 FLAC 通过慢 NAS 加载，需要 >12s 才开始播放 | 播放开始后正常继续，不因固定轮询超时失败 |
| U2 | 正常文件快速加载（<1s） | 行为不变，等待时间更短（立即响应 vs 最多 200ms 延迟） |
| U3 | 文件确实无法播放（网络断开、格式错误） | 超时后仍返回 failed，行为与修复前一致 |

---

## §2 已实现的功能骨架

### 2.1 文件与分层

| 层 | 文件 | 行数 | 角色 |
|---|---|---|---|
| Domain | `lib/features/player/domain/playback_orchestrator.dart` | 468 | 播放编排：load/skip/remove/saveProgress |
| Contract | `lib/core/contracts/audio_player_contract.dart` | ~30 | IAudioPlayer 抽象（含 playerStateStream） |
| Test | `test/features/player/ref_14_test.dart` | 605 | PlaybackOrchestrator 现有测试（28 用例） |
| Test Helper | `test/helpers/mock_audio_player.dart` | 447 | MockAudioPlayer（支持 playerStateStream 桩） |

### 2.2 关键代码段

| 区域 | 行号 | 说明 |
|---|---|---|
| 轮询等待 | `playback_orchestrator.dart:210-216` | `for` 循环 60 次 × 200ms 延迟检查 `player.playing` |
| 超时兜底 | `playback_orchestrator.dart:217-223` | 循环后二次检查 + 失败时 stop + return failed |
| playerStateStream 已有使用 | `playback_orchestrator.dart:446` | `_startPauseSaveListener` 已用同一 stream 做暂停检测 |
| playerStateStream 接口 | `audio_player_contract.dart:21` | `Stream<PlayerState> get playerStateStream;` |
| PlayerState 结构 | `just_audio` 库 | `PlayerState(bool playing, ProcessingState processingState)` |

---

## §3 行为规约

### 3.1 BUG-18-S1: stream-based wait replacing polling (`status: new`)

```
Given loadAndPlay 已调用 player.setAudioSource 和 unawaited(player.play())
When  等待播放开始
Then  监听 player.playerStateStream，收到 playing==true 时立即继续
      超时（30s）内未收到 playing==true → stop + return failed
否定断言:
  - 不使用 for 循环 + Future.delayed 轮询 player.playing（当前 BUG 行为）
  - 不缩短超时时间（新超时 ≥ 原 12s）
  - 不在收到 playing==true 后仍继续等待（立即响应）
```
Code evidence: `lib/features/player/domain/playback_orchestrator.dart:207-223`

**修改指令：**

**文件：** `lib/features/player/domain/playback_orchestrator.dart:207-223`

**当前代码：**
```dart
          // Start playback (don't await — may never complete).
          unawaited(player.play());
          var playStarted = false;
          for (int i = 0; i < 60; i++) {
            await Future<void>.delayed(const Duration(milliseconds: 200));
            if (player.playing) {
              playStarted = true;
              break;
            }
          }
          if (!playStarted && player.playing) {
            playStarted = true;
          }
          if (!playStarted) {
            await player.stop();
            return const TrackLoadResult.failed();
          }
```

**修改为：**
```dart
          // Start playback (don't await — may never complete).
          unawaited(player.play());

          // Wait for playing state via stream (replaces polling loop).
          // P4: play() Future may never complete, so we rely on
          // playerStateStream instead.
          final playStarted = await () async {
            // Fast path: already playing (e.g. stream emits before subscribe).
            if (player.playing) return true;
            final completer = Completer<bool>();
            late StreamSubscription<PlayerState> sub;
            sub = player.playerStateStream.listen((state) {
              if (state.playing) {
                completer.complete(true);
                sub.cancel();
              }
            });
            // Ensure subscription is cancelled on timeout too.
            completer.future.whenComplete(() => sub.cancel());
            try {
              return await completer.future
                  .timeout(const Duration(seconds: 30));
            } on TimeoutException {
              return false;
            }
          }();

          if (!playStarted) {
            await player.stop();
            return const TrackLoadResult.failed();
          }
```

**边界裁决：**
- `player.playing` 在订阅前已为 true → 立即返回 true（fast path，不等 stream 事件）
- stream 在 30s 内发出 `playing==true` → 立即 complete，不等超时（响应速度 >> 200ms 轮询间隔）
- 30s 超时 → 返回 false → stop + failed（与原 12s 超时语义一致，但窗口更宽）
- stream 在等待期间报错 → Completer 永不 complete → 超时兜底（不 crash）
- `player.playerStateStream` 是 broadcast stream → 订阅不影响其他 listener（`_startPauseSaveListener` 同 stream 正常工作）
- 新请求 superseded → gate 机制在 stream 等待之后检查（:224-226），行为不变

**测试文件：** `test/features/player/bug_18_stream_wait_test.dart`

---

## §4 不变量

- **[BUG-18-INV1]** 等待机制不依赖固定轮询间隔
  证据：修复后使用 `playerStateStream.listen()` 事件驱动，无 `Future.delayed` 循环
  Code evidence: 修复后 `playback_orchestrator.dart:210-232`

- **[BUG-18-INV2]** 超时时间 ≥ 原 12s（不缩短）
  证据：新超时设为 30s（> 12s），覆盖原 60×200ms = 12s 窗口

---

## §5 测试规约

### 5.1 现有测试清单

| 测试文件 | 覆盖 | 备注 |
|---|---|---|
| `test/features/player/ref_14_test.dart` | loadAndPlay 正常流程、无连接、无密码、skip、remove | 28 用例；`player.playing` 桩为 `thenReturn(true)` 直接跳过轮询 |
| `test/features/player/ply_02_test.dart` | loadAndPlay 边界场景 | 通过桩 `player.playing = true` 绕过轮询 |
| `test/features/player/bug_06_test.dart` | handler play/pause/stop 超时 | 使用 `MockAudioPlayer` + `playerStateStream` 桩 |

### 5.2 测试 ID 派生清单

```
BUG-18-S1           # stream-based wait 替换 polling
BUG-18-INV1         # 无固定轮询间隔
BUG-18-INV2         # 超时 ≥ 12s
```

### 5.3 测试覆盖盲点

| 未覆盖 ID | 现状 | 应补偿方式 |
|---|---|---|
| BUG-18-S1 正常路径 | ref_14 桩 `player.playing=true` 直接通过，未覆盖等待逻辑 | 用 StreamController 延迟发出 `PlayerState(true, ...)` → 断言 loadAndPlay 成功且耗时 < 轮询周期 |
| BUG-18-S1 超时路径 | 无测试覆盖轮询超时 | 用 StreamController 不发 playing 事件 → 断言 30s 超时后返回 failed + stop 被调用 |
| BUG-18-S1 即时响应 | 无测试验证立即响应 | 用 StreamController 在 50ms 后发 playing → 断言 loadAndPlay 在 ~50ms 内完成（非 200ms+ 轮询延迟） |
| BUG-18-S1 fast path | 无测试覆盖已播放场景 | 桩 `player.playing=true` + 空 stream → 断言立即返回 loaded |

### 5.4 测试文件位置

| 测试 ID | 文件路径 |
|---|---|
| BUG-18-S1 | `test/features/player/bug_18_stream_wait_test.dart` |
| BUG-18-INV1 | `test/features/player/bug_18_stream_wait_test.dart` |
| BUG-18-INV2 | `test/features/player/bug_18_stream_wait_test.dart` |

---

## §6 算法样例

不适用——本修复为机制替换（轮询 → 流式），无新算法。

---

## §7 跨模块影响

| 其它 feature | 影响点 | 需要补的回归断言 |
|---|---|---|
| PLY | `ref_14_test.dart` 现有 28 用例 | 桩 `player.playing=true` 的用例仍通过（fast path 命中） |
| PLY | `ply_02_test.dart` 现有用例 | 同上 |
| PLY | `playerStateStream` 其他 listener | `_startPauseSaveListener`（:446）独立订阅同一 broadcast stream，不受影响 |

---

## §8 平台特性与手动 QA

| 风险 | 近似测试方案 | 测不了 → 进 mqa-backlog |
|---|---|---|
| P4: `await player.play()` 的 Future 可能永不完成 | 当前已用 `unawaited(player.play())`，不依赖 play() Future | 无需真机验证（机制不变） |
| P7: just_audio 本地 HTTP 代理拖慢远程大文件加载 | 单元测试用 mock player 模拟延迟 stream 事件 | 真机验证：大 FLAC 慢 NAS 加载是否不再超时 |
| P3: playing 状态在 Android 某些场景不传播 | mock 模拟 `playerStateStream` 延迟发送 | 真机验证：慢 NAS 场景播放是否正常开始 |

---

## §9 dev-status.json 条目对照

见统一更新：`docs/dev/dev-status.json`。

---

## §10 changelog

- 2026-07-27: 创建 BUG-18 spec（基于 cr-2026-06-28.md FRAGILE-02）
- 2026-08-05: cr-20260804-1922 复核：修订实现性错误/门禁指向——核查 cr §4 S4「audio_session 依赖位置记录错误」：本 spec 全文无 audio_session/pubspec 记录（grep 零命中，无可修订处）；误记实际位于 BUG-22.md（三处 `pubspec.yaml:38` dev_dependencies 区引用），已在 BUG-22.md 更正为 dependencies 主依赖（pubspec.yaml:16-19，2f946ff 移正）
