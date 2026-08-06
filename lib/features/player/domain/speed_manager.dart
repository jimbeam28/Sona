// lib/features/player/domain/speed_manager.dart
// Pure Dart domain logic for playback speed management.
//
// Extracted from player_provider.dart (REF-10) so they can be tested
// independently of Flutter widgets and Riverpod.
//
// REF-04 (SET2): canonical home for the speed/step keys, options,
// validation, and write helpers — settings_service no longer defines them.
// The SharedPreferences type arrives via shared/preferences_bridge.dart
// (REF-01-A1 pattern) so this file stays free of plugin-package imports.

import '../../../shared/preferences_bridge.dart';

/// SharedPreferences key for the default playback speed.
const defaultSpeedKey = 'default_playback_speed';

/// SharedPreferences key for the seek step setting.
const seekStepPrefsKey = 'seek_step_seconds';

/// Default seek step in seconds.
const defaultSeekStep = 15;

/// Available playback speed multipliers.
const List<double> speedOptions = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0];

/// Available seek step options in seconds.
const List<int> seekStepOptions = [10, 15, 30, 60];

/// Returns `true` if [speed] is one of the valid [speedOptions].
///
/// Uses a tolerance of 0.01 for floating-point comparison.
/// Pure function — testable without any providers or platform channels.
bool isValidSpeed(double speed) {
  return speedOptions.any((s) => (s - speed).abs() < 0.01);
}

/// Persists [speed] to [prefs] if it is a valid speed option.
///
/// Returns `true` if the value was persisted, `false` otherwise.
bool setDefaultSpeed(SharedPreferences? prefs, double speed) {
  if (!isValidSpeed(speed)) return false;
  prefs?.setDouble(defaultSpeedKey, speed);
  return true;
}

/// Persists [seconds] to [prefs] if it is a valid seek step option.
///
/// Returns `true` if the value was persisted, `false` otherwise.
bool setSeekStep(SharedPreferences? prefs, int seconds) {
  if (!seekStepOptions.contains(seconds)) return false;
  prefs?.setInt(seekStepPrefsKey, seconds);
  return true;
}

/// Human-readable Chinese label for a seek step value.
String labelForSeekStep(int seconds) {
  return '$seconds秒';
}
