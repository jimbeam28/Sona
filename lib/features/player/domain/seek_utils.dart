// lib/features/player/domain/seek_utils.dart
// Pure utility functions for audio seek / skip operations.
//
// Extracted from player_provider.dart (REF-08) so they can be tested
// independently of Flutter and Riverpod.
//
// Functions:
//   clampSeek  — clamps a target position to the valid range [0, total]
//   skipForward  — advances position by a given step, clamped to total
//   skipBackward — retreats position by a given step, clamped to zero

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
