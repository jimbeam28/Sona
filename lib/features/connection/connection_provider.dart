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

import '../../core/database/dao/connection_dao.dart';
import '../../core/network/webdav_client.dart';
import '../../core/services/storage_utils.dart';
import '../../shared/models/connection_config.dart';
import 'domain/connection_service.dart';

// ── Infrastructure providers ──────────────────────────────────────────────────

final connectionDaoProvider = Provider<ConnectionDao>((ref) => ConnectionDao());

final webDavClientProvider =
    Provider<WebDavClientInterface>((ref) => WebDavClient());

final secureStorageProvider =
    Provider<FlutterSecureStorage>((ref) => const FlutterSecureStorage());

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
    state = const ValidationLoading();
    debugPrint('[Conn] validating: url=$url basePath=$basePath');
    final normalisedUrl = normaliseWebDavUrl(url);
    final result = await _client.validate(
      url: normalisedUrl,
      username: username,
      password: password,
      basePath: basePath,
    );
    debugPrint('[Conn] validation result: ${result.status}');
    if (result.isSuccess) {
      state = const ValidationSuccess();
    } else {
      state = ValidationError(result.message ?? '无法连接到服务器，请检查地址和网络');
    }
  }

  void reset() => state = const ValidationIdle();
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

  debugPrint(
      '[Conn] startupValidation: checking id=${activeConn.id} url=${activeConn.url}');

  // Read the password from secure storage
  final storage = ref.watch(secureStorageProvider);
  final passwordKey = 'connection_password_${activeConn.id}';
  final password = await safeStorageRead(storage, key: passwordKey);
  if (password == null || password.isEmpty) {
    debugPrint('[Conn] startupValidation: no password');
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
final switchActiveConnectionProvider =
    FutureProvider.family<void, int>((ref, id) async {
  final service = ref.watch(connectionServiceProvider);
  debugPrint('[Conn] switch: id=$id');
  await service.setActive(id);
  ref.invalidate(activeConnectionProvider);
  ref.invalidate(connectionListProvider);
  debugPrint('[Conn] switch: done id=$id');
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

  ConnectionSaver(Object daoOrService, [FlutterSecureStorage? storage])
      : _service = daoOrService is ConnectionService
            ? daoOrService
            : ConnectionService(daoOrService as ConnectionDao, storage!);

  Future<ConnectionConfig> save({
    required ConnectionConfig config,
    required String password,
  }) =>
      _service.save(config: config, password: password);
}

final connectionSaverProvider = Provider<ConnectionSaver>((ref) {
  return ConnectionSaver(ref.watch(connectionServiceProvider));
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

  ConnectionUpdater(Object daoOrService, [FlutterSecureStorage? storage])
      : _service = daoOrService is ConnectionService
            ? daoOrService
            : ConnectionService(daoOrService as ConnectionDao, storage!);

  Future<void> update({
    required ConnectionConfig config,
    String? password,
  }) =>
      _service.update(config: config, password: password);
}

final connectionUpdaterProvider = Provider<ConnectionUpdater>((ref) {
  return ConnectionUpdater(ref.watch(connectionServiceProvider));
});

// ── Delete connection use-case ──────────────────────────────────────────────────

/// Deletes the connection with [id].
///
/// Throws [LastConnectionException] when only one connection remains (CON-T32).
/// Cascades to play_progress records and secure-storage password entry (CON-T31).
/// Auto-activates another connection if the deleted one was active (CON-T34).
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
