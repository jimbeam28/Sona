# BUG-21 — autoSave/pauseSave provider 缺 ref.onDispose 资源泄漏

> 来源：`docs/cr/cr-2026-06-28.md` FRAGILE-07 (F7)
> dev-plan 流程：Bug 修复模式

---

## §0 头部元数据

```yaml
id: BUG-21
name: autoSave/pauseSave provider 缺 ref.onDispose 资源泄漏
priority: P1
status: draft
created_at: 2026-07-27
last_updated: 2026-07-27
spec_anchored_files:
  - lib/features/player/player_provider.dart
cross_module_impacts: [PLY]
parent_feature: Player
manual_qa_required: false
```

---

## §1 用户视角

### 1.0 原始需求

> cr-2026-06-28.md FRAGILE-07 (F7)：`player_provider.dart` `_startAutoSaveProvider`（:200-204）和 `_startPauseSaveProvider`（:209-218）创建 Timer / StreamSubscription 但无 `ref.onDispose` 取消。`startProcessingListenerProvider`（:229）有 `ref.onDispose`，这两个没有，不一致。ProviderScope dispose 后定时器/订阅继续运行，可能访问已释放 provider 导致异常或静默错误。

### 1.1 这一功能干什么（一句话）

修复 `_startAutoSaveProvider` 和 `_startPauseSaveProvider` 缺少 `ref.onDispose` 清理导致的资源泄漏。

### 1.2 用户期望的场景

| ID | 你看到的样子 | 期望行为 |
|----|----|----|
| U1 | ProviderScope dispose（如测试 tearDown）后 | 定时器/订阅被取消，不再触发回调，不访问已释放 provider |
| U2 | 正常播放中 10s 自动保存 | 行为不变（onDispose 是额外保护，不影响正常路径） |

---

## §2 已实现的功能骨架

### 2.1 文件与分层

| 层 | 文件 | 行数 | 角色 |
|---|---|---|---|
| Provider | `lib/features/player/player_provider.dart` | ~337 | 播放状态管理 |

### 2.2 关键 Provider 表

| Provider 名 | 类型 | 实现位置 | 用途 |
|---|---|---|---|
| `_startAutoSaveProvider` | `Provider<void Function()>` | `:200-204` | 启动 10s 周期定时器保存进度 |
| `_startPauseSaveProvider` | `Provider<void Function(AudioPlayer)>` | `:209-218` | 监听播放状态变化，暂停时保存进度 |
| `startProcessingListenerProvider` | `Provider<void Function()>` | `:229-244` | 监听处理状态（**有** `ref.onDispose`，对照标杆） |

---

## §3 行为规约

### 3.1 修复后行为

- **[BUG-21-S1]** `_startAutoSaveProvider` dispose 时取消定时器 (`status: new`)
  ```
  Given _startAutoSaveProvider 已启动（Timer.periodic 在跑）
  When  ProviderScope dispose（或 provider 被 invalidate）
  Then  Timer 被 cancel，不再触发
  否定断言:
    - 不在 dispose 后继续触发 Timer.periodic
    - 不访问已释放的 saveProgressProvider
    - 不改变正常播放时的 10s 保存行为
  ```
  Code evidence: `lib/features/player/player_provider.dart:200-204`（`_startAutoSaveProvider` 无 `ref.onDispose`）
  对照：`player_provider.dart:229-230`（`startProcessingListenerProvider` 有 `ref.onDispose`）

  **修改指令 — `lib/features/player/player_provider.dart`（_startAutoSaveProvider）**

  位置：`:200-204`

  当前代码（:200-204）：
  ```dart
  final _startAutoSaveProvider = Provider<void Function()>((ref) => () {
        ref.read(_autoSaveTimerProvider)?.cancel();
        ref.read(_autoSaveTimerProvider.notifier).state = Timer.periodic(
            const Duration(seconds: 10), (_) => ref.read(saveProgressProvider)());
      });
  ```

  改为：
  ```dart
  final _startAutoSaveProvider = Provider<void Function()>((ref) {
    ref.onDispose(() {
      ref.read(_autoSaveTimerProvider)?.cancel();
    });
    return () {
      ref.read(_autoSaveTimerProvider)?.cancel();
      ref.read(_autoSaveTimerProvider.notifier).state = Timer.periodic(
          const Duration(seconds: 10), (_) => ref.read(saveProgressProvider)());
    };
  });
  ```

  边界裁决：
  - 正常 cancel 路径（`_cancelAutoSaveProvider` `:205-208`）→ 行为不变（onDispose 是额外保护）
  - 多次 start → cancel → start → 中间 Timer 被正确清理（返回函数内已有 cancel）
  - dispose 时 Timer 为 null → `?.cancel()` 是 no-op，安全
  - onDispose 闭包在 Provider body 层（不在返回函数内），确保 Provider 生命周期绑定时注册

- **[BUG-21-S2]** `_startPauseSaveProvider` dispose 时取消订阅 (`status: new`)
  ```
  Given _startPauseSaveProvider 已启动（playerStateStream.listen 在跑）
  When  ProviderScope dispose（或 provider 被 invalidate）
  Then  StreamSubscription 被 cancel，不再接收事件
  否定断言:
    - 不在 dispose 后继续接收 playerStateStream 事件
    - 不访问已释放的 saveProgressProvider
    - 不改变正常暂停时保存进度的行为
  ```
  Code evidence: `lib/features/player/player_provider.dart:209-218`（`_startPauseSaveProvider` 无 `ref.onDispose`）
  对照：`player_provider.dart:229-230`（`startProcessingListenerProvider` 有 `ref.onDispose`）

  **修改指令 — `lib/features/player/player_provider.dart`（_startPauseSaveProvider）**

  位置：`:209-218`

  当前代码（:209-218）：
  ```dart
  final _startPauseSaveProvider =
      Provider<void Function(AudioPlayer)>((ref) => (p) {
            ref.read(_pauseSaveSubProvider)?.cancel();
            var was = p.playing;
            ref.read(_pauseSaveSubProvider.notifier).state =
                p.playerStateStream.listen((s) {
              if (was && !s.playing) ref.read(saveProgressProvider)();
              was = s.playing;
            });
          });
  ```

  改为：
  ```dart
  final _startPauseSaveProvider =
      Provider<void Function(AudioPlayer)>((ref) {
    ref.onDispose(() {
      ref.read(_pauseSaveSubProvider)?.cancel();
    });
    return (p) {
      ref.read(_pauseSaveSubProvider)?.cancel();
      var was = p.playing;
      ref.read(_pauseSaveSubProvider.notifier).state =
          p.playerStateStream.listen((s) {
        if (was && !s.playing) ref.read(saveProgressProvider)();
        was = s.playing;
      });
    };
  });
  ```

  边界裁决：
  - 正常 cancel 路径（`_cancelPauseSaveProvider` `:219-222`）→ 行为不变
  - 多次 start → cancel → start → 中间 Subscription 被正确清理
  - dispose 时 Subscription 为 null → `?.cancel()` 是 no-op，安全
  - onDispose 闭包在 Provider body 层（不在返回函数内），确保 Provider 生命周期绑定时注册
  - `was` 局部变量在返回函数内，不受 onDispose 影响

  **测试文件位置：`test/features/player/bug_bug21_repro_test.dart`**

---

## §4 不变量

- **[BUG-21-INV1]** 所有创建 Timer / StreamSubscription 的 provider 都有对应的 onDispose 清理
  证据：`player_provider.dart:229-230`（`startProcessingListenerProvider` 已有）→ `:200-204,:209-218`（修复目标）

- **[BUG-21-INV2]** `_startAutoSaveProvider` 与 `_startPauseSaveProvider` 的 onDispose 模式与 `startProcessingListenerProvider` 一致
  证据：`player_provider.dart:229-230`（标杆模式：Provider body 内 `ref.onDispose(() => ref.read(...)?.cancel())`）

---

## §5 测试规约

### 5.2 测试 ID 派生清单

```
BUG-21-S1 S2          # autoSave/pauseSave dispose 清理
BUG-21-INV1           # 全 Timer/Subscription provider 有 onDispose
BUG-21-INV2           # onDispose 模式一致性
```

### 5.4 测试文件位置

| 测试 ID | 文件路径 |
|---------|----------|
| BUG-21-S1 | `test/features/player/bug_bug21_repro_test.dart` |
| BUG-21-S2 | `test/features/player/bug_bug21_repro_test.dart` |
| BUG-21-INV1 | `test/features/player/bug_bug21_repro_test.dart`（全 provider onDispose 扫描用例） |
| BUG-21-INV2 | `test/features/player/bug_bug21_repro_test.dart`（模式一致性验证） |

---

## §7 跨模块影响

无跨模块影响。修复局限在 `player_provider.dart`，纯 provider 生命周期修复，不影响其他 feature 的不变量。

---

## §8 平台特性与手动 QA

本功能不涉及平台原生特性，全部可在 `flutter test` 中验证。

---

## §9 dev-status.json 条目对照

见统一更新：`docs/dev/dev-status.json`。

---

## §10 changelog

- 2026-07-27: 创建 BUG-21 spec（基于 cr-2026-06-28.md FRAGILE-07 / F7）
