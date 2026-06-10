// lib/features/player/widgets/queue_button.dart
// Queue button for opening the playback queue sheet.

import 'package:flutter/material.dart';

/// Queue button for opening the playback queue sheet.
class QueueButton extends StatelessWidget {
  final VoidCallback onTap;

  const QueueButton({super.key, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onTap,
      icon: const Icon(Icons.queue_music),
      iconSize: 20,
      tooltip: '播放列表',
      visualDensity: VisualDensity.compact,
    );
  }
}
