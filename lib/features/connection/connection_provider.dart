// lib/features/connection/connection_provider.dart
// Thin Riverpod glue: providers that wire dependencies into the domain layer.
//
// All business logic lives in [ConnectionService] (domain/connection_service.dart)
// and [ConnectionValidatorNotifier] (which delegates WebDAV probing to
// [WebDavClientInterface]).  This file only exposes Riverpod providers with
// stable public APIs so the rest of the app can `ref.watch` / `ref.read` them.

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../core/contracts/database_contract.dart';
import '../../core/contracts/storage_contract.dart';
// REF-17-S2: 异常类型改经 database_contract 获得；本 import 仅剩组合根
// 构造 ConnectionDao 具体类一处用途（show 收窄）。
import '../../core/database/dao/connection_dao.dart' show ConnectionDao;
import '../../core/network/webdav_client.dart';
import '../../core/services/storage_utils.dart';
import '../../shared/di/providers.dart'
    show directoryCacheProvider, navigationStackProvider;
import '../../shared/models/connection_config.dart';
import 'domain/connection_service.dart';

// Re-export the module's value type alongside its providers (same pattern as
// player_provider exposing PlayMode) so consumers importing this file see the
// activeConnectionProvider's element type without a second import path.
export '../../shared/models/connection_config.dart' show ConnectionConfig;

// ── Infrastructure providers ──────────────────────────────────────────────────

final connectionDaoProvider =
    Provider<IConnectionDao>((ref) => ConnectionDao());

final webDavClientProvider =
    Provider<WebDavClientInterface>((ref) => WebDavClient());

/// REF-01-A2: production adapter that wraps [FlutterSecureStorage] behind the
/// [ISecureStorage] contract.  The concrete plugin type never leaks past this
/// adapter into the domain layer.
class FlutterSecureStorageAdapter implements ISecureStorage {
  final FlutterSecureStorage _impl;
  const FlutterSecureStorageAdapter(
      [this._impl = const FlutterSecureStorage()]);

  @override
  Future<String?> read({required String key}) => _impl.read(key: key);

  @override
  Future<void> write({required String key, required String? value}) =>
      _impl.write(key: key, value: value);

  @override
  Future<void> delete({required String key}) => _impl.delete(key: key);

  @override
  Future<bool> containsKey({required String key}) =>
      _impl.containsKey(key: key);
}

final secureStorageProvider =
    Provider<ISecureStorage>((ref) => const FlutterSecureStorageAdapter());

/// Provider for [ConnectionService] — the pure-Dart CRUD facade.
final connectionServiceProvider = Provider<ConnectionService>((ref) {
  return ConnectionService(
    ref.watch(connectionDaoProvider),
    ref.watch(secureStorageProvider),
  );
});

// ── Active connection ─────────────────────────────────────────────────────────

/// Resolves the currently active [ConnectionConfig] from the database.
/// Returns null when no active connection is configured.
final activeConnectionProvider = FutureProvider<ConnectionConfig?>((ref) async {
  final dao = ref.watch(connectionDaoProvider);
  return dao.findActive();
});

// ── All connections list ──────────────────────────────────────────────────────

/// Returns all saved connections ordered by creation date.
final connectionListProvider =
    FutureProvider<List<ConnectionConfig>>((ref) async {
  final dao = ref.watch(connectionDaoProvider);
  return dao.findAll();
});

// ── Connection validation state ───────────────────────────────────────────────

/// Represents the lifecycle of a "test connection" operation.
abstract class ConnectionValidationState {
  const ConnectionValidationState();
}

class ValidationIdle extends ConnectionValidationState {
  const ValidationIdle();
}

class ValidationLoading extends ConnectionValidationState {
  const ValidationLoading();
}

class ValidationSuccess extends ConnectionValidationState {
  const ValidationSuccess();
}

class ValidationError extends ConnectionValidationState {
  final String message;
  const ValidationError(this.message);
}

/// StateNotifier that drives the "测试连接" → result flow.
class ConnectionValidatorNotifier
    extends StateNotifier<ConnectionValidationState> {
  final WebDavClientInterface _client;

  int _validationEpoch = 0;

  ConnectionValidatorNotifier(this._client) : super(const ValidationIdle());

  /// Performs the WebDAV PROPFIND validation.
  ///
  /// Includes a re-entry guard: if a validation is already in-flight the call
  /// is silently ignored (CON-T17).
  Future<void> validate({
    required String url,
    required String username,
    required String password,
    String basePath = '/',
  }) async {
    if (state is ValidationLoading) return; // re-entry guard
    final epoch = ++_validationEpoch; // BUG-14: 本次请求的 epoch
    state = const ValidationLoading();
    // CON2/NET7: strip any user:pass@ before logging (LogBuffer mirror).
    debugPrint(
        '[Conn] validating: url=${redactUrlForLog(url)} basePath=$basePath');
    final normalisedUrl = normaliseWebDavUrl(url);
    final result = await _client.validate(
      url: normalisedUrl,
      username: username,
      password: password,
      basePath: basePath,
    );
    if (epoch != _validationEpoch) return; // BUG-14: 过期结果丢弃（不落地）
    debugPrint('[Conn] validation result: ${result.status}');
    if (result.isSuccess) {
      state = const ValidationSuccess();
    } else {
      state = ValidationError(result.message ?? '无法连接到服务器，请检查地址和网络');
    }
  }

  void reset() {
    _validationEpoch++; // BUG-14: 使所有 in-flight 请求失效
    state = const ValidationIdle();
  }
}

final connectionValidatorProvider = StateNotifierProvider<
    ConnectionValidatorNotifier, ConnectionValidationState>((ref) {
  final client = ref.watch(webDavClientProvider);
  return ConnectionValidatorNotifier(client);
});

// ── Startup auto-validation ────────────────────────────────────────────────────
//
// Watches [activeConnectionProvider] and automatically validates the active
// connection whenever it resolves to a non-null value.  This covers both
// app-startup (CON-T15 / CON-T16) and connection-switch scenarios.
//
// Returns null when no active connection exists, otherwise the raw validation
// result from the WebDAV client.
//
// Usage: watch this provider from an app-shell-level widget that can react to
// [ConnectionHealthError] by prompting the user to reconfigure.

final startupValidationProvider =
    FutureProvider<WebDavValidationResult?>((ref) async {
  final activeConn = await ref.watch(activeConnectionProvider.future);
  if (activeConn == null) {
    debugPrint('[Conn] startupValidation: no active connection');
    return null;
  }
  // H-7: guard against null connection id from corrupted DB records.
  if (activeConn.id == null) {
    debugPrint('[Conn] startupValidation: null connection id');
    return WebDavValidationResult.authError();
  }

  // CON2/NET7: legacy rows may still carry user:pass@ in the url column —
  // redact before logging so the per-boot check never leaks credentials.
  debugPrint('[Conn] startupValidation: checking id=${activeConn.id} '
      'url=${redactUrlForLog(activeConn.url)}');

  // Read the password from secure storage
  final storage = ref.watch(secureStorageProvider);
  final passwordKey = 'connection_password_${activeConn.id}';
  String? password;
  try {
    password = await safeStorageRead(storage, key: passwordKey);
  } on SecureStorageTimeoutException {
    // secret-logs gate: semantic log only, no credential words.
    debugPrint('[Conn] startupValidation: secure storage read timeout');
    return WebDavValidationResult.error('读取密码超时，请重试');
  }
  if (password == null || password.isEmpty) {
    debugPrint('[Conn] startupValidation: no secret stored');
    return WebDavValidationResult.authError();
  }

  // Run validation silently (no connectionValidatorProvider state changes)
  final client = ref.watch(webDavClientProvider);
  final result = await client.validate(
    url: activeConn.url,
    username: activeConn.username,
    password: password,
    basePath: activeConn.basePath,
  );
  debugPrint('[Conn] startupValidation result: ${result.status}');
  return result;
});

// ── Switch active connection ────────────────────────────────────────────────────

/// Switches the active connection to the connection with the given [id].
/// Invalidates [activeConnectionProvider] and [connectionListProvider] so the
/// UI reacts immediately.
///
/// REF-18-S1 (cr-20260822-2051 D2): P11 收敛 —— 写动作改回调形态（同
/// setDefaultSpeedProvider），build 体只剩闭包构造；任何元素重建不再隐式重放
/// 数据库写。调用方 `ref.read(switchActiveConnectionProvider)(id)` 直调。
final switchActiveConnectionProvider =
    Provider<Future<void> Function(int)>((ref) {
  final service = ref.watch(connectionServiceProvider);
  return (int id) async {
    debugPrint('[Conn] switch: id=$id');
    await service.setActive(id);
    ref.invalidate(activeConnectionProvider);
    ref.invalidate(connectionListProvider);
    // BUG-16: switch 路径收敛进 CON3 钩子 —— 浏览器状态复位从 widget 层
    // （connection_list_screen.dart，随页面销毁丢失）上移到 provider 层，
    // 切换期间退出列表页不再丢复位（cr-20260816-0804 F3）。
    resetBrowserStateOnActiveConnectionChange(ref);
    debugPrint('[Conn] switch: done id=$id');
  };
});

// ── Save connection use-case ──────────────────────────────────────────────────

/// Backward-compatible shim: exposes [ConnectionService.save] via the same
/// `ConnectionSaver` interface that screens already use.
///
/// Supports two construction patterns:
/// - `ConnectionSaver(service)` — new style, delegates to [ConnectionService].
/// - `ConnectionSaver(dao, storage)` — legacy style, wraps in a [ConnectionService].
class ConnectionSaver {
  final ConnectionService _service;

  ConnectionSaver(Object daoOrService, [ISecureStorage? storage])
      : _service = daoOrService is ConnectionService
            ? daoOrService
            : ConnectionService(daoOrService as ConnectionDao, storage!);

  Future<ConnectionConfig> save({
    required ConnectionConfig config,
    required String password,
  }) =>
      _service.save(config: config, password: password);
}

/// [ConnectionSaver] that refreshes derived providers after a successful save.
///
/// CON1: the refresh duty lives in the provider layer — NOT in the widget —
/// so `ref.invalidate` can never run against a disposed widget element when
/// the user leaves the page while the save is in flight (pre-fix the
/// widget-level invalidate threw a swallowed StateError and both providers
/// stayed stale for the rest of the session). Mirrors the invalidation
/// pattern of [switchActiveConnectionProvider] / [deleteConnectionProvider].
class _SaveAndRefreshSaver extends ConnectionSaver {
  final Ref _ref;

  _SaveAndRefreshSaver(super.daoOrService, this._ref);

  @override
  Future<ConnectionConfig> save({
    required ConnectionConfig config,
    required String password,
  }) async {
    final saved = await super.save(config: config, password: password);
    _ref.invalidate(activeConnectionProvider);
    _ref.invalidate(connectionListProvider);
    return saved;
  }
}

final connectionSaverProvider = Provider<ConnectionSaver>((ref) {
  return _SaveAndRefreshSaver(ref.watch(connectionServiceProvider), ref);
});

// ── Update connection use-case ──────────────────────────────────────────────────

/// Backward-compatible shim: exposes [ConnectionService.update] via the same
/// `ConnectionUpdater` interface that screens already use.
///
/// Supports two construction patterns:
/// - `ConnectionUpdater(service)` — new style, delegates to [ConnectionService].
/// - `ConnectionUpdater(dao, storage)` — legacy style, wraps in a [ConnectionService].
class ConnectionUpdater {
  final ConnectionService _service;

  ConnectionUpdater(Object daoOrService, [ISecureStorage? storage])
      : _service = daoOrService is ConnectionService
            ? daoOrService
            : ConnectionService(daoOrService as ConnectionDao, storage!);

  Future<void> update({
    required ConnectionConfig config,
    String? password,
  }) =>
      _service.update(config: config, password: password);
}

/// CON3: unified "active connection config changed → reset browser state"
/// hook — the single place that clears browser-side state when a mutation
/// changes what the active connection resolves to.
///
/// Callers (must run AFTER the underlying DB write succeeds):
/// - edit/update — [_UpdateAndRefreshUpdater] below (CON3)
/// - delete — [deleteConnectionProvider] (CON3)
/// - switch — [switchActiveConnectionProvider] (BUG-16, converged onto this
///   hook 2026-08-16; previously the widget layer in connection_list_screen
///   performed the identical two invalidates and lost them when the page was
///   disposed mid-switch).
///
/// Both browser providers must go: the directory cache is keyed
/// `'${conn.id}:$path'` — id-only — so an edit that keeps the id would hit
/// the 5-minute TTL with listings fetched from the old server / old basePath,
/// and a deep navigationStack path may not exist under the new basePath
/// (PROPFIND 404), so the stack must reset to root (invalidating the
/// StateNotifierProvider rebuilds NavigationStackNotifier to `['/']`).
///
/// Browser providers are reached exclusively through the shared/di bridge
/// (REF-31) — features never import each other directly.
void resetBrowserStateOnActiveConnectionChange(Ref ref) {
  ref.invalidate(directoryCacheProvider);
  ref.invalidate(navigationStackProvider);
}

/// [ConnectionUpdater] that refreshes derived providers after a successful
/// update — see [_SaveAndRefreshSaver] for the CON1 rationale (editing the
/// active connection mid-flight must not leave stale provider state when the
/// user leaves the edit page before the update resolves). CON3 adds the
/// browser-state reset via [resetBrowserStateOnActiveConnectionChange].
class _UpdateAndRefreshUpdater extends ConnectionUpdater {
  final Ref _ref;

  _UpdateAndRefreshUpdater(super.daoOrService, this._ref);

  @override
  Future<void> update({
    required ConnectionConfig config,
    String? password,
  }) async {
    await super.update(config: config, password: password);
    _ref.invalidate(activeConnectionProvider);
    _ref.invalidate(connectionListProvider);
    // CON3: the active connection's effective config (url / basePath / …)
    // may have changed — reset browser state through the unified hook so the
    // 5-minute directory TTL never serves stale listings from the old
    // server/path. Success path only: failures rethrow above this line.
    resetBrowserStateOnActiveConnectionChange(_ref);
  }
}

final connectionUpdaterProvider = Provider<ConnectionUpdater>((ref) {
  return _UpdateAndRefreshUpdater(ref.watch(connectionServiceProvider), ref);
});

// ── Delete connection use-case ──────────────────────────────────────────────────

/// Deletes the connection with [id].
///
/// Throws [LastConnectionException] when only one connection remains (CON-T32).
/// Cascades to play_progress records and secure-storage password entry (CON-T31).
/// Auto-activates another connection if the deleted one was active (CON-T34).
///
/// REF-18-S2: 回调形态（同 S1），写副作用全部移入闭包。
final deleteConnectionProvider = Provider<Future<void> Function(int)>((ref) {
  final service = ref.watch(connectionServiceProvider);
  return (int id) async {
    debugPrint('[Conn] delete: id=$id');
    bool wasActive = false;
    try {
      wasActive = await service.delete(id);
    } on LastConnectionException {
      debugPrint('[Conn] delete: blocked — last connection');
      throw const LastConnectionException('无法删除最后一个连接');
    }
    debugPrint('[Conn] delete: done id=$id');

    ref.invalidate(activeConnectionProvider);
    ref.invalidate(connectionListProvider);

    if (wasActive) {
      resetBrowserStateOnActiveConnectionChange(ref);
    }
  };
});
