// lib/features/player/background_playback_notifier.dart
// FIX-06: BackgroundPlaybackNotifier + Provider split from domain layer.
//
// This file holds the Riverpod/Flutter-dependent parts that were previously
// in domain/background_playback.dart.  The pure-logic types and functions
// remain in the domain file.
//
// REF-03 (cr-20260816-0802 D1 裁决 A): the notifier is now a read-only mirror
// of the production state machine owned by NasAudioHandler._config.  All the
// former drive-input methods (onAppLifecycleChange / onMediaControl /
// onAudioFocusChange / startPlayback / pausePlayback / stopPlayback /
// setBackgroundEnabled) had no production callers and were removed; the only
// entry point left is [BackgroundPlaybackNotifier.syncFromHandler], wired via
// backgroundPlaybackSyncProvider (BUG-02 dependency).

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'domain/background_playback.dart';

/// Read-only mirror of the background-playback state machine.
///
/// The production state machine lives in `NasAudioHandler._config`
/// (lib/core/services/audio_handler.dart); every transition is pushed here
/// through [syncFromHandler] so the Riverpod layer stays in sync without
/// owning any transition logic.
class BackgroundPlaybackNotifier
    extends StateNotifier<BackgroundPlaybackConfig> {
  BackgroundPlaybackNotifier() : super(BackgroundPlaybackConfig.initial);

  /// Mirrors the config pushed by [NasAudioHandler] so the Riverpod layer
  /// stays in sync with the handler's internal state machine.
  void syncFromHandler(BackgroundPlaybackConfig config) {
    state = config;
  }
}

/// Provider for the background-playback state notifier.
final backgroundPlaybackProvider =
    StateNotifierProvider<BackgroundPlaybackNotifier, BackgroundPlaybackConfig>(
  (ref) => BackgroundPlaybackNotifier(),
);
