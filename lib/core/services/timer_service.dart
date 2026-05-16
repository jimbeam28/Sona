// lib/core/services/timer_service.dart
// Pure-logic timer state machine for the Timer module.
//
// Provides TMR-01 (set duration timer), TMR-02 (stop after current track),
// TMR-03 (countdown display), TMR-04 (cancel), and TMR-05 (expiry stop)
// as a fully testable state machine with no Flutter or platform dependencies.
//
// The [TimerService] manages the timer lifecycle:
//   startDuration(minutes) -> state becomes duration mode with endTime
//   startAfterCurrent()   -> state becomes afterCurrent mode
//   cancel()              -> state returns to null (idempotent)
//   checkExpired()        -> returns true if duration timer expired,
//                            clears state, and signals that pause() should
//                            be called (TMR-05)

/// The mode of an active sleep timer.
enum TimerMode {
  /// Fixed-duration countdown (TMR-01).
  duration,

  /// Stop after the current track finishes (TMR-02).
  afterCurrent,
}

/// Immutable value object representing the current sleep-timer state.
///
/// - [mode] is [TimerMode.duration] when a fixed-duration timer is active
///   and [TimerMode.afterCurrent] when "stop after current track" is set.
/// - [endTime] is set only for duration mode — the wall-clock time when
///   the timer will expire.
/// - [startedAt] is the wall-clock time when the timer was started.
class TimerState {
  final TimerMode mode;
  final DateTime? endTime;
  final DateTime startedAt;

  const TimerState({
    required this.mode,
    this.endTime,
    required this.startedAt,
  });

  /// Returns the remaining time until expiry, or `null` for afterCurrent mode.
  ///
  /// For duration mode, this is `endTime - now`.  When the timer has already
  /// passed its end time, returns [Duration.zero].
  /// TMR-T09: remaining time query returns correct Duration.
  Duration? get remainingTime {
    if (mode == TimerMode.afterCurrent) return null;
    if (endTime == null) return null;
    final now = DateTime.now();
    final remaining = endTime!.difference(now);
    return remaining.isNegative ? Duration.zero : remaining;
  }

  /// Whether the duration timer has passed its end time.
  ///
  /// For afterCurrent mode this is always `false` — expiry happens when
  /// the track ends, not based on wall-clock time.
  bool get isExpired {
    if (mode == TimerMode.afterCurrent) return false;
    if (endTime == null) return false;
    return !endTime!.isAfter(DateTime.now());
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TimerState &&
          mode == other.mode &&
          endTime == other.endTime;

  @override
  int get hashCode => Object.hash(mode, endTime);

  @override
  String toString() =>
      'TimerState(mode: $mode, endTime: $endTime, startedAt: $startedAt)';
}

/// Pure-logic sleep-timer service — TMR-01 through TMR-05.
///
/// Manages a single timer at a time.  Starting a new timer replaces any
/// active timer.  Cancellation is idempotent.  Expiry detection is a
/// synchronous check that the caller drives (e.g. via a periodic tick).
///
/// All methods are synchronous and side-effect-free except for updating
/// the internal [state].  The caller is responsible for:
///   - Calling [checkExpired] on a periodic interval
///   - Calling [AudioHandler.pause] when [checkExpired] returns true
///   - Showing the Snackbar when expiry happens in the foreground
///   - Listening for track-completion when in afterCurrent mode
class TimerService {
  TimerState? _state;

  /// The current timer state, or `null` if no timer is active.
  TimerState? get state => _state;

  /// Whether a timer is currently active.
  bool get isActive => _state != null;

  // ── TMR-01: Set fixed-duration timer ─────────────────────────────────────

  /// Starts a fixed-duration sleep timer for [minutes] minutes. (TMR-01)
  ///
  /// If a timer is already active it is replaced — the old timer's expiry
  /// will no longer trigger a stop (TMR-T04).
  ///
  /// Returns the new [TimerState] (never null).
  TimerState startDuration(int minutes) {
    // G-4: guard against negative input which would set endTime in the past.
    if (minutes < 0) throw ArgumentError.value(minutes, 'minutes', 'must not be negative');
    final now = DateTime.now();
    _state = TimerState(
      mode: TimerMode.duration,
      endTime: now.add(Duration(minutes: minutes)),
      startedAt: now,
    );
    return _state!;
  }

  // ── TMR-02: Set stop-after-current-track timer ────────────────────────────

  /// Sets the timer to stop after the current track finishes. (TMR-02)
  ///
  /// In this mode [state.remainingTime] returns `null` and [checkExpired]
  /// always returns `false`.  The caller must detect track completion
  /// separately and call [onTrackCompleted] to trigger the stop.
  ///
  /// If a duration timer was active it is replaced.
  TimerState startAfterCurrent() {
    _state = TimerState(
      mode: TimerMode.afterCurrent,
      startedAt: DateTime.now(),
    );
    return _state!;
  }

  /// Should be called by the caller when the current track finishes while
  /// in afterCurrent mode. (TMR-05)
  ///
  /// Returns `true` if the timer was in afterCurrent mode and the stop
  /// was triggered (the state is cleared).  Returns `false` if no
  /// afterCurrent timer was active.
  ///
  /// TMR-T06: track completion triggers pause, state cleared.
  /// TMR-T07: after triggering, state is null (no repeat).
  bool onTrackCompleted() {
    if (_state != null && _state!.mode == TimerMode.afterCurrent) {
      _state = null;
      return true;
    }
    return false;
  }

  // ── TMR-04: Cancel timer ─────────────────────────────────────────────────

  /// Cancels the active timer. (TMR-04)
  ///
  /// Idempotent: calling [cancel] when no timer is active is a no-op and
  /// does not throw (TMR-T18).
  ///
  /// After cancellation, the timer's expiry will NOT trigger a stop even
  /// if the wall clock passes the original end time (TMR-T17).
  ///
  /// Returns `true` if a timer was actually cancelled, `false` if there
  /// was no active timer.
  bool cancel() {
    final hadActive = _state != null;
    _state = null;
    return hadActive;
  }

  // ── TMR-05: Check for duration-timer expiry ──────────────────────────────

  /// Checks whether a duration timer has expired. (TMR-05)
  ///
  /// If a duration timer is active and has passed its [endTime]:
  ///   1. The state is cleared (set to null).
  ///   2. Returns `true` to signal that [AudioHandler.pause()] should be
  ///      called and a Snackbar shown (if in foreground).
  ///
  /// For afterCurrent mode, always returns `false` — use [onTrackCompleted]
  /// instead.
  ///
  /// TMR-T19: duration timer expiry triggers stop, state becomes null.
  bool checkExpired() {
    if (_state == null) return false;
    if (_state!.mode == TimerMode.afterCurrent) return false;
    if (_state!.isExpired) {
      _state = null;
      return true;
    }
    return false;
  }

  // ── TMR-03: Remaining-time display formatting ────────────────────────────

  /// Formats a [remaining] duration for display as MM:SS. (TMR-03)
  ///
  /// - `null` → `null` (no timer active or afterCurrent mode)
  /// - Otherwise → `MM:SS` (e.g. `04:35`, `00:45`)
  ///
  /// The [remaining] parameter should come from [TimerState.remainingTime].
  String? formatRemaining(Duration? remaining) {
    if (remaining == null) return null;
    final totalSeconds = remaining.inSeconds;
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  /// Returns the display string for the current timer state.
  ///
  /// - `null` if no timer is active (TMR-T14)
  /// - `null` for afterCurrent mode (TMR-T13) — the caller should display
  ///   "播完停止" instead
  /// - Formatted countdown for duration mode
  String? get displayString {
    if (_state == null) return null;
    if (_state!.mode == TimerMode.afterCurrent) return null;
    return formatRemaining(_state!.remainingTime);
  }

  /// Returns a label for the after-current mode (TMR-T25).
  static const String afterCurrentLabel = '播完停止';
}
