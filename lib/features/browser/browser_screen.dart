// lib/features/browser/browser_screen.dart
// Full UI for BRW-01: directory listing + BRW-02: directory navigation.
//
// States:
//   - Loading  → skeleton / spinner
//   - Error    → error message + retry button
//   - Empty    → "此目录为空" message
//   - Data     → scrollable list of directory + audio-file tiles

// H-3 note: this file's primary interaction is an async callback that uses
// context extensively after awaits.  Per-line suppressions would clutter the
// handler unreasonably, so file-level suppression is kept intentionally.
// ignore_for_file: use_build_context_synchronously

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/network/webdav_client.dart';
import '../../shared/models/nas_file.dart';
import '../../shared/models/play_progress.dart';
import '../../shared/models/play_queue.dart';
import '../../shared/di/providers.dart';
import 'widgets/file_list_item.dart';

class BrowserScreen extends ConsumerWidget {
  const BrowserScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final navStack = ref.watch(navigationStackProvider);
    final currentPath = navStack.last;

    // B-3: activate queue persistence listener.
    ref.watch(persistQueueOnChangeProvider);
    // PLY-04: clear queue when active connection changes
    ref.watch(clearQueueOnConnectionSwitchProvider);

    final contentsAsync = ref.watch(directoryContentsProvider(currentPath));

    return PopScope(
      canPop: navStack.length <= 1,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          ref.read(navigationStackProvider.notifier).pop();
        }
      },
      child: Column(
        children: [
          // Breadcrumb navigation bar (BRW-02)
          const BreadcrumbBar(),
          const Divider(height: 1),

          // Directory contents
          Expanded(
            child: contentsAsync.when(
              loading: () => const _LoadingView(),
              error: (error, _) {
                // BUG-10（cr-20260816-0803 F1）：错误卫生——非 WebDavException
                // 一律固定兜底文案，原始异常只经 debugPrint 进 LogBuffer
                //（对齐 BUG-23-S5 裁决；redactUrlForLog 剥离 URL userinfo）。
                if (error is! WebDavException) {
                  debugPrint('[Browser] directory load error: '
                      '${redactUrlForLog(error.toString())}');
                }
                return _ErrorView(
                  message:
                      error is WebDavException ? error.message : '加载失败，请稍后重试',
                  onRetry: () {
                    ref.invalidate(directoryContentsProvider(currentPath));
                  },
                );
              },
              data: (files) {
                if (files.isEmpty) {
                  return const _EmptyView();
                }
                return RefreshIndicator(
                  onRefresh: () async {
                    final currentPath = ref.read(navigationStackProvider).last;
                    // REF-06: 传活跃连接 id，清除只命中本连接的缓存
                    // （cr-20260816-0803 D1）。
                    final connId =
                        ref.read(activeConnectionProvider).valueOrNull?.id;
                    ref.read(clearDirectoryCacheProvider)(connId, currentPath);
                    final _ = await ref
                        .refresh(directoryContentsProvider(currentPath).future);
                  },
                  child: _FileList(
                    files: files,
                    playNextEnabled:
                        (ref.watch(audioPlayingProvider).valueOrNull ??
                                false) &&
                            ref.watch(currentPlayQueueProvider) != null,
                    onPlayNext: (NasFile f) async {
                      final ok = await ref.read(insertAfterCurrentProvider)(f);
                      if (ok && context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('已加入下一曲：${f.name}'),
                            duration: const Duration(seconds: 2),
                          ),
                        );
                      }
                    },
                    onDirectoryTap: (dirPath) {
                      ref.read(navigationStackProvider.notifier).push(dirPath);
                    },
                    onFileTap: (tappedFile) async {
                      debugPrint('[Browser] onFileTap: ${tappedFile.path}');
                      final contents = ref
                          .read(directoryContentsProvider(currentPath))
                          .valueOrNull;
                      if (contents == null) return;

                      final audioFiles =
                          contents.where((f) => !f.isDirectory).toList();
                      final startIndex = audioFiles
                          .indexWhere((f) => f.path == tappedFile.path);
                      if (startIndex < 0) return;

                      // PRG-01: check for saved playback progress before playing.
                      // BUG-12: read progressForFileProvider directly (same
                      // pattern as playlist_detail_screen) — the old registry
                      // was never populated.
                      int? startPositionMs;
                      final conn =
                          ref.read(activeConnectionProvider).valueOrNull;
                      if (conn != null && conn.id != null) {
                        // BUG-18: progressForFileProvider 的 future 抛错
                        // （SQLite 读异常）时不得冒未处理异常中断播放流程——
                        // catch + 日志，按无进度播放（对齐
                        // playlist_detail_screen.dart:48-75；SCHEMA.md §5
                        // catch-log 裁决）。
                        try {
                          final progress =
                              await ref.read(progressForFileProvider((
                            connectionId: conn.id!,
                            filePath: tappedFile.path,
                          )).future);
                          if (!context.mounted) return;
                          if (progress != null && progress.positionMs >= 5000) {
                            final container =
                                ProviderScope.containerOf(context);
                            final resume = await showProgressResumeDialog(
                                context, container, progress);
                            if (resume == true) {
                              startPositionMs = progress.positionMs;
                            } else if (resume == false) {
                              ref.read(clearProgressProvider)(
                                connectionId: conn.id!,
                                filePath: tappedFile.path,
                              );
                            }
                          }
                        } catch (e) {
                          // On error, play from beginning — but do not
                          // swallow silently (catch-log criterion, SCHEMA.md
                          // §5, same as playlist_detail).
                          debugPrint('[Browser] play: progress resume lookup '
                              'failed, playing from beginning: $e');
                        }
                      }

                      debugPrint(
                          '[Browser] onFileTap: queue ${audioFiles.length} tracks idx=$startIndex');

                      final goRouter = GoRouter.of(context);

                      // O3 链路（cr-20260804-1922 §5）: 按当前 playModeProvider
                      // 的模式建队。恒以默认 sequential 建队会让「先切 shuffle
                      // 再建队」的用户丢模式——播放行为是 shuffle（orchestrator
                      // 从 playModeProvider 同步），但队列 playMode 字段落
                      // sequential → 持久化 sequential → 重启忠实恢复 sequential。
                      // 复用 f3cb8eb 的 withMode 机制（进 shuffle 生成排列且
                      // 指针锚定当前曲; 同模式幂等; 单曲无排列），不在创建点
                      // 手写排列生成。跨 feature 经 shared/di 桥接读取。
                      final queue = PlayQueue(
                        files: audioFiles,
                        currentIndex: startIndex,
                        startPositionMs: startPositionMs,
                      ).withMode(ref.read(playModeProvider));
                      ref.read(currentPlayQueueProvider.notifier).state = queue;
                      final connId =
                          ref.read(activeConnectionProvider).valueOrNull?.id;
                      ref.read(lastQueueConnectionIdProvider.notifier).state =
                          connId;
                      await goRouter.push('/player');
                    },
                    onFileLongPress: (tappedFile) async {
                      // BUG-12: read progressForFileProvider directly.
                      final conn =
                          ref.read(activeConnectionProvider).valueOrNull;
                      if (conn == null || conn.id == null) return;
                      // BUG-18: 同类裸奔点加固（cr-0805 F1 勘察补充）。
                      PlayProgress? progress;
                      try {
                        progress = await ref.read(progressForFileProvider((
                          connectionId: conn.id!,
                          filePath: tappedFile.path,
                        )).future);
                      } catch (e) {
                        // 查询失败 → 无进度可展示，静默返回（catch-log
                        // 裁决，日志照留）。
                        debugPrint(
                            '[Browser] long-press: progress resume lookup '
                            'failed: $e');
                        return;
                      }
                      if (progress == null || !context.mounted) return;
                      // 类型提升锚点：局部可变变量在下方 bottom sheet 闭包内
                      // 不提升，先落到 stable final 供闭包读取（BUG-18）。
                      final resolvedProgress = progress;

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
                                    style:
                                        Theme.of(context).textTheme.titleMedium,
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
                                    '已保存进度 ${resolvedProgress.formattedPosition}',
                                    style:
                                        Theme.of(context).textTheme.bodySmall,
                                  ),
                                  onTap: () {
                                    ref.read(clearProgressProvider)(
                                      connectionId:
                                          resolvedProgress.connectionId,
                                      filePath: resolvedProgress.filePath,
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
        ],
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
  final void Function(NasFile file)? onPlayNext;
  final bool playNextEnabled;

  const _FileList({
    required this.files,
    this.onDirectoryTap,
    required this.onFileTap,
    this.onFileLongPress,
    this.onPlayNext,
    this.playNextEnabled = false,
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
            key: ValueKey(file.path),
            file: file,
            onTap: onDirectoryTap != null
                ? (_) => onDirectoryTap!(file.path)
                : null,
          );
        }
        return AudioFileListTile(
          key: ValueKey(file.path),
          file: file,
          onTap: (_) {
            // ignore: discarded_futures
            onFileTap(file);
          },
          onLongPress:
              onFileLongPress != null ? () => onFileLongPress!(file) : null,
          onPlayNext: onPlayNext != null ? (_) => onPlayNext!(file) : null,
          playNextEnabled: playNextEnabled,
        );
      },
    );
  }
}
