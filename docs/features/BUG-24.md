# BUG-24 — withoutIndex 在 shuffle 模式下重置排列且指针与当前曲脱钩

```yaml
id: BUG-24
name: withoutIndex shuffle 指针不变量断裂（删曲后轮次重置/当前曲重复/上一首跳随机）
priority: P3
status: active
created_at: 2026-08-23
last_updated: 2026-08-23
spec_anchored_files:
  - lib/shared/models/play_queue.dart
cross_module_impacts:
  - lib/features/browser/browser_screen.dart
  - lib/features/playlist/playlist_detail_screen.dart
  - lib/features/player/domain/playback_orchestrator.dart
parent_feature: PlayQueue
manual_qa_required: false
```

---

## §1 用户视角

### 1.0 原始需求（来源逐字记录）

> 来源：docs/cr/cr-20260823-1421.md F2（走查发现，复核确认仍存在，2026-08-23 分流）。
>
> "shuffle 模式删曲后整体重洗且指针归 0，与同文件 withMode 文档（:98-105）声明的不变量 `order[pos]==currentIndex` 矛盾。对照 insertAfterCurrent（:227-241，BUG-04-S1 逐项 remap 保持逻辑映射）处理不对称。用户可感知：删曲后'下一首'按脱钩排列走、当前曲可能本轮重复播放；删后先点'上一首'→ retreatShuffle null → 二次重洗跳到新轮末尾随机曲。"
> 自检答案："aud_01 PLY-G06 六个 withoutIndex 用例全部 sequential 模式，shuffle 分支零覆盖。"
> 复核裁决（2026-08-23）：FRAGILE/Major → dev-plan Bug 流程；TEST-GAP T1 并入本规格。

### 1.1 一句话

随机播放时从队列删掉一首歌，接下来的"下一首/上一首"必须仍然接得上当前的随机轮次——不能偷偷重新洗牌、把正在听的歌又排回这一轮。

### 1.2 用户期望的场景

| ID | 你看到的样子 | 期望行为 |
|----|----|----|
| U1 | 随机播放中，在队列面板删掉任意一首 | 继续点"下一首"，听到的歌延续本轮随机顺序，已播过的当前曲不再冒出来 |
| U2 | 删歌后立刻点"上一首" | 回到上一首已播的歌，而不是跳到一首随机的歌 |
| U3 | 删掉正在播的这首 | 接替者顶上并继续本轮随机顺序 |

---

## §2 已实现骨架（逆抽锚点）

| 层 | 文件 | 角色 |
|---|---|---|
| Model | lib/shared/models/play_queue.dart:98-105 | withMode 文档声明的指针不变量：`order[pos] == currentIndex` 由 withIndex(BUG-04-S4)/fromMap(BUG-14)/regeneration 共同维护 |
| Model | lib/shared/models/play_queue.dart:186-215 | withoutIndex：:205-214 对 shuffle 与 sequential 一律传 shuffleOrder:null/shufflePosition:null → 构造器 :58-63 重洗+指针归 0（缺陷点）；:197-204 currentIndex 调整语义正确（aud_01 PLY-G06 锚定） |
| Model | lib/shared/models/play_queue.dart:227-241 | insertAfterCurrent BUG-04-S1 对照组：逐项 remap 保逻辑映射（不对称证据） |
| Orchestrator | lib/features/player/domain/playback_orchestrator.dart:258-284, :291-318, :429-448 | skipToNext/skipToPrevious/computeNextQueue 全部依赖 advanceShuffle/retreatShuffle + 耗尽重洗（BUG-04-S2/S3），指针脱钩直接放大为用户可感知症状 |
| 门禁测试 | test/shared/bug_bug24_shuffle_without_index_test.dart | 公开 API 行为锚定（walkRound 走整轮），20 种子 × 2 场景，修复前 FAIL（repro-test.sh fail 确认 2026-08-23） |

---

## §3 行为规约

### 3.1 现状锚定（逆抽）

- **[BUG-24-S0]** sequential 语义：withoutIndex 调整 currentIndex（前曲删除减一/当前删除保持/末尾钳制）、非当前删除保留 startPositionMs
  Code evidence: `lib/shared/models/play_queue.dart:197-208` + `test/features/coverage/aud_01_coverage_gaps_test.dart:540-633`
- **[BUG-24-S0b]** 不变量既有维护点：withIndex 指针重定位 :150-166、fromMap 归位 :366-376、withMode 进 shuffle 锚定 :114-137

### 3.2 修复目标

- **[BUG-24-S1]** shuffle 队列删任意一曲后，排列与指针保持"逻辑连续"（`status: new`）
  ```
  Given shuffle 模式队列（length ≥ 3）满足不变量 order[pos] == currentIndex
  When withoutIndex(index) 执行
  Then 结果仍是 shuffle 模式且 shuffleOrder 为剩余索引的完备置换（长度 n-1）
       且 shufflePosition 锚定 currentIndex 在新排列中的槽位（order[newPos] == newcurrentIndex）
       因而从新队列出发 advanceShuffle 走满一轮：恰好覆盖其余各曲一次、绝不重访当前曲
  否定断言:
    - 不得整体重洗排列（原排列经 index 映射后仍指向同一逻辑曲目集合）
    - sequential 模式行为零变更（S0 语义逐条保留）
    - 单曲残留场景（n-1 == 1）维持现有约定：无排列（shuffleOrder/shufflePosition 为 null）
  ```
  Code evidence: 修改点 `lib/shared/models/play_queue.dart:205-214`
- **[BUG-24-S2]** 删除当前曲：接替者移入其索引位（既有 :200-204 语义保留）并成为新指针锚点；startPositionMs 清空（既有语义）
  否定断言: 接替者在本轮内不被 advanceShuffle 重访
  Code evidence: 同上修改点 + `aud_01_coverage_gaps_test.dart:549-566`（回归）

边界裁决表：

| 输入 | 裁决 |
|---|---|
| 删除 index < currentIndex | 其左侧索引全体 -1 映射进新排列；currentIndex-1 的槽位继承原当前曲槽位 |
| 删除 index == currentIndex | 移除该曲槽位；新指针 = 新排列中 newCurrentIndex 的槽位 |
| 删除 index > currentIndex | 该索引直接从排列中剔除，其余不动 |
| n-1 == 1 | 维持现状：清空排列与指针（单曲无排列约定） |
| 非 shuffle | 走 S0 现状路径零变更 |

---

## §4 不变量

- **[BUG-24-INV1]** shuffle 模式下任何产生新 PlayQueue 的公开方法（withMode/withIndex/fromMap/insertAfterCurrent/advanceShuffle/retreatShuffle/withoutIndex/编排层 regenerate）产出的队列都满足 `shuffleOrder[shufflePosition] == currentIndex`
  证据：play_queue.dart:98-105（声明）、:150-156/:124/:374-375（既有实现）、:205-214（本修复补齐）

---

## §5 测试规约

### 5.1 现有测试清单

| 测试文件 | 覆盖 | 备注 |
|---|---|---|
| test/features/coverage/aud_01_coverage_gaps_test.dart:540-633 | withoutIndex sequential 六态 | 全绿即可 |
| test/shared/play_queue_insert_test.dart | insertAfterCurrent remap | 全绿即可 |

### 5.2 测试 ID 派生清单

```
BUG-24-S1, BUG-24-S2, BUG-24-INV1
```

### 5.3 测试覆盖盲点

真机长队列（数百曲）性能不可测——remap 是 O(n)，与现状重洗同为 O(n)，无回归风险。

### 5.4 门禁测试文件（spec-scan --gate 硬校验）

| 测试文件 | 覆盖 ID | 说明 |
|---|---|---|
| test/shared/bug_bug24_shuffle_without_index_test.dart | BUG-24-S1/S2 | 修复前 FAIL 已由 repro-test.sh fail 确认（2026-08-23）；修复后必须 PASS |

---

## §6 算法样例

**[BUG-24-ALG1-withoutIndex-shuffle-remap]**
```
输入：旧排列 order（含被删 index）、shufflePosition pos、被删 index、新当前曲 newIndex
映射：mapped = order.where((i) => i != index).map((i) => i > index ? i - 1 : i)
     （每个旧索引唯一映射到新索引；被删曲槽位移除）
锚定：newPos = mapped.indexOf(newIndex)   // 由 INV1 保证必然存在
输出：PlayQueue(files: newList, currentIndex: newIndex,
      playMode: playMode, shuffleOrder: mapped, shufflePosition: newPos,
      startPositionMs: 按 :208 既有规则)
边界：newList.length == 1 → mapped 视为空 → 返回无排列队列（见裁决表末行）
```

---

## §7 跨模块影响

impact 反查（2026-08-23）：play_queue ← browser（建队/恢复）、playlist_detail（建队）、player_provider（同步/applyLatestProgress）、playback_controls（next/prev 预览）、player_screen_logic、playback_orchestrator（导航）。

| 其它模块 | 影响点 | 影响条件 | 回归断言要求 |
|---|---|---|---|
| player 编排层 | removeTrack 当前曲路径 loadAndPlay | 删当前曲后 shuffle 导航起点变化 | bug_remove_track_progress_test 全绿 |
| browser / playlist | 建队点 withMode(shuffle) | 无（不经过 withoutIndex） | brw/ply 既有测试全绿 |
| playback_controls | nextShuffleIndex/previousShuffleIndex 预览 | 指针锚定后预览与实际一致 | ref_05/ply 既有测试全绿 |

**修改点（弱模型照单执行）**：
1. `lib/shared/models/play_queue.dart` withoutIndex（现 :186-215）：按 §6 ALG1 重写 :205-214 的返回构造——shuffle 且 newList.length > 1 时用映射后的排列与锚定指针；否则维持现有 null 透传。
2. 全量回归：cov-gate --skip-test + flutter test 全绿（重点 aud_01 / bug_bug04_fixed / play_mode_queue_writeback）。

---

## §8 平台特性与手动 QA

核对踩坑库：P12 相关（值对象字段变更触发重建——本修复不改字段集，== / hashCode 零变更）。其余条款无交集。纯 Dart 模型层改动，全部可在 flutter test 验证，manual_qa_required=false。

---

## §9 dev-status.json 条目对照

```json
"BUG-24": {
  "spec_file": "docs/features/BUG-24.md",
  "spec_anchored_files": ["lib/shared/models/play_queue.dart"],
  "scenarios": ["BUG-24-S1", "BUG-24-S2"],
  "invariants": ["BUG-24-INV1"],
  "algorithms": ["BUG-24-ALG1"],
  "manual_qa_required": false,
  "user_acceptance_text": "见 §1.2"
}
```
