// lib/features/settings/domain/settings_service.dart
// Pure Dart domain service for settings persistence.
//
// Extracted from settings_provider.dart (REF-27) so that theme and
// remember-speed read/write logic can be tested independently of
// Flutter widgets and Riverpod providers.
//
// REF-01-A1: theme mode is represented as a String ('system'/'light'/'dark')
// instead of the Flutter ThemeMode enum — zero Flutter dependencies.
//
// REF-04 (SET2): speed/step keys, options, validation, and write helpers
// were removed from this file — speed_manager.dart is their single
// canonical home.  Only theme + remember-speed remain here.

import '../../../shared/preferences_bridge.dart';

/// SharedPreferences keys used by the settings service.
const _themeModeKey = 'theme_mode';
const _rememberSpeedKey = 'remember_playback_speed';

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
