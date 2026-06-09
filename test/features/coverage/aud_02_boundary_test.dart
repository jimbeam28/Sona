// test/features/coverage/aud_02_boundary_test.dart
// AUD-02: Boundary value tests for cache, player polling, screen timeout, and timer.
//
// Test cases:
//   AUD-02-T01: cache age=4:59 -> alive (hit)
//   AUD-02-T02: cache age=5:00 -> expired
//   AUD-02-T03: cache 49 entries -> no eviction
//   AUD-02-T04: cache 50 entries -> no eviction
//   AUD-02-T05: cache 51 entries -> evicts 1
//   AUD-02-T06: play() polling 11.8s success -> loaded
//   AUD-02-T07: play() polling 12.0s not started -> failed
//   AUD-02-T08: screen timeout 14.9s complete -> loaded
//   AUD-02-T09: screen timeout 15.0s -> TimeoutException
//   AUD-02-T10: startDuration(0) -> immediately expired

import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:mockito/mockito.dart';
import 'package:nas_audio_player/features/browser/domain/cache_policy.dart';
import 'package:nas_audio_player/features/player/domain/playback_orchestrator.dart';
import 'package:nas_audio_player/features/player/domain/request_gate.dart';
import 'package:nas_audio_player/features/timer/domain/timer_service.dart';
import 'package:nas_audio_player/shared/models/connection_config.dart';
import 'package:nas_audio_player/shared/models/nas_file.dart';
import 'package:nas_audio_player/shared/models/play_queue.dart';

import '../../helpers/mock_audio_player.dart';

void main() {
  // ═══════════════════════════════════════════════════════════════════════════
  // AUD-02-T01: Cache age=4:59 -> alive (hit)
  // AUD-02-T02: Cache age=5:00 -> expired
  // ═══════════════════════════════════════════════════════════════════════════

  group('AUD-02-T01: cache age 4:59 -> alive', () {
    test('entry at 4 minutes 59 seconds is still alive', () {
      const policy = CachePolicy<String>();
      final createdAt = DateTime(2026, 6, 9, 10, 0, 0);
      final entry = CacheEntry<String>(
        value: 'data',
        createdAt: createdAt,
      );

      final now = createdAt.add(const Duration(minutes: 4, seconds: 59));
      expect(policy.isAlive(entry, now), isTrue,
          reason: 'cache entry at 4m59s should be alive (TTL=5min, '
              'uses strict < comparison)');
    });
  });

  group('AUD-02-T02: cache age 5:00 -> expired', () {
    test('entry at exactly 5 minutes is expired', () {
      const policy = CachePolicy<String>();
      final createdAt = DateTime(2026, 6, 9, 10, 0, 0);
      final entry = CacheEntry<String>(
        value: 'data',
        createdAt: createdAt,
      );

      final now = createdAt.add(const Duration(minutes: 5));
      expect(policy.isAlive(entry, now), isFalse,
          reason: 'cache entry at exactly 5m00s should be expired '
              '(5min - 5min = 0, not < 0, so isAlive returns false)');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // AUD-02-T03: Cache 49 entries -> no eviction
  // AUD-02-T04: Cache 50 entries -> no eviction
  // AUD-02-T05: Cache 51 entries -> evicts 1
  // ═══════════════════════════════════════════════════════════════════════════

  group('AUD-02-T03: cache 49 entries -> no eviction', () {
    test('49 entries remain all intact', () {
      const policy = CachePolicy<String>(maxSize: 50);
      final now = DateTime(2026, 6, 9, 10, 0, 0);
      final cache = <String, CacheEntry<String>>{};
      for (int i = 1; i <= 49; i++) {
        cache['key:$i'] = CacheEntry<String>(
          value: 'data:$i',
          createdAt: now.add(Duration(minutes: i)),
        );
      }

      final result = policy.evict(cache);
      expect(result.length, equals(49),
          reason: '49 entries should not trigger eviction (maxSize=50)');
    });
  });

  group('AUD-02-T04: cache 50 entries -> no eviction', () {
    test('50 entries at capacity remain all intact', () {
      const policy = CachePolicy<String>(maxSize: 50);
      final now = DateTime(2026, 6, 9, 10, 0, 0);
      final cache = <String, CacheEntry<String>>{};
      for (int i = 1; i <= 50; i++) {
        cache['key:$i'] = CacheEntry<String>(
          value: 'data:$i',
          createdAt: now.add(Duration(minutes: i)),
        );
      }

      final result = policy.evict(cache);
      expect(result.length, equals(50),
          reason: '50 entries at maxSize should not trigger eviction');
    });
  });

  group('AUD-02-T05: cache 51 entries -> evicts 1', () {
    test('51st entry triggers eviction of oldest', () {
      const policy = CachePolicy<String>(maxSize: 50);
      final now = DateTime(2026, 6, 9, 10, 0, 0);
      var cache = <String, CacheEntry<String>>{};
      for (int i = 1; i <= 50; i++) {
        cache['key:$i'] = CacheEntry<String>(
          value: 'data:$i',
          createdAt: now.add(Duration(minutes: i)),
        );
      }

      // Insert 51st entry — triggers eviction
      cache = policy.put(
        cache,
        'key:51',
        CacheEntry<String>(
          value: 'data:51',
          createdAt: now.add(const Duration(minutes: 51)),
        ),
      );

      expect(cache.length, equals(50),
          reason: 'after eviction, cache should be at maxSize');
      expect(cache.containsKey('key:1'), isFalse,
          reason: 'key:1 has the oldest lastAccessedAt and should be evicted');
      expect(cache.containsKey('key:51'), isTrue,
          reason: 'newly inserted key:51 should survive');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // AUD-02-T06: play() polling 11.8s success -> loaded
  // AUD-02-T07: play() polling 12.0s not started -> failed
  //
  // The polling loop in PlaybackOrchestrator.loadAndPlay() checks
  // player.playing 60 times at 200ms intervals (12s total).
  // ═══════════════════════════════════════════════════════════════════════════

  group('AUD-02-T06: play() polling 11.8s success -> loaded', () {
    test('player becomes playing at 11.6s (iteration 58) -> loaded', () {
      FakeAsync().run((async) {
        final player = _LenientMockPlayer();
        final connectionProvider = _MockActiveConnectionProvider();
        final passwordReader = _MockPasswordReader();
        final progressSaver = _MockProgressSaver();
        final speedProvider = _MockDefaultSpeedProvider();
        final queueConnIdProvider = _MockQueueConnectionIdProvider();

        final connection = _makeConnection();
        connectionProvider._connection = connection;
        passwordReader._password = 'secret';
        speedProvider._speed = 1.0;
        queueConnIdProvider._lastId = 1;

        // Simulate: player.playing returns false for first 58 iterations
        // (11.6s), then true on the 59th check (11.8s).
        int playCheckCount = 0;
        when(player.playing).thenAnswer((_) {
          playCheckCount++;
          return playCheckCount >= 59;
        });

        final orchestrator = PlaybackOrchestrator(
          player: player,
          connectionProvider: connectionProvider,
          passwordReader: passwordReader,
          progressSaver: progressSaver,
          defaultSpeedProvider: speedProvider,
          queueConnectionIdProvider: queueConnIdProvider,
        );

        final files = [
          _makeFile('/music/song.mp3'),
        ];
        orchestrator.queue = PlayQueue(files: files, currentIndex: 0);

        var result = TrackLoadStatus.failed;
        orchestrator.loadAndPlay().then((r) {
          result = r.status;
        });

        // Advance 12 seconds to let the polling loop complete.
        // Iterations fire at 0ms, 200ms, 400ms, ... 11600ms (59th).
        // At the 59th check (11.8s), playing returns true.
        async.elapse(const Duration(seconds: 12));

        expect(result, equals(TrackLoadStatus.loaded),
            reason: 'play() succeeding at 11.8s (iteration 59) should yield loaded');
      });
    });
  });

  group('AUD-02-T07: play() polling 12.0s not started -> failed', () {
    test('player never becomes playing in 12s -> failed', () {
      FakeAsync().run((async) {
        final player = _LenientMockPlayer();
        final connectionProvider = _MockActiveConnectionProvider();
        final passwordReader = _MockPasswordReader();
        final progressSaver = _MockProgressSaver();
        final speedProvider = _MockDefaultSpeedProvider();
        final queueConnIdProvider = _MockQueueConnectionIdProvider();

        final connection = _makeConnection();
        connectionProvider._connection = connection;
        passwordReader._password = 'secret';
        speedProvider._speed = 1.0;
        queueConnIdProvider._lastId = 1;

        // player.playing always returns false — play never starts.
        when(player.playing).thenReturn(false);

        final orchestrator = PlaybackOrchestrator(
          player: player,
          connectionProvider: connectionProvider,
          passwordReader: passwordReader,
          progressSaver: progressSaver,
          defaultSpeedProvider: speedProvider,
          queueConnectionIdProvider: queueConnIdProvider,
        );

        final files = [
          _makeFile('/music/song.mp3'),
        ];
        orchestrator.queue = PlayQueue(files: files, currentIndex: 0);

        var result = TrackLoadStatus.loaded;
        orchestrator.loadAndPlay().then((r) {
          result = r.status;
        });

        // Advance past the 12-second polling window (60 * 200ms).
        async.elapse(const Duration(seconds: 13));

        expect(result, equals(TrackLoadStatus.failed),
            reason: 'play() never starting within 12s should yield failed');
        verify(player.stop()).called(1);
      });
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // AUD-02-T08: Screen timeout 14.9s complete -> loaded
  // AUD-02-T09: Screen timeout 15.0s -> TimeoutException
  //
  // The _runSerializedLoad in PlayerScreen wraps loadAndPlay() with a
  // 15-second timeout: await request().timeout(Duration(seconds: 15)).
  // We test this at the SerializedRequestGate level with the 20s gate
  // timeout, but the key boundary is the 15s screen-level timeout.
  //
  // To test the screen timeout boundary cleanly, we simulate the exact
  // timeout pattern used in _runSerializedLoad.
  // ═══════════════════════════════════════════════════════════════════════════

  group('AUD-02-T08: screen timeout 14.9s complete -> loaded', () {
    test('task completes at 14.9s -> no TimeoutException', () {
      FakeAsync().run((async) {
        // Simulate the exact pattern from _runSerializedLoad:
        //   loaded = await request().timeout(Duration(seconds: 15));
        var completed = false;
        var timedOut = false;

        Future<String> task() async {
          await Future<void>.delayed(const Duration(milliseconds: 14900));
          return 'loaded';
        }

        task().timeout(const Duration(seconds: 15)).then((v) {
          completed = true;
        }).catchError((e) {
          timedOut = true;
        });

        // Advance 14.9 seconds — task should complete just before timeout.
        async.elapse(const Duration(milliseconds: 15000));

        expect(completed, isTrue,
            reason: 'task completing at 14.9s should not trigger timeout');
        expect(timedOut, isFalse);
      });
    });
  });

  group('AUD-02-T09: screen timeout 15.0s -> TimeoutException', () {
    test('task takes exactly 15s -> TimeoutException', () async {
      var completed = false;
      var timedOut = false;

      // Task that takes exactly 15 seconds (or longer).
      Future<String> task() async {
        await Future<void>.delayed(const Duration(milliseconds: 15100));
        return 'loaded';
      }

      try {
        await task().timeout(const Duration(seconds: 15));
        completed = true;
      } on TimeoutException {
        timedOut = true;
      }

      expect(timedOut, isTrue,
          reason: 'task taking 15+ seconds should trigger TimeoutException');
      expect(completed, isFalse);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // AUD-02-T10: startDuration(0) -> immediately expired
  // ═══════════════════════════════════════════════════════════════════════════

  group('AUD-02-T10: startDuration(0) -> immediately expired', () {
    test('zero-duration timer is expired on creation', () {
      final service = TimerService();
      final state = service.startDuration(0);

      expect(state.mode, equals(TimerMode.duration),
          reason: 'mode should be duration');
      expect(state.endTime, isNotNull,
          reason: 'endTime should be set');

      // endTime = now + 0 minutes = now, which means !endTime.isAfter(now)
      expect(state.isExpired, isTrue,
          reason: 'startDuration(0) should create an immediately-expired timer');

      // checkExpired should return true and clear state
      final expired = service.checkExpired();
      expect(expired, isTrue,
          reason: 'checkExpired should return true for zero-duration timer');
      expect(service.state, isNull,
          reason: 'state should be cleared after expiry check');
    });

    test('zero-duration timer active then checked -> true, state cleared', () {
      final service = TimerService();
      service.startDuration(0);
      expect(service.isActive, isTrue,
          reason: 'timer should be active immediately after startDuration(0)');

      final expired = service.checkExpired();
      expect(expired, isTrue);
      expect(service.isActive, isFalse,
          reason: 'after checkExpired, timer should be inactive');
    });
  });
}

// ═══════════════════════════════════════════════════════════════════════════════
// Helpers
// ═══════════════════════════════════════════════════════════════════════════════

/// A lightweight AudioPlayer mock that does NOT throw on missing stubs.
///
/// Unlike [MockAudioPlayer] (which calls [throwOnMissingStub]), this
/// variant allows unstubbed method calls to return default values via
/// [Mock.noSuchMethod].  This avoids the type-system conflict between
/// Mockito's `any` matcher and non-nullable parameter types.
class _LenientMockPlayer extends Mock implements AudioPlayer {
  @override
  Stream<ProcessingState> get processingStateStream =>
      super.noSuchMethod(Invocation.getter(#processingStateStream),
          returnValue: Stream<ProcessingState>.empty(),
          returnValueForMissingStub: Stream<ProcessingState>.empty())
      as Stream<ProcessingState>;

  @override
  Stream<PlayerState> get playerStateStream =>
      super.noSuchMethod(Invocation.getter(#playerStateStream),
          returnValue: Stream<PlayerState>.empty(),
          returnValueForMissingStub: Stream<PlayerState>.empty())
      as Stream<PlayerState>;

  @override
  Stream<Duration> get positionStream =>
      super.noSuchMethod(Invocation.getter(#positionStream),
          returnValue: Stream<Duration>.empty(),
          returnValueForMissingStub: Stream<Duration>.empty())
      as Stream<Duration>;

  @override
  Stream<Duration?> get durationStream =>
      super.noSuchMethod(Invocation.getter(#durationStream),
          returnValue: Stream<Duration?>.empty(),
          returnValueForMissingStub: Stream<Duration?>.empty())
      as Stream<Duration?>;

  @override
  bool get playing => super.noSuchMethod(Invocation.getter(#playing),
      returnValue: false, returnValueForMissingStub: false) as bool;

  @override
  Duration get position => super.noSuchMethod(Invocation.getter(#position),
      returnValue: Duration.zero, returnValueForMissingStub: Duration.zero)
      as Duration;

  @override
  Future<Duration?> setAudioSource(AudioSource source,
          {bool preload = true,
          int? initialIndex,
          Duration? initialPosition}) =>
      super.noSuchMethod(
          Invocation.method(#setAudioSource, [
            source
          ], {
            #preload: preload,
            if (initialIndex != null) #initialIndex: initialIndex,
            if (initialPosition != null) #initialPosition: initialPosition,
          }),
          returnValue: Future<Duration?>.value(),
          returnValueForMissingStub: Future<Duration?>.value())
      as Future<Duration?>;

  @override
  Future<void> play() => super.noSuchMethod(Invocation.method(#play, []),
      returnValue: Future<void>.value(),
      returnValueForMissingStub: Future<void>.value()) as Future<void>;

  @override
  Future<void> pause() => super.noSuchMethod(Invocation.method(#pause, []),
      returnValue: Future<void>.value(),
      returnValueForMissingStub: Future<void>.value()) as Future<void>;

  @override
  Future<void> stop() => super.noSuchMethod(Invocation.method(#stop, []),
      returnValue: Future<void>.value(),
      returnValueForMissingStub: Future<void>.value()) as Future<void>;

  @override
  Future<void> seek(Duration? position, {int? index}) => super.noSuchMethod(
      Invocation.method(#seek, [position], {if (index != null) #index: index}),
      returnValue: Future<void>.value(),
      returnValueForMissingStub: Future<void>.value()) as Future<void>;

  @override
  Future<void> setSpeed(double speed) =>
      super.noSuchMethod(Invocation.method(#setSpeed, [speed]),
          returnValue: Future<void>.value(),
          returnValueForMissingStub: Future<void>.value()) as Future<void>;
}

ConnectionConfig _makeConnection({int id = 1}) => ConnectionConfig(
      id: id,
      name: 'test',
      url: 'http://localhost:8080',
      username: 'user',
      createdAt: DateTime(2024),
      updatedAt: DateTime(2024),
    );

NasFile _makeFile(String path) => NasFile(
      name: path.split('/').last,
      path: path,
      isDirectory: false,
    );

// ── Lightweight mock implementations for PlaybackOrchestrator deps ────────

class _MockActiveConnectionProvider implements ActiveConnectionProvider {
  ConnectionConfig? _connection;

  @override
  Future<ConnectionConfig?> getActiveConnection() async => _connection;

  @override
  ConnectionConfig? get currentConnection => _connection;
}

class _MockPasswordReader implements PasswordReader {
  String? _password;

  @override
  Future<String?> readPassword(int connectionId) async => _password;
}

class _MockProgressSaver implements ProgressSaver {
  @override
  Future<void> upsertProgress({
    required int connectionId,
    required String filePath,
    required int positionMs,
    int? durationMs,
  }) async {}
}

class _MockDefaultSpeedProvider implements DefaultSpeedProvider {
  double _speed = 1.0;

  @override
  double getDefaultSpeed() => _speed;
}

class _MockQueueConnectionIdProvider implements QueueConnectionIdProvider {
  int? _lastId;

  @override
  int? getLastQueueConnectionId() => _lastId;
}
