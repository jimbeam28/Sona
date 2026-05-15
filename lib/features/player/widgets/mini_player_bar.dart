// lib/features/player/widgets/mini_player_bar.dart
// PLY-08: 迷你播放器 — a compact player bar shown at the bottom of the
// Browser screen when audio is loaded/playing.
//
// Shows:
//   - Current track name (MediaItem.title, truncated)
//   - Thin progress bar
//   - Play/pause button
//   - Next track button
//   - Tap body → navigate to full player page (/player)
//
// Visibility: only shown when currentPlayQueueProvider is non-null (audio
// has been loaded).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:just_audio/just_audio.dart';

import '../../../core/services/audio_source_builder.dart';
import '../../../shared/models/play_queue.dart';
import '../../browser/browser_provider.dart';
import '../../connection/connection_provider.dart';
import '../player_provider.dart';

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
    final playMode = ref.watch(playModeProvider);

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
          height: 56,
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
                        GestureDetector(
                          onTap: () => GoRouter.of(context).push('/player'),
                          child: Expanded(
                            child: Text(
                              queue.current.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                          ),
                        ),
                        // Play/pause button
                        _PlayPauseButton(player: player),
                        // Next track button
                        _NextButton(
                          player: player,
                          queue: queue,
                          playMode: playMode,
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

            final value =
                position.inMilliseconds / duration.inMilliseconds;
            final clamped = value.clamp(0.0, 1.0);

            return SizedBox(
              height: 2,
              child: LinearProgressIndicator(
                value: clamped,
                minHeight: 2,
                backgroundColor: Theme.of(context)
                    .colorScheme
                    .surfaceContainerHighest,
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
            } else {
              player.play();
            }
          },
          icon: Icon(isPlaying ? Icons.pause : Icons.play_arrow),
          iconSize: 28,
          tooltip: isPlaying ? '暂停' : '播放',
          visualDensity: VisualDensity.compact,
        );
      },
    );
  }
}

// ── Next button ────────────────────────────────────────────────────────────────

class _NextButton extends ConsumerWidget {
  final AudioPlayer player;
  final PlayQueue queue;
  final PlayMode playMode;

  const _NextButton({
    required this.player,
    required this.queue,
    required this.playMode,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Determine whether a next track is available.
    final nextIdx = PlayQueue.nextIndex(
      queue.currentIndex,
      queue.length,
      playMode,
    );

    final hasNext = nextIdx != null;

    return IconButton(
      onPressed: hasNext
          ? () async {
              // Update the queue to point to the next track.
              final updatedQueue = queue.withIndex(nextIdx);
              ref.read(currentPlayQueueProvider.notifier).state = updatedQueue;
              // Load and play the next track directly (B-1).
              final conn = ref.read(activeConnectionProvider).valueOrNull;
              if (conn == null) return;
              final storage = ref.read(secureStorageProvider);
              final password = await storage.read(key: 'connection_password_${conn.id}');
              if (password == null || password.isEmpty) return;
              final source = AudioSourceBuilder.buildWithBasePath(
                baseUrl: conn.url,
                filePath: updatedQueue.current.path,
                username: conn.username,
                password: password,
              );
              await player.stop();
              await player.setAudioSource(source);
              await player.play();
            }
          : null,
      icon: const Icon(Icons.skip_next),
      iconSize: 28,
      tooltip: hasNext ? '下一首' : '没有下一首',
      visualDensity: VisualDensity.compact,
    );
  }
}
