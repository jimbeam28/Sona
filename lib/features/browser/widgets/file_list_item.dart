// lib/features/browser/widgets/file_list_item.dart
// List-tile widgets for directory and audio-file entries in the browser.

import 'package:flutter/material.dart';

import '../../../shared/models/nas_file.dart';

/// Tap callback type for directory and file list items.
typedef FileItemTapCallback = void Function(NasFile file);

// ── Directory list tile ─────────────────────────────────────────────────────────

/// A [ListTile] representing a directory entry.
///
/// Displays a folder icon and the directory name.  [onTap] fires with the
/// [NasFile] when the user taps the tile.
class DirectoryListTile extends StatelessWidget {
  final NasFile file;
  final FileItemTapCallback? onTap;

  const DirectoryListTile({
    super.key,
    required this.file,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const Icon(Icons.folder_outlined, color: Colors.amber),
      title: Text(
        file.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap != null ? () => onTap!(file) : null,
    );
  }
}

// ── Audio file list tile ────────────────────────────────────────────────────────

/// A [ListTile] representing an audio file entry.
///
/// Displays an icon that distinguishes music from audiobook files,
/// the file name, and optionally the file size.  [onTap] fires with the
/// [NasFile] when the user taps the tile.
///
/// When [progressPercentage] is non-null, a thin progress bar is shown
/// at the bottom of the tile to indicate playback progress (BRW-T47).
class AudioFileListTile extends StatelessWidget {
  final NasFile file;
  final FileItemTapCallback? onTap;
  final VoidCallback? onLongPress;
  final double? progressPercentage;

  const AudioFileListTile({
    super.key,
    required this.file,
    this.onTap,
    this.onLongPress,
    this.progressPercentage,
  });

  IconData get _icon {
    switch (file.audioType) {
      case AudioFileType.audiobook:
        return Icons.headphones;
      case AudioFileType.music:
        return Icons.music_note_outlined;
      case null:
        return Icons.audio_file_outlined;
    }
  }

  Color get _iconColor {
    switch (file.audioType) {
      case AudioFileType.audiobook:
        return Colors.deepOrange;
      case AudioFileType.music:
        return Colors.blue;
      case null:
        return Colors.grey;
    }
  }

  String? get _sizeLabel {
    if (file.size == null) return null;
    final bytes = file.size!;
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    final tile = ListTile(
      leading: Icon(_icon, color: _iconColor),
      title: Text(
        file.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: _sizeLabel != null ? Text(_sizeLabel!) : null,
      onTap: onTap != null ? () => onTap!(file) : null,
      onLongPress: onLongPress,
    );

    if (progressPercentage == null) return tile;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        tile,
        Padding(
          padding: const EdgeInsets.only(left: 72, right: 16),
          child: LinearProgressIndicator(
            value: progressPercentage,
            minHeight: 2,
            backgroundColor: Colors.grey.shade200,
          ),
        ),
      ],
    );
  }
}
