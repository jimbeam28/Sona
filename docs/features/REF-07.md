# REF-07 — ConnectionConfig ==/hashCode 补全（MDL5）

> 来源：`docs/cr/cr-20260724-0110.md` MDL5
> dev-plan 流程：Refactoring 模式

---

## §0 头部元数据

```yaml
id: REF-07
name: ConnectionConfig ==/hashCode 补全（MDL5）
priority: P1
status: draft
created_at: 2026-07-27
last_updated: 2026-07-27
spec_anchored_files:
  - lib/shared/models/connection_config.dart
cross_module_impacts: [CON]
parent_feature: Connection
manual_qa_required: false
```

---

## §1 用户视角

### 1.0 原始需求

> cr-20260724-0110.md MDL5：`connection_config.dart:90-94` — only has toString, no ==/hashCode override. Only model among 5 that lacks value equality. Currently safe (FutureProvider always notifies = over-notification). Risk: future == addition without all fields → BUG-01 family.

### 1.1 这一功能干什么（一句话）

为 ConnectionConfig 补全值相等性（== / hashCode），使其与其他 4 个 model 一致。

### 1.2 用户期望的场景

| ID | 你看到的样子 | 期望行为 |
|----|----|----|
| U1 | 两个相同字段的 ConnectionConfig 实例比较 | 返回 true（值相等） |
| U2 | 任一字段不同的两个 ConnectionConfig 实例比较 | 返回 false |

---

## §2 已实现的功能骨架

### 2.1 文件与分层

| 层 | 文件 | 行数 | 角色 |
|---|---|---|---|
| Model | `lib/shared/models/connection_config.dart` | 94 | ConnectionConfig 数据模型 |

### 2.2 关键代码段

| 区域 | 行号 | 说明 |
|---|---|---|
| 字段定义 | `connection_config.dart:6-13` | id / name / url / username / basePath / isActive / createdAt / updatedAt（8 个字段） |
| toString | `connection_config.dart:90-93` | 唯一 override，缺 == / hashCode |
| 参考实现 | `nas_file.dart:202-213` | `identical(this, other) ||` + `Object.hash(...)` 模式 |

---

## §3 行为规约

### 3.1 补全 == / hashCode

- **[REF-07-S1]** 添加 ConnectionConfig == override (`status: new`)
  ```
  Given 两个 ConnectionConfig 实例所有字段相同
  When  用 == 比较
  Then  返回 true
  否定断言:
    - 不忽略 id 字段（id 不同 → 不等，即使其余字段相同）
    - 不忽略 createdAt / updatedAt 字段（时间不同 → 不等）
    - 不忽略 isActive 字段（活跃状态不同 → 不等）
    - 不忽略 basePath 字段（路径不同 → 不等）
    - 不改变 toString 的现有行为
  ```
  Code evidence: `lib/shared/models/connection_config.dart:6-13`（8 字段）；`:90-93`（仅有 toString）

  **修改指令 — `lib/shared/models/connection_config.dart`**

  位置：`:90-94`

  当前代码：
  ```dart
    @override
    String toString() =>
        'ConnectionConfig(id: $id, name: $name, url: $url, username: $username, '
        'basePath: $basePath, isActive: $isActive)';
  }
  ```
  改为：
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
    int get hashCode =>
        Object.hash(id, name, url, username, basePath, isActive, createdAt, updatedAt);

    @override
    String toString() =>
        'ConnectionConfig(id: $id, name: $name, url: $url, username: $username, '
        'basePath: $basePath, isActive: $isActive)';
  }
  ```

- **[REF-07-S2]** 负向测试 — 每个字段不同均导致不等 (`status: new`)
  ```
  Given 基准 ConnectionConfig 实例 A
  When  创建实例 B 仅某一个字段与 A 不同
  Then  A != B
  否定断言:
    - 不因 hashCode 碰撞而误判相等（hashCode 覆盖所有 8 字段）
    - 不因 id 为 null 而跳过比较（null == null → true，null != 非null → false）
  ```
  Code evidence: `lib/shared/models/connection_config.dart:6-13`（8 字段）

---

## §4 不变量

- **[REF-07-INV1]** ConnectionConfig 实现值相等性覆盖所有字段
  证据：`connection_config.dart:90-101`（== 覆盖 id/name/url/username/basePath/isActive/createdAt/updatedAt）

- **[REF-07-INV2]** hashCode 与 == 一致（相等对象 hashCode 相同）
  证据：`connection_config.dart:103-104`（Object.hash 参数与 == 字段相同）

---

## §5 测试规约

### 5.1 现有测试清单

| 测试文件 | 覆盖 | 备注 |
|---|---|---|
| `test/features/connection/` | Connection 功能测试 | 需检查是否有 == 相关测试 |

### 5.2 测试 ID 派生清单

```
REF-07-S1           # 正向：所有字段相同 → 相等
REF-07-S2           # 负向：每个字段不同 → 不等（8 条子用例）
REF-07-INV1         # == 覆盖所有字段
REF-07-INV2         # hashCode 一致性
```

### 5.3 测试覆盖盲点

| 未覆盖 ID | 现状 | 应补偿方式 |
|---|---|---|
| REF-07-S1 | 无测试验证 ConnectionConfig 值相等 | 构造两个相同字段的实例 → expect(a == b, true) + expect(a.hashCode, b.hashCode) |
| REF-07-S2 | 无测试验证各字段不同导致不等 | 对每个字段分别构造差异实例 → expect(a != b, true)（8 条） |

---

## §6 算法样例

不适用——值相等性为简单字段逐一比较。

---

## §7 跨模块影响

| 其它 feature | 影响点 | 需要补的回归断言 |
|---|---|---|
| CON | connection_provider / connection_service | 现有逻辑不依赖 ==（安全），未来添加去重/比较时自动生效 |

---

## §8 平台特性与手动 QA

本功能不涉及平台原生特性，全部可在 `flutter test` 中验证。

---

## §9 dev-status.json 条目对照

见统一更新：`docs/dev/dev-status.json`。

---

## §10 changelog

- 2026-07-27: 创建 REF-07 spec（基于 cr-20260724-0110.md MDL5）
