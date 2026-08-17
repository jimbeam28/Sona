// lib/core/contracts/progress_policy.dart
// Pure-function policy for deciding when to save or clear playback progress.
//
// Moved from lib/features/progress/domain/progress_policy.dart (REF-09):
// the data layer (ProgressDao) consumes this policy, so it must live in the
// core layer to keep core→feature dependency direction clean.  Zero Flutter
// dependencies.

/// Returns `true` when [positionMs] is >= 5 000 ms.
///
/// Positions under 5 seconds are considered "not started" and should not
/// be saved (PRG-T03, PRG-T05).
bool shouldSave(int positionMs) => positionMs >= 5000;

/// Returns `true` when the position is past the "finished" threshold.
///
/// A file is considered finished when its position exceeds
/// `duration - window`, where window = `clamp(ceil(duration * 10%), 1000, 10000)`
/// (BUG-20: dynamic window — a fixed 10 s window aggressively cleared
/// 10-15 s short files whose save threshold is only 5 s; long files
/// (duration >= 100 000 ms) keep the original 10 s window).
/// In this case the progress record should be cleared rather than saved
/// (PRG-T04, PRG-T06).
///
/// Returns `false` when [durationMs] is null (unknown duration).
/// Returns `false` when [durationMs] <= 10 000 ms (short file protection, G-3).
bool shouldClear(int positionMs, int? durationMs) {
  if (durationMs == null) return false;
  if (durationMs <= 10000) return false;
  final window = (durationMs * 0.1).ceil().clamp(1000, 10000);
  return positionMs > durationMs - window;
}
