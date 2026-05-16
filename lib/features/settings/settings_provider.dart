// lib/features/settings/settings_provider.dart
// Riverpod providers for the Settings feature.
//
// Provides:
//   - themeModeProvider    — persists ThemeMode to SharedPreferences
//   - defaultSpeed setters — re-exported from player_provider
//   - seekStep persistence — extended from player_provider
//
// SET-01: default_playback_speed (wraps player_provider)
// SET-03: theme_mode
// SET-04: seek_step_seconds

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../browser/browser_provider.dart';
import '../player/player_provider.dart';

// ── Theme mode (SET-03) ─────────────────────────────────────────────────────────

/// SharedPreferences key for the theme mode setting.
const _themeModeKey = 'theme_mode';

/// Returns the [ThemeMode] stored in [prefs], or [ThemeMode.system] if not set.
///
/// Pure function — testable without any providers or platform channels.
ThemeMode getThemeMode(SharedPreferences? prefs) {
  if (prefs == null) return ThemeMode.system;
  final saved = prefs.getString(_themeModeKey);
  if (saved == null) return ThemeMode.system;
  return ThemeMode.values.cast<ThemeMode?>().firstWhere(
        (e) => e!.name == saved,
        orElse: () => ThemeMode.system,
      )!;
}

/// Persists [mode] to SharedPreferences.
///
/// Pure function — testable without any providers or platform channels.
void setThemeMode(SharedPreferences? prefs, ThemeMode mode) {
  prefs?.setString(_themeModeKey, mode.name);
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

/// The currently active theme mode, persisted to SharedPreferences.
///
/// Reads the value from SharedPreferences on first access.  When
/// SharedPreferences is unavailable (test environments) defaults to
/// [ThemeMode.system].
final themeModeProvider = Provider<ThemeMode>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return getThemeMode(prefs);
});

/// Persists a new theme mode to SharedPreferences and invalidates
/// [themeModeProvider] so that it re-reads the updated value.
final setThemeModeProvider = Provider<void Function(ThemeMode)>((ref) {
  return (ThemeMode mode) {
    final prefs = ref.read(sharedPreferencesProvider);
    setThemeMode(prefs, mode);
    ref.invalidate(themeModeProvider);
  };
});

// ── Seek step (SET-04) ─────────────────────────────────────────────────────────

/// SharedPreferences key for the seek step setting.
const _seekStepKey = 'seek_step_seconds';

/// Available seek step options in seconds.
const List<int> seekStepOptions = [10, 15, 30, 60];

/// Persists [seconds] to SharedPreferences if it is one of the valid
/// [seekStepOptions].
///
/// Returns `true` if the value was persisted, `false` otherwise.
bool setSeekStep(SharedPreferences? prefs, int seconds) {
  if (!seekStepOptions.contains(seconds)) return false;
  prefs?.setInt(_seekStepKey, seconds);
  return true;
}

/// Human-readable Chinese label for a seek step value.
String labelForSeekStep(int seconds) {
  return '$seconds秒';
}

// ── Remember speed (F-4) ─────────────────────────────────────────────────────

const _rememberSpeedKey = 'remember_playback_speed';

/// Returns whether the "remember playback speed" setting is enabled.
bool getRememberSpeed(SharedPreferences? prefs) {
  if (prefs == null) return false;
  return prefs.getBool(_rememberSpeedKey) ?? false;
}

/// The "remember speed" setting — when enabled, adjusting speed during playback
/// also updates the default speed so it persists across song changes.
final rememberSpeedProvider = Provider<bool>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return getRememberSpeed(prefs);
});

/// Persists the remember-speed preference.
final setRememberSpeedProvider = Provider<void Function(bool)>((ref) {
  return (bool value) {
    ref.read(sharedPreferencesProvider)?.setBool(_rememberSpeedKey, value);
    ref.invalidate(rememberSpeedProvider);
  };
});

/// The seek step setting, persisted to SharedPreferences.
///
/// Reads the value from SharedPreferences on first access.  When
/// SharedPreferences is unavailable (test environments) defaults to 15.
final seekStepSettingProvider = Provider<int>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return readSeekStep(prefs);
});

/// Persists a new seek step to SharedPreferences and invalidates both
/// [seekStepSettingProvider] and [seekStepProvider] so that the player
/// picks up the new value.
final setSeekStepSettingProvider = Provider<void Function(int)>((ref) {
  return (int seconds) {
    setSeekStep(ref.read(sharedPreferencesProvider), seconds);
    ref.invalidate(seekStepSettingProvider);
    // Also update the runtime seek step used by the player.
    ref.read(seekStepProvider.notifier).state = seconds;
  };
});
