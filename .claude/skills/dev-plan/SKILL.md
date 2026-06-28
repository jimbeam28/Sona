---
name: dev-plan
description: |
  分析新功能需求或 Bug，基于现有代码逆抽行为规约 + 增量加新需求 Scenario，输出 `docs/features/{ID}.md` 详细设计文档与 `docs/dev/dev-status.json` 进度项。
  触发场景：用户提到"制定计划"、"设计功能"、"分析需求"、"分析bug"、"开发计划"、"dev-plan"，或任何需要先分析再实现的请求。
  不触发：用户提到"开始开发"、"实现"、"dev-exe"或明确要执行已有计划时——应由 dev-exe 处理。
---

# 开发计划制定 (dev-plan)

为每个待开发功能或 Bug 修复产出一份**锚到代码、不脑补**的详细设计文档，并更新 `dev-status.json`。
产出的文档是 dev-exe 的输入，是**约束 LLM 实现不脑补**的唯一规约源。

## 四条铁律（违反 = 输出无效）

1. **锚到代码**：§3 每条 Scenario、§4 每条不变量、§6 每条算法样例必须给出 `file:line` 证据。无证据 = 不能写入文档。
2. **禁止凭空发明现有行为**：§3"现有行为 Scenario"必须基于读到的代码逆抽，不能根据"功能应当如何"脑补。读不到代码 → 文档先标 TODO，不允许猜测。
3. **增量加新需求 Scenario**：用户新需求对应的 Scenario 必须显式标 `status: new`，证明它**不是从代码逆抽**而是来自本轮需求。
4. **否定断言必带（防假阴面）**：每条 `status: new` Scenario 必须显式声明**否定断言**——指明哪些状态/事件不应发生。理由：默认只写"应该发生的"，测试就只断言正向行为，反向断言（"不该发生的没发生"）缺失导致负面 bug 难抓。

   **否定断言格式**：在 Scenario 的 GWT 块末尾追加：
   ```
   否定断言:
     - <不该发生的状态变化> （例：queue.length 不变）
     - <不该触发的事件/副作用> （例：不调用 audioHandler.play）
   ```
   若该 Scenario 真无任何否定面（罕见），写 `否定断言: 无`，反例见下面 BRW-09 示例。dev-check 第 7 项会基于此验证测试是否真有否定断言。

---

## 输入

用户输入两类之一：
- **新功能**：需求描述、交互流程、设计要求
- **Bug 修复**：Bug 现象、复现步骤、涉及模块（用户不一定熟悉代码，描述可能有歧义）

---

## 执行流程

### 步骤 0：判断功能 ID 与既有文档

1. 检查 `docs/features/{ID}.md` 是否存在
   - **存在** → 走"修订模式"（步骤 1B + 3B）
   - **不存在** → 走"新建模式"（步骤 1A + 3A）
2. 分析用户输入判断是**新功能**还是 **Bug 修复**
3. 确定功能 ID：
   - 沿用现有模块编号体系（CON / BRW / PLY / TMR / PRG / SET）
   - 新功能编号尾号自增（参考 `docs/dev/dev-status.json` 已用编号）
4. 读取 `docs/features/_TEMPLATE.md` 作为本次输出格式基线

### 步骤 1A：新建模式 — 代码勘察

> **目的**：在不脑补的前提下把"现有功能骨架"摸清楚，作为新文档 §2 / §3 现有部分的基础。

1. 用 `explore` / `grep` / `read` 定位本功能的代码：
   - 入口路由（`lib/main.dart` / `lib/app/router.dart`）
   - screen、widget、provider、domain service / validator、shared model
   - 既有测试文件清单
2. 列出文件清单 + 每文件责任 + 每文件行数
3. 列出关键 Provider 表（名称、类型、实现 file:line、用途）
4. 画状态机骨架（若有状态机）
5. 列出现有测试覆盖了哪些 Scenario（用 `grep` 抽 test 名），**估测**现有覆盖盲点

**勘察结果**作为内部工作产物，整理为后续 §2 的内容。**不允许跳过勘察直接写 Scenario**。

### 步骤 1B：修订模式 — 既有文档校对

1. 读 `docs/features/{ID}.md` 的 §2 / §3 / §4
2. 对每条 Scenario / INV 的 Code evidence 重新核对文件位置：
   - 文件被改名 / 移动 → 同步更新证据
   - 行号已漂移 → 至少更新到正确文件；行号可省略，标 `~file` 表示"该文件附近"
   - 代码删除 → Scenario 改 `status: deprecated`，不能假装还在
3. 列出"本次需要修订的点"清单供步骤 3B 使用

### 步骤 2：分析新需求 / Bug

#### 新功能

1. 将用户需求转写为"用户视角 Scenario"（§1.2 的行）——**纯中文、不出现代码术语**
2. 为每条用户视角 Scenario 对应一条 §3 技术层 Scenario（带 Code evidence 锚点）+ **每条必须带否定断言**（见铁律 4）
3. 若需求影响 §4 不变量 → 列新增/修改的不变量（不变量本身已经是"不变"的语义，可不带否定断言）
4. 若需求引入纯函数 → 列 §6 算法样例
5. 评估跨模块影响（§7）：
   - 用 `grep` 找出本功能 Provider / Model / Service 被哪些其它 feature 引用
   - 每个引用方列一行：可能影响其什么不变量
6. 评估 §8 平台特性：是否涉及 `audio_service` / `audio_focus` / `background_service` / `MethodChannel` / 通知栏
   - 涉及 → `§0 manual_qa_required = true`，**必须**产出 `docs/dev/mqa-{ID}.md`
   - 不涉及 → 显式写 false

**否定断言示例**（BRW-09"下一曲播放"功能）：
```
[{ID}-S2] 不在播放时点击"下一曲"图标
  Given 队列存在但 currentTrack = null（未开始播放）
  When 用户点击文件 T 的"下一曲"图标
  Then 图标处于禁用态（或不响应点击）
  否定断言:
    - queue 长度不变（不插入新曲）
    - currentIndex 不变（不切换当前曲）
    - 不调用 IAudioHandler.play / IAudioHandler.load
```

#### Bug 修复

1. **复现测试先行**（本步骤是 Bug 修复的硬门禁）：
   - 根据用户描述写**一条能复现该 Bug 的失败测试**（`test/features/{feature}/bug_{ID}_repro_test.dart`）
   - 运行 `flutter test test/features/{feature}/bug_{ID}_repro_test.dart`
   - **测试必须 FAIL**——若 PASS 说明没复现或 bug 已被其它修改影响，回到步骤 1 重读代码
   - 测试 FAIL 后才允许分析根因
2. 读代码定位根因：每个根因都要有 `file:line` 证据
3. 分析修复方案：列出需要改动哪些文件、改什么、为什么这个改法消除根因而非掩盖症状
4. 写 §1.2 用户视角 Scenario "修复后用户看到 X"
5. 写 §3 技术层 Scenario "修复后行为 Y"（status: new）
6. **不允许**只对症状打补丁——若修复方案无明显根因消除点，输出"修复存疑，建议人工评审"

### 步骤 3A：新建模式 — 输出 `docs/features/{ID}.md`

按 `docs/features/_TEMPLATE.md` 输出**完整文档**，必填章节：
- §0 元数据
- §1.1 一句话 + §1.2 用户视角 Scenario 表（**用户审的部分**）
- §2 已实现功能骨架（§2.1 文件与分层、§2.2 Provider 表、§2.3 状态机图）
- §3 行为规约 Given-When-Then（现有 + 新增；新增的标 `status: new`）
- §4 不变量
- §5.1 现有测试清单、§5.2 测试 ID 派生清单、§5.3 测试覆盖盲点
- §6 算法样例（若涉及纯函数）
- §7 跨模块影响
- §8 平台特性与手动 QA
- §9 dev-status.json 条目对照
- §10 与历史文档对照（若迁移自 state.md / 其它文档）

### 步骤 3B：修订模式 — 输出 `docs/features/{ID}.md` 增量更新

1. 保留原本档的全部既有 Scenario / INV，不动它们的 `status`
2. 在 §3 末尾追加本次新增 / 修改的 Scenario，每条标 `status: new` 或 `status: modified`，**每条 `status: new` 必须带否定断言**（铁律 4）
3. 修改 §4 不变量：新增标 `status: new`，删除标 `status: deprecated`，**不直接删行**
4. 同步更新 §2（文件清单、Provider 表）若涉及文件结构变化
5. 同步更新 §5.3 测试覆盖盲点（含本次新加的未覆盖 Scenario）
6. 同步更新 §7 跨模块影响
7. 同步更新 §8 manual_qa_required
8. 在文档末尾追加 changelog：`- YYYY-MM-DD: {本次需求摘要} (status: new)`

### 步骤 4：更新 `docs/dev/dev-status.json`

#### 4.1 清理已完成项

删除 `impl_status == "done"` 且 `test_status == "passed"` 的条目，从 `order` 数组中移除对应 ID。
**已 done 条目不允许长期留在 status.json 中**——已完成内容保存在 git 提交历史中。

#### 4.2 添加新条目（按模板 §9 字段）

```json
"{ID}": {
  "name": "{名称}",
  "spec_file": "docs/features/{ID}.md",
  "spec_anchored_files": ["lib/.../a.dart", "lib/.../b.dart"],
  "scenarios": ["{ID}-S1", ..., "{ID}-S{n}"],
  "invariants": ["{ID}-INV1", ..., "{ID}-INV{n}"],
  "algorithms": ["{ID}-ALG1", ...],
  "test_files": ["test/.../x_test.dart", ...],
  "test_coverage_gaps": ["{ID}-S5", "{ID}-INV3", ...],
  "cross_module_impacts": ["BRW", "PRG"],
  "manual_qa_required": false,
  "manual_qa_file": null,
  "user_acceptance_text": "见 docs/features/{ID}.md §1.2",
  "impl_status": "pending",
  "test_status": "pending",
  "dependencies": ["{依赖编号}"],
  "retry_count": 0,
  "last_error": "",
  "last_updated": "{YYYY-MM-DD}"
}
```

字段规则：
- `spec_anchored_files`：必须非空——锚到代码是铁律
- `scenarios` / `invariants`：必须列出本功能全部 ID，dev-exe 用它做覆盖率门禁
- `test_coverage_gaps`：明确列出未覆盖的 ID，dev-exe 必须为每条产出测试
- `manual_qa_required` 为 true 时 `manual_qa_file` 必须指向 `docs/dev/mqa-{ID}.md`
- Bug 修复时 `dependencies` 列出本 bug 涉及的 feature ID（用于追踪）
- `impl_status`：`"pending"` / `"done"` / `"failed"` / `"blocked"`
- `test_status`：`"pending"` / `"passed"`
- `retry_count`：dev-exe 执行失败 +1，达到 3 次 → `"blocked"`
- `check_status`：`"pending"` / `"passed"` / `"round_1"` / `"round_2"` / `"round_3"` / `"blocked_after_3_rounds"` —— 由 dev-check skill 维护，dev-plan 创建条目时设 `"pending"`
- `check_round`：0 起，每次 dev-check 打回 +1，达到 3 标 `blocked_after_3_rounds`
- `last_check_round_results`：指向 `docs/dev/check_log.md` 中最末条目位置的引用字符串
- `last_checked_at`：日期

#### 4.3 更新 order

将新条目 ID 追加到 `order` 数组末尾（除非有依赖关系要求特定顺序）。

#### 4.4 更新 metadata

更新 `last_updated` 日期和 `total` / `pending` 计数。

### 步骤 5：呈现给用户审

输出三件事让用户审：

1. **§1.2 用户视角 Scenario 表**——这是用户唯一需要审的部分，纯中文无代码术语。要求用户确认每条与最初需求对得上。
2. **跨模块影响清单**——告诉用户："我改这个功能，会影响 BRW / PRG / PLY 的 X/Y/Z 不变量"。
3. **测试覆盖盲点清单**——告诉用户："现有测试漏了 X 条 Scenario / 不变量，dev-exe 会补上"。

用户 ack 后，dev-plan 流程结束。用户未 ack 之前**不得**进入 dev-exe。

---

## Bug 修复特例：复现测试硬门禁

Bug 修复场景下，步骤 2 第 1 步是一条**硬门禁**：

1. 在分析根因之前，**先写一条能复现该 Bug 的失败测试**
   - 文件路径：`test/features/{feature}/bug_{ID}_repro_test.dart`
   - 测试名：`bug_{ID}: {bug 现象一句话}`
2. 运行该测试，**必须 FAIL**
3. PASS → 说明你没复现，回到步骤 1A/1B 重新读代码
4. FAIL 后才允许写修复方案、写新 Scenario
5. 该复现测试在 dev-exe 完成 Bug 修复后必须 PASS——这是"修复已落地"的硬指标

**理由**：终结"反复修同一个 bug"——失败复现测试存在意味着下次 bug 复回时 CI 会爆。

---

## 并行处理多个独立 Bug

多个独立 Bug 同时输入时：
1. 为每个 Bug 启动一个独立 Agent 分析，写临时文件 `docs/dev/.debug-bug-{N}.md`
2. 每个 Agent 产出：bug 现象、复现测试方案、根因、修复方案、涉及文件、Scenario 编号
3. 汇总成 `docs/features/BUG-{NN}.md`（每条 bug 一份）
4. 清理临时文件
5. 与用户一次性审完整批 changelog

---

## 输出验收检查

dev-plan 流程结束前必须确认：

- [ ] `docs/features/{ID}.md` 存在且符合 `_TEMPLATE.md` 格式
- [ ] §3 每条 Scenario 都有 `Code evidence: file:line`
- [ ] §3 每条 `status: new` Scenario 都有 `否定断言:` 块（铁律 4）
- [ ] §4 每条不变量都有 `证据: file:line`
- [ ] §1.2 用户视角 Scenario 表无代码术语
- [ ] §5.3 测试覆盖盲点已明确列出未覆盖 ID
- [ ] §7 跨模块影响已用 grep 列真实引用方
- [ ] §8 manual_qa_required 评估完整
- [ ] Bug 修复场景：`test/features/.../bug_{ID}_repro_test.dart` 已写、已运行、已 FAIL
- [ ] `docs/dev/dev-status.json` 结构有效，scenarios / invariants 与文档一致
- [ ] 已向用户呈现 §1.2 + 跨模块影响 + 测试盲点，等待 ack

任一条不满足 → 输出无效。

---

## 参考：现有模块命名规范

| 模块 | 缩写 | 测试编号前缀 | ID 前缀 |
|------|------|-------------|---------|
| Connection | CON | CON-T | CON-NN |
| Browser | BRW | BRW-T | BRW-NN |
| Player | PLY | PLY-T | PLY-NN |
| Timer | TMR | TMR-T | TMR-NN |
| Progress | PRG | PRG-T | PRG-NN |
| Playlist | PLY | PLY-T | PLY-NN |
| Settings | SET | SET-T | SET-NN |
| 跨模块集成 | INT | INT-T | INT-NN |

新功能编号策略：
- 沿用现有最大编号尾号 +1
- Bug 修复编号：`BUG-{NN}`（不与功能 ID 混用）