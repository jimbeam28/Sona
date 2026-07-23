---
name: dev-check
description: |
  独立评审 dev-exe 产出——定位为"强模型对弱模型产出的审计"：3 项判断检查（测试空壳/实现忠实/跨模块破坏）+ 机械项走脚本。不亲手修复，只出问题清单打回 dev-exe，上限 2 轮。
  触发：用户提到"检查""审查""dev-check"，或 dev-exe 完成后用户手动启动。
  不触发："实现/开发"→ dev-exe；"分析/规划"→ dev-plan。
  与 dev-exe 门禁的区别：门禁查"每条 spec 被测了没"（机械），dev-check 查"测试和实现对不对"（判断）。
---

# dev-check — 独立评审

> 格式见 `../../reference/SCHEMA.md`；脚本在 `../../scripts/`。
>
> **三条铁律**：
> 1. **不亲手修复**——只把问题清单写进 `docs/dev/check_log.md`。dev-check 改代码就没人审 dev-check 的改动。
> 2. **从需求推回实现**：第一动作是重读 spec §1.0 用户原话 + §1.2 用户视角表，不是从代码倒推需求。
> 3. **2 轮上限**：打回重做最多 2 轮仍 FAIL → `dev-status.sh block <ID>`，人工介入。
>
> **读范围纪律**：只读 spec + git diff + 改动涉及的测试文件。不扫全库——本 skill 便宜在看得少、判得准。

## 输入与前置

指定 ID；或 `bash ../../scripts/dev-status.sh pending` 列全部 impl=done 且 check≠passed 的条目。`check_status=blocked_after_rounds` → 停止并报人工。

## 三项判断检查（本 skill 存在理由——机械门禁抓不住的）

### 检查 1：测试空壳审计

读 §3/§4 每条对应的 test：

- 真断言了 Scenario 的核心状态变化吗？（只 setup 不 assert / `isNotNull` 占位 / `expect(1, equals(1))` = 空壳 → FAIL）
- 每条否定断言有真 `expect(..., unchanged)` / 等值原值 / `verifyNever` 吗？
- ALG 有黄金 + 边界 + 异常三档吗？边界 Scenario（队尾/禁用态/空队列）有专测吗？

### 检查 2：实现语义忠实（对抗式）

对 git diff 逐条审 §3/§4：

- **给每条 INV 找一条可违反的代码路径**——找到 = FAIL（测试全绿 ≠ INV 真被守护）
- Scenario 声明的状态变化 + 副作用在代码中真实发生了吗？
- 代码有没有做 §3 没说的事（自由发挥）→ FAIL
- §1.0 用户原话的每句期待，§1.2 都有对应 Scenario 且实现落地了吗？（漏 = dev-plan 脑补或遗漏 → FAIL，回 dev-plan）

### 检查 3：跨模块破坏

```bash
bash ../../scripts/cross-imports.sh impact <git diff 涉及的文件...>   # 引用方 vs §7 声明：被影响但未声明 = FAIL
bash ../../scripts/cross-imports.sh all                              # 基线外新违规 = FAIL
bash ../../scripts/cov-gate.sh --only test                           # 全量回归：spec 声明范围外的新 FAIL = FAIL
```

## 机械项（读脚本输出即可，不重判）

`bash ../../scripts/spec-scan.sh <ID>`（覆盖矩阵无缺项）、`bash ../../scripts/repro-test.sh <path> pass`（Bug 项）、`bash docs/dev/scripts/coverage-check.sh check-check`（基线漂移）。任一机械项红 → 计 FAIL 入清单。

## 结论

问题清单写 `docs/dev/check_log.md` 最末条（格式 SCHEMA §3.2）——**修复指令精确到函数与改法**，弱模型 dev-exe 要能照单执行，不留判断空间。

- **全 PASS** → `bash ../../scripts/dev-status.sh pass <ID>` + `bash docs/dev/scripts/coverage-check.sh refresh`（基线单调上行）
- **FAIL** → `bash ../../scripts/dev-status.sh bump-round <ID>`（impl 回 pending），报告"请手动启动 dev-exe {ID} 重做"

报告：3 项判断 verdict + 机械项结果 + 问题数 + 行动。BLOCKED → 输出两轮完整问题清单，请用户决定（spec 错 → 回 dev-plan / 实现方向错 → 人工修 / 需求歧义 → 重新拍板）。
