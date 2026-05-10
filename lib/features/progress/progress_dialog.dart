// lib/features/progress/progress_dialog.dart
// PRG-03: 进度恢复确认提示 — resume-confirmation dialog widget.
//
// Displays a dialog when the user taps a file that has saved playback
// progress.  Shows the saved position and two actions:
//   - "继续播放" — seek to saved position and play (auto-selected after 5 s)
//   - "从头播放" — start from beginning, delete the progress record
//
// The countdown is driven by [ProgressResumeNotifier].  When the countdown
// reaches 0 the dialog auto-selects "继续播放".

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/models/play_progress.dart';
import 'progress_provider.dart';

/// Shows the resume-confirmation dialog and returns the user's choice.
///
/// Returns `true` when the user chooses "继续播放" (resume from saved position),
/// `false` when the user chooses "从头播放" (start from beginning).
///
/// The dialog auto-closes after the notifier-triggered timeout.
/// The caller is responsible for dismissing the notifier state after
/// handling the result.
Future<bool?> showProgressResumeDialog(
  BuildContext context,
  ProviderContainer container,
  PlayProgress progress,
) {
  // Start the countdown in the notifier
  container.read(progressResumeProvider.notifier).show(progress);

  return showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => _ProgressResumeDialog(progress: progress),
  ).then((result) {
    // Clean up the notifier state when the dialog closes
    container.read(progressResumeProvider.notifier).dismiss();
    return result;
  });
}

/// Internal dialog widget that listens to [progressResumeProvider] for
/// the countdown and triggers auto-close when it expires.
class _ProgressResumeDialog extends ConsumerWidget {
  final PlayProgress progress;

  const _ProgressResumeDialog({required this.progress});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final resumeState = ref.watch(progressResumeProvider);

    // If the state was cleared externally or the dialog is no longer
    // relevant, pop with null.
    if (resumeState == null) {
      // Schedule pop after build to avoid build-during-build errors
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) Navigator.of(context).pop(null);
      });
      return const SizedBox.shrink();
    }

    // Auto-select "继续播放" when the countdown expires (PRG-T21)
    if (resumeState.isExpired && resumeState.countdownSeconds <= 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) Navigator.of(context).pop(true);
      });
    }

    final countdown = resumeState.countdownSeconds;

    return AlertDialog(
      title: const Text('恢复播放进度'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '上次播放到 ${progress.formattedPosition}',
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          const SizedBox(height: 8),
          Text(
            '是否从此处继续？',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('从头播放'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(
            countdown > 0 ? '继续播放 ($countdown)' : '继续播放',
          ),
        ),
      ],
    );
  }
}
