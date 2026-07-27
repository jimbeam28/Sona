# TEST-03 — 主页测试缺口（HOME2+HOME3+HOME4）

> 来源：`docs/cr/cr-20260724-0110.md` HOME2 (line 258-261) + HOME3 (line 263-266) + HOME4 (line 268-271)
> dev-plan 流程：TEST-GAP 模式（补测，不修改生产代码）

---

## §0 头部元数据

```yaml
id: TEST-03
name: 主页测试缺口（HOME2+HOME3+HOME4）
priority: P1
status: draft
created_at: 2026-07-27
last_updated: 2026-07-27
spec_anchored_files:
  - lib/features/home/home_screen.dart
  - lib/features/onboarding/onboarding.dart
cross_module_impacts: [BRW, PLY]
parent_feature: Home
manual_qa_required: true
```

---

## §1 用户视角

### 1.0 原始需求

> cr-20260724-0110.md HOME2：`home_screen_test.dart:24-39` 本地重实现 onPopInvokedWithResult 闭包并断言，全程未 pumpWidget(HomeScreen)；删除 PopScope 或改 canPop=true 或删除 moveTaskToBack() 测试仍全绿。返回键退后台是音频播放器关键用户行为，"看似有测"实则零防护。
> cr-20260724-0110.md HOME3：`home_screen.dart:34-46` savedIndex 越界判定与写回监听器无用例覆盖；把 `< 2` 改成 `< 1` 或删写回监听器测试不红。
> cr-20260724-0110.md HOME4：`onboarding.dart:40-47` error 分支 → /connection；ONB-03 只覆盖 data 分支的 authError，把 error 分支重定向改成 /browser 测试全绿。

### 1.1 这一功能干什么（一句话）

补齐主页模块缺失的测试锚点，使系统返回退后台、Tab 持久化、onboarding 异常分支有真实自动化守护。

### 1.2 用户期望的场景

| ID | 你看到的样子 | 期望行为 |
|----|----|----|
| U1 | 在主页按系统返回键 | 不退出 app，退到后台继续播放（PopScope canPop=false + moveTaskToBack） |
| U2 | 切到文件浏览 Tab，退出 app，重启 | 恢复到文件浏览 Tab（Tab 索引持久化） |
| U3 | 启动时 startupValidation 失败（网络错误） | 跳转到连接页（/connection），非主页 |

---

## §2 当前测试骨架

### 2.1 测试文件与覆盖

| 层 | 文件 | 行数 | 角色 | 现状 |
|---|---|---|---|---|
| 测试 | `test/features/home/home_screen_test.dart` | ~39 | PopScope/返回键 | **HOME2**：本地重实现闭包，未 pumpWidget(HomeScreen) |
| — | — | — | Tab 持久化 | **HOME3**：零覆盖 |
| 测试 | `test/features/onboarding/` | — | 启动引导 | **HOME4**：只覆盖 authError，error 分支零覆盖 |

### 2.2 缺失的测试锚点

| 缺失行为 | 代码出处 | 当前测试状态 | 可逃逸的 mutation |
|---|---|---|---|
| PopScope canPop=false + moveTaskToBack | `home_screen.dart:83-99` | 零守护（HOME2） | 删除 PopScope 测试全绿 |
| Tab 索引持久化（恢复+写回） | `home_screen.dart:34-46` | 零覆盖（HOME3） | 删写回监听器测试全绿 |
| onboarding startupValidation error 分支 | `onboarding.dart:40-47` | 零覆盖（HOME4） | 改 error 重定向为 /browser 测试全绿 |

---

## §3 测试补强规约

### 3.1 HOME2 — PopScope + moveTaskToBack

- **[TEST-03-S1]** 真实 HomeScreen 的 PopScope 接线（`status: new`）
  ```
  Given pumpWidget(HomeScreen) with mock MethodChannel
  When  模拟系统返回键（tester.pageBack() 或 Navigator.maybePop）
  Then  PopScope canPop=false 阻止路由 pop
  And   moveTaskToBack() 被调用（MethodChannel 'moveTaskToBack' invoked）
  否定断言:
    - 不在 pop 后退出路由（应被 PopScope 拦截）
    - 不在拦截后不调用 moveTaskToBack（应退到后台）
    - 不改变非系统返回的导航行为（如 AppBar 返回按钮应正常 pop）
  ```
  Code evidence: `lib/features/home/home_screen.dart:83-99`（PopScope + onPopInvokedWithResult）
  Mutation risk: 删除 PopScope 或改 canPop=true → 返回键退出 app → 测试当前全绿（零守护）
  Test anchoring: widget test — pumpWidget(HomeScreen)，模拟返回，verify MethodChannel invoke

- **[TEST-03-S2]** 非 Android 平台 PopScope 行为（`status: new`）
  ```
  Given pumpWidget(HomeScreen) on non-Android platform（如 test 环境）
  When  模拟系统返回键
  Then  PopScope canPop=false 仍拦截
  And   moveTaskToBack() 不抛异常（非 Android 为 no-op）
  否定断言:
    - 不在非 Android 平台抛异常（moveTaskToBack 应 graceful no-op）
    - 不在非 Android 平台不拦截返回（仍应 canPop=false）
    - 不改变 Android 平台的行为
  ```
  Code evidence: `lib/core/services/background_service.dart:9-10`（非 Android no-op）
  Test anchoring: widget test — 同上，断言无异常

### 3.2 HOME3 — Tab 索引持久化

- **[TEST-03-S3]** 预置 index=1 启动落浏览器 Tab（`status: new`）
  ```
  Given SharedPreferences 预置 'home_tab_index' = 1
  When  pumpWidget(HomeScreen)
  Then  默认选中 Tab 1（文件浏览）
  And   TabBarView 展示 BrowserScreen
  否定断言:
    - 不在预置 index=1 时默认选 Tab 0（应恢复到 Tab 1）
    - 不在启动时不写回 index（应恢复而非重置）
    - 不改变预置 index=0 时的行为（应选 Tab 0）
  ```
  Code evidence: `lib/features/home/home_screen.dart:34-40`（savedIndex 恢复）
  Test anchoring: widget test — 内存 SharedPreferences，pump HomeScreen，断言 TabController.index=1

- **[TEST-03-S4]** 切 Tab 后 prefs 已写入（`status: new`）
  ```
  Given pumpWidget(HomeScreen)，初始 Tab 0
  When  切换到 Tab 1（文件浏览）
  Then  SharedPreferences 'home_tab_index' = 1
  否定断言:
    - 不在切换后不写回 prefs（应持久化）
    - 不在切换回 Tab 0 后不写回（应每次切换都持久化）
    - 不改变不切换时的 prefs 值（应保持初始值）
  ```
  Code evidence: `lib/features/home/home_screen.dart:42-46`（写回监听器）
  Mutation risk: 删写回监听器 → Tab 不持久化 → 测试当前全绿（零守护）
  Test anchoring: widget test — 切 Tab，断言 prefs 写入

- **[TEST-03-S5]** savedIndex 越界判定（`status: new`）
  ```
  Given SharedPreferences 预置 'home_tab_index' = 5（越界，只有 2 个 Tab）
  When  pumpWidget(HomeScreen)
  Then  默认选中 Tab 0（越界回落）
  否定断言:
    - 不在越界时选 Tab 5（应回落到 0）
    - 不在越界时抛异常（应 graceful 回落）
    - 不改变合法 index 的行为
  ```
  Code evidence: `lib/features/home/home_screen.dart:34-40`（savedIndex 越界判定）
  Test anchoring: widget test — 预置越界 index，pump，断言 Tab 0

### 3.3 HOME4 — onboarding error 分支

- **[TEST-03-S6]** startupValidation 抛异常→路由到 /connection（`status: new`）
  ```
  Given startupValidationProvider.overrideWith((ref) async => throw Exception('network'))
  When  pump MaterialApp with onboarding route
  Then  路由跳转到 /connection（非 /browser）
  否定断言:
    - 不在抛异常时路由到 /browser（应到 /connection）
    - 不在抛异常时不跳转（应 redirect）
    - 不改变 authError 分支的行为（也应到 /connection）
  ```
  Code evidence: `lib/features/onboarding/onboarding.dart:40-47`（error 分支 → /connection）
  Mutation risk: 改 error 重定向为 /browser → 测试当前全绿（零守护）
  Test anchoring: widget test — override provider，pump onboarding，断言路由

- **[TEST-03-S7]** startupValidation authError→路由到 /connection（`status: new`）
  ```
  Given startupValidationProvider.overrideWith((ref) async => WebDavValidationResult.authError())
  When  pump MaterialApp with onboarding route
  Then  路由跳转到 /connection
  否定断言:
    - 不在 authError 时路由到 /browser（应到 /connection）
    - 不在 authError 时不跳转（应 redirect）
    - 不改变成功分支的行为（应到 /browser）
  ```
  Code evidence: `lib/features/onboarding/onboarding.dart:40-47`（authError 分支）
  Test anchoring: widget test — 同 ONB-03，确认已覆盖

---

## §4 不变量

- **[TEST-03-INV1]** 主页 PopScope canPop=false 且系统返回触发 moveTaskToBack
  证据：TEST-03-S1/S2 守护

- **[TEST-03-INV2]** Tab 索引持久化：启动恢复 + 切换写回
  证据：TEST-03-S3~S5 守护

- **[TEST-03-INV3]** onboarding startupValidation 失败（error/authError）→ /connection
  证据：TEST-03-S6/S7 守护

---

## §5 测试规约

### 5.1 现有测试清单

| 测试文件 | 覆盖 | 备注 |
|---|---|---|
| `home_screen_test.dart` | PopScope（空壳） | **HOME2**：本地重实现闭包，需重写 |
| — | Tab 持久化 | **HOME3**：零覆盖，需新增 |
| onboarding 测试 | authError 分支 | **HOME4**：error 分支零覆盖，需补 |

### 5.2 测试 ID 派生清单

```
TEST-03-S1~S2     # HOME2 PopScope + moveTaskToBack
TEST-03-S3~S5     # HOME3 Tab 持久化
TEST-03-S6~S7     # HOME4 onboarding error 分支
TEST-03-INV1~INV3 # 不变量守护
```

### 5.3 测试覆盖盲点

| 未覆盖 ID | 现状 | 应补偿方式 |
|---|---|---|
| TEST-03-S1/S2 | PopScope 零守护 | widget test：pumpWidget(HomeScreen)，模拟返回 |
| TEST-03-S3~S5 | Tab 持久化零覆盖 | widget test：内存 SharedPreferences，验证恢复+写回 |
| TEST-03-S6 | onboarding error 分支零覆盖 | widget test：override provider 抛异常 |
| TEST-03-S7 | onboarding authError 分支 | 确认现有 ONB-03 已覆盖 |

### 5.4 测试文件位置

| 测试 ID | 文件路径 | 类型 |
|---|---|---|
| TEST-03-S1~S2 | `test/features/home/test_03_home2_test.dart` | widget test |
| TEST-03-S3~S5 | `test/features/home/test_03_home3_test.dart` | widget test |
| TEST-03-S6~S7 | `test/features/home/test_03_home4_test.dart` | widget test |
| TEST-03-INV1~INV3 | 同上分散 | — |

---

## §6 算法样例

不适用——本 spec 为测试补强，无新算法。

---

## §7 跨模块影响

| 其它 feature | 影响点 | 需要补的回归断言 |
|---|---|---|
| BRW | Tab 1 默认展示 BrowserScreen | 现有 browser test 可能需更新 mock |
| PLY | Tab 0 默认展示 PlaylistScreen | 现有 playlist test 可能需更新 mock |
| CON | onboarding error 分支跳转 /connection | 现有 connection test 可能需更新 |

---

## §8 平台特性与手动 QA

| 风险 | 近似测试方案 | 测不了 → 进 mqa-backlog |
|---|---|---|
| Android 真机 moveTaskToBack 行为 | mock MethodChannel | 真机验证：返回键是否真的退到后台而非退出 app |
| 后台播放是否继续 | mock audio_service | 真机验证：退后台后音频是否继续播放 |

---

## §9 dev-status.json 条目对照

见统一更新：`docs/dev/dev-status.json`。

---

## §10 changelog

- 2026-07-27: 创建 TEST-03 spec（基于 cr-20260724-0110.md HOME2+HOME3+HOME4）
