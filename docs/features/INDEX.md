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

## Bug 文档

| ID | 名称 | 状态 | 最近更新 | 主锚点文件 | 主归属 feature | 跨模块影响 | S/INV/ALG | impl / test / check |
|---|---|---|---|---|---|---|---|---|

## TEST-GAP 文档

| ID | 名称 | 状态 | 最近更新 | 主锚点文件 | 归属 feature | S/INV/ALG | test / check |
|---|---|---|---|---|---|---|---|

## 状态汇总

- 功能文档：0 份
- Refactoring 文档：0 份
- Bug 文档：0 份
- TEST-GAP 文档：0 份
- 待 dev-exe：0 份

## 已知缺口

（暂无）

## changelog

- 2026-08-15: 全部 49 份 spec（BUG-04~32 / REF-01~09 / TEST-01~11）已 impl/test/check 全闭环，随清理任务归档删除（git 历史保留）。dev-status.json 同步清空。
- 2026-08-05: cr-20260804-1922 §4 复核修订同步——BUG-04（S2 片段 n=1 死循环更正 + §5.4 门禁改指向 bug_bug04_fixed_test.dart）/ BUG-10（门禁欠账标注 + dev-status gaps 记账）/ BUG-18（audio_session 误记核查：本文件无记录，误记在 BUG-22）/ BUG-22（audio_session 依赖位置更正为 dependencies 主依赖）/ BUG-25（S4/S5 原方案实证不可行，按落地实现更正）/ BUG-32（日志文案快照按 f4ef23b 更正 + S2 测试路径笔误）；最近更新列同步
- 2026-08-06: REF-01～REF-09 修订——补 §5.4「测试文件位置」门禁节（spec-scan --gate 硬门禁前置，af084af 引入）；最近更新列同步
- 2026-07-27: 新增 BUG-18～BUG-32、REF-05～REF-09、TEST-09～TEST-11（cr-2026-06-28 + cr-20260724-0110.md 全量纳入）
- 2026-07-27: 新增 TEST-05～TEST-08（cr-20260724-0110.md PRG7-9 + TMR6-7 + NET9-10+CTR7 + SVC8-10）
- 2026-07-27: 新增 TEST-01～TEST-04（cr-20260724-0110.md 测试缺口）
- 2026-07-27: 新增 REF-01～REF-04（cr-2026-06-28 + cr-20260724-0110.md 重构项）
- 2026-07-27: 清空历史产物，基于 cr-20260724-0110.md 剩余问题重建索引
- 2026-07-27: 新增 BUG-27（PLY4+PLY5）、BUG-28（SET1）
