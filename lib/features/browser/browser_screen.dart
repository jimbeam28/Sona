// lib/features/browser/browser_screen.dart
// Full UI for BRW-01: directory listing + BRW-02: directory navigation.
//
// States:
//   - Loading  → skeleton / spinner
//   - Error    → error message + retry button
//   - Empty    → "此目录为空" message
//   - Data     → scrollable list of directory + audio-file tiles

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/network/webdav_client.dart';
import '../../shared/models/nas_file.dart';
import '../../shared/models/play_progress.dart';
import '../../shared/models/play_queue.dart';
import '../player/widgets/mini_player_bar.dart';
import '../progress/progress_dialog.dart';
import '../progress/progress_provider.dart';
import 'browser_provider.dart';
import 'widgets/breadcrumb_bar.dart';
import 'widgets/file_list_item.dart';

class BrowserScreen extends ConsumerWidget {
  const BrowserScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final navStack = ref.watch(navigationStackProvider);
    final currentPath = navStack.last;

    final contentsAsync = ref.watch(directoryContentsProvider(currentPath));

    // When directory contents load, trigger progress loading in background
    ref.listen(directoryContentsProvider(currentPath), (prev, next) {
      if (next.hasValue) {
        ref.invalidate(loadProgressForDirectoryProvider(currentPath));
      }
    });

    return PopScope(
      canPop: navStack.length <= 1,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          ref.read(navigationStackProvider.notifier).pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('文件浏览器'),
          centerTitle: true,
          leading: navStack.length > 1
              ? IconButton(
                  icon: const Icon(Icons.arrow_back),
                  tooltip: '返回上级',
                  onPressed: () {
                    ref.read(navigationStackProvider.notifier).pop();
                  },
                )
              : null,
          actions: [
            IconButton(
              icon: const Icon(Icons.settings),
              tooltip: '设置',
              onPressed: () => context.push('/settings'),
            ),
            PopupMenuButton<SortOption>(
              icon: const Icon(Icons.sort),
              tooltip: '排序方式',
              onSelected: (option) {
                ref.read(sortOptionProvider.notifier).setOption(option);
              },
              itemBuilder: (context) {
                final current = ref.watch(sortOptionProvider);
                return [
                  PopupMenuItem(
                    value: SortOption.nameAsc,
                    child: _SortMenuItem(
                      title: '名称升序',
                      selected: current == SortOption.nameAsc,
                    ),
                  ),
                  PopupMenuItem(
                    value: SortOption.nameDesc,
                    child: _SortMenuItem(
                      title: '名称降序',
                      selected: current == SortOption.nameDesc,
                    ),
                  ),
                  PopupMenuItem(
                    value: SortOption.modifiedDesc,
                    child: _SortMenuItem(
                      title: '修改时间',
                      selected: current == SortOption.modifiedDesc,
                    ),
                  ),
                ];
              },
            ),
          ],
        ),
        body: Column(
          children: [
            // Breadcrumb navigation bar (BRW-02)
            const BreadcrumbBar(),
            const Divider(height: 1),

            // Directory contents
            Expanded(
              child: contentsAsync.when(
                loading: () => const _LoadingView(),
                error: (error, _) => _ErrorView(
                  message: error is WebDavException
                      ? error.message
                      : '加载失败：$error',
                  onRetry: () {
                    ref.invalidate(directoryContentsProvider(currentPath));
                  },
                ),
                data: (files) {
                  if (files.isEmpty) {
                    return const _EmptyView();
                  }
                  return RefreshIndicator(
                    onRefresh: () async {
                      final currentPath =
                          ref.read(navigationStackProvider).last;
                      ref.read(clearDirectoryCacheProvider)(currentPath);
                      await ref.refresh(
                          directoryContentsProvider(currentPath).future);
                    },
                    child: _FileList(
                      files: files,
                      onDirectoryTap: (dirPath) {
                        ref
                            .read(navigationStackProvider.notifier)
                            .push(dirPath);
                      },
                      onFileTap: (tappedFile) {
                      // BRW-04: Build play queue from current directory.
                      // Re-read the cached contents so we have the full
                      // filtered/sorted list (the UI may show a subset).
                      final contents = ref
                          .read(directoryContentsProvider(currentPath))
                          .valueOrNull;
                      if (contents == null) return;

                      final audioFiles =
                          contents.where((f) => !f.isDirectory).toList();
                      final startIndex = audioFiles
                          .indexWhere((f) => f.path == tappedFile.path);
                      if (startIndex < 0) return;

                      // Check for saved playback progress
                      final progress =
                          ref.read(playProgressProvider(tappedFile.path));

                      // Lazily resolve GoRouter — only needed when the user
                      // actually taps a file.
                      final goRouter = GoRouter.of(context);

                      if (progress != null) {
                        // PRG-03: Show resume dialog with countdown timer.
                        // Dialog returns true=continue, false=start over,
                        // null=dismissed.
                        final container =
                            ProviderScope.containerOf(context);
                        // ignore: discarded_futures
                        showProgressResumeDialog(
                          context,
                          container,
                          progress,
                        ).then((continuePlayback) {
                          if (!context.mounted) return;
                          if (continuePlayback == true) {
                            // Resume from saved position
                            final queue = PlayQueue(
                              files: audioFiles,
                              currentIndex: startIndex,
                              startPositionMs: progress.positionMs,
                            );
                            ref
                                .read(currentPlayQueueProvider.notifier)
                                .state = queue;
                            goRouter.go('/player');
                          } else {
                            // Start from beginning (or dialog dismissed)
                            // PRG-T20: also delete progress on start-over
                            if (continuePlayback == false) {
                              ref.read(clearProgressProvider)(
                                connectionId: progress.connectionId,
                                filePath: progress.filePath,
                              );
                            }
                            final queue = PlayQueue(
                              files: audioFiles,
                              currentIndex: startIndex,
                            );
                            ref
                                .read(currentPlayQueueProvider.notifier)
                                .state = queue;
                            goRouter.go('/player');
                          }
                        });
                      } else {
                        // No saved progress — play from beginning.
                        final queue = PlayQueue(
                          files: audioFiles,
                          currentIndex: startIndex,
                        );
                        ref
                            .read(currentPlayQueueProvider.notifier)
                            .state = queue;
                        goRouter.go('/player');
                      }
                    },
                    onFileLongPress: (tappedFile) {
                      final progress =
                          ref.read(playProgressProvider(tappedFile.path));
                      if (progress == null) return;

                      showModalBottomSheet(
                        context: context,
                        builder: (ctx) {
                          return SafeArea(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: Text(
                                    tappedFile.name,
                                    style: Theme.of(context).textTheme.titleMedium,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const Divider(height: 1),
                                ListTile(
                                  leading: const Icon(Icons.delete_outline,
                                      color: Colors.red),
                                  title: const Text('清除播放进度'),
                                  subtitle: Text(
                                    '已保存进度 ${progress.formattedPosition}',
                                    style: Theme.of(context).textTheme.bodySmall,
                                  ),
                                  onTap: () {
                                    ref.read(clearProgressProvider)(
                                      connectionId: progress.connectionId,
                                      filePath: progress.filePath,
                                    );
                                    Navigator.of(ctx).pop();
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('播放进度已清除'),
                                      ),
                                    );
                                  },
                                ),
                                const SizedBox(height: 8),
                              ],
                            ),
                          );
                        },
                      );
                    },
                  ),
                );
              },
            ),
            ),
            // Mini player bar (PLY-08) — shown when audio is loaded/playing
            const MiniPlayerBar(),
          ],
        ),
      ),
    );
  }
}

// ── Loading state ───────────────────────────────────────────────────────────────

class _LoadingView extends StatelessWidget {
  const _LoadingView();

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: 8,
      itemBuilder: (context, index) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Row(
            children: [
              // Icon placeholder
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              const SizedBox(width: 16),
              // Text placeholder
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

// ── Error state ─────────────────────────────────────────────────────────────────

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorView({
    required this.message,
    required this.onRetry,
  });

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
              style: TextStyle(
                color: Theme.of(context).colorScheme.error,
              ),
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

// ── Empty state ─────────────────────────────────────────────────────────────────

class _EmptyView extends StatelessWidget {
  const _EmptyView();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.folder_open_outlined, size: 48, color: Colors.grey),
          SizedBox(height: 16),
          Text(
            '此目录为空',
            style: TextStyle(color: Colors.grey, fontSize: 16),
          ),
        ],
      ),
    );
  }
}

// ── File list ───────────────────────────────────────────────────────────────────

class _FileList extends StatelessWidget {
  final List<NasFile> files;
  final void Function(String dirPath)? onDirectoryTap;
  final void Function(NasFile file) onFileTap;
  final void Function(NasFile file)? onFileLongPress;

  const _FileList({
    required this.files,
    this.onDirectoryTap,
    required this.onFileTap,
    this.onFileLongPress,
  });

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: files.length,
      separatorBuilder: (_, __) => const Divider(height: 1, indent: 72),
      itemBuilder: (context, index) {
        final file = files[index];
        if (file.isDirectory) {
          return DirectoryListTile(
            file: file,
            onTap: onDirectoryTap != null
                ? (_) => onDirectoryTap!(file.path)
                : null,
          );
        }
        return AudioFileListTile(
          file: file,
          onTap: (_) => onFileTap(file),
          onLongPress: onFileLongPress != null ? () => onFileLongPress!(file) : null,
        );
      },
    );
  }
}

// ── Sort menu item ──────────────────────────────────────────────────────────────

/// A row in the sort popup menu that shows a checkmark when [selected] is true.
class _SortMenuItem extends StatelessWidget {
  final String title;
  final bool selected;

  const _SortMenuItem({required this.title, required this.selected});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        if (selected)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Icon(Icons.check, size: 18, color: Theme.of(context).colorScheme.primary),
          )
        else
          const SizedBox(width: 26),
        Text(title),
      ],
    );
  }
}
