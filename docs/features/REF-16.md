# REF-16 — coverage-debt.txt 两条过期债务登记移除（重扫实测达标清理）

## §0 头部元数据

```yaml
id: REF-16
name: coverage-debt.txt 过期登记移除（timer_service 97.30% / playback_orchestrator 98.39%）
priority: P2
status: active
created_at: 2026-08-16
last_updated: 2026-08-16
spec_anchored_files:
  - docs/dev/coverage-debt.txt
  - docs/dev/scripts/coverage-check.sh
  - docs/dev/baseline-coverage.json
cross_module_impacts: []                 # 流程记账文件清理，零 lib/ 影响
manual_qa_required: false                # 文档/门禁脚本配置变更，不涉平台原生
```

---

## §1 用户视角

### 1.0 原始需求（用户原话逐字记录）

来源：`docs/cr/cr-20260816-0806-test-helpers.md` D2（cr 复核分流，用户裁决"修"→ 转 REF 需求流程；注：任务下达文本将该条标为"cr-0806 D5"，但内容与 cr 报告 D2 逐字一致，D5 实为"本地 mock 变体扩散"——按内容归属 D2）：

> #### D2. coverage-debt.txt 两条登记已过期，与 coverage-check.sh 实测输出不一致
> - 类型 / 严重度 / 维度：DESIGN / Minor / 一致性（流程记账）
> - 证据：
>   - `docs/dev/coverage-debt.txt:10-11`：`timer_service.dart 79.0`、`playback_orchestrator.dart 87.5`；
>   - 本走查实测 `coverage-check.sh check-check` 输出：`lib/features/timer/domain/timer_service.dart: 97.30%`、`lib/features/player/domain/playback_orchestrator.dart: 98.39%`（baseline-coverage.json 同值）——均 ≥ 90% 硬阈；
>   - 登记簿自身规则（coverage-debt.txt:5）："文件只能删除（达 90% 后移出）"。
> - 现象与取舍：两条债务登记已无实际豁免作用（债务底线低于现覆盖），纯记账噪音；若后续覆盖回落到 88%~90% 区间，旧底线会悄悄豁免新欠账，掩盖漂移。
> - 修复建议：达标文件从登记簿移除（符合"只减不增"规则）。

用户裁决：**修**——按实测值重扫更新登记（若已 ≥90% 则删除条目）。

### 1.1 这一功能干什么（一句话）

把覆盖率债务登记簿里两条已经达标的过期登记删掉，恢复这两文件守 90% 硬阈，消除"旧底线悄悄豁免新欠账"的隐患。

### 1.2 用户期望的场景

| ID | 你看到的样子 | 期望行为 |
|----|----|----|
| U1 | 打开覆盖率债务登记簿 | 里面只剩真实的欠账登记，不再有两条已达标（97.30% / 98.39%）的过期条目 |
| U2 | 某个文件覆盖率今后掉到 88%~90% 区间 | 门禁按 90% 硬阈正确拦截（报 FAIL），不会被旧底线悄悄豁免 |
| U3 | 覆盖率门禁检查（check-exe / check-check） | 与清理前一样正常通过，登记簿删除不影响任何门禁数值 |

---

## §2 已实现的功能骨架（代码锚点）

### 2.1 文件与分层

| 层 | 文件 | 行数 | 角色 |
|---|---|---|---|
| 流程记账 | `docs/dev/coverage-debt.txt` | 41 | 覆盖率债务登记：头部规则注释（1-8）+ 两条债务登记（10-11）+ TEST-GAP 注释区（13-41） |
| 门禁脚本 | `docs/dev/scripts/coverage-check.sh` | 265 | 覆盖率三门禁：check-exe（critical ≥90%，债务文件豁免底线）/ check-check（基线漂移）/ refresh（刷基线） |
| 基线 | `docs/dev/baseline-coverage.json` | — | 覆盖率基线（check-check 对照源；critical_files 内含两文件现值） |
| 覆盖率数据 | `coverage/lcov.info` | — | 当前实测数据源（2026-08-15 23:26 生成） |

### 2.2 关键 Provider 表

无 Provider，跳过。

### 2.3 状态机图

无状态机，跳过。

---

## §3 行为规约（Given-When-Then）

### 3.1 现有行为（逆抽）

- **[REF-16-S1]** 登记簿现状：两文件债务登记（timer_service 79.0 / playback_orchestrator 87.5）
  ```
  Given docs/dev/coverage-debt.txt
  When 读取登记条目
  Then 第 10 行 `lib/features/timer/domain/timer_service.dart 79.0`（注释：暂停/恢复边界与 custom 时长分支测试缺口，BUG-03 后未补齐）
  And 第 11 行 `lib/features/player/domain/playback_orchestrator.dart 87.5`（注释：player bug 高发区）
  ```
  Code evidence: `docs/dev/coverage-debt.txt:10-11`

- **[REF-16-S2]** 门禁语义：债务文件豁免 90% 硬阈改守登记底线（底线 79.0 / 87.5）
  ```
  Given coverage-check.sh check-exe 的 load_debt（86-92 行）解析登记簿为 COV_DEBT 关联数组
  When 对 critical 文件做门禁判断（121 行 `floor="${COV_DEBT[$f]:-90.0}"`）
  Then 两文件在登记簿时底线为 79.0 / 87.5（而非 90 硬阈）
  And 文件删除登记后 → COV_DEBT 无该键 → floor 回落 90.0 硬阈
  ```
  Code evidence: `docs/dev/scripts/coverage-check.sh:84-92`（load_debt）/ :121（floor 取值）/ :122-127（比较与输出）

- **[REF-16-S3]** 登记簿规则："只减不增，底线只能上调，文件只能删除（达 90% 后移出）"
  ```
  Given docs/dev/coverage-debt.txt 头部注释与 coverage-check.sh 注释
  When 核对规则
  Then coverage-debt.txt:5 "底线只能上调（补测试后），文件只能删除（达 90% 后移出）；新增登记须说明理由"
  And coverage-check.sh:83 "登记簿只减不增须经评审"
  ```
  Code evidence: `docs/dev/coverage-debt.txt:5`、`docs/dev/scripts/coverage-check.sh:83`

### 3.2 修改方案（status: new）

设计裁决（用户裁决"修"，按实测值更新：两文件均已 ≥90% → **删除条目**，符合"只减不增"规则）：

**实测数据（2026-08-16 dev-plan 复测，数据源 `coverage/lcov.info`，生成时间 2026-08-15 23:26）**：

| 文件 | 命中行 LH | 总行 LF | 实测覆盖率 | 判定 |
|---|---|---|---|---|
| lib/features/timer/domain/timer_service.dart | 72 | 74 | **97.30%** | ≥90% → 删除登记 |
| lib/features/player/domain/playback_orchestrator.dart | 122 | 124 | **98.39%** | ≥90% → 删除登记 |

- 复现命令：`bash docs/dev/scripts/coverage-check.sh check-check` → EXIT=0，输出 `lib/features/timer/domain/timer_service.dart: 97.30%` / `lib/features/player/domain/playback_orchestrator.dart: 98.39%`（与 baseline-coverage.json 同值 97.30 / 98.39，已 jq 核对）。
- 独立核对：awk 直接解析 lcov.info（timer_service LH=72/LF=74、playback_orchestrator LH=122/LF=124）→ 与 check-check 输出一致。

| 边界情况 | 裁决 |
|---|---|
| 两条登记均 ≥90% | 整行删除（coverage-debt.txt:10-11），**不保留任何残留注释**（行 12 空行保留以分隔头部与 TEST-GAP 区） |
| 头部注释（1-8）与"由 2026-07-23 …产出"说明（7-8） | 保留（登记簿用途说明仍有效；TEST-GAP 注释区 13-41 保留——那些是 TEST-GAP 去向登记，非债务登记，不在本次范围） |
| 底线回落后 check-exe 行为 | COV_DEBT 空 → 两文件守 90 硬阈；现覆盖 97.30/98.39 > 90 → 门禁照常 EXIT=0 |
| baseline-coverage.json | **不刷新**——基线漂移检测（check-check）与登记簿无耦合，刷新是 dev-check PASS 后职责（SCHEMA §1.2），本次不动 |
| coverage-check.sh 脚本 | **零改动**（load_debt 对空登记簿返回空数组，逻辑天然兼容，S2 证据） |

- **[REF-16-S4]** 实测两文件当前覆盖率并记录判定（status: new）
  ```
  Given dev-exe 复测（flutter test --coverage 或既有 coverage/lcov.info + check-check）
  When 解析两文件覆盖率
  Then timer_service.dart == 97.30%（LH=72/LF=74）
  And playback_orchestrator.dart == 98.39%（LH=122/LF=124）
  And check-check EXIT=0（两文件无漂移）
  Then 判定：均 ≥ 90% 硬阈 → 登记删除路径（S5）
  否定断言:
    - 若实测值与登记值（79.0 / 87.5）一致（未达标）——本裁决不成立，禁止删除（本条目实测已达标，此路径不触发）
    - 不得改动 baseline-coverage.json（不得 refresh）
  ```
  Code evidence（数据源）: `coverage/lcov.info`（2026-08-15 23:26）；`docs/dev/baseline-coverage.json` critical_files 两键值 97.30/98.39；复测命令 `bash docs/dev/scripts/coverage-check.sh check-check`（本机 EXIT=0 实证，2026-08-16）。

- **[REF-16-S5]** 删除 coverage-debt.txt 第 10-11 行两条登记（status: new）
  ```
  Given docs/dev/coverage-debt.txt 第 10-11 行
  When 编辑
  Then 第 10 行（timer_service.dart 79.0 及行尾注释）整行删除
  And 第 11 行（playback_orchestrator.dart 87.5 及行尾注释）整行删除
  And 第 1-8 行头部注释、第 12 行空行、第 13-41 行 TEST-GAP 注释区原样保留
  否定断言:
    - 不得删除或改动第 13-41 行 TEST-GAP 登记区（那是 TEST-GAP 去向注释，非债务登记）
    - 不得修改第 1-8 行规则注释（"只减不增"规则文本不变）
    - 不得新增任何条目（"只减不增"纪律，S3 证据）
    - 两文件标识符（timer_service / playback_orchestrator）在登记簿中零残留
  ```
  Code evidence（修改点）: `docs/dev/coverage-debt.txt:10-11` 整行删除（修改后文件共 39 行：1-8 头 + 9 空行 + 10-38 TEST-GAP 区…… 注：行号按删除后实际文件为准，dev-exe 以内容匹配删除目标行即可）。

- **[REF-16-S6]** 删除后门禁验证：check-exe EXIT=0，两文件守 90 硬阈（status: new）
  ```
  Given 删除完成
  When bash docs/dev/scripts/coverage-check.sh check-exe
  Then EXIT=0（无债务 → floor=90.0；两文件 97.30%/98.39% > 90% 通过）
  And 输出两行 [ OK ]：lib/features/timer/domain/timer_service.dart — 97.30%
  And 输出两行 [ OK ]：lib/features/player/domain/playback_orchestrator.dart — 98.39%
  And 总覆盖率行与单文件最低行输出正常
  否定断言:
    - 不得出现 [FAIL]（两文件现覆盖高于硬阈，必须 OK）
    - 输出中不得出现"（债务底线 …%）"后缀（登记已删，floor 无债务覆盖）
    - check-check 不得因此变化（基线未动，EXIT=0 保持）
  ```
  Code evidence（验证命令）: `bash docs/dev/scripts/coverage-check.sh check-exe`（`docs/dev/scripts/coverage-check.sh:95-145`；floor 回退逻辑 :121；输出形态 :123-127）。

---

## §4 不变量

- **[REF-16-INV1]** 登记簿只减不增：任何时刻登记条目不得多于上一次评审时刻，且新条目须经评审
  证据：`docs/dev/coverage-debt.txt:5`（"底线只能上调（补测试后），文件只能删除（达 90% 后移出）；新增登记须说明理由"）+ `docs/dev/scripts/coverage-check.sh:83`（"登记簿只减不增须经评审"）。
  测试断言：S5 否定断言"不得新增任何条目"实现。

---

## §5 测试规约

### 5.1 现有测试清单

| 测试文件 | 覆盖的 Scenario / INV | 备注 |
|---|---|---|
| 无（本条目为流程记账文件清理，无既有测试文件直接锚定登记簿内容） | — | 验证方式为脚本退出码（S6） |

### 5.2 测试 ID 派生清单（dev-exe 派发测试 Agent 用）

```
REF-16-S1 … S3        # 现状逆抽（实现前快照，不写测试）
REF-16-S4 … S6        # 修改目标（S4 实测复测 / S5 文件编辑 + grep 校验 / S6 check-exe 退出码）
REF-16-INV1           # 不变量（S5 否定断言实现）
```

dev-exe 要求：S4 由复测命令输出记录；S5 由文件编辑 + `grep -n "timer_service\|playback_orchestrator" docs/dev/coverage-debt.txt` 零残留校验；S6 由 `check-exe` 退出码 0 实现。无新测试文件。

### 5.3 测试覆盖盲点（dev-plan 写本文档时识别）

| 未覆盖 ID | 现状 | 应补偿方式 |
|---|---|---|
| 无 | — | 本条目行为全部由脚本退出码 + grep 校验锚定，无需单测 |

### 5.4 测试文件位置（spec-scan --gate 硬校验）

无新建测试文件——本条目为流程记账清理，门禁 = 既有覆盖率来源测试保持全绿 + 脚本退出码。列出两文件的覆盖率来源回归锚（既有文件，dev-exe 须保持其全绿，保证 S4 实测数据可复现）：

| 测试文件 | 覆盖 ID | 说明 |
|---|---|---|
| test/features/timer/timer_test.dart | REF-16-S4（timer_service 覆盖率来源之一） | 既有文件，保持全绿 |
| test/features/player/bug_08_repro_test.dart | REF-16-S4（playback_orchestrator 覆盖率来源之一） | 既有文件，保持全绿 |

（注：两文件仅为覆盖率来源回归锚，本条目不改动任何测试文件与 lib/ 代码；真正的门禁验证 = `check-exe` EXIT=0 + grep 残留校验。）

---

## §6 算法样例

无纯函数算法，跳过。

---

## §7 跨模块影响

| 其它位置 | 影响点 | 影响条件 | 需要补的回归断言 |
|---|---|---|---|
| coverage-check.sh check-exe 门禁 | load_debt 解析到空登记簿 → COV_DEBT 空 → 两文件 floor 从 79.0/87.5 回落到 90.0 硬阈 | 登记删除生效 | S6：check-exe EXIT=0 且两文件 [ OK ]（现覆盖 97.30/98.39 > 90） |
| baseline-coverage.json / check-check | 无耦合，不刷新、不变化 | — | S4 否定断言：不动 baseline |
| 未来覆盖回落到 88%~90% 区间 | 两文件按 90 硬阈报 [FAIL]（不再被 79.0/87.5 旧底线豁免） | 登记删除生效 | 这正是 cr D2 修复动机——回归断言为 check-exe 对两文件底线 = 90.0（S6 输出无"债务底线"后缀） |
| dev-status / cov-gate 流水线 | 无（cov-gate 调 check-exe，行为如上） | — | cov-gate EXIT=0 |

---

## §8 平台特性与手动 QA

设计前已逐条核对 `docs/dev/platform-pitfalls.md`：本条目不触及 P1~P17 任何条目（流程记账文件清理，不涉任何平台特性）。

**真机风险列**：

| 风险 | 近似测试方案 | 测不了 → 进 mqa-backlog |
|---|---|---|
| 无（改动全部在脚本退出码与文件 grep 可验证范围内） | S6 check-exe 退出码 + grep 残留校验 | 无 |

本功能不涉及平台原生特性，全部可在 `flutter test` 与门禁脚本中验证 → `manual_qa_required = false`。

---

## §9 dev-status.json 条目对照

```json
"REF-16": {
  "spec_file": "docs/features/REF-16.md",
  "spec_anchored_files": [
    "docs/dev/coverage-debt.txt",
    "docs/dev/scripts/coverage-check.sh",
    "docs/dev/baseline-coverage.json"
  ],
  "scenarios": ["REF-16-S4", "REF-16-S5", "REF-16-S6"],
  "invariants": ["REF-16-INV1"],
  "algorithms": [],
  "manual_qa_required": false,
  "user_acceptance_text": "见 §1.2"
}
```

注：S1~S3 为现状逆抽锚定（实现前行为快照），不入 scenarios 清单。
