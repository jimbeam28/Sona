// lib/features/player/domain/player_screen_logic.dart
// Pure-function logic extracted from PlayerScreen.
// Zero Flutter / Riverpod dependencies — independently unit-testable.

import '../../../shared/models/play_queue.dart';

// ── Source ↔ Queue matching ──────────────────────────────────────────────────

/// Returns `true` when the player's loaded source URI path ends with
/// [queue]'s current file path.
///
/// [currentSourcePath] is the decoded URI path of the currently loaded
/// audio source (i.e. `Uri.decodeComponent(source.uri.path)`), or `null`
/// when no source is loaded.
bool sourceMatchesQueue(String? currentSourcePath, PlayQueue queue) {
  if (currentSourcePath == null) return false;
  return currentSourcePath.endsWith(queue.current.path);
}

// ── Path helpers ─────────────────────────────────────────────────────────────

/// Extracts the parent directory from a file [path].
///
/// Returns `'/'` when [path] has no parent segment (e.g. `'/file.mp3'`).
String parentDir(String path) {
  final idx = path.lastIndexOf('/');
  if (idx <= 0) return '/';
  return path.substring(0, idx);
}

// ── Load-failure classification ──────────────────────────────────────────────

/// Reason why a track load failed.
enum LoadFailureReason {
  /// No active connection was found.
  noConnection,

  /// The connection password is missing or empty.
  noPassword,

  /// An unspecified / generic failure.
  generic,
}

/// Classifies the reason for a track-load failure based on the availability
/// of connection metadata.
///
/// Both parameters are simple booleans so the caller can gather the data
/// from any source (providers, tests, etc.) without coupling this function
/// to a specific data-access pattern.
LoadFailureReason classifyLoadFailure({
  required bool hasActiveConnection,
  required bool hasPassword,
}) {
  if (!hasActiveConnection) return LoadFailureReason.noConnection;
  if (!hasPassword) return LoadFailureReason.noPassword;
  return LoadFailureReason.generic;
}

/// Returns a user-visible error message for the given [reason].
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

/// Returns `true` when [reason] represents an authentication-related failure
/// (missing connection or missing password).
bool isAuthError(LoadFailureReason reason) {
  return reason == LoadFailureReason.noConnection ||
      reason == LoadFailureReason.noPassword;
}
