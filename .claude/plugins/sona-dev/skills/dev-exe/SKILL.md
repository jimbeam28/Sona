---
name: dev-exe
description: |
  按 docs/features/{ID}.md 实施：测试先行 → 实现 → 脚本门禁。为弱模型设计——判断权在 spec，门禁权在脚本退出码。
  触发：用户提到"开始开发""实现""执行计划""dev-exe"。
  模式：单 ID 模式（`dev-exe {ID}`）；批量模式（`dev-exe 批量` / `dev-exe all`）——从 dev-status.json 按顺序读取 pending 项逐个执行。
  不触发：用户提到"分析/规划/制定计划"→ dev-plan。给出的 ID 无 spec 或无 status 条目 → 提示先 dev-plan。
---

# dev-exe — 实施 docs/features/{ID}.md

> 格式见 `../../reference/SCHEMA.md`；脚本在 `../../scripts/`。
>
> **三条铁律**：
> 1. **测试与实现分离**：测试 Agent 只读 spec §1.2/§3/§4/§6 + test/helpers 清单，**禁读 lib/**——测试贴合规约而非贴合实现。
> 2. **实现不改测试断言**：测试不过 → 修实现；spec 歧义 → 回 dev-plan 改 §3。严禁改断言"通过"。
> 3. **门禁以脚本退出码为准**，不接受自报结果。

## 输入与前置

**单 ID 模式**：`dev-exe {ID}`。

**批量模式**：`dev-exe 批量` / `dev-exe all`。读取 `docs/dev/dev-status.json`，按顺序处理每项：

```bash
# 获取 pending 列表（dependencies 全 done、impl_status 为 null/new/failed）
bash ../../scripts/dev-status.sh list-pending
```

对每项执行完整流程（§1-§6），任一项 `impl_status=failed` 或 `impl_status=blocked` 时**跳过该项继续下一项**，不中断批量。批量完成后汇总：成功 ID 列表、失败 ID 列表、跳过原因。

**前置检查**（两种模式通用）：`bash ../../scripts/dev-status.sh show <ID>` 确认：spec_file 存在、dependencies 全 done、impl_status 非 blocked。

**返工检测**：`check_round > 0` → **必读** `docs/dev/check_log.md` 最末条作为本轮修复靶点，逐条修复（靶点的"修复指令"已精确到函数，照单执行）。

## 流程

### 1. 测试先行（起 Agent A —— 建议中档模型）

Agent 输入：spec 全文 + `test/helpers/` 现有 fakes 清单。约束：

- 每个 `{ID}-S{n}` / `{ID}-INV{n}` ≥1 条 test，命名 `test('{ID}-S{n}: ...')`
- 每条否定断言 → 对应 `expect(..., unchanged)` / `verifyNever` 类断言
- 每条 ALG → 黄金样例 + 边界 + 异常三档
- Bug 项：基于已 FAIL 的 `bug_{ID}_repro_test.dart` 补修复后预期 PASS 的测试
- **禁读 lib/**。此时不跑测试（无实现，FAIL 必然）。

### 2. 实现（起 Agent B —— 弱模型即可）

Agent 输入：spec 全文（§2 锚点定位修改处）+ Agent A 的测试清单与断言 + 锚点文件代码。架构约束：UI→Provider→Domain→Contract 分层；Domain 零 Flutter 依赖；跨 feature 经 `shared/di/providers.dart`；禁 `dynamic` 替身。约束：不许跳 §3 任一 Scenario、不许违反 §4 任一 INV；Bug 项必须使复现测试 PASS。产出：修改文件 → Scenario 对照表。

### 3. 脚本门禁（本会话执行，退出码为准）

```bash
bash ../../scripts/spec-scan.sh --gate <ID>          # 硬门禁（Bug 项与非 Bug 项都跑）：spec §5.4「测试文件位置」指定的每个测试文件必须已存在于磁盘，缺一即退出码 1
bash ../../scripts/repro-test.sh <§5.4 复现文件> pass # Bug 项：§5.4 门禁文件中凡复现测试（spec 标注"复现测试/修复前 FAIL"，通常 bug_*_repro_test.dart）必须逐一跑 pass——一个文件一次调用，不得笼统代过
bash ../../scripts/cov-gate.sh                       # format + analyze(0 warning) + 全量 test + critical 覆盖率 ≥90%；非 Bug 项的 §5.4 门禁文件同样必须被全量 test 覆盖
bash ../../scripts/spec-scan.sh <ID>                 # 覆盖矩阵：每条 S/INV/ALG 在 test/ 有命中
bash ../../scripts/cross-imports.sh all              # 架构门禁：基线外零新违规
```

**修复循环上限 2 轮**。仍不过 → `impl_status=failed`、`retry_count+1`、`last_error` 记账，向用户报告并**建议升级强模型接手**（弱模型第 3 轮起几乎不收敛，继续烧 token 无意义）。
失败归因：旧测试 FAIL = 跨模块影响漏识 → 回 dev-plan §7；spec 歧义 → 回 dev-plan §3；架构违规 → 改代码。

### 4. MQA 攒单（不阻塞）

`manual_qa_required=true` → 把真机验证项按 SCHEMA §3.3 格式追加进 `docs/dev/mqa-backlog.md`，impl_status 照常推进 done。用户下次装真机时批量跑清单。

### 5. 标 done

**完成判定（验收位）**：标 done 前按 spec §3 行为规约（含每条修改指令）逐条核对落地——多 Scenario 的 spec 不许只挑容易的做；"编译过/测试绿"不等于完成，缺条回 §2 实现。

```bash
bash ../../scripts/dev-status.sh set <ID> impl_status '"done"'
bash ../../scripts/dev-status.sh set <ID> test_status '"passed"'
# test_files 一律用 --gate 输出回填（脚本解析），禁止手拼
bash ../../scripts/dev-status.sh set <ID> test_files "$(bash ../../scripts/spec-scan.sh --gate <ID> | jq -R . | jq -s -c .)"
```

**不动 check_\* 字段**（dev-check 还没跑）。

提交并推送：

```bash
git add lib/ test/ docs/
git commit -m "dev-exe(<ID>): implement + tests passed"
git push
```

报告：门禁结果 + critical 覆盖率摘要 + 一句"下一步：手动启动 dev-check {ID}"。**不自动链 dev-check**——审查独立性来自与开发上下文隔离。

### 6. 真机 bug 回写

本项若是真机来源的 bug 修复 → 按 `docs/dev/platform-pitfalls.md` 末尾格式回写一条（让 bug 只发生一次）。

## 失败上报

任一硬门禁 2 轮不过：报失败门禁项 + 原因（具体 test 名/现象）+ 已试轮次 + 建议（升级强模型 / 回 dev-plan / 人工介入）。retry_count ≥ 3 → `impl_status=blocked`。
