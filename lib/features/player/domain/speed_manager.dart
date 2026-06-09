// lib/features/player/domain/speed_manager.dart
// Pure Dart domain logic for playback speed management.
//
// Extracted from player_provider.dart (REF-10) so they can be tested
// independently of Flutter widgets and Riverpod.
//
// Functions:
//   speedOptions   — the 6 available playback speed multipliers
//   isValidSpeed   — checks if a speed is one of the valid options
//   getDefaultSpeed — reads default speed from SharedPreferences
//   readSeekStep   — reads seek step from SharedPreferences
//
// Zero Flutter widget dependencies — only shared_preferences for storage.

import 'package:shared_preferences/shared_preferences.dart';

/// SharedPreferences key for the default playback speed.
const defaultSpeedKey = 'default_playback_speed';

/// SharedPreferences key for the seek step setting.
const seekStepPrefsKey = 'seek_step_seconds';

/// Default seek step in seconds.
const defaultSeekStep = 15;

/// Available playback speed multipliers.
const List<double> speedOptions = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0];

/// Returns `true` if [speed] is one of the valid [speedOptions].
///
/// Uses a tolerance of 0.01 for floating-point comparison.
/// Pure function — testable without any providers or platform channels.
bool isValidSpeed(double speed) {
  return speedOptions.any((s) => (s - speed).abs() < 0.01);
}

/// Returns the default playback speed from [prefs], or 1.0 if not set.
///
/// Pure function — testable without any providers or platform channels.
double getDefaultSpeed(SharedPreferences? prefs) {
  if (prefs == null) return 1.0;
  final value = prefs.getDouble(defaultSpeedKey);
  return value ?? 1.0;
}

/// Returns the seek step stored in [prefs], or [defaultSeekStep] if not set.
///
/// Pure function — testable without any providers or platform channels.
int readSeekStep(SharedPreferences? prefs) {
  if (prefs == null) return defaultSeekStep;
  return prefs.getInt(seekStepPrefsKey) ?? defaultSeekStep;
}
