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

---

## [2026-08-09] REF-04/REF-05/REF-06/REF-09 - 第 1 轮 dev-check

### 总 verdict: REF-04 PASS / REF-05 FAIL（1 项测试缺口）/ REF-06 PASS / REF-09 PASS

本机自跑验证：settings/player/timer/browser 四块相关套件全部 PASS（+332/+335），`flutter analyze` 触及文件零 error/warning，`spec-scan --gate/--neg` 四 ID 全 exit 0，`cross-imports.sh` 三检 clean。

---

### REF-04（1b51c7b）— PASS

| 检查 | verdict | 要点 |
|---|---|---|
| 1. 测试空壳审计 | PASS | ref_27_test 静态断言 3 条（8 符号禁止/8 符号规范/key 值不变）非空壳（文件不存在即失败）；settings_test 新增 4 条迁移行为测试（setDefaultSpeed/setSeekStep 合法/非法写读，prefs 真断言）；bug_bug28 全部 seekStepProvider 断言转 seekStepSettingProvider 且保留核心否定断言（非法值 7 不更新数据源 + prefs 不写）；ply_02 默认 15/更新 30 均为真断言 |
| 2. 实现语义忠实 | PASS | S1/S2：settings_service 8 符号全删（settings_service.dart 现仅 theme+remember-speed），speed_manager 单源（speed_manager.dart:15/18/21/24/27/33/40/49/56），key 值原样；S3：seekStepProvider 删除、playback_controls.dart:28 直 watch seekStepSettingProvider、setSeekStepSettingProvider 无手动同步（settings_provider.dart:118-119）；S4：sharedPreferencesProvider 定义于 shared/di/providers.dart:250，browser_provider.dart:22 re-export（消费者 main/timer/home/player 经 di 获取，行为不变）；S5：文件头改为 re-export facade 描述，无 "ONLY file" 字样 |
| 3. 跨模块破坏 | PASS | §7 声明 SET/PLY/BRW 与 grep 引用方一致；timer/home/main 消费 sharedPreferencesProvider 路径未断（全量套件绿）；`_service.` 残留仅 theme/remember-speed 6 处，无死引用 |

Design 观察（不阻断）：
1. bug_bug28_repro_test.dart:119 'REF-04-S4/U3' 语义翻转——prefs=null（纯测试环境）时 setSeekStepSettingProvider(30) 后数据源保持 15（旧行为为运行时 30）。生产路径 main.dart:56 恒 override 非 null prefs，无用户可见影响；测试注释已声明。后续 dev-plan 可评估是否在 §3.2 否定断言补一句 null-prefs 语义。
2. settings_provider.dart:21-22 用 `export speed_manager show ...` 而非 spec 建议的直接 import，`setSeekStep` 经 di/providers.dart re-export 链回环解析（settings_provider→di→settings_provider 循环，Dart 合法、编译期安全）。若日后 di 的 settings export 列表移除 setSeekStep，settings_provider.dart:118 编译即断，非静默风险。可留待后续 CR。

---

### REF-05（db9318f + edb60a0）— FAIL

| 检查 | verdict | 要点 |
|---|---|---|
| 1. 测试空壳审计 | FAIL | 见问题 1（§5.3 要求的正向路径行为测试缺失） |
| 2. 实现语义忠实 | PASS | S1：TimerStateNotifier 仅剩 startDuration/startAfterCurrent/cancel/checkExpired/onTrackCompleted（timer_provider.dart:49-84），TimerService.pause/resume、TimerMode.paused、remainingMs 均保留；S2：TimerButton 类删、re-export 仅 TimerBottomSheet（providers.dart:182），TimerControl 零改动（timer_control.dart:58 仍经 di 用 TimerBottomSheet）；S3：copyWith 删除且 lib/ 零引用残留；S4：startDuration 不再写 lastCustom（timer_provider.dart:49-53），唯一写入点 timer_button.dart:179-182（自定义确认），预设/上次时长 tile（:52-71）只走 startDurationTimerProvider，不触碰 lastCustom——可违反路径不存在 |
| 3. 跨模块破坏 | PASS | §7 声明仅 PLY（TimerControl）；widget_helpers 删 48 行（wrapWithTimerProviders/pumpTimerWidget/timerContainerOf/wrapWithTimerProvidersAndPrefs）grep 全库零残留引用；bug_bug29 用 _PausedInjectTimerNotifier 子类注入 paused state，断言语义保留（暂停冻结显示/流切换毫秒值均仍断言） |

### FAIL 问题清单

1. **REF-05-S4 正向路径测试缺失**（TEST-GAP，spec §5.3/§5.4 明确要求）
   - 证据：spec §5.3 补偿要求"启动预设 5 分钟 → 检查 lastCustomTimerMinutes 未变；**启动自定义 30 分钟 → 检查值为 30**"；实现仅有前半（timer_test.dart 'REF-05-S4: 预置 30 分钟自定义记忆，预设 5 分钟启动不覆盖'）+ 一条文本级 `contains('setLastCustomTimerMinutesProvider')`（timer_test.dart:1016-1021，不证明接线到确认路径）
   - 检索：`grep -rn "setLastCustomTimerMinutesProvider" test/features/timer/` → 除 REF-05 静态断言外零命中；旧 widget 用例 '确认自定义时长后保存为上次时长'（确认→prefs==5）随 TimerButton group 删除后未重建
   - 现象：唯一写入点的正向行为无测试锚定——若 timer_button.dart:179-182 的写入被误删，本组测试全绿
   - 修复指令：test/features/timer/timer_test.dart REF-05-S4 group 内新增一条 provider 级用例（无需 widget 交互）：`setMockInitialValues({})` + prefs override → `container.read(setLastCustomTimerMinutesProvider)(30)` 后 `container.read(startDurationTimerProvider)(5)` → 断言 `container.read(lastCustomTimerMinutesProvider)==30` 且 `prefs.getInt(lastCustomTimerMinutesKey)==30`（覆盖"自定义确认写入 30 后再走预设不被覆盖"，即 §5.3 后半句）
   - 修复后再跑：`flutter test test/features/timer/` 全绿即可，无需改实现

---

### REF-06（7bf9e03）— PASS

| 检查 | verdict | 要点 |
|---|---|---|
| 1. 测试空壳审计 | PASS | ref_19_test 仅留 sortFiles 顶层函数用例（目录优先/三排序全断言）；bug_15/bug_31 转 directoryContentsProvider 驱动后 callCount/TTL 边界/resort 不请求网络等断言语义保留（bug_bug31：4m59s 存活/5m 过期 refetch/callCount 1→2→3 真计数）；brw_03 BRW-T47 两条已删 |
| 2. 实现语义忠实 | PASS | S1：DirectoryService/ISecurePasswordReader/DirectoryResult 删除，sortFiles 提为顶层函数且 body 与原静态方法逐行一致（目录优先 + nameAsc/nameDesc/modifiedDesc 同 switch）；browser_provider.dart:19-21 export 补 sortFiles（INV3），wrapper 删除；directoryContentsProvider 内联逻辑零改动（INV1）。S2：file_list_item.dart 参数+渲染分支+文档注释全删，其余参数（file/onTap/onLongPress/onPlayNext/playNextEnabled）原样；browser_screen.dart:362 调用点本就未传参，无需改 |
| 3. 跨模块破坏 | PASS | §7 声明"无"；grep 确认 ISecurePasswordReader/DirectoryResult/DirectoryService 在 lib/ 与 test/ 零残留（除注释）；di/providers.dart:47 sortFiles 仍在导出列表，消费方（home_screen 等）不断链 |

Design 观察（不阻断，供 dev-plan 处理）：
1. spec §3.1 否定断言"不删除 ISecurePasswordReader"与同节修改指令"删除 ISecurePasswordReader + DirectoryResult"自相矛盾；实现遵从修改指令（正确——该抽象仅被已删的 DirectoryService 使用）。建议 dev-plan 后续修订 spec 删掉该条矛盾否定断言。
2. spec §5.4 要求删除 brw_07_test.dart:280（progressPercentage null 用例），实现保留为 BRW-T48 group（brw_07_test.dart:288-316，断言"无 LinearProgressIndicator"）。该用例不引用已删 API、断言当前真实行为，无害但未按 spec 表执行。可留作有意保留或删除，需 dev-plan 裁决。

---

### REF-09（21d705d）— PASS

| 检查 | verdict | 要点 |
|---|---|---|
| 1. 测试空壳审计 | PASS | settings_test 新增 2 条：SectionHeader 单测真断言 fontSize 13/w600/padding (16,16,16,4)（widget 树取 Text/Padding 实例比对）；SettingsScreen 渲染 4 个分组标题；既有 SET-T34 断言 AboutScreen '开源许可'（settings_test.dart:693-703），About 侧由既有测试兜底 |
| 2. 实现语义忠实 | PASS | section_header.dart 与原两处私有 _SectionHeader 逐行一致（padding/fontSize/fontWeight/color 全同）；settings_screen 5 处 + about_screen 1 处仅换类名，无样式/布局改动；唯一差异是新增 `super.key`（原私有类无 key 参数，渲染行为不变）；无第三方文件新增引用（grep 仅两个页面 + 测试） |
| 3. 跨模块破坏 | PASS | 仅 Settings 模块内部；`_SectionHeader` 全库零残留 |

### 行动
- REF-05 打回 dev-exe：按上方修复指令补正向路径行为测试（不动实现、不动已有断言）
- REF-04/REF-06/REF-09 可 `dev-status.sh pass`；三个 Design 观察登记供后续 dev-plan/CR 裁决（不阻断本轮）
- REF-06 的 spec 自相矛盾（ISecurePasswordReader）建议 dev-plan 在下次修订 spec 时清理

---

## [2026-08-09 21:30] REF-01（c236572）+ REF-02（5691ab9）+ REF-03（4441d89）- 第 1 轮 dev-check

### REF-01（c236572）— PASS

| 检查 | verdict | 要点 |
|---|---|---|
| 1. 测试空壳审计 | PASS | S1/S2：settings_test REF-01-S1/S2 组真断言（null/非法值回退 system、key 'theme_mode' 与值格式不变、label 三档+unknown 回退、provider 映射 dark/invalid/system、setThemeModeProvider 写回读回）；S3/S4：ref_22 编译锚+密码 key 格式+回滚+isA 契约断言；S5：ply_02 loaded/failed/superseded 三态真断言（含否定 isLoaded 恒 false）；S6：mock 编译锚；S9：brw_07 内存版 persist（默认 nameAsc + writeCount==0 否定、setOption 写入+恢复、SharedPreferences 后端 key/格式不变）；INV1/INV2 静态文件扫描（文件不存在即失败，非空壳）。S7/S8 由 ref_01_domain_pure_test 静态扫描兜底 |
| 2. 实现语义忠实 | PASS | A1：ThemeMode→String 四映射点全落（get/set/label+provider 反向映射），非法值回退与原 firstWhere orElse 语义一致；A2：ConnectionService 收 ISecureStorage+Adapter，key 格式不变；A3：TrackLoadResult 去 player 字段，isLoaded 语义（status==loaded）不变，lib/ 零 player 字段残留；A4：orchestrator 收 IAudioPlayer，全部 player 调用（setAudioSource/seek/setSpeed/play/stop/position/durationStream 等 13 处，playback_orchestrator.dart:191-405）均在契约表面内，ProcessingState 经 contract re-export；A5：速度/步长读取上移 provider 且默认值与 key 与原函数逐条等价（player_provider.dart:64、settings_provider seekStepSettingProvider）；A6：ISortOptionPersist+SharedPreferences 后端，key 'browser_sort_option' 不变 |
| 3. 跨模块破坏 | PASS | §7 声明 SET/CON/PLY/BRW；audio_source_builder preloadAudioSource 参数化（core/services 层）调用方 bug_32/brw 等已适配；shared/di export 换 seekStepPrefsKey/defaultSeekStep 后 timer/home 等跨 feature 消费方编译全绿；cross-imports all/impact 退出 0；全量 2282 测试通过 |

### REF-02（5691ab9）— PASS

| 检查 | verdict | 要点 |
|---|---|---|
| 1. 测试空壳审计 | PASS | S1-S3/S8：编译锚+isA 运行时断言+默认实例否定（con_01/ply_09/prg_test/bug_05）；S6/S9：静态文本扫描（import 列表无 features/、contract 与 DAO 无 rawInsert 字样）；S7：编译锚+playbackStateStream/mediaItemStream 非空；S10：行为（唯一连接抛 LastConnectionException+行仍存在否定）+文档文本双断言；S11：编译锚+状态机回归（countdown 5→4）；rawInsertForTest 迁移（prg_test 5 处+bug_26 否定"显式时间戳不受 clock 注入"）语义保留 |
| 2. 实现语义忠实 | PASS | S1-S3：三 DAO provider 换 I* 接口且实例创建不变；S4：secureStorageProvider 返回 FlutterSecureStorageAdapter；S5：FakeSecureStorage implements ISecureStorage（不继承）；S6：contract 仅 import audio_service+background_playback_contract（221 行搬移+feature re-export 保兼容，零行为变化）；S7：NasAudioHandler implements IAudioHandler 全 17 成员由编译强制；S8：provider 类型 IAudioHandler?；S9：rawInsert 从 contract+DAO 双删；S10：delete dartdoc 补异常条件；S11：ProgressService required IProgressDao（无默认值），PlaylistService/ConnectionService 收 I*Dao 为 S1-S3 必要适配 |
| 3. 跨模块破坏 | PASS | §7 声明 CON/PLY/BRW/PRG/SET/TMR；main.dart:65 override NasAudioHandler 兼容新类型；player_screen 仅用契约成员；helpers 三件套（fake_secure_storage/mock_audio_player/fake_progress_dao）全部实现 I* 接口；cross-imports all 退出 0（background_playback_contract 纯 Dart 零 import 无新违规）；全量 2282 测试通过 |

### REF-03（4441d89）— PASS

| 检查 | verdict | 要点 |
|---|---|---|
| 1. 测试空壳审计 | PASS | S1：lib/ grep SaveTrigger 零残留；ref_25_test 5 触发点（periodic/pause/skipNext/skipPrev/complete）改为字符串驱动后 isTrue/isNull 断言语义完整保留；S2/S3：REF-02-S9 静态扫描+rawInsertForTest 迁移用例兜底 |
| 2. 实现语义忠实 | PASS | S1：SaveTrigger enum 与 saveProgress trigger 参数双删，upsert 委托参数传递逐条不变（connectionId/filePath/positionMs/durationMs）；S2：progress_dao/contract rawInsert 删除；INV1/INV2 grep 实证 |
| 3. 跨模块破坏 | PASS | §7 声明仅 PRG；bug_09 fake 存根删除、aud_05/ref_25 注入 FakeProgressDao 全部编译；全量 2282 测试通过 |

### 问题清单（非阻断，登记供后续 dev-exe/dev-plan）

1. **audioHandlerProvider 消费点 cast 回具体类**（FRAGILE，REF-02-S8）
   - 证据：lib/features/player/player_provider.dart:126-130 `(ref.read(audioHandlerProvider) as NasAudioHandler?)?.mediaItem.add(null)`——契约真启用后 IAudioHandler 表面无清空 media item 能力，wiring 点被迫强转回具体类。
   - 现象：生产（main.dart 恒注入 NasAudioHandler）与现有测试（恒 override null）不炸；但 REF-02 目标正是"contract 为唯一依赖边界"，未来任何测试 override 非 NasAudioHandler 的 IAudioHandler mock 即在此行 TypeError。
   - 修复指令：`lib/core/contracts/audio_handler_contract.dart` IAudioHandler 增加 `void clearMediaItem();`；`lib/core/services/audio_handler.dart` NasAudioHandler override 实现 `mediaItem.add(null)`；player_provider.dart:126-130 改为 `ref.read(audioHandlerProvider)?.clearMediaItem()`（q==null 分支）；bug_05_handler_play_test.dart REF-02-S7 组补一条断言（mock 注入后调用 clearMediaItem 不抛）。

2. **rawInsertForTest 与 DAO 的 DB 身份解耦**（FRAGILE，REF-03-S3）
   - 证据：test/helpers/test_database.dart:156 用 `DatabaseHelper.instance.database` 全局单例；原 rawInsert 走 `_dao._db`（注入 helper）。当前测试 DAO 均默认构造（grep `ProgressDao(helper` 零使用），行为等价。
   - 现象：未来测试若 `ProgressDao(helper: X)` 注入独立 DB 再调 rawInsertForTest，播种静默落到错误 DB（断言挂）。
   - 修复指令：test_database.dart rawInsertForTest 增加可选参数 `Future<void> rawInsertForTest(PlayProgress progress, {Database? db})`，`db ??= await DatabaseHelper.instance.database`；现有调用点无需改（保持默认路径），后续注入 helper 的测试显式传自己的 db。

3. **preferences_bridge 使 domain 层字面 import 干净但类型仍依赖插件**（DESIGN，REF-01-A1）
   - 证据：lib/shared/preferences_bridge.dart export SharedPreferences；settings_service.dart:15 import bridge 后函数签名仍用 `SharedPreferences?`（:23/32/59/69/88/94）。spec 修改指令本身给出的签名就含 SharedPreferences?，dev-exe 忠实执行；"Domain 零插件依赖"仅字面达成。
   - 处理：后续 REF（如真正的 reader 抽象）由 dev-plan 评估，本轮不阻断。

4. **secureStorageProvider 运行时适配器类型未锚定**（TEST-GAP，REF-01-S4/REF-02-S4）
   - 证据：ref_22_test REF-01-S4 仅断言 `isA<ISecureStorage>()`；spec 期望"运行时实例为 FlutterSecureStorage 的适配器"（实现正确，connection_provider.dart:55 `const FlutterSecureStorageAdapter()`）。
   - 修复指令（可选）：ref_22_test REF-01-S4 组补一条 `expect(container.read(secureStorageProvider), isA<FlutterSecureStorageAdapter>())`。

5. **log_forwarder/audio_player_adapter/audio_source_builder 改动超出 spec 文件清单**（DESIGN，REF-01 自由发挥）
   - 证据：REF-01 新增 lib/core/services/log_forwarder.dart、audio_player_adapter.dart，并把 audio_source_builder.dart 参数改 ISecureStorage——spec §3 未列。均为消除 6 文件 flutter import 的必要配套（debugPrint 转发行为逐字节等价、adapter 纯转发、调用方全适配），commit message 已声明 BUG-19/24 语义保留。登记备案，无行为风险。

### 行动
- REF-01/REF-02/REF-03 均判 PASS，执行 `dev-status.sh pass` × 3 + `coverage-check.sh refresh`
- 问题 1（cast）建议下个涉 player 的 dev-exe 轮按修复指令顺手处理；问题 3/5 由 dev-plan 评估；问题 2/4 可选修复

---

# 2026-08-09 批量审计（REF-01~09 + TEST-01~11，16 项）

> 输入：批量 dev-exe 完成后手动启动 dev-check。机械项全绿：spec-scan 16/16 rc=0、cross-imports all clean、coverage-check 基线无漂移、cov-gate --only test 全量 2282 PASS。

## Verdict 汇总

| ID | verdict | 问题 |
|---|---|---|
| REF-01~03 | PASS | 见上条记录（5 条非阻断登记） |
| REF-04 | PASS | 无 |
| **REF-05** | **FAIL** | TEST-GAP：正向"自定义 30 分钟 → lastCustom=30"行为测试缺失 |
| REF-06 | PASS | 无（非阻断观察：BRW-T48 未按 §5.4 删除，留 dev-plan 裁决） |
| REF-07 | PASS | 无（9dd6396 lint 修正确） |
| REF-08 | PASS | DESIGN（低）：还原后重装路径无显式单测 |
| REF-09 | PASS | 无 |
| TEST-01 | PASS | FRAGILE：S9 连点 4/5 次 tap miss，门控零守护；TEST-GAP：静默吞错未登记 |
| TEST-02 | PASS | FRAGILE（轻微）：空壳 con_01_test 未删（文件头已登记） |
| TEST-03 | PASS | TEST-GAP：S1 AppBar 返回否定断言缺失 |
| TEST-04 | PASS | 无（S1 含扩展名锚定正确） |
| TEST-05 | PASS | 无 |
| TEST-06 | PASS | 无 |
| TEST-07 | PASS | FRAGILE：webdav_client_test.dart:52-54/115-121 stale 注释（spec 已 617e874 同步，注释未改） |
| TEST-08 | PASS | FRAGILE：TEST-08.md §3 S6 仍写"gained 恢复播放"，与生产（BUG-22 D1 删除）冲突——spec 待同步 |
| TEST-09 | PASS | FRAGILE：S1 依赖真实 DateTime.now() 同毫秒 flake 风险；TEST-GAP：S3 FK PRAGMA 无断言 |
| **TEST-10** | **FAIL** | BUG：S2 漏 modifiedAt 字段（BUG-30 加入，spec 晚于实现）；FRAGILE×2：S6 三处 hashCode 负面双字段差异、S2 isDirectory 负面混淆 audioType |
| TEST-11 | PASS | TEST-GAP（低）×2：S2/S3 过滤状态否定断言空转 |

## FAIL 项修复指令（dev-exe 照单执行）

### REF-05（TEST-GAP）
- 证据：timer_test.dart:1016-1021 仅有负向（预设 5 分钟不覆盖 30）+ 文本级 contains('setLastCustomTimerMinutesProvider')，不证明接线；行为写入点 timer_button.dart:179-182 若被误删测试全绿。
- 修复：timer_test.dart 补 provider 级正向用例——`setLastCustomTimerMinutesProvider(30)` → `startDurationTimerProvider(5)` → 断言 lastCustom==30 且 prefs==30。不动实现。

### TEST-10
1. **BUG（S2 漏 modifiedAt）**：NasFile 生产 ==/hashCode 含 modifiedAt（nas_file.dart:223,228，BUG-30 于 2026-07-28 加入，晚于 TEST-10 spec），S2 只测 5 字段——删掉 modifiedAt 测试仍全绿，违反 TEST-10-INV1。修复：model_equality_test.dart S2 group（:153 后）追加 `testAudio('song.mp3','/music/song.mp3', size:1024, type:music, modifiedAt:DateTime(2026,1,2))` 与 base 不等 + hashCode 不同；同步改 :111 注释字段表。
2. **FRAGILE（S2 isDirectory 负面混淆）**：:141-144 testDir 未传 audioType → null，与 base 差两个字段。修复：两侧显式传相同 audioType（isDirectory:true, size:null, type:music）。
3. **FRAGILE（S6 三处 hashCode 负面空断言）**：:319-357 比较队列未传 startPositionMs → 与 base(0) 差两字段。修复：三处均补传 `startPositionMs: 0` 保持单字段差异。

## 非阻断问题登记（不阻断 PASS，供后续轮次处理）

1. REF-01 player_provider.dart:130 `as NasAudioHandler?` cast 打破契约边界 → 修复：IAudioHandler 加 `clearMediaItem()`（见上条记录问题 1）
2. REF-08 还原后重装路径补显式用例：`final o=debugPrint; install(); debugPrint=o; install(); debugPrint('x');` 断言 entries==1
3. TEST-01 S9 连点测试名实不符：建议仿 brw10 _GatedProgressDao 加 Completer 门使 5 次 tap 全落地；TEST-01 S3 静默吞错在文件头登记漂移
4. TEST-03 补 AppBar 设置图标 → /settings 断言（PopScope 不影响正常 push）
5. TEST-07 :52-54/:115-121 stale 注释改写为"与 spec §3 S5 一致（2026-08-09 锚定）"
6. TEST-08 spec 同步（见下）
7. TEST-09 S1 注入确定性 clock 防同毫秒 flake；S3 补 `PRAGMA foreign_keys == 1` 断言（可选）
8. TEST-11 S2/S3 复制/清空前先 enterText 设置过滤，演练"复制后过滤不变/清空不受过滤影响"否定断言
9. REF-06 BRW-T48 未删、REF-05 30 分钟旧用例随 TimerButton 删除未重建——均留 dev-plan 裁决
10. TEST-10 S7 前置构造依赖 List.shuffle 算法稳定性（有兜底断言），更稳做法仿 bug_bug04_fixed_test.dart:125-138 直接注入 order

## 行动
- REF-05、TEST-10：`bump-round`（impl 回 pending），需 dev-exe 重做
- TEST-08 spec §3 S6 与生产矛盾：同 617e874 先例，修订 spec 锚定生产（BUG-22 D1 已删 gained 恢复分支）
- 其余 PASS 项建议执行 `dev-status.sh pass`（REF-04/06/07/08/09、TEST-01~09/11）

---

## [2026-08-14 00:56] REF-05 + TEST-10 - 第 2 轮 dev-check

> 输入：round-1 FAIL 打回后 dev-exe 重做（d9a1a92，仅 test/ 与 status 变更，零 lib/ 改动）。机械项全绿：spec-scan REF-05/TEST-10 rc=0（含 --gate §5.4 存在性硬校验）、cross-imports impact/all clean、coverage-check check-check rc=0 无漂移、cov-gate --only test 全量 2284 PASS。

### REF-05 — 第 2 轮 verdict: PASS

| 检查 | verdict | 要点 |
|---|---|---|
| 1. 测试空壳审计 | PASS | round-1 TEST-GAP（S4 正向）已补：timer_test.dart:954-984 走真实接线（setLastCustomTimerMinutesProvider(30) → 断言 lastCustom==30 且 prefs==30 → startDurationTimerProvider(5) → 断言两者仍 30）。删掉 startDuration 内写入守卫或丢失 setLastCustom 的 prefs 写都会炸：真断言。:924-952 负向用例保留；S1/S2/S3/INV1-3 静态断言 :991-1054 未动 |
| 2. 实现语义忠实 | PASS | timer_provider.dart:43-86 notifier 仅 startDuration/startAfterCurrent/cancel/checkExpired/onTrackCompleted，无 pause/resume；:49-53 startDuration 不再写 lastCustom（INV3 唯一写入点 grep 实证 timer_button.dart）；TimerService.pause/resume 保留（:1004-1005 静态断言） |
| 3. 跨模块破坏 | PASS | round-2 零 lib/ 改动；全量 2284 PASS |

### TEST-10 — 第 2 轮 verdict: FAIL

| 检查 | verdict | 要点 |
|---|---|---|
| 1. 测试空壳审计 | FAIL | S2 modifiedAt 负面（:171-179）真断言 == false + hashCode 不同，单字段差异 ✓；S6 三处 hashCode 负面补传 startPositionMs:0 后单字段差异 ✓（:342-347/:353-358/:375-380）；**S2 isDirectory 负面（:142-153）仍双字段差异（见下）** |
| 2. 实现语义忠实 | FAIL | INV1 存在可违反代码路径：nas_file.dart:221 删除 `isDirectory == other.isDirectory` 后现有测试全绿 |
| 3. 跨模块破坏 | PASS | 零 lib/ 改动，全量 2284 PASS |

### FAIL 问题清单

1. **S2 isDirectory 负面测试仍非单字段差异**（检查项 1+2，@TEST-10-S2 / TEST-10-INV1）
   - 证据：model_equality_test.dart:142-153 — base 为 testAudio(size: 1024)（:116），负面侧 `const NasFile(..., isDirectory: true, audioType: AudioFileType.music)` 未传 size → null。两实例差异字段 = isDirectory **且** size（1024 vs null）。:143 注释"仅 isDirectory 单独差异"与实际不符。
   - 现象：round-1 修复指令"(isDirectory:true, size:null, type:music)"只解决了 audioType 混淆，size 混淆仍在；若 nas_file.dart:221 漏掉 isDirectory 参与 ==，本测试因 size 不同依旧返回 false 而全绿——TEST-10-S2"每个字段单独变动"与 INV1 的 isDirectory 守卫未真正锚定。
   - 修复指令：model_equality_test.dart:146 的 `const NasFile(...)` 补传 `size: 1024`，使负面侧仅 isDirectory 与 base 不同（size/modifiedAt/audioType 全部对齐）；同时把 :143 注释改为"两侧 size/modifiedAt/audioType 相同，仅 isDirectory 单独差异"。其余修复（modifiedAt 负面、S6 三处 startPositionMs:0）均正确，勿动。

### 行动
- REF-05 判 PASS → 执行 `dev-status.sh pass REF-05` + `coverage-check.sh refresh`
- TEST-10 判 FAIL → 执行 `dev-status.sh bump-round TEST-10`（impl 回 pending），请手动启动 dev-exe TEST-10 重做
