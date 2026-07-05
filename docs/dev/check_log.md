# dev-check 评审日志

每轮评审追加一节，最末条为最新一轮。dev-exe 被打回重做时必须读本文件最末条作为修复靶点清单。

---

## [2026-07-05 22:00] BRW-09 - 第 1 轮 dev-check

### 检查结果

| 检查项 | Verdict | 问题数 | 详情 |
|---|---|---|---|
| 1. spec vs 原需求贴合度 | PASS | 0 | §1.2 U1-U8 与 S1-S9 一一对应；无脑补 Scenario |
| 2. 实现对 spec 忠实度 | PASS | 0 | PlayQueue.insertAfterCurrent/playback_orchestrator.insertAfterCurrent/file_list_item 三层实现忠实 INV1-4 |
| 3. 回归测试充分性 | PASS | 0 | brw_09_test.dart / ply_insert_after_current_test.dart / play_queue_insert_test.dart 各 Scenario 都有真实断言 |
| 4. 跨模块已识别不变量未破坏 | PASS | 0 | §7 PLY-REG-1/2/3 三项回归断言齐全（ply_insert_after_current_test.dart:217 / play_queue_insert_test.dart:247/275） |
| 5. 跨模块被漏识的破坏（含跑全量） | PASS | 0 | 全量 1657 测试 PASS；改动文件 lib/shared/models/play_queue.dart 被 PLY/PRG/BRW/Playlist 多模块 import，全量回归未失败 |
| 6. 基线覆盖率漂移 | PASS（建立基线） | 0 | baseline-coverage.json 此前为 empty 状态；本轮 PASS 后由 cov-drift.sh refresh 写入基线 |
| 7. 否定断言未被破坏 | PASS | 0 | §3 多条否定语义（不去重/不移动/不替换原位）由 play_queue_insert_test.dart S5/S6/INV3 显式断言；BRW-09 spec 未用"否定断言:"字面块（早于 dev-plan 铁律 4），自然语言否定皆有对应 expect |

### 总 verdict: PASS

### 行动
- dev-status.json 已置 `check_status=passed`
- 已刷新 docs/dev/baseline-coverage.json 基线快照（cov-drift.sh refresh）

---

## [2026-07-05 22:00] BUG-01 - 第 1 轮 dev-check

### 检查结果

| 检查项 | Verdict | 问题数 | 详情 |
|---|---|---|---|
| 1. spec vs 原需求贴合度 | PASS | 0 | §1.2 U1"切歌后面板刷新" / U2"shuffle 序列变更触发 UI 重建"对应 §3 S1-S6 |
| 2. 实现对 spec 忠实度 | PASS | 0 | play_queue.dart:309-326 == 与 hashCode 已纳入 _listEquals(_shuffleOrder) + _shufflePosition；与 §3 S4/S5 一致 |
| 3. 回归测试充分性 | PASS | 0 | bug_bug01_repro_test.dart 3 条 + bug_bug01_fixed_test.dart 8 条，每条 neg 断言含 `expect(..., isFalse)` |
| 4. 跨模块已识别不变量未破坏 | **FAIL** | 2 | 见下 |
| 5. 跨模块被漏识的破坏 | PASS | 0 | 全量回归 PASS；改动文件仅 lib/shared/models/play_queue.dart |
| 6. 基线覆盖率漂移 | PASS | 0 | 同 BRW-09，建立基线 |
| 7. 否定断言未被破坏 | PASS | 0 | §3 S4/S5/S6 否定断言块均有对应 test 真断言 |

### 总 verdict: FAIL

### FAIL 问题清单

1. **§7 PLY 回归断言缺失**（@BUG-01 cross_module_impacts[0]）
   - 证据：spec 行 "切 shuffle 序列后 `o.queue` 应同步到 orchestrator" 无对应 test
   - 检索：`grep -rn "shuffle.*queue.*sync\|advanceShuffle.*orchestrator\|currentPlayQueue.*shuffle" test/features/player/` → 无命中
   - 现象：§7 显式列出"`player_provider.dart:111-113 ref.listen(currentPlayQueueProvider) 依赖 == 触发同步`"需要回归断言，但 dev-exe 未补对应测试验证"shuffle 序列变更后 orchestrator.queue 真的被同步"
   - 修复建议：在 test/features/player/ 新增一条用例——构造 shuffle PlayQueue、推进 advanceShuffle 后写入 currentPlayQueueProvider，断言 `playbackOrchestratorProvider.queue == 该推进后队列`（验证 == 修复后被 ref.listen 真正捕获）

2. **§7 PRG 回归断言缺失**（@BUG-01 cross_module_impacts[1]）
   - 证据：spec 行 "持久化 persistQueueOnChangeProvider 依赖 ref.listen 比较... 须确认 persist 不短路" 无对应 test
   - 检索：`grep -rn "persistQueue.*shuffle\|shuffle.*persist" test/` → 无命中
   - 现象：§7 要求验证"shuffle 字段纳入 == 后，persist provider 不会因 == 判等不变化而短路写 prefs"；现状无该回归断言
   - 修复建议：在 test/features/progress/ 或 test/features/player/ 新增一条用例——构造 shuffle PlayQueue A → 写入 currentPlayQueueProvider → 调用 advanceShuffle 得 B → 写入 → 断言 persist 被触发（B != A），与 shuffle 字段未变化场景成对照

### 行动
- dev-status.json BUG-01 已置 `check_status=round_1 / check_round=1 / impl_status=pending / test_status=pending`
- 等待用户手动启动 `dev-exe BUG-01` 重做（dev-exe 必读本节作为修复靶点）

---

## [2026-07-05 22:00] BUG-02 - 第 1 轮 dev-check

### 检查结果

| 检查项 | Verdict | 问题数 | 详情 |
|---|---|---|---|
| 1. spec vs 原需求贴合度 | PASS | 0 | §1.2 U1"重复文件只应出现一次" / U2"输入 list 中重复 N 次仅一条"对应 §3 S1-S3 |
| 2. 实现对 spec 忠实度 | PASS | 0 | playlist_service.dart:64-83 的 addTracksToPlaylist 已加 `seen.add(file.path)` 内存去重，对齐 §3 S2 |
| 3. 回归测试充分性 | PASS | 0 | bug_bug02_repro_test.dart 2 条 + bug_bug02_fixed_test.dart 8 条覆盖 S2/S3/INV1/INV2/ALG 全档 |
| 4. 跨模块已识别不变量未破坏 | PASS | 0 | §7 显式声明"无外部 feature 依赖此方法的去重行为"，无回归要求 |
| 5. 跨模块被漏识的破坏 | PASS | 0 | 全量回归 PASS；改动仅 lib/features/playlist/domain/playlist_service.dart，无跨模块 import |
| 6. 基线覆盖率漂移 | PASS | 0 | 同上 |
| 7. 否定断言未被破坏 | PASS | 0 | §3 S2/S3 否定断言块（"同 path 项不应多次插入 DB" / "不应跳过同批次首次以外不同 path 文件"等）由 bug_bug02_fixed_test.dart 4 条"否定"命名测试真实断言 |

### 总 verdict: PASS

### 行动
- dev-status.json 已置 `check_status=passed`
- 已刷新 docs/dev/baseline-coverage.json 基线快照

---

## [2026-07-05 22:00] BUG-03 - 第 1 轮 dev-check

### 检查结果

| 检查项 | Verdict | 问题数 | 详情 |
|---|---|---|---|
| 1. spec vs 原需求贴合度 | PASS | 0 | §1.2 U1"30 秒暂停后恢复应保留 30 秒" / U2"多次不应越累越多"对应 §3 S1-S5 |
| 2. 实现对 spec 忠实度 | PASS | 0 | timer_service.dart:240-253 resume 用 `now.add(Duration(milliseconds: ms))` 毫秒精度，对齐 S3/ALG |
| 3. 回归测试充分性 | PASS | 0 | bug_bug03_repro_test.dart 2 条 + bug_bug03_fixed_test.dart 11 条覆盖 S3/S4/S5/INV1/INV2/INV3/ALG 全档 |
| 4. 跨模块已识别不变量未破坏 | **FAIL** | 1 | 见下 |
| 5. 跨模块被漏识的破坏 | PASS | 0 | 全量回归 PASS；改动仅 lib/features/timer/domain/timer_service.dart |
| 6. 基线覆盖率漂移 | PASS | 0 | 同上 |
| 7. 否定断言未被破坏 | PASS | 0 | §3 S3/S4/S5 否定断言块均由 bug_bug03_fixed_test.dart "否定"命名测试断言 |

### 总 verdict: FAIL

### FAIL 问题清单

1. **§7 PRG 回归断言缺失**（@BUG-03 cross_module_impacts[0]）
   - 证据：spec 行 "在 prg_test 加 `timer 到期触发 saveProgress @ 30s 应按预期落库` 端到端用例" 无对应 test
   - 检索：`grep -rn "timer.*saveProgress\|saveProgress.*30\|BUG-03.*prg" test/features/progress/ test/features/timer/` → 无命中
   - 现象：§7 要求验证"resume 时间变化可能改变 expiry wall clock → 进度保存期间联动是否正确"；现状 prg_test.dart 中无 timer 与 saveProgress 之间端到端联动测试
   - 修复建议：在 test/features/progress/ 新增一条用例——构造 TimerService 注入 fake clock，startDuration(1) → elapse 30s → pause → resume → elapse 至 expiry → 模拟 onTrackCompleted 触发 saveProgress → 断言 progress DB 中 filePath/positionMs=30000 落库（误差 ≤1ms）

### 行动
- dev-status.json BUG-03 已置 `check_status=round_1 / check_round=1 / impl_status=pending / test_status=pending`
- 等待用户手动启动 `dev-exe BUG-03` 重做