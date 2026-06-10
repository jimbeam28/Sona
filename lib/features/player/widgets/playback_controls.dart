// lib/features/player/widgets/playback_controls.dart
// Row of playback controls: previous, skip backward, play/pause, skip forward, next.
// PLY-T55~T56.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';

import '../../../shared/models/play_queue.dart';
import '../../../shared/di/providers.dart';
import '../domain/seek_utils.dart';
import '../player_provider.dart';

/// Row of playback controls: previous, skip backward, play/pause, skip forward, next.
/// PLY-T55~T56.
class PlaybackControls extends ConsumerWidget {
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  const PlaybackControls({
    super.key,
    this.onPrevious,
    this.onNext,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final player = ref.watch(audioPlayerProvider);
    final seekStep = ref.watch(seekStepProvider);
    final queue = ref.watch(currentPlayQueueProvider);
    final mode = ref.watch(playModeProvider);

    // PLY-01: use deterministic shuffle methods for shuffle mode
    final prevIdx = queue != null
        ? (mode == PlayMode.shuffle
            ? queue.previousShuffleIndex()
            : PlayQueue.previousIndex(queue.currentIndex, queue.length, mode))
        : null;
    final nextIdx = queue != null
        ? (mode == PlayMode.shuffle
            ? queue.nextShuffleIndex()
            : PlayQueue.nextIndex(queue.currentIndex, queue.length, mode))
        : null;

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // Previous track
        _buildSkipButton(
          icon: Icons.skip_previous,
          tooltip: '上一首',
          enabled: prevIdx != null,
          onPressed: prevIdx != null ? onPrevious : null,
        ),
        const SizedBox(width: 8),
        // Skip backward
        _buildSeekButton(
          seconds: seekStep,
          tooltip: '后退 ${seekStep}s',
          onPressed: () {
            final position = player.position;
            final skipTarget = skipBackward(position, seconds: seekStep);
            player.seek(skipTarget);
          },
        ),
        const SizedBox(width: 24),
        // Play / Pause
        StreamBuilder<PlayerState>(
          stream: player.playerStateStream,
          builder: (context, snapshot) {
            final isPlaying = snapshot.data?.playing ?? false;
            return IconButton.filled(
              onPressed: () {
                if (isPlaying) {
                  player.pause();
                } else {
                  if (player.processingState == ProcessingState.completed) {
                    player.seek(Duration.zero);
                  }
                  player.play();
                }
              },
              iconSize: 64,
              icon: Icon(isPlaying ? Icons.pause : Icons.play_arrow),
              style: IconButton.styleFrom(
                minimumSize: const Size(80, 80),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(40),
                ),
              ),
            );
          },
        ),
        const SizedBox(width: 24),
        // Skip forward
        _buildSeekButton(
          seconds: seekStep,
          tooltip: '前进 ${seekStep}s',
          isForward: true,
          onPressed: () {
            final position = player.position;
            final duration = player.duration ?? Duration.zero;
            final skipTarget =
                skipForward(position, duration, seconds: seekStep);
            player.seek(skipTarget);
          },
        ),
        const SizedBox(width: 8),
        // Next track
        _buildSkipButton(
          icon: Icons.skip_next,
          tooltip: '下一首',
          enabled: nextIdx != null,
          onPressed: nextIdx != null ? onNext : null,
        ),
      ],
    );
  }

  Widget _buildSeekButton({
    required int seconds,
    String? tooltip,
    bool enabled = true,
    bool isForward = false,
    VoidCallback? onPressed,
  }) {
    return InkWell(
      onTap: enabled ? onPressed : null,
      borderRadius: BorderRadius.circular(24),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildSeekIcon(
              seconds: seconds,
              isForward: isForward,
              enabled: enabled,
            ),
            Text(
              '${seconds}s',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: enabled ? null : Colors.grey,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSeekIcon({
    required int seconds,
    required bool isForward,
    required bool enabled,
  }) {
    final color = enabled ? null : Colors.grey;
    final icon = Icon(Icons.replay, size: 28, color: color);

    if (isForward) {
      return Transform(
        alignment: Alignment.center,
        transform: Matrix4.diagonal3Values(-1, 1, 1),
        child: icon,
      );
    }

    return icon;
  }

  Widget _buildSkipButton({
    required IconData icon,
    String? tooltip,
    bool enabled = true,
    VoidCallback? onPressed,
  }) {
    return IconButton(
      onPressed: onPressed,
      iconSize: 36,
      icon: Icon(icon),
      tooltip: tooltip,
      color: enabled ? null : Colors.grey,
      disabledColor: Colors.grey,
    );
  }
}
