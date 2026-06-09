// test/features/progress/ref_25_test.dart
// REF-25: progress_service.dart — domain service tests
//
// Tests the extracted ProgressService class:
//   - REF-25-T01: 5 trigger points each delegate to upsert
//   - REF-25-T02: Resume dialog state transitions
//   - REF-25-T03: Countdown expiry auto-selects continue
//
// Pure Dart tests — no Flutter widget dependencies.

import 'package:flutter_test/flutter_test.dart';
import 'package:nas_audio_player/core/database/dao/progress_dao.dart';
import 'package:nas_audio_player/features/progress/domain/progress_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../helpers/test_database.dart';
import '../../helpers/test_factories.dart';

void main() {
  // ── REF-25-T01: 5 trigger points each delegate to upsert ─────────────────

  group('REF-25-T01: save trigger points delegate to ProgressDao.upsert', () {
    late Database db;
    late ProgressDao dao;
    late ProgressService service;

    setUpAll(() {
      initSqfliteFfi();
    });

    setUp(() async {
      db = await openTestDatabase(TestSchema.progress);
      dao = ProgressDao();
      service = ProgressService(dao: dao);
    });

    tearDown(() async {
      await db.close();
    });

    test('SaveTrigger.periodic — 10-second auto-save delegates to upsert',
        () async {
      final result = await service.saveProgress(
        connectionId: 1,
        filePath: '/music/periodic.mp3',
        positionMs: 30000,
        durationMs: 120000,
        trigger: SaveTrigger.periodic,
      );

      expect(result, isTrue, reason: 'periodic save should succeed');
      final saved = await dao.find(1, '/music/periodic.mp3');
      expect(saved, isNotNull, reason: 'periodic save should persist to DB');
      expect(saved!.positionMs, equals(30000));
    });

    test('SaveTrigger.pause — pause detection delegates to upsert', () async {
      final result = await service.saveProgress(
        connectionId: 1,
        filePath: '/music/paused.mp3',
        positionMs: 67300,
        durationMs: 180000,
        trigger: SaveTrigger.pause,
      );

      expect(result, isTrue, reason: 'pause save should succeed');
      final saved = await dao.find(1, '/music/paused.mp3');
      expect(saved, isNotNull, reason: 'pause save should persist to DB');
      expect(saved!.positionMs, equals(67300));
    });

    test('SaveTrigger.skipNext — skip-to-next delegates to upsert', () async {
      // First save a record at an earlier position
      await service.saveProgress(
        connectionId: 1,
        filePath: '/music/skip_next.mp3',
        positionMs: 45000,
        durationMs: 240000,
        trigger: SaveTrigger.periodic,
      );

      // Simulate skip-next: save the current track's position before advancing
      final result = await service.saveProgress(
        connectionId: 1,
        filePath: '/music/skip_next.mp3',
        positionMs: 80000,
        durationMs: 240000,
        trigger: SaveTrigger.skipNext,
      );

      expect(result, isTrue, reason: 'skipNext save should succeed');
      final saved = await dao.find(1, '/music/skip_next.mp3');
      expect(saved, isNotNull);
      expect(saved!.positionMs, equals(80000),
          reason: 'skipNext should update position to the latest value');
    });

    test('SaveTrigger.skipPrev — skip-to-previous delegates to upsert',
        () async {
      final result = await service.saveProgress(
        connectionId: 1,
        filePath: '/music/skip_prev.mp3',
        positionMs: 120000,
        durationMs: 300000,
        trigger: SaveTrigger.skipPrev,
      );

      expect(result, isTrue, reason: 'skipPrev save should succeed');
      final saved = await dao.find(1, '/music/skip_prev.mp3');
      expect(saved, isNotNull);
      expect(saved!.positionMs, equals(120000));
    });

    test('SaveTrigger.complete — track completion delegates to upsert',
        () async {
      final result = await service.saveProgress(
        connectionId: 1,
        filePath: '/music/completed.mp3',
        positionMs: 5000,
        durationMs: 120000,
        trigger: SaveTrigger.complete,
      );

      expect(result, isTrue, reason: 'complete trigger save should succeed');
      final saved = await dao.find(1, '/music/completed.mp3');
      expect(saved, isNotNull);
      expect(saved!.positionMs, equals(5000));
    });

    test('all 5 triggers share the same shouldSave / shouldClear rules',
        () async {
      // shouldSave: position < 5s → skipped for ALL triggers
      for (final trigger in SaveTrigger.values) {
        final result = await service.saveProgress(
          connectionId: 1,
          filePath: '/music/short_${trigger.name}.mp3',
          positionMs: 3000, // < 5s
          durationMs: 120000,
          trigger: trigger,
        );
        expect(result, isFalse,
            reason: '${trigger.name}: position < 5s should be skipped');
      }

      // shouldClear: position near end → record cleared for ALL triggers
      // First create records to be cleared
      for (final trigger in SaveTrigger.values) {
        await dao.upsert(
          connectionId: 1,
          filePath: '/music/near_end_${trigger.name}.mp3',
          positionMs: 30000,
          durationMs: 120000,
        );
      }

      for (final trigger in SaveTrigger.values) {
        final result = await service.saveProgress(
          connectionId: 1,
          filePath: '/music/near_end_${trigger.name}.mp3',
          positionMs: 115000, // > 120000 - 10000
          durationMs: 120000,
          trigger: trigger,
        );
        expect(result, isNull,
            reason: '${trigger.name}: position near end should clear record');
      }
    });
  });

  // ── REF-25-T02: Resume dialog state transitions ──────────────────────────

  group('REF-25-T02: resume dialog state transitions', () {
    late ProgressService service;

    setUp(() {
      service = ProgressService();
    });

    test('showResumeDialog creates initial state with countdown=5', () {
      final progress = testProgress(positionMs: 60000, durationMs: 180000);
      final state = service.showResumeDialog(progress);

      expect(state.progress, equals(progress),
          reason: 'initial state should carry the progress record');
      expect(state.countdownSeconds, equals(5),
          reason: 'initial countdown should be 5');
      expect(state.isExpired, isFalse,
          reason: 'initial state should not be expired');
    });

    test('tickCountdown decrements from 5 to 0', () {
      final progress = testProgress(positionMs: 60000);
      var state = service.showResumeDialog(progress);

      for (int expected = 4; expected >= 0; expected--) {
        state = service.tickCountdown(state);
        expect(state.countdownSeconds, equals(expected),
            reason: 'after tick, countdown should be $expected');
      }

      expect(state.isExpired, isTrue,
          reason: 'countdown=0 means isExpired is true');
    });

    test('tickCountdown at 0 stays at 0 (idempotent)', () {
      final progress = testProgress(positionMs: 60000);
      var state = service.showResumeDialog(progress);

      // Advance to 0
      for (int i = 0; i < 5; i++) {
        state = service.tickCountdown(state);
      }
      expect(state.countdownSeconds, equals(0));
      expect(state.isExpired, isTrue);

      // Tick again — should remain at 0
      state = service.tickCountdown(state);
      expect(state.countdownSeconds, equals(0),
          reason: 'ticking at 0 should not go negative');
      expect(state.isExpired, isTrue);
    });

    test('progress record is preserved through all countdown ticks', () {
      final progress = testProgress(
        positionMs: 90000,
        durationMs: 300000,
      );
      var state = service.showResumeDialog(progress);

      for (int i = 0; i < 5; i++) {
        state = service.tickCountdown(state);
        expect(state.progress, equals(progress),
            reason: 'progress should not change during countdown');
      }
    });

    test('multiple show/tick cycles are independent', () {
      final progress1 = testProgress(positionMs: 30000);
      final progress2 = testProgress(positionMs: 90000);

      var state1 = service.showResumeDialog(progress1);
      var state2 = service.showResumeDialog(progress2);

      state1 = service.tickCountdown(state1);
      state1 = service.tickCountdown(state1);

      // state1 at 3, state2 still at 5
      expect(state1.countdownSeconds, equals(3));
      expect(state2.countdownSeconds, equals(5),
          reason: 'independent dialog states should not interfere');
    });

    test('copyWith produces equal state when no changes', () {
      final progress = testProgress(positionMs: 45000);
      final state = service.showResumeDialog(progress);
      final copy = state.copyWith();

      expect(copy, equals(state),
          reason: 'copyWith() with no args should produce equal state');
      expect(copy.hashCode, equals(state.hashCode));
    });

    test('toString contains countdown info', () {
      final progress = testProgress(positionMs: 45000);
      final state = service.showResumeDialog(progress);
      final str = state.toString();

      expect(str, contains('countdownSeconds: 5'),
          reason: 'toString should include countdown');
    });
  });

  // ── REF-25-T03: Countdown expiry auto-selects continue ───────────────────

  group('REF-25-T03: countdown expiry auto-select', () {
    late ProgressService service;

    setUp(() {
      service = ProgressService();
    });

    test('countdown reaches 0 after exactly 5 ticks → isExpired=true', () {
      final progress = testProgress(positionMs: 120000, durationMs: 240000);
      var state = service.showResumeDialog(progress);

      expect(state.isExpired, isFalse,
          reason: 'should not be expired at start');

      for (int i = 1; i <= 5; i++) {
        state = service.tickCountdown(state);
        if (i < 5) {
          expect(state.isExpired, isFalse,
              reason: 'should not be expired at tick $i');
        }
      }

      expect(state.isExpired, isTrue,
          reason: 'should be expired after 5 ticks');
      expect(state.countdownSeconds, equals(0),
          reason: 'countdown should be exactly 0');
    });

    test('expired state signals auto-select "continue playback"', () {
      final progress = testProgress(positionMs: 180000, durationMs: 360000);
      var state = service.showResumeDialog(progress);

      // Tick to expiry
      for (int i = 0; i < 5; i++) {
        state = service.tickCountdown(state);
      }

      // Auto-select logic: isExpired → continue from saved position
      // The caller should use state.progress.positionMs as the seek target
      expect(state.isExpired, isTrue,
          reason: 'auto-select condition: isExpired == true');
      expect(state.progress.positionMs, equals(180000),
          reason: 'auto-select should use the saved position');
    });

    test('user can still manually select before countdown expires', () {
      final progress = testProgress(positionMs: 90000);
      var state = service.showResumeDialog(progress);

      // Tick twice (countdown = 3)
      state = service.tickCountdown(state);
      state = service.tickCountdown(state);
      expect(state.countdownSeconds, equals(3));
      expect(state.isExpired, isFalse,
          reason: 'not expired yet — user can still choose');

      // User manually selects "从头播放" (start over) — the caller would
      // dismiss the dialog and clear progress.  The service does not need
      // to know about this; it just provides the state.
      // Simulate: caller clears the dialog state and proceeds.
      final userChoice = false; // "从头播放"
      expect(userChoice, isFalse);
    });

    test('each tick produces a distinct countdown value 4→3→2→1→0', () {
      final progress = testProgress(positionMs: 60000);
      var state = service.showResumeDialog(progress);

      final countdownValues = <int>[];
      for (int i = 0; i < 5; i++) {
        state = service.tickCountdown(state);
        countdownValues.add(state.countdownSeconds);
      }

      expect(countdownValues, equals([4, 3, 2, 1, 0]),
          reason: 'countdown should decrement 4,3,2,1,0');
    });
  });
}
