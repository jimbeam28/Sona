// lib/shared/models/play_progress.dart
// Data model for saved playback progress.
//
// Each record tracks where the user left off in a given file so that
// playback can be resumed later (Progress module).  For BRW-04 the model is
// used to decide whether to show a resume dialog when a file is tapped.

/// Saved playback position for a specific file on a specific connection.
class PlayProgress {
  final int connectionId;
  final String filePath;
  final int positionMs;
  final int? durationMs;
  final DateTime lastPlayedAt;

  const PlayProgress({
    required this.connectionId,
    required this.filePath,
    required this.positionMs,
    this.durationMs,
    required this.lastPlayedAt,
  });

  /// Playback progress as a fraction [0.0, 1.0].
  /// Returns 0.0 when [durationMs] is null or zero.
  double get percentage {
    if (durationMs != null && durationMs! > 0) {
      return (positionMs / durationMs!).clamp(0.0, 1.0);
    }
    return 0.0;
  }

  /// Human-readable position string.
  ///
  /// Formats as `H:MM:SS` when the position is >= 1 hour,
  /// otherwise `M:SS` or `MM:SS`.
  String get formattedPosition {
    final totalSeconds = positionMs ~/ 1000;
    final hours = totalSeconds ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    final seconds = totalSeconds % 60;

    if (hours > 0) {
      return '$hours:'
          '${minutes.toString().padLeft(2, '0')}:'
          '${seconds.toString().padLeft(2, '0')}';
    }
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  String toString() =>
      'PlayProgress(connectionId: $connectionId, filePath: $filePath, '
      'positionMs: $positionMs, durationMs: $durationMs)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PlayProgress &&
          connectionId == other.connectionId &&
          filePath == other.filePath &&
          positionMs == other.positionMs &&
          durationMs == other.durationMs;

  @override
  int get hashCode =>
      Object.hash(connectionId, filePath, positionMs, durationMs);
}
