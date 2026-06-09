// lib/features/timer/timer_provider.dart
// Riverpod providers for the Timer feature — TMR-01 through TMR-05.
//
// Provides:
//   - [timerServiceProvider] — the singleton [TimerService] instance.
//   - [timerStateProvider] — a [StateNotifierProvider] that wraps the service
//     and exposes the active [TimerState] (or null).
//   - [remainingTimeProvider] — a [StreamProvider] that emits the remaining
//     [Duration] every second while a duration timer is active (TMR-03/TMR-T15).
//   - [formattedRemainingProvider] — a derived [Provider] that formats the
//     remaining time for display.
//   - [timerActiveProvider] — convenience [Provider] that returns whether a
//     timer is currently active.
//   - [timerModeProvider] — convenience [Provider] that returns the current
//     [TimerMode] or null.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../browser/browser_provider.dart';
import 'domain/timer_service.dart';

// ── Service instance ──────────────────────────────────────────────────────────

/// The singleton [TimerService] used application-wide.
///
/// Created lazily on first read and kept alive for the app lifetime.
final timerServiceProvider = Provider<TimerService>((ref) {
  final service = TimerService();
  ref.onDispose(() {}); // no-op — the service has no resources to release
  return service;
});

// ── Timer state ───────────────────────────────────────────────────────────────

/// TMR-01: Notifier that wraps [TimerService] and automatically keeps
/// the timer state in sync without manual [ref.invalidate] calls.
///
/// All timer actions go through this notifier so UI listeners are
/// notified automatically on every state change.
class TimerStateNotifier extends Notifier<TimerState?> {
  TimerService get _service => ref.read(timerServiceProvider);

  @override
  TimerState? build() => _service.state;

  void startDuration(int minutes) {
    debugPrint('[Timer] startDuration: ${minutes}min');
    _service.startDuration(minutes);
    ref.read(setLastCustomTimerMinutesProvider)(minutes);
    state = _service.state;
  }

  void startAfterCurrent() {
    debugPrint('[Timer] startAfterCurrent');
    _service.startAfterCurrent();
    state = _service.state;
  }

  void cancel() {
    debugPrint('[Timer] cancel');
    _service.cancel();
    state = _service.state;
  }

  /// Returns `true` if the duration timer expired and pause should be called.
  bool checkExpired() {
    final expired = _service.checkExpired();
    if (expired) {
      debugPrint('[Timer] expired, pausing');
      state = _service.state;
    }
    return expired;
  }

  /// Returns `true` if an afterCurrent timer was active and triggered the stop.
  bool onTrackCompleted() {
    final triggered = _service.onTrackCompleted();
    if (triggered) {
      debugPrint('[Timer] afterCurrent completed, triggering stop');
      state = _service.state;
    }
    return triggered;
  }

  // TMR-03: pause/resume support
  void pause() {
    _service.pause();
    state = _service.state;
  }

  void resume() {
    _service.resume();
    state = _service.state;
  }
}

/// TMR-01: uses [TimerStateNotifier] so state updates auto-notify listeners.
final timerStateProvider =
    NotifierProvider<TimerStateNotifier, TimerState?>(TimerStateNotifier.new);

// ── Timer active ──────────────────────────────────────────────────────────────

/// Returns `true` when a timer is currently active.
final timerActiveProvider = Provider<bool>((ref) {
  final state = ref.watch(timerStateProvider);
  return state != null;
});

// ── Timer mode ────────────────────────────────────────────────────────────────

/// Returns the current [TimerMode], or `null` if no timer is active.
final timerModeProvider = Provider<TimerMode?>((ref) {
  final state = ref.watch(timerStateProvider);
  return state?.mode;
});

// ── Last custom duration (C-3) ───────────────────────────────────────────────

const lastCustomTimerMinutesKey = 'last_custom_timer_minutes';

int? readLastCustomTimerMinutes(dynamic prefs) {
  if (prefs == null) return null;
  final value = prefs.getInt(lastCustomTimerMinutesKey);
  if (value == null || value <= 0) return null;
  return value;
}

final lastCustomTimerMinutesProvider = Provider<int?>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return readLastCustomTimerMinutes(prefs);
});

final setLastCustomTimerMinutesProvider = Provider<void Function(int)>((ref) {
  return (int minutes) {
    if (minutes <= 0) return;
    ref
        .read(sharedPreferencesProvider)
        ?.setInt(lastCustomTimerMinutesKey, minutes);
    ref.invalidate(lastCustomTimerMinutesProvider);
  };
});

// ── Remaining time stream (TMR-03) ────────────────────────────────────────────

/// Emits the remaining [Duration] every second while a duration timer is
/// active. Emits `null` when no duration timer is set or in afterCurrent mode.
///
/// TMR-T15: countdown updates every second.
final remainingTimeProvider = StreamProvider<Duration?>((ref) {
  final state = ref.watch(timerStateProvider);

  if (state == null || state.mode != TimerMode.duration) {
    return Stream.value(null);
  }

  // Emit the remaining time every second.  Stop the stream (by emitting
  // null which takeWhile discards) when the timer is cancelled or reaches
  // zero.
  var didEmitZero = false;
  return Stream.periodic(const Duration(seconds: 1), (_) {
    final currentState = ref.read(timerStateProvider);
    if (currentState == null || currentState.mode != TimerMode.duration) {
      return null;
    }
    return currentState.remainingTime;
  }).takeWhile((d) {
    if (d == null) return false;
    if (d == Duration.zero) {
      if (didEmitZero) return false;
      didEmitZero = true;
      return true;
    }
    return true;
  });
});

// ── Formatted remaining display (TMR-03) ──────────────────────────────────────

/// Returns the formatted display string for the current timer state.
///
/// - `null` when no timer is active or in afterCurrent mode.
/// - `"X分钟"` or `"Xs"` for duration mode countdown.
///
/// For afterCurrent mode, the UI should show [TimerService.afterCurrentLabel]
/// ("播完停止") instead.
final formattedRemainingProvider = Provider<String?>((ref) {
  final remaining = ref.watch(remainingTimeProvider).valueOrNull;
  final service = ref.watch(timerServiceProvider);
  return service.formatRemaining(remaining);
});

// ── Timer actions ─────────────────────────────────────────────────────────────

/// Provider of the [VoidCallback] to set a duration timer (TMR-01).
///
/// Usage: `ref.read(startDurationTimerProvider)(5)` for 5 minutes.
final startDurationTimerProvider = Provider<void Function(int minutes)>((ref) {
  return (int minutes) {
    ref.read(timerStateProvider.notifier).startDuration(minutes);
  };
});

/// Provider of the [VoidCallback] to set after-current mode (TMR-02).
final startAfterCurrentProvider = Provider<void Function()>((ref) {
  return () {
    ref.read(timerStateProvider.notifier).startAfterCurrent();
  };
});

/// Provider of the [VoidCallback] to cancel the active timer (TMR-04).
final cancelTimerProvider = Provider<void Function()>((ref) {
  return () {
    ref.read(timerStateProvider.notifier).cancel();
  };
});

/// Provider of a function that checks timer expiry (TMR-05).
///
/// Returns `true` if the duration timer expired and pause should be called.
/// The caller should then call `AudioHandler.pause()` and show a Snackbar
/// if the app is in the foreground.
final checkTimerExpiryProvider = Provider<bool Function()>((ref) {
  return () {
    return ref.read(timerStateProvider.notifier).checkExpired();
  };
});

/// Provider of a function called when a track completes (TMR-02 expiry).
///
/// Returns `true` if an afterCurrent timer was active and triggered the stop.
/// The caller should then call `AudioHandler.pause()`.
final onTrackCompletedProvider = Provider<bool Function()>((ref) {
  return () {
    return ref.read(timerStateProvider.notifier).onTrackCompleted();
  };
});
