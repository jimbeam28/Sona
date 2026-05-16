// lib/features/timer/widgets/timer_button.dart
// Timer button and bottom-sheet menu — TMR-01 through TMR-05 UI.
//
// [TimerButton] shows the current timer state as an icon button that can
// be added to the player screen.  When inactive it shows a sandglass icon;
// when active it shows the remaining countdown or "播完停止".
//
// Tapping the button opens [TimerBottomSheet] with options:
//   - 5 分钟 / 10 分钟 / 15 分钟 (TMR-01)
//   - 播完当前 (TMR-02)
//   - 取消定时 (TMR-04, only shown when timer is active)

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../timer_provider.dart';
import '../../../core/services/timer_service.dart';

/// An icon button that shows the current timer state and opens a
/// bottom-sheet menu on tap.
///
/// Intended to be placed on the player screen toolbar.
///
/// TMR-T23: inactive state shows sandglass icon, no text.
/// TMR-T24: active duration timer shows remaining time text.
/// TMR-T25: afterCurrent mode shows "播完停止" label.
/// TMR-T26: tapping inactive button shows 4-option menu.
/// TMR-T27: tapping active button shows 5-option menu (incl. cancel).
class TimerButton extends ConsumerWidget {
  const TimerButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(timerStateProvider);
    final isActive = state != null;
    final isAfterCurrent = state?.mode == TimerMode.afterCurrent;

    // Resolve the display text.
    String? displayText;
    if (isAfterCurrent) {
      displayText = TimerService.afterCurrentLabel;
    } else if (isActive) {
      displayText = ref.watch(formattedRemainingProvider);
    }

    return IconButton(
      onPressed: () => _showBottomSheet(context, ref, isActive),
      icon: Icon(
        Icons.hourglass_bottom,
        color: isActive
            ? Theme.of(context).colorScheme.primary
            : null,
      ),
      tooltip: isActive ? (displayText ?? '定时中') : '定时',
    );
  }

  void _showBottomSheet(
    BuildContext context,
    WidgetRef ref,
    bool isActive,
  ) {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => TimerBottomSheet(isActive: isActive),
    );
  }
}

/// The bottom-sheet menu for selecting or cancelling a sleep timer.
///
/// Always shows: 5分钟 / 10分钟 / 15分钟 / 播完当前 (TMR-T26)
/// When timer is active, also shows: 取消定时 (TMR-T27)
class TimerBottomSheet extends ConsumerWidget {
  final bool isActive;

  const TimerBottomSheet({super.key, required this.isActive});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.6,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              '定时停止播放',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const Divider(height: 1),
          // Duration options (TMR-01)
          _TimerOptionTile(
            icon: Icons.timer,
            label: '5 分钟',
            onTap: () {
              ref.read(startDurationTimerProvider)(5);
              Navigator.of(context).pop();
            },
          ),
          _TimerOptionTile(
            icon: Icons.timer,
            label: '10 分钟',
            onTap: () {
              ref.read(startDurationTimerProvider)(10);
              Navigator.of(context).pop();
            },
          ),
          // Stop after current (TMR-02)
          _TimerOptionTile(
            icon: Icons.skip_next,
            label: '播完当前',
            onTap: () {
              ref.read(startAfterCurrentProvider)();
              Navigator.of(context).pop();
            },
          ),
          // Custom duration
          _TimerOptionTile(
            icon: Icons.more_time,
            label: '自定义',
            onTap: () {
              Navigator.of(context).pop();
              _showCustomTimerPicker(context, ref);
            },
          ),
          // Cancel option (TMR-04), only when active
          if (isActive) ...[
            const Divider(height: 1),
            _TimerOptionTile(
              icon: Icons.cancel,
              label: '取消定时',
              textColor: Colors.red,
              iconColor: Colors.red,
              onTap: () {
                ref.read(cancelTimerProvider)();
                Navigator.of(context).pop();
              },
            ),
          ],
          const SizedBox(height: 8),
        ],
          ),
        ),
      ),
    );
  }

  void _showCustomTimerPicker(BuildContext context, WidgetRef ref) {
    int selectedHours = 0;
    int selectedMinutes = 5;

    final fixedHourCtrl = FixedExtentScrollController(initialItem: selectedHours);
    final fixedMinuteCtrl = FixedExtentScrollController(initialItem: selectedMinutes);

    showModalBottomSheet(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            return SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Header: cancel / title / confirm
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx),
                          style: TextButton.styleFrom(foregroundColor: Colors.grey),
                          child: const Text('取消'),
                        ),
                        const Text(
                          '自定义时长',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                        TextButton(
                          onPressed: () {
                            final totalMinutes = selectedHours * 60 + selectedMinutes;
                            if (totalMinutes > 0) {
                              ref.read(startDurationTimerProvider)(totalMinutes);
                            }
                            Navigator.pop(ctx);
                          },
                          child: const Text('确认'),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  // Scroll pickers — hours : minutes
                  SizedBox(
                    height: 200,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // Hours
                        SizedBox(
                          width: 80,
                          child: ListWheelScrollView.useDelegate(
                            controller: fixedHourCtrl,
                            itemExtent: 40,
                            diameterRatio: 2.0,
                            physics: const FixedExtentScrollPhysics(),
                            onSelectedItemChanged: (index) {
                              setSheetState(() => selectedHours = index);
                            },
                            childDelegate: ListWheelChildBuilderDelegate(
                              childCount: 24,
                              builder: (context, index) {
                                return Center(
                                  child: Text(
                                    '$index',
                                    style: TextStyle(
                                      fontSize: 20,
                                      fontWeight: index == selectedHours
                                          ? FontWeight.bold
                                          : FontWeight.normal,
                                      color: index == selectedHours
                                          ? Theme.of(context).colorScheme.primary
                                          : null,
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                        const Text('小时', style: TextStyle(fontSize: 16)),
                        const SizedBox(width: 24),
                        // Minutes
                        SizedBox(
                          width: 80,
                          child: ListWheelScrollView.useDelegate(
                            controller: fixedMinuteCtrl,
                            itemExtent: 40,
                            diameterRatio: 2.0,
                            physics: const FixedExtentScrollPhysics(),
                            onSelectedItemChanged: (index) {
                              setSheetState(() => selectedMinutes = index);
                            },
                            childDelegate: ListWheelChildBuilderDelegate(
                              childCount: 60,
                              builder: (context, index) {
                                return Center(
                                  child: Text(
                                    index.toString().padLeft(2, '0'),
                                    style: TextStyle(
                                      fontSize: 20,
                                      fontWeight: index == selectedMinutes
                                          ? FontWeight.bold
                                          : FontWeight.normal,
                                      color: index == selectedMinutes
                                          ? Theme.of(context).colorScheme.primary
                                          : null,
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                        const Text('分钟', style: TextStyle(fontSize: 16)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

/// A single option tile in the timer bottom sheet.
class _TimerOptionTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? textColor;
  final Color? iconColor;

  const _TimerOptionTile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.textColor,
    this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: iconColor),
      title: Text(
        label,
        style: textColor != null ? TextStyle(color: textColor) : null,
      ),
      onTap: onTap,
    );
  }
}
