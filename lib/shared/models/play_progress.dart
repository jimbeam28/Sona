// lib/shared/models/play_progress.dart
// Data model for saved playback progress.
//
// Each record tracks where the user left off in a given file so that
// playback can be resumed later (Progress module).  For BRW-04 the model is
// used to decide whether to show a resume dialog when a file is tapped.

/// Saved playback position for a specific file on a specific connection.
class PlayProgress {
  final int? id;
  final int connectionId;
  final String filePath;
  final int positionMs;
  final int? durationMs;
  final DateTime lastPlayedAt;

  const PlayProgress({
    this.id,
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

  // ── Database serialisation ────────────────────────────────────────────────

  /// Creates a [PlayProgress] from a database row map.
  factory PlayProgress.fromMap(Map<String, dynamic> map) {
    return PlayProgress(
      id: map['id'] as int?,
      connectionId: map['connection_id'] as int,
      filePath: map['file_path'] as String,
      positionMs: map['position_ms'] as int,
      durationMs: map['duration_ms'] as int?,
      lastPlayedAt:
          DateTime.fromMillisecondsSinceEpoch(map['last_played_at'] as int),
    );
  }

  /// Converts this model to a database row map suitable for INSERT/UPDATE.
  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'connection_id': connectionId,
      'file_path': filePath,
      'position_ms': positionMs,
      'duration_ms': durationMs,
      'last_played_at': lastPlayedAt.millisecondsSinceEpoch,
    };
  }

  // ── copyWith ──────────────────────────────────────────────────────────────

  /// Returns a copy with selectively overridden fields.
  PlayProgress copyWith({
    int? id,
    int? connectionId,
    String? filePath,
    int? positionMs,
    int? durationMs,
    bool clearDuration = false,
    DateTime? lastPlayedAt,
  }) {
    return PlayProgress(
      id: id ?? this.id,
      connectionId: connectionId ?? this.connectionId,
      filePath: filePath ?? this.filePath,
      positionMs: positionMs ?? this.positionMs,
      durationMs: clearDuration ? null : (durationMs ?? this.durationMs),
      lastPlayedAt: lastPlayedAt ?? this.lastPlayedAt,
    );
  }

  @override
  String toString() =>
      'PlayProgress(id: $id, connectionId: $connectionId, filePath: $filePath, '
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
