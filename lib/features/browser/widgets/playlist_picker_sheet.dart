// lib/features/browser/widgets/playlist_picker_sheet.dart
// BRW-01 S7/S8 播放单选择面板（单一实现点）。
//
// MSEL-01-S6 依赖声明落地：BRW-01 的 picker 流程提取为顶层函数
// [showPlaylistPickerSheet]，文件夹加入（BRW-01 _addToPlaylistFlow）与多选批量
// 加入（MSEL-01 showPlaylistPickerProvider 默认实现）共用同一实现，零复制粘贴。
// 返回值语义：true = 本次面板操作完成了一次「添加曲目」（含新建后添加）；
// false = 用户关闭面板 / 未选择 / 取消。

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/di/providers.dart';
import '../../../shared/models/nas_file.dart';

/// Opens the playlist picker sheet for [files]; resolves to whether an add
/// completed (see header). [title] is the sheet header text — BRW-01 passes
/// the source folder name, MSEL-01 uses the default.
Future<bool> showPlaylistPickerSheet(
  BuildContext context,
  WidgetRef ref,
  List<NasFile> files, {
  String title = '加入播放单',
}) async {
  final added = await showModalBottomSheet<bool>(
    context: context,
    builder: (sheetContext) => _PlaylistPickerSheet(title: title, files: files),
  );
  return added ?? false;
}

class _PlaylistPickerSheet extends ConsumerWidget {
  final String title;
  final List<NasFile> files;

  const _PlaylistPickerSheet({
    required this.title,
    required this.files,
  });

  Future<void> _addFiles(
    BuildContext context,
    WidgetRef ref,
    int playlistId,
  ) async {
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(addTracksToPlaylistProvider)(playlistId, files);
    } catch (e) {
      debugPrint('[Browser] folder add-to-playlist failed: $e');
      messenger.showSnackBar(
        const SnackBar(content: Text('添加失败，请重试')),
      );
      return;
    }
    navigator.pop(true);
    messenger.showSnackBar(
      SnackBar(content: Text('已添加 ${files.length} 首')),
    );
  }

  Future<void> _showCreateAndAddDialog(
    BuildContext sheetContext,
    WidgetRef ref,
  ) async {
    final controller = TextEditingController();
    var created = false;
    await showDialog<void>(
      context: sheetContext,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (ctx, setState) {
          final canConfirm = controller.text.trim().isNotEmpty;
          return AlertDialog(
            title: const Text('新建播放单'),
            content: TextField(
              controller: controller,
              autofocus: true,
              onChanged: (_) => setState(() {}),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: canConfirm
                    ? () async {
                        final navigator = Navigator.of(ctx);
                        final messenger = ScaffoldMessenger.of(ctx);
                        try {
                          // REF-07: only emptiness is validated here — the
                          // raw name (leading/trailing spaces included) goes
                          // to storage untouched. Service direct call so the
                          // returned id feeds addTracks (createPlaylistProvider
                          // wraps it as Future<void> and drops the id).
                          final newId = await ref
                              .read(playlistServiceProvider)
                              .createPlaylist(controller.text);
                          await ref.read(addTracksToPlaylistProvider)(
                              newId, files);
                        } catch (e) {
                          debugPrint(
                              '[Browser] folder create-playlist failed: $e');
                          messenger.showSnackBar(
                            const SnackBar(content: Text('创建失败，请重试')),
                          );
                          return;
                        }
                        created = true;
                        messenger.showSnackBar(
                          SnackBar(content: Text('已添加 ${files.length} 首')),
                        );
                        navigator.pop();
                      }
                    : null,
                child: const Text('创建'),
              ),
            ],
          );
        },
      ),
    );
    if (!created || !sheetContext.mounted) return;
    Navigator.of(sheetContext).pop(true);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playlistsAsync = ref.watch(playlistListProvider);
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              title,
              style: Theme.of(context).textTheme.titleMedium,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const Divider(height: 1),
          Flexible(
            child: playlistsAsync.when(
              loading: () => const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (_, __) => Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('加载播放单失败，请重试'),
                    const SizedBox(height: 8),
                    TextButton.icon(
                      onPressed: () => ref.invalidate(playlistListProvider),
                      icon: const Icon(Icons.refresh),
                      label: const Text('重试'),
                    ),
                  ],
                ),
              ),
              data: (playlists) {
                if (playlists.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: Text('还没有播放单')),
                  );
                }
                return ListView.builder(
                  shrinkWrap: true,
                  itemCount: playlists.length,
                  itemBuilder: (context, index) {
                    final playlist = playlists[index];
                    return ListTile(
                      leading: const Icon(Icons.queue_music),
                      title: Text(
                        playlist.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      onTap: () {
                        final playlistId = playlist.id;
                        if (playlistId == null) return;
                        // ignore: discarded_futures
                        _addFiles(context, ref, playlistId);
                      },
                    );
                  },
                );
              },
            ),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.add),
            title: const Text('新建播放单'),
            onTap: () {
              // ignore: discarded_futures
              _showCreateAndAddDialog(context, ref);
            },
          ),
        ],
      ),
    );
  }
}
