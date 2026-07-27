# TEST-10 — MDL6+MDL7：模型测试缺口

> 来源：`docs/cr/cr-20260724-0110.md` MDL6 (line 909-912) + MDL7 (line 914-917)
> dev-plan 流程：TEST-GAP 补测模式

---

## §0 头部元数据

```yaml
id: TEST-10
name: 模型测试缺口（MDL6+MDL7）
priority: P1
status: draft
created_at: 2026-07-27
last_updated: 2026-07-27
spec_anchored_files:
  - lib/shared/models/connection_config.dart
  - lib/shared/models/nas_file.dart
  - lib/shared/models/play_progress.dart
  - lib/shared/models/playlist.dart
  - lib/shared/models/play_queue.dart
  - test/shared/play_queue_insert_test.dart
cross_module_impacts: [CON, BRW, PRG, PLY]
parent_feature: null
manual_qa_required: false
```

---

## §1 用户视角

### 1.0 原始需求

> cr-20260724-0110.md MDL6：仅 PlayQueue 有 ==/hashCode 正负测试（bug_bug01_fixed_test.dart）。ConnectionConfig 完全无 == / hashCode 实现（`connection_config.dart` 仅 toString）。NasFile（`nas_file.dart:203-213`）、Playlist（`playlist.dart:61-69`）、PlaylistTrack（`playlist.dart:122-131`）、PlayProgress（`play_progress.dart:108-118`）有 == / hashCode 但零测试锚定。P12 要求正面（全字段同 → equal）+ 负面（每字段单独变 → not equal）测试。
>
> cr-20260724-0110.md MDL7：`play_queue_insert_test.dart:110-113` — shuffle insert 测试仅断言 `advanceShuffle() returnsNormally`。若将 `play_queue.dart:175-176` 改为 `shuffleOrder: null`（触发重算，违反 BRW-09 INV2），测试仍然通过。

### 1.1 这一功能干什么（一句话）

为所有 model 类补 == / hashCode 正负测试，并加强 shuffle insert 测试以检测 shuffleOrder 被意外置 null。

### 1.2 用户期望的场景

| ID | 你看到的样子 | 期望行为 |
|----|----|----|
| U1 | 两个 ConnectionConfig 所有字段相同 | `==` 返回 true，hashCode 相等 |
| U2 | 两个 ConnectionConfig 某个字段不同 | `==` 返回 false |
| U3 | NasFile/Playlist/PlaylistTrack/PlayProgress 同理 | 正面全字段同 → equal，负面每字段变 → not equal |
| U4 | shuffle 模式下 insertAfterCurrent 不重算 shuffleOrder | nextShuffleIndex 序列在 insert 前后保持一致 |

---

## §2 已实现的功能骨架

### 2.1 文件与分层

| 层 | 文件 | 行数 | 角色 |
|---|---|---|---|
| Model | `lib/shared/models/connection_config.dart` | 94 | 无 == / hashCode |
| Model | `lib/shared/models/nas_file.dart` | 214 | == :203-210, hashCode :213 |
| Model | `lib/shared/models/play_progress.dart` | 119 | == :108-114, hashCode :117-118 |
| Model | `lib/shared/models/playlist.dart` | 132 | Playlist == :61-66, hashCode :69; PlaylistTrack == :122-128, hashCode :131 |
| Model | `lib/shared/models/play_queue.dart` | 339 | == :309-317, hashCode :320-326 |
| Test (现有) | `test/shared/play_queue_insert_test.dart` | 302 | :110-113 弱 shuffle 断言 |
| Test (现有) | `test/features/player/bug_bug01_fixed_test.dart` | - | PlayQueue == / hashCode 正负测试 |

### 2.2 各模型 == / hashCode 字段覆盖

| 模型 | == 字段 | hashCode 字段 | 现有测试 |
|---|---|---|---|
| ConnectionConfig | **无实现** | **无实现** | 无 |
| NasFile | name, path, isDirectory, size, audioType (:203-210) | 同 (:213) | 无 |
| PlayProgress | connectionId, filePath, positionMs, durationMs (:108-114) | 同 (:117-118) | 无 |
| Playlist | id, name, trackCount (:61-66) | 同 (:69) | 无 |
| PlaylistTrack | id, playlistId, filePath, fileName (:122-128) | 同 (:131) | 无 |
| PlayQueue | files(list), currentIndex, startPositionMs, playMode, _shuffleOrder(list), _shufflePosition (:309-317) | 同 (:320-326) | 有（bug_bug01_fixed_test） |

---

## §3 行为规约

### 3.1 ConnectionConfig 需新增 == / hashCode

- **[TEST-10-S1]** ConnectionConfig == / hashCode 实现 (`status: new`)
  ```
  Given ConnectionConfig 类
  When  两个实例所有字段（id, name, url, username, basePath, isActive, createdAt, updatedAt）相同
  Then  == 返回 true
  And   hashCode 相等
  否定断言:
    - 不在缺少 == 实现时使用引用相等（当前 BUG：无 == → 不同实例永远 != 即使字段相同）
    - 不遗漏任何字段（所有 8 个字段必须参与 == 和 hashCode）
  ```
  Code evidence: `lib/shared/models/connection_config.dart:5-94`（无 == / hashCode 实现）

  **修改指令 — `lib/shared/models/connection_config.dart`**

  在 `toString()` 方法前（`:90` 之前）新增：

  ```dart
    @override
    bool operator ==(Object other) =>
        identical(this, other) ||
        other is ConnectionConfig &&
            id == other.id &&
            name == other.name &&
            url == other.url &&
            username == other.username &&
            basePath == other.basePath &&
            isActive == other.isActive &&
            createdAt == other.createdAt &&
            updatedAt == other.updatedAt;

    @override
    int get hashCode => Object.hash(
        id, name, url, username, basePath, isActive, createdAt, updatedAt);
  ```

  边界裁决：
  - 所有 8 个字段参与比较，与 copyWith 参数一一对应
  - `id` 为 nullable int（`int?`）→ `Object.hash` 正确处理 null
  - `createdAt` / `createdAt` 为 DateTime → DateTime.== 按毫秒精度比较
  - 与 copyWith 配合：`a.copyWith()` == `a` 必须成立

  **测试文件位置：`test/shared/model_equality_test.dart`**

### 3.2 各模型正面+负面 == / hashCode 测试

- **[TEST-10-S2]** NasFile == / hashCode 正负测试 (`status: new`)
  ```
  Given 两个 NasFile 实例
  When  所有字段（name, path, isDirectory, size, audioType）相同
  Then  == 返回 true，hashCode 相等
  When  每个字段单独变动（name 不同 / path 不同 / isDirectory 不同 / size 不同 / audioType 不同）
  Then  == 返回 false
  否定断言:
    - 不在某个字段不同时仍返回 == true（漏比字段）
    - 不在 hashCode 中遗漏字段（避免 Set/Map 碰撞）
  ```
  Code evidence: `nas_file.dart:203-213`

  **测试文件位置：`test/shared/model_equality_test.dart`**

- **[TEST-10-S3]** PlayProgress == / hashCode 正负测试 (`status: new`)
  ```
  Given 两个 PlayProgress 实例
  When  所有字段（connectionId, filePath, positionMs, durationMs）相同
  Then  == 返回 true，hashCode 相等
  When  每个字段单独变动
  Then  == 返回 false
  否定断言:
    - 不在某个字段不同时仍返回 == true
    - 不比较 id 字段（id 是 DB 自增主键，不参与业务相等性——与现有 == 实现一致 :108-114）
  ```
  Code evidence: `play_progress.dart:108-118`

  **测试文件位置：`test/shared/model_equality_test.dart`**

- **[TEST-10-S4]** Playlist == / hashCode 正负测试 (`status: new`)
  ```
  Given 两个 Playlist 实例
  When  所有字段（id, name, trackCount）相同
  Then  == 返回 true，hashCode 相等
  When  每个字段单独变动
  Then  == 返回 false
  否定断言:
    - 不在某个字段不同时仍返回 == true
  ```
  Code evidence: `playlist.dart:61-69`

  **测试文件位置：`test/shared/model_equality_test.dart`**

- **[TEST-10-S5]** PlaylistTrack == / hashCode 正负测试 (`status: new`)
  ```
  Given 两个 PlaylistTrack 实例
  When  所有字段（id, playlistId, filePath, fileName）相同
  Then  == 返回 true，hashCode 相等
  When  每个字段单独变动
  Then  == 返回 false
  否定断言:
    - 不在某个字段不同时仍返回 == true
    - 不比较 addedAt 字段（与现有 == 实现一致 :122-128，addedAt 不参与相等性）
  ```
  Code evidence: `playlist.dart:122-131`

  **测试文件位置：`test/shared/model_equality_test.dart`**

- **[TEST-10-S6]** PlayQueue == / hashCode 正负测试（已有 bug_bug01_fixed_test，此处补全缺失字段的独立负面测试） (`status: new`)
  ```
  Given 两个 PlayQueue 实例
  When  每个字段单独变动（files / currentIndex / startPositionMs / playMode / shuffleOrder / shufflePosition）
  Then  == 返回 false
  否定断言:
    - 不遗漏任何字段的负面测试（bug_bug01_fixed_test 已覆盖部分，需检查完整性）
  ```
  Code evidence: `play_queue.dart:309-326`

  **测试文件位置：`test/shared/model_equality_test.dart`**

### 3.3 Shuffle insert 顺序保持测试

- **[TEST-10-S7]** insertAfterCurrent 不重算 shuffleOrder (`status: new`)
  ```
  Given PlayQueue（PlayMode.shuffle, 4 文件, currentIndex=1）
        用固定 seed Random 生成 shuffleOrder=[2,0,3,1]，shufflePosition=0
  When  insertAfterCurrent 插入新文件 Y
  Then  新队列的 shuffleOrder == [2,0,3,1]（原序不变，Y 不在其中——直到下次重算）
  And   shufflePosition 不变
  And   用 nextShuffleIndex 取出序列，与 insert 前取出的前 N 项一致
  否定断言:
    - 不将 shuffleOrder 置为 null（`play_queue.dart:175` 当前传 `_shuffleOrder`；若改为 `null` 则触发重算 → 违反 BRW-09 INV2）
    - 不改变已有 shuffle 序列的顺序
    - 不改变 shufflePosition
  ```
  Code evidence:
  - `play_queue.dart:168-178`（insertAfterCurrent 传 `shuffleOrder: _shuffleOrder`）
  - `play_queue_insert_test.dart:110-113`（当前弱断言：仅 `returnsNormally`）
  - `play_queue.dart:175-176`（关键行：`shuffleOrder: _shuffleOrder, shufflePosition: _shufflePosition`）

  **测试文件位置：`test/shared/play_queue_insert_test.dart`**

---

## §4 不变量

- **[TEST-10-INV1]** 所有 model 类的 == 覆盖所有业务字段，hashCode 与 == 一致
  证据：`nas_file.dart:203-213`、`play_progress.dart:108-118`、`playlist.dart:61-69,122-131`、`play_queue.dart:309-326`

- **[TEST-10-INV2]** insertAfterCurrent 保持原有 shuffleOrder 不变（BRW-09 INV2）
  证据：`play_queue.dart:175-176`（`shuffleOrder: _shuffleOrder`）

---

## §5 测试规约

### 5.1 现有测试清单

| 测试文件 | 覆盖 | 备注 |
|---|---|---|
| `bug_bug01_fixed_test.dart` | PlayQueue == / hashCode 正负 | 已覆盖 shuffle 字段 |
| `bug_bug01_repro_test.dart` | PlayQueue hashCode 碰撞 | 回归测试 |
| `play_queue_insert_test.dart:110-113` | insertAfterCurrent shuffle 行为 | **弱断言：仅 returnsNormally** |

### 5.2 测试 ID 派生清单

```
TEST-10-S1          # ConnectionConfig == / hashCode 实现
TEST-10-S2 ~ S6     # 各模型正负 == / hashCode 测试
TEST-10-S7          # insertAfterCurrent 不重算 shuffleOrder
TEST-10-INV1 INV2   # 字段覆盖完整性 + shuffle 保持
```

### 5.3 测试覆盖盲点

| 未覆盖 ID | 现状 | 应补偿方式 |
|---|---|---|
| TEST-10-S1 | ConnectionConfig 无 == / hashCode | 实现 + 正面测试（全字段同 → equal）+ 负面测试（每字段变 → not equal） |
| TEST-10-S2 | NasFile 有 == 无测试 | 正面 + 5 个负面（每字段一个） |
| TEST-10-S3 | PlayProgress 有 == 无测试 | 正面 + 4 个负面 |
| TEST-10-S4 | Playlist 有 == 无测试 | 正面 + 3 个负面 |
| TEST-10-S5 | PlaylistTrack 有 == 无测试 | 正面 + 4 个负面 |
| TEST-10-S6 | PlayQueue 部分覆盖 | 检查 bug_bug01_fixed_test 完整性，补缺失字段独立负面 |
| TEST-10-S7 | `play_queue_insert_test.dart:110-113` 弱断言 | 固定 seed 构造 shuffleOrder → 断言 insert 前后序列一致 |

### 5.4 测试文件位置

| 测试 ID | 文件路径 |
|---|---|
| TEST-10-S1 ~ S6 | `test/shared/model_equality_test.dart` |
| TEST-10-S7 | `test/shared/play_queue_insert_test.dart`（追加到现有文件） |

---

## §6 算法样例

不适用——本 spec 为补测，无新算法（ConnectionConfig 的 == / hashCode 实现为机械添加）。

---

## §7 跨模块影响

| 其它 feature | 影响点 | 需要补的回归断言 |
|---|---|---|
| CON | ConnectionConfig 新增 == 后，Provider 中 `==` 比较行为变化 | 确认 Provider state equality 检查不受影响 |
| BRW | NasFile == 测试补全后可能发现现有测试依赖引用相等 | 运行全量测试确认无回归 |
| PRG | PlayProgress == 测试补全后验证 shouldSave/shouldClear 中的比较正确 | 无额外回归 |
| PLY | Playlist/PlaylistTrack == 测试补全 | 确认 playlist_service 去重逻辑与 == 语义一致 |

---

## §8 平台特性与手动 QA

本功能不涉及平台原生特性，全部可在 `flutter test` 中验证。

---

## §9 dev-status.json 条目对照

```json
"TEST-10": {
  "spec_file": "docs/features/TEST-10.md",
  "spec_anchored_files": [
    "lib/shared/models/connection_config.dart",
    "lib/shared/models/nas_file.dart",
    "lib/shared/models/play_progress.dart",
    "lib/shared/models/playlist.dart",
    "lib/shared/models/play_queue.dart",
    "test/shared/play_queue_insert_test.dart"
  ],
  "scenarios": ["TEST-10-S1", "TEST-10-S2", "TEST-10-S3", "TEST-10-S4", "TEST-10-S5", "TEST-10-S6", "TEST-10-S7"],
  "invariants": ["TEST-10-INV1", "TEST-10-INV2"],
  "algorithms": [],
  "test_files": ["test/shared/model_equality_test.dart", "test/shared/play_queue_insert_test.dart"],
  "test_coverage_gaps": [],
  "cross_module_impacts": ["CON", "BRW", "PRG", "PLY"],
  "manual_qa_required": false,
  "manual_qa_file": null,
  "user_acceptance_text": "见 §1.2",
  "impl_status": "pending",
  "test_status": "pending",
  "check_status": "pending",
  "check_round": 0,
  "last_check_round_results": "",
  "last_checked_at": "",
  "dependencies": [],
  "retry_count": 0,
  "last_error": "",
  "last_updated": "2026-07-27"
}
```

---

## §10 changelog

- 2026-07-27: 创建 TEST-10 spec（基于 cr-20260724-0110.md MDL6 + MDL7）
