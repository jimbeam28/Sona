// lib/features/player/widgets/speed_control.dart
// Speed display button with speed selector dialog.
// PLY-T17.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';

import '../../../shared/di/providers.dart';
import '../player_provider.dart';

/// Speed display button with speed selector dialog.
/// PLY-T17.
class SpeedControl extends ConsumerWidget {
  const SpeedControl({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final player = ref.watch(audioPlayerProvider);

    return StreamBuilder<double>(
      stream: player.speedStream,
      builder: (context, snapshot) {
        final currentSpeed = snapshot.data ?? 1.0;

        return OutlinedButton.icon(
          onPressed: () =>
              _showSpeedSelector(context, ref, player, currentSpeed),
          icon: const Icon(Icons.speed, size: 20),
          label: Text('${currentSpeed}x'),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          ),
        );
      },
    );
  }

  void _showSpeedSelector(
    BuildContext context,
    WidgetRef ref,
    AudioPlayer player,
    double currentSpeed,
  ) {
    showModalBottomSheet<double>(
      context: context,
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  '播放速度',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const Divider(height: 1),
              ...speedOptions.map((speed) {
                final isSelected = (speed - currentSpeed).abs() < 0.01;
                return ListTile(
                  leading: isSelected
                      ? Icon(Icons.check,
                          color: Theme.of(context).colorScheme.primary)
                      : const SizedBox(width: 24),
                  title: Text('${speed}x'),
                  trailing: isSelected
                      ? Text('当前',
                          style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(context).colorScheme.primary,
                          ))
                      : null,
                  onTap: () {
                    player.setSpeed(speed);
                    ref.read(currentSpeedProvider.notifier).state = speed;
                    // F-4: if "remember speed" is on, update the default too.
                    if (ref.read(rememberSpeedProvider)) {
                      ref.read(setDefaultSpeedProvider)(speed);
                    }
                    Navigator.of(ctx).pop();
                  },
                );
              }),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }
}
