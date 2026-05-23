// lib/features/progress/progress_provider.dart
// Riverpod providers for the Progress feature.
//
// Manages playback-progress persistence and resume-dialog state.
//
// PRG-01: 自动保存播放进度 — upsertProgressProvider triggers UPSERT
// PRG-02: 启动时恢复播放进度 — progressForFileProvider queries by (connectionId, filePath)
// PRG-03: 进度恢复确认提示 — ProgressResumeState manages the 5-second countdown
// PRG-04: 清除单个文件进度 — clearProgressProvider deletes a single record

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/database/dao/progress_dao.dart';
import '../../shared/models/play_progress.dart';

// ── DAO instance ────────────────────────────────────────────────────────────────

/// Singleton [ProgressDao] used by all progress providers.
///
/// Can be overridden in tests to inject a DAO backed by an in-memory database.
final progressDaoProvider = Provider<ProgressDao>((ref) => ProgressDao());

// ── PRG-01 / PRG-02: Query & mutate progress ───────────────────────────────────

/// Returns the saved playback progress for a given file on a given connection,
/// or `null` when no record exists (PRG-T11, PRG-T12).
final progressForFileProvider =
    FutureProvider.family<PlayProgress?, ({int connectionId, String filePath})>(
  (ref, key) async {
    final dao = ref.watch(progressDaoProvider);
    return dao.find(key.connectionId, key.filePath);
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
/// via [ProgressDao.upsert].  Callers pass the raw playback state and
/// the DAO handles the business rules.
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
    final dao = ref.read(progressDaoProvider);
    debugPrint('[Progress] upsert: file=$filePath pos=${positionMs}ms'
        ' dur=${durationMs ?? 'null'}ms');
    // PRG-02: use composite-key UPSERT instead of single-record mode
    await dao.upsert(
      connectionId: connectionId,
      filePath: filePath,
      positionMs: positionMs,
      durationMs: durationMs,
    );
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
    final dao = ref.read(progressDaoProvider);
    debugPrint('[Progress] clear: file=$filePath');
    await dao.delete(connectionId, filePath);
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

/// State for the progress-resume confirmation dialog (PRG-03).
///
/// When playback progress exists for a file, the dialog displays the saved
/// position, two action buttons, and a 5-second auto-select countdown.
class ProgressResumeState {
  /// The saved progress record that triggered this dialog.
  final PlayProgress progress;

  /// Seconds remaining before auto-selecting "继续播放" (PRG-T21, PRG-T22).
  /// Starts at 5 and counts down to 0.
  final int countdownSeconds;

  const ProgressResumeState({
    required this.progress,
    this.countdownSeconds = 5,
  });

  /// Whether the countdown has reached zero (auto-select triggered).
  bool get isExpired => countdownSeconds <= 0;

  ProgressResumeState copyWith({int? countdownSeconds}) {
    return ProgressResumeState(
      progress: progress,
      countdownSeconds: countdownSeconds ?? this.countdownSeconds,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ProgressResumeState &&
          progress == other.progress &&
          countdownSeconds == other.countdownSeconds;

  @override
  int get hashCode => Object.hash(progress, countdownSeconds);

  @override
  String toString() =>
      'ProgressResumeState(progress: $progress, countdownSeconds: $countdownSeconds)';
}

/// Manages the countdown timer for the resume dialog.
///
/// When the dialog appears, the countdown starts at 5 and decrements
/// every second.  When it reaches 0 the dialog auto-selects "继续播放".
class ProgressResumeNotifier extends StateNotifier<ProgressResumeState?> {
  Timer? _timer;

  ProgressResumeNotifier() : super(null);

  /// Shows the resume dialog with [progress] and starts the countdown.
  void show(PlayProgress progress) {
    _cancelTimer();
    debugPrint('[Progress] resumeDialog: show ${progress.formattedPosition}');
    state = ProgressResumeState(progress: progress);

    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (state == null) {
        _cancelTimer();
        return;
      }
      final next = state!.countdownSeconds - 1;
      if (next <= 0) {
        state = state!.copyWith(countdownSeconds: 0);
        _cancelTimer();
      } else {
        state = state!.copyWith(countdownSeconds: next);
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
    StateNotifierProvider<ProgressResumeNotifier, ProgressResumeState?>((ref) {
  return ProgressResumeNotifier();
});
