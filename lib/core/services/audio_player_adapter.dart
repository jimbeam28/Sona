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
  // BUG-08（cr-20260816-0802 F4）：P17 分层表 5s 平台层补齐到 IAudioPlayer
  // 通道。语义分层：
  //   setAudioSource —— 加载成败判定点，超时必须以 TimeoutException 结束
  //     （orchestrator catch → failed → 不 play，杜绝 ghost）；
  //   seek/setSpeed/play/pause/stop —— 超时静默返回（BUG-17 同款裁决，
  //     P4：平台调用失败不向用户冒泡；seek 另因 restore 路径
  //     player_provider.dart:237 无 try 包裹，抛错即 unhandled）。
  static const _platformTimeout = Duration(seconds: 5);

  @override
  Future<Duration?> setAudioSource(AudioSource source) =>
      _impl.setAudioSource(source).timeout(_platformTimeout);

  @override
  Future<void> play() =>
      _impl.play().timeout(_platformTimeout, onTimeout: () {});

  @override
  Future<void> pause() =>
      _impl.pause().timeout(_platformTimeout, onTimeout: () {});

  @override
  Future<void> stop() =>
      _impl.stop().timeout(_platformTimeout, onTimeout: () {});

  @override
  Future<void> seek(Duration position) =>
      _impl.seek(position).timeout(_platformTimeout, onTimeout: () {});

  @override
  Future<void> setSpeed(double speed) =>
      _impl.setSpeed(speed).timeout(_platformTimeout, onTimeout: () {});

  @override
  Future<void> setVolume(double volume) => _impl.setVolume(volume);

  @override
  Future<void> dispose() => _impl.dispose();
}
