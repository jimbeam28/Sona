# TEST-07 — 网络/helper 测试缺口（NET9+NET10+CTR7）

> 来源：`docs/cr/cr-20260724-0110.md` NET9 (line 747-750) + NET10 (line 752-755) + CTR7 (line 602-605)
> dev-plan 流程：TEST-GAP 补测模式

---

## §0 头部元数据

```yaml
id: TEST-07
name: 网络/helper 测试缺口（NET9+NET10+CTR7）
priority: P1
status: draft
created_at: 2026-07-27
last_updated: 2026-07-27
spec_anchored_files:
  - lib/core/network/webdav_client.dart
  - test/helpers/fake_webdav_client.dart
  - test/helpers/fake_secure_storage.dart
cross_module_impacts: [CON, BRW, CTR]
parent_feature: null
manual_qa_required: false
```

---

## §1 用户视角

### 1.0 原始需求

> cr-20260724-0110.md NET9：整个代码库零 MockClient 使用。validate status 分支、listDirectory 非 207、超时、URL 拼接从未执行。`brw_01_test.dart:151-174` BRW-T04/T05 仅构造 `const WebDavException(...)` 断言字段——从未走 client 路径。
> cr-20260724-0110.md NET10：`fake_webdav_client.dart:6-8,26-27` 注释谎报默认行为。不模拟服务器绝对路径 href。无错误注入。
> cr-20260724-0110.md CTR7：`fake_secure_storage.dart` 未覆写 containsKey → 调用走平台通道 → 测试中 MissingPluginException。

### 1.1 这一功能干什么（一句话）

补齐网络层真实 HTTP 测试、修复 fake helper 注释和行为缺陷、补全 FakeSecureStorage.containsKey。

### 1.2 用户期望的场景

| ID | 你看到的样子 | 期望行为 |
|----|----|----|
| U1 | WebDAV 服务器返回 200/401/403/500 | validate 正确映射为对应 WebDavValidationStatus |
| U2 | listDirectory 返回非 207 状态码 | 抛出 WebDavException 带正确 statusCode |
| U3 | 网络请求超时 | 抛出 TimeoutException |
| U4 | 测试中使用 containsKey | 不抛 MissingPluginException，返回正确布尔值 |
| U5 | 测试中注入 WebDAV 错误 | fake client 可配置抛出指定异常 |

---

## §2 已实现的功能骨架

### 2.1 文件与分层

| 层 | 文件 | 行数 | 角色 |
|---|---|---|---|
| Network | `lib/core/network/webdav_client.dart` | 428 | WebDavClient（http.Client）+ validate + listDirectory |
| Helper | `test/helpers/fake_webdav_client.dart` | 134 | MockWebDavClient + SpyWebDavClient |
| Helper | `test/helpers/fake_secure_storage.dart` | 81 | FakeSecureStorage |
| 测试 | `test/features/browser/brw_01_test.dart` | 450 | BRW 系列测试 |

### 2.2 关键代码段

| 区域 | 行号 | 说明 |
|---|---|---|
| validate HTTP 调用 | `webdav_client.dart:166+` | http.Client.send + status 分支 |
| listDirectory HTTP 调用 | `webdav_client.dart` 200+ | PROPFIND Depth:1 + XML 解析 |
| BRW-T04/T05 仅构造异常 | `brw_01_test.dart:151-174` | `const WebDavException(...)` 字段断言 |
| fake_webdav_client 注释 | `fake_webdav_client.dart:6-8,26-27` | 谎报默认行为 |
| FakeSecureStorage 缺 containsKey | `fake_secure_storage.dart` | 无 containsKey override |
| WebDavClient 构造函数 | `webdav_client.dart:160-164` | 接受注入 http.Client + timeout |

---

## §3 行为规约

### 3.1 补测行为

- **[TEST-07-S1]** MockClient validate 200 → success (`status: new`)
  ```
  Given MockClient 对 PROPFIND 返回 207 Multi-Status + 有效 XML body
  When  WebDavClient.validate(url, user, pass) 被调用
  Then  返回 WebDavValidationResult.success()
  否定断言:
    - 不使用 MockWebDavClient 直接返回结果（当前 NET9 问题：零 MockClient）
    - 不跳过 HTTP 层（必须真实走 http.Client.send 路径）
  ```
  Code evidence: `lib/core/network/webdav_client.dart:160-164`（接受 http.Client 注入）

- **[TEST-07-S2]** MockClient validate 401 → authError (`status: new`)
  ```
  Given MockClient 对 PROPFIND 返回 401 Unauthorized
  When  WebDavClient.validate(url, user, pass) 被调用
  Then  返回 WebDavValidationResult.authError()
  否定断言:
    - 不在非 207 状态时返回 success
    - 不在 401 时抛异常而非返回 authError
  ```
  Code evidence: `webdav_client.dart:166+`（status 分支）

- **[TEST-07-S3]** MockClient validate 超时 → networkError (`status: new`)
  ```
  Given MockClient 在 10s 内不响应（模拟超时）
  When  WebDavClient.validate(url, user, pass) 被调用（默认 5s 超时）
  Then  返回 WebDavValidationResult.networkError()
  否定断言:
    - 不在超时时抛未捕获异常
    - 不改变正常响应路径行为
  ```
  Code evidence: `webdav_client.dart:162-164`（`Duration timeout = const Duration(seconds: 5)`）

- **[TEST-07-S4]** MockClient listDirectory 非 207 → WebDavException (`status: new`)
  ```
  Given MockClient 对 PROPFIND Depth:1 返回 500 Internal Server Error
  When  WebDavClient.listDirectory(url, user, pass, path) 被调用
  Then  抛出 WebDavException 且 statusCode == 500
  否定断言:
    - 不在 500 时返回空列表
    - 不在非 207 时静默成功
  ```
  Code evidence: `webdav_client.dart:128`（`Throws [WebDavException] on auth failures (401) or network errors`）

- **[TEST-07-S5]** MockClient listDirectory malformed body → WebDavException (`status: new`)
  ```
  Given MockClient 对 PROPFIND Depth:1 返回 207 + 无效 XML body
  When  WebDavClient.listDirectory(url, user, pass, path) 被调用
  Then  抛出 WebDavException（XML 解析失败）
  否定断言:
    - 不在 XML 解析失败时返回空列表
    - 不在 malformed body 时静默成功
  ```
  Code evidence: `webdav_client.dart` listDirectory XML 解析路径

- **[TEST-07-S6]** FakeWebDavClient 注释修正 + 错误注入 (`status: new`)
  ```
  Given MockWebDavClient 的 listDirectory 默认行为
  When  注释和实际行为对照
  Then  注释准确描述默认行为（不谎报）
  And   支持错误注入模式（可配置抛 WebDavException）
  否定断言:
    - 不在注释中声称"throws UnimplementedError"当实际返回空列表（当前 NET10 问题）
    - 不在无 error injection 支持时假装完整
  ```
  Code evidence: `test/helpers/fake_webdav_client.dart:6-8,26-27`（注释与实际不符）

- **[TEST-07-S7]** FakeSecureStorage.containsKey 正常返回 (`status: new`)
  ```
  Given FakeSecureStorage 中已存储 key "connection_password_1"
  When  containsKey(key: "connection_password_1") 被调用
  Then  返回 true
  And   containsKey(key: "nonexistent") 返回 false
  否定断言:
    - 不抛 MissingPluginException（当前 CTR7 问题：未覆写 containsKey）
    - 不走平台通道（必须使用内存 map 实现）
  ```
  Code evidence: `test/helpers/fake_secure_storage.dart`（无 containsKey override）

---

## §4 不变量

- **[TEST-07-INV1]** WebDavClient 使用注入的 http.Client（可替换为 MockClient）
  证据：`webdav_client.dart:160-161`（`http.Client? httpClient`）

- **[TEST-07-INV2]** FakeSecureStorage 所有操作在内存中完成（无平台通道）
  证据：`fake_secure_storage.dart`（Map<String, String> _store 驱动）

---

## §5 测试规约

### 5.1 现有测试清单

| 测试文件 | 覆盖 | 备注 |
|---|---|---|
| `test/features/browser/brw_01_test.dart:151-174` | BRW-T04/T05 | 仅构造 WebDavException 断言字段 |
| `test/helpers/fake_webdav_client.dart` | Mock/Spy 实现 | 注释与实际不符，无错误注入 |
| `test/helpers/fake_secure_storage.dart` | Fake 实现 | 缺 containsKey |

### 5.2 测试 ID 派生清单

```
TEST-07-S1          # MockClient validate 200
TEST-07-S2          # MockClient validate 401
TEST-07-S3          # MockClient validate 超时
TEST-07-S4          # MockClient listDirectory 非 207
TEST-07-S5          # MockClient listDirectory malformed body
TEST-07-S6          # FakeWebDavClient 注释修正 + 错误注入
TEST-07-S7          # FakeSecureStorage.containsKey
TEST-07-INV1        # http.Client 注入
TEST-07-INV2        # FakeSecureStorage 无平台通道
```

### 5.3 测试覆盖盲点

| 未覆盖 ID | 现状 | 应补偿方式 |
|---|---|---|
| TEST-07-S1~S3 | 零 MockClient 使用 | 用 package:http/testing MockClient 覆盖 status 分支 + 超时 |
| TEST-07-S4~S5 | listDirectory 错误路径未测 | MockClient 返回非 207 / malformed body → 断言 WebDavException |
| TEST-07-S6 | fake 注释谎报 | 修正注释 + 添加 throwOnListDirectory 错误注入模式 |
| TEST-07-S7 | containsKey 未覆写 | 添加 containsKey override 走内存 map |

### 5.4 测试文件位置

| 测试 ID | 文件路径 |
|---|---|
| TEST-07-S1~S5 | `test/features/browser/brw_01_test.dart`（新增 group）或新文件 `test/core/network/webdav_client_test.dart` |
| TEST-07-S6 | `test/helpers/fake_webdav_client.dart`（修正 + 添加错误注入） |
| TEST-07-S7 | `test/helpers/fake_secure_storage.dart`（添加 containsKey override） |

---

## §6 算法样例

不适用——本 spec 为补测 + helper 修复，无新算法。

---

## §7 跨模块影响

| 其它 feature | 影响点 | 需要补的回归断言 |
|---|---|---|
| CON | connection_provider 使用 WebDavClient.validate | MockClient 测试不影响现有 fake-based 测试 |
| BRW | browser_provider 使用 WebDavClient.listDirectory | MockClient 测试为新增，不改变现有 SpyWebDavClient 测试 |
| CTR | FakeSecureStorage 被所有 feature 测试使用 | containsKey 新增为增量，不破坏现有 override 方法 |

---

## §8 平台特性与手动 QA

本功能不涉及平台原生特性。MockClient 测试全部可在 `flutter test` 中验证。FakeSecureStorage.containsKey 修复消除 MissingPluginException 使更多测试可在纯 Dart 环境运行。

---

## §9 dev-status.json 条目对照

见统一更新：`docs/dev/dev-status.json`。

---

## §10 changelog

- 2026-07-27: 创建 TEST-07 spec（基于 cr-20260724-0110.md NET9 + NET10 + CTR7）
