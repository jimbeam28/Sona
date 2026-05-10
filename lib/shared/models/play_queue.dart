// lib/shared/models/play_queue.dart
// Data model for the audio playback queue.
//
// The queue holds an ordered list of audio files and tracks which file is
// currently being played.  It is built by the Browser module (BRW-04) when
// the user taps an audio file, and consumed by the Player module.

import 'nas_file.dart';

/// Represents a sequential play queue of audio files.
///
/// [files] contains only audio (non-directory) entries, ordered by the
/// current directory sort.  [currentIndex] points to the file that should
/// start playing first.
///
/// [startPositionMs] is an optional resume position (milliseconds).  When
/// non-null the Player module should seek to this position before starting
/// playback.
class PlayQueue {
  final List<NasFile> files;
  final int currentIndex;
  final int? startPositionMs;

  const PlayQueue({
    required this.files,
    required this.currentIndex,
    this.startPositionMs,
  });

  /// The file currently being played.
  NasFile get current => files[currentIndex];

  /// Whether there is another file after the current one.
  bool get hasNext => currentIndex < files.length - 1;

  /// Whether there is a file before the current one.
  bool get hasPrevious => currentIndex > 0;

  /// Total number of audio files in the queue.
  int get length => files.length;

  @override
  String toString() =>
      'PlayQueue(files: ${files.length}, currentIndex: $currentIndex, '
      'startPositionMs: $startPositionMs)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PlayQueue &&
          _listEquals(files, other.files) &&
          currentIndex == other.currentIndex &&
          startPositionMs == other.startPositionMs;

  @override
  int get hashCode =>
      Object.hash(Object.hashAll(files), currentIndex, startPositionMs);
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
