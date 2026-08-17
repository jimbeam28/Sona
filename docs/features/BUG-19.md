# BUG-19 — 生产 DB 迁移逻辑（v1→v2）零锚定：db_migration_test 内联重实现 `_onUpgrade`、test_database schema 双份手工同步

## §0 头部元数据

```yaml
id: BUG-19
name: 生产 DB 迁移逻辑（v1→v2）零锚定：db_migration_test 内联重实现 _onUpgrade、test_database schema 双份手工同步
priority: P1
status: active
created_at: 2026-08-16
last_updated: 2026-08-16
spec_anchored_files:
  - lib/core/database/database_helper.dart
  - test/helpers/test_database.dart
  - test/features/coverage/db_migration_test.dart
  - test/core/bug_19_repro_test.dart
cross_module_impacts: [Connection, Progress, Playlist, Browser]
parent_feature: null   # 跨模块测试基础设施 bug（影响全部 DAO 测试），无单一归属
manual_qa_required: false
```

---

## §1 用户视角

### 1.0 原始需求（用户原话逐字记录）

来源：`docs/cr/cr-20260816-0806-test-helpers.md` F1（cr 复核已确认仍存在）：

> #### F1. 生产 DB 迁移逻辑（v1→v2）零锚定：db_migration_test 内联重实现 `_onUpgrade`，schema 双份手工同步
> - 类型 / 严重度 / 维度：FRAGILE / Major / 可测性（helper 漂移）
> - 证据：
>   - `test/features/coverage/db_migration_test.dart:6` — 文件头自述："Does NOT rely on DatabaseHelper singleton -- exercises raw SQL directly"
>   - `test/features/coverage/db_migration_test.dart:113-120`：
>     ```dart
>     /// Run the same upgrade logic as DatabaseHelper._onUpgrade.
>     Future<void> _runV1ToV2Upgrade(Database db) async {
>       // Equivalent to: if (oldVersion < 2) _createPlaylistTables(db);
>       await db.execute(_v2Playlists);
>       await db.execute(_v2PlaylistTracks);
>       await db.execute(_v2PlaylistIndex);
>       await db.setVersion(2);
>     }
>     ```
>   - 生产迁移 `lib/core/database/database_helper.dart:73-77`（`_onUpgrade`）从未被任何测试经真实 open 路径触发：BUG-16-S1（test/features/connection/bug_16_repro_test.dart:416-485）走的是真实 `DatabaseHelper.instance.database` 首次安装 onCreate 路径，版本已为 2，不触发 onUpgrade。
>   - schema 双份：test_database.dart:30-78 与 db_migration_test.dart:13-68 各内联一份 DDL，生产在 database_helper.dart:38-102。当前逐字段一致（已核对 connections / play_progress / playlists / playlist_tracks 四表 + 两索引），但无任何比对机制。
> - 复现路径（条件化）：未来生产新增 v3 迁移（或修改 playlists 表结构）→ dev-exe 只改 database_helper.dart → db_migration_test / openTestDatabase 内联 SQL 不同步 → **所有迁移/DAO 测试全绿**（它们断言的是内联副本），生产 v1→v2→v3 迁移若坏，无任何测试变红。
> - 自检答案：测试假设本身就错——db_migration_test 假设"内联 SQL == 生产迁移逻辑"恒成立，无机制保证同步（正是 §3 锚定 3"helper 漂移"的教科书形态）。
> - 修复建议：删掉 `_runV1ToV2Upgrade` 副本，用 `resetForTest()` + 真实 openDatabase(version: 2) 路径以 onUpgrade 跑 v1 库（参照 BUG-16-S1 模式）；或至少加一条"内联 DDL 与 database_helper.dart 源码文本 diff"的守卫测试。

### 1.1 这一功能干什么（一句话）

消除测试库 schema 与生产数据库 schema 的"双份手工同步"——测试用库结构、迁移测试全部改为直接驱动生产迁移逻辑，让"改坏生产迁移必然有测试变红"。

### 1.2 用户期望的场景

| ID | 你看到的样子 | 期望行为 |
|----|----|----|
| U1 | 升级 App 后，以前保存的服务器连接、播放进度、播放单全部还在 | 数据一条不丢（修复前这些保证没有任何自动化测试守护——生产迁移逻辑若被改坏，测试全部照样通过） |
| U2 | 开发者在测试里打开的"测试数据库"，与安装后 App 真实使用的数据库结构完全一致 | 永远一致（修复前测试库建表语句是手抄副本，与真实结构悄悄不同步也不会有人发现） |

---

## §2 已实现的功能骨架（代码锚点）

### 2.1 文件与分层

| 层 | 文件 | 行数 | 角色 |
|---|---|---|---|
| Core | `lib/core/database/database_helper.dart` | 115 | 生产数据库初始化：_onCreate / _onUpgrade / _createPlaylistTables / overrideDatabase / resetForTest |
| 测试 helper | `test/helpers/test_database.dart` | 165 | openTestDatabase：内联 schema 副本 + DatabaseHelper 注入 |
| 测试 | `test/features/coverage/db_migration_test.dart` | 233 | TREF-06 迁移测试：内联重实现 _onUpgrade |
| 测试 | `test/core/bug_19_repro_test.dart` | 本 spec §5.4 | 本 Bug 门禁（Part A 生产真实迁移锚定 + Part B 副本不一致实证） |

### 2.2 关键 Provider 表

本 Bug 不涉 Provider（纯 SQLite 迁移基础设施），跳过。

### 2.3 状态机图

本 Bug 不涉状态机，跳过。

---

## §3 行为规约（Given-When-Then）

### 3.1 现有行为（逆抽，缺陷态）

- **[BUG-19-S1]** db_migration_test 内联重实现 `_onUpgrade`，6 个迁移用例全部断言副本而非生产逻辑
  ```
  Given 测试环境（sqflite_ffi）
  When 运行 db_migration_test 的 DB-MIG-01~06
  Then 升级用例（DB-MIG-03/04）调用 `_runV1ToV2Upgrade`（内联副本）
  And 生产 `_onUpgrade`（database_helper.dart:73-77）零执行
  ```
  Code evidence:
  - `test/features/coverage/db_migration_test.dart:113-120`（`_runV1ToV2Upgrade`，注释自认 "Run the same upgrade logic as DatabaseHelper._onUpgrade"）
  - `test/features/coverage/db_migration_test.dart:181`（DB-MIG-03 调 `_runV1ToV2Upgrade(db)`）、:202（DB-MIG-04 同）
  - `test/features/coverage/db_migration_test.dart:6`（文件头自述 "Does NOT rely on DatabaseHelper singleton -- exercises raw SQL directly"）

- **[BUG-19-S2]** test_database 内联 schema 副本与生产 DDL 存在可观测差异（幂等语义）
  ```
  Given openTestDatabase(TestSchema.playlist) 打开测试库
  When 查询 sqlite_master.sql
  Then playlists/playlist_tracks/索引的建表原文为裸 CREATE TABLE/INDEX
  And 生产 _createPlaylistTables 的原文为 CREATE TABLE/INDEX IF NOT EXISTS
      （生产"表已存在时重跑"不抛错，副本会抛 DatabaseException）
  ```
  Code evidence:
  - `test/helpers/test_database.dart:62-78`（`_createPlaylistTables` 裸 CREATE，无 IF NOT EXISTS）
  - `lib/core/database/database_helper.dart:81/89/99`（`CREATE TABLE/INDEX IF NOT EXISTS`）
  - repro 实证：`test/core/bug_19_repro_test.dart` Part B 修复前 FAIL——sqlite_master.sql 为裸 `CREATE TABLE playlists`，断言 `contains('IF NOT EXISTS')` 失败

- **[BUG-19-S3]** 生产 `_onUpgrade` 从未经真实 open 路径触发
  ```
  Given 全测试集
  When 扫描所有触发 DatabaseHelper open 路径的测试
  Then BUG-16-S1（bug_16_repro_test.dart:414-478）走首次安装 onCreate（版本已为 2）
  And 无任何测试以 version<2 的库文件触发 openDatabase 的 onUpgrade 回调
  ```
  Code evidence:
  - `test/features/connection/bug_16_repro_test.dart:414-478`（首次安装 → onCreate；重启 → 版本匹配无回调，:449-450 注释原文"版本匹配 → 不触发 onCreate，只走 onConfigure"）
  - `lib/core/database/database_helper.dart:73-77`（`_onUpgrade` 无任何调用点——grep lib/ + test/ 仅 db_migration_test.dart:113 注释提及）

### 3.2 修复方案（status: new）

修复总策略：**生产 schema/迁移逻辑单一权威（database_helper.dart），test_database 与 db_migration_test 一律经生产代码建库，不再有独立内联 DDL**。唯一 lib/ 改动是给 DatabaseHelper 增加一个公开的建 schema 入口（包装既有私有 `_onCreate`，零行为变化）。

- **[BUG-19-S4]** database_helper.dart 新增公开入口 `createSchema`，包装生产 `_onCreate` （status: new）
  ```
  Given DatabaseHelper（实例单例）
  When 调用 DatabaseHelper.instance.createSchema(db)（任意数据库句柄）
  Then 执行与首次安装 onCreate 完全相同的建表序列：
      connections → play_progress → idx_progress_lookup → playlists →
      playlist_tracks → idx_playlist_tracks_playlist_id
  And 全部 CREATE 带 IF NOT EXISTS 幂等语义
  否定断言:
    - createSchema 不得改变 _onCreate 既有行为（_onCreate 本身一行不改）
    - createSchema 不得执行任何 DROP/DELETE/INSERT（只建表）
    - createSchema 不得修改传入 db 的 user_version（不 setVersion）
  ```
  **修改点**：`lib/core/database/database_helper.dart:102` 之后（`_createPlaylistTables` 结束 `}` 与 :104 `overrideDatabase` 注释之间）插入：
  ```dart
  // Exposed for testing (BUG-19): runs the production v2 schema creation
  // (onCreate) against any database handle, so test helpers can build the
  // exact production schema without re-declaring DDL.
  Future<void> createSchema(Database db) async {
    await _onCreate(db, _dbVersion);
  }
  ```
  `_onCreate` 签名 `(Database db, int version)`（database_helper.dart:37）直接复用；`_dbVersion = 2`（:9）。不新增任何其它方法、不改私有方法。

- **[BUG-19-S5]** test_database.dart 删除内联 DDL 副本，openTestDatabase 改经生产 createSchema 建库 + 子集 DROP （status: new）
  ```
  Given openTestDatabase(schema)（四个 TestSchema 子集语义不变）
  When 打开 in-memory 库
  Then 经 DatabaseHelper.instance.createSchema(db) 建生产全量 v2 schema
  And 按 TestSchema 子集 DROP 多余表（保留原子集语义）
  And DatabaseHelper.instance.overrideDatabase(db) 注入（不变）
  否定断言:
    - test_database.dart 不得再包含任何 CREATE TABLE / CREATE INDEX 文本（内联 DDL 副本彻底删除）
    - openTestDatabase 返回的库中，保留的表与修复前同名同结构（子集语义逐表一致）
    - connections 表在 TestSchema.connections 下仍唯一存在（不得多出 play_progress/playlists/playlist_tracks）
  ```
  **修改点**：`test/helpers/test_database.dart`
  1. 删除 :30-78 四个常量 `_createConnectionsTable` / `_createPlayProgressTable` / `_createProgressIndex` / `_createPlaylistTables`（整块删除）
  2. `openTestDatabase`（:96-131）body 替换为：
  ```dart
  Future<Database> openTestDatabase(TestSchema schema) async {
    final db = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        onConfigure: (db) async {
          await db.execute('PRAGMA foreign_keys = ON');
        },
      ),
    );

    // 生产 v2 schema（database_helper.dart _onCreate）——单一权威来源
    // （BUG-19：修复前内联 DDL 副本与生产双份手工同步，无比对机制）。
    await DatabaseHelper.instance.createSchema(db);

    // 子集语义：DROP 掉不属于本 schema 的表。顺序必须满足 FK 依赖
    // （playlist_tracks 先于 playlists；play_progress 先于 connections），
    // 索引随表自动删除。
    switch (schema) {
      case TestSchema.connections:
        await db.execute('DROP TABLE IF EXISTS playlist_tracks');
        await db.execute('DROP TABLE IF EXISTS playlists');
        await db.execute('DROP TABLE IF EXISTS play_progress');
        break;
      case TestSchema.progress:
        await db.execute('DROP TABLE IF EXISTS playlist_tracks');
        await db.execute('DROP TABLE IF EXISTS playlists');
        break;
      case TestSchema.playlist:
        await db.execute('DROP TABLE IF EXISTS play_progress');
        await db.execute('DROP TABLE IF EXISTS connections');
        break;
      case TestSchema.full:
        break;
    }

    DatabaseHelper.instance.overrideDatabase(db);
    return db;
  }
  ```
  3. :80-83 `initSqfliteFfi`、:137-149 `seedConnection`、:151-165 `ProgressDaoTestHelper` **不动**。
  4. 文件头 :1-7 注释补一句 schema 来源说明（一句即可，dev-exe 照写）：
  ```
  // Schema 由生产 DatabaseHelper.createSchema（database_helper.dart _onCreate）
  // 单一来源构建（BUG-19），本文件不声明任何 CREATE 语句。
  ```
  **可行性依据**：`DatabaseHelper.instance` 是 `DatabaseHelper._()` 私有构造的单例（database_helper.dart:11-12），`createSchema` 为实例方法可经 `DatabaseHelper.instance.createSchema(db)` 调用；`_onCreate` 全量建表包含四表+两索引（database_helper.dart:38-71），IF NOT EXISTS 建表后在 DROP 前表必存在，`DROP TABLE IF EXISTS` 幂等安全。sqlite_sequence 表随 DROP TABLE 自动清理（SQLite 标准行为），无残留行影响后续插入的自增 ID。

- **[BUG-19-S6]** db_migration_test.dart 删除 `_runV1ToV2Upgrade` 副本与 v2 内联 DDL，升级用例改真实 open 路径驱动 （status: new）
  ```
  Given DB-MIG-03/04（升级行为用例）
  When 运行 db_migration_test
  Then 升级用例经 DatabaseHelper.instance.database 真实 open 路径触发生产 _onUpgrade
  And 生产 _createPlaylistTables 被执行（不再有 _runV1ToV2Upgrade 副本）
  否定断言:
    - db_migration_test.dart 不得再包含 _runV1ToV2Upgrade 函数
    - db_migration_test.dart 不得再包含 _v2Playlists/_v2PlaylistTracks/_v2PlaylistIndex 常量（v2 DDL 副本删除；v1 常量保留，见下）
    - 生产 _onUpgrade 之外的任何代码不得再执行"补建 v2 表"的 SQL（唯一执行点是生产迁移）
  ```
  **修改点**：`test/features/coverage/db_migration_test.dart`
  1. 删除 :45-68 `_v2Playlists` / `_v2PlaylistTracks` / `_v2PlaylistIndex` 三个常量（v2 DDL 副本）；**保留** :13-43 `_v1Connections` / `_v1PlayProgress` / `_v1ProgressIndex` 与 :72-81 `_openV1Database`——v1 是历史遗留形态，重建它是迁移测试的必要输入，不构成漂移面。
  2. 删除 :83-95 `_openV2Database` 与 :113-120 `_runV1ToV2Upgrade`（副本函数）。
  3. 新增 :72 附近（`_openV1Database` 之后）文件级辅助函数（照抄 repro Part A 的驱动模式，:96-100 节）：
  ```dart
  /// 经 DatabaseHelper 真实 open 路径触发生产 _onUpgrade（BUG-19）：
  /// 以 version:2 打开一个 user_version=1 的库文件 → sqflite 调
  /// _onUpgrade(1, 2) → _createPlaylistTables。
  ///
  /// 返回迁移完成的库句柄；调用方负责 addTearDown(db.close)。
  Future<Database> _runRealV1ToV2Migration() async {
    // 镜像 DatabaseHelper._dbName（私有常量）。
    const dbFileName = 'nas_audio_player.db';
    DatabaseHelper.instance.resetForTest();
    final dbPath = p.join(await getDatabasesPath(), dbFileName);
    await deleteDatabase(dbPath);
    final v1 = await databaseFactoryFfi.openDatabase(dbPath);
    await v1.execute('PRAGMA foreign_keys = ON');
    await v1.execute(_v1Connections);
    await v1.execute(_v1PlayProgress);
    await v1.execute(_v1ProgressIndex);
    await v1.setVersion(1);
    await v1.close();
    DatabaseHelper.instance.resetForTest();
    return DatabaseHelper.instance.database;
  }
  ```
  新增 import（照抄 repro Part A 头部）：`package:nas_audio_player/core/database/database_helper.dart`、`package:path/path.dart as p`；`getDatabasesPath`/`deleteDatabase`/`databaseFactory` 由 `sqflite_ffi.dart` 导出（bug_16_repro_test.dart:53/398 已实证）。
  4. 用例改写（保留 6 个用例编号 DB-MIG-01~06 与断言意图，驱动源换成生产路径）：
     - DB-MIG-01（v1 结构）：**保留原样**（:135-146，v1 是历史输入）。
     - DB-MIG-02（v2 四表）：改为 `final db = await openTestDatabase(TestSchema.full);` + 原断言（经生产 onCreate，见 test_database 修复）。import `../../helpers/test_database.dart`。
     - DB-MIG-03（v1→v2 数据保留）：body 替换为——`final db = await _runRealV1ToV2Migration();` → 先裸插 1 行 connections（原 :168-178 插入代码保留）→ 断言升级后数据保留（原 :184-194 断言保留）。注意顺序：插入必须在 v1 库上（`_runRealV1ToV2Migration` 已把迁移跑完）——故拆分：该用例不调 `_runRealV1ToV2Migration` 的封装，而是内联 v1 建库+插数据+真实迁移三步（照抄 repro A1 前 40 行：`_createV1Database` 带哨兵插入 → resetForTest → `DatabaseHelper.instance.database` → 断言）。**裁决**：DB-MIG-03 直接内联三步，不复用 `_runRealV1ToV2Migration`（它无插入步骤）。
     - DB-MIG-04（v1→v2 建索引）：body 替换为 `final db = await _runRealV1ToV2Migration();` + 原索引断言（:205-206）。
     - DB-MIG-05（v2 全索引）：改为 `openTestDatabase(TestSchema.full)` + 原断言（:217-218）。
     - DB-MIG-06（FK）：保留原样（:223-231，PRAGMA 断言与 schema 来源无关；生产 onConfigure 已保证 FK=ON）。
  5. 文件头 :4-6 注释改为：`// Tests schema creation and migration using sqflite_ffi. v1 schema is
     // rebuilt locally (historical input); v2 schema and the v1→v2 upgrade are
     // driven through the real DatabaseHelper open path (BUG-19).`
  6. DB-MIG-03/04 新增 `setUpAll`（照抄 bug_16_repro_test.dart:395-399）：
  ```dart
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });
  ```
  （DB-MIG-02/05 走 `openTestDatabase` 的调用方无需此设置——`openTestDatabase` 直接使用 `databaseFactoryFfi`。）

**边界裁决（弱模型照此实现，无需二次判断）**：

| 边界情况 | 裁决 |
|---|---|
| `createSchema` 重复调用（同一 db 两次） | 不抛错（IF NOT EXISTS 幂等）；测试不触发此场景，无需测试 |
| `createSchema` 在 v1 库上调用（有 connections/play_progress 无 playlists） | 全量 IF NOT EXISTS 建表，v1 表保留、playlists 表补建——与真实迁移语义一致 |
| `TestSchema.connections` 子集 DROP 后 play_progress 表不存在时再插 play_progress 行 | 抛 DatabaseException（无此表）——与修复前行为一致（原副本也只建 connections） |
| `seedConnection` 在子集 DROP 后使用 | 不变（只依赖 connections 表，:137-149 不动） |
| DB-MIG-03 内联三步与 `_runRealV1ToV2Migration` 重复 | 允许重复（测试文件内部自洽优先）；若 dev-exe 认为可合并为带可选插入参数的单一 helper，亦可，但 DB-MIG-03 必须断言插入行存在 |
| 磁盘库文件 `nas_audio_player.db` 与其它测试（如 BUG-16-S1）共用 | 每个用例开头 `deleteDatabase(dbPath)` 清场 + 结束时 `DatabaseHelper.instance.resetForTest()`；bug_16_repro_test.dart 已证明同文件多用例安全 |
| 现有 30 个 openTestDatabase 调用方（con_03~09 / prg / ply_10/11 等） | 断言零改动、零编译改动——`openTestDatabase` 签名与返回值类型不变；语义（四子集表清单）经 S5 否定断言守护 |
| `initSqfliteFfi`（test_database.dart:80-83） | 不动；DB-MIG-06 原样保留即可（sqfliteFfiInit 幂等） |

---

## §4 不变量

- **[BUG-19-INV1]** test/ 下不得存在与生产 schema 独立的内联 CREATE 副本
  证据：修复后 `grep -rn "CREATE TABLE\|CREATE INDEX" test/` 除 v1 历史输入（db_migration_test.dart:13-43）与 repro/既有断言外 0 命中；test_database.dart:30-78 删除；db_migration_test.dart:45-68 删除。未来新增测试库必须经 `openTestDatabase` / `DatabaseHelper.instance.createSchema`。

- **[BUG-19-INV2]** 生产迁移逻辑（`_onUpgrade` → `_createPlaylistTables`）必须经真实 open 路径被执行
  证据：`_onUpgrade` 是私有方法（database_helper.dart:73），唯一合法执行路径是 `openDatabase(version: 2)` 打开 user_version<2 的库；bug_19_repro Part A（A1/A2）与 DB-MIG-03/04 经 `DatabaseHelper.instance.database` 驱动。若生产 `_onUpgrade` 被改坏（漏建索引、改错 CASCADE、删掉 if 分支），A1/A2 与 DB-MIG-03/04 必红。

---

## §5 测试规约

### 5.1 现有测试清单

| 测试文件 | 覆盖的 Scenario / INV | 备注 |
|---|---|---|
| test/core/bug_19_repro_test.dart | BUG-19-S2（Part B 实证）、S4/S5/S6 修复后 PASS、INV2（Part A） | 本 Bug 门禁（修复前 FAIL，已用 repro-test.sh fail 确认） |
| test/features/coverage/db_migration_test.dart | BUG-19-S1（现状段）、S6（改写后） | 6 个用例经 S6 改写后驱动生产路径 |
| test/features/connection/bug_16_repro_test.dart | BUG-19-S3（佐证：唯一真实 open 路径测试但走 onCreate） | 既有文件，零改动 |

### 5.2 测试 ID 派生清单（dev-exe 派发测试 Agent 用）

```
BUG-19-S1 … S6        # Scenario（S1~S3 为缺陷态/现状锚定，S4~S6 为修复目标）
BUG-19-INV1 … INV2    # 不变量
```

dev-exe 要求：S4~S6/INV1/INV2 由 §5.4 门禁测试覆盖；S1~S3 由既有测试文件锚定（S1 = db_migration_test 现状段，S2/S3 = bug_19 repro Part B/A + bug_16_repro_test 佐证）。

### 5.3 测试覆盖盲点（dev-plan 写本文档时识别）

| 未覆盖 ID | 现状 | 应补偿方式 |
|---|---|---|
| BUG-19-INV1（grep 层面） | 无自动化断言"test/ 无内联 CREATE 副本" | dev-exe 手动 grep 核对（一次性）；不引入新测试——修复本身即删除全部副本 |

### 5.4 测试文件位置（spec-scan --gate 硬校验）

| 测试文件 | 覆盖 ID | 说明 |
|---|---|---|
| test/core/bug_19_repro_test.dart | BUG-19-S4、S5、S6、INV2（Part A 三断言组）+ S2 实证（Part B） | 门禁：dev-exe 修复后必须 PASS（repro-test.sh pass） |
| test/features/coverage/db_migration_test.dart | BUG-19-S6（改写后）、S1（现状段） | 既有文件，按 S6 修改点改写 |

---

## §6 算法样例

本 Bug 不涉纯函数算法，跳过。

---

## §7 跨模块影响

`bash cross-imports.sh impact lib/core/database/database_helper.dart`（2026-08-16）→ lib/ 侧引用方：三个 DAO（playlist_dao / progress_dao / connection_dao）。`test_database.dart` 被 30 个测试文件 import（grep 2026-08-16 核实，含本 repro）：

| 其它 feature | 影响点 | 影响条件 | 需要补的回归断言 |
|---|---|---|---|
| Core DAO（PlaylistDao / ProgressDao / ConnectionDao） | `database_helper.dart` 新增公开 `createSchema` | `_onCreate`/`_onUpgrade`/`_createPlaylistTables` 一行不改，DAO 无感知 | 三个 DAO 既有测试全绿（DAO 行为零变化） |
| Connection（con_03/04/05/06/09、bug_14/16、bug_bug10、bug_bug17） | `openTestDatabase` 实现换源（生产 createSchema + 子集 DROP） | 子集表清单逐表一致（S5 否定断言守护） | 上述 9 个文件全绿 |
| Progress（prg、bug_11、ref_25、test_09、net1_legacy_progress、bug_bug03） | 同上 | 同上 | 上述 6 个文件全绿 |
| Playlist（ply_10/11、ref_26、bug_08、bug_bug02×2、bug_bug25、net1_legacy_playlist） | 同上 | 同上 | 上述 8 个文件全绿 |
| Browser（brw_04、net1_legacy_queue_restore） | 同上 | 同上 | 上述 2 个文件全绿 |
| Coverage（aud_03、int_g01、int_g05、bug_bug26） | 同上 | 同上 | 上述 4 个文件全绿 |

**回归断言要求（dev-exe 门禁）**：
1. `flutter test test/` 全绿（尤其上述 29 个引用文件 + bug_16_repro_test + db_migration_test）。
2. `bash .claude/plugins/sona-dev/scripts/repro-test.sh test/core/bug_19_repro_test.dart pass` 退出码 0。
3. `bash .claude/plugins/sona-dev/scripts/cross-imports.sh all` 退出码 0（新增 import 不破坏 domain-flutter / feature-isolation / secret-logs——db_migration_test 新增 import 均为既有依赖，无新依赖）。
4. `flutter analyze --no-fatal-infos` 0 error / 0 warning（`p`、`getDatabasesPath`、`deleteDatabase` 均为既有依赖符号）。

---

## §8 平台特性与手动 QA

设计前已逐条核对 `docs/dev/platform-pitfalls.md`：本 Bug 为纯测试基础设施修复，不触及 P1~P17 任何一条（无播放/网络/超时/生命周期/Provider 变化）。sqflite 的 openDatabase `version/onUpgrade` 协议（onUpgrade 返回后自动推进 user_version）是 sqflite 跨平台（Android/桌面 ffi）同一语义，ffi 真实路径可完整近似 Android 端迁移行为。

**真机风险列**：

| 风险 | 近似测试方案 | 测不了 → 进 mqa-backlog |
|---|---|---|
| 无（不涉及平台原生：无 audio_service / MethodChannel / 通知栏 / 网络 / 真机时序） | 本 Bug 不涉及平台原生特性，全部可在 `flutter test` 中验证 | 无 |

---

## §9 dev-status.json 条目对照

```json
"BUG-19": {
  "spec_file": "docs/features/BUG-19.md",
  "spec_anchored_files": ["lib/core/database/database_helper.dart", "test/helpers/test_database.dart", "test/features/coverage/db_migration_test.dart", "test/core/bug_19_repro_test.dart"],
  "scenarios": ["BUG-19-S1", "BUG-19-S2", "BUG-19-S3", "BUG-19-S4", "BUG-19-S5", "BUG-19-S6"],
  "invariants": ["BUG-19-INV1", "BUG-19-INV2"],
  "algorithms": [],
  "manual_qa_required": false,
  "user_acceptance_text": "见 §1.2"
}
```
