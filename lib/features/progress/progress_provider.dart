// lib/features/progress/progress_provider.dart
// Riverpod providers for the Progress feature.
//
// Manages playback-progress persistence and resume-dialog state.
//
// PRG-01: 自动保存播放进度 — upsertProgressProvider triggers UPSERT
// PRG-02: 启动时恢复播放进度 — progressForFileProvider queries by (connectionId, filePath)
// PRG-03: 进度恢复确认提示 — ProgressResumeNotifier manages the 5-second countdown
// PRG-04: 清除单个文件进度 — clearProgressProvider deletes a single record

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/database/dao/progress_dao.dart';
import '../../shared/models/play_progress.dart';
import 'domain/progress_service.dart';

// ── DAO instance ────────────────────────────────────────────────────────────────

/// Singleton [ProgressDao] used by all progress providers.
///
/// Can be overridden in tests to inject a DAO backed by an in-memory database.
final progressDaoProvider = Provider<ProgressDao>((ref) => ProgressDao());

// ── ProgressService instance ─────────────────────────────────────────────────────

/// Singleton [ProgressService] that encapsulates business logic for progress
/// persistence and the resume-dialog state machine.
///
/// Delegates to [ProgressDao] (injected via [progressDaoProvider]) for data access.
final progressServiceProvider = Provider<ProgressService>((ref) {
  return ProgressService(dao: ref.read(progressDaoProvider));
});

// ── PRG-01 / PRG-02: Query & mutate progress ───────────────────────────────────

/// Returns the saved playback progress for a given file on a given connection,
/// or `null` when no record exists (PRG-T11, PRG-T12).
final progressForFileProvider =
    FutureProvider.family<PlayProgress?, ({int connectionId, String filePath})>(
  (ref, key) async {
    final service = ref.watch(progressServiceProvider);
    return service.getProgress(key.connectionId, key.filePath);
  },
);

/// Returns recently played progress records, ordered by last_played_at DESC
/// (PRG-T16).
final recentlyPlayedProvider =
    FutureProvider.family<List<PlayProgress>, int?>((ref, limit) async {
  final dao = ref.watch(progressDaoProvider);
  return dao.getRecentlyPlayed(limit: limit ?? 20);
});

/// Returns the most recently played progress record, or `null` when none
/// exists. Used during app startup to restore the current track's position.
final latestPlayedProgressProvider = FutureProvider<PlayProgress?>((ref) async {
  final dao = ref.watch(progressDaoProvider);
  return dao.findLatest();
});

/// Action provider: upserts (or clears) playback progress.
///
/// Handles PRG-T03 (skip if < 5 s) and PRG-T04 (clear if near end)
/// via [ProgressService.saveProgress].  Callers pass the raw playback state and
/// the service handles the business rules.
final upsertProgressProvider = Provider<
    void Function({
      required int connectionId,
      required String filePath,
      required int positionMs,
      int? durationMs,
    })>((ref) {
  return ({
    required int connectionId,
    required String filePath,
    required int positionMs,
    int? durationMs,
  }) async {
    final service = ref.read(progressServiceProvider);
    debugPrint('[Progress] upsert: file=$filePath pos=${positionMs}ms'
        ' dur=${durationMs ?? 'null'}ms');
    try {
      await service.saveProgress(
        connectionId: connectionId,
        filePath: filePath,
        positionMs: positionMs,
        durationMs: durationMs,
      );
    } catch (e) {
      debugPrint('[Progress] upsert failed: $e');
      return;
    }
    // Invalidate the query providers so UI refreshes
    ref.invalidate(progressForFileProvider((
      connectionId: connectionId,
      filePath: filePath,
    )));
    ref.invalidate(recentlyPlayedProvider(null));
    ref.invalidate(latestPlayedProgressProvider);
  };
});

/// Action provider: deletes a single progress record (PRG-T26, PRG-T28).
final clearProgressProvider = Provider<
    void Function({
      required int connectionId,
      required String filePath,
    })>((ref) {
  return ({
    required int connectionId,
    required String filePath,
  }) async {
    final service = ref.read(progressServiceProvider);
    debugPrint('[Progress] clear: file=$filePath');
    try {
      await service.clearProgress(connectionId, filePath);
    } catch (e) {
      debugPrint('[Progress] clear failed: $e');
      return;
    }
    // Invalidate so the UI refreshes
    ref.invalidate(progressForFileProvider((
      connectionId: connectionId,
      filePath: filePath,
    )));
    ref.invalidate(recentlyPlayedProvider(null));
    ref.invalidate(latestPlayedProgressProvider);
  };
});

// ── PRG-03: Resume dialog state ─────────────────────────────────────────────────

/// Manages the countdown timer for the resume dialog.
///
/// When the dialog appears, the countdown starts at 5 and decrements
/// every second.  When it reaches 0 the dialog auto-selects "继续播放".
///
/// Delegates state creation and countdown logic to [ProgressService].
class ProgressResumeNotifier extends StateNotifier<ResumeDialogState?> {
  final ProgressService _service;
  Timer? _timer;

  ProgressResumeNotifier(this._service) : super(null);

  /// Shows the resume dialog with [progress] and starts the countdown.
  void show(PlayProgress progress) {
    _cancelTimer();
    debugPrint('[Progress] resumeDialog: show ${progress.formattedPosition}');
    state = _service.showResumeDialog(progress);

    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (state == null) {
        _cancelTimer();
        return;
      }
      final next = _service.tickCountdown(state!);
      if (next.isExpired) {
        state = next;
        _cancelTimer();
      } else {
        state = next;
      }
    });
  }

  /// Dismisses the dialog and cancels the timer.
  void dismiss() {
    _cancelTimer();
    state = null;
  }

  void _cancelTimer() {
    _timer?.cancel();
    _timer = null;
  }

  @override
  void dispose() {
    _cancelTimer();
    super.dispose();
  }
}

/// Provider for the resume-dialog state.
///
/// The Browser page reads this to decide whether to show the dialog,
/// and the dialog widget reads/writes it to manage the countdown.
final progressResumeProvider =
    StateNotifierProvider<ProgressResumeNotifier, ResumeDialogState?>((ref) {
  return ProgressResumeNotifier(ref.read(progressServiceProvider));
});
