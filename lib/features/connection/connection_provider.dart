// lib/features/connection/connection_provider.dart
// Riverpod providers for the Connection feature.
// Written without code generation — uses StateNotifier / AsyncNotifier patterns
// from flutter_riverpod directly (no @riverpod annotations, no build_runner).

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../core/database/dao/connection_dao.dart';
import '../../core/network/webdav_client.dart';
import '../../core/services/storage_utils.dart';
import '../../shared/models/connection_config.dart';

// ── Infrastructure providers ──────────────────────────────────────────────────

final connectionDaoProvider = Provider<ConnectionDao>((ref) => ConnectionDao());

final webDavClientProvider =
    Provider<WebDavClientInterface>((ref) => WebDavClient());

final secureStorageProvider =
    Provider<FlutterSecureStorage>((ref) => const FlutterSecureStorage());

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
  final dao = ref.watch(connectionDaoProvider);
  debugPrint('[Conn] switch: id=$id');
  await dao.setActive(id);
  ref.invalidate(activeConnectionProvider);
  ref.invalidate(connectionListProvider);
  debugPrint('[Conn] switch: done id=$id');
});

// ── Save connection use-case ──────────────────────────────────────────────────

/// Encapsulates saving a new connection to the DB and secure storage.
class ConnectionSaver {
  final ConnectionDao _dao;
  final FlutterSecureStorage _storage;

  ConnectionSaver(this._dao, this._storage);

  /// Saves [config] + [password] atomically:
  /// 1. Insert row with a temp key.
  /// 2. Read the assigned id.
  /// 3. Write password to secure storage under `connection_password_{id}`.
  /// 4. Update the row's password column to the final key.
  ///
  /// Returns the saved [ConnectionConfig] with its database id set.
  Future<ConnectionConfig> save({
    required ConnectionConfig config,
    required String password,
  }) async {
    const tempKey = 'connection_password_temp';

    // Insert with temp key to get the AUTOINCREMENT id
    final id = await _dao.insert(config, passwordKey: tempKey);
    debugPrint('[Conn] save: inserted id=$id name=${config.name}');

    // Persist password under the permanent key
    final permanentKey = 'connection_password_$id';
    try {
      await safeStorageWrite(_storage, key: permanentKey, value: password);
    } catch (_) {
      // H-1: rollback the DB insert if secure-storage write fails.
      debugPrint('[Conn] save: secure-storage write failed, rolling back');
      await _dao.delete(id);
      rethrow;
    }

    // Update the row to reference the permanent key
    final savedConfig = config.copyWith(id: id, isActive: true);
    await _dao.update(savedConfig, passwordKey: permanentKey);

    // Mark as active (clears any previous active flag)
    await _dao.setActive(id);
    debugPrint('[Conn] save: done id=$id');

    return savedConfig;
  }
}

final connectionSaverProvider = Provider<ConnectionSaver>((ref) {
  return ConnectionSaver(
    ref.watch(connectionDaoProvider),
    ref.watch(secureStorageProvider),
  );
});

// ── Update connection use-case ──────────────────────────────────────────────────

/// Encapsulates updating an existing connection in the DB and secure storage.
class ConnectionUpdater {
  final ConnectionDao _dao;
  final FlutterSecureStorage _storage;

  ConnectionUpdater(this._dao, this._storage);

  /// Updates [config] in the database.
  ///
  /// If [password] is non-null and non-empty it is written to secure storage;
  /// otherwise the existing stored password is left untouched.
  Future<void> update({
    required ConnectionConfig config,
    String? password,
  }) async {
    final permanentKey = 'connection_password_${config.id}';

    if (password != null && password.isNotEmpty) {
      await safeStorageWrite(_storage, key: permanentKey, value: password);
    }
    debugPrint('[Conn] update: id=${config.id} name=${config.name}');

    await _dao.update(config, passwordKey: permanentKey);
    debugPrint('[Conn] update: done id=${config.id}');
  }
}

final connectionUpdaterProvider = Provider<ConnectionUpdater>((ref) {
  return ConnectionUpdater(
    ref.watch(connectionDaoProvider),
    ref.watch(secureStorageProvider),
  );
});

// ── Delete connection use-case ──────────────────────────────────────────────────

/// Deletes the connection with [id].
///
/// Cascades to:
/// - play_progress records for this connection (DAO level, CON-T31)
/// - secure-storage password entry (CON-T31)
///
/// Throws [LastConnectionException] when only one connection remains (CON-T32).
/// Auto-activates another connection if the deleted one was active (CON-T34).
final deleteConnectionProvider =
    FutureProvider.family<void, int>((ref, id) async {
  final dao = ref.watch(connectionDaoProvider);
  final storage = ref.watch(secureStorageProvider);

  debugPrint('[Conn] delete: id=$id');
  try {
    await dao.delete(id);
  } on LastConnectionException {
    debugPrint('[Conn] delete: blocked — last connection');
    throw const LastConnectionException('无法删除最后一个连接');
  }

  // Remove the password from secure storage (CON-T31)
  await safeStorageDelete(storage, key: 'connection_password_$id');
  debugPrint('[Conn] delete: done id=$id');

  ref.invalidate(activeConnectionProvider);
  ref.invalidate(connectionListProvider);
});
