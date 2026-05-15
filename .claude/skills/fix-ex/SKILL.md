---
name: fix-ex
description: 按照修复文档严格修复问题。当用户提到"修复问题"、"fix"、问题编号（A-1, B-2, C-3 等格式）、"fix-ex"、或任何涉及按修复文档修复缺陷的请求时使用此 skill。
---

# 问题修复工作流 (fix-ex)

此 skill 按严格流程修复一个问题，所有修复和验证均以修复分析文档（`docs/dev/fix.md` 和 `docs/dev/fix-status.json`）为准。

## 输入

需要一个**修复编号**（如 `A-1`、`B-3`、`C-2`）。如果不确定编号，先从 `docs/dev/fix-status.json` 中查找。

---

## 工作流步骤

### 第1步：解析修复配置

1. 读取 `docs/dev/fix-status.json`，遍历所有批次（`batch-a`, `batch-b`, `batch-c`）的 `fixes`，找到目标修复编号的配置节。
2. 提取：`name`、`issues`、`design_doc`（格式 `docs/fix.md §章节`）、`current_status`、`work_items`、`files_involved`、`dependencies`。
3. 读取 `docs/dev/fix.md`，定位到该修复编号对应的章节，完整理解修复方案和具体代码要求。
4. 检查 `dependencies` 是否非空：
   - 如果有依赖项，检查依赖项的 `impl_status` 是否都是 `done`
   - 如果有未完成的依赖项，**先停止当前修复**，提示用户先完成依赖项

**向用户确认以下信息后再继续：**
- 修复编号和名称
- 关联的问题编号
- 修复文档章节
- 工作项数量
- 涉及的文件列表
- 依赖项状态（如有）

### 第2步：实现修复

启动新的 Agent（general-purpose），**严格按修复文档中的修复方案实现**。

Agent prompt 必须包含：
- 修复文档路径和章节号（如 `docs/fix.md §Batch A — A-3`）
- 从修复文档中提取的该修复的**完整修复方案**（包括所有代码示例、逻辑描述、触发条件等）
- `fix-status.json` 中该修复的 `work_items` 完整列表
- `fix-status.json` 中该修复的 `files_involved` 完整列表
- `fix-status.json` 中该修复的 `current_status`（当前问题描述）
- **强制约束：严格按修复文档中的方案实现，不得自行发挥或添加文档未提及的修改。不得跳过任何 work_item。每个 work_item 都必须完成。**

Agent 输出：
- 创建/修改的文件列表
- 与修复文档 work_items 的对应关系说明

### 第3步：验证修复实现

启动新的 Agent（general-purpose），**对照修复文档逐项验证**第2步的实现。

Agent prompt 必须包含：
- 修复文档路径和章节号
- 修复文档中该修复的完整修复方案
- `fix-status.json` 中该修复的 `work_items` 完整列表
- 第2步输出的文件列表
- **验证标准：逐项对照修复文档中的每个要求，检查是否已正确实现，不得遗漏任何 work_item**

Agent 需要：
- 读取每个实现文件的代码
- 逐项核对修复文档的要求和 work_items 列表
- 如发现偏差或遗漏，**直接修复代码**
- 报告：通过了哪些检查项，修复了哪些问题

### 第4步：静态分析与全量测试

**在本会话中直接执行（不使用 Agent）**，确保静态分析和全部测试通过：

1. 运行 `flutter analyze`，确认无 error 级别问题（info/warning 可忽略，但不得引入新的 warning）
2. 运行 `flutter test`，确认全部测试通过
3. 如有失败：
   - 分析根因，直接修复代码
   - 重复直到 `flutter analyze` 零 error + `flutter test` 全通过
4. 如果遇到无法解决的失败，报告具体原因并暂停

---

## 完成后

汇报汇总：
- 修复编号和名称
- 修改的文件列表
- 验证结果（通过项/总项）
- 静态分析结果（error 数 / 总 issue 数）
- 测试通过情况（通过数 / 总数）
- 建议将 `docs/dev/fix-status.json` 中对应修复的 `impl_status` 更新为 `done`

**质量门禁：** 第4步必须通过（`flutter analyze` 零 error + `flutter test` 全过），否则视为未完成。
