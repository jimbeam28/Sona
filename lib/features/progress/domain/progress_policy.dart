// lib/features/progress/domain/progress_policy.dart
// Pure-function policy for deciding when to save or clear playback progress.
//
// Extracted from ProgressDao to keep the decision logic testable
// independently of the database layer.  Zero Flutter dependencies.

/// Returns `true` when [positionMs] is >= 5 000 ms.
///
/// Positions under 5 seconds are considered "not started" and should not
/// be saved (PRG-T03, PRG-T05).
bool shouldSave(int positionMs) => positionMs >= 5000;

/// Returns `true` when the position is past the "finished" threshold.
///
/// A file is considered finished when its position exceeds
/// `duration - 10 000` ms (10 seconds before the end).
/// In this case the progress record should be cleared rather than saved
/// (PRG-T04, PRG-T06).
///
/// Returns `false` when [durationMs] is null (unknown duration).
/// Returns `false` when [durationMs] <= 10 000 ms (short file protection, G-3).
bool shouldClear(int positionMs, int? durationMs) {
  if (durationMs == null) return false;
  // G-3: files shorter than 10 s should never auto-clear — the 10-second
  // window is meaningless when the file itself is shorter than that.
  if (durationMs <= 10000) return false;
  return positionMs > durationMs - 10000;
}
