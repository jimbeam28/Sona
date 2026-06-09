// lib/core/contracts/audio_player_contract.dart
// Abstract interface wrapping just_audio.AudioPlayer.
//
// This contract decouples the domain/presentation layers from the concrete
// just_audio implementation, enabling fakes/mocks for testing without
// platform channels.

import 'dart:async';

import 'package:just_audio/just_audio.dart';

/// Abstract interface for audio playback.
///
/// Mirrors the subset of [AudioPlayer] methods used by the application so
/// that [PlaybackOrchestrator], player providers, and UI widgets can depend
/// on this interface rather than the concrete class.
abstract class IAudioPlayer {
  // ── Streams ─────────────────────────────────────────────────────────────

  /// Stream of player state changes (playing + processingState).
  Stream<PlayerState> get playerStateStream;

  /// Stream of current playback position.
  Stream<Duration> get positionStream;

  /// Stream of audio duration (null until metadata is available).
  Stream<Duration?> get durationStream;

  /// Stream of processing state changes.
  Stream<ProcessingState> get processingStateStream;

  // ── Properties ──────────────────────────────────────────────────────────

  /// Whether the player is currently playing.
  bool get playing;

  /// The current playback position.
  Duration get position;

  /// The duration of the current audio source, or null if not available.
  Duration? get duration;

  /// The buffered position.
  Duration get bufferedPosition;

  /// The current playback speed.
  double get speed;

  /// The current audio source, or null if none is set.
  AudioSource? get audioSource;

  // ── Actions ─────────────────────────────────────────────────────────────

  /// Sets the audio source and prepares for playback.
  Future<Duration?> setAudioSource(AudioSource source);

  /// Starts or resumes playback.
  Future<void> play();

  /// Pauses playback.
  Future<void> pause();

  /// Stops playback and resets the position.
  Future<void> stop();

  /// Seeks to the given [position].
  Future<void> seek(Duration position);

  /// Sets the playback speed.
  Future<void> setSpeed(double speed);

  /// Releases all resources.
  Future<void> dispose();
}
