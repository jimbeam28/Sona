# features 文档索引

> 用途：dev-plan 在步骤 0 判断"新需求是否已有对应文档"时扫本索引即可，不必逐个打开 `docs/features/*.md` 读 §1.1。
> 维护：每次 dev-plan 创建或修订 `{ID}.md` 后必须同步更新本索引；dev-check / dev-exe 不动本索引。
> 配套关系：
> - `docs/dev/dev-status.json` 是**工作队列**（done+passed 项会被清出，参见 dev-plan 步骤 4.1），不是完整登记簿
> - 本索引才是 `docs/features/` 的**完整登记**——含已清出 status.json 的历史 spec（如 CON-01）

---

## 如何使用本索引（dev-plan 步骤 0 决策路径）

新需求 / Bug 进来时：

1. 按模块（CON / BRW / PLY / TMR / PRG / SET）在下面"功能文档"表找候选
2. 比对"名称"列与"主锚点文件"列，判断是否落在已有 `{ID}.md` 范围内
3. 命中 → **修订模式**（步骤 1B），读对应 `{ID}.md` 的 §1.1 + §1.2 确认范围
4. 未命中 → **新建模式**（步骤 1A），按模块编号尾号自增
5. Bug：dev-plan 步骤 0 hybrid 策略——
   - 单特性 bug 且对应 feature 文档**已存在** → 走修订模式 fold 为 `status: new` Scenario（**不建独立 BUG-NN.md**）
   - 单特性 bug 且对应 feature 文档**不存在** → 新建 `BUG-NN.md`（BUG-02 / BUG-03 即此情形）
   - 跨模块 bug 无单一归属 → 新建 `BUG-NN.md`（BUG-01 即此情形）

---

## 功能文档

| ID | 名称 | 状态 | 最近更新 | 主锚点文件 | S/INV/ALG | impl / test / check | MQA | 在 status.json |
|---|---|---|---|---|---|---|---|---|
| BRW-09 | 文件列表"下一曲播放"图标 | draft | 2026-06-28 | `lib/features/browser/widgets/file_list_item.dart` | 9/4/1 | done / passed / pending | no | yes |
| CON-01 | 添加 WebDAV 连接 | active | 2026-06-28 | `lib/features/connection/connection_screen.dart` | 15/7/0 | done / passed / — | no | no（done 后清出） |
| SET-01 | 设置页"清除目录缓存" | draft | 2026-07-23 | `lib/features/settings/settings_screen.dart` | 7/3/0 | pending / pending / pending | no | yes |

## Bug 文档

| ID | 名称 | 状态 | 最近更新 | 主锚点文件 | 主归属 feature | 跨模块影响 | S/INV/ALG | impl / test / check |
|---|---|---|---|---|---|---|---|---|
| BUG-01 | PlayQueue == / hashCode 漏比 shuffle 字段 | active | 2026-06-28 | `lib/shared/models/play_queue.dart` | null（跨模块） | PLY, PRG, BRW-09 | 6/3/0 | done / passed / pending |
| BUG-02 | addTracksToPlaylist 缺内存内去重 | active | 2026-06-28 | `lib/features/playlist/domain/playlist_service.dart` | Playlist | — | 3/2/0 | done / passed / pending |
| BUG-03 | TimerService.resume() 用 ceil() 转分钟精度损失 | active | 2026-06-28 | `lib/features/timer/domain/timer_service.dart` | Timer | PRG | 5/3/1 | done / passed / pending |

> "主归属 feature"列对应 `BUG-NN.md` §0 的 `parent_feature` 字段；`null` 表示跨模块 bug 无单一归属。

---

## 状态汇总

- 功能文档：3 份（CON-01 active / BRW-09 draft / SET-01 draft）
- Bug 文档：3 份（全部 active）
- 待 dev-check：4 份（BRW-09 / BUG-01 / BUG-02 / BUG-03，全部 `check_status=pending`）
- 已清出 `dev-status.json` 但 spec 留存：1 份（CON-01，impl+test 已 done，仅作历史 spec）
- 进行中：SET-01（新流程 dogfood，impl=pending）

---

## 已知缺口

（暂无）

---

## changelog

- 2026-07-05: 首版索引创建（5 份文档登记：BRW-09 / CON-01 / BUG-01 / BUG-02 / BUG-03）
- 2026-07-05: 配套 dev-plan skill 步骤 0 引入 hybrid bug fold 策略 + INDEX 同步门禁；3 份 BUG-NN.md §0 加 `parent_feature` 字段；_TEMPLATE.md 加 `parent_feature` 字段定义；"已知缺口"原 3 项全部解决清空
- 2026-07-23: 登记 SET-01（新流程重构后首个 dogfood 功能）
