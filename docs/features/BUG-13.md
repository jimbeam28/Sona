# BUG-13 — player 错误态"检查连接"按钮用 Navigator.pushNamed 调未注册路由，必抛 FlutterError

## §0 头部元数据

```yaml
id: BUG-13
name: player 错误态"检查连接"按钮用 Navigator.pushNamed 调未注册路由，必抛 FlutterError
priority: P1
status: active
created_at: 2026-08-16
last_updated: 2026-08-16
spec_anchored_files:
  - lib/features/player/player_screen.dart
cross_module_impacts: [Connection, App]
parent_feature: Player（音频播放/Player 模块）
manual_qa_required: false
```

---

## §1 用户视角

### 1.0 原始需求（用户原话逐字记录）

来源：`docs/cr/cr-20260816-0804-connection-playlist.md` B3（cr 复核 2026-08-16 已确认仍存在）：

> #### B3. player 错误态"检查连接"用 Navigator.pushNamed 调未注册路由，必抛 FlutterError
> - 类型 / 严重度 / 维度：BUG / Major / 正确性（路由跳转失效）
> - 证据：
>   - `lib/features/player/player_screen.dart:417-420` — `onPressed: () { Navigator.of(context).pop(); Navigator.of(context).pushNamed('/connection'); }`
>   - go_router 14.8.1 `builder.dart:438` — RouterDelegate 的 Navigator 仅 `Navigator(pages: _pages!, onPopPage: ...)`，**无 onGenerateRoute / onUnknownRoute**；`pushNamed` 解析失败时抛 `FlutterError('Navigator.onGenerateRoute returned null for requested route')`
>   - 代码库自身约定：全项目导航均走 `context.go/push`（go_router 扩展，见 router.dart 全部路由）；`/connection` 路由表只存在于 go_router（`router.dart:27-31`）
> - 复现路径：播放中凭据失效（改错密码或服务器改密）→ 加载 401 → 错误态显示"检查连接"按钮（player_screen.dart:395-424）→ 点击 → `pop()` 先退出播放页，随后 `pushNamed('/connection')` 在无 onGenerateRoute 的 Navigator 上抛 FlutterError → 期望：进入连接编辑页修改凭据；实际：弹出播放页 + 未捕获异常（debug 红屏 / release 静默失败），修复路径断掉。
> - 自检答案：分支零覆盖——grep 全 test/ 无任何测试点击"检查连接"按钮（player 错误态测试只断言文案与重试按钮），该导航分支从未被执行。
> - 修复建议：改用 `context.pop()` + `context.push('/connection')`（go_router 扩展）；注意当前代码先 pop 再用旧 context push 的时序问题一并处理。

### 1.1 这一功能干什么（一句话）

把播放器认证错误态"检查连接"按钮的导航从裸 `Navigator.pushNamed` 改为 go_router 扩展导航，使点击真正进入连接配置页且不抛异常。

### 1.2 用户期望的场景

| ID | 你看到的样子 | 期望行为 |
|----|----|----|
| U1 | 播放中凭据失效（服务器改密等），播放页显示"检查连接"按钮 | 点击后退出播放页、进入连接配置页，可以修改凭据（修复前：弹出播放页 + 未捕获异常，debug 红屏 / release 静默无反应） |
| U2 | 从连接配置页返回 | 回到配置前所在的页面（浏览器主页），无异常 |
| U3 | 非认证类加载失败（网络断开）的错误态 | 界面不变——只有认证错误才显示"检查连接"按钮（修复不改按钮显示条件） |

---

## §2 已实现的功能骨架（代码锚点）

### 2.1 文件与分层

| 层 | 文件 | 行数 | 角色 |
|---|---|---|---|
| UI | `lib/features/player/player_screen.dart` | 432 | 错误态 `_buildError`（:371-431）；"检查连接"按钮（:416-423，onPressed :417-420 pushNamed） |
| Domain | `lib/features/player/domain/player_screen_logic.dart` | 108 | `isAuthError`（:100-107）决定按钮显示条件 |
| 路由 | `lib/app/router.dart` | 80 | `/connection` GoRoute（:27-31）、`/player` GoRoute（:58-62） |
| 测试 | `test/features/player/bug_bug13_repro_test.dart` | 本 spec §5.4 | 本 Bug 门禁 |

### 2.2 关键 Provider 表

本 Bug 不涉 provider，跳过。

### 2.3 状态机图

本 Bug 不涉状态机（单按钮导航修复），跳过。

---

## §3 行为规约（Given-When-Then）

### 3.1 现有行为（逆抽，缺陷态）

- **[BUG-13-S1]** "检查连接"按钮 onPressed 用裸 Navigator pop + pushNamed，必抛 FlutterError
  ```
  Given PlayerScreen 处于认证错误态（_loadState.isAuthError == true，isAuth 分支渲染）
  When 用户点击"检查连接"按钮
  Then onPressed 执行 Navigator.of(context).pop()（先退出播放页）
  And 随后 Navigator.of(context).pushNamed('/connection')
       → go_router 14.8.1 的 Navigator 无 onGenerateRoute
       → 抛 FlutterError('Navigator.onGenerateRoute returned null for
         requested route')
  And 用户期望的连接配置页不会出现（路由跳转断掉）
  ```
  Code evidence: `lib/features/player/player_screen.dart:417-420`；go_router 14.8.1 `builder.dart:438`（`Navigator(pages: _pages!, onPopPage: ...)` 无 onGenerateRoute）；`router.dart:27-31`（/connection 只存在于 go_router 路由表）

- **[BUG-13-S2]** 认证错误态按钮显示条件（现状锚定，修复不改）
  ```
  Given _loadState.isAuthError == true（noConnection / noPassword，player_screen_logic.dart:100-107）
  When 渲染错误态
  Then 显示"检查连接"按钮（isAuth 分支 :414-424）
  And isAuthError == false 时无该按钮（只有"重试"）
  ```
  Code evidence: `lib/features/player/player_screen.dart:395-424`；`player_screen_logic.dart:100-107`

### 3.2 修复方案（status: new）

- **[BUG-13-S3]** 改用 go_router 扩展 `context.pop()` + `context.push('/connection')`（status: new）
  ```
  Given PlayerScreen 处于认证错误态（/player 为 push 进入的页面，pop 有效）
  When 用户点击"检查连接"按钮
  Then context.pop() 退出播放页（go_router delegate 校验 canPop，见可行性依据）
  And context.push('/connection') 进入连接配置页（/connection 已在 go_router 路由表）
  And 不抛任何异常
  否定断言:
    - 不调用 Navigator.pushNamed（裸 Navigator 无 onGenerateRoute）
    - 不抛 FlutterError / GoError
    - 不调用 context.go（会重置整个导航栈，改变返回语义）
    - 非认证错误态下按钮不出现（S2 显示条件不变）
  ```
  **修改点（唯一生产代码改动）**：`lib/features/player/player_screen.dart:417-420`：
  ```dart
  // 修改前（417-420 行）:
  onPressed: () {
    Navigator.of(context).pop();
    Navigator.of(context).pushNamed('/connection');
  },
  // 修改后:
  onPressed: () {
    context.pop();
    context.push('/connection');
  },
  ```
  player_screen.dart 已 import `go_router` 扩展（`:15` `import 'package:go_router/go_router.dart';`，文件内已用 context.push，见 :263 `/connections/edit/...` 等处），无需新增 import。
  **可行性依据（铁律 6，go_router 14.8.1 源码）**：
  - `context.pop()` → `GoRouter.pop`（router.dart:499-510）→ `routerDelegate.pop`（delegate.dart:98-105）：先 `_findCurrentNavigator()` 并 `state.canPop()` 检查，栈底抛 `GoError('There is nothing to pop')`——故生产语义要求 /player 恒为 push 页面（router.dart:58-62 下 /player 由 /browser push 进入，栈底必为根路由，pop 有效）。
  - 同一同步回调内 `pop()` 后 `push()`：pop 经 NavigatorState.pop 同步调度退出动画，push 立即加入新页面（GoRouter push → delegate 更新 _pages → Navigator rebuild）；go_router 官方 `custom_transition_page_test.dart:191` 等测试展示 pop 后继续 pump 即可完成。本方案的端到端验证即 §5.4 门禁测试（bug_bug13_repro_test.dart：GoPlayer push 进入 /player → 点击 → 断言到达 /connection stub 且无异常）——该测试修复前 FAIL（FlutterError）、修复后必须 PASS，等价于最小验证片段（铁律 6 形式②）。

**边界裁决（弱模型照此实现，无需二次判断）**：

| 边界情况 | 裁决 |
|---|---|
| /player 为栈底（理论上不应发生） | context.pop() 抛 GoError——生产不可达（/player 恒由 /browser push 进入，router.dart:58-62）；不做额外守卫（避免过度防御，dev-check 核实） |
| 认证错误态 + 用户已在下拉面板等覆盖层 | 按钮在错误态主界面（无覆盖层时可见），context 解析最近 Navigator 正常 |
| 连接配置页返回 | go_router back 回浏览器主页（pop 已把 player 出栈），无额外处理 |
| 按钮显示条件 | 不改（S2 现状锚定；非认证错误无按钮） |

---

## §4 不变量

- **[BUG-13-INV1]** 全项目导航只走 go_router 扩展（context.go / context.push / context.pop），lib/ 禁止出现 `Navigator.pushNamed`（裸 Navigator 无 onGenerateRoute）
  证据：`lib/app/router.dart` 全部路由经 go_router；go_router 14.8.1 builder.dart:438；grep lib/ `pushNamed` 仅 player_screen.dart:419 一处（本 Bug 修复后清零）

---

## §5 测试规约

### 5.1 现有测试清单

| 测试文件 | 覆盖的 Scenario / INV | 备注 |
|---|---|---|
| test/features/player/player_screen_logic_test.dart:161-176 | isAuthError 纯函数 | 按钮显示条件的逻辑层锚定 |
| test/features/player/ply_01_test.dart:295-310 | PlayerLoadState.isAuthError | 同上 |
| grep 全 test/ | 无"检查连接"按钮交互测试 | 自检答案：分支零覆盖 |

### 5.2 测试 ID 派生清单（dev-exe 派发测试 Agent 用）

```
BUG-13-S1, S2        # 缺陷态/现状锚定
BUG-13-S3            # 修复目标
BUG-13-INV1          # 不变量
```

dev-exe 要求：S3 由 §5.4 门禁测试覆盖；S1/S2 由门禁测试驱动（缺陷态断言）与既有纯函数测试锚定。

### 5.3 测试覆盖盲点（dev-plan 写本文档时识别）

| 未覆盖 ID | 现状 | 应补偿方式 |
|---|---|---|
| 无 | — | — |

### 5.4 测试文件位置（spec-scan --gate 硬校验）

| 测试文件 | 覆盖 ID | 说明 |
|---|---|---|
| test/features/player/bug_bug13_repro_test.dart | BUG-13-S3 | 门禁：修复前 FAIL（已用 repro-test.sh fail 确认，含 push 进入 /player 的真实生产形态）；dev-exe 修复后必须 PASS（repro-test.sh pass） |

---

## §6 算法样例

本 Bug 不涉纯函数算法，跳过。

---

## §7 跨模块影响

`bash cross-imports.sh impact lib/features/player/player_screen.dart`（2026-08-16）→ 引用方：

| 其它 feature | 影响点 | 影响条件 | 需要补的回归断言 |
|---|---|---|---|
| App（router.dart:58-62） | /player 路由 builder 引用 PlayerScreen | 类名/构造签名不变 | 编译 + analyze 0 warning |
| Connection（/connection 路由） | 导航目标连接配置页 | /connection GoRoute 已注册（router.dart:27-31） | 既有 connection 测试全绿；BUG-11 修复后 /connection 从多处可达 |
| Player 既有 widget 测试（ply_02 / ply_14 / bug_02 等） | MaterialApp(home: PlayerScreen()) 装配 | 本修复只改按钮 onPressed（认证错误态才渲染），既有测试不触达该按钮 | 全部保持绿 |

---

## §8 平台特性与手动 QA

设计前已逐条核对 `docs/dev/platform-pitfalls.md`：本 Bug 为路由导航修复，不触及音频/生命周期/并发条目。go_router 栈底 pop 语义（delegate.dart:98-105 GoError）已在 §3 可行性依据处置。

**真机风险列**：无。本功能不涉及平台原生特性（无 audio_service / MethodChannel / 通知栏 / 真机时序），全部可在 `flutter test` 中验证。

---

## §9 dev-status.json 条目对照

```json
"BUG-13": {
  "spec_file": "docs/features/BUG-13.md",
  "spec_anchored_files": ["lib/features/player/player_screen.dart"],
  "scenarios": ["BUG-13-S1", "BUG-13-S2", "BUG-13-S3"],
  "invariants": ["BUG-13-INV1"],
  "algorithms": [],
  "manual_qa_required": false,
  "user_acceptance_text": "见 §1.2"
}
```
