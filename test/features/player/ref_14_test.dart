// test/features/player/ref_14_test.dart
// REF-14: PlaybackOrchestrator — core playback orchestration logic tests.
//
// Tests:
//   REF-14-T01: loadAndPlay normal flow → loaded
//   REF-14-T02: loadAndPlay no connection → failed
//   REF-14-T03: loadAndPlay no password → failed
//   REF-14-T04: skipToNext → save progress → update queue → loadAndPlay
//   REF-14-T05: skipToPrevious → save progress → update queue → loadAndPlay
//   REF-14-T06: removeTrack empty queue → stop
//   REF-14-T07: removeTrack current track → next track
//   REF-14-T08: removeTrack non-current track → update queue only

import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:nas_audio_player/features/player/domain/playback_orchestrator.dart';
import 'package:nas_audio_player/features/player/domain/play_mode.dart';
import 'package:nas_audio_player/features/player/domain/request_gate.dart';
import 'package:nas_audio_player/shared/models/connection_config.dart';
import 'package:nas_audio_player/shared/models/nas_file.dart';
import 'package:nas_audio_player/shared/models/play_queue.dart';

import 'ref_14_test.mocks.dart';

@GenerateMocks([
  AudioPlayer,
  ActiveConnectionProvider,
  PasswordReader,
  ProgressSaver,
  DefaultSpeedProvider,
  QueueConnectionIdProvider,
])
void main() {
  // ── Helpers ──────────────────────────────────────────────────────────────

  NasFile makeFile(String path) => NasFile(
        name: path.split('/').last,
        path: path,
        isDirectory: false,
      );

  ConnectionConfig makeConnection({int? id = 1}) => ConnectionConfig(
        id: id,
        name: 'test',
        url: 'http://localhost:8080',
        username: 'user',
        createdAt: DateTime(2024),
        updatedAt: DateTime(2024),
      );

  PlayQueue makeQueue({
    required List<String> paths,
    int currentIndex = 0,
    PlayMode playMode = PlayMode.sequential,
  }) {
    final files = paths.map(makeFile).toList();
    return PlayQueue(
      files: files,
      currentIndex: currentIndex,
      playMode: playMode,
    );
  }

  /// Creates a fully wired [PlaybackOrchestrator] with mock dependencies.
  ///
  /// [mockPlayer] is configured to support setAudioSource + play flow by
  /// default.  Individual tests can override behavior on the mocks.
  ({
    PlaybackOrchestrator orchestrator,
    MockAudioPlayer player,
    MockActiveConnectionProvider connectionProvider,
    MockPasswordReader passwordReader,
    MockProgressSaver progressSaver,
    MockDefaultSpeedProvider speedProvider,
    MockQueueConnectionIdProvider queueConnIdProvider,
  }) createOrchestrator({
    ConnectionConfig? connection,
    String? password,
    double defaultSpeed = 1.0,
    int? lastQueueConnectionId,
  }) {
    final player = MockAudioPlayer();
    final connectionProvider = MockActiveConnectionProvider();
    final passwordReader = MockPasswordReader();
    final progressSaver = MockProgressSaver();
    final speedProvider = MockDefaultSpeedProvider();
    final queueConnIdProvider = MockQueueConnectionIdProvider();

    // Default stubs.
    when(connectionProvider.getActiveConnection())
        .thenAnswer((_) async => connection);
    when(connectionProvider.currentConnection).thenReturn(connection);
    when(passwordReader.readPassword(any)).thenAnswer((_) async => password);
    when(speedProvider.getDefaultSpeed()).thenReturn(defaultSpeed);
    when(queueConnIdProvider.getLastQueueConnectionId())
        .thenReturn(lastQueueConnectionId);
    when(progressSaver.upsertProgress(
      connectionId: anyNamed('connectionId'),
      filePath: anyNamed('filePath'),
      positionMs: anyNamed('positionMs'),
      durationMs: anyNamed('durationMs'),
    )).thenAnswer((_) async {});

    // Player stubs for loadAndPlay flow.
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

    final orchestrator = PlaybackOrchestrator(
      player: player,
      connectionProvider: connectionProvider,
      passwordReader: passwordReader,
      progressSaver: progressSaver,
      defaultSpeedProvider: speedProvider,
      queueConnectionIdProvider: queueConnIdProvider,
    );

    return (
      orchestrator: orchestrator,
      player: player,
      connectionProvider: connectionProvider,
      passwordReader: passwordReader,
      progressSaver: progressSaver,
      speedProvider: speedProvider,
      queueConnIdProvider: queueConnIdProvider,
    );
  }

  // ── REF-14-T01: loadAndPlay normal flow → loaded ─────────────────────────

  group('REF-14-T01: loadAndPlay normal flow', () {
    test('loads and plays successfully with valid connection and password',
        () async {
      final env = createOrchestrator(
        connection: makeConnection(),
        password: 'secret',
      );
      env.orchestrator.queue = makeQueue(paths: ['/music/song.mp3']);

      final result = await env.orchestrator.loadAndPlay();

      expect(result.isLoaded, isTrue);
      verify(env.player.setAudioSource(any)).called(1);
      verify(env.player.play()).called(1);
    });

    test('seeks to start position when queue has startPositionMs', () async {
      final env = createOrchestrator(
        connection: makeConnection(),
        password: 'secret',
      );
      final queue = makeQueue(paths: ['/music/song.mp3']);
      env.orchestrator.queue = queue.withStartPosition(30000);

      await env.orchestrator.loadAndPlay();

      verify(env.player.seek(const Duration(milliseconds: 30000))).called(1);
    });

    test('applies default speed when not 1.0', () async {
      final env = createOrchestrator(
        connection: makeConnection(),
        password: 'secret',
        defaultSpeed: 1.5,
      );
      env.orchestrator.queue = makeQueue(paths: ['/music/song.mp3']);

      await env.orchestrator.loadAndPlay();

      verify(env.player.setSpeed(1.5)).called(1);
    });

    test('does not apply speed when default is 1.0', () async {
      final env = createOrchestrator(
        connection: makeConnection(),
        password: 'secret',
        defaultSpeed: 1.0,
      );
      env.orchestrator.queue = makeQueue(paths: ['/music/song.mp3']);

      await env.orchestrator.loadAndPlay();

      verifyNever(env.player.setSpeed(any));
    });
  });

  // ── REF-14-T02: loadAndPlay no connection → failed ──────────────────────

  group('REF-14-T02: loadAndPlay no connection', () {
    test('returns failed when no active connection', () async {
      final env = createOrchestrator(connection: null);
      env.orchestrator.queue = makeQueue(paths: ['/music/song.mp3']);

      final result = await env.orchestrator.loadAndPlay();

      expect(result.status, equals(TrackLoadStatus.failed));
    });

    test('returns failed when connection ID mismatches saved ID', () async {
      final env = createOrchestrator(
        connection: makeConnection(id: 2),
        password: 'secret',
        lastQueueConnectionId: 1,
      );
      env.orchestrator.queue = makeQueue(paths: ['/music/song.mp3']);

      final result = await env.orchestrator.loadAndPlay();

      expect(result.status, equals(TrackLoadStatus.failed));
    });

    test('returns failed when queue is null', () async {
      final env = createOrchestrator(
        connection: makeConnection(),
        password: 'secret',
      );
      // Queue is null by default.

      final result = await env.orchestrator.loadAndPlay();

      expect(result.status, equals(TrackLoadStatus.failed));
    });

    test('returns failed when queue is empty', () async {
      final env = createOrchestrator(
        connection: makeConnection(),
        password: 'secret',
      );
      env.orchestrator.queue = PlayQueue(files: [], currentIndex: 0);

      final result = await env.orchestrator.loadAndPlay();

      expect(result.status, equals(TrackLoadStatus.failed));
    });
  });

  // ── REF-14-T03: loadAndPlay no password → failed ────────────────────────

  group('REF-14-T03: loadAndPlay no password', () {
    test('returns failed when password is null', () async {
      final env = createOrchestrator(
        connection: makeConnection(),
        password: null,
      );
      env.orchestrator.queue = makeQueue(paths: ['/music/song.mp3']);

      final result = await env.orchestrator.loadAndPlay();

      expect(result.status, equals(TrackLoadStatus.failed));
    });

    test('returns failed when password is empty', () async {
      final env = createOrchestrator(
        connection: makeConnection(),
        password: '',
      );
      env.orchestrator.queue = makeQueue(paths: ['/music/song.mp3']);

      final result = await env.orchestrator.loadAndPlay();

      expect(result.status, equals(TrackLoadStatus.failed));
    });
  });

  // ── REF-14-T04: skipToNext → save progress → update queue → loadAndPlay ─

  group('REF-14-T04: skipToNext', () {
    test('saves progress, advances queue, and loads next track', () async {
      final env = createOrchestrator(
        connection: makeConnection(),
        password: 'secret',
      );
      env.orchestrator.queue = makeQueue(
        paths: ['/music/song1.mp3', '/music/song2.mp3'],
        currentIndex: 0,
      );
      when(env.player.position).thenReturn(const Duration(seconds: 30));
      when(env.player.duration).thenReturn(const Duration(seconds: 180));

      final result = await env.orchestrator.skipToNext();

      expect(result.isLoaded, isTrue);
      expect(env.orchestrator.queue!.currentIndex, equals(1));
      verify(env.progressSaver.upsertProgress(
        connectionId: 1,
        filePath: '/music/song1.mp3',
        positionMs: 30000,
        durationMs: 180000,
      )).called(1);
    });

    test('returns failed when at end of sequential queue', () async {
      final env = createOrchestrator(
        connection: makeConnection(),
        password: 'secret',
      );
      env.orchestrator.queue = makeQueue(
        paths: ['/music/song1.mp3'],
        currentIndex: 0,
      );

      final result = await env.orchestrator.skipToNext();

      expect(result.status, equals(TrackLoadStatus.failed));
    });

    test('returns failed when queue is null', () async {
      final env = createOrchestrator();

      final result = await env.orchestrator.skipToNext();

      expect(result.status, equals(TrackLoadStatus.failed));
    });

    test('wraps to start in repeatAll mode', () async {
      final env = createOrchestrator(
        connection: makeConnection(),
        password: 'secret',
      );
      env.orchestrator.playMode = PlayMode.repeatAll;
      env.orchestrator.queue = makeQueue(
        paths: ['/music/song1.mp3', '/music/song2.mp3'],
        currentIndex: 1,
        playMode: PlayMode.repeatAll,
      );

      final result = await env.orchestrator.skipToNext();

      expect(result.isLoaded, isTrue);
      expect(env.orchestrator.queue!.currentIndex, equals(0));
    });
  });

  // ── REF-14-T05: skipToPrevious → save progress → update queue → loadAndPlay

  group('REF-14-T05: skipToPrevious', () {
    test('saves progress, goes back, and loads previous track', () async {
      final env = createOrchestrator(
        connection: makeConnection(),
        password: 'secret',
      );
      env.orchestrator.queue = makeQueue(
        paths: ['/music/song1.mp3', '/music/song2.mp3'],
        currentIndex: 1,
      );
      when(env.player.position).thenReturn(const Duration(seconds: 60));
      when(env.player.duration).thenReturn(const Duration(seconds: 200));

      final result = await env.orchestrator.skipToPrevious();

      expect(result.isLoaded, isTrue);
      expect(env.orchestrator.queue!.currentIndex, equals(0));
      verify(env.progressSaver.upsertProgress(
        connectionId: 1,
        filePath: '/music/song2.mp3',
        positionMs: 60000,
        durationMs: 200000,
      )).called(1);
    });

    test('returns failed when at start of sequential queue', () async {
      final env = createOrchestrator(
        connection: makeConnection(),
        password: 'secret',
      );
      env.orchestrator.queue = makeQueue(
        paths: ['/music/song1.mp3'],
        currentIndex: 0,
      );

      final result = await env.orchestrator.skipToPrevious();

      expect(result.status, equals(TrackLoadStatus.failed));
    });

    test('returns failed when queue is null', () async {
      final env = createOrchestrator();

      final result = await env.orchestrator.skipToPrevious();

      expect(result.status, equals(TrackLoadStatus.failed));
    });

    test('wraps to end in repeatAll mode', () async {
      final env = createOrchestrator(
        connection: makeConnection(),
        password: 'secret',
      );
      env.orchestrator.playMode = PlayMode.repeatAll;
      env.orchestrator.queue = makeQueue(
        paths: ['/music/song1.mp3', '/music/song2.mp3'],
        currentIndex: 0,
        playMode: PlayMode.repeatAll,
      );

      final result = await env.orchestrator.skipToPrevious();

      expect(result.isLoaded, isTrue);
      expect(env.orchestrator.queue!.currentIndex, equals(1));
    });
  });

  // ── REF-14-T06: removeTrack empty queue → stop ──────────────────────────

  group('REF-14-T06: removeTrack empty queue', () {
    test('stops playback and clears queue when last track removed', () async {
      final env = createOrchestrator(
        connection: makeConnection(),
        password: 'secret',
      );
      env.orchestrator.queue = makeQueue(
        paths: ['/music/song1.mp3'],
        currentIndex: 0,
      );

      await env.orchestrator.removeTrack(0);

      verify(env.player.stop()).called(1);
      expect(env.orchestrator.queue, isNull);
    });
  });

  // ── REF-14-T07: removeTrack current track → next track ──────────────────

  group('REF-14-T07: removeTrack current track', () {
    test('loads the next track when current track is removed', () async {
      final env = createOrchestrator(
        connection: makeConnection(),
        password: 'secret',
      );
      env.orchestrator.queue = makeQueue(
        paths: ['/music/song1.mp3', '/music/song2.mp3', '/music/song3.mp3'],
        currentIndex: 0,
      );
      when(env.player.position).thenReturn(const Duration(seconds: 10));
      when(env.player.duration).thenReturn(const Duration(seconds: 100));

      await env.orchestrator.removeTrack(0);

      // After removing index 0, current should now point to what was song2.
      expect(env.orchestrator.queue!.length, equals(2));
      expect(env.orchestrator.queue!.current.path, equals('/music/song2.mp3'));
      // loadAndPlay was called (setAudioSource invoked).
      verify(env.player.setAudioSource(any)).called(1);
    });
  });

  // ── REF-14-T08: removeTrack non-current track → only update queue ───────

  group('REF-14-T08: removeTrack non-current track', () {
    test('updates queue but does not reload when non-current track removed',
        () async {
      final env = createOrchestrator(
        connection: makeConnection(),
        password: 'secret',
      );
      env.orchestrator.queue = makeQueue(
        paths: ['/music/song1.mp3', '/music/song2.mp3', '/music/song3.mp3'],
        currentIndex: 0,
      );

      // Remove track at index 2 (not current).
      await env.orchestrator.removeTrack(2);

      expect(env.orchestrator.queue!.length, equals(2));
      expect(env.orchestrator.queue!.currentIndex, equals(0));
      expect(env.orchestrator.queue!.current.path, equals('/music/song1.mp3'));
      // loadAndPlay was NOT called.
      verifyNever(env.player.setAudioSource(any));
    });

    test('adjusts current index when track before current is removed',
        () async {
      final env = createOrchestrator(
        connection: makeConnection(),
        password: 'secret',
      );
      env.orchestrator.queue = makeQueue(
        paths: ['/music/song1.mp3', '/music/song2.mp3', '/music/song3.mp3'],
        currentIndex: 2,
      );

      // Remove track at index 0 (before current at 2).
      await env.orchestrator.removeTrack(0);

      expect(env.orchestrator.queue!.length, equals(2));
      // currentIndex should shift down by 1.
      expect(env.orchestrator.queue!.currentIndex, equals(1));
      expect(env.orchestrator.queue!.current.path, equals('/music/song3.mp3'));
      verifyNever(env.player.setAudioSource(any));
    });
  });

  // ── Extra: selectQueueIndex ─────────────────────────────────────────────

  group('REF-14: selectQueueIndex', () {
    test('selects a valid index and loads the track', () async {
      final env = createOrchestrator(
        connection: makeConnection(),
        password: 'secret',
      );
      env.orchestrator.queue = makeQueue(
        paths: ['/music/song1.mp3', '/music/song2.mp3', '/music/song3.mp3'],
        currentIndex: 0,
      );

      final result = await env.orchestrator.selectQueueIndex(2);

      expect(result.isLoaded, isTrue);
      expect(env.orchestrator.queue!.currentIndex, equals(2));
    });

    test('returns failed for same index', () async {
      final env = createOrchestrator(
        connection: makeConnection(),
        password: 'secret',
      );
      env.orchestrator.queue = makeQueue(
        paths: ['/music/song1.mp3', '/music/song2.mp3'],
        currentIndex: 0,
      );

      final result = await env.orchestrator.selectQueueIndex(0);

      expect(result.status, equals(TrackLoadStatus.failed));
    });

    test('returns failed for out-of-bounds index', () async {
      final env = createOrchestrator(
        connection: makeConnection(),
        password: 'secret',
      );
      env.orchestrator.queue = makeQueue(
        paths: ['/music/song1.mp3'],
        currentIndex: 0,
      );

      final result = await env.orchestrator.selectQueueIndex(5);

      expect(result.status, equals(TrackLoadStatus.failed));
    });

    test('returns failed when queue is null', () async {
      final env = createOrchestrator();

      final result = await env.orchestrator.selectQueueIndex(0);

      expect(result.status, equals(TrackLoadStatus.failed));
    });
  });

  // ── Extra: saveProgress ─────────────────────────────────────────────────

  group('REF-14: saveProgress', () {
    test('saves current position to progress saver', () async {
      final env = createOrchestrator(
        connection: makeConnection(),
        password: 'secret',
      );
      // Set up a loaded state with connection ID recorded.
      env.orchestrator.queue = makeQueue(paths: ['/music/song.mp3']);
      when(env.player.position).thenReturn(const Duration(seconds: 45));
      when(env.player.duration).thenReturn(const Duration(seconds: 300));

      // First load to record the connection ID.
      await env.orchestrator.loadAndPlay();

      // Now save.
      env.orchestrator.saveProgress();

      verify(env.progressSaver.upsertProgress(
        connectionId: 1,
        filePath: '/music/song.mp3',
        positionMs: 45000,
        durationMs: 300000,
      )).called(1);
    });

    test('does nothing when queue is null', () {
      final env = createOrchestrator();

      // Should not throw.
      env.orchestrator.saveProgress();

      verifyNever(env.progressSaver.upsertProgress(
        connectionId: anyNamed('connectionId'),
        filePath: anyNamed('filePath'),
        positionMs: anyNamed('positionMs'),
        durationMs: anyNamed('durationMs'),
      ));
    });
  });
}
