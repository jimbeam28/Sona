// lib/features/player/player_screen.dart
// Placeholder player page for BRW-04.
//
// This screen is shown after the user taps an audio file in the Browser.
// It reads the current play queue from [currentPlayQueueProvider] and
// displays basic queue information.  The full Player module will replace
// this placeholder in a future feature cycle.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../browser/browser_provider.dart';

class PlayerPlaceholder extends ConsumerWidget {
  const PlayerPlaceholder({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final queue = ref.watch(currentPlayQueueProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(queue?.current.name ?? '播放器'),
        centerTitle: true,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.play_circle_outline,
                size: 80,
                color: Colors.grey,
              ),
              const SizedBox(height: 16),
              Text(
                queue?.current.name ?? '未选择文件',
                style: Theme.of(context).textTheme.titleMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                '播放器模块开发中...',
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: Colors.grey),
              ),
              if (queue != null) ...[
                const SizedBox(height: 16),
                Text(
                  '队列: ${queue.length} 个文件, '
                  '当前位置: ${queue.currentIndex + 1}/${queue.length}',
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: Colors.grey),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
