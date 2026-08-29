# features 文档索引

> 用途：dev-plan 在步骤 0 判断"新需求是否已有对应文档"时扫本索引即可，不必逐个打开 `docs/features/*.md` 读 §1.1。
> 维护：每次 dev-plan 创建或修订 `{ID}.md` 后必须同步更新本索引；dev-check / dev-exe 不动本索引。

---

## 如何使用本索引（dev-plan 步骤 0 决策路径）

新需求 / Bug 进来时：

1. 按模块（CON / BRW / PLY / TMR / PRG / SET）在下面"功能文档"表找候选
2. 比对"名称"列与"主锚点文件"列，判断是否落在已有 `{ID}.md` 范围内
3. 命中 → **修订模式**（步骤 1B），读对应 `{ID}.md` 的 §1.1 + §1.2 确认范围
4. 未命中 → **新建模式**（步骤 1A），按模块编号尾号自增
5. Bug：dev-plan 步骤 0 hybrid 策略——
   - 单特性 bug 且对应 feature 文档**已存在** → 走修订模式 fold 为 `status: new` Scenario（**不建独立 BUG-NN.md**）
   - 单特性 bug 且对应 feature 文档**不存在** → 新建 `BUG-NN.md`
   - 跨模块 bug 无单一归属 → 新建 `BUG-NN.md`

---

## 功能文档

| ID | 名称 | 状态 | 最近更新 | 主锚点文件 | S/INV/ALG | impl / test / check | MQA | 在 status.json |
|---|---|---|---|---|---|---|---|---|
| PLY-01 | 播放队列拖动重排 | active | 2026-08-23 | lib/features/player/widgets/queue_sheet.dart | 11/3/2 | pending / pending / pending | false（手势体验 1 条进 backlog） | ✅ |
| TMR-01 | 定时停止音量淡出 | active | 2026-08-23 | lib/features/player/player_provider.dart | 7/4/1 | pending / pending / pending | true | ✅ |
| BRW-01 | 文件夹级操作（递归播放与加入播放单） | active | 2026-08-23 | lib/features/browser/browser_screen.dart | 9/4/1 | pending / pending / pending | false（扫描耗时/限速 2 条进 backlog） | ✅ |
| SRCH-01 | 文件搜索（子树 · 立即播放/下一曲） | active | 2026-08-23 | lib/features/browser/browser_screen.dart | 11/4/1 | pending / pending / pending | false（扫描耗时 1 条进 backlog） | ✅ |
| MSEL-01 | 批量多选（跨目录勾选） | active | 2026-08-23 | lib/features/browser/browser_screen.dart | 8/4/1 | pending / pending / pending | false | ✅ |
| DL-01 | 离线下载（串行队列 · 本地播放） | active | 2026-08-29 | lib/features/player/domain/playback_orchestrator.dart | 13/5/2 | pending / pending / pending | true | ✅ |

## Refactoring 文档

| ID | 名称 | 状态 | 最近更新 | 主锚点文件 | 跨模块影响 | S/INV/ALG | impl / test / check |
|---|---|---|---|---|---|---|---|
| REF-28 | 两处列表项补业务 ValueKey | active | 2026-08-29 | lib/features/downloads/downloads_screen.dart | DL, BRW | 2/1/0 | pending / pending / pending |

## Bug 文档

| ID | 名称 | 状态 | 最近更新 | 主锚点文件 | 主归属 feature | 跨模块影响 | S/INV/ALG | impl / test / check |
|---|---|---|---|---|---|---|---|---|
| BUG-33 | 扫描类操作逐层放大 secure-storage 读与目录缓存冲刷 | active | 2026-08-29 | lib/features/browser/browser_provider.dart | null（跨模块） | BRW, SRCH, DL | 3/3/1 | pending / pending / pending |---|

## TEST-GAP 文档

| ID | 名称 | 状态 | 最近更新 | 主锚点文件 | 归属 feature | S/INV/ALG | test / check |
|---|---|---|---|---|---|---|---|

## 状态汇总

- 功能文档：6 份（PLY-01 / TMR-01 / BRW-01 / SRCH-01 / MSEL-01 / DL-01）
- Refactoring 文档：1 份（REF-28）
- Bug 文档：1 份（BUG-33）
- TEST-GAP 文档：0 份
- 待 dev-exe：3 份（DL-01 重新挂起含 S11~S13 fold；BUG-33；REF-28）

## 折叠归并备注（cr-20260816-0802 F1）

- **cr-0802 F1（通知/锁屏 skip 回调绑 PlayerScreen 生命周期）折叠归并不建文档**：与 BUG-01（QueueHandler 移除）/ BUG-02（回调接线迁移 backgroundPlaybackSyncProvider 应用级）修复方案完全重叠——F1 证据 `player_screen.dart:77-78/114-115` 与 cr-0801 F1 → BUG-02 的 `player_screen.dart:74-79/112-116` 是同一接线点；"app 启动后未进过 /player 时失效"由 BUG-02-S5（home build eager-wire）+ BUG-02-S7（空队列安全）覆盖；"mini_player_bar 无 skip 按钮"为事实说明无需修复。归并后无独立问题残留。

## 已知缺口

- BUG-02-S7（空队列接线无副作用）与 BUG-01-S1~S3（现状锚定）需 dev-exe 补 provider 级/既有测试锚定（见各 spec §5.2/§5.3）
- BUG-08 修复后需按平台踩坑库规则回写 P17 分层表（adapter 六动作 5s 层）——dev-exe 职责（BUG-08 spec §5.3/§8）

## changelog

- 2026-08-29（cr-20260826-0027 复核分流落地）：**DL-01 修订 fold**（B1 Critical 生产装配缺 remoteUrlResolver → DL-01-S11 status:new，fix 按 entry.connectionId 解析 effective base URL，per-entry 端口取代全局活跃连接；回归锚即 T1，测试载体 `bug_b1_wiring_repro_test.dart` 实测 FAIL=占位基址→修复后应 PASS；D1 recoverOrphanDownloads 直查表 → DL-01-S12；D3 DownloadManager 时间源 → DL-01-S13）。**新增 BUG-33**（F1 扫描放大：buildScanFetchDir 会话级密码读一次 + 不经目录缓存，search/collectFolder 双接线；repro 门禁 bug_33_repro_test.dart 实测 FAIL=3 层扫描 readCalls==3→修复后应 ==1）。**新增 REF-28**（D2 两处列表项补 ValueKey：下载行 record.id / 搜索命中 file.path）。repro 两门禁均以 repro-test.sh fail 确认真实 FAIL；DESIGN 条目（D1/D2/D3）无 repro 门禁要求。
- 2026-08-23（第二批）: 新增 SRCH-01 / MSEL-01 / DL-01 三份功能 spec（B 批功能，访谈裁决全部按推荐执行）。SRCH-01：folder_searcher 纯 Dart 流式扫描（事件流 HitFound/ScanProgress/ScanDone，200 目录上限截断、**单层失败跳过不整体终止——与 BRW-01 整体失败语义有意相反** §3.0）、行点击=立即播放（收集器建队+进度恢复对话框三分支复刻 onFileTap :139-176）、「下一首播」复用 insertAfterCurrentProvider 带同款置灰门禁；MSEL-01：跨目录勾选 store=插入序 Map（组间序=首次进入序、组内序=当前排序快照、快照淘汰回退字典序 ALG1），以此播放 startPositionMs 恒 null，加入播放单单点复用 BRW-01 picker，退出多选模式即清空；DL-01：DB v3 downloads 表 + IDownloadDao + WebDavClient.downloadFile（GET 流式、chunk 30s 静默超时、.part 原子改名）+ 串行泵状态机（ALG1 迁移表穷举）+ loadAndPlay 注入 localSourceResolver 本地优先（命中免密码读，缺失静默回退远程标 failed）+ /downloads 管理页与启动孤儿恢复。**入口变更声明待用户复核**：文件下载入口从"行按钮"移入长按菜单（trailing 被下一首播常驻占用）。DL-01 §8-R2 AudioSource.file 需 dev-exe 最小冒烟验证后回填。spec-scan --neg 全 0；六条目依赖链 PLY→TMR→BRW→SRCH→MSEL→DL。

- 2026-08-23: 新增 PLY-01 / TMR-01 / BRW-01 三份功能 spec（用户采纳建议批次 A2/A3/A4；A1「继续收听」经访谈裁决砍掉——冷启动恢复链路 browser_provider.dart:191-266 + player_provider.dart:216-242 + audio_source_builder.dart:167/177 已覆盖单本续听场景，增量仅剩"多内容并行切换"非用户模式）。PLY-01：QueueSheet 加 ReorderableListView 拖动重排（shuffle 双闸禁用 S4/S8）+ PlayQueue.move 纯模型方法（ALG1 含 currentIndex 跟随映射表）；TMR-01：IAudioPlayer 契约扩 setVolume（adapter/mockito 依据登记 §8-R1/R2）+ fade_policy 纯函数 + timerTickWithFadeProvider 合并四驱动点（S6），到期单 tick 完成 setVolume(0)→pause→setVolume(1.0)（S3/INV4）；BRW-01：folder_collector DFS 先序收集（上限 kFolderScanMaxFiles=500，S2 截断/S3 错误透传整体失败）+ 目录长按双入口（从此处播放复刻 onFileTap 建队形态 startPositionMs=null / 加入播放单含新建即加入路径，createPlaylist 经 playlistServiceProvider 直连取 id——createPlaylistProvider 包装丢 id 的勘察发现）。三份 spec-scan --neg 全 0，dev-status 三条目 pending 入队。
- 2026-08-23: 全部 47 项（BUG-01~28 + REF-01~19）已 impl/test/check 全闭环（末批 BUG-23~28 + REF-19 dev-check 于 2026-08-23 全 PASS），随清理任务归档删除（git 历史保留）。dev-status.json 同步清空。REF-05 键契约措辞漂移（check_log 2026-08-23 登记）未及增量补即随归档消失，如需恢复从 git 历史取回后走 dev-plan。
- 2026-08-23: cr-20260823-1421 复核分流落地（全量走查 10 条：FRAGILE×5 / DESIGN×2 / TEST-GAP×3）。**新增 BUG-23~BUG-28**（F1-F5 + D2 用户裁决"修"；六条门禁均以 repro-test.sh fail 确认真实 FAIL——bug_bug23_timeout_stop_guard_test.dart fakeAsync 驱动 A/B 两请求交错实证 30s 兜底 stop 无 isLatest 守卫、bug_bug24_shuffle_without_index_test.dart 公开 API walkRound 行为锚定 20 种子实证删曲后当前曲本轮重访（模型无公开排列 getter，编译级复现不可用，行为等价锚定）、bug_bug25_queue_sheet_dup_key_test.dart widget 级实证重复 path 队列 duplicate-key 断言、bug_bug26_pubspec_state_notifier_test.dart 结构断言实证主依赖缺声明、bug_bug27_restore_race_test.dart 可控 Completer DAO 实证恢复窗口覆盖用户队列并错位 seek（勘察补强：restore 路径经 connectionDaoProvider.findById，须 stub 否则 sqflite 工厂未初始化提前中止；player.audioSource 缺 stub 会以 MissingStubError 抢占失败信号）、bug_bug28_txn_activate_test.dart 结构断言+行为回归实证自动激活在事务外。命名：bug_bug23/26/27_repro_test.dart 等已被旧轮占用，全部门禁用描述性后缀（BUG-21 completed_seek 先例）。TEST-GAP T1/T2/T3 并入 BUG-24/23/25 门禁。**新增 REF-19**（D1 用户裁决"修"→ 转 REF 需求流程；DESIGN 条目无 repro 门禁要求）。dev-plan 勘察超出 cr 原文两处：① BUG-24 修复语义升级为"排列 remap + 指针锚定"而非仅文档豁免（与 insertAfterCurrent BUG-04-S1 对称）；② BUG-27 边界表固化 :217 await 阶段天然安全序不被破坏。
- 2026-08-22: cr-20260822-2051 复核分流落地。**新增 BUG-20/21/22**（F1/F2/F4 用户选定第一批；三条 repro 门禁均以 repro-test.sh fail 确认真实 FAIL——bug_bug20_repro_test.dart widget 级实证 dispose 取消监听后暂停不再保存、bug_bug21_completed_seek_test.dart 实证 nq==null 分支缺 seek(0)、bug_bug22_repro_test.dart 真 SQLite 实证删除后曲目 family 缓存滞留；BUG-21 门禁文件名带描述后缀避开既有 bug_bug21_repro_test.dart，SCHEMA §1.3）。**新增 REF-17/REF-18**（D1/D2 用户裁决"修"→ 转 REF 需求流程；DESIGN 条目无 repro 门禁要求）。**T1/T2/T3 补测完成**（aud_05 八个纯注释空壳改真实驱动：browser 六态经 _FakeDav 注入 + gate superseded + orchestrator 四条 failed 短路；int_g01 与 aud_01 INT-G01 自演组改生产监听器+switch 路径真实驱动——关键发现：ref.listen 须在 invalidate 后显式重读 activeConnectionProvider 才收到通知（生产等价于 home/BrowserScreen 常驻 watch），测试已加注释锚定该语义；aud_01 LOG-G01 十一个 isNotNull 用例改 buildUriWithBasePath/buildAuthHeader 精确断言——顺带实证 Dart Uri 不转义撇号（RFC3986 sub-delim）与 query 空串返回 '' 非 null 两处平台行为）。**T4-T8 登记、F5-F9 待批次二**（见 docs/dev/cr-backlog.md）。**D3 关单**（记录裁决理由不建条目）。三文件补测后 flutter test 241 全绿。
- 2026-08-16: cr-20260816-0801~0806 复核 DESIGN 裁决关闭 5 条（用户按推荐裁决，记录理由不建条目）：① cr-0801 D3（normaliseWebDavUrl 对无端口 https 强制补 5005）——特定 NAS 环境约定，非通用缺陷；② cr-0801 D4（PlaylistDao.reorderTrack 同毫秒碰撞）——added_at base+i 偏移已保证同批序，跨批碰撞不改变相对顺序；③ cr-0805 D4（Timer paused 模式 UI 生产不可达）——服务层 pause/resume 保留供测试与未来 UI 用；④ cr-0806 D4（bug_10_test.dart 命名/位置偏离约定）——已知债务 INDEX 已登记，迁移成本高于收益；⑤ cr-0806 D5（本地 mock 变体扩散）——渐进迁移，不强制一轮收敛
- 2026-08-16: 新增 REF-14、REF-15、REF-16（cr-20260816-0806-test-helpers.md DESIGN 条目用户裁决"修"→ 转 REF 需求流程落地；DESIGN 条目无 repro 门禁要求）。**编号归属勘误**：任务下达将 REF-16 标为"cr-0806 D5"，但内容（coverage-debt.txt 两条登记过期）与 cr 报告 D2 逐字一致，D5 实为"本地 mock 变体扩散"——按内容归属 D2 落地，D5 不在本次 3 条内。REF-14 设计裁决（D1）：共享 helper 新增单一类 `HangingFakeSecureStorage extends FakeSecureStorage`（构造参 hangRead/hangWrite/hangDelete 默认 false，per-method 可配对齐 cr 修复建议原文）+ readCalls/writeCalls/deleteCalls 计数器（支撑 svc_storage_utils_test.dart:46 `readCalls == 1` 断言；计数在挂起短路前递增）；挂起机制 `Completer<T>().future` 与三处本地实现逐字节同构（bug_10:171 / bug_bug32:56/74/91 / svc:22 实证，非新模式）；bug_bug32 的 `_MapStorage`/`_ThrowingReadStorage` 保留不迁（非挂起家族，防语义漂移）；三文件删类后 `import 'dart:async'` 一并移除（dart:core core.dart:167 再导出 Future/Stream 实证，Completer 仅存在于被删类）。迁移点：bug_10_test.dart 删 157-192（调用点 :29/:59 换 hangRead/hangWrite）、bug_bug32 删 44-93（调用点 :230/:290/:294/:325/:364/:427/:546）、svc_storage_utils 删 14-24（调用点 :36，断言 :46 不变）。REF-15 设计裁决（D3）：8 处坏形态 `addTearDown(() => container.dispose)`（:137/:164/:222/:239/:296/:321/:454/:478）逐行改 `addTearDown(container.dispose)`；可行性依据（铁律 6 实证）：riverpod 2.6.1 container.dart:625 `void dispose()` 同步非 Future，tear-off `void Function()` 可赋值 `AsyncCallback`，仓库 10+ 处编译实证（bug_13_repro_test:233/256、o3:68、bug_bug31:99/149/179、bug_06:178、brw_04:167/238、brw_05:55）；await 形态不需要（dispose 为 void）；断言零改动。REF-16 设计裁决（D2）：实测两文件（lcov.info 2026-08-15 23:26 + check-check EXIT=0 + awk 独立核对）——timer_service 72/74=97.30%、playback_orchestrator 122/124=98.39%，均 ≥90% → **删除 coverage-debt.txt:10-11 两条登记**（符合"只减不增"规则，coverage-debt.txt:5）；头部注释与 TEST-GAP 区（13-41）保留；check-exe 验证 floor 回落 90 硬阈仍 EXIT=0；baseline-coverage.json 不 refresh（check-check 无耦合，刷新归 dev-check PASS 职责）
- 2026-08-16: 新增 REF-09~REF-13（cr-20260816-0805-progress-timer-settings.md D1/D2/D3/D5/D6 用户裁决"修"→ 转 REF 需求流程落地；DESIGN 条目无 repro 门禁要求）。REF-09 设计裁决：progress_policy 下沉 `core/contracts/progress_policy.dart`（选 core/contracts 而非 core/database：本质是"何时持久化"的决策契约，且用户裁决给出 core/contracts 优先）；extractTitleFromPath 下沉 `shared/media_title.dart`（纯字符串工具，webdav_paths 先例），player 侧 domain/media_control.dart 改 re-export 保 feature 消费方路径零改动；audio_handler.dart:24 改直连 shared 并随 `hide MediaAction` 消失；cross-imports.sh 新增 core→feature 方向检查（check_core_feature 并入 all）；coverage-check.sh:30 critical 路径同步改（否则 cov-gate 查不到新文件）；manual_qa_required=true（audio_handler 被触碰，通知栏标题 MQA）。REF-10 设计裁决（证据修正：cr 原判"顶层三函数死代码"有误——settings_test.dart:529-574 REF-01-S1 组经 settings_domain 别名直接调用）：统一到实例方法单份，**必须先迁 settings_test REF-01-S1 组再删顶层三函数（settings_service.dart:23-46）**，S5 迁移绿后 S6 才删（顺序铁律写进 spec）；settings_provider.dart:36-42 同名顶层 getThemeMode 是 String→ThemeMode 映射、职责独立不删；shared/di re-export（ThemeMode 版）不受影响。REF-11 设计裁决（D3 二选一）：**补回 15 分钟 tile**（timer_button.dart:72 前插入，5/10/15 递增档序）——文档三处（头注释 :4-7 / timer_test:16-17 / TMR-T26）已承诺 15 分钟，删文档需改 3 处且丢常见睡眠档，补 tile 只加 UI 一处；按 cr T2 一并补 TimerBottomSheet widget 测试锚定 tile 集合（D3 漂移未被抓的直接原因）。REF-12 设计裁决（D5，证据修正：cr 只 grep lib/，test/ 有 25+ 处读取）：**删残留**而非接读取方——生产运行时速真理源是 player.speedStream（speed_control:21-24/79、orchestrator:201），手写镜像制造双源漂移（P10 反面），"接读取方"无自然读取点；删除 player_provider:178/180-181/336-338、speed_control:80、di:97 五处，测试迁移把容器级"写镜像模拟调速"升级为 SpeedControl widget 门控测试（ref_12_speed_gate_test.dart，MockAudioPlayer 直测 speed_control.dart:78-84 remember 门控）；PLY-T43/44 纯镜像存在性测试删除。REF-13 设计裁决（D6）：**删两处 invalidate**（progress_provider.dart:102/:130）——family 全项目（lib+test）零消费，invalidate 对未创建元素 no-op 纯噪音；保留 recentlyPlayedProvider 定义+di re-export+DAO getRecentlyPlayed 作为未来「最近播放」功能位；写路径 invalidate 集收敛为真实订阅面（progressForFile/latestPlayed，P10 纪律）
- 2026-08-16: 新增 REF-06、REF-07、REF-08（cr-20260816-0803-browser-home.md D1 + cr-20260816-0804-connection-playlist.md D1/D2 用户裁决"修"→ 转 REF 需求流程落地；DESIGN 条目无 repro 门禁要求）。REF-06 设计裁决：clearDirectoryCacheProvider 签名改双参 `int Function(int? connectionId, String? path)`——connectionId+path 非空 → `'$connectionId:$path'` 全等精确匹配（跨连接误清消除）；path==null → 全量清除语义与修复前逐字节一致（connectionId 忽略）；connectionId null + path 非空 → 降级旧后缀匹配保守回退（生产调用方不走此形状，S7 负断言锚定）；子目录不被父路径清除（S5 负断言）。生产调用方两处：browser_screen.dart:71 下拉刷新传活跃连接 id（S8）、settings_screen.dart:233 全量清除改 (null,null)（S9）；切换连接清缓存走 ref.invalidate(directoryCacheProvider) 直清不受影响（§7）。既有 brw_05/brw_06/set_01 三份测试单参调用点必须同步改双参（§5.1 列明行号）。REF-07 设计裁决：importPlaylist 空串/纯空白名归默认名 `'导入的播放单'`（playlist_service.dart:162 单行修改，与"缺失"同语义）；**不做一般性 trim**（'  X  ' 原样保存，S6 负断言）；createPlaylist 不改（UI 门禁 playlist_list_screen.dart:167-168 保持为创建路径唯一门禁，S8 负断言）；已落库空名不追溯改名（导出再导入自然归一，S7）；BUG-25-S1 is-check 结构保留（INV2）。与 BUG-11（连接添加入口）无交集（§7 显式声明）。REF-08 设计裁决：PlaylistService 构造注入 `DateTime Function()? clock`（playlist_dao.dart:13-19 BUG-26-S4 同款，`clock ?? DateTime.now`），:36/:70/:166 三处 DateTime.now() 改 `_clock()` 单次取时（S3/S4 计数时钟负断言：去重文件与空列表不多取时）；playlistServiceProvider 装配不改（S6 源码级负断言）；DAO insert 路径不覆盖 model 时间戳保持为 INV1（insert 时间戳权威归 service 时钟）；playlist_detail_screen.dart:276 重命名路径 UI 层 DateTime.now() 不改（DAO updatePlaylist :81 以自身 _clock 覆盖 updated_at，值不落库，§3.2 边界表）
- 2026-08-16: 新增 REF-01、REF-02（cr-20260816-0801-core-shared.md D1/D2 用户裁决"修"→ 转 REF 需求流程落地；DESIGN 条目无 repro 门禁要求）。REF-01 设计裁决：绝对 URL href 以 host 相同（大小写不敏感）判定"本服务器"剥 authority（端口/scheme 不参与——反代/端口改写场景），根挂载不再跳过 relativise（相对 href 行为逐字节保持，INV2 锚定），异 host 原样不吞（S6 否定断言）；normalizeStoredPath 语义不改，仅注释措辞许可（webdav_paths.dart:115-116 声称与 _relativisePath identical 在绝对 URL 输入上不再严格成立，存储数据无该形态生产者）。REF-02 设计裁决：统一规则"新字段默认入等、例外仅限自增 id 与审计时间戳、除外必须登记+否定断言锚定"，新增 lib/shared/models/equality_registry.dart 为唯一登记点（6 模型全量），现有相等性语义零变更（既有 model_equality_test 断言不改）；勘察补出 cr 原文外的 2 条测试缺口——PlayProgress.lastPlayedAt 除外（play_progress.dart:107-118）与 Playlist.createdAt/updatedAt 除外（playlist.dart:60-69）均零锚定，S8/S9 补断言
- 2026-08-16: 新增 REF-03、REF-04、REF-05（cr-20260816-0802-player.md D1/D2/D3 用户裁决"修"→ 转 REF 需求流程落地；DESIGN 条目无 repro 门禁要求）。REF-03 设计裁决：删死面方案 A——notifier 缩为只读镜像，删除 7 个零调用驱动方法（onAppLifecycleChange/onMediaControl/onAudioFocusChange/startPlayback/pausePlayback/stopPlayback/setBackgroundEnabled）+ mapLifecycleState + backgroundPlaybackEnabledProvider（player_provider.dart:219）；**保留 syncFromHandler + backgroundPlaybackProvider + backgroundPlaybackSyncProvider**——与 BUG-02-S5 修复方案（接线载体依赖 `ref.read(backgroundPlaybackProvider.notifier)` 与 `n.syncFromHandler`，BUG-02.md §3.2）显式裁决不冲突，两条目可任意顺序执行；domain 纯函数与 ply_03 对其测试保留（cr 原文裁决）；ply_03/ref_13 中死面测试同步删除。REF-04 设计裁决：superseded 不渲染 error（'加载已被新的播放请求替换'文案消失），改对齐自检——播放器已与队列一致（sequenceState!=null + sourceMatchesQueue + processingState!=idle，复用 initState 快路径既有符号）→ 直接 ready；未对齐 → 保持 loading + 自动重发 _loadAndPlay() 收敛（补 cr 修复建议未覆盖的边界：外部请求——通知栏 skip/自动切歌/removeTrack——落地后页面状态不更新会永久 loading，S3 勘察实证）。REF-05 设计裁决：QueueSheet 改 ConsumerWidget 内部 watch currentPlayQueueProvider（经 shared/di 桥接，不直接 import browser_provider），删 queue 构造参数、两个调用方（player_screen.dart:237-255 / mini_player_bar.dart:142-158）签名同步删参；queue null/empty → 空态文本'队列为空'（不自动 pop，P11 纪律）；ListTile 加 ValueKey(file.path)（P13 处置）；越界兜底（orchestrator:320 → snackbar）保持。
- 2026-08-16: 新增 BUG-19（cr-20260816-0806-test-helpers.md F1 复核确认后落地；repro 门禁以 repro-test.sh fail 确认真实 FAIL——bug_19_repro_test.dart Part B 实证 openTestDatabase(playlist) 的 sqlite_master.sql 为裸 CREATE TABLE（test_database.dart:63/70/77 无 IF NOT EXISTS），与生产 database_helper.dart:81/89/99 幂等语义不一致；Part A（生产真实 v1→v2 迁移，经 DatabaseHelper.instance.database 驱动 onUpgrade，含数据搬迁/user_version/FK+CASCADE/升级重跑幂等）当前 PASS 修复后保留为锚定。勘察实证一处超出 cr 原文：test_database.dart:62-78 副本缺 IF NOT EXISTS 是可观测差异点（cr 仅称"逐字段一致"，未提幂等语义差），repro 以此作为当前 FAIL 断言；修复唯一 lib/ 改动为 database_helper.dart 新增公开 createSchema 包装 _onCreate，test_database/db_migration_test 内联副本全部删除）
- 2026-08-16: 新增 BUG-18（cr-20260816-0805-progress-timer-settings.md F1 复核确认后落地；repro 门禁以 repro-test.sh fail 确认真实 FAIL——bug_18_repro_test.dart 实证 DAO 读进度抛错时 takeException 非空 + 不跳 /player + 无失败日志）。勘察实证一处超出 cr 原文：onFileLongPress 的恢复进度查询（browser_screen.dart:167-170）与 onFileTap 同类裸奔（cr F1「读路径是唯一裸奔点」应含此点），修复一并覆盖（BUG-18-S4）。修复语义对齐 playlist_detail_screen.dart:48-75（catch-log 裁决，SCHEMA.md §5）
- 2026-08-16: 新增 BUG-11~BUG-17（cr-20260816-0804-connection-playlist.md B1/B2/B3 + F1/F2/F3/F4 复核确认后落地；7 条 repro 门禁均以 repro-test.sh fail 确认真实 FAIL——bug_bug11 实证列表页/空态无添加入口、bug_bug12 实证非法 basePath 校验放行、bug_bug13 实证"检查连接"pushNamed 抛 FlutterError、bug_bug14 实证 reset 后 in-flight 完成落地 Success、bug_bug15 实证创建失败 unhandled async exception、bug_bug16 实证切换期间退出页面后浏览器状态不复位、bug_bug17 实证步骤 4/5 失败孤儿行+永久 key 残留。命名：bug_11~17_repro_test.dart 已被旧轮占用，全部用全称形态 bug_bug{N}_repro_test.dart）。勘察实证两处超出 cr 原文：① BUG-13 修复用 context.pop() 须 /player 为 push 页面（go_router 14.8.1 delegate.dart:98-105 栈底 pop 抛 GoError），repro 按生产形态 push 进入；② BUG-17 回滚删行撞 DAO CON-T32 守卫（connection_dao.dart:119-122，首次添加 0→1 时步骤 2 回滚已失效的连带缺陷），修复引入契约方法 deleteWithoutGuard 一并处置
- 2026-08-16: 新增 BUG-09、BUG-10（cr-20260816-0803-browser-home.md B1 + F1 复核确认后落地；2 条 repro 门禁均以 repro-test.sh fail 确认真实 FAIL——bug_09_repro_test.dart 实证 channel 收到 moveTaskToBack + navStack 2→1；bug_bug10_repro_test.dart 实证固定文案缺失 + 日志无原始异常。命名：bug_10_repro_test.dart 已被旧轮 PRG1 占用，F1 门禁用全称形态 bug_bug10_repro_test.dart）。实证修正 cr 报告一处：播放单 Tab + 浏览器栈深按返回（cr B1 同族场景）不出现静默目录回退——TabBarView 非可见页 dispose，BrowserScreen 的 PopScope 不注册（bug_09 用例 3 修复前 PASS 为证），故 BUG-09 修复仅需 home_screen.dart 侧判定，见 BUG-09-S3/S6）
- 2026-08-16: 新增 BUG-03~BUG-08（cr-20260816-0802-player.md B1/B2/B3 + F2/F3/F4 复核确认后落地；cr-0802 F1 与 BUG-01/02 方案重叠，折叠归并不建文档，见"折叠归并备注"）。6 条 repro 门禁均以 repro-test.sh fail 确认真实 FAIL（bug_03/04/05/06/07/08_repro_test.dart）
- 2026-08-16: 新增 BUG-01、BUG-02（cr-20260816-0801-core-shared.md B1/F1 复核确认后落地；repro 门禁均以 repro-test.sh fail 确认真实 FAIL）
- 2026-08-15: 全部 49 份 spec（BUG-04~32 / REF-01~09 / TEST-01~11）已 impl/test/check 全闭环，随清理任务归档删除（git 历史保留）。dev-status.json 同步清空。
- 2026-08-05: cr-20260804-1922 §4 复核修订同步——BUG-04（S2 片段 n=1 死循环更正 + §5.4 门禁改指向 bug_bug04_fixed_test.dart）/ BUG-10（门禁欠账标注 + dev-status gaps 记账）/ BUG-18（audio_session 误记核查：本文件无记录，误记在 BUG-22）/ BUG-22（audio_session 依赖位置更正为 dependencies 主依赖）/ BUG-25（S4/S5 原方案实证不可行，按落地实现更正）/ BUG-32（日志文案快照按 f4ef23b 更正 + S2 测试路径笔误）；最近更新列同步
- 2026-08-06: REF-01～REF-09 修订——补 §5.4「测试文件位置」门禁节（spec-scan --gate 硬门禁前置，af084af 引入）；最近更新列同步
- 2026-07-27: 新增 BUG-18～BUG-32、REF-05～REF-09、TEST-09～TEST-11（cr-2026-06-28 + cr-20260724-0110.md 全量纳入）
- 2026-07-27: 新增 TEST-05～TEST-08（cr-20260724-0110.md PRG7-9 + TMR6-7 + NET9-10+CTR7 + SVC8-10）
- 2026-07-27: 新增 TEST-01～TEST-04（cr-20260724-0110.md 测试缺口）
- 2026-07-27: 新增 REF-01～REF-04（cr-2026-06-28 + cr-20260724-0110.md 重构项）
- 2026-07-27: 清空历史产物，基于 cr-20260724-0110.md 剩余问题重建索引
- 2026-07-27: 新增 BUG-27（PLY4+PLY5）、BUG-28（SET1）
