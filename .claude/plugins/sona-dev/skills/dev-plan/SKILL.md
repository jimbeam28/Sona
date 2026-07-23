---
name: dev-plan
description: |
  讨论新功能/Bug 需求，把讨论清楚的落地为 docs/features/{ID}.md 规约 + dev-status.json 条目。
  触发：用户提到"制定计划""设计功能""分析需求""分析bug""开发计划""dev-plan"。
  不触发：用户明确要"开始开发/实现"→ dev-exe。
---

# dev-plan — 设计讨论 → 规约落地

> 格式与字段统一见 `../../reference/SCHEMA.md`；脚本在 `../../scripts/`（相对本 skill）。
> 本 skill 由强模型执行：产出规约的精度决定弱模型 dev-exe 的成败。

## 四条铁律（违反 = 输出无效）

1. **锚到代码**：Scenario / 不变量 / 算法样例必须给 `file:line` 证据；读不到代码标 TODO，不脑补。
2. **现有行为靠逆抽**：不得凭"功能应当如何"发明现有行为。
3. **新需求显式标 `status: new`**，与逆抽内容区分。
4. **每条 `status: new` Scenario 必带否定断言**（格式见 SCHEMA §2）——防"只断言该发生的、漏断言不该发生的"假阴面 bug（BUG-01 即此类）。

## 流程

### 0. 定位

- 扫 `docs/features/INDEX.md` 判定模式：
  - **新建**：未命中已有文档 → 编号 `bash ../../scripts/dev-status.sh next-id <PREFIX>`
  - **修订**：命中已有 {ID}.md → 在其 §3 末尾增量追加
  - **Bug fold**：单特性 bug 且父文档存在 → 折叠为父文档 `status: new` Scenario；跨模块 bug → 新建 `BUG-NN.md`（§0 `parent_feature` 字段见 SCHEMA §2）
- 判断新功能 vs Bug：用户输入是需求描述 → 新功能；是现象+复现步骤 → Bug。

### 1. 需求访谈（新功能不可跳过；Bug 跳过本步直接进步骤 2 的复现门禁）

与用户逐条核对边界问题，**答清楚的才进 spec**：

- 空列表 / 队列只有一项？最后一项 / 队尾边界？
- 快速连点 / 操作中途返回？后台切回？
- 网络断开 / 弱网 / 大文件（远程 FLAC）？
- 音频焦点被抢（来电、其它播放器）？

随后逐条核对 `docs/dev/platform-pitfalls.md`：本需求触及哪几条同类场景？**触及即在 §3 中显式处置**（写进 Scenario 或不变量），不允许"之后注意"。

### 2. 勘察（锚到代码）

用 grep/read 定位本功能：入口路由、screen、widget、provider、domain service、shared model、既有测试。列文件清单 + 责任 + 行数，逆抽现有行为骨架。**不允许跳过勘察直接写 Scenario。**

### 3. 落文档 `docs/features/{ID}.md`（按 SCHEMA §2）

- **§1.0 用户原话逐字记录**（跨会话交接的唯一需求源）
- §1.2 用户视角表：纯中文、无代码术语
- §3：现有行为逆抽带证据；新需求 = `status: new` + 否定断言 + **修改点级描述**（指明改哪个文件哪个函数、每个边界情况的裁决——弱模型照此实现，不需要二次判断）
- §7 跨模块：用 `bash ../../scripts/cross-imports.sh impact <锚点文件...>` 列引用方，每个引用方写回归断言要求
- §8 真机风险列：逐条写 fake 测不到、只有真机会出什么；能近似测的写成测试，真测不了的进 `docs/dev/mqa-backlog.md`
- **Bug 硬门禁**：先写失败复现测试 `test/features/{feat}/bug_{ID}_repro_test.dart`，跑 `bash ../../scripts/repro-test.sh <path> fail`——**FAIL 之后才允许分析根因**（PASS = 没复现，回步骤 2 重读代码）。修复后该测试必须 PASS。不允许只打症状补丁：无明确根因消除点 → 输出"修复存疑，建议人工评审"。

### 4. 自检门禁（脚本退出码为准）

```bash
bash ../../scripts/spec-scan.sh --neg <ID>          # 否定断言结构，必须 0
bash ../../scripts/spec-scan.sh --count <ID>        # S/INV/ALG 计数 → 同步 INDEX.md
bash ../../scripts/dev-status.sh create <ID> <name> <spec_file> <锚点文件...>   # 自动校验锚点存在
bash ../../scripts/dev-status.sh set <ID> scenarios '["..."]'    # 补 ID 清单 / gaps / impacts
```

同步更新 `docs/features/INDEX.md`（格式见 SCHEMA §3.1）。

### 5. 呈现给用户审

输出三件：① §1.2 用户视角表（与 §1.0 原话逐条对得上）② 跨模块影响清单 ③ 测试盲点 + 真机风险列。**用户 ack 后流程结束，不自动进 dev-exe。**
