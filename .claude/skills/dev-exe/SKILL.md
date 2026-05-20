---
name: dev-exe
description: |
  按照开发计划实现代码。支持批量模式（循环所有 pending 项）和单条模式（指定编号）。
  触发场景：用户提到"开始开发"、"实现功能"、"修复问题"、"dev-exe"、功能编号（CON-01 等）、修复编号（A-1 等）、或任何涉及按开发计划实现代码的请求。
---

# 代码实现 (dev-exe)

读取 `docs/dev/dev-status.json`，按 `dev-plan.md` 中对应章节实现代码。

## 输入

可选的**条目编号**（如 `CON-01`、`A-1`、`I-4`）：
- **有编号**：只处理指定条目（单条模式）
- **无编号**：循环处理所有 pending 条目（批量模式）

## 前置：读取上下文

- `docs/dev/dev-status.json` — 进度跟踪
- `docs/dev/dev-plan.md` — 开发计划

---

## 单条模式工作流

### 第1步：解析条目配置

1. 从 `dev-status.json` 的 `items` 中找到目标条目
2. 提取：`name`、`plan_section`、`impl_status`、`dependencies`
3. 根据 `plan_section` 读取 `dev-plan.md` 中对应章节，理解完整实现要求
4. 检查 `dependencies`：
   - 如果依赖项中有 `impl_status != "done"` 的，**停止**，提示用户先完成依赖项

**向用户确认：**
- 条目编号和名称
- 实现要点
- 涉及文件
- 依赖项状态

### 第2步：实现代码与测试

启动新的 Agent（general-purpose），严格按 `dev-plan.md` 中该条目的实现要点编写代码，同时实现测试用例。

Agent prompt 必须包含：
- `dev-plan.md` 中该条目的完整内容（实现要点、涉及文件、测试用例）
- 架构约束（分层：UI → Provider → Service → Data）
- 测试工具配置（mockito、sqflite_ffi、fake_async、ProviderContainer 等）
- **强制约束：严格按计划实现，不得自行发挥。不得跳过任何实现要点。每个测试用例都必须有对应的测试代码。**

Agent 输出：
- 创建/修改的文件列表（代码 + 测试）
- 与实现要点和测试用例的对应关系

### 第3步：验证实现并运行测试

启动新的 Agent（general-purpose），对照 `dev-plan.md` 逐项验证实现，运行测试并修复直至全部通过。

Agent prompt 必须包含：
- `dev-plan.md` 中该条目的完整实现要点和测试用例
- 第2步输出的文件列表
- **验证标准：逐项核对每个实现要点是否已正确完成，每个测试用例是否已覆盖**

Agent 需要：
1. 读取每个实现文件的代码，逐项核对实现要点
2. 发现偏差或遗漏直接修复
3. 运行 `flutter test`，分析失败原因
4. 如果代码不符合计划 → 修改代码
5. 如果测试与用例描述不一致 → 修改测试
6. 重复直到全部通过
7. 报告：验证结果、测试通过数/总数、修复了哪些问题

### 第4步：静态分析与全量测试

**在本会话中直接执行（不使用 Agent）：**

1. 运行 `flutter analyze`，确认 0 issues
2. 运行 `flutter test`，确认全部通过
3. 如有失败，直接修复，重复直到全部通过

**质量门禁：** 第4步必须通过，否则视为未完成。

---

## 批量模式工作流

### 循环前：环境检查

1. 确认 git 仓库有远程 origin 且可推送
2. 确认 `docs/dev/dev-status.json` 存在
3. 确认 `docs/dev/dev_log.md` 存在（不存在则创建）

### 循环体（每轮处理一个条目）

**步骤 A：选择条目**

读取 `dev-status.json`，按 `order` 数组顺序找第一个 `impl_status == "pending"` 的条目。跳过依赖未完成的条目。

如果无 pending 条目，报告完成并结束。

**步骤 B：执行单条模式工作流**

对该条目执行第1-4步。

**步骤 C：追加日志**

```markdown
---

## [YYYY-MM-DD HH:MM] [编号] - [名称]

**状态**: ✅ 成功 / ⚠️ 失败（原因）

### 修改文件
- `lib/path/to/file.dart` — 说明

### 测试结果
- 通过: X / 总计: Y
```

追加到 `docs/dev/dev_log.md`。

**步骤 D：更新状态并提交**

1. 更新 `dev-status.json`：
   - 成功：`impl_status = "done"`, `test_status = "passed"`
   - 失败：保持 `"pending"`，记录原因
2. Git 提交推送：
   ```bash
   git add -A
   git commit -m "feat: 实现 [编号] - [名称]"  # 或 fix: 修复 [编号] - [名称]
   git push
   ```

**步骤 E：继续下一个**

---

## 中断处理

- 某条目失败 → 记录日志，保持 `pending`，继续下一个
- git push 失败 → 暂停，等待用户处理
- 依赖未完成 → 跳过该条目

---

## 完成后汇报

```
═══════════════════════════════════
  实现完成
═══════════════════════════════════
  条目编号:  XXX-XX
  名称:      XXXX
  修改文件:  N 个
  测试通过:  X / Y
  静态分析:  0 issues
═══════════════════════════════════
```
