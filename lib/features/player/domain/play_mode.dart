// lib/features/player/domain/play_mode.dart
// Pure Dart domain logic for playback mode.
//
// Extracted from play_queue.dart (PlayMode enum, nextIndex, previousIndex)
// and player_provider.dart (iconForPlayMode, labelForPlayMode) so they can
// be tested independently of Flutter and Riverpod.
//
// Zero Flutter dependencies — only dart:math is used (for shuffle).

import 'dart:math';

/// Playback mode for the audio queue.
///
/// Determines what happens when the current track finishes or the user
/// skips to next/previous.
enum PlayMode {
  /// Play files in order; stop at the end of the queue.
  sequential,

  /// Replay the current track from the beginning.
  repeatOne,

  /// Play files in order; wrap to the first track after the last.
  repeatAll,

  /// Play files in random order.
  shuffle,
}

/// Returns the next [PlayMode] in the cycle:
///   sequential -> repeatOne -> repeatAll -> shuffle -> sequential ...
PlayMode nextPlayMode(PlayMode current) {
  return PlayMode.values[(current.index + 1) % PlayMode.values.length];
}

/// Returns a human-readable Chinese label for the given [PlayMode].
String labelForPlayMode(PlayMode mode) {
  switch (mode) {
    case PlayMode.sequential:
      return '顺序播放';
    case PlayMode.repeatOne:
      return '单曲循环';
    case PlayMode.repeatAll:
      return '列表循环';
    case PlayMode.shuffle:
      return '随机播放';
  }
}

/// Returns the index of the next track given [mode], or `null` when
/// playback should stop (sequential mode at end of queue).
///
/// [current] is the current index (0-based).  [length] is the number of
/// items in the queue.  [random] is used for shuffle mode; if not
/// provided a default [Random] is used.  Providing a seeded [Random]
/// makes the function deterministic for testing.
///
/// Boundary conditions:
/// - Empty queue (length == 0) → null
/// - Out-of-bounds current (< 0 or >= length) → null
/// - Single-item queue with sequential → null (no next)
/// - Single-item queue with repeatOne → same index
/// - Single-item queue with repeatAll → same index
/// - Single-item queue with shuffle → null (no different index)
int? nextIndex(int current, int length, PlayMode mode, {Random? random}) {
  // Guard against out-of-bounds or empty queue.
  if (length == 0 || current < 0 || current >= length) return null;
  switch (mode) {
    case PlayMode.sequential:
      return current < length - 1 ? current + 1 : null;
    case PlayMode.repeatOne:
      return current;
    case PlayMode.repeatAll:
      return (current + 1) % length;
    case PlayMode.shuffle:
      if (length <= 1) return null;
      final rng = random ?? Random();
      int next;
      do {
        next = rng.nextInt(length);
      } while (next == current);
      return next;
  }
}

/// Returns the index of the previous track given [mode], or `null` when
/// there is no previous track (sequential mode at start of queue).
///
/// [current] is the current index (0-based).  [length] is the number of
/// items in the queue.  [random] is used for shuffle mode.
///
/// Boundary conditions:
/// - Empty queue (length == 0) → null
/// - Out-of-bounds current (< 0 or >= length) → null
/// - Single-item queue with sequential → null (no previous)
/// - Single-item queue with repeatOne → same index
/// - Single-item queue with repeatAll → same index
/// - Single-item queue with shuffle → null (no different index)
int? previousIndex(int current, int length, PlayMode mode, {Random? random}) {
  // Guard against out-of-bounds or empty queue.
  if (length == 0 || current < 0 || current >= length) return null;
  switch (mode) {
    case PlayMode.sequential:
      return current > 0 ? current - 1 : null;
    case PlayMode.repeatOne:
      return current;
    case PlayMode.repeatAll:
      return (current - 1 + length) % length;
    case PlayMode.shuffle:
      if (length <= 1) return null;
      final rng = random ?? Random();
      int prev;
      do {
        prev = rng.nextInt(length);
      } while (prev == current);
      return prev;
  }
}
