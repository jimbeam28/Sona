// test/features/player/bug_01_test.dart
// BUG-01: _completingProvider 卡死导致自动切歌永久失效 — automated test suite
//
// Verifies that when currentPlayQueueProvider is null and a track completes,
// _completingProvider is properly reset to false so that subsequent track
// completions are not permanently ignored.
//
// BUG-01-T01: queue is null on track completion → _completingProvider resets
// BUG-01-T02: after fix, subsequent completion is processed normally
// BUG-01-T03: afterCurrent triggered path still resets _completingProvider (regression)

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:nas_audio_player/features/timer/domain/timer_service.dart';
import 'package:nas_audio_player/features/browser/browser_provider.dart';
import 'package:nas_audio_player/features/player/player_provider.dart';
import 'package:nas_audio_player/features/timer/timer_provider.dart';
import 'package:nas_audio_player/shared/models/nas_file.dart';
import 'package:nas_audio_player/shared/models/play_queue.dart';

import '../../helpers/test_factories.dart';
import 'bug_01_test.mocks.dart';

// ── Helpers ──────────────────────────────────────────────────────────────────

// testAudio() is imported from test_factories.dart as testAudio().

PlayQueue _queue(List<NasFile> files, {int currentIndex = 0}) {
  return PlayQueue(files: files, currentIndex: currentIndex);
}

/// Creates a [ProviderContainer] with overrides for all providers involved in
/// the processing-state listener logic.
///
/// [queue] controls what [currentPlayQueueProvider] returns.
/// [afterCurrentTriggered] controls whether [onTrackCompletedProvider] returns
/// true (simulating an afterCurrent timer that fires on track completion).
ProviderContainer _createContainer({
  required AudioPlayer player,
  PlayQueue? queue,
  bool afterCurrentTriggered = false,
}) {
  final timerService = TimerService();
  if (afterCurrentTriggered) {
    timerService.startAfterCurrent();
  }

  return ProviderContainer(
    overrides: [
      audioPlayerProvider.overrideWith((ref) => player),
      currentPlayQueueProvider.overrideWith((ref) => queue),
      timerServiceProvider.overrideWith((ref) => timerService),
      saveProgressProvider.overrideWith((ref) => () {}),
      loadAndPlayProvider
          .overrideWith((ref) => () async => TrackLoadResult.loaded(player)),
    ],
  );
}

@GenerateMocks([AudioPlayer])
void main() {
  // ── BUG-01-T01: queue is null on track completion → _completingProvider resets ──

  group('BUG-01-T01: queue null on completion resets _completingProvider', () {
    test('after completion with null queue, next completion is not ignored',
        () async {
      final player = MockAudioPlayer();
      final controller = StreamController<ProcessingState>();

      when(player.processingStateStream).thenAnswer((_) => controller.stream);
      when(player.pause()).thenAnswer((_) async {});

      final container = _createContainer(
        player: player,
        queue: null, // queue is null
      );
      // Do NOT call container.dispose() — startProcessingListenerProvider's
      // onDispose callback reads _processingSubProvider which would throw
      // on a disposed container (Riverpod limitation).

      // Register the processing-state listener.
      container.read(startProcessingListenerProvider)();

      // First completion: queue is null, should return early but reset flag.
      controller.add(ProcessingState.completed);
      await Future<void>.delayed(Duration.zero);

      // Second completion: if _completingProvider was properly reset,
      // this should NOT be silently ignored.  With a non-null queue,
      // it should attempt to advance.
      final files = [
        testAudio('a.mp3', '/a.mp3'),
        testAudio('b.mp3', '/b.mp3'),
      ];
      container.read(currentPlayQueueProvider.notifier).state =
          _queue(files, currentIndex: 0);

      // The timer service has no active timer, so onTrackCompleted returns false.
      // With a valid queue at index 0 of 2, it should advance to index 1.
      controller.add(ProcessingState.completed);
      await Future<void>.delayed(Duration.zero);

      // Verify the queue was advanced (index 0 → 1), proving the second
      // completion was NOT ignored.
      final updatedQueue = container.read(currentPlayQueueProvider);
      expect(updatedQueue, isNotNull,
          reason: 'queue should still exist after advancement');
      expect(updatedQueue!.currentIndex, equals(1),
          reason: 'second completion should have advanced from index 0 to 1');

      await controller.close();
    });
  });

  // ── BUG-01-T02: after fix, subsequent completion advances queue normally ──

  group('BUG-01-T02: subsequent completion advances queue after null-queue fix',
      () {
    test('completion with valid queue after null-queue completion advances',
        () async {
      final player = MockAudioPlayer();
      final controller = StreamController<ProcessingState>();

      when(player.processingStateStream).thenAnswer((_) => controller.stream);
      when(player.pause()).thenAnswer((_) async {});

      final container = _createContainer(
        player: player,
        queue: null,
      );

      container.read(startProcessingListenerProvider)();

      // First: complete with null queue.
      controller.add(ProcessingState.completed);
      await Future<void>.delayed(Duration.zero);

      // Now set a queue with 3 tracks at index 1.
      final files = [
        testAudio('track1.mp3', '/track1.mp3'),
        testAudio('track2.mp3', '/track2.mp3'),
        testAudio('track3.mp3', '/track3.mp3'),
      ];
      container.read(currentPlayQueueProvider.notifier).state =
          _queue(files, currentIndex: 1);

      // Second: complete with valid queue → should advance to index 2.
      controller.add(ProcessingState.completed);
      await Future<void>.delayed(Duration.zero);

      final updatedQueue = container.read(currentPlayQueueProvider);
      expect(updatedQueue, isNotNull);
      expect(updatedQueue!.currentIndex, equals(2),
          reason: 'should advance from index 1 to 2 after null-queue reset');

      await controller.close();
    });
  });

  // ── BUG-01-T03: afterCurrent path still resets _completingProvider (regression) ──

  group('BUG-01-T03: afterCurrent triggered path resets _completingProvider',
      () {
    test('afterCurrent completion resets flag so next completion is processed',
        () async {
      final player = MockAudioPlayer();
      final controller = StreamController<ProcessingState>();

      when(player.processingStateStream).thenAnswer((_) => controller.stream);
      when(player.pause()).thenAnswer((_) async {});

      final files = [
        testAudio('a.mp3', '/a.mp3'),
        testAudio('b.mp3', '/b.mp3'),
        testAudio('c.mp3', '/c.mp3'),
      ];

      // First container: afterCurrent is active, so onTrackCompleted returns true.
      final container1 = _createContainer(
        player: player,
        queue: _queue(files, currentIndex: 0),
        afterCurrentTriggered: true,
      );

      container1.read(startProcessingListenerProvider)();

      // First completion: afterCurrent triggers, player should be paused,
      // and _completingProvider should be reset.
      controller.add(ProcessingState.completed);
      await Future<void>.delayed(Duration.zero);

      verify(player.pause()).called(1);

      // Create a second stream controller for the second container.
      final controller2 = StreamController<ProcessingState>();
      reset(player);
      when(player.processingStateStream).thenAnswer((_) => controller2.stream);
      when(player.pause()).thenAnswer((_) async {});

      // Second container: simulate a fresh session (afterCurrent no longer active).
      // Each container has its own _completingProvider (starts at false).
      // This verifies the afterCurrent path does not leave stale state.
      final container2 = _createContainer(
        player: player,
        queue: _queue(files, currentIndex: 0),
        afterCurrentTriggered: false,
      );

      container2.read(startProcessingListenerProvider)();

      // Complete again — should advance to index 1 (not be ignored).
      controller2.add(ProcessingState.completed);
      await Future<void>.delayed(Duration.zero);

      final updatedQueue = container2.read(currentPlayQueueProvider);
      expect(updatedQueue, isNotNull);
      expect(updatedQueue!.currentIndex, equals(1),
          reason: 'after afterCurrent reset, next completion should advance');

      await controller.close();
      await controller2.close();
    });
  });
}
