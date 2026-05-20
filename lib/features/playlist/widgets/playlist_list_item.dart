// lib/features/playlist/widgets/playlist_list_item.dart
// A single row in the playlist list showing name and track count.

import 'package:flutter/material.dart';

import '../../../shared/models/playlist.dart';

class PlaylistListItem extends StatelessWidget {
  final Playlist playlist;
  final VoidCallback onTap;

  const PlaylistListItem({
    super.key,
    required this.playlist,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const Icon(Icons.queue_music, size: 40),
      title: Text(
        playlist.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        '${playlist.trackCount} 首',
        style: Theme.of(context).textTheme.bodySmall,
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
}
