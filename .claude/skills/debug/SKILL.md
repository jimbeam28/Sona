---
name: debug
description: 根据用户描述的bug现象分析原因，输出修复方案到 docs/dev/fix.md 和 docs/dev/fix-status.json。当用户说"debug"、"调试"、"排查"、"分析bug"、"查原因"、或任何涉及根据bug描述定位根因并输出修复方案的请求时使用此 skill。
---

# Bug 分析与修复方案生成 (debug)

根据用户描述的 bug 现象，分析代码查找根因，生成修复方案文档链：修复计划 → 修复状态跟踪。该 skill 只分析和输出分析结果，不修改代码。

## 输入

用户需要描述 **bug 现象**，可以包含：
- Bug 的具体表现（什么情况下出现、预期行为 vs 实际行为）
- 复现步骤
- 涉及的功能模块或页面
- 相关的错误日志或截图（如有）
- 多个 bug 可以一并描述

---

## 流程

### 步骤 0：清理已完成的修复，合并新项

检查 `docs/dev/fix.md`、`docs/dev/fix-status.json` 是否存在且不为空：

**如不存在或为空**：直接生成新文件。

**如已存在**：读取 `docs/dev/fix-status.json`，按以下策略处理：

1. **删除已完成项**：遍历所有 batches → fixes，删除 `impl_status` 为 `"done"` 的 fix
2. **清理空批次**：如果某个 batch 下所有 fix 都被删除，则删除该 batch 节点
3. **保留进行中/未完成项**：`impl_status` 为 `"pending"`、`"in_progress"` 的 fix 全部保留
4. **同步 fix.md**：根据 fix-status.json 中保留的项，从 fix.md 中删除已完成修复对应的章节，保留未完成的章节
5. **合并新项**：将本次分析产出的新修复合并到 fix.md 和 fix-status.json 中。新修复编号接续已有编号（如已有 A-1、A-2，新修复从 A-3 开始）

完成清理后，将保留的 fix.md 和 fix-status.json 作为"已有内容"传递给步骤 1 和步骤 2。

---

### 步骤 1：分析 Bug 并生成修复计划 (fix.md)

根据用户描述的 bug 现象分析代码，查找根因并制定修复方案。

#### 1.1 启动并行分析

如果用户描述了**多个独立的 bug**，为每个 bug 启动一个 Agent（general-purpose）进行并行分析。每个 Agent 只负责一个 bug，分析结果写到一个临时文件。

每个 Agent 的 prompt 必须包含：
- 该 bug 的完整描述（现象、复现步骤、错误信息）
- 项目结构说明（CLAUDE.md）
- 相关设计文档路径

每个 Agent 的分析要求：
1. 阅读相关源码文件，根据 bug 现象追踪代码逻辑，定位根因
2. 阅读 `docs/design/` 下相关模块的设计文档，对照设计意图确认是否为实现偏差
3. 输出内容：
   - 描述 bug 现象（用户报告 + 分析确认）
   - 定位根因（引用源码文件路径和行号，说明逻辑缺陷）
   - 给出**可操作的修复方案**（含代码示例、触发条件、逻辑描述）
   - 标注优先级：P0（核心功能崩溃/不可用）/ P1（功能异常但可绕过）/ P2（轻微问题）
   - 涉及文件列表
4. 将分析结果写入临时文件 `docs/dev/.debug-bug-N.md`（N 为 bug 序号）

如果只有**单个 bug**，直接在当前上下文完成分析，不需要启用 Agent。

#### 1.2 汇总合并

所有并行 Agent 完成后（或单 bug 分析完成后），读取所有分析结果，合并写入 `docs/dev/fix.md`：

1. 按优先级分批（Batch A: P0, Batch B: P1, Batch C: P2）
2. 每个修复包含：
   - 修复编号（A-1, A-2, ..., B-1, ..., C-1, ...），接续已有编号
   - 描述性名称
   - bug 现象描述
   - 根因分析（含源码位置）
   - 详细的修复方案（含代码示例）
   - 涉及文件列表
3. 制定实施顺序（`implementation_order`），考虑依赖关系：
   - 独立修复优先
   - 有依赖关系的修复按依赖顺序排列
4. 总览表：批次、优先级、任务数、说明
5. 清理临时文件 `docs/dev/.debug-bug-*.md`

**输出格式**：写入 `docs/dev/fix.md`，格式如下：

```markdown
# 修复开发计划

> 分析日期：YYYY-MM-DD
> Bug 描述：[用户报告的 bug 摘要]
> 优先级分级：P0 核心功能崩溃 → P1 功能异常 → P2 轻微问题

---

## 总览

| 批次 | 优先级 | 任务数 | 说明 |
|------|--------|--------|------|
| ... | ... | ... | ... |

---

## Bug 分析

### BUG-1 bug 标题

**现象**：...
**根因**：...（引用源码位置）
**影响范围**：...

---

## Batch A — P0 严重缺陷

### A-1  修复名称

**关联 Bug**：BUG-1
**根因**：...

**修复方案**：...

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

### 步骤 2：生成修复状态文件 (fix-status.json)

依据 `docs/dev/fix.md`（步骤 1 的产出）生成修复状态跟踪 JSON。

**要求**：
1. 为每个批次创建 `batches.batch-X` 条目，包含：
   - `label`：批次中文标签
   - `priority`：P0/P1/P2
   - `description`：批次说明
   - `fixes`：该批次的所有修复
2. 每个修复包含：
   - `name`：修复名称（从 fix.md 提取）
   - `issues`：关联 bug 编号数组
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

- 步骤 0、1、2 必须**顺序执行**，后一步依赖前一步的产出
- 步骤 1 中，**多个 bug 时启用并行 Agent 分析**，每个 bug 一个 Agent；单个 bug 时直接在当前上下文完成
- 步骤 1.2 的汇总合并和步骤 2 在当前上下文中完成
- 步骤 1 在开始前，必须先 Read `docs/dev/fix.md`（如已存在则读取步骤 0 清理后的版本）
- 步骤 2 在开始前，必须先 Read `docs/dev/fix.md`（步骤 1 产出）
- 该 skill **只分析不修改代码**，修复方案供后续 fix-ex 使用
- 生成的 fix.md 和 fix-status.json 必须内容一致、互相可追溯
- 新修复编号接续已有编号，不重复不覆盖
