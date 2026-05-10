// lib/features/player/player_provider.dart
// Riverpod providers for the Player feature.
//
// Provides an AudioPlayer instance and load-state management so the
// player screen (PLY-01) can load WebDAV audio streams with Basic Auth
// and react to errors gracefully.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';

// ── AudioPlayer instance ───────────────────────────────────────────────────────

/// The [AudioPlayer] instance used for playback.
///
/// Created lazily on first read and disposed when the provider container
/// is destroyed (app lifecycle).  Only one player exists application-wide.
final audioPlayerProvider = Provider<AudioPlayer>((ref) {
  final player = AudioPlayer();
  ref.onDispose(() => player.dispose());
  return player;
});

// ── Player load state ──────────────────────────────────────────────────────────

/// Lifecycle of loading an audio source into the player.
enum PlayerLoadStatus {
  /// No source has been loaded yet.
  idle,

  /// The source is being loaded / buffered.
  loading,

  /// The source is loaded and the player is ready to play.
  ready,

  /// Loading failed.
  error,
}

/// Tracks the current source-loading state of the player.
///
/// Managed by the [PlayerScreen] locally (not a global StateNotifier)
/// because the load cycle is tightly coupled to the screen lifecycle
/// (rebuilding the screen for a different file starts a fresh load).
class PlayerLoadState {
  final PlayerLoadStatus status;
  final String? errorMessage;

  /// Whether the error is an authentication failure (401 / 403).
  final bool isAuthError;

  const PlayerLoadState({
    this.status = PlayerLoadStatus.idle,
    this.errorMessage,
    this.isAuthError = false,
  });

  static const idle = PlayerLoadState();

  static const loading =
      PlayerLoadState(status: PlayerLoadStatus.loading);

  static const ready = PlayerLoadState(status: PlayerLoadStatus.ready);

  factory PlayerLoadState.error(String message, {bool isAuthError = false}) {
    return PlayerLoadState(
      status: PlayerLoadStatus.error,
      errorMessage: message,
      isAuthError: isAuthError,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PlayerLoadState &&
          status == other.status &&
          errorMessage == other.errorMessage &&
          isAuthError == other.isAuthError;

  @override
  int get hashCode => Object.hash(status, errorMessage, isAuthError);

  @override
  String toString() =>
      'PlayerLoadState(status: $status, errorMessage: $errorMessage, '
      'isAuthError: $isAuthError)';
}

// ── Seek utility functions ──────────────────────────────────────────────────────

/// Clamps [target] to the range `[Duration.zero, total]`.
///
/// Used by seek, skip-forward, and skip-backward logic to ensure positions
/// never go negative or exceed the track duration.
///
/// PLY-T10~T12: seek with clamping; PLY-T13~T16: skip forward/backward.
Duration clampSeek(Duration target, Duration total) {
  if (target < Duration.zero) return Duration.zero;
  if (target > total) return total;
  return target;
}

/// Returns the position after skipping forward by [seconds] (default 15).
///
/// The result is clamped to [total] so it never exceeds the track duration.
/// PLY-T13~T14.
Duration skipForward(Duration current, Duration total, {int seconds = 15}) {
  return clampSeek(current + Duration(seconds: seconds), total);
}

/// Returns the position after skipping backward by [seconds] (default 15).
///
/// The result is clamped to [current] so it never goes below zero or
/// forward of the current position.
/// PLY-T15~T16.
Duration skipBackward(Duration current, {int seconds = 15}) {
  return clampSeek(current - Duration(seconds: seconds), current);
}

/// Configurable seek step in seconds (default 15).
///
/// Can be overridden later by settings.  Currently used by skip-forward
/// and skip-backward controls.
final seekStepProvider = StateProvider<int>((ref) => 15);

// ── Speed options ───────────────────────────────────────────────────────────────

/// Available playback speed multipliers.
const List<double> speedOptions = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0];

// ── Time formatting helper ─────────────────────────────────────────────────────

/// Formats a [Duration] as a human-readable timestamp.
///
/// - Durations under 1 hour: `MM:SS` (e.g. `05:30`)
/// - Durations 1 hour or more: `H:MM:SS` (e.g. `1:23:45`)
/// - Null: `--:--`
String formatDuration(Duration? duration) {
  if (duration == null) return '--:--';
  final totalSeconds = duration.inSeconds;
  final hours = totalSeconds ~/ 3600;
  final minutes = (totalSeconds % 3600) ~/ 60;
  final seconds = totalSeconds % 60;

  final mm = minutes.toString().padLeft(2, '0');
  final ss = seconds.toString().padLeft(2, '0');

  if (hours > 0) {
    return '$hours:$mm:$ss';
  }
  return '$mm:$ss';
}
