// lib/features/progress/domain/progress_service.dart
// Domain service for the Progress feature.
//
// Encapsulates the orchestration logic for progress persistence and
// the resume-dialog state machine.  Pure Dart — no Flutter/Riverpod
// dependencies — so it can be unit-tested with plain constructors.
//
// REF-25: Extracted from progress_provider.dart
//   - 5 save trigger-point orchestration (delegate to ProgressDao.upsert)
//   - Resume-dialog state management (countdown state machine)

import 'dart:async';

import '../../../core/database/dao/progress_dao.dart';
import '../../../shared/models/play_progress.dart';

// ── Save trigger points ──────────────────────────────────────────────────────

/// Enumerates the 5 playback events that trigger a progress save.
///
/// Each value maps to a distinct call-site in the player layer:
/// 1. [periodic]  — 10-second auto-save timer
/// 2. [pause]     — player transitions from playing to paused
/// 3. [skipNext]  — user (or auto-advance) skips to the next track
/// 4. [skipPrev]  — user skips to the previous track
/// 5. [complete]  — current track finishes playback
enum SaveTrigger {
  periodic,
  pause,
  skipNext,
  skipPrev,
  complete,
}

/// Pure-logic service that coordinates progress persistence and the
/// resume-dialog countdown state machine.
///
/// All dependencies are injected through the constructor so the class
/// has zero service-locator / Flutter dependencies.
class ProgressService {
  final ProgressDao _dao;

  ProgressService({ProgressDao? dao}) : _dao = dao ?? ProgressDao();

  // ── Progress persistence ─────────────────────────────────────────────────

  /// Saves playback progress for the given [trigger].
  ///
  /// Delegates to [ProgressDao.upsert] which applies the business rules
  /// (skip < 5 s, clear near end).  Returns the DAO result:
  ///   `true`  — record created / updated
  ///   `false` — save skipped (position < 5 s)
  ///   `null`  — record cleared (position near end of track)
  Future<bool?> saveProgress({
    required int connectionId,
    required String filePath,
    required int positionMs,
    int? durationMs,
    SaveTrigger trigger = SaveTrigger.periodic,
  }) {
    return _dao.upsert(
      connectionId: connectionId,
      filePath: filePath,
      positionMs: positionMs,
      durationMs: durationMs,
    );
  }

  /// Looks up saved progress for a file on a connection.
  Future<PlayProgress?> getProgress(int connectionId, String filePath) {
    return _dao.find(connectionId, filePath);
  }

  /// Deletes saved progress for a file on a connection.
  Future<void> clearProgress(int connectionId, String filePath) {
    return _dao.delete(connectionId, filePath);
  }

  // ── Resume dialog state machine ──────────────────────────────────────────

  static const int _defaultCountdownSeconds = 5;

  /// Creates the initial [ResumeDialogState] for the given [progress].
  ///
  /// The countdown starts at [_defaultCountdownSeconds] (5).
  ResumeDialogState showResumeDialog(PlayProgress progress) {
    return ResumeDialogState(
      progress: progress,
      countdownSeconds: _defaultCountdownSeconds,
    );
  }

  /// Advances the countdown by one second and returns the new state.
  ///
  /// When the countdown reaches 0 the returned state has [isExpired] == true.
  /// The caller should treat an expired state as "auto-select continue".
  ResumeDialogState tickCountdown(ResumeDialogState current) {
    if (current.isExpired) return current;
    final next = current.countdownSeconds - 1;
    return current.copyWith(countdownSeconds: next <= 0 ? 0 : next);
  }
}

// ── Resume dialog state ──────────────────────────────────────────────────────

/// Immutable state for the progress-resume confirmation dialog.
///
/// Encapsulates the saved [progress] record and the auto-select
/// [countdownSeconds].  When [countdownSeconds] reaches 0 the dialog
/// should auto-select "继续播放" (resume from saved position).
class ResumeDialogState {
  final PlayProgress progress;
  final int countdownSeconds;

  const ResumeDialogState({
    required this.progress,
    this.countdownSeconds = 5,
  });

  /// Whether the countdown has reached zero.
  bool get isExpired => countdownSeconds <= 0;

  ResumeDialogState copyWith({int? countdownSeconds}) {
    return ResumeDialogState(
      progress: progress,
      countdownSeconds: countdownSeconds ?? this.countdownSeconds,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ResumeDialogState &&
          progress == other.progress &&
          countdownSeconds == other.countdownSeconds;

  @override
  int get hashCode => Object.hash(progress, countdownSeconds);

  @override
  String toString() =>
      'ResumeDialogState(progress: $progress, countdownSeconds: $countdownSeconds)';
}
