// lib/features/settings/domain/settings_service.dart
// Pure Dart domain service for settings persistence.
//
// Extracted from settings_provider.dart (REF-27) so that theme, speed,
// and seek step read/write logic can be tested independently of
// Flutter widgets and Riverpod providers.
//
// Zero Flutter widget dependencies — only shared_preferences for storage.

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

/// Pure Dart service for reading and writing settings to SharedPreferences.
///
/// All methods are instance-level and accept a [SharedPreferences] instance
/// (or null) so they can be tested without platform channels.
class SettingsService {
  const SettingsService();

  // ── Theme mode ──────────────────────────────────────────────────────────

  /// Returns the [ThemeMode] stored in [prefs], or [ThemeMode.system] if not set.
  ThemeMode getThemeMode(SharedPreferences? prefs) {
    if (prefs == null) return ThemeMode.system;
    final saved = prefs.getString(_themeModeKey);
    if (saved == null) return ThemeMode.system;
    return ThemeMode.values.cast<ThemeMode?>().firstWhere(
          (e) => e!.name == saved,
          orElse: () => ThemeMode.system,
        )!;
  }

  /// Persists [mode] to [prefs].
  ///
  /// Does nothing if [prefs] is null.
  void setThemeMode(SharedPreferences? prefs, ThemeMode mode) {
    prefs?.setString(_themeModeKey, mode.name);
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

  /// Human-readable Chinese label for a [ThemeMode].
  String labelForThemeMode(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.system:
        return '跟随系统';
      case ThemeMode.light:
        return '亮色';
      case ThemeMode.dark:
        return '暗色';
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
