// lib/features/player/domain/playback_orchestrator.dart
// REF-14: Core playback orchestration logic extracted to the domain layer.
//
// PlaybackOrchestrator encapsulates the full playback pipeline: loading a
// track, navigating the queue, removing tracks, and persisting progress.
// All dependencies are injected through the constructor — zero Riverpod
// imports.
//
// Methods:
//   loadAndPlay()       — load the current queue entry and start playback
//   skipToNext()        — advance the queue and load the next track
//   skipToPrevious()    — go back one track and load it
//   selectQueueIndex()  — jump to a specific queue index
//   removeTrack()       — remove a track from the queue (stop if empty)
//   saveProgress()      — persist the current playback position
//
// Internal state:
//   - SerializedRequestGate  — serializes overlapping load requests
//   - Auto-save timer        — saves progress every 10 seconds
//   - Processing listener    — handles track completion / auto-advance

import 'dart:async';

import 'package:just_audio/just_audio.dart';

import '../../../core/services/audio_source_builder.dart';
import '../../../shared/models/connection_config.dart';
import '../../../shared/models/play_queue.dart';
import 'request_gate.dart';

// ── Dependency interfaces ────────────────────────────────────────────────────

/// Provides the active [ConnectionConfig], or `null` if none is active.
///
/// Abstracts the Riverpod `activeConnectionProvider` so PlaybackOrchestrator
/// has no Riverpod dependency.
abstract class ActiveConnectionProvider {
  /// Returns the active connection asynchronously (for load operations).
  Future<ConnectionConfig?> getActiveConnection();

  /// Returns the currently cached active connection synchronously
  /// (for save operations where async is not feasible).
  ConnectionConfig? get currentConnection;
}

/// Reads the password for a given connection from secure storage.
abstract class PasswordReader {
  /// Returns the password for [connectionId], or `null` / empty if not found.
  Future<String?> readPassword(int connectionId);
}

/// Persists playback progress to the database.
abstract class ProgressSaver {
  /// Saves (upserts) the current playback position.
  Future<void> upsertProgress({
    required int connectionId,
    required String filePath,
    required int positionMs,
    int? durationMs,
  });
}

/// Provides the default playback speed setting.
abstract class DefaultSpeedProvider {
  double getDefaultSpeed();
}

/// Provides the queue connection ID that was active when the queue was created.
abstract class QueueConnectionIdProvider {
  int? getLastQueueConnectionId();
}

// ── PlaybackOrchestrator ─────────────────────────────────────────────────────

/// Core playback orchestrator that coordinates queue navigation, audio loading,
/// progress persistence, and listener management.
///
/// All external dependencies are injected through the constructor.
/// This class contains zero Riverpod or Flutter widget dependencies.
class PlaybackOrchestrator {
  final AudioPlayer player;
  final ActiveConnectionProvider connectionProvider;
  final PasswordReader passwordReader;
  final ProgressSaver progressSaver;
  final DefaultSpeedProvider defaultSpeedProvider;
  final QueueConnectionIdProvider queueConnectionIdProvider;

  /// Callback invoked whenever [queue] is mutated by orchestrator methods.
  ///
  /// This allows the Riverpod layer to synchronise its
  /// `currentPlayQueueProvider` state with the orchestrator's internal queue.
  void Function(PlayQueue?)? onQueueChanged;

  // ── Mutable state ─────────────────────────────────────────────────────

  /// The current play queue.  Set by the caller before calling load methods.
  PlayQueue? _queue;
  PlayQueue? get queue => _queue;
  set queue(PlayQueue? value) {
    _queue = value;
    onQueueChanged?.call(value);
  }

  /// The current play mode.
  PlayMode playMode = PlayMode.sequential;

  /// The connection ID that was active when the queue was last loaded.
  int? _activeConnectionId;

  final SerializedRequestGate _gate = SerializedRequestGate();
  Timer? _autoSaveTimer;
  StreamSubscription<ProcessingState>? _processingSub;
  StreamSubscription<PlayerState>? _pauseSaveSub;
  bool _completing = false;

  PlaybackOrchestrator({
    required this.player,
    required this.connectionProvider,
    required this.passwordReader,
    required this.progressSaver,
    required this.defaultSpeedProvider,
    required this.queueConnectionIdProvider,
  });

  /// The connection ID that was active when the queue was last loaded.
  int? get activeConnectionId => _activeConnectionId;

  // ── loadAndPlay ─────────────────────────────────────────────────────────

  /// Loads the current queue entry into the player and starts playback.
  ///
  /// Returns [TrackLoadResult.loaded] on success, [TrackLoadResult.failed]
  /// on any error (no queue, no connection, no password, playback failed),
  /// or [TrackLoadResult.superseded] if a newer request was scheduled.
  Future<TrackLoadResult> loadAndPlay({bool registerListeners = true}) {
    return _gate.schedule<TrackLoadResult>(
      onSuperseded: () => const TrackLoadResult.superseded(),
      task: (requestId) async {
        final q = queue;
        if (q == null || q.length == 0) {
          return const TrackLoadResult.failed();
        }

        try {
          // Check connection.
          final savedConnId =
              queueConnectionIdProvider.getLastQueueConnectionId();
          final activeConn = await connectionProvider
              .getActiveConnection()
              .timeout(const Duration(seconds: 5));
          if (activeConn == null) {
            return const TrackLoadResult.failed();
          }
          if (savedConnId != null && activeConn.id != savedConnId) {
            return const TrackLoadResult.failed();
          }
          if (!_gate.isLatest(requestId)) {
            return const TrackLoadResult.superseded();
          }

          // Read password.
          final password =
              await passwordReader.readPassword(activeConn.id!).timeout(
                    const Duration(seconds: 5),
                    onTimeout: () => null,
                  );
          if (password == null || password.isEmpty) {
            return const TrackLoadResult.failed();
          }
          if (!_gate.isLatest(requestId)) {
            return const TrackLoadResult.superseded();
          }

          // Build audio source.
          final source = AudioSourceBuilder.buildWithBasePath(
            baseUrl: activeConn.url,
            filePath: q.current.path,
            username: activeConn.username,
            password: password,
          );

          // Register processing listener before loading.
          if (registerListeners) _startProcessingListener();

          await player.setAudioSource(source);

          // Seek to resume position if specified.
          if (q.startPositionMs != null) {
            await player.seek(Duration(milliseconds: q.startPositionMs!));
          }

          // Apply default speed.
          final defaultSpeed = defaultSpeedProvider.getDefaultSpeed();
          if ((defaultSpeed - 1.0).abs() > 0.01) {
            await player.setSpeed(defaultSpeed);
          }

          if (!_gate.isLatest(requestId)) {
            return const TrackLoadResult.superseded();
          }

          // Start playback (don't await — may never complete).
          unawaited(player.play());
          var playStarted = false;
          for (int i = 0; i < 60; i++) {
            await Future<void>.delayed(const Duration(milliseconds: 200));
            if (player.playing) {
              playStarted = true;
              break;
            }
          }
          if (!playStarted && player.playing) {
            playStarted = true;
          }
          if (!playStarted) {
            await player.stop();
            return const TrackLoadResult.failed();
          }
          if (!_gate.isLatest(requestId)) {
            return const TrackLoadResult.superseded();
          }

          // Record active connection ID.
          _activeConnectionId = activeConn.id;

          // Start background listeners for progress persistence.
          if (registerListeners) {
            _startAutoSave();
            _startPauseSaveListener();
          }

          return TrackLoadResult.loaded(player);
        } catch (e) {
          return const TrackLoadResult.failed();
        } finally {
          _completing = false;
        }
      },
    );
  }

  // ── skipToNext ──────────────────────────────────────────────────────────

  /// Advances to the next track in the queue and loads it.
  ///
  /// Saves the current progress before advancing.
  Future<TrackLoadResult> skipToNext({bool registerListeners = true}) async {
    final q = queue;
    if (q == null) return const TrackLoadResult.failed();

    PlayQueue? nextQueue;
    if (playMode == PlayMode.shuffle) {
      nextQueue = q.advanceShuffle();
    }
    nextQueue ??= () {
      final ni = PlayQueue.nextIndex(q.currentIndex, q.length, playMode);
      return ni != null ? q.withIndex(ni) : null;
    }();

    if (nextQueue == null) {
      return const TrackLoadResult.failed();
    }

    saveProgress();
    queue = nextQueue;
    return loadAndPlay(registerListeners: registerListeners);
  }

  // ── skipToPrevious ──────────────────────────────────────────────────────

  /// Goes back to the previous track in the queue and loads it.
  ///
  /// Saves the current progress before going back.
  Future<TrackLoadResult> skipToPrevious(
      {bool registerListeners = true}) async {
    final q = queue;
    if (q == null) return const TrackLoadResult.failed();

    PlayQueue? prevQueue;
    if (playMode == PlayMode.shuffle) {
      prevQueue = q.retreatShuffle();
    }
    prevQueue ??= () {
      final pi = PlayQueue.previousIndex(q.currentIndex, q.length, playMode);
      return pi != null ? q.withIndex(pi) : null;
    }();

    if (prevQueue == null) {
      return const TrackLoadResult.failed();
    }

    saveProgress();
    queue = prevQueue;
    return loadAndPlay(registerListeners: registerListeners);
  }

  // ── selectQueueIndex ────────────────────────────────────────────────────

  /// Selects a specific queue index and loads that track.
  Future<TrackLoadResult> selectQueueIndex(int index,
      {bool registerListeners = true}) async {
    final q = queue;
    if (q == null || index < 0 || index >= q.length) {
      return const TrackLoadResult.failed();
    }
    if (index == q.currentIndex) {
      return const TrackLoadResult.failed();
    }

    saveProgress();
    queue = q.withIndex(index);
    return loadAndPlay(registerListeners: registerListeners);
  }

  // ── removeTrack ─────────────────────────────────────────────────────────

  /// Removes the track at [index] from the queue.
  ///
  /// - If the queue becomes empty, stops playback.
  /// - If the removed track was the current one, loads the next track.
  /// - If the removed track was not the current one, just updates the queue.
  Future<void> removeTrack(int index, {bool registerListeners = true}) async {
    final q = queue;
    if (q == null || index < 0 || index >= q.length) return;

    final wasCurrent = index == q.currentIndex;
    final newQueue = q.withoutIndex(index);

    if (newQueue.length == 0) {
      await player.stop();
      queue = null;
      _cancelAutoSave();
      _cancelPauseSave();
      return;
    }

    queue = newQueue;
    if (wasCurrent) {
      saveProgress();
      await loadAndPlay(registerListeners: registerListeners);
    }
  }

  // ── saveProgress ────────────────────────────────────────────────────────

  /// Saves the current playback position to the database.
  ///
  /// Uses the synchronous [ActiveConnectionProvider.currentConnection] to
  /// determine the connection ID, matching the original Riverpod behaviour
  /// where `ref.read(activeConnectionProvider).valueOrNull` is read at save
  /// time.
  void saveProgress() {
    final q = queue;
    final connId = connectionProvider.currentConnection?.id;
    if (q == null || connId == null) return;

    progressSaver.upsertProgress(
      connectionId: connId,
      filePath: q.current.path,
      positionMs: player.position.inMilliseconds,
      durationMs: player.duration?.inMilliseconds,
    );
  }

  // ── Processing listener (track completion) ──────────────────────────────

  /// Registers a listener on [player.processingStateStream] that handles
  /// track completion — auto-advance to next track or stop.
  void _startProcessingListener() {
    _processingSub?.cancel();
    _processingSub = player.processingStateStream.listen((state) {
      if (state == ProcessingState.completed) {
        if (_completing) return;
        _completing = true;

        final nextQueue = computeNextQueue();
        if (nextQueue == null) {
          player.pause();
          _completing = false;
          return;
        }

        saveProgress();
        queue = nextQueue;
        unawaited(loadAndPlay());
      }
    });
  }

  /// Computes the next queue entry based on the current mode, or `null` if
  /// playback should stop.
  PlayQueue? computeNextQueue() {
    final q = queue;
    if (q == null) return null;

    if (playMode == PlayMode.shuffle) {
      final advanced = q.advanceShuffle();
      if (advanced != null) return advanced;
    }

    final ni = PlayQueue.nextIndex(q.currentIndex, q.length, playMode);
    if (ni == null) return null;
    return q.withIndex(ni);
  }

  // ── Auto-save timer ─────────────────────────────────────────────────────

  void _startAutoSave() {
    _autoSaveTimer?.cancel();
    _autoSaveTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      saveProgress();
    });
  }

  void _cancelAutoSave() {
    _autoSaveTimer?.cancel();
    _autoSaveTimer = null;
  }

  // ── Pause-save listener ─────────────────────────────────────────────────

  void _startPauseSaveListener() {
    _pauseSaveSub?.cancel();
    var wasPlaying = player.playing;
    _pauseSaveSub = player.playerStateStream.listen((state) {
      final playing = state.playing;
      if (wasPlaying && !playing) {
        saveProgress();
      }
      wasPlaying = playing;
    });
  }

  void _cancelPauseSave() {
    _pauseSaveSub?.cancel();
    _pauseSaveSub = null;
  }

  // ── Cleanup ─────────────────────────────────────────────────────────────

  /// Cancels all internal subscriptions and timers.
  void dispose() {
    _processingSub?.cancel();
    _pauseSaveSub?.cancel();
    _cancelAutoSave();
  }
}
