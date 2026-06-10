// lib/features/player/widgets/timer_control.dart
// Timer control button that shows remaining time when active.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../timer/domain/timer_service.dart';
import '../../timer/timer_provider.dart';
import '../../timer/widgets/timer_button.dart';

/// Timer control button that shows remaining time when active.
class TimerControl extends ConsumerWidget {
  const TimerControl({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(timerStateProvider);
    final isActive = state != null;
    final isAfterCurrent = state?.mode == TimerMode.afterCurrent;

    String? displayText;
    if (isAfterCurrent) {
      displayText = TimerService.afterCurrentLabel;
    } else if (isActive) {
      displayText = ref.watch(formattedRemainingProvider);
    }

    if (isActive && displayText != null) {
      return TextButton.icon(
        onPressed: () => _showTimerSheet(context, true),
        icon: Icon(Icons.timer,
            size: 18, color: Theme.of(context).colorScheme.primary),
        label: Text(
          displayText,
          style: TextStyle(
            fontFamily: 'monospace',
            fontSize: 13,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      );
    }

    return IconButton(
      onPressed: () => _showTimerSheet(context, false),
      icon: const Icon(Icons.timer),
      iconSize: 20,
      tooltip: '定时停止',
      visualDensity: VisualDensity.compact,
    );
  }

  void _showTimerSheet(BuildContext context, bool isActive) {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => TimerBottomSheet(isActive: isActive),
    );
  }
}
