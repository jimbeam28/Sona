// lib/features/player/widgets/play_mode_control.dart
// Play mode toggle button that cycles through modes and shows the
// corresponding icon.
//
// Modes cycle: sequential -> repeatOne -> repeatAll -> shuffle -> sequential ...

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../player_provider.dart';

/// Play mode toggle button that cycles through modes and shows the
/// corresponding icon.
///
/// Modes cycle: sequential -> repeatOne -> repeatAll -> shuffle -> sequential ...
class PlayModeControl extends ConsumerWidget {
  const PlayModeControl({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(playModeProvider);
    final nextMode = ref.watch(nextPlayModeProvider);

    return IconButton(
      onPressed: nextMode,
      icon: Icon(iconForPlayMode(mode)),
      iconSize: 20,
      tooltip: labelForPlayMode(mode),
      visualDensity: VisualDensity.compact,
    );
  }
}
