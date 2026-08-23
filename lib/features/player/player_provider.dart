// lib/features/player/player_provider.dart — REF-15: thin glue layer.
// Delegates to PlaybackOrchestrator (REF-14). Processing-state listener,
// auto-save, and pause-save remain here (bridge just_audio → Riverpod).

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/contracts/audio_handler_contract.dart';
import '../../core/services/audio_handler.dart';
import '../../core/services/log_forwarder.dart';
import '../../core/services/audio_player_adapter.dart';
import '../../shared/models/connection_config.dart';
import '../../shared/models/nas_file.dart';
import '../../shared/models/play_progress.dart';
import '../../shared/models/play_queue.dart';
import '../../shared/webdav_paths.dart';
import '../../shared/di/providers.dart';
import 'background_playback_notifier.dart';
import 'domain/playback_orchestrator.dart';
import 'domain/request_gate.dart';
import 'domain/speed_manager.dart' as sm;

export 'background_playback_notifier.dart'
    show BackgroundPlaybackNotifier, backgroundPlaybackProvider;
export 'domain/background_playback.dart'
    show
        AppLifecyclePhase,
        AudioFocusState,
        BackgroundPlaybackConfig,
        BackgroundPlaybackState,
        MediaControlAction,
        computePlaybackStateAfterLifecycle,
        shouldContinueInBackground;
export 'domain/media_control.dart' show formatDuration;
export 'domain/play_mode.dart' show PlayMode, labelForPlayMode;
export 'domain/request_gate.dart'
    show
        PlayerLoadStatus,
        PlayerLoadState,
        SerializedRequestGate,
        TrackLoadResult,
        TrackLoadStatus;
export 'domain/speed_manager.dart'
    show
        speedOptions,
        isValidSpeed,
        defaultSpeedKey,
        seekStepPrefsKey,
        defaultSeekStep;

final audioPlayerProvider = Provider<AudioPlayer>((ref) {
  final p = AudioPlayer();
  ref.onDispose(() => p.dispose());
  return p;
});

/// REF-01-A5: reads the default playback speed directly from
/// [SharedPreferences] (domain layer no longer exposes a reader function).
double _readDefaultSpeed(SharedPreferences? prefs) =>
    prefs?.getDouble(sm.defaultSpeedKey) ?? 1.0;
final audioPlayingProvider = StreamProvider<bool>((ref) {
  final player = ref.watch(audioPlayerProvider);
  return player.playingStream;
});
final audioHandlerProvider = Provider<IAudioHandler?>((ref) => null);

class _Deps
    implements
        ActiveConnectionProvider,
        PasswordReader,
        ProgressSaver,
        DefaultSpeedProvider,
        QueueConnectionIdProvider {
  final Ref _ref;
  _Deps(this._ref);
  @override
  Future<ConnectionConfig?> getActiveConnection() =>
      _ref.read(activeConnectionProvider.future);
  @override
  ConnectionConfig? get currentConnection =>
      _ref.read(activeConnectionProvider).valueOrNull;
  @override
  Future<String?> readPassword(int id) =>
      _ref.read(secureStorageProvider).read(key: 'connection_password_$id');
  @override
  Future<void> upsertProgress({
    required int connectionId,
    required String filePath,
    required int positionMs,
    int? durationMs,
  }) async =>
      _ref.read(upsertProgressProvider)(
          connectionId: connectionId,
          filePath: filePath,
          positionMs: positionMs,
          durationMs: durationMs);
  @override
  double getDefaultSpeed() =>
      _readDefaultSpeed(_ref.read(sharedPreferencesProvider));
  @override
  int? getLastQueueConnectionId() => _ref.read(lastQueueConnectionIdProvider);
}

final playbackOrchestratorProvider = Provider<PlaybackOrchestrator>((ref) {
  final d = _Deps(ref);
  final o = PlaybackOrchestrator(
    player: AudioPlayerAdapter(ref.read(audioPlayerProvider)),
    connectionProvider: d,
    passwordReader: d,
    progressSaver: d,
    defaultSpeedProvider: d,
    queueConnectionIdProvider: d,
  );
  // Guard to prevent circular updates between orchestrator and Riverpod.
  var _syncingFromOrchestrator = false;
  // Sync orchestrator queue → Riverpod state.
  o.onQueueChanged = (q) {
    _syncingFromOrchestrator = true;
    ref.read(currentPlayQueueProvider.notifier).state = q;
    _syncingFromOrchestrator = false;
    if (q == null) {
      // REF-02-S8: the provider is typed as IAudioHandler; clearing the
      // notification media item needs the concrete BehaviorSubject exposed by
      // BaseAudioHandler (not part of the contract surface), so the wiring
      // point casts back to the concrete handler.
      (ref.read(audioHandlerProvider) as NasAudioHandler?)?.mediaItem.add(null);
    } else {
      _syncMediaItemToHandler(ref);
    }
  };
  // Sync Riverpod state → orchestrator queue (external mutations only).
  ref.listen<PlayQueue?>(currentPlayQueueProvider, (_, n) {
    if (!_syncingFromOrchestrator) o.queue = n;
  });
  o.queue = ref.read(currentPlayQueueProvider);
  ref.listen<PlayMode>(playModeProvider, (_, n) => o.playMode = n);
  o.playMode = ref.read(playModeProvider);
  ref.onDispose(() => o.dispose());
  return o;
});

final playModeProvider = StateProvider<PlayMode>((ref) => PlayMode.sequential);
final nextPlayModeProvider = Provider<PlayMode Function()>((ref) => () {
      final c = ref.read(playModeProvider);
      final n = PlayMode.values[(c.index + 1) % PlayMode.values.length];
      ref.read(playModeProvider.notifier).state = n;
      // O3 follow-up (cr-20260804-1922 §5 O3): sync the queue's playMode
      // field with the new mode.  Without this the persisted queue
      // (persistQueueOnChange → PlayQueue.toMap) keeps the mode from queue
      // creation forever, so a restart restores the stale mode via
      // restoreQueueFromPrefsProvider and the user's selection is lost.
      // No queue (pure mode toggle without playback) → nothing to write.
      // Equal-mode guard keeps repeated toggles side-effect free.  The queue
      // write is captured naturally by persistQueueOnChange; no cycle — a
      // queue change never writes playModeProvider.
      final q = ref.read(currentPlayQueueProvider);
      if (q != null && q.playMode != n) {
        ref.read(currentPlayQueueProvider.notifier).state = q.withMode(n);
      }
      return n;
    });
IconData iconForPlayMode(PlayMode mode) => switch (mode) {
      PlayMode.sequential => Icons.playlist_play,
      PlayMode.repeatOne => Icons.repeat_one,
      PlayMode.repeatAll => Icons.repeat,
      PlayMode.shuffle => Icons.shuffle,
    };
final defaultSpeedProvider = Provider<double>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return _readDefaultSpeed(prefs);
});
final setDefaultSpeedProvider = Provider<void Function(double)>((ref) => (s) {
      if (!sm.isValidSpeed(s)) return;
      ref.read(sharedPreferencesProvider)?.setDouble(sm.defaultSpeedKey, s);
      ref.invalidate(defaultSpeedProvider);
    });

int sanitizeResumePosition(int pos, int? dur) => pos < 0
    ? 0
    : (dur != null && dur > 0 && pos >= dur)
        ? 0
        : pos;

/// Applies the latest saved progress to [queue] when it refers to the same
/// connection and the same current track.
///
/// [connectionRoot] (cr-20260804-1922 O1) — when supplied, both the stored
/// progress path and the queue's current path are normalised with it before
/// comparison. This makes startup resume work for pre-NET1 progress rows
/// that hold server-absolute paths while the restored queue carries
/// connection-root-relative paths (or vice versa). When omitted the paths are
/// compared verbatim (legacy behaviour, kept for callers without a connection
/// context).
PlayQueue? applyLatestProgressToQueue({
  required PlayQueue? queue,
  required int? activeConnectionId,
  required PlayProgress? latestProgress,
  String? connectionRoot,
}) {
  if (queue == null || activeConnectionId == null || latestProgress == null)
    return queue;
  if (latestProgress.connectionId != activeConnectionId) return queue;
  final progressPath = connectionRoot == null
      ? latestProgress.filePath
      : normalizeStoredPath(latestProgress.filePath, basePath: connectionRoot);
  final queuePath = connectionRoot == null
      ? queue.current.path
      : normalizeStoredPath(queue.current.path, basePath: connectionRoot);
  if (progressPath != queuePath) return queue;
  return queue.withStartPosition(sanitizeResumePosition(
      latestProgress.positionMs, latestProgress.durationMs));
}

final restoreStartupProgressProvider = FutureProvider<void>((ref) async {
  await ref.read(restoreQueueFromPrefsProvider.future);
  final q = ref.read(currentPlayQueueProvider);
  final c = ref.read(activeConnectionProvider).valueOrNull;
  final p = await ref.read(latestPlayedProgressProvider.future);
  final r = applyLatestProgressToQueue(
      queue: q,
      activeConnectionId: c?.id,
      latestProgress: p,
      // O1: normalise both sides of the path comparison so pre-NET1
      // server-absolute progress rows still align with the restored queue.
      connectionRoot:
          c == null ? null : webDavConnectionRoot(c.url, c.basePath));
  if (r != null && r != q) {
    ref.read(currentPlayQueueProvider.notifier).state = r;
    final pl = ref.read(audioPlayerProvider);
    if (pl.audioSource != null) {
      await pl.seek(Duration(milliseconds: r.startPositionMs ?? 0));
    }
  }
});
final backgroundPlaybackSyncProvider = Provider<void>((ref) {
  final h = ref.read(audioHandlerProvider);
  final n = ref.read(backgroundPlaybackProvider.notifier);
  h?.onConfigChanged = n.syncFromHandler;
  // BUG-02: skip 回调归应用级接线（P8 踩坑：播放生命周期资源严禁绑定
  // 页面 dispose）。通知栏/耳机 skip → 编排层推进队列；空队列下
  // orchestrator 安全返回 failed（playback_orchestrator.dart:253-255），
  // 无副作用。接线时机 = home_screen.dart:80 的 eager-read。
  h?.onSkipToNextRequested = () {
    unawaited(ref.read(skipToNextProvider)());
  };
  h?.onSkipToPreviousRequested = () {
    unawaited(ref.read(skipToPreviousProvider)());
  };
  ref.onDispose(() {
    h?.onConfigChanged = null;
    h?.onSkipToNextRequested = null;
    h?.onSkipToPreviousRequested = null;
  });
});

final _processingSubProvider =
    StateProvider<StreamSubscription<void>?>((ref) => null);
final _autoSaveTimerProvider = StateProvider<Timer?>((ref) => null);
final _pauseSaveSubProvider =
    StateProvider<StreamSubscription<void>?>((ref) => null);
final _completingProvider = StateProvider<bool>((ref) => false);

final saveProgressProvider = Provider<void Function()>(
    (ref) => () => ref.read(playbackOrchestratorProvider).saveProgress());

final _startAutoSaveProvider = Provider<void Function()>((ref) {
  // BUG-21: cancel via the locally captured handle. ref.read() inside
  // onDispose throws during ProviderContainer.dispose (the container is
  // already marked disposed) and the timer would leak.
  Timer? timer;
  ref.onDispose(() => timer?.cancel());
  return () {
    ref.read(_autoSaveTimerProvider)?.cancel();
    timer = Timer.periodic(
        const Duration(seconds: 10), (_) => ref.read(saveProgressProvider)());
    ref.read(_autoSaveTimerProvider.notifier).state = timer;
  };
});
final _cancelAutoSaveProvider = Provider<void Function()>((ref) => () {
      ref.read(_autoSaveTimerProvider)?.cancel();
      ref.read(_autoSaveTimerProvider.notifier).state = null;
    });
final _startPauseSaveProvider = Provider<void Function(AudioPlayer)>((ref) {
  // BUG-21: cancel via the locally captured handle (see _startAutoSaveProvider).
  StreamSubscription<void>? sub;
  ref.onDispose(() => sub?.cancel());
  return (p) {
    ref.read(_pauseSaveSubProvider)?.cancel();
    var was = p.playing;
    sub = p.playerStateStream.listen((s) {
      if (was && !s.playing) ref.read(saveProgressProvider)();
      was = s.playing;
    });
    ref.read(_pauseSaveSubProvider.notifier).state = sub;
  };
});
final _cancelPauseSaveProvider = Provider<void Function()>((ref) => () {
      ref.read(_pauseSaveSubProvider)?.cancel();
      ref.read(_pauseSaveSubProvider.notifier).state = null;
    });

final cancelProcessingListenerProvider = Provider<void Function()>((ref) => () {
      ref.read(_processingSubProvider)?.cancel();
      ref.read(_processingSubProvider.notifier).state = null;
    });

final startProcessingListenerProvider = Provider<void Function()>((ref) {
  // BUG-21: cancel via the locally captured handle (see _startAutoSaveProvider).
  StreamSubscription<void>? sub;
  ref.onDispose(() => sub?.cancel());
  return () {
    final player = ref.read(audioPlayerProvider);
    ref.read(cancelProcessingListenerProvider)();
    sub = player.processingStateStream.listen((state) {
      if (state != ProcessingState.completed) return;
      if (ref.read(_completingProvider)) return;
      ref.read(_completingProvider.notifier).state = true;
      if (ref.read(onTrackCompletedProvider)()) {
        player.pause();
        ref.read(_completingProvider.notifier).state = false;
        return;
      }
      final o = ref.read(playbackOrchestratorProvider);
      final nq = o.computeNextQueue();
      if (nq == null) {
        // P2: Android completed 态忽略后续 seek/play —— 必须显式 seek(0) 退出该态
        unawaited(player.seek(Duration.zero));
        player.pause();
        ref.read(_completingProvider.notifier).state = false;
        return;
      }
      ref.read(saveProgressProvider)();
      ref.read(currentPlayQueueProvider.notifier).state = nq;
      unawaited(ref.read(loadAndPlayProvider)());
    });
    ref.read(_processingSubProvider.notifier).state = sub;
  };
});

/// Starts playback listeners after a successful track load.
/// Shared by loadAndPlayProvider and queue-navigation providers.
void _startPlaybackListeners(Ref ref) {
  _syncMediaItemToHandler(ref);
  ref.read(startProcessingListenerProvider)();
  ref.read(_startAutoSaveProvider)();
  ref.read(_startPauseSaveProvider)(ref.read(audioPlayerProvider));
}

/// BUG-04（cr-20260816-0802 B2）：加载成功/队列变更时把当前曲目推送到
/// audio_service mediaItem 流，通知栏/锁屏才能显示曲名与时长。
/// handler 为 null（AudioService.init 失败）时空操作。
void _syncMediaItemToHandler(Ref ref) {
  final h = ref.read(audioHandlerProvider);
  if (h == null) return;
  final q = ref.read(currentPlayQueueProvider);
  if (q == null || q.length == 0) return;
  h.setMediaItemFromPath(q.current.path);
}

/// BUG-03（cr-20260816-0802 B1）：gate 超时/平台错误经异常路径抛回
/// （request_gate.dart completeError）。守卫必须无条件复位（try/finally
/// 语义），异常记日志后吞掉——completed 监听器 unawaited 无错误处理，放任
/// 传播即 unhandled async error，且守卫卡 true 会让自动切歌永久失效。
Future<TrackLoadResult> _runLoadOrchestrated(
  Ref ref,
  Future<TrackLoadResult> Function() action,
) async {
  TrackLoadResult r;
  try {
    r = await action();
  } catch (e, st) {
    debugLog('[Player] loadAndPlay failed: $e\n$st');
    return const TrackLoadResult.failed();
  } finally {
    ref.read(_completingProvider.notifier).state = false;
  }
  if (r.isLoaded) _startPlaybackListeners(ref);
  return r;
}

final Provider<Future<TrackLoadResult> Function()> loadAndPlayProvider =
    Provider<Future<TrackLoadResult> Function()>((ref) => () async {
          return _runLoadOrchestrated(
              ref, () => ref.read(playbackOrchestratorProvider).loadAndPlay());
        });

final Provider<Future<TrackLoadResult> Function()> skipToNextProvider =
    Provider<Future<TrackLoadResult> Function()>((ref) => () async {
          return _runLoadOrchestrated(
              ref, () => ref.read(playbackOrchestratorProvider).skipToNext());
        });

final skipToPreviousProvider =
    Provider<Future<TrackLoadResult> Function()>((ref) => () async {
          return _runLoadOrchestrated(ref,
              () => ref.read(playbackOrchestratorProvider).skipToPrevious());
        });

final selectQueueIndexProvider =
    Provider<Future<TrackLoadResult> Function(int)>((ref) => (i) async {
          return _runLoadOrchestrated(ref,
              () => ref.read(playbackOrchestratorProvider).selectQueueIndex(i));
        });

final removeTrackFromQueueProvider =
    Provider<Future<void> Function(int)>((ref) => (i) async {
          final q = ref.read(currentPlayQueueProvider);
          if (q == null || i < 0 || i >= q.length) return;
          final wasCurrent = i == q.currentIndex;
          final result =
              await ref.read(playbackOrchestratorProvider).removeTrack(i);
          // BUG-07（cr-20260816-0802 F3）：wasCurrent 删除 + 加载成功即
          // 无条件启动监听器，不依赖同步读 player.playing（P3：加载期间
          // 暂停/playing 不传播 → 旧条件判定漏启 → 自动切歌/自动保存缺失）。
          if (wasCurrent && result != null && result.isLoaded) {
            _startPlaybackListeners(ref);
          }
        });

final insertAfterCurrentProvider =
    Provider<Future<bool> Function(NasFile)>((ref) => (NasFile f) async {
          return ref.read(playbackOrchestratorProvider).insertAfterCurrent(f);
        });

final reconnectPlaybackListenersProvider =
    Provider<void Function()>((ref) => () {
          ref.read(startProcessingListenerProvider)();
          ref.read(_startAutoSaveProvider)();
          ref.read(_startPauseSaveProvider)(ref.read(audioPlayerProvider));
        });
final cancelPlaybackSubscriptionsProvider =
    Provider<void Function()>((ref) => () {
          ref.read(_cancelAutoSaveProvider)();
          ref.read(_cancelPauseSaveProvider)();
        });
