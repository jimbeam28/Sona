# REF-02 — 值对象 ==/hashCode 字段集统一规则 + 集中登记（防 P12）

## §0 头部元数据

```yaml
id: REF-02
name: 值对象相等性统一规则与集中登记表
priority: P2
status: active
created_at: 2026-08-16
last_updated: 2026-08-16
spec_anchored_files:
  - lib/shared/models/connection_config.dart
  - lib/shared/models/play_progress.dart
  - lib/shared/models/playlist.dart
  - lib/shared/models/nas_file.dart
  - lib/shared/models/play_queue.dart
cross_module_impacts: [CON, PRG, PLT, PLY, BRW]   # 全部共享模型消费方
manual_qa_required: false                          # 纯 Dart 值对象，无平台原生
```

---

## §1 用户视角

### 1.0 原始需求（用户原话逐字记录）

来源：`docs/cr/cr-20260816-0801-core-shared.md` D2（cr 复核分流，用户裁决"修"→ 转 REF 需求流程）：

> #### D2. 值对象 ==/hashCode 字段集跨模型不一致，加字段时 P12 风险面更大
> - 类型 / 严重度 / 维度：DESIGN / Info / 正确性（P12 交叉）
> - 证据：`ConnectionConfig` ==/hashCode 含全部 8 字段（connection_config.dart:90-105）；`PlayProgress` 不含 id/lastPlayedAt（play_progress.dart:107-118）；`Playlist` 不含 createdAt/updatedAt（playlist.dart:60-69）；`PlaylistTrack` 不含 addedAt（playlist.dart:123-133）。
> - 取舍分析：每个模型内部四处同步（== / hashCode / copyWith / fromMap·toMap）自洽，且 model_equality_test.dart:220-225、310-318 用否定断言显式锚定了"id/addedAt 不参与相等"的取舍——这是有意设计，非缺陷。但跨模型策略不一致（ConnectionConfig 全字段、其余按业务语义裁剪），后续任何模型加字段时，"加 ==/hashCode 还是加排除清单"需逐模型重新判断，P12 踩坑概率高于统一策略。
> - 修复建议：在模型文件或文档中统一声明"相等性 = 业务身份字段集，时间戳/自增 id 是否入集按语义单例裁决"的规则并集中登记，避免逐模型自由发挥。

用户裁决：**修**——落地统一规则 + 代码化集中登记表（不动任何模型现有相等性语义）。

### 1.1 这一功能干什么（一句话）

为全部共享值对象（ConnectionConfig / PlayProgress / Playlist / PlaylistTrack / NasFile / PlayQueue）确立"字段入等"的统一决策规则，并把每个模型的入等/除外字段集登记到一份代码化登记表，使将来加字段时"入等还是除外"是机械裁决而非逐模型自由发挥（防 P12 静默不刷新）。

### 1.2 用户期望的场景

| ID | 你看到的样子 | 期望行为 |
|----|----|----|
| U1 | 在连接列表 / 播放记录 / 播放单之间切换使用 | 界面刷新与更新行为与之前完全一致（本次修改不改任何模型的比较语义，纯新增规则与登记） |
| U2 | 将来给某个数据模型加新字段 | 新字段默认参与比较（界面随数据变化正常刷新）；确实需要"不影响比较"的字段（自增编号、记录时间戳）按统一规则登记豁免并配测试，不再需要每次拍脑袋 |

---

## §2 已实现的功能骨架（代码锚点）

### 2.1 文件与分层

| 层 | 文件 | 行数 | 角色 |
|---|---|---|---|
| Shared | `lib/shared/models/connection_config.dart` | 111 | == 全 8 字段（90-101）/ hashCode（104-105）/ copyWith（68-88）/ fromMap·toMap（39-66） |
| Shared | `lib/shared/models/play_progress.dart` | 119 | == 4 字段（107-114）/ hashCode（117-118）/ copyWith（83-100）/ fromMap·toMap（56-78） |
| Shared | `lib/shared/models/playlist.dart` | 134 | Playlist == 3 字段（60-66）/ hashCode（69）；PlaylistTrack == 4 字段（123-130）/ hashCode（133） |
| Shared | `lib/shared/models/nas_file.dart` | 229 | == 全 6 字段（215-224）/ hashCode（227-228）/ copyWith（189-208） |
| Shared | `lib/shared/models/play_queue.dart` | 422 | == 含 shuffle 内部状态（391-400）/ hashCode（402-409） |
| 测试 | `test/shared/model_equality_test.dart` | 389 | REF-07 段（36-107）/ TEST-10-S2~S6（114-388）：正反断言锚定各模型相等性 |

### 2.2 关键 Provider 表

本功能不涉 Provider（纯值对象语义层），跳过。

### 2.3 状态机图

无状态机，跳过。

---

## §3 行为规约（Given-When-Then）

### 3.1 现有行为（逆抽）

- **[REF-02-S1]** ConnectionConfig ==/hashCode 含全部 8 字段（id/name/url/username/basePath/isActive/createdAt/updatedAt）
  ```
  Given 两个 ConnectionConfig 仅 id（或 createdAt / updatedAt 任一）不同，其余相同
  When 比较 == 或 hashCode
  Then 不相等（全字段参与）
  ```
  Code evidence: `lib/shared/models/connection_config.dart:90-105`；锚定：`test/shared/model_equality_test.dart:36-107`（REF-07 段，含 id/createdAt/updatedAt 负面断言 55-97）。

- **[REF-02-S2]** PlayProgress ==/hashCode 含 4 字段（connectionId/filePath/positionMs/durationMs），id 与 lastPlayedAt 除外
  ```
  Given 两个 PlayProgress 仅 id 不同，其余相同
  When 比较 == / hashCode
  Then 相等（id 是 DB 自增主键，不参与业务相等）
  ```
  Code evidence: `lib/shared/models/play_progress.dart:107-118`；id 除外锚定：`test/shared/model_equality_test.dart:220-225`（否定断言）；**lastPlayedAt 除外零锚定（缺口，§5.3）**。

- **[REF-02-S3]** Playlist ==/hashCode 含 3 字段（id/name/trackCount），createdAt 与 updatedAt 除外
  ```
  Given 两个 Playlist 仅 createdAt/updatedAt 不同，其余相同
  When 比较 == / hashCode
  Then 相等（审计时间戳不参与）
  ```
  Code evidence: `lib/shared/models/playlist.dart:60-69`；**createdAt/updatedAt 除外零锚定（缺口，§5.3）**；id/name/trackCount 参与锚定：`test/shared/model_equality_test.dart:251-261`。

- **[REF-02-S4]** PlaylistTrack ==/hashCode 含 4 字段（id/playlistId/filePath/fileName），addedAt 除外
  ```
  Given 两个 PlaylistTrack 仅 addedAt 不同，其余相同
  When 比较 == / hashCode
  Then 相等（addedAt 不参与）
  ```
  Code evidence: `lib/shared/models/playlist.dart:123-133`；addedAt 除外锚定：`test/shared/model_equality_test.dart:310-318`（否定断言）；其余字段参与锚定：293-308。

- **[REF-02-S5]** NasFile 与 PlayQueue ==/hashCode 全字段参与（无除外）
  ```
  Given NasFile 仅任一字段（含 modifiedAt）不同 / PlayQueue 仅任一字段（含 shuffle 内部态）不同
  When 比较 == / hashCode
  Then 不相等
  ```
  Code evidence: `lib/shared/models/nas_file.dart:215-228`（modifiedAt 为内容时间戳，入等）；`lib/shared/models/play_queue.dart:391-409`（含 _shuffleOrder/_shufflePosition）；锚定：`test/shared/model_equality_test.dart:114-181`（TEST-10-S2）/ 327-388（TEST-10-S6）。

### 3.2 修改方案（status: new）

**统一规则（单源化，写入新增登记表文件头部）**：

1. **默认入等**：值对象新增任何字段必须同时进入 `==` 与 `hashCode`，并与 `copyWith` / `fromMap`·`toMap` 同步（四同步，REF-02-INV1）。
2. **例外资格仅限两类字段**：自增 DB 主键（`id`）；审计时间戳（`createdAt` / `updatedAt` / `lastPlayedAt` / `addedAt`）。内容时间戳（如 `NasFile.modifiedAt`）永远入等。
3. **例外裁决**：相等性 = 业务身份字段集；选择"除外"必须同时满足 (a) 登记进 `equality_registry.dart` 的 `entries` 表；(b) 有否定断言测试锚定（"该字段不同仍相等"）。
4. **登记表是唯一登记点**（单源）：dev-plan / dev-check / cr 走查一律以 `equality_registry.dart` 为核对基准，不在 spec / INDEX 中重复登记。

**现有 4 个模型的除外/入等语义全部保持**（S1~S5 锚定不变，model_equality_test.dart 既有断言一行不改）——本 REF 只新增登记表、模型文件注释、补缺测试锚定，不改变任何模型行为。

- **[REF-02-S6]** 新增 `lib/shared/models/equality_registry.dart` 集中登记表（6 模型全量登记） （status: new）
  ```
  Given 新建文件 lib/shared/models/equality_registry.dart
  When dev-plan / dev-check / cr 核对任一共享值对象的相等性字段集
  Then entries 表含 6 条记录，逐条与各模型 == 实现一致（REF-02-INV2）
  And 表头注释声明统一规则 4 条（默认入等 / 例外资格 / 例外三要素 / 唯一登记点）
  否定断言:
    - 不得改动任何既有模型文件中的 ==/hashCode/copyWith/fromMap·toMap 实现（纯新增）
    - 登记表不得遗漏任一共享值对象（ConnectionConfig/PlayProgress/Playlist/PlaylistTrack/NasFile/PlayQueue 六者缺一即违规）
  ```
  **修改点（新建文件）**——`lib/shared/models/equality_registry.dart` 全文（弱模型照抄）：
  ```dart
  // lib/shared/models/equality_registry.dart
  // REF-02 值对象相等性统一规则与集中登记（cr-20260816-0801 D2 裁决落地）。
  //
  // 统一规则:
  //   1. 默认入等: 值对象新增任何字段必须同时进入 == 与 hashCode，
  //      并与 copyWith / fromMap·toMap 同步（四同步不变量）。
  //   2. 例外资格仅限两类字段: 自增 DB 主键 (id)；审计时间戳
  //      (createdAt / updatedAt / lastPlayedAt / addedAt)。
  //      内容时间戳（如 NasFile.modifiedAt）永远入等。
  //   3. 例外裁决: 相等性 = 业务身份字段集；选择"除外"必须同时满足
  //      (a) 登记进本文件 entries 表；(b) 有否定断言测试锚定
  //      （"该字段不同仍相等"）。
  //   4. 本表是唯一登记点: dev-plan / dev-check / cr 以此核对各模型 == 实现。

  /// 单条登记：模型名 / 入等字段（逗号分隔）/ 除外字段 + 理由。
  class EqualityRule {
    final String model;
    final String equalityFields;
    final String exclusions;

    const EqualityRule(this.model, this.equalityFields, this.exclusions);
  }

  /// 共享值对象相等性集中登记表（与各模型 == 实现逐条一致，REF-02-INV2）。
  class EqualityRegistry {
    const EqualityRegistry._();

    static const List<EqualityRule> entries = [
      EqualityRule('ConnectionConfig',
          'id,name,url,username,basePath,isActive,createdAt,updatedAt',
          '无（全 8 字段入等，REF-07 锚定）'),
      EqualityRule('PlayProgress',
          'connectionId,filePath,positionMs,durationMs',
          'id（DB 自增主键）; lastPlayedAt（审计时间戳）'),
      EqualityRule('Playlist', 'id,name,trackCount',
          'createdAt,updatedAt（审计时间戳）'),
      EqualityRule('PlaylistTrack', 'id,playlistId,filePath,fileName',
          'addedAt（审计时间戳）'),
      EqualityRule('NasFile',
          'name,path,isDirectory,size,modifiedAt,audioType',
          '无（modifiedAt 为内容时间戳，必入等）'),
      EqualityRule('PlayQueue',
          'files,currentIndex,startPositionMs,playMode,_shuffleOrder,_shufflePosition',
          '无（全字段入等）'),
    ];
  }
  ```
  **代码无消费者是设计意图**（登记表是审计面非执行面，供 dev-plan/dev-check/cr 与测试核对），analyze 不得报未使用告警（顶层 const 类定义不触发 unused 规则）。

- **[REF-02-S7]** 6 个模型文件头部注释引用统一规则 （status: new）
  ```
  Given equality_registry.dart 已存在
  When 打开任一共享值对象模型文件
  Then 文件头部注释（第 1-2 行区域）含一句登记引用，格式:
       '// 相等性规则与登记：见 equality_registry.dart（REF-02）'
  否定断言:
    - 除注释外不得改动模型文件任何代码行
  ```
  **修改点**（每文件仅加注释，`===` 号为新增行）：
  - `lib/shared/models/connection_config.dart:1-4`（原头部注释 3 行后追加）
  - `lib/shared/models/play_progress.dart:1-6`（原头部注释后追加）
  - `lib/shared/models/playlist.dart:1-4`（原头部注释后追加）
  - `lib/shared/models/nas_file.dart:1-2`（原头部注释后追加）
  - `lib/shared/models/play_queue.dart:1-9`（原头部注释后追加）

- **[REF-02-S8]** 补锚定：PlayProgress.lastPlayedAt 除外（现有行为，补否定断言测试）
  ```
  Given 两个 PlayProgress 仅 lastPlayedAt 不同（id 相同、业务字段相同）
  When 比较 == / hashCode
  Then 相等（lastPlayedAt 不参与，与 play_progress.dart:107-118 现有实现一致）
  否定断言:
    - 业务字段（positionMs / durationMs / filePath / connectionId）任一不同 → 仍不相等
  ```
  Code evidence: `lib/shared/models/play_progress.dart:107-118`（现有 == 已排除 lastPlayedAt）；测试落位 §5.4。

- **[REF-02-S9]** 补锚定：Playlist.createdAt/updatedAt 除外（现有行为，补否定断言测试）
  ```
  Given 两个 Playlist 仅 createdAt 与 updatedAt 不同（id/name/trackCount 相同）
  When 比较 == / hashCode
  Then 相等（审计时间戳不参与，与 playlist.dart:60-69 现有实现一致）
  否定断言:
    - id / name / trackCount 任一不同 → 仍不相等
  ```
  Code evidence: `lib/shared/models/playlist.dart:60-69`（现有 == 已排除 createdAt/updatedAt）；测试落位 §5.4。

---

## §4 不变量

- **[REF-02-INV1]** 四同步：每个共享值对象的 `==` / `hashCode` / `copyWith` / `fromMap`·`toMap` 字段集同步演进（P12 规避核心）
  证据：`connection_config.dart:39-105` / `play_progress.dart:56-118` / `playlist.dart:21-133` / `nas_file.dart:89-228`（各模型四处齐备）；P12 踩坑库 `docs/dev/platform-pitfalls.md:82-86`（91a9ed6 BUG-01 判例）。

- **[REF-02-INV2]** 登记表与实现一致：`equality_registry.dart` 的 entries 逐条等于各模型 `==` 实现的字段集
  证据：`equality_registry.dart`（S6 新建）+ `connection_config.dart:90-105` / `play_progress.dart:107-118` / `playlist.dart:60-69`、`123-133` / `nas_file.dart:215-228` / `play_queue.dart:391-409`；测试见 §5.4。

- **[REF-02-INV3]** 例外资格闭合：任何模型的除外字段必须属于 {自增 id} ∪ {审计时间戳} 之一
  证据：`equality_registry.dart` 头部规则第 2 条（S6 新建）+ 现有全部除外字段（id / lastPlayedAt / createdAt / updatedAt / addedAt）均在闭集内。

---

## §5 测试规约

### 5.1 现有测试清单

| 测试文件 | 覆盖的 Scenario / INV | 备注 |
|---|---|---|
| test/shared/model_equality_test.dart:36-107 | REF-02-S1 | REF-07 段：全 8 字段正反断言，**断言一行不改** |
| test/shared/model_equality_test.dart:188-226 | REF-02-S2（id 除外部分） | TEST-10-S3：含 id 除外否定断言（220-225） |
| test/shared/model_equality_test.dart:232-262 | REF-02-S3（参与字段部分） | TEST-10-S4：id/name/trackCount 负面 |
| test/shared/model_equality_test.dart:268-319 | REF-02-S4 | TEST-10-S5：含 addedAt 除外否定断言（310-318） |
| test/shared/model_equality_test.dart:114-181 / 327-388 | REF-02-S5 | TEST-10-S2 / TEST-10-S6 |

### 5.2 测试 ID 派生清单（dev-exe 派发测试 Agent 用）

```
REF-02-S1 … S9        # Scenario（S1~S5 现状锚定，S6/S7 登记+注释，S8/S9 补锚定）
REF-02-INV1 … INV3    # 不变量
```

dev-exe 要求：S1~S5 由既有 model_equality_test.dart 覆盖（断言不变）；S6/S7 由 §5.4 门禁文件覆盖（登记表结构 + 模型注释存在性 + 与实现一致性）；S8/S9 由 §5.4 门禁文件覆盖。

### 5.3 测试覆盖盲点（dev-plan 写本文档时识别）

| 未覆盖 ID | 现状 | 应补偿方式 |
|---|---|---|
| REF-02-S2 的 lastPlayedAt 除外 | == 已排除但零锚定（cr D2 未列、TEST-10-S3 未覆盖） | §5.4 门禁文件补否定断言（S8） |
| REF-02-S3 的 createdAt/updatedAt 除外 | == 已排除但零锚定（TEST-10-S4 未覆盖） | §5.4 门禁文件补否定断言（S9） |
| REF-02-S6/S7（登记表与注释） | 新产物 | §5.4 门禁文件做结构断言 |

### 5.4 测试文件位置（spec-scan --gate 硬校验）

新建：`test/shared/ref_02_equality_registry_test.dart`（命名已 grep 核实与既有文件无冲突；**禁止改动** test/shared/model_equality_test.dart 既有断言）

| 测试文件 | 覆盖 ID | 说明 |
|---|---|---|
| test/shared/ref_02_equality_registry_test.dart | REF-02-S6、S7、S8、S9、REF-02-INV1、REF-02-INV2、REF-02-INV3 | 门禁：dev-exe 实施后必须 PASS（cov-gate 内） |
| test/shared/model_equality_test.dart | REF-02-S1 ~ S5 | 既有文件，断言保持不变 |

---

## §6 算法样例

本 REF 不涉纯函数算法（登记表为静态数据），跳过。

---

## §7 跨模块影响

`bash cross-imports.sh impact lib/shared/models/connection_config.dart lib/shared/models/play_progress.dart lib/shared/models/playlist.dart`（2026-08-16）→ 引用方：

| 其它 feature | 影响点 | 影响条件 | 需要补的回归断言 |
|---|---|---|---|
| Connection（connection_provider / connection_service / connection_screen / connection_edit_screen / connection_list_screen / connection_form / edit_screen_logic） | ConnectionConfig 相等性消费方 | **零行为变化**（S6/S7 仅新增文件与注释） | 既有 connection 测试全绿 |
| Progress（progress_service / progress_provider / progress_dialog） | PlayProgress 相等性消费方 | 零行为变化 | 既有 progress 测试全绿 |
| Playlist（playlist_service / playlist_provider / playlist_detail_screen / playlist_list_item / playlist_track_item） | Playlist / PlaylistTrack 相等性消费方 | 零行为变化 | 既有 playlist 测试全绿 |
| Player（player_provider / playback_orchestrator） | ConnectionConfig / PlayProgress 消费方 | 零行为变化 | 既有 player 测试全绿 |
| Core DAO（connection_dao / progress_dao / playlist_dao / database_contract） | fromMap·toMap 序列化面 | 零行为变化 | 既有 dao 测试全绿 |
| 测试侧（model_equality_test.dart） | 既有断言保持 | S6~S9 为纯新增 | 全绿（断言不改） |

---

## §8 平台特性与手动 QA

设计前已逐条核对 `docs/dev/platform-pitfalls.md`：本 REF 直接处置 **P12**（值对象 ==/hashCode 漏字段 → UI 静默不更新，91a9ed6 判例）——统一规则 + 登记表 + 补缺锚定即 P12 的预防性落地；其余 P1~P17 均不触及（纯 Dart 值对象层，无平台通道 / 监听器 / 超时 / 竞态）。

**真机风险列**：

| 风险 | 近似测试方案 | 测不了 → 进 mqa-backlog |
|---|---|---|
| 无（零行为变化的纯新增；UI 刷新行为由既有测试锚定） | 既有全部测试 | 无 |

本功能不涉及平台原生特性，全部可在 `flutter test` 中验证 → `manual_qa_required = false`。

---

## §9 dev-status.json 条目对照

```json
"REF-02": {
  "spec_file": "docs/features/REF-02.md",
  "spec_anchored_files": [
    "lib/shared/models/connection_config.dart",
    "lib/shared/models/play_progress.dart",
    "lib/shared/models/playlist.dart",
    "lib/shared/models/nas_file.dart",
    "lib/shared/models/play_queue.dart"
  ],
  "scenarios": ["REF-02-S1", "REF-02-S2", "REF-02-S3", "REF-02-S4", "REF-02-S5", "REF-02-S6", "REF-02-S7", "REF-02-S8", "REF-02-S9"],
  "invariants": ["REF-02-INV1", "REF-02-INV2", "REF-02-INV3"],
  "algorithms": [],
  "manual_qa_required": false,
  "user_acceptance_text": "见 §1.2"
}
```
