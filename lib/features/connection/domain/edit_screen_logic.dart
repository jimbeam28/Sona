// lib/features/connection/domain/edit_screen_logic.dart
// Pure functions for the ConnectionEditScreen validation-gate logic.
// Extracted to enable independent unit testing without Flutter dependencies.

import '../../../shared/models/connection_config.dart';

/// Holds the current form field values for the edit screen.
///
/// Used to compare against the original [ConnectionConfig] to determine
/// whether credential-related fields have changed.
class EditFieldChanges {
  final String url;
  final String username;
  final String basePath;
  final String password;

  const EditFieldChanges({
    required this.url,
    required this.username,
    required this.basePath,
    required this.password,
  });
}

/// Validation status enum — domain-level mirror of the Riverpod validation
/// state, decoupled from Flutter.
enum ValidationStatus {
  idle,
  loading,
  success,
  error,
}

/// Determines whether the user modified a field that affects connectivity
/// (URL, username, basePath, or password) and therefore must re-validate
/// before saving.
///
/// Returns `true` when re-validation is needed.
///
/// Parameters:
/// - [original]: the original connection config (null means safety net —
///   always require validation).
/// - [current]: the current form field values.
/// - [isAttached]: whether the form controller is attached (if not, no
///   comparison is possible — return false).
bool needsValidation({
  required ConnectionConfig? original,
  required EditFieldChanges current,
  required bool isAttached,
}) {
  if (original == null) return true;
  if (!isAttached) return false;
  return current.url != original.url ||
      current.username != original.username ||
      current.basePath != original.basePath ||
      current.password.isNotEmpty;
}

/// Determines whether the save button should be enabled.
///
/// If re-validation is required (i.e. credential fields changed), the
/// [validationStatus] must be [ValidationStatus.success].
/// If no re-validation is needed (e.g. only the display name changed),
/// saving is always allowed.
bool canSave({
  required bool needsRevalidation,
  required ValidationStatus validationStatus,
}) {
  if (needsRevalidation) {
    return validationStatus == ValidationStatus.success;
  }
  return true;
}
