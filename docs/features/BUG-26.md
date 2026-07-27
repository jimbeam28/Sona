# BUG-26 — DB3+DB4+DB5+DB6 — DAO 健壮性缺陷簇

> 来源：`docs/cr/cr-20260724-0110.md` DB3 (line 638-642) + DB4 (line 644-649) + DB5 (line 651-655) + DB6 (line 657-661)
> 另 LIST4 (line 381-383) 与 DB3 同根合并处理
> dev-plan 流程：Bug 修复模式

---

## §0 头部元数据

```yaml
id: BUG-26
name: DB3+DB4+DB5+DB6 — DAO 健壮性缺陷簇
priority: P2
status: draft
created_at: 2026-07-27
last_updated: 2026-07-27
spec_anchored_files:
  - lib/core/database/dao/playlist_dao.dart
  - lib/core/database/dao/connection_dao.dart
  - lib/core/database/dao/progress_dao.dart
cross_module_impacts: [PLY, CON, PRG]
parent_feature: null
manual_qa_required: false
```

---

## §1 用户视角

### 1.0 原始需求

> cr-20260724-0110.md DB3+LIST4（同根）：`removeTracks([])` 生成非法 SQL `WHERE id IN ()` → SQLite 语法错误。DB4：`reorderTrack` 无索引越界校验，坏 index 抛 RangeError。DB5：`connection_dao.delete` 对 play_progress 删除用 `catch(_)` 吞掉一切异常。DB6：DAO 直接 `DateTime.now()`，"当前时刻"不可注入，测试只能用 rawInsert 绕过。

### 1.1 这一功能干什么（一句话）

修复四个 DAO 层的健壮性缺陷：空列表 SQL 注入、索引越界、异常吞没过宽、时钟不可注入。

### 1.2 用户期望的场景

| ID | 你看到的样子 | 期望行为 |
|----|----|----|
| U1 | 程序化调用 `removeTracks([])` | 静默返回，不抛 SQLite 语法异常 |
| U2 | 程序化调用 `reorderTrack(playlistId, 99, 0)` 越界索引 | 静默返回，不抛 RangeError |
| U3 | `connection_dao.delete` 级联删除 play_progress，真实 IO 错误发生 | 异常不被吞没，能向上传播给调用方 |
| U4 | 测试需要在受控时钟下验证 upsert/reorderTrack 的时间行为 | 可通过构造函数注入 clock，无需 rawInsert 绕过 |

---

## §2 已实现的功能骨架

### 2.1 文件与分层

| 层 | 文件 | 行数 | 角色 |
|---|---|---|---|
| Data | `lib/core/database/dao/playlist_dao.dart` | 124 | 播放单 + 曲目 CRUD |
| Data | `lib/core/database/dao/connection_dao.dart` | 154 | 连接 CRUD + 级联删除 |
| Data | `lib/core/database/dao/progress_dao.dart` | 179 | 播放进度 UPSERT + 查询 |
| Contract | `lib/core/contracts/database_contract.dart` | 124 | IConnectionDao / IProgressDao / IPlaylistDao 抽象接口 |

### 2.2 关键方法表

| 方法 | 文件 | 行号 | 问题 |
|---|---|---|---|
| `removeTracks` | `playlist_dao.dart` | :75-83 | 空列表 → `WHERE id IN ()` 语法错误 |
| `reorderTrack` | `playlist_dao.dart` | :97-123 | 无索引越界校验 |
| `delete` | `connection_dao.dart` | :110-147 | `catch(_)` 过宽 |
| 多处 | 三个 DAO | 见下 | `DateTime.now()` 硬编码 |

---

## §3 行为规约

### 3.1 修复后行为

- **[BUG-26-S1]** removeTracks 空列表提前返回 (`status: new`)
  ```
  Given 调用 removeTracks([])
  When  trackIds 为空列表
  Then  方法静默返回，不执行任何 SQL
  否定断言:
    - 不生成 `WHERE id IN ()` 的非法 SQL
    - 不抛出 DatabaseException 或 SQLite 语法错误
    - 不改变非空列表的正常删除行为（trackIds=[1,2,3] 仍正确删除）
  ```
  Code evidence: `lib/core/database/dao/playlist_dao.dart:75-83`
  ```dart
  Future<void> removeTracks(List<int> trackIds) async {
    final db = await _db;
    final placeholders = List.filled(trackIds.length, '?').join(',');
    await db.delete(
      'playlist_tracks',
      where: 'id IN ($placeholders)',
      whereArgs: trackIds,
    );
  }
  ```
  当 `trackIds.length == 0` → `List.filled(0, '?').join(',')` → `''` → `WHERE id IN ()` → SQLite 语法错误。
  对照：同文件 `:105`（`if (tracks.length < 2) return;`）有类似守卫模式。

  **修改指令 — `lib/core/database/dao/playlist_dao.dart`（removeTracks）**

  位置：`:75-83`

  当前代码（:75-83）：
  ```dart
  Future<void> removeTracks(List<int> trackIds) async {
    final db = await _db;
    final placeholders = List.filled(trackIds.length, '?').join(',');
    await db.delete(
      'playlist_tracks',
      where: 'id IN ($placeholders)',
      whereArgs: trackIds,
    );
  }
  ```

  改为：
  ```dart
  Future<void> removeTracks(List<int> trackIds) async {
    if (trackIds.isEmpty) return;
    final db = await _db;
    final placeholders = List.filled(trackIds.length, '?').join(',');
    await db.delete(
      'playlist_tracks',
      where: 'id IN ($placeholders)',
      whereArgs: trackIds,
    );
  }
  ```

  边界裁决：
  - `trackIds=[]` → 第一行 return，不碰数据库
  - `trackIds=[1]` → 正常路径，`WHERE id IN (?)`，行为不变
  - `trackIds=[1,2,3]` → 正常路径，行为不变
  - UI 当前不可达此路径（选空即退出选择模式），但公开契约边界已加固

  **测试文件位置：`test/features/coverage/bug_bug26_repro_test.dart`**

- **[BUG-26-S2]** reorderTrack 索引越界静默返回 (`status: new`)
  ```
  Given reorderTrack(playlistId, oldIndex, newIndex) 被调用
  When  oldIndex 或 newIndex 超出曲目列表范围
  Then  方法静默返回，不修改任何数据
  否定断言:
    - 不抛出 RangeError（removeAt/insert 越界）
    - 不修改任何 playlist_tracks 行的 added_at
    - 不改变正常索引范围内的重排行为
  ```
  Code evidence: `lib/core/database/dao/playlist_dao.dart:97-123`
  ```dart
  Future<void> reorderTrack(int playlistId, int oldIndex, int newIndex) async {
    final db = await _db;
    final tracks = await db.query(...);
    if (tracks.length < 2) return;
    if (oldIndex == newIndex) return;

    final moved = List<Map<String, dynamic>>.from(tracks);
    moved.removeAt(oldIndex);       // :109 — 无边界检查
    moved.insert(newIndex, tracks[oldIndex]);  // :110 — 无边界检查
    ...
  }
  ```
  `removeAt(oldIndex)` 当 `oldIndex >= tracks.length` → RangeError；`insert(newIndex, ...)` 当 `newIndex > tracks.length` → RangeError。

  **修改指令 — `lib/core/database/dao/playlist_dao.dart`（reorderTrack）**

  位置：`:97-106`（在已有守卫后增加越界检查）

  当前代码（:97-106）：
  ```dart
  Future<void> reorderTrack(int playlistId, int oldIndex, int newIndex) async {
    final db = await _db;
    final tracks = await db.query(
      'playlist_tracks',
      where: 'playlist_id = ?',
      whereArgs: [playlistId],
      orderBy: 'added_at ASC, id ASC',
    );
    if (tracks.length < 2) return;
    if (oldIndex == newIndex) return;
  ```

  改为：
  ```dart
  Future<void> reorderTrack(int playlistId, int oldIndex, int newIndex) async {
    final db = await _db;
    final tracks = await db.query(
      'playlist_tracks',
      where: 'playlist_id = ?',
      whereArgs: [playlistId],
      orderBy: 'added_at ASC, id ASC',
    );
    if (tracks.length < 2) return;
    if (oldIndex == newIndex) return;
    if (oldIndex < 0 || oldIndex >= tracks.length) return;
    if (newIndex < 0 || newIndex >= tracks.length) return;
  ```

  边界裁决：
  - `oldIndex=-1` → 新守卫 return，不抛异常
  - `oldIndex=tracks.length` → 新守卫 return（`>=` 拦截）
  - `newIndex=tracks.length` → 新守卫 return（`insert` 允许 `length` 但语义不符预期——末尾追加等于不动，交由守卫统一拦截）
  - `oldIndex=0, newIndex=tracks.length-1` → 正常路径，行为不变
  - 调用方 `playlist_detail_screen.dart:186` 已有标准 newIndex 修正，正常拖拽安全；此守卫防异步刷新间陈旧越界索引

- **[BUG-26-S3]** connection_dao.delete 收窄 catch 范围 (`status: new`)
  ```
  Given connection_dao.delete(id) 级联删除 play_progress
  When  play_progress 表不存在（测试 schema 场景）
  Then  异常被捕获并忽略，继续删除 connections 行
  否定断言:
    - 不吞掉非"表不存在"的其他异常（如 IO 错误、约束违反）
    - 不改变 play_progress 表存在时的正常级联删除行为
    - 不改变 LastConnectionException 保护逻辑（:114-117）
  ```
  Code evidence: `lib/core/database/dao/connection_dao.dart:127-132`
  ```dart
  try {
    await txn.delete('play_progress',
        where: 'connection_id = ?', whereArgs: [id]);
  } catch (_) {
    // play_progress table not yet created — safe to ignore
  }
  ```
  `catch (_)` 捕获所有异常，包括真正的 IO 错误、磁盘满、约束违反等。

  **修改指令 — `lib/core/database/dao/connection_dao.dart`（delete 方法）**

  位置：`:127-132`

  当前代码（:127-132）：
  ```dart
  try {
    await txn.delete('play_progress',
        where: 'connection_id = ?', whereArgs: [id]);
  } catch (_) {
    // play_progress table not yet created — safe to ignore
  }
  ```

  改为：
  ```dart
  try {
    await txn.delete('play_progress',
        where: 'connection_id = ?', whereArgs: [id]);
  } on DatabaseException catch (e) {
    if (!e.isNoSuchTableError()) rethrow;
  }
  ```

  边界裁决：
  - play_progress 表不存在 → `DatabaseException` with `isNoSuchTableError()=true` → 忽略（保持原行为）
  - play_progress 表存在，正常删除 → 无异常，行为不变
  - 磁盘 IO 错误 → `DatabaseException` with `isNoSuchTableError()=false` → rethrow，向上传播
  - 非 DatabaseException 异常（如 ArgumentError）→ 不匹配 `on DatabaseException`，自动向上传播
  - FK ON 时此手动删除与 CASCADE 重复，但冗余无害（删除空集合）

- **[BUG-26-S4]** DAO 构造函数支持 clock 注入 (`status: new`)
  ```
  Given DAO 构造时传入自定义 clock 函数
  When  调用 upsert / reorderTrack / update / setActive
  Then  使用注入的 clock 获取当前时间戳而非 DateTime.now()
  否定断言:
    - 不在默认参数下改变生产行为（默认 `DateTime.now`）
    - 不在注入固定 clock 时产生与注入值不同的时间戳
    - 不改变现有 rawInsert 的测试播种能力（保持兼容）
  ```
  Code evidence（所有 `DateTime.now()` 位置）：
  - `progress_dao.dart:56` — `final now = DateTime.now().millisecondsSinceEpoch;`（upsert）
  - `playlist_dao.dart:41` — `map['updated_at'] = DateTime.now().millisecondsSinceEpoch;`（updatePlaylist）
  - `playlist_dao.dart:112` — `final base = DateTime.now().millisecondsSinceEpoch;`（reorderTrack）
  - `connection_dao.dart:82` — `map['updated_at'] = DateTime.now().millisecondsSinceEpoch;`（update）
  - `connection_dao.dart:94` — `{'is_active': 1, 'updated_at': DateTime.now().millisecondsSinceEpoch}`（setActive）

  **修改指令 — `lib/core/database/dao/progress_dao.dart`**

  位置：`:16-22`（构造函数 + 字段）

  当前代码（:16-22）：
  ```dart
  class ProgressDao implements IProgressDao {
    final DatabaseHelper _helper;

    ProgressDao({DatabaseHelper? helper})
        : _helper = helper ?? DatabaseHelper.instance;
  ```

  改为：
  ```dart
  class ProgressDao implements IProgressDao {
    final DatabaseHelper _helper;
    final DateTime Function() _clock;

    ProgressDao({DatabaseHelper? helper, DateTime Function()? clock})
        : _helper = helper ?? DatabaseHelper.instance,
          _clock = clock ?? DateTime.now;
  ```

  使用点（:56）：
  ```dart
  final now = _clock().millisecondsSinceEpoch;
  ```

  **修改指令 — `lib/core/database/dao/playlist_dao.dart`**

  位置：`:9-15`（构造函数 + 字段）

  当前代码（:9-15）：
  ```dart
  class PlaylistDao implements IPlaylistDao {
    final DatabaseHelper _helper;

    PlaylistDao({DatabaseHelper? helper})
        : _helper = helper ?? DatabaseHelper.instance;
  ```

  改为：
  ```dart
  class PlaylistDao implements IPlaylistDao {
    final DatabaseHelper _helper;
    final DateTime Function() _clock;

    PlaylistDao({DatabaseHelper? helper, DateTime Function()? clock})
        : _helper = helper ?? DatabaseHelper.instance,
          _clock = clock ?? DateTime.now;
  ```

  使用点（:41, :112）替换 `DateTime.now()` → `_clock()`：
  ```dart
  map['updated_at'] = _clock().millisecondsSinceEpoch;  // :41
  final base = _clock().millisecondsSinceEpoch;          // :112
  ```

  **修改指令 — `lib/core/database/dao/connection_dao.dart`**

  位置：`:19-25`（构造函数 + 字段）

  当前代码（:19-25）：
  ```dart
  class ConnectionDao implements IConnectionDao {
    final DatabaseHelper _helper;

    ConnectionDao({DatabaseHelper? helper})
        : _helper = helper ?? DatabaseHelper.instance;
  ```

  改为：
  ```dart
  class ConnectionDao implements IConnectionDao {
    final DatabaseHelper _helper;
    final DateTime Function() _clock;

    ConnectionDao({DatabaseHelper? helper, DateTime Function()? clock})
        : _helper = helper ?? DatabaseHelper.instance,
          _clock = clock ?? DateTime.now;
  ```

  使用点（:82, :94）替换 `DateTime.now()` → `_clock()`：
  ```dart
  map['updated_at'] = _clock().millisecondsSinceEpoch;  // :82
  {'is_active': 1, 'updated_at': _clock().millisecondsSinceEpoch},  // :94
  ```

  边界裁决：
  - 默认 `clock=null` → `DateTime.now`，生产行为完全不变
  - 测试注入 `() => DateTime(2026, 1, 1)` → 所有时间戳固定为受控值，可验证排序/UPSERT 行为
  - 现有 `rawInsert` 保持不动（测试仍可用来播种任意时间戳，两种播种方式并存不冲突）
  - 构造签名向后兼容（新增可选命名参数）

  **测试文件位置：`test/features/coverage/bug_bug26_repro_test.dart`**

---

## §4 不变量

- **[BUG-26-INV1]** `removeTracks` 对空输入不执行 SQL
  证据：`playlist_dao.dart:75-83`（修复目标）→ 修复后第一行 `if (trackIds.isEmpty) return;`

- **[BUG-26-INV2]** `reorderTrack` 对越界索引不抛异常
  证据：`playlist_dao.dart:108-110`（修复目标）→ 修复后 `:107-108` 添加边界检查

- **[BUG-26-INV3]** `connection_dao.delete` 只忽略"表不存在"异常
  证据：`connection_dao.dart:127-132`（修复目标）→ 修复后 `on DatabaseException catch (e) { if (!e.isNoSuchTableError()) rethrow; }`

- **[BUG-26-INV4]** 所有 DAO 的 `DateTime.now()` 通过可注入 clock 获取
  证据：`progress_dao.dart:56`、`playlist_dao.dart:41,112`、`connection_dao.dart:82,94`（5 处修复目标）

---

## §5 测试规约

### 5.2 测试 ID 派生清单

```
BUG-26-S1           # removeTracks 空列表提前返回
BUG-26-S2           # reorderTrack 索引越界静默返回
BUG-26-S3           # connection_dao.delete 收窄 catch 范围
BUG-26-S4           # DAO clock 注入
BUG-26-INV1         # removeTracks 空输入不执行 SQL
BUG-26-INV2         # reorderTrack 越界不抛异常
BUG-26-INV3         # delete 只忽略"表不存在"
BUG-26-INV4         # DateTime.now 可注入
```

### 5.4 测试文件位置

| 测试 ID | 文件路径 |
|---------|----------|
| BUG-26-S1 | `test/features/coverage/bug_bug26_repro_test.dart` |
| BUG-26-S2 | `test/features/coverage/bug_bug26_repro_test.dart` |
| BUG-26-S3 | `test/features/coverage/bug_bug26_repro_test.dart` |
| BUG-26-S4 | `test/features/coverage/bug_bug26_repro_test.dart` |
| BUG-26-INV1 | `test/features/coverage/bug_bug26_repro_test.dart` |
| BUG-26-INV2 | `test/features/coverage/bug_bug26_repro_test.dart` |
| BUG-26-INV3 | `test/features/coverage/bug_bug26_repro_test.dart` |
| BUG-26-INV4 | `test/features/coverage/bug_bug26_repro_test.dart` |

---

## §7 跨模块影响

| 其它 feature | 影响点 | 影响条件 | 需要补的回归断言 |
|---|---|---|---|
| PLY | `PlaylistDao.removeTracks` / `reorderTrack` | 播放单曲目删除/重排 | 空列表删除静默返回；越界重排静默返回 |
| CON | `ConnectionDao.delete` 级联删除 | 连接删除 | catch 收窄后真实 IO 错误能向上传播 |
| PRG | `ProgressDao.upsert` 时间戳 | 进度保存 | clock 注入后可在受控时钟下验证 |

---

## §8 平台特性与手动 QA

本功能不涉及平台原生特性，全部可在 `flutter test` 中验证。

---

## §9 dev-status.json 条目对照

见统一更新：`docs/dev/dev-status.json`。

---

## §10 changelog

- 2026-07-27: 创建 BUG-26 spec（基于 cr-20260724-0110.md DB3+DB4+DB5+DB6 + LIST4）
