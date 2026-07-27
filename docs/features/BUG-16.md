# BUG-16 — FK PRAGMA 只在 onCreate 置位

> 来源：`docs/cr/cr-20260724-0110.md` DB2 = CTR8
> dev-plan 流程：Bug 修复模式

---

## §0 头部元数据

```yaml
id: BUG-16
name: FK PRAGMA 只在 onCreate 置位
priority: P0
status: draft
created_at: 2026-07-27
last_updated: 2026-07-27
spec_anchored_files:
  - lib/core/database/database_helper.dart
  - lib/core/database/dao/playlist_dao.dart
  - test/helpers/test_database.dart
cross_module_impacts: [PLY]
parent_feature: null  # core/database，影响 Playlist 级联删除
manual_qa_required: false
```

---

## §1 用户视角

### 1.0 原始需求

> cr-20260724-0110.md DB2：PRAGMA foreign_keys=ON 只在 _onCreate 执行，重启后（版本匹配不触发 onCreate）FK 回默认 OFF。删播放单只删 playlists 行，playlist_tracks 残留孤儿行永久泄漏。测试 helper 每次 open 强制 FK=ON 掩盖此问题。

### 1.1 这一功能干什么（一句话）

修复重启后外键约束失效导致删除播放单泄漏孤儿行的缺陷。

### 1.2 用户期望的场景

| ID | 你看到的样子 | 期望行为 |
|----|----|----|
| U1 | 创建播放单 + 添加曲目 → 删除播放单 → 重启 App | 数据库中无孤儿 playlist_tracks 行 |

---

## §2 已实现的功能骨架

### 2.1 文件与分层

| 层 | 文件 | 行数 | 角色 |
|---|---|---|---|
| Core Database | `lib/core/database/database_helper.dart` | ~100 | DatabaseProvider 单例 |
| DAO | `lib/core/database/dao/playlist_dao.dart` | ~120 | deletePlaylist 依赖 CASCADE |
| Test Helper | `test/helpers/test_database.dart` | ~120 | 每次 open 强制 FK=ON（假绿） |

---

## §3 行为规约

### 3.1 修复后行为

- **[BUG-16-S1]** PRAGMA 移到 onConfigure（每次 open 执行） (`status: new`)
  ```
  Given 数据库被打开（首次/重启/升级）
  When  openDatabase 执行 onConfigure 回调
  Then  执行 PRAGMA foreign_keys = ON
  否定断言:
    - 不只在 _onCreate 中置位（当前 BUG 行为）
    - 不在 _onUpgrade 中置位（升级也不保证每次都执行）
    - 不改变 schema 定义（schema 中 ON DELETE CASCADE 保持不变）
  ```
   Code evidence: `lib/core/database/database_helper.dart:33`（PRAGMA 只在 _onCreate）

   **修改指令 — `lib/core/database/database_helper.dart`**

   修改 1：在 `_openDatabase` 方法中添加 `onConfigure` 回调

   位置：`:24-29`（openDatabase 调用）

   当前代码（:24-29）：
   ```dart
       return openDatabase(
         path,
         version: _dbVersion,
         onCreate: _onCreate,
         onUpgrade: _onUpgrade,
       );
   ```

   改为：
   ```dart
       return openDatabase(
         path,
         version: _dbVersion,
         onConfigure: _onConfigure,
         onCreate: _onCreate,
         onUpgrade: _onUpgrade,
       );
   ```

   修改 2：新增 `_onConfigure` 方法

   位置：在 `_openDatabase` 方法之后（`:30` 之后），`_onCreate` 方法之前

   新增代码：
   ```dart
     Future<void> _onConfigure(Database db) async {
       await db.execute('PRAGMA foreign_keys = ON');
     }
   ```

   修改 3：从 `_onCreate` 中移除 PRAGMA 语句

   位置：`:33`（`_onCreate` 内的 PRAGMA 行）

   当前代码（:32-33）：
   ```dart
     Future<void> _onCreate(Database db, int version) async {
       await db.execute('PRAGMA foreign_keys = ON');
   ```

   改为：
   ```dart
     Future<void> _onCreate(Database db, int version) async {
   ```

   边界裁决：
   - `onConfigure` 在每次数据库打开时执行（首次/重启/升级均触发）→ FK 约束始终生效
   - 已有数据库（v1 或 v2 升级路径）：`onConfigure` 在 `onUpgrade` 之前执行 → 升级过程中 FK 已生效 → CASCADE 删除在升级期间也能正确工作
   - PRAGMA foreign_keys 是 per-connection 设置（非 per-database）→ 不需要数据迁移，每次 open 重新设置即可
   - `onConfigure` 在 `onCreate` 之前执行 → 新建数据库时 FK 在 schema 创建前已生效
   - `_onConfigure` 方法签名 `Future<void> Function(Database)` 匹配 sqflite `openDatabase` 的 `onConfigure` 参数类型

   **测试文件位置：`test/features/connection/bug_16_repro_test.dart`**

- **[BUG-16-S2]** test_database 与生产 schema 单源化 (`status: new`)
  ```
  Given 测试用数据库
  When  打开测试数据库
  Then  使用与生产相同的 openDatabase 路径（含 onConfigure PRAGMA）
        不再单独强制 FK=ON
  否定断言:
    - 不在测试 helper 中硬编码 FK=ON 掩盖生产行为
  ```
   Code evidence: `test/helpers/test_database.dart:104-115`（每次 open 强制 FK=ON）

   **修改指令 — `test/helpers/test_database.dart`**

   位置：`:91`（`databaseFactoryFfi.openDatabase` 调用）

   当前代码（:91）：
   ```dart
     final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
   ```

   改为：
   ```dart
     final db = await databaseFactoryFfi.openDatabase(
       inMemoryDatabasePath,
       onConfigure: (db) async {
         await db.execute('PRAGMA foreign_keys = ON');
       },
     );
   ```

   位置：`:104-106`（TestSchema.playlist case 内手动 PRAGMA）

   当前代码（:104-106）：
   ```dart
       case TestSchema.playlist:
         await db.execute('PRAGMA foreign_keys = ON');
         await db.execute(_createPlaylistTables);
   ```

   改为：
   ```dart
       case TestSchema.playlist:
         await db.execute(_createPlaylistTables);
   ```

   位置：`:109-110`（TestSchema.full case 内手动 PRAGMA）

   当前代码（:109-110）：
   ```dart
       case TestSchema.full:
         await db.execute('PRAGMA foreign_keys = ON');
   ```

   改为：
   ```dart
       case TestSchema.full:
   ```

   边界裁决：
   - `onConfigure` 在 `openDatabase` 返回前执行 → 所有 schema 创建（switch 内）执行时 FK 已生效
   - `TestSchema.connections` 和 `TestSchema.progress` case 原本没有手动 PRAGMA → 现在统一通过 onConfigure 获得 FK=ON → 行为变化：这两个 schema 现在也有 FK 约束（之前没有），但这是正确的（与生产一致）
   - `onConfigure` 回调的 `db` 参数类型是 `Database`（sqflite_common_ffi 的 Database），与生产 sqflite 的 `Database` 接口一致
   - 删除手动 PRAGMA 后，如果 onConfigure 意外不执行 → FK 不会生效 → 测试会暴露此问题（比之前更严格）

   **测试文件位置：`test/features/connection/bug_16_repro_test.dart`**

---

## §4 不变量

- **[BUG-16-INV1]** 每次数据库 open 后 FK 约束生效
  证据：`database_helper.dart:33`（修复目标：移到 onConfigure）

- **[BUG-16-INV2]** 测试与生产数据库行为一致
  证据：`test_database.dart:104-115`（修复目标：单源化）

---

## §5 测试规约

### 5.2 测试 ID 派生清单

```
BUG-16-S1 S2          # PRAGMA 位置 + 测试单源化
BUG-16-INV1 INV2      # 每次 open 生效 + 测试=生产
```

### 5.4 测试文件位置

| 测试 ID | 文件路径 |
|---------|----------|
| BUG-16-S1 | `test/features/connection/bug_16_repro_test.dart` |
| BUG-16-S2 | `test/features/connection/bug_16_repro_test.dart`（验证 test_database FK 行为） |

---

## §7 跨模块影响

| 其它 feature | 影响点 | 影响条件 | 需要补的回归断言 |
|---|---|---|---|
| PLY | deletePlaylist CASCADE | 重启后删单 | 删单后 playlist_tracks 无孤儿行 |

---

## §8 平台特性与手动 QA

本功能不涉及平台原生特性，全部可在 `flutter test` 中验证。

---

## §9 dev-status.json 条目对照

见统一更新：`docs/dev/dev-status.json`。

---

## §10 changelog

- 2026-07-27: 创建 BUG-16 spec（基于 cr-20260724-0110.md DB2 = CTR8）
