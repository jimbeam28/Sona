// lib/features/player/background_playback.dart
// Background playback state model for PLY-03.
//
// Provides pure-logic enums and a state machine that models audio focus,
// background playback, and notification-control transitions.  These are
// fully testable without AudioPlayer or platform channels.
//
// The actual audio_service wiring (Android foreground service, iOS
// background modes) lives in lib/core/services/audio_handler.dart
// (PLY-04); this module defines the application-level state that
// gates those behaviours.

import 'package:meta/meta.dart';

// ── Enums ───────────────────────────────────────────────────────────────────────

/// Audio focus states as defined by the system audio manager.
///
///   - [gained]: the app has audio focus (normal playback).
///   - [lost]: another app has taken focus permanently — playback should stop.
///   - [transient]: another app has taken focus temporarily (e.g. a
///     notification sound) — playback may duck but should resume afterwards.
enum AudioFocusState { gained, lost, transient }

/// Background playback states of the player.
///
///   - [playing]: audio is actively playing (foreground or background).
///   - [paused]:  audio is paused but the player session is still alive,
///     so it can be resumed from a notification or lock-screen control.
///   - [stopped]: the player session has been torn down; a new [play]
///     must be issued to restart.
enum BackgroundPlaybackState { playing, paused, stopped }

/// The user-facing playback action from notification / lock-screen controls.
///
/// These are the actions that external UI (notification, lock screen,
/// headset buttons) can trigger on the background player.
enum MediaControlAction { play, pause, stop, togglePlayPause }

// ── State machine ───────────────────────────────────────────────────────────────

/// Immutable value object that captures the state of background audio playback.
///
/// The state transitions are driven by two orthogonal inputs:
///   1. **App lifecycle** — when the app moves between foreground and
///      background, [isInForeground] changes but audio continues.
///   2. **Media controls** — pause / play actions from notification or
///      lock-screen controls.
///
/// The invariants are:
///   - Audio continues playing when the app transitions to background
///     as long as [backgroundEnabled] is true.
///   - Pausing from a notification sets [playbackState] to [paused]
///     but does not tear down the background session.
///   - Lock-screen state (a system concern) does not interrupt playback.
@immutable
class BackgroundPlaybackConfig {
  /// Whether background playback is enabled by the user/app config.
  final bool backgroundEnabled;

  /// Whether the app is currently in the foreground.
  final bool isInForeground;

  /// The current audio focus status.
  final AudioFocusState audioFocus;

  /// The current playback state of the background player.
  final BackgroundPlaybackState playbackState;

  const BackgroundPlaybackConfig({
    this.backgroundEnabled = true,
    this.isInForeground = true,
    this.audioFocus = AudioFocusState.gained,
    this.playbackState = BackgroundPlaybackState.stopped,
  });

  // ── Factory constructors ──────────────────────────────────────────────────

  /// Initial state: background playback enabled, app in foreground,
  /// player stopped.
  static const initial = BackgroundPlaybackConfig();

  /// Convenience for a playing state with the given configuration.
  factory BackgroundPlaybackConfig.playing({
    bool backgroundEnabled = true,
    bool isInForeground = true,
    AudioFocusState audioFocus = AudioFocusState.gained,
  }) {
    return BackgroundPlaybackConfig(
      backgroundEnabled: backgroundEnabled,
      isInForeground: isInForeground,
      audioFocus: audioFocus,
      playbackState: BackgroundPlaybackState.playing,
    );
  }

  /// Convenience for a paused state.
  factory BackgroundPlaybackConfig.paused({
    bool backgroundEnabled = true,
    bool isInForeground = true,
    AudioFocusState audioFocus = AudioFocusState.gained,
  }) {
    return BackgroundPlaybackConfig(
      backgroundEnabled: backgroundEnabled,
      isInForeground: isInForeground,
      audioFocus: audioFocus,
      playbackState: BackgroundPlaybackState.paused,
    );
  }

  // ── State transitions ─────────────────────────────────────────────────────

  /// Returns a new state with [isInForeground] updated and, if the app has
  /// gone to background with [backgroundEnabled] == true, audio continues
  /// playing (PLY-T20).
  BackgroundPlaybackConfig updateForeground(bool inForeground) {
    // When going to background with background playback enabled,
    // the playback state is NOT affected — audio continues.
    if (!inForeground && backgroundEnabled) {
      return copyWith(isInForeground: false);
    }
    // When coming back to foreground, it's a no-op on playback.
    // When background is disabled and app goes to background,
    // we could stop, but the default behaviour is to keep the state
    // as-is — the platform layer (audio_service) handles that.
    return copyWith(isInForeground: inForeground);
  }

  /// Handles a media control action from notification or lock screen
  /// (PLY-T21, PLY-T22).
  ///
  /// Returns a new state with the playback state updated based on the action.
  BackgroundPlaybackConfig handleMediaControl(MediaControlAction action) {
    switch (action) {
      case MediaControlAction.play:
        return copyWith(playbackState: BackgroundPlaybackState.playing);
      case MediaControlAction.pause:
        return copyWith(playbackState: BackgroundPlaybackState.paused);
      case MediaControlAction.stop:
        return copyWith(playbackState: BackgroundPlaybackState.stopped);
      case MediaControlAction.togglePlayPause:
        return playbackState == BackgroundPlaybackState.playing
            ? copyWith(playbackState: BackgroundPlaybackState.paused)
            : copyWith(playbackState: BackgroundPlaybackState.playing);
    }
  }

  /// Updates the audio focus state.  When focus is [lost], playback
  /// should stop; when focus is [gained] (e.g. call ended), playback
  /// may resume if it was previously playing.
  BackgroundPlaybackConfig updateAudioFocus(AudioFocusState focus) {
    switch (focus) {
      case AudioFocusState.gained:
        // If we were playing before losing focus, resume.
        // Otherwise just mark focus as gained.
        return copyWith(audioFocus: AudioFocusState.gained);
      case AudioFocusState.lost:
        // Permanently lost focus — stop playback.
        return copyWith(
          audioFocus: AudioFocusState.lost,
          playbackState: BackgroundPlaybackState.paused,
        );
      case AudioFocusState.transient:
        // Temporary loss — duck but keep playing state.
        return copyWith(audioFocus: AudioFocusState.transient);
    }
  }

  // ── Queries ────────────────────────────────────────────────────────────────

  /// Whether audio should be actively producing sound right now.
  ///
  /// This is true when:
  ///   - The playback state is [playing], AND
  ///   - Audio focus has not been permanently lost.
  bool get isAudioActive =>
      playbackState == BackgroundPlaybackState.playing &&
      audioFocus != AudioFocusState.lost;

  /// Whether the notification / lock-screen should show the "pause" action.
  bool get showPauseAction => playbackState == BackgroundPlaybackState.playing;

  /// Whether the notification / lock-screen should show the "play" action.
  bool get showPlayAction =>
      playbackState != BackgroundPlaybackState.playing &&
      playbackState != BackgroundPlaybackState.stopped;

  // ── copyWith ──────────────────────────────────────────────────────────────

  BackgroundPlaybackConfig copyWith({
    bool? backgroundEnabled,
    bool? isInForeground,
    AudioFocusState? audioFocus,
    BackgroundPlaybackState? playbackState,
  }) {
    return BackgroundPlaybackConfig(
      backgroundEnabled: backgroundEnabled ?? this.backgroundEnabled,
      isInForeground: isInForeground ?? this.isInForeground,
      audioFocus: audioFocus ?? this.audioFocus,
      playbackState: playbackState ?? this.playbackState,
    );
  }

  // ── Equality ──────────────────────────────────────────────────────────────

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BackgroundPlaybackConfig &&
          backgroundEnabled == other.backgroundEnabled &&
          isInForeground == other.isInForeground &&
          audioFocus == other.audioFocus &&
          playbackState == other.playbackState;

  @override
  int get hashCode => Object.hash(
        backgroundEnabled,
        isInForeground,
        audioFocus,
        playbackState,
      );

  @override
  String toString() => 'BackgroundPlaybackConfig('
      'backgroundEnabled: $backgroundEnabled, '
      'isInForeground: $isInForeground, '
      'audioFocus: $audioFocus, '
      'playbackState: $playbackState)';
}
