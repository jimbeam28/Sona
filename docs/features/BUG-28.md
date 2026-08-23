# BUG-28 — ConnectionDao.delete 自动激活在事务外，两步间中断致零活跃连接

```yaml
id: BUG-28
name: delete 的 CON-T34 自动激活未与删行同事务（进程中断窗口 → 全库零活跃）
priority: P4
status: active
created_at: 2026-08-23
last_updated: 2026-08-23
spec_anchored_files:
  - lib/core/database/dao/connection_dao.dart
cross_module_impacts:
  - lib/features/connection/connection_provider.dart
parent_feature: Connection
manual_qa_required: false
```

---

## §1 用户视角

### 1.0 原始需求（来源逐字记录）

> 来源：docs/cr/cr-20260823-1421.md D2（走查 DESIGN 条目；用户裁决 2026-08-23 选定"修"，走 Bug 流程建条目）。
>
> "ConnectionDao.delete（connection_dao.dart:139-144）的 CON-T34 自动激活发生在删除事务之外（事务提交后另行 findAll + setActive）。进程在这两步间被杀 → 全库零活跃连接。后果可自愈但概率非零，不值得留给用户踩。"
> 原走查处置建议："维持现状可接受；若追求完备，把 auto-activate 移入 delete 事务内。"

### 1.1 一句话

删除"当前正在使用的连接"时，切换到另一个连接的动作必须和删除动作绑成一件事——不能删完还没切就断电，留下一个"哪个都没选"的状态。

### 1.2 用户期望的场景

| ID | 你看到的样子 | 期望行为 |
|----|----|----|
| U1 | 删除当前使用的连接（还有其它连接） | 重进 App 后一定有且仅有一个连接处于使用中 |
| U2 | 删除非活跃连接 | 活跃连接不变（既有语义） |

---

## §2 已实现骨架（逆抽锚点）

| 层 | 文件 | 角色 |
|---|---|---|
| DAO | lib/core/database/dao/connection_dao.dart:110-147 | delete()：:114-117 CON-T32 守卫；:123-136 删除事务（progress + 行）；**:139-144 事务外 findAll + setActive**（缺陷点）；deleteWithoutGuard :157-177 同构同缺陷 |
| DAO | lib/core/database/dao/connection_dao.dart:88-99 | setActive 自带独立事务——嵌套进删除事务不可行，需事务内联 txn.update |
| 门禁测试 | test/features/connection/bug_bug28_txn_activate_test.dart | 结构断言（BUG-18-INV1 先例）+ 行为回归锚定，修复前 FAIL |

---

## §3 行为规约

### 3.1 现状锚定（逆抽）

- **[BUG-28-S0]** 终态语义（保留）：wasActive 返回值、CON-T34"删除后恰有一个活跃"、激活对象 = created_at ASC 首个剩余连接
  Code evidence: `lib/core/database/dao/connection_dao.dart:139-146` + `test/features/connection/con_04_test.dart`（既有锚定）

### 3.2 修复目标

- **[BUG-28-S1]** 删行与自动激活原子化（`status: new`）
  ```
  Given 连接数 ≥ 2 且待删连接为活跃
  When delete(id) 执行
  Then 在同一个 db.transaction 闭包内完成：清零全部 is_active、删 play_progress、删连接行、点亮首个剩余连接（txn.update where created_at ASC 首行 / id 最小者按既有 findAll 排序语义）
       且事务外不再有 findAll()/setActive() 收尾
  否定断言:
    - 不改变 CON-T32 守卫位置与语义（先 count 后删）
    - 不改变 wasActive 返回值语义（S0 回归）
    - 不引入 setActive() 嵌套调用（其内部自开事务，sqflite 事务内再调 db.transaction 会脱离外层事务语义）
  ```
  Code evidence: 修改点 `lib/core/database/dao/connection_dao.dart:123-146`
- **[BUG-28-S2]** deleteWithoutGuard 同步修复（同构缺陷一并消除）：补偿回滚路径同样不得留下零活跃窗口
  否定断言: 不改变 BUG-17 赋予它的"无 CON-T32 守卫"语义
  Code evidence: 修改点 `lib/core/database/dao/connection_dao.dart:161-176`

边界裁决表：

| 场景 | 裁决 |
|---|---|
| 待删为活跃且剩余 ≥1 | 事务内点亮 created_at ASC 首个剩余（与现 findAll().first 排序一致：findAll 按 created_at ASC） |
| 待删非活跃 | 事务内不做任何 is_active 写（现状：仅 wasActive=false 分支跳过） |
| 仅剩一个（守卫拦截） | 抛 LastConnectionException，零写库（现状不变） |
| 剩余查询结果为空 | 防御分支保留（理论不可达：count≥2 已保证） |

---

## §4 不变量

- **[BUG-28-INV1]** 任意成功返回的 delete/deleteWithoutGuard 之后，数据库状态必然满足「恰有一个活跃连接」或「零连接」，不存在中间态持久化
  证据：connection_dao.dart:123-146（修改点）+ database_helper.dart:33-35（FK/PRAGMA 事务边界）

---

## §5 测试规约

### 5.1 现有测试清单

| 测试文件 | 覆盖 | 备注 |
|---|---|---|
| test/features/connection/con_04_test.dart 等 | delete/setActive 既有语义 | 全绿即可（S0 回归） |

### 5.2 测试 ID 派生清单

```
BUG-28-S1, BUG-28-S2, BUG-28-INV1（S2 与 S1 共用结构门禁覆盖两个方法体）
```

### 5.3 测试覆盖盲点

进程级崩溃注入（kill between statements）单测不可行——以源码结构断言为代理门禁（BUG-18-INV1 先例），终态行为由行为回归锚定。

### 5.4 门禁测试文件（spec-scan --gate 硬校验）

| 测试文件 | 覆盖 ID | 说明 |
|---|---|---|
| test/features/connection/bug_bug28_txn_activate_test.dart | BUG-28-S1/S2 | 修复前 FAIL 已由 repro-test.sh fail 确认（2026-08-23）；修复后必须 PASS |

---

## §6 算法样例

不涉及纯函数算法，跳过。

---

## §7 跨模块影响

impact 反查（2026-08-23）：connection_dao ← connection_provider（ConnectionService.delete / _rollbackSave 经 deleteWithoutGuard）、connection_service。

| 其它模块 | 影响点 | 影响条件 | 回归断言要求 |
|---|---|---|---|
| connection service | delete 后 invalidate active/list | 终态语义不变 | con_04/con_06 全绿 |
| connection service | save 回滚路径 deleteWithoutGuard | 回滚终态不变（无活跃残留或保持原活跃） | bug_bug17_repro_test 全绿 |

**修改点（弱模型照单执行）**：
1. `lib/core/database/dao/connection_dao.dart` delete()（现 :123-146）：把 wasActive 判定提前到事务前（已有），事务闭包内追加：
   ```dart
   if (wasActive) {
     final remaining = await txn.query('connections',
         orderBy: 'created_at ASC', limit: 1);
     if (remaining.isNotEmpty) {
       await txn.update(
         'connections',
         {'is_active': 1, 'updated_at': _clock().millisecondsSinceEpoch},
         where: 'id = ?',
         whereArgs: [remaining.first['id']],
       );
     }
   }
   ```
   并删除原 :139-144 的事务外 findAll/setActive 块。
2. deleteWithoutGuard（:161-176）同构改造（注意其 txn 内已删行，remaining 查询自然排除待删行）。
3. 全量回归：cov-gate --skip-test + flutter test 全绿（重点 con_04 / bug_bug17_repro / int_g01_connection_switch_test）。

---

## §8 平台特性与手动 QA

核对踩坑库：P16 无交集（时间仅 updated_at 打点，毫秒精度既有）。sqflite 事务语义依据：sqflite 2.4.x `db.transaction((txn) {...})` 闭包内必须用 txn 句柄、嵌套 db.transaction 会开启独立事务脱离外层——故本修复用 txn.query/txn.update 内联而非复用 setActive()。manual_qa_required=false（纯 SQLite 层，ffi 可全验）。

---

## §9 dev-status.json 条目对照

```json
"BUG-28": {
  "spec_file": "docs/features/BUG-28.md",
  "spec_anchored_files": ["lib/core/database/dao/connection_dao.dart"],
  "scenarios": ["BUG-28-S1", "BUG-28-S2"],
  "invariants": ["BUG-28-INV1"],
  "algorithms": [],
  "manual_qa_required": false,
  "user_acceptance_text": "见 §1.2"
}
```
