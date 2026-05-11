---
name: analysis
description: 分析代码生成修复文档链。对用户指定的模块或目录进行逐功能分析，生成 analysis.md → fix.md → fix-status.json。当用户说"分析代码"、"分析模块"、"代码分析"、"analysis"、或任何涉及对项目代码进行分析并生成修复计划的请求时使用此 skill。
---

# 代码分析与修复计划生成 (analysis)

对用户指定的模块或目录进行逐功能分析，生成三层修复文档链：分析报告 → 修复计划 → 修复状态跟踪。

## 输入

用户需要指定分析**范围**，如：
- 模块名（`Connection`、`Browser`、`Player`、`Timer`、`Progress`、`Settings`）
- 目录路径（`lib/features/player/`、`lib/core/services/`）
- 不指定 = 分析全部模块

---

## 流程

### 步骤 0：清理旧文档

检查 `docs/dev/analysis.md`、`docs/dev/fix.md`、`docs/dev/fix-status.json` 是否存在且不为空：
- 如存在 → 删除后重新生成
- 如不存在或为空 → 直接生成

---

### 步骤 1：生成分析报告 (analysis.md)

启动新的 Agent（general-purpose），对用户指定的范围进行逐功能、逐文件分析。

Agent prompt 必须包含：

**分析范围**：用户指定的模块/目录，或全部模块（`lib/features/` + `lib/core/`）。

**分析依据**：
- 读取 `docs/design/` 下的设计文档（`module-connection.md`、`module-browser.md`、`module-player.md`、`module-timer.md`、`module-progress.md`、`module-settings.md`），提取每个功能的设计要求
- 读取 `lib/` 下的实现代码，逐文件对照设计文档
- 读取 `docs/design/architecture.md` 了解架构约束
- 读取 `CLAUDE.md` 了解模块说明和架构分层

**分析要求**：
1. 按模块分组，模块内按功能编号逐一分析
2. 每个功能标注符合度：✅ 完全符合 / ⚠️ 存在偏差 / 🔴 存在严重缺陷
3. 对每个发现的问题：
   - 描述具体偏差（设计要求 vs 实际实现）
   - 引用设计文档章节号
   - 引用源码文件路径和行号
   - 说明影响范围
   - 给出**可操作的修复建议**（含代码示例）
4. 汇总部分按优先级分级：
   - P0：核心功能无法使用
   - P1：功能存在但行为与设计不符
   - P2：轻微偏差，不影响主流程

**输出格式**：写入 `docs/dev/analysis.md`，格式如下：

```markdown
# 实现合规性分析报告

> 分析日期：YYYY-MM-DD
> 覆盖模块：ModuleA · ModuleB · ...
> 分析依据：docs/design/module-*.md 设计文档 + lib/ 实现代码

---

## 总体结论

| 模块 | 实现完整度 | 关键问题数 |
|------|-----------|-----------|
| ... | ... | ... |

---

## 一、ModuleA 模块

### FUNC-01 功能名 ✅/⚠️/🔴 状态

... 具体分析 ...

---

## N、问题汇总与优先级

### P0 严重缺陷

| # | 问题 | 影响功能 | 位置 |
|---|------|---------|------|
| 1 | ... | ... | ... |

### P1 功能偏差
...

### P2 轻微偏差
...
```

---

### 步骤 2：生成修复计划 (fix.md)

启动新的 Agent（general-purpose），依据 `docs/dev/analysis.md` 生成修复计划。

Agent prompt 必须包含：

**输入**：`docs/dev/analysis.md`（步骤 1 的产出）

**要求**：
1. 按优先级分批（Batch A: P0, Batch B: P1, Batch C: P2）
2. 每个修复包含：
   - 修复编号（A-1, A-2, ..., B-1, ..., C-1, ...）
   - 描述性名称
   - 关联的问题（从 analysis.md 的问题编号映射）
   - 当前状态描述
   - **详细的修复方案**（含代码示例、触发条件、逻辑描述）
   - 涉及文件列表
3. 制定实施顺序（`implementation_order`），考虑依赖关系：
   - 独立修复优先
   - 有依赖关系的修复按依赖顺序排列
   - 标注每个修复的预估工时
4. 总览表：批次、优先级、任务数、说明

**输出格式**：写入 `docs/dev/fix.md`，格式如下：

```markdown
# 修复开发计划

> 依据：docs/analysis.md 分析报告
> 制定日期：YYYY-MM-DD
> 优先级分级：P0 核心功能缺失 → P1 功能偏差 → P2 轻微偏差

---

## 总览

| 批次 | 优先级 | 任务数 | 说明 |
|------|--------|--------|------|
| ... | ... | ... | ... |

---

## Batch A — P0 严重缺陷

### A-1  修复名称

**关联问题**：问题编号列表
**当前状态**：...

**需要完成的工作：**
1. ...
...

**涉及文件**：
- ...

---

## 实施顺序建议

...
```

---

### 步骤 3：生成修复状态文件 (fix-status.json)

启动新的 Agent（general-purpose），依据 `docs/dev/fix.md` 生成修复状态跟踪 JSON。

Agent prompt 必须包含：

**输入**：`docs/dev/fix.md`（步骤 2 的产出）

**要求**：
1. 为每个批次创建 `batches.batch-X` 条目，包含：
   - `label`：批次中文标签
   - `priority`：P0/P1/P2
   - `description`：批次说明
   - `fixes`：该批次的所有修复
2. 每个修复包含：
   - `name`：修复名称（从 fix.md 提取）
   - `issues`：关联问题编号数组
   - `design_doc`：引用 fix.md 的章节（格式 `docs/fix.md §Batch X — 编号`）
   - `current_status`：当前状态描述
   - `work_items`：工作项数组（从 fix.md 的"需要完成的工作"提取，每个步骤一个字符串）
   - `files_involved`：涉及文件数组
   - `impl_status`：初始值 `"pending"`
   - `dependencies`：依赖的其他修复编号数组（从 fix.md 的实施顺序推断）
3. 提取 `implementation_order`：从 fix.md 的实施顺序转换为 JSON 数组
4. 添加 `status_values` 和 `metadata` 字段

**输出格式**：写入 `docs/dev/fix-status.json`，格式如下：

```json
{
  "batches": {
    "batch-a": {
      "label": "Batch A — P0 严重缺陷",
      "priority": "P0",
      "description": "...",
      "fixes": {
        "A-1": {
          "name": "...",
          "issues": ["..."],
          "design_doc": "docs/fix.md §Batch A — A-1",
          "current_status": "...",
          "work_items": ["...", "..."],
          "files_involved": ["...", "..."],
          "impl_status": "pending",
          "dependencies": []
        }
      }
    }
  },
  "implementation_order": [
    {"step": 1, "tasks": ["A-5", "A-6"], "note": "..."}
  ],
  "status_values": {
    "impl_status": ["pending", "in_progress", "done"]
  },
  "metadata": {
    "source": "docs/fix.md",
    "date": "YYYY-MM-DD",
    "total_fixes": N,
    "by_priority": {"P0": N, "P1": N, "P2": N}
  }
}
```

---

## 注意事项

- 步骤 1、2、3 必须**顺序执行**，后一步依赖前一步的产出
- 步骤 2 的 Agent 在开始前，必须先 Read `docs/dev/analysis.md`（步骤 1 产出）
- 步骤 3 的 Agent 在开始前，必须先 Read `docs/dev/fix.md`（步骤 2 产出）
- 每个 Agent 都必须严格以对应输入文档为依据，不得自行发挥
- 生成的三个文档（analysis.md、fix.md、fix-status.json）必须内容一致、互相可追溯
