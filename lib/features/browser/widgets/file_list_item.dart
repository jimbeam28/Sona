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
  final VoidCallback? onLongPress;

  const DirectoryListTile({
    super.key,
    required this.file,
    this.onTap,
    this.onLongPress,
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
      // No explicit long-press handler → swallow the gesture instead of let
      // stock ListTile misfire onTap after a long hold.
      onLongPress: onLongPress ?? (onTap != null ? () {} : null),
    );
  }
}

// ── Audio file list tile ────────────────────────────────────────────────────────

/// A [ListTile] representing an audio file entry.
///
/// Displays an icon that distinguishes music from audiobook files,
/// the file name, and optionally the file size.  [onTap] fires with the
/// [NasFile] when the user taps the tile.
class AudioFileListTile extends StatelessWidget {
  final NasFile file;
  final FileItemTapCallback? onTap;
  final VoidCallback? onLongPress;
  final FileItemTapCallback? onPlayNext;
  final bool playNextEnabled;

  /// MSEL-01: 多选模式行形态——leading 变 [Checkbox]、trailing next-play 整体
  /// 消失、长按禁用（tap 全部归勾选，S1/S2）。
  final bool multiSelect;

  /// 多选模式下本行的勾选态（仅 [multiSelect] 为 true 时有意义）。
  final bool checked;

  const AudioFileListTile({
    super.key,
    required this.file,
    this.onTap,
    this.onLongPress,
    this.onPlayNext,
    this.playNextEnabled = true,
    this.multiSelect = false,
    this.checked = false,
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
    // MSEL-01-S1/S2 多选态：leading Checkbox + 无 trailing + 无长按；
    // 勾选动作统一走 onTap（Checkbox 与行 tap 同一回调）。
    if (multiSelect) {
      return ListTile(
        leading: Checkbox(
          value: checked,
          onChanged: onTap != null ? (_) => onTap!(file) : null,
        ),
        title: Text(
          file.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: _sizeLabel != null ? Text(_sizeLabel!) : null,
        onTap: onTap != null ? () => onTap!(file) : null,
      );
    }
    final playNextActive = playNextEnabled && onPlayNext != null;
    final nextIcon = IconButton(
      icon: const Icon(Icons.queue_music),
      onPressed: playNextActive ? () => onPlayNext!(file) : null,
      tooltip: playNextActive ? '加入下一曲' : '请先开始播放后再用此功能',
    );
    final trailing = playNextActive
        ? nextIcon
        : GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {},
            child: nextIcon,
          );
    return ListTile(
      leading: Icon(_icon, color: _iconColor),
      title: Text(
        file.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: _sizeLabel != null ? Text(_sizeLabel!) : null,
      trailing: trailing,
      onTap: onTap != null ? () => onTap!(file) : null,
      onLongPress: onLongPress,
    );
  }
}
