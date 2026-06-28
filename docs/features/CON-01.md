# CON-01 添加 WebDAV 连接

> 文档类型：功能详细设计（行为规约锚到代码）
> 维护策略：仅在该功能需要新增/修改时由 dev-plan 流程更新；不一次性倒推全项目
> 最近一次校对：2026-06-28（基于现有代码逆抽）

---

## §1 用户视角

### 1.1 这一功能干什么（一句话）

用户填写 WebDAV 服务器地址/账号/密码，先验证可连通，验证成功后才能保存——保证不会保存一条连不通的连接到 DB。

### 1.2 用户期望的场景（你来扫这一节就够了）

| ID | 你看到的样子 | 期望行为 |
|----|----|----|
| U1 | 没填 URL 直接点"测试连接" | 表单底下提示"请输入服务器地址"，**不发送网络请求** |
| U2 | 填了合法 URL+账号+密码，点"测试连接" | 按钮变转圈"连接中…"，结果出来后变绿色"连接成功"或红色错误消息 |
| U3 | 验证成功后改了密码框 | 绿色提示立刻消失，"保存"按钮变回灰禁用——防止拿旧验证结果存新密码 |
| U4 | 验证成功后点"保存" | 保存中…转圈，1~2 秒内跳到文件浏览页 |
| U5 | 保存过程中磁盘满了/加密存储失败 | 弹红底 SnackBar"保存失败：…"，**没有半条哭连接留在系统里** |
| U6 | 没验证直接点保存 | "保存"按钮一直是灰的，点不动 |
| U7 | 启动 App 时已有保存连接但服务器挂了 | 标题变"修复 WebDAV 连接"，顶部橙色横幅提示 |

> 上面这张表是**你能审的部分**，不出现代码、不看代码也能判断对错。下面 §2~§5 是给 LLM 用的技术规约。

---

## §2 已实现的功能骨架（代码锚点）

> 由 dev-plan 在首次写本文档时——基于现有代码逆抽得出。每条都标了代码出处（file:line），LLM 后续修改时可快速定位、不能凭空发挥。

### 2.1 文件与分层

| 层 | 文件 | 行数 | 角色 |
|---|---|---|---|
| UI（添加页） | `lib/features/connection/connection_screen.dart` | 298 | 表单+按钮+保存编排（`_ConnectionScreenState`） |
| UI（编辑页） | `lib/features/connection/connection_edit_screen.dart` | 378 | 复用同一表单，验证门控逻辑见 §4.2 |
| UI（列表页） | `lib/features/connection/connection_list_screen.dart` | 362 | 切换/删除/入口跳编辑 |
| UI（表单部件） | `lib/features/connection/widgets/connection_form.dart` | 239 | 5 个 `TextFormField` + `ConnectionFormController` 桥接 |
| Provider | `lib/features/connection/connection_provider.dart` | 263 | 验证 StateNotifier + save/update/delete FutureProvider + 启动自检 |
| Domain（服务） | `lib/features/connection/domain/connection_service.dart` | 111 | 纯 Dart CRUD，无 Flutter 依赖 |
| Domain（校验） | `lib/features/connection/domain/connection_validator.dart` | 124 | URL/必填/basePath 校验纯函数 |
| Domain（编辑门控） | `lib/features/connection/domain/edit_screen_logic.dart` | 73 | 决定"凭证改了没，要不要重新验证" |
| 测试 | `test/features/connection/con_01_test.dart` 等 12 份 | — | 见 §5.1 测试清单 |

### 2.2 关键 Provider 表

| Provider 名 | 类型 | 实现位置 | 用途 |
|---|---|---|---|
| `connectionValidatorProvider` | `StateNotifierProvider<_, ConnectionValidationState>` | connection_provider.dart:117 | 持有 Idle/Loading/Success/Error 四态 |
| `connectionSaverProvider` | `Provider<ConnectionSaver>` | connection_provider.dart:210 | 调 `ConnectionService.save` |
| `connectionUpdaterProvider` | `Provider<ConnectionUpdater>` | connection_provider.dart:237 | 调 `ConnectionService.update` |
| `deleteConnectionProvider` | `FutureProvider.family<void, int>` | connection_provider.dart:248 | 删除，抛 `LastConnectionException` 时 UI 报错 |
| `switchActiveConnectionProvider` | `FutureProvider.family<void, int>` | connection_provider.dart:177 | 切换活跃连接 |
| `activeConnectionProvider` | `FutureProvider<ConnectionConfig?>` | connection_provider.dart:41 | 当前活跃连接 `findActive` |
| `connectionListProvider` | `FutureProvider<List<ConnectionConfig>>` | connection_provider.dart:49 | 全部连接 `findAll` |
| `startupValidationProvider` | `FutureProvider<WebDavValidationResult?>` | connection_provider.dart:135 | 启动时静默自检活跃连接（不改 UI 验证状态） |

### 2.3 状态机（恢复/启动验证除外）

```
                reset()
       ┌───────────────────────────────┐
       ▼                                │
   ┌────────┐  validate(formOk)  ┌──────┴────┐
   │  Idle  │ ─────────────────▶│  Loading  │
   └────────┘                   └─────┬─────┘
       ▲                              │
       │ reset()                      │ result.isSuccess
       │                              ▼
   ┌────────┐                   ┌──────────┐
   │ Error  │◀───────────────── │ Success  │
   └────────┘  failed           └──────────┘
       ▲                              │
       │ └─validate(formOk)──重新验证 ┘
       │
       └─ 用户修字段 → onFieldChanged() → reset()
```

(对应代码：`ConnectionValidatorNotifier` connection_provider.dart:80-115)

---

## §3 行为规约（Given-When-Then）

> 这就是 state.md 转移表的等价物，但用 Gherkin-style 表达，便于 LLM 后续从此处派生 test。
> 每条 Scenario 编号 `CON-01-S{n}`，在 §5.1 中作为测试 ID。

### 3.1 Add 屏幕（`ConnectionScreen`）

- **[CON-01-S1]** 表单非法时不发请求
  ```
  Given 用户在添加连接页，URL 为空
  When 点击"测试连接"
  Then 不发起 PROPFIND 请求
  And URL 字段显示"请输入服务器地址"
  ```
  Code evidence: `connection_screen.dart:159` 先 `_formController.validate()`，不通则提前返回

- **[CON-01-S2]** 验证成功后保存按钮可用
  ```
  Given validation 状态为 ValidationSuccess 且未在保存中
  Then "保存"按钮 enabled=true
  And "测试连接"按钮 enabled=true
  ```
  Code evidence: `connection_screen.dart:103` `onPressed: (isValidated && !_isSaving) ? _onSave : null`

- **[CON-01-S3]** Loading 中两按钮都禁用
  ```
  Given 验证进行中（ValidationLoading）
  Then "测试连接"按钮 disabled、显示转圈"连接中…"
  And "保存"按钮 disabled
  ```
  Code evidence: `connection_screen.dart:86` 与 `:103`

- **[CON-01-S4]** 字段变更立即失效旧验证
  ```
  Given ValidationSuccess 已显示绿色横幅
  When 用户在 URL/用户名/密码/basePath 任一框输入字符
  Then 横幅消失，验证状态回到 Idle
  And "保存"按钮重新禁用
  ```
  Code evidence: `connection_screen.dart:151-155` `_onFieldChanged` → `validator.reset()`

- **[CON-01-S5]** 网络异常进入 Error 状态
  ```
  Given ValidationLoading
  When WebDavClient 抛出异常或 result.isSuccess=false
  Then state = ValidationError(result.message ?? 默认文案)
  And 横幅红色显示错误消息
  ```
  Code evidence: `connection_provider.dart:107-111`

- **[CON-01-S6]** 重入保护
  ```
  Given ValidationLoading
  When 再次调用 validate()
  Then 调用被静默忽略
  ```
  Code evidence: `connection_provider.dart:96` `if (state is ValidationLoading) return;`

- **[CON-01-S7]** 保存成功跳转 Browser
  ```
  Given ValidationSuccess 且未在保存中，点击"保存"
  When ConnectionService.save 成功完成
  Then activeConnectionProvider / connectionListProvider 被刷新
  And 路由跳转至 /browser
  ```
  Code evidence: `connection_screen.dart:202-209`

- **[CON-01-S8]** 保存失败 SnackBar + 无残留
  ```
  Given 用户点保存，DB INSERT 成功但 SecureStorage 写入抛异常
  When save() 内部抛出
  Then DB 中该行已被 delete 回滚
  And SecureStorage 不残留临时 key
  And UI 弹 SnackBar"保存失败：…"
  And 保留当前页面，不跳转
  ```
  Code evidence: `connection_service.dart:51-55` 回滚 + rethrow；`connection_screen.dart:210-218`

- **[CON-01-S9]** 启动时已有连接不通则进入"修复"模式
  ```
  Given App 启动，activeConnection 存在且服务器不可达
  When startupValidationProvider 返回 isSuccess=false
  Then 标题显示"修复 WebDAV 连接"
  And 顶部橙色横幅显示"已保存连接验证失败：…"
  ```
  Code evidence: `connection_screen.dart:39-46` + `:51`

### 3.2 Edit 屏幕（`ConnectionEditScreen`）—— 复用表单，门控不同

- **[CON-01-S10]** 只改显示名不需要重新验证
  ```
  Given 编辑页打开，原始 config 在 _originalConfig
  When 用户只修改"显示名称"字段
  Then "保存"按钮 enabled（不需 ValidationSuccess）
  And 点击保存直接成功，不弹"请先测试连接"
  ```
  Code evidence: `edit_screen_logic.dart:65-72` `canSave` 在 needsRevalidation=false 时直接返回 true

- **[CON-01-S11]** URL/用户名/basePath/密码任一改变，需重新验证
  ```
  Given 编辑页，原始 config 在 _originalConfig
  When URL 与原始不同（其它字段未动）
  Then needsValidation=true
  And 需 ValidationSuccess 才能 canSave=true
  ```
  Code evidence: `edit_screen_logic.dart:53-56`

- **[CON-01-S12]** 凭证改了但没验证直接点保存会被拦
  ```
  Given needsValidation=true 且 ValidationStatus != success
  When 用户点击"保存"
  Then 弹红色 SnackBar"请先测试连接后再保存"
  And 不调用 updater.update
  ```
  Code evidence: `connection_edit_screen.dart:230-247`

### 3.3 List 屏幕（`ConnectionListScreen`）—— 切换/删除

- **[CON-01-S13]** 切换活跃连接刷新 Browser 缓存
  ```
  Given 用户在列表页点非活跃连接
  When switchActiveConnectionProvider(id) 完成
  Then 清空 directoryCacheProvider / navigationStackProvider
  And 弹 SnackBar"已切换到「X」"
  And 当前活跃标记更新
  ```
  Code evidence: `connection_list_screen.dart:78-79` 显式 `ref.invalidate`

- **[CON-01-S14]** 删除最后一个连接被拦
  ```
  Given 总连接数 = 1
  When 用户触发删除
  Then 弹"无法删除 / 至少保留一个连接"对话框
  And 不调用 deleteConnectionProvider
  ```
  Code evidence: `connection_list_screen.dart:111-128`

- **[CON-01-S15]** 删除当前活跃连接自动激活另一个
  ```
  Given 删除的是 activeConnection，且总数 > 1
  When deleteConnectionProvider(id) 完成
  Then DAO auto-activate 另一条连接
  And activeConnectionProvider 刷新后仍能返回非 null
  ```
  Code evidence: `connection_service.dart:97-100` 注释 Cascades / 自动激活；`connection_dao.dart` （外部）

---

## §4 不变量（必须永远成立）

每条 INV 须有测试断言（见 §5.2）。

- **[CON-01-INV1]** 同一时刻最多一个 `validate()` 在飞。  
  证据：`connection_provider.dart:96` 重入 guard。
- **[CON-01-INV2]** `reset()` 从任何状态调用都能回到 Idle，永不抛异常。  
  证据：`connection_provider.dart:114` 仅 `state = ValidationIdle()`。
- **[CON-01-INV3]** "保存"按钮仅在 `[ValidationSuccess & 未保存中]` 时可用（添加页）。  
  证据：`connection_screen.dart:103`。
- **[CON-01-INV4]** `ConnectionService.save` 失败时**不留半条连接**——DB row 已删除 + SecureStorage 临时 key 不写入永久 key。
  证据：`connection_service.dart:51-55` catch + Dao.delete + rethrow。
- **[CON-01-INV5]** 同一时刻 DB 中最多一行 `isActive=true`。
  证据：`connection_service.dart:62` 调 `_dao.setActive(id)` 事务切换。
- **[CON-01-INV6]** password 在 DB 中永远不存明文，仅存 `connection_password_{id}` 引用 key；真值只在 SecureStorage。
  证据：`connection_service.dart:48` + dao insert 仅传 passwordKey 字符串。
- **[CON-01-INV7]** Edit 页 _originalConfig 必须用 postFrameCallback 捕获，不能在 build() 里捕获（避免 race / null）。
  证据：`connection_edit_screen.dart:43-46`。

---

## §5 测试规约

### 5.1 现有测试清单（12 份）

| 测试文件 | 估测覆盖的 Scenario/INV | 备注 |
|---|---|---|
| `test/features/connection/con_01_test.dart` | S1, S2, S3, INV1, INV3 | Add 页主流程 |
| `con_02_test.dart` | S9 | 启动验证"修复"模式 |
| `con_03_test.dart` | S10, S11, S12 | Edit 页门控 |
| `con_04_test.dart` | _originalConfig 捕获（INV7） | |
| `con_05_test.dart` | URL hostname 自动填充（form 行为） | |
| `con_06_test.dart` | S5 网络错误入 Error | |
| `con_08_test.dart` | INV4 回滚 | save 失败回滚 |
| `con_09_test.dart` | S13 切换+刷新缓存 | |
| `bug_08_con_test.dart` | —— | 一条具体 bug 回归 |
| `ref_21_test.dart` | —— | 重构回归 |
| `ref_22_test.dart` | —— | 重构回归 |
| `edit_screen_logic_test.dart` | S10, S11 | _needsValidation/canSave 纯函数 |

> 覆盖盲点（dev-plan 后续若改 CON-01 时需补）：**S4 字段变更失效旧验证**、**S6 重入保护**、**S7 跳转断言**、**INV5 同时只有一个 active**、**INV6 密码明文不出现在 DB 行**——目前没有显式断言。

### 5.2 派生测试 ID（dev-exe 派发测试 Agent 用）

按 §3 + §4，本功能完整测试套应有 ID：

```
CON-01-S1 … S15        # 15 个 Scenario
CON-01-INV1 … INV7     #  7 个不变量
CON-01-ALG1 …          # 见 §6 算法样例（若有）
```

dev-exe 要求：派发测试 Agent 时，**每个未覆盖的 ID 必须产出一条 test**；已覆盖的引用现有文件即可。

### §6 算法样例（如有纯函数）

`validateUrl / validateRequired / validateBasePath / validateDdnsHostname / needsValidation / canSave` 都是纯函数，应有样例表：

```
ALG validateUrl:
  ("", null, "   ") → 非空错误          # 必填
  ("192.168.1.1")   → http://192.168.1.1:5005 norm + 通过
  ("http://x:5005") → 通过               # 含端口
  ("nas..com")      → 失败               # 双点
  ("http://")       → 失败               # 没 host
```

(完全枚举此处略；dev-plan 改这些函数时会补全。)

---

## §7 跨模块影响（dev-plan 必填）

修改本功能可能影响以下其它 feature 的不变量，**dev-plan 在做需求分析时必须列出**：

| 其它 feature | 影响点 | 影响条件 |
|---|---|---|
| Browser | 删除/切换连接会影响 `directoryCacheProvider` / `navigationStackProvider` | S13、删除场景 |
| Player | 切换连接后当前正在播放的曲目应该如何处理？ | **目前代码未显式处理——这是已知 gap，dev-plan 若涉及切换/删除时必须 explicit** |
| Progress | `play_progress` 表 ON DELETE CASCADE 连接删除 | DAO 层；INV：删连接后不会留 orphan 进度 |
| Playlist | `playlist` 与连接的绑定（若有） | 待 dev-plan 时 grep 确认 |

---

## §8 平台特性（手动 QA）

本功能**不涉及** audio_service / AudioFocus / MethodChannel / 通知栏——全部可在 `flutter test` 中验证，无需手动 QA。

若未来加入"连接成功后通知栏提示"之类，dev-plan 必须将这条改为 `manual_qa: required` 并产出 `mqa-CON-01.md`。

---

## §9 dev-status.json 条目对照

```json
"CON-01": {
  "spec_file": "docs/features/CON-01.md",
  "spec_anchored_files": [
    "lib/features/connection/connection_screen.dart",
    "lib/features/connection/connection_edit_screen.dart",
    "lib/features/connection/connection_list_screen.dart",
    "lib/features/connection/widgets/connection_form.dart",
    "lib/features/connection/connection_provider.dart",
    "lib/features/connection/domain/connection_service.dart",
    "lib/features/connection/domain/connection_validator.dart",
    "lib/features/connection/domain/edit_screen_logic.dart"
  ],
  "scenarios": ["CON-01-S1" ... "CON-01-S15"],
  "invariants": ["CON-01-INV1" ... "CON-01-INV7"],
  "test_files": [
    "test/features/connection/con_01_test.dart",
    "...",
    "test/features/connection/edit_screen_logic_test.dart"
  ],
  "test_coverage_gaps": [
    "S4", "S6", "S7", "INV5", "INV6"
  ],
  "cross_module_impacts": ["BRW", "PRG", "PLY"],
  "manual_qa_required": false,
  "user_acceptance_text": "见 §1.2 用户期望的场景表"
}
```

---

## 附：本份样本和原 state.md §1 Connection 的对照

| 原 state.md | 本份 CON-01.md | 变化点 |
|---|---|---|
| 转移表（From/Trigger/Action/To） | §3 Given-When-Then 表 | 表达等价，BDD 风格更通用 |
| 不变量段 | §4 不变量段 | 不变 |
| 原子保存流程 5 步 | §3 S8 INV4 | 拆成 Scenario + INV 双重断言 |
| 编辑页验证门控逻辑 | §3 S10/S11/S12 | 显式化为 Scenario |
| 列表页切换/删除 | §3 S13/S14/S15 | 原 state.md 几乎没专门描述，本份新增 |
| 跨模块影响 | §7 | 原 state.md §9 整段；本份只列与 CON 相关行 |
| 算法样例 | §6 | 原 state.md 几乎不写算法样例 |
| 用户视角可审表 | §1.2 | **新增**——你能扫的部分，anchor 于公司流程 |
| 代码锚点 | §2 | **新增**——LLM 实现时定位证据 |
| 测试清单 / 覆盖盲点 | §5 | **新增**——LLM 实现后验证门禁依据 |
| 手动 QA 门禁 | §8 | **新增**——区分自动可测 vs 只能真机 |