---
name: cr
description: |
  代码走查与复核（双模式，二选一，默认走查）。
  走查模式：扫描用户指定范围（目录 / 功能模块 / git 记录，未指定时默认 lib/ + test/），三层检查——机械层（脚本输出）/ 模式层（checklist）/ 功能层（P 库核对 + spec 符合性 + 测试锚定 + 状态机穷举四种锚定法做语义缺陷分析），输出类型化问题清单到 docs/cr/cr-{YYYYMMDD-HHMM}.md（BUG / FRAGILE / DESIGN / TEST-GAP × 严重度 × 复现路径）。
  复核模式：遍历 docs/cr/ 下所有走查报告逐条复核；仍存在的问题按类型分流——BUG/FRAGILE 调 dev-plan Bug 流程、DESIGN 调需求流程或用户裁决、TEST-GAP 直接补测或登记——然后删除该 cr 文档；如 docs/cr/ 为空则提示后退出。
  触发场景：用户提到"走查"、"代码走查"、"code review"、"review 代码"、"/cr"、"复核"、"复核走查"——默认走查，用户明说"复核"切复核模式。
  与 dev-check 的区别：dev-check 是 dev-exe 流程内的独立 spec 评审（贴合度 / 忠实度 / 覆盖率漂移）；/cr 是与 spec 流程无关的通用代码 review，用于日常任意代码片段走查。
  不触发：用户提到"检查"、"审查"、"dev-check"、"验证 spec"时归 dev-check；"实现"、"开发"归 dev-exe。
---

# 代码走查与复核 (cr)

> **本 skill 属 plugin `sona-dev`，路径 `.claude/plugins/sona-dev/skills/cr/`。**
> **脚本调用铁律**：凡下表所列动作，**必须**经脚本间接执行，禁止裸跑等价 bash。
> plugin 脚本相对本 skill base：`../../scripts/`；coverage-check.sh 在 `docs/dev/scripts/`。
>
> | 动作 | 脚本 |
> |---|---|
> | Domain 零 Flutter / Feature 隔离 / 敏感日志 / 层间反向依赖扫描 | `bash ../../scripts/cross-imports.sh {domain-flutter\|feature-isolation\|secret-logs\|all}` |
> | 反查改动文件的调用方（git 范围扩充） | `bash ../../scripts/cross-imports.sh impact <files...>` |
> | flutter analyze / dart format | `bash ../../scripts/cov-gate.sh --skip-test` |
> | 覆盖率基线 / 欠测 critical 文件 | `bash docs/dev/scripts/coverage-check.sh check-check` |
>
> git 历史查询（`git log --since/--grep/-N`）无脚本封装，直跑即可。
> 语义判断（模式层 / 功能层 / 写报告）属非确定性，走 read/edit 工具。

通用代码 review 工具，独立于 dev-plan / dev-exe / dev-check 流程。两种模式互斥，默认走查。
**维度清单、锚定法细则、P 库核对映射表见 `../../reference/cr-dimensions.md`；报告格式见 `../../reference/SCHEMA.md` §3.7。**

## 模式判定

读用户原话：

- 含"**复核**" / "**复核走查**" / "verify cr reports" → **复核模式**
- 其余（含"走查"、"code review"、"review 代码"、"/cr" 等）→ **走查模式**（默认）

---

## 走查模式

### 第 1 步：解析范围

四类范围互斥（同一次走查只取其一；用户给出多个时优先级 git > 功能 > 目录；默认兜底）：

| 类型 | 用户表达示例 | 解析为 |
|---|---|---|
| **git 记录** | "走查上周的提交" / "含 'WebDAV' 的提交" / "最近 3 个 commit" | `git log --since=... / --grep=... / -<N> --name-only --pretty=format:"%h %s"` 取改动文件 |
| **功能模块** | "走查 player 模块" | `lib/features/{name}/` + `test/features/{name}/` |
| **目录** | "看 lib/core/database/" | 用户指定路径（同时覆盖 lib 与 test 内同路径） |
| **默认** | 未指定 | `lib/` + `test/` 全量 |

**git 范围扩充（强制）**：走查对象 = git 触及文件 + `bash ../../scripts/cross-imports.sh impact <触及文件...>` 反查出的调用方——功能缺陷常发生在改动与未改动的交界面。每个文件整文件走查，不限于 diff 增量行。

### 第 2 步：加载硬约束与踩坑库

走查前**必读**：

1. `CLAUDE.md` 的"架构分层"与"数据库"两节 → 5 条硬约束（cr-dimensions.md §0）。
2. `docs/dev/platform-pitfalls.md` 全文 → 功能层 P 库核对依据（真机 bug 换来的失败模式，只增不删）。

### 第 3 步：三层走查

**Layer 1 机械层**（只贴脚本输出，不重复判断）：

```bash
bash ../../scripts/cross-imports.sh all        # 基线外架构违规
bash ../../scripts/cov-gate.sh --skip-test     # analyze 0 warning + format
```

非零退出 → 按 cr-dimensions.md §1 的映射计问题。`arch-baseline.txt` 已登记的存量债不计新账。

**Layer 2 模式层**（checklist 快过）：正确性健壮性 / 并发时序 / 可测性 / 性能四套清单（cr-dimensions.md §2），每条问题打严重度 + `file:line` 证据。

**Layer 3 功能层**（主菜，约六成精力）：对范围内每个模块按锚定可靠度依次用四种锚定法（cr-dimensions.md §3）：

1. **踩坑核对**：P1–P16 中与本次范围触及场景相关的条款逐条核对（同 dev-plan 的核对纪律）。
2. **spec 符合性**：已有 `docs/features/{ID}.md` 的模块 → 借 dev-check 对抗法"给每条 INV 找一条可违反的代码路径"，Scenario 逐条核对实现。
3. **测试锚定**：无 spec 的模块 → 逐个 domain 公开函数问"现有测试能否区分正确实现与一个貌似合理的错误实现"；欠断言分支 × coverage-check.sh 欠测行 = 缺陷候选区。
4. **状态机穷举 + 内部一致性**：枚举 (状态 × 事件) 矩阵查漏格；查语义不明 / 双重职责的函数（缺陷前兆）。

**哲学边界**：功能缺陷的锚定源是 P 库 / spec / 测试 / 内部一致性 / 用户域常识。CLAUDE.md 规定"代码为准，文档未覆盖是文档待补，不是代码违规"——**严禁**拿不存在的文档挑代码的刺。

### 第 4 步：对抗自检（防假阳性）

写报告前对每条 BUG / FRAGILE 强制自问：**现有测试为什么没抓住它？** 合法答案仅三种：测试空壳 / 该分支零覆盖 / 测试假设本身就错。一种都答不上 → 降级 DESIGN 或删除。执行细则见 cr-dimensions.md §4。功能断言的假阳性会污染下游 dev-plan，比漏报更伤流程。

### 第 5 步：写走查报告

格式见 `../../reference/SCHEMA.md` §3.7，输出 `docs/cr/cr-{YYYYMMDD-HHMM}.md`（时间戳精确到分钟防撞名）。每条问题 = **类型 × 严重度 × 证据**：

| 类型 | 含义 | 硬性要求 |
|---|---|---|
| **BUG** | 有确定复现路径 | 复现路径（操作/输入序列 → 期望 → 实际）+ 自检答案 + `file:line` |
| **FRAGILE** | 特定条件触发 | 条件化复现路径 + 自检答案 + `file:line` |
| **DESIGN** | 设计取舍待用户裁决 | 现象 + 取舍分析（写不出复现路径故不列 BUG） |
| **TEST-GAP** | 缺行为锚定 | 欠测行为描述 + 建议锚定方式 |

写完在终端报告：报告路径 + BUG/FRAGILE 数量 + 一句话下一步（"/cr 复核 分流进 dev 流程 / 手动修小问题 / 按 file:line 查证"）。

**铁律**：
1. **不修代码**：本 skill 只出清单，修复归复核分流或用户手动。
2. **不脑补**：写不出复现路径不得列 BUG；每条问题必带 `file:line` + 实际代码片段，不允许只说"可能有"。
3. **范围列全**：报告末尾"已检查文件清单"必须真实覆盖第 1 步解析的全部文件（含 impact 调用方），便于复核追溯。

---

## 复核模式

### 第 1 步：列出待复核报告

```bash
ls docs/cr/cr-*.md 2>/dev/null
```

无文件 → 输出"`docs/cr/` 为空，无可复核的走查报告"并退出。有 → 按文件名时间戳升序处理。

### 第 2 步：逐条复核

对每条问题打开 `证据` 处文件行，**重新判定**是否仍存在：

- **已修复**（代码已改 / 文件已删 / 行不存在）→ 标"已修复"。
- **仍存在** → 进第 3 步。

旧格式报告（重构前产出，无类型字段）按所在节推断类型：BUG 节 → BUG、FRAGILE 节 → FRAGILE、测试缺口节 → TEST-GAP、其余架构/风格节 → 按严重度直接归入修复清单。

### 第 3 步：按类型分流（不是一律派 Bug 流程）

| 类型 | 去向 |
|---|---|
| **BUG / FRAGILE** | 加载 dev-plan **Bug 流程**：证据 = 本报告 `file:line` + 复现路径。dev-plan 先写**失败复现测试**（`test/features/{feature}/bug_{ID}_repro_test.dart`，修复前必须 FAIL，硬门禁）→ 逆抽输出 `docs/features/BUG-{N}.md` + `dev-status.json` 条目（参照 BUG-01/02/03 格式） |
| **DESIGN** | dev-plan **需求流程**（无复现测试，按行为裁决立新需求 Scenario），或向用户呈现取舍直接裁决：修（转需求流程）/ 关（记录裁决理由，不建条目） |
| **TEST-GAP** | 不建 spec：直接补锚定测试（可作 dev-exe 任务），或登记 `docs/dev/coverage-debt.txt` |

dev-plan 完成后向用户呈现 §1.2 用户视角表 → 用户 ack 后**不自动继**，是否启动 dev-exe 由用户手动决定。

### 第 4 步：删除已复核的 cr 文档

每个报告的所有问题处理完（修复 / 分流 / 裁决关闭）后，**删除**该 `docs/cr/cr-{ts}.md`。cr 报告是一次性快照：问题要么已修复、要么已进 dev 流程，文档本身不留存。

### 第 5 步：终端汇报

```
═══════════════════════════════════
  cr 复核完成
═══════════════════════════════════
  复核报告数：N
  问题总数：M
    已修复：X
    仍存在 → 已分流：
      - BUG-{K}（来源 cr-{ts}.md B1，dev-plan Bug 流程）
      - {ID} 新需求（来源 cr-{ts}.md D1，dev-plan 需求流程）
      - TEST-GAP × n（已补测 / 已登记 coverage-debt）
    裁决关闭：Y
  已清理 cr 文档：cr-{ts1}.md / cr-{ts2}.md
  下一步：用户可手动启动 dev-exe {BUG-ID} 执行修复
═══════════════════════════════════
```

**复核模式铁律**：
1. **不修代码**：复核只判定"是否仍存在"+ 分流，修复走 dev-plan / dev-exe 链。
2. **不跳过 dev-plan**：仍存在的 BUG/FRAGILE 必须经 dev-plan 写 spec + 复现测试，不允许直接调 dev-exe。
3. **cr 文档必删**：处理完即删，不留堆积。

---

## 与其它 skill 的协作

| 场景 | 链路 |
|---|---|
| `/cr` 走查发现问题 → 用户想修 | 用户手动 `/cr 复核` → 按类型分流（BUG/FRAGILE→dev-plan Bug 流程 / DESIGN→需求流程或裁决 / TEST-GAP→补测）→ 用户 ack spec → 手动 dev-exe → 手动 dev-check |
| 一次性小问题直接修 | `/cr` 仅出清单，用户自行编辑代码，下次复核标"已修复" |
| dev-exe 修出新真机 bug | 必须回写 `docs/dev/platform-pitfalls.md`（dev-exe 铁律）→ 下次 cr 功能层踩坑核对自动纳入新条款，闭环 |
| 复核发现 docs/cr 空 | 提示后退出，不擅自调 dev-plan |

`dev-plan` 接到 cr 派来的 BUG/FRAGILE 时遵守其铁律：先写失败复现测试且修复前必须 FAIL，才允许分析根因。cr 报告的 `file:line` + 复现路径即 Bug 输入证据。

---

## 完成后汇报

走查模式：

```
═══════════════════════════════════
  cr 走查完成
═══════════════════════════════════
  走查范围：<范围描述>
  覆盖文件：N（含 impact 调用方 K 个）
  报告路径：docs/cr/cr-{ts}.md
  问题分布：BUG X / FRAGILE Y / DESIGN Z / TEST-GAP W
  下一步：
    - 想修：/cr 复核（按类型分流进 dev 流程），或手动编辑代码
    - 查证据：报告内 file:line + 复现路径
═══════════════════════════════════
```

复核模式见第 5 步格式。
