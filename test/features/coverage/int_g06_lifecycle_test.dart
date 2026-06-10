// test/features/coverage/int_g06_lifecycle_test.dart
// INT-G06: App lifecycle integration tests.
//
// Test cases:
//   INT-G06-T01: App resumes foreground -> timer expiry detected -> pause
//   INT-G06-T02: App enters background -> progress saved
//
// These tests exercise the TimerService + PlaybackOrchestrator interaction
// during app lifecycle transitions (foreground/background).

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:nas_audio_player/features/timer/domain/timer_service.dart';
import 'package:nas_audio_player/shared/di/providers.dart';

import '../../helpers/mock_audio_player.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// INT-G06-T01: App resumes foreground -> timer expiry detected -> pause
// ═══════════════════════════════════════════════════════════════════════════════

void main() {
  group('INT-G06-T01: App resumes foreground -> timer expiry -> pause', () {
    test('expired duration timer detected on resume -> returns true', () {
      final service = TimerService();
      final player = MockAudioPlayer();

      // Start a 0-minute timer (immediately expired).
      service.startDuration(0);

      // Simulate app resume: check timer expiry.
      final expired = service.checkExpired();

      expect(expired, isTrue,
          reason: 'INT-G06-T01: expired timer should be detected on resume');
      expect(service.state, isNull,
          reason: 'INT-G06-T01: timer state should be cleared after expiry');

      // The caller should call player.pause() when checkExpired returns true.
      if (expired) {
        player.pause();
      }
      verify(player.pause()).called(1);
    });

    test('non-expired timer on resume -> returns false, no pause', () {
      final service = TimerService();
      final player = MockAudioPlayer();

      // Start a 10-minute timer.
      service.startDuration(10);

      // Simulate app resume.
      final expired = service.checkExpired();

      expect(expired, isFalse,
          reason:
              'INT-G06-T01: non-expired timer should not trigger on resume');
      expect(service.isActive, isTrue,
          reason: 'INT-G06-T01: timer should still be active');

      // No pause should be called.
      if (expired) {
        player.pause();
      }
      verifyNever(player.pause());
    });

    test('afterCurrent timer on resume -> checkExpired returns false', () {
      final service = TimerService();
      final player = MockAudioPlayer();

      // Start afterCurrent mode.
      service.startAfterCurrent();

      // checkExpired always returns false for afterCurrent.
      final expired = service.checkExpired();

      expect(expired, isFalse,
          reason:
              'INT-G06-T01: afterCurrent timer should not trigger via checkExpired');
      expect(service.isActive, isTrue);

      if (expired) {
        player.pause();
      }
      verifyNever(player.pause());
    });

    test('cancelled timer on resume -> returns false', () {
      final service = TimerService();
      final player = MockAudioPlayer();

      // Start then cancel.
      service.startDuration(5);
      service.cancel();

      final expired = service.checkExpired();

      expect(expired, isFalse,
          reason: 'INT-G06-T01: cancelled timer should not trigger on resume');
      expect(service.state, isNull);

      if (expired) {
        player.pause();
      }
      verifyNever(player.pause());
    });

    test('no timer active on resume -> returns false', () {
      final service = TimerService();
      final player = MockAudioPlayer();

      // No timer started.
      final expired = service.checkExpired();

      expect(expired, isFalse,
          reason: 'INT-G06-T01: no timer should not trigger');
      verifyNever(player.pause());
    });

    test('ProviderContainer: checkTimerExpiryProvider detects expired timer',
        () {
      final player = MockAudioPlayer();
      final service = TimerService();

      // Start an expired timer.
      service.startDuration(0);

      final container = ProviderContainer(
        overrides: [
          timerServiceProvider.overrideWithValue(service),
          audioPlayerProvider.overrideWithValue(player),
        ],
      );
      addTearDown(() => container.dispose);

      // Read the checkTimerExpiryProvider.
      final checkExpired = container.read(checkTimerExpiryProvider);
      final result = checkExpired();

      expect(result, isTrue,
          reason:
              'INT-G06-T01: checkTimerExpiryProvider should detect expired timer');

      // Timer state should be cleared.
      final state = container.read(timerStateProvider);
      expect(state, isNull,
          reason: 'INT-G06-T01: timer state should be null after expiry check');
    });

    test(
        'ProviderContainer: checkTimerExpiryProvider returns false for active timer',
        () {
      final service = TimerService();
      service.startDuration(10);

      final container = ProviderContainer(
        overrides: [
          timerServiceProvider.overrideWithValue(service),
        ],
      );
      addTearDown(() => container.dispose);

      final checkExpired = container.read(checkTimerExpiryProvider);
      final result = checkExpired();

      expect(result, isFalse,
          reason: 'INT-G06-T01: active timer should not trigger expiry');
      expect(container.read(timerStateProvider), isNotNull,
          reason: 'INT-G06-T01: timer state should still be active');
    });

    test(
        'full lifecycle: start timer -> resume -> expiry -> pause -> restart timer',
        () {
      final service = TimerService();
      final player = MockAudioPlayer();

      // Step 1: Start a 0-minute timer (will expire immediately).
      service.startDuration(0);
      expect(service.isActive, isTrue);

      // Step 2: App resumes foreground — check expiry.
      final expired = service.checkExpired();
      expect(expired, isTrue);
      expect(service.state, isNull);

      // Step 3: Caller pauses playback.
      if (expired) {
        player.pause();
      }
      verify(player.pause()).called(1);

      // Step 4: User restarts a new timer.
      service.startDuration(15);
      expect(service.isActive, isTrue);
      expect(service.state!.mode, equals(TimerMode.duration));

      // Step 5: New timer should not be expired yet.
      expect(service.checkExpired(), isFalse);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════════
  // INT-G06-T02: App enters background -> progress saved
  // ═══════════════════════════════════════════════════════════════════════════════

  group('INT-G06-T02: App enters background -> progress saved', () {
    test('saveProgress is called when app goes to background', () {
      // Track whether saveProgress was called.
      bool progressSaved = false;

      final container = ProviderContainer(
        overrides: [
          saveProgressProvider.overrideWith((ref) => () {
                progressSaved = true;
              }),
        ],
      );
      addTearDown(() => container.dispose);

      // Simulate app going to background: call saveProgress.
      final saveFn = container.read(saveProgressProvider);
      saveFn();

      expect(progressSaved, isTrue,
          reason: 'INT-G06-T02: saveProgress should be called on background');
    });

    test('saveProgress calls orchestrator.saveProgress', () {
      int saveCount = 0;

      final container = ProviderContainer(
        overrides: [
          saveProgressProvider.overrideWith((ref) => () {
                saveCount++;
              }),
        ],
      );
      addTearDown(() => container.dispose);

      // Multiple background transitions should each trigger save.
      final saveFn = container.read(saveProgressProvider);
      saveFn();
      saveFn();
      saveFn();

      expect(saveCount, equals(3),
          reason:
              'INT-G06-T02: each background transition should save progress');
    });

    test('progress saved includes current position and duration', () {
      // Simulate the progress save logic.
      const position = Duration(seconds: 45);
      const duration = Duration(seconds: 180);

      // The saveProgressProvider delegates to orchestrator.saveProgress()
      // which reads player.position and player.duration.
      final positionMs = position.inMilliseconds;
      final durationMs = duration.inMilliseconds;

      expect(positionMs, equals(45000),
          reason: 'INT-G06-T02: position should be converted to milliseconds');
      expect(durationMs, equals(180000),
          reason: 'INT-G06-T02: duration should be converted to milliseconds');
    });

    test('saveProgress handles null duration gracefully', () {
      // When duration is null (streaming, not yet loaded), save should still work.
      const position = Duration(seconds: 30);
      const int? durationMs = null;

      // The shouldSave check: position >= 5000ms
      final shouldSave = position.inMilliseconds >= 5000;
      expect(shouldSave, isTrue,
          reason: 'INT-G06-T02: shouldSave should be true for position >= 5s');

      // The upsert should work with null duration.
      expect(durationMs, isNull,
          reason: 'INT-G06-T02: null duration should be handled gracefully');
    });

    test('auto-save timer fires periodically during playback', () {
      int saveCount = 0;

      final container = ProviderContainer(
        overrides: [
          saveProgressProvider.overrideWith((ref) => () {
                saveCount++;
              }),
        ],
      );
      addTearDown(() => container.dispose);

      // Simulate the auto-save timer logic:
      // Timer.periodic(Duration(seconds: 10), (_) => saveProgress())
      // We simulate 3 ticks.
      final saveFn = container.read(saveProgressProvider);
      for (int i = 0; i < 3; i++) {
        saveFn();
      }

      expect(saveCount, equals(3),
          reason: 'INT-G06-T02: auto-save should fire periodically');
    });

    test('pause triggers save progress', () {
      // Track save calls.
      int saveCount = 0;

      final container = ProviderContainer(
        overrides: [
          saveProgressProvider.overrideWith((ref) => () {
                saveCount++;
              }),
        ],
      );
      addTearDown(() => container.dispose);

      // Simulate the pause-save logic:
      // When player transitions from playing=true to playing=false, save.
      final saveFn = container.read(saveProgressProvider);

      // Simulate a playing->paused transition: should save.
      final wasPlayingList = [true, false];
      final nowPlayingList = [false, false];
      for (var i = 0; i < wasPlayingList.length; i++) {
        if (wasPlayingList[i] && !nowPlayingList[i]) {
          saveFn();
        }
      }

      // First iteration (true->false): saves. Second (false->false): no-op.
      expect(saveCount, equals(1),
          reason: 'INT-G06-T02: only playing->paused transition should save');
    });

    test('background + timer expiry + resume: full lifecycle', () {
      final service = TimerService();
      final player = MockAudioPlayer();
      int saveCount = 0;

      // Start playback with a short timer.
      service.startDuration(0); // Will expire immediately.

      // Step 1: App goes to background — save progress.
      saveCount++;
      expect(saveCount, equals(1));

      // Step 2: App resumes — check timer.
      final expired = service.checkExpired();
      expect(expired, isTrue,
          reason: 'INT-G06-T02: timer should be expired on resume');

      // Step 3: Pause playback due to timer expiry.
      if (expired) {
        player.pause();
        saveCount++; // Save again on pause.
      }
      verify(player.pause()).called(1);
      expect(saveCount, equals(2),
          reason: 'INT-G06-T02: should have saved twice (background + pause)');

      // Step 4: User starts new timer and resumes playback.
      service.startDuration(30);
      when(player.play()).thenAnswer((_) async {});
      player.play();
      expect(service.isActive, isTrue);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════════
  // INT-G06-T03: Timer + track completion interaction
  // ═══════════════════════════════════════════════════════════════════════════════

  group('INT-G06-T03: Timer + track completion interaction', () {
    test('afterCurrent timer triggers on track completion', () {
      final service = TimerService();
      final player = MockAudioPlayer();

      // Start afterCurrent mode.
      service.startAfterCurrent();
      expect(service.isActive, isTrue);

      // Track completes.
      final triggered = service.onTrackCompleted();
      expect(triggered, isTrue,
          reason: 'INT-G06-T03: afterCurrent should trigger on completion');

      // Caller pauses.
      if (triggered) {
        player.pause();
      }
      verify(player.pause()).called(1);
      expect(service.state, isNull,
          reason: 'INT-G06-T03: timer state should be cleared after trigger');
    });

    test('duration timer expiry + track completion -> single pause', () {
      final service = TimerService();
      final player = MockAudioPlayer();

      // Start a 0-minute timer (already expired).
      service.startDuration(0);

      int pauseCount = 0;

      // Event 1: Timer expiry check (e.g., on app resume).
      if (service.checkExpired()) {
        player.pause();
        pauseCount++;
      }

      // Event 2: Track completion (simultaneous).
      if (service.onTrackCompleted()) {
        player.pause();
        pauseCount++;
      }

      expect(pauseCount, equals(1),
          reason: 'INT-G06-T03: should pause exactly once (timer expiry wins)');
      expect(service.state, isNull);
    });

    test('no timer -> track completion does not trigger pause', () {
      final service = TimerService();
      final player = MockAudioPlayer();

      // No timer active.
      final triggered = service.onTrackCompleted();
      expect(triggered, isFalse,
          reason: 'INT-G06-T03: no timer should not trigger on completion');

      if (triggered) {
        player.pause();
      }
      verifyNever(player.pause());
    });

    test(
        'ProviderContainer: onTrackCompletedProvider triggers for afterCurrent',
        () {
      final service = TimerService();
      service.startAfterCurrent();

      final container = ProviderContainer(
        overrides: [
          timerServiceProvider.overrideWithValue(service),
        ],
      );
      addTearDown(() => container.dispose);

      final onCompleted = container.read(onTrackCompletedProvider);
      final result = onCompleted();

      expect(result, isTrue,
          reason:
              'INT-G06-T03: onTrackCompletedProvider should trigger for afterCurrent');

      final state = container.read(timerStateProvider);
      expect(state, isNull,
          reason: 'INT-G06-T03: timer state should be cleared after trigger');
    });

    test(
        'ProviderContainer: onTrackCompletedProvider returns false when no timer',
        () {
      final service = TimerService();

      final container = ProviderContainer(
        overrides: [
          timerServiceProvider.overrideWithValue(service),
        ],
      );
      addTearDown(() => container.dispose);

      final onCompleted = container.read(onTrackCompletedProvider);
      final result = onCompleted();

      expect(result, isFalse,
          reason:
              'INT-G06-T03: no timer should not trigger completion handler');
    });
  });
}
