# BUG-09 — 嵌套 PopScope 双重动作：浏览器子目录按返回键时目录回退且应用退到后台（moveTaskToBack）

## §0 头部元数据

```yaml
id: BUG-09
name: 嵌套 PopScope 双重动作：浏览器子目录返回键同时触发目录回退 + moveTaskToBack
priority: P1
status: active
created_at: 2026-08-16
last_updated: 2026-08-16
spec_anchored_files:
  - lib/features/home/home_screen.dart
  - lib/features/browser/browser_screen.dart
cross_module_impacts: [HOME, BRW]
parent_feature: null           # 跨模块：Home 路由级 PopScope × Browser 目录级 PopScope 协作
manual_qa_required: true       # 涉 MethodChannel moveTaskToBack + Android 系统返回键/手势
```

---

## §1 用户视角

### 1.0 原始需求（用户原话逐字记录）

来源：`docs/cr/cr-20260816-0803-browser-home.md` B1（cr 复核已确认仍存在）：

> #### B1. 浏览器子目录按返回键：目录回退 + 应用退到后台（嵌套 PopScope 双重动作）
> - 类型 / 严重度 / 维度：BUG / Major / 并发时序（P9 族）+ 功能-状态机
> - 证据：
>   - `lib/features/home/home_screen.dart:81-87`
>     ```dart
>     return PopScope(
>         canPop: false,
>         onPopInvokedWithResult: (didPop, _) {
>           if (!didPop) {
>             moveTaskToBack();
>           }
>         },
>     ```
>   - `lib/features/browser/browser_screen.dart:40-46`
>     ```dart
>     return PopScope(
>       canPop: navStack.length <= 1,
>       onPopInvokedWithResult: (didPop, _) {
>         if (!didPop) {
>           ref.read(navigationStackProvider.notifier).pop();
>         }
>       },
>     ```
>   - 框架行为依据（本机 Flutter SDK）：`navigator.dart:5559-5561` — `case RoutePopDisposition.doNotPop: lastEntry.route.onPopInvokedWithResult(false, result);`；`routes.dart:2048-2053` — `for (final PopEntry<Object?> popEntry in _popEntries) { popEntry.onPopInvokedWithResult(didPop, result); }`：doNotPop 时**同一路由上注册的全部 PopScope** 都以 `didPop=false` 收到回调。
> - 复现路径：
>   1. 浏览器进入子目录（navStack = ['/', '/music']，BrowserScreen 的 canPop=false 生效）
>   2. 按系统返回键 → 路由 pop disposition = doNotPop → HomeScreen 与 BrowserScreen 的 onPopInvokedWithResult **都被**以 didPop=false 调用
>   3. BrowserScreen 弹一级目录（期望行为 ✓）；HomeScreen 同时执行 `moveTaskToBack()`（实际行为 ✗）——应用退到后台
>   4. 期望：仅回退一级目录、应用保持前台；实际：目录回退 + 应用最小化（返回前台后用户发现目录已变）
>   5. 同族场景：播放单 Tab 下浏览器栈仍深时按返回，同样双重动作（静默目录回退 + 后台化）
>   - 实证：scratch 测试（已删除）pump 真实 HomeScreen + 子目录 navStack，`tester.binding.handlePopRoute()` 后断言失败输出 `Expected: empty / Actual: ['moveTaskToBack']`，同时 navStack 长度 2→1。
> - 自检答案：**该分支零覆盖**——test_03_home2（TEST-03-S1/S2）只测浏览器在根目录（navStack 长度 1）的返回键；TST-T60/T61 直接调 `notifier.pop()` 绕开 PopScope 接线；没有任何测试在子目录深度驱动系统返回键，嵌套 PopScope 交互是盲区。
> - 修复建议（方向，不给代码）：HomeScreen 的 handler 在 moveTaskToBack 前先读 `navigationStackProvider` 长度，仅当浏览器栈在根时才退后台（子目录深度让给 BrowserScreen 处理）；或把 moveTaskToBack 收敛进 BrowserScreen 根目录分支、HomeScreen 只做兜底。需先写失败复现测试（pump 真实 HomeScreen + 子目录 + handlePopRoute，断言 channel 不收到 moveTaskToBack）。

### 1.1 这一功能干什么（一句话）

修复 Home 页系统返回键的分工：浏览器子目录深度时返回键只回退目录、应用保持前台；仅在浏览器栈在根（或播放单 Tab）时才退到后台。

### 1.2 用户期望的场景

| ID | 你看到的样子 | 期望行为 |
|----|----|----|
| U1 | 在文件浏览里进到子目录（如"音乐"文件夹）后按返回键 | 只退回上一级目录，应用保持在前台（修复前：目录回退了，应用同时被最小化到后台） |
| U2 | 从后台切回刚才的子目录页面 | 目录还是刚才那个目录（修复前：目录已被静默回退，且页面与记忆不一致） |
| U3 | 在文件浏览的根目录按返回键 | 应用退到后台，页面保持原样（现有正确行为，不得回归） |
| U4 | 在"播放单"页按返回键 | 应用退到后台，无论浏览器目录栈有多深都不被改动（修复前若浏览器栈深会静默回退） |
| U5 | 从"设置"等子页面按返回键 | 正常返回上一页，不受影响 |

---

## §2 已实现的功能骨架（代码锚点）

### 2.1 文件与分层

| 层 | 文件 | 行数 | 角色 |
|---|---|---|---|
| UI（路由宿主） | `lib/features/home/home_screen.dart` | 202 | Home 页：Tab（播放单/文件浏览器）+ PopScope 拦截系统返回 → moveTaskToBack（81-87） |
| UI（浏览器） | `lib/features/browser/browser_screen.dart` | 393 | 文件浏览：PopScope 按目录栈深动态 canPop（40-46），!didPop → 弹一级目录 |
| Domain | `lib/features/browser/domain/navigation_stack.dart` | 41 | 目录导航栈（push/pop，根 `/` 永驻） |
| 路由 | `lib/app/router.dart` | — | `/browser` → HomeScreen（46-48），HomeScreen 唯一外部调用方 |
| 测试 | `test/features/home/bug_09_repro_test.dart` | 本 spec §5.4 | 本 Bug 门禁（修复前 FAIL，已用 repro-test.sh fail 确认） |

### 2.2 关键 Provider 表

| Provider 名 | 类型 | 实现位置 | 用途 |
|---|---|---|---|
| navigationStackProvider | StateNotifierProvider<List<String>> | browser_provider.dart:131-133 | 目录导航栈；经 shared/di/providers.dart:37 re-export（home_screen.dart:11 已 import） |

### 2.3 状态机图（PopScope 嵌套接线）

```
系统返回键 ──▶ Home 路由 maybePop
   │  disposition 判定：任一 PopScope canPop=false → doNotPop（路由不退出）
   ▼
同一路由全部 PopScope 收到 onPopInvokedWithResult(false)
   ├─ HomeScreen（canPop 恒 false，home_screen.dart:82）──▶ 无条件 moveTaskToBack（缺陷点）
   └─ BrowserScreen（canPop = navStack.length<=1，browser_screen.dart:41）
        ├─ 栈深 >1：didPop=false → notifier.pop() 弹一级目录 ✓
        └─ 栈根：pop() 是 no-op（navigation_stack.dart:22-26）→ 无动作
```

---

## §3 行为规约（Given-When-Then）

### 3.1 现有行为（逆抽，缺陷态）

- **[BUG-09-S1]** 子目录深度 + 浏览器 Tab 可见按返回键 → 目录回退 **且** 应用退到后台（缺陷根源）
  ```
  Given HomeScreen 已挂载（/browser 路由），浏览器 Tab 可见，navStack = ['/', '/music']
        （BrowserScreen canPop=false :41；HomeScreen canPop=false :82）
  When 系统返回键（handlePopRoute）
  Then 路由 disposition = doNotPop（home_screen.dart:82 拦截）
  And HomeScreen 与 BrowserScreen 的 onPopInvokedWithResult 都以 didPop=false 被调用
        （框架行为：navigator.dart:5559-5561 / routes.dart:2048-2053）
  And BrowserScreen pop() → navStack 2→1（目录回退 ✓，期望行为）
  And HomeScreen 同时 moveTaskToBack()（✗ 应用最小化——缺陷动作）
  ```
  Code evidence: `lib/features/home/home_screen.dart:81-87`（:83-86 无条件 moveTaskToBack）；`lib/features/browser/browser_screen.dart:40-46`；实证：`test/features/home/bug_09_repro_test.dart` 用例 1 修复前 FAIL——`Actual: [MethodCall:MethodCall(moveTaskToBack, null)]`。

- **[BUG-09-S2]** 浏览器 Tab 根目录按返回键 → moveTaskToBack（现有正确行为）
  ```
  Given 浏览器 Tab 可见，navStack = ['/']（BrowserScreen canPop=true :41，HomeScreen canPop=false :82）
  When 系统返回键
  Then disposition 仍 doNotPop（HomeScreen :82）→ 两 handler 收到 didPop=false
  And BrowserScreen pop() 为 no-op（navigation_stack.dart:22-26：length>1 才弹）
  And HomeScreen moveTaskToBack() → 应用退后台
  ```
  Code evidence: `home_screen.dart:82-86`；锚定测试：`test/features/home/test_03_home2_test.dart`（TEST-03-S1，channel 收到 moveTaskToBack）+ `test/features/home/bug_09_repro_test.dart` 用例 2（修复前 PASS）。

- **[BUG-09-S3]** 播放单 Tab 按返回键 → 仅 moveTaskToBack，目录栈不被静默回退
  ```
  Given 播放单 Tab 可见（index 0），navStack = ['/', '/music']（浏览器栈深）
  When 系统返回键
  Then TabBarView 非可见页（BrowserScreen）不在元素树中 → 其 PopScope 未注册
        → 仅 HomeScreen handler 收到 didPop=false → moveTaskToBack
  And navStack 保持 ['/', '/music'] 不变（无静默目录回退）
  ```
  Code evidence（实证）: `test/features/home/bug_09_repro_test.dart` 用例 3（修复前 PASS：channel 收到恰好 1 次 moveTaskToBack，navStack 不变）——证明 cr 报告"同族场景（播放单 Tab 静默回退）"在真实现接线中**不成立**：TabBarView 切换完成后非可见 Tab 的 BrowserScreen 被 dispose，其 PopScope 不注册。该用例转为修复后的回归断言（S6）。

### 3.2 修复方案（status: new）

- **[BUG-09-S4]** 子目录深度 + 浏览器 Tab 可见按返回键 → 仅目录回退，不 moveTaskToBack（修改点） （status: new）
  ```
  Given 浏览器 Tab 可见（_tabController.index == 1）且 navStack 长度 > 1
  When 系统返回键 → HomeScreen handler 以 didPop=false 被调用
  Then HomeScreen 跳过 moveTaskToBack（把目录回退让给 BrowserScreen 的 handler）
  And BrowserScreen pop() → navStack 回退一级（期望行为保持不变）
  否定断言:
    - MethodChannel 'com.example.nas_audio_player/background' 不得收到 'moveTaskToBack' 调用
    - HomeScreen 路由不得被 pop 退出（canPop:false 语义不变）
    - navStack 必须仍回退一级（修复不得连目录回退一起吞掉）
  ```
  **修改点**：`lib/features/home/home_screen.dart:81-87` — 在 moveTaskToBack 前检查"浏览器 Tab 可见 && 目录栈深"，二者同时成立时跳过（让给 BrowserScreen）：
  ```dart
  return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          final browserVisible = _tabController.index == 1;
          final browserStackDeep =
              ref.read(navigationStackProvider).length > 1;
          if (!(browserVisible && browserStackDeep)) {
            moveTaskToBack();
          }
        }
      },
      child: Scaffold(...) // 其余 build 不变
  ```
  **无新增 import**：`navigationStackProvider` 已由 `shared/di/providers.dart:37` re-export，`home_screen.dart:11` 已 import 该 facade；`ref.read` 在事件回调中读取 provider 是现有同款模式（`browser_screen.dart:44` 同场景）。
  **修改范围边界**：`browser_screen.dart:40-46` **不动**（其行为正确：栈深时 pop、栈根时 no-op）。

- **[BUG-09-S5]** 浏览器 Tab 根目录按返回键 → moveTaskToBack（回归锚定） （status: new）
  ```
  Given 浏览器 Tab 可见且 navStack = ['/']
  When 系统返回键
  Then browserVisible && browserStackDeep = true && false = false → 走 moveTaskToBack
  And BrowserScreen handler pop() 为 no-op（根目录）
  否定断言:
    - moveTaskToBack 必须恰好调用 1 次（修复不得让根目录返回失效）
    - navStack 保持 ['/']（根目录 pop 是 no-op）
    - HomeScreen 路由不被 pop 退出
  ```
  修改点：同上（S4 的 else 分支即为本行为；dev-exe 用 `bug_09_repro_test.dart` 用例 2 断言）。

- **[BUG-09-S6]** 播放单 Tab（任意目录栈深）按返回键 → moveTaskToBack，目录栈不变（回归锚定） （status: new）
  ```
  Given 播放单 Tab 可见（index 0），navStack 深（如 ['/', '/music']）
  When 系统返回键
  Then browserVisible = false → 走 moveTaskToBack（与修复前行为一致）
  And 非可见 BrowserScreen 的 PopScope 未注册 → 无目录回退
  否定断言:
    - moveTaskToBack 恰好 1 次（播放单 Tab 返回必须能退后台）
    - navStack 不得被静默回退（保持 ['/', '/music']）
  ```
  修改点：同上（S4 条件不命中即本行为）；实证基础：`bug_09_repro_test.dart` 用例 3 修复前即 PASS，修复后必须保持 PASS。

**边界裁决（弱模型照此实现，无需二次判断）**：

| 边界情况 | 裁决 |
|---|---|
| `_tabController.index` 读点 | handler 回调时 `_tabController.index` 即为当前可见 Tab（Tab 切换动画中 index 已更新为目标值，indexIsChanging=true）；动画中按返回按"目标 Tab"判定——浏览器 Tab 目标 + 栈深 → 让给 BrowserScreen（其 PopScope 已注册） |
| didPop == true | 现有语义不变：不执行任何动作（canPop:false 下 didPop 恒为 false，分支保留兼容） |
| 播放单 Tab + 栈深 | browserVisible=false → moveTaskToBack（目录栈不动，S6） |
| 根目录 + 栈深不可能同真 | navStack 至少含根 `/`（navigation_stack.dart:13），length>1 即栈深 |
| 其它路由（/player、/settings）压在上面 | 返回键先 pop 顶层路由，HomeScreen 的 PopScope 不参与（顶层路由 pop 成功，didPop=true 路径在顶层消费）——本修改点不触碰该路径 |

---

## §4 不变量

- **[BUG-09-INV1]** 系统返回键永不 pop 退出 Home 路由（HomeScreen PopScope canPop 恒 false）
  证据：`lib/features/home/home_screen.dart:82`（canPop: false）+ `test/features/home/test_03_home2_test.dart` TEST-03-S1/S2 否定断言。

- **[BUG-09-INV2]** 浏览器子目录深度时返回键必须回退一级目录
  证据：`lib/features/browser/browser_screen.dart:41-45`（canPop 动态 + !didPop → pop）；修复后与 S4 条件互斥成立（栈深 + 浏览器可见时 HomeScreen 让路）。

- **[BUG-09-INV3]** 返回键不得静默改变不可见浏览器 Tab 的目录栈
  证据（实证）：`test/features/home/bug_09_repro_test.dart` 用例 3（播放单 Tab + 栈深 → navStack 不变）；机制：TabBarView 非可见页 dispose → PopScope 不注册。

- **[BUG-09-INV4]** 同一路由上注册的全部 PopScope 在 doNotPop 时都以 didPop=false 收到回调（框架行为，方案前提）
  证据：Flutter SDK `navigator.dart:5559-5561` / `routes.dart:2048-2053`（cr 报告引用的本机 SDK 行为）。

---

## §5 测试规约

### 5.1 现有测试清单

| 测试文件 | 覆盖的 Scenario / INV | 备注 |
|---|---|---|
| test/features/home/test_03_home2_test.dart | BUG-09-S2（TEST-03-S1/S2 根目录返回） | 仅覆盖根目录深度（cr 自检答案：子目录深度零覆盖） |
| test/features/home/bug_09_repro_test.dart | BUG-09-S1/S2/S3/S4/S5/S6 + INV1/2/3 | 本 Bug 门禁（修复前 FAIL，已用 repro-test.sh fail 确认） |
| test/features/browser/brw_08_test.dart TST-T60/T61 | 目录栈 pop 纯逻辑 | 直调 notifier.pop()，不涉 PopScope 接线（cr 自检答案） |

### 5.2 测试 ID 派生清单（dev-exe 派发测试 Agent 用）

```
BUG-09-S1 … S6        # Scenario（S1 缺陷锚定，S2/S3 现有行为锚定，S4/S5/S6 修复目标+回归）
BUG-09-INV1 … INV4    # 不变量
BUG-09-MAN1 … MAN3    # 手动 QA 步骤（见 §8）
```

dev-exe 要求：S4/S5/S6 + INV1~3 由 §5.4 门禁测试覆盖；S1 = 门禁用例 1 的修复前 FAIL 证据（修复后该用例转为 PASS，即 S4）；S2 = 用例 2；S3 = 用例 3；INV4 = 框架行为前提（无需单独测试，S4 依赖）。

### 5.3 测试覆盖盲点（dev-plan 写本文档时识别）

| 未覆盖 ID | 现状 | 应补偿方式 |
|---|---|---|
| BUG-09-MAN1~3 | 系统返回键/手势/后台切换为真机行为 | 进 mqa-backlog（§8） |
| Tab 切换动画中（indexIsChanging）按返回 | fake 可近似但不驱动动画中按键 | 边界裁决表已裁决；dev-exe 可不补测试，真机 MAN3 覆盖 |

### 5.4 测试文件位置（spec-scan --gate 硬校验）

| 测试文件 | 覆盖 ID | 说明 |
|---|---|---|
| test/features/home/bug_09_repro_test.dart | BUG-09-S4、BUG-09-S5、BUG-09-S6、BUG-09-INV1、BUG-09-INV2、BUG-09-INV3 | 门禁：dev-exe 修复后必须 PASS（repro-test.sh pass） |

---

## §6 算法样例

本 Bug 不涉纯函数算法，跳过。

---

## §7 跨模块影响

`bash cross-imports.sh impact lib/features/home/home_screen.dart lib/features/browser/browser_screen.dart`（2026-08-16）→ home_screen.dart 唯一外部引用方 `lib/app/router.dart`（`/browser` 路由，router.dart:46-48）；browser_screen.dart 仅经 `shared/di/providers.dart:234` facade re-export，无直接外部 import。

| 其它 feature | 影响点 | 影响条件 | 需要补的回归断言 |
|---|---|---|---|
| HOME（router.dart:46-48 /browser → HomeScreen） | 修改 HomeScreen build 内 handler；路由/启动流程不变 | 仅 handler 分支变化 | onboarding_test / test_03_home3/h4（pump HomeScreen 的既有测试）全绿；bug_09_repro_test.dart PASS |
| BRW（browser_screen.dart:40-46 不修改） | 目录回退语义不变（栈深 pop、根 no-op） | 无代码改动 | brw_08 TST-T60/T61 + test_01_brw09/10/11 全绿（目录导航回归） |
| PLY（PlaylistListScreen 同 Tab 宿主） | 播放单 Tab 返回行为不变（S6） | 无代码改动 | ply_09 / test_04_list9（pump 真实 HomeScreen）全绿 |
| Player（mini_player_bar 同宿主） | HomeScreen build 结构不变 | 无代码改动 | test_04_list9 MiniPlayerBar 断言全绿 |

---

## §8 平台特性与手动 QA

设计前已逐条核对 `docs/dev/platform-pitfalls.md`：本 Bug 触及 **P15 族**（PopScope/onPopInvokedWithResult 为 Flutter 3.22+ 回调签名，本机 SDK 行为已由 cr 报告引用 `navigator.dart:5559-5561` / `routes.dart:2048-2053` 锚定——同一路由上全部 PopScope 都以 didPop=false 收到回调）；非 P9（无异步 setState 路径，handler 为同步回调）。

**真机风险列**（fake 测不到、只有真机会出问题的）：

| 风险 | 近似测试方案 | 测不了 → 进 mqa-backlog |
|---|---|---|
| Android 系统返回键 + 手势返回（edge-to-edge 手势导航）在子目录深度的实际表现 | bug_09_repro_test.dart（handlePopRoute 模拟系统返回事件，断言 channel 无 moveTaskToBack） | BUG-09-MAN1：真机浏览器进 ≥2 层子目录按返回/手势返回 → 仅逐级回退目录，应用保持前台 |
| 根目录返回 → moveTaskToBack 的真机表现（task 退后台、前台服务续播） | test_03_home2 TEST-03-S1 + bug_09 用例 2（channel 断言） | BUG-09-MAN2：真机浏览器根目录/播放单 Tab 按返回 → 应用最小化、音频继续播放 |
| Android 13+ 预测性返回（Predictive Back）动画下连按返回 | 无近似 | BUG-09-MAN3：真机 Android 13+ 子目录快速连按返回 → 目录逐级回退且应用不退后台；Tab 切换动画中按返回不崩溃 |

涉及 MethodChannel（moveTaskToBack）+ 系统返回键真机行为 → `manual_qa_required = true`；MAN1~3 已列入 mqa-backlog 攒单。

---

## §9 dev-status.json 条目对照

```json
"BUG-09": {
  "spec_file": "docs/features/BUG-09.md",
  "spec_anchored_files": [
    "lib/features/home/home_screen.dart",
    "lib/features/browser/browser_screen.dart"
  ],
  "scenarios": ["BUG-09-S1", "BUG-09-S2", "BUG-09-S3", "BUG-09-S4", "BUG-09-S5", "BUG-09-S6"],
  "invariants": ["BUG-09-INV1", "BUG-09-INV2", "BUG-09-INV3", "BUG-09-INV4"],
  "algorithms": [],
  "manual_qa_required": true,
  "user_acceptance_text": "见 §1.2"
}
```
