// lib/features/timer/widgets/timer_button.dart
// Timer bottom-sheet menu — TMR-01 through TMR-05 UI.
//
// The bottom-sheet menu with options:
//   - 5 分钟 / 10 分钟 / 15 分钟 (TMR-01)
//   - 播完当前 (TMR-02)
//   - 取消定时 (TMR-04, only shown when timer is active)

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../timer_provider.dart';

/// The bottom-sheet menu for selecting or cancelling a sleep timer.
///
/// Always shows: 5分钟 / 10分钟 / 15分钟 / 播完当前 (TMR-T26)
/// When timer is active, also shows: 取消定时 (TMR-T27)
class TimerBottomSheet extends ConsumerWidget {
  final bool isActive;

  const TimerBottomSheet({super.key, required this.isActive});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lastCustomMinutes = ref.watch(lastCustomTimerMinutesProvider);

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
              if (lastCustomMinutes != null)
                _TimerOptionTile(
                  icon: Icons.history,
                  label: '上次时长（${_formatMinutesLabel(lastCustomMinutes)}）',
                  onTap: () {
                    ref.read(startDurationTimerProvider)(lastCustomMinutes);
                    Navigator.of(context).pop();
                  },
                ),
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
              _TimerOptionTile(
                icon: Icons.timer,
                label: '15 分钟',
                onTap: () {
                  ref.read(startDurationTimerProvider)(15);
                  Navigator.of(context).pop();
                },
              ),
              _TimerOptionTile(
                icon: Icons.skip_next,
                label: '播完当前',
                onTap: () {
                  ref.read(startAfterCurrentProvider)();
                  Navigator.of(context).pop();
                },
              ),
              _TimerOptionTile(
                icon: Icons.more_time,
                label: '自定义',
                onTap: () {
                  // Capture root navigator context BEFORE popping the timer sheet,
                  // otherwise the context becomes invalid and the custom picker
                  // sheet shows in a broken state (confirm button won't work).
                  final rootCtx =
                      Navigator.of(context, rootNavigator: true).context;
                  Navigator.of(context).pop();
                  showModalBottomSheet<void>(
                    context: rootCtx,
                    builder: (_) => const _CustomTimerPickerSheet(),
                  );
                },
              ),
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
}

class _CustomTimerPickerSheet extends ConsumerStatefulWidget {
  const _CustomTimerPickerSheet();

  @override
  ConsumerState<_CustomTimerPickerSheet> createState() =>
      _CustomTimerPickerSheetState();
}

class _CustomTimerPickerSheetState
    extends ConsumerState<_CustomTimerPickerSheet> {
  static const int _initialHours = 0;
  static const int _initialMinutes = 5;

  late int _selectedHours;
  late int _selectedMinutes;
  late final FixedExtentScrollController _hourController;
  late final FixedExtentScrollController _minuteController;

  int get _totalMinutes => _selectedHours * 60 + _selectedMinutes;

  @override
  void initState() {
    super.initState();
    _selectedHours = _initialHours;
    _selectedMinutes = _initialMinutes;
    _hourController = FixedExtentScrollController(initialItem: _selectedHours);
    _minuteController =
        FixedExtentScrollController(initialItem: _selectedMinutes);
  }

  @override
  void dispose() {
    _hourController.dispose();
    _minuteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  style: TextButton.styleFrom(foregroundColor: Colors.grey),
                  child: const Text('取消'),
                ),
                const Text(
                  '自定义时长',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                TextButton(
                  onPressed: _totalMinutes == 0
                      ? null
                      : () {
                          ref.read(setLastCustomTimerMinutesProvider)(
                            _totalMinutes,
                          );
                          ref.read(startDurationTimerProvider)(_totalMinutes);
                          Navigator.pop(context);
                        },
                  child: const Text('确认'),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          SizedBox(
            height: 200,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  width: 80,
                  child: ListWheelScrollView.useDelegate(
                    controller: _hourController,
                    itemExtent: 40,
                    diameterRatio: 2.0,
                    physics: const FixedExtentScrollPhysics(),
                    onSelectedItemChanged: (index) {
                      setState(() => _selectedHours = index);
                    },
                    childDelegate: ListWheelChildBuilderDelegate(
                      childCount: 24,
                      builder: (context, index) {
                        return Center(
                          child: Text(
                            '$index',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: index == _selectedHours
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                              color: index == _selectedHours
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
                SizedBox(
                  width: 80,
                  child: ListWheelScrollView.useDelegate(
                    controller: _minuteController,
                    itemExtent: 40,
                    diameterRatio: 2.0,
                    physics: const FixedExtentScrollPhysics(),
                    onSelectedItemChanged: (index) {
                      setState(() => _selectedMinutes = index);
                    },
                    childDelegate: ListWheelChildBuilderDelegate(
                      childCount: 60,
                      builder: (context, index) {
                        return Center(
                          child: Text(
                            index.toString().padLeft(2, '0'),
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: index == _selectedMinutes
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                              color: index == _selectedMinutes
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
  }
}

String _formatMinutesLabel(int minutes) {
  final hours = minutes ~/ 60;
  final remainingMinutes = minutes % 60;
  if (hours == 0) return '$remainingMinutes分钟';
  if (remainingMinutes == 0) return '$hours小时';
  return '$hours小时$remainingMinutes分钟';
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
