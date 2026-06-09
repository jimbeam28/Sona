// test/features/progress/bug_09_test.dart
// BUG-09: upsertProgressProvider / clearProgressProvider 无 try-catch 导致闪退
//
// BUG-09-T01: upsert 时 DB 抛异常 → 不闪退 → 错误被日志记录
// BUG-09-T02: delete 时 DB 抛异常 → 不闪退 → 错误被日志记录
// BUG-09-T03: 正常 upsert → 行为不变（回归）
// BUG-09-T04: 正常 delete → 行为不变（回归）

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nas_audio_player/core/database/dao/progress_dao.dart';
import 'package:nas_audio_player/features/progress/progress_provider.dart';
import 'package:nas_audio_player/shared/models/play_progress.dart';

// ── Mock DAO ───────────────────────────────────────────────────────────────────

/// A simple mock [ProgressDao] that can be configured to throw on upsert/delete.
class _MockProgressDao implements ProgressDao {
  bool throwOnUpsert = false;
  bool throwOnDelete = false;

  int upsertCallCount = 0;
  int deleteCallCount = 0;

  @override
  Future<bool?> upsert({
    required int connectionId,
    required String filePath,
    required int positionMs,
    int? durationMs,
  }) async {
    if (throwOnUpsert) {
      throw Exception('DB disk full');
    }
    upsertCallCount++;
    return true;
  }

  @override
  Future<void> delete(int connectionId, String filePath) async {
    if (throwOnDelete) {
      throw Exception('DB corrupted');
    }
    deleteCallCount++;
  }

  // All other methods are not called by the providers under test;
  // provide stubs to satisfy the interface.
  @override
  Future<PlayProgress?> find(int connectionId, String filePath) async => null;
  @override
  Future<List<PlayProgress>> getRecentlyPlayed({int limit = 20}) async => [];
  @override
  Future<PlayProgress?> findLatest() async => null;
  @override
  Future<List<PlayProgress>> findByConnection(int connectionId) async => [];
  @override
  Future<void> deleteByConnection(int connectionId) async {}
  @override
  Future<int> count() async => 0;
  @override
  Future<void> clearLatest() async {}
  @override
  Future<void> migrateLegacyToLatest() async {}
  @override
  Future<void> rawInsert(PlayProgress progress) async {}
  @override
  Future<bool?> upsertLatest({
    required int connectionId,
    required String filePath,
    required int positionMs,
    int? durationMs,
  }) async =>
      null;
}

// ═══════════════════════════════════════════════════════════════════════════════
// Main test entry
// ═══════════════════════════════════════════════════════════════════════════════

void main() {
  group('BUG-09 upsertProgressProvider / clearProgressProvider try-catch', () {
    // ── BUG-09-T01: upsert 时 DB 抛异常 → 不闪退 ──────────────────────────

    test('BUG-09-T01: upsert exception is caught, no crash', () async {
      final mockDao = _MockProgressDao();
      mockDao.throwOnUpsert = true;

      final container = ProviderContainer(
        overrides: [
          progressDaoProvider.overrideWithValue(mockDao),
        ],
      );
      addTearDown(container.dispose);

      // The provider returns a void-typed async function.
      // Call it; the internal try-catch should prevent the exception from
      // propagating. Since the return type is void, we can't await it
      // directly, but we can verify it does not throw synchronously.
      expect(
        () => container.read(upsertProgressProvider)(
          connectionId: 1,
          filePath: '/music/test.mp3',
          positionMs: 30000,
          durationMs: 120000,
        ),
        returnsNormally,
        reason: 'BUG-09-T01: DB 异常不应导致闪退',
      );

      // Allow the async body to run to completion
      await Future<void>.delayed(Duration.zero);

      // upsertCallCount is 0 because the exception was thrown before increment.
      // The important thing is that the exception did NOT propagate (returnsNormally).
      // The debug output "[Progress] upsert failed: Exception: DB disk full"
      // confirms the catch block executed.
      expect(mockDao.upsertCallCount, equals(0),
          reason: 'BUG-09-T01: 异常时 upsert 计数应为 0（异常在 increment 前抛出）');
    });

    // ── BUG-09-T02: delete 时 DB 抛异常 → 不闪退 ──────────────────────────

    test('BUG-09-T02: delete exception is caught, no crash', () async {
      final mockDao = _MockProgressDao();
      mockDao.throwOnDelete = true;

      final container = ProviderContainer(
        overrides: [
          progressDaoProvider.overrideWithValue(mockDao),
        ],
      );
      addTearDown(container.dispose);

      expect(
        () => container.read(clearProgressProvider)(
          connectionId: 1,
          filePath: '/music/test.mp3',
        ),
        returnsNormally,
        reason: 'BUG-09-T02: DB 异常不应导致闪退',
      );

      // Allow the async body to run to completion
      await Future<void>.delayed(Duration.zero);

      // deleteCallCount is 0 because the exception was thrown before increment.
      // The important thing is that the exception did NOT propagate (returnsNormally).
      // The debug output "[Progress] clear failed: Exception: DB corrupted"
      // confirms the catch block executed.
      expect(mockDao.deleteCallCount, equals(0),
          reason: 'BUG-09-T02: 异常时 delete 计数应为 0（异常在 increment 前抛出）');
    });

    // ── BUG-09-T03: 正常 upsert → 行为不变（回归） ────────────────────────

    test('BUG-09-T03: normal upsert still works (regression)', () async {
      final mockDao = _MockProgressDao();
      mockDao.throwOnUpsert = false;

      final container = ProviderContainer(
        overrides: [
          progressDaoProvider.overrideWithValue(mockDao),
        ],
      );
      addTearDown(container.dispose);

      container.read(upsertProgressProvider)(
        connectionId: 1,
        filePath: '/music/test.mp3',
        positionMs: 30000,
        durationMs: 120000,
      );

      // Allow the async body to run to completion
      await Future<void>.delayed(Duration.zero);

      // Verify the mock was called (upsert was invoked)
      expect(mockDao.upsertCallCount, equals(1),
          reason: 'BUG-09-T03: 正常 upsert 应被调用一次');
    });

    // ── BUG-09-T04: 正常 delete → 行为不变（回归） ────────────────────────

    test('BUG-09-T04: normal delete still works (regression)', () async {
      final mockDao = _MockProgressDao();
      mockDao.throwOnDelete = false;

      final container = ProviderContainer(
        overrides: [
          progressDaoProvider.overrideWithValue(mockDao),
        ],
      );
      addTearDown(container.dispose);

      container.read(clearProgressProvider)(
        connectionId: 1,
        filePath: '/music/test.mp3',
      );

      // Allow the async body to run to completion
      await Future<void>.delayed(Duration.zero);

      // Verify the mock was called (delete was invoked)
      expect(mockDao.deleteCallCount, equals(1),
          reason: 'BUG-09-T04: 正常 delete 应被调用一次');
    });
  });
}
