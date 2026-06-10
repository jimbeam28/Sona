# 测试覆盖空白填补与架构重构方案

> 生成日期：2026-06-10
> 基于：docs/test_ana.md 分析结果

---

## 目录

1. [方案总览](#方案总览)
2. [任务 1：OnboardingPage 重定向逻辑测试](#任务-1onboardingpage-重定向逻辑测试)
3. [任务 2：DatabaseHelper 迁移专项测试](#任务-2databasehelper-迁移专项测试)
4. [任务 3：PlayerScreen 嵌入逻辑提取到 Domain 层](#任务-3playerscreen-嵌入逻辑提取到-domain-层)
5. [任务 4：ConnectionEditScreen 验证门逻辑提取为纯函数](#任务-4connectioneditscreen-验证门逻辑提取为纯函数)
6. [任务 5：为提取后的纯函数编写独立单元测试](#任务-5为提取后的纯函数编写独立单元测试)
7. [实施顺序与依赖关系](#实施顺序与依赖关系)

---

## 方案总览

本方案解决 4 个覆盖空白和 2 个架构问题，共 5 个任务：

| 任务 | 类型 | 优先级 | 影响范围 | 新增测试 |
|------|------|-------|---------|---------|
| 1. OnboardingPage 测试 | 覆盖空白 | 中 | `lib/app/onboarding.dart` | 5 个 Widget 测试 |
| 2. DatabaseHelper 迁移测试 | 覆盖空白 | 中 | `lib/core/database/database_helper.dart` | 4 个单元测试 |
| 3. PlayerScreen 逻辑提取 | 架构重构 | 高 | `lib/features/player/player_screen.dart` + 新文件 | 8 个单元测试 |
| 4. ConnectionEditScreen 逻辑提取 | 架构重构 | 中 | `lib/features/connection/connection_edit_screen.dart` + 新文件 | 6 个单元测试 |
| 5. 提取后纯函数测试 | 覆盖空白 | 高 | 任务 3/4 产出的新文件 | 14 个单元测试 |

**核心原则**：
- 提取的函数必须是**纯 Dart**，零 Flutter/Riverpod 依赖
- 新测试文件放在对应 feature 的目录下，命名遵循 `{source}_test.dart` 惯例
- 提取后原 Widget 调用提取后的纯函数，行为不变

---

## 任务 1：OnboardingPage 重定向逻辑测试

### 问题分析

`lib/app/onboarding.dart` 包含 3 条重定向路径，均通过 `WidgetsBinding.instance.addPostFrameCallback` 执行：

1. **连接列表为空** → 显示引导 CTA（`_onboardingScaffold`）
2. **连接存在 + 验证成功** → `context.go('/browser')`
3. **连接存在 + 验证失败** → `context.go('/connection')`

当前无任何测试覆盖这 3 条路径。

### 测试方案

创建 `test/features/home/onboarding_test.dart`（放在 home 目录下，因为 OnboardingPage 是 app 启动入口的一部分）：

```dart
// test/features/home/onboarding_test.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sona/app/onboarding.dart';
import 'package:sona/features/connection/connection_provider.dart';
import 'package:sona/shared/models/connection_config.dart';
import 'package:sona/core/network/webdav_client.dart';

// ── Test cases ─────────────────────────────────────────────────────────────

void main() {
  group('OnboardingPage redirect logic', () {
    testWidgets('ONB-01: empty connection list shows CTA', (tester) async {
      // connectionListProvider 返回空列表
      // 期望：显示 "添加第一个 NAS 连接" 文本和 "添加连接" 按钮
      // 不发生路由跳转
    });

    testWidgets('ONB-02: connections exist + validation success → /browser',
        (tester) async {
      // connectionListProvider 返回 [validConnection]
      // startupValidationProvider 返回 ValidationSuccess
      // 期望：postFrameCallback 后路由为 /browser
      // 验证 restoreStartupProgressProvider 被读取
    });

    testWidgets('ONB-03: connections exist + validation failure → /connection',
        (tester) async {
      // connectionListProvider 返回 [validConnection]
      // startupValidationProvider 返回 ValidationError
      // 期望：postFrameCallback 后路由为 /connection
    });

    testWidgets('ONB-04: connectionListProvider loading shows spinner',
        (tester) async {
      // connectionListProvider 处于 loading 状态
      // 期望：显示 CircularProgressIndicator
    });

    testWidgets('ONB-05: connectionListProvider error shows error view',
        (tester) async {
      // connectionListProvider 抛出异常
      // 期望：显示 OnboardingErrorView，包含 "数据加载失败" 文本和 "重试" 按钮
    });
  });
}
```

### 实现要点

- 使用 `ProviderScope` 的 `overrides` 注入 mock 的 `connectionListProvider` 和 `startupValidationProvider`
- 路由跳转验证：使用 `GoRouter` 的 `navigatorKey` 或 mock `GoRouter.of(context).go()`
- 由于 `addPostFrameCallback` 在 `build` 之后执行，需要 `await tester.pumpAndSettle()` 等待回调完成

### 依赖

- 需要 `mocktail` 包（或使用 Riverpod 的 `ProviderOverride` 直接覆盖）
- 不需要修改源码，纯 Widget 测试

---

## 任务 2：DatabaseHelper 迁移专项测试

### 问题分析

`lib/core/database/database_helper.dart` 包含：
- `_onCreate`：创建 v2 全量表结构（connections + play_progress + playlists + playlist_tracks）
- `_onUpgrade`：v1→v2 迁移（仅创建 playlists + playlist_tracks 表）

当前迁移逻辑仅被 `ply_10_test.dart` 间接覆盖（通过 DAO 操作验证表存在），缺少：
- 迁移后表结构完整性验证
- 迁移后已有数据保留验证
- 迁移后索引存在性验证

### 测试方案

创建 `test/features/coverage/db_migration_test.dart`：

```dart
// test/features/coverage/db_migration_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Database db;

  setUp(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  tearDown(() async {
    await db.close();
  });

  group('DatabaseHelper migration v1 → v2', () {
    test('DB-MIG-01: v1 schema has connections and play_progress tables', () async {
      // 用 sqflite_ffi 创建内存数据库，手动执行 v1 _onCreate 的 SQL
      // 验证 connections 和 play_progress 表存在
      // 验证 playlists 和 playlist_tracks 表不存在
    });

    test('DB-MIG-02: v2 schema has all 4 tables', () async {
      // 创建 v2 数据库（调用完整的 _onCreate）
      // 验证 connections、play_progress、playlists、playlist_tracks 表均存在
    });

    test('DB-MIG-03: upgrade from v1 preserves connections data', () async {
      // 1. 创建 v1 数据库
      // 2. 插入一条 connection 记录
      // 3. 关闭数据库
      // 4. 以 v2 打开同一数据库（触发 _onUpgrade）
      // 5. 验证 connection 记录仍存在
      // 6. 验证 playlists 表已创建且为空
    });

    test('DB-MIG-04: upgrade from v1 creates playlist indexes', () async {
      // 创建 v1 数据库 → 升级到 v2
      // 查询 sqlite_master 验证 idx_playlist_tracks_playlist_id 索引存在
    });

    test('DB-MIG-05: v2 fresh install includes all indexes', () async {
      // 直接创建 v2 数据库
      // 验证 idx_progress_lookup 和 idx_playlist_tracks_playlist_id 索引均存在
    });

    test('DB-MIG-06: foreign keys enabled on create', () async {
      // 创建 v2 数据库
      // 执行 PRAGMA foreign_keys 验证返回 1
    });
  });
}
```

### 实现要点

- 使用 `sqflite_ffi` 创建内存数据库，不依赖 `DatabaseHelper` 单例
- 手动执行 SQL 来模拟 v1 和 v2 的 schema
- 通过 `openDatabase` 的 `version`、`onCreate`、`onUpgrade` 参数模拟迁移流程
- 查询 `sqlite_master` 表验证表/索引存在性

### 依赖

- 项目已有 `sqflite_ffi` 依赖（测试环境）
- 不需要修改源码

---

## 任务 3：PlayerScreen 嵌入逻辑提取到 Domain 层

### 问题分析

`lib/features/player/player_screen.dart` 的 `_PlayerScreenState` 包含 3 个可测试的纯逻辑方法：

| 方法 | 当前行号 | 逻辑 | 提取价值 |
|------|---------|------|---------|
| `_sourceMatchesQueue()` | L126-135 | 判断 player 当前加载的 URI 是否匹配队列当前文件 | 高 — 核心判断逻辑 |
| `_parentDir()` | L226-230 | 从文件路径提取父目录 | 中 — 路径操作工具 |
| `_runSerializedLoad()` 中的错误分类 | L150-224 | 根据失败原因分类错误消息 | 高 — 错误处理逻辑 |

`_runSerializedLoad()` 整体不适合直接提取（依赖 `mounted`、`setState`、`ref.read`），但其**错误分类逻辑**可以提取为纯函数。

### 提取方案

#### 3.1 新建 `lib/features/player/domain/player_screen_logic.dart`

```dart
// lib/features/player/domain/player_screen_logic.dart
// Pure-Dart helper functions extracted from PlayerScreen state.
// Zero Flutter / Riverpod dependencies.

import 'package:just_audio/just_audio.dart';
import '../../../shared/models/play_queue.dart';

/// Returns `true` when the player's loaded source URI matches [queue]'s
/// current file path.
///
/// This is used to decide whether a reload is needed when the PlayerScreen
/// is re-opened — if the source already matches, we skip the load.
bool sourceMatchesQueue(AudioPlayer player, PlayQueue queue) {
  final state = player.sequenceState;
  if (state == null) return false;
  final source = state.currentSource;
  if (source is UriAudioSource) {
    final decoded = Uri.decodeComponent(source.uri.path);
    return decoded.endsWith(queue.current.path);
  }
  return false;
}

/// Extracts the parent directory from a file path.
///
/// - `/music/artist/song.mp3` → `/music/artist`
/// - `/song.mp3` → `/`
/// - `song.mp3` → `/`
String parentDir(String filePath) {
  final idx = filePath.lastIndexOf('/');
  if (idx <= 0) return '/';
  return filePath.substring(0, idx);
}

/// Describes the outcome of a load-failure classification.
enum LoadFailureReason {
  /// No active connection configured.
  noConnection,

  /// Password not found in secure storage.
  noPassword,

  /// Generic load failure (e.g. network error, audio source error).
  generic,
}

/// Classifies a load failure by inspecting the connection and password state.
///
/// Returns `null` when the failure cannot be classified (caller should treat
/// as [LoadFailureReason.generic]).
///
/// Parameters:
/// - [hasActiveConnection]: whether an active connection exists
/// - [hasPassword]: whether the password is available in secure storage
LoadFailureReason classifyLoadFailure({
  required bool hasActiveConnection,
  required bool hasPassword,
}) {
  if (!hasActiveConnection) return LoadFailureReason.noConnection;
  if (!hasPassword) return LoadFailureReason.noPassword;
  return LoadFailureReason.generic;
}

/// Returns a user-facing error message for the given [reason].
String errorMessageForLoadFailure(LoadFailureReason reason) {
  switch (reason) {
    case LoadFailureReason.noConnection:
      return '没有活跃的连接';
    case LoadFailureReason.noPassword:
      return '密码未保存';
    case LoadFailureReason.generic:
      return '加载失败';
  }
}

/// Returns `true` when the error is an authentication-related error that
/// should show the "检查连接" button.
bool isAuthError(LoadFailureReason reason) {
  return reason == LoadFailureReason.noConnection ||
      reason == LoadFailureReason.noPassword;
}
```

#### 3.2 修改 `lib/features/player/player_screen.dart`

替换 `_sourceMatchesQueue` 和 `_parentDir` 为调用提取后的函数：

```dart
// player_screen.dart 顶部新增 import
import 'domain/player_screen_logic.dart';

// _PlayerScreenState 中删除 _sourceMatchesQueue 和 _parentDir 方法，
// 改为直接调用：
// - sourceMatchesQueue(player, queue)  替代  _sourceMatchesQueue(player, queue)
// - parentDir(path)  替代  _parentDir(path)
```

`_runSerializedLoad` 中的错误分类逻辑（L194-L216）替换为：

```dart
// 替换原来的 if-else 链
final activeConn = ref.read(activeConnectionProvider).valueOrNull;
final storage = ref.read(secureStorageProvider);
String? pw;
if (activeConn != null) {
  pw = await safeStorageRead(storage,
      key: 'connection_password_${activeConn.id}');
}
final reason = classifyLoadFailure(
  hasActiveConnection: activeConn != null,
  hasPassword: pw != null && pw.isNotEmpty,
);
_safeSetState(() {
  _loadState = PlayerLoadState.error(
    errorMessageForLoadFailure(reason),
    isAuthError: isAuthError(reason),
  );
});
```

### 行为不变性

- `sourceMatchesQueue` 逻辑与原 `_sourceMatchesQueue` 完全一致
- `parentDir` 逻辑与原 `_parentDir` 完全一致
- `classifyLoadFailure` + `errorMessageForLoadFailure` + `isAuthError` 组合与原 if-else 链的错误消息和 `isAuthError` 标志完全一致
- Widget 层不再包含可独立测试的业务逻辑

---

## 任务 4：ConnectionEditScreen 验证门逻辑提取为纯函数

### 问题分析

`lib/features/connection/connection_edit_screen.dart` 的 `_ConnectionEditScreenState` 包含 2 个纯逻辑方法：

| 方法 | 当前行号 | 逻辑 | 提取价值 |
|------|---------|------|---------|
| `_needsValidation()` | L191-198 | 判断表单字段是否变更到需要重新验证 | 高 — 核心验证门逻辑 |
| `_canSave()` | L201-207 | 判断保存按钮是否应启用 | 高 — UI 状态决策 |

### 提取方案

#### 4.1 新建 `lib/features/connection/domain/edit_screen_logic.dart`

```dart
// lib/features/connection/domain/edit_screen_logic.dart
// Pure-Dart helper functions extracted from ConnectionEditScreen state.
// Zero Flutter / Riverpod dependencies.

import '../../../shared/models/connection_config.dart';

/// Describes which fields the user has changed in the edit form.
class EditFieldChanges {
  final String url;
  final String username;
  final String basePath;
  final String password; // empty means "not changed"

  const EditFieldChanges({
    required this.url,
    required this.username,
    required this.basePath,
    required this.password,
  });
}

/// Returns `true` when the user modified a field that affects connectivity
/// (URL, username, basePath, or password) and therefore must re-validate
/// before saving.
///
/// [original] is the connection config loaded from the database.
/// [current] describes the current form field values.
/// [isAttached] is whether the form controller is attached to a widget.
bool needsValidation({
  required ConnectionConfig? original,
  required EditFieldChanges current,
  required bool isAttached,
}) {
  if (original == null) return true; // safety net
  if (!isAttached) return false;
  return current.url != original.url ||
      current.username != original.username ||
      current.basePath != original.basePath ||
      current.password.isNotEmpty;
}

/// Returns `true` when the save button should be enabled.
///
/// [needsRevalidation] is the result of [needsValidation].
/// [validationState] is the current validation state from the provider.
/// For the state type, we use a simple enum to avoid importing Riverpod types.
enum ValidationStatus { idle, loading, success, error }

bool canSave({
  required bool needsRevalidation,
  required ValidationStatus validationStatus,
}) {
  if (needsRevalidation) {
    return validationStatus == ValidationStatus.success;
  }
  // Only the display name changed — no validation required (CON-T30).
  return true;
}
```

#### 4.2 修改 `lib/features/connection/connection_edit_screen.dart`

替换 `_needsValidation` 和 `_canSave` 为调用提取后的函数：

```dart
// connection_edit_screen.dart 顶部新增 import
import 'domain/edit_screen_logic.dart';

// _ConnectionEditScreenState 中删除 _needsValidation 和 _canSave 方法，
// 改为直接调用：

// 在 _onSave 和 build 中使用：
final changes = EditFieldChanges(
  url: _formController.url,
  username: _formController.username,
  basePath: _formController.basePath,
  password: _formController.password,
);
final needsRevalidation = needsValidation(
  original: _originalConfig,
  current: changes,
  isAttached: _formController.isAttached,
);
final canSaveResult = canSave(
  needsRevalidation: needsRevalidation,
  validationStatus: _mapValidationState(validationState),
);
```

需要添加一个映射函数将 Riverpod 状态类型映射为纯 Dart 枚举：

```dart
ValidationStatus _mapValidationState(ConnectionValidationState state) {
  if (state is ValidationIdle) return ValidationStatus.idle;
  if (state is ValidationLoading) return ValidationStatus.loading;
  if (state is ValidationSuccess) return ValidationStatus.success;
  return ValidationStatus.error;
}
```

### 行为不变性

- `needsValidation` 逻辑与原 `_needsValidation` 完全一致
- `canSave` 逻辑与原 `_canSave` 完全一致
- Widget 层仅保留映射调用，不再包含可独立测试的决策逻辑

---

## 任务 5：为提取后的纯函数编写独立单元测试

### 5.1 PlayerScreen 提取逻辑测试

创建 `test/features/player/player_screen_logic_test.dart`：

```dart
// test/features/player/player_screen_logic_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:sona/features/player/domain/player_screen_logic.dart';

void main() {
  group('sourceMatchesQueue', () {
    test('PSL-01: sequenceState is null returns false', () {
      // 构造一个 sequenceState 为 null 的 AudioPlayer
      // 期望：返回 false
    });

    test('PSL-02: currentSource is UriAudioSource with matching path', () {
      // 构造 URI 为 http://host/music/song.mp3 的 source
      // queue.current.path 为 /music/song.mp3
      // 期望：返回 true（decoded path 以 queue path 结尾）
    });

    test('PSL-03: currentSource is UriAudioSource with non-matching path', () {
      // source URI path 为 /music/other.mp3
      // queue.current.path 为 /music/song.mp3
      // 期望：返回 false
    });

    test('PSL-04: currentSource is not UriAudioSource returns false', () {
      // 构造 ProgressiveAudioSource（非 UriAudioSource）
      // 期望：返回 false
    });

    test('PSL-05: URL-encoded path matches decoded queue path', () {
      // source URI path 为 /music/%E4%B8%AD%E6%96%87.mp3
      // queue.current.path 为 /music/中文.mp3
      // 期望：返回 true
    });
  });

  group('parentDir', () {
    test('PSL-06: nested path returns parent', () {
      expect(parentDir('/music/artist/song.mp3'), '/music/artist');
    });

    test('PSL-07: root-level file returns /', () {
      expect(parentDir('/song.mp3'), '/');
    });

    test('PSL-08: no leading slash returns /', () {
      expect(parentDir('song.mp3'), '/');
    });

    test('PSL-09: trailing slash preserved', () {
      expect(parentDir('/music/'), '/music');
    });
  });

  group('classifyLoadFailure', () {
    test('PSL-10: no connection → noConnection', () {
      expect(
        classifyLoadFailure(hasActiveConnection: false, hasPassword: true),
        LoadFailureReason.noConnection,
      );
    });

    test('PSL-11: has connection, no password → noPassword', () {
      expect(
        classifyLoadFailure(hasActiveConnection: true, hasPassword: false),
        LoadFailureReason.noPassword,
      );
    });

    test('PSL-12: has connection, has password → generic', () {
      expect(
        classifyLoadFailure(hasActiveConnection: true, hasPassword: true),
        LoadFailureReason.generic,
      );
    });

    test('PSL-13: no connection, no password → noConnection (priority)', () {
      // 无连接优先于无密码
      expect(
        classifyLoadFailure(hasActiveConnection: false, hasPassword: false),
        LoadFailureReason.noConnection,
      );
    });
  });

  group('errorMessageForLoadFailure', () {
    test('PSL-14: noConnection message', () {
      expect(errorMessageForLoadFailure(LoadFailureReason.noConnection), '没有活跃的连接');
    });

    test('PSL-15: noPassword message', () {
      expect(errorMessageForLoadFailure(LoadFailureReason.noPassword), '密码未保存');
    });

    test('PSL-16: generic message', () {
      expect(errorMessageForLoadFailure(LoadFailureReason.generic), '加载失败');
    });
  });

  group('isAuthError', () {
    test('PSL-17: noConnection is auth error', () {
      expect(isAuthError(LoadFailureReason.noConnection), true);
    });

    test('PSL-18: noPassword is auth error', () {
      expect(isAuthError(LoadFailureReason.noPassword), true);
    });

    test('PSL-19: generic is NOT auth error', () {
      expect(isAuthError(LoadFailureReason.generic), false);
    });
  });
}
```

### 5.2 ConnectionEditScreen 提取逻辑测试

创建 `test/features/connection/edit_screen_logic_test.dart`：

```dart
// test/features/connection/edit_screen_logic_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:sona/features/connection/domain/edit_screen_logic.dart';
import 'package:sona/shared/models/connection_config.dart';

void main() {
  final original = ConnectionConfig(
    id: 1,
    name: 'My NAS',
    url: 'http://192.168.1.1:5005',
    username: 'admin',
    basePath: '/music',
    isActive: true,
    createdAt: DateTime(2024),
    updatedAt: DateTime(2024),
  );

  group('needsValidation', () {
    test('ESL-01: original is null → true (safety net)', () {
      expect(
        needsValidation(
          original: null,
          current: EditFieldChanges(url: '', username: '', basePath: '', password: ''),
          isAttached: true,
        ),
        true,
      );
    });

    test('ESL-02: not attached → false', () {
      expect(
        needsValidation(
          original: original,
          current: EditFieldChanges(url: 'different', username: 'admin', basePath: '/music', password: ''),
          isAttached: false,
        ),
        false,
      );
    });

    test('ESL-03: no changes → false', () {
      expect(
        needsValidation(
          original: original,
          current: EditFieldChanges(
            url: original.url,
            username: original.username,
            basePath: original.basePath,
            password: '',
          ),
          isAttached: true,
        ),
        false,
      );
    });

    test('ESL-04: URL changed → true', () {
      expect(
        needsValidation(
          original: original,
          current: EditFieldChanges(
            url: 'http://10.0.0.1:5005',
            username: original.username,
            basePath: original.basePath,
            password: '',
          ),
          isAttached: true,
        ),
        true,
      );
    });

    test('ESL-05: username changed → true', () {
      expect(
        needsValidation(
          original: original,
          current: EditFieldChanges(
            url: original.url,
            username: 'root',
            basePath: original.basePath,
            password: '',
          ),
          isAttached: true,
        ),
        true,
      );
    });

    test('ESL-06: basePath changed → true', () {
      expect(
        needsValidation(
          original: original,
          current: EditFieldChanges(
            url: original.url,
            username: original.username,
            basePath: '/audiobooks',
            password: '',
          ),
          isAttached: true,
        ),
        true,
      );
    });

    test('ESL-07: password provided → true', () {
      expect(
        needsValidation(
          original: original,
          current: EditFieldChanges(
            url: original.url,
            username: original.username,
            basePath: original.basePath,
            password: 'newpassword',
          ),
          isAttached: true,
        ),
        true,
      );
    });

    test('ESL-08: only name changed (not in EditFieldChanges) → false', () {
      // name 变更不触发验证 — EditFieldChanges 不包含 name 字段
      expect(
        needsValidation(
          original: original,
          current: EditFieldChanges(
            url: original.url,
            username: original.username,
            basePath: original.basePath,
            password: '',
          ),
          isAttached: true,
        ),
        false,
      );
    });
  });

  group('canSave', () {
    test('ESL-09: no revalidation needed → always true', () {
      expect(
        canSave(
          needsRevalidation: false,
          validationStatus: ValidationStatus.idle,
        ),
        true,
      );
    });

    test('ESL-10: revalidation needed + idle → false', () {
      expect(
        canSave(
          needsRevalidation: true,
          validationStatus: ValidationStatus.idle,
        ),
        false,
      );
    });

    test('ESL-11: revalidation needed + loading → false', () {
      expect(
        canSave(
          needsRevalidation: true,
          validationStatus: ValidationStatus.loading,
        ),
        false,
      );
    });

    test('ESL-12: revalidation needed + success → true', () {
      expect(
        canSave(
          needsRevalidation: true,
          validationStatus: ValidationStatus.success,
        ),
        true,
      );
    });

    test('ESL-13: revalidation needed + error → false', () {
      expect(
        canSave(
          needsRevalidation: true,
          validationStatus: ValidationStatus.error,
        ),
        false,
      );
    });

    test('ESL-14: no revalidation + error → true (name-only change)', () {
      expect(
        canSave(
          needsRevalidation: false,
          validationStatus: ValidationStatus.error,
        ),
        true,
      );
    });
  });
}
```

### 测试覆盖对照

| 提取函数 | 测试 ID | 测试场景数 |
|---------|---------|-----------|
| `sourceMatchesQueue` | PSL-01~05 | 5 |
| `parentDir` | PSL-06~09 | 4 |
| `classifyLoadFailure` | PSL-10~13 | 4 |
| `errorMessageForLoadFailure` | PSL-14~16 | 3 |
| `isAuthError` | PSL-17~19 | 3 |
| `needsValidation` | ESL-01~08 | 8 |
| `canSave` | ESL-09~14 | 6 |
| **合计** | | **33** |

---

## 实施顺序与依赖关系

```
任务 1 (OnboardingPage 测试)  ── 独立，可立即开始
任务 2 (DB 迁移测试)          ── 独立，可立即开始
任务 3 (PlayerScreen 提取)    ── 独立，可立即开始
  └── 任务 5a (PSL 测试)      ── 依赖任务 3 完成
任务 4 (ConnectionEditScreen 提取) ── 独立，可立即开始
  └── 任务 5b (ESL 测试)      ── 依赖任务 4 完成
```

**建议执行顺序**：

1. **任务 3 + 5a**（优先级最高）— PlayerScreen 是最复杂的 Widget，提取后降低维护成本
2. **任务 4 + 5b**（优先级高）— ConnectionEditScreen 提取工作量小，收益明确
3. **任务 2**（优先级中）— 迁移测试是安全网，防止未来 schema 变更破坏数据
4. **任务 1**（优先级中）— OnboardingPage 测试确保首次用户体验路径正确

**预估工作量**：

| 任务 | 新增文件 | 修改文件 | 新增测试 | 预估耗时 |
|------|---------|---------|---------|---------|
| 1 | 1 | 0 | 5 | 0.5h |
| 2 | 1 | 0 | 6 | 0.5h |
| 3 | 1 | 1 | 0 | 0.5h |
| 4 | 1 | 1 | 0 | 0.5h |
| 5 | 2 | 0 | 33 | 1h |
| **合计** | **6** | **2** | **44** | **3h** |

---

## 附录：文件变更清单

### 新增文件（6 个）

| 文件路径 | 用途 |
|---------|------|
| `lib/features/player/domain/player_screen_logic.dart` | PlayerScreen 提取的纯函数 |
| `lib/features/connection/domain/edit_screen_logic.dart` | ConnectionEditScreen 提取的纯函数 |
| `test/features/home/onboarding_test.dart` | OnboardingPage Widget 测试 |
| `test/features/coverage/db_migration_test.dart` | 数据库迁移专项测试 |
| `test/features/player/player_screen_logic_test.dart` | PlayerScreen 纯函数单元测试 |
| `test/features/connection/edit_screen_logic_test.dart` | ConnectionEditScreen 纯函数单元测试 |

### 修改文件（2 个）

| 文件路径 | 变更内容 |
|---------|---------|
| `lib/features/player/player_screen.dart` | 删除 `_sourceMatchesQueue`/`_parentDir`，替换 `_runSerializedLoad` 中的错误分类逻辑为调用纯函数 |
| `lib/features/connection/connection_edit_screen.dart` | 删除 `_needsValidation`/`_canSave`，替换为调用纯函数 |

### 不变文件

所有现有测试文件**不需要修改** — 提取是纯重构，行为不变。
