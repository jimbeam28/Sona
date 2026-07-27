# BUG-14 — PlayQueue shuffle 状态只写不读（重启丢序列）

> 来源：`docs/cr/cr-20260724-0110.md` MDL1
> dev-plan 流程：Bug 修复模式

---

## §0 头部元数据

```yaml
id: BUG-14
name: PlayQueue shuffle 状态只写不读（重启丢序列）
priority: P0
status: draft
created_at: 2026-07-27
last_updated: 2026-07-27
spec_anchored_files:
  - lib/features/browser/browser_provider.dart
  - lib/shared/models/play_queue.dart
cross_module_impacts: [PLY]
parent_feature: null  # 跨模块：锚点为 browser_provider 恢复路径 + PlayQueue 持久化
manual_qa_required: false
```

---

## §1 用户视角

### 1.0 原始需求

> cr-20260724-0110.md MDL1：toMap 显式持久化 shuffleOrder/shufflePosition，但 restoreQueueFromPrefsProvider 手工重建 PlayQueue 时不传这两个字段 → 重启后 shuffle 序列和位置 100% 丢失。

### 1.1 这一功能干什么（一句话）

修复重启后 shuffle 播放序列丢失的缺陷。

### 1.2 用户期望的场景

| ID | 你看到的样子 | 期望行为 |
|----|----|----|
| U1 | shuffle 模式正播 D（index 3），order=[2,0,3,1] pos=2 → 杀进程重启 | 恢复后 shuffle 序列和位置不变，按"下一首"播放 order 中 D 之后的曲目 |

---

## §2 已实现的功能骨架

### 2.1 文件与分层

| 层 | 文件 | 行数 | 角色 |
|---|---|---|---|
| Provider | `lib/features/browser/browser_provider.dart` | ~170 | restoreQueueFromPrefsProvider |
| Shared Model | `lib/shared/models/play_queue.dart` | 309 | toMap/fromMap 含 shuffle 字段 |

---

## §3 行为规约

### 3.1 修复后行为

- **[BUG-14-S1]** 恢复路径传递 shuffleOrder 和 shufflePosition (`status: new`)
  ```
  Given prefs 中队列 JSON 含 shuffleOrder=[2,0,3,1], shufflePosition=2
  When  restoreQueueFromPrefsProvider 恢复队列
  Then  PlayQueue 构造传入 shuffleOrder 和 shufflePosition
  否定断言:
    - 不忽略 JSON 中的 shuffle 字段（当前 BUG 行为）
    - 不重新随机生成排列
    - fromMap 对 order 元素做 < files.length 防御（恢复时文件可能已从 NAS 删除）
  ```
  Code evidence: `lib/features/browser/browser_provider.dart:141-166`（restoreQueueFromPrefsProvider 手工重建不传 shuffle 字段）
  对照：`lib/shared/models/play_queue.dart:268-275`（toMap 正确写入）
  对照：`lib/shared/models/play_queue.dart:283-301`（fromMap 正确读取，但生产零调用）

   **修改指令 — `lib/features/browser/browser_provider.dart`**

   位置：`:154-166`（手工提取字段 + 手工构造 PlayQueue）

   当前代码（:154-166）：
   ```dart
       final idx = (m['currentIndex'] as int?) ?? 0;
       if (idx >= files.length) return;
       final posMs = m['startPositionMs'] as int?;
       final modeName = m['playMode'] as String?;
       final mode = modeName != null
           ? PlayMode.values.firstWhere((m) => m.name == modeName,
               orElse: () => PlayMode.sequential)
           : PlayMode.sequential;
       ref.read(currentPlayQueueProvider.notifier).state = PlayQueue(
           files: files,
           currentIndex: idx,
           startPositionMs: posMs,
           playMode: mode);
   ```

   改为：
   ```dart
       final idx = (m['currentIndex'] as int?) ?? 0;
       if (idx >= files.length) return;
       ref.read(currentPlayQueueProvider.notifier).state =
           PlayQueue.fromMap(m, files);
   ```

   边界裁决：
   - `PlayQueue.fromMap` 内部已处理 `playMode` 解析（`:284-288`）、`shuffleOrder`/`shufflePosition` 读取（`:289-292`）→ 删除的 `posMs`/`modeName`/`mode` 局部变量全部由 fromMap 内部处理
   - `idx >= files.length` 的 guard 保留在 fromMap 调用前（`:155`），fromMap 不做 currentIndex 边界检查
   - fromMap 失败（如 JSON 字段类型不匹配）→ 被外层 `try/catch`（`:146`）捕获，静默返回，不崩溃
   - `PlayQueue` 已在 `browser_provider.dart` 顶层 import（通过 `play_queue.dart`），`fromMap` 是 factory → 无需新增 import

   **修改指令 — `lib/shared/models/play_queue.dart`（fromMap shuffleOrder 防御）**

   位置：`:290-291`（shuffleOrder 解析无边界过滤）

   当前代码（:290-291）：
   ```dart
       final shuffleOrder =
           shuffleOrderRaw?.map((e) => (e as num).toInt()).toList();
   ```

   改为：
   ```dart
       final shuffleOrder = shuffleOrderRaw
           ?.map((e) => (e as num).toInt())
           .where((e) => e >= 0 && e < files.length)
           .toList();
   ```

   边界裁决：
   - 恢复时文件可能已从 NAS 删除 → files.length 可能小于持久化时的 length → 过滤掉越界索引
   - 过滤后 shuffleOrder 可能为空列表 → 保留为空列表（不置 null），PlayQueue 构造函数会接受
   - 过滤后 shuffleOrder 为空但 playMode == shuffle → PlayQueue 构造函数（`:57-60`）在 `shuffleOrder` 非 null 时直接使用传入值，不会重新生成 → 空列表意味着 shuffle 模式下无有效曲目可播，由 Player 层处理（不会崩溃，只是无曲目）
   - 负数索引同样被过滤（`e >= 0`）

   **测试文件位置：`test/features/browser/bug_14_repro_test.dart`**

- **[BUG-14-S2]** 恢复路径改用 PlayQueue.fromMap 或显式传参 (`status: new`)
  ```
  Given 恢复路径需要重建 PlayQueue
  When  构造 PlayQueue
  Then  优先使用 PlayQueue.fromMap（已含 shuffle 字段处理）
        或手工构造时显式传入 shuffleOrder/shufflePosition
  否定断言:
    - 不绕过 fromMap 手工重建遗漏字段
  ```
  Code evidence: `lib/shared/models/play_queue.dart:283-301`（fromMap 已实现但生产零调用）

   **修改指令：与 BUG-14-S1 相同**（S1 的修改指令已覆盖本场景——将 `browser_provider.dart:154-166` 的手工构造替换为 `PlayQueue.fromMap(m, files)`，并在 `play_queue.dart:290-291` 添加 shuffleOrder 边界过滤）。S1 和 S2 描述同一修复的两个视角：S1 关注字段传递，S2 关注路径统一。

---

## §4 不变量

- **[BUG-14-INV1]** toMap → fromMap round-trip 保留所有字段（含 shuffle）
  证据：`play_queue.dart:268-301`

- **[BUG-14-INV2]** 恢复路径与持久化路径字段一致
  证据：`browser_provider.dart:141-166`（修复目标）

---

## §5 测试规约

### 5.2 测试 ID 派生清单

```
BUG-14-S1 S2          # 恢复传 shuffle + 路径统一
BUG-14-INV1 INV2      # round-trip + 路径一致
```

### 5.4 测试文件位置

| 测试 ID | 文件路径 |
|---------|----------|
| BUG-14-S1 S2 | `test/features/browser/bug_14_repro_test.dart` |
| BUG-14-INV1 | `test/features/browser/bug_14_repro_test.dart`（round-trip 用例） |

---

## §7 跨模块影响

| 其它 feature | 影响点 | 影响条件 | 需要补的回归断言 |
|---|---|---|---|
| PLY | shuffle 模式下重启后下一曲顺序 | 队列恢复 | 恢复后 advanceShuffle 返回正确下一曲 |

---

## §8 平台特性与手动 QA

本功能不涉及平台原生特性，全部可在 `flutter test` 中验证。

---

## §9 dev-status.json 条目对照

见统一更新：`docs/dev/dev-status.json`。

---

## §10 changelog

- 2026-07-27: 创建 BUG-14 spec（基于 cr-20260724-0110.md MDL1）
