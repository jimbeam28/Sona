# TEST-09 — TG-DB1：数据库集成测试缺口

> 来源：`docs/cr/cr-20260724-0110.md` TG-DB1 (line 676-679)
> dev-plan 流程：TEST-GAP 补测模式

---

## §0 头部元数据

```yaml
id: TEST-09
name: 数据库集成测试缺口（TG-DB1）
priority: P1
status: draft
created_at: 2026-07-27
last_updated: 2026-07-27
spec_anchored_files:
  - lib/core/database/dao/progress_dao.dart
  - test/features/progress/prg_test.dart
  - test/helpers/test_database.dart
cross_module_impacts: [PRG, BRW, PLY]
parent_feature: PRG
manual_qa_required: false
```

---

## §1 用户视角

### 1.0 原始需求

> cr-20260724-0110.md TG-DB1：缺少 "multi-file progress write → startup restore → other files' progress survives" 的桥接集成测试。当前 `prg_test.dart:284`（per-file independent）和 `:511`（findLatest pruning）各自验证单点行为，但没有将 upsert 多文件 → 读 latestPlayedProgressProvider → 验证所有文件进度未丢失串成端到端流。`bug_bug03_cross_module` 用真实 DAO 但未走 startup restore 路径。同时，`test_database.dart` 与生产 schema 单源化（BUG-16）可消除 DB2 假绿问题。

### 1.1 这一功能干什么（一句话）

补充数据库集成测试：验证多文件进度写入后 startup restore 路径不会丢失其它文件的进度记录。

### 1.2 用户期望的场景

| ID | 你看到的样子 | 期望行为 |
|----|----|----|
| U1 | 播放 A、B 两首曲目（各有进度）→ 关闭 App → 重新打开 | startup restore 能找到最近播放的进度，且 A 和 B 的进度记录均存在 |
| U2 | 多文件写入后调 findLatest | findLatest 返回最近一条，不删减其它文件的记录 |

---

## §2 已实现的功能骨架

### 2.1 文件与分层

| 层 | 文件 | 行数 | 角色 |
|---|---|---|---|
| DAO | `lib/core/database/dao/progress_dao.dart` | 179 | upsert / find / findLatest / count / rawInsert |
| Provider | `lib/features/progress/progress_provider.dart` | ~140 | latestPlayedProgressProvider 调 findLatest |
| Test (现有) | `test/features/progress/prg_test.dart` | 1781 | :284 per-file independent, :511 findLatest 纯查询 |
| Test (现有) | `test/features/progress/bug_bug03_cross_module_test.dart` | - | 用真实 DAO 但未走 startup restore 路径 |
| Test Helper | `test/helpers/test_database.dart` | 120 | 测试 DB 初始化 |

### 2.2 关键代码段

| 区域 | 行号 | 说明 |
|---|---|---|
| ProgressDao.upsert | `progress_dao.dart:40-71` | UPSERT 语义（ConflictAlgorithm.replace） |
| ProgressDao.findLatest | `progress_dao.dart:118-122` | 纯查询：getRecentlyPlayed(limit: 1) |
| ProgressDao.count | `progress_dao.dart:161-166` | 全表行数 |
| latestPlayedProgressProvider | `progress_provider.dart:59` | startup restore 入口 |
| per-file independent 测试 | `prg_test.dart:284` | `count == 2` 断言 |
| findLatest 纯查询测试 | `prg_test.dart:516-539` | 验证不删其它记录 |

---

## §3 行为规约

### 3.1 桥接集成测试

- **[TEST-09-S1]** 多文件 upsert → findLatest → 所有记录存活 (`status: new`)
  ```
  Given 测试数据库已初始化（TestSchema.progress），有 connection id=1
  When  upsert 文件 A（positionMs=15000, durationMs=180000）
        再 upsert 文件 B（positionMs=30000, durationMs=300000, lastPlayedAt 晚于 A）
        然后调 findLatest() 模拟 startup restore
  Then  findLatest 返回 B（最近播放）
  And   find(1, A_path) 非 null 且 positionMs == 15000
  And   find(1, B_path) 非 null 且 positionMs == 30000
  And   count() == 2（未被剪枝）
  否定断言:
    - findLatest 不删除 A 的进度记录（当前 prg_test.dart:516 已断言但无端到端桥接）
    - upsert B 不覆盖 A 的记录（UPSERT 按 (connection_id, file_path) UNIQUE）
    - count 不减少（不被 findLatest 或其他查询副作用删除）
  ```
  Code evidence:
  - `progress_dao.dart:40-71`（upsert UPSERT 语义）
  - `progress_dao.dart:118-122`（findLatest 纯查询）
  - `prg_test.dart:284`（per-file count 断言，无桥接）
  - `prg_test.dart:516-539`（findLatest 纯查询，无 startup restore 路径）

  **测试文件位置：`test/features/progress/test_09_integration_test.dart`**

### 3.2 桥接 latestPlayedProgressProvider 路径

- **[TEST-09-S2]** latestPlayedProgressProvider 端到端：多文件写入 → Provider 返回最新 → 其它文件存活 (`status: new`)
  ```
  Given 测试数据库已初始化（TestSchema.progress），有 connection id=1
        progressDaoProvider 注入真实 ProgressDao
  When  通过 DAO rawInsert 写入文件 A（lastPlayedAt 较早）
        通过 DAO rawInsert 写入文件 B（lastPlayedAt 较晚）
        通过 ProviderContainer 读取 latestPlayedProgressProvider.future
  Then  Provider 返回 B 的进度
  And   find(1, A_path) 非 null
  And   find(1, B_path) 非 null
  And   count() == 2
  否定断言:
    - latestPlayedProgressProvider 的读取不产生删除副作用（BUG-11 裁决：纯查询）
    - 不因 Provider 读取导致 A 的记录消失
  ```
  Code evidence:
  - `progress_provider.dart:59`（latestPlayedProgressProvider 定义）
  - `progress_dao.dart:118-122`（findLatest 底层实现）
  - `bug_bug03_cross_module_test.dart`（用真实 DAO 但未走 Provider 路径）

  **测试文件位置：`test/features/progress/test_09_integration_test.dart`**

### 3.3 test_database ↔ 生产 schema 一致性验证

- **[TEST-09-S3]** 测试 helper schema 与生产 schema 列定义一致 (`status: new`)
  ```
  Given 通过 openTestDatabase(TestSchema.full) 打开测试数据库
  When  查询 sqlite_master 获取所有表名和列信息
  Then  测试 DB 包含 connections / play_progress / playlists / playlist_tracks 四张表
  And   play_progress 表包含 id/connection_id/file_path/position_ms/duration_ms/last_played_at 列
  And   play_progress 有 UNIQUE(connection_id, file_path) 约束
  And   play_progress 有 idx_progress_lookup 索引
  否定断言:
    - 测试 schema 不遗漏生产 schema 的任何列或约束
    - 不在测试 helper 中硬编码 FK=ON 来掩盖生产 schema 差异（BUG-16 修复后应通过 onConfigure 统一）
  ```
  Code evidence:
  - `test_database.dart:42-53`（测试 play_progress schema）
  - `test_database.dart:104-115`（手动 FK PRAGMA 假绿）
  - `lib/core/database/database_helper.dart`（生产 schema）

  **测试文件位置：`test/features/progress/test_09_integration_test.dart`**

---

## §4 不变量

- **[TEST-09-INV1]** findLatest 是纯查询，无删除副作用
  证据：`progress_dao.dart:118-122`（只调 getRecentlyPlayed(limit: 1)）

- **[TEST-09-INV2]** UPSERT 按 (connection_id, file_path) 唯一，不同文件互不覆盖
  证据：`test_database.dart:50-51`（UNIQUE 约束），`progress_dao.dart:67`（ConflictAlgorithm.replace）

---

## §5 测试规约

### 5.1 现有测试清单

| 测试文件 | 覆盖的 Scenario / INV | 备注 |
|---|---|---|
| `prg_test.dart:275-284` | per-file independent | 两文件各自有记录，count == 2 |
| `prg_test.dart:516-539` | findLatest 纯查询 | 验证不删其它记录 |
| `bug_bug03_cross_module_test.dart` | 真实 DAO 跨模块 | 未走 latestPlayedProgressProvider 路径 |

### 5.2 测试 ID 派生清单

```
TEST-09-S1 S2 S3       # 桥接集成 + Provider 端到端 + schema 一致性
TEST-09-INV1 INV2      # findLatest 纯查询 + UPSERT 唯一
```

### 5.3 测试覆盖盲点

| 未覆盖 ID | 现状 | 应补偿方式 |
|---|---|---|
| TEST-09-S1 | prg_test.dart:284 和 :511 分别断言但不桥接 | upsert A+B → findLatest → find(A) + find(B) + count == 2 |
| TEST-09-S2 | bug_bug03_cross_module 用真实 DAO 但无 Provider 路径 | ProviderContainer + latestPlayedProgressProvider → 验证全链路 |
| TEST-09-S3 | test_database 与生产 schema 无一致性断言 | 查 sqlite_master 验证表/列/约束一致 |

### 5.4 测试文件位置

| 测试 ID | 文件路径 |
|---|---|
| TEST-09-S1 | `test/features/progress/test_09_integration_test.dart` |
| TEST-09-S2 | `test/features/progress/test_09_integration_test.dart` |
| TEST-09-S3 | `test/features/progress/test_09_integration_test.dart` |

---

## §6 算法样例

不适用——本 spec 为补测，无新算法。

---

## §7 跨模块影响

| 其它 feature | 影响点 | 需要补的回归断言 |
|---|---|---|
| BRW | startup restore 路径涉及 browser_provider | 多文件进度不丢失 |
| PLY | 播放器启动时读 latestPlayedProgressProvider | Provider 端到端返回正确记录 |

---

## §8 平台特性与手动 QA

本功能不涉及平台原生特性，全部可在 `flutter test` 中验证。

---

## §9 dev-status.json 条目对照

```json
"TEST-09": {
  "spec_file": "docs/features/TEST-09.md",
  "spec_anchored_files": [
    "lib/core/database/dao/progress_dao.dart",
    "test/features/progress/prg_test.dart",
    "test/helpers/test_database.dart"
  ],
  "scenarios": ["TEST-09-S1", "TEST-09-S2", "TEST-09-S3"],
  "invariants": ["TEST-09-INV1", "TEST-09-INV2"],
  "algorithms": [],
  "test_files": ["test/features/progress/test_09_integration_test.dart"],
  "test_coverage_gaps": [],
  "cross_module_impacts": ["PRG", "BRW", "PLY"],
  "manual_qa_required": false,
  "manual_qa_file": null,
  "user_acceptance_text": "见 §1.2",
  "impl_status": "pending",
  "test_status": "pending",
  "check_status": "pending",
  "check_round": 0,
  "last_check_round_results": "",
  "last_checked_at": "",
  "dependencies": ["BUG-16"],
  "retry_count": 0,
  "last_error": "",
  "last_updated": "2026-07-27"
}
```

---

## §10 changelog

- 2026-07-27: 创建 TEST-09 spec（基于 cr-20260724-0110.md TG-DB1）
