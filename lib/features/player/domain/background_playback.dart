// lib/features/player/domain/background_playback.dart
// REF-13: Background playback state machine extracted to domain layer.
//
// Moved from lib/features/player/background_playback.dart and
// lib/features/player/player_provider.dart.
//
// REF-02 (S6): AudioFocusState / BackgroundPlaybackState / MediaControlAction
// and BackgroundPlaybackConfig now live in core/contracts
// (background_playback_contract.dart) so the contract layer can reference
// them without a feature-layer import (CTR3).  They are re-exported here for
// backward compatibility — downstream `import .../background_playback.dart`
// callers are unchanged.
//
// Contains:
//   - AppLifecyclePhase — pure-Dart mirror of Flutter's AppLifecycleState
//   - shouldContinueInBackground() — pure helper function
//   - computePlaybackStateAfterLifecycle() — pure helper function
//
// Zero platform dependencies — fully testable in plain Dart.

import '../../../core/contracts/background_playback_contract.dart';

export '../../../core/contracts/background_playback_contract.dart';

// ── Enums ───────────────────────────────────────────────────────────────────────

/// Lifecycle phases — mirrors Flutter's [AppLifecycleState] but without
/// the Flutter dependency.
///
/// Each value maps 1:1 to the corresponding [AppLifecycleState] variant.
enum AppLifecyclePhase { resumed, inactive, paused, detached, hidden }

// ── Pure helper functions ──────────────────────────────────────────────────────

/// Helper function that determines whether playback should continue
/// when the app transitions to background, given the current
/// background-enabled flag and playback state.
///
/// This is a pure function, fully testable without widgets or platform
/// channels (PLY-T20).
///
/// Returns `true` if audio should continue in background.
bool shouldContinueInBackground({
  required bool backgroundEnabled,
  required BackgroundPlaybackState currentPlaybackState,
}) {
  if (!backgroundEnabled) return false;
  // Only continue if the player is actively playing.
  return currentPlaybackState == BackgroundPlaybackState.playing;
}

/// Pure function: given an [AppLifecyclePhase] and playback state,
/// returns the expected [BackgroundPlaybackState] after the transition.
///
/// This models the lifecycle-handling logic without depending on
/// StateNotifier or AudioPlayer, so it can be tested in isolation
/// (PLY-T20).
BackgroundPlaybackConfig computePlaybackStateAfterLifecycle({
  required AppLifecyclePhase newState,
  required bool backgroundEnabled,
  required BackgroundPlaybackState currentPlaybackState,
}) {
  switch (newState) {
    case AppLifecyclePhase.resumed:
      // Coming back to foreground — playback state unchanged.
      return BackgroundPlaybackConfig(
        backgroundEnabled: backgroundEnabled,
        isInForeground: true,
        playbackState: currentPlaybackState,
      );
    case AppLifecyclePhase.inactive:
    case AppLifecyclePhase.paused:
    case AppLifecyclePhase.hidden:
      // Going to background — if background is enabled and audio is
      // playing, it should continue.
      if (!shouldContinueInBackground(
        backgroundEnabled: backgroundEnabled,
        currentPlaybackState: currentPlaybackState,
      )) {
        // If background playback is disabled or player is not playing,
        // the state reflects that the app is in background but audio
        // state is unchanged (it may already be paused/stopped).
        return BackgroundPlaybackConfig(
          backgroundEnabled: backgroundEnabled,
          isInForeground: false,
          playbackState: currentPlaybackState,
        );
      }
      // Background playback enabled and audio is playing — continue.
      return BackgroundPlaybackConfig(
        backgroundEnabled: backgroundEnabled,
        isInForeground: false,
        playbackState: BackgroundPlaybackState.playing,
      );
    case AppLifecyclePhase.detached:
      return BackgroundPlaybackConfig(
        backgroundEnabled: backgroundEnabled,
        isInForeground: false,
        playbackState: BackgroundPlaybackState.stopped,
      );
  }
}
