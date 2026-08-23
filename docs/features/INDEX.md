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

## Refactoring 文档

| ID | 名称 | 状态 | 最近更新 | 主锚点文件 | 跨模块影响 | S/INV/ALG | impl / test / check |
|---|---|---|---|---|---|---|---|
| REF-01 | listDirectory 绝对 URL href 相对化（含根挂载） | active | 2026-08-16 | lib/core/network/webdav_client.dart | BRW, PLY, PLT | 7/2/1 | pending / pending / pending |
| REF-02 | 值对象相等性统一规则与集中登记表 | active | 2026-08-16 | lib/shared/models/connection_config.dart | CON, PRG, PLT, PLY, BRW | 9/3/0 | pending / pending / pending |
| REF-03 | 后台播放状态机去镜像（handler 唯一状态机，notifier 缩为只读镜像） | active | 2026-08-16 | lib/features/player/background_playback_notifier.dart | PLY, HOME | 8/2/0 | pending / pending / pending |
| REF-04 | superseded 结果不渲染错误态（保持 loading / 对齐即 ready / 自动重发收敛） | active | 2026-08-16 | lib/features/player/player_screen.dart | PLY | 5/2/0 | pending / pending / pending |
| REF-05 | 队列面板 live 数据源（watch currentPlayQueueProvider + ValueKey + 空态） | active | 2026-08-16 | lib/features/player/widgets/queue_sheet.dart | PLY, BRW, HOME | 7/2/0 | pending / pending / pending |
| REF-06 | clearDirectoryCacheProvider 连接级精确匹配（path 后缀匹配 → 连接级全等） | active | 2026-08-16 | lib/features/browser/browser_provider.dart | BRW, SET, CON | 9/2/1 | pending / pending / pending |
| REF-07 | importPlaylist 空名/纯空格名归一默认名（服务层裁决，UI 创建门禁语义对齐） | active | 2026-08-16 | lib/features/playlist/domain/playlist_service.dart | PLT | 8/2/1 | pending / pending / pending |
| REF-08 | PlaylistService 注入 now provider（createPlaylist/addTracksToPlaylist/importPlaylist） | active | 2026-08-16 | lib/features/playlist/domain/playlist_service.dart | PLT | 6/2/0 | pending / pending / pending |
| REF-09 | 数据层反向依赖 feature 解耦（core→feature 零依赖） | active | 2026-08-16 | lib/core/database/dao/progress_dao.dart | PRG, PLY, Core | 9/3/1 | pending / pending / pending |
| REF-10 | settings_service 顶层函数与实例方法双份实现统一为实例方法单份 | active | 2026-08-16 | lib/features/settings/domain/settings_service.dart | SET | 6/3/0 | pending / pending / pending |
| REF-11 | 定时弹窗补回 15 分钟预设 tile（对齐头注释/TMR-T26 文档） | active | 2026-08-16 | lib/features/timer/widgets/timer_button.dart | TMR, HOME | 6/3/0 | pending / pending / pending |
| REF-12 | 删除 currentSpeedProvider write-only 残留 | active | 2026-08-16 | lib/features/player/player_provider.dart | PLY, SET | 8/3/0 | pending / pending / pending |
| REF-13 | 删除 upsert/clear 对 recentlyPlayedProvider 的无效 invalidate | active | 2026-08-16 | lib/features/progress/progress_provider.dart | PRG, PLY | 6/2/0 | pending / pending / pending |
| REF-14 | FakeSecureStorage 挂起变体提取（HangingFakeSecureStorage 共享化） | active | 2026-08-16 | test/helpers/fake_secure_storage.dart | —（测试基础设施） | 10/2/0 | pending / pending / pending |
| REF-15 | int_g06 8 处 addTearDown tear-off 坏形态修正（ProviderContainer 真正释放） | active | 2026-08-16 | test/features/coverage/int_g06_lifecycle_test.dart | —（纯测试代码） | 4/1/0 | pending / pending / pending |
| REF-16 | coverage-debt.txt 过期登记移除（timer_service 97.30% / playback_orchestrator 98.39%） | active | 2026-08-16 | docs/dev/coverage-debt.txt | —（流程记账） | 6/1/0 | pending / pending / pending |
| REF-17 | Provider 层平台包直引收敛（组合根豁免显式化 + LastConnectionException 上提 + 门禁盲区封堵） | active | 2026-08-22 | lib/features/connection/connection_provider.dart | PLY, CON, Core | 3/1/0 | pending / pending / pending |
| REF-18 | switch/delete 连接写副作用移出 FutureProvider build 体（P11 模式收敛） | active | 2026-08-22 | lib/features/connection/connection_provider.dart | BRW, CON | 3/1/0 | pending / pending / pending |

## Bug 文档

| ID | 名称 | 状态 | 最近更新 | 主锚点文件 | 主归属 feature | 跨模块影响 | S/INV/ALG | impl / test / check |
|---|---|---|---|---|---|---|---|---|
| BUG-01 | 通知栏/耳机 skip 必抛 TypeError（QueueHandler.queueIndex! 解包） | active | 2026-08-16 | lib/core/services/audio_handler.dart | Player | PLY | 5/2/0 | pending / pending / pending |
| BUG-02 | skip 回调绑定 PlayerScreen dispose，退出播放页后通知栏按钮失效（P8） | active | 2026-08-16 | lib/features/player/player_screen.dart | Player | PLY, HOME | 8/2/0 | pending / pending / pending |
| BUG-03 | gate 超时后守卫复位丢失，自动切歌永久失效（_completingProvider 卡死） | active | 2026-08-16 | lib/features/player/player_provider.dart | Player | PLY, TMR | 6/3/0 | pending / pending / pending |
| BUG-04 | 通知栏/锁屏 mediaItem 从不更新（setMediaItemFromPath 零生产调用方） | active | 2026-08-16 | lib/core/services/audio_handler.dart | Player | PLY | 7/3/0 | pending / pending / pending |
| BUG-05 | loadAndPlay 静默 catch 无日志（catch-log 裁决违规） | active | 2026-08-16 | lib/features/player/domain/playback_orchestrator.dart | Player | PLY | 3/2/0 | pending / pending / pending |
| BUG-06 | 启动恢复 preload 绕门直连 AudioPlayer，晚到副作用覆盖用户选择（P14） | active | 2026-08-16 | lib/features/browser/browser_provider.dart | Browser | BRW, PLY | 5/3/0 | pending / pending / pending |
| BUG-07 | removeTrack 后监听器条件启动依赖旧播放状态（playing 判定） | active | 2026-08-16 | lib/features/player/player_provider.dart | Player | PLY | 4/2/0 | pending / pending / pending |
| BUG-08 | AudioPlayerAdapter 六动作无 5s 超时兜底（P17 分层缺口 + ghost 播放） | active | 2026-08-16 | lib/core/services/audio_player_adapter.dart | Player | PLY, BRW | 6/3/0 | pending / pending / pending |
| BUG-09 | 嵌套 PopScope 双重动作：浏览器子目录返回键同时触发目录回退 + moveTaskToBack | active | 2026-08-16 | lib/features/home/home_screen.dart | Home（跨模块） | HOME, BRW | 6/4/0 | pending / pending / pending |
| BUG-10 | 错误视图对非 WebDavException 暴露原始异常文本（与 BUG-23-S5 裁决相悖） | active | 2026-08-16 | lib/features/browser/browser_screen.dart | Browser | BRW | 3/2/0 | pending / pending / pending |
| BUG-11 | 全 UI 无"添加第二个连接"入口（列表页/空态无添加按钮） | active | 2026-08-16 | lib/features/connection/connection_list_screen.dart | Connection | Settings, App | 5/1/0 | pending / pending / pending |
| BUG-12 | validateBasePath 是死代码，基础路径字段从未接入表单校验 | active | 2026-08-16 | lib/features/connection/widgets/connection_form.dart | Connection | Connection | 3/1/0 | pending / pending / pending |
| BUG-13 | player 错误态"检查连接"按钮用 Navigator.pushNamed 调未注册路由，必抛 FlutterError | active | 2026-08-16 | lib/features/player/player_screen.dart | Player | Connection, App | 3/1/0 | pending / pending / pending |
| BUG-14 | 验证请求 in-flight 期间改字段，过期结果覆盖 reset，保存门被绕过 | active | 2026-08-16 | lib/features/connection/connection_provider.dart | Connection | Connection | 3/1/0 | pending / pending / pending |
| BUG-15 | 新建播放单 fire-and-forget 无错误处理，DB 失败成未捕获异常 | active | 2026-08-16 | lib/features/playlist/playlist_list_screen.dart | Playlist | Playlist | 3/1/0 | pending / pending / pending |
| BUG-16 | 切换连接时 widget 层 invalidate 无 mounted 守卫 + catch 无日志 | active | 2026-08-16 | lib/features/connection/connection_list_screen.dart | Connection | Browser, Connection | 4/1/0 | pending / pending / pending |
| BUG-17 | save() 原子性只覆盖步骤 2，步骤 4/5 失败留下共享临时 key 的孤儿行 | active | 2026-08-16 | lib/features/connection/domain/connection_service.dart | Connection | Connection | 4/3/0 | pending / pending / pending |
| BUG-18 | Browser 读进度路径裸奔无 try/catch（恢复进度查询抛错无反馈无日志） | active | 2026-08-16 | lib/features/browser/browser_screen.dart | Browser | BRW, PRG | 4/2/0 | pending / pending / pending |
| BUG-19 | 生产 DB 迁移逻辑（v1→v2）零锚定：db_migration_test 内联重实现 _onUpgrade、test_database schema 双份手工同步 | active | 2026-08-16 | lib/core/database/database_helper.dart | 跨模块（Core/Database） | Connection, Progress, Playlist, Browser | 6/2/0 | pending / pending / pending |
| BUG-20 | 退出播放页后自动保存/暂停保存监听被取消，后台收听进度丢失窗口 | active | 2026-08-22 | lib/features/player/player_screen.dart | Player | HOME, PRG | 3/2/0 | pending / pending / pending |
| BUG-21 | 末曲播完缺 seek(0)，播放器滞留 completed 态（P2 部分合规） | active | 2026-08-22 | lib/features/player/player_provider.dart | Player | — | 2/1/0 | pending / pending / pending |
| BUG-22 | deletePlaylist 漏 invalidate 曲目 family 缓存（幽灵数据滞留） | active | 2026-08-22 | lib/features/playlist/playlist_provider.dart | Playlist | — | 1/1/0 | pending / pending / pending |

## TEST-GAP 文档

| ID | 名称 | 状态 | 最近更新 | 主锚点文件 | 归属 feature | S/INV/ALG | test / check |
|---|---|---|---|---|---|---|---|

## 状态汇总

- 功能文档：0 份
- Refactoring 文档：18 份
- Bug 文档：22 份
- TEST-GAP 文档：0 份
- 待 dev-exe：40 份（BUG-01 / BUG-02 / BUG-03 / BUG-04 / BUG-05 / BUG-06 / BUG-07 / BUG-08 / BUG-09 / BUG-10 / BUG-11 / BUG-12 / BUG-13 / BUG-14 / BUG-15 / BUG-16 / BUG-17 / BUG-18 / BUG-19 / BUG-20 / BUG-21 / BUG-22 / REF-01 / REF-02 / REF-03 / REF-04 / REF-05 / REF-06 / REF-07 / REF-08 / REF-09 / REF-10 / REF-11 / REF-12 / REF-13 / REF-14 / REF-15 / REF-16 / REF-17 / REF-18）

## 折叠归并备注（cr-20260816-0802 F1）

- **cr-0802 F1（通知/锁屏 skip 回调绑 PlayerScreen 生命周期）折叠归并不建文档**：与 BUG-01（QueueHandler 移除）/ BUG-02（回调接线迁移 backgroundPlaybackSyncProvider 应用级）修复方案完全重叠——F1 证据 `player_screen.dart:77-78/114-115` 与 cr-0801 F1 → BUG-02 的 `player_screen.dart:74-79/112-116` 是同一接线点；"app 启动后未进过 /player 时失效"由 BUG-02-S5（home build eager-wire）+ BUG-02-S7（空队列安全）覆盖；"mini_player_bar 无 skip 按钮"为事实说明无需修复。归并后无独立问题残留。

## 已知缺口

- BUG-02-S7（空队列接线无副作用）与 BUG-01-S1~S3（现状锚定）需 dev-exe 补 provider 级/既有测试锚定（见各 spec §5.2/§5.3）
- BUG-08 修复后需按平台踩坑库规则回写 P17 分层表（adapter 六动作 5s 层）——dev-exe 职责（BUG-08 spec §5.3/§8）

## changelog

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
