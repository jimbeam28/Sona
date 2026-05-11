---
name: dev
description: 全量自动化开发。按顺序实现 docs/dev/dev-status.json 中所有未完成的功能，逐个调用 dev-ex 流程，记录日志并提交。当用户说"开始开发"、"实现全部功能"、"全量开发"、"dev"、"批量实现"、"自动开发所有功能"时使用此 skill。
---

# 全量功能开发 (dev)

循环实现 `docs/dev/dev-status.json` 中所有 `impl_status == "pending"` 的功能，每个功能遵循 dev-ex 工作流，完成后记录日志并 git 提交推送。

---

## 循环前：环境检查

1. 确认当前目录是 git 仓库，有远程仓库 origin 且可推送（`git remote -v`）。
   - 如未配置远程仓库，提示用户先配置。
2. 确认 `docs/dev/dev-status.json` 存在。
3. 确认 `docs/dev/dev_log.md` 存在，如不存在则创建空文件。

---

## 循环体（每轮处理一个功能）

### 步骤 A：选择功能

读取 `docs/dev/dev-status.json`，找到所有 `impl_status == "pending"` 的功能。

选择策略：
- 按 `docs/dev/dev-status.json` 中模块的出现顺序遍历（connection → browser → player → timer → progress → settings）
- 每个模块内按功能编号字母序排列
- 取第一个 pending 功能

如果所有功能 `impl_status` 都已不是 `pending`，报告"所有功能已完成"并结束循环。

**向用户报告：** 本轮选中 `[编号] - [名称]`，所属模块，设计文档引用。

### 步骤 B：执行 dev-ex 工作流

对此功能执行 dev-ex 技能定义的完整流程：

1. **解析功能配置**：读取设计文档对应章节和测试设计文档中对应的测试用例。
2. **实现功能**（新 Agent）：严格按设计文档实现代码。
3. **验证实现**（新 Agent）：对照设计文档检查，有问题直接修复。
4. **实现测试**（新 Agent）：严格按测试设计文档实现测试用例。
5. **验证测试**（新 Agent）：对照测试设计文档检查，有遗漏直接修复。
6. **运行测试并修复**（新 Agent）：运行测试，修改代码直至全部通过。

详细规范见 dev-ex skill 的第1-6步。

### 步骤 C：追加实现日志

将本轮实现的摘要追加到 `docs/dev/dev_log.md`。如果文件不存在，先创建。

日志格式：

```markdown
---

## [YYYY-MM-DD HH:MM] [编号] - [名称]

**模块**: [模块名]
**状态**: ✅ 成功 / ⚠️ 部分完成（说明原因）

### 实现文件
- `lib/path/to/file1.dart` — 简要说明
- `lib/path/to/file2.dart` — 简要说明

### 测试文件
- `test/path/to/test_file.dart` — 测试用例 N 个

### 测试结果
- 通过: X / 总计: Y
- （如有失败，列出失败用例和原因）

### 备注
（如有异常、注意事项、手动修复内容等）
```

### 步骤 D：更新状态并提交

1. 更新 `docs/dev/dev-status.json` 中该功能的状态：
   - `impl_status`: 根据结果设为 `"done"` 或保持 `"in_progress"`
   - `test_impl_status`: 根据结果设为 `"done"` 或保持 `"pending"`
   - `test_pass_status`: 根据结果设为 `"passed"`、`"partial"` 或 `"failed"`

2. Git 提交并推送：
   ```bash
   git add -A
   git commit -m "feat([模块名]): 实现 [编号] - [名称]"
   git push
   ```
   - 如果 push 失败（如冲突），报告错误并暂停，等待用户处理后再继续。

### 步骤 E：继续下一个

回到步骤 A，选择下一个 pending 功能。

---

## 循环结束

所有功能 `impl_status == "done"` 后，汇报总览：

```
═══════════════════════════════════
  全量开发完成
═══════════════════════════════════
  总功能数:    N
  成功实现:    N
  总测试通过:  N/N
  Git 提交数:  N
═══════════════════════════════════
```

---

## 中断处理

如果某轮循环中步骤 B（dev-ex 流程）失败：
1. 记录失败原因到日志。
2. 将该功能 `impl_status` 保持为 `"pending"` 并附带备注。
3. 继续处理下一个功能，不中断整体循环。
4. 循环结束后，列出所有失败的功能供用户检查。

如果 git push 失败：
1. 暂停循环。
2. 提示用户解决推送问题。
3. 问题解决后继续循环。
