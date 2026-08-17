# REF-07 — importPlaylist 空名称归一默认名（服务层校验，UI 创建门禁语义对齐）

## §0 头部元数据

```yaml
id: REF-07
name: importPlaylist 空名/纯空格名归一默认名（服务层裁决）
priority: P2
status: active
created_at: 2026-08-16
last_updated: 2026-08-16
spec_anchored_files:
  - lib/features/playlist/domain/playlist_service.dart
  - lib/features/playlist/playlist_list_screen.dart
cross_module_impacts: [PLT]   # playlist 自身（import/export 链路 + 列表展示）
manual_qa_required: false     # 纯 Dart 服务层 JSON 解析逻辑，全可单测，不涉平台原生
```

---

## §1 用户视角

### 1.0 原始需求（用户原话逐字记录）

来源：`docs/cr/cr-20260816-0804-connection-playlist.md` D1（cr 复核分流，用户裁决"修"→ 转 REF 需求流程，无复现测试要求）：

> #### D1. importPlaylist 接受空字符串名称，产生无名播放单（UI 创建门禁被绕过）
> - 类型 / 严重度 / 维度：DESIGN / Minor / 功能-状态机（导入边界裁决）
> - 证据：`lib/features/playlist/domain/playlist_service.dart:162` — `data['name'] is String ? data['name'] as String : '导入的播放单'`，空串 `''` 不归"缺失"分支；UI 侧创建门禁 `playlist_list_screen.dart:167-168` 拦截空名
> - 现象：导入 `{"name":"","tracks":[]}` → 列表出现无名播放单；`exportPlaylist`（:121-134）可导出空名单再导入，往返保持空名。取舍：导入器是否应把空串归一为默认名（与"缺失"同语义），或允许空名作为合法边界。写不出崩溃/错乱复现，故不列 BUG。
> - 修复建议：裁决后二选一——`name.trim().isEmpty` 归默认名，或显式文档化空名合法。

用户裁决：**空名归默认名**——`name.trim().isEmpty` 时归默认名 `'导入的播放单'`（与"缺失"字段同语义），不允许空名作为合法边界。

### 1.1 这一功能干什么（一句话）

导入播放单时，名称字段为空字符串或纯空白时，自动使用默认名"导入的播放单"——与名称字段缺失时的行为一致，杜绝列表中出现无名播放单。

### 1.2 用户期望的场景

| ID | 你看到的样子 | 期望行为 |
|----|----|----|
| U1 | 导入的播放单文件里没有"名称"字段 | 导入后自动叫"导入的播放单"（现状保持） |
| U2 | 导入的播放单文件里名称是空的（或只有空格） | 导入后自动叫"导入的播放单"（修复前：列表出现一个没有名字的播放单） |
| U3 | 导入的播放单文件里名称是" 我的歌单 "（前后带空格） | 名称原样保存为" 我的歌单 "（不做额外修剪，现状保持） |
| U4 | 新建播放单对话框里不填名称直接点"创建" | 不创建任何播放单（现状保持，UI 门禁不归本修改范围） |
| U5 | 修复前已经产生的无名播放单，导出再导入 | 再导入后变成"导入的播放单"（修复后行为）；已存在的无名播放单不会被追溯改名 |

---

## §2 已实现的功能骨架（代码锚点）

### 2.1 文件与分层

| 层 | 文件 | 行数 | 角色 |
|---|---|---|---|
| Domain | `lib/features/playlist/domain/playlist_service.dart` | 203 | `importPlaylist`（147-202）：JSON 解码 → name 解析（:162）→ tracks 解析（:170-180）→ insertPlaylist（:182-186）→ addTracks（:197-199）；`exportPlaylist`（121-134） |
| Provider | `lib/features/playlist/playlist_provider.dart` | 167 | `importPlaylistProvider`（159-167）：调 service.importPlaylist + invalidate playlistListProvider |
| UI | `lib/features/playlist/playlist_list_screen.dart` | 281 | `_CreatePlaylistDialog`（134-177）：创建门禁 `name.trim()` 后空名 return（:167-168）——**仅创建路径**，导入无 UI 入口（grep 全 lib：importPlaylistProvider 只有 shared/di 桥接 re-export，无 UI 调用方） |
| 桥接 | `lib/shared/di/providers.dart` | 250 | `importPlaylistProvider` re-export（:228） |
| 测试 | `test/features/playlist/ref_26_test.dart` | 384 | import 组（248-384）：缺失名 → 默认名（:288-296）、空 JSON（:341-351）、往返（:353-379）等 |
| 测试 | `test/features/playlist/bug_bug25_repro_test.dart` | ~190 | BUG-25-S1 结构健壮性（name 非 String 形态 :145/:154） |

### 2.2 关键 Provider 表

| Provider 名 | 类型 | 实现位置 | 用途 |
|---|---|---|---|
| importPlaylistProvider | Provider<Future<int> Function(String jsonString)> | playlist_provider.dart:159-167 | 导入入口（当前零 UI 调用方，供测试/未来 UI 使用） |
| playlistListProvider | FutureProvider<List<Playlist>> | playlist_provider.dart:73-79 | 播放单列表（导入后 invalidate） |

### 2.3 状态机图

本功能无状态机（JSON 解析纯函数段），跳过。

---

## §3 行为规约（Given-When-Then）

### 3.1 现有行为（逆抽，缺陷态）

- **[REF-07-S1]** name 字段缺失或非 String → 归默认名 `'导入的播放单'`
  ```
  Given JSON 无 name 字段（'{"tracks":[]}'）或 name 为 123（非 String）
  When importPlaylist(jsonString)
  Then data['name'] is String == false → name = '导入的播放单'
  And 创建 name=='导入的播放单' 的播放单行
  ```
  Code evidence: `lib/features/playlist/domain/playlist_service.dart:162`（三元非 String 分支）；BUG-25-S1 结构性健壮性裁决（:158-161 注释）
  测试锚定：`test/features/playlist/ref_26_test.dart:288-296`（缺失名）、`:341-351`（空 JSON）；`bug_bug25_repro_test.dart:145-154`（name:123）。

- **[REF-07-S2]** name 为空字符串 `''`（is String 为 true）→ 原样透传，创建无名播放单（缺陷态）
  ```
  Given JSON '{"name":"","tracks":[]}'
  When importPlaylist(jsonString)
  Then data['name'] is String == true → name = ''（空串不归缺失分支）
  And 创建 name=='' 的播放单行 → 列表出现无名播放单
  ```
  Code evidence: `lib/features/playlist/domain/playlist_service.dart:162`（`is String` 对 `''` 成立，无 trim 检查）
  缺陷态锚定：零锚定（ref_26/bug_bug25 全部 import 用例无空串 name 输入）——§5.3 盲点，§5.4 门禁补缺陷态用例。

- **[REF-07-S3]** exportPlaylist 原样导出 name，空名单往返保持空名（缺陷态）
  ```
  Given DB 中存在 name=='' 的播放单
  When exportPlaylist(id) 后再 importPlaylist(导出的 JSON)
  Then 导出 JSON 'name':''（:128）→ 再导入 name 仍为 ''（S2 缺陷态）→ 往返保持空名
  ```
  Code evidence: `lib/features/playlist/domain/playlist_service.dart:127-133`（`'name': playlist.name` 原样导出）；cr-0804 D1 原文确认

### 3.2 修改方案（status: new）

设计裁决（用户裁决"空名归默认名"）：

| 边界情况 | 裁决 |
|---|---|
| name 缺失 / 非 String（如 123） | 归默认名 `'导入的播放单'`（现有行为，:162 三元非 String 分支保持） |
| name == `''`（空字符串） | **NEW**：`trim().isEmpty` → 归默认名 `'导入的播放单'` |
| name 为纯空白（如 `'   '`、`'\t'`） | **NEW**：`trim().isEmpty` → 归默认名 `'导入的播放单'` |
| name 为 `'  X  '`（trim 后非空） | 原样保存 `'  X  '`（**不做一般性 trim**——最小行为变更，现有行为保持；与 UI 创建门禁的 trim 语义不一致是既有事实，不在本修改范围） |
| createPlaylist('')（服务层直接调用，绕过 UI 门禁） | **不改**：仍原样透传（cr D1 范围仅 importPlaylist；UI 创建门禁 playlist_list_screen.dart:167-168 保持为创建路径的唯一门禁） |
| 修复前已落库的空名播放单 | **不追溯改名**（无数据迁移；下次导出再导入时自然归一为默认名，U5） |

- **[REF-07-S4]** importPlaylist 空串名 → 归默认名 `'导入的播放单'` （status: new）
  ```
  Given JSON '{"name":"","tracks":[{"filePath":"/a.mp3","fileName":"a.mp3"}]}'
  When importPlaylist(jsonString)
  Then name 解析：is String==true 但 trim().isEmpty → 归 '导入的播放单'
  And 创建 name=='导入的播放单' 的播放单行，tracks 正常导入（1 条）
  And 返回值为新建播放单 id（> 0）
  否定断言:
    - 数据库行 name 不得为空字符串（findAllPlaylists 读回 name == '导入的播放单'）
    - tracks 导入行为不得改变（空名裁决不影响去重/空 path 跳过逻辑 :170-180）
    - 不得抛出任何异常（空串是合法输入）
  ```
  **修改点（唯一生产代码改动）**：`lib/features/playlist/domain/playlist_service.dart:162`：
  ```dart
  // 修改前（162 行）:
  final name = data['name'] is String ? data['name'] as String : '导入的播放单';
  // 修改后:
  // REF-07: 空串/纯空白名归默认名（与"缺失"同语义，cr-20260816-0804 D1）。
  final rawName = data['name'];
  final name = (rawName is String && rawName.trim().isNotEmpty)
      ? rawName
      : '导入的播放单';
  ```
  **注意**：dev-exe 修改后 `dart format`（多行声明自动格式化）。修改点不触碰 :158-161 的 BUG-25-S1 is-check 结构（仍以 `is String` 判定类型，仅新增 trim 检查）。

- **[REF-07-S5]** importPlaylist 纯空白名 → 归默认名 （status: new）
  ```
  Given JSON '{"name":"   ","tracks":[]}'（纯空格）或 '{"name":"\t"}'（制表符）
  When importPlaylist(jsonString)
  Then rawName.trim().isEmpty == true → name = '导入的播放单'
  否定断言:
    - 创建的行 name 不得为空白（读回 == '导入的播放单'）
    - 不得改变 tracks 行为（tracks 缺失 → 空列表，现有 :163-164 保持）
  ```
  Code evidence（修改点）: `playlist_service.dart:162`（修改后 `rawName.trim().isNotEmpty` 判定）。

- **[REF-07-S6]** trim 后非空名称原样保存（不做一般性 trim） （status: new）
  ```
  Given JSON '{"name":"  My List  ","tracks":[]}'
  When importPlaylist(jsonString)
  Then rawName.trim().isNotEmpty == true → name = '  My List  '（原样）
  否定断言:
    - 名称不得被修剪为 'My List'（保持原样——一般性 trim 不在裁决范围）
    - 缺失/空名归一逻辑不受影响（S1/S4/S5 行为独立成立）
  ```
  Code evidence（修改点）: `playlist_service.dart:162`（修改后仅 trim 用于 isEmpty 判定，赋值用 rawName）。

- **[REF-07-S7]** 空名播放单导出再导入 → 导入后为默认名 （status: new）
  ```
  Given DB 存在 name=='' 的播放单（修复前产生或服务层直建）
  When exportPlaylist(id) 得到 '{"name":"",...}'，再 importPlaylist 该 JSON
  Then 导出内容不变（'name':'' 原样导出，:128 不改）
  And 再导入时 S4 裁决生效 → 新行 name == '导入的播放单'
  否定断言:
    - 已存在的空名行不得被追溯改名（export 不产生副作用）
    - 导出的 JSON 不得在导出端被改写（导出语义零变更）
  ```
  Code evidence（修改点）: `playlist_service.dart:162`（修改后）+ `:127-133`（export 保持不改）。

- **[REF-07-S8]** createPlaylist 服务层行为保持（空名原样透传，门禁仍在 UI 层） （status: new）
  ```
  Given 直接调用 service.createPlaylist('')
  When 创建播放单
  Then 行为与修复前一致：name='' 原样传入 DAO insert（无服务层校验）
  And UI 创建门禁 playlist_list_screen.dart:167-168（trim 后空名 return）保持为创建路径唯一门禁
  否定断言:
    - createPlaylist 不得新增 trim/默认名逻辑（本 REF 范围仅 importPlaylist，:35-42 不改）
    - UI 门禁行为不变（新建对话框空名不创建、不报错）
  ```
  Code evidence: `lib/features/playlist/domain/playlist_service.dart:35-42`（createPlaylist 现状）+ `playlist_list_screen.dart:166-171`（UI 门禁现状，不改）。

---

## §4 不变量

- **[REF-07-INV1]** importPlaylist 创建的播放单行 name 必非空（trim 后）
  证据：`playlist_service.dart:162`（修改后 `rawName.trim().isNotEmpty` 才用原始值，否则默认名）——任一输入下 name 均为 `'导入的播放单'` 或 trim 非空串。

- **[REF-07-INV2]** importPlaylist 对任意合法/结构异常 JSON 不抛 TypeError / NoSuchMethodError（BUG-25-INV1 结构健壮性保持）
  证据：`playlist_service.dart:148-164`（is-check 结构）+ 修改点仅新增 trim 判定，`data['name']` 的类型检查路径不变；`bug_bug25_repro_test.dart:131-186` 锚定。

---

## §5 测试规约

### 5.1 现有测试清单

| 测试文件 | 覆盖的 Scenario / INV | 备注 |
|---|---|---|
| test/features/playlist/ref_26_test.dart:288-296 | REF-07-S1 | 缺失名 → 默认名；修复后保持绿 |
| test/features/playlist/ref_26_test.dart:341-351 | REF-07-S1 | 空 JSON `{}` → 默认名；保持绿 |
| test/features/playlist/ref_26_test.dart:353-379 | REF-07-S7 前半（export 往返） | 非空名往返 name 保持；保持绿 |
| test/features/playlist/bug_bug25_repro_test.dart:145-186 | REF-07-S1（name:123 等结构形态）、REF-07-INV2 | 保持绿 |
| test/features/playlist/ply_10_test.dart:481-622 | importPlaylistProvider 链路 | 全部非空名输入（grep 核实无空串 name 用例）；签名不改 → 保持绿 |

### 5.2 测试 ID 派生清单（dev-exe 派发测试 Agent 用）

```
REF-07-S1 … S8        # Scenario（S1~S3 现状锚定含缺陷态，S4~S8 修复目标）
REF-07-INV1 … INV2    # 不变量
```

dev-exe 要求：S1 由 ref_26/bug_bug25 既有用例覆盖；S2/S3 缺陷态与 S4~S8、INV1/2 由 §5.4 门禁文件覆盖。

### 5.3 测试覆盖盲点（dev-plan 写本文档时识别）

| 未覆盖 ID | 现状 | 应补偿方式 |
|---|---|---|
| REF-07-S2（空串名缺陷态）、S3（往返保持空名缺陷态） | 零锚定（全部 import 用例无空串 name 输入） | §5.4 门禁文件先按缺陷态断言（修复前 PASS 即当前缺陷），dev-exe 修复后翻转 |
| REF-07-S5/S6（纯空白 / trim 后非空） | 零锚定 | §5.4 门禁文件 |
| REF-07-S8（createPlaylist 不改） | ply_11 PLY-T56 只测创建成功 | §5.4 门禁文件补 createPlaylist('') 原样透传断言 |

### 5.4 测试文件位置（spec-scan --gate 硬校验）

新建：`test/features/playlist/ref_07_import_name_test.dart`（PlaylistService + 内存测试库直测，手法同 ref_26_test；命名已核实与既有文件无冲突）

| 测试文件 | 覆盖 ID | 说明 |
|---|---|---|
| test/features/playlist/ref_07_import_name_test.dart | REF-07-S2、S3、S4、S5、S6、S7、S8、REF-07-INV1、REF-07-INV2 | 门禁：dev-exe 修复后必须 PASS（cov-gate 内） |
| test/features/playlist/ref_26_test.dart / bug_bug25_repro_test.dart / ply_10_test.dart | REF-07-S1 | 既有文件，断言不变，修复后保持绿 |

---

## §6 算法样例

```
ALG [REF-07-ALG1-normalizeImportName]:
  输入: name 缺失 → 期望: '导入的播放单'                                  # 主流程（现有）
  输入: name = 123（非 String）→ 期望: '导入的播放单'                      # 主流程（现有）
  输入: name = '' → 期望: '导入的播放单'（trim().isEmpty）                  # 边界（新）
  输入: name = '   ' → 期望: '导入的播放单'（纯空白）                       # 边界（新）
  输入: name = '  X  ' → 期望: '  X  '（原样，不做一般性 trim）             # 边界（裁决：不改）
  输入: name = 'X' → 期望: 'X'                                            # 主流程
```

---

## §7 跨模块影响

`bash cross-imports.sh impact lib/features/playlist/domain/playlist_service.dart`（2026-08-16）→ 引用方：

| 其它 feature | 影响点 | 影响条件 | 需要补的回归断言 |
|---|---|---|---|
| Playlist（playlist_provider.dart:159-167） | importPlaylistProvider 仅透传 jsonString，不经 name | 无（service 签名不变，仅内部 name 解析改一行） | ply_10 import 链路用例保持绿 |
| Playlist UI（playlist_list_screen.dart:166-171） | 创建门禁（:167-168 trim+空名 return）与本 REF 无关 | 不改 | ply_11 创建用例保持绿 |
| 桥接（shared/di/providers.dart:228） | importPlaylistProvider re-export | 无 | 编译 + analyze 0 warning |
| 导出链路（playlist_service.dart:121-134 exportPlaylist） | export 语义零变更（:128 原样导出 name） | 无 | ref_26 往返用例保持绿 |
| BUG-25（bug_bug25_repro_test.dart:131-186） | 结构健壮性 is-check 路径 | 修改点保留 is-check 结构，仅新增 trim 判定 | BUG-25-S1 相关用例保持绿 |
| BUG-11（连接添加入口） | **无关**：BUG-11 为连接 feature 入口可达性，本 REF 为 playlist 导入名裁决，无交集 | 无 | 无 |

---

## §8 平台特性与手动 QA

设计前已逐条核对 `docs/dev/platform-pitfalls.md`：本 REF 为纯 Dart 服务层 JSON 解析裁决，不触及任何踩坑条目（P1~P17 均不相关——无音频/生命周期/并发/时间/超时/平台通道）。

**真机风险列**：

| 风险 | 近似测试方案 | 测不了 → 进 mqa-backlog |
|---|---|---|
| 真实"播放单导出文件"中的空名/纯空白名形态与 fixture 假设不符 | 单测 fixture 覆盖 '' / '   ' / '\t' / '  X  ' 四种形态（S4/S5/S6） | 无（行为全部可在 `flutter test` 中验证，不涉平台原生） |

本功能不涉及平台原生特性，全部可在 `flutter test` 中验证 → `manual_qa_required = false`。

---

## §9 dev-status.json 条目对照

```json
"REF-07": {
  "spec_file": "docs/features/REF-07.md",
  "spec_anchored_files": [
    "lib/features/playlist/domain/playlist_service.dart",
    "lib/features/playlist/playlist_list_screen.dart"
  ],
  "scenarios": ["REF-07-S1", "REF-07-S2", "REF-07-S3", "REF-07-S4", "REF-07-S5", "REF-07-S6", "REF-07-S7", "REF-07-S8"],
  "invariants": ["REF-07-INV1", "REF-07-INV2"],
  "algorithms": ["REF-07-ALG1-normalizeImportName"],
  "manual_qa_required": false,
  "user_acceptance_text": "见 §1.2"
}
```
