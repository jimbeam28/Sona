# BUG-10 — 删除活跃连接后不复位导航栈

> 来源：`docs/cr/cr-20260724-0110.md` CON4
> dev-plan 流程：Bug 修复模式

---

## §0 头部元数据

```yaml
id: BUG-10
name: 删除活跃连接后不复位导航栈
priority: P1
status: draft
created_at: 2026-07-27
last_updated: 2026-07-27
spec_anchored_files:
  - lib/features/connection/connection_provider.dart
  - lib/features/connection/connection_list_screen.dart
cross_module_impacts: [BRW]
parent_feature: Connection
manual_qa_required: false
```

---

## §1 用户视角

### 1.0 原始需求

> cr-20260724-0110.md CON4：deleteConnectionProvider 仅 invalidate active/list，不清浏览器缓存/导航栈。删除活跃连接后自动激活下一个，但浏览器仍停留旧连接深层路径，对新连接发旧路径请求 404。

### 1.1 这一功能干什么（一句话）

修复删除活跃连接后浏览器不重置到根目录的缺陷。

### 1.2 用户期望的场景

| ID | 你看到的样子 | 期望行为 |
|----|----|----|
| U1 | 连接 A 浏览到 3 层深 → 删除 A → B 自动激活 | 返回浏览 Tab 显示 B 的根目录，导航栈复位 |

---

## §2 已实现的功能骨架

### 2.1 文件与分层

| 层 | 文件 | 行数 | 角色 |
|---|---|---|---|
| Provider | `lib/features/connection/connection_provider.dart` | ~350 | deleteConnectionProvider |
| UI | `lib/features/connection/connection_list_screen.dart` | ~180 | 删除流程 |

---

## §3 行为规约

### 3.1 修复后行为

- **[BUG-10-S1]** 删除活跃连接后重置浏览器状态 (`status: new`)
  ```
  Given 活跃连接 A 被删除，B 自动激活
  When  deleteConnectionProvider 完成
  Then  调用 resetBrowserStateOnActiveConnectionChange(ref)（与 CON3 编辑页同钩子）
        directoryCacheProvider + navigationStackProvider 被 invalidate
  否定断言:
    - 不遗留旧连接的目录缓存
    - 不遗留旧连接的导航栈（浏览器不停留深层路径）
    - 不影响非活跃连接删除时的浏览器状态
  ```
  Code evidence: `lib/features/connection/connection_provider.dart:331-346`（deleteConnectionProvider 无浏览器刷新）
  对照：`connection_provider.dart:316`（update 已调 resetBrowserStateOnActiveConnectionChange）
  对照：`connection_list_screen.dart:78-80`（切换路径显式清缓存+复位导航栈）

  #### 修改指令

  **修改点 1：ConnectionService.delete 返回 wasActive**

  文件：`lib/features/connection/domain/connection_service.dart:97-100`

  当前代码：
  ```dart
  Future<void> delete(int id) async {
    await _dao.delete(id);
    await safeStorageDelete(_storage, key: 'connection_password_$id');
  }
  ```

  改为：
  ```dart
  Future<bool> delete(int id) async {
    final wasActive = await _dao.delete(id);
    await safeStorageDelete(_storage, key: 'connection_password_$id');
    return wasActive;
  }
  ```

  变更说明：`ConnectionDao.delete` 已返回 `bool`（wasActive，CON-T34），当前被丢弃。改为向上传播，让 provider 层知道是否需要重置浏览器。返回类型从 `void` → `bool` 对现有调用方（忽略返回值）向后兼容。

  **修改点 2：deleteConnectionProvider 条件性重置浏览器**

  文件：`lib/features/connection/connection_provider.dart:331-346`

  当前代码：
  ```dart
  final deleteConnectionProvider =
      FutureProvider.family<void, int>((ref, id) async {
    final service = ref.watch(connectionServiceProvider);

    debugPrint('[Conn] delete: id=$id');
    try {
      await service.delete(id);
    } on LastConnectionException {
      debugPrint('[Conn] delete: blocked — last connection');
      throw const LastConnectionException('无法删除最后一个连接');
    }
    debugPrint('[Conn] delete: done id=$id');

    ref.invalidate(activeConnectionProvider);
    ref.invalidate(connectionListProvider);
  });
  ```

  改为：
  ```dart
  final deleteConnectionProvider =
      FutureProvider.family<void, int>((ref, id) async {
    final service = ref.watch(connectionServiceProvider);

    debugPrint('[Conn] delete: id=$id');
    final bool wasActive;
    try {
      wasActive = await service.delete(id);
    } on LastConnectionException {
      debugPrint('[Conn] delete: blocked — last connection');
      throw const LastConnectionException('无法删除最后一个连接');
    }
    debugPrint('[Conn] delete: done id=$id');

    ref.invalidate(activeConnectionProvider);
    ref.invalidate(connectionListProvider);
    // BUG-10: if the deleted connection was active, the DAO auto-activated
    // another (CON-T34) — reset browser state so the new connection starts
    // at root instead of inheriting the old connection's deep path.
    if (wasActive) {
      resetBrowserStateOnActiveConnectionChange(ref);
    }
  });
  ```

  变更说明：
  - 捕获 `service.delete(id)` 的返回值 `wasActive`。
  - 仅当被删连接是活跃连接时才调 `resetBrowserStateOnActiveConnectionChange(ref)`（与 `:316` 编辑路径同钩子）。
  - 非活跃连接删除不触发浏览器重置（满足否定断言第 3 条）。

  **边界裁决：**
  - 删除活跃连接 → DAO auto-activate 另一个 → `wasActive = true` → 重置浏览器 → 新连接从根目录开始。
  - 删除非活跃连接 → `wasActive = false` → 不重置浏览器 → 当前浏览状态不变。
  - 删除最后一个连接 → `LastConnectionException` 在 `service.delete` 内抛出 → 不走到 `wasActive` 赋值 → 不重置（合理：无连接可浏览）。
  - `resetBrowserStateOnActiveConnectionChange` 已在 `:289-292` 定义，invalidate `directoryCacheProvider` + `navigationStackProvider`。

  **测试文件位置：** `test/features/connection/bug_10_test.dart`

---

## §4 不变量

- **[BUG-10-INV1]** 活跃连接变更（切换/编辑/删除）均触发浏览器状态重置
  证据：`connection_list_screen.dart:78-80`（切换）, `connection_provider.dart:316`（编辑）, `:331-346`（删除，修复目标）

---

## §5 测试规约

### 5.2 测试 ID 派生清单

```
BUG-10-S1           # 删除后重置浏览器
BUG-10-INV1         # 三种变更均触发
```

### 5.4 测试文件位置

| 测试 ID | 文件路径 |
|---|---|
| BUG-10-S1 | `test/features/connection/bug_10_test.dart` |
| BUG-10-INV1 | `test/features/connection/bug_10_test.dart` |

---

## §7 跨模块影响

| 其它 feature | 影响点 | 影响条件 | 需要补的回归断言 |
|---|---|---|---|
| BRW | directoryCacheProvider + navigationStackProvider | 删除活跃连接 | 删除后 directoryCache 为空、navigationStack 在根 |

---

## §8 平台特性与手动 QA

本功能不涉及平台原生特性，全部可在 `flutter test` 中验证。

---

## §9 dev-status.json 条目对照

见统一更新：`docs/dev/dev-status.json`。

---

## §10 changelog

- 2026-07-27: 创建 BUG-10 spec（基于 cr-20260724-0110.md CON4）
