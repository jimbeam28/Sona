# BUG-23 — 网络健壮性缺陷簇（NET4 + NET5 + NET6 + NET8）

> 来源：`docs/cr/cr-20260724-0110.md` NET4 (line 712-717) + NET5 (line 719-724) + NET6 (line 726-731) + NET8 (line 741-745)
> dev-plan 流程：Bug 修复模式

---

## §0 头部元数据

```yaml
id: BUG-23
name: 网络健壮性缺陷簇（NET4 + NET5 + NET6 + NET8）
priority: P1
status: draft
created_at: 2026-07-27
last_updated: 2026-07-27
spec_anchored_files:
  - lib/core/network/webdav_client.dart
cross_module_impacts: [BRW, CON]
parent_feature: Core/Network
manual_qa_required: false
```

---

## §1 用户视角

### 1.0 原始需求

> cr-20260724-0110.md:
> NET4: `webdav_client.dart:209` timeout 只罩 `send()`（响应头），`bytesToString()` 无超时，慢速服务器可致目录加载永久挂起；`:231` validate 的 `drain()` 可以把已成功结果翻转为失败。
> NET5: `webdav_client.dart:350-351` responseRegex 大小写敏感，`:411-414` 标签子串匹配，多 propstat 只取第一块。
> NET6: `webdav_client.dart:211-226` 状态码映射把 3xx/5xx 与"不可达"混为一谈；`:301-307` listDirectory 非 207 一律裸状态码。
> NET8: `webdav_client.dart:330` 兜底异常把原始异常文本拼进用户可见消息。

### 1.1 这一功能干什么（一句话）

修复 WebDAV 客户端的四个健壮性缺陷：超时覆盖不全、XML 正则脆弱、HTTP 状态码映射粗放、异常信息泄露原始文本。

### 1.2 用户期望的场景

| ID | 你看到的样子 | 期望行为 |
|----|----|----|
| U1 | 慢速 NAS 返回 body 延迟 | 5s 内超时报错，不永久挂起 |
| U2 | 服务器发 `<D:Response>` 大写前缀 | 正常解析目录条目 |
| U3 | 服务器返回 301/500 | 错误提示可操作（"请改用 https" / "服务器内部错误"），非笼统"无法连接" |
| U4 | 网络异常（Connection refused 等） | 用户看到友好中文消息，原始异常仅进日志 |

---

## §2 已实现的功能骨架

### 2.1 文件与分层

| 层 | 文件 | 行数 | 角色 |
|---|---|---|---|
| Network | `lib/core/network/webdav_client.dart` | 428 | WebDAV 客户端实现 |

### 2.2 关键方法表

| 方法 | 位置 | 用途 |
|---|---|---|
| `validate` | `:167-241` | 验证连接（PROPFIND Depth:0） |
| `listDirectory` | `:247-331` | 列目录（PROPFIND Depth:1） |
| `_parsePropfindResponse` | `:346-377` | XML 响应解析 |
| `_extractXmlContent` | `:409-427` | XML 标签提取 |

---

## §3 行为规约

### 3.1 修复后行为

- **[BUG-23-S1]** listDirectory 的 body 读取包进整体 deadline (`status: new`)
  ```
  Given listDirectory 发起 PROPFIND 请求
  When  服务器返回响应头后 body 传输缓慢/中断
  Then  5s 整体 deadline 到期后抛出 WebDavException('连接超时')
  否定断言:
    - 不在 send() 超时后继续等待 body 读取
    - 不改变 207 正常响应的解析逻辑
  ```
  Code evidence: `webdav_client.dart:287`（`.timeout(_timeout)` 只作用于 send）
  Code evidence: `webdav_client.dart:289`（`bytesToString()` 无超时）

  **修改指令 — `lib/core/network/webdav_client.dart`（listDirectory 超时）**

  位置：`:280-289`

  当前代码（:280-289）：
  ```dart
    try {
      final request = http.Request('PROPFIND', targetUri)
        ..headers['Authorization'] = authHeader
        ..headers['Depth'] = '1'
        ..headers['Content-Type'] = 'application/xml';

      final streamedResponse =
          await _httpClient.send(request).timeout(_timeout);

      final body = await streamedResponse.stream.bytesToString();
  ```

  改为：
  ```dart
    try {
      final request = http.Request('PROPFIND', targetUri)
        ..headers['Authorization'] = authHeader
        ..headers['Depth'] = '1'
        ..headers['Content-Type'] = 'application/xml';

      final streamedResponse =
          await _httpClient.send(request).timeout(_timeout);

      final body = await streamedResponse.stream
          .bytesToString()
          .timeout(_timeout);
  ```

  边界裁决：
  - send 用 5s，body 再用 5s → 最坏 10s（与 validate 的 send+drain 模型对齐）
  - body 超时 → TimeoutException → 已有 catch 转 `WebDavException('连接超时')`（`:322-324`）
  - 大目录 body 超过 5s 传输 → 用户看到超时错误，可重试

- **[BUG-23-S2]** validate 的 drain 改为 fire-and-forget，不影响已判定结果 (`status: new`)
  ```
  Given validate 已判定成功（207）或失败
  When  drain 挂起或抛错
  Then  已判定结果不被翻转
  否定断言:
    - 不在 drain 超时后将成功翻转为 networkError
    - 不在 drain 抛错后改变已返回的 result
    - 不阻塞 validate 返回
  ```
  Code evidence: `webdav_client.dart:228-232`（先算 result 再 drain，drain 在 return 前 await）
  Code evidence: `webdav_client.dart:211-227`（result 闭包先完成）

  **修改指令 — `lib/core/network/webdav_client.dart`（validate drain）**

  位置：`:228-232`

  当前代码（:228-232）：
  ```dart
      debugPrint('[WebDAV] validate result: ${result.status}'
          ' (HTTP ${streamedResponse.statusCode})');
      // G-5: drain the response body so the HTTP connection can be reused.
      await streamedResponse.stream.drain<void>();
      return result;
  ```

  改为：
  ```dart
      debugPrint('[WebDAV] validate result: ${result.status}'
          ' (HTTP ${streamedResponse.statusCode})');
      // G-5: drain the response body so the HTTP connection can be reused.
      // Fire-and-forget — drain failure must not flip the already-decided result.
      unawaited(streamedResponse.stream.drain<void>().catchError((_) {}));
      return result;
  ```

  边界裁决：
  - drain 挂起 → 不再阻塞 return（unawaited）
  - drain 抛错 → catchError 吞掉，不影响 result
  - HTTP 连接复用可能略受影响（未排空的 body 可能导致连接不可复用）→ 可接受代价，远优于"成功被翻转为失败"

- **[BUG-23-S3]** responseRegex 大小写不敏感 + 标签边界收紧 (`status: new`)
  ```
  Given 服务器返回 <D:Response> 或 <d:RESPONSE> 等不同大小写前缀
  When  _parsePropfindResponse 解析响应
  Then  正确匹配所有 response 块
  否定断言:
    - 不遗漏大写前缀的 response 块
    - 不匹配到 propstat 等包含 tagName 子串的其他标签
  ```
  Code evidence: `webdav_client.dart:350-351`（responseRegex 无 `caseSensitive:false`）
  Code evidence: `webdav_client.dart:411-414`（`_extractXmlContent` 已用 `caseSensitive:false` — 内部防御不一致）
  Code evidence: `webdav_client.dart:412`（`<[^>]*$tagName[^>]*>` 子串匹配 — 查 prop 先命中 propstat）

  **修改指令 — `lib/core/network/webdav_client.dart`（responseRegex）**

  位置：`:350-351`

  当前代码（:350-351）：
  ```dart
    final responseRegex =
        RegExp(r'<[^>]*response[^>]*>(.*?)</[^>]*response[^>]*>', dotAll: true);
  ```

  改为：
  ```dart
    final responseRegex = RegExp(
      r'<[^>]*response[^>]*>(.*?)</[^>]*response[^>]*>',
      dotAll: true,
      caseSensitive: false,
    );
  ```

  **修改指令 — `lib/core/network/webdav_client.dart`（_extractXmlContent 标签边界）**

  位置：`:409-427`

  当前代码（:411-414）：
  ```dart
    final regex = RegExp(
      '<[^>]*$tagName[^>]*>(.*?)</[^>]*$tagName[^>]*>',
      dotAll: true,
      caseSensitive: false,
    );
  ```

  改为：
  ```dart
    final escapedTag = RegExp.escape(tagName);
    final regex = RegExp(
      '<[^>]*\\b$escapedTag\\b[^>]*>(.*?)</[^>]*\\b$escapedTag\\b[^>]*>',
      dotAll: true,
      caseSensitive: false,
    );
  ```

  同位置 selfClosingRegex（:420-422）：
  当前：
  ```dart
    final selfClosingRegex = RegExp(
      '<[^>]*$tagName[^>]*/>',
      caseSensitive: false,
    );
  ```

  改为：
  ```dart
    final selfClosingRegex = RegExp(
      '<[^>]*\\b$escapedTag\\b[^>]*/>',
      caseSensitive: false,
    );
  ```

  边界裁决：
  - `\b` 词边界确保 `prop` 不匹配 `propstat`，`response` 不匹配 `multistatus-response`（如果存在的话）
  - `RegExp.escape(tagName)` 防御 tagName 含正则特殊字符（当前全为纯字母，但增强鲁棒性）
  - responseRegex 的 `response` 匹配加 `caseSensitive:false` — 与 `_extractXmlContent` 的防御等级对齐
  - 多 propstat 场景：当前 `firstMatch` 只取第一个 prop 块 — 此缺陷不在本次修复范围（NET5 描述中提到但未列为必改项，需更大改动）

- **[BUG-23-S4]** HTTP 状态码分离 3xx/5xx/404 分支 (`status: new`)
  ```
  Given validate 或 listDirectory 收到非标准状态码
  When  状态码为 3xx（重定向）或 5xx（服务器错误）
  Then  返回/抛出区分性错误消息，而非笼统的"无法连接"
  否定断言:
    - 不将 301/302 报为"无法连接到服务器"
    - 不将 500/503 报为"无法连接到服务器"
    - 不改变 207/401/403/404 的已有映射
  ```
  Code evidence: `webdav_client.dart:220-225`（validate default 分支：3xx/5xx 全部 networkError）
  Code evidence: `webdav_client.dart:301-307`（listDirectory 非 207 一律 `服务器返回异常状态码 N`）

  **修改指令 — `lib/core/network/webdav_client.dart`（validate 状态分支）**

  位置：`:211-227`

  当前代码（:211-227）：
  ```dart
      final result = () {
        switch (streamedResponse.statusCode) {
          case 207:
            return WebDavValidationResult.success();
          case 401:
          case 403:
            return WebDavValidationResult.authError();
          case 404:
            return WebDavValidationResult.pathNotFound();
          default:
            if (streamedResponse.statusCode >= 200 &&
                streamedResponse.statusCode < 300) {
              return WebDavValidationResult.success();
            }
            return WebDavValidationResult.networkError();
        }
      }();
  ```

  改为：
  ```dart
      final result = () {
        switch (streamedResponse.statusCode) {
          case 207:
            return WebDavValidationResult.success();
          case 401:
          case 403:
            return WebDavValidationResult.authError();
          case 404:
            return WebDavValidationResult.pathNotFound();
          default:
            if (streamedResponse.statusCode >= 200 &&
                streamedResponse.statusCode < 300) {
              return WebDavValidationResult.success();
            }
            if (streamedResponse.statusCode >= 300 &&
                streamedResponse.statusCode < 400) {
              return const WebDavValidationResult._(
                WebDavValidationStatus.networkError,
                '服务器重定向，请检查地址是否应为 https',
              );
            }
            if (streamedResponse.statusCode >= 500) {
              return const WebDavValidationResult._(
                WebDavValidationStatus.networkError,
                '服务器内部错误，请稍后重试',
              );
            }
            return WebDavValidationResult.networkError();
        }
      }();
  ```

  **修改指令 — `lib/core/network/webdav_client.dart`（listDirectory 状态分支）**

  位置：`:301-307`

  当前代码（:301-307）：
  ```dart
      if (streamedResponse.statusCode != 207) {
        debugPrint(
            '[WebDAV] listDirectory: bad status ${streamedResponse.statusCode}');
        throw WebDavException(
          '服务器返回异常状态码 ${streamedResponse.statusCode}',
          statusCode: streamedResponse.statusCode,
        );
      }
  ```

  改为：
  ```dart
      if (streamedResponse.statusCode != 207) {
        debugPrint(
            '[WebDAV] listDirectory: bad status ${streamedResponse.statusCode}');
        final message = switch (streamedResponse.statusCode) {
          >= 300 && < 400 => '服务器重定向，请检查地址是否应为 https',
          >= 500 => '服务器内部错误，请稍后重试',
          _ => '服务器返回异常状态码 ${streamedResponse.statusCode}',
        };
        throw WebDavException(
          message,
          statusCode: streamedResponse.statusCode,
        );
      }
  ```

  边界裁决：
  - 3xx 提示"改 https" — 当前 http.Client.send 不自动跟随重定向，用户需手动改 URL scheme
  - 5xx "服务器内部错误" — 不暴露服务器细节
  - 其他 4xx（非 401/403/404）→ 保留"异常状态码 N"兜底
  - listDirectory 404 → 走默认 `异常状态码 404` — 如需单独提示路径问题，需额外分支（暂不在本次范围，可后续细化）

- **[BUG-23-S5]** listDirectory 兜底异常使用枚举文案，原始异常仅进日志 (`status: new`)
  ```
  Given listDirectory 捕获到非预期异常
  When  异常类型为 SocketException 等
  Then  抛出 WebDavException 使用固定中文文案，原始异常仅进 debugPrint/LogBuffer
  否定断言:
    - 不在 WebDavException.message 中拼接原始异常文本
    - 不向用户暴露 OS Error、errno、address 等内部信息
    - 不丢失原始异常的日志可追溯性
  ```
  Code evidence: `webdav_client.dart:330`（`throw WebDavException('无法连接到服务器：$e')`）
  Code evidence: `webdav_client.dart:328-329`（debugPrint 已 redact，但 `$e` 仍进用户可见消息）

  **修改指令 — `lib/core/network/webdav_client.dart`（listDirectory catch）**

  位置：`:325-331`

  当前代码（:325-331）：
  ```dart
    } catch (e) {
      // Same second-order leak as validate(): exception text can carry the
      // request uri with userinfo — redact the logged copy (NET7/CON2).
      debugPrint(
          '[WebDAV] listDirectory error: ${redactUrlForLog(e.toString())}');
      throw WebDavException('无法连接到服务器：$e');
    }
  ```

  改为：
  ```dart
    } catch (e) {
      debugPrint(
          '[WebDAV] listDirectory error: ${redactUrlForLog(e.toString())}');
      throw const WebDavException('无法连接到服务器，请检查地址和网络');
    }
  ```

  边界裁决：
  - 固定文案与 `WebDavValidationResult.networkError()` 的 `:35` 文案对齐
  - 原始异常经 debugPrint 进 LogBuffer（`installLogBufferHook` 已挂），可追溯
  - 不再泄露 SocketException 内部信息（OS Error、errno、address）

  **测试文件位置：`test/features/browser/bug_bug23_repro_test.dart`**

---

## §4 不变量

- **[BUG-23-INV1]** 所有用户可见的 WebDavException.message 使用固定文案，不含 `$e` 插值
  证据：`webdav_client.dart:271`（`无法构建请求地址` — 已合规）、`:295-296`（`用户名或密码错误` — 已合规）、`:330`（修复目标）

- **[BUG-23-INV2]** 所有 body/stream 读取操作有超时保护
  证据：`webdav_client.dart:209`（validate send 有 timeout）、`:287`（listDirectory send 有 timeout）、`:289`（listDirectory body 无 timeout — 修复目标）

- **[BUG-23-INV3]** validate 已判定结果不被 drain 翻转
  证据：`webdav_client.dart:228-232`（drain 在 return 前 await — 修复目标）

---

## §5 测试规约

### 5.2 测试 ID 派生清单

```
BUG-23-S1           # listDirectory body 读取超时
BUG-23-S2           # validate drain 不翻转结果
BUG-23-S3           # responseRegex 大小写不敏感 + 标签边界
BUG-23-S4           # 3xx/5xx 状态码分离
BUG-23-S5           # 兜底异常固定文案
BUG-23-INV1         # WebDavException.message 无 $e 插值
BUG-23-INV2         # body/stream 读取有超时
BUG-23-INV3         # drain 不翻转结果
```

### 5.4 测试文件位置

| 测试 ID | 文件路径 |
|---------|----------|
| BUG-23-S1 | `test/features/browser/bug_bug23_repro_test.dart` |
| BUG-23-S2 | `test/features/browser/bug_bug23_repro_test.dart` |
| BUG-23-S3 | `test/features/browser/bug_bug23_repro_test.dart` |
| BUG-23-S4 | `test/features/browser/bug_bug23_repro_test.dart` |
| BUG-23-S5 | `test/features/browser/bug_bug23_repro_test.dart` |
| BUG-23-INV1 | `test/features/browser/bug_bug23_repro_test.dart` |
| BUG-23-INV2 | `test/features/browser/bug_bug23_repro_test.dart` |
| BUG-23-INV3 | `test/features/browser/bug_bug23_repro_test.dart` |

---

## §7 跨模块影响

| 模块 | 影响 | 说明 |
|------|------|------|
| BRW | 正面 | 浏览器页目录加载不再永久挂起，错误提示更可操作 |
| CON | 正面 | 连接验证错误提示更精确（区分重定向/服务器错误） |
| PLY | 无 | 不涉及播放 |

---

## §8 平台特性与手动 QA

本功能不涉及平台原生特性。S1-S5 全部可用 `package:http/testing` MockClient 在 `flutter test` 中验证。

---

## §9 dev-status.json 条目对照

见统一更新：`docs/dev/dev-status.json`。

---

## §10 changelog

- 2026-07-27: 创建 BUG-23 spec（基于 cr-20260724-0110.md NET4 + NET5 + NET6 + NET8）
