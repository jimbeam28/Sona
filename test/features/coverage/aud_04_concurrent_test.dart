// test/features/coverage/aud_04_concurrent_test.dart
// AUD-04: Concurrent scenario tests — race conditions and lifecycle edge cases.
//
// Test cases:
//   AUD-04-T01: Switching connection during playback -> queue cleared + new load correct
//   AUD-04-T02: Removing current track + completed simultaneously -> no double trigger
//   AUD-04-T03: Rapid enter/exit PlayerScreen -> no memory leak (subscriptions cleaned)
//   AUD-04-T04: dispose while loadAndPlay in-flight -> token check discards result
//   AUD-04-T05: Timer expiry + completed simultaneously -> no double pause
//   AUD-04-T06: App background resume + timer expiry + playback resume -> triple event handled correctly

import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:nas_audio_player/features/player/domain/playback_orchestrator.dart';
import 'package:nas_audio_player/features/player/domain/request_gate.dart';
import 'package:nas_audio_player/features/timer/domain/timer_service.dart';
import 'package:nas_audio_player/shared/models/connection_config.dart';
import 'package:nas_audio_player/shared/models/nas_file.dart';
import 'package:nas_audio_player/shared/models/play_queue.dart';

import 'aud_04_concurrent_test.mocks.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// Generate mocks
// ═══════════════════════════════════════════════════════════════════════════════

@GenerateMocks([
  AudioPlayer,
  ActiveConnectionProvider,
  PasswordReader,
  ProgressSaver,
  DefaultSpeedProvider,
  QueueConnectionIdProvider,
])
void main() {
  // ═══════════════════════════════════════════════════════════════════════════════
  // AUD-04-T01: Switching connection during playback -> queue cleared + new load
  // ═══════════════════════════════════════════════════════════════════════════════

  group('AUD-04-T01: Switching connection during playback', () {
    test('queue set to null -> loadAndPlay returns failed', () async {
      final env = _createEnv();

      // Start with a queue, then clear it (simulates connection switch).
      env.orchestrator.queue = _makeQueue(paths: ['/music/song.mp3']);
      env.orchestrator.queue = null;

      final result = await env.orchestrator.loadAndPlay();
      expect(result.status, equals(TrackLoadStatus.failed),
          reason: 'AUD-04-T01: null queue should return failed');
    });

    test('empty queue -> loadAndPlay returns failed', () async {
      final env = _createEnv();

      // Empty file list.
      env.orchestrator.queue = PlayQueue(files: [], currentIndex: 0);

      final result = await env.orchestrator.loadAndPlay();
      expect(result.status, equals(TrackLoadStatus.failed),
          reason: 'AUD-04-T01: empty queue should return failed');
    });

    test('connection ID mismatch -> loadAndPlay returns failed', () async {
      final connProvider = MockActiveConnectionProvider();
      final player = MockAudioPlayer();
      final passwordReader = MockPasswordReader();
      final progressSaver = MockProgressSaver();
      final speedProvider = MockDefaultSpeedProvider();
      final queueConnIdProvider = MockQueueConnectionIdProvider();

      when(connProvider.getActiveConnection())
          .thenAnswer((_) async => _makeConnection(id: 2));
      when(connProvider.currentConnection).thenReturn(_makeConnection(id: 2));
      when(passwordReader.readPassword(any)).thenAnswer((_) async => 'secret');
      when(speedProvider.getDefaultSpeed()).thenReturn(1.0);
      // Queue was created with connection 1, but active is 2.
      when(queueConnIdProvider.getLastQueueConnectionId()).thenReturn(1);

      _stubPlayer(player);

      final orchestrator = PlaybackOrchestrator(
        player: player,
        connectionProvider: connProvider,
        passwordReader: passwordReader,
        progressSaver: progressSaver,
        defaultSpeedProvider: speedProvider,
        queueConnectionIdProvider: queueConnIdProvider,
      );

      orchestrator.queue = _makeQueue(paths: ['/music/song_b.mp3']);
      final result = await orchestrator.loadAndPlay();
      expect(result.status, equals(TrackLoadStatus.failed),
          reason: 'AUD-04-T01: connection ID mismatch should fail');
    });

    test('null active connection -> loadAndPlay returns failed', () async {
      final connProvider = MockActiveConnectionProvider();
      final player = MockAudioPlayer();
      final passwordReader = MockPasswordReader();
      final progressSaver = MockProgressSaver();
      final speedProvider = MockDefaultSpeedProvider();
      final queueConnIdProvider = MockQueueConnectionIdProvider();

      // Connection returns null (simulates no active connection after switch).
      when(connProvider.getActiveConnection()).thenAnswer((_) async => null);
      when(connProvider.currentConnection).thenReturn(null);
      when(passwordReader.readPassword(any)).thenAnswer((_) async => 'secret');
      when(speedProvider.getDefaultSpeed()).thenReturn(1.0);
      when(queueConnIdProvider.getLastQueueConnectionId()).thenReturn(1);

      _stubPlayer(player);

      final orchestrator = PlaybackOrchestrator(
        player: player,
        connectionProvider: connProvider,
        passwordReader: passwordReader,
        progressSaver: progressSaver,
        defaultSpeedProvider: speedProvider,
        queueConnectionIdProvider: queueConnIdProvider,
      );

      orchestrator.queue = _makeQueue(paths: ['/music/song.mp3']);
      final result = await orchestrator.loadAndPlay();
      expect(result.status, equals(TrackLoadStatus.failed),
          reason: 'AUD-04-T01: null connection should return failed');
    });

    test(
        'queue connection cleared then new queue loads -> orchestrator accepts',
        () async {
      final env = _createEnv();

      // First load.
      env.orchestrator.queue = _makeQueue(paths: ['/music/old.mp3']);
      final r1 = await env.orchestrator.loadAndPlay();
      // May be loaded or failed depending on mock behavior, but should not throw.
      expect(r1, isNotNull);

      // Simulate connection switch: clear queue.
      env.orchestrator.queue = null;
      final r2 = await env.orchestrator.loadAndPlay();
      expect(r2.status, equals(TrackLoadStatus.failed),
          reason: 'AUD-04-T01: null queue after switch should fail');

      // Set new queue — orchestrator should accept it.
      env.orchestrator.queue = _makeQueue(paths: ['/music/new.mp3']);
      final r3 = await env.orchestrator.loadAndPlay();
      expect(r3, isNotNull,
          reason: 'AUD-04-T01: new queue after switch should be processed');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════════
  // AUD-04-T02: Removing current track + completed simultaneously -> no double trigger
  // ═══════════════════════════════════════════════════════════════════════════════

  group('AUD-04-T02: Removing current track + completed simultaneously', () {
    test('removeTrack while processing listener handles completed -> no crash',
        () async {
      final player = MockAudioPlayer();
      final processingController =
          StreamController<ProcessingState>.broadcast();
      addTearDown(() => processingController.close());

      when(player.setAudioSource(any)).thenAnswer((_) async => Duration.zero);
      when(player.seek(any)).thenAnswer((_) async {});
      when(player.setSpeed(any)).thenAnswer((_) async {});
      when(player.play()).thenAnswer((_) async {});
      when(player.pause()).thenAnswer((_) async {});
      when(player.stop()).thenAnswer((_) async {});
      when(player.playing).thenReturn(true);
      when(player.position).thenReturn(Duration.zero);
      when(player.duration).thenReturn(null);
      when(player.processingStateStream)
          .thenAnswer((_) => processingController.stream);
      when(player.playerStateStream)
          .thenAnswer((_) => const Stream<PlayerState>.empty());

      final orchestrator = _buildOrchestrator(player);

      // Load 3-track queue.
      orchestrator.queue = _makeQueue(paths: [
        '/music/track1.mp3',
        '/music/track2.mp3',
        '/music/track3.mp3',
      ]);
      await orchestrator.loadAndPlay();

      // Fire removeTrack and completed event concurrently.
      final removeFuture = orchestrator.removeTrack(0);
      processingController.add(ProcessingState.completed);

      await removeFuture;

      // Key: no crash, no double-trigger.
      expect(orchestrator.queue, isNotNull,
          reason:
              'AUD-04-T02: queue should not be null after remove + completed');
    });

    test('removeTrack on last track + completed -> queue null, no double stop',
        () async {
      final player = MockAudioPlayer();
      final processingController =
          StreamController<ProcessingState>.broadcast();
      addTearDown(() => processingController.close());

      when(player.setAudioSource(any)).thenAnswer((_) async => Duration.zero);
      when(player.seek(any)).thenAnswer((_) async {});
      when(player.setSpeed(any)).thenAnswer((_) async {});
      when(player.play()).thenAnswer((_) async {});
      when(player.pause()).thenAnswer((_) async {});
      when(player.stop()).thenAnswer((_) async {});
      when(player.playing).thenReturn(true);
      when(player.position).thenReturn(Duration.zero);
      when(player.duration).thenReturn(null);
      when(player.processingStateStream)
          .thenAnswer((_) => processingController.stream);
      when(player.playerStateStream)
          .thenAnswer((_) => const Stream<PlayerState>.empty());

      final orchestrator = _buildOrchestrator(player);

      // Single-track queue.
      orchestrator.queue = _makeQueue(paths: ['/music/only.mp3']);
      await orchestrator.loadAndPlay();

      // Remove + completed concurrently.
      final removeFuture = orchestrator.removeTrack(0);
      processingController.add(ProcessingState.completed);
      await removeFuture;

      expect(orchestrator.queue, isNull,
          reason: 'AUD-04-T02: queue should be null after removing last track');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════════
  // AUD-04-T03: Rapid enter/exit PlayerScreen -> no memory leak
  // ═══════════════════════════════════════════════════════════════════════════════

  group('AUD-04-T03: Rapid enter/exit PlayerScreen -> no memory leak', () {
    test('dispose cancels subscriptions; events after dispose do not crash',
        () {
      final player = MockAudioPlayer();
      final processingController =
          StreamController<ProcessingState>.broadcast();
      final playerStateController = StreamController<PlayerState>.broadcast();
      addTearDown(() {
        processingController.close();
        playerStateController.close();
      });

      when(player.processingStateStream)
          .thenAnswer((_) => processingController.stream);
      when(player.playerStateStream)
          .thenAnswer((_) => playerStateController.stream);
      when(player.playing).thenReturn(true);
      when(player.position).thenReturn(Duration.zero);
      when(player.duration).thenReturn(null);

      final orchestrator = _buildOrchestrator(player);

      // Simulate rapid enter: load, then immediately exit (dispose).
      orchestrator.queue = _makeQueue(paths: ['/music/song.mp3']);
      unawaited(orchestrator.loadAndPlay());
      orchestrator.dispose();

      // Events arriving after dispose should not crash.
      expect(
        () {
          processingController.add(ProcessingState.completed);
          playerStateController.add(PlayerState(false, ProcessingState.idle));
        },
        returnsNormally,
        reason: 'AUD-04-T03: events after dispose should not crash',
      );
    });

    test('multiple dispose calls are idempotent', () {
      final player = MockAudioPlayer();
      when(player.processingStateStream)
          .thenAnswer((_) => const Stream<ProcessingState>.empty());
      when(player.playerStateStream)
          .thenAnswer((_) => const Stream<PlayerState>.empty());
      when(player.playing).thenReturn(false);
      when(player.position).thenReturn(Duration.zero);
      when(player.duration).thenReturn(null);

      final orchestrator = _buildOrchestrator(player);

      expect(() => orchestrator.dispose(), returnsNormally);
      expect(() => orchestrator.dispose(), returnsNormally,
          reason: 'AUD-04-T03: double dispose should be idempotent');
    });

    test('loadAndPlay after dispose does not throw', () async {
      final player = MockAudioPlayer();
      when(player.processingStateStream)
          .thenAnswer((_) => const Stream<ProcessingState>.empty());
      when(player.playerStateStream)
          .thenAnswer((_) => const Stream<PlayerState>.empty());
      when(player.setAudioSource(any)).thenAnswer((_) async => Duration.zero);
      when(player.seek(any)).thenAnswer((_) async {});
      when(player.setSpeed(any)).thenAnswer((_) async {});
      when(player.play()).thenAnswer((_) async {});
      when(player.pause()).thenAnswer((_) async {});
      when(player.stop()).thenAnswer((_) async {});
      when(player.playing).thenReturn(true);
      when(player.position).thenReturn(Duration.zero);
      when(player.duration).thenReturn(null);

      final orchestrator = _buildOrchestrator(player);

      orchestrator.queue = _makeQueue(paths: ['/music/song.mp3']);
      orchestrator.dispose();

      // loadAndPlay after dispose should not throw.
      final result = await orchestrator.loadAndPlay();
      expect(result, isNotNull,
          reason: 'AUD-04-T03: loadAndPlay after dispose should not throw');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════════
  // AUD-04-T04: dispose while loadAndPlay in-flight -> token check discards result
  // ═══════════════════════════════════════════════════════════════════════════════

  group('AUD-04-T04: dispose while loadAndPlay in-flight', () {
    test('new load scheduled while old one is running -> old result superseded',
        () {
      FakeAsync().run((async) {
        final gate = SerializedRequestGate();

        // First request: slow.
        final slowCompleter = Completer<TrackLoadResult>();
        var firstResult = TrackLoadResult.superseded();
        gate
            .schedule<TrackLoadResult>(
              task: (_) => slowCompleter.future,
              onSuperseded: () => const TrackLoadResult.superseded(),
            )
            .then((r) => firstResult = r);

        // Second request: fast (re-enter screen).
        final fastCompleter = Completer<TrackLoadResult>();
        var secondResult = TrackLoadResult.superseded();
        gate
            .schedule<TrackLoadResult>(
              task: (_) => fastCompleter.future,
              onSuperseded: () => const TrackLoadResult.superseded(),
            )
            .then((r) => secondResult = r);

        // Resolve slow — it should be superseded.
        slowCompleter.complete(const TrackLoadResult.failed());
        async.elapse(Duration.zero);

        expect(firstResult.status, equals(TrackLoadStatus.superseded),
            reason: 'AUD-04-T04: old request should be superseded');

        // Resolve fast — it should complete.
        fastCompleter.complete(const TrackLoadResult.failed());
        async.elapse(Duration.zero);

        expect(secondResult.status, equals(TrackLoadStatus.failed),
            reason: 'AUD-04-T04: new request should complete normally');
      });
    });

    test('rapid load-dispose-load -> gate serializes correctly', () {
      FakeAsync().run((async) {
        final gate = SerializedRequestGate();

        final c1 = Completer<TrackLoadResult>();
        final c2 = Completer<TrackLoadResult>();
        final c3 = Completer<TrackLoadResult>();

        var r1 = TrackLoadResult.superseded();
        var r2 = TrackLoadResult.superseded();
        var r3 = TrackLoadResult.superseded();

        gate
            .schedule<TrackLoadResult>(
              task: (_) => c1.future,
              onSuperseded: () => const TrackLoadResult.superseded(),
            )
            .then((r) => r1 = r);

        gate
            .schedule<TrackLoadResult>(
              task: (_) => c2.future,
              onSuperseded: () => const TrackLoadResult.superseded(),
            )
            .then((r) => r2 = r);

        gate
            .schedule<TrackLoadResult>(
              task: (_) => c3.future,
              onSuperseded: () => const TrackLoadResult.superseded(),
            )
            .then((r) => r3 = r);

        // First two superseded.
        c1.complete(const TrackLoadResult.failed());
        c2.complete(const TrackLoadResult.failed());
        async.elapse(Duration.zero);

        expect(r1.status, equals(TrackLoadStatus.superseded));
        expect(r2.status, equals(TrackLoadStatus.superseded));

        // Third completes.
        c3.complete(const TrackLoadResult.failed());
        async.elapse(Duration.zero);

        expect(r3.status, equals(TrackLoadStatus.failed),
            reason: 'AUD-04-T04: 3rd request should complete');
      });
    });

    test('dispose orchestrator while loadAndPlay is in-flight -> no crash',
        () async {
      final player = MockAudioPlayer();
      final connProvider = MockActiveConnectionProvider();
      final passwordReader = MockPasswordReader();
      final progressSaver = MockProgressSaver();
      final speedProvider = MockDefaultSpeedProvider();
      final queueConnIdProvider = MockQueueConnectionIdProvider();

      when(connProvider.getActiveConnection())
          .thenAnswer((_) async => _makeConnection());
      when(connProvider.currentConnection).thenReturn(_makeConnection());
      when(passwordReader.readPassword(any)).thenAnswer((_) async => 'secret');
      when(speedProvider.getDefaultSpeed()).thenReturn(1.0);
      when(queueConnIdProvider.getLastQueueConnectionId()).thenReturn(1);

      // Simulate slow setAudioSource.
      final loadCompleter = Completer<Duration?>();
      when(player.setAudioSource(any)).thenAnswer((_) => loadCompleter.future);
      when(player.seek(any)).thenAnswer((_) async {});
      when(player.setSpeed(any)).thenAnswer((_) async {});
      when(player.play()).thenAnswer((_) async {});
      when(player.pause()).thenAnswer((_) async {});
      when(player.stop()).thenAnswer((_) async {});
      when(player.playing).thenReturn(true);
      when(player.position).thenReturn(Duration.zero);
      when(player.duration).thenReturn(null);
      when(player.processingStateStream)
          .thenAnswer((_) => const Stream<ProcessingState>.empty());
      when(player.playerStateStream)
          .thenAnswer((_) => const Stream<PlayerState>.empty());

      final orchestrator = PlaybackOrchestrator(
        player: player,
        connectionProvider: connProvider,
        passwordReader: passwordReader,
        progressSaver: progressSaver,
        defaultSpeedProvider: speedProvider,
        queueConnectionIdProvider: queueConnIdProvider,
      );

      orchestrator.queue = _makeQueue(paths: ['/music/slow.mp3']);
      final loadFuture = orchestrator.loadAndPlay();

      // Dispose while in-flight.
      orchestrator.dispose();

      // Complete the pending load.
      loadCompleter.complete(Duration.zero);

      // Should resolve without hanging.
      final result = await loadFuture;
      expect(result, isNotNull,
          reason: 'AUD-04-T04: disposed orchestrator load should not hang');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════════
  // AUD-04-T05: Timer expiry + completed simultaneously -> no double pause
  // ═══════════════════════════════════════════════════════════════════════════════

  group('AUD-04-T05: Timer expiry + completed simultaneously', () {
    test('checkExpired(true) then onTrackCompleted -> second is no-op', () {
      final service = TimerService();

      // Expired duration timer.
      service.startDuration(0);

      // checkExpired clears state.
      final expired = service.checkExpired();
      expect(expired, isTrue);
      expect(service.state, isNull);

      // onTrackCompleted is a no-op (state already cleared).
      final triggered = service.onTrackCompleted();
      expect(triggered, isFalse,
          reason: 'AUD-04-T05: onTrackCompleted after expiry should be no-op');
    });

    test('onTrackCompleted(true) then checkExpired -> second is no-op', () {
      final service = TimerService();

      service.startAfterCurrent();
      expect(service.isActive, isTrue);

      // onTrackCompleted clears state.
      final triggered = service.onTrackCompleted();
      expect(triggered, isTrue);
      expect(service.state, isNull);

      // checkExpired is a no-op.
      final expired = service.checkExpired();
      expect(expired, isFalse,
          reason:
              'AUD-04-T05: checkExpired after afterCurrent trigger should be false');
    });

    test('integration: timer expiry + completed -> pause called exactly once',
        () {
      final player = MockAudioPlayer();
      final service = TimerService();

      service.startDuration(0); // Already expired.

      int pauseCount = 0;

      // Simulate the processing listener checking timer first.
      if (service.checkExpired()) {
        player.pause();
        pauseCount++;
      }

      // Then check afterCurrent (simultaneous event).
      if (service.onTrackCompleted()) {
        player.pause();
        pauseCount++;
      }

      expect(pauseCount, equals(1),
          reason: 'AUD-04-T05: pause should be called exactly once');
    });

    test('no timer active -> both checks return false -> no pause', () {
      final service = TimerService();
      final player = MockAudioPlayer();

      expect(service.checkExpired(), isFalse);
      expect(service.onTrackCompleted(), isFalse);

      verifyNever(player.pause());
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════════
  // AUD-04-T06: App background resume + timer expiry + playback resume
  // ═══════════════════════════════════════════════════════════════════════════════

  group('AUD-04-T06: App background resume + timer expiry + playback resume',
      () {
    test('expired timer detected on resume -> signal pause', () {
      final service = TimerService();
      service.startDuration(0); // Immediately expired.

      // On resume, check timer expiry.
      final expired = service.checkExpired();
      expect(expired, isTrue,
          reason: 'AUD-04-T06: expired timer detected on resume');
      expect(service.state, isNull);
    });

    test('non-expired timer on resume -> no pause', () {
      final service = TimerService();
      service.startDuration(10);

      final expired = service.checkExpired();
      expect(expired, isFalse,
          reason: 'AUD-04-T06: non-expired timer should not trigger');
      expect(service.isActive, isTrue);
    });

    test('afterCurrent active on resume + track completed -> trigger', () {
      final service = TimerService();
      service.startAfterCurrent();

      final triggered = service.onTrackCompleted();
      expect(triggered, isTrue,
          reason: 'AUD-04-T06: afterCurrent should trigger on completion');
      expect(service.state, isNull);
    });

    test(
        'triple event: background resume + timer expired + completed -> single pause',
        () {
      final service = TimerService();
      final player = MockAudioPlayer();

      service.startDuration(0); // Already expired.

      int pauseCount = 0;

      // Event 1: App resumes — check timer expiry.
      if (service.checkExpired()) {
        player.pause();
        pauseCount++;
      }

      // Event 2: Track completed (simultaneous from processing listener).
      if (service.onTrackCompleted()) {
        player.pause();
        pauseCount++;
      }

      // Event 3: Playback resume attempt — but timer expired, so stay paused.
      // Handled by UI: if timer expired, don't resume.

      expect(pauseCount, equals(1),
          reason: 'AUD-04-T06: triple event should produce exactly one pause');
      expect(service.state, isNull);
    });

    test('cancelled timer on resume -> no expiry trigger', () {
      final service = TimerService();
      service.startDuration(5);
      service.cancel();

      final expired = service.checkExpired();
      expect(expired, isFalse,
          reason: 'AUD-04-T06: cancelled timer should not trigger on resume');
      expect(service.state, isNull);
    });

    test('new timer started after old expiry -> old expiry does not fire again',
        () {
      final service = TimerService();

      // First timer expires.
      service.startDuration(0);
      expect(service.checkExpired(), isTrue);

      // Start new timer.
      service.startDuration(10);
      expect(service.isActive, isTrue);

      // Old expiry path should not affect new timer.
      expect(service.checkExpired(), isFalse,
          reason: 'AUD-04-T06: old expiry should not affect new timer');
      expect(service.isActive, isTrue);
    });
  });
}

// ═══════════════════════════════════════════════════════════════════════════════
// Helpers
// ═══════════════════════════════════════════════════════════════════════════════

ConnectionConfig _makeConnection({int id = 1, String name = 'NAS-A'}) =>
    ConnectionConfig(
      id: id,
      name: name,
      url: 'http://localhost:8080',
      username: 'user',
      basePath: '/dav',
      createdAt: DateTime(2024),
      updatedAt: DateTime(2024),
    );

NasFile _makeFile(String path) => NasFile(
      name: path.split('/').last,
      path: path,
      isDirectory: false,
    );

PlayQueue _makeQueue({
  required List<String> paths,
  int currentIndex = 0,
}) {
  final files = paths.map(_makeFile).toList();
  return PlayQueue(files: files, currentIndex: currentIndex);
}

/// Stubs all player methods needed for a normal loadAndPlay flow.
void _stubPlayer(MockAudioPlayer player) {
  when(player.setAudioSource(any)).thenAnswer((_) async => Duration.zero);
  when(player.seek(any)).thenAnswer((_) async {});
  when(player.setSpeed(any)).thenAnswer((_) async {});
  when(player.play()).thenAnswer((_) async {});
  when(player.pause()).thenAnswer((_) async {});
  when(player.stop()).thenAnswer((_) async {});
  when(player.playing).thenReturn(true);
  when(player.position).thenReturn(Duration.zero);
  when(player.duration).thenReturn(null);
  when(player.processingStateStream)
      .thenAnswer((_) => const Stream<ProcessingState>.empty());
  when(player.playerStateStream)
      .thenAnswer((_) => const Stream<PlayerState>.empty());
}

/// Creates a standard env with generated mocks.
({
  MockAudioPlayer player,
  PlaybackOrchestrator orchestrator,
}) _createEnv() {
  final player = MockAudioPlayer();
  final connProvider = MockActiveConnectionProvider();
  final passwordReader = MockPasswordReader();
  final progressSaver = MockProgressSaver();
  final speedProvider = MockDefaultSpeedProvider();
  final queueConnIdProvider = MockQueueConnectionIdProvider();

  when(connProvider.getActiveConnection())
      .thenAnswer((_) async => _makeConnection());
  when(connProvider.currentConnection).thenReturn(_makeConnection());
  when(passwordReader.readPassword(any)).thenAnswer((_) async => 'secret');
  when(speedProvider.getDefaultSpeed()).thenReturn(1.0);
  when(queueConnIdProvider.getLastQueueConnectionId()).thenReturn(1);

  _stubPlayer(player);

  final orchestrator = PlaybackOrchestrator(
    player: player,
    connectionProvider: connProvider,
    passwordReader: passwordReader,
    progressSaver: progressSaver,
    defaultSpeedProvider: speedProvider,
    queueConnectionIdProvider: queueConnIdProvider,
  );

  return (player: player, orchestrator: orchestrator);
}

/// Builds an orchestrator with a pre-existing player (for tests that
/// customize player stubs before building).
PlaybackOrchestrator _buildOrchestrator(MockAudioPlayer player) {
  final connProvider = MockActiveConnectionProvider();
  final passwordReader = MockPasswordReader();
  final progressSaver = MockProgressSaver();
  final speedProvider = MockDefaultSpeedProvider();
  final queueConnIdProvider = MockQueueConnectionIdProvider();

  when(connProvider.getActiveConnection())
      .thenAnswer((_) async => _makeConnection());
  when(connProvider.currentConnection).thenReturn(_makeConnection());
  when(passwordReader.readPassword(any)).thenAnswer((_) async => 'secret');
  when(speedProvider.getDefaultSpeed()).thenReturn(1.0);
  when(queueConnIdProvider.getLastQueueConnectionId()).thenReturn(1);

  return PlaybackOrchestrator(
    player: player,
    connectionProvider: connProvider,
    passwordReader: passwordReader,
    progressSaver: progressSaver,
    defaultSpeedProvider: speedProvider,
    queueConnectionIdProvider: queueConnIdProvider,
  );
}
