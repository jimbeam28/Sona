// lib/features/settings/domain/settings_service.dart
// Pure Dart domain service for settings persistence.
//
// Extracted from settings_provider.dart (REF-27) so that theme, speed,
// and seek step read/write logic can be tested independently of
// Flutter widgets and Riverpod providers.
//
// REF-01-A1: theme mode is represented as a String ('system'/'light'/'dark')
// instead of the Flutter ThemeMode enum — zero Flutter dependencies.

import '../../../shared/preferences_bridge.dart';

/// SharedPreferences keys used by the settings service.
const _themeModeKey = 'theme_mode';
const _defaultSpeedKey = 'default_playback_speed';
const _seekStepKey = 'seek_step_seconds';
const _rememberSpeedKey = 'remember_playback_speed';

/// Default values for settings.
const _defaultSeekStep = 15;

/// Available seek step options in seconds.
const List<int> seekStepOptions = [10, 15, 30, 60];

/// Available playback speed multipliers.
const List<double> speedOptions = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0];

/// Reads the theme mode stored in [prefs] as a String
/// (`'system'`/`'light'`/`'dark'`), or `'system'` when not set (REF-01-A1).
String getThemeMode(SharedPreferences? prefs) {
  if (prefs == null) return 'system';
  final raw = prefs.getString(_themeModeKey);
  if (raw != 'system' && raw != 'light' && raw != 'dark') return 'system';
  return raw!;
}

/// Persists the theme mode [mode] (a String: `'system'`/`'light'`/`'dark'`)
/// to [prefs] (REF-01-A1).
void setThemeMode(SharedPreferences? prefs, String mode) {
  prefs?.setString(_themeModeKey, mode);
}

/// Human-readable Chinese label for a theme mode String (REF-01-A1).
String labelForThemeMode(String mode) {
  switch (mode) {
    case 'light':
      return '亮色';
    case 'dark':
      return '暗色';
    default:
      return '跟随系统';
  }
}

/// Pure Dart service for reading and writing settings to SharedPreferences.
///
/// All methods are instance-level and accept a [SharedPreferences] instance
/// (or null) so they can be tested without platform channels.
class SettingsService {
  const SettingsService();

  // ── Theme mode ──────────────────────────────────────────────────────────

  /// Returns the theme mode stored in [prefs] as a String
  /// (`'system'`/`'light'`/`'dark'`), or `'system'` if not set (REF-01-A1).
  String getThemeMode(SharedPreferences? prefs) {
    if (prefs == null) return 'system';
    final raw = prefs.getString(_themeModeKey);
    if (raw != 'system' && raw != 'light' && raw != 'dark') return 'system';
    return raw!;
  }

  /// Persists the theme mode [mode] (a String) to [prefs] (REF-01-A1).
  ///
  /// Does nothing if [prefs] is null.
  void setThemeMode(SharedPreferences? prefs, String mode) {
    prefs?.setString(_themeModeKey, mode);
  }

  // ── Default speed ───────────────────────────────────────────────────────

  /// Returns the default playback speed from [prefs], or 1.0 if not set.
  double getDefaultSpeed(SharedPreferences? prefs) {
    if (prefs == null) return 1.0;
    final value = prefs.getDouble(_defaultSpeedKey);
    return value ?? 1.0;
  }

  /// Persists [speed] to [prefs] if it is a valid speed option.
  ///
  /// Returns `true` if the value was persisted, `false` otherwise.
  bool setDefaultSpeed(SharedPreferences? prefs, double speed) {
    if (!isValidSpeed(speed)) return false;
    prefs?.setDouble(_defaultSpeedKey, speed);
    return true;
  }

  /// Returns `true` if [speed] is one of the valid [speedOptions].
  bool isValidSpeed(double speed) {
    return speedOptions.any((s) => (s - speed).abs() < 0.01);
  }

  // ── Seek step ───────────────────────────────────────────────────────────

  /// Returns the seek step stored in [prefs], or [_defaultSeekStep] if not set.
  int getSeekStep(SharedPreferences? prefs) {
    if (prefs == null) return _defaultSeekStep;
    return prefs.getInt(_seekStepKey) ?? _defaultSeekStep;
  }

  /// Persists [seconds] to [prefs] if it is a valid seek step option.
  ///
  /// Returns `true` if the value was persisted, `false` otherwise.
  bool setSeekStep(SharedPreferences? prefs, int seconds) {
    if (!seekStepOptions.contains(seconds)) return false;
    prefs?.setInt(_seekStepKey, seconds);
    return true;
  }

  /// Human-readable Chinese label for a theme mode String (REF-01-A1).
  String labelForThemeMode(String mode) {
    switch (mode) {
      case 'light':
        return '亮色';
      case 'dark':
        return '暗色';
      default:
        return '跟随系统';
    }
  }

  /// Human-readable Chinese label for a seek step value.
  String labelForSeekStep(int seconds) {
    return '$seconds秒';
  }

  // ── Remember speed ────────────────────────────────────────────────────

  /// Returns whether the "remember playback speed" setting is enabled.
  bool getRememberSpeed(SharedPreferences? prefs) {
    if (prefs == null) return false;
    return prefs.getBool(_rememberSpeedKey) ?? false;
  }

  /// Persists the remember-speed preference.
  void setRememberSpeed(SharedPreferences? prefs, bool value) {
    prefs?.setBool(_rememberSpeedKey, value);
  }
}
