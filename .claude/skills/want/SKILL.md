---
name: want
description: |
  为新功能模块制定完整的开发计划。当用户需要为项目创建新功能的设计文档和开发状态跟踪时使用此 skill。
  触发场景：用户提到"制定开发计划"、"设计新功能"、"创建功能设计文档"、"want"、"我想要"、"需要开发"、或需要为 docs/design 和 docs/dev 目录创建/更新开发计划文件时。
---

# 新功能开发计划制定

本 skill 引导完成为新功能模块制定开发计划的完整流程：设计文档编写 → 开发状态文件生成。

## 执行流程

### 步骤 1：收集功能信息

向用户确认以下信息：

1. **模块名称**（英文，如 connection、browser、player、timer、progress、settings）
2. **模块中文标签**（如「Connection 模块」）
3. **功能列表**：每个功能需要包含：
   - 功能编号（格式：`{MODULE_ABBR}-{序号}`，如 CON-01、BRW-02、PLY-01、TMR-03、PRG-01、SET-04）
   - 功能名称
   - 优先级（P0/P1/P2）
4. **功能设计细节**：每个功能需要描述：
   - 用户入口和交互流程
   - 核心实现逻辑
   - 涉及的数据模型（如有）
   - Provider/状态管理设计（如有）
   - UI 组件结构（如有）
   - 关键文件列表

如果用户提供的信息不完整，就已知信息进行合理推断并确认，不要因为信息不全而卡住。

### 步骤 2：创建设计文档

在 `docs/design/` 下创建设计文档，文件命名规则：`module-{模块名称}.md`。

#### 设计文档必须包含以下章节结构：

```markdown
# {模块中文名} 模块功能设计

## 1. 模块概述
<!-- 1-2 段描述模块的整体目标和使用场景 -->

## 2. 功能列表
<!-- 表格列出所有功能 -->
| 功能编号 | 功能名称 | 优先级 |
|----------|----------|--------|
| XXX-01 | xxx | P0 |

## 3. 功能详细设计
<!-- 为每个功能编写详细设计，使用功能编号作为小节标题 -->
### XXX-01 功能名称
**入口：** 用户从哪里进入
**交互流程：** 步骤化描述
**实现：** 技术实现方案（含关键代码片段）
**状态管理：** Provider 设计（如有）
**UI 结构：** 组件树（如有）

### XXX-02 功能名称
<!-- 同上格式 -->

## 4. 数据模型
<!-- 该模块涉及的 Dart 数据类定义 -->

## 5. Provider 设计
<!-- 模块的 Riverpod Provider 设计，含伪代码 -->

## 6. UI 结构
<!-- 关键页面的组件树结构 -->

## 7. 测试用例设计
<!-- 按功能分组，每个功能列出测试用例表 -->
### 7.1 单元测试 — XXX-01 功能名称
| 用例编号 | 测试场景 | 预期结果 |
|----------|----------|----------|
| XXX-T01 | 场景描述 | 预期行为 |

### 7.2 Widget 测试 — XXX-01 功能名称
<!-- 如有 UI 交互需要 Widget 测试 -->

## 8. 关键文件
<!-- 列出实现该模块涉及的所有文件路径和职责 -->
| 文件 | 职责 |
|------|------|
| lib/features/xxx/xxx.dart | 描述 |
```

#### 设计文档编写要点：

- **功能开发描述要详细**：每个功能的实现方案要具体到代码层面，包括使用的库、关键方法、状态流转
- **测试用例设计要全面**：覆盖正常路径、边界条件、异常情况、并发场景、UI 交互
- **测试用例编号规范**：格式 `{模块缩写}-T{序号}`，如 `CON-T01`、`BRW-T12`
- 测试用例按类型分组：单元测试（业务逻辑）、Widget 测试（UI 交互）
- 每个测试用例表包含：用例编号、测试场景、预期结果

### 步骤 3：生成开发状态文件

根据设计文档生成 `docs/dev/dev-status.json`。

#### 3.1 清理已完成的项，合并新项

如果文件已存在且不为空，按以下策略处理：

1. **删除已完成项**：遍历所有 module → features，删除同时满足以下条件的 feature：
   - `impl_status` 为 `"done"`
   - `test_pass_status` 为 `"passed"`
2. **清理空模块**：如果某个 module 下所有 feature 都被删除，则删除该 module 节点
3. **保留进行中/未完成项**：`impl_status` 或 `test_pass_status` 为 `"pending"`、`"in_progress"`、`"partial"`、`"failed"` 的 feature 全部保留
4. **合并新模块**：将新设计文档对应的 module 合并到 JSON 中。如果 module key 已存在，则在该 module 下新增 features（不覆盖已有的未完成 features）

#### 3.2 JSON 结构

```json
{
  "modules": {
    "{module_key}": {
      "label": "{模块中文标签}",
      "features": {
        "{功能编号}": {
          "name": "{功能名称}",
          "design_doc": "{设计文档文件名} §{章节号}",
          "impl_tasks": [],
          "impl_status": "pending",
          "test_tasks": [],
          "test_cases": ["{测试用例编号列表}"],
          "test_impl_status": "pending",
          "test_pass_status": "pending"
        }
      }
    }
  },
  "status_values": {
    "impl_status": ["pending", "in_progress", "done"],
    "test_impl_status": ["pending", "in_progress", "done"],
    "test_pass_status": ["pending", "partial", "passed", "failed"]
  }
}
```

#### 3.3 填写规则

- **module_key**：模块英文名（小写），如 `connection`、`browser`
- **impl_tasks**：初始为空数组 `[]`，留给后续 dev-ex skill 填充具体任务编号
- **test_tasks**：初始为空数组 `[]`，留给后续 dev-ex skill 填充具体测试任务编号
- **impl_status**：新功能统一设为 `"pending"`
- **test_impl_status**：新功能统一设为 `"pending"`
- **test_pass_status**：新功能统一设为 `"pending"`
- **test_cases**：从设计文档的测试用例设计章节提取所有测试用例编号，填入数组
- **design_doc**：格式为 `module-{模块名}.md §{章节号}`，如 `module-timer.md §3.1`
- 如果 dev-status.json 中已有其他模块的数据，新模块合并进去而非覆盖（但所有功能状态重置为新生成的）

#### 3.4 测试用例编号提取

从设计文档第 7 章「测试用例设计」中提取所有形如 `XXX-T01` 的用例编号。确保不遗漏任何一个测试用例。

### 步骤 4：验证输出

完成后检查：
- 设计文档路径正确：`docs/design/module-{name}.md`
- 设计文档包含所有必要章节（1-8 章）
- dev-status.json 结构完整，JSON 格式有效
- 所有测试用例编号已完整提取
- status_values 节点存在

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

设计文档命名：`module-{英文名}.md`，如 `module-connection.md`
