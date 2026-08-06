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
import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

import '../../features/player/media_control_model.dart' hide MediaAction;
import '../contracts/audio_handler_contract.dart';
import '../contracts/background_playback_contract.dart';

/// Supplies the [AudioSession] used to subscribe to audio-focus event
/// streams.
///
/// Production code uses the default ([AudioSession.instance]); tests may
/// inject a fake session to drive interruption events deterministically —
/// the same testability-injection style as the DAO `clock` parameters
/// (BUG-26/BUG-31 precedent).
typedef AudioSessionProvider = Future<AudioSession> Function();

/// The [BaseAudioHandler] implementation for NAS Audio Player.
///
/// Holds a reference to the app-level [AudioPlayer] and translates
/// system media commands into calls on that player.  Player-state changes
/// are reflected in the notification via [playbackState] and [mediaItem]
/// streams.
class NasAudioHandler extends BaseAudioHandler
    with QueueHandler, SeekHandler
    implements IAudioHandler {
  final AudioPlayer _player;

  /// Injectable audio-session supplier (testability injection, same style as
  /// the DAO `clock` parameters).  Defaults to [AudioSession.instance];
  /// production behaviour is unchanged.
  final AudioSessionProvider _audioSessionProvider;

  /// Callbacks for queue navigation — set by the app after initialisation.
  NextTrackCallback? onSkipToNextRequested;
  PreviousTrackCallback? onSkipToPreviousRequested;

  /// Callback fired when the background-playback config changes, so the
  /// Riverpod-layer [BackgroundPlaybackNotifier] can mirror the state.
  ConfigChangeCallback? onConfigChanged;

  // ── Background-playback state ──────────────────────────────────────────

  BackgroundPlaybackConfig _config = BackgroundPlaybackConfig.initial;
  ProcessingState _lastProcessingState = ProcessingState.idle;

  /// The current background-playback configuration, driven by the pure-logic
  /// state machine in [BackgroundPlaybackConfig].
  @override
  BackgroundPlaybackConfig get config => _config;

  // ── Streams (IAudioHandler contract) ─────────────────────────────────────

  /// Stream of playback-state changes for notification / lock-screen.
  ///
  /// Backed by the [BaseAudioHandler.playbackState] [BehaviorSubject] —
  /// consumers can access `.value` for the current state and `.add()` to
  /// push updates.
  @override
  Stream<PlaybackState> get playbackStateStream => playbackState;

  /// Stream of the current media item metadata.
  @override
  Stream<MediaItem?> get mediaItemStream => mediaItem;

  // ── Subscriptions ──────────────────────────────────────────────────────

  StreamSubscription<PlayerState>? _stateSub;
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<Duration?>? _durationSub;
  StreamSubscription<AudioInterruptionEvent>? _interruptionSub;
  StreamSubscription<void>? _becomingNoisySub;

  NasAudioHandler(this._player, {AudioSessionProvider? audioSessionProvider})
      : _audioSessionProvider =
            audioSessionProvider ?? (() => AudioSession.instance) {
    _stateSub = _player.playerStateStream.listen(_onPlayerStateChanged);
    _positionSub = _player.positionStream.listen(_onPositionChanged);
    _durationSub = _player.durationStream.listen(_onDurationChanged);
    _initAudioSession();
  }

  Future<void> _initAudioSession() async {
    try {
      final session = await _audioSessionProvider();
      _interruptionSub = session.interruptionEventStream.listen((event) {
        // BUG-22 (spec §3.1): pause/duck are transient interruptions —
        // playback resumes when the interruption ends (audio_session emits
        // the matching end event with the same type, and just_audio's
        // default interruption handling performs the actual pause/resume).
        // Mapping them to `lost` would treat the post-call focus regain
        // (AudioInterruptionEvent(begin:false, type:pause)) as a permanent
        // loss and pause again, breaking resume-after-call.  Only `unknown`
        // is a permanent loss.
        switch (event.type) {
          case AudioInterruptionType.pause:
          case AudioInterruptionType.duck:
            onAudioFocusChange(AudioFocusState.transient);
          case AudioInterruptionType.unknown:
            onAudioFocusChange(AudioFocusState.lost);
        }
      });
      _becomingNoisySub = session.becomingNoisyEventStream.listen((_) {
        onAudioFocusChange(AudioFocusState.lost);
      });
    } catch (e) {
      // Degrade gracefully when the audio session is unavailable (e.g. no
      // platform channels in flutter test): focus handling is disabled but
      // core playback still works (BUG-22-INV3).
      debugPrint('[AudioHandler] audio session init failed: $e');
    }
  }

  // ── State sync ─────────────────────────────────────────────────────────

  void _onPlayerStateChanged(PlayerState state) {
    _lastProcessingState = state.processingState;
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
  @override
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
      _updateConfig(
          _config.copyWith(playbackState: BackgroundPlaybackState.playing));
    } else if (!playing &&
        _config.playbackState == BackgroundPlaybackState.playing) {
      _updateConfig(
          _config.copyWith(playbackState: BackgroundPlaybackState.paused));
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
  /// Fed by the audio-session streams subscribed in [_initAudioSession]:
  /// pause/duck interruptions map to [AudioFocusState.transient], `unknown`
  /// interruptions and becoming-noisy events map to [AudioFocusState.lost].
  ///
  /// When focus is permanently [AudioFocusState.lost], playback is paused.
  /// [AudioFocusState.transient] only updates the state machine — resuming
  /// after the interruption ends is covered by the transient semantics plus
  /// just_audio's own interruption handling.  [AudioFocusState.gained] has
  /// no emitter in this app; the state machine still accepts it for the
  /// notifier path, but the handler performs no playback side effect (the
  /// former gained auto-resume branch was dead code, removed per
  /// cr-20260728-1700 D1).
  @override
  void onAudioFocusChange(AudioFocusState focus) {
    final next = _config.updateAudioFocus(focus);
    _updateConfig(next);

    switch (focus) {
      case AudioFocusState.lost:
        pause();
      case AudioFocusState.transient:
      case AudioFocusState.gained:
        break;
    }
  }

  // ── BaseAudioHandler overrides ─────────────────────────────────────────

  @override
  Future<void> play() async {
    final next = _config.handleMediaControl(MediaControlAction.play);
    _updateConfig(next);
    try {
      if (_lastProcessingState == ProcessingState.completed) {
        try {
          await _player.seek(Duration.zero).timeout(const Duration(seconds: 5));
        } catch (_) {
          // Recovery seek failed or timed out (P4) — still attempt play.
        }
      }
      await _player.play().timeout(const Duration(seconds: 5));
    } catch (_) {
      // Timeout or platform error — silently ignore
    }
  }

  @override
  Future<void> pause() async {
    final next = _config.handleMediaControl(MediaControlAction.pause);
    _updateConfig(next);
    try {
      await _player.pause().timeout(const Duration(seconds: 5));
    } catch (_) {
      // Timeout or platform error — silently ignore
    }
  }

  @override
  Future<void> stop() async {
    final next = _config.handleMediaControl(MediaControlAction.stop);
    _updateConfig(next);
    try {
      await _player.stop().timeout(const Duration(seconds: 5));
    } catch (_) {
      // Timeout or platform error — silently ignore
    }
  }

  @override
  Future<void> seek(Duration position) async {
    try {
      await _player.seek(position).timeout(const Duration(seconds: 5));
    } catch (_) {}
  }

  @override
  Future<void> setSpeed(double speed) async {
    try {
      await _player.setSpeed(speed).timeout(const Duration(seconds: 5));
    } catch (_) {}
  }

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
    try {
      await _player.stop().timeout(const Duration(seconds: 5));
    } catch (_) {
      // Timeout or platform error — silently ignore
    }
  }

  // ── Cleanup ────────────────────────────────────────────────────────────

  @override
  void dispose() {
    _stateSub?.cancel();
    _positionSub?.cancel();
    _durationSub?.cancel();
    _interruptionSub?.cancel();
    _becomingNoisySub?.cancel();
  }
}
