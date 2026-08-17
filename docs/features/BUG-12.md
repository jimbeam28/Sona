# BUG-12 — validateBasePath 是死代码，基础路径字段从未接入表单校验

## §0 头部元数据

```yaml
id: BUG-12
name: validateBasePath 是死代码，基础路径字段从未接入表单校验
priority: P2
status: active
created_at: 2026-08-16
last_updated: 2026-08-16
spec_anchored_files:
  - lib/features/connection/widgets/connection_form.dart
  - lib/features/connection/domain/connection_validator.dart
cross_module_impacts: [Connection]
parent_feature: Connection（连接管理模块）
manual_qa_required: false
```

---

## §1 用户视角

### 1.0 原始需求（用户原话逐字记录）

来源：`docs/cr/cr-20260816-0804-connection-playlist.md` B2（cr 复核 2026-08-16 已确认仍存在）：

> #### B2. validateBasePath 是死代码——基础路径校验器从未接入表单
> - 类型 / 严重度 / 维度：BUG / Minor / 正确性（校验门形同虚设）
> - 证据：
>   - `lib/features/connection/widgets/connection_form.dart:224-234` — 基础路径 TextFormField **无 `validator` 属性**（对比 url 字段 :161、用户名 :175、密码 :200-205 均有）
>   - `lib/features/connection/domain/connection_validator.dart:58-76` — `validateBasePath` 声明的规则（"必须以 / 开头"、"不能包含 .."）与 `BasePathResult` 在 lib/ 下**零调用**（grep 全 lib 仅定义处；调用方只有测试 `test/features/connection/ref_21_test.dart:95-137` 与 `test_02_con13_test.dart:264-268`）
> - 复现路径：添加连接页 → 基础路径输入 `x`（无前导 /）或 `/dav/../etc`（含 ..）→ 测试连接（表单校验通过，字段无 validator）→ PROPFIND 到拼接路径（`webdav_paths.dart:44-57` 的 segment() 静默补 /，`..` 由服务器归一）→ 若返回 207 → 保存按钮解锁 → 带 `..`/无斜杠的 basePath 持久化。期望：保存前出现"基础路径必须以 / 开头"/"基础路径不能包含 .."的内联错误；实际：直接保存成功。
> - 自检答案：测试假设本身就错——ref_21/test_02_con13 直接对函数做单测（覆盖率 100% 造成"已守护"假信号），从未经表单/保存链路断言该字段的校验器存在；没有任何 widget 测试在基础路径输入非法值后断言错误文案。
> - 修复建议：给 `_basePathController` 字段接 `validator: validateBasePath`（注意其返回值是 BasePathResult 需适配），并补"非法值 → 错误文案 + 保存禁用"的 widget 级正反断言；或删除死代码并裁决 `..` 是否可接受。

### 1.1 这一功能干什么（一句话）

把基础路径字段的校验规则（必须以 `/` 开头、不能包含 `..`）真正接入添加/编辑连接表单，非法值在"测试连接/保存"前以内联错误拦截，杜绝带 `..` 或畸形路径的 basePath 持久化。

### 1.2 用户期望的场景

| ID | 你看到的样子 | 期望行为 |
|----|----|----|
| U1 | 在添加连接页的基础路径栏输入 `dav`（没写开头的斜杠） | 点"测试连接"时这一栏下面立刻出现红字"基础路径必须以 / 开头"，请求不发出去（修复前：校验直接通过，请求照发） |
| U2 | 在基础路径栏输入 `/dav/../etc` | 点"测试连接"时出现红字"基础路径不能包含 .."，请求不发出去（修复前：校验通过，带 .. 的路径被保存） |
| U3 | 基础路径栏留空 | 一切照旧——空值按 `/` 处理，不报错（基础路径本来就是选填） |
| U4 | 基础路径栏输入合法值如 `/dav` | 不出现任何错误提示，测试连接照常发起 |

---

## §2 已实现的功能骨架（代码锚点）

### 2.1 文件与分层

| 层 | 文件 | 行数 | 角色 |
|---|---|---|---|
| UI | `lib/features/connection/widgets/connection_form.dart` | 239 | 表单：url 字段 validator（:161）、用户名（:175）、密码（:200-205）、基础路径字段**无 validator**（:224-234） |
| Domain | `lib/features/connection/domain/connection_validator.dart` | 138 | `validateBasePath`（:58-76）返回 `BasePathResult`（:125-137）；lib/ 零调用（仅测试直接单测） |
| 消费方 | `lib/features/connection/connection_screen.dart` / `connection_edit_screen.dart` | 304/452 | `ConnectionForm` 两个消费方；`_onTestConnection` 先 `_formController.validate()`（screen:159） |
| 测试 | `test/features/connection/bug_bug12_repro_test.dart` | 本 spec §5.4 | 本 Bug 门禁 |

### 2.2 关键 Provider 表

| Provider 名 | 类型 | 实现位置 | 用途 |
|---|---|---|---|
| webDavClientProvider | Provider<WebDavClientInterface> | connection_provider.dart:28-29 | 测试连接 PROPFIND（repro 用 MockWebDavClient 覆写） |

### 2.3 状态机图

本 Bug 不涉状态机，跳过。

---

## §3 行为规约（Given-When-Then）

### 3.1 现有行为（逆抽，缺陷态）

- **[BUG-12-S1]** 基础路径 TextFormField 无 validator，表单校验对非法值放行
  ```
  Given ConnectionForm 渲染（添加/编辑页）
  When 用户在基础路径字段输入无前导 / 或含 .. 的值，点"测试连接"
  Then _formController.validate() 仅校验 url/用户名/密码三字段
       （connection_form.dart:161/:175/:200-205）
  And 基础路径字段（:224-234）无 validator → 不产生任何内联错误
  And 请求照常发出（screen:159-168 校验通过后调 validator.validate）
  ```
  Code evidence: `lib/features/connection/widgets/connection_form.dart:224-234`（无 validator 属性）；`connection_form.dart:35`（`validate()` 委托 FormState.validate）

- **[BUG-12-S2]** `validateBasePath` / `BasePathResult` 在 lib/ 下零调用
  ```
  Given validateBasePath 声明规则："空值默认 /"（:60-62）、"必须以 / 开头"（:63-68）、
        "不能包含 .."（:69-74）
  When 用户输入非法 basePath 走完整表单链路
  Then 该函数从不执行（grep lib/ 仅定义处，零调用方）
  ```
  Code evidence: `lib/features/connection/domain/connection_validator.dart:58-76`；grep 全 lib（2026-08-16 核实）；调用方仅测试 `test/features/connection/ref_21_test.dart:95-137`、`test_02_con13_test.dart:264-268`

### 3.2 修复方案（status: new）

- **[BUG-12-S3]** 基础路径字段接入 validator（status: new）
  ```
  Given ConnectionForm 渲染
  When 用户输入非法 basePath（无前导 / 或含 ..）并点"测试连接"
  Then 表单校验显示内联错误（"基础路径必须以 / 开头" / "基础路径不能包含 .."）
  And validate() 返回 false → _onTestConnection 提前 return（screen:159）→
      不发起 WebDAV 请求
  否定断言:
    - 非法 basePath 时不得发起 validate PROPFIND 请求（mock 的 validate 调用数 0）
    - 非法 basePath 时不得出现 ValidationSuccess / ValidationLoading 状态变化
    - 合法值（空、'/'、'/dav'）不产生错误文案（正反两条）
  ```
  **修改点（唯一生产代码改动）**：`lib/features/connection/widgets/connection_form.dart:224-234` 基础路径 TextFormField 增加 `validator`（返回 `String?`，与 url/用户名/密码字段同型）：
  ```dart
  // 修改前（224-234 行）:
  TextFormField(
    controller: _basePathController,
    decoration: const InputDecoration(
      labelText: '基础路径（选填）',
      hintText: '/',
      prefixIcon: Icon(Icons.folder_outlined),
      border: OutlineInputBorder(),
    ),
    textInputAction: TextInputAction.done,
    autocorrect: false,
  ),
  // 修改后:
  TextFormField(
    controller: _basePathController,
    decoration: const InputDecoration(
      labelText: '基础路径（选填）',
      hintText: '/',
      prefixIcon: Icon(Icons.folder_outlined),
      border: OutlineInputBorder(),
    ),
    textInputAction: TextInputAction.done,
    autocorrect: false,
    validator: (v) => validateBasePath(v).error,
  ),
  ```
  `validateBasePath` 已 import（connection_form.dart:8）；其返回 `BasePathResult`，`.error` 为 `String?`，空值/合法值返回 null（不报错）——适配即为取 `.error` 字段。

**边界裁决（弱模型照此实现，无需二次判断）**：

| 边界情况 | 输入 | 裁决 |
|---|---|---|
| 空 / 纯空白 | `''`、`'   '` | 不报错（BasePathResult(normalised: '/')，error=null）——基础路径选填语义保持 |
| 合法绝对路径 | `'/'`、`'/dav'`、`'/music/01'` | 不报错（error=null） |
| 无前导 / | `'dav'`、`'music/01'` | 报"基础路径必须以 / 开头" |
| 含 .. | `'/dav/../etc'`、`'../x'`（先触发无 / 错误）、`'/a/b..c'` | 含 `..` 子串即报"基础路径不能包含 .."（validateBasePath 用 `contains('..')` 判定，connection_validator.dart:69；注意 `/a/b..c` 因含 `..` 子串同样拦截——保持现有函数语义，不修改 validateBasePath） |
| 仅含空格前缀的合法路径 | `' /dav'` | trim 后为 `/dav` → 不报错（函数已 trim，:59） |
| 编辑页初始值 | 既有连接的合法 basePath | 渲染时不触发校验（validator 只在 validate() 调用时执行），无副作用 |
| `_formController.basePath` getter | 空→'/' | 与 validator 语义一致（form:30-33），不改 |

---

## §4 不变量

- **[BUG-12-INV1]** `validateBasePath` 不得被修改（其规则与返回类型是既有测试 ref_21_test.dart:95-137、test_02_con13_test.dart:264-268 的锚点），修复只接线不重写
  证据：`lib/features/connection/domain/connection_validator.dart:58-76`；既有单测锚定（ref_21/test_02_con13）

---

## §5 测试规约

### 5.1 现有测试清单

| 测试文件 | 覆盖的 Scenario / INV | 备注 |
|---|---|---|
| test/features/connection/ref_21_test.dart:95-137 | validateBasePath 纯函数 | 直接单测，100% 覆盖率是死代码假信号（自检答案） |
| test/features/connection/test_02_con13_test.dart:264-268 | 同上 | 同上 |

### 5.2 测试 ID 派生清单（dev-exe 派发测试 Agent 用）

```
BUG-12-S1, S2        # 缺陷态/现状锚定
BUG-12-S3            # 修复目标
BUG-12-INV1          # 不变量
```

dev-exe 要求：S3 由 §5.4 门禁测试覆盖（正反两条已含）；S1/S2 由门禁测试驱动（缺陷态断言）与既有纯函数测试锚定；INV1 由 ref_21/test_02_con13 既有测试锚定（不得改动）。

### 5.3 测试覆盖盲点（dev-plan 写本文档时识别）

| 未覆盖 ID | 现状 | 应补偿方式 |
|---|---|---|
| 无 | — | — |

### 5.4 测试文件位置（spec-scan --gate 硬校验）

| 测试文件 | 覆盖 ID | 说明 |
|---|---|---|
| test/features/connection/bug_bug12_repro_test.dart | BUG-12-S3 | 门禁：修复前 FAIL（已用 repro-test.sh fail 确认）；dev-exe 修复后必须 PASS（repro-test.sh pass） |

---

## §6 算法样例

本 Bug 不涉新增算法（validateBasePath 既有函数不改，样例见 §3 边界裁决表）。

---

## §7 跨模块影响

`bash cross-imports.sh impact lib/features/connection/widgets/connection_form.dart lib/features/connection/domain/connection_validator.dart`（2026-08-16）→ 引用方：

| 其它 feature | 影响点 | 影响条件 | 需要补的回归断言 |
|---|---|---|---|
| Connection 添加页（connection_screen.dart:73-76/157-168） | 消费 ConnectionForm + `_formController.validate()` | validator 接线后非法 basePath 在测试连接前被拦 | con_01 既有 widget 测试全绿（其填入的均为合法 basePath 或不填） |
| Connection 编辑页（connection_edit_screen.dart:119-127/235-268） | 同上 | 同上；既有连接 basePath 均合法 → 编辑保存不受影响 | con_05/edit_screen_logic 既有测试全绿 |
| ref_21 / test_02_con13 纯函数测试 | validateBasePath 直接单测 | 函数本体不改 | 保持全绿（INV1） |

---

## §8 平台特性与手动 QA

设计前已逐条核对 `docs/dev/platform-pitfalls.md`：本 Bug 为表单校验接线，不触及任何踩坑条目。

**真机风险列**：无。本功能不涉及平台原生特性（无 audio_service / MethodChannel / 通知栏 / 真机时序），全部可在 `flutter test` 中验证。

---

## §9 dev-status.json 条目对照

```json
"BUG-12": {
  "spec_file": "docs/features/BUG-12.md",
  "spec_anchored_files": ["lib/features/connection/widgets/connection_form.dart", "lib/features/connection/domain/connection_validator.dart"],
  "scenarios": ["BUG-12-S1", "BUG-12-S2", "BUG-12-S3"],
  "invariants": ["BUG-12-INV1"],
  "algorithms": [],
  "manual_qa_required": false,
  "user_acceptance_text": "见 §1.2"
}
```
