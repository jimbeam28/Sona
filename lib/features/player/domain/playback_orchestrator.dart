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
//
// Playback listeners (track-completion auto-advance, auto-save, pause-save)
// live in the provider layer (player_provider.dart) — BUG-27-S2 removed the
// orchestrator-internal copies, which were never enabled in production.

import 'dart:async';
import 'dart:math';

import '../../../core/contracts/audio_player_contract.dart';
import '../../../core/services/audio_source_builder.dart';
import '../../../core/services/log_forwarder.dart';
import '../../../shared/models/connection_config.dart';
import '../../../shared/models/nas_file.dart';
import '../../../shared/models/play_queue.dart';
import '../../../shared/webdav_paths.dart';
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

/// Core playback orchestrator that coordinates queue navigation, audio
/// loading, and progress persistence.
///
/// All external dependencies are injected through the constructor.
/// This class contains zero Riverpod or Flutter widget dependencies.
class PlaybackOrchestrator {
  final IAudioPlayer player;
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

  /// RNG for shuffle-round regeneration (BUG-04-S2/S3).  Tests inject a
  /// seeded instance for determinism.
  final Random _rng;

  /// DL-01-S6 local-first port: resolves the local file path for a fully
  /// downloaded (done) entry, or null to continue with remote streaming.
  /// Optional — null keeps the pre-DL-01 behaviour byte-for-byte (INV1).
  final Future<String?> Function(int connectionId, String filePath)?
      localSourceResolver;

  PlaybackOrchestrator({
    required this.player,
    required this.connectionProvider,
    required this.passwordReader,
    required this.progressSaver,
    required this.defaultSpeedProvider,
    required this.queueConnectionIdProvider,
    Random? random,
    this.localSourceResolver,
  }) : _rng = random ?? Random();

  /// The connection ID that was active when the queue was last loaded.
  int? get activeConnectionId => _activeConnectionId;

  // ── loadAndPlay ─────────────────────────────────────────────────────────

  /// Loads the current queue entry into the player and starts playback.
  ///
  /// Returns [TrackLoadResult.loaded] on success, [TrackLoadResult.failed]
  /// on any error (no queue, no connection, no password, playback failed),
  /// or [TrackLoadResult.superseded] if a newer request was scheduled.
  Future<TrackLoadResult> loadAndPlay() {
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

          // DL-01-S6: 本地优先加载。已完整下载（done）且文件仍在磁盘时直接读
          // 本地，跳过密码读取与远程建源（免一次 secure storage 读）。resolver
          // 抛错按 null 兜底继续远程路径（BUG-18 同族加固），await 之后照例做
          // isLatest 复查防 superseded 竞态。
          String? localPath;
          final resolver = localSourceResolver;
          if (resolver != null) {
            try {
              localPath = await resolver(activeConn.id!, q.current.path);
            } catch (e) {
              debugLog('[Player] loadAndPlay: local source lookup failed: $e');
            }
            if (!_gate.isLatest(requestId)) {
              return const TrackLoadResult.superseded();
            }
          }

          if (localPath != null) {
            // Local hit: authenticated remote build bypassed entirely.
            await player.setAudioSource(AudioSourceBuilder.file(localPath));
          } else {
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

            // Build audio source. NET1: use the effective base URL so the
            // connection base (url.path joined with basePath) is applied exactly
            // once to the relative filePath returned by listDirectory.
            final source = AudioSourceBuilder.buildWithBasePath(
              baseUrl:
                  webDavEffectiveBaseUrl(activeConn.url, activeConn.basePath),
              filePath: q.current.path,
              username: activeConn.username,
              password: password,
            );

            await player.setAudioSource(source);
          }

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
          var playStarted = player.playing;
          if (!playStarted) {
            final completer = Completer<bool>();
            StreamSubscription<PlayerState>? sub;
            sub = player.playerStateStream.listen((state) {
              if (state.playing && !completer.isCompleted) {
                completer.complete(true);
                sub?.cancel();
              }
            });
            try {
              // BUG-18: timeout must not be shorter than the original 12s
              // polling window (spec BUG-18-S1/INV2 fixes it at 30s).
              playStarted = await completer.future
                  .timeout(const Duration(seconds: 30), onTimeout: () => false);
            } finally {
              sub.cancel();
            }
          }
          if (!playStarted) {
            // BUG-23 (cr-20260823-1421 F1): 被取代的任务不得停掉后继请求的
            // 加载现场——removeTrack（BUG-27-S1）同款时效纪律：对共享 player
            // 做破坏性收尾前必须确认自己仍是 latest。
            if (!_gate.isLatest(requestId)) {
              return const TrackLoadResult.superseded();
            }
            await player.stop();
            return const TrackLoadResult.failed();
          }
          if (!_gate.isLatest(requestId)) {
            return const TrackLoadResult.superseded();
          }

          // Record active connection ID.
          _activeConnectionId = activeConn.id;

          return const TrackLoadResult.loaded();
        } catch (e) {
          // BUG-05（cr-20260816-0802 B3）：catch-log 全局裁决（SCHEMA.md §5）——
          // 任何 catch 必须先留日志才允许吞掉异常。对照 saveProgress 正确写法
          // （:407-413）。异常文本不含凭证（连接密码只经 PasswordReader 传递，
          // 不进任务体异常）。
          debugLog('[Player] loadAndPlay failed: $e');
          return const TrackLoadResult.failed();
        }
      },
    );
  }

  // ── skipToNext ──────────────────────────────────────────────────────────

  /// Advances to the next track in the queue and loads it.
  ///
  /// Saves the current progress before advancing.
  Future<TrackLoadResult> skipToNext() async {
    final q = queue;
    if (q == null) return const TrackLoadResult.failed();

    PlayQueue? nextQueue;
    if (playMode == PlayMode.shuffle) {
      nextQueue = q.advanceShuffle();
      if (nextQueue == null && q.length > 0) {
        // BUG-04-S2 (user adjudication 2026-07-24): the permutation is
        // exhausted → reshuffle a fresh round instead of degrading to a
        // random blind pick (cr-20260724-0110 PLY3).
        nextQueue = _regenerateShuffleQueue(q, excludeIndex: q.currentIndex);
      }
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
    return loadAndPlay();
  }

  // ── skipToPrevious ──────────────────────────────────────────────────────

  /// Goes back to the previous track in the queue and loads it.
  ///
  /// Saves the current progress before going back.
  Future<TrackLoadResult> skipToPrevious() async {
    final q = queue;
    if (q == null) return const TrackLoadResult.failed();

    PlayQueue? prevQueue;
    if (playMode == PlayMode.shuffle) {
      prevQueue = q.retreatShuffle();
      if (prevQueue == null && q.length > 0) {
        // BUG-04-S3: at the head of the permutation → reshuffle a fresh
        // round and land on its LAST entry (pointer at the end), never a
        // random previousIndex pick.
        prevQueue = _regenerateShuffleQueue(q,
            excludeIndex: q.currentIndex, forPrevious: true);
      }
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
    return loadAndPlay();
  }

  // ── selectQueueIndex ────────────────────────────────────────────────────

  /// Selects a specific queue index and loads that track.
  Future<TrackLoadResult> selectQueueIndex(int index) async {
    final q = queue;
    if (q == null || index < 0 || index >= q.length) {
      return const TrackLoadResult.failed();
    }
    if (index == q.currentIndex) {
      return const TrackLoadResult.failed();
    }

    saveProgress();
    queue = q.withIndex(index);
    return loadAndPlay();
  }

  // ── removeTrack ─────────────────────────────────────────────────────────

  /// Removes the track at [index] from the queue.
  ///
  /// - If the queue becomes empty, stops playback and returns `null`.
  /// - If the removed track was the current one, loads the next track and
  ///   returns its [TrackLoadResult] so the caller can start playback
  ///   listeners on success (BUG-07 — load outcome, not `player.playing`).
  /// - If the removed track was not the current one, just updates the queue
  ///   and returns `null` (no load).
  Future<TrackLoadResult?> removeTrack(int index) async {
    final q = queue;
    if (q == null || index < 0 || index >= q.length) return null;

    final wasCurrent = index == q.currentIndex;
    final newQueue = q.withoutIndex(index);

    if (newQueue.length == 0) {
      // BUG-27-S1: invalidate any in-flight gate request BEFORE stopping so
      // a suspended load task (weak network) resumes into isLatest()==false
      // → superseded, instead of continuing to setAudioSource + play
      // (ghost playback).  With the gate idle this is a harmless ID bump.
      _gate.beginRequest();
      await player.stop();
      queue = null;
      return null;
    }

    if (wasCurrent) {
      // cr-20260804-1922 §5 O2: save BEFORE reassigning the queue so
      // q.current still refers to the removed track — same ordering as
      // skipToNext / skipToPrevious / selectQueueIndex.  Saving after the
      // reassignment would persist the removed track's position under the
      // NEXT track's path (进度张冠李戴 → wrong resume position later).
      saveProgress();
      queue = newQueue;
      return await loadAndPlay();
    } else {
      queue = newQueue;
      return null;
    }
  }

  // ── insertAfterCurrent ─────────────────────────────────────────────────

  /// Inserts [file] immediately after the current track in the queue.
  ///
  /// - The current track keeps playing; the new file becomes the next track.
  /// - Does **not** call [loadAndPlay] or [saveProgress] (no track switch).
  /// - Triggers [onQueueChanged] so the Riverpod layer syncs.
  ///
  /// Returns `true` on success, `false` when there is no active queue.
  bool insertAfterCurrent(NasFile file) {
    final q = queue;
    if (q == null) return false;
    queue = q.insertAfterCurrent(file);
    return true;
  }

  /// Reorders the queue by moving the track at [from] to index [to].
  ///
  /// PLY-01-S5: pure order change — writes back through the [queue] setter
  /// (which fires [onQueueChanged] for Riverpod sync) and returns `true`.
  /// Never calls saveProgress / loadAndPlay / _gate.beginRequest or any
  /// player method: no track switch happens and in-flight loads stay valid
  /// (PLY-01-S11).
  ///
  /// PLY-01-S6: returns `false` without any callback when there is no active
  /// queue, when the indices are out of range / equal (model short-circuit
  /// yields an identical instance), or when the queue is in shuffle mode
  /// (PLY-01-INV3 model gate).  The only production caller of
  /// [PlayQueue.move] (PLY-01-INV2 single-writer discipline).
  Future<bool> moveTrack(int from, int to) async {
    final q = queue;
    if (q == null) return false;
    final moved = q.move(from, to);
    if (identical(moved, q)) return false;
    queue = moved;
    return true;
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

    unawaited(progressSaver
        .upsertProgress(
      connectionId: connId,
      filePath: q.current.path,
      positionMs: player.position.inMilliseconds,
      durationMs: player.duration?.inMilliseconds,
    )
        .catchError((Object e) {
      // BUG-19: DB lock / disk full / disposed — log and swallow. The save
      // is fire-and-forget, so the error must never surface as an unhandled
      // async error, but it must not vanish silently either (observability
      // via log — never swallow without logging).
      debugLog('[Player] saveProgress failed: $e');
    }));
  }

  // ── Queue progression (track completion) ────────────────────────────────

  /// Computes the next queue entry based on the current mode, or `null` if
  /// playback should stop.
  PlayQueue? computeNextQueue() {
    final q = queue;
    if (q == null) return null;

    if (playMode == PlayMode.shuffle) {
      final advanced = q.advanceShuffle();
      if (advanced != null) return advanced;
      // BUG-04-S2 (user adjudication 2026-07-24): permutation exhausted →
      // reshuffle a fresh round; never degrade to a random blind pick
      // (cr-20260724-0110 PLY3).
      if (q.length > 0) {
        return _regenerateShuffleQueue(q, excludeIndex: q.currentIndex);
      }
      return null;
    }

    final ni = PlayQueue.nextIndex(q.currentIndex, q.length, playMode);
    if (ni == null) return null;
    return q.withIndex(ni);
  }

  // ── Shuffle regeneration (BUG-04-S2/S3) ─────────────────────────────────

  /// Generates a fresh Fisher-Yates round when the current permutation is
  /// exhausted — user adjudication 2026-07-24「重洗新一轮」.
  ///
  /// [excludeIndex] (the track that just finished / is playing) is kept out
  /// of the first slot so the same track never replays right after a round
  /// completes (BUG-04-S2 negative assertion).  With [forPrevious]
  /// (BUG-04-S3) the pointer is placed at the LAST slot instead, so a
  /// reshuffle triggered by skipToPrevious lands on the new round's final
  /// track and retreatShuffle can walk backwards through the round.
  ///
  /// Single-track queues degenerate to replaying that one track (spec §3.2
  /// 边界裁决: `files.length == 1` → 仍播同一首).
  PlayQueue _regenerateShuffleQueue(PlayQueue q,
      {required int excludeIndex, bool forPrevious = false}) {
    List<int> order;
    do {
      order = PlayQueue.generateShuffleOrder(q.length, _rng);
    } while (q.length > 1 && order[0] == excludeIndex);
    final position = forPrevious ? order.length - 1 : 0;
    return PlayQueue(
      files: q.files,
      currentIndex: order[position],
      startPositionMs: null,
      playMode: q.playMode,
      shuffleOrder: order,
      shufflePosition: position,
    );
  }

  // ── Cleanup ─────────────────────────────────────────────────────────────

  /// Lifecycle hook kept for call-site compatibility (player_provider.dart
  /// registers it via ref.onDispose).  Playback listeners live in the
  /// provider layer (BUG-27-S2), so the orchestrator itself holds no
  /// subscriptions or timers to clean up.
  void dispose() {}
}
