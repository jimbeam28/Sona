// lib/features/playlist/playlist_detail_screen.dart
// Full UI for PLY-13: playlist detail screen with track list, selection mode,
// and add-tracks browser.

// ignore_for_file: use_build_context_synchronously

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../shared/models/play_queue.dart';
import '../../shared/models/playlist.dart';
import '../browser/browser_provider.dart';
import '../connection/connection_provider.dart';
import '../progress/progress_dialog.dart';
import '../progress/progress_provider.dart';
import 'playlist_provider.dart';
import 'widgets/add_tracks_browser.dart';
import 'widgets/playlist_track_item.dart';

class PlaylistDetailScreen extends ConsumerStatefulWidget {
  final int playlistId;

  const PlaylistDetailScreen({super.key, required this.playlistId});

  @override
  ConsumerState<PlaylistDetailScreen> createState() =>
      _PlaylistDetailScreenState();
}

class _PlaylistDetailScreenState extends ConsumerState<PlaylistDetailScreen> {
  final Set<int> _selectedIds = {};
  bool _selectionMode = false;

  void _exitSelectionMode() {
    setState(() {
      _selectionMode = false;
      _selectedIds.clear();
    });
  }

  void _playTrackAtIndex(List<PlaylistTrack> tracks, int index) async {
    final filePath = tracks[index].filePath;
    final conn = ref.read(activeConnectionProvider).valueOrNull;

    int? startPositionMs;

    // PRG-01 / PLS-04: check for saved playback progress
    if (conn != null && conn.id != null) {
      try {
        final progress = await ref.read(progressForFileProvider(
            (connectionId: conn.id!, filePath: filePath)).future);
        if (progress != null && progress.positionMs >= 5000) {
          final resume = await showProgressResumeDialog(
            context,
            ProviderScope.containerOf(context),
            progress,
          );
          if (resume == true) {
            startPositionMs = progress.positionMs;
          }
        }
      } catch (_) {
        // On error, play from beginning
      }
    }

    if (!context.mounted) return;

    final nasFiles = tracks.map((t) => t.toNasFile()).toList();
    final queue = PlayQueue(
      files: nasFiles,
      currentIndex: index,
      startPositionMs: startPositionMs,
    );
    ref.read(currentPlayQueueProvider.notifier).state = queue;
    ref.read(lastQueueConnectionIdProvider.notifier).state = conn?.id;
    context.push('/player');
  }

  @override
  Widget build(BuildContext context) {
    final playlistId = widget.playlistId;
    final tracksAsync = ref.watch(playlistTracksProvider(playlistId));

    // Resolve playlist name from playlistListProvider
    final playlistsAsync = ref.watch(playlistListProvider);
    final playlistName = playlistsAsync.whenOrNull(
          data: (list) {
            final match = list.where((p) => p.id == playlistId);
            return match.isNotEmpty ? match.first.name : '播放单';
          },
        ) ??
        '播放单';

    return Scaffold(
      appBar: _selectionMode ? _selectionAppBar(playlistId) : _normalAppBar(playlistName, playlistId),
      body: tracksAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.error_outline,
                    size: 48, color: Theme.of(context).colorScheme.error),
                const SizedBox(height: 16),
                Text('加载失败：$error',
                    textAlign: TextAlign.center,
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error)),
                const SizedBox(height: 24),
                OutlinedButton.icon(
                  onPressed: () =>
                      ref.invalidate(playlistTracksProvider(playlistId)),
                  icon: const Icon(Icons.refresh),
                  label: const Text('重试'),
                ),
              ],
            ),
          ),
        ),
        data: (tracks) {
          if (tracks.isEmpty) {
            return const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.queue_music_outlined, size: 64, color: Colors.grey),
                  SizedBox(height: 16),
                  Text('播放单为空',
                      style: TextStyle(color: Colors.grey, fontSize: 16)),
                  SizedBox(height: 8),
                  Text('点击右上角 + 添加曲目',
                      style: TextStyle(color: Colors.grey, fontSize: 14)),
                ],
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: tracks.length,
            separatorBuilder: (_, __) =>
                const Divider(height: 1, indent: 72),
            itemBuilder: (context, index) {
              final track = tracks[index];
              return PlaylistTrackItem(
                track: track,
                selected: _selectedIds.contains(track.id),
                onTap: () {
                  if (_selectionMode) {
                    setState(() {
                      if (_selectedIds.contains(track.id)) {
                        _selectedIds.remove(track.id);
                        if (_selectedIds.isEmpty) _exitSelectionMode();
                      } else {
                        _selectedIds.add(track.id!);
                      }
                    });
                  } else {
                    _playTrackAtIndex(tracks, index);
                  }
                },
                onLongPress: () {
                  if (!_selectionMode) {
                    setState(() {
                      _selectionMode = true;
                      _selectedIds.add(track.id!);
                    });
                  }
                },
              );
            },
          );
        },
      ),
    );
  }

  AppBar _normalAppBar(String playlistName, int playlistId) {
    return AppBar(
      title: Text(playlistName),
      centerTitle: true,
      actions: [
        // PLS-01: rename playlist
        IconButton(
          icon: const Icon(Icons.edit_outlined),
          tooltip: '重命名',
          onPressed: () => _showRenameDialog(playlistId, playlistName),
        ),
        IconButton(
          icon: const Icon(Icons.add),
          tooltip: '添加曲目',
          onPressed: () => showAddTracksBrowser(context, playlistId),
        ),
        PopupMenuButton<TrackSortOption>(
          icon: const Icon(Icons.sort),
          tooltip: '排序方式',
          onSelected: (option) {
            ref.read(trackSortProvider.notifier).state = option;
          },
          itemBuilder: (context) {
            final current = ref.watch(trackSortProvider);
            return [
              _sortItem('添加时间', TrackSortOption.addedAsc, current),
              _sortItem('文件名升序', TrackSortOption.nameAsc, current),
              _sortItem('文件名降序', TrackSortOption.nameDesc, current),
            ];
          },
        ),
      ],
    );
  }

  Future<void> _showRenameDialog(int playlistId, String currentName) async {
    final controller = TextEditingController(text: currentName);
    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('重命名播放单'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: '名称',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            child: const Text('保存'),
          ),
        ],
      ),
    );

    if (newName != null && newName.isNotEmpty && newName != currentName) {
      final playlistsAsync = ref.read(playlistListProvider);
      final playlist = playlistsAsync.valueOrNull
          ?.where((p) => p.id == playlistId)
          .firstOrNull;
      if (playlist != null) {
        await ref.read(updatePlaylistProvider)(
          playlist.copyWith(name: newName, updatedAt: DateTime.now()),
        );
      }
    }
  }

  AppBar _selectionAppBar(int playlistId) {
    return AppBar(
      leading: IconButton(
        icon: const Icon(Icons.close),
        onPressed: _exitSelectionMode,
      ),
      title: Text('已选 ${_selectedIds.length} 首'),
      centerTitle: true,
      actions: [
        IconButton(
          icon: const Icon(Icons.select_all),
          tooltip: '全选',
          onPressed: () {
            final tracks =
                ref.read(playlistTracksProvider(playlistId)).valueOrNull;
            if (tracks != null) {
              setState(() {
                _selectedIds.addAll(tracks.map((t) => t.id!));
              });
            }
          },
        ),
        IconButton(
          icon: const Icon(Icons.deselect),
          tooltip: '取消全选',
          onPressed: () {
            setState(() => _selectedIds.clear());
          },
        ),
        IconButton(
          icon: const Icon(Icons.delete_outline),
          tooltip: '删除',
          onPressed: () async {
            final confirmed = await showDialog<bool>(
              context: context,
              builder: (ctx) => AlertDialog(
                title: const Text('确认删除'),
                content: Text('确认删除选中的 ${_selectedIds.length} 首曲目？'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(ctx).pop(false),
                    child: const Text('取消'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(ctx).pop(true),
                    child: const Text('删除',
                        style: TextStyle(color: Colors.red)),
                  ),
                ],
              ),
            );
            if (confirmed == true) {
              await ref.read(removeTracksFromPlaylistProvider)(
                playlistId,
                _selectedIds.toList(),
              );
              _exitSelectionMode();
            }
          },
        ),
      ],
    );
  }

  PopupMenuItem<TrackSortOption> _sortItem(
      String title, TrackSortOption value, TrackSortOption current) {
    return PopupMenuItem(
      value: value,
      child: Row(
        children: [
          if (current == value)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Icon(Icons.check,
                  size: 18, color: Theme.of(context).colorScheme.primary),
            )
          else
            const SizedBox(width: 26),
          Text(title),
        ],
      ),
    );
  }
}
