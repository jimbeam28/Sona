# BUG-20 — 10-15s 短文件 shouldClear 阈值过激

> 来源：`docs/cr/cr-2026-06-28.md` FRAGILE-06 AND `docs/cr/cr-20260724-0110.md` PRG6（同一根因）
> dev-plan 流程：Bug 修复模式

---

## §0 头部元数据

```yaml
id: BUG-20
name: 10-15s 短文件 shouldClear 阈值过激
priority: P1
status: draft
created_at: 2026-07-27
last_updated: 2026-07-27
spec_anchored_files:
  - lib/features/progress/domain/progress_policy.dart
cross_module_impacts: [PRG]
parent_feature: null
manual_qa_required: false
```

---

## §1 用户视角

### 1.0 原始需求

> cr-2026-06-28 FRAGILE-06 与 cr-20260724-0110 PRG6（同根因）：`shouldClear` 对 10-15s 短文件阈值过激，`shouldSave` 与 `shouldClear` 冲突导致 10-15s 文件永远无法保存进度。

### 1.1 这一功能干什么（一句话）

修复 10-15s 短文件播放超过 5s 后退出、再次进入无续播对话框的缺陷——原因是保存阈值与清除阈值冲突。

### 1.2 用户期望的场景

| ID | 你看到的样子 | 期望行为 |
|----|----|----|
| U1 | 10-15s 有声书片段 → 播放 >5s 后退出 | 再次进入弹出续播对话框，从上次位置继续 |
| U2 | 12s 文件播放到 6s 处暂停退出 | 进度被保存（不被清除），下次打开从 6s 续播 |

---

## §2 已实现的功能骨架

### 2.1 文件与分层

| 层 | 文件 | 行数 | 角色 |
|---|---|---|---|
| Domain | `lib/features/progress/domain/progress_policy.dart` | 28 | 纯函数：shouldSave / shouldClear 决策 |
| Data | `lib/core/database/dao/progress_dao.dart` | ~180 | 调用 policy 函数执行 UPSERT / 清除 |
| Domain | `lib/features/progress/domain/progress_service.dart` | 143 | 编排 save trigger → DAO |
| 测试 | `test/features/progress/ref_24_test.dart` | 117 | 16 tests for progress_policy |

---

## §3 行为规约

### 3.1 修复后行为

- **[BUG-20-S1]** shouldClear 阈值与 shouldSave 不冲突 (`status: new`)
  ```
  Given durationMs=12000, positionMs=6000
  When  调用 shouldSave(6000) 和 shouldClear(6000, 12000)
  Then  shouldSave=true AND shouldClear=false
  否定断言:
    - 不应出现 shouldSave=true 且 shouldClear=true 的情况（除非 durationMs > 15000 且 positionMs 确实接近结尾）
    - 不改变 >30s 长文件的行为（向后兼容：durationMs=600000 时 clear window 仍为 10000ms）
    - 不改变 <=10s 文件的保护（G-3 不变：durationMs <= 10000 时 shouldClear 始终返回 false）
  ```
  Code evidence: `lib/features/progress/domain/progress_policy.dart:22-28`

  **当前 BUG 行为**：
  - `durationMs=12000` → `shouldClear` threshold = `12000 - 10000 = 2000`
  - `shouldSave` 触发于 `positionMs >= 5000`
  - 因此 `positionMs=5000` → shouldSave=true, shouldClear(5000 > 2000)=true → 保存后立即被清除

  #### 修改指令

  **修改点：将固定 10000ms 清除窗口改为动态窗口**

  文件：`lib/features/progress/domain/progress_policy.dart:27`

  当前代码：
  ```dart
  return positionMs > durationMs - 10000;
  ```

  改为：
  ```dart
  return positionMs > durationMs - (durationMs * 0.1).ceil().clamp(1000, 10000);
  ```

  变更说明：
  - 清除窗口 = `max(1000, min(10000, durationMs * 10%))`
  - 短文件窗口缩小（避免与 shouldSave@5000 冲突），长文件窗口保持 10000ms（向后兼容）
  - G-3 保护行（`:26`）不变：`durationMs <= 10000` 仍直接返回 false

  **边界裁决：**
  - `durationMs=10001` → window=`max(1000, min(10000, 1001))` = 1001 → clear at positionMs > 9000（不冲突）
  - `durationMs=12000` → window=`max(1000, min(10000, 1200))` = 1200 → clear at positionMs > 10800（与 shouldSave@5000 无冲突）
  - `durationMs=15000` → window=`max(1000, min(10000, 1500))` = 1500 → clear at positionMs > 13500（无冲突）
  - `durationMs=50000` → window=`max(1000, min(10000, 5000))` = 5000 → clear at positionMs > 45000（合理）
  - `durationMs=60000` → window=`max(1000, min(10000, 6000))` = 6000 → clear at positionMs > 54000（合理）
  - `durationMs=600000` → window=`max(1000, min(10000, 60000))` = 10000 → clear at positionMs > 590000（与修改前完全一致，向后兼容）
  - `durationMs=10000` → G-3 保护触发（`:26`）→ 直接返回 false（行为不变）
  - `durationMs=5000` → G-3 保护触发 → 直接返回 false（行为不变）

  **测试文件位置：** `test/features/progress/bug_bug20_repro_test.dart`

---

## §4 不变量

- **[BUG-20-INV1]** shouldSave=true 且 shouldClear=true 不共存（除非 durationMs > 15000 且 positionMs 接近结尾）
  证据：`progress_policy.dart:11`（shouldSave）+ `progress_policy.dart:22-28`（shouldClear）

- **[BUG-20-INV2]** <=10s 文件行为不变（G-3 保护）
  证据：`progress_policy.dart:26`（`if (durationMs <= 10000) return false;`）

---

## §5 测试规约

### 5.1 现有测试清单

| 测试文件 | 覆盖的 Scenario / INV | 备注 |
|---|---|---|
| `test/features/progress/ref_24_test.dart` | REF-24-T01~T16（16 tests） | shouldSave/shouldClear 边界 + 基本行为 |

### 5.2 测试 ID 派生清单

```
BUG-20-S1           # shouldClear 阈值与 shouldSave 不冲突
BUG-20-INV1         # shouldSave=true 且 shouldClear=true 不共存（10-15s 范围）
BUG-20-INV2         # <=10s 文件行为不变
```

### 5.3 测试覆盖盲点

| 未覆盖 ID | 现状 | 应补偿方式 |
|---|---|---|
| BUG-20-S1 | ref_24_test.dart 只覆盖固定 10000ms 窗口，无 10-15s 范围边界测试 | 补 10001/12000/15000/50000/600000 各一条边界用例 |
| BUG-20-INV1 | 无测试断言 shouldSave 与 shouldClear 互斥性 | 补 durationMs=12000 positionMs=6000 场景 |
| BUG-20-INV2 | ref_24_test.dart 有 durationMs<=10000 用例但需确认修改后仍通过 | 回归验证 |

### 5.4 测试文件位置

| 测试 ID | 文件路径 |
|---|---|
| BUG-20-S1 | `test/features/progress/bug_bug20_repro_test.dart` |
| BUG-20-INV1 | `test/features/progress/bug_bug20_repro_test.dart` |
| BUG-20-INV2 | `test/features/progress/bug_bug20_repro_test.dart` |

---

## §6 算法样例

```
ALG [BUG-20-ALG1-shouldClear]:
  输入: positionMs=6000, durationMs=12000     → 期望: false（window=1200, 6000 > 10800? No）
  输入: positionMs=11000, durationMs=12000    → 期望: true （window=1200, 11000 > 10800? Yes）
  输入: positionMs=5000, durationMs=12000     → 期望: false（shouldSave=true, shouldClear=false → 保存成功）
  输入: positionMs=590000, durationMs=600000  → 期望: true （window=10000, 590000 > 590000? No, 590001 → Yes）
  输入: positionMs=9000, durationMs=10000     → 期望: false（G-3 保护，durationMs <= 10000）
  输入: positionMs=9000, durationMs=10001     → 期望: false（window=1001, 9000 > 9000? No）
  输入: positionMs=9001, durationMs=10001     → 期望: true （window=1001, 9001 > 9000? Yes）
```

---

## §7 跨模块影响

| 其它 feature | 影响点 | 影响条件 | 需要补的回归断言 |
|---|---|---|---|
| PRG | progress_service.saveProgress → progress_dao.upsertProgress → shouldClear | 10-15s 短文件播放 >5s | 进度被正确保存（不被清除），续播对话框正常弹出 |

---

## §8 平台特性与手动 QA

本功能不涉及平台原生特性，全部可在 `flutter test` 中验证。

---

## §9 dev-status.json 条目对照

```json
"BUG-20": {
  "spec_file": "docs/features/BUG-20.md",
  "spec_anchored_files": ["lib/features/progress/domain/progress_policy.dart"],
  "scenarios": ["BUG-20-S1"],
  "invariants": ["BUG-20-INV1", "BUG-20-INV2"],
  "algorithms": ["BUG-20-ALG1-shouldClear"],
  "test_files": ["test/features/progress/bug_bug20_repro_test.dart"],
  "test_coverage_gaps": ["BUG-20-S1", "BUG-20-INV1", "BUG-20-INV2"],
  "cross_module_impacts": ["PRG"],
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

- 2026-07-27: 创建 BUG-20 spec（基于 cr-2026-06-28 FRAGILE-06 + cr-20260724-0110 PRG6）
