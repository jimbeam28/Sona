---
name: dev-check
description: |
  独立评审 dev-exe 产出的代码与文档。7 项检查（spec vs 原需求贴合度 / 实现对 spec 忠实度 / 回归测试充分性 / 跨模块破坏 / 跨模块漏识并跑全量 / 基线覆盖率漂移 / 否定断言守护）。
  不亲手修复——只出问题清单，打回 dev-exe 重做。最多 3 轮返工，仍 fail 标 blocked。
  触发场景：用户提到"检查"、"审查"、"dev-check"、"验证"、"review"，或 dev-exe 完成后用户手动启动检查。
  不触发：用户提到"实现"、"开发"、"dev-exe"、"dev-plan"时——分别为 dev-exe / dev-plan 处理。
  与 dev-exe 内部 Agent C 的区别：Agent C 在 dev-exe 流程内部，被 spec 框住视角，只验证 spec 被覆盖；dev-check 是独立视角，质疑 spec 本身和实现对原需求的贴合度，并守护跨 PR 累积漂移。
---

# 独立评审 (dev-check)

dev-exe 跑完后，由**未参与过开发的**视角独立评审。不是简单重叠 dev-exe 第 5 步 Agent C 的 spec 覆盖验证——那一步是流程内部、被 spec 框住视角、只检查"每条 spec 是否被测"。dev-check 的工作是**质疑 spec 本身对不对、实现对原需求贴不贴**。

## 三条铁律

1. **不亲手修复**：dev-check 只出问题清单，**严禁**直接编辑 lib/ 或 test/ 代码。修复责任归 dev-exe。若 dev-check 改代码，就没人审 dev-check 的改动。
2. **重读原需求**：dev-check 第一动作是重读用户最初需求描述 + `docs/features/{ID}.md §1.2` 用户视角表——**不是从实现推回需求**，而是从需求推回实现。
3. **3 轮上限**：dev-check 打回 dev-exe 重做最多 3 轮。仍 fail → 标 `dev-status.json` 中该项 `impl_status = "blocked"`、`check_status = "blocked_after_3_rounds"`，等用户人工介入。

---

## 输入

可选的功能**条目编号**（如 `BRW-09`）：
- **有编号**：只评审该条目
- **无编号**：评审 `dev-status.json` 中所有 `impl_status == "done"` 且 `check_status` 未设为 `"passed"` 的条目（即 dev-exe 跑完但还没被独立评审的）

## 前置：读取上下文

必读：
- `docs/dev/dev-status.json` — 进度跟踪（找 done 且未 check 通的项）
- `docs/features/{ID}.md` — 详细设计文档
- `docs/features/_TEMPLATE.md` — 字段定义

读实现时牵挂的下游文件（仅 grep 不读全）：
- `git log -3 --name-only` 看 dev-exe 最新提交改了什么文件
- `git show HEAD` 看具体改动 diff
- 用户最初需求描述：搜 `docs/dev/dev_log.md` 最末条目或会话历史

---

## 单条评审工作流

### 第 1 步：解析条目状态

1. 从 `dev-status.json` 的 `items` 中找到目标条目
2. 确认 `impl_status == "done"` 且 `test_status == "passed"`——dev-check 只评审 dev-exe 自认完成的条目；未完成直接打回 dev-exe
3. 读 `check_status`（如果存在）：
   - 不存在或 `"pending"` → 首轮评审
   - `"round_1"` / `"round_2"` → 已进行过若干轮打回
   - `"blocked_after_3_rounds"` → **停止**，提示用户已超 3 轮上限，需人工介入
4. 读 `last_check_round_results`（如果存在）了解上一轮被指出的问题

### 第 2 步：7 项独立检查

每项产出 verdict（PASS / FAIL）+ 证据（file:line）+ 问题描述（若 FAIL）。

#### 检查 1：spec vs 原需求贴合度

> dev-plan 写 spec 时可能漏描述了你最初需求里的隐含期待。dev-check 重读原需求文字 + §1.2 表对照。

1. 找到用户最初需求描述（会话历史或 `docs/dev/dev_log.md` 末尾）
2. 重读 `docs/features/{ID}.md §1.2` 用户视角 Scenario 表
3. 逐条对比：
   - 用户需求的每一句话是否都有对应 Scenario？
   - 是否漏掉了用户没明说但显然隐含的期待（"下一曲播放"会不会有人理解为"立即跳下一曲"而非"加入下一曲位置"？）
   - §1.2 每条 Scenario 是否在用户需求里有直接出处？有没有 dev-plan 自己脑补的细节？
4. FAIL 条件：
   - 用户需求中存在某条期待对应不上任何 §1.2 Scenario
   - §1.2 某条 Scenario 没有用户需求出处（dev-plan 自加的脑补）

#### 检查 2：实现对 spec 的忠实度

> dev-exe Agent B 实现时可能偷偷偏离 §3 spec，agent C 只查覆盖率不查语义。

1. 读 §3 每条 Scenario 的 Code evidence + 实际代码 diff
2. 对每条 Scenario：
   - Scenario 描述的状态变化 + 副作用是否在代码中**真实被实现**？
   - 不变量 INV 是否在代码中**真正被守护**？不只是"测试通过"——是代码本身的逻辑保证这条 INV 成立
3. FAIL 条件：
   - 某条 Scenario 在代码中无对应实现（spec 说了但代码漏做）
   - 某条 INV 实际上可被代码路径违反而 dev-exe 没发现
   - 代码做了 §3 spec 没说的事（dev-exe 自发挥）

#### 检查 3：回归测试充分性

> dev-exe 的回归门禁只查 `flutter test` 全 PASS——但不查测试本身是否浅薄。

1. 读 §5 测试规约列出的测试文件，逐文件 grep 关键 test 名
2. 对每条 Scenario / INV 的对应 test：
   - 是否真正断言了 Scenario 描述的状态变化（不是只 setup 不 assert）？
   - 边界 Scenario（S8 队尾、S2 禁用态等）是否有专门 test？
   - 算法样例（§6）是否有典型 + 边界 + 异常 三档？
3. 重点检查：是否存在"只构造对象不调方法"的空骨架测试？是否存在"assert(true)"或"expect(1, equals(1))"形式通过但未测实际行为？
4. FAIL 条件：
   - 某条 Scenario 的 test 实际未断言该 Scenario 的核心行为
   - 边界 / 异常样例缺失
   - 测试断言显式宽泛到不具约束力（如 `expect(result, isNotNull)`，但 Scenario 要求具体值）

#### 检查 4：跨模块已识别的不变量是否被破坏

> §7 列出了 cross_module_impacts。dev-exe 应该补 PLY-REG-1/2/3 等回归断言。dev-check 验证这些回归是否真实存在并断言了正确的事。

1. 读 `docs/features/{ID}.md §7` 跨模块影响表
2. 对每行"需要补的回归断言"：
   - 用 `grep` 在 `test/features/{cross_module}/` 找对应 test
   - 检查测试断言是否真正断言了该回归点（不是只 setup）
3. 跑 `flutter test test/features/{cross_module}/` 确认全 PASS
4. FAIL 条件：
   - §7 某行没有对应回归测试
   - 测试存在但断言不针对该跨模块影响点
   - 跨模块测试 FAIL

#### 检查 5：跨模块被漏识的破坏

> dev-plan §7 可能漏识——dev-check 用 grep + diff + **全量 widget/test 跑一遍** 验证是否真不动其它 feature 的文件。

1. `git show HEAD --name-only` 列出本次改动文件
2. 用 `grep -rln` 搜索：
   - 改动文件是否 import 了跨模块的 feature 文件？（如改了 lib/shared/models/play_queue.dart——哪些 feature import 了它？）
   - cross_module_impacts 字段之外的 feature 是否真的没被影响？
3. **强制跑全量测试套件（不只 grep）**：在本目录直接执行
   ```bash
   flutter test
   ```
   任一测试 FAIL 而 §7 cross_module_impacts 没声明该 feature → 这是被漏识的破坏
4. **golden test / widget test 特别检查**：跨 widget test 若有任何 "expected: a, got: b" 类断言失败且涉及跨 feature widget——属于漏识的跨模块破坏
5. 对每个 import 方：抽查其相关测试是否仍 PASS
6. FAIL 条件：
   - 改动文件被 §7 之外的 feature import，但 dev-plan 没列入 cross_module_impacts
   - 该 import 方的现有测试因本次改动 FAIL
   - 全量 `flutter test` 出现任一新 FAIL 不在 spec 声明范围内

#### 检查 6：基线漂移检测（覆盖率回退）

> 单条 PR pass 不能阻止跨 PR 累积漂移——上次 PASS 的 BRW-08 这次因为改 PLY 被破坏，但旧测试断言不严仍能 PASS。本项用基线覆盖率快照做对比：当前 lcov.info vs 上次 dev-check PASS 时存的 `docs/dev/baseline-coverage.json`，任一文件下降算 FAIL。

1. 读 `docs/dev/baseline-coverage.json`：
   ```json
   {
     "last_updated": "YYYY-MM-DD",
     "last_passed_feature": "{ID}",
     "baseline_overall": 76.4,
     "critical_files": {
       "lib/shared/models/play_queue.dart": 92.5,
       "lib/features/player/domain/playback_orchestrator.dart": 88.0,
       ...
     },
     "all_files": { ... }
   }
   ```
2. 读当前 dev-exe 完成时生成的 `coverage/lcov.info`
3. 解析 lcov.info 得到 per-file 覆盖率（同 dev-exe 第 7 步脚本）
4. **三项硬比较**：
   - 任一 `critical_files` 文件覆盖率 < baseline 中对应值，**且**降幅 > 容忍阈值 2% → FAIL
   - 总 `baseline_overall` 降幅 > 1% → FAIL
   - 任一基线中存在但当前 lcov.info 缺失的文件 → FAIL（说明文件被移除 / 重命名但未追踪）
5. **基线无文件时**（首次 dev-check）：把当前 lcov.info 全量写入 baseline-coverage.json 作为基线，本项视为 PASS（仅建立基线）。要求 dev-check 在 PASS 后第 4 步必须执行"刷新基线"。
6. **PASS 后刷新基线**：本次 dev-check 走全 PASS 时，把当前 lcov.info 覆盖率结果覆写 `docs/dev/baseline-coverage.json`（每次 PASS update 一次，让基线持续往上推）。
7. FAIL 条件：上述三项任一项不通过
   - 修复建议：要么 dev-exe 补回测试覆盖率；要么承认本次改动有意降低覆盖率（例如删测试时则需在 §3 / §7 显式说明）

#### 检查 7：否定断言未被破坏（防假阴面）

> dev-check 不仅查"应该有的有没有"，也查"应该没有的有没有"。dev-plan §3 每条新增 Scenario 应带否定断言（见 dev-plan §3 铁律 4），dev-check 验证这些否定断言在测试中实际被执行。

1. 读 `docs/features/{ID}.md §3`，找所有带 `否定断言:` 或 `And 不应` 标记的 Scenario
2. 对每条否定断言：
   - 在 `test/features/{feature}/` 找对应 test
   - 测试是否真包含对"不应发生"事件的断言？例 `expect(queue.length, unchanged)` 而非仅 setup
3. FAIL 条件：
   - Scenario 声明带否定断言但测试中无对应断言
   - 否定断言被 dev-exe Agent A 误解为正向断言（例把"queue 应不变"写成"queue 应 == N"指过严或过松）

### 第 3 步：汇总评审报告

输出 `docs/dev/check_log.md`（不存在则创建），追加条目：

```markdown
## [YYYY-MM-DD HH:MM] [条目ID] - 第 N 轮 dev-check

### 检查结果

| 检查项 | Verdict | 问题数 | 详情 |
|---|---|---|---|
| 1. spec vs 原需求贴合度 | PASS / FAIL | N | ... |
| 2. 实现对 spec 忠实度 | PASS / FAIL | N | ... |
| 3. 回归测试充分性 | PASS / FAIL | N | ... |
| 4. 跨模块已识别不变量未破坏 | PASS / FAIL | N | ... |
| 5. 跨模块被漏识的破坏（含跑全量）| PASS / FAIL | N | ... |
| 6. 基线覆盖率漂移 | PASS / FAIL | N | ... |
| 7. 否定断言未被破坏 | PASS / FAIL | N | ... |

### 总 verdict: PASS / FAIL

### FAIL 问题清单（若有）

1. **问题标题**（对应检查项 N，@BRW-09-S5）
   - 证据：file:line
   - 现象：...
   - 修复建议：...

2. ...
```

### 第 4 步：根据 verdict 决定下一步

**全 7 项 PASS**：
1. 更新 `dev-status.json`：
   ```json
   "check_status": "passed",
   "check_round": N,
   "last_checked_at": "YYYY-MM-DD"
   ```
2. **刷新基线覆盖率快照**（关键）：把当前 `coverage/lcov.info` 解析为 per-file 覆盖率，覆写 `docs/dev/baseline-coverage.json`：
   ```json
   {
     "last_updated": "YYYY-MM-DD",
     "last_passed_feature": "{ID}",
     "baseline_overall": <总覆盖率%>,
     "critical_files": { "<file>": <百分比>, ... },
     "all_files":      { "<file>": <百分比>, ... }
   }
   ```
   理由：每次 PASS = 当前主分支状态被设为下次 PR 比较的基线，覆盖率只能单调上行。
3. 报告"dev-check PASS，可继续下一项。基线覆盖率快照已刷新。"

**任一项 FAIL**：
1. 更新 `dev-status.json`：
   ```json
   "check_status": "round_N",
   "check_round": N,
   "last_check_round_results": "见 docs/dev/check_log.md @ 条目ID 第 N 轮",
   "last_check_failure_count": K
   ```
2. **将条目状态从 done 改回 pending**：
   ```json
   "impl_status": "pending",
   "test_status": "pending",
   "check_round": N
   ```
   理由：dev-check 打回后，dev-exe 必须按问题清单重做，重做后才能再升 done。
3. 报告"dev-check FAIL @ 检查项 N，已打回 dev-exe，请用户手动启动 dev-exe {ID} 重做"——按下回后人工接力启动 dev-exe。

**3 轮上限判定**：
- `check_round = 2` 的对应轮次仍 FAIL → 进入 round 3
- `check_round = 3` 仍 FAIL → 强制 BLOCKED：
  ```json
  "impl_status": "blocked",
  "check_status": "blocked_after_3_rounds",
  "last_error": "dev-check 3 轮仍未通过，需人工介入"
  ```
  输出完整 3 轮问题清单给用户，停止自动循环。

---

## 多轮返工机制

dev-check 出 FAIL → 用户手动启动 `dev-exe {ID}` → dev-exe 必须在执行前读取 `docs/dev/check_log.md` 最末条目作为问题清单 → 修复后跑完自身门禁标记 done → 用户手动启动 `dev-check {ID}` → 重复。

dev-exe skill 在每次执行前**必须**：
1. 检查 `dev-status.json` 中 `check_round` 字段
2. 若 `> 0` —— 必读 `docs/dev/check_log.md` 最末条作为本轮修复靶点
3. 不允许跳过这些靶点直接重写新代码

这条机制是 dev-check 能真正打回 dev-exe 的硬约束——否则 dev-exe 跑完不一定针对 dev-check 出的问题。

---

## dev-check 与 dev-exe Agent C 的关系

| 维度 | dev-exe Agent C | dev-check |
|---|---|---|
| 视角 | 在 dev-exe 流程内部 | 独立视角 |
| 工作 | 验证 spec 被覆盖 | 质疑 spec 本身 + 实现忠实 |
| 输入 | `docs/features/{ID}.md` | `docs/features/{ID}.md` + 用户最初需求 + git diff + 跨模块 grep |
| 输出 | 覆盖矩阵 + missing ID | 5 项 verdict + 问题清单 |
| 失败动作 | 补测试 | 打回 dev-exe |
| 不做的事 | 不质疑 spec | 不亲手改代码 |

二者**互补不替代**：Agent C 守"每条 spec 被测"；dev-check 守"spec 本身 + 实现忠实 + 跨模块未破坏"。

---

## 完成后汇报

PASS：
```
═══════════════════════════════════
  dev-check PASS
═══════════════════════════════════
  条目编号:     {ID}
  评审轮次:     第 N 轮
  检查项 1: spec 贴合度          PASS
  检查项 2: 实现忠实度          PASS
  检查项 3: 回归充分性          PASS
  检查项 4: 跨模块已识别未破坏  PASS
  检查项 5: 跨模块漏识（含全量）PASS
  检查项 6: 基线覆盖率漂移      PASS（/ 基线已建立）
  检查项 7: 否定断言守护        PASS
  已更新 dev-status.json:check_status=passed
  已刷新 docs/dev/baseline-coverage.json
═══════════════════════════════════
```

FAIL：
```
═══════════════════════════════════
  dev-check FAIL（第 N 轮）
═══════════════════════════════════
  条目编号:     {ID}
  评审轮次:     第 N 轮（上限 3）

  检查项 1: spec 贴合度          FAIL（K 个问题）
  检查项 2: 实现忠实度          PASS
  ...

  问题清单（详见 docs/dev/check_log.md）:
  1. [检查项1] §1.2 U5 表对应 Scenario S5，但实现未约束用户视角描述的"当前在播是队列尾"边界
     证据: lib/.../file_list_item.dart:42
     建议: 在 insertAfterCurrent 中加 files.length == currentIndex+1 的分支处理
  ...

  行动:
  - dev-status.json 已更新为 round_{N}，impl_status 改回 pending
  - 请用户手动启动: dev-exe {ID}
  - dev-exe 会自动读取本轮问题清单作为修复靶点
═══════════════════════════════════
```

BLOCKED：
```
═══════════════════════════════════
  dev-check BLOCKED（已超 3 轮上限）
═══════════════════════════════════
  条目编号:     {ID}
  完整问题历史: docs/dev/check_log.md
  本条目已标 blocked_after_3_rounds

  请人工介入：
  1. 阅读历史 3 轮问题清单
  2. 决定: (a) spec 本身错 → 回 dev-plan 重写 §3 ；(b) 实现方向错 → 亲自修代码 ；(c) 需求歧义 → 与用户重新拍板
═══════════════════════════════════
```