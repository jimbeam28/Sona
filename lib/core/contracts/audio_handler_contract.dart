// lib/core/contracts/audio_handler_contract.dart
// Abstract interface wrapping NasAudioHandler (audio_service).
//
// This contract decouples the domain/presentation layers from the concrete
// BaseAudioHandler implementation, enabling fakes/mocks for testing without
// platform channels or audio_service initialization.

import 'package:audio_service/audio_service.dart';

import '../../features/player/background_playback.dart';
import '../services/audio_handler.dart';

/// Abstract interface for the audio service handler.
///
/// Mirrors the subset of [NasAudioHandler] methods used by the application
/// so that providers and widgets can depend on this interface rather than
/// the concrete class.
abstract class IAudioHandler {
  // ── Streams ─────────────────────────────────────────────────────────────

  /// Stream of playback state changes (for notification / lock-screen).
  ///
  /// Uses the same [BehaviorSubject] type from BaseAudioHandler.
  /// Consumers can access `.value` for the current state and `.add()` to
  /// push updates.
  Stream<PlaybackState> get playbackStateStream;

  /// Stream of the current media item metadata.
  Stream<MediaItem?> get mediaItemStream;

  // ── Properties ──────────────────────────────────────────────────────────

  /// The current background-playback configuration.
  BackgroundPlaybackConfig get config;

  // ── Media actions ───────────────────────────────────────────────────────

  /// Starts or resumes playback.
  Future<void> play();

  /// Pauses playback.
  Future<void> pause();

  /// Stops playback.
  Future<void> stop();

  /// Seeks to the given [position].
  Future<void> seek(Duration position);

  /// Sets the playback speed.
  Future<void> setSpeed(double speed);

  /// Skips to the next track.
  Future<void> skipToNext();

  /// Skips to the previous track.
  Future<void> skipToPrevious();

  // ── Media item ──────────────────────────────────────────────────────────

  /// Updates the notification media item to represent [filePath].
  void setMediaItemFromPath(String filePath, {Duration? duration});

  // ── Audio focus ─────────────────────────────────────────────────────────

  /// Drives the background-playback state machine with an audio-focus change.
  void onAudioFocusChange(AudioFocusState focus);

  // ── Callbacks ───────────────────────────────────────────────────────────

  /// Callback for when the handler needs to advance to the next track.
  set onSkipToNextRequested(NextTrackCallback? callback);

  /// Callback for when the handler needs to go to the previous track.
  set onSkipToPreviousRequested(PreviousTrackCallback? callback);

  /// Callback fired when the background-playback config changes.
  set onConfigChanged(ConfigChangeCallback? callback);

  // ── Cleanup ─────────────────────────────────────────────────────────────

  /// Releases all resources.
  void dispose();
}
