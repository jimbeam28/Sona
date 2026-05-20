// lib/features/playlist/widgets/playlist_track_item.dart
// A single row in the playlist track list showing file name and selection state.

import 'package:flutter/material.dart';

import '../../../shared/models/playlist.dart';

class PlaylistTrackItem extends StatelessWidget {
  final PlaylistTrack track;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  const PlaylistTrackItem({
    super.key,
    required this.track,
    this.selected = false,
    required this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: selected
          ? const Icon(Icons.check_circle, color: Colors.deepPurple)
          : const Icon(Icons.music_note, size: 40),
      title: Text(
        track.fileName,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      selected: selected,
      onTap: onTap,
      onLongPress: onLongPress,
    );
  }
}
