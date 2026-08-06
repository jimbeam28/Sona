// lib/core/services/audio_player_adapter.dart
// REF-01-A4: production adapter that bridges just_audio's concrete
// AudioPlayer to the IAudioPlayer contract.
//
// The domain layer (PlaybackOrchestrator) depends only on IAudioPlayer;
// this adapter is the single place that maps contract calls onto the
// concrete plugin class.

import 'dart:async';

import 'package:just_audio/just_audio.dart';

import '../contracts/audio_player_contract.dart';

/// Wraps a concrete [AudioPlayer] behind the [IAudioPlayer] contract.
class AudioPlayerAdapter implements IAudioPlayer {
  final AudioPlayer _impl;

  AudioPlayerAdapter(this._impl);

  // ── Streams ─────────────────────────────────────────────────────────────

  @override
  Stream<PlayerState> get playerStateStream => _impl.playerStateStream;

  @override
  Stream<Duration> get positionStream => _impl.positionStream;

  @override
  Stream<Duration?> get durationStream => _impl.durationStream;

  @override
  Stream<ProcessingState> get processingStateStream =>
      _impl.processingStateStream;

  // ── Properties ──────────────────────────────────────────────────────────

  @override
  bool get playing => _impl.playing;

  @override
  Duration get position => _impl.position;

  @override
  Duration? get duration => _impl.duration;

  @override
  Duration get bufferedPosition => _impl.bufferedPosition;

  @override
  double get speed => _impl.speed;

  @override
  AudioSource? get audioSource => _impl.audioSource;

  // ── Actions ─────────────────────────────────────────────────────────────

  @override
  Future<Duration?> setAudioSource(AudioSource source) =>
      _impl.setAudioSource(source);

  @override
  Future<void> play() => _impl.play();

  @override
  Future<void> pause() => _impl.pause();

  @override
  Future<void> stop() => _impl.stop();

  @override
  Future<void> seek(Duration position) => _impl.seek(position);

  @override
  Future<void> setSpeed(double speed) => _impl.setSpeed(speed);

  @override
  Future<void> dispose() => _impl.dispose();
}
