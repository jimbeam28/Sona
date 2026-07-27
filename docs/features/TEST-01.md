# TEST-01 — 浏览器测试缺口（BRW9+BRW10+BRW11）

> 来源：`docs/cr/cr-20260724-0110.md` BRW9 (line 121-124) + BRW10 (line 126-129) + BRW11 (line 131-135)
> dev-plan 流程：TEST-GAP 模式（补测，不修改生产代码）

---

## §0 头部元数据

```yaml
id: TEST-01
name: 浏览器测试缺口（BRW9+BRW10+BRW11）
priority: P1
status: draft
created_at: 2026-07-27
last_updated: 2026-07-27
spec_anchored_files:
  - lib/features/browser/browser_screen.dart
  - lib/features/browser/browser_provider.dart
cross_module_impacts: [BRW]
parent_feature: Browser
manual_qa_required: false
```

---

## §1 用户视角

### 1.0 原始需求

> cr-20260724-0110.md BRW9：`brw_04_test.dart:247-264` 断言测试内自定义常量，不触碰任何被测代码；长按分支 `if (progress == null) return;`（browser_screen.dart:145-146）零守护（反转该条件测试全绿）。
> cr-20260724-0110.md BRW10：`brw_07_test.dart:353-383` 标题为 batch query 实际只调 `dao.find`，从未调用该 provider；无"点击带进度文件→弹对话框"widget 测试。
> cr-20260724-0110.md BRW11：`brw_09_test.dart:29-45,93,119,220` pump 前定死 playing；INV4 用例名为"无 race"实为连点计数。

### 1.1 这一功能干什么（一句话）

补齐浏览器模块缺失的测试锚点，使关键用户交互（长按菜单、进度恢复对话框、播放态图标启用）有真实自动化守护。

### 1.2 用户期望的场景

| ID | 你看到的样子 | 期望行为 |
|----|----|----|
| U1 | 长按文件，弹出菜单 | 菜单内容正确反映进度存在与否（有进度→显示"删除进度"，无进度→无菜单或不同选项） |
| U2 | 点击带进度的文件 | 弹出进度恢复对话框（"从 1:23 继续播放"） |
| U3 | 播放状态变化（playing ↔ paused） | 播放/暂停图标 onPressed 态同步响应 |

---

## §2 当前测试骨架

### 2.1 测试文件与覆盖

| 层 | 文件 | 行数 | 角色 | 现状 |
|---|---|---|---|---|
| 测试 | `test/features/browser/brw_04_test.dart` | ~264 | 进度菜单交互 | **BRW9**：断言自定常量，不触碰生产代码 |
| 测试 | `test/features/browser/brw_07_test.dart` | ~383 | 批量查询 | **BRW10**：只调 `dao.find`，未调 `loadProgressForDirectoryProvider` |
| 测试 | `test/features/browser/brw_09_test.dart` | ~220 | 播放态图标 | **BRW11**：playing 静态打桩，无响应性测试 |

### 2.2 缺失的测试锚点

| 缺失行为 | 代码出处 | 当前测试状态 | 可逃逸的 mutation |
|---|---|---|---|
| 长按文件弹出菜单（有/无进度） | `browser_screen.dart:145-146` | 零覆盖 | 反转 `if (progress == null) return;` 测试全绿 |
| 点击带进度文件→弹对话框 | `browser_screen.dart:87-95` | 零覆盖 | 删除对话框弹出逻辑测试全绿 |
| `loadProgressForDirectoryProvider` 正确调用 DAO 批量查询 | `browser_provider.dart` | 只测 `dao.find`，未测该 provider | BRW4 竞态场景零守护 |
| playing 态响应式翻转 | `browser_screen.dart:293-300` | 静态打桩，无翻转测试 | 删除响应式订阅测试全绿 |

---

## §3 测试补强规约

### 3.1 BRW9 — 长按菜单交互

- **[TEST-01-S1]** 长按文件 tile，有进度时弹出菜单（`status: new`）
  ```
  Given playProgressProvider 返回非空进度（file.path = '/music/a.mp3'，进度 = 1:23）
  When  长按该文件 tile
  Then  弹出菜单，包含"删除进度"选项
  否定断言:
    - 不在无进度时弹出"删除进度"菜单（反转 `if (progress == null) return;` 应触发菜单）
    - 不在长按时不触发 `onLongPress` 回调（应仅弹菜单，不触发其他动作）
    - 不改变点击行为（点击 tile 应继续触发文件播放逻辑）
  ```
  Code evidence: `lib/features/browser/browser_screen.dart:145-146`（`if (progress == null) return;`）
  Mutation risk: 反转该条件 → 无进度时也弹菜单 → 测试当前全绿（零守护）

- **[TEST-01-S2]** 长按文件 tile，无进度时不弹菜单（`status: new`）
  ```
  Given playProgressProvider 返回 null（file.path = '/music/b.mp3'）
  When  长按该文件 tile
  Then  不弹出菜单（或弹出空菜单）
  否定断言:
    - 不在无进度时弹出"删除进度"选项（应被 `if (progress == null) return;` 拦截）
    - 不在长按时触发 `onLongPress` 回调（应仅弹菜单，不触发其他动作）
    - 不改变点击行为（点击 tile 应继续触发文件播放逻辑）
  ```
  Code evidence: `lib/features/browser/browser_screen.dart:145-146`
  Test anchoring: widget test — `pumpWidget(HomeScreen)` with override `playProgressProvider`，`longPress` tile，断言菜单存在/缺失

- **[TEST-01-S3]** 长按菜单点击"删除进度"触发 DAO 删除（`status: new`）
  ```
  Given playProgressProvider 返回非空进度，长按文件 tile 弹出菜单
  When  点击"删除进度"
  Then  调用 IProgressDao.delete(connectionId, filePath)
  And   playProgressProvider 刷新为 null
  否定断言:
    - 不在点击后不刷新 provider（应 invalidate playProgressProvider）
    - 不在删除失败时静默吞错（应展示 SnackBar 或恢复进度）
    - 不改变其他文件 tile 的进度状态（仅删除被点击文件的进度）
  ```
  Code evidence: `lib/features/browser/browser_screen.dart:145-146`（长按菜单分支）
  Test anchoring: widget test — 长按 tile，点击菜单项，`verify(progressDao.delete(...)).called(1)`

### 3.2 BRW10 — 批量进度查询 + 点击→对话框

- **[TEST-01-S4]** `loadProgressForDirectoryProvider` 调用 DAO 批量查询（`status: new`）
  ```
  Given 目录 '/music' 包含 3 个文件（a.mp3, b.mp3, c.mp3）
  When  调用 loadProgressForDirectoryProvider(connectionId: 1, path: '/music')
  Then  返回 Map<filePath, PlayProgress>，包含 3 个文件的进度（部分为 null）
  否定断言:
    - 不在查询时逐个文件调用 `dao.find`（应批量查询，一次 SQL）
    - 不在返回结果时不刷新缓存（应更新 _progressRegistry）
    - 不改变单次 `dao.find` 的返回值语义（仍返回 null 或 PlayProgress）
  ```
  Code evidence: `lib/features/browser/browser_provider.dart`（loadProgressForDirectoryProvider）
  Mutation risk: 改为逐个查询 → 性能下降 → 测试当前全绿（零守护）
  Test anchoring: provider test — `ProviderContainer` + fake DAO，调用 provider，`verify(dao.findBatch(...)).called(1)`

- **[TEST-01-S5]** 点击带进度文件→弹进度恢复对话框（`status: new`）
  ```
  Given 点击文件 a.mp3，该文件有进度（进度 = 1:23）
  When  点击该文件 tile
  Then  弹出进度恢复对话框（"从 1:23 继续播放" / "从头播放"）
  否定断言:
    - 不在无进度时弹出对话框（应直接播放）
    - 不在点击后不弹出对话框（应触发恢复逻辑）
    - 不改变点击无进度文件的行为（应直接播放，无弹窗）
  ```
  Code evidence: `lib/features/browser/browser_screen.dart:87-95`（点击→对话框）
  Test anchoring: widget test — `pumpWidget(BrowserScreen)`，点击带进度文件，`find.byType(ProgressDialog)`

- **[TEST-01-S6]** BRW4 竞态场景：快速切目录不污染进度（`status: new`）
  ```
  Given 在目录 A 浏览，loadProgressForDirectoryProvider 正在查询
  When  快速切到目录 B（在 A 的查询完成前）
  Then  目录 B 的进度不包含目录 A 的文件
  否定断言:
    - 不在切换目录后残留旧目录的进度（应清空 _progressRegistry）
    - 不在查询完成后更新错误的目录（应按 path 匹配）
    - 不改变正常查询的返回值语义
  ```
  Code evidence: `lib/features/browser/browser_provider.dart`（_progressRegistry）
  Test anchoring: provider test — 模拟异步查询，快速切换，断言最终进度属于目录 B

### 3.3 BRW11 — playing 态响应式翻转

- **[TEST-01-S7]** 初始 playing=false，翻转为 true 后图标启用（`status: new`）
  ```
  Given 初始 playingStateProvider = false
  When  pump BrowserScreen
  And   翻转 playingStateProvider = true（经响应式源）
  Then  播放/暂停图标 onPressed 由 null 变非 null
  否定断言:
    - 不在翻转后不更新图标状态（应响应 playingStateProvider 变化）
    - 不在初始 playing=false 时图标 onPressed 非 null（应禁用）
    - 不改变其他图标的行为（仅更新播放/暂停图标）
  ```
  Code evidence: `lib/features/browser/browser_screen.dart:293-300`（图标 onPressed 绑定）
  Test anchoring: widget test — `pumpWidget(BrowserScreen)` with playingStateProvider=false，`ref.read(playingStateProvider.notifier).state = true`，`find.byIcon(...).onPressed != null`

- **[TEST-01-S8]** 初始 playing=true，翻转为 false 后图标禁用（`status: new`）
  ```
  Given 初始 playingStateProvider = true
  When  pump BrowserScreen
  And   翻转 playingStateProvider = false（经响应式源）
  Then  播放/暂停图标 onPressed 由非 null 变 null
  否定断言:
    - 不在翻转后不更新图标状态（应响应 playingStateProvider 变化）
    - 不在初始 playing=true 时图标 onPressed 为 null（应启用）
    - 不改变其他图标的行为（仅更新播放/暂停图标）
  ```
  Code evidence: `lib/features/browser/browser_screen.dart:293-300`
  Test anchoring: widget test — 同上，反向翻转

- **[TEST-01-S9]** INV4 真实竞态测试：快速连点不导致多播（`status: new`）
  ```
  Given BrowserScreen 已渲染，文件 a.mp3 无进度
  When  快速连点该文件 5 次（<100ms 间隔）
  Then  仅触发一次播放逻辑（ SerializedRequestGate 串行化）
  否定断言:
    - 不在连点后触发多次播放（应被门控拦截）
    - 不在连点后导致 UI 冻结（应异步处理）
    - 不改变单次点击的行为（应正常播放）
  ```
  Code evidence: `lib/features/browser/browser_screen.dart:87-95`（点击→播放）
  Mutation risk: 当前 INV4 测试只计数，未测真实竞态 → 删除门控测试全绿
  Test anchoring: widget test — `tester.tap()` 5 次快速连点，`verify(audioPlayer.play()).called(1)`

---

## §4 不变量

- **[TEST-01-INV1]** 所有浏览器关键用户交互（长按菜单、进度恢复、播放态图标）有 widget test 守护
  证据：TEST-01-S1~S9 补齐后覆盖

- **[TEST-01-INV2]** `loadProgressForDirectoryProvider` 有独立 provider test，不依赖 `dao.find` 间接守护
  证据：TEST-01-S4 直接测试该 provider

- **[TEST-01-INV3]** playing 态响应性有翻转测试，非静态打桩
  证据：TEST-01-S7/S8 覆盖

---

## §5 测试规约

### 5.1 现有测试清单

| 测试文件 | 覆盖 | 备注 |
|---|---|---|
| `brw_04_test.dart` | 进度菜单（空壳） | **BRW9**：断言自定常量，需重写 |
| `brw_07_test.dart` | 批量查询（名实不符） | **BRW10**：只测 dao.find，需补 provider test |
| `brw_09_test.dart` | 播放态图标（静态打桩） | **BRW11**：无响应性测试，需补翻转测试 |

### 5.2 测试 ID 派生清单

```
TEST-01-S1~S3     # BRW9 长按菜单
TEST-01-S4~S6     # BRW10 批量进度 + 对话框
TEST-01-S7~S9     # BRW11 playing 态响应
TEST-01-INV1~INV3 # 不变量守护
```

### 5.3 测试覆盖盲点

| 未覆盖 ID | 现状 | 应补偿方式 |
|---|---|---|
| TEST-01-S1/S2 | 长按菜单零覆盖 | widget test：override playProgressProvider，longPress tile |
| TEST-01-S3 | 菜单点击→DAO 删除零覆盖 | widget test：点击菜单项，verify dao.delete |
| TEST-01-S4 | loadProgressForDirectoryProvider 零覆盖 | provider test：ProviderContainer + fake DAO |
| TEST-01-S5 | 点击→对话框零覆盖 | widget test：点击带进度文件，find ProgressDialog |
| TEST-01-S6 | BRW4 竞态零覆盖 | provider test：模拟异步查询 + 快速切换 |
| TEST-01-S7/S8 | playing 态翻转零覆盖 | widget test：pump 后翻转 playingStateProvider |
| TEST-01-S9 | INV4 真实竞态零覆盖 | widget test：快速连点，verify play() called(1) |

### 5.4 测试文件位置

| 测试 ID | 文件路径 | 类型 |
|---|---|---|
| TEST-01-S1~S3 | `test/features/browser/test_01_brw09_test.dart` | widget test |
| TEST-01-S4~S6 | `test/features/browser/test_01_brw10_test.dart` | provider test + widget test |
| TEST-01-S7~S9 | `test/features/browser/test_01_brw11_test.dart` | widget test |
| TEST-01-INV1~INV3 | 同上分散 | — |

---

## §6 算法样例

不适用——本 spec 为测试补强，无新算法。

---

## §7 跨模块影响

| 其它 feature | 影响点 | 需要补的回归断言 |
|---|---|---|
| BRW | `browser_screen.dart` 长按分支 | 现有 widget test 可能需更新菜单断言 |
| BRW | `browser_provider.dart` loadProgressForDirectoryProvider | 现有 provider test 可能需调整 mock DAO |
| BRW | `brw_04_test.dart` / `brw_07_test.dart` / `brw_09_test.dart` | 需重写空壳测试 |

---

## §8 平台特性与手动 QA

本 spec 不涉及平台原生特性，全部可在 `flutter test` 中验证。

---

## §9 dev-status.json 条目对照

见统一更新：`docs/dev/dev-status.json`。

---

## §10 changelog

- 2026-07-27: 创建 TEST-01 spec（基于 cr-20260724-0110.md BRW9+BRW10+BRW11）
