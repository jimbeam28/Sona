// lib/features/player/widgets/now_playing_icon.dart
// Animated music icon that pulses while playing.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';

import '../player_provider.dart';

/// Animated music icon that pulses while playing.
class NowPlayingIcon extends ConsumerWidget {
  const NowPlayingIcon({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final player = ref.watch(audioPlayerProvider);

    return StreamBuilder<PlayerState>(
      stream: player.playerStateStream,
      builder: (context, snapshot) {
        final isPlaying = snapshot.data?.playing ?? false;
        return Icon(
          Icons.music_note,
          size: 120,
          color: isPlaying
              ? Theme.of(context).colorScheme.primary
              : Colors.grey[400],
        );
      },
    );
  }
}
