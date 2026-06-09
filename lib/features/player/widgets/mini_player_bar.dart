// lib/features/player/widgets/mini_player_bar.dart
// PLY-08: 迷你播放器 — a compact player bar shown at the bottom of the
// Browser screen when audio is loaded/playing.
//
// Shows:
//   - Current track name (MediaItem.title, truncated)
//   - Thin progress bar
//   - Play/pause button
//   - Queue list button
//   - Tap body → navigate to full player page (/player)
//
// Visibility: only shown when currentPlayQueueProvider is non-null (audio
// has been loaded).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:just_audio/just_audio.dart';

import '../../timer/domain/timer_service.dart';
import '../../../shared/models/play_queue.dart';
import '../../browser/browser_provider.dart';
import '../../timer/timer_provider.dart';
import '../player_provider.dart';
import 'queue_sheet.dart';

/// A compact player bar displayed at the bottom of the Browser screen.
///
/// Shows basic playback info and controls so the user can manage playback
/// without leaving the Browser.  Tapping the body area navigates to the
/// full player screen.
class MiniPlayerBar extends ConsumerWidget {
  const MiniPlayerBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final queue = ref.watch(currentPlayQueueProvider);

    // Only visible when audio has been loaded (queue is non-null).
    if (queue == null || queue.length == 0) {
      return const SizedBox.shrink();
    }

    final player = ref.watch(audioPlayerProvider);
    // F-3: watch timer state so users can see countdown from the browser.
    final timerState = ref.watch(timerStateProvider);
    final timerDisplay =
        timerState != null ? ref.watch(formattedRemainingProvider) : null;
    final isAfterCurrent = timerState?.mode == TimerMode.afterCurrent;

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 4,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 64,
          child: Material(
            color: Colors.transparent,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Column(
                children: [
                  // Thin progress bar at the very top
                  _MiniProgressBar(player: player),
                  // Track name + controls row
                  Expanded(
                    child: Row(
                      children: [
                        // Track info (name) — only tapping the title navigates
                        Expanded(
                          child: GestureDetector(
                            onTap: () => GoRouter.of(context).push('/player'),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    queue.current.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style:
                                        Theme.of(context).textTheme.bodyMedium,
                                  ),
                                ),
                                // F-3: timer countdown indicator
                                if (timerState != null) ...[
                                  const SizedBox(width: 4),
                                  Icon(
                                    Icons.timer,
                                    size: 14,
                                    color:
                                        Theme.of(context).colorScheme.primary,
                                  ),
                                  const SizedBox(width: 2),
                                  Text(
                                    isAfterCurrent
                                        ? TimerService.afterCurrentLabel
                                        : (timerDisplay ?? ''),
                                    style: TextStyle(
                                      fontSize: 11,
                                      color:
                                          Theme.of(context).colorScheme.primary,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                        // Play/pause button
                        _PlayPauseButton(player: player),
                        // Queue list button
                        IconButton(
                          onPressed: () => _showQueueSheet(context, ref, queue),
                          icon: const Icon(Icons.queue_music),
                          iconSize: 28,
                          tooltip: '播放列表',
                          visualDensity: VisualDensity.standard,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Queue sheet ─────────────────────────────────────────────────────────────

void _showQueueSheet(BuildContext context, WidgetRef ref, PlayQueue queue) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => QueueSheet(
      queue: queue,
      errorMessage: '无法加载音频，请检查连接配置',
      onSelectIndex: (index) async {
        final loaded = await ref.read(selectQueueIndexProvider)(index);
        return loaded.isLoaded;
      },
      onRemoveIndex: (index) {
        ref.read(removeTrackFromQueueProvider)(index);
      },
    ),
  );
}

// ── Thin progress bar ──────────────────────────────────────────────────────────

/// A thin (2px) linear progress indicator that reflects playback position.
class _MiniProgressBar extends StatelessWidget {
  final AudioPlayer player;

  const _MiniProgressBar({required this.player});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Duration>(
      stream: player.positionStream,
      builder: (context, posSnapshot) {
        final position = posSnapshot.data ?? Duration.zero;

        return StreamBuilder<Duration?>(
          stream: player.durationStream,
          builder: (context, durSnapshot) {
            final duration = durSnapshot.data;
            if (duration == null || duration == Duration.zero) {
              return const SizedBox(height: 2);
            }

            final value = position.inMilliseconds / duration.inMilliseconds;
            final clamped = value.clamp(0.0, 1.0);

            return SizedBox(
              height: 2,
              child: LinearProgressIndicator(
                value: clamped,
                minHeight: 2,
                backgroundColor:
                    Theme.of(context).colorScheme.surfaceContainerHighest,
                valueColor: AlwaysStoppedAnimation<Color>(
                  Theme.of(context).colorScheme.primary,
                ),
              ),
            );
          },
        );
      },
    );
  }
}

// ── Play / Pause button ────────────────────────────────────────────────────────

class _PlayPauseButton extends StatelessWidget {
  final AudioPlayer player;

  const _PlayPauseButton({required this.player});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<PlayerState>(
      stream: player.playerStateStream,
      builder: (context, snapshot) {
        final isPlaying = snapshot.data?.playing ?? false;
        return IconButton(
          onPressed: () {
            if (isPlaying) {
              player.pause();
            } else if (player.processingState == ProcessingState.idle) {
              // PLY-02: if source is already loaded (e.g. after notification
              // stop), call play() directly instead of navigating.
              if (player.audioSource != null) {
                player.play();
              } else {
                GoRouter.of(context).push('/player');
              }
            } else {
              if (player.processingState == ProcessingState.completed) {
                player.seek(Duration.zero);
              }
              player.play();
            }
          },
          icon: Icon(isPlaying ? Icons.pause : Icons.play_arrow),
          iconSize: 32,
          tooltip: isPlaying ? '暂停' : '播放',
          visualDensity: VisualDensity.standard,
        );
      },
    );
  }
}
