# BUG-04 — Shuffle 排列一致性缺陷簇

> 来源：`docs/cr/cr-20260724-0110.md` PLY1 / PLY3 / MDL4
> dev-plan 流程：Bug 修复模式（已先写复现测试并确认 FAIL）
> 用户裁决（2026-07-24）：PLY3 shuffle 排列耗尽策略 → 重洗新一轮

---

## §0 头部元数据

```yaml
id: BUG-04
name: Shuffle 排列一致性缺陷簇
priority: P0
status: draft
created_at: 2026-07-27
last_updated: 2026-08-05
spec_anchored_files:
  - lib/shared/models/play_queue.dart
  - lib/features/player/domain/playback_orchestrator.dart
  - lib/features/player/domain/play_mode.dart
cross_module_impacts: [PLY, BRW]
parent_feature: null
manual_qa_required: false
```

---

## §1 用户视角

### 1.0 原始需求

> cr-20260724-0110.md 走查发现 shuffle 排列一致性缺陷簇：insertAfterCurrent 破坏排列、排列耗尽降级随机、withIndex 不更新 shufflePosition。用户裁决：耗尽时重洗新一轮。

### 1.1 这一功能干什么（一句话）

修复 shuffle 模式下排列被破坏、耗尽后降级随机、手动选曲后 shufflePosition 失同步三个关联缺陷。

### 1.2 用户期望的场景

| ID | 你看到的样子 | 期望行为 |
|----|----|----|
| U1 | shuffle 模式下从浏览器"下一曲"插入一首歌 | 插入后 shuffle 排列正确重映射，后续"下一曲"按预期顺序播放，不跳曲不丢曲 |
| U2 | shuffle 模式完整播完一轮所有曲目 | 自动开始新一轮 shuffle（重新生成排列），不随机盲选、不重播刚播完的曲目 |
| U3 | shuffle 模式下从队列面板点击一首歌 | "下一首"播放 shuffle 序列中该曲之后的那首，不重播刚点的曲 |

---

## §2 已实现的功能骨架

### 2.1 文件与分层

| 层 | 文件 | 行数 | 角色 |
|---|---|---|---|
| Shared Model | `lib/shared/models/play_queue.dart` | 339 | PlayQueue 值对象 + shuffle 排列 + 导航 |
| Domain | `lib/features/player/domain/playback_orchestrator.dart` | 468 | 播放编排 |
| Domain | `lib/features/player/domain/play_mode.dart` | ~85 | nextIndex/previousIndex |

### 2.2 关键数据结构

| 字段 | 类型 | 位置 | 说明 |
|---|---|---|---|
| `_shuffleOrder` | `List<int>?` | `play_queue.dart:42` | Fisher-Yates 排列 |
| `_shufflePosition` | `int?` | `play_queue.dart:43` | 当前在排列中的位置 |
| 构造器 | — | `play_queue.dart:49-62` | shuffleOrder=null 时自动生成新排列 |
| `_generateShuffleOrder` | static | `play_queue.dart:65-74` | Fisher-Yates 算法 |

---

## §3 行为规约

### 3.1 PLY1 — insertAfterCurrent 破坏 shuffle 排列

- **[BUG-04-S1]** insertAfterCurrent 在 shuffle 模式下重映射排列 (`status: new`)
  ```
  Given files=[A,B,C,D], currentIndex=0, shuffleOrder=[0,2,3,1]
  When  insertAfterCurrent(X) → files=[A,X,B,C,D]
  Then  shuffleOrder 中 >currentIndex 的索引 +1 → [0,3,4,2]
        新文件索引 (currentIndex+1=1) 不入排列
  否定断言:
    - 不直接携带旧 _shuffleOrder 不变
    - 不重生成整个排列（仅做索引重映射）
    - currentIndex 不变
  ```
  Code evidence: `play_queue.dart:168-178`

  **修改指令**：
  1. 在 `PlayQueue` 类 `_generateShuffleOrder` 方法（:74）之后新增：
     ```dart
     static List<int>? _remapShuffleOrderAfterInsert(
         List<int>? order, int currentIndex) {
       if (order == null) return null;
       return order.map((idx) => idx > currentIndex ? idx + 1 : idx).toList();
     }
     ```
  2. 修改 `insertAfterCurrent`（:168-178），第 175 行 `shuffleOrder: _shuffleOrder,` 改为：
     ```dart
     shuffleOrder: _remapShuffleOrderAfterInsert(_shuffleOrder, currentIndex),
     ```
  3. 同步更新方法文档注释（:159-167），删除"shuffle order is not recomputed"的旧描述，改为"shuffle order 中 >currentIndex 的索引 +1，新文件不入排列"。
  4. **边界裁决**：
     - `_shuffleOrder == null`（sequential 模式）→ 返回 null，行为不变
     - `currentIndex` 是最后一个元素 → 新文件插入末尾，无索引需 +1，排列不变
     - 多次连续 insertAfterCurrent → 每次独立重映射，累积正确

### 3.2 PLY3 — shuffle 排列耗尽后重洗

- **[BUG-04-S2]** advanceShuffle 返回 null 时重洗新一轮 (`status: new`)
  ```
  Given shuffle 队列 [A,B,C], shuffleOrder=[0,2,1], shufflePosition=2 (末位)
  When  computeNextQueue()（advanceShuffle 返回 null）
  Then  生成新 shuffleOrder（Fisher-Yates），shufflePosition=0
        新排列第一首 ≠ 刚播完的 currentIndex
  否定断言:
    - 不降级到 PlayQueue.nextIndex(shuffle) 随机盲选
    - 新排列不以末位曲目开头
    - withIndex 不携带旧 shufflePosition
  ```
  Code evidence: `playback_orchestrator.dart:252-263`（skipToNext）, `:413-425`（computeNextQueue）

  **修改指令**：
  1. 在 `PlaybackOrchestrator` 类中新增私有方法：
     ```dart
     /// 生成新 shuffle 排列，排除 [excludeIndex]（刚播完的曲目）作为首曲。
     /// 返回 shufflePosition=0 的新 PlayQueue。
     PlayQueue _regenerateShuffleQueue(PlayQueue q, {int? excludeIndex}) {
       // 构造器 shuffleOrder=null 会自动生成新排列
       // 但需保证 order[0] != excludeIndex
       final rng = Random();
       List<int> order;
       do {
         order = PlayQueue.generateShuffleOrderPublic(q.length, rng);
       } while (excludeIndex != null && order.isNotEmpty && order[0] == excludeIndex);
       return PlayQueue(
         files: q.files,
         currentIndex: order[0],
         startPositionMs: null,
         playMode: q.playMode,
         shuffleOrder: order,
         shufflePosition: 0,
       );
     }
     ```

     > **⚠ 更正（2026-08-05，cr-20260804-1922 §4 S4 复核）**：上述片段的重洗循环条件
     > `excludeIndex != null && order.isNotEmpty && order[0] == excludeIndex` 在
     > `q.length == 1` 时**死循环**——order 恒为 `[0]`、`excludeIndex` 恒为 0，条件恒真，
     > 与下方边界裁决「`files.length == 1` → 仍播同一首」自相矛盾。原片段不得作为实现依据。
     > 实际落地实现（commit 17a9010）以 `q.length > 1` 守卫规避，`excludeIndex` 改为非空
     > `required` 参数，并将 S3 的 forPrevious 合入同一方法：
     >
     > ```dart
     > // lib/features/player/domain/playback_orchestrator.dart:456-471（当前实现语义）
     > PlayQueue _regenerateShuffleQueue(PlayQueue q,
     >     {required int excludeIndex, bool forPrevious = false}) {
     >   List<int> order;
     >   do {
     >     order = PlayQueue.generateShuffleOrder(q.length, _rng);
     >   } while (q.length > 1 && order[0] == excludeIndex);
     >   final position = forPrevious ? order.length - 1 : 0;
     >   return PlayQueue(
     >     files: q.files,
     >     currentIndex: order[position],
     >     startPositionMs: null,
     >     playMode: q.playMode,
     >     shuffleOrder: order,
     >     shufflePosition: position,
     >   );
     > }
     > ```
     >
     > 单曲队列退化为重播该曲（循环一次即退出，不死循环）；`forPrevious: true` 时指针落
     > 排列末尾（S3）。接入点：`skipToNext`（`playback_orchestrator.dart:261-266`）、
     > `skipToPrevious`（`:292-300`）、`computeNextQueue`（`:425-434`）。
  2. 在 `PlayQueue` 类中将 `_generateShuffleOrder`（:65）改为公开方法（去掉下划线前缀或新增公开包装），以便 orchestrator 调用。建议新增：
     ```dart
     /// 公开 Fisher-Yates 排列生成，供编排层重洗用。
     static List<int> generateShuffleOrder(int n, Random rng) =>
         _generateShuffleOrder(n, rng);
     ```
  3. 修改 `computeNextQueue`（:413-425），将第 420-424 行的 fallback 逻辑：
     ```dart
     final ni = PlayQueue.nextIndex(q.currentIndex, q.length, playMode);
     if (ni == null) return null;
     return q.withIndex(ni);
     ```
     替换为：
     ```dart
     // shuffle 耗尽 → 重洗新一轮（用户裁决 2026-07-24）
     if (playMode == PlayMode.shuffle) {
       return _regenerateShuffleQueue(q, excludeIndex: q.currentIndex);
     }
     final ni = PlayQueue.nextIndex(q.currentIndex, q.length, playMode);
     if (ni == null) return null;
     return q.withIndex(ni);
     ```
  4. 修改 `skipToNext`（:252-263）中同样的 fallback 逻辑（:260-263），替换为：
     ```dart
     nextQueue ??= () {
       if (playMode == PlayMode.shuffle) {
         return _regenerateShuffleQueue(q, excludeIndex: q.currentIndex);
       }
       final ni = PlayQueue.nextIndex(q.currentIndex, q.length, playMode);
       return ni != null ? q.withIndex(ni) : null;
     }();
     ```
  5. **边界裁决**：
     - `files.length == 1` → 重洗后排列=[0]，仍播同一首（合理：只有一首）
     - `files.length == 0` → computeNextQueue 返回 null（已在 :414-415 守卫）
     - 重洗循环（order[0]==excludeIndex）期望 1-2 次迭代即退出（概率 1/n）

- **[BUG-04-S3]** skipToPrevious 在排列头部时重洗 (`status: new`)
  ```
  Given shuffle 队列, shufflePosition=0 (排列头部)
  When  skipToPrevious()（retreatShuffle 返回 null）
  Then  生成新 shuffleOrder，shufflePosition=末尾
  否定断言:
    - 不降级到 previousIndex 随机
  ```
  Code evidence: `playback_orchestrator.dart:279-300`

  **修改指令**：
  1. 修改 `skipToPrevious`（:279-300）中第 288-291 行的 fallback 逻辑：
     ```dart
     prevQueue ??= () {
       final pi = PlayQueue.previousIndex(q.currentIndex, q.length, playMode);
       return pi != null ? q.withIndex(pi) : null;
     }();
     ```
     替换为：
     ```dart
     prevQueue ??= () {
       if (playMode == PlayMode.shuffle) {
         // 排列头部 → 重洗，shufflePosition 放末尾
         final newQ = _regenerateShuffleQueue(q, excludeIndex: q.currentIndex);
         // 将 shufflePosition 移到末尾，currentIndex 移到排列最后一首
         final order = newQ.shuffleOrderForTest; // 需暴露 getter 或用 withIndex
         final lastPos = order.length - 1;
         return PlayQueue(
           files: q.files,
           currentIndex: order[lastPos],
           startPositionMs: null,
           playMode: q.playMode,
           shuffleOrder: order,
           shufflePosition: lastPos,
         );
       }
       final pi = PlayQueue.previousIndex(q.currentIndex, q.length, playMode);
       return pi != null ? q.withIndex(pi) : null;
     }();
     ```
     **实现简化建议**：可在 `PlayQueue` 中新增 `PlayQueue regenerateShuffleWithLastPosition(int excludeIndex, Random rng)` 工厂方法，避免 orchestrator 直接操作排列内部。

     > **⚠ 更正（2026-08-05，cr-20260804-1922 §4 S4 复核）**：实际落地实现（commit 17a9010）
     > 未采用本节片段与工厂方法建议，而是复用 S2 更正块中的
     > `_regenerateShuffleQueue(q, excludeIndex: q.currentIndex, forPrevious: true)`
     > （`playback_orchestrator.dart:292-300,456-471`）：指针落排列末尾、
     > `currentIndex = order[末尾]`，语义与本 Scenario 一致（末位曲目 ≠ 刚播完曲目
     > 由重洗守卫在 `q.length > 1` 时保证；单曲队列退化为重播）。
  2. **边界裁决**：
     - `files.length == 1` → 排列=[0]，末尾=0，仍播同一首
     - 重洗后末位曲目 ≠ 刚播完的曲目（由 _regenerateShuffleQueue 保证首位≠excludeIndex，末位自然不同）

### 3.3 MDL4 — withIndex 更新 shufflePosition

- **[BUG-04-S4]** withIndex 在 shuffle 模式下重定位 shufflePosition (`status: new`)
  ```
  Given files=[A,B,C,D], shuffleOrder=[0,2,1,3], shufflePosition=0 (播 A)
  When  withIndex(2)（用户点击 C）
  Then  shufflePosition = indexOf(2) in shuffleOrder = 2
  否定断言:
    - 不原样透传旧 _shufflePosition
    - 不重生成排列（仅重定位指针）
    - 若 newIndex 不在 shuffleOrder 中，降级为排列末尾
  ```
  Code evidence: `play_queue.dart:100-108`

  **修改指令**：
  1. 修改 `withIndex` 方法（`play_queue.dart:101-108`），将第 106-107 行：
     ```dart
     shuffleOrder: _shuffleOrder,
     shufflePosition: _shufflePosition,
     ```
     替换为：
     ```dart
     shuffleOrder: _shuffleOrder,
     shufflePosition: _shuffleOrder != null
         ? (_shuffleOrder!.indexOf(newIndex) != -1
             ? _shuffleOrder!.indexOf(newIndex)
             : _shuffleOrder!.length - 1)
         : null,
     ```
  2. **边界裁决**：
     - `_shuffleOrder == null`（sequential 模式）→ shufflePosition=null，行为不变
     - `newIndex` 在 `_shuffleOrder` 中 → shufflePosition = 其位置（O(n) 查找，n 通常 <1000 可接受）
     - `newIndex` 不在 `_shuffleOrder` 中（理论上不应发生，但防御性处理）→ 降级为排列末尾
     - `newIndex == currentIndex` → shufflePosition 不变（indexOf 返回原位置）

---

## §4 不变量

- **[BUG-04-INV1]** shuffle 排列中的索引始终有效（< files.length）
  证据：`play_queue.dart:57-62`（构造器生成排列）, 修复后 `_remapShuffleOrderAfterInsert` 保持有效性

- **[BUG-04-INV2]** advanceShuffle/retreatShuffle 确定性：同排列同位置 → 同结果
  证据：`play_queue.dart:205-218`

- **[BUG-04-INV3]** withIndex 后 shufflePosition 指向 newIndex 在 shuffleOrder 中的位置
  证据：`play_queue.dart:100-108`（修复目标）

---

## §5 测试规约

### 5.1 现有测试清单

| 测试文件 | 覆盖 | 备注 |
|---|---|---|
| `test/features/player/ply_05_test.dart` | 非 shuffle 等价类、排列生成 | 57 测试，未覆盖 shuffle+insert / 耗尽 / withIndex×shuffle |
| `test/features/player/ply_insert_after_current_test.dart` | insertAfterCurrent | 全部 sequential，shuffle+insert 零覆盖 |
| `test/shared/play_queue_insert_test.dart` | insertAfterCurrent shuffle | 空壳断言（returnsNormally） |

### 5.2 测试 ID 派生清单

```
BUG-04-S1 S2 S3 S4       # 修复后行为
BUG-04-INV1 INV2 INV3    # 不变量
BUG-04-ALG1              # 索引重映射算法
BUG-04-ALG2              # 重洗算法
```

### 5.3 测试覆盖盲点

| 未覆盖 ID | 应补偿方式 |
|---|---|
| BUG-04-S1 | 构造 shuffle 队列 → insertAfterCurrent → 断言排列索引正确（逐元素比对） |
| BUG-04-S2 | 构造排列末位 → computeNextQueue → 断言新排列生成 + order[0] != 旧 currentIndex |
| BUG-04-S3 | 构造排列首位 → skipToPrevious → 断言新排列 + shufflePosition=末尾 |
| BUG-04-S4 | 构造 shuffle 队列 → withIndex(n) → 断言 shufflePosition == shuffleOrder.indexOf(n) |

### 5.4 测试文件位置

门禁：`test/features/player/bug_bug04_fixed_test.dart`（覆盖 S1-S4 + INV1-3 + ALG1/2，两态实证修复前 FAIL + mutation 锚定；commit 17a9010）

> **⚠ 更正（2026-08-05，cr-20260804-1922 复核）**：原列的 `bug_bug04_repro_test.dart`
> **从未创建**（`git log --all` 对该路径零命中）；「修复前 FAIL」实证由复核门禁
> 两态验证承担（见 17a9010 commit message）。实际门禁为上列 `bug_bug04_fixed_test.dart`。

---

## §6 算法样例

```
ALG [BUG-04-ALG1-remapShuffleOrder]:
  输入: order=[0,2,3,1], currentIndex=0  → 期望: [0,3,4,2]
  输入: order=[0,2,3,1], currentIndex=2  → 期望: [0,2,4,1]
  输入: order=null                        → 期望: null
  输入: order=[0], currentIndex=0         → 期望: [0]（无 >0 的索引）

ALG [BUG-04-ALG2-regenerateShuffle]:
  输入: n=4, excludeIndex=3  → 期望: order.length=4, order[0]!=3, 包含 {0,1,2,3}
  输入: n=1, excludeIndex=0  → 期望: [0]（唯一选择，无法排除）
  输入: n=2, excludeIndex=0  → 期望: order[0]=1（唯一非 exclude 选择）
```

---

## §7 跨模块影响

| 其它 feature | 影响点 | 需要补的回归断言 |
|---|---|---|
| PLY | `player_provider.dart:111-113` ref.listen | 排列变更触发 == 变化 → listener 正常触发 |
| BRW | `browser_screen.dart:87` insertAfterCurrentProvider | shuffle 模式下插入后下一曲顺序正确 |

---

## §8 平台特性与手动 QA

本功能不涉及平台原生特性，全部可在 `flutter test` 中验证。

---

## §9 dev-status.json 条目对照

见统一更新：`docs/dev/dev-status.json`。

---

## §10 changelog

- 2026-07-27: 创建 BUG-04 spec（基于 cr-20260724-0110.md PLY1/PLY3/MDL4 + 用户裁决 PLY3=重洗）
- 2026-07-27: 增强 §3 修改指令（精确到行号 + 代码片段 + 边界裁决）
- 2026-08-05: cr-20260804-1922 复核：修订实现性错误/门禁指向——§3.2 S2 更正原 regenerate 片段 n=1 死循环并贴实际实现语义（playback_orchestrator.dart:456-471，q.length>1 守卫 + forPrevious）；S3 更正实际实现为同方法复用；§5.4 门禁改指向实际落地的 bug_bug04_fixed_test.dart（原 bug_bug04_repro_test.dart 从未创建，git log --all 证实）
