// lib/shared/models/play_queue.dart
// Data model for the audio playback queue.
//
// The queue holds an ordered list of audio files and tracks which file is
// currently being played.  It is built by the Browser module (BRW-04) when
// the user taps an audio file, and consumed by the Player module.
//
// PLY-05: 播放队列管理 — adds PlayMode support and queue-navigation logic
// (nextIndex / previousIndex) so the Player module can implement skip-to-next,
// skip-to-previous, and mode-aware queue wrapping.

import 'dart:math';

import 'nas_file.dart';

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

/// Represents a sequential play queue of audio files.
///
/// [files] contains only audio (non-directory) entries, ordered by the
/// current directory sort.  [currentIndex] points to the file that should
/// start playing first.
///
/// [startPositionMs] is an optional resume position (milliseconds).  When
/// non-null the Player module should seek to this position before starting
/// playback.
///
/// [playMode] controls what happens when a track ends (sequential by default).
class PlayQueue {
  final List<NasFile> files;
  final int currentIndex;
  final int? startPositionMs;
  final PlayMode playMode;

  const PlayQueue({
    required this.files,
    required this.currentIndex,
    this.startPositionMs,
    this.playMode = PlayMode.sequential,
  });

  /// The file currently being played.
  NasFile get current => files[currentIndex];

  /// Whether there is another file after the current one.
  bool get hasNext => currentIndex < files.length - 1;

  /// Whether there is a file before the current one.
  bool get hasPrevious => currentIndex > 0;

  /// Total number of audio files in the queue.
  int get length => files.length;

  /// Returns a copy of this queue with a different [playMode].
  PlayQueue withMode(PlayMode mode) => PlayQueue(
        files: files,
        currentIndex: currentIndex,
        startPositionMs: startPositionMs,
        playMode: mode,
      );

  /// Returns a copy of this queue with a different [currentIndex].
  PlayQueue withIndex(int newIndex) => PlayQueue(
        files: files,
        currentIndex: newIndex,
        startPositionMs: startPositionMs,
        playMode: playMode,
      );

  /// Returns a copy of this queue with a different [startPositionMs].
  PlayQueue withStartPosition(int? ms) => PlayQueue(
        files: files,
        currentIndex: currentIndex,
        startPositionMs: ms,
        playMode: playMode,
      );

  /// Returns a copy of this queue with the track at [index] removed.
  ///
  /// Adjusts [currentIndex] so it still points to the same logical track:
  /// - If the removed track is before [currentIndex], decrement
  /// - If the removed track IS [currentIndex], keep the same index (the next
  ///   track shifts into this position) unless it was the last track
  PlayQueue withoutIndex(int index) {
    final newList = files.toList();
    newList.removeAt(index);
    if (newList.isEmpty) {
      return PlayQueue(
        files: newList,
        currentIndex: 0,
        startPositionMs: null,
        playMode: playMode,
      );
    }
    int newIndex = currentIndex;
    if (index < currentIndex) {
      newIndex = currentIndex - 1;
    } else if (index == currentIndex) {
      if (currentIndex >= newList.length) {
        newIndex = newList.length - 1;
      }
    }
    return PlayQueue(
      files: newList,
      currentIndex: newIndex,
      startPositionMs: index == currentIndex ? null : startPositionMs,
      playMode: playMode,
    );
  }

  // ── Queue navigation (PLY-05) ──────────────────────────────────────────

  /// Returns the index of the next track given [mode], or `null` when
  /// playback should stop (sequential mode at end of queue).
  ///
  /// [current] is the current index (0-based).  [length] is the number of
  /// items in the queue.  [random] is used for shuffle mode; if not
  /// provided a default [Random] is used.  Providing a seeded [Random]
  /// makes the function deterministic for testing.
  ///
  /// PLY-T32 (sequential at end → null), PLY-T33 (repeatAll wraps),
  /// PLY-T34 (shuffle returns different index), PLY-T35 (repeatOne).
  static int? nextIndex(int current, int length, PlayMode mode,
      {Random? random}) {
    // H-4: guard against out-of-bounds current index.
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
  static int? previousIndex(int current, int length, PlayMode mode,
      {Random? random}) {
    // H-4: guard against out-of-bounds current index.
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

  // ── Persistence helpers (PLY-T37) ───────────────────────────────────────

  /// Serialises this queue to a JSON-compatible map.
  ///
  /// File identities are stored as paths; the caller is responsible for
  /// reconstructing [NasFile] objects on deserialisation.
  Map<String, dynamic> toMap() => {
        'filePaths': files.map((f) => f.path).toList(),
        'currentIndex': currentIndex,
        'startPositionMs': startPositionMs,
        'playMode': playMode.name,
      };

  /// Reconstructs a [PlayQueue] from a previously-serialised map and a
  /// list of resolved [NasFile] objects.
  ///
  /// The [files] list must be provided externally because [NasFile]
  /// carries metadata that cannot be serialised inline (it is rebuilt from
  /// the file system or cache on app restart).
  factory PlayQueue.fromMap(Map<String, dynamic> map, List<NasFile> files) {
    final modeName = map['playMode'] as String?;
    final mode = modeName != null
        ? PlayMode.values.firstWhere((m) => m.name == modeName,
            orElse: () => PlayMode.sequential)
        : PlayMode.sequential;
    return PlayQueue(
      files: files,
      currentIndex: map['currentIndex'] as int? ?? 0,
      startPositionMs: map['startPositionMs'] as int?,
      playMode: mode,
    );
  }

  @override
  String toString() =>
      'PlayQueue(files: ${files.length}, currentIndex: $currentIndex, '
      'startPositionMs: $startPositionMs, playMode: $playMode)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PlayQueue &&
          _listEquals(files, other.files) &&
          currentIndex == other.currentIndex &&
          startPositionMs == other.startPositionMs &&
          playMode == other.playMode;

  @override
  int get hashCode =>
      Object.hash(Object.hashAll(files), currentIndex, startPositionMs,
          playMode);
}

/// Shallow list equality helper used by [PlayQueue.==].
bool _listEquals<T>(List<T> a, List<T> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (int i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
