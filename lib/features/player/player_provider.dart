// lib/features/player/player_provider.dart
// Riverpod providers for the Player feature.
//
// Provides an AudioPlayer instance and load-state management so the
// player screen (PLY-01) can load WebDAV audio streams with Basic Auth
// and react to errors gracefully.
//
// PLY-03: 后台播放 — includes background-playback-enabled flag and
// AppLifecycleState handling so audio continues when the app goes to
// background.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/services/audio_handler.dart';
import '../../core/services/audio_source_builder.dart';
import '../../shared/models/play_progress.dart';
import '../../shared/models/play_queue.dart';
import '../browser/browser_provider.dart';
import '../connection/connection_provider.dart';
import '../progress/progress_provider.dart';
import '../timer/timer_provider.dart';
import 'background_playback.dart';

// ── AudioPlayer instance ───────────────────────────────────────────────────────

/// The [AudioPlayer] instance used for playback.
///
/// Created lazily on first read and disposed when the provider container
/// is destroyed (app lifecycle).  Only one player exists application-wide.
final audioPlayerProvider = Provider<AudioPlayer>((ref) {
  final player = AudioPlayer();
  ref.onDispose(() => player.dispose());
  return player;
});

/// The [NasAudioHandler] instance created by [AudioService.init].
///
/// Provided via [ProviderScope.overrides] in [main] so that the player
/// screen and other widgets can interact with the handler directly.
/// Returns `null` by default — overridden in [main] with the actual instance
/// (which may also be null if [AudioService.init] fails).
final audioHandlerProvider = Provider<NasAudioHandler?>((ref) => null);

// ── Player load state ──────────────────────────────────────────────────────────

/// Lifecycle of loading an audio source into the player.
enum PlayerLoadStatus {
  /// No source has been loaded yet.
  idle,

  /// The source is being loaded / buffered.
  loading,

  /// The source is loaded and the player is ready to play.
  ready,

  /// Loading failed.
  error,
}

/// Tracks the current source-loading state of the player.
///
/// Managed by the [PlayerScreen] locally (not a global StateNotifier)
/// because the load cycle is tightly coupled to the screen lifecycle
/// (rebuilding the screen for a different file starts a fresh load).
class PlayerLoadState {
  final PlayerLoadStatus status;
  final String? errorMessage;

  /// Whether the error is an authentication failure (401 / 403).
  final bool isAuthError;

  const PlayerLoadState({
    this.status = PlayerLoadStatus.idle,
    this.errorMessage,
    this.isAuthError = false,
  });

  static const idle = PlayerLoadState();

  static const loading = PlayerLoadState(status: PlayerLoadStatus.loading);

  static const ready = PlayerLoadState(status: PlayerLoadStatus.ready);

  factory PlayerLoadState.error(String message, {bool isAuthError = false}) {
    return PlayerLoadState(
      status: PlayerLoadStatus.error,
      errorMessage: message,
      isAuthError: isAuthError,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PlayerLoadState &&
          status == other.status &&
          errorMessage == other.errorMessage &&
          isAuthError == other.isAuthError;

  @override
  int get hashCode => Object.hash(status, errorMessage, isAuthError);

  @override
  String toString() =>
      'PlayerLoadState(status: $status, errorMessage: $errorMessage, '
      'isAuthError: $isAuthError)';
}

/// Result of attempting to load the current queue entry into the player.
enum TrackLoadStatus {
  loaded,
  failed,
  superseded,
}

/// Outcome wrapper for serialized load requests.
class TrackLoadResult {
  final TrackLoadStatus status;
  final AudioPlayer? player;

  const TrackLoadResult._(this.status, this.player);

  const TrackLoadResult.loaded(AudioPlayer player)
      : this._(TrackLoadStatus.loaded, player);

  const TrackLoadResult.failed() : this._(TrackLoadStatus.failed, null);

  const TrackLoadResult.superseded() : this._(TrackLoadStatus.superseded, null);

  bool get isLoaded => status == TrackLoadStatus.loaded && player != null;
  bool get isSuperseded => status == TrackLoadStatus.superseded;
}

/// Serializes asynchronous requests and lets the latest one win.
///
/// Older requests are allowed to finish, but their completion is discarded
/// once a newer request has been scheduled. This prevents overlapping
/// `stop -> setAudioSource -> play` chains on the shared [AudioPlayer].
class SerializedRequestGate {
  int _latestRequestId = 0;
  bool _running = false;
  _QueuedRequest<dynamic>? _pendingRequest;

  int beginRequest() => ++_latestRequestId;

  bool isLatest(int requestId) => requestId == _latestRequestId;

  Future<T> schedule<T>({
    required Future<T> Function(int requestId) task,
    required T Function() onSuperseded,
  }) {
    final requestId = beginRequest();
    final completer = Completer<T>();
    final request = _QueuedRequest<T>(
      requestId: requestId,
      task: task,
      onSuperseded: onSuperseded,
      completer: completer,
    );

    if (_running) {
      _pendingRequest?.completeSuperseded();
      _pendingRequest = request;
    } else {
      _start(request);
    }

    return completer.future;
  }

  void _start<T>(_QueuedRequest<T> request) {
    _running = true;
    unawaited(() async {
      try {
        final result = await request.task(request.requestId);
        request.complete(
            isLatest(request.requestId) ? result : request.onSuperseded());
      } catch (e) {
        if (isLatest(request.requestId)) {
          request.completer.completeError(e);
        } else {
          request.complete(request.onSuperseded());
        }
      } finally {
        _running = false;
        final next = _pendingRequest;
        _pendingRequest = null;
        if (next != null) {
          _start<dynamic>(next);
        }
      }
    }());
  }
}

class _QueuedRequest<T> {
  final int requestId;
  final Future<T> Function(int requestId) task;
  final T Function() onSuperseded;
  final Completer<T> completer;

  _QueuedRequest({
    required this.requestId,
    required this.task,
    required this.onSuperseded,
    required this.completer,
  });

  void complete(T result) {
    if (!completer.isCompleted) {
      completer.complete(result);
    }
  }

  void completeSuperseded() {
    complete(onSuperseded());
  }
}

// ── Seek utility functions ──────────────────────────────────────────────────────

/// Clamps [target] to the range `[Duration.zero, total]`.
///
/// Used by seek, skip-forward, and skip-backward logic to ensure positions
/// never go negative or exceed the track duration.
///
/// PLY-T10~T12: seek with clamping; PLY-T13~T16: skip forward/backward.
Duration clampSeek(Duration target, Duration total) {
  if (target < Duration.zero) return Duration.zero;
  if (target > total) return total;
  return target;
}

/// Returns the position after skipping forward by [seconds] (default 15).
///
/// The result is clamped to [total] so it never exceeds the track duration.
/// PLY-T13~T14.
Duration skipForward(Duration current, Duration total, {int seconds = 15}) {
  return clampSeek(current + Duration(seconds: seconds), total);
}

/// Returns the position after skipping backward by [seconds] (default 15).
///
/// The result is clamped to [current] so it never goes below zero or
/// forward of the current position.
/// PLY-T15~T16.
Duration skipBackward(Duration current, {int seconds = 15}) {
  return clampSeek(current - Duration(seconds: seconds), current);
}

// ── Seek step persistence (SET-04) ──────────────────────────────────────────

/// SharedPreferences key for the seek step setting.
const _seekStepPrefsKey = 'seek_step_seconds';

/// Default seek step in seconds.
const _defaultSeekStep = 15;

/// Returns the seek step stored in [prefs], or [_defaultSeekStep] if not set.
///
/// Pure function — testable without any providers or platform channels.
int readSeekStep(SharedPreferences? prefs) {
  if (prefs == null) return _defaultSeekStep;
  return prefs.getInt(_seekStepPrefsKey) ?? _defaultSeekStep;
}

/// Configurable seek step in seconds (default 15), read from SharedPreferences.
///
/// Used by skip-forward and skip-backward controls.
final seekStepProvider = StateProvider<int>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return readSeekStep(prefs);
});

// ── Play mode (PLY-06) ────────────────────────────────────────────────────────────

/// The current playback mode for the audio queue.
///
/// Defaults to [PlayMode.sequential].  The user can cycle through modes
/// via a button on the player screen.
final playModeProvider = StateProvider<PlayMode>((ref) => PlayMode.sequential);

/// Returns a function that cycles [playModeProvider] to the next mode.
///
/// The modes cycle in order:
///   sequential → repeatOne → repeatAll → shuffle → sequential …
///
/// Tapping the play-mode button on the player screen calls this function.
final nextPlayModeProvider = Provider<PlayMode Function()>((ref) {
  return () {
    final current = ref.read(playModeProvider);
    final next = PlayMode.values[(current.index + 1) % PlayMode.values.length];
    debugPrint('[Player] playMode: ${current.name} → ${next.name}');
    ref.read(playModeProvider.notifier).state = next;
    return next;
  };
});

/// Returns the icon that visually represents the given [PlayMode].
///
/// Each mode has a distinct Material icon so the user can identify the
/// current playback mode at a glance (PLY-T61).
IconData iconForPlayMode(PlayMode mode) {
  switch (mode) {
    case PlayMode.sequential:
      return Icons.playlist_play;
    case PlayMode.repeatOne:
      return Icons.repeat_one;
    case PlayMode.repeatAll:
      return Icons.repeat;
    case PlayMode.shuffle:
      return Icons.shuffle;
  }
}

/// Returns a human-readable Chinese label for the given [PlayMode].
String labelForPlayMode(PlayMode mode) {
  switch (mode) {
    case PlayMode.sequential:
      return '顺序播放';
    case PlayMode.repeatOne:
      return '单曲循环';
    case PlayMode.repeatAll:
      return '列表循环';
    case PlayMode.shuffle:
      return '随机播放';
  }
}

// ── Speed options ───────────────────────────────────────────────────────────────

/// Available playback speed multipliers.
const List<double> speedOptions = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0];

// ── Speed persistence (PLY-07) ───────────────────────────────────────────────

/// SharedPreferences key for the default playback speed.
const _defaultSpeedKey = 'default_playback_speed';

/// Returns the default playback speed from [prefs], or 1.0 if not set.
///
/// Pure function — testable without any providers or platform channels.
double getDefaultSpeed(SharedPreferences? prefs) {
  if (prefs == null) return 1.0;
  final value = prefs.getDouble(_defaultSpeedKey);
  return value ?? 1.0;
}

/// Returns `true` if [speed] is one of the valid [speedOptions].
///
/// Uses a tolerance of 0.01 for floating-point comparison.
/// Pure function — testable without any providers or platform channels.
bool isValidSpeed(double speed) {
  return speedOptions.any((s) => (s - speed).abs() < 0.01);
}

/// The default playback speed, persisted to SharedPreferences.
///
/// Reads the value from SharedPreferences on first access.  When
/// SharedPreferences is unavailable (test environments) defaults to 1.0.
///
/// This is the "settings-level" default.  It is NOT updated when the user
/// changes speed during playback via the player UI — that only affects
/// [currentSpeedProvider].  The default speed is applied when opening a new
/// file (PLY-T47) and is only changed via the Settings screen.
final defaultSpeedProvider = Provider<double>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return getDefaultSpeed(prefs);
});

/// Persists a new default speed to SharedPreferences and invalidates
/// [defaultSpeedProvider] so that it re-reads the updated value.
///
/// Non-[speedOptions] values are silently ignored.
/// This is the function that the Settings screen would call.
final setDefaultSpeedProvider = Provider<void Function(double)>((ref) {
  return (double speed) {
    if (!isValidSpeed(speed)) return;
    debugPrint('[Settings] defaultSpeed: ${speed}x');
    final prefs = ref.read(sharedPreferencesProvider);
    prefs?.setDouble(_defaultSpeedKey, speed);
    ref.invalidate(defaultSpeedProvider);
    // Sync the runtime speed provider so the player UI reflects the change
    // immediately.  The next loadAndPlayProvider call (triggered by selecting
    // a new song or by the player screen's queue-match logic) will apply the
    // speed to the AudioPlayer.  We cannot safely access AudioPlayer here
    // because its constructor requires platform bindings absent in tests.
    ref.read(currentSpeedProvider.notifier).state = speed;
  };
});

/// Tracks the actual playback speed applied to the player.
///
/// Initialized from [defaultSpeedProvider] so that every new file starts at
/// the user's preferred default speed (PLY-T47).  When the user selects a
/// different speed via the player's speed selector, only this provider is
/// updated — [defaultSpeedProvider] is left unchanged (PLY-T46).
final currentSpeedProvider = StateProvider<double>((ref) {
  // Use ref.read (not ref.watch) so that currentSpeed is seeded from
  // defaultSpeed on first access but does NOT re-evaluate when the
  // settings-level default changes later (PLY-T46).
  return ref.read(defaultSpeedProvider);
});

// ── Time formatting helper ─────────────────────────────────────────────────────

/// Formats a [Duration] as a human-readable timestamp.
///
/// - Durations under 1 hour: `MM:SS` (e.g. `05:30`)
/// - Durations 1 hour or more: `H:MM:SS` (e.g. `1:23:45`)
/// - Null: `--:--`
String formatDuration(Duration? duration) {
  if (duration == null) return '--:--';
  final totalSeconds = duration.inSeconds;
  final hours = totalSeconds ~/ 3600;
  final minutes = (totalSeconds % 3600) ~/ 60;
  final seconds = totalSeconds % 60;

  final mm = minutes.toString().padLeft(2, '0');
  final ss = seconds.toString().padLeft(2, '0');

  if (hours > 0) {
    return '$hours:$mm:$ss';
  }
  return '$mm:$ss';
}

/// Normalizes a restored resume position before it is applied to the player.
///
/// Invalid values fall back to `0` so startup recovery never attempts to seek
/// beyond the track duration and leave the player in a broken state.
int sanitizeResumePosition(int positionMs, int? durationMs) {
  if (positionMs < 0) return 0;
  if (durationMs != null && durationMs > 0 && positionMs >= durationMs) {
    return 0;
  }
  return positionMs;
}

/// Applies the latest saved progress to the current queue when it still points
/// at the same file on the same active connection.
PlayQueue? applyLatestProgressToQueue({
  required PlayQueue? queue,
  required int? activeConnectionId,
  required PlayProgress? latestProgress,
}) {
  if (queue == null || activeConnectionId == null || latestProgress == null) {
    return queue;
  }
  if (latestProgress.connectionId != activeConnectionId) return queue;
  if (latestProgress.filePath != queue.current.path) return queue;
  return queue.withStartPosition(
    sanitizeResumePosition(
      latestProgress.positionMs,
      latestProgress.durationMs,
    ),
  );
}

// ── Background playback (PLY-03) ─────────────────────────────────────────────────

/// Whether background audio playback is enabled.
///
/// When true, audio continues playing when the app enters the background
/// (via [AudioPlayer]'s built-in background support and the audio_service
/// integration planned for PLY-04).
///
/// This flag can be toggled by settings or platform constraints.  It is
/// read by the app-lifecycle observer to decide whether to pause or
/// continue playback on a lifecycle transition.
final backgroundPlaybackEnabledProvider = StateProvider<bool>((ref) => true);

/// Restores the latest saved playback position onto the persisted queue during
/// app startup so pressing play resumes from the last known position.
final restoreStartupProgressProvider = FutureProvider<void>((ref) async {
  await ref.read(restoreQueueFromPrefsProvider.future);

  final queue = ref.read(currentPlayQueueProvider);
  final activeConn = ref.read(activeConnectionProvider).valueOrNull;
  final latestProgress = await ref.read(latestPlayedProgressProvider.future);
  final restoredQueue = applyLatestProgressToQueue(
    queue: queue,
    activeConnectionId: activeConn?.id,
    latestProgress: latestProgress,
  );

  if (restoredQueue != null && restoredQueue != queue) {
    ref.read(currentPlayQueueProvider.notifier).state = restoredQueue;
    final player = ref.read(audioPlayerProvider);
    if (player.audioSource != null) {
      await player.seek(
        Duration(milliseconds: restoredQueue.startPositionMs ?? 0),
      );
    }
  }
});

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

/// Bridges [NasAudioHandler.onConfigChanged] to [BackgroundPlaybackNotifier]
/// so the Riverpod layer mirrors the handler's internal state machine (PLY-F).
///
/// This provider is read once at app startup (via [HomeScreen]) and kept alive
/// for the lifetime of the app — the callback is unregistered on dispose.
final backgroundPlaybackSyncProvider = Provider<void>((ref) {
  final handler = ref.read(audioHandlerProvider);
  final notifier = ref.read(backgroundPlaybackProvider.notifier);
  handler?.onConfigChanged = notifier.syncFromHandler;
  ref.onDispose(() {
    handler?.onConfigChanged = null;
  });
});

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

// ── D-1: Unified playback entry point ──────────────────────────────────────────
//
// These providers extract the shared "load, play, and set up listeners" logic
// so that both the full player screen and the mini player bar can trigger
// playback through the same code path.  Previously the mini bar's skip and
// queue-selection handlers duplicated a subset of _loadAndPlay(), skipping
// listener setup and breaking auto-next, auto-save, and timer features.

/// Holds the current [processingStateStream] subscription so it can be
/// cancelled and re-created from any call site.
final _processingSubProvider =
    StateProvider<StreamSubscription<void>?>((ref) => null);

/// Cancels the active processing-state subscription.
final cancelProcessingListenerProvider = Provider<void Function()>((ref) {
  return () {
    ref.read(_processingSubProvider)?.cancel();
    ref.read(_processingSubProvider.notifier).state = null;
  };
});

/// Registers (or re-registers) the processing-state listener that handles
/// track completion — auto-advance to next or afterCurrent timer stop.
///
/// Extracted from [loadAndPlayProvider] so the PlayerScreen can re-register
/// the listener when it re-opens and skips reloading a matching source.
final startProcessingListenerProvider = Provider<void Function()>((ref) {
  // PLY-05: cancel processing subscription on dispose to prevent
  // the listener from reading stale Riverpod state after disposal.
  ref.onDispose(() {
    ref.read(_processingSubProvider)?.cancel();
  });

  return () {
    final player = ref.read(audioPlayerProvider);
    ref.read(cancelProcessingListenerProvider)();
    final sub = player.processingStateStream.listen((state) {
      if (state == ProcessingState.completed) {
        if (ref.read(_completingProvider)) {
          debugPrint('[Player] track completed (ignored, already completing)');
          return;
        }
        ref.read(_completingProvider.notifier).state = true;
        debugPrint('[Player] track completed');
        final triggered = ref.read(onTrackCompletedProvider)();
        if (triggered) {
          debugPrint('[Player] afterCurrent timer triggered, pausing');
          player.pause();
          ref.read(_completingProvider.notifier).state = false;
        } else {
          debugPrint('[Player] advancing to next track');
          final q = ref.read(currentPlayQueueProvider);
          final m = ref.read(playModeProvider);
          if (q == null) return;
          // PLY-01: use deterministic shuffle order for shuffle mode
          PlayQueue? nq;
          if (m == PlayMode.shuffle) {
            nq = q.advanceShuffle();
          }
          nq ??= () {
            final ni = PlayQueue.nextIndex(q.currentIndex, q.length, m);
            if (ni == null) return null;
            return q.withIndex(ni);
          }();
          if (nq == null) {
            debugPrint('[Player] no next track, completed');
            player.pause();
            ref.read(_completingProvider.notifier).state = false;
            return;
          }
          ref.read(saveProgressProvider)();
          ref.read(currentPlayQueueProvider.notifier).state = nq;
          unawaited(ref.read(loadAndPlayProvider)());
        }
      }
    });
    ref.read(_processingSubProvider.notifier).state = sub;
  };
});

/// Saves the current playback position to the database.
final saveProgressProvider = Provider<void Function()>((ref) {
  return () {
    final queue = ref.read(currentPlayQueueProvider);
    final conn = ref.read(activeConnectionProvider).valueOrNull;
    if (queue == null || conn?.id == null) return;
    final player = ref.read(audioPlayerProvider);
    ref.read(upsertProgressProvider)(
      connectionId: conn!.id!,
      filePath: queue.current.path,
      positionMs: player.position.inMilliseconds,
      durationMs: player.duration?.inMilliseconds,
    );
  };
});

/// Holds the periodic auto-save timer so it can be cancelled.
final _autoSaveTimerProvider = StateProvider<Timer?>((ref) => null);

/// Starts (or restarts) a periodic timer that saves progress every 10 seconds.
final _startAutoSaveProvider = Provider<void Function()>((ref) {
  return () {
    ref.read(_autoSaveTimerProvider)?.cancel();
    final timer = Timer.periodic(const Duration(seconds: 10), (_) {
      ref.read(saveProgressProvider)();
    });
    ref.read(_autoSaveTimerProvider.notifier).state = timer;
  };
});

/// Cancels the auto-save timer.
final _cancelAutoSaveProvider = Provider<void Function()>((ref) {
  return () {
    ref.read(_autoSaveTimerProvider)?.cancel();
    ref.read(_autoSaveTimerProvider.notifier).state = null;
  };
});

/// Holds the player-state subscription for pause-triggered saves.
final _pauseSaveSubProvider =
    StateProvider<StreamSubscription<void>?>((ref) => null);

/// Guards against duplicate [ProcessingState.completed] events so that
/// a second completion does not advance the queue an extra time while
/// the first advance is still loading the next track.
final _completingProvider = StateProvider<bool>((ref) => false);

/// Gate that serializes load requests for the shared [AudioPlayer].
final _loadRequestGateProvider = Provider<SerializedRequestGate>((ref) {
  return SerializedRequestGate();
});

/// Starts a listener that saves progress whenever the player transitions
/// from playing to paused.
final _startPauseSaveProvider = Provider<void Function(AudioPlayer)>((ref) {
  return (AudioPlayer player) {
    ref.read(_pauseSaveSubProvider)?.cancel();
    var wasPlaying = player.playing;
    final sub = player.playerStateStream.listen((state) {
      final playing = state.playing;
      if (wasPlaying && !playing) {
        ref.read(saveProgressProvider)();
      }
      wasPlaying = playing;
    });
    ref.read(_pauseSaveSubProvider.notifier).state = sub;
  };
});

/// Re-registers all playback listeners that were cancelled when the
/// PlayerScreen was disposed.  Call this when the screen re-opens and
/// skips [_loadAndPlay] because the source already matches.
final reconnectPlaybackListenersProvider = Provider<void Function()>((ref) {
  return () {
    ref.read(startProcessingListenerProvider)();
    ref.read(_startAutoSaveProvider)();
    ref.read(_startPauseSaveProvider)(ref.read(audioPlayerProvider));
  };
});

/// Cancels the pause-save listener.
final _cancelPauseSaveProvider = Provider<void Function()>((ref) {
  return () {
    ref.read(_pauseSaveSubProvider)?.cancel();
    ref.read(_pauseSaveSubProvider.notifier).state = null;
  };
});

/// Advances the queue to the next track and loads it via [loadAndPlayProvider].
///
/// G-2: this provider only updates the queue, then delegates to
/// [loadAndPlayProvider].  The processing listener inside loadAndPlayProvider
/// calls an inlined _advanceToNext helper instead of reading this provider,
/// breaking the cycle.
final Provider<Future<TrackLoadResult> Function()> skipToNextProvider =
    Provider<Future<TrackLoadResult> Function()>((ref) {
  return () async {
    final queue = ref.read(currentPlayQueueProvider);
    final mode = ref.read(playModeProvider);
    if (queue == null) return const TrackLoadResult.failed();
    // PLY-01: use deterministic shuffle order for shuffle mode
    final nextQueue = mode == PlayMode.shuffle
        ? queue.advanceShuffle()
        : () {
            final ni = PlayQueue.nextIndex(queue.currentIndex, queue.length, mode);
            return ni != null ? queue.withIndex(ni) : null;
          }();
    if (nextQueue == null) {
      debugPrint('[Player] skipNext: no next track (mode=$mode)');
      return const TrackLoadResult.failed();
    }
    debugPrint('[Player] skipNext: idx=${nextQueue.currentIndex} file=${nextQueue.current.path}');
    ref.read(saveProgressProvider)();
    ref.read(currentPlayQueueProvider.notifier).state = nextQueue;
    return ref.read(loadAndPlayProvider)();
  };
});

/// Moves the queue backward and loads the selected track through the
/// serialized playback pipeline.
final skipToPreviousProvider =
    Provider<Future<TrackLoadResult> Function()>((ref) {
  return () async {
    final queue = ref.read(currentPlayQueueProvider);
    final mode = ref.read(playModeProvider);
    if (queue == null) return const TrackLoadResult.failed();
    // PLY-01: use deterministic shuffle history for shuffle mode
    final prevQueue = mode == PlayMode.shuffle
        ? queue.retreatShuffle()
        : () {
            final pi = PlayQueue.previousIndex(queue.currentIndex, queue.length, mode);
            return pi != null ? queue.withIndex(pi) : null;
          }();
    if (prevQueue == null) {
      debugPrint('[Player] skipPrev: no previous track (mode=$mode)');
      return const TrackLoadResult.failed();
    }
    debugPrint('[Player] skipPrev: idx=${prevQueue.currentIndex} file=${prevQueue.current.path}');
    ref.read(saveProgressProvider)();
    ref.read(currentPlayQueueProvider.notifier).state = prevQueue;
    return ref.read(loadAndPlayProvider)();
  };
});

/// Selects a queue index and loads that track through the serialized
/// playback pipeline.
final selectQueueIndexProvider =
    Provider<Future<TrackLoadResult> Function(int)>((ref) {
  return (int index) async {
    final queue = ref.read(currentPlayQueueProvider);
    if (queue == null || index < 0 || index >= queue.length) {
      return const TrackLoadResult.failed();
    }
    if (index == queue.currentIndex) {
      debugPrint('[Player] selectIndex: already at idx=$index');
      return const TrackLoadResult.failed();
    }
    debugPrint('[Player] selectIndex: idx=$index file=${queue.files[index].path}');
    ref.read(saveProgressProvider)();
    ref.read(currentPlayQueueProvider.notifier).state = queue.withIndex(index);
    return ref.read(loadAndPlayProvider)();
  };
});

/// Removes a track from the queue at [index].  If the removed track is
/// currently playing the next track is loaded; if the queue becomes empty
/// playback is stopped.
final removeTrackFromQueueProvider =
    Provider<Future<void> Function(int)>((ref) {
  return (int index) async {
    final queue = ref.read(currentPlayQueueProvider);
    if (queue == null || index < 0 || index >= queue.length) return;
    final wasCurrent = index == queue.currentIndex;
    final player = ref.read(audioPlayerProvider);
    final newQueue = queue.withoutIndex(index);
    if (newQueue.length == 0) {
      await player.stop();
      ref.read(currentPlayQueueProvider.notifier).state = null;
      final handler = ref.read(audioHandlerProvider);
      handler?.mediaItem.add(null);
      ref.read(_cancelAutoSaveProvider)();
      ref.read(_cancelPauseSaveProvider)();
      return;
    }
    ref.read(currentPlayQueueProvider.notifier).state = newQueue;
    if (wasCurrent) {
      ref.read(saveProgressProvider)();
      await ref.read(loadAndPlayProvider)();
    }
  };
});

/// Unified entry point for loading and playing the current queue's track.
///
/// Must be called whenever the playback source needs to change — whether
/// from the full player screen, the mini bar next button, or the queue sheet.
/// Registers all required listeners (completion, auto-save, pause-save) and
/// applies the default speed.
///
/// Returns the [AudioPlayer] after the source is loaded and playing, or
/// `null` on failure.
///
final Provider<Future<TrackLoadResult> Function()> loadAndPlayProvider =
    Provider<Future<TrackLoadResult> Function()>((ref) {
  return () async {
    final gate = ref.read(_loadRequestGateProvider);
    return gate.schedule<TrackLoadResult>(
      onSuperseded: () => const TrackLoadResult.superseded(),
      task: (requestId) async {
        final queue = ref.read(currentPlayQueueProvider);
        if (queue == null || queue.length == 0) {
          debugPrint('[Provider] loadAndPlay: queue null/empty');
          return const TrackLoadResult.failed();
        }

        try {
          debugPrint('[Provider] loadAndPlay: start file=${queue.current.path}');
          // E-2: if the connection has changed since the queue was created,
          // refuse to load — file paths may not exist on the new connection.
          final savedConnId = ref.read(lastQueueConnectionIdProvider);
          final activeConn = await ref.read(activeConnectionProvider.future);
          if (activeConn == null) {
            debugPrint('[Provider] loadAndPlay: no active connection');
            return const TrackLoadResult.failed();
          }
          if (savedConnId != null && activeConn.id != savedConnId) {
            debugPrint('[Provider] loadAndPlay: connection changed');
            return const TrackLoadResult.failed();
          }
          if (!gate.isLatest(requestId)) {
            debugPrint('[Provider] loadAndPlay: superseded before auth');
            return const TrackLoadResult.superseded();
          }

          final storage = ref.read(secureStorageProvider);
          final password =
              await storage.read(key: 'connection_password_${activeConn.id}');
          if (password == null || password.isEmpty) {
            debugPrint('[Provider] loadAndPlay: no password');
            return const TrackLoadResult.failed();
          }
          if (!gate.isLatest(requestId)) {
            return const TrackLoadResult.superseded();
          }

          final source = AudioSourceBuilder.buildWithBasePath(
            baseUrl: activeConn.url,
            filePath: queue.current.path,
            username: activeConn.username,
            password: password,
          );

          final player = ref.read(audioPlayerProvider);

          // Register completion listener before loading new source
          // (preserves A-2 fix).  Do NOT call player.stop() here —
          // setAudioSource() handles stopping the current source internally,
          // and an explicit stop() causes an idle state transition that
          // triggers audio_service's androidStopForegroundOnPause, which
          // can cause a native crash when switching tracks during playback.
          ref.read(startProcessingListenerProvider)();

          debugPrint('[Provider] loadAndPlay: calling setAudioSource');
          await player.setAudioSource(source);
          debugPrint('[Provider] loadAndPlay: setAudioSource done');

          if (queue.startPositionMs != null) {
            await player.seek(Duration(milliseconds: queue.startPositionMs!));
          }

          // Update the notification with the current track info.
          final handler = ref.read(audioHandlerProvider);
          handler?.setMediaItemFromPath(
            queue.current.path,
            duration: player.duration,
          );

          // Apply the default playback speed.
          final defaultSpeed = ref.read(defaultSpeedProvider);
          if ((defaultSpeed - 1.0).abs() > 0.01) {
            await player.setSpeed(defaultSpeed);
            ref.read(currentSpeedProvider.notifier).state = defaultSpeed;
          }
          if (!gate.isLatest(requestId)) {
            return const TrackLoadResult.superseded();
          }

          debugPrint('[Provider] loadAndPlay: calling play()');
          // A-4: Don't await play() — its Future may never complete due to
          // platform-channel contention with audio_service.  Instead poll
          // player.playing so the UI shows controls as soon as audio starts.
          unawaited(player.play());
          // PLY-03: increased timeout to 60 × 200ms = 12s and added
          // a final confirmation check to avoid false-positive failures.
          var playStarted = false;
          for (int i = 0; i < 60; i++) {
            await Future<void>.delayed(const Duration(milliseconds: 200));
            if (player.playing) {
              playStarted = true;
              break;
            }
          }
          if (!playStarted) {
            // Final confirmation: the platform may have taken longer than
            // expected to update the playing flag.
            if (player.playing) {
              playStarted = true;
              debugPrint('[Provider] loadAndPlay: play() started late');
            }
          }
          if (!playStarted) {
            debugPrint('[Provider] loadAndPlay: play() never started');
            await player.stop();
            return const TrackLoadResult.failed();
          }
          debugPrint('[Provider] loadAndPlay: player now playing');
          if (!gate.isLatest(requestId)) {
            return const TrackLoadResult.superseded();
          }

          // Start background listeners for progress persistence.
          ref.read(_startAutoSaveProvider)();
          ref.read(_startPauseSaveProvider)(player);

          return TrackLoadResult.loaded(player);
        } catch (e, st) {
          debugPrint('loadAndPlayProvider error: $e\n$st');
          return const TrackLoadResult.failed();
        } finally {
          ref.read(_completingProvider.notifier).state = false;
        }
      },
    );
  };
});

/// Cancels all background subscriptions set up by [loadAndPlayProvider].
///
/// Call this when the player screen is disposed to stop auto-save and
/// pause-save listeners.
///
/// Does NOT cancel the processing-state listener — it must persist so that
/// auto-advance works when only the mini player bar is visible.
final cancelPlaybackSubscriptionsProvider = Provider<void Function()>((ref) {
  return () {
    ref.read(_cancelAutoSaveProvider)();
    ref.read(_cancelPauseSaveProvider)();
  };
});

/// Pure function: given an [AppLifecycleState] and playback state,
/// returns the expected [BackgroundPlaybackState] after the transition.
///
/// This models the lifecycle-handling logic without depending on
/// StateNotifier or AudioPlayer, so it can be tested in isolation
/// (PLY-T20).
BackgroundPlaybackConfig computePlaybackStateAfterLifecycle({
  required AppLifecycleState newState,
  required bool backgroundEnabled,
  required BackgroundPlaybackState currentPlaybackState,
}) {
  switch (newState) {
    case AppLifecycleState.resumed:
      // Coming back to foreground — playback state unchanged.
      return BackgroundPlaybackConfig(
        backgroundEnabled: backgroundEnabled,
        isInForeground: true,
        playbackState: currentPlaybackState,
      );
    case AppLifecycleState.inactive:
    case AppLifecycleState.paused:
    case AppLifecycleState.hidden:
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
    case AppLifecycleState.detached:
      return BackgroundPlaybackConfig(
        backgroundEnabled: backgroundEnabled,
        isInForeground: false,
        playbackState: BackgroundPlaybackState.stopped,
      );
  }
}
