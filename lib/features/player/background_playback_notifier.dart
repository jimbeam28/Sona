// lib/features/player/background_playback_notifier.dart
// FIX-06: BackgroundPlaybackNotifier + Provider split from domain layer.
//
// This file holds the Riverpod/Flutter-dependent parts that were previously
// in domain/background_playback.dart.  The pure-logic types and functions
// remain in the domain file.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'domain/background_playback.dart';

/// Maps Flutter's [AppLifecycleState] to the domain layer's [AppLifecyclePhase].
AppLifecyclePhase mapLifecycleState(AppLifecycleState state) => switch (state) {
      AppLifecycleState.resumed => AppLifecyclePhase.resumed,
      AppLifecycleState.inactive => AppLifecyclePhase.inactive,
      AppLifecycleState.paused => AppLifecyclePhase.paused,
      AppLifecycleState.detached => AppLifecyclePhase.detached,
      AppLifecycleState.hidden => AppLifecyclePhase.hidden,
    };

/// Manages the background-playback state machine (PLY-T20~T23).
///
/// Exposed as a [StateNotifier] so that both the player screen and the
/// app-lifecycle observer can drive transitions.  The state machine is
/// pure logic — it does not touch [AudioPlayer] directly, making it
/// fully testable.
class BackgroundPlaybackNotifier
    extends StateNotifier<BackgroundPlaybackConfig> {
  BackgroundPlaybackNotifier() : super(BackgroundPlaybackConfig.initial);

  /// Call when the app lifecycle changes (foreground <-> background).
  ///
  /// If background playback is enabled, audio should continue playing
  /// when the app goes to background (PLY-T20).
  void onAppLifecycleChange(AppLifecycleState lifecycleState) {
    switch (lifecycleState) {
      case AppLifecycleState.resumed:
        state = state.updateForeground(true);
      case AppLifecycleState.inactive:
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
        // App going to background — audio continues if backgroundEnabled.
        state = state.updateForeground(false);
      case AppLifecycleState.detached:
        // App being destroyed — stop playback.
        state = state.copyWith(
          isInForeground: false,
          playbackState: BackgroundPlaybackState.stopped,
        );
    }
  }

  /// Call when a notification media-control action is received
  /// (PLY-T21, PLY-T22).
  void onMediaControl(MediaControlAction action) {
    state = state.handleMediaControl(action);
  }

  /// Call when audio focus changes (e.g. another app starts/stops
  /// playing audio).
  void onAudioFocusChange(AudioFocusState focus) {
    state = state.updateAudioFocus(focus);
  }

  /// Start playback (sets state to playing).
  void startPlayback() {
    state = state.copyWith(playbackState: BackgroundPlaybackState.playing);
  }

  /// Pause playback (sets state to paused).
  void pausePlayback() {
    state = state.copyWith(playbackState: BackgroundPlaybackState.paused);
  }

  /// Stop playback and tear down the background session.
  void stopPlayback() {
    state = state.copyWith(playbackState: BackgroundPlaybackState.stopped);
  }

  /// Toggle background playback enabled flag.
  void setBackgroundEnabled(bool enabled) {
    state = state.copyWith(backgroundEnabled: enabled);
  }

  /// Mirrors the config pushed by [NasAudioHandler] so the Riverpod layer
  /// stays in sync with the handler's internal state machine (PLY-F).
  void syncFromHandler(BackgroundPlaybackConfig config) {
    state = config;
  }
}

/// Provider for the background-playback state notifier.
final backgroundPlaybackProvider =
    StateNotifierProvider<BackgroundPlaybackNotifier, BackgroundPlaybackConfig>(
  (ref) => BackgroundPlaybackNotifier(),
);
