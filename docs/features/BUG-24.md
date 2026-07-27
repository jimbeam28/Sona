# BUG-24 — 连接编辑健壮性（CON5 + CON6 + CON7 + CON8）

> 来源：`docs/cr/cr-20260724-0110.md` CON5 (line 182-187) + CON6 (line 189-194) + CON7 (line 196-201) + CON8 (line 203-208)
> dev-plan 流程：Bug 修复模式

---

## §0 头部元数据

```yaml
id: BUG-24
name: 连接编辑健壮性（CON5 + CON6 + CON7 + CON8）
priority: P1
status: draft
created_at: 2026-07-27
last_updated: 2026-07-27
spec_anchored_files:
  - lib/features/connection/connection_edit_screen.dart
  - lib/features/connection/domain/connection_service.dart
cross_module_impacts: [CON]
parent_feature: Connection
manual_qa_required: false
```

---

## §1 用户视角

### 1.0 原始需求

> cr-20260724-0110.md:
> CON5: `connection_edit_screen.dart:43-57` `_originalConfig` 一次性 best-effort 捕获，`:277` 强解包崩溃路径。
> CON6: `connection_service.dart:73-84` `update()` 非原子无回滚，storage 写成功后 DAO 失败 → 状态不一致。
> CON7: `connection_service.dart:97-100` `delete()` 先删 DB（不可逆），后删 storage，后者失败 → 提示与状态矛盾 + 孤儿密码 key。
> CON8: `connection_edit_screen.dart:229-238` 测试连接用空密码发送验证，保存用已存密码 — 语义矛盾。

### 1.1 这一功能干什么（一句话）

修复连接编辑的四个健壮性缺陷：消除 `_originalConfig` 强解包、对齐 `update()` 原子性、`delete()` 的 storage 清理降级 best-effort、测试连接与保存的密码语义对齐。

### 1.2 用户期望的场景

| ID | 你看到的样子 | 期望行为 |
|----|----|----|
| U1 | 编辑页保存时 `_originalConfig` 未捕获 | 按 id 现查兜底，不崩溃 |
| U2 | 改密码保存时 DAO 失败 | 回滚 storage，状态一致 |
| U3 | 删除连接时 secure_storage 超时 | 连接已删除 + 提示成功（密码清理为 best-effort） |
| U4 | 编辑页只改 URL 密码留空，点"测试连接" | 使用已存密码测试，与"保存"语义一致 |

---

## §2 已实现的功能骨架

### 2.1 文件与分层

| 层 | 文件 | 行数 | 角色 |
|---|---|---|---|
| UI | `lib/features/connection/connection_edit_screen.dart` | 397 | 编辑页 Widget |
| Domain | `lib/features/connection/domain/connection_service.dart` | 111 | CRUD 服务 |
| Domain | `lib/features/connection/domain/edit_screen_logic.dart` | ~80 | 编辑判定纯函数 |

### 2.2 关键方法表

| 方法 | 位置 | 用途 |
|---|---|---|
| `_captureOriginalIfNeeded` | `connection_edit_screen.dart:48-57` | 一次性捕获原始配置 |
| `_onTestConnection` | `connection_edit_screen.dart:229-238` | 测试连接（用表单密码） |
| `_onSave` | `connection_edit_screen.dart:241-321` | 保存（`:277` 强解包） |
| `update` | `connection_service.dart:73-84` | 更新连接（非原子） |
| `delete` | `connection_service.dart:97-100` | 删除连接（DB 先行） |

---

## §3 行为规约

### 3.1 修复后行为

- **[BUG-24-S1]** `_onSave` 消除 `_originalConfig` 强解包 (`status: new`)
  ```
  Given 编辑页 _originalConfig 未捕获（首帧 list 未解析）
  When  用户点保存
  Then  按 id 现查 connectionListProvider 获取原始配置兜底，不崩溃
  否定断言:
    - 不在 _originalConfig 为 null 时抛 Null check operator error
    - 不改变 _originalConfig 已捕获时的正常保存行为
    - 不改变 needsRevalidation 判定逻辑
  ```
  Code evidence: `connection_edit_screen.dart:277`（`_originalConfig!.copyWith(...)`）
  Code evidence: `connection_edit_screen.dart:204`（`if (_originalConfig == null) return true;` safety net — 说明已知可能为 null）
  Code evidence: `connection_edit_screen.dart:48-57`（`_captureOriginalIfNeeded` 只在 postFrame 跑一次）

  **修改指令 — `lib/features/connection/connection_edit_screen.dart`（_onSave 内获取 original）**

  位置：`:265-282`

  当前代码（:265-282）：
  ```dart
    try {
      final updater = ref.read(connectionUpdaterProvider);

      // Determine display name: use user input or fall back to hostname
      final rawName = _formController.displayName;
      final effectiveName = rawName.isNotEmpty
          ? rawName
          : ConnectionConfig.hostnameFromUrl(_formController.url);

      // Normalise URL before saving
      final normalisedUrl = normaliseWebDavUrl(_formController.url);

      final config = _originalConfig!.copyWith(
        name: effectiveName,
        url: normalisedUrl,
        username: _formController.username,
        basePath: _formController.basePath,
      );
  ```

  改为：
  ```dart
    try {
      final updater = ref.read(connectionUpdaterProvider);

      final rawName = _formController.displayName;
      final effectiveName = rawName.isNotEmpty
          ? rawName
          : ConnectionConfig.hostnameFromUrl(_formController.url);

      final normalisedUrl = normaliseWebDavUrl(_formController.url);

      final original = _originalConfig ??
          ref
              .read(connectionListProvider)
              .valueOrNull
              ?.where((c) => c.id == widget.connectionId)
              .firstOrNull;
      if (original == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('无法获取连接信息，请重试'),
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
          );
        }
        return;
      }

      final config = original.copyWith(
        name: effectiveName,
        url: normalisedUrl,
        username: _formController.username,
        basePath: _formController.basePath,
      );
  ```

  边界裁决：
  - `_originalConfig` 已捕获 → 走原路径（`??` 不触发）
  - `_originalConfig` 未捕获但 list 已解析 → 按 id 查到，正常保存
  - `_originalConfig` 未捕获且 list 未解析 → 友好提示"无法获取连接信息"
  - `firstOrNull` 返回 null（id 不存在）→ 同上友好提示
  - `_needsRevalidation` getter（`:204`）已有 `_originalConfig == null → return true` safety net → 此时需验证才能保存，符合预期

- **[BUG-24-S2]** `update()` 对齐 `save()` 原子性策略 (`status: new`)
  ```
  Given update() 被调用，含新密码
  When  safeStorageWrite 成功但 DAO update 失败
  Then  storage 回滚到旧密码，状态一致
  否定断言:
    - 不在 DAO 失败后保留新密码在 storage 中
    - 不改变 DAO 成功 storage 成功的正常路径
    - 不改变 password 为 null 时的行为（不写 storage）
  ```
  Code evidence: `connection_service.dart:73-84`（先 storage 后 DAO，DAO 失败无补偿）
  对照：`connection_service.dart:38-65`（`save()` 有完整 rollback：storage 失败 → 删 DB 行）

  **修改指令 — `lib/features/connection/domain/connection_service.dart`（update）**

  位置：`:73-84`

  当前代码（:73-84）：
  ```dart
  Future<void> update({
    required ConnectionConfig config,
    String? password,
  }) async {
    final permanentKey = 'connection_password_${config.id}';

    if (password != null && password.isNotEmpty) {
      await safeStorageWrite(_storage, key: permanentKey, value: password);
    }

    await _dao.update(config, passwordKey: permanentKey);
  }
  ```

  改为：
  ```dart
  Future<void> update({
    required ConnectionConfig config,
    String? password,
  }) async {
    final permanentKey = 'connection_password_${config.id}';

    if (password != null && password.isNotEmpty) {
      final oldPassword = await safeStorageRead(_storage, key: permanentKey);
      await safeStorageWrite(_storage, key: permanentKey, value: password);
      try {
        await _dao.update(config, passwordKey: permanentKey);
      } catch (_) {
        await safeStorageWrite(_storage, key: permanentKey, value: oldPassword);
        rethrow;
      }
    } else {
      await _dao.update(config, passwordKey: permanentKey);
    }
  }
  ```

  边界裁决：
  - 密码未变（`password == null`）→ 直接 DAO update，无 storage 操作（行为不变）
  - 密码变更 + storage 成功 + DAO 成功 → 正常路径
  - 密码变更 + storage 成功 + DAO 失败 → 读旧密码回写 storage → rethrow
  - 密码变更 + storage 失败 → safeStorageWrite 已 rethrow，不进入 DAO
  - 旧密码读取失败（超时）→ `oldPassword` 为 null → 回滚写 null → 密码丢失，但 DAO 也失败了 → 用户需重新输入密码（可接受降级）

- **[BUG-24-S3]** `delete()` 的 storage 清理降级 best-effort (`status: new`)
  ```
  Given delete() 被调用
  When  DAO 删除成功但 secure_storage 删除超时/失败
  Then  连接已删除（成功提示），storage 清理失败仅记日志
  否定断言:
    - 不在 storage 删除失败时向用户报"删除失败"
    - 不在 storage 删除失败时 rethrow 异常
    - 不改变 DAO 删除成功 storage 删除成功的正常路径
  ```
  Code evidence: `connection_service.dart:97-100`（DAO delete 后 safeStorageDelete，后者 5s 超时 rethrow）
  Code evidence: `storage_utils.dart:38-48`（`safeStorageDelete` 超时 rethrow）
  Code evidence: `connection_list_screen.dart:163-171`（catch 后弹"删除失败"）

  **修改指令 — `lib/features/connection/domain/connection_service.dart`（delete）**

  位置：`:97-100`

  当前代码（:97-100）：
  ```dart
  Future<void> delete(int id) async {
    await _dao.delete(id);
    await safeStorageDelete(_storage, key: 'connection_password_$id');
  }
  ```

  改为：
  ```dart
  Future<void> delete(int id) async {
    await _dao.delete(id);
    try {
      await safeStorageDelete(_storage, key: 'connection_password_$id');
    } catch (_) {
    }
  }
  ```

  边界裁决：
  - DAO 删除失败 → 异常正常抛出，UI 报"删除失败"（行为不变）
  - DAO 成功 + storage 成功 → 正常路径（行为不变）
  - DAO 成功 + storage 失败 → 静默吞掉异常，连接已删除 → UI 报"连接已删除"
  - 残留孤儿密码 key → 不影响功能（下次同 id 连接会覆盖，id 是 AUTOINCREMENT 不会复用）
  - 安全考量：孤儿 key 不泄露（仍在 secure_storage 加密中），仅占少量空间

- **[BUG-24-S4]** 测试连接密码为空时使用已存密码 (`status: new`)
  ```
  Given 编辑页密码字段为空
  When  用户点"测试连接"
  Then  使用 secure_storage 中已存密码发送验证请求
  否定断言:
    - 不用空字符串作为密码发送验证请求
    - 不改变密码字段非空时的测试行为
    - 不改变"保存"时密码为空的语义（保留旧密码）
  ```
  Code evidence: `connection_edit_screen.dart:229-238`（`_onTestConnection` 直接用 `_formController.password`）
  Code evidence: `connection_edit_screen.dart:286-288`（`_onSave` 中密码为空传 null → 保留旧密码）
  Code evidence: `connection_form.dart:183`（表单提示"留空保持不变"）

  **修改指令 — `lib/features/connection/connection_edit_screen.dart`（_onTestConnection）**

  位置：`:229-238`

  当前代码（:229-238）：
  ```dart
  Future<void> _onTestConnection() async {
    if (!_formController.validate()) return;

    final validator = ref.read(connectionValidatorProvider.notifier);
    await validator.validate(
      url: _formController.url,
      username: _formController.username,
      password: _formController.password,
      basePath: _formController.basePath,
    );
  }
  ```

  改为：
  ```dart
  Future<void> _onTestConnection() async {
    if (!_formController.validate()) return;

    var password = _formController.password;
    if (password.isEmpty) {
      final storedPassword = await safeStorageRead(
        ref.read(secureStorageProvider),
        key: 'connection_password_${widget.connectionId}',
      );
      password = storedPassword ?? '';
    }

    final validator = ref.read(connectionValidatorProvider.notifier);
    await validator.validate(
      url: _formController.url,
      username: _formController.username,
      password: password,
      basePath: _formController.basePath,
    );
  }
  ```

  边界裁决：
  - 密码字段非空 → 用表单密码（行为不变）
  - 密码字段为空 + storage 有值 → 用已存密码测试
  - 密码字段为空 + storage 无值（理论上不应发生，除非 storage 被清空）→ 用空串测试 → 可能 401（用户看到"密码错误"）→ 合理（数据不一致时应报错）
  - 需要 `secureStorageProvider` — 需确认已在 di/providers.dart 中定义（grep 确认已在用）
  - `safeStorageRead` 超时返回 null → `?? ''` → 空串验证，同上

  **测试文件位置：`test/features/connection/bug_bug24_repro_test.dart`**

---

## §4 不变量

- **[BUG-24-INV1]** `connection_edit_screen.dart` 不存在 `_originalConfig!` 强解包
  证据：`connection_edit_screen.dart:277`（修复目标）

- **[BUG-24-INV2]** `connection_service.dart` 的 `update()` 与 `save()` 有相同的原子性策略（失败回滚）
  证据：`connection_service.dart:38-65`（`save` rollback 标杆）→ `:73-84`（修复目标）

- **[BUG-24-INV3]** `connection_service.dart` 的 `delete()` 中 secure_storage 操作不 rethrow
  证据：`connection_service.dart:97-100`（修复目标）→ `storage_utils.dart:38-48`（`safeStorageDelete` rethrow — 需在调用方 catch）

- **[BUG-24-INV4]** 测试连接与保存的密码语义一致：空密码 = 使用已存密码
  证据：`connection_edit_screen.dart:286-288`（保存时空密码传 null = 保留旧密码）→ `:229-238`（测试连接需对齐）

---

## §5 测试规约

### 5.2 测试 ID 派生清单

```
BUG-24-S1           # _originalConfig 强解包消除
BUG-24-S2           # update() 原子性对齐
BUG-24-S3           # delete() storage best-effort
BUG-24-S4           # 测试连接密码语义对齐
BUG-24-INV1         # 无 _originalConfig! 强解包
BUG-24-INV2         # update/save 原子性一致
BUG-24-INV3         # delete storage 不 rethrow
BUG-24-INV4         # 测试/保存密码语义一致
```

### 5.4 测试文件位置

| 测试 ID | 文件路径 |
|---------|----------|
| BUG-24-S1 | `test/features/connection/bug_bug24_repro_test.dart` |
| BUG-24-S2 | `test/features/connection/bug_bug24_repro_test.dart` |
| BUG-24-S3 | `test/features/connection/bug_bug24_repro_test.dart` |
| BUG-24-S4 | `test/features/connection/bug_bug24_repro_test.dart` |
| BUG-24-INV1 | `test/features/connection/bug_bug24_repro_test.dart` |
| BUG-24-INV2 | `test/features/connection/bug_bug24_repro_test.dart` |
| BUG-24-INV3 | `test/features/connection/bug_bug24_repro_test.dart` |
| BUG-24-INV4 | `test/features/connection/bug_bug24_repro_test.dart` |

---

## §7 跨模块影响

| 模块 | 影响 | 说明 |
|------|------|------|
| CON | 正面 | 编辑/删除连接更健壮，错误提示更准确 |
| BRW | 无 | 不涉及浏览器 |
| PLY | 无 | 不涉及播放 |

---

## §8 平台特性与手动 QA

本功能不涉及平台原生特性。S1-S4 全部可在 `flutter test` 中用 `ProviderContainer` + fake 依赖验证。

---

## §9 dev-status.json 条目对照

见统一更新：`docs/dev/dev-status.json`。

---

## §10 changelog

- 2026-07-27: 创建 BUG-24 spec（基于 cr-20260724-0110.md CON5 + CON6 + CON7 + CON8）
