// lib/features/connection/domain/connection_service.dart
// Pure-Dart service encapsulating connection CRUD use-cases.
// Extracted from connection_provider.dart to enable unit testing without
// Flutter or Riverpod dependencies.
//
// Responsibilities:
// - save:   atomic DB insert + SecureStorage write + rollback on failure
// - update: DB update + optional password rotation
// - delete: last-connection protection + secure-storage cleanup + auto-activate
// - setActive: transactional switch (single active connection)

import '../../../core/contracts/storage_contract.dart';
import '../../../core/database/dao/connection_dao.dart';
import '../../../core/services/log_forwarder.dart';
import '../../../core/services/storage_utils.dart';
import '../../../shared/models/connection_config.dart';

/// Pure-Dart service for connection lifecycle operations.
///
/// Depends only on [ConnectionDao] and [ISecureStorage] — no Flutter
/// framework, no Riverpod, no BuildContext.
class ConnectionService {
  final ConnectionDao _dao;
  final ISecureStorage _storage;

  ConnectionService(this._dao, this._storage);

  // ── Save ──────────────────────────────────────────────────────────────────

  /// Saves [config] + [password] atomically:
  /// 1. Insert row with a temporary password key.
  /// 2. Write password to secure storage under the permanent key.
  /// 3. If step 2 fails, delete the DB row (rollback) and rethrow.
  /// 4. Update the row to reference the permanent password key.
  /// 5. Set the saved connection as the only active one.
  ///
  /// Returns the saved [ConnectionConfig] with its database id set.
  Future<ConnectionConfig> save({
    required ConnectionConfig config,
    required String password,
  }) async {
    const tempKey = 'connection_password_temp';

    // Step 1: insert with temp key to get the AUTOINCREMENT id.
    final id = await _dao.insert(config, passwordKey: tempKey);

    // Step 2: persist password under the permanent key.
    final permanentKey = 'connection_password_$id';
    try {
      await safeStorageWrite(_storage, key: permanentKey, value: password);
    } catch (_) {
      // Step 3: rollback — remove the DB row if secure-storage write fails.
      await _dao.delete(id);
      rethrow;
    }

    // Step 4: update the row to reference the permanent key.
    final savedConfig = config.copyWith(id: id, isActive: true);
    await _dao.update(savedConfig, passwordKey: permanentKey);

    // Step 5: mark as active (clears any previous active flag).
    await _dao.setActive(id);

    return savedConfig;
  }

  // ── Update ────────────────────────────────────────────────────────────────

  /// Updates [config] in the database.
  ///
  /// If [password] is non-null and non-empty, it is written to secure storage;
  /// otherwise the existing stored password is left untouched.
  ///
  /// BUG-24-S2: mirrors [save]'s atomicity strategy — when the password is
  /// rotated, the previous password is read first and restored if the DAO
  /// update fails after the storage write succeeded. Without the rollback the
  /// new password would already be effective while the DB still referenced the
  /// old config, leaving the connection permanently broken (401).
  Future<void> update({
    required ConnectionConfig config,
    String? password,
  }) async {
    final permanentKey = 'connection_password_${config.id}';

    if (password != null && password.isNotEmpty) {
      String? oldPassword;
      try {
        oldPassword = await safeStorageRead(_storage, key: permanentKey);
      } catch (_) {
        // Read failure (e.g. timeout) degrades to null: the rollback below
        // then clears the key. Losing the password is acceptable here since
        // the DAO update also failed and the user must retry anyway.
        oldPassword = null;
      }
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

  // ── Delete ────────────────────────────────────────────────────────────────

  /// Deletes the connection with [id].
  ///
  /// Throws [LastConnectionException] when only one connection remains.
  ///
  /// Cascades to:
  /// - play_progress records for this connection (DAO level).
  /// - secure-storage password entry.
  ///
  /// If the deleted connection was active, the DAO auto-activates another.
  Future<bool> delete(int id) async {
    final wasActive = await _dao.delete(id);
    try {
      await safeStorageDelete(_storage, key: 'connection_password_$id');
    } catch (e) {
      // Best-effort cleanup: the DB row is already gone and ids are
      // AUTOINCREMENT (never reused), so an orphaned password key is
      // acceptable (BUG-24-S3 ruling — delete must not fail on cleanup
      // failure). But the error must not vanish silently either: catch-log
      // discipline (same criterion as CON1/BUG-19/LIST6). Only the key name
      // and the exception are logged — never a secret value.
      debugLog('[Conn] delete: secure storage cleanup failed for id=$id: $e');
    }
    return wasActive;
  }

  // ── Switch active connection ──────────────────────────────────────────────

  /// Switches the active connection to the one identified by [id].
  ///
  /// Uses a database transaction to guarantee exactly one active connection
  /// at all times.
  Future<void> setActive(int id) async {
    await _dao.setActive(id);
  }
}
