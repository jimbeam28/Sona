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
| REF-01 | Domain 层 Flutter 依赖清理（A1-A6） | draft | 2026-07-27 | `lib/features/*/domain/*.dart` (6 files) | SET, CON, PLY, BRW | 9/3/0 | pending / pending / pending |
| REF-02 | 契约层真启用（CTR2-CTR6+SVC6+PRG5） | draft | 2026-07-27 | `lib/core/contracts/*.dart` | CON, PLY, BRW, PRG, SET, TMR | 11/5/0 | pending / pending / pending |
| REF-03 | 死代码清理（PRG4+DB8） | draft | 2026-07-27 | `lib/features/progress/domain/progress_service.dart` | PRG | 3/2/0 | pending / pending / pending |
| REF-04 | 架构整合（SET2+DI1+DI2+DI3） | draft | 2026-07-27 | `lib/features/settings/domain/settings_service.dart` | SET, PLY, BRW | 5/4/0 | pending / pending / pending |
| REF-05 | 定时器死代码清理（TMR2+TMR4+TMR5） | draft | 2026-07-27 | `lib/features/timer/timer_provider.dart` | PLY | 4/3/0 | pending / pending / pending |
| REF-06 | 浏览器死代码（BRW6+BRW7） | draft | 2026-07-27 | `lib/features/browser/browser_provider.dart` | — | 2/3/0 | pending / pending / pending |
| REF-07 | ConnectionConfig ==/hashCode 补全（MDL5） | draft | 2026-07-27 | `lib/shared/models/connection_config.dart` | CON | 2/2/0 | pending / pending / pending |
| REF-08 | installLogBufferHook 幂等化（SVC7） | draft | 2026-07-27 | `lib/core/services/log_buffer.dart` | — | 1/2/0 | pending / pending / pending |
| REF-09 | _SectionHeader 共享组件提取（SET4） | draft | 2026-07-27 | `lib/features/settings/settings_screen.dart` | — | 1/2/0 | pending / pending / pending |

## Bug 文档

| ID | 名称 | 状态 | 最近更新 | 主锚点文件 | 主归属 feature | 跨模块影响 | S/INV/ALG | impl / test / check |
|---|---|---|---|---|---|---|---|---|
| BUG-04 | Shuffle 排列一致性缺陷簇 | draft | 2026-08-05 | `lib/shared/models/play_queue.dart` | null（跨模块） | PLY, BRW | 4/3/2 | pending / pending / pending |
| BUG-05 | 通知/锁屏 play() 缺 completed 态 seek(0) 恢复 | draft | 2026-07-27 | `lib/core/services/audio_handler.dart` | Player | — | 1/1/0 | pending / pending / pending |
| BUG-06 | "下一曲"图标启用态不响应播放状态 | draft | 2026-07-27 | `lib/features/browser/browser_screen.dart` | Browser | PLY | 2/1/0 | pending / pending / pending |
| BUG-07 | AppBar 排序菜单不随 Tab 切换刷新 | draft | 2026-07-27 | `lib/features/home/home_screen.dart` | Home | — | 1/1/0 | pending / pending / pending |
| BUG-08 | 播放单批添加 ≥40 曲目显示乱序 + 拖拽移错 | draft | 2026-07-27 | `lib/features/playlist/playlist_provider.dart` | Playlist | — | 2/1/0 | pending / pending / pending |
| BUG-09 | 添加曲目弹窗跨目录全选判定错误 | draft | 2026-07-27 | `lib/features/playlist/widgets/add_tracks_browser.dart` | Playlist | — | 1/1/0 | pending / pending / pending |
| BUG-10 | 删除活跃连接后不复位导航栈 | draft | 2026-08-05 | `lib/features/connection/connection_provider.dart` | Connection | BRW | 1/1/0 | pending / pending / pending |
| BUG-11 | WebDAV XML 解析不做实体反转义 | draft | 2026-07-27 | `lib/core/network/webdav_client.dart` | null（core） | BRW | 1/1/0 | pending / pending / pending |
| BUG-12 | normaliseWebDavUrl 无 try/catch | draft | 2026-07-27 | `lib/core/network/webdav_client.dart` | null（core） | CON | 1/1/0 | pending / pending / pending |
| BUG-13 | "从头播放"不删进度记录 | draft | 2026-07-27 | `lib/features/progress/progress_dialog.dart` | Progress | — | 1/1/0 | pending / pending / pending |
| BUG-14 | PlayQueue shuffle 状态只写不读 | draft | 2026-07-27 | `lib/features/browser/browser_provider.dart` | null（跨模块） | PLY | 2/2/0 | pending / pending / pending |
| BUG-15 | 音频识别基于 displayname 而非 href | draft | 2026-07-27 | `lib/shared/models/nas_file.dart` | null（跨模块） | BRW | 1/1/0 | pending / pending / pending |
| BUG-16 | FK PRAGMA 只在 onCreate 置位 | draft | 2026-07-27 | `lib/core/database/database_helper.dart` | null（core） | PLY | 2/2/0 | pending / pending / pending |
| BUG-17 | seek/setSpeed 无超时保护 | draft | 2026-07-27 | `lib/core/services/audio_handler.dart` | Player | — | 2/1/0 | pending / pending / pending |
| BUG-18 | loadAndPlay 12s 轮询等待播放开始 | draft | 2026-08-05 | `lib/features/player/domain/playback_orchestrator.dart` | null（跨模块） | PLY | 0/2/0 | pending / pending / pending |
| BUG-19 | saveProgress fire-and-forget 无错误处理 | draft | 2026-07-27 | `lib/features/player/domain/playback_orchestrator.dart` | Player | PLY, PRG | 1/1/0 | pending / pending / pending |
| BUG-20 | 10-15s 短文件 shouldClear 阈值过激 | draft | 2026-07-27 | `lib/features/progress/domain/progress_policy.dart` | null（跨模块） | PRG | 1/2/1 | pending / pending / pending |
| BUG-21 | autoSave/pauseSave provider 缺 ref.onDispose 资源泄漏 | draft | 2026-07-27 | `lib/features/player/player_provider.dart` | Player | PLY | 2/2/0 | pending / pending / pending |
| BUG-22 | 音频焦点死代码 + 无超时（SVC2 + SVC3） | draft | 2026-08-05 | `lib/core/services/audio_handler.dart` | Player | PLY | 2/3/0 | pending / pending / pending |
| BUG-23 | 网络健壮性缺陷簇（NET4+NET5+NET6+NET8） | draft | 2026-07-27 | `lib/core/network/webdav_client.dart` | null（core） | BRW, CON | 5/3/0 | pending / pending / pending |
| BUG-24 | 连接编辑健壮性（CON5+CON6+CON7+CON8） | draft | 2026-07-27 | `lib/features/connection/domain/connection_service.dart` | Connection | CON | 4/4/0 | pending / pending / pending |
| BUG-25 | 播放单健壮性（LIST3+LIST5+LIST6+LIST7+LIST8） | draft | 2026-08-05 | `lib/features/playlist/domain/playlist_service.dart` | Playlist | PLY | 5/6/0 | pending / pending / pending |
| BUG-26 | DAO 健壮性缺陷簇（DB3+DB4+DB5+DB6） | draft | 2026-07-27 | `lib/core/database/dao/playlist_dao.dart` | null（跨模块） | PLY, CON, PRG | 4/4/0 | pending / pending / pending |
| BUG-27 | 播放器健壮性（PLY4+PLY5） | draft | 2026-07-27 | `lib/features/player/domain/playback_orchestrator.dart` | null（跨模块） | PLY | 2/3/0 | pending / pending / pending |
| BUG-28 | setSeekStepSettingProvider 忽略校验返回值（SET1） | draft | 2026-07-27 | `lib/features/settings/settings_provider.dart` | null（跨模块） | SET, PLY | 1/2/0 | pending / pending / pending |
| BUG-29 | 定时器显示一致性（TMR1+TMR3） | draft | 2026-07-27 | `lib/features/timer/timer_provider.dart` | Timer | TMR | 2/2/0 | pending / pending / pending |
| BUG-30 | NasFile ==/hashCode 漏 modifiedAt（MDL3） | draft | 2026-07-27 | `lib/shared/models/nas_file.dart` | null（跨模块） | BRW | 2/2/0 | pending / pending / pending |
| BUG-31 | 浏览器 UI 与可测性（BRW5+BRW8） | draft | 2026-07-27 | `lib/features/browser/browser_screen.dart` | Browser | BRW | 3/2/0 | pending / pending / pending |
| BUG-32 | 服务层健壮性（SVC4+SVC5） | draft | 2026-08-05 | `lib/core/services/storage_utils.dart` | null（跨模块） | CON, PLY, BRW | 2/3/0 | pending / pending / pending |

> "主归属 feature"列对应 `BUG-NN.md` §0 的 `parent_feature` 字段；`null` 表示跨模块 bug 无单一归属。

## TEST-GAP 文档

| ID | 名称 | 状态 | 最近更新 | 主锚点文件 | 归属 feature | S/INV/ALG | test / check |
|---|---|---|---|---|---|---|---|
| TEST-01 | 浏览器测试缺口（BRW9+BRW10+BRW11） | draft | 2026-07-27 | `lib/features/browser/browser_screen.dart` | Browser | 9/3/0 | pending / pending |
| TEST-02 | 连接测试缺口（CON11+CON12+CON13） | draft | 2026-07-27 | `lib/features/connection/connection_list_screen.dart` | Connection | 7/3/0 | pending / pending |
| TEST-03 | 主页测试缺口（HOME2+HOME3+HOME4） | draft | 2026-07-27 | `lib/features/home/home_screen.dart` | Home | 7/3/0 | pending / pending |
| TEST-04 | 播放单测试缺口（LIST9+LIST10） | draft | 2026-07-27 | `lib/features/player/widgets/mini_player_bar.dart` | Playlist | 6/2/0 | pending / pending |
| TEST-05 | 进度测试缺口（PRG7+PRG8+PRG9） | draft | 2026-07-27 | `lib/features/progress/progress_dialog.dart` | Progress | 4/2/0 | pending / pending |
| TEST-06 | 定时器测试缺口（TMR6+TMR7） | draft | 2026-07-27 | `lib/features/timer/domain/timer_service.dart` | Timer | 7/3/0 | pending / pending |
| TEST-07 | 网络/helper 测试缺口（NET9+NET10+CTR7） | draft | 2026-07-27 | `lib/core/network/webdav_client.dart` | null（跨模块） | 7/2/0 | pending / pending |
| TEST-08 | 服务层测试缺口（SVC8+SVC9+SVC10） | draft | 2026-07-27 | `lib/core/services/audio_handler.dart` | null（跨模块） | 8/2/0 | pending / pending |
| TEST-09 | 数据库集成测试缺口（TG-DB1） | draft | 2026-07-27 | `lib/core/database/dao/progress_dao.dart` | null（跨模块） | 3/2/0 | pending / pending |
| TEST-10 | 模型测试缺口（MDL6+MDL7） | draft | 2026-07-27 | `lib/shared/models/connection_config.dart` | null（跨模块） | 7/2/0 | pending / pending |
| TEST-11 | 设置测试缺口（SET3 — LogViewer 行为测试） | draft | 2026-07-27 | `lib/features/settings/log_viewer_screen.dart` | Settings | 3/2/0 | pending / pending |

> TEST-GAP 文档专注测试补强，不修改生产代码。test_status 标注补测进度。

---

## 状态汇总

- 功能文档：0 份
- Refactoring 文档：9 份（全部 draft）
- Bug 文档：29 份（全部 draft）
- TEST-GAP 文档：11 份（全部 draft）
- 待 dev-exe：49 份

---

## 已知缺口

（暂无）

---

## changelog

- 2026-08-05: cr-20260804-1922 §4 复核修订同步——BUG-04（S2 片段 n=1 死循环更正 + §5.4 门禁改指向 bug_bug04_fixed_test.dart）/ BUG-10（门禁欠账标注 + dev-status gaps 记账）/ BUG-18（audio_session 误记核查：本文件无记录，误记在 BUG-22）/ BUG-22（audio_session 依赖位置更正为 dependencies 主依赖）/ BUG-25（S4/S5 原方案实证不可行，按落地实现更正）/ BUG-32（日志文案快照按 f4ef23b 更正 + S2 测试路径笔误）；最近更新列同步
- 2026-07-27: 新增 BUG-18～BUG-32、REF-05～REF-09、TEST-09～TEST-11（cr-2026-06-28 + cr-20260724-0110.md 全量纳入）
- 2026-07-27: 新增 TEST-05～TEST-08（cr-20260724-0110.md PRG7-9 + TMR6-7 + NET9-10+CTR7 + SVC8-10）
- 2026-07-27: 新增 TEST-01～TEST-04（cr-20260724-0110.md 测试缺口）
- 2026-07-27: 新增 REF-01～REF-04（cr-2026-06-28 + cr-20260724-0110.md 重构项）
- 2026-07-27: 清空历史产物，基于 cr-20260724-0110.md 剩余问题重建索引
- 2026-07-27: 新增 BUG-27（PLY4+PLY5）、BUG-28（SET1）
