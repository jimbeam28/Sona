# dev-check 评审日志

每轮评审追加一节，最末条为最新一轮。dev-exe 被打回重做时必须读本文件最末条作为修复靶点清单。

## [2026-08-21 19:32] BUG-01~19 + REF-01~16 批量审计（35 项） - 第 1 轮 dev-check

### 总 verdict: FAIL（28 PASS / 7 FAIL）

机械项：spec-scan 35/35 rc=0；cross-imports all 绿；cov-gate --only test 全绿（2430 tests）；coverage-check check-check **红**——REF-09 将 `lib/features/progress/domain/progress_policy.dart` 迁至 `lib/core/contracts/` 后基线残留旧路径两条（baseline-coverage.json:18/:45），新路径未登记。属改名簿记残留而非覆盖率回归（总覆盖 91.01% > 基线 86.61%），随本轮 PASS 刷新基线消除。

### FAIL 问题清单（7 项，全部为测试侧缺口——无需改 lib/ 生产代码）

1. **BUG-03-S6 手动切歌异常路径零测试锚定，§5.4 门禁虚标**（检查1，@BUG-03-S6）
   - 证据：docs/features/BUG-03.md:261 声明 bug_03_repro_test.dart 覆盖 S5/S6；实测该文件仅 1 用例（test/features/player/bug_03_repro_test.dart:101），只驱动 loadAndPlayProvider，从未调 skipToNextProvider/skipToPreviousProvider/selectQueueIndexProvider 异常路径；全库无 throwing orchestrator 注入。
   - 现象：S6 的 Then（守卫复位+日志+返回 failed）对三个手动切歌入口零 expect 支撑；拆回裸 await 门禁仍绿。
   - 自检：实现经共享 helper `_runLoadOrchestrated` 结构等价（player_provider.dart:364-379），缺陷纯在测试面。
   - 修复指令：bug_03_repro_test.dart 补一条用例——override playbackOrchestratorProvider 为 skipToNext 抛 TimeoutException 的 stub，依次调用三个切歌 provider，逐个 expect：返回 isLoaded==false、调用后 _completingProvider==false、日志含 `[Player]`、Zone 内无 unhandled error。
2. **BUG-04-S7 时长更新恢复生效零测试锚定，§5.4 门禁虚标**（检查1，@BUG-04-S7）
   - 证据：docs/features/BUG-04.md:241 声明门禁覆盖 S5~S7；实测 bug_04_repro_test.dart 三用例只断言 title/id/null（:86-89/:148/:200），无 duration 断言；audio_handler_test.dart:327-348 也未测 `_onDurationChanged` copyWith 分支（audio_handler.dart:174-178）。
   - 现象：「mediaItem 非空后时长更新自然生效」（U5）与「时长更新不得改 title/id/artUri」均无处落地。
   - 修复指令：bug_04_repro_test.dart 补一条用例——MockAudioPlayer.durationStream 桩改 StreamController，T1 式加载成功后 emit Duration(minutes:5)，expect handler.mediaItem.value!.duration==Duration(minutes:5) 且 title/id 不变、artUri 仍 null（顺带锚 INV3）。
3. **BUG-17 首次添加（0→1）边界零覆盖，S4 与 INV3 无任何测试触达**（检查1，@BUG-17-S4 / BUG-17-INV3）
   - 证据：spec §5.2 明文"含首次添加边界"、§5.3 再令追加 0 连接失败用例；实测 bug_bug17_repro_test.dart:44-47 两用例都预置一条连接；grep 全库 deleteWithoutGuard 无任何测试触达 count==1 场景。
   - 现象：deleteWithoutGuard 的存在意义（0→1 时守卫版 delete 抛 LastConnectionException 使回滚失效）零守护；把 connection_service.dart:95 改回 `_dao.delete(id)` 一行，现有测试照样全绿。
   - 自检：dev-exe 只实现了 S4 代码面、漏了 spec 两处明文派发的测试面。
   - 修复指令：bug_bug17_repro_test.dart 删除 _setup() 预置 insert 后追加三用例（步骤 2 storage 写失败 / 步骤 4 update 失败 / 步骤 5 setActive 失败各一）：expectLater(service.save(...), throwsA(isNot(isA<LastConnectionException>)))，随后断言 findAll() isEmpty 且 storage.peek('connection_password_1') isNull。
4. **BUG-19-INV1 全库清场承诺未兑现——test/ 下仍有 6 处内联 CREATE 副本，其中 ply_10 是活跃的迁移逻辑重实现**（检查2，@BUG-19-INV1 / BUG-19-S6 否定断言3）
   - 证据：INV1 声称修复后 grep 除 v1 历史输入外 0 命中，实测命中：ply_10_test.dart:363-385（PLY-T55 注释自述 "as the migration would"，手写 CREATE TABLE playlists/playlist_tracks + INDEX，且从未触发真实 onUpgrade）、ply_13_test.dart:778-794/:803、ply_14_test.dart:286-302/:311、brw_04_test.dart:291-310、brw_07_test.dart:356-375、con_06_test.dart:65-73（CON-T31 "simplified version" schema 已漂移实证）。
   - 现象：cr 原文复现路径在这 6 个文件原样成立——改坏生产 DDL 或副本彼此漂移，相关测试依旧全绿；spec §7 inventory 漏登它们的自建库段落。
   - 自检：§5.3 派给 dev-exe 的"手动 grep 一次性核对"未执行或漏检（均为本次 commit 未触及的既有代码）。
   - 修复指令：ply_10 PLY-T55 改经真实 open 路径驱动（复用 db_migration_test.dart:107 `_runRealV1ToV2Migration` 模式）或删除该用例（意图已被 DB-MIG-03/04 覆盖）；ply_13 TST-T82、ply_14 TST-T87、brw_04 TST-T128、brw_07 TST-16 改用 `openTestDatabase(TestSchema.playlist / .full)`；con_06 CON-T31 改 `openTestDatabase(TestSchema.progress)`；确属历史形态输入的按 dev-plan 流程补登记豁免，不得静默保留。
5. **REF-05-S4 「删除当前曲→高亮跟随」核心状态变化未被真正锚定，isNotNull 占位**（检查1，@REF-05-S4/U2）
   - 证据：test/features/player/ref_05_queue_sheet_live_test.dart:133-140 —— `expect(currentTile.title, isNotNull)` 占位；若高亮错误地留在旧 index（c.mp3 行），本用例依然全绿。
   - 现象：Scenario U2/S4 核心变化（『当前』标记移到新当前曲目行）不可判伪。
   - 修复指令：将 ref_05_queue_sheet_live_test.dart:140 的 `expect(currentTile.title, isNotNull)` 替换为 `expect((currentTile.title as Text).data, 'a.mp3')`（或 find.descendant 定位断言）。
6. **REF-06-S8 否定断言「生产调用必须传活跃连接 id」零回归护栏，门禁仅模拟不锚定**（检查1，@REF-06-S8）
   - 证据：ref_06_cache_clear_test.dart:198-205 测试自己手工传 id，从未执行 browser_screen.dart:83-85 真实 onRefresh 体；若 :85 被改回传 null，编译过、静默降级后缀匹配，全仓无一测试失败。
   - 自检：盲点源于 spec §5.4 规定的模拟式覆盖手法（同 brw_05/set_01），属 dev-plan 设计缺口，打回对象需裁。
   - 修复指令：ref_06_cache_clear_test.dart 追加静态源断言用例（仿 ref_10_unify_test.dart:97-117 File 读源模式）：读 lib/features/browser/browser_screen.dart 源码，expect contains `'clearDirectoryCacheProvider)(connId, currentPath)'` 且 isNot contains `'clearDirectoryCacheProvider)(null,'`。
7. **REF-11 门禁测试名承诺「0 分钟禁用确认」但无任何对应断言**（检查1，@REF-11-S3/S6）
   - 证据：ref_11_timer_sheet_test.dart:200-217 函数体仅断言『自定义时长』与确认 TextButton 存在；全程未滚到 0h0m，也未断言 onPressed==null。timer_button.dart:184-185 禁用分支若被删，本门禁仍绿。
   - 修复指令：该测试内追加：drag ListWheelScrollView 至 hour=0/minute=0，pumpAndSettle 后 `expect(tester.widget<TextButton>(find.widgetWithText(TextButton, '确认')).onPressed, isNull)`，再滚回非零断言非 null。

### PASS 附带低危备注（不阻断，登记备查）

- REF-02：equality_registry 测试 ConnectionConfig 用例循环体近似退化（实际防护由 model_equality_test 承担）。
- REF-03：mirror 测试 public-method 正则匹配不到 `Future<void>` 形态声明（死符号黑名单已补偿指定符号）。
- REF-04：S4 否定断言「不调 player.stop/pause/seek」无 verifyNever（人工核读确认只读状态）。
- REF-12：S6/S7 未直接断言 defaultSpeedProvider 值（ply_07/set_01 已补偿该面）；TST-T73~78 保留容器形态与 §3.2 措辞张力。
- REF-14：S8/S9 明令移除的 `import 'dart:async';` 仍在 bug_10_test.dart:10 与 bug_bug32_repro_test.dart:16（有显式 Future 引用故 analyze 不报；零行为影响，dev-exe 重做时可顺手删）；范围外 storage_utils_test/bug_07_test 仍有本地挂起 fake，建议后续 REF 收敛。
- REF-16：coverage-check.sh 新增 load_debt 尾部 `return 0` 与 spec"零改动"字面冲突——实为化解 spec 内部矛盾（登记簿变纯注释结尾会使 check-exe 假失败）的最小必要修复，已在代码注释+commit message 双重登记；**需 dev-plan 增量补一条 Scenario 回写 spec，严禁直接改 features 文档**。
- REF-08：spec REF-08-S4 否定断言第 3 条与 §3.2 表自相矛盾（实现取"循环前取时一次"符合主导裁决，不改判）。
- BUG-01：S5 第二否定断言（skip 不动 playbackState 其它字段）无用例锚定；测试组名 S1/S2 实为 S4/S5 内容（cosmetic）。
- BUG-02：只断言回调非 null，未驱动回调触发行为面；onDispose 清线分支无断言（接线体 4 行，风险低）。
- BUG-06：实现新增第三道闸 `_sourceStillIssed`（audio_source_builder.dart:173/:186-193）超出 §3 文本——判定为良性增强（正是 §5.3 盲点表点名的补口），已核实 identical 语义与 pub 缓存源码。
- BUG-08：INV3「<5s 正常完成不变」无直接用例（SDK .timeout 透传语义，风险极低）；P17 表回写 platform-pitfalls.md 未见记录 [待复核]。
- BUG-11：点击导航未驱动（onPressed 1 行 context.push 同款既有模式）；S4/S5 二级否定断言（PopupMenu 不变/不触发 setActive）未落地。
- BUG-12：S3 否定断言「不得发起 PROPFIND」未以 mock 调用数落地（validator false → screen 提前 return 属既有结构，风险低）。
- BUG-15/16/18：部分二级否定断言由结构或既有测试间接承载，materiality 低。
- BUG-03/07 共性既有暴露面：removeTrackFromQueueProvider 内部 loadAndPlay 抛错浮出 fire-and-forget 调用点（player_screen.dart:254 / mini_player_bar.dart:152）——修复前即存在，建议后续 cr 登记 FRAGILE。

### 结论与行动

- 28 项 PASS → `dev-status.sh pass <ID>`（BUG-01/02/05/06/07/08/09/10/11/12/13/14/15/16/18 + REF-01/02/03/04/07/08/09/10/12/13/14/15/16）+ coverage-check refresh（消 REF-09 改名基线残留，总覆盖 91.01% 单调上行）。
- 7 项 FAIL（BUG-03/04/17/19、REF-05/06/11）→ `bump-round`，impl/test 回 pending；全部为测试侧缺口，dev-exe 重做不需触碰 lib/（REF-06 打回对象含 dev-plan 补 Scenario 裁决项）。请手动启动 dev-exe 逐项重做。

## [2026-08-22 12:47] BUG-03/04/17/19 + REF-05/06/11 返工复审 - 第 2 轮 dev-check

### 总 verdict: PASS（7/7）

审计对象：commit 71ce62e（纯测试侧 delta，lib/ 零改动）。逐项核对第 1 轮修复靶点落地情况：

| ID | 靶点 | 落地证据 | verdict |
|---|---|---|---|
| BUG-03 | S6 三入口异常路径 | bug_03_repro_test.dart 新用例：throwing orchestrator stub → 三 provider 各返回 isLoaded==false + `[Player] loadAndPlay failed` 日志捕获 + 第二次 completed 正常 pause（守卫复位行为面，pauseCalls==1）+ 挂起 Completer 清理 | PASS |
| BUG-04 | S7 时长更新 + INV3 | bug_04_repro_test.dart T4：durationStream 改 StreamController，加载成功后 emit Duration(minutes:5) → mediaItem.duration 等值断言 + title/id 不变 + artUri isNull | PASS |
| BUG-17 | S4/INV3 首次添加边界 | bug_bug17_repro_test.dart 三条 0→1 用例（步骤 2/4/5 失败各一）：throwsA(isNot(LastConnectionException)) + findAll isEmpty + permanent key peek isNull + count()==0 否定面；真 DAO + openTestDatabase 生产路径；既有 S1/S2 未动 | PASS |
| BUG-19 | INV1 六处清场 | ply_10 PLY-T55 删除（迁移意图已由 DB-MIG-03/04 真实驱动覆盖，留档注释）；ply_13/ply_14 → openTestDatabase(TestSchema.playlist)；brw_04/brw_07 → TestSchema.progress + FK 感知 seedConnection；con_06 漂移 schema 删除、列名对齐生产（duration_ms/last_played_at）。六文件 grep CREATE TABLE 零可执行命中 | PASS |
| REF-05 | 高亮跟随判别力 | 占位 `isNotNull` 替换为 `(currentTile.title as Text).data == 'a.mp3'` 定位断言——高亮留旧 index 行时 FAIL | PASS |
| REF-06 | S8 静态护栏 | 新增源码静态断言：contains `(connId, currentPath)` + isNot contains `(null,`——onRefresh 改回传 null 时必红 | PASS |
| REF-11 | S3/S6 归零禁用 | 默认态确认 onPressed isNotNull + jumpToItem(0) 后 onPressed isNull + 回滚非零恢复 isNotNull——禁用分支被删时必红 | PASS |

### 机械项

spec-scan --gate ×7 / repro-test ×4 / 覆盖矩阵 ×7 / cross-imports all 全绿；cov-gate ALL PASS（全量 2435 tests，pre-push hook 复跑再证）；coverage-check check-check 绿（基线 91.20%）。

### 基础设施备注（不属任何 ID，不阻断）

1. **基线陈旧键死循环修复**：refresh 的 critical 文件清单从旧基线 critical_files 键回读，REF-09 改名遗留的 `lib/features/progress/domain/progress_policy.dart` 键（值 0）自我永续导致 check-check 恒红。本轮手工删除该键后 refresh 重生成（91.01→91.20% 单调上行）。若后续再有文件改名，同样需手动清键。
2. cov-gate.sh DEFAULT_CRITICAL 仍含旧路径（运行时 [SKIP] 不致命），建议下次触及该脚本时顺手同步。
3. REF-11 采用 FixedExtentScrollController.jumpToItem 替代 drag 驱动滚轮——经真实 onSelectedItemChanged 通知路径，判别力等价且确定性更强。

### 行动

7 项全部 `dev-status.sh pass` + coverage-check refresh。队列清空。

## [2026-08-23 13:07] BUG-20/21/22 + REF-17/18 - 第 1 轮 dev-check

### 总 verdict: PASS（5/5）

审计对象：commit f1e1419（BUG-20/21/22）+ 4921131（REF-17/18）。从 §1.0 用户原话推回：U1-U3 期待（后台进度不丢/末曲拖动可用/删单无幽灵/装配点显式化/重建不重放写库）均有对应 Scenario 且实现落地。

**检查 1 测试空壳审计 — 全 PASS**

| ID | 门禁测试 | 判定 |
|---|---|---|
| BUG-20 | bug_bug20_repro_test.dart | 真断言：S1 对照组恒真锚定 + S2-T01 计数 3（修复前停 2）+ S2-T02 ≥4（修复前停 2）；脚手架修订（UncontrolledProviderScope 保活退页）合理——整树 pumpWidget(SizedBox) 会连带销毁根容器、与 INV1 自身机制混淆，spec §2/§5.4 已追认，断言逐字未动 |
| BUG-21 | bug_bug21_completed_seek_test.dart | verify(seek(0)).called(1)+verify(pause).called(1)；否定面 `same(before)` 对象同一性 + verifyNever(play()) |
| BUG-22 | bug_bug22_repro_test.dart | 真 SQLite 预热缓存→删→空；否定面 idB 删除后 idA 内容逐项不变 |
| REF-17 | con_06 / bug_bug10 零断言改动全绿 | re-export 兼容性成立 |
| REF-18 | con_04/06/09 + bug_bug10 + int_g01 调用形态纯机械替换 | 唯一删行 con_06:377 有 spec §5.1 明文授权 |

**检查 2 实现语义忠实 — 全 PASS**

- BUG-20：player_screen.dart dispose 仅移除 cancelPlaybackSubscriptionsProvider() 调用，INV2 收尾保存 `_saveProgressWithContainer` 保留在位；cancelPlaybackSubscriptionsProvider 定义未删（prg_test 引用不受影响）
- BUG-21：nq==null 分支 `unawaited(player.seek(Duration.zero))` 插于 pause 之前，dart:async import 在位（player_provider.dart:4），守卫复位行未动
- BUG-22：invalidate(tracks(id)) 先于 list，顺序同 spec 修改点
- REF-17-S2：异常类体原样上提 database_contract.dart（const 构造+toString 一致）；dao 改 re-export show；connection_provider :15 按 round-1 补登记收窄为 `show ConnectionDao`（spec §7 已授权该修订）
- REF-17-S3：cross-imports.sh provider-platform 检查并入 all，扫描模式含五平台包，白名单两行 kind+file 登记 arch-baseline
- REF-18：两 provider 闭包体语句与 S0 逆抽序列逐字一致（debugPrint→setActive/delete→invalidate×2→CON3 条件钩子）；build 体零写副作用零 invalidate
- 未发现给 INV 找到可违反路径；未发现 spec 外自由发挥的 lib/ 改动

**检查 3 跨模块破坏 — PASS**

cross-imports.sh all EXIT=0（provider-platform 生效，两 BASELINED 行命中豁免）；impact 反查与各 spec §7 声明一致；cov-gate --only test ALL PASS（2442 tests, 261s, EXIT=0）。

**机械项**

spec-scan ×5 EXIT=0；repro-test pass ×3 ✓；coverage-check check-check OK（总覆盖 91.19%，漂移 0.01% ≤ 容忍）。

### 非阻断问题（随 PASS 登记，不回退本轮 verdict）

1. **TEST-GAP/Minor**：bug_bug20_repro_test.dart 头注释 L21 与 group 名把 10s 自动保存用例误标为 "BUG-20-S2-T02"（应为 BUG-20-S3-T01），致 spec-scan BUG-20-S3 行 gate 文件显示 "-"。修复指令：将该文件 L21 注释与对应 group/test 标签改为 BUG-20-S3-T01。
2. **FRAGILE/Minor**：ID 复用撞车——旧批次遗留 test/features/progress/bug_bug20_repro_test.dart（progress 清除窗口）与 test/features/player/bug_bug22_interruption_stream_test.dart（音频中断流）仍以同 ID 命名留存，新批次 BUG-20/22 spec 复用 ID 后 spec-scan 模糊匹配将新 INV 映射到旧目录文件。修复指令：两遗留文件头注释首行追加"[历史批次 BUG-20/22，ID 已被新 spec 复用，本文件属已归档旧项]"消歧标注。
3. **INFO**：REF-17-S1 豁免条款落点为 cr-dimensions.md 维度3（硬约束第3条实际宿主，措辞与 spec 逐字一致），非 spec 字面的 CLAUDE.md §0.3——CLAUDE.md 现文并无该节，属 dev-plan 引用错位，实质合规。
4. **INFO**：f1e1419 携带超范围测试加强（int_g01/aud_01/aud_05 自演自证壳改为真实驱动生产路径，溯源 cr-20260822-2051 T1/T2），方向正确但 commit message 未逐字声明。

### 行动

5 项全部 `dev-status.sh pass` + coverage-check refresh。

### 第 1 轮问题收尾（2026-08-23）

非阻断问题 1/2 已修复：bug_bug20_repro_test.dart 用例标签改为 BUG-20-S3-T01（spec-scan S3 行恢复 gate 映射）；两个历史批次遗留文件头加 ID 复用消歧标注。受影响 3 个测试文件 32 用例全绿，analyze 零新增（208 条 info 为 HEAD 存量）。问题 3/4 属 INFO 记录性条目，无需动作。

## [2026-08-23 20:19] BUG-23/24/25/26/27/28 + REF-19 - 第 1 轮 dev-check

### 总 verdict: PASS（7/7）

审计对象：commit 01a97e2。从各 spec §1.0 用户原话推回：U 系期待（重试不被旧任务打断/随机轮次删曲不断裂/重复曲目面板正常渲染/依赖显式声明/启动恢复让位用户选曲/删连接切换原子化/阈值单源）均有对应 Scenario 且实现落地。

**检查 1 测试空壳审计 — 全 PASS**

| ID | 门禁测试 | 判定 |
|---|---|---|
| BUG-23 | bug_bug23_timeout_stop_guard_test.dart | 真断言：前置 errorA isA\<TimeoutException\>（外层语义保留）+ 关键窗口 verifyNever(stop) + resultB.isLoaded + 收尾再 verifyNever(stop)；broadcast stream 桩属脚手架修订（单订阅流二次 listen 抛错被 catch 吞为 failed），断言逐字未动，合理 |
| BUG-24 | bug_bug24_shuffle_without_index_test.dart | P1 完备置换/P2 映射保序/P3 不重访三命题 × 20 种子 × 2 场景；否定面 isNot(contains) + sequential 回归守卫 + n-1==1 边界 + INV1 advance/retreat 互逆；头注释如实记录初版门禁与 spec Given 自相矛盾的重写过程，现版忠实编码 S1/S2 |
| BUG-25 | bug_bug25_queue_sheet_dup_key_test.dart | 键集合唯一性 toSet().length == length（修复前 2≠3 缩水 FAIL）+ 渲染完整性 findsNWidgets(3) + "当前"标记唯一；头注释如实说明 sliver 惰性列表无 duplicate-key 异常信号、故锚定 INV1 本体 |
| BUG-26 | bug_bug26_pubspec_state_notifier_test.dart | 主依赖段正则锚定 + 前置非空守卫防门禁空转（结构断言先例合规） |
| BUG-27 | bug_bug27_restore_race_test.dart | 可控 Completer DAO 确定性开窗 + same(userQueue) 对象同一性核心断言 + verifyNever(seek) + restoreError isNull 前置 |
| BUG-28 | bug_bug28_txn_activate_test.dart | 结构代理门禁（§5.3 明文授权：崩溃注入不可行）——is_active 处理在事务闭包内 + 事务外无 findAll/setActive 残留 + deleteWithoutGuard 保持无 CON-T32 守卫；行为回归真 SQLite 终态恰一活跃 |
| REF-19 | ref_19_threshold_single_source_test.dart | lib/ 全量扫描 >= 5000 零命中 + 前置 policy 定义存在防空转 |

**检查 2 实现语义忠实 — 全 PASS**

- BUG-23：playback_orchestrator.dart:233-235 与 spec §7 修改点逐字一致（isLatest→superseded / stop+failed 二分）；成功路径 :204/:239 既有守卫未动
- BUG-24：ALG1 映射式重写 play_queue.dart:212-225 与 §6 伪码一致；anchor<0 兜底 newOrder.length-1 与 withIndex :155 既有的"排除曲退化到队尾"约定同构，非自由发挥；边界裁决表五行全部落实（sequential 不入分支、n-1==1 双 null、startPositionMs 规则保留）
- BUG-25：queue_sheet.dart 复合键 '$index:$path' 逐字符合 spec；insertAfterCurrent 不去重语义与按索引删除契约零触碰
- BUG-26：pubspec.yaml dependencies 段 http 之后追加 state_notifier ^1.0.0（含溯源注释），pubspec.lock 同步 "direct main"，riverpod 条目零变更
- BUG-27：player_provider.dart:233-235 identical 复核插于写回前，abandon 分支零写入零 seek，与 §7 修改点逐字一致
- BUG-28：delete/deleteWithoutGuard 双方法同事务内联 txn.query(created_at ASC limit 1)+txn.update，无 setActive 嵌套；CON-T32 守卫位置与 wasActive 返回值不变；findAll :43 orderBy 'created_at ASC' 证实激活目标排序声明成立。实现省去 spec 文字中的"清零全部 is_active"步骤——≤1 活跃不变量下该步恒为 no-op，终态逐状态等价，不构成偏离
- REF-19：两处 UI 表达式替换 + show ProgressDao import，policy 本体与 dialog 零变更
- 对抗检索：未发现任何一条 INV 存在可违反路径；lib/ 改动无 spec 外自由发挥

**既有测试改动审查（2 处，均放行）**

1. ref_05_queue_sheet_live_test INV2 断言改写：BUG-25 spec 有意取代 ValueKey(path) 契约，旧断言与新规约直接冲突必须同步；新断言保留 P13 意图（ValueKey\<String\> + 锚定业务 path 后缀 + 集合唯一）。REF-05.md 措辞漂移已由测试注释登记"待 dev-plan 增量补"，符合 CLAUDE.md 文档滞后条款。
2. bug_bug24 门禁测试自修：初版与 spec 自身 Given 矛盾（裸构造器指针锚槽位 0 / advanceShuffle 单向遍历数学不可达），现版经上表判定忠实。

**检查 3 跨模块破坏 — PASS**

cross-imports.sh all EXIT=0（仅 2 条 BASELINED legacy）；impact 反查 play_queue 引用方（browser/browser_provider/playlist_detail/player_provider/playback_controls/player_screen_logic/playback_orchestrator）均在 BUG-24 §7 反查文本内；cov-gate --only test ALL PASS（2496 tests, 268s, EXIT=0）。

**机械项**

spec-scan ×7 矩阵全命中；repro-test pass ×7 ✓；coverage-check check-check OK（零漂移）。

### 非阻断观察（随 PASS 登记，无需动作）

1. **INFO**：loadAndPlay 的 startPositionMs seek（playback_orchestrator.dart:195）位于 :204 isLatest 守卫之前——被取代任务的 setup 型 seek 理论上可落在后继请求加载窗口内。属本批 spec S0/S0b 明文锚定的现状（修改点仅为 ：229-231），非本轮引入；若未来走查升级 INV1 到"setup 动作全覆盖"需另行 dev-plan。
2. **INFO**：bug_bug25 测试未直测 U2"删除第 N 行只移除该位置条目"——删除链路契约按 spec 否定断言要求保持不变，由 ref_05 S6 回调接线用例承载，可接受。

### 行动

7 项全部 `dev-status.sh pass` + coverage-check refresh。
