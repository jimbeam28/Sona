# BUG-19 — saveProgress fire-and-forget 无错误处理

> 来源：`docs/cr/cr-2026-06-28.md` FRAGILE-03
> dev-plan 流程：Bug 修复模式

---

## §0 头部元数据

```yaml
id: BUG-19
name: saveProgress fire-and-forget 无错误处理
priority: P1
status: draft
created_at: 2026-07-27
last_updated: 2026-07-27
spec_anchored_files:
  - lib/features/player/domain/playback_orchestrator.dart
cross_module_impacts: [PLY, PRG]
parent_feature: Player
manual_qa_required: true
```

---

## §1 用户视角

### 1.0 原始需求

> cr-2026-06-28.md FRAGILE-03：`progressSaver.upsertProgress` 的 Future 未被 await。在 `dispose()` 后仍在执行的保存会静默失败。dispose 窗口期间进度保存失败静默丢数据。

### 1.1 这一功能干什么（一句话）

修复 `saveProgress()` 内 fire-and-forget 的 `Future<void>` 未做错误处理、dispose 后可能产生 unhandled async error 的缺陷。

### 1.2 用户期望的场景

| ID | 你看到的样子 | 期望行为 |
|----|----|----|
| U1 | 切歌/暂停/自动保存时进度写入 | 即使 DB 异常或 dispose 窗口，不产生 unhandled error、不丢进度 |
| U2 | 快速退出 App 时恰好触发 auto-save | catchError 吞掉异常，不触发已释放资源 |

---

## §2 已实现的功能骨架

### 2.1 文件与分层

| 层 | 文件 | 行数 | 角色 |
|---|---|---|---|
| Domain | `lib/features/player/domain/playback_orchestrator.dart` | ~468 | PlaybackOrchestrator — saveProgress 定义 |
| Contract | `lib/core/contracts/database_contract.dart` | — | ProgressSaver 抽象接口 |
| Data | `lib/core/database/dao/progress_dao.dart` | — | upsertProgress 实现（SQLite） |

---

## §3 行为规约

### 3.1 修复后行为

- **[BUG-19-S1]** saveProgress 异步错误不泄漏 (`status: new`)
  ```
  Given PlaybackOrchestrator.saveProgress() 被调用
  When  progressSaver.upsertProgress() 返回的 Future 以 error 完成
  Then  catchError 捕获错误并记日志，不产生 unhandled async error
  否定断言:
    - 不产生 unhandled async error（当前 BUG 行为：Future 返回但无 await/catch）
    - 不阻塞调用方（saveProgress 仍为 void 返回，7 处调用方无需改动）
    - dispose 后不触发已释放资源（catchError 吞掉 dispose 期间的异常）
  ```
   Code evidence: `lib/features/player/domain/playback_orchestrator.dart:378-383`（`progressSaver.upsertProgress(...)` 返回 `Future<void>` 但无任何处理）
   对照：`playback_orchestrator.dart:208`（`unawaited(player.play())` — 同文件已有的 fire-and-forget 模式）

   **修改指令 — `lib/features/player/domain/playback_orchestrator.dart`**

   位置：`:373-384`

   当前代码（:373-384）：
   ```dart
     void saveProgress() {
       final q = queue;
       final connId = connectionProvider.currentConnection?.id;
       if (q == null || connId == null) return;

       progressSaver.upsertProgress(
         connectionId: connId,
         filePath: q.current.path,
         positionMs: player.position.inMilliseconds,
         durationMs: player.duration?.inMilliseconds,
       );
     }
   ```

   改为：
   ```dart
     void saveProgress() {
       final q = queue;
       final connId = connectionProvider.currentConnection?.id;
       if (q == null || connId == null) return;

       unawaited(
         progressSaver.upsertProgress(
           connectionId: connId,
           filePath: q.current.path,
           positionMs: player.position.inMilliseconds,
           durationMs: player.duration?.inMilliseconds,
         ).catchError((e, st) {
           // DB lock / disk full / disposed — log and swallow
         }),
       );
     }
   ```

   `dart:async` 已在 `:22` 导入，`unawaited` 无需额外 import。

   边界裁决：
   - DB 锁（SQLite SQLITE_BUSY）→ catchError 捕获，记日志不抛，不影响播放
   - 磁盘满 → catchError 捕获，同上
   - dispose 后 Future 完成 → catchError 吞掉异常，不触发已释放资源（参考 P8：监听器归编排层持有，dispose 时序需安全）
   - 正常路径 → `unawaited` + `catchError` 不改变语义，upsertProgress 正常完成 → 行为与修复前一致
   - 与 `player.play()` at `:208` 使用相同的 `unawaited()` 模式，保持代码风格一致

   **测试文件位置：`test/features/player/bug_bug19_repro_test.dart`**

---

## §4 不变量

- **[BUG-19-INV1]** saveProgress 调用方不受影响
  证据：`saveProgress()` 签名为 `void`，7 处调用方均不 await 返回值：
  - `skipToNext` → `:269`
  - `skipToPrevious` → `:297`
  - `selectQueueIndex` → `:315`
  - `removeTrack` → `:344`
  - `_startProcessingListener`（track completion）→ `:404`
  - `_startAutoSave`（Timer.periodic 10s）→ `:432`
  - `_startPauseSaveListener`（pause 状态变化）→ `:449`

  修复仅改 `saveProgress()` 内部实现，签名不变，所有调用方零改动。

---

## §5 测试规约

### 5.2 测试 ID 派生清单

```
BUG-19-S1          # saveProgress 异步错误不泄漏
BUG-19-INV1        # 7 处调用方不受影响
```

### 5.4 测试文件位置

| 测试 ID | 文件路径 |
|---------|----------|
| BUG-19-S1 | `test/features/player/bug_bug19_repro_test.dart` |
| BUG-19-INV1 | `test/features/player/bug_bug19_repro_test.dart`（调用方无感回归） |

---

## §7 跨模块影响

| 其它 feature | 影响点 | 影响条件 | 需要补的回归断言 |
|---|---|---|---|
| PRG (progress) | `saveProgress()` 是进度持久化唯一入口 | auto-save timer 每 10s + 切歌/暂停/track-completion 时调用 | 修复后 upsertProgress 正常路径行为不变；catchError 仅在异常时生效 |
| PLY (player) | `player_provider.dart` auto-save timer 间接调用 `saveProgress()` | Timer.periodic 触发 | 调用方签名/行为不变，无回归风险 |

---

## §8 平台特性与手动 QA

| 风险 | 近似测试方案 | 测不了 → 进 mqa-backlog |
|---|---|---|
| dispose 窗口期间 DB 写入异常 | fake ProgressSaver 返回 Future.error → 验证无 unhandled error | 真机验证：快速退出 App 时恰好 auto-save 触发 |

参考 `docs/dev/platform-pitfalls.md` P8：播放监听器归编排层持有，dispose 时序需安全。本修复确保 dispose 后 in-flight 的 saveProgress 不产生 unhandled error。

---

## §9 dev-status.json 条目对照

见统一更新：`docs/dev/dev-status.json`。

---

## §10 changelog

- 2026-07-27: 创建 BUG-19 spec（基于 cr-2026-06-28.md FRAGILE-03）
