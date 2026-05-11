// lib/core/services/audio_handler.dart
// Android audio_service handler for background playback and media controls.
//
// Implements [BaseAudioHandler] with [QueueHandler] and [SeekHandler]
// mixins so that notification / lock-screen controls, headphone buttons,
// and Android system media commands all work through a single entry point.
//
// The handler is created by [AudioService.init] in [main] and receives
// the application-wide [AudioPlayer] instance directly.  State is synced
// from the player streams into [playbackState] and [mediaItem] so that
// the system notification reflects the current track and playback state.

import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';

import '../../features/player/media_control_model.dart' hide MediaAction;

/// Callback for when the handler needs to advance to the next track.
///
/// The handler itself does not own or read the play queue — it delegates
/// queue navigation to the app layer which has access to Riverpod state.
typedef NextTrackCallback = void Function();
typedef PreviousTrackCallback = void Function();

/// The [BaseAudioHandler] implementation for NAS Audio Player.
///
/// Holds a reference to the app-level [AudioPlayer] and translates
/// system media commands into calls on that player.  Player-state changes
/// are reflected in the notification via [playbackState] and [mediaItem]
/// streams.
class NasAudioHandler extends BaseAudioHandler
    with QueueHandler, SeekHandler {
  final AudioPlayer _player;

  /// Callbacks for queue navigation — set by the app after initialisation.
  NextTrackCallback? onSkipToNextRequested;
  PreviousTrackCallback? onSkipToPreviousRequested;

  // ── Subscriptions ──────────────────────────────────────────────────────

  StreamSubscription<PlayerState>? _stateSub;
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<Duration?>? _durationSub;

  NasAudioHandler(this._player) {
    _stateSub = _player.playerStateStream.listen(_onPlayerStateChanged);
    _positionSub = _player.positionStream.listen(_onPositionChanged);
    _durationSub = _player.durationStream.listen(_onDurationChanged);
  }

  // ── State sync ─────────────────────────────────────────────────────────

  void _onPlayerStateChanged(PlayerState state) {
    final controls = _buildControls(state.playing);
    playbackState.add(playbackState.value.copyWith(
      controls: controls,
      systemActions: const {
        MediaAction.seek,
        MediaAction.seekForward,
        MediaAction.seekBackward,
      },
      androidCompactActionIndices: const [0, 1, 2],
      playing: state.playing,
      processingState: _mapProcessingState(state.processingState),
      updatePosition: _player.position,
      bufferedPosition: _player.bufferedPosition,
      speed: _player.speed,
    ));
  }

  void _onPositionChanged(Duration position) {
    playbackState.add(playbackState.value.copyWith(
      updatePosition: position,
    ));
  }

  void _onDurationChanged(Duration? duration) {
    if (duration != null && mediaItem.value != null) {
      mediaItem.add(mediaItem.value!.copyWith(duration: duration));
    }
  }

  /// Updates the notification [mediaItem] to represent [filePath].
  void setMediaItemFromPath(String filePath, {Duration? duration}) {
    final title = extractTitleFromPath(filePath);
    mediaItem.add(MediaItem(
      id: filePath,
      title: title,
      duration: duration,
      artUri: null, // default icon
    ));
  }

  // ── Media controls ─────────────────────────────────────────────────────

  List<MediaControl> _buildControls(bool playing) {
    return [
      MediaControl.skipToPrevious,
      if (playing) MediaControl.pause else MediaControl.play,
      MediaControl.skipToNext,
    ];
  }

  AudioProcessingState _mapProcessingState(ProcessingState state) {
    switch (state) {
      case ProcessingState.idle:
        return AudioProcessingState.idle;
      case ProcessingState.loading:
        return AudioProcessingState.loading;
      case ProcessingState.buffering:
        return AudioProcessingState.buffering;
      case ProcessingState.ready:
        return AudioProcessingState.ready;
      case ProcessingState.completed:
        return AudioProcessingState.completed;
    }
  }

  // ── BaseAudioHandler overrides ─────────────────────────────────────────

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> stop() async {
    await _player.stop();
    await super.stop();
  }

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> setSpeed(double speed) => _player.setSpeed(speed);

  @override
  Future<void> skipToNext() {
    onSkipToNextRequested?.call();
    return super.skipToNext();
  }

  @override
  Future<void> skipToPrevious() {
    onSkipToPreviousRequested?.call();
    return super.skipToPrevious();
  }

  @override
  Future<void> onTaskRemoved() async {
    // Stop playback when the user swipes away the notification.
    await _player.stop();
  }

  // ── Cleanup ────────────────────────────────────────────────────────────

  void dispose() {
    _stateSub?.cancel();
    _positionSub?.cancel();
    _durationSub?.cancel();
  }
}
