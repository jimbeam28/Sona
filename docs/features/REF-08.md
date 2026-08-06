# REF-08 — installLogBufferHook 幂等化（SVC7）

> 来源：`docs/cr/cr-20260724-0110.md` SVC7
> dev-plan 流程：Refactoring 模式

---

## §0 头部元数据

```yaml
id: REF-08
name: installLogBufferHook 幂等化（SVC7）
priority: P1
status: draft
created_at: 2026-07-27
last_updated: 2026-07-27
spec_anchored_files:
  - lib/core/services/log_buffer.dart
cross_module_impacts: []
parent_feature: null
manual_qa_required: false
```

---

## §1 用户视角

### 1.0 原始需求

> cr-20260724-0110.md SVC7：`log_buffer.dart:55-63` — captures "current debugPrint" and wraps it. Calling twice → each message logged twice. Hot-restart re-runs main() without clearing the global assignment.

### 1.1 这一功能干什么（一句话）

使 `installLogBufferHook()` 幂等：多次调用不会产生多层包装，热重启后不会重复记录日志。

### 1.2 用户期望的场景

| ID | 你看到的样子 | 期望行为 |
|----|----|----|
| U1 | 热重启 app（hot restart） | 日志不会重复记录（每条 debugPrint 只进 LogBuffer 一次） |
| U2 | 正常启动 app | 日志正常记录（行为不变） |

---

## §2 已实现的功能骨架

### 2.1 文件与分层

| 层 | 文件 | 行数 | 角色 |
|---|---|---|---|
| Service | `lib/core/services/log_buffer.dart` | 63 | LogBuffer + installLogBufferHook |
| Caller | `lib/main.dart:27` | — | 唯一调用点 |

### 2.2 关键代码段

| 区域 | 行号 | 说明 |
|---|---|---|
| installLogBufferHook | `log_buffer.dart:55-63` | 捕获当前 debugPrint 并包装 |
| main() 调用 | `main.dart:27` | 热重启时重新执行 |
| 问题机制 | `log_buffer.dart:56` | `final original = debugPrint;` — 第二次调用时 original 已是包装后的版本 |

---

## §3 行为规约

### 3.1 幂等化

- **[REF-08-S1]** installLogBufferHook 多次调用仅安装一次 (`status: new`)
  ```
  Given installLogBufferHook 已被调用一次
  When  再次调用 installLogBufferHook
  Then  debugPrint 仍为第一次安装时的包装版本（不嵌套包装）
  And   每条 debugPrint 消息仅被 LogBuffer.instance.add 记录一次
  否定断言:
    - 不在第二次调用时产生双层包装（当前 BUG：original 捕获的是已包装版本）
    - 不在热重启后导致日志重复（main() 重新执行 installLogBufferHook）
    - 不改变首次调用的行为（正常包装 debugPrint → LogBuffer）
    - 不改变 LogBuffer 的其它行为（add / clear / entries）
  ```
  Code evidence: `lib/core/services/log_buffer.dart:55-63`（`final original = debugPrint;` 每次调用都捕获当前值）；`lib/main.dart:27`（热重启时重新执行）

  **修改指令 — `lib/core/services/log_buffer.dart`**

  位置：`:51-63`

  当前代码：
  ```dart
  /// Installs a [debugPrint] hook that mirrors output into [LogBuffer].
  ///
  /// The original synchronous printer is still invoked so console logs
  /// continue to work when the device is attached to a host.
  void installLogBufferHook() {
    final original = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {
      if (message != null) {
        LogBuffer.instance.add(message);
      }
      original(message, wrapWidth: wrapWidth);
    };
  }
  ```
  改为：
  ```dart
  bool _logHookInstalled = false;

  /// Installs a [debugPrint] hook that mirrors output into [LogBuffer].
  ///
  /// The original synchronous printer is still invoked so console logs
  /// continue to work when the device is attached to a host.
  ///
  /// Idempotent: calling multiple times (e.g. after hot restart) only
  /// installs the hook once, avoiding duplicate log entries.
  void installLogBufferHook() {
    if (_logHookInstalled) return;
    _logHookInstalled = true;
    final original = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {
      if (message != null) {
        LogBuffer.instance.add(message);
      }
      original(message, wrapWidth: wrapWidth);
    };
  }
  ```

  边界裁决：
  - 首次调用 → `_logHookInstalled` 为 false → 正常安装 → 设为 true
  - 第二次调用（或热重启后 main() 重跑）→ `_logHookInstalled` 为 true → 直接 return
  - 注意：热重启时 `_logHookInstalled` 作为顶层变量是否被重置取决于 Dart VM。若热重启重置顶层变量，则 hook 会重新安装一次（安全：此时 original 是 Dart 原始 debugPrint，非包装版本）。若热重启不重置顶层变量，则直接 return（安全）。两种情况都不会产生嵌套包装。

---

## §4 不变量

- **[REF-08-INV1]** installLogBufferHook 幂等：多次调用不产生嵌套包装
  证据：`log_buffer.dart` 中 `_logHookInstalled` 静态 guard 确保仅安装一次

- **[REF-08-INV2]** 每条 debugPrint 消息仅被 LogBuffer 记录一次
  证据：不存在多层包装 → add() 仅调用一次

---

## §5 测试规约

### 5.1 现有测试清单

| 测试文件 | 覆盖 | 备注 |
|---|---|---|
| 无 | — | 当前无 installLogBufferHook 的单元测试 |

### 5.2 测试 ID 派生清单

```
REF-08-S1           # 多次调用幂等
REF-08-INV1         # 不嵌套包装
REF-08-INV2         # 不重复记录
```

### 5.3 测试覆盖盲点

| 未覆盖 ID | 现状 | 应补偿方式 |
|---|---|---|
| REF-08-S1 | 无测试 | 调用 installLogBufferHook 两次 → debugPrint 一条消息 → LogBuffer.entries.length == 1 |

### 5.4 测试文件位置

| 测试 ID | 文件路径 |
|---|---|
| REF-08-S1 | `test/core/services/log_buffer_test.dart`（新建） |

---

## §6 算法样例

不适用——本修复为添加 guard flag，无新算法。

---

## §7 跨模块影响

| 其它 feature | 影响点 | 需要补的回归断言 |
|---|---|---|
| 无 | — | 仅影响 LogBuffer 内部实现 |

---

## §8 平台特性与手动 QA

本功能不涉及平台原生特性，全部可在 `flutter test` 中验证。

---

## §9 dev-status.json 条目对照

见统一更新：`docs/dev/dev-status.json`。

---

## §10 changelog

- 2026-07-27: 创建 REF-08 spec（基于 cr-20260724-0110.md SVC7）
- 2026-08-06: dev-plan 修订——补 §5.4「测试文件位置」门禁节（spec-scan --gate 硬门禁前置，af084af 引入）；门禁文件 = 新建 test/core/services/log_buffer_test.dart（当前无任何 log_buffer 单元测试）
