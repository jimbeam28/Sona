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

                      // Check for saved playback progress (placeholder — always
                      // null until the Progress module is built).
                      final progress =
                          ref.read(playProgressProvider(tappedFile.path));

                      // Lazily resolve GoRouter — only needed when the user
                      // actually taps a file.
                      final goRouter = GoRouter.of(context);

                      if (progress != null) {
                        _showProgressResumeDialog(
                          context,
                          progress,
                          () {
                            final queue = PlayQueue(
                              files: audioFiles,
                              currentIndex: startIndex,
                            );
                            ref
                                .read(currentPlayQueueProvider.notifier)
                                .state = queue;
                            goRouter.go('/player');
                          },
                          () {
                            final queue = PlayQueue(
                              files: audioFiles,
                              currentIndex: startIndex,
                              startPositionMs: progress.positionMs,
                            );
                            ref
                                .read(currentPlayQueueProvider.notifier)
                                .state = queue;
                            goRouter.go('/player');
                          },
                        );
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
                  ),
                );
              },
            ),
            ),
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

  const _FileList({
    required this.files,
    this.onDirectoryTap,
    required this.onFileTap,
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
        );
      },
    );
  }
}

// ── Progress resume dialog ────────────────────────────────────────────────────────

/// Shows a confirmation dialog asking the user whether to resume playback
/// from the saved position or start over from the beginning.
///
/// [progress] provides the saved position for display.
/// [onStartOver] is called when the user chooses "从头播放".
/// [onContinue] is called when the user chooses "继续播放".
void _showProgressResumeDialog(
  BuildContext context,
  PlayProgress progress,
  VoidCallback onStartOver,
  VoidCallback onContinue,
) {
  showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('恢复播放'),
      content: Text(
        '上次播放到 ${progress.formattedPosition}，是否从此处继续？',
      ),
      actions: [
        TextButton(
          onPressed: () {
            Navigator.of(ctx).pop();
            onStartOver();
          },
          child: const Text('从头播放'),
        ),
        FilledButton(
          onPressed: () {
            Navigator.of(ctx).pop();
            onContinue();
          },
          child: const Text('继续播放'),
        ),
      ],
    ),
  );
}
