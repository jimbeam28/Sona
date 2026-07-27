# BUG-30 — NasFile ==/hashCode 漏 modifiedAt（MDL3）

> 来源：`docs/cr/cr-20260724-0110.md` MDL3 (line 891-895)
> dev-plan 流程：Bug 修复模式

---

## §0 头部元数据

```yaml
id: BUG-30
name: NasFile ==/hashCode 漏 modifiedAt（MDL3）
priority: P2
status: draft
created_at: 2026-07-27
last_updated: 2026-07-27
spec_anchored_files:
  - lib/shared/models/nas_file.dart
cross_module_impacts: [BRW]
parent_feature: Browser
manual_qa_required: false
```

---

## §1 用户视角

### 1.0 原始需求

> cr-20260724-0110.md MDL3：`nas_file.dart:203-213` — ==/hashCode 覆盖 5/6 字段（除 `modifiedAt` 外的所有字段）。`copyWith`（`:176-195`）包含 `modifiedAt`。`directory_service.dart:206-207` 按 `modifiedAt` 排序。当前无直接危害（`DirectoryResult` 不实现 ==，provider 总是创建新实例）。但若未来引入增量 diff 缓存（`listEquals` 跳过相同元素），仅修改时间变化的文件 → `NasFile ==` 返回 true → UI 静默不更新（BUG-01 家族）。

### 1.1 这一功能干什么（一句话）

修复 `NasFile` 的 `==`/`hashCode` 遗漏 `modifiedAt` 字段，与 `copyWith`/`fromMap` 四地同步模式对齐。

### 1.2 用户期望的场景

| ID | 你看到的样子 | 期望行为 |
|----|----|----|
| U1 | 远程文件仅修改时间变化（内容不变） | NasFile == 返回 false，UI 正确刷新 |
| U2 | 两个 NasFile 所有字段（含 modifiedAt）相同 | NasFile == 返回 true（不变） |
| U3 | sortFiles 按 modifiedDesc 排序 | 行为不变（排序不依赖 ==） |

---

## §2 已实现的功能骨架

### 2.1 文件与分层

| 层 | 文件 | 行数 | 角色 |
|---|---|---|---|
| Shared Model | `lib/shared/models/nas_file.dart` | 214 | NasFile 数据模型 |
| Domain | `lib/features/browser/domain/directory_service.dart` | 213 | 排序逻辑（按 modifiedAt） |

### 2.2 关键代码段

| 区域 | 行号 | 说明 |
|---|---|---|
| NasFile.== | `nas_file.dart:203-210` | 覆盖 name, path, isDirectory, size, audioType（5 字段，缺 modifiedAt） |
| NasFile.hashCode | `nas_file.dart:213` | `Object.hash(name, path, isDirectory, size, audioType)`（同 5 字段） |
| NasFile.copyWith | `nas_file.dart:176-195` | 包含 modifiedAt（:192） |
| NasFile 字段声明 | `nas_file.dart:8-14` | 6 字段：name, path, isDirectory, size, modifiedAt, audioType |
| sortFiles modifiedDesc | `directory_service.dart:206-207` | 按 `modifiedAt?.millisecondsSinceEpoch` 排序 |

---

## §3 行为规约

### 3.1 修复后行为

- **[BUG-30-S1]** `NasFile.==` 包含 `modifiedAt` (`status: new`)
  ```
  Given NasFile a(name:'x', path:'/x', isDirectory:false, size:100, modifiedAt:T1, audioType:music)
    and NasFile b(name:'x', path:'/x', isDirectory:false, size:100, modifiedAt:T2, audioType:music)
    where T1 != T2
  When  a == b
  Then  返回 false
  否定断言:
    - 不在 modifiedAt 不同时返回 true（当前 BUG：== 忽略 modifiedAt → 返回 true）
    - 不改变其他 5 字段的比较逻辑（向后兼容）
    - 不破坏 hashCode 与 == 的一致性（a==b → a.hashCode==b.hashCode）
  ```
  Code evidence: `lib/shared/models/nas_file.dart:203-210`（== 缺 modifiedAt）

  **修改指令 — `lib/shared/models/nas_file.dart`（== 操作符）**

  位置：`:203-210`

  当前代码（:203-210）：
  ```dart
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NasFile &&
          name == other.name &&
          path == other.path &&
          isDirectory == other.isDirectory &&
          size == other.size &&
          audioType == other.audioType;
  ```

  改为：
  ```dart
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NasFile &&
          name == other.name &&
          path == other.path &&
          isDirectory == other.isDirectory &&
          size == other.size &&
          modifiedAt == other.modifiedAt &&
          audioType == other.audioType;
  ```

  边界裁决：
  - 两者 `modifiedAt` 均为 null → `null == null` → true（符合语义：均无修改时间时视为相同）
  - 一方 null 一方非 null → false（不同）
  - 两者 `modifiedAt` 相同 DateTime → true
  - `modifiedAt` 为 DateTime，其 `==` 比较 tick 精度（纳秒级），足够区分 PROPFIND 返回的时间戳

- **[BUG-30-S2]** `NasFile.hashCode` 包含 `modifiedAt` (`status: new`)
  ```
  Given NasFile a 和 NasFile b 仅 modifiedAt 不同
  When  比较 a.hashCode 和 b.hashCode
  Then  不要求相等（因 a != b）
  否定断言:
    - 不在 modifiedAt 不同时 hashCode 仍相同（当前 BUG：hashCode 忽略 modifiedAt）
    - 不破坏 hashCode/== 一致性（相等对象必须 hashCode 相等）
    - 不引入 null 安全问题（modifiedAt 可为 null）
  ```
  Code evidence: `lib/shared/models/nas_file.dart:213`（hashCode 缺 modifiedAt）

  **修改指令 — `lib/shared/models/nas_file.dart`（hashCode）**

  位置：`:213`

  当前代码（:213）：
  ```dart
  int get hashCode => Object.hash(name, path, isDirectory, size, audioType);
  ```

  改为：
  ```dart
  int get hashCode => Object.hash(name, path, isDirectory, size, modifiedAt, audioType);
  ```

  边界裁决：
  - `Object.hash` 接受 nullable 参数，`modifiedAt` 为 null 时安全
  - 6 字段全部传入 `Object.hash`，与 == 字段集完全对齐
  - 与 `copyWith`（:176-195）的字段集对齐（四地同步：==/hashCode/copyWith/fromProps）

  **测试文件位置：`test/features/browser/bug_bug30_repro_test.dart`**

---

## §4 不变量

- **[BUG-30-INV1]** NasFile 的 ==/hashCode/copyWith/fromProps 字段集完全一致
  证据：修复后 == 和 hashCode 均含 modifiedAt，与 copyWith（:176-195）和 fromProps（:75-128）对齐

- **[BUG-30-INV2]** `a == b` 当且仅当所有 6 字段均相等
  证据：`nas_file.dart:203-210`（修复后）覆盖 name/path/isDirectory/size/modifiedAt/audioType

---

## §5 测试规约

### 5.1 现有测试清单

| 测试文件 | 覆盖 | 备注 |
|---|---|---|
| `test/features/browser/` | BRW-01~08 浏览器功能测试 | 现有测试不涉及 NasFile == 语义 |

### 5.2 测试 ID 派生清单

```
BUG-30-S1           # == 包含 modifiedAt
BUG-30-S2           # hashCode 包含 modifiedAt
BUG-30-INV1         # ==/hashCode/copyWith/fromProps 字段集一致
BUG-30-INV2         # 全 6 字段相等判定
```

### 5.3 测试覆盖盲点

| 未覆盖 ID | 现状 | 应补偿方式 |
|---|---|---|
| BUG-30-S1 | 无测试断言 NasFile == 对 modifiedAt 的敏感性 | 构造两个仅 modifiedAt 不同的 NasFile → 断言 `a != b` |
| BUG-30-S2 | 无测试断言 hashCode 对 modifiedAt 的敏感性 | 构造两个仅 modifiedAt 不同的 NasFile → 断言 `a.hashCode != b.hashCode`（不强制，但不应总相同） |
| BUG-30-INV1 | 无测试验证四地同步 | 构造 NasFile → copyWith(modifiedAt: 新值) → 断言 != 原对象 |

### 5.4 测试文件位置

| 测试 ID | 文件路径 |
|---|---|
| BUG-30-S1 | `test/features/browser/bug_bug30_repro_test.dart` |
| BUG-30-S2 | `test/features/browser/bug_bug30_repro_test.dart` |
| BUG-30-INV1 | `test/features/browser/bug_bug30_repro_test.dart` |
| BUG-30-INV2 | `test/features/browser/bug_bug30_repro_test.dart` |

---

## §6 算法样例

不适用——本修复为字段对齐，无新算法。

---

## §7 跨模块影响

| 其它 feature | 影响点 | 需要补的回归断言 |
|---|---|---|
| BRW | `directory_service.dart:206-207` 按 modifiedAt 排序 | sortFiles 排序行为不变（排序不依赖 ==） |
| BRW | 现有 NasFile 构造（fromProps、测试 factories） | hashCode 变化不影响 Map/Set 中现有使用（NasFile 不作为 Map key 使用） |

---

## §8 平台特性与手动 QA

本功能不涉及平台原生特性，全部可在 `flutter test` 中验证。

---

## §9 dev-status.json 条目对照

见统一更新：`docs/dev/dev-status.json`。

---

## §10 changelog

- 2026-07-27: 创建 BUG-30 spec（基于 cr-20260724-0110.md MDL3）
