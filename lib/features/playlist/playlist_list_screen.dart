// lib/features/playlist/playlist_list_screen.dart
// Full UI for PLY-12: playlist list screen.
//
// States:
//   - Loading  → skeleton list
//   - Error    → error message + retry
//   - Empty    → icon + "还没有播放单，点击 + 新建"
//   - Data     → scrollable list of PlaylistListItem

// ignore_for_file: use_build_context_synchronously

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:go_router/go_router.dart';

import 'playlist_provider.dart';
import 'widgets/playlist_list_item.dart';

class PlaylistListScreen extends ConsumerWidget {
  const PlaylistListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playlistsAsync = ref.watch(playlistListProvider);

    return Stack(
      children: [
        playlistsAsync.when(
          loading: () => const _LoadingView(),
          error: (error, _) => _ErrorView(
            message: '加载失败：$error',
            onRetry: () => ref.invalidate(playlistListProvider),
          ),
          data: (playlists) {
            if (playlists.isEmpty) {
              return const _EmptyView();
            }
            return ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: playlists.length,
              separatorBuilder: (_, __) => const Divider(height: 1, indent: 72),
              itemBuilder: (context, index) {
                final playlist = playlists[index];
                return Slidable(
                  key: ValueKey(playlist.id),
                  endActionPane: ActionPane(
                    motion: const DrawerMotion(),
                    children: [
                      SlidableAction(
                        onPressed: (_) async {
                          final confirmed = await showDialog<bool>(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              title: const Text('确认删除'),
                              content:
                                  Text('确认删除播放单「${playlist.name}」？此操作不可撤销。'),
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
                            final del = ref.read(deletePlaylistProvider);
                            try {
                              await del(playlist.id!);
                            } catch (e) {
                              // BUG-25-S3: a DB failure must not vanish
                              // silently — log it and show an error SnackBar.
                              debugPrint('[Playlist] delete failed: $e');
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('删除失败：$e'),
                                    backgroundColor:
                                        Theme.of(context).colorScheme.error,
                                  ),
                                );
                              }
                            }
                          }
                        },
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white,
                        icon: Icons.delete_outline,
                        label: '删除',
                      ),
                    ],
                  ),
                  child: PlaylistListItem(
                    playlist: playlist,
                    onTap: () => context.push('/playlist/${playlist.id}'),
                  ),
                );
              },
            );
          },
        ),
        Positioned(
          bottom: 16,
          right: 16,
          child: FloatingActionButton(
            onPressed: () => _showCreateDialog(context, ref),
            child: const Icon(Icons.add),
          ),
        ),
      ],
    );
  }

  void _showCreateDialog(BuildContext context, WidgetRef ref) {
    // BUG-25-S5: the dialog content is a ConsumerStatefulWidget that owns its
    // TextEditingController — disposing the controller from a `.then` on the
    // showDialog future would race the dialog's exit animation (the content is
    // still mounted and listening while the route animates out).
    showDialog<void>(
      context: context,
      builder: (_) => const _CreatePlaylistDialog(),
    );
  }
}

/// BUG-25-S5: create-dialog content as a ConsumerStatefulWidget so the
/// dialog-local [TextEditingController] is disposed together with the dialog
/// element (no leak on repeated open/close — LIST8).
class _CreatePlaylistDialog extends ConsumerStatefulWidget {
  const _CreatePlaylistDialog();

  @override
  ConsumerState<_CreatePlaylistDialog> createState() =>
      _CreatePlaylistDialogState();
}

class _CreatePlaylistDialogState extends ConsumerState<_CreatePlaylistDialog> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('新建播放单'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        decoration: const InputDecoration(hintText: '播放单名称'),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        TextButton(
          onPressed: () async {
            final name = _controller.text.trim();
            if (name.isEmpty) return;
            String? error;
            try {
              await ref.read(createPlaylistProvider)(name);
            } catch (e) {
              // BUG-25-S3 同款纪律：DB 失败不得静默消失。
              debugPrint('[Playlist] create failed: $e');
              error = '$e';
            } finally {
              if (context.mounted) Navigator.of(context).pop();
            }
            if (error != null && context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('创建失败：$error'),
                  backgroundColor: Theme.of(context).colorScheme.error,
                ),
              );
            }
          },
          child: const Text('创建'),
        ),
      ],
    );
  }
}

// ── Loading state ───────────────────────────────────────────────────────────

class _LoadingView extends StatelessWidget {
  const _LoadingView();

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: 6,
      itemBuilder: (context, index) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Container(
                  height: 14,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ── Error state ─────────────────────────────────────────────────────────────

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline,
              size: 48,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
            const SizedBox(height: 24),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('重试'),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Empty state ─────────────────────────────────────────────────────────────

class _EmptyView extends StatelessWidget {
  const _EmptyView();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.queue_music_outlined, size: 64, color: Colors.grey),
          SizedBox(height: 16),
          Text(
            '还没有播放单，点击 + 新建',
            style: TextStyle(color: Colors.grey, fontSize: 16),
          ),
        ],
      ),
    );
  }
}
