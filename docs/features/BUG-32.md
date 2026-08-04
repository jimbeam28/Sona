# BUG-32 — 服务层健壮性（SVC4+SVC5）

> 来源：`docs/cr/cr-20260724-0110.md` SVC4 (line 790-795) + SVC5 (line 797-802)
> dev-plan 流程：Bug 修复模式

---

## §0 头部元数据

```yaml
id: BUG-32
name: 服务层健壮性（SVC4+SVC5）
priority: P1
status: draft
created_at: 2026-07-27
last_updated: 2026-08-05
spec_anchored_files:
  - lib/core/services/storage_utils.dart
  - lib/core/services/background_service.dart
cross_module_impacts: [CON, PLY, BRW]
parent_feature: null
manual_qa_required: true
```

---

## §1 用户视角

### 1.0 原始需求

> cr-20260724-0110.md SVC4：`storage_utils.dart:12-16` — `safeStorageRead` 超时返回 null。调用方无法区分"无值"和"超时"。`audio_source_builder.dart:152` 静默跳过预加载；`connection_provider.dart:154`、`player_screen.dart:201` 同理。Android Keystore 高负载/锁屏延迟（部分三星/华为设备）→ 读取 >5s → 返回 null → 静默失败。
> cr-20260724-0110.md SVC5：`background_service.dart:9-11` — `invokeMethod` 返回 Future，函数为 void 且未 unawaited/catchError。若原生层抛 PlatformException（Activity 已销毁）→ 未处理异步错误。

### 1.1 这一功能干什么（一句话）

使 `safeStorageRead` 的超时与无值可区分，并修复 `moveTaskToBack` 的未处理异步错误。

### 1.2 用户期望的场景

| ID | 你看到的样子 | 期望行为 |
|----|----|----|
| U1 | Android Keystore 高负载导致 secure_storage 读取 >5s | 调用方收到超时异常而非 null，可展示错误提示或重试 |
| U2 | secure_storage 中确实无此 key | 返回 null（行为不变） |
| U3 | Android Activity 已销毁时按返回键 | 不抛未处理异步错误，app 稳定退到后台 |
| U4 | 非 Android 平台按返回键 | 无操作（行为不变） |

---

## §2 已实现的功能骨架

### 2.1 文件与分层

| 层 | 文件 | 行数 | 角色 |
|---|---|---|---|
| Service | `lib/core/services/storage_utils.dart` | 48 | safeStorageRead / safeStorageWrite / safeStorageDelete |
| Service | `lib/core/services/background_service.dart` | 11 | moveTaskToBack MethodChannel 调用 |
| Caller | `lib/core/services/audio_source_builder.dart` | 161 | preloadAudioSource 调用 safeStorageRead |
| Caller | `lib/features/connection/connection_provider.dart` | 346 | startupValidation 调用 safeStorageRead |
| Caller | `lib/features/browser/browser_provider.dart` | 195 | directoryContentsProvider 调用 safeStorageRead |
| Caller | `lib/features/player/player_screen.dart` | 426 | _runSerializedLoad 调用 safeStorageRead |
| Caller | `lib/features/home/home_screen.dart` | 201 | onPopInvokedWithResult 调用 moveTaskToBack |

### 2.2 关键代码段

| 区域 | 行号 | 说明 |
|---|---|---|
| safeStorageRead 超时返回 null | `storage_utils.dart:11-16` | catch all → return null |
| audio_source_builder 静默跳过 | `audio_source_builder.dart:150-152` | `pw == null → return` |
| connection_provider authError | `connection_provider.dart:160-163` | `password == null → authError` |
| browser_provider 密码未保存 | `browser_provider.dart:82-83` | `pw == null → throw WebDavException('密码未保存')` |
| player_screen 分类错误 | `player_screen.dart:197-199` | `pw == null → hasPassword=false → classifyLoadFailure` |
| moveTaskToBack 未处理 Future | `background_service.dart:9-10` | `void moveTaskToBack()` + `_channel.invokeMethod(...)` 无 await/catch |
| moveTaskToBack 调用方 | `home_screen.dart:84` | `moveTaskToBack()` in onPopInvokedWithResult |

---

## §3 行为规约

### 3.1 修复后行为

- **[BUG-32-S1]** `safeStorageRead` 超时时抛出 `SecureStorageTimeoutException` (`status: new`)
  ```
  Given FlutterSecureStorage.read(key: 'x') 在 5s 内未返回（超时）
  When  调用 safeStorageRead(storage, key: 'x')
  Then  抛出 SecureStorageTimeoutException（非返回 null）
  否定断言:
    - 不在超时时返回 null（当前 BUG：catch all → return null）
    - 不在 key 不存在时抛异常（key 不存在 → 正常返回 null）
    - 不改变 safeStorageWrite / safeStorageDelete 的超时行为（它们已 rethrow）
  ```
  Code evidence: `lib/core/services/storage_utils.dart:11-16`（catch all 返回 null）

  **修改指令 — `lib/core/services/storage_utils.dart`（safeStorageRead）**

  位置：`:1-17`

  当前代码（:1-17）：
  ```dart
  import 'dart:async';
  import 'package:flutter/foundation.dart';
  import 'package:flutter_secure_storage/flutter_secure_storage.dart';

  /// Reads from [storage] with a 5-second timeout.
  /// Returns null on timeout or error.
  Future<String?> safeStorageRead(
    FlutterSecureStorage storage, {
    required String key,
  }) async {
    try {
      return await storage.read(key: key).timeout(const Duration(seconds: 5));
    } catch (e) {
      debugPrint('[Storage] safeRead failed: $e');
      return null;
    }
  }
  ```

  改为：
  ```dart
  import 'dart:async';
  import 'package:flutter/foundation.dart';
  import 'package:flutter_secure_storage/flutter_secure_storage.dart';

  /// Thrown when [safeStorageRead] exceeds its timeout.
  /// Callers can distinguish "no value" (null) from "timeout" (this exception).
  class SecureStorageTimeoutException implements Exception {
    final String key;
    final Duration timeout;
    const SecureStorageTimeoutException({required this.key, required this.timeout});
    @override
    String toString() =>
        'SecureStorageTimeoutException: read($key) exceeded ${timeout.inSeconds}s';
  }

  /// Reads from [storage] with a 5-second timeout.
  /// Returns null when the key does not exist.
  /// Throws [SecureStorageTimeoutException] on timeout.
  /// Returns null on other errors (logged).
  Future<String?> safeStorageRead(
    FlutterSecureStorage storage, {
    required String key,
  }) async {
    try {
      return await storage.read(key: key).timeout(const Duration(seconds: 5));
    } on TimeoutException {
      debugPrint('[Storage] safeRead timeout: key=$key');
      throw SecureStorageTimeoutException(
          key: key, timeout: const Duration(seconds: 5));
    } catch (e) {
      debugPrint('[Storage] safeRead failed: $e');
      return null;
    }
  }
  ```

  边界裁决：
  - key 不存在 → `storage.read()` 返回 null → 正常返回 null（不变）
  - 超时 → `TimeoutException` → 抛出 `SecureStorageTimeoutException`（新增）
  - 其他异常（如 PlatformException）→ catch → return null（不变，兼容旧行为）
  - `SecureStorageTimeoutException` 实现 `Exception` → 调用方可选择性 catch

  **调用方适配：**

  **`audio_source_builder.dart:150-152`** — 当前代码：
  ```dart
    final pw =
        await safeStorageRead(storage, key: 'connection_password_$connectionId');
    if (pw == null || pw.isEmpty) return;
  ```
  改为：
  ```dart
    final String? pw;
    try {
      pw = await safeStorageRead(storage, key: 'connection_password_$connectionId');
    } on SecureStorageTimeoutException {
      debugPrint('[AudioSource] preload: password read timeout');
      return;
    }
    if (pw == null || pw.isEmpty) return;
  ```

  **`connection_provider.dart:160-163`** — 当前代码：
  ```dart
    final password = await safeStorageRead(storage, key: passwordKey);
    if (password == null || password.isEmpty) {
      debugPrint('[Conn] startupValidation: no password');
      return WebDavValidationResult.authError();
    }
  ```
  改为：
  ```dart
    final String? password;
    try {
      password = await safeStorageRead(storage, key: passwordKey);
    } on SecureStorageTimeoutException {
      debugPrint('[Conn] startupValidation: password read timeout');
      return const WebDavValidationResult.error('读取密码超时，请重试');
    }
    if (password == null || password.isEmpty) {
      debugPrint('[Conn] startupValidation: no password');
      return WebDavValidationResult.authError();
    }
  ```

  **`browser_provider.dart:81-83`** — 当前代码：
  ```dart
    final pw =
        await safeStorageRead(storage, key: 'connection_password_${conn.id}');
    if (pw == null || pw.isEmpty) throw const WebDavException('密码未保存');
  ```
  改为：
  ```dart
    final String? pw;
    try {
      pw = await safeStorageRead(storage, key: 'connection_password_${conn.id}');
    } on SecureStorageTimeoutException {
      throw const WebDavException('读取密码超时，请重试');
    }
    if (pw == null || pw.isEmpty) throw const WebDavException('密码未保存');
  ```

  **`player_screen.dart:196-199`** — 当前代码：
  ```dart
          final pw = await safeStorageRead(storage,
              key: 'connection_password_${activeConn.id}');
          hasPassword = pw != null && pw.isNotEmpty;
  ```
  改为：
  ```dart
          try {
            final pw = await safeStorageRead(storage,
                key: 'connection_password_${activeConn.id}');
            hasPassword = pw != null && pw.isNotEmpty;
          } on SecureStorageTimeoutException {
            debugPrint('[Player] password read timeout');
            hasPassword = false;
          }
  ```

  > **⚠ 更正（2026-08-05，cr-20260804-1922 复核；f4ef23b secret-logs）**：上述调用方适配
  > 片段中含 "password" 的日志文案已改为 secure storage 语义化文案（日志文案不得含
  > 凭证关键字——secret-logs 门禁判据），catch + 日志 + 跳过/降级语义不变。
  > 当前文案以以下 file:line 为准：
  > - `lib/core/services/audio_source_builder.dart:156` — `'[AudioSource] preload: secure storage read timeout, skip'`（原 spec 文案 `'[AudioSource] preload: password read timeout'`）
  > - `lib/features/connection/connection_provider.dart:165` — `'[Conn] startupValidation: secure storage read timeout'`（原 spec 文案 `'[Conn] startupValidation: password read timeout'`）
  > - `lib/features/connection/connection_provider.dart:169` — `'[Conn] startupValidation: no secret stored'`（原 spec 文案 `'[Conn] startupValidation: no password'`，S1 当前代码块与改后块两处同改）
  > - `lib/features/player/player_screen.dart:203` — `'[Player] secure storage read timeout'`（原 spec 文案 `'[Player] password read timeout'`）
  >
  > 用户可见文案不变（属 banner 非日志，不受凭证关键字约束）：
  > `WebDavValidationResult.error('读取密码超时，请重试')`（`connection_provider.dart:166`）、
  > `WebDavException('读取密码超时，请重试')`（`browser_provider.dart:94`）。

- **[BUG-32-S2]** `moveTaskToBack` 处理异步错误 (`status: new`)
  ```
  Given Android Activity 已销毁
  When  用户按返回键触发 moveTaskToBack
  Then  不抛未处理异步错误
  否定断言:
    - 不在 Activity 销毁后产生 unhandled async error（当前 BUG：invokeMethod Future 未捕获）
    - 不改变正常场景下 moveTaskToBack 的行为（Activity 存活 → 正常退到后台）
    - 不改变非 Android 平台的 no-op 行为
  ```
  Code evidence: `lib/core/services/background_service.dart:9-10`（`void` 函数 + `_channel.invokeMethod(...)` 无 await/catch）

  **修改指令 — `lib/core/services/background_service.dart`**

  位置：`:1-11`

  当前代码（:1-11）：
  ```dart
  import 'package:flutter/services.dart';

  const _channel = MethodChannel('com.example.nas_audio_player/background');

  /// Moves the Android task to the background without exiting the app.
  ///
  /// On platforms other than Android this is a no-op.  The app stays alive
  /// and audio playback continues via the foreground service.
  void moveTaskToBack() {
    _channel.invokeMethod('moveTaskToBack');
  }
  ```

  改为：
  ```dart
  import 'dart:async';

  import 'package:flutter/services.dart';

  const _channel = MethodChannel('com.example.nas_audio_player/background');

  /// Moves the Android task to the background without exiting the app.
  ///
  /// On platforms other than Android this is a no-op.  The app stays alive
  /// and audio playback continues via the foreground service.
  void moveTaskToBack() {
    unawaited(_channel.invokeMethod('moveTaskToBack').catchError((_) {}));
  }
  ```

  边界裁决：
  - Activity 存活 → `invokeMethod` 正常完成 → `catchError` 不触发
  - Activity 已销毁 → 原生层抛 `PlatformException` → `catchError` 吞掉 → 无 unhandled error
  - 非 Android → MethodChannel 无实现 → `MissingPluginException` → `catchError` 吞掉 → no-op
  - `unawaited` 显式标记不等待 Future → 消除 `discarded_futures` lint 警告
  - 调用方 `home_screen.dart:84` 无需修改（函数签名不变，仍为 `void`）

  **测试文件位置：`test/features/timer/bug_bug32_repro_test.dart`**
  更正（2026-08-05）：上行路径笔误——实际门禁为 `test/features/coverage/bug_bug32_repro_test.dart`（与 §5.4 一致；commit 08fd938 创建、f4ef23b 扩充。注意 `.gitignore` `coverage/` 误伤该目录，入库需 `git add -f`，见 cr-20260804-1922 §5 O6）

---

## §4 不变量

- **[BUG-32-INV1]** `safeStorageRead` 超时与无值可区分
  证据：修复后超时抛 `SecureStorageTimeoutException`（`storage_utils.dart:14-18`），key 不存在返回 null

- **[BUG-32-INV2]** 所有 `safeStorageRead` 调用方都区分超时与无值
  证据：4 个调用方均添加 `on SecureStorageTimeoutException` 处理（`audio_source_builder.dart:150`、`connection_provider.dart:160`、`browser_provider.dart:82`、`player_screen.dart:197`）

- **[BUG-32-INV3]** 所有 MethodChannel fire-and-forget 调用都有错误处理
  证据：`background_service.dart:10` 使用 `unawaited(...catchError((_) {}))`

---

## §5 测试规约

### 5.1 现有测试清单

| 测试文件 | 覆盖 | 备注 |
|---|---|---|
| `test/helpers/fake_secure_storage.dart` | 模拟 FlutterSecureStorage | 可用于构造超时场景 |

### 5.2 测试 ID 派生清单

```
BUG-32-S1           # safeStorageRead 超时抛异常
BUG-32-S2           # moveTaskToBack 错误处理
BUG-32-INV1         # 超时与无值可区分
BUG-32-INV2         # 调用方区分超时
BUG-32-INV3         # MethodChannel 错误处理
```

### 5.3 测试覆盖盲点

| 未覆盖 ID | 现状 | 应补偿方式 |
|---|---|---|
| BUG-32-S1 | 无测试验证 safeStorageRead 超时行为 | 用 fake storage 模拟超时 → 断言抛出 SecureStorageTimeoutException |
| BUG-32-S1 key 不存在 | 无测试验证 key 不存在时返回 null | fake storage 返回 null → 断言 safeStorageRead 返回 null |
| BUG-32-S2 | 无测试验证 moveTaskToBack 错误处理 | 用 mock MethodChannel 抛 PlatformException → 断言不抛未处理错误 |

### 5.4 测试文件位置

| 测试 ID | 文件路径 |
|---|---|
| BUG-32-S1 | `test/features/coverage/bug_bug32_repro_test.dart` |
| BUG-32-S2 | `test/features/coverage/bug_bug32_repro_test.dart` |
| BUG-32-INV1 | `test/features/coverage/bug_bug32_repro_test.dart` |
| BUG-32-INV2 | `test/features/coverage/bug_bug32_repro_test.dart` |
| BUG-32-INV3 | `test/features/coverage/bug_bug32_repro_test.dart` |

---

## §6 算法样例

不适用——本修复为异常处理改进，无新算法。

---

## §7 跨模块影响

| 其它 feature | 影响点 | 需要补的回归断言 |
|---|---|---|
| CON | `connection_provider.dart:160` | 超时不再返回 authError，改为超时错误提示 |
| PLY | `player_screen.dart:197` | 超时不再分类为"无密码"，hasPassword 保持 false |
| BRW | `browser_provider.dart:82` | 超时不再抛"密码未保存"，改为"读取密码超时" |
| BRW | `audio_source_builder.dart:150` | 超时不再静默跳过，记录日志后跳过 |

---

## §8 平台特性与手动 QA

| 风险 | 近似测试方案 | 测不了 → 进 mqa-backlog |
|---|---|---|
| Android Keystore 高负载延迟（三星/华为） | fake storage 模拟超时 | 真机验证：高负载下密码读取超时是否显示错误提示而非静默失败 |
| Activity 销毁后 moveTaskToBack | mock MethodChannel 抛异常 | 真机验证：快速连按返回键是否导致 crash |

---

## §9 dev-status.json 条目对照

见统一更新：`docs/dev/dev-status.json`。

---

## §10 changelog

- 2026-07-27: 创建 BUG-32 spec（基于 cr-20260724-0110.md SVC4 + SVC5）
- 2026-08-05: cr-20260804-1922 复核：修订实现性错误/门禁指向——S1 调用方适配片段中 4 处含 "password" 的日志文案快照过时，按 f4ef23b（secret-logs）当前文案更正（audio_source_builder.dart:156 / connection_provider.dart:165,169 / player_screen.dart:203）；S2 测试文件位置笔误 timer/ 更正为 coverage/（与 §5.4 一致）
