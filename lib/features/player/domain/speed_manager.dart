// lib/features/player/domain/speed_manager.dart
// Pure Dart domain logic for playback speed management.
//
// Extracted from player_provider.dart (REF-10) so they can be tested
// independently of Flutter widgets and Riverpod.
//
// Constants:
//   speedOptions   — the 6 available playback speed multipliers
//   defaultSpeedKey / seekStepPrefsKey / defaultSeekStep — persistence keys
// Pure function:
//   isValidSpeed   — checks if a speed is one of the valid options
//
// REF-01-A5: persistence reads (getDefaultSpeed / readSeekStep) moved to the
// provider layer — callers read SharedPreferences directly.

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
