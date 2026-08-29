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

## [2026-08-24 09:05] PLY-01 + TMR-01 + BRW-01 - 第 1 轮 dev-check

### 总 verdict: PASS（3/3）

审计对象：commit 4e82e01（PLY-01）/ 8b98b48（TMR-01）/ 8e5652d（BRW-01）。从各 spec §1.0 用户原话推回：U 系期待（长按拖动且当前曲跟随/shuffle 拖不动/重排冷启动保持/慢网加载中可重排；最后 10 秒渐弱到零再静默停止、取消最迟 1 秒恢复、播完当前曲不淡出；目录长按两入口/递归先序排序一致/500 截断提示/中途失败不用半截结果/新建即加入）均有对应 Scenario 且实现落地。

**检查 1 测试空壳审计 — 全 PASS**

| ID | 门禁测试 | 判定 |
|---|---|---|
| PLY-01 | ply_01_queue_reorder_test.dart | ALG1 黄金表 §6 七行逐行断言 + S1 值对象语义 identical 反证 + 四元字段经 toMap 持久化层核对 + verifyZeroInteractions(player)；S5 三模式循环断言 onQueueChanged 恰一次 + verifyNever(play/pause/stop/seek) + saver.calls 空；S11 手控 Completer 挂起 setAudioSource 后 moveTrack，断言 X 以原请求完成且 setAudioSourceCalls 恒 1（spec §5.3 盲点补偿如实落地）；S10 真 SharedPreferences 集成断言 _qKey filePaths/currentIndex 落盘 + connection id 不变否定面；INV2 含 UI/persistence 层 `.move(` 源码扫描守卫。无空壳 |
| TMR-01 | tmr_01_volume_fade_test.dart | ALG1 黄金表八行 + [0,1] 区间性质测试（含 -1h/-1ms/10001ms 边界）；S3/S4 verifyInOrder(setVolume(0.0)→pause→setVolume(1.0)) + verifyNever(stop) + 到期后 tick verifyNoMoreInteractions；S4 三态（null/afterCurrent/>10s）verifyZeroInteractions；S5 写 0.4 级中间值取消后下一 tick 收敛 1.0（spec §5.3 盲点补偿落地）；S6 双 tick pause 恰一次幂等闸（盲点补偿落地）；INV1 lib/ 全量文件扫描守单一写权；INV3 afterCurrent 与 paused 冻结窗口内均断言 writtenVolumes 无 <1.0。无空壳 |
| BRW-01 | brw_01_folder_actions_test.dart | collectFolderAudio 六行黄金表 + fetchDir 调用次序数组精确断言（root→A 先序非广度）+ S2 截断后 `/r/B` 零多余 fetchDir + S3 多层混合错误 calls 序与 throwsA(message) 保留（盲点补偿落地）；S4 三态含 null-onLongPress 吞手势不误触 onTap 否定面；S5 loading 出现/消失 + 队列/连接 id provider 写入断言 + 600 文件截断 SnackBar '已截取前 500 首'（盲点补偿落地）+ 空结果不建队不导航；S6 completeError → 固定文案 + 异常原文 findsNothing 脱敏断言 + 双 provider 未写否定面；S7 AsyncError 态渲染 + 新建入口可用（盲点补偿落地）；S8 空名禁用确认不调 service + ' My Mix ' 原样入库（REF-07）+ createPlaylistProvider 未被调否定面。无空壳 |

**检查 2 实现语义忠实 — 全 PASS**

- PLY-01：PlayQueue.move（play_queue.dart:272-308）与 §6 ALG1 映射逐步一致（手验七行样例全对）；防御短路五分支返回 this 零拷贝符合 S3；shuffle 闸在模型层（move 首行条件）；moveTrack（playback_orchestrator.dart:415-424）identical 复核后才写 setter——S6"无回调"由赋值点保证；grep 实证 PlayQueue.move 生产调用点仅 playback_orchestrator.dart:418 一处（INV2）；ALG2 校正 + old==new no-op 在 queue_sheet onReorder 内联实现；双入口接线 + unawaited 形态符合 S9
- TMR-01：timerTickWithFadeProvider（player_provider.dart:69-89）与 spec §3.3 参考实现逐行等价（lastWritten 闭包门/到期顺序/恢复分支）；契约 diff 纯追加（contract :77 一行 + adapter :90-91 透传一行），既有签名零改动符合 S1 否定面；grep 实证 lib/ setVolume 调用点仅 player_provider.dart:76/:84 两处（同一闭包，INV1 达成）；四驱动点全部换线 unawaited(timerTickWithFadeProvider) ，checkTimerExpiry 生产调用点归零（grep 仅剩定义与 di export，S6 达成）；到期瞬间即使无前序淡出 tick（Doze 直跳过期）顺序仍为 0→pause→1.0（lastWritten 门自愈），INV4 在对抗路径下成立
- BRW-01：collectFolderAudio 用递归严格先序实现，产出与 S1 Then（[B,A1,C]）、ALG1 行2（[X,B] 严格先序裁决）、用户原话「递归先序遍历」三方一致；_playFromFolder 与 onFileTap 建队形态逐句同构（browser_screen.dart:185-195 vs 558-570：withMode/playModeProvider 只读/currentPlayQueue 单点写/valueOrNull?.id 连接归属/push '/player'）；startPositionMs 恒 null（INV3 有 toMap 层测试锚定）；截断文案引用 kFolderScanMaxFiles 常量非手写 500（INV4）；di 补导出 playlistServiceProvider 且 browser→playlist 方向唯一（S9）
- 对抗检索：三条 INV 未找到可违反路径；lib/ 改动无 spec 外自由发挥（BRW-01 新增的 addTracks/create 失败 catch + SnackBar 属 SCHEMA §5 catch-log 全局裁决的落实，与 S6 先例同构，非越权）

**检查 3 跨模块破坏 — PASS**

cross-imports.sh all EXIT=0（仅 2 条 BASELINED legacy）；impact 反查三批改动文件的引用方（player_screen/mini_player_bar/browser_provider/playlist_detail_screen/orchestrator/adapter/home 等）均在各自 spec §7 声明范围内；cov-gate --only test ALL PASS（2569 tests, 267s, EXIT=0）。

**机械项**

spec-scan ×3 矩阵全命中（S/INV 全部映射到门禁测试文件）；coverage-check check-check OK（91.56% vs 基线 91.39%，总覆盖上行，单文件零漂移）。repro-test 不适用（三件均为新功能非 Bug）。

### 非阻断观察（随 PASS 登记，无需本轮动作）

1. **Minor**：本批两个新测试文件各引入一条 info 级 unnecessary_import——ply_01_queue_reorder_test.dart:10（play_mode.dart 经 player_provider 已提供）与 tmr_01_volume_fade_test.dart:6（fade_policy.dart 经 shared/di 已提供）。CI 门禁 --no-fatal-infos 容忍，analyze 总数 208→209 条全 info 零 warning/error。下次任一相关 ID 进 dev-exe 时顺手删除这两行 import 即可。
2. **INFO**：PLY-01-S9 两处生产入口接线由源码 contains 断言锚定（player_screen/mini_player_bar 的 _showQueueSheet 为私有函数不可 widget 直测），配合弹窗宿主转发用例 + INV2 spy 用例分段覆盖全链路，可接受。
3. **INFO**：BRW-01 spec §3.1 内嵌迭代版伪码与其自身 S1 Then / ALG1 行2 相矛盾（伪码本层音频全收后再入栈会产出 [B,C,A1]/[B,X]），实现按规范性语句（Scenario Then + ALG 样例 + 用户原话「递归先序」）取递归严格先序，行为正确。spec 伪码属 dev-plan 文档瑕疵——按 CLAUDE.md 纪律，若需修正须走 dev-plan 流程，不在 check 直接改文档。
4. **INFO**：TMR-01 spec INV3 证据括号内"paused 冻结 <10s 会持续写入 <1 常数"的假设性推演与 INV3 本句"paused 从不产生 <1.0"矛盾；实现取 INV3 本句语义（paused → active=false → target 恒 1.0）且有测试锚定。同条 3：文档措辞问题归 dev-plan，不影响行为。

### 行动

3 项全部 `dev-status.sh pass` + coverage-check refresh。

## [2026-08-24 12:10] SRCH-01 - 第 1 轮 dev-check

### 总 verdict: FAIL（3 打回项 + 2 随轮 Minor）

审计对象：commit 6bdffd3。从 spec §1.0 用户原话推回：U1–U9（放大镜开合 / 半秒自动搜+状态行 / 点行即播带续听对话框 / 音符插下一曲 / 无队列置灰 / 200 截断可取消 / 单层失败跳过 / 无匹配文案 / 收起或切连接全清）均有对应 Scenario 且主体落地——S1–S4 域层、S8 入口挂载（breadcrumb_bar.dart 零改动核实）、S9 四象限状态行、S10 三分支进度镜像 + 真对话框 + 消失文件 + 整体失败脱敏、S11 三态按钮均真实断言非空壳。但存在以下问题：

**检查 1 测试空壳审计 — 部分 FAIL**

- S5 空白 query 用例（srch_01_folder_search_test.dart:453-488）断言 `hits isEmpty`，但其前置扫描被 gate 挂起从未产生命中——断言恒真，无法区分"保留旧结果"与"复位零结果"两种实现，未钉死 spec S5「回到'已打开但零结果零扫描'态」的状态迁移。
- **[F3] §5.3 第三行承诺的盲点补偿「S7 连接切换清理」未交付**：spec §5.3 明确要求 notifier/widget 级测试触发连接切换后 state 复位且 sub.cancelled；srch_01_folder_search_test.dart 全文无任何 activeConnectionProvider 切换触发点。修复指令：widget 组新增用例——完成一次有命中的扫描后重新 pumpWidget 覆盖 activeConnectionProvider 为另一 id 的连接，断言 searchSession 复位为关闭初值（panelOpen=false/hits 空/dirsScanned=0），且对旧扫描 gate complete 后 hits 保持空（订阅已取消）。
- **[F5·Minor] S10① resume==false 分支（从头播并清进度）无专测**：三分支只测了 true 与 null。修复指令：preset 进度 store → 点击行 → 对话框点"从头播放"钮 → 断言 progress store 条目被清除且 queue.startPositionMs 为 null。

**检查 2 实现语义忠实 — FAIL**

- **[F1·Major] 跨 query 命中累积：新一轮扫描不清 hits，多轮结果永久叠加**。证据链：browser_provider.dart:376 `_startScan` 的 copyWith（:382-388）不含 `hits`；:406 `_onEvent` 对 HitFound 一律 `[...state.hits, hit]` 尾追；全文件除 closePanel 外无任何清空点，ScanDone 分支（:410-415）只写 running/truncated/skippedDirs——:384 注释所称"保留上一轮命中直至完成态覆盖"的覆盖点在代码中不存在。可违反路径：输入'晴'等扫描完成得 N 条命中 → 改输'晴天版' → 终态 hits = 两轮并集，S9 状态行'命中 M'计数虚高。违反 §1.0 定稿版「当前页面显示所有相关的音乐」（按当前 query）、U2、S6 单流归约前提。现有测试全部绕过：S5 双轮用例第一轮 gate 挂起零命中、S6-late 用例第二轮即被取消，故全绿。修复指令：
  1. browser_provider.dart:382 copyWith 增加 `hits: const []`；
  2. onQueryChanged 空白分支（:367-371）按 S5 字面改为整体复位开面板初值：`_sub?.cancel(); state = const SearchSessionState(panelOpen: true);`（替换现 `state = state.copyWith(running: false, query: '')`）；
  3. 同步删除注释中不存在的"S6-late"语义声明；
  4. 新增门禁测试：第一轮有命中完成后换 query 重扫 → 终态只含新 query 命中且 dirsScanned 重计；有命中状态下输入空白 → hits 清空回零结果态。
  （若 dev-exe 认为"保留旧结果直至新结果到达"是想要的产品行为，必须先回 dev-plan 增补 Scenario——不允许实现侧自行保留。）
- **[F2·Medium] fetchDir 形态偏离 §3/S10② 参照，且触及 INV2 字面**：spec S10② literal `ref.read(directoryContentsProvider(p).future)`，镜像参照 _collectFolder（browser_screen.dart:852-855）同为 read；实现两处用 `ref.refresh`（browser_provider.dart:396、browser_screen.dart:563）。后果：(a) 与主列表"从此处播放"失败面分叉——绕过缓存强制逐层网络往返，弱网下点击播放比同动作更易落入 catch SnackBar；(b) INV2 字面「搜索扫描自身只读——除 session 状态外不写任何 provider」，refresh 逐层改写 directoryContentsProvider 缓存状态（200 层冲刷 LRU），字面构成 provider 写副作用；(c) 属 §3 未声明的自由发挥。修复指令：两处回退为 `(p) => ref.read(directoryContentsProvider(p).future)`；若坚持新鲜读语义须先回 dev-plan 出增补 Scenario + INV2 措辞修订再实施。
- **[F4·Minor] ScanProgress 相对 §3.1 参照实现被上移到本层命中之前**（folder_searcher.dart:77 vs spec §3.1 yield 序：命中→压栈→progress）：终态等价、无可区分 Scenario，但属对规约代码的无声明改动，且 srch_01 测试 S6 中间态断言（layer1HitSeqs contains ['m2_x.mp3']）按实现序书写而非规约序。修复指令（随本轮一并做）：folder_searcher.dart 将 ScanProgress yield 移回子目录反向压栈之后；srch_01 测试 S6 中间态断言同步改为规约序期望（dirsScanned==1 快照的 hits 应已含本层全部命中 ['m2_x.mp3','m2_x.mp3']）。

**检查 3 跨模块破坏 — PASS**

cross-imports.sh all EXIT=0（仅 2 条 BASELINED legacy）；impact 反查三文件引用方均在 browser feature 内部 + main.dart，与 §7 声明一致；cov-gate --only test ALL PASS（2657 tests, 265s）——brw/ply/prg/home 回归网全绿，INV1 关闭态渲染路径无破坏。

**机械项 — 全绿**

spec-scan SRCH-01 矩阵 S11/INV4 全映射门禁文件（ALG1 行 test_files='-' 与 PLY-01/BRW-01 已过检惯例一致，ALG 黄金+变体+边界三档实测存在）；coverage-check check-check OK（91.71% vs 基线 91.56%，总覆盖上行单文件零漂移）；repro-test 不适用（新功能非 Bug）。

### 非阻断观察（不随打回项处理，供 dev-plan 参考）

1. **INFO**：cancelScan 后 UI 形态 spec 未定义——hits 空 + query 非空时居中显示'无匹配结果'（扫描并未完成宣判）、hits 非空时状态行显示'命中 M'如已完成。建议下次 dev-plan 触及 SRCH 时增补取消后展示 Scenario。
2. **INFO**：S4 测试对 spec 示例自相矛盾处（原期望 ['am.mp3'] 与 fetched==[root] 互斥）做了正确裁决并留注释说明，处理得当。

### 行动

`dev-status.sh bump-round SRCH-01`（check_round=1，impl 回 pending）。请手动启动 dev-exe SRCH-01 重做，以本节 F1/F2/F3/F4/F5 为修复靶点清单。

## [2026-08-24 13:05] SRCH-01 - 第 2 轮 dev-check

### 总 verdict: FAIL（F1–F5 修复核验全过 + 新增 1 Minor）

审计对象：commit 5c68e3b。从 spec §1.0 用户原话推回复核：U2/U3/U5/U8/U9 在重做后逐一对回实现与测试。

**上轮靶点修复核验 — 5/5 过**

| ID | 核验 |
|---|---|
| F1 | `_startScan` 启动即 `hits: const []`（browser_provider.dart:388）；空白 query 复位开面板初值并吞挂起 debounce（:366-373）；虚构"S6-late"注释已除。两条新用例真实断言：换 query 终态只含新 query 命中且 dirsScanned 重计；有命中态输入空白 → 零结果零扫描复位 + 挂起 debounce 零 fetchDir |
| F2 | 两处 fetchDir 回归 `ref.read`（browser_provider.dart:395 / browser_screen.dart:562），与 S10② 及 _collectFolder(:853) 镜像一致（screen:80 refresh 为 BRW 下拉刷新既有代码，不在 SRCH 面）；被第 1 轮实现带偏的 4 条测试排布修正后全部否定断言本体保留（迟到事件丢弃/guard 分支/脱敏文案/零写入逐一仍在） |
| F3 | 连接切换用例真实覆盖：切 connId → ref.listen → closePanel 全清七字段断言 + 挂起订阅取消迟到命中零残留；若移除 listener 该用例必红（panelOpen/running 断言），非空壳 |
| F4 | folder_searcher.dart:74-85 yield 序与 §3.1 逐字一致（本层命中→反向压栈→ScanProgress）；S6 中间态断言按规约序书写并通过 |
| F5 | 「从头播放」用例：进度记录自 store 删除 + startPositionMs null + currentIndex=1，三断言齐全 |

**检查 1 测试空壳 — PASS**（38 用例，新增 4 条均为真状态断言；S10 三分支现已全覆盖）
**检查 3 跨模块破坏 — PASS**（cross-imports rc=0；cov-gate --only test ALL PASS 267s，brw/ply/prg/home 回归网全绿）
**机械项 — 全绿**（spec-scan 矩阵 non-ALG 零缺映射；coverage-check check-check 单文件零漂移总覆盖上行；repro-test 不适用）

### FAIL 问题清单（1 项）

1. **[F6·Minor] running 期零命中提前渲染「无匹配结果」，违反 S9 条件面**（检查 2）
   - 证据：browser_screen.dart:430-433 `if (session.hits.isEmpty) { body = session.query.isEmpty ? shrink : Center(Text('无匹配结果')); }` ——未检查 `session.running`。spec S9 Then 字面「hits 空且 **done**→居中文案'无匹配结果'」，running 分支只声明顶部状态行。可复现路径：任何新扫描首层尚无命中期间（如整轮无命中的查询），屏幕同时出现「已扫 N 个目录…」+「无匹配结果」。属 §3 未声明状态的自由发挥。
   - 修复指令：
     1. browser_screen.dart:431 空命中分支条件改为 `session.query.isEmpty || session.running` 时 `SizedBox.shrink`，仅 done 且空才渲染居中文案；
     2. 现有用例「SRCH-01-S9: running 态显示已扫 N 个目录与取消钮…」的 running 断言区补一行 `expect(find.text('无匹配结果'), findsNothing)`；
     3. 「空 hits 且 done」既有用例修复后语义不变应保持全绿，不得改动其断言。

### 非阻断观察（不随打回项处理）

1. **INFO**：cancelScan 后（query 非空、hits 空、!running）内容区将显示「无匹配结果」——spec 对取消后的内容区渲染未定义（S9 只定义 running/done 两态），维持第 1 轮观察，建议下次 dev-plan 触及 SRCH 时增补取消后展示 Scenario。
2. **INFO**：INV2 字面复核——ref.read 首次访问实例化并缓存 directoryContentsProvider 条目，属全 app 一致的懒加载缓存语义（主列表浏览同款），不构成语义写，达标。

### 行动

`dev-status.sh bump-round SRCH-01`（check_round=2，impl 回 pending）。请手动启动 dev-exe SRCH-01 重做，以本节 F6 为唯一修复靶点。

## [2026-08-24 17:10] SRCH-01 - 第 3 轮 dev-check

### 总 verdict: PASS

审计对象：commit 6af570d（唯一靶点 F6）。从 spec §1.0 推回：U8「搜不到东西→显示无匹配结果」对应 S9 条件面「hits 空且 done」，本轮修复后实现与规约逐字对齐。

**F6 修复核验 — 过**

1. 实现条件改法与指令一致（browser_screen.dart:430-433）：`(session.query.isEmpty || session.running) → SizedBox.shrink`，居中文案仅「hits 空且 done」渲染；
2. running 态用例补 `findsNothing` 否定断言（srch_01_folder_search_test.dart:950-951），若回退条件该断言必红（hold 挂起扫描下 running=true 且 hits 空），非空壳；
3. 「空 hits 且 done」既有用例零改动保持全绿——done 态渲染路径未被波及。

**对抗式穷举**：`_SearchResultsView` body 分支以 (running, query, hits) 三字段穷举四组合逐一比对 S9 Then——running∧空命中→留空 ✓ / done∧空命中∧query 非空→无匹配结果（U8）✓ / query 空→留空（S5 复位态）✓ / hits 非空→列表 ✓。本分支再无可违反路径。

**检查 1 测试空壳 — PASS**（38 用例；本轮净增 2 行断言）
**检查 2 实现忠实 — PASS**（F6 关闭；无新增自由发挥面；INV1 关闭态路径未触及）
**检查 3 跨模块破坏 — PASS**（cross-imports rc=0；cov-gate --only test ALL PASS 348s）

**机械项 — 全绿**：spec-scan 矩阵 non-ALG 零缺映射；coverage-check check-check OK（91.77% vs 基线 91.56%，总覆盖上行单文件零漂移）；repro-test 不适用。

### 非阻断观察（沿用前两轮登记，不重复展开）

cancelScan 后内容区显示「无匹配结果」仍属 spec 未定义面（S9 只声明 running/done 两态）——已两次登记 INFO，归 dev-plan 下次触及 SRCH 时增补 Scenario。

### 行动

`dev-status.sh pass SRCH-01` + `coverage-check.sh refresh`（基线单调上行 91.56% → 91.77%）。

## [2026-08-24 21:50] MSEL-01 - 第 1 轮 dev-check

### 总 verdict: PASS

审计对象：commit 6b24df3。从 spec §1.0 推回：「B3 = 批量多选：多选文件 → 批量加入播放单/建队」，五条裁决（面包屑入口/仅音频可选/tap 勾选跨目录累积/底栏四钮/排序序非点选序）+ 定稿补充（退出即清空防幽灵选择、组间进入序组内快照序、选择模式长按与 next-play 禁用）逐条对应 U1~U9 → S1~S8 落地核验。

**对抗式穷举（检查 2 核心）**：

- **INV1**：multiSelect==false 分支走原 `ListView.separated`（`_buildRow` 复用同参数），onFileTap/onFileLongPress/onPlayNext 原闭包逐字节保留（`multiSelect ? null : 原闭包` 三处门禁）→ 关闭态无可违反路径；
- **INV2**：multi_select_ordering.dart 仅 import nas_file，纯函数 snapshotOf 注入 ✅；**INV3**：playSelectionProvider 全程无 progressForFile 触点，startPositionMs 缺省 null（测试钉到 toMap 层）✅；**INV4**：browser_provider.dart 零 playlist 符号导入，picker 单点提取 widgets/playlist_picker_sheet.dart，BRW-01 `_addToPlaylistFlow`（title: dir.name 传参保形）与 MSEL 共用一实现 ✅；
- **S5 镜像性**：`GoRouter.of(context)` → 双 provider 写 → push 发起后立即 mode=false+clear（push Future 在 pop 才完成，注释论证成立且与 onFileTap 参照系一致）；空 store / connId null 两防御分支零写入零导航，否定面有专测；
- **S6 关闭≠成功**：picker 返回值语义 true⇔完成添加（含新建路径 pop(true)），widget 侧 `!ok || !context.mounted` 双守卫（P14 在位）；
- **S7**：ref.listen(activeConnectionProvider) id 变更 → mode=false+clear，零残留有专测。

**检查 1 测试空壳 — PASS**（29 用例：S5 断言链 currentIndex=0/playMode shuffle 消费证明/startPositionMs null 含序列化层/双写与零写入否定面齐全；ALG1 黄金 [a1,a2,b1]+组间序反例+过滤恰一次+空 store+字典序回退+全局去重六档；INV2/INV4 为源码扫描测试非占位）

**检查 2 实现忠实 — PASS**（无 §3 未声明的自由发挥；R2 裁决 Container+SafeArea 底栏落地，滚动几何有专测）

**检查 3 跨模块破坏 — PASS**（cross-imports impact 引用方全在 app/browser/connection 声明域；all 基线外零违规；同一 commit cov-gate ALL PASS + pre-push hook 全量 2636 绿，brw/srch/ply/home 回归网未破）

**机械项 — 全绿**：spec-scan 矩阵 S/INV 全命中（ALG 行 test_files `-` 为脚本对 ALG 的固定口径，退出码 0）；coverage-check check-check 总覆盖 91.92% vs 基线 91.77% 单文件零漂移；repro-test 不适用（非 Bug 项）。

### 非阻断观察（不随本轮处理）

1. **FRAGILE·low**：`MultiSelectSelectionNotifier.remove()`（browser_provider.dart:454-463）组清空即移除该组键 → 该目录后续重新勾选时组序移至 store 末尾（如 dirA 清空重勾后序变 [dirB,…,dirA]）。spec §3 未定义空组生命周期，键插入序契约本身自洽，无 Scenario/INV 可判违——建议下次 dev-plan 触及 MSEL 时增补 Scenario 或裁决「保留空组键位」。
2. **INFO**：多选会话期列表改非虚拟化滚动列（browser_screen.dart `_FileList` multiSelect 分支）——勾选框跨滚动稳定所需，普通浏览态虚拟化原样（INV1 守护），大目录性能属已知取舍，实现方已注释文档化。

### 行动

`dev-status.sh pass MSEL-01` + `coverage-check.sh refresh`（基线单调上行 91.77% → 91.92%）。

## [2026-08-25 10:03] DL-01 - 第 1 轮 dev-check

### 总 verdict: FAIL

审计对象：commit 7592c9f。从 spec §1.0 推回：B5 离线下载九条裁决（双入口/DB v3+Documents+.part 原子/无续传/串行/done 且本地存在才走本地/零新鲜度/手动管理/孤儿标 failed/无前台 Service）+ 入口形态变更声明（文件级入口移入长按菜单）逐条对应 U1~U9 → S1~S10 落地核验。

**检查 1 测试空壳 — PASS**：S1 迁移含 v2→v3/v1→v3 双路径 + 四旧表行数列集合零改动否定面 + DDL 层 UNIQUE 拒绝；S2 十方法全行为锁定（upsert 只更新三列、findDoneLocalPath 四态矩阵、markAllNonDoneFailed 时间戳否定面）；S3 本机 HttpServer 假源六用例（黄金分块/无 Content-Length/401/404/中途断流/chunk 静默死链，Range 与 If-Modified-Since 否定头断言在位）；S5 head-block 技术钉死 pending-at-rest、INV2 maxConcurrent==1、节流双档（1 天/0）补偿 §5.3；S6 调用序 log 锁定 INV1 + resolver 挂起 superseded 竞态；ALG1 十一格穷举 + ALG2 探针调用序逐个锁定。无占位断言。

**检查 2 实现语义忠实 — FAIL ×1**（见下方清单）。其余逐条对审通过：S6 else 分支原文保留（INV1）、resolver==null 时零新增 gate 检查点、本地命中跳过 readPassword/buildWithBasePath 有 reader.calls==0 断言；INV3/INV4 端口注入成立；INV5 三重闸（.part 原子改名/findDoneLocalPath 仅 done/updateProgress 仅 downloading）无可违反路径；§1.0 九句期待全部有对应 Scenario 且落地；入口形态变更已按 spec 声明留用户复核。

**检查 3 跨模块破坏 — PASS**：cross-imports all clean（仅基线 legacy debt）；impact 引用方全在 §7 声明域（PLY/BRW/SETTINGS/DB）；cov-gate 全量回归 2700 用例全绿（ply_02~08/net1 族 INV1 回归网未破）。

**机械项 — 全绿**：spec-scan exit 0（ALG 行 `-` 为脚本固定口径，与 MSEL-01 先例一致）；coverage-check check-check 总覆盖 91.49% vs 基线 91.92%，降幅 0.43% ≤ 容忍；flutter analyze 0 error；repro-test 不适用（非 Bug 项）。

### FAIL 问题清单

1. **clearAll 不取消进行中任务，留下无记录孤儿文件**（检查项 2，@DL-01-S9）
   - 证据：lib/core/services/download_manager.dart:378-385（clearAll 只删已知 localPath 与行，无任何 _cancelRequested 协调）；lib/features/downloads/downloads_screen.dart:151（确认对话框文案承诺「进行中的任务一并取消」）；docs/features/DL-01.md:280（S9 否定断言「清空全部…进行中任务一并取消」）
   - 现象：downloading 行的 local_path 在完成前恒为 ''（仅 setStatus(done) 才写入），clearAll 对该行实际没删到任何产物；deleteByConnection 删行后，in-flight 传输继续 → 成功路径 rename .part→saveTo 落盘，setStatus(done) 打在已删除行上静默 no-op → 磁盘留下 UI 不可见、无 DB 记录的孤儿文件（存储泄漏至卸载）；失败路径虽自清 .part 但传输本身未被中止。可复现路径：管理页存在挂起型下载条目 → 点清空全部并确认 → 放行挂起的传输 → saveTo 文件残留且 totalBytes/列表均不可见。
   - 修复指令：在 `DownloadManager.clearAll`（download_manager.dart:378）遍历 rows 时，对 `rec.status == DownloadStatus.downloading && rec.id != null` 的行先执行 `_cancelRequested.add(rec.id!)` 再删文件，最后照旧 `deleteByConnection`。语义依据：引擎 onProgress（:301）与传输后复查（:321）已消费该标志，会在下一进度刻度抛 `_DownloadCancelled` 并走 `_cleanupTransferArtifacts(saveTo)` 兜底删净 .part+成品，drainPump catch（:212）因标志在场跳过 setStatus(failed)——与单条 cancel(id) 的协作取消语义完全一致。并在 dl_01_download_test.dart S9 组补一用例：hangGate 脚本令泵停在 downloading → clearAll → complete 放行 → 断言 `findByLocation` 为 null、`_allFilesUnder(fs.downloadRoot)` 为空（无成品无 .part）、泵安静退出。
2. **IoDownloadFileSystem 异步 warm-up 竞态可把首条任务误标 failed**（检查项 2，@DL-01-S5，FRAGILE 级）
   - 证据：lib/core/services/download_manager.dart:80-85（root 未就绪时 `downloadRoot` getter 抛 StateError）；lib/features/downloads/downloads_provider.dart:36-37（provider 首读即构造，`_resolveDefaultRoot` 异步回填）
   - 现象：provider 构建后极短窗口内 enqueueMany 触发 pump，`_transfer` 读 `_fs.downloadRoot` 可能 StateError → 被 drainPump catch 标 failed，用户看到假失败需手动重试。概率低但真实（慢 IO 首启）。
   - 修复指令：给 `DownloadFileSystem` 端口加 `Future<void> ensureReady()`（IoDownloadFileSystem 实现：await 内部 root future；_TempDirFs/fake 为立即完成的 no-op），`_transfer` 在计算 dir 前先 `await _fs.ensureReady()`。不改任何测试断言，仅在 dl 测试 fake 补一个空实现。

### 非阻断观察（不随本轮处理）

1. IDownloadDao 在 spec 十方法外新增 findById / listPending（database_contract.dart:145-158）——串行泵「取最早 pending 一条」（S5）所需查询基础设施，只读、无行为外溢，不计自由发挥。
2. WebDavClient.downloadFile 绕过注入 `_httpClient` 自建 IOClient 并以空 HttpOverrides 脱离测试全局 mock（webdav_client.dart 新增 `_RealHttpOverrides` 段）——manager 层 INV4 注入端口不受影响，生产环境空 overrides 等价默认行为；每次下载新建连接属串行队列下的可接受取舍，已注释文档化。
3. `updateProgress` 以 unawaited 落库——sqflite 单写队列保序，风险可忽略；若未来换异步多通道存储需改 await。

### 行动

FAIL → `dev-status.sh bump-round DL-01`（impl/test 回 pending，check=round_1）。请手动启动 dev-exe DL-01 重做：仅需处理上述 2 条问题清单（修复指令已精确到函数），其余实现与测试保持原样，勿动既有断言。

## [2026-08-25 21:49] DL-01 - 第 2 轮 dev-check

### 总 verdict: PASS

审计对象：commit 670f65d（返工增量）。从 spec §1.0 推回复核：B5 九条裁决与 U1~U9 场景映射不变，本轮仅核验第 1 轮 F1/F2 修复靶点及增量无越界。

**修复靶点核验（检查 2 核心，对抗式）**：

- **F1 clearAll 取消协调**（download_manager.dart:389-406）：标志先于删行落位 ✅。可违反路径穷举——①放行后引擎在 post-transfer 复查处丢弃产物并跳过 failed 标记（S5 F1 用例真实异步锁定终态：文件系统 isEmpty + listByConnection isEmpty 双否定面）；②传输已先完成的竞态：status 读为 done 不打标志，走 done 删除路径同样删文件；③死链挂起：30s chunk-idle 超时 → downloadFile 自清 .part → manager 兜底清 saveTo；④跨连接隔离：listByConnection 只取本连接行。孤儿文件泄漏路径已闭合，对话框文案承诺与行为一致。
- **F2 ensureReady 端口**（download_manager.dart:49/85/274）：`_warmingUp ??=` 备忘录化防重复 resolve；atRoot 构造器 `_root != null` 直接短路；`downloadRoot` 的 StateError 分支在 `_transfer` await ensureReady 后不可达；抽象成员新增的两个实现方（IoDownloadFileSystem/_TempDirFs）均已补齐，analyze 0 error 佐证无第三方实现遗漏。
- **越界改动扫描**：diff 为纯插入（实现 +31 行、测试 +90 行），既有断言零改动 ✅。

**检查 1 测试空壳 — PASS**：新增两用例均为真状态断言——S5 F1 含前置锚（downling+.part 存在）与三重否定面（产物清空/行零回写/不误标 failed）；S9 F1 锁 UI 集成链（对话框流 + override 注入的同一 manager 实例）。测试放置的机械适配（完整中止链路归 S5 组真实异步、widget 收敛到确定性部分）已在用例注释中说明理由，属 FakeAsync 假时钟无法驱动真实 IO 的既知约束，非断言弱化。

**检查 3 跨模块破坏 — PASS**：cross-imports all clean；impact 引用方仅 downloads 特性自身（§7 声明域内）；cov-gate 全量回归 2702 用例全绿（pre-push hook 与 cov-gate 双跑一致）。

**机械项 — 全绿**：spec-scan exit 0；coverage-check check-check 总覆盖 91.45% vs 基线 91.92%，降幅 0.47% ≤ 容忍（降幅来源为 DL-01 新增约 800 行 lib 分母扩张，critical 单文件零漂移）；repro-test 不适用（非 Bug 项）。

### 非阻断观察（不随本轮处理）

1. `clearAll` 对已完成传输的迟到取消会在 `_cancelRequested` 留下永久 stale id（int 集合，量级可忽略；AUTOINCREMENT 保证不复用 id，无行为影响）。
2. 本轮 refresh 后基线总覆盖将自 91.92% 记为 91.45%（新功能代码分母效应），critical 文件全部持平或上行——属增长性稀释而非回归，后续轮次以新基线守漂移。

### 行动

全 PASS → `dev-status.sh pass DL-01` + `coverage-check.sh refresh`。manual_qa_required=true 的真机清单已在初始实施时登记 mqa-backlog.md，本轮逻辑修复无需追加。

## [2026-08-26 00:15] DL-01 - 第 3 轮 dev-check（S7 修订 v2 返工增量）

### 总 verdict: PASS

审计对象：commit d977217。本轮靶点 = dev-plan 修订 a50b7d9 的 S7 入口形态重做（用户复核裁决推翻长按菜单入口），前两轮已 PASS 的 S1~S6/S8~S10 仅做回归确认未重审。从 spec §1.0 推回四句期待逐条映射：「行尾两个按钮」→U1、「长按菜单不再有下载项」→回退(b)、「恢复 BUG-18 原形态（无进度不弹层）」→回退(a)+prg 还原、「搜索结果行明确不做」→否定专测。

**检查 1 测试空壳 — PASS**（S7 组 9 用例净重写）：U1 结构三连（Row mainAxisSize.min / descendant 有序图标集 / tooltip / onPressed 恒非 null）+ 行为落库（SnackBar+DB 含 connId/path/status）；U8 双否定（拦截文案 + 行数=1）；failed 再入队否定面；不触发行 tap 三重零写入（Player findsNothing + 两 provider null）；多选态真实驱动（checklist 进入 + Checkbox 前置锚）双图标 findsNothing；目录行 chevron 域内存在 + download 域内不存在；搜索行真实走完扫描流后全局 findsNothing（树根只放目录行排除主列表干扰源）；回退(a)(b) 分别锁「整层不弹」与「仅清除项+固定文案+进度行删除」。无占位断言。

**检查 2 实现语义忠实 — PASS**（对抗式穷举）：When①②③ 逐字落地——downloadBtn 恒接无禁用态；吞点击 GestureDetector 收窄至 nextBtn 单体（diff 证实 wrap 仅赋 nextBtn）；_FileList 透传与 onPlayNext 同款 `(!multiSelect && !=null)` 门禁；_downloadTappedFile 本体零改动复用。可违反路径逐一排除：①downloadBtn 被裹→U1 入队必败功能性钉死；②nextBtn 包裹被拆→BRW-09-S9 队列不变断言必红（穿透即触发行 tap 建新队）；③早退恢复在 context.mounted 后行为等价原 :70；④清除项转无条件渲染系早退后死分支的 analyzer 消除，内容/动作/文案逐字节保留且否定断言④有专测；⑤多选/搜索/目录三处零波及各有专测。dev-exe 中途的测试定位器修正（直取 children → descendant 穿透）经核验为 Agent A 断言超出 spec 结构规定的缺陷修正：序与集合语义原样保留，包裹层存在性另由 U1 功能链+BRW-09-S9 双重钉死，非断言弱化。

**检查 3 跨模块破坏 — PASS**：cross-imports impact 引用方全在 browser 声明域（§7 BRW）；all 基线外零违规；cov-gate --only test 全量 2707 用例绿（brw_09/MSEL/prg/srch/ply 回归网未破）。

**机械项 — 全绿**：spec-scan rc=0 矩阵无缺项；coverage-check check-check 总覆盖 91.47% vs 基线 91.45%（上行），critical 单文件零漂移；repro-test 不适用（非 Bug 项）。

### 非阻断观察（不随本轮处理）

1. **INFO**：主列表 onDownload 接线回调在 tap 时读 activeConnectionProvider 并做 `conn == null || conn.id == null` 守卫——spec 字面为闭包作用域 `conn.id!`（该作用域无 conn 变量）。tap 时读取比 build 时捕获更新鲜，守卫镜像 showFileLongPressSheet:917 同款防御（BUG-18 同族），浏览器页必有活跃连接前置下守卫不可达，判等价偏优实现，不计自由发挥。
2. **INFO**：MAN7 已追加 mqa-backlog.md:51（窄屏双按钮容纳性真机复核）——入口形态裁决「96dp Material 标准形态可容纳」唯一剩余验证面。

### 行动

`dev-status.sh pass DL-01` + `coverage-check.sh refresh`（基线 91.45% → 91.47%）。

## [2026-08-29 18:39] DL-01 / BUG-33 / REF-28 - 第 1 轮 dev-check（commit 8177b90 折叠批次）

### 总 verdict: FAIL（BUG-33 + DL-01 打回；REF-28 通过）

审计对象：commit 8177b90（dev-exe 一次提交实现三项：DL-01 折叠 S11/S12/S13 + S8 目录下载接线；BUG-33 扫描会话 fetchDir 重构；REF-28 两处 ValueKey）。从各 spec §1.0 推回：
- **DL-01**：U10（真实下载能完成）→ S11 生产接线；D1 → S12 收敛 Dao；D3 → S13 时钟注入。B5-8 启动恢复语义不变。
- **BUG-33**：F1 三句期待（一次密码读 / 不挤缓存 / 切连接行为不变）→ S2/S3 落地。
- **REF-28**：D2 用户裁决「修」→ S1/S2 补键。

**检查 1 测试空壳 — PASS**（新测试全部真断言，无占位）：
- bug_33_repro_test：F1 锚（3 层扫描 readCalls==1）+ S2 否定（扫描前后 directoryCacheProvider size 不变）+ ALG1（跨层 listDirectory 密码一致且读恰一次）。
- bug_b1_wiring_repro_test：T1 载体，build 真实 downloadManagerProvider，`calledUrls.single == webDavEffectiveBaseUrl(conn.url, basePath)`，前置 pending→done 完成等待。
- dl_01_download_test 新增：S11 双连接基址逐条正确（`['http://conn1','http://conn2']`）+ 否定（resolver null → 占位 + failed）；S12 空表 [] + 跨连接恢复矩阵（pending/downloading→failed、done/failed 不动）；S13 固定时钟落库 createdAt/updatedAt；S12 Dao 去重 {1,2}。
- ref_28_value_key_test×2：真实 id 从 dao 读回（禁止猜测），byKey 断言到位。
- 空壳缺口见下方 FAIL 问题 1（无安全存储超时注入用例）。

**检查 2 实现语义忠实 — FAIL ×1**（见下方问题清单）。其余逐条对审通过：
- S11：`_remoteUrlResolver` 签名改 per-connection `Future<String?> Function(int)`；`baseUrl` 按 `entry.connectionId` 解析（`_nextPendingEntry` 从 DB 行取 connectionId，泵跨连接不串凭证）；downloads_provider 零 activeConnectionProvider 引用（否定①）；null → 保底占位 → failed 不崩（否定③，有专测）。②生产装配按 spec 逐字落地。
- S12：`listDistinctConnections` 入 IDownloadDao + DownloadDao 实现，'downloads' 表名字面量在 download_manager.dart 唯一残留为本地目录名 `p.join(docs.path,'downloads')`（:81，非 SQL 表名，合法）；recoverOrphanDownloads 改 `dao.listDistinctConnections()` 循环 markAllNonDoneFailed，catch-log 保留（:432 原样）。
- S13：构造注入 `clock`（默认 DateTime.now）；enqueueMany `:190` 与 onProgress `:327` 的 now 改经 `_clock()`；生产装配不传 clock（行为零变化）。见非阻断 1（spec 内部文字矛盾）。
- BUG-33-S2：`buildScanFetchDir` 提取 + `_filterDirectoryEntries` 单一来源（directoryContentsProvider 与扫描共用同一函数，:133/:149 同码）；搜索 `_startScan`、`_scanFolderWithLoading`、`_playSearchHit` 三处换线；`_collectFolder` 系旧注释（spec :568-570 实指 `_playSearchHit` 内 collectFolderAudio），实际两处扫描调用点均已接线。
- BUG-33-S3：searchFolderSubtree 单层 catch→skipped++（folder_searcher.dart:70-72）、collectFolderAudio 整体上抛原样；未新增逐层 try/catch。
- REF-28：S1 `key: ValueKey(record.id)` + `_DownloadRow` 补 `super.key`，回调接线零改动；S2 `key: ValueKey(hit.file.path)` 单行插入。INV1 键值来源均为业务 ID。
- buildScanFetchDir 签名偏离 spec 的 `WidgetRef ref` 形态改显式依赖注入——注释已论证（search notifier 的 ref 非 WidgetRef），行为等价、否定断言全保持，判机械适配不计自由发挥。

**检查 3 跨模块破坏 — PASS**：cross-imports all clean（仅基线 legacy debt）；impact 引用方全在 §7 声明域（browser_screen/breadcrumb_bar 属 BRW、downloads_screen/main 属 DL）；cov-gate --only test 全量 2718 用例全绿（brw_01/srch_01/ply 族回归网未破，含改动后需补 webDav/secureStorage override 的 srch/brw/dl widget 夹具机械适配）。

**机械项 — 全绿**：spec-scan rc=0×3（DL-01 矩阵 S1~S13/INV1~5 全命中，ALG 行 `-` 为脚本固定口径）；repro-test bug_33 / bug_b1 双 pass ✓；coverage-check check-check 总覆盖 91.80% vs 基线 91.47%（上行），critical 单文件零漂移。

### FAIL 问题清单

1. **buildScanFetchDir 的 safeStorageRead 超时抛 SecureStorageTimeoutException，三个调用点均落于既有错误处理之外——文件夹扫描 loading 卡死 / 搜索面板永久「扫描中」**（检查项 2，@BUG-33-S2，兼及 DL-01-S8 / BRW-01 / SRCH-01 调用方）
   - 证据：lib/features/browser/browser_provider.dart:442-455（`_startScan` 在 `state.copyWith(running:true)` 之后 await，throw 则 running 恒 true）；browser_screen.dart:1060-1072（`_scanFolderWithLoading` 的 `await buildScanFetchDir` 在 try/catch(collectFolderAudio) 之前，throw 则 :1045 `barrierDismissible:false` 的 loading 对话框永不 pop）；browser_screen.dart:569-580（`_playSearchHit` 同前，throw 则无 SnackBar）；对照同文件 directoryContentsProvider:117-124 将 `SecureStorageTimeoutException` 显式转为 `WebDavException('读取密码超时，请重试')`。
   - 现象：safeStorageRead（storage_utils.dart:28-31）文档化地抛 `SecureStorageTimeoutException`（5s 平台通道挂起——正是 F1 所述真实通道延迟类、也是该超时包装存在的唯一理由）。修复前扫描任一层存储超时 → directoryContentsProvider 抛 WebDavException → 文件夹扫描被 collectFolderAudio catch 兜住（pop+固定文案）、搜索被 searchFolderSubtree 单层 skip（folder_searcher.dart:70-72）。修复后密码读上移为**会话装配段一次读**（S2 设计使然），但三调用点均无兜底：文件夹扫描 loading 卡死 + unhandled async error；搜索 running 卡 true 面板假死（后续 query 也无法复位）；搜索命中播放静默无反馈。可复现：`_startScan`/文件夹扫描期间 secure-storage 读挂起 ≥5s。
   - 修复指令（精确到函数，dev-exe 照单执行）：
     1. `_scanFolderWithLoading`（browser_screen.dart:1060）：把 `final scanFetchDir = await buildScanFetchDir(...)` 包进 try/catch；catch 内执行与下方 collectFolderAudio catch（:1080-1086）完全相同的三步：`navigator.pop(); messenger.showSnackBar(const SnackBar(content: Text('无法读取文件夹内容，请检查连接'))); return null;`。`null` 分支（:1066-1072）不动。
     2. `_playSearchHit`（browser_screen.dart:569）：包进 try/catch；catch 内 `messenger.showSnackBar(const SnackBar(content: Text('无法读取文件夹内容，请检查连接'))); return;`。`null` 分支（:575-580）不动。
     3. `_startScan`（browser_provider.dart:442）：包进 try/catch；catch 内 `state = state.copyWith(running: false); return;`（与 fetchDir==null 分支 :452-454 同错误落位，query 已保留）。P14 守卫（:451 `_disposed || !state.running || state.query != q`）保持在此 try 之后、订阅之前，顺序不动。
     4. 测试补：bug_33_repro_test.dart 增一用例——`HangingFakeSecureStorage(hangRead: true)` 驱动 `_startScan`（fake_async 或真实 5s 超时推进），断言搜索 running 最终置 false 且不抛异常、面板不卡；文件夹扫描侧同构（`_scanFolderWithLoading` 返回 null + 对话框关闭 + 固定文案）可选其一并在用例注释说明共享兜底。注意：安全存储挂起对 `safeStorageRead` 是 5s 超时抛异常（非 null），fake 需让 read future 永不完成（hangRead 已满足），测试内推进超时或直接以 `ReadThrowingFakeSecureStorage` 代理等价路径。
     5. 明确不违反 BUG-33-S3 否定断言「不引入新的 try/catch 覆盖层」：S3 否定面约束的是**逐层 listDirectory 错误**的成败语义（search skip / folder throw 原样保留，一行未动）；会话装配段的**一次性密码读**是 S2 新增的独立前置步骤，其失败须落位到各调用点既有错误分支——与 directoryContentsProvider 的 WebDavException 转换同族，非覆盖层。

### 非阻断观察（不随本轮处理）

1. **spec 内部文字矛盾（DL-01-S13，请 dev-plan 修订）**：Then 写「:306 lastWriteAt 初值改经 _clock()」，同场景否定断言写「节流锚点 lastWriteAt 初值、进度写判断逻辑不变」。实现保留 `lastWriteAt = DateTime.fromMillisecondsSinceEpoch(0)`（epoch 锚点）仅改 `now` 来源。若按 Then 字面改 lastWriteAt 经 `_clock()`，首回调 `now.difference(lastWriteAt)≈0 < throttle` → 首回调不落库，直接破坏 dl_01_download_test.dart:1594-1613「首回调立即写库」与引擎注释「First progress callback always lands (epoch anchor)」。实现取否定断言分支，正确。建议 spec 修订为「:185/:318 的 now 改经 _clock()；lastWriteAt 保持 epoch 锚定不变」。
2. **INFO**：srch_01 / brw_01 / dl_01 既有 widget 测试的搜索与文件夹扫描夹具需补 webDav/secureStorage/activeConnection override（因扫描 fetchDir 从 directoryContentsProvider 改道 webDavClientProvider）——纯测试装配机械适配，断言语义原样保留，已全绿。

### 行动

FAIL → `dev-status.sh bump-round BUG-33` + `dev-status.sh bump-round DL-01`（impl/test 回 pending）。REF-28 全项通过 → `dev-status.sh pass REF-28` + `coverage-check.sh refresh`。请手动启动 dev-exe 重做：仅需处理问题清单 1（修复指令已精确到函数与测试补位），其余实现与测试保持原样，勿动既有断言。

## [2026-08-29 19:35] BUG-33 - 第 2 轮 dev-check / DL-01 - 第 2 轮 dev-check（commit 673dadc 返工增量）

### 总 verdict: BUG-33 FAIL ×1（新增）；DL-01 PASS

审计对象：commit 673dadc（第 1 轮问题清单 1 的唯一修复靶点）。从 spec §1.0 推回：F1 三句期待 + 第 1 轮 FAIL 指令「会话装配段密码读超时须落位各调用点既有错误分支」逐字核验三个调用点。

**第 1 轮修复靶点核验（检查 2 核心，对抗式）**：

- **_scanFolderWithLoading（browser_screen.dart:1079-1094）**：catch 执行与 collectFolderAudio catch 完全相同的三步（pop loading + 固定文案 + return null）✅。三个消费方（DL-01-S8 `_downloadFolder` :921-922、BRW-01 `_playFromFolder` :1126-1127、播放单 `_addToPlaylistFlow` :1155-1156）对 null 均 `return`（文案由 scan 已显示），DL-01-S8 下载路径装配超时正确中止、无泄漏。此路径无共享 running 类状态，无并发窗口，无 clobber 类比问题 ✅。
- **_playSearchHit（browser_screen.dart:574-594）**：catch → 固定文案 SnackBar + return，无状态写入、无导航副作用，与 collectFolderAudio 失败分支同款 ✅。
- **_startScan（browser_provider.dart:447-459）**：catch → `running=false` + return，单扫描挂起用例（bug_33_repro_test 新增）真实断言复位成功 ✅。**但此处发现第 1 轮修复引入的新竞态缺陷——见下方问题清单 1。**

**检查 1 测试空壳 — PASS**：两个新增用例均为真状态断言、非占位——
- bug_33_repro_test「密码读超时 → _startScan 复位 running」（sync fakeAsync）：前置锚（running 挂起 true）→ 推进 5s → running 置 false + query 保留 + panelOpen 保持 + hits 空 → 二次触发证明面板不卡（重新挂起→再次超时复位）✅。
- brw_01「扫描装配段密码读超时 → _scanFolderWithLoading」：loading 对话框前置锚 → 推进 5s → 固定文案 + Dialog findsNothing + CircularProgressIndicator findsNothing + Player findsNothing + 双队列 provider null 五重否定面 ✅。
- 但新测试仅覆盖「单扫描挂起」，未覆盖「重叠扫描 A 迟到超时 clobber B」——缺口见问题清单 1。

**检查 3 跨模块破坏 — PASS**：cross-imports all clean（仅基线 legacy debt）；impact 引用方全在 browser 声明域（§7 BRW/DL 内）；cov-gate --only test 全量 2720 用例全绿（含 dl_01_download_test、srch_01、brw_01 回归网）。

**机械项 — 全绿**：spec-scan rc=0（S/INV/ALG 矩阵无缺项，ALG 行 `-` 为脚本固定口径）；repro-test bug_33 pass ✓；coverage-check check-check 总覆盖 91.78% vs 基线 91.80%，降幅 0.02% ≤ 容忍，critical 单文件零漂移。

### FAIL 问题清单

1. **_startScan catch 无条件写 running=false：旧扫描迟到超时 clobber 新在途扫描的 running**（检查项 2，@BUG-33-S2 修改点③，兼及 SRCH-01-S6 迟事件语义）
   - 证据：lib/features/browser/browser_provider.dart:455-459（catch 在 P14 守卫 :463 之前直接 `state.copyWith(running: false)`）；同函数 fetchDir==null 分支 :464-467 与成功路径均在守卫之后——catch 是唯一绕过守卫的状态写。
   - 现象：搜索扫描装配段挂起 ≥5s（正是本轮修复目标场景）期间用户改输入 → 新 query 的 `_startScan` B 已启动（running=true, query='ab'，仍挂起在其自身密码读）→ 旧扫描 A 的 safeStorageRead 5s 超时到达 → A 的 catch 无条件把 running 打回 false → B 的后续装配结果被守卫 `!state.running` 丢弃（B 成功则永不订阅，B 超时则空等）→ 面板显示「无匹配结果」（hits 空且 done）假阴性。**修复前（8177b90）此重叠场景 B 正常完成**——本修复把单挂起卡死换成重叠场景的新回归。可复现：sync fakeAsync 双扫描重叠测试实证（A 挂起→改输入→B 挂起→推进 5s 后 running 恒 false 且 B 被丢弃）。
   - 修复指令（精确到函数，dev-exe 照单执行）：
     1. `SearchSessionNotifier`（browser_provider.dart:374）新增字段 `int _scanEpoch = 0;`（放 `_disposed` 之后）。
     2. `_startScan`（:423）首行 `if (_disposed) return;` 之后加 `final epoch = ++_scanEpoch;`。
     3. catch（:455-459）在 `state = state.copyWith(running: false);` 之前加守卫：`if (_disposed || epoch != _scanEpoch) return;`——迟到异常只允许落位到「仍是最新扫描」的情形，新扫描已接管（epoch 递增）则不得写 running。P14 守卫（:463）与 fetchDir==null 分支、订阅顺序一律不动。
     4. 测试补（bug_33_repro_test.dart 增一用例，必须 sync fakeAsync——**async fakeAsync 回调会吞掉 expect 失败**，实证 exp：`fakeAsync((async) async {...})` 内 `expect(false,isTrue)` 恒 pass，测试变空壳）：
        - 前置：`HangingFakeSecureStorage(hangRead: true)`；`activeConnectionProvider.overrideWith((ref) async => conn)` + `secureStorageProvider` + `webDavClientProvider` 三个 override（与既有挂起用例同夹具，无需 prefs）。
        - 步骤：`openPanel` → `onQueryChanged('a')` → `elapse(600ms)`（A 启动挂起）→ `onQueryChanged('ab')` → `elapse(600ms)`（B 启动挂起）→ 逐段 `elapse(4200ms)` + `elapse(200ms)` + `elapse(100ms)` 跨过 A 的 5s 超时点（B 仍在飞行）→ 断言 `running == true`（旧扫描 A 的迟到超时不得把 B 打回 false）。
        - 修复前该断言 FAIL（running 恒 false），修复后 PASS——真红真绿门禁。
     5. 可选加固（不阻塞，建议一并做，同样 2 行）：成功路径守卫 :463 改 `if (_disposed || epoch != _scanEpoch || state.query != q) return;`——闭合同 query 重输（清空后重打同词）下 A 迟到成功与 B 双重订阅的边角。若 dev-exe 判定风险，仅完成 1-4 亦达标。
   - 不违反 BUG-33-S3：S3 否定面约束的是逐层 listDirectory 错误的成败语义（search skip / folder throw 一行未动）；本守卫属 S2 会话装配段错误处理的正确性修正，非覆盖层。

### 非阻断观察（不随本轮处理）

1. **INFO**：BRW-01/SRCH-01 与 DL-01 同受本轮 BUG-33 修复影响（`_scanFolderWithLoading`/`_startScan` 换 fetchDir），round-1 已登记夹具机械适配全绿；本轮新发现仅落在 `_startScan`（搜索路径），DL-01-S8 文件夹下载路径（`_scanFolderWithLoading`）无此竞态——单模态对话框无共享 running 状态，已核验三个消费方 null 处理完整。

### 行动

BUG-33 FAIL → `dev-status.sh bump-round BUG-33`（impl/test 回 pending，check_round=2）。DL-01 全项通过 → `dev-status.sh pass DL-01` + `coverage-check.sh refresh`。请手动启动 dev-exe BUG-33 重做：仅需处理问题清单 1（修复指令已精确到函数与测试补位，含 sync fakeAsync 教训），其余实现与测试保持原样，勿动既有断言。
