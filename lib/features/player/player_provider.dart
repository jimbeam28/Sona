// lib/features/player/player_provider.dart — REF-15: thin glue layer.
// Delegates to PlaybackOrchestrator (REF-14). Processing-state listener,
// auto-save, and pause-save remain here (bridge just_audio → Riverpod).

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';
import '../../core/services/audio_handler.dart';
import '../../shared/models/connection_config.dart';
import '../../shared/models/play_progress.dart';
import '../../shared/models/play_queue.dart';
import '../../shared/di/providers.dart';
import 'domain/background_playback.dart';
import 'domain/playback_orchestrator.dart';
import 'domain/request_gate.dart';
import 'domain/speed_manager.dart' as sm;

export 'domain/background_playback.dart'
    show
        AudioFocusState,
        BackgroundPlaybackConfig,
        BackgroundPlaybackNotifier,
        BackgroundPlaybackState,
        MediaControlAction,
        backgroundPlaybackProvider,
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
    show speedOptions, isValidSpeed, getDefaultSpeed, readSeekStep;

final audioPlayerProvider = Provider<AudioPlayer>((ref) {
  final p = AudioPlayer();
  ref.onDispose(() => p.dispose());
  return p;
});
final audioHandlerProvider = Provider<NasAudioHandler?>((ref) => null);

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
      sm.getDefaultSpeed(_ref.read(sharedPreferencesProvider));
  @override
  int? getLastQueueConnectionId() => _ref.read(lastQueueConnectionIdProvider);
}

final playbackOrchestratorProvider = Provider<PlaybackOrchestrator>((ref) {
  final d = _Deps(ref);
  final o = PlaybackOrchestrator(
    player: ref.read(audioPlayerProvider),
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
      ref.read(audioHandlerProvider)?.mediaItem.add(null);
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

final seekStepProvider = StateProvider<int>(
    (ref) => sm.readSeekStep(ref.watch(sharedPreferencesProvider)));
final playModeProvider = StateProvider<PlayMode>((ref) => PlayMode.sequential);
final nextPlayModeProvider = Provider<PlayMode Function()>((ref) => () {
      final c = ref.read(playModeProvider);
      final n = PlayMode.values[(c.index + 1) % PlayMode.values.length];
      ref.read(playModeProvider.notifier).state = n;
      return n;
    });
IconData iconForPlayMode(PlayMode mode) => switch (mode) {
      PlayMode.sequential => Icons.playlist_play,
      PlayMode.repeatOne => Icons.repeat_one,
      PlayMode.repeatAll => Icons.repeat,
      PlayMode.shuffle => Icons.shuffle,
    };
final defaultSpeedProvider = Provider<double>(
    (ref) => sm.getDefaultSpeed(ref.watch(sharedPreferencesProvider)));
final setDefaultSpeedProvider = Provider<void Function(double)>((ref) => (s) {
      if (!sm.isValidSpeed(s)) return;
      ref.read(sharedPreferencesProvider)?.setDouble(sm.defaultSpeedKey, s);
      ref.invalidate(defaultSpeedProvider);
      ref.read(currentSpeedProvider.notifier).state = s;
    });
final currentSpeedProvider =
    StateProvider<double>((ref) => ref.read(defaultSpeedProvider));

int sanitizeResumePosition(int pos, int? dur) => pos < 0
    ? 0
    : (dur != null && dur > 0 && pos >= dur)
        ? 0
        : pos;

PlayQueue? applyLatestProgressToQueue({
  required PlayQueue? queue,
  required int? activeConnectionId,
  required PlayProgress? latestProgress,
}) {
  if (queue == null || activeConnectionId == null || latestProgress == null)
    return queue;
  if (latestProgress.connectionId != activeConnectionId) return queue;
  if (latestProgress.filePath != queue.current.path) return queue;
  return queue.withStartPosition(sanitizeResumePosition(
      latestProgress.positionMs, latestProgress.durationMs));
}

final backgroundPlaybackEnabledProvider = StateProvider<bool>((ref) => true);
final restoreStartupProgressProvider = FutureProvider<void>((ref) async {
  await ref.read(restoreQueueFromPrefsProvider.future);
  final q = ref.read(currentPlayQueueProvider);
  final c = ref.read(activeConnectionProvider).valueOrNull;
  final p = await ref.read(latestPlayedProgressProvider.future);
  final r = applyLatestProgressToQueue(
      queue: q, activeConnectionId: c?.id, latestProgress: p);
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
  ref.onDispose(() => h?.onConfigChanged = null);
});

final _processingSubProvider =
    StateProvider<StreamSubscription<void>?>((ref) => null);
final _autoSaveTimerProvider = StateProvider<Timer?>((ref) => null);
final _pauseSaveSubProvider =
    StateProvider<StreamSubscription<void>?>((ref) => null);
final _completingProvider = StateProvider<bool>((ref) => false);

final saveProgressProvider = Provider<void Function()>(
    (ref) => () => ref.read(playbackOrchestratorProvider).saveProgress());

final _startAutoSaveProvider = Provider<void Function()>((ref) => () {
      ref.read(_autoSaveTimerProvider)?.cancel();
      ref.read(_autoSaveTimerProvider.notifier).state = Timer.periodic(
          const Duration(seconds: 10), (_) => ref.read(saveProgressProvider)());
    });
final _cancelAutoSaveProvider = Provider<void Function()>((ref) => () {
      ref.read(_autoSaveTimerProvider)?.cancel();
      ref.read(_autoSaveTimerProvider.notifier).state = null;
    });
final _startPauseSaveProvider =
    Provider<void Function(AudioPlayer)>((ref) => (p) {
          ref.read(_pauseSaveSubProvider)?.cancel();
          var was = p.playing;
          ref.read(_pauseSaveSubProvider.notifier).state =
              p.playerStateStream.listen((s) {
            if (was && !s.playing) ref.read(saveProgressProvider)();
            was = s.playing;
          });
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
  ref.onDispose(() => ref.read(_processingSubProvider)?.cancel());
  return () {
    final player = ref.read(audioPlayerProvider);
    ref.read(cancelProcessingListenerProvider)();
    ref.read(_processingSubProvider.notifier).state =
        player.processingStateStream.listen((state) {
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
        player.pause();
        ref.read(_completingProvider.notifier).state = false;
        return;
      }
      ref.read(saveProgressProvider)();
      ref.read(currentPlayQueueProvider.notifier).state = nq;
      unawaited(ref.read(loadAndPlayProvider)());
    });
  };
});

/// Starts playback listeners after a successful track load.
/// Shared by loadAndPlayProvider and queue-navigation providers.
void _startPlaybackListeners(Ref ref) {
  ref.read(startProcessingListenerProvider)();
  ref.read(_startAutoSaveProvider)();
  ref.read(_startPauseSaveProvider)(ref.read(audioPlayerProvider));
  final ds = ref.read(defaultSpeedProvider);
  if ((ds - 1.0).abs() > 0.01)
    ref.read(currentSpeedProvider.notifier).state = ds;
}

final Provider<Future<TrackLoadResult> Function()> loadAndPlayProvider =
    Provider<Future<TrackLoadResult> Function()>((ref) => () async {
          final r = await ref
              .read(playbackOrchestratorProvider)
              .loadAndPlay(registerListeners: false);
          if (r.isLoaded) _startPlaybackListeners(ref);
          ref.read(_completingProvider.notifier).state = false;
          return r;
        });

final Provider<Future<TrackLoadResult> Function()> skipToNextProvider =
    Provider<Future<TrackLoadResult> Function()>((ref) => () async {
          final r = await ref
              .read(playbackOrchestratorProvider)
              .skipToNext(registerListeners: false);
          if (r.isLoaded) _startPlaybackListeners(ref);
          ref.read(_completingProvider.notifier).state = false;
          return r;
        });

final skipToPreviousProvider =
    Provider<Future<TrackLoadResult> Function()>((ref) => () async {
          final r = await ref
              .read(playbackOrchestratorProvider)
              .skipToPrevious(registerListeners: false);
          if (r.isLoaded) _startPlaybackListeners(ref);
          ref.read(_completingProvider.notifier).state = false;
          return r;
        });

final selectQueueIndexProvider =
    Provider<Future<TrackLoadResult> Function(int)>((ref) => (i) async {
          final r = await ref
              .read(playbackOrchestratorProvider)
              .selectQueueIndex(i, registerListeners: false);
          if (r.isLoaded) _startPlaybackListeners(ref);
          ref.read(_completingProvider.notifier).state = false;
          return r;
        });

final removeTrackFromQueueProvider =
    Provider<Future<void> Function(int)>((ref) => (i) async {
          final q = ref.read(currentPlayQueueProvider);
          if (q == null || i < 0 || i >= q.length) return;
          await ref
              .read(playbackOrchestratorProvider)
              .removeTrack(i, registerListeners: false);
          // removeTrack may have loaded a new track (if wasCurrent).
          // Check if the player is now playing to decide if listeners are needed.
          final player = ref.read(audioPlayerProvider);
          if (player.playing) _startPlaybackListeners(ref);
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
