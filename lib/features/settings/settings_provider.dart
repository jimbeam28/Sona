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

// REF-04 (SET2): seek step options, validation, and label formatting are
// canonical in speed_manager.dart; re-exported here so settings consumers
// keep a single settings-side import surface.
export '../player/domain/speed_manager.dart'
    show seekStepOptions, setSeekStep, labelForSeekStep;

// ── Domain service singleton ─────────────────────────────────────────────────

/// Shared [SettingsService] instance used by all providers and re-exported
/// pure-function wrappers.
const _service = SettingsService();

// ── Theme mode (SET-03) ─────────────────────────────────────────────────────

/// Returns the [ThemeMode] stored in [prefs], or [ThemeMode.system] if not set.
///
/// REF-01-S2: the domain layer stores theme mode as a String; this provider
/// boundary maps the String back to the [ThemeMode] enum.
ThemeMode getThemeMode(SharedPreferences? prefs) {
  final raw = _service.getThemeMode(prefs);
  return ThemeMode.values.cast<ThemeMode?>().firstWhere(
        (e) => e!.name == raw,
        orElse: () => ThemeMode.system,
      )!;
}

/// Persists [mode] to SharedPreferences.
///
/// REF-01-S2: maps the [ThemeMode] enum to its name String for the domain
/// layer.  Storage key and value format are unchanged.
void setThemeMode(SharedPreferences? prefs, ThemeMode mode) =>
    _service.setThemeMode(prefs, mode.name);

/// Human-readable Chinese label for a [ThemeMode].
///
/// REF-01-S2: delegates to the domain layer's String-based label function.
String labelForThemeMode(ThemeMode mode) =>
    _service.labelForThemeMode(mode.name);

/// The currently active theme mode, persisted to SharedPreferences.
final themeModeProvider = Provider<ThemeMode>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return getThemeMode(prefs);
});

/// Persists a new theme mode to SharedPreferences and invalidates
/// [themeModeProvider] so that it re-reads the updated value.
final setThemeModeProvider = Provider<void Function(ThemeMode)>((ref) {
  return (ThemeMode mode) {
    debugPrint('[Settings] themeMode: ${mode.name}');
    final prefs = ref.read(sharedPreferencesProvider);
    setThemeMode(prefs, mode);
    ref.invalidate(themeModeProvider);
  };
});

// ── Seek step (SET-04) ─────────────────────────────────────────────────────

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
/// REF-01-A5: reads SharedPreferences directly (the domain layer no longer
/// exposes a reader function).  When SharedPreferences is unavailable (test
/// environments) defaults to 15.
final seekStepSettingProvider = Provider<int>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return prefs?.getInt(seekStepPrefsKey) ?? defaultSeekStep;
});

/// Persists a new seek step to SharedPreferences and invalidates
/// [seekStepSettingProvider] so the player picks up the new value.
///
/// REF-04 (DI1): [seekStepSettingProvider] is the single data source for the
/// seek step — there is no player-side copy to sync anymore.
final setSeekStepSettingProvider = Provider<void Function(int)>((ref) {
  return (int seconds) {
    debugPrint('[Settings] seekStep: ${seconds}s');
    if (!setSeekStep(ref.read(sharedPreferencesProvider), seconds)) return;
    ref.invalidate(seekStepSettingProvider);
  };
});
