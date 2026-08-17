# BUG-11 — 全 UI 无"添加第二个连接"入口（列表页/空态无添加按钮）

## §0 头部元数据

```yaml
id: BUG-11
name: 全 UI 无"添加第二个连接"入口（列表页/空态无添加按钮）
priority: P1
status: active
created_at: 2026-08-16
last_updated: 2026-08-16
spec_anchored_files:
  - lib/features/connection/connection_list_screen.dart
  - lib/features/connection/domain/connection_validator.dart
cross_module_impacts: [Settings, App]
parent_feature: Connection（连接管理模块）
manual_qa_required: false
```

---

## §1 用户视角

### 1.0 原始需求（用户原话逐字记录）

来源：`docs/cr/cr-20260816-0804-connection-playlist.md` B1（cr 复核 2026-08-16 已确认仍存在，唯一偏差：`_EmptyState` 行号偏移 2 行，不影响结论）：

> #### B1. 无 UI 入口添加第二个连接（"连接管理"承诺"添加"却无添加按钮）
> - 类型 / 严重度 / 维度：BUG / Major / 功能-状态机（导航图可达性）
> - 证据：
>   - `lib/features/settings/settings_screen.dart:51-53` — 设置页入口副标题明文承诺"添加、编辑或切换连接"，onTap 仅 `context.push('/connections')`
>   - `lib/features/connection/connection_list_screen.dart:24-63` — 列表页 AppBar 无 actions、列表项仅有编辑/删除/切换，**无任何"添加"入口**；`:331-361` `_EmptyState` 文案"添加一个 WebDAV 连接即可开始"但无按钮
>   - `lib/app/onboarding.dart:30,106` — `/connection`（添加页）唯一可达路径是 onboarding 的 CTA，而 onboarding 仅在 `connections.isEmpty` 时显示 CTA（`:29-30`）；`router.dart:27-31` 该路由无其它引用（grep 全 lib 仅 onboarding + player_screen:419 pushNamed）
> - 复现路径：已有 ≥1 个连接 → 主页 → 设置 → 管理 NAS 连接 → 列表页只有编辑/删除/切换 → 无法进入"添加连接"页；而删除连接、切换活动连接、setActive 唯一约束（`connection_dao.dart:93-104`）证明多连接是受支持状态。期望：列表页（或设置页）提供"添加"入口；实际：无任何入口，且 `_EmptyState` 显示"添加…即可开始"的无效文案。
> - 自检答案：测试假设本身就错——con_01/test_02_con13 等全部**预置种子连接**渲染列表页，无任何测试走"设置→连接管理→添加"的完整导航图；空表 `_EmptyState` 无断言。
> - 修复建议：列表页 AppBar 或 FAB 增加"添加连接"入口（`context.push('/connection')`），或删掉空态无效文案；若单连接是产品定夺，需用户裁决（D 类分流）。

### 1.1 这一功能干什么（一句话）

修复"已有 ≥1 个连接时无法再从 UI 添加新连接"的导航可达性缺陷——连接管理列表页（及空态页）必须提供"添加连接"入口，使多连接成为用户可达的受支持状态。

### 1.2 用户期望的场景

| ID | 你看到的样子 | 期望行为 |
|----|----|----|
| U1 | 已经配好一个 NAS 连接，想再添加第二个 | 设置 → 管理 NAS 连接 → 列表页顶部有"添加"按钮，点它进入添加连接页（修复前：列表页只有编辑/删除/切换，无处可点） |
| U2 | 进入连接管理页时一个连接都没有 | 页面显示"还没有保存的连接 / 添加一个 WebDAV 连接即可开始"，并且有一个"添加连接"按钮可以直接开始添加（修复前：只有文案没有按钮，想添加只能退回首页） |
| U3 | 设置页"连接"分组的入口 | 副标题"添加、编辑或切换连接"承诺的能力全部可达（修复后该承诺成立） |
| U4 | 已有连接时的列表页布局 | 添加按钮出现在 AppBar，不遮挡、不改变列表项编辑/删除/切换的现有交互 |

---

## §2 已实现的功能骨架（代码锚点）

### 2.1 文件与分层

| 层 | 文件 | 行数 | 角色 |
|---|---|---|---|
| UI | `lib/features/connection/connection_list_screen.dart` | 362 | 连接列表页：AppBar（:25-28 无 actions）+ `_ConnectionListView`（:178-329）+ `_EmptyState`（:333-361） |
| UI | `lib/features/settings/settings_screen.dart` | 259 | 设置页"管理 NAS 连接"入口（:48-54），副标题承诺"添加、编辑或切换连接" |
| UI | `lib/app/onboarding.dart` | 171 | 空表 CTA"添加连接"（:105-112），仅 `connections.isEmpty` 时显示（:29-30/:74） |
| 路由 | `lib/app/router.dart` | 80 | `/connection` GoRoute 已注册（:27-31）但无其它 UI 入口 |
| 测试 | `test/features/connection/bug_bug11_repro_test.dart` | 本 spec §5.4 | 本 Bug 门禁 |

### 2.2 关键 Provider 表

| Provider 名 | 类型 | 实现位置 | 用途 |
|---|---|---|---|
| connectionListProvider | FutureProvider<List<ConnectionConfig>> | connection_provider.dart:77-81 | 列表数据源 |
| activeConnectionProvider | FutureProvider<ConnectionConfig?> | connection_provider.dart:69-72 | 当前活跃连接 |

### 2.3 状态机图

本 Bug 不涉状态机（导航可达性缺陷），跳过。

---

## §3 行为规约（Given-When-Then）

### 3.1 现有行为（逆抽，缺陷态）

- **[BUG-11-S1]** 连接列表页 AppBar 无任何 actions，列表项仅提供编辑/删除/切换
  ```
  Given 已有 ≥1 个连接（connectionListProvider 返回非空列表）
  When 渲染 ConnectionListScreen
  Then AppBar（connection_list_screen.dart:25-28）无 actions
  And 列表项 PopupMenu 只有 edit/delete 两项（:259-291）
  And 列表项滑出 Slidable 只有 编辑/删除 两动作（:305-321）
  And 点击列表项仅在非活跃时切换连接（:292-297），无任何"添加"入口
  ```
  Code evidence: `lib/features/connection/connection_list_screen.dart:24-63`、`:259-321`

- **[BUG-11-S2]** `/connection` 路由全 lib 仅 onboarding 空表 CTA 与 player_screen pushNamed 两处引用，添加页不可达
  ```
  Given 已有 ≥1 个连接（onboarding 进入 data 分支且 connections.isNotEmpty）
  When 用户从任意页面尝试进入"添加连接"页
  Then context.push('/connection') 的唯一调用点在 onboarding.dart:42/53（启动验证失败重定向）
      与 onboarding.dart:106（空表 CTA，仅在 connections.isEmpty 时渲染）
  And player_screen.dart:419 的 pushNamed('/connection') 是未注册路由（见 BUG-13，点击即抛错）
  And router.dart:27-31 的 /connection GoRoute 无其它引用方
  ```
  Code evidence: `lib/app/onboarding.dart:29-30/:74/:105-112`；`lib/app/router.dart:27-31`；grep 全 lib（2026-08-16 核实）

- **[BUG-11-S3]** 空态 `_EmptyState` 只有文案、无添加按钮
  ```
  Given connectionListProvider 返回空列表
  When 渲染 ConnectionListScreen
  Then 显示"还没有保存的连接"+"添加一个 WebDAV 连接即可开始"（:345/:354）
  And 无任何按钮/可点击入口（_EmptyState 是纯 Column，:333-361）
  ```
  Code evidence: `lib/features/connection/connection_list_screen.dart:333-361`

### 3.2 修复方案（status: new）

- **[BUG-11-S4]** 列表页 AppBar 增加"添加连接"入口（status: new）
  ```
  Given 已有 ≥1 个连接（列表非空）渲染 ConnectionListScreen
  When 用户查看列表页
  Then AppBar 存在 tooltip='添加连接' 的 IconButton（Icons.add）
  And 点击该按钮 → context.push('/connection') 进入添加连接页
  否定断言:
    - 列表项 PopupMenu 的 编辑/删除 两项保持不变（不新增菜单项）
    - 已有列表项滑出动作（编辑/删除 SlidableAction）保持不变
    - 点击添加按钮不得改变当前活动连接（不触发 setActive）
    - 空列表时 S4 的 AppBar 按钮同样存在（S3 的空态另有 S5 按钮）
  ```
  **修改点（唯一生产代码改动）**：`lib/features/connection/connection_list_screen.dart:25-28` AppBar 增加 `actions`：
  ```dart
  // 修改前（25-28 行）:
  appBar: AppBar(
    title: const Text('NAS 连接管理'),
    centerTitle: true,
  ),
  // 修改后:
  appBar: AppBar(
    title: const Text('NAS 连接管理'),
    centerTitle: true,
    actions: [
      IconButton(
        icon: const Icon(Icons.add),
        tooltip: '添加连接',
        onPressed: () => context.push('/connection'),
      ),
    ],
  ),
  ```
  模式依据：与 `lib/features/connection/connection_screen.dart:137-143` 现有 AppBar action（tooltip '管理连接' + `context.push('/connections')`）同款；`context.push` 是 go_router 扩展（全项目导航约定，见 CLAUDE.md 路由表）。该文件已 import `go_router`（connection_list_screen.dart:10），无需新增 import。

- **[BUG-11-S5]** 空态 `_EmptyState` 增加"添加连接"按钮（status: new）
  ```
  Given connectionListProvider 返回空列表渲染 ConnectionListScreen
  When 用户看到空态
  Then 空态文案下方存在"添加连接"按钮
  And 点击该按钮 → context.push('/connection') 进入添加连接页
  否定断言:
    - 空态图标与两行文案保持不变（仅新增按钮）
    - 非空列表渲染时 _EmptyState 不出现（现有分支 :41-43 不变）
  ```
  **修改点**：`lib/features/connection/connection_list_screen.dart:333-361` `_EmptyState.build` 的 Column 末尾（:356 `Text(...)` 之后）追加：
  ```dart
  const SizedBox(height: 24),
  FilledButton.icon(
    onPressed: () => context.push('/connection'),
    icon: const Icon(Icons.add),
    label: const Text('添加连接'),
  ),
  ```
  `_EmptyState` 当前是无状态 StatelessWidget 且未接收 context 之外的参数——`build(BuildContext context)` 内可用 `context.push`（go_router 已 import，文件头 :10）。**注意**：dev-exe 修改后需运行 `dart format`（`context.push` 闭包内箭头函数若超 80 列自动换行）。

**边界裁决（弱模型照此实现，无需二次判断）**：

| 边界情况 | 裁决 |
|---|---|
| 列表非空时 AppBar 按钮与列表项并存 | S4 只加 AppBar action，不动 `_ConnectionListView` 任何代码 |
| 列表为空时 AppBar 按钮与空态按钮并存 | 两者都存在（AppBar action 恒渲染，空态按钮随空态渲染）；点哪个都进 `/connection` |
| `/connection` 路由在 go_router 已注册（router.dart:27-31） | 无需改路由表；`context.push('/connection')` 直接可用 |
| 添加页返回 | go_router 默认 back 行为不变（返回列表页），无额外处理 |
| settings_screen.dart:51 副标题文案 | 不改（修复后承诺成立，文案即真实） |

---

## §4 不变量

- **[BUG-11-INV1]** `/connection` 添加页路由必须保持在 go_router 路由表（router.dart:27-31），全项目导航仅走 go_router 扩展（`context.push`/`context.go`），禁止 `Navigator.pushNamed`（无 onGenerateRoute，BUG-13）
  证据：`lib/app/router.dart:27-31`；go_router 14.8.1 builder.dart:438（Navigator 无 onGenerateRoute）

---

## §5 测试规约

### 5.1 现有测试清单

| 测试文件 | 覆盖的 Scenario / INV | 备注 |
|---|---|---|
| test/features/connection/test_02_con11_test.dart | 列表页切换连接行为 | 全部预置种子连接渲染列表页，无"添加"导航路径（自检答案确认） |
| test/features/connection/con_01_test.dart | 添加页表单行为 | 直接渲染 ConnectionScreen，不经列表页导航 |

### 5.2 测试 ID 派生清单（dev-exe 派发测试 Agent 用）

```
BUG-11-S1 … S3        # 缺陷态/现状锚定
BUG-11-S4, S5         # 修复目标
BUG-11-INV1           # 不变量
```

dev-exe 要求：S4/S5 已由 §5.4 门禁测试覆盖；S1~S3 由 §5.4 门禁测试驱动（S1/S3 即门禁的缺陷态断言）与既有测试锚定。

### 5.3 测试覆盖盲点（dev-plan 写本文档时识别）

| 未覆盖 ID | 现状 | 应补偿方式 |
|---|---|---|
| 无 | 全部可由 flutter test 验证 | — |

### 5.4 测试文件位置（spec-scan --gate 硬校验）

| 测试文件 | 覆盖 ID | 说明 |
|---|---|---|
| test/features/connection/bug_bug11_repro_test.dart | BUG-11-S4、BUG-11-S5 | 门禁：修复前 FAIL（已用 repro-test.sh fail 确认）；dev-exe 修复后必须 PASS（repro-test.sh pass） |
| test/features/connection/bug_bug11_repro_test.dart | BUG-11-S1~S3（缺陷态断言） | 同文件内 S1/S2 用例的失败断言即缺陷态锚定 |

---

## §6 算法样例

本 Bug 不涉纯函数算法，跳过。

---

## §7 跨模块影响

`bash cross-imports.sh impact lib/features/connection/connection_list_screen.dart`（2026-08-16）→ 引用方：

| 其它 feature | 影响点 | 影响条件 | 需要补的回归断言 |
|---|---|---|---|
| App（router.dart:33-36） | `/connections` 路由 builder 引用 ConnectionListScreen | 类名/构造签名不变 | 编译 + analyze 0 warning |
| Settings（settings_screen.dart:48-54） | "管理 NAS 连接"入口 push('/connections') | 无（导航目标不变，副标题承诺修复后成立） | settings 模块既有测试全绿 |
| Connection 自身（test_02_con11_test.dart / con_01_test.dart 等） | 列表页渲染路径 | AppBar 加 actions 不影响列表 body | 既有 connection 测试全绿；test_02_con11 的切换断言不变 |
| Player（player_screen.dart:419，BUG-13 链路） | pushNamed 是 BUG-13 的修复对象，与本 Bug 的 /connection 可达性修复互补 | BUG-13 修复后 /connection 从 player 错误态可达 | BUG-13 门禁测试 PASS |

---

## §8 平台特性与手动 QA

设计前已逐条核对 `docs/dev/platform-pitfalls.md`：本 Bug 为纯导航可达性修复，不触及任何踩坑条目（P1~P17 均不相关——无音频、无生命周期监听器、无并发、无时间、无超时层）。

**真机风险列**：无。本功能不涉及平台原生特性（无 audio_service / MethodChannel / 通知栏 / 真机时序），全部可在 `flutter test` 中验证。

---

## §9 dev-status.json 条目对照

```json
"BUG-11": {
  "spec_file": "docs/features/BUG-11.md",
  "spec_anchored_files": ["lib/features/connection/connection_list_screen.dart", "lib/features/connection/domain/connection_validator.dart"],
  "scenarios": ["BUG-11-S1", "BUG-11-S2", "BUG-11-S3", "BUG-11-S4", "BUG-11-S5"],
  "invariants": ["BUG-11-INV1"],
  "algorithms": [],
  "manual_qa_required": false,
  "user_acceptance_text": "见 §1.2"
}
```
