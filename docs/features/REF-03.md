# REF-03 — 死代码清理（PRG4 + DB8）

> 来源：`docs/cr/cr-20260724-0110.md` PRG4 + DB8

---

## §0 头部元数据

```yaml
id: REF-03
name: 死代码清理（PRG4 + DB8）
priority: P2
status: draft
created_at: 2026-07-27
last_updated: 2026-07-27
spec_anchored_files:
  - lib/features/progress/domain/progress_service.dart
  - lib/core/database/dao/progress_dao.dart
  - lib/core/contracts/database_contract.dart
cross_module_impacts: [PRG]
parent_feature: null
manual_qa_required: false
```

---

## §1 用户视角

### 1.0 原始需求

> cr-20260724-0110.md PRG4：`progress_service.dart:19-33` — SaveTrigger 枚举声称 5 个调用点但 service 完全忽略 trigger 参数（直接透传给 DAO，不做分支）。死参数。
> cr-20260724-0110.md DB8：`progress_dao.dart:78-83` — `rawInsert`（注释 "Useful for testing"）存在于生产 DAO 和 contract 接口中。测试专用方法不应出现在生产代码和接口定义里。

### 1.1 这一功能干什么（一句话）

删除 `SaveTrigger` 死代码和 `rawInsert` 生产代码泄漏，使接口表面最小化。

### 1.2 用户期望的场景

| ID | 你看到的样子 | 期望行为 |
|----|----|----|
| U1 | ProgressService.saveProgress 签名 | 无 trigger 参数 |
| U2 | IProgressDao 接口 | 无 rawInsert 方法 |
| U3 | ProgressDao 生产类 | 无 rawInsert 方法 |
| U4 | 测试中使用 rawInsert | 通过 test helper extension 或直接在测试中操作 DB |

---

## §2 已实现的功能骨架

### 2.1 文件与分层

| 层 | 文件 | 行数 | 角色 |
|---|---|---|---|
| Domain | `lib/features/progress/domain/progress_service.dart` | 143 | SaveTrigger enum(:27-33) + saveProgress(:54-67) |
| DAO | `lib/core/database/dao/progress_dao.dart` | 179 | rawInsert(:78-83) |
| Contract | `lib/core/contracts/database_contract.dart` | 124 | rawInsert(:67) |
| Test | `test/features/progress/ref_25_test.dart` | — | SaveTrigger 测试（14 处引用） |
| Test | `test/features/progress/prg_test.dart` | — | rawInsert 测试（5 处调用） |
| Test | `test/features/progress/bug_09_test.dart` | — | fake 中 rawInsert 存根（:62） |

### 2.2 关键代码段

| 区域 | 行号 | 说明 |
|---|---|---|
| SaveTrigger enum | `progress_service.dart:27-33` | 5 个值：periodic/pause/skipNext/skipPrev/complete |
| saveProgress trigger 参数 | `progress_service.dart:54-67` | 参数 `SaveTrigger trigger = SaveTrigger.periodic`，但函数体不引用 trigger |
| rawInsert DAO | `progress_dao.dart:78-83` | 直接插入，跳过 shouldSave/shouldClear 策略检查 |
| rawInsert contract | `database_contract.dart:67` | `Future<void> rawInsert(PlayProgress progress);` |

---

## §3 行为规约

### 3.1 PRG4 — 删除 SaveTrigger 死代码

- **[REF-03-S1]** ProgressService.saveProgress 无 trigger 参数 (`status: new`)
  ```
  Given ProgressService.saveProgress 方法签名
  When  静态分析
  Then  无 SaveTrigger 参数
  And   无 SaveTrigger enum 定义
  否定断言:
    - 不在 progress_service.dart 中出现 SaveTrigger 枚举（当前 :27-33）
    - 不在 saveProgress 参数列表中出现 trigger（当前 :59 `SaveTrigger trigger = SaveTrigger.periodic`）
    - 不改变 saveProgress 的返回值（仍委托 _dao.upsert 返回 bool?）
    - 不改变 upsert 调用的参数传递（connectionId/filePath/positionMs/durationMs 不变）
  ```
  Code evidence: `lib/features/progress/domain/progress_service.dart:27-33`（enum）、`:59`（参数）、`:61-66`（函数体不引用 trigger）

  **修改指令 — `lib/features/progress/domain/progress_service.dart`**

  位置：`:19-33`（注释 + enum）
  删除整个 SaveTrigger enum 及其注释块（`:19-33`）。

  位置：`:47-67`（saveProgress 方法）
  当前代码（:54-67）：
  ```dart
  Future<bool?> saveProgress({
    required int connectionId,
    required String filePath,
    required int positionMs,
    int? durationMs,
    SaveTrigger trigger = SaveTrigger.periodic,
  }) {
    return _dao.upsert(
      connectionId: connectionId,
      filePath: filePath,
      positionMs: positionMs,
      durationMs: durationMs,
    );
  }
  ```
  改为：
  ```dart
  Future<bool?> saveProgress({
    required int connectionId,
    required String filePath,
    required int positionMs,
    int? durationMs,
  }) {
    return _dao.upsert(
      connectionId: connectionId,
      filePath: filePath,
      positionMs: positionMs,
      durationMs: durationMs,
    );
  }
  ```

  **调用方适配：**

  `test/features/progress/ref_25_test.dart` — 14 处 `trigger:` 参数需删除。测试逻辑不变（所有 trigger 值都委托给同一个 upsert）。

  `progress_provider.dart:86-91` — `service.saveProgress(...)` 不传 trigger（已无此参数），无需修改。

### 3.2 DB8 — rawInsert 移出生产代码

- **[REF-03-S2]** IProgressDao 不含 rawInsert (`status: new`)
  ```
  Given IProgressDao 接口定义
  When  静态分析
  Then  不包含 rawInsert 方法
  否定断言:
    - 不在 database_contract.dart 中出现 rawInsert（当前 :67）
    - 不在 progress_dao.dart 生产类中出现 rawInsert（当前 :78-83）
    - 不改变 upsert/find/delete 等生产方法的行为
  ```
  Code evidence: `lib/core/contracts/database_contract.dart:67`、`lib/core/database/dao/progress_dao.dart:78-83`

  **修改指令 — `lib/core/contracts/database_contract.dart`**

  位置：`:66-67`
  当前：
  ```dart
  /// Inserts a progress record directly without policy checks.
  Future<void> rawInsert(PlayProgress progress);
  ```
  删除这两行。

  **修改指令 — `lib/core/database/dao/progress_dao.dart`**

  位置：`:75-83`
  当前：
  ```dart
  /// Inserts a [progress] record directly without [shouldSave] / [shouldClear]
  /// checks.  Useful for testing when you need explicit control over
  /// timestamps (e.g. [getRecentlyPlayed] ordering tests).
  Future<void> rawInsert(PlayProgress progress) async {
    final db = await _db;
    final map = progress.toMap();
    map.remove('id'); // let AUTOINCREMENT assign it
    await db.insert('play_progress', map);
  }
  ```
  删除这 9 行。

  **测试适配：**

  在 `test/helpers/test_database.dart` 或新建 `test/helpers/progress_test_helper.dart` 添加：
  ```dart
  extension ProgressDaoTestHelper on ProgressDao {
    Future<void> rawInsertForTest(PlayProgress progress) async {
      // 直接操作底层 DB，绕过 shouldSave/shouldClear
    }
  }
  ```

  或者更简洁：测试中直接使用 test database 的 `Database` 实例执行 `db.insert('play_progress', progress.toMap())`。

  `test/features/progress/prg_test.dart` — 5 处 `dao.rawInsert(...)` 改为使用 test helper。
  `test/features/progress/bug_09_test.dart:62` — fake 中 `rawInsert` 存根需删除。

- **[REF-03-S3]** 测试中 rawInsert 使用 test helper (`status: new`)
  ```
  Given 测试文件需要直接插入 progress 记录
  When  测试运行
  Then  使用 test helper（非 production DAO 方法）
  否定断言:
    - 不在测试中调用 production DAO 的 rawInsert（已删除）
    - 不改变测试的数据设置语义（rawInsertForTest 等价于原 rawInsert）
  ```
  Code evidence: `test/features/progress/prg_test.dart:438,468,476,518,526,1210`

---

## §4 不变量

- **[REF-03-INV1]** SaveTrigger enum 不存在于代码库
  证据：`grep SaveTrigger` 在 `lib/` 下零结果

- **[REF-03-INV2]** rawInsert 不存在于生产代码
  证据：`grep rawInsert` 在 `lib/` 下零结果（仅在 `test/` 的 helper extension 中存在）

---

## §5 测试规约

### 5.1 现有测试清单

| 测试文件 | 覆盖 | 备注 |
|---|---|---|
| `test/features/progress/ref_25_test.dart` | SaveTrigger 参数 | 需删除 trigger 参数（14 处） |
| `test/features/progress/prg_test.dart` | rawInsert 使用 | 需迁移到 test helper（5 处） |
| `test/features/progress/bug_09_test.dart` | fake rawInsert 存根 | 需删除存根（:62） |

### 5.2 测试 ID 派生清单

```
REF-03-S1 … S3        # Scenario
REF-03-INV1 … INV2    # 不变量
```

### 5.3 测试覆盖盲点

| 未覆盖 ID | 现状 | 应补偿方式 |
|---|---|---|
| REF-03-S1 | ref_25_test.dart 需适配 | 删除 trigger 参数后测试仍验证 saveProgress 委托 upsert |
| REF-03-S3 | prg_test.dart 需适配 | 验证 rawInsertForTest 行为等价 |

---

## §6 算法样例

不适用——本重构为死代码删除，无新算法。

---

## §7 跨模块影响

| 其它 feature | 影响点 | 需要补的回归断言 |
|---|---|---|
| PRG | saveProgress 签名变更 | 所有 progress 测试编译通过 |
| PRG | rawInsert 移出 DAO | prg_test 和 bug_09_test 适配 |

---

## §8 平台特性与手动 QA

本功能不涉及平台原生特性，全部可在 `flutter test` 中验证。

---

## §9 dev-status.json 条目对照

见统一更新：`docs/dev/dev-status.json`。

---

## §10 changelog

- 2026-07-27: 创建 REF-03 spec（基于 cr-20260724-0110.md PRG4 + DB8）
