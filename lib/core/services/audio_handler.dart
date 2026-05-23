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
//
// PLY-F: background-playback behaviour is driven by [BackgroundPlaybackConfig],
// a pure-logic state machine that models audio focus, media controls, and
// foreground/background transitions.

import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';

import '../../features/player/background_playback.dart';
import '../../features/player/media_control_model.dart' hide MediaAction;

/// Callback for when the handler needs to advance to the next track.
///
/// The handler itself does not own or read the play queue — it delegates
/// queue navigation to the app layer which has access to Riverpod state.
typedef NextTrackCallback = void Function();
typedef PreviousTrackCallback = void Function();

/// Callback invoked whenever [BackgroundPlaybackConfig] changes inside the
/// handler, so that the Riverpod [BackgroundPlaybackNotifier] can stay in sync.
typedef ConfigChangeCallback = void Function(BackgroundPlaybackConfig config);

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

  /// Callback fired when the background-playback config changes, so the
  /// Riverpod-layer [BackgroundPlaybackNotifier] can mirror the state.
  ConfigChangeCallback? onConfigChanged;

  // ── Background-playback state ──────────────────────────────────────────

  BackgroundPlaybackConfig _config = BackgroundPlaybackConfig.initial;

  /// The current background-playback configuration, driven by the pure-logic
  /// state machine in [BackgroundPlaybackConfig].
  BackgroundPlaybackConfig get config => _config;

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
    // Sync the background-playback config with the actual player state.
    _syncConfigFromPlayerState(state.playing);

    final controls = _buildControls();
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

  // ── Config sync ────────────────────────────────────────────────────────

  /// Synchronises the internal [BackgroundPlaybackConfig] with the raw
  /// playing state from [AudioPlayer].
  void _syncConfigFromPlayerState(bool playing) {
    if (playing && _config.playbackState != BackgroundPlaybackState.playing) {
      _updateConfig(_config.copyWith(
          playbackState: BackgroundPlaybackState.playing));
    } else if (!playing &&
        _config.playbackState == BackgroundPlaybackState.playing) {
      _updateConfig(_config.copyWith(
          playbackState: BackgroundPlaybackState.paused));
    }
  }

  void _updateConfig(BackgroundPlaybackConfig next) {
    if (_config == next) return;
    _config = next;
    onConfigChanged?.call(_config);
  }

  // ── Media controls ─────────────────────────────────────────────────────

  List<MediaControl> _buildControls() {
    return [
      MediaControl.skipToPrevious,
      if (_config.showPauseAction) MediaControl.pause else MediaControl.play,
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

  // ── Audio focus ────────────────────────────────────────────────────────

  /// Drives the background-playback state machine with an audio-focus change.
  ///
  /// Called by the app layer when the system audio focus changes (e.g.
  /// another app starts playing, a phone call begins/ends).
  ///
  /// When focus is permanently [lost], playback is paused.  When focus is
  /// [gained] back, playback may resume if the config state allows it.
  void onAudioFocusChange(AudioFocusState focus) {
    final next = _config.updateAudioFocus(focus);
    _updateConfig(next);

    // Act on the focus change.
    switch (focus) {
      case AudioFocusState.lost:
        _player.pause();
      case AudioFocusState.transient:
        // Ducking handled by platform — no explicit action needed here.
        break;
      case AudioFocusState.gained:
        // Resume if the state machine says audio should be active.
        if (_config.isAudioActive && !_player.playing) {
          _player.play();
        }
    }
  }

  // ── BaseAudioHandler overrides ─────────────────────────────────────────

  @override
  Future<void> play() async {
    final next = _config.handleMediaControl(MediaControlAction.play);
    _updateConfig(next);
    await _player.play();
  }

  @override
  Future<void> pause() async {
    final next = _config.handleMediaControl(MediaControlAction.pause);
    _updateConfig(next);
    await _player.pause();
  }

  @override
  Future<void> stop() async {
    final next = _config.handleMediaControl(MediaControlAction.stop);
    _updateConfig(next);
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
    final next = _config.handleMediaControl(MediaControlAction.stop);
    _updateConfig(next);
    await _player.stop();
  }

  // ── Cleanup ────────────────────────────────────────────────────────────

  void dispose() {
    _stateSub?.cancel();
    _positionSub?.cancel();
    _durationSub?.cancel();
  }
}
