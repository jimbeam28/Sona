# 功能详细设计文档模板

> 每个有 ID 的功能（如 `CON-01`、`BRW-03`、`PLY-12`）都按本模板维护一份 `docs/features/{ID}.md`。
> dev-plan skill 在新功能或 bug 分析时基于本模板输出，dev-exe skill 按本文档实施。
>
> **核心原则：文档锚到代码，不脑补；任何 Scenario 和不变量都必须有代码出处（file:line）。**
> **维护策略：仅在功能被新增/修改时由 dev-plan 写或改；不一次性倒推全项目。**

---

## §0 头部元数据

```yaml
id: {ID}                    # 如 CON-01
name: {功能名称}              # 如 "添加 WebDAV 连接"
priority: P0 | P1 | P2
status: draft | active | deprecated
created_at: YYYY-MM-DD
last_updated: YYYY-MM-DD
spec_anchored_files:
  - lib/path/to/file_a.dart
  - lib/path/to/file_b.dart
cross_module_impacts: [BRW, PRG, PLY]   # 改本功能会影响的 feature 列表
manual_qa_required: false | true        # 涉及平台原生（audio_service / AudioFocus / MethodChannel / 通知栏）必须 true
```

---

## §1 用户视角（你来扫这一节就够）

### 1.1 这一功能干什么（一句话）

\<用户视角的功能描述\>

### 1.2 用户期望的场景

> 纯中文、不出现代码术语、按业务流程描述。这一节是**用户唯一需要审的部分**，按"用户看见 X / 期望 Y"成对列出。dev-plan 写完后，请你扫这一节，与最初需求对不上时打回 dev-plan 重写。

| ID | 你看到的样子 | 期望行为 |
|----|----|----|
| U1 | | |
| U2 | | |

---

## §2 已实现的功能骨架（代码锚点）

> 由 dev-plan 在首次写本文档时——基于现有代码逆抽得出。每条都要标代码出处（file:line 或路径），LLM 实现时**不得**凭空发挥，必须按锚点定位。

### 2.1 文件与分层

| 层 | 文件 | 行数 | 角色 |
|---|---|---|---|
| UI | | | |
| Provider | | | |
| Domain | | | |
| 测试 | | | |

### 2.2 关键 Provider 表

| Provider 名 | 类型 | 实现位置 | 用途 |
|---|---|---|---|
| | | | |

### 2.3 状态机图（若有）

```
（用 ASCII / mermaid 画当前状态机骨架；纯算法类功能跳过本节）
```

---

## §3 行为规约（Given-When-Then）

> 这是功能的硬规约。每条 Scenario 编号 `{ID}-S{n}`，作为 test ID。
> **本节由你提供增量需求时由 dev-plan 增补；现有行为由 dev-plan 逆抽得出。**
> **每条 Scenario 必须给出 Code evidence（file:line），证明该行为在代码中真实存在。**
> **每条 `status: new` Scenario 必须带 `否定断言:` 块**（dev-plan 铁律 4，防假阴面 bug）：
>   显式声明哪些状态/事件不应发生——dev-exe 测试 Agent A 须为每条否定断言写对应 `expect(..., unchanged)` 类断言，dev-check 第 7 项会验证。

### 3.x {子功能名}

- **[{ID}-S{n}]** {一句话描述} （`status: new` 或省略）
  ```
  Given {前置}
  When {触发}
  Then {状态变化 / 副作用}
  And {其它断言}
  否定断言:                              # 仅 status: new 必填；现有行为可省
    - <不该发生的状态变化> （例：queue.length 不变）
    - <不该触发的事件/副作用> （例：不调用 IAudioHandler.play）
  ```
  Code evidence: `<file:line>`

---

## §4 不变量

> 永远成立的规则。每条 INV 须有测试断言（见 §5.2）。每条 INV 必须给出 Code evidence。

- **[{ID}-INV{n}]** {一句话不变量}
  证据：`<file:line>`

---

## §5 测试规约

### 5.1 现有测试清单

| 测试文件 | 覆盖的 Scenario / INV | 备注 |
|---|---|---|
| | | |

### 5.2 测试 ID 派生清单（dev-exe 派发测试 Agent 用）

```
{ID}-S1 … S{n}        # Scenario
{ID}-INV1 … INV{n}    # 不变量
{ID}-ALG1 …           # 算法样例（若有，见 §6）
{ID}-MAN1 …           # 手动 QA 步骤（若有，见 §8）
```

dev-exe 要求：每个未覆盖的 ID 必须产出一条 test 或一项手动 QA 项；已覆盖的引用现有文件即可。

### 5.3 测试覆盖盲点（dev-plan 写本文档时识别）

| 未覆盖 ID | 现状 | 应补偿方式 |
|---|---|---|
| | | |

---

## §6 算法样例（若涉及纯函数）

> 纯函数（URL 校验、状态机转移函数、speed manager 等）使用样例表代替转移表：

```
ALG {函数名}:
  输入: <值>     → 期望: <值/副作用>      # 主流程
  输入: <边界>   → 期望: <边界结果>      # 边界
  输入: <异常>   → 期望: <错误/抛出>      # 异常
```

---

## §7 跨模块影响

> dev-plan 在做需求分析时**必须**列：修改本功能可能影响哪些其它 feature 的不变量。
> 若 §0 标了 `cross_module_impacts: [BRW, PLY]`，本节必须有对应行。

| 其它 feature | 影响点 | 影响条件 | 需要补的回归断言 |
|---|---|---|---|
| | | | |

---

## §8 平台特性与手动 QA

涉及以下任一项，`§0 manual_qa_required` 必须为 true，并产出 `docs/dev/mqa-{ID}.md`：
- `audio_service` / `audio_focus` / `background_service`
- 任何 `MethodChannel` 调用
- 通知栏、锁屏控件、后台播放
- 真机时序（网络抖动、快速连点、AudioService ↔ just_audio 边对齐）

若本功能**不涉及**，写：
> 本功能不涉及平台原生特性，全部可在 `flutter test` 中验证，无需手动 QA。

若涉及，必须列出手动 QA 步骤（每步骤可勾选）：
```
MAN-1: <场景描述与前置条件>
  步骤 1: ...
  步骤 2: ...
  期望: ...
  □ 已通过 / 实施人: ___ / 时间: ___
```

dev-exe 严禁在 manual_qa_required=true 且 mqa-{ID}.md 全部步骤未勾选的情况下标 `impl_status=done`。

---

## §9 dev-status.json 条目对照

```json
"{ID}": {
  "spec_file": "docs/features/{ID}.md",
  "spec_anchored_files": ["..."],
  "scenarios": ["{ID}-S1", ..., "{ID}-S{n}"],
  "invariants": ["{ID}-INV1", ..., "{ID}-INV{n}"],
  "algorithms":  ["{ID}-ALG1", ...],
  "test_files": ["..."],
  "test_coverage_gaps": [...],
  "cross_module_impacts": ["BRW", "PRG", "PLY"],
  "manual_qa_required": false,
  "manual_qa_file": null,
  "user_acceptance_text": "见 §1.2",
  "impl_status": "pending",
  "test_status": "pending",
  "check_status": "pending",
  "check_round": 0,
  "last_check_round_results": "",
  "last_checked_at": "",
  "dependencies": [],
  "retry_count": 0,
  "last_error": "",
  "last_updated": ""
}
```

字段生命周期：
- **dev-plan 创建**：`impl_status=test_status="pending"`，`check_status="pending"`，`check_round=0`
- **dev-exe 完成 7 步门禁**：`impl_status="done"`，`test_status="passed"`——不动 check_*
- **dev-check 通过**：`check_status="passed"`，写 `last_checked_at`
- **dev-check 打回**：`check_status="round_{N}"`，`check_round=N`，**并把 `impl_status` 改回 "pending"** 触发 dev-exe 重做
- **dev-exe 重做**：读取 `check_round` 决定带 dev-check 上轮问题清单作为修复靶点
- **dev-check 3 轮上限**：`check_status="blocked_after_3_rounds"`，`impl_status="blocked"`

---

## §10 与原 state.md / 历史文档对照（仅首份逆抽时写）

| 原文档 | 本份 {ID}.md | 变化点 |
|---|---|---|
| | | |