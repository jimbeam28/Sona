# BUG-12 — normaliseWebDavUrl 无 try/catch

> 来源：`docs/cr/cr-20260724-0110.md` NET3
> dev-plan 流程：Bug 修复模式

---

## §0 头部元数据

```yaml
id: BUG-12
name: normaliseWebDavUrl 无 try/catch
priority: P1
status: draft
created_at: 2026-07-27
last_updated: 2026-07-27
spec_anchored_files:
  - lib/core/network/webdav_client.dart
  - lib/features/connection/domain/connection_validator.dart
cross_module_impacts: [CON]
parent_feature: null  # core/network，影响 Connection 表单校验
manual_qa_required: false
```

---

## §1 用户视角

### 1.0 原始需求

> cr-20260724-0110.md NET3：normaliseWebDavUrl 调 Uri.parse 无 try/catch，非法端口输入（如 `192.168.1.100:50o5`）抛 FormatException，Debug 红屏 / Release 按钮无反馈。

### 1.1 这一功能干什么（一句话）

修复 URL 含非法端口时校验流程崩溃的缺陷。

### 1.2 用户期望的场景

| ID | 你看到的样子 | 期望行为 |
|----|----|----|
| U1 | URL 填 `192.168.1.100:50o5`（0/o 键误触） | 校验返回"URL 格式不正确"，不崩溃 |

---

## §2 已实现的功能骨架

### 2.1 文件与分层

| 层 | 文件 | 行数 | 角色 |
|---|---|---|---|
| Core Network | `lib/core/network/webdav_client.dart` | ~430 | normaliseWebDavUrl |
| Domain | `lib/features/connection/domain/connection_validator.dart` | ~110 | isValidWebDavUrl（有 try/catch） |

---

## §3 行为规约

### 3.1 修复后行为

- **[BUG-12-S1]** normaliseWebDavUrl 内部捕获 Uri.parse 异常 (`status: new`)
  ```
  Given 用户输入 `http://x:abc`（非法端口）
  When  normaliseWebDavUrl 被调用
  Then  返回原串（交后续 isValidWebDavUrl 出友好错误），不抛异常
  否定断言:
    - 不抛 FormatException（当前 BUG 行为）
    - 不改变合法 URL 的归一化结果
  ```
  Code evidence: `lib/core/network/webdav_client.dart:47-60`（normaliseWebDavUrl 无 try/catch）
  对照：`webdav_client.dart:63-71`（isValidWebDavUrl 有 try/catch）

  #### 修改指令

  **修改点 1：normaliseWebDavUrl 包裹 try/catch**

  文件：`lib/core/network/webdav_client.dart:47-60`

  当前代码：
  ```dart
  String normaliseWebDavUrl(String raw) {
    final trimmed = raw.trim();
    String url;
    if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
      url = trimmed;
    } else {
      url = 'http://$trimmed';
    }
    final uri = Uri.parse(url);
    if (!uri.hasPort && uri.host.isNotEmpty) {
      return uri.replace(port: 5005).toString();
    }
    return url;
  }
  ```

  改为：
  ```dart
  String normaliseWebDavUrl(String raw) {
    final trimmed = raw.trim();
    String url;
    if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
      url = trimmed;
    } else {
      url = 'http://$trimmed';
    }
    try {
      final uri = Uri.parse(url);
      if (!uri.hasPort && uri.host.isNotEmpty) {
        return uri.replace(port: 5005).toString();
      }
    } catch (_) {
      // BUG-12: malformed URL (e.g. illegal port "http://x:abc") —
      // return as-is; the downstream isValidWebDavUrl gate will reject it.
    }
    return url;
  }
  ```

  变更说明：
  - `Uri.parse(url)` 和 `uri.replace(port: 5005)` 包裹在 try/catch 内。
  - 异常时直接返回 `url`（已加 scheme 的原始串），不抛异常。
  - 后续 `isValidWebDavUrl` 会对非法 URL 返回 false，表单显示友好错误。

  **边界裁决：**
  - 合法 URL `http://192.168.1.100:5005` → 正常归一化，无变化。
  - 无端口 `192.168.1.100` → 加 scheme + 默认端口 → `http://192.168.1.100:5005`。
  - 非法端口 `http://x:abc` → `Uri.parse` 抛 FormatException → catch → 返回 `http://x:abc` → `isValidWebDavUrl` 返回 false → 表单显示"URL 格式不正确"。
  - 完全非法 `:::invalid:::` → 加 scheme → `http://:::invalid:::` → `Uri.parse` 可能成功（Dart Uri 很宽松）→ 返回原串 → `isValidWebDavUrl` 检查 host 为空 → false。
  - 空串 → 加 scheme → `http://` → `Uri.parse` 成功，host 为空 → 不进入 if → 返回 `http://` → `isValidWebDavUrl` 返回 false。

  **测试文件位置：** `test/features/browser/bug_12_test.dart`

---

## §4 不变量

- **[BUG-12-INV1]** normaliseWebDavUrl 对任何输入不抛异常
  证据：`webdav_client.dart:47-60`（修复目标）

---

## §5 测试规约

### 5.2 测试 ID 派生清单

```
BUG-12-S1           # 非法端口不抛异常
BUG-12-INV1         # 幂等安全
```

### 5.4 测试文件位置

| 测试 ID | 文件路径 |
|---|---|
| BUG-12-S1 | `test/features/browser/bug_12_test.dart` |
| BUG-12-INV1 | `test/features/browser/bug_12_test.dart` |

---

## §7 跨模块影响

| 其它 feature | 影响点 | 影响条件 | 需要补的回归断言 |
|---|---|---|---|
| CON | 连接表单校验流程 | 用户输入非法 URL | 校验返回错误而非崩溃 |

---

## §8 平台特性与手动 QA

本功能不涉及平台原生特性，全部可在 `flutter test` 中验证。

---

## §9 dev-status.json 条目对照

见统一更新：`docs/dev/dev-status.json`。

---

## §10 changelog

- 2026-07-27: 创建 BUG-12 spec（基于 cr-20260724-0110.md NET3）
