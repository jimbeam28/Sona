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
---

## [2026-07-23 23:44] SET-01 - 第 1 轮 dev-check

### 总 verdict: PASS

三项判断检查：

| 检查 | verdict | 问题数 | 要点 |
|---|---|---|---|
| 1. 测试空壳审计 | PASS | 0 | set_01_test.dart 10 条用例逐条核对：S1 removed==3 + cache isEmpty + spy.listDirectoryCallCount==0（真否定断言）+ queue/conn/nav equals(before)；S2 removed==1 + 键删/留 + audiobookBefore.value/createdAt 原值比对；S3 removed==0 + 空 + spy==0；S4 title/subtitle/SnackBar 逐字文案 + AlertDialog findsNothing + 状态清空；S5 文案逐字 + state 保持空；S6 result equals(cached) 与 spy 网络结果可区分 + lastAccessedAt isAfter；S7 spy==0 反证键格式；INV1 四 provider（含 sortOption）双分支 equals(before)；INV2 首读命中(count==0)→clear(null)→再读 count==1 且取回网络新数据（可证伪，非摆设）；INV3 运行时读源码 contains('features/browser/') isFalse。无 isNotNull 占位/空断言 |
| 2. 实现语义忠实 | PASS | 0 | INV1：逐分支找违反路径——两分支仅写 directoryCacheProvider + invalidate directoryContentsProvider，无任何监听器把缓存变更桥接到 queue/conn/nav/sort，不可违反。INV2：browser_provider.dart:38-41 count 先记→map 清空→`ref.invalidate(directoryContentsProvider)`（family 全量，同步闭包无插入窗口），不可违反。INV3：settings_screen.dart:15 仅 import shared/di/providers.dart，providers.dart:31-32 导出 directoryCacheProvider/clearDirectoryCacheProvider。返回类型真改 `Provider<int Function(String?)>`（:35），两分支均 return int。SnackBar"已清除 N 条目录缓存"/"没有可清除的缓存"、subtitle"当前缓存 N 条目录"与 §3.2/§1.2 逐字一致。未发现 spec 未说的行为（leading icon/Divider 与既有 section 样式一致，非行为偏离） |
| 3. 跨模块破坏 | PASS | 0 | cross-imports.sh impact 输出 = browser(15 行)+main.dart，与 §7 声明一致，settings 不在引用方（经 DI 桥消费不构成违规）；cross-imports.sh all exit 0（feature-isolation clean，余下均 arch-baseline 已登记 legacy debt）；browser_screen.dart:78 调用忽略返回值，void→int 兼容（§7 BRW 行落地）；本评审自跑 test/features/settings + test/features/browser 共 225/225 PASS，主控全量 1672/1672 PASS |

settings_test.dart 修改核对（是否掩盖回归）：git diff 仅一个 hunk——SET-T23 头部加视口放大（800×2400 @1x）+ 双 addTearDown reset。四条 section header 断言（播放设置/外观/连接/关于 findsOneWidget）原样保留，断言语义零弱化。"关于被挤出视口"理由成立：SettingsScreen 用 ListView（懒加载，settings_screen.dart:28），SET-01 在"连接"与"关于"间插入"存储" section+Divider（:56-60），默认 800×600@3x 逻辑视口仅 ~200px 高，"关于" header 落在构建范围外；手法与 test/features/player/ply_14_test.dart 既有先例一致（已核实存在）。

机械项：
- `spec-scan.sh SET-01`：矩阵 S1~S7 + INV1~3 全部映射到 set_01_test.dart，无 - 行，exit 0
- `spec-scan.sh --neg SET-01`：S1/S3/S4/S5 四条 status:new 均带否定断言块，exit 0
- `coverage-check.sh check-check`：exit 0。baseline-coverage.json 此前不存在（新流程首轮 dev-check），脚本已按设计建立基线 overall=77.49%（非阻断 WARN）

Minor 观察（不阻断，不计 FAIL，供后续迭代参考）：
1. S4 否定断言"页面不跳转"以 `find.byType(SettingsScreen), findsOneWidget` 落地——可捕获 pop（home 被移除），但无法区分 push（新路由压栈时底层路由仍留在 widget 树）。实现中 _ClearCacheTile.onTap 无任何 Navigator 调用，行为本身正确，仅断言判别力偏弱。后续可改为断言 ModalRoute 深度或 Navigator 栈。
2. S2（status: modified）Then 中"directoryContentsProvider('/music') 被 invalidate"一行未在 set_01_test.dart 直接断言；该行为是 spec 修改点明示"不动"的既有逻辑（browser_provider.dart:58 invalidate(path) 原样保留），风险极低。

### 行动
- `dev-status.sh pass SET-01`：check_status=passed，写 last_checked_at
- `coverage-check.sh refresh`：PASS 后刷新基线（首轮即本轮建立的 77.49% 基线）
