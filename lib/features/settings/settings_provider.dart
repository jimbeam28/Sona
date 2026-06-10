// lib/features/settings/settings_provider.dart
// Riverpod providers for the Settings feature.
//
// All business logic is delegated to [SettingsService] (domain layer).
// This file only handles dependency assembly and ref.invalidate().
//
// SET-01: default_playback_speed (wraps player_provider)
// SET-03: theme_mode
// SET-04: seek_step_seconds

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../shared/di/providers.dart';
import 'domain/settings_service.dart';

// ── Domain service singleton ─────────────────────────────────────────────────

/// Shared [SettingsService] instance used by all providers and re-exported
/// pure-function wrappers.
const _service = SettingsService();

// ── Theme mode (SET-03) ─────────────────────────────────────────────────────

/// Returns the [ThemeMode] stored in [prefs], or [ThemeMode.system] if not set.
///
/// Delegates to [SettingsService.getThemeMode].
ThemeMode getThemeMode(SharedPreferences? prefs) =>
    _service.getThemeMode(prefs);

/// Persists [mode] to SharedPreferences.
///
/// Delegates to [SettingsService.setThemeMode].
void setThemeMode(SharedPreferences? prefs, ThemeMode mode) =>
    _service.setThemeMode(prefs, mode);

/// Human-readable Chinese label for a [ThemeMode].
///
/// Delegates to [SettingsService.labelForThemeMode].
String labelForThemeMode(ThemeMode mode) => _service.labelForThemeMode(mode);

/// The currently active theme mode, persisted to SharedPreferences.
final themeModeProvider = Provider<ThemeMode>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return _service.getThemeMode(prefs);
});

/// Persists a new theme mode to SharedPreferences and invalidates
/// [themeModeProvider] so that it re-reads the updated value.
final setThemeModeProvider = Provider<void Function(ThemeMode)>((ref) {
  return (ThemeMode mode) {
    debugPrint('[Settings] themeMode: ${mode.name}');
    final prefs = ref.read(sharedPreferencesProvider);
    _service.setThemeMode(prefs, mode);
    ref.invalidate(themeModeProvider);
  };
});

// ── Seek step (SET-04) ─────────────────────────────────────────────────────

/// Available seek step options in seconds.
const List<int> seekStepOptions = [10, 15, 30, 60];

/// Persists [seconds] to SharedPreferences if it is one of the valid
/// [seekStepOptions].
///
/// Delegates to [SettingsService.setSeekStep].
bool setSeekStep(SharedPreferences? prefs, int seconds) =>
    _service.setSeekStep(prefs, seconds);

/// Human-readable Chinese label for a seek step value.
///
/// Delegates to [SettingsService.labelForSeekStep].
String labelForSeekStep(int seconds) => _service.labelForSeekStep(seconds);

// ── Remember speed (F-4) ─────────────────────────────────────────────────────

/// Returns whether the "remember playback speed" setting is enabled.
///
/// Delegates to [SettingsService.getRememberSpeed].
bool getRememberSpeed(SharedPreferences? prefs) =>
    _service.getRememberSpeed(prefs);

/// The "remember speed" setting — when enabled, adjusting speed during playback
/// also updates the default speed so it persists across song changes.
final rememberSpeedProvider = Provider<bool>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return _service.getRememberSpeed(prefs);
});

/// Persists the remember-speed preference.
final setRememberSpeedProvider = Provider<void Function(bool)>((ref) {
  return (bool value) {
    debugPrint('[Settings] rememberSpeed: $value');
    _service.setRememberSpeed(ref.read(sharedPreferencesProvider), value);
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
    debugPrint('[Settings] seekStep: ${seconds}s');
    _service.setSeekStep(ref.read(sharedPreferencesProvider), seconds);
    ref.invalidate(seekStepSettingProvider);
    // Also update the runtime seek step used by the player.
    ref.read(seekStepProvider.notifier).state = seconds;
  };
});
