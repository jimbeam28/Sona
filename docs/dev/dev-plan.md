# 开发计划

> 基于 docs/test_refactor.md 测试覆盖空白填补与架构重构方案生成。
> 更新日期: 2026-06-10

---

## 待实现 — 测试覆盖空白与架构重构

### TREF-01 PlayerScreen 嵌入逻辑提取到 Domain 层

**来源**：新功能（架构重构） | **优先级**：P1
**涉及文件**：
- `lib/features/player/domain/player_screen_logic.dart`（新建）
- `lib/features/player/player_screen.dart`（修改）

**依赖**：无

**实现要点**：
- 新建 `player_screen_logic.dart`，包含 5 个纯 Dart 函数/枚举：
  - `sourceMatchesQueue(AudioPlayer, PlayQueue)` — 判断 player 当前 URI 是否匹配队列
  - `parentDir(String)` — 从文件路径提取父目录
  - `LoadFailureReason` 枚举 — `noConnection` / `noPassword` / `generic`
  - `classifyLoadFailure({hasActiveConnection, hasPassword})` — 分类加载失败原因
  - `errorMessageForLoadFailure(LoadFailureReason)` — 返回用户可见错误消息
  - `isAuthError(LoadFailureReason)` — 判断是否为认证错误
- 修改 `player_screen.dart`：
  - 删除 `_sourceMatchesQueue()`（L126-135），替换为 `sourceMatchesQueue(player, queue)`
  - 删除 `_parentDir()`（L226-230），替换为 `parentDir(path)`
  - 替换 `_runSerializedLoad()` 中的错误分类逻辑（L194-L216）为 `classifyLoadFailure()` + `errorMessageForLoadFailure()` + `isAuthError()`

**代码锚点**：
- `lib/features/player/player_screen.dart:126-135` — `_sourceMatchesQueue()` 当前实现（需提取）
  ```dart
  bool _sourceMatchesQueue(AudioPlayer player, PlayQueue queue) {
    final state = player.sequenceState;
    if (state == null) return false;
    final source = state.currentSource;
    if (source is UriAudioSource) {
      final decoded = Uri.decodeComponent(source.uri.path);
      return decoded.endsWith(queue.current.path);
    }
    return false;
  }
  ```
- `lib/features/player/player_screen.dart:226-230` — `_parentDir()` 当前实现（需提取）
  ```dart
  String _parentDir(String filePath) {
    final idx = filePath.lastIndexOf('/');
    if (idx <= 0) return '/';
    return filePath.substring(0, idx);
  }
  ```
- `lib/features/player/player_screen.dart:194-216` — 错误分类 if-else 链（需替换）
- `lib/features/progress/domain/progress_policy.dart` — 参考：纯函数提取模式

**测试用例**：TREF-01-T01 ~ TREF-01-T03
- TREF-01-T01: `flutter test test/features/player/` 全量回归通过
- TREF-01-T02: `flutter analyze` 0 issues
- TREF-01-T03: `player_screen_logic.dart` 零 Flutter/Riverpod import

**验收标准**：
- [ ] `player_screen_logic.dart` 不 import `flutter` 或 `flutter_riverpod`
- [ ] `player_screen.dart` 不再包含 `_sourceMatchesQueue` 和 `_parentDir` 方法
- [ ] `_runSerializedLoad` 中的错误分类逻辑已替换为纯函数调用
- [ ] `flutter test` 全量回归通过
- [ ] `flutter analyze` 0 issues
- [ ] `dart format` 无格式变更

---

### TREF-02 ConnectionEditScreen 验证门逻辑提取为纯函数

**来源**：新功能（架构重构） | **优先级**：P1
**涉及文件**：
- `lib/features/connection/domain/edit_screen_logic.dart`（新建）
- `lib/features/connection/connection_edit_screen.dart`（修改）

**依赖**：无

**实现要点**：
- 新建 `edit_screen_logic.dart`，包含：
  - `EditFieldChanges` 类 — 描述表单当前字段值（url/username/basePath/password）
  - `needsValidation({original, current, isAttached})` — 判断是否需要重新验证
  - `ValidationStatus` 枚举 — `idle` / `loading` / `success` / `error`
  - `canSave({needsRevalidation, validationStatus})` — 判断保存按钮是否启用
- 修改 `connection_edit_screen.dart`：
  - 删除 `_needsValidation()`（L191-198），替换为 `needsValidation(original, current, isAttached)`
  - 删除 `_canSave()`（L201-207），替换为 `canSave(needsRevalidation, validationStatus)`
  - 添加 `_mapValidationState()` 辅助函数将 Riverpod 状态映射为 `ValidationStatus` 枚举

**代码锚点**：
- `lib/features/connection/connection_edit_screen.dart:191-198` — `_needsValidation()` 当前实现（需提取）
  ```dart
  bool _needsValidation() {
    if (_originalConfig == null) return true;
    if (!_formController.isAttached) return false;
    return _formController.url != _originalConfig!.url ||
        _formController.username != _originalConfig!.username ||
        _formController.basePath != _originalConfig!.basePath ||
        _formController.password.isNotEmpty;
  }
  ```
- `lib/features/connection/connection_edit_screen.dart:201-207` — `_canSave()` 当前实现（需提取）
  ```dart
  bool _canSave(ConnectionValidationState validationState) {
    if (_needsValidation()) {
      return validationState is ValidationSuccess;
    }
    return true;
  }
  ```
- `lib/features/connection/domain/connection_validator.dart` — 参考：纯函数提取模式

**测试用例**：TREF-02-T01 ~ TREF-02-T03
- TREF-02-T01: `flutter test test/features/connection/` 全量回归通过
- TREF-02-T02: `flutter analyze` 0 issues
- TREF-02-T03: `edit_screen_logic.dart` 零 Flutter/Riverpod import

**验收标准**：
- [ ] `edit_screen_logic.dart` 不 import `flutter` 或 `flutter_riverpod`
- [ ] `connection_edit_screen.dart` 不再包含 `_needsValidation` 和 `_canSave` 方法
- [ ] `flutter test` 全量回归通过
- [ ] `flutter analyze` 0 issues
- [ ] `dart format` 无格式变更

---

### TREF-03 PlayerScreen 提取逻辑单元测试

**来源**：新功能（测试覆盖空白） | **优先级**：P1
**涉及文件**：
- `test/features/player/player_screen_logic_test.dart`（新建）

**依赖**：TREF-01

**实现要点**：
- 测试 `sourceMatchesQueue`：5 个场景（null sequenceState / 匹配路径 / 不匹配路径 / 非 UriAudioSource / URL 编码路径）
- 测试 `parentDir`：4 个场景（嵌套路径 / 根级文件 / 无前导斜杠 / 尾部斜杠）
- 测试 `classifyLoadFailure`：4 个场景（无连接 / 无密码 / 有连接有密码 / 无连接无密码优先级）
- 测试 `errorMessageForLoadFailure`：3 个场景（每种 reason 一条消息）
- 测试 `isAuthError`：3 个场景（noConnection→true / noPassword→true / generic→false）
- 共 19 个测试用例，编号 PSL-01 ~ PSL-19

**代码锚点**：
- `test/features/player/ref_08_test.dart` — 参考：纯函数测试模式
- `test/features/player/ref_14_test.dart` — 参考：PlaybackOrchestrator 测试模式

**测试用例**：TREF-03-T01 ~ TREF-03-T19
- TREF-03-T01 (PSL-01): `sourceMatchesQueue` sequenceState 为 null → false
- TREF-03-T02 (PSL-02): `sourceMatchesQueue` URI 匹配 → true
- TREF-03-T03 (PSL-03): `sourceMatchesQueue` URI 不匹配 → false
- TREF-03-T04 (PSL-04): `sourceMatchesQueue` 非 UriAudioSource → false
- TREF-03-T05 (PSL-05): `sourceMatchesQueue` URL 编码路径匹配 → true
- TREF-03-T06 (PSL-06): `parentDir` 嵌套路径 → 父目录
- TREF-03-T07 (PSL-07): `parentDir` 根级文件 → `/`
- TREF-03-T08 (PSL-08): `parentDir` 无前导斜杠 → `/`
- TREF-03-T09 (PSL-09): `parentDir` 尾部斜杠 → 保留
- TREF-03-T10 (PSL-10): `classifyLoadFailure` 无连接 → noConnection
- TREF-03-T11 (PSL-11): `classifyLoadFailure` 有连接无密码 → noPassword
- TREF-03-T12 (PSL-12): `classifyLoadFailure` 有连接有密码 → generic
- TREF-03-T13 (PSL-13): `classifyLoadFailure` 无连接无密码 → noConnection（优先级）
- TREF-03-T14 (PSL-14): `errorMessageForLoadFailure` noConnection → "没有活跃的连接"
- TREF-03-T15 (PSL-15): `errorMessageForLoadFailure` noPassword → "密码未保存"
- TREF-03-T16 (PSL-16): `errorMessageForLoadFailure` generic → "加载失败"
- TREF-03-T17 (PSL-17): `isAuthError` noConnection → true
- TREF-03-T18 (PSL-18): `isAuthError` noPassword → true
- TREF-03-T19 (PSL-19): `isAuthError` generic → false

**验收标准**：
- [ ] 19 个测试用例全部通过
- [ ] `flutter test test/features/player/player_screen_logic_test.dart` 通过
- [ ] `flutter analyze` 0 issues

---

### TREF-04 ConnectionEditScreen 提取逻辑单元测试

**来源**：新功能（测试覆盖空白） | **优先级**：P1
**涉及文件**：
- `test/features/connection/edit_screen_logic_test.dart`（新建）

**依赖**：TREF-02

**实现要点**：
- 测试 `needsValidation`：8 个场景（null original / not attached / no changes / URL changed / username changed / basePath changed / password provided / only name changed）
- 测试 `canSave`：6 个场景（no revalidation → true / revalidation+idle → false / revalidation+loading → false / revalidation+success → true / revalidation+error → false / no revalidation+error → true）
- 共 14 个测试用例，编号 ESL-01 ~ ESL-14

**代码锚点**：
- `test/features/connection/ref_21_test.dart` — 参考：纯验证函数测试模式

**测试用例**：TREF-04-T01 ~ TREF-04-T14
- TREF-04-T01 (ESL-01): `needsValidation` null original → true
- TREF-04-T02 (ESL-02): `needsValidation` not attached → false
- TREF-04-T03 (ESL-03): `needsValidation` no changes → false
- TREF-04-T04 (ESL-04): `needsValidation` URL changed → true
- TREF-04-T05 (ESL-05): `needsValidation` username changed → true
- TREF-04-T06 (ESL-06): `needsValidation` basePath changed → true
- TREF-04-T07 (ESL-07): `needsValidation` password provided → true
- TREF-04-T08 (ESL-08): `needsValidation` only name changed → false
- TREF-04-T09 (ESL-09): `canSave` no revalidation → true
- TREF-04-T10 (ESL-10): `canSave` revalidation+idle → false
- TREF-04-T11 (ESL-11): `canSave` revalidation+loading → false
- TREF-04-T12 (ESL-12): `canSave` revalidation+success → true
- TREF-04-T13 (ESL-13): `canSave` revalidation+error → false
- TREF-04-T14 (ESL-14): `canSave` no revalidation+error → true

**验收标准**：
- [ ] 14 个测试用例全部通过
- [ ] `flutter test test/features/connection/edit_screen_logic_test.dart` 通过
- [ ] `flutter analyze` 0 issues

---

### TREF-05 OnboardingPage 重定向逻辑测试

**来源**：新功能（测试覆盖空白） | **优先级**：P2
**涉及文件**：
- `test/features/home/onboarding_test.dart`（新建）

**依赖**：无

**实现要点**：
- 使用 `ProviderScope` 的 `overrides` 注入 mock 的 `connectionListProvider` 和 `startupValidationProvider`
- 测试 3 条重定向路径 + loading + error 共 5 个场景
- 路由跳转验证使用 `GoRouter` 的 `navigatorKey` 或 mock
- `addPostFrameCallback` 需要 `await tester.pumpAndSettle()` 等待

**代码锚点**：
- `lib/app/onboarding.dart:13-77` — `OnboardingPage.build()` 重定向逻辑（需测试）
  ```dart
  // 3 条路径：
  // 1. connections.isEmpty → _onboardingScaffold (CTA)
  // 2. connections.isNotEmpty + validation success → context.go('/browser')
  // 3. connections.isNotEmpty + validation failure → context.go('/connection')
  ```
- `test/features/home/home_screen_test.dart` — 参考：HomeScreen Widget 测试模式
- `test/features/connection/con_01_test.dart` — 参考：Provider override 模式

**测试用例**：TREF-05-T01 ~ TREF-05-T05
- TREF-05-T01 (ONB-01): 空连接列表 → 显示 CTA "添加第一个 NAS 连接"
- TREF-05-T02 (ONB-02): 连接存在 + 验证成功 → 路由跳转 /browser
- TREF-05-T03 (ONB-03): 连接存在 + 验证失败 → 路由跳转 /connection
- TREF-05-T04 (ONB-04): connectionListProvider loading → 显示 CircularProgressIndicator
- TREF-05-T05 (ONB-05): connectionListProvider error → 显示 OnboardingErrorView

**验收标准**：
- [ ] 5 个测试用例全部通过
- [ ] `flutter test test/features/home/onboarding_test.dart` 通过
- [ ] `flutter analyze` 0 issues

---

### TREF-06 DatabaseHelper 迁移专项测试

**来源**：新功能（测试覆盖空白） | **优先级**：P2
**涉及文件**：
- `test/features/coverage/db_migration_test.dart`（新建）

**依赖**：无

**实现要点**：
- 使用 `sqflite_ffi` 创建内存数据库，不依赖 `DatabaseHelper` 单例
- 手动执行 SQL 模拟 v1 和 v2 schema
- 通过 `openDatabase` 的 `version`/`onCreate`/`onUpgrade` 参数模拟迁移
- 查询 `sqlite_master` 验证表/索引存在性

**代码锚点**：
- `lib/core/database/database_helper.dart:32-68` — `_onCreate` v2 全量建表（需测试）
- `lib/core/database/database_helper.dart:70-74` — `_onUpgrade` v1→v2 迁移（需测试）
- `lib/core/database/database_helper.dart:76-99` — `_createPlaylistTables` 播放单表创建
- `test/features/playlist/ply_10_test.dart` — 参考：DAO 测试中使用 sqflite_ffi 的模式

**测试用例**：TREF-06-T01 ~ TREF-06-T06
- TREF-06-T01 (DB-MIG-01): v1 schema 有 connections 和 play_progress 表，无 playlists 表
- TREF-06-T02 (DB-MIG-02): v2 schema 有全部 4 张表
- TREF-06-T03 (DB-MIG-03): v1→v2 升级后 connections 数据保留
- TREF-06-T04 (DB-MIG-04): v1→v2 升级后 playlist 索引创建
- TREF-06-T05 (DB-MIG-05): v2 全新安装包含所有索引
- TREF-06-T06 (DB-MIG-06): 创建时 foreign_keys 已启用

**验收标准**：
- [ ] 6 个测试用例全部通过
- [ ] `flutter test test/features/coverage/db_migration_test.dart` 通过
- [ ] `flutter analyze` 0 issues
