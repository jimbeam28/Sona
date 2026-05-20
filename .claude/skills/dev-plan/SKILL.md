---
name: dev-plan
description: |
  分析需求或 Bug，制定统一的开发计划。适用于功能开发和 Bug 修复两种场景，输出 dev-plan.md 和 dev-status.json。
  触发场景：用户提到"制定开发计划"、"设计新功能"、"debug"、"分析bug"、"dev-plan"、"我想要"、"需要开发"、功能编号（CON-01 等格式）、或任何需要规划代码变更的请求。
---

# 开发计划制定 (dev-plan)

分析用户需求（新功能或 Bug 修复），输出统一的开发计划文档和进度跟踪文件。

## 输入

用户描述需要做什么，可能是：
- **新功能**：功能描述、交互流程、设计要求
- **Bug 修复**：Bug 现象、复现步骤、涉及模块

## 执行流程

### 步骤 1：判断类型并分析

根据用户输入判断是**新功能**还是 **Bug 修复**。

#### 如果是新功能

收集以下信息（信息不完整时合理推断并确认，不要卡住）：

1. **模块名称**（英文，如 connection、browser、player、timer、progress、settings）
2. **功能编号**（格式：`{MODULE_ABBR}-{序号}`，如 CON-07、BRW-08）
3. **功能名称**（简短描述）
4. **优先级**（P0/P1/P2）
5. **实现要点**：
   - 用户入口和交互流程
   - 核心实现逻辑
   - 涉及的数据模型
   - Provider/状态管理设计
   - UI 组件结构
   - 关键文件列表
6. **测试用例**：列出测试场景和预期结果，编号格式 `{ABBREV}-T{NN}`

#### 如果是 Bug 修复

1. 阅读相关源码文件，根据 bug 现象追踪代码逻辑，定位根因
2. 输出分析结果：
   - Bug 现象描述
   - 根因（引用源码文件路径和行号）
   - 可操作的修复方案（含代码示例、触发条件、逻辑描述）
   - 优先级：P0（核心功能崩溃）/ P1（功能异常但可绕过）/ P2（轻微问题）
   - 涉及文件列表
3. **测试用例**：列出验证修复的测试场景和预期结果。如果已有测试覆盖该场景则标注"已有测试覆盖"，否则给出新增测试用例（编号格式 `{MODULE}-FIX-T{NN}`）

**多个独立 Bug 时**：为每个 Bug 启动一个 Agent 并行分析，每个 Agent 将结果写入临时文件 `docs/dev/.debug-bug-N.md`，完成后汇总合并，清理临时文件。

### 步骤 2：更新 dev-plan.md

读取 `docs/dev/dev-plan.md`（如不存在则创建），追加新条目。

**格式：**

```markdown
### {编号} {名称}

**来源**：新功能 / Bug 修复 | **优先级**：P0/P1/P2
**涉及文件**：`lib/path/to/file.dart`
**依赖**：无 / 依赖项编号
**关联 Bug**：BUG-X（Bug 修复时填写）

**实现要点**：
- 要点 1
- 要点 2

**测试用例**：XXX-T01 ~ XXX-T05
```

- 新条目追加到 `## 待实现` 章节顶部
- 已完成的条目保留在 `## 已完成` 章节，按时间倒序

### 步骤 3：更新 dev-status.json

读取 `docs/dev/dev-status.json`。

#### 3.1 清理已完成项

删除 `impl_status == "done"` 且 `test_status == "passed"` 的条目，从 `order` 数组中移除对应 ID。

#### 3.2 添加新条目

每个新条目格式：

```json
"{编号}": {
  "name": "{名称}",
  "plan_section": "dev-plan.md §{编号}",
  "impl_status": "pending",
  "test_status": "pending",
  "dependencies": ["{依赖编号}"]
}
```

- `plan_section`：引用 dev-plan.md 中对应条目
- `impl_status`：新条目统一为 `"pending"`
- `test_status`：新条目统一为 `"pending"`
- `dependencies`：从 dev-plan.md 提取依赖关系

#### 3.3 更新 order

将新条目 ID 追加到 `order` 数组末尾（除非有依赖关系要求特定顺序）。

#### 3.4 更新 metadata

更新 `last_updated` 日期和 `total` / `pending` 计数。

### 步骤 4：验证

- `dev-plan.md` 格式正确，新条目信息完整
- `dev-status.json` 结构完整，JSON 有效
- `dev-plan.md` 和 `dev-status.json` 中的条目一一对应
- `order` 数组与 `items` 中的条目一致

---

## 参考：现有模块命名规范

| 模块 | 缩写 | 测试编号前缀 |
|------|------|-------------|
| Connection | CON | CON-T |
| Browser | BRW | BRW-T |
| Player | PLY | PLY-T |
| Timer | TMR | TMR-T |
| Progress | PRG | PRG-T |
| Settings | SET | SET-T |
