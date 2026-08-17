# BUG-14 — 验证请求 in-flight 期间改字段，过期结果覆盖 reset，保存门被绕过

## §0 头部元数据

```yaml
id: BUG-14
name: 验证请求 in-flight 期间改字段，过期结果覆盖 reset，保存门被绕过
priority: P1
status: active
created_at: 2026-08-16
last_updated: 2026-08-16
spec_anchored_files:
  - lib/features/connection/connection_provider.dart
  - lib/features/connection/connection_screen.dart
  - lib/features/connection/connection_edit_screen.dart
cross_module_impacts: [Connection]
parent_feature: Connection（连接管理模块）
manual_qa_required: false
```

---

## §1 用户视角

### 1.0 原始需求（用户原话逐字记录）

来源：`docs/cr/cr-20260816-0804-connection-playlist.md` F1（cr 复核 2026-08-16 已确认仍存在）：

> #### F1. 验证请求 in-flight 期间改字段，过期结果覆盖 reset，保存门被绕过
> - 类型 / 严重度 / 维度：FRAGILE / Major / 并发时序（stale 状态覆盖）
> - 证据：
>   - `lib/features/connection/connection_provider.dart:124-142` — `ConnectionValidatorNotifier.validate` 无请求版本号/字段快照：`state = ValidationLoading(); final result = await _client.validate(...); state = result.isSuccess ? Success() : Error(...)`
>   - `lib/features/connection/connection_screen.dart:151-155` — `_onFieldChanged` 仅 `validator.reset()`；`:103` 保存门 `(isValidated && !_isSaving)` 只看当前 state；表单字段在验证期间**不禁用**（只有按钮禁用 :86）
>   - `lib/features/connection/connection_edit_screen.dart:189-196`（reset）、`:279-291`（`_onSave` 复查 `validationState is! ValidationSuccess` 才拦截）
> - 复现路径（条件：验证 ≤5s 窗口内改字段）：添加页填 URL A → 点"测试连接"（Loading，请求 in-flight）→ 改 URL 为 B（onFieldChanged → reset → Idle）→ in-flight 请求（针对 A）返回成功 → `state = ValidationSuccess` → 保存按钮解锁 → 保存 B。期望：改字段后旧验证结果作废、保存必须重新验证（CON-01/CON-T28 语义）；实际：以对 A 的验证结果放行 B 的保存，未验证连接直接落库。编辑页同构（改 URL 后再动任意字段即触发）。
> - 自检答案：分支零覆盖——con_02 的 CON-T17 只测"Loading 中二次点击被忽略"（MockWebDavClient.hang 模式存在但从未与"字段变更 + 完成"组合）；无任何测试断言"reset 之后 in-flight 完成不得落地"。
> - 修复建议：validate 开始时捕获字段快照（或请求序号），完成时对比当前表单值/自增版本号，不一致则丢弃结果（或至少不置 Success）；补 hang + 改字段 + 完成 的三段式测试。

### 1.1 这一功能干什么（一句话）

给连接验证增加"过期结果丢弃"机制：字段在验证请求 in-flight 期间被修改（reset 触发）后，旧请求完成时不得覆盖状态，保证"保存"只能被针对**当前字段值**的验证结果解锁。

### 1.2 用户期望的场景

| ID | 你看到的样子 | 期望行为 |
|----|----|----|
| U1 | 填好连接 A 的信息，点"测试连接"，转圈等待时把地址改成 B | 修改字段后旧结果作废——A 的验证成功**不得**让"保存"按钮亮起；保存前必须重新验证（修复前：A 的结果返回后保存按钮解锁，B 未经验证就能保存） |
| U2 | 转圈时改字段，旧请求**失败** | 不弹出针对 A 的失败提示（页面保持"已改字段待验证"的干净状态） |
| U3 | 正常流程（填完 → 测试连接 → 成功后保存） | 行为完全不变：验证成功 → 保存解锁 |
| U4 | 编辑页（修改既有连接） | 与 U1 同构：改字段后旧验证结果同样作废，保存按钮按既有 canSave 规则保持禁用 |

---

## §2 已实现的功能骨架（代码锚点）

### 2.1 文件与分层

| 层 | 文件 | 行数 | 角色 |
|---|---|---|---|
| Provider | `lib/features/connection/connection_provider.dart` | 384 | `ConnectionValidatorNotifier`（:108-145）：validate 无条件覆盖 state（:118-142）；re-entry guard（:124）；reset（:144） |
| UI | `lib/features/connection/connection_screen.dart` | 304 | `_onFieldChanged` 只 reset（:151-155）；保存门 `(isValidated && !_isSaving)`（:103）；测试连接按钮只按 Loading 禁用（:86） |
| UI | `lib/features/connection/connection_edit_screen.dart` | 452 | `_onFieldChanged` 只 reset（:189-196）；`_onSave` 复查 `validationState is! ValidationSuccess`（:279-291） |
| 测试 | `test/features/connection/bug_bug14_repro_test.dart` | 本 spec §5.4 | 本 Bug 门禁 |

### 2.2 关键 Provider 表

| Provider 名 | 类型 | 实现位置 | 用途 |
|---|---|---|---|
| connectionValidatorProvider | StateNotifierProvider<ConnectionValidatorNotifier, ConnectionValidationState> | connection_provider.dart:147-151 | 验证状态机（Idle/Loading/Success/Error） |
| webDavClientProvider | Provider<WebDavClientInterface> | connection_provider.dart:28-29 | PROPFIND 验证（≤5s，P17 独立超时表） |

### 2.3 状态机图

```
Idle ──validate()──▶ Loading ──成功──▶ Success
 ▲                    │ 失败              │
 │◀─────reset()───────┴────────────────────┘
   （任何字段变更触发，两屏 onFieldChanged 均只调 reset）
   BUG: Loading 期间的 reset 不使 in-flight 请求失效——
        await 返回后无条件写 Success/Error（无版本判别）
```

---

## §3 行为规约（Given-When-Then）

### 3.1 现有行为（逆抽，缺陷态）

- **[BUG-14-S1]** validate 完成回调无条件覆盖 state，无请求版本/快照判别
  ```
  Given validate() 调用（state → Loading，请求 in-flight）
  When 请求返回
  Then state = result.isSuccess ? ValidationSuccess() : ValidationError(...)
       （不检查期间是否发生过 reset / 字段是否已变）
  ```
  Code evidence: `lib/features/connection/connection_provider.dart:118-142`（:124 仅 re-entry guard，:137-141 无条件落地）

- **[BUG-14-S2]** 字段变更只 reset，保存门只看当前 state，字段不禁用
  ```
  Given 验证请求 in-flight
  When 用户修改任一字段
  Then _onFieldChanged 仅 validator.reset()（state → Idle）
  And 表单字段仍可编辑（只有"测试连接/保存"按钮按 Loading/保存中禁用，
       connection_screen.dart:86/:103）
  And 保存门 (isValidated && !_isSaving) 只看当前 state（:103）——
      过期结果落地 Success 即解锁
  ```
  Code evidence: `lib/features/connection/connection_screen.dart:86/:103/:151-155`；`connection_edit_screen.dart:189-196/:279-291`

### 3.2 修复方案（status: new）

- **[BUG-14-S3]** 验证 epoch 机制：reset 使 in-flight 请求结果失效（status: new）
  ```
  Given validate() 调用（epoch=N，state → Loading）
  When 请求返回时 epoch 已 ≠ N（期间 reset() 或新 validate 已开始）
  Then 丢弃该结果：state 保持不变（Idle）
  When 请求返回时 epoch 仍 == N
  Then 照常落地 Success/Error（现有语义不变）
  否定断言:
    - reset 之后 in-flight 完成不得把 state 置为 ValidationSuccess
    - reset 之后 in-flight 完成不得把 state 置为 ValidationError
    - 保存门（connection_screen.dart:103）不得被过期结果解锁
    - 正常路径（无 reset）行为不变：Success 仍解锁保存
  ```
  **修改点**：`lib/features/connection/connection_provider.dart` `ConnectionValidatorNotifier`（:108-145）：
  ```dart
  // 新增字段（:110 附近）:
  int _validationEpoch = 0;

  // validate()（:118-142）修改，核心两处:
  Future<void> validate({...}) async {
    if (state is ValidationLoading) return; // re-entry guard 保持
    final epoch = ++_validationEpoch;       // ① 本次请求的 epoch
    state = const ValidationLoading();
    ...
    final result = await _client.validate(...);
    if (epoch != _validationEpoch) return;  // ② 过期结果丢弃（不落地）
    ...
  }

  // reset()（:144）修改:
  void reset() {
    _validationEpoch++;                     // 使所有 in-flight 请求失效
    state = const ValidationIdle();
  }
  ```
  模式依据（铁律 6）：StateNotifier 内自增 int 计数判过期是 Riverpod 官方文档推荐的 stale-result 防护模式（`provider_state` 文档 "discard stale results" 章节，Riverpod 2.x）；本项目 StateNotifier 已在用（connection_provider.dart:108），无新框架 API，不需要额外验证片段。

**边界裁决（弱模型照此实现，无需二次判断）**：

| 边界情况 | 裁决 |
|---|---|
| Loading 中再次 validate（未 reset） | re-entry guard（:124 `if (state is ValidationLoading) return`）照旧忽略，epoch 不变 |
| reset 后立刻再次 validate | 第二次 validate 取新 epoch；第一个请求完成时 epoch 不匹配 → 丢弃；第二个请求完成时匹配 → 落地。两个请求互不串扰 |
| 连续多次 reset（无 validate） | epoch 单调递增，无请求可落地，state 保持 Idle |
| 编辑页复用同一 provider 实例 | 添加页与编辑页共享 connectionValidatorProvider（riverpod 容器级）——切换页面时旧页 in-flight 请求因 epoch 失效被丢弃（行为正确：新页面自己的 validate 取新 epoch）；页面切换本身不调 reset，若旧请求恰好在新 validate 前完成且 epoch 相同 → 落地（可接受：页面级共享语义既有，不扩大改动面） |
| 保存门 | 不改 connection_screen.dart:103 / edit :279-291 的门逻辑（过期结果不再解锁，门自然生效） |
| hang 超时路径 | validate 请求本身 ≤5s 超时（webdav_client）——超时抛错走 catch？现有代码 validate 无 try/catch，超时异常上抛给调用方（screen `_onTestConnection` await）——本次修复不改该路径（越界，cr F1 未涉） |

---

## §4 不变量

- **[BUG-14-INV1]** 任意时刻 `connectionValidatorProvider` 的 state 只能由"当时最新一次 validate 调用的结果"写入（更早的调用结果一律丢弃）
  证据：修复后 connection_provider.dart:118-142 + `_validationEpoch` 机制；缺陷态证据 :137-141（无条件落地）

---

## §5 测试规约

### 5.1 现有测试清单

| 测试文件 | 覆盖的 Scenario / INV | 备注 |
|---|---|---|
| test/features/connection/con_02_test.dart（CON-T17） | Loading 中二次点击被忽略 | hang 模式存在但从未与"字段变更 + 完成"组合（自检答案） |

### 5.2 测试 ID 派生清单（dev-exe 派发测试 Agent 用）

```
BUG-14-S1, S2        # 缺陷态/现状锚定
BUG-14-S3            # 修复目标
BUG-14-INV1          # 不变量
```

dev-exe 要求：S3 由 §5.4 门禁测试覆盖（成功/失败两个分支已含）；S1/S2 由门禁测试驱动（缺陷态断言）。

### 5.3 测试覆盖盲点（dev-plan 写本文档时识别）

| 未覆盖 ID | 现状 | 应补偿方式 |
|---|---|---|
| 无 | — | — |

### 5.4 测试文件位置（spec-scan --gate 硬校验）

| 测试文件 | 覆盖 ID | 说明 |
|---|---|---|
| test/features/connection/bug_bug14_repro_test.dart | BUG-14-S3、BUG-14-INV1 | 门禁：修复前 FAIL（已用 repro-test.sh fail 确认，S1/S2 两条 hang+reset+complete 三段式）；dev-exe 修复后必须 PASS（repro-test.sh pass） |

---

## §6 算法样例

本 Bug 不涉纯函数算法（epoch 判别为两行状态逻辑，见 §3 修改点），跳过。

---

## §7 跨模块影响

`bash cross-imports.sh impact lib/features/connection/connection_provider.dart`（2026-08-16）→ 引用方：

| 其它 feature | 影响点 | 影响条件 | 需要补的回归断言 |
|---|---|---|---|
| Connection 添加页（connection_screen.dart:32/:151-155） | watch connectionValidatorProvider + onFieldChanged | 修复只改 notifier 内部（validate/reset），对外状态语义不变 | con_01 既有测试全绿（CON-T17 Loading 重入、成功解锁等） |
| Connection 编辑页（connection_edit_screen.dart:68/:189-196/:279-291） | 同上 | 同上 | con_05 / edit_screen_logic 既有测试全绿 |
| onboarding 启动验证（startupValidationProvider :165-209） | 不经 notifier（独立 FutureProvider） | 修复不改 startupValidation | 无 |
| con_02（CON-T17 hang 模式） | notifier 直接单测 | reset+complete 组合是新覆盖（本 Bug 补上） | con_02 既有测试全绿 |

---

## §8 平台特性与手动 QA

设计前已逐条核对 `docs/dev/platform-pitfalls.md`：触及 **P13/P14 同类并发时序**（async gap 中旧结果覆盖新状态）——本修复即在该模式上建立版本判别，已在 §3 显式处置。P17 分层表不涉及（不改任何超时数值）。

**真机风险列**：无。本功能不涉及平台原生特性，全部可在 `flutter test` 中验证（hang+reset+complete 三段式在 fake 上即可复现，无需真机网络）。

---

## §9 dev-status.json 条目对照

```json
"BUG-14": {
  "spec_file": "docs/features/BUG-14.md",
  "spec_anchored_files": ["lib/features/connection/connection_provider.dart", "lib/features/connection/connection_screen.dart", "lib/features/connection/connection_edit_screen.dart"],
  "scenarios": ["BUG-14-S1", "BUG-14-S2", "BUG-14-S3"],
  "invariants": ["BUG-14-INV1"],
  "algorithms": [],
  "manual_qa_required": false,
  "user_acceptance_text": "见 §1.2"
}
```
