# TEST-02 — 连接测试缺口（CON11+CON12+CON13）

> 来源：`docs/cr/cr-20260724-0110.md` CON11 (line 222-225) + CON12 (line 227-230) + CON13 (line 232-236)
> dev-plan 流程：TEST-GAP 模式（补测，不修改生产代码）

---

## §0 头部元数据

```yaml
id: TEST-02
name: 连接测试缺口（CON11+CON12+CON13）
priority: P1
status: draft
created_at: 2026-07-27
last_updated: 2026-07-27
spec_anchored_files:
  - lib/features/connection/connection_list_screen.dart
  - lib/features/connection/connection_edit_screen.dart
  - lib/features/connection/connection_provider.dart
  - lib/features/connection/domain/connection_validator.dart
cross_module_impacts: [CON, BRW]
parent_feature: Connection
manual_qa_required: false
```

---

## §1 用户视角

### 1.0 原始需求

> cr-20260724-0110.md CON11：`con_09_test.dart:74-88,203-222` 测试内手工清缓存再断言——删掉 `connection_list_screen.dart:79-80` 两行 invalidate 测试依然绿。"切换清浏览器缓存"（S13）实际无自动化守护。
> cr-20260724-0110.md CON12：零 widget 测试覆盖 ConnectionEditScreen。S10/S11/S12 屏幕级接线无人守护。
> cr-20260724-0110.md CON13：`con_01_test.dart:62-95,125-135` 测试内重定义局部 validateUrl 再断言（不 import 真函数）；TST-T124/125/145-147 构造字面量/本地状态机自我断言。

### 1.1 这一功能干什么（一句话）

补齐连接模块缺失的测试锚点，使切换清缓存、编辑页保存逻辑、URL 校验有真实自动化守护。

### 1.2 用户期望的场景

| ID | 你看到的样子 | 期望行为 |
|----|----|----|
| U1 | 切换到另一连接 | 浏览器目录缓存清空，展示新连接的根目录 |
| U2 | 编辑页只改名称，不改 URL | 直接保存，不需重新验证 |
| U3 | 编辑页改 URL，未验证就点保存 | 弹 SnackBar 提示"请先验证连接"，不调用 updater |
| U4 | 填写 URL | 真 validateUrl 被调用，拒绝非法 URL |

---

## §2 当前测试骨架

### 2.1 测试文件与覆盖

| 层 | 文件 | 行数 | 角色 | 现状 |
|---|---|---|---|---|
| 测试 | `test/features/connection/con_09_test.dart` | ~222 | 切换/删除连接 | **CON11**：自清缓存后断言，零守护 |
| 测试 | `test/features/connection/con_01_test.dart` | ~744 | URL 校验/保存流程 | **CON13**：重定义局部 validateUrl，空壳测试 |
| — | — | — | ConnectionEditScreen widget test | **CON12**：零覆盖 |

### 2.2 缺失的测试锚点

| 缺失行为 | 代码出处 | 当前测试状态 | 可逃逸的 mutation |
|---|---|---|---|
| 切换连接后清浏览器缓存 | `connection_list_screen.dart:79-80` | 零守护（CON11） | 删除 invalidate 两行测试全绿 |
| ConnectionEditScreen S10/S11/S12 | `connection_edit_screen.dart:262-278` | 零覆盖（CON12） | 删除 S12 门控测试全绿 |
| 真 validateUrl 调用 | `connection_validator.dart:17-42` | 测自定副本（CON13） | 改真函数逻辑测试全绿 |

---

## §3 测试补强规约

### 3.1 CON11 — 切换清浏览器缓存

- **[TEST-02-S1]** 切换连接后 directoryCacheProvider 状态变化（`status: new`）
  ```
  Given 当前活跃连接 A，浏览器已缓存目录 /music（directoryCacheProvider 非空）
  When  用户切换到连接 B
  Then  directoryCacheProvider 被清空（state 变为空 Map）
  否定断言:
    - 不在切换后残留旧缓存（应 invalidate directoryCacheProvider）
    - 不在切换后不清导航栈（应同时 invalidate navigationStackProvider）
    - 不改变切换前 directoryCacheProvider 的状态（仅在切换后清空）
  ```
  Code evidence: `lib/features/connection/connection_list_screen.dart:79-80`
  Mutation risk: 删除这两行 invalidate → 切换后仍展示旧缓存 → 测试当前全绿（零守护）
  Test anchoring: provider test — ProviderContainer，切换连接，断言 directoryCacheProvider 变空

- **[TEST-02-S2]** 切换连接后 navigationStackProvider 复位（`status: new`）
  ```
  Given 当前活跃连接 A，导航栈深度 3（A 深层路径）
  When  用户切换到连接 B
  Then  navigationStackProvider 复位为仅含根目录
  否定断言:
    - 不在切换后残留旧导航栈（应 invalidate navigationStackProvider）
    - 不在切换后不清目录缓存（应同时 invalidate directoryCacheProvider）
    - 不改变切换前的导航状态（仅在切换后复位）
  ```
  Code evidence: `lib/features/connection/connection_list_screen.dart:79-80`
  Test anchoring: provider test — 同上，断言 navigationStackProvider 复位

### 3.2 CON12 — ConnectionEditScreen widget test

- **[TEST-02-S3]** 编辑页只改名称直接保存（S10）（`status: new`）
  ```
  Given ConnectionEditScreen 已渲染，原始连接 name='NAS'，URL='http://nas.local'
  When  修改 name 为 'My NAS'，不改 URL
  And   点击"保存"
  Then  直接调用 connectionService.update()（不重新验证）
  And   导航回退到连接列表
  否定断言:
    - 不在只改名称时触发 validateConnection（应跳过验证）
    - 不在保存后不更新连接列表（应 invalidate connectionListProvider）
    - 不改变保存后的导航行为（应 pop 回列表页）
  ```
  Code evidence: `lib/features/connection/connection_edit_screen.dart:262-278`
  Test anchoring: widget test — pumpWidget(ConnectionEditScreen)，改名称，点保存，`verify(connectionService.update(...)).called(1)`

- **[TEST-02-S4]** 编辑页改 URL 未验证点保存弹 SnackBar（S12）（`status: new`）
  ```
  Given ConnectionEditScreen 已渲染，原始 URL='http://nas.local'
  When  修改 URL 为 'http://new-nas.local'
  And   不点"验证连接"，直接点"保存"
  Then  弹 SnackBar "请先验证连接"
  And   不调用 connectionService.update()
  否定断言:
    - 不在未验证时调用 update（应被 S12 门控拦截）
    - 不在点保存后不弹 SnackBar（应提示用户验证）
    - 不改变验证后保存的行为（验证通过后应正常保存）
  ```
  Code evidence: `lib/features/connection/connection_edit_screen.dart:269-274`（S12 门控）
  Test anchoring: widget test — 改 URL，点保存，`find.text('请先验证连接')`，`verifyNever(connectionService.update(...))`

- **[TEST-02-S5]** 编辑页首帧列表未解析时的捕获兜底（INV7）（`status: new`）
  ```
  Given ConnectionEditScreen 首帧时 connectionListProvider 未解析（loading）
  When  渲染编辑页
  And   数据到达后修改名称
  And   点保存
  Then  正确捕获原始配置，直接保存（不重新验证）
  否定断言:
    - 不在首帧未解析时强解包 _originalConfig 抛异常（应等数据到达后捕获）
    - 不在数据到达后不捕获原始配置（应补捕获）
    - 不改变首帧已解析时的行为（应正常捕获）
  ```
  Code evidence: `lib/features/connection/connection_edit_screen.dart:43-57`（_originalConfig 捕获）
  Test anchoring: widget test — 延迟解析 connectionListProvider，渲染编辑页，断言不崩溃

### 3.3 CON13 — 真函数调用

- **[TEST-02-S6]** 真 validateUrl 被调用（CON-T01~T03/T07）（`status: new`）
  ```
  Given ConnectionScreen 已渲染
  When  输入 URL 'http://admin:pass@nas.local'（含 userInfo）
  And   点击"测试连接"
  Then  真 validateUrl 被调用，返回错误"URL 不应包含用户名密码"
  And   不调用 webDavClient.validateConnection()
  否定断言:
    - 不在 URL 含 userInfo 时调用 validateConnection（应被校验拦截）
    - 不在校验失败时不展示错误文案（应展示具体错误）
    - 不改变合法 URL 的校验行为（应正常通过）
  ```
  Code evidence: `lib/features/connection/domain/connection_validator.dart:17-42`（validateUrl）
  Test anchoring: widget test — pumpWidget(ConnectionScreen)，输入非法 URL，点测试，断言错误文案

- **[TEST-02-S7]** 删除 TST-T124/125/145-147 自证自答测试（`status: new`）
  ```
  Given 现有测试 con_01_test.dart:636-744 包含字面量/本地状态机断言
  When  审查测试覆盖
  Then  删除或改写为真实 widget 树断言
  否定断言:
    - 不在测试中重定义局部函数再断言（应调真函数）
    - 不在测试中构造字面量自我断言（应测试真实行为）
    - 不改变测试的覆盖范围（应守护相同的生产代码路径）
  ```
  Code evidence: `test/features/connection/con_01_test.dart:636-744`（字面量空壳）
  Test anchoring: 删除或改写为 widget test

---

## §4 不变量

- **[TEST-02-INV1]** 切换连接后浏览器状态（缓存+导航栈）被清空
  证据：TEST-02-S1/S2 守护

- **[TEST-02-INV2]** ConnectionEditScreen 屏幕级行为有 widget test 守护
  证据：TEST-02-S3~S5 覆盖 S10/S11/S12/INV7

- **[TEST-02-INV3]** 所有校验测试调用真 validateUrl，非本地副本
  证据：TEST-02-S6/S7 守护

---

## §5 测试规约

### 5.1 现有测试清单

| 测试文件 | 覆盖 | 备注 |
|---|---|---|
| `con_09_test.dart` | 切换/删除（空壳） | **CON11**：自清缓存后断言，需重写 |
| `con_01_test.dart` | URL 校验/保存（空壳） | **CON13**：重定义局部函数，需改写 |
| — | ConnectionEditScreen | **CON12**：零覆盖，需新增 |

### 5.2 测试 ID 派生清单

```
TEST-02-S1~S2     # CON11 切换清缓存
TEST-02-S3~S5     # CON12 ConnectionEditScreen
TEST-02-S6~S7     # CON13 真函数调用
TEST-02-INV1~INV3 # 不变量守护
```

### 5.3 测试覆盖盲点

| 未覆盖 ID | 现状 | 应补偿方式 |
|---|---|---|
| TEST-02-S1/S2 | 切换清缓存零守护 | provider test：切换连接，断言 cache/stack 清空 |
| TEST-02-S3~S5 | ConnectionEditScreen 零覆盖 | widget test：覆盖 S10/S11/S12/INV7 |
| TEST-02-S6 | 真 validateUrl 零调用 | widget test：输入非法 URL，断言错误文案 |
| TEST-02-S7 | 字面量空壳测试 | 删除或改写为 widget test |

### 5.4 测试文件位置

| 测试 ID | 文件路径 | 类型 |
|---|---|---|
| TEST-02-S1~S2 | `test/features/connection/test_02_con11_test.dart` | provider test |
| TEST-02-S3~S5 | `test/features/connection/test_02_con12_test.dart` | widget test |
| TEST-02-S6~S7 | `test/features/connection/test_02_con13_test.dart` | widget test（改写 con_01） |
| TEST-02-INV1~INV3 | 同上分散 | — |

---

## §6 算法样例

不适用——本 spec 为测试补强，无新算法。

---

## §7 跨模块影响

| 其它 feature | 影响点 | 需要补的回归断言 |
|---|---|---|
| BRW | directoryCacheProvider 被切换清空 | 现有 browser test 可能需更新 mock |
| CON | `connection_list_screen.dart` invalidate 逻辑 | 现有 con_09_test 需重写 |
| CON | `connection_edit_screen.dart` 保存逻辑 | 新增 widget test |

---

## §8 平台特性与手动 QA

本 spec 不涉及平台原生特性，全部可在 `flutter test` 中验证。

---

## §9 dev-status.json 条目对照

见统一更新：`docs/dev/dev-status.json`。

---

## §10 changelog

- 2026-07-27: 创建 TEST-02 spec（基于 cr-20260724-0110.md CON11+CON12+CON13）
