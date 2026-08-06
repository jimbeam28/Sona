// test/features/player/bug_bug19_repro_test.dart
// BUG-19: saveProgress fire-and-forget 无错误处理 — automated repro &
// regression suite (spec §5.4 门禁测试).
//
// PlaybackOrchestrator.saveProgress() fires progressSaver.upsertProgress()
// fire-and-forget.  This suite verifies:
//   * a failing save (DB lock / disk full / dispose window) never surfaces
//     as an unhandled async error (BUG-19-S1),
//   * the error is recorded via debugPrint — spec §3.1 S1 requires
//     「catchError 捕获错误并记日志」; silent swallowing is NOT acceptable
//     (复核判据同 CON1 复核修正 d0f43c4「可接受须有日志」),
//   * playback is never blocked by a save failure (S1 否定断言),
//   * the 7 saveProgress call sites are unaffected and the normal-path
//     upsert arguments stay unchanged (BUG-19-INV1).
//
// BUG-19-S1-T01: upsert 失败 → saveProgress 正常返回，无 unhandled async
//                error，错误被记入日志（否定断言：不静默）
// BUG-19-S1-T02: upsert 失败 → 后续切歌仍正常加载（播放不受影响）
// BUG-19-S1-T03: dispose 窗口 — in-flight 保存在 dispose() 之后失败 →
//                无 unhandled async error，错误被记入日志
// BUG-19-INV1-T01: 直接调用方（skipToNext / skipToPrevious /
//                  selectQueueIndex / removeTrack）正常路径仍触发 upsert
// BUG-19-INV1-T02: track completion 监听器仍触发 save
// BUG-19-INV1-T03: auto-save Timer.periodic(10s) 仍触发 save
// BUG-19-INV1-T04: playing→paused 转换仍触发 save
//
// BUG-27-S2 迁移说明（2026-08-05）：INV1-T02/T03/T04 原先直接驱动
// orchestrator 内部 listener（loadAndPlay 默认 registerListeners:true）。
// BUG-27-S2 删除该死代码后（生产线所有调用均传 false，listener 实际由
// provider 层平行实现承载），三组用例等价迁移到 provider 层平行实现：
//   T02 → startProcessingListenerProvider（completed → save + 进曲）
//   T03 → reconnectPlaybackListenersProvider 启动的 auto-save Timer
//   T04 → reconnectPlaybackListenersProvider 启动的 pause-save 订阅
// 断言语义保持不变：保存被触发、路径归属正确、周期/dispose 行为一致。
// orchestrator 层的 upsert 参数断言仍由 INV1-T01 组覆盖。

import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:nas_audio_player/core/contracts/audio_player_contract.dart';
import 'package:mockito/mockito.dart';
import 'package:nas_audio_player/features/player/domain/playback_orchestrator.dart';
import 'package:nas_audio_player/features/player/domain/request_gate.dart';
import 'package:nas_audio_player/shared/di/providers.dart';
import 'package:nas_audio_player/shared/models/connection_config.dart';
import 'package:nas_audio_player/shared/models/nas_file.dart';
import 'package:nas_audio_player/shared/models/play_queue.dart';

import '../../helpers/mock_audio_player.dart';

// ── Recorded upsert call ─────────────────────────────────────────────────────

typedef SaveCall = ({
  int connectionId,
  String filePath,
  int positionMs,
  int? durationMs
});

// ── Hand-written fakes (no build_runner needed) ─────────────────────────────

/// [ProgressSaver] that records every call and can be rigged to fail:
///   * [errorToThrow] — thrown after the optional [gate] completes,
///   * [gate]         — external completer that suspends the save so the
///                      failure can be scheduled AFTER dispose() (S1-T03).
class _RecordingProgressSaver implements ProgressSaver {
  final List<SaveCall> calls = [];
  Object? errorToThrow;
  Completer<void>? gate;

  @override
  Future<void> upsertProgress({
    required int connectionId,
    required String filePath,
    required int positionMs,
    int? durationMs,
  }) async {
    calls.add((
      connectionId: connectionId,
      filePath: filePath,
      positionMs: positionMs,
      durationMs: durationMs,
    ));
    final g = gate;
    if (g != null) await g.future;
    final e = errorToThrow;
    if (e != null) throw e;
  }
}

class _FakeConnectionProvider implements ActiveConnectionProvider {
  ConnectionConfig? connection;

  @override
  ConnectionConfig? get currentConnection => connection;

  @override
  Future<ConnectionConfig?> getActiveConnection() async => connection;
}

class _FakePasswordReader implements PasswordReader {
  @override
  Future<String?> readPassword(int connectionId) async => 'secret';
}

class _FakeSpeedProvider implements DefaultSpeedProvider {
  @override
  double getDefaultSpeed() => 1.0;
}

class _FakeQueueConnIdProvider implements QueueConnectionIdProvider {
  @override
  int? getLastQueueConnectionId() => null;
}

/// Minimal fake [AudioPlayer] recording the interactions the orchestrator
/// performs.
///
/// Hand-written (no Mockito) to sidestep the `any`-matcher vs non-nullable
/// parameter conflict — same rationale as aud_02's `_LenientMockPlayer`.
/// Unimplemented members throw via [Fake], so any unexpected player access
/// fails the test loudly.
class _FakePlayer extends Fake implements AudioPlayer, IAudioPlayer {
  int setAudioSourceCalls = 0;
  bool playingStub = true;
  Duration positionStub = const Duration(seconds: 30);
  Duration? durationStub = const Duration(seconds: 180);
  StreamController<ProcessingState>? processingController;
  StreamController<PlayerState>? playerStateController;

  @override
  Stream<ProcessingState> get processingStateStream =>
      processingController?.stream ?? const Stream.empty();

  @override
  Stream<PlayerState> get playerStateStream =>
      playerStateController?.stream ?? const Stream.empty();

  @override
  bool get playing => playingStub;

  @override
  Duration get position => positionStub;

  @override
  Duration? get duration => durationStub;

  @override
  Future<Duration?> setAudioSource(AudioSource source,
      {bool preload = true,
      int? initialIndex,
      Duration? initialPosition}) async {
    setAudioSourceCalls++;
    return Duration.zero;
  }

  @override
  Future<void> play() async {}

  @override
  Future<void> pause() async {}

  @override
  Future<void> stop() async {}

  @override
  Future<void> seek(Duration? position, {int? index}) async {}

  @override
  Future<void> setSpeed(double speed) async {}
}

// ── Test environment ─────────────────────────────────────────────────────────

void main() {
  NasFile makeFile(String path) => NasFile(
        name: path.split('/').last,
        path: path,
        isDirectory: false,
      );

  final connection = ConnectionConfig(
    id: 1,
    name: 'test',
    url: 'http://localhost:8080',
    username: 'user',
    createdAt: DateTime(2024),
    updatedAt: DateTime(2024),
  );

  PlayQueue makeQueue(List<String> paths, {int currentIndex = 0}) => PlayQueue(
        files: paths.map(makeFile).toList(),
        currentIndex: currentIndex,
      );

  /// Builds a fully wired [PlaybackOrchestrator] with fake dependencies.
  ///
  /// [saveError] rigs the progress saver so every upsert completes with an
  /// error — the BUG-19 failure injection.
  ({
    PlaybackOrchestrator orchestrator,
    _FakePlayer player,
    _RecordingProgressSaver saver,
    StreamController<ProcessingState> processingController,
    StreamController<PlayerState> playerStateController,
  }) createEnv({Object? saveError}) {
    final saver = _RecordingProgressSaver()..errorToThrow = saveError;
    final connectionProvider = _FakeConnectionProvider()
      ..connection = connection;

    // Broadcast controllers so listeners can re-subscribe across loads.
    final processingController = StreamController<ProcessingState>.broadcast();
    final playerStateController = StreamController<PlayerState>.broadcast();

    final player = _FakePlayer()
      ..processingController = processingController
      ..playerStateController = playerStateController;

    final orchestrator = PlaybackOrchestrator(
      player: player,
      connectionProvider: connectionProvider,
      passwordReader: _FakePasswordReader(),
      progressSaver: saver,
      defaultSpeedProvider: _FakeSpeedProvider(),
      queueConnectionIdProvider: _FakeQueueConnIdProvider(),
    );

    return (
      orchestrator: orchestrator,
      player: player,
      saver: saver,
      processingController: processingController,
      playerStateController: playerStateController,
    );
  }

  /// Captures everything written through [debugPrint] during [body].
  ///
  /// Restores the original printer in `finally` (flutter_test verifies
  /// foundation debug variables between tests).
  Future<List<String>> captureLogs(Future<void> Function() body) async {
    final logs = <String>[];
    final originalDebugPrint = debugPrint;
    debugPrint = (message, {wrapWidth}) => logs.add(message ?? '');
    try {
      await body();
    } finally {
      debugPrint = originalDebugPrint;
    }
    return logs;
  }

  // ═════════════════════════════════════════════════════════════════════════
  // BUG-19-S1: saveProgress 异步错误不泄漏
  // ═════════════════════════════════════════════════════════════════════════

  group('BUG-19-S1-T01: failing upsert never becomes an unhandled error', () {
    test('saveProgress returns normally, error is logged, nothing leaks',
        () async {
      final env = createEnv(saveError: StateError('DB busy (SQLITE_BUSY)'));
      addTearDown(env.orchestrator.dispose);
      addTearDown(env.processingController.close);
      addTearDown(env.playerStateController.close);
      env.orchestrator.queue = makeQueue(['/music/song1.mp3']);

      final logs = await captureLogs(() async {
        // saveProgress must stay synchronous and void — callers (7 sites)
        // never await it (否定断言：不阻塞调用方).
        expect(() => env.orchestrator.saveProgress(), returnsNormally);
        // Let the failing future settle.  Without catchError the error would
        // reach the test zone as an unhandled async error and fail this test
        // (pre-fix repro behaviour).
        await pumpEventQueue(times: 50);
      });

      expect(env.saver.calls, hasLength(1), reason: '保存调用本身必须发出');
      expect(
        logs.where((l) => l.contains('saveProgress failed')),
        isNotEmpty,
        reason: 'spec §3.1 S1：catchError 捕获错误并记日志 — '
            '不得静默吞掉（复核判据：可接受须有日志）',
      );
    });
  });

  group('BUG-19-S1-T02: save failure does not block playback', () {
    test('skipToNext still loads the next track when the save fails', () async {
      final env = createEnv(saveError: StateError('disk full'));
      addTearDown(env.orchestrator.dispose);
      addTearDown(env.processingController.close);
      addTearDown(env.playerStateController.close);
      env.orchestrator.queue =
          makeQueue(['/music/song1.mp3', '/music/song2.mp3']);

      final result = await env.orchestrator.skipToNext();

      expect(result.isLoaded, isTrue, reason: '保存失败不得阻塞切歌加载');
      expect(env.orchestrator.queue!.currentIndex, equals(1));
      expect(env.orchestrator.queue!.current.path, '/music/song2.mp3');
      expect(env.player.setAudioSourceCalls, equals(1));

      // Let the failed save settle — still no unhandled error.
      await pumpEventQueue(times: 50);
      expect(env.saver.calls, hasLength(1));
    });
  });

  group('BUG-19-S1-T03: dispose window — in-flight save fails after dispose',
      () {
    test('no unhandled error, error logged, no disposed resource touched',
        () async {
      final gate = Completer<void>();
      final env = createEnv();
      env.saver.gate = gate;
      addTearDown(env.orchestrator.dispose);
      addTearDown(env.processingController.close);
      addTearDown(env.playerStateController.close);
      env.orchestrator.queue = makeQueue(['/music/song1.mp3']);

      // Fire the save; it suspends on the gate (simulating a slow DB write).
      env.orchestrator.saveProgress();
      expect(env.saver.calls, hasLength(1), reason: '保存调用已发出并挂在 gate 上');

      // User exits the app: listeners and timers are disposed while the save
      // is still in flight (U2：快速退出恰好触发 auto-save).
      env.orchestrator.dispose();

      final logs = await captureLogs(() async {
        gate.completeError(StateError('database disposed'));
        await pumpEventQueue(times: 50);
      });

      expect(
        logs.where((l) => l.contains('saveProgress failed')),
        isNotEmpty,
        reason: 'dispose 窗口内的保存失败必须有日志，不得静默丢失',
      );
      // If catchError were missing, the gate error would have failed this
      // test as an unhandled async error — reaching here proves containment.
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  // BUG-19-INV1: 7 处调用方不受影响（正常路径行为不变）
  // ═════════════════════════════════════════════════════════════════════════

  group('BUG-19-INV1-T01: direct call sites still trigger upsert', () {
    test('skipToNext saves the outgoing track with correct arguments',
        () async {
      final env = createEnv();
      addTearDown(env.orchestrator.dispose);
      addTearDown(env.processingController.close);
      addTearDown(env.playerStateController.close);
      env.orchestrator.queue =
          makeQueue(['/music/song1.mp3', '/music/song2.mp3']);

      final result = await env.orchestrator.skipToNext();

      expect(result.isLoaded, isTrue);
      expect(env.saver.calls, hasLength(1));
      expect(
        env.saver.calls.single,
        equals((
          connectionId: 1,
          filePath: '/music/song1.mp3',
          positionMs: 30000,
          durationMs: 180000,
        )),
        reason: '正常路径 upsert 参数必须与修复前一致',
      );
    });

    test('skipToPrevious saves the outgoing track', () async {
      final env = createEnv();
      addTearDown(env.orchestrator.dispose);
      addTearDown(env.processingController.close);
      addTearDown(env.playerStateController.close);
      env.orchestrator.queue =
          makeQueue(['/music/song1.mp3', '/music/song2.mp3'], currentIndex: 1);

      final result = await env.orchestrator.skipToPrevious();

      expect(result.isLoaded, isTrue);
      expect(env.saver.calls, hasLength(1));
      expect(env.saver.calls.single.filePath, '/music/song2.mp3');
      expect(env.orchestrator.queue!.currentIndex, equals(0));
    });

    test('selectQueueIndex saves the outgoing track', () async {
      final env = createEnv();
      addTearDown(env.orchestrator.dispose);
      addTearDown(env.processingController.close);
      addTearDown(env.playerStateController.close);
      env.orchestrator.queue =
          makeQueue(['/music/song1.mp3', '/music/song2.mp3']);

      final result = await env.orchestrator.selectQueueIndex(1);

      expect(result.isLoaded, isTrue);
      expect(env.saver.calls, hasLength(1));
      expect(env.saver.calls.single.filePath, '/music/song1.mp3');
      expect(env.orchestrator.queue!.currentIndex, equals(1));
    });

    test('removeTrack(current) still triggers a save', () async {
      final env = createEnv();
      addTearDown(env.orchestrator.dispose);
      addTearDown(env.processingController.close);
      addTearDown(env.playerStateController.close);
      env.orchestrator.queue =
          makeQueue(['/music/song1.mp3', '/music/song2.mp3']);

      await env.orchestrator.removeTrack(0);

      expect(env.saver.calls, hasLength(1), reason: '删当前曲仍需触发保存');
      expect(env.orchestrator.queue!.current.path, '/music/song2.mp3');
      expect(env.player.setAudioSourceCalls, equals(1));
    });
  });

  group(
      'BUG-19-INV1-T02: track completion listener still saves'
      '（BUG-27-S2 迁移：provider 层平行实现）', () {
    test('completed state triggers saveProgress then advances', () async {
      final processingController =
          StreamController<ProcessingState>.broadcast();
      addTearDown(processingController.close);
      final player = MockAudioPlayer();
      when(player.processingStateStream)
          .thenAnswer((_) => processingController.stream);
      when(player.position).thenReturn(const Duration(seconds: 30));
      when(player.duration).thenReturn(const Duration(minutes: 3));

      final savePaths = <String>[];
      final loads = <String>[];
      late final ProviderContainer container;
      container = ProviderContainer(overrides: [
        audioPlayerProvider.overrideWithValue(player),
        // Timer feature: no active afterCurrent timer.
        onTrackCompletedProvider.overrideWithValue(() => false),
        // Record the queue's current path at each save (save fires BEFORE
        // the queue advances — same attribution the orchestrator listener
        // guaranteed).
        saveProgressProvider.overrideWithValue(() {
          final q = container.read(currentPlayQueueProvider);
          savePaths.add(q?.current.path ?? 'null-queue');
        }),
        loadAndPlayProvider.overrideWithValue(() async {
          loads.add('loadAndPlay');
          return const TrackLoadResult.loaded();
        }),
      ]);
      addTearDown(container.dispose);

      container.read(currentPlayQueueProvider.notifier).state =
          makeQueue(['/music/song1.mp3', '/music/song2.mp3']);
      container.read(playModeProvider.notifier).state = PlayMode.sequential;

      container.read(startProcessingListenerProvider)();
      processingController.add(ProcessingState.completed);
      await pumpEventQueue(times: 50);

      expect(savePaths, hasLength(1), reason: '曲目播完必须触发保存');
      expect(savePaths.single, '/music/song1.mp3',
          reason: '保存必须记在播完曲目名下（进曲前的队列状态）');
      expect(container.read(currentPlayQueueProvider)!.current.path,
          '/music/song2.mp3',
          reason: '完成后必须进曲');
      expect(loads, hasLength(1), reason: '进曲必须触发 loadAndPlay');
    });
  });

  group(
      'BUG-19-INV1-T03: auto-save timer still saves every 10s'
      '（BUG-27-S2 迁移：provider 层平行实现）', () {
    test('Timer.periodic(10s) keeps firing after the fix', () {
      FakeAsync().run((async) {
        final player = MockAudioPlayer();
        when(player.playing).thenReturn(true);

        final savePaths = <String>[];
        late final ProviderContainer container;
        container = ProviderContainer(overrides: [
          audioPlayerProvider.overrideWithValue(player),
          saveProgressProvider.overrideWithValue(() {
            final q = container.read(currentPlayQueueProvider);
            savePaths.add(q?.current.path ?? 'null-queue');
          }),
        ]);
        container.read(currentPlayQueueProvider.notifier).state =
            makeQueue(['/music/song1.mp3', '/music/song2.mp3']);

        // reconnect 入口同时启动 processing listener / autoSave / pauseSave
        // （生产路径：加载成功后 _startPlaybackListeners 调用同一组件）。
        container.read(reconnectPlaybackListenersProvider)();
        async.flushMicrotasks();
        expect(savePaths, isEmpty, reason: '启动本身不触发保存');

        async.elapse(const Duration(seconds: 10));
        expect(savePaths, hasLength(1), reason: '10s 自动保存必须触发');
        expect(savePaths.single, '/music/song1.mp3');

        async.elapse(const Duration(seconds: 10));
        expect(savePaths, hasLength(2), reason: '周期保存持续生效');

        container.dispose();
        async.elapse(const Duration(seconds: 30));
        expect(savePaths, hasLength(2), reason: 'dispose 后定时器必须停止');
      });
    });
  });

  group(
      'BUG-19-INV1-T04: pause transition still saves'
      '（BUG-27-S2 迁移：provider 层平行实现）', () {
    test('playing → paused triggers saveProgress', () {
      FakeAsync().run((async) {
        final playerStateController = StreamController<PlayerState>.broadcast();
        final player = MockAudioPlayer();
        when(player.playing).thenReturn(true);
        when(player.playerStateStream)
            .thenAnswer((_) => playerStateController.stream);

        final savePaths = <String>[];
        late final ProviderContainer container;
        container = ProviderContainer(overrides: [
          audioPlayerProvider.overrideWithValue(player),
          saveProgressProvider.overrideWithValue(() {
            final q = container.read(currentPlayQueueProvider);
            savePaths.add(q?.current.path ?? 'null-queue');
          }),
        ]);
        container.read(currentPlayQueueProvider.notifier).state =
            makeQueue(['/music/song1.mp3']);

        container.read(reconnectPlaybackListenersProvider)();
        async.flushMicrotasks();

        // Still playing → no save; then pause → save.
        playerStateController.add(PlayerState(true, ProcessingState.ready));
        async.flushMicrotasks();
        expect(savePaths, isEmpty);

        playerStateController.add(PlayerState(false, ProcessingState.ready));
        async.flushMicrotasks();
        expect(savePaths, hasLength(1), reason: '暂停转换必须触发保存');
        expect(savePaths.single, '/music/song1.mp3');

        container.dispose();
        // 否定断言：dispose 后订阅已 cancel，暂停事件不再触发保存。
        playerStateController.add(PlayerState(true, ProcessingState.ready));
        playerStateController.add(PlayerState(false, ProcessingState.ready));
        async.flushMicrotasks();
        expect(savePaths, hasLength(1), reason: 'dispose 后不得继续保存');
        playerStateController.close();
      });
    });
  });
}
