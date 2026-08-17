# BUG-17 — save() 原子性只覆盖步骤 2，步骤 4/5 失败留下共享临时 key 的孤儿行

## §0 头部元数据

```yaml
id: BUG-17
name: save() 原子性只覆盖步骤 2，步骤 4/5 失败留下共享临时 key 的孤儿行
priority: P1
status: active
created_at: 2026-08-16
last_updated: 2026-08-16
spec_anchored_files:
  - lib/features/connection/domain/connection_service.dart
  - lib/core/contracts/database_contract.dart
cross_module_impacts: [Connection]
parent_feature: Connection（连接管理模块）
manual_qa_required: false
```

---

## §1 用户视角

### 1.0 原始需求（用户原话逐字记录）

来源：`docs/cr/cr-20260816-0804-connection-playlist.md` F4（cr 复核 2026-08-16 已确认仍存在）：

> #### F4. save() 原子性只覆盖步骤 2——步骤 4/5 失败留下引用共享临时 key 的孤儿行
> - 类型 / 严重度 / 维度：FRAGILE / Minor / 正确性（原子性承诺不完整）
> - 证据：
>   - `lib/features/connection/domain/connection_service.dart:42-64` — save() 回滚仅包住步骤 2（storage 写失败 → 删行 :51-55）；步骤 4（`_dao.update` :59）与步骤 5（`_dao.setActive` :62）失败无回滚：DB 行已存在且 password 列引用**共享常量** `'connection_password_temp'`（:42），密码却已写入该 id 的永久 key
>   - 对比 update()（BUG-24-S2）为此专门做了 storage 回滚（:85-101）
> - 复现路径（条件：步骤 4/5 的 DAO 写失败）：保存连接 → insert 成功 → 密码写入永久 key → DAO update 抛错 → 异常上抛（用户看到"保存失败"），但 DB 残留一行 password='connection_password_temp' 的孤儿连接 → 列表可见、startupValidation 读 key `connection_password_<id>` 拿到密码（密码其实存在）→ 该行实际可用但 is_active 未置位/或与其它孤儿行共享 temp key：删除任一孤儿行会删掉 temp key 使其它孤儿行密码引用失效（safeStorageDelete :121）。
> - 自检答案：分支零覆盖——REF-22-T02 只测步骤 2 失败回滚；bug_bug24 只测 update/delete 路径；save 步骤 4/5 失败注入无测试。
> - 修复建议：步骤 4/5 失败时删行 + 删永久 key 全量回滚（对齐 update 的 BUG-24-S2 模式）；或改用每次 save 唯一的临时 key（UUID 化）消除共享 key 交叉污染；补步骤 4/5 失败注入测试。

### 1.1 这一功能干什么（一句话）

让"保存连接"的原子性承诺覆盖全部失败点：步骤 4（update）或步骤 5（setActive）失败时回滚删行 + 删永久密码 key，杜绝残留引用共享临时 key 的孤儿行。

### 1.2 用户期望的场景

| ID | 你看到的样子 | 期望行为 |
|----|----|----|
| U1 | 保存连接时数据库中途写失败（如磁盘满） | 显示"保存失败"提示，且数据库里**不残留**任何新建的连接行（修复前：列表里多出一条密码引用悬空的孤儿连接） |
| U2 | 保存失败后查看连接列表 | 列表与保存前完全一致（修复前：出现可见但半残的孤儿行） |
| U3 | 保存成功 | 行为完全不变：行入库、密码写入安全存储、置为活动连接 |
| U4 | 第一次添加连接（此前 0 个连接）时保存失败 | 同样不残留行（修复前：回滚删行会撞"至少保留一个连接"保护，行照样残留且报错文案误导——勘察发现的连带缺陷，见 §3.2 边界裁决） |

---

## §2 已实现的功能骨架（代码锚点）

### 2.1 文件与分层

| 层 | 文件 | 行数 | 角色 |
|---|---|---|---|
| Domain | `lib/features/connection/domain/connection_service.dart` | 143 | `save`（:38-65）：5 步写入 + 仅步骤 2 回滚（:49-55）；`update`（:79-105）有 BUG-24-S2 storage 回滚（:96-101）；`delete`（:118-132）best-effort 清理（:120-130） |
| Contract | `lib/core/contracts/database_contract.dart` | 49 | `IConnectionDao`：insert/findAll/findById/findActive/findPasswordKey/update/setActive/delete/count（:17-49） |
| Data | `lib/core/database/dao/connection_dao.dart` | 160 | `ConnectionDao.delete`（:115-149）：`count() <= 1 → throw LastConnectionException`（:119-122）——回滚删行的守卫边界 |
| 测试 | `test/features/connection/bug_bug17_repro_test.dart` | 本 spec §5.4 | 本 Bug 门禁 |

### 2.2 关键 Provider 表

| Provider 名 | 类型 | 实现位置 | 用途 |
|---|---|---|---|
| connectionServiceProvider | Provider<ConnectionService> | connection_provider.dart:58-63 | save/update/delete/setActive 门面 |
| secureStorageProvider | Provider<ISecureStorage> | connection_provider.dart:54-55 | 密码存储（key 格式 `connection_password_{id}`） |

### 2.3 状态机图

```
save(config, password):
  步骤1 insert(passwordKey: 'connection_password_temp')  → id
  步骤2 safeStorageWrite('connection_password_$id')      ← 失败 → 删行回滚（:49-55）
  步骤3 （步骤 2 的失败回滚）
  步骤4 _dao.update(config, passwordKey: permanentKey)   ← 失败 → 当前无回滚（BUG）
  步骤5 _dao.setActive(id)                               ← 失败 → 当前无回滚（BUG）
  → 返回 savedConfig
```

---

## §3 行为规约（Given-When-Then）

### 3.1 现有行为（逆抽，缺陷态）

- **[BUG-17-S1]** save 的 temp key 是共享常量，步骤 4/5 失败无回滚
  ```
  Given save() 执行到步骤 4（_dao.update）或步骤 5（_dao.setActive）
  When 该 DAO 调用抛错
  Then 异常上抛给调用方（connection_screen.dart:210-224 显示"保存失败"）
  And DB 行已存在且 password 列 = 'connection_password_temp'（共享常量 :42）
  And storage 已有 'connection_password_<id>'（步骤 2 已写入 :48-50）
  And 无任何清理 → 孤儿行残留，且与其它孤儿行共享 temp key
       （删除任一孤儿行会删掉 temp key，其它孤儿行密码引用失效）
  ```
  Code evidence: `lib/features/connection/domain/connection_service.dart:42-64`（:57-62 无 try/catch）

- **[BUG-17-S2]** 对照参照：update() 的 BUG-24-S2 storage 回滚
  ```
  Given update() 旋转密码
  When _dao.update 抛错
  Then safeStorageWrite(permanentKey, oldPassword) 恢复旧密码（:96-101）
  ```
  Code evidence: `lib/features/connection/domain/connection_service.dart:96-101`

### 3.2 修复方案（status: new）

- **[BUG-17-S3]** 步骤 4/5 失败全量回滚：删行 + 删永久 key（status: new）
  ```
  Given save() 步骤 4（_dao.update）或步骤 5（_dao.setActive）抛错
  When 异常发生
  Then 补偿执行：删 DB 行（绕过 CON-T32 守卫，见 S4 依据）+ 删永久 key
       'connection_password_<id>'
  And 补偿自身失败时 debugLog 记录（不回抛、不吞静默，catch-log 纪律）
  And 原异常 rethrow（调用方仍看到"保存失败"）
  否定断言:
    - 失败后 findAll() 不得包含本次新建的行（孤儿行清零）
    - 失败后 storage 不得残留 'connection_password_<id>' 永久 key
    - 失败后不得残留 'connection_password_temp' 的 DB 引用
    - 成功后行为不变（S1 逆抽的 5 步顺序保持）
  ```
  **修改点 1（service 层）**：`lib/features/connection/domain/connection_service.dart:57-62`：
  ```dart
  // 修改前（56-63 行）:
  // Step 4: update the row to reference the permanent key.
  final savedConfig = config.copyWith(id: id, isActive: true);
  await _dao.update(savedConfig, passwordKey: permanentKey);

  // Step 5: mark as active (clears any previous active flag).
  await _dao.setActive(id);

  return savedConfig;
  // 修改后:
  // Step 4: update the row to reference the permanent key.
  final savedConfig = config.copyWith(id: id, isActive: true);
  try {
    await _dao.update(savedConfig, passwordKey: permanentKey);
    // Step 5: mark as active (clears any previous active flag).
    await _dao.setActive(id);
  } catch (_) {
    // BUG-17（cr-20260816-0804 F4）：步骤 4/5 失败全量回滚 —— 删行 +
    // 删永久 key，不留引用共享 temp key 的孤儿行（对齐 BUG-24-S2）。
    await _rollbackSave(id, permanentKey);
    rethrow;
  }

  return savedConfig;
  ```
  **修改点 2（service 层新增私有方法）**：
  ```dart
  // 新增（置于 save() 之后）—— 回滚补偿，best-effort 但必须留日志：
  Future<void> _rollbackSave(int id, String permanentKey) async {
    try {
      await _dao.deleteWithoutGuard(id);
    } catch (e) {
      debugLog('[Conn] save rollback: row delete failed for id=$id: $e');
    }
    try {
      await safeStorageDelete(_storage, key: permanentKey);
    } catch (e) {
      debugLog('[Conn] save rollback: storage cleanup failed for id=$id: $e');
    }
  }
  ```
  说明（弱模型照抄）：`_rollbackSave` 不 rethrow——补偿失败不再掩盖原异常（原异常已在调用方 catch 中继续上抛）；两个补偿步骤独立 try（删行失败也要尝试删 key）。`debugLog` 来自 `log_forwarder.dart`（connection_service.dart:14 已 import）。

- **[BUG-17-S4]** 契约新增无守卫删行方法，同时修复步骤 2 回滚的"首个连接"边界（status: new）
  ```
  Given 回滚删行时 DB 中仅剩本次插入的 1 行（首次添加连接的保存失败）
  When 补偿执行删行
  Then 删除成功（不被 CON-T32 "至少保留一个连接" 守卫拦截）
  And 用户看到的是原异常（保存失败），而非误导性的"至少保留一个连接"
  否定断言:
    - 首次添加连接保存失败时不得残留孤儿行（S3 断言在此边界同样成立）
    - 用户路径的 delete（连接管理页删除）守卫不变——CON-T32 保护
      仍适用于用户删除操作
  ```
  **修改点 1（契约）**：`lib/core/contracts/database_contract.dart:40-45` `IConnectionDao.delete` 之后新增：
  ```dart
  /// Deletes the connection row with [id] WITHOUT the CON-T32 last-connection
  /// guard. Compensation-only method: MUST NOT be used for user-facing
  /// deletes (only for service-layer rollback of a row just inserted by
  /// the same call).
  Future<bool> deleteWithoutGuard(int id);
  ```
  **修改点 2（DAO 实现）**：`lib/core/database/dao/connection_dao.dart` 新增实现（不含守卫的删行 + 级联 progress 清理——复制 :115-149 除 count 守卫外的部分）：
  ```dart
  Future<bool> deleteWithoutGuard(int id) async {
    final db = await _db;
    final config = await findById(id);
    final wasActive = config?.isActive ?? false;
    await db.transaction((txn) async {
      try {
        await txn.delete('play_progress',
            where: 'connection_id = ?', whereArgs: [id]);
      } on DatabaseException catch (e) {
        if (!e.isNoSuchTableError()) rethrow;
      }
      await txn.delete('connections', where: 'id = ?', whereArgs: [id]);
    });
    if (wasActive) {
      final remainingConfigs = await findAll();
      if (remainingConfigs.isNotEmpty) {
        await setActive(remainingConfigs.first.id!);
      }
    }
    return wasActive;
  }
  ```
  **修改点 3（service 步骤 2 回滚同步收敛）**：`lib/features/connection/domain/connection_service.dart:51-55`：
  ```dart
  // 修改前（51-55 行）:
    } catch (_) {
      // Step 3: rollback — remove the DB row if secure-storage write fails.
      await _dao.delete(id);
      rethrow;
    }
  // 修改后:
    } catch (_) {
      // Step 3: rollback — remove the DB row if secure-storage write fails.
      // BUG-17: 用无守卫删行 —— 首次添加连接（0→1）时 count()==1，
      // 守卫版 delete 会抛 LastConnectionException 使回滚失效。
      await _deleteRowForRollback(id);
      rethrow;
    }
  ```
  其中 `_deleteRowForRollback` 为 service 私有封装（失败留日志、不掩盖原异常）：
  ```dart
  Future<void> _deleteRowForRollback(int id) async {
    try {
      await _dao.deleteWithoutGuard(id);
    } catch (e) {
      debugLog('[Conn] save rollback: row delete failed for id=$id: $e');
    }
  }
  ```
  （若 dev-exe 选择让 `_rollbackSave` 与 `_deleteRowForRollback` 合并实现亦可，但两个入口的日志行为必须与上述一致。）

**边界裁决（弱模型照此实现，无需二次判断）**：

| 边界情况 | 裁决 |
|---|---|
| 步骤 4 失败（update 抛错） | `_rollbackSave`：删行（无守卫）+ 删永久 key → rethrow 原异常 |
| 步骤 5 失败（setActive 抛错） | 同上（try 块内两步在同一 catch） |
| 步骤 2 失败（storage 写抛错） | 修改点 3：`_deleteRowForRollback`（无守卫删行）→ rethrow；**不含删永久 key**（永久 key 未写入） |
| 首次添加连接（0 行）步骤 2/4/5 失败 | 无守卫删行 → 删除成功，无孤儿行（S4 修复目标）；用户看到原异常文案 |
| 既有连接存在时保存失败 | 同上（无守卫删行对该场景同样正确） |
| 补偿删行/删 key 自身失败 | `_rollbackSave` / `_deleteRowForRollback` 内 catch + debugLog，不回抛（不掩盖原异常） |
| 用户路径删除（连接管理页） | 守卫不变（connection_dao.dart:115-122 CON-T32 照旧） |
| bug_06_repro_test.dart:42 `_FakeConnectionDao implements IConnectionDao` | 契约新增方法后必须补实现（返回 true 即可）——dev-exe 必须同步修改该文件，否则编译失败 |
| 既有测试 ref_22 / bug_bug24 / con_09 等 | 均 extend ConnectionDao 或经 service 调用——无守卫方法为新增，既有测试不调用它，全部保持绿 |

---

## §4 不变量

- **[BUG-17-INV1]** 任何 save() 失败路径（步骤 2/4/5）都不允许在 DB 中残留本次新建的行：要么完整入库，要么全量回滚
  证据：修复后 connection_service.dart:38-65 + `_rollbackSave`/`_deleteRowForRollback`；缺陷态证据 :57-62（无回滚）

- **[BUG-17-INV2]** `'connection_password_temp'` 临时 key 的 DB 引用不允许在 save 失败后残留（temp key 是共享常量，残留即交叉污染源）
  证据：`lib/features/connection/domain/connection_service.dart:42`（共享常量）+ 修复后回滚保证

- **[BUG-17-INV3]** CON-T32"至少保留一个连接"守卫只适用于用户路径删除；服务层补偿删行（deleteWithoutGuard）不受其约束
  证据：`lib/core/database/dao/connection_dao.dart:115-122`（守卫在用户 delete）；修复后 deleteWithoutGuard 无守卫

---

## §5 测试规约

### 5.1 现有测试清单

| 测试文件 | 覆盖的 Scenario / INV | 备注 |
|---|---|---|
| test/features/connection/ref_22_test.dart（REF-22-T02） | 步骤 2 失败回滚 | 只测 storage 失败（自检答案）；预置一条连接绕开守卫 |
| test/features/connection/bug_bug24_repro_test.dart | update/delete 路径回滚 | 不涉 save 步骤 4/5 |

### 5.2 测试 ID 派生清单（dev-exe 派发测试 Agent 用）

```
BUG-17-S1, S2        # 缺陷态/现状锚定
BUG-17-S3, S4        # 修复目标
BUG-17-INV1 … INV3   # 不变量
```

dev-exe 要求：S3/S4 由 §5.4 门禁测试覆盖（步骤 4、步骤 5、含首次添加边界）；INV1~INV3 由门禁测试断言覆盖。

### 5.3 测试覆盖盲点（dev-plan 写本文档时识别）

| 未覆盖 ID | 现状 | 应补偿方式 |
|---|---|---|
| S4 的"首次添加（0→1）"边界 | 门禁测试 S1/S2 预置了 1 条连接 | dev-exe 在门禁测试内追加"0 连接时步骤 2/4/5 失败"用例（断言无孤儿行 + 异常是原异常非 LastConnectionException）——若追加用例使缺陷态不再 FAIL，须保持原 S1/S2 用例不变（它们已 FAIL 确认） |

### 5.4 测试文件位置（spec-scan --gate 硬校验）

| 测试文件 | 覆盖 ID | 说明 |
|---|---|---|
| test/features/connection/bug_bug17_repro_test.dart | BUG-17-S3、BUG-17-S4、BUG-17-INV1~INV3 | 门禁：修复前 FAIL（已用 repro-test.sh fail 确认——步骤 4/5 失败后孤儿行 + 永久 key 残留）；dev-exe 修复后必须 PASS（repro-test.sh pass） |
| test/features/connection/ref_22_test.dart | BUG-17-S1（缺陷态锚定）+ REF-22-T02 | 既有测试，断言不变 |
| test/features/browser/bug_06_repro_test.dart:42 | IConnectionDao 契约实现 | 契约新增 deleteWithoutGuard 后必须补实现（编译门禁） |

---

## §6 算法样例

本 Bug 不涉纯函数算法，跳过。

---

## §7 跨模块影响

`bash cross-imports.sh impact lib/features/connection/domain/connection_service.dart`（2026-08-16）→ 引用方：

| 其它 feature | 影响点 | 影响条件 | 需要补的回归断言 |
|---|---|---|---|
| Connection provider 层（connection_provider.dart:58-63/:274-276/:353-355） | connectionServiceProvider / ConnectionSaver 包装 | 类签名不变（新增私有方法 + 契约新增方法，公开 API 不变） | con_01 / con_02 / con_09 既有测试全绿 |
| Connection 保存 UI（connection_screen.dart:197-200） | saver.save 调用 | 失败仍 rethrow → "保存失败" SnackBar 不变 | con_01 既有保存测试全绿 |
| Connection DAO（connection_dao.dart:115-149） | 新增 deleteWithoutGuard（复制删行逻辑） | 守卫版 delete 不动；用户删除行为不变 | ref_22-T03/T04（删除守卫/级联）全绿 |
| IConnectionDao 契约实现方（bug_06_repro_test.dart:42） | 契约新增方法 | 必须补实现（return true）否则编译失败 | 编译 + bug_06 测试全绿 |
| 启动验证（connection_provider.dart:165-209 startupValidation） | 读 key connection_password_<id> | 孤儿行不再存在（修复目标）；正常连接读取路径不变 | bug_16 / con_03 既有测试全绿 |

---

## §8 平台特性与手动 QA

设计前已逐条核对 `docs/dev/platform-pitfalls.md`：触及 **P17 分层表**的独立存储超时条目（flutter_secure_storage 读/写/删 5s，BUG-32）——本修复的 `_rollbackSave` 用 `safeStorageDelete`（已含 5s 超时，storage_utils.dart），不改任何超时数值，不回写分层表。

**真机风险列**：无。本功能不涉及平台原生特性（storage 侧经 ISecureStorage 契约 + fake 可完整测试；真机存储失败路径与 fake 语义一致），全部可在 `flutter test` 中验证。

---

## §9 dev-status.json 条目对照

```json
"BUG-17": {
  "spec_file": "docs/features/BUG-17.md",
  "spec_anchored_files": ["lib/features/connection/domain/connection_service.dart", "lib/core/contracts/database_contract.dart"],
  "scenarios": ["BUG-17-S1", "BUG-17-S2", "BUG-17-S3", "BUG-17-S4"],
  "invariants": ["BUG-17-INV1", "BUG-17-INV2", "BUG-17-INV3"],
  "algorithms": [],
  "manual_qa_required": false,
  "user_acceptance_text": "见 §1.2"
}
```
