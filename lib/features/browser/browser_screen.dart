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

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/database/dao/progress_dao.dart' show ProgressDao;
import '../../core/network/webdav_client.dart';
import '../../shared/models/download_record.dart' show DownloadStatus;
import '../../shared/models/nas_file.dart';
import '../../shared/models/play_progress.dart';
import '../../shared/models/play_queue.dart';
import '../../shared/di/providers.dart';
import 'browser_provider.dart';
import 'domain/folder_collector.dart';
import 'domain/folder_searcher.dart' show SearchHit, kSearchMaxDirs;
import 'domain/multi_select_ordering.dart';
import 'widgets/file_list_item.dart';
import 'widgets/playlist_picker_sheet.dart' show showPlaylistPickerSheet;

class BrowserScreen extends ConsumerStatefulWidget {
  const BrowserScreen({super.key});

  @override
  ConsumerState<BrowserScreen> createState() => _BrowserScreenState();
}

class _BrowserScreenState extends ConsumerState<BrowserScreen> {
  // SRCH-01-S8: 搜索框 controller 提升到 State 生命周期，避免 rebuild 丢文本。
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _buildBody(context, ref);
  }

  Widget _buildBody(BuildContext context, WidgetRef ref) {
    final navStack = ref.watch(navigationStackProvider);
    final currentPath = navStack.last;

    // B-3: activate queue persistence listener.
    ref.watch(persistQueueOnChangeProvider);
    // PLY-04: clear queue when active connection changes
    ref.watch(clearQueueOnConnectionSwitchProvider);

    // SRCH-01-S7: 连接切换 → 收起搜索面板并全清会话（closePanel 全清语义）。
    ref.listen(activeConnectionProvider, (prev, next) {
      if (prev?.valueOrNull?.id != next.valueOrNull?.id) {
        ref.read(searchSessionProvider.notifier).closePanel();
      }
    });

    // MSEL-01-S7: 连接切换 → 自动退出多选并清空选择存储
    // （clearQueueOnConnectionSwitchProvider 同款联动点，零残留）。
    ref.listen(activeConnectionProvider, (prev, next) {
      if (prev?.valueOrNull?.id != next.valueOrNull?.id) {
        ref.read(multiSelectModeProvider.notifier).state = false;
        ref.read(multiSelectSelectionProvider.notifier).clear();
      }
    });

    final session = ref.watch(searchSessionProvider);
    final multiSelect = ref.watch(multiSelectModeProvider);
    final contentsAsync = ref.watch(directoryContentsProvider(currentPath));

    // BRW-01 下拉刷新（原 data 分支内联闭包原样上提，token 不变；浅层缩进
    // 保证 REF-06-S8 源码静态断言的关键调用行保持单行字面量）。
    Future<void> handleRefresh() async {
      final currentPath = ref.read(navigationStackProvider).last;
      // REF-06: 传活跃连接 id，清除只命中本连接的缓存
      // （cr-20260816-0803 D1）。
      final connId = ref.read(activeConnectionProvider).valueOrNull?.id;
      ref.read(clearDirectoryCacheProvider)(connId, currentPath);
      final _ =
          await ref.refresh(directoryContentsProvider(currentPath).future);
    }

    return PopScope(
      canPop: navStack.length <= 1,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          ref.read(navigationStackProvider.notifier).pop();
        }
      },
      child: Column(
        children: [
          // Breadcrumb navigation bar (BRW-02)。SRCH-01-S8：放大镜入口挂载在
          // BreadcrumbBar 外层 Row，breadcrumb_bar.dart 内部零改动。
          // MSEL-01-B3-1：多选入口为同一 Row 内 search 之后的 Icons.checklist
          // 按钮（tap 进入 / 再 tap 退出，退出即 clear() 选择存储）。
          Row(
            children: [
              const Expanded(child: BreadcrumbBar()),
              IconButton(
                icon: const Icon(Icons.search),
                tooltip: session.panelOpen ? '收起搜索' : '搜索文件',
                onPressed: () {
                  final notifier = ref.read(searchSessionProvider.notifier);
                  if (ref.read(searchSessionProvider).panelOpen) {
                    notifier.closePanel();
                  } else {
                    notifier.openPanel();
                  }
                },
              ),
              IconButton(
                icon: const Icon(Icons.checklist),
                tooltip: multiSelect ? '退出多选' : '多选',
                onPressed: () {
                  final entering = !ref.read(multiSelectModeProvider);
                  ref.read(multiSelectModeProvider.notifier).state = entering;
                  if (!entering) {
                    // S1 否定面：退出多选模式即清空全部选择（防幽灵选择）。
                    ref.read(multiSelectSelectionProvider.notifier).clear();
                  }
                },
              ),
            ],
          ),
          const Divider(height: 1),

          // SRCH-01-S8/S9: 面板开启时在 Divider 与内容区之间插入搜索框行
          // （autofocus 输入框 + 清空钮 + 收起钮）。
          if (session.panelOpen)
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    autofocus: true,
                    // 不用 prefixIcon(Icons.search)：面板开启时入口按钮已是唯一
                    // 放大镜图标，避免语义重复。
                    decoration: const InputDecoration(
                      hintText: '搜索当前文件夹及子文件夹',
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.symmetric(horizontal: 16),
                    ),
                    onChanged: (raw) => ref
                        .read(searchSessionProvider.notifier)
                        .onQueryChanged(raw),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.clear),
                  tooltip: '清空搜索词',
                  onPressed: () {
                    _searchController.clear();
                    // controller.clear() 不触发 onChanged，手动停流。
                    ref.read(searchSessionProvider.notifier).onQueryChanged('');
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  tooltip: '收起搜索',
                  onPressed: () =>
                      ref.read(searchSessionProvider.notifier).closePanel(),
                ),
              ],
            ),

          // Directory contents / search results。SRCH-01-INV1：面板关闭态走
          // 原 contentsAsync.when 分支，渲染路径与现状逐字节等价。
          Expanded(
            child: session.panelOpen
                ? const _SearchResultsView()
                : contentsAsync.when(
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
                        message: error is WebDavException
                            ? error.message
                            : '加载失败，请稍后重试',
                        onRetry: () {
                          ref.invalidate(
                              directoryContentsProvider(currentPath));
                        },
                      );
                    },
                    data: (files) {
                      if (files.isEmpty) {
                        return const _EmptyView();
                      }
                      return RefreshIndicator(
                        onRefresh: handleRefresh,
                        child: _FileList(
                          files: files,
                          // MSEL-01：多选态行形态切换（leading Checkbox、无
                          // trailing）；关闭时保持 false，渲染与现状等价（INV1）。
                          multiSelect: multiSelect,
                          checkedPaths: multiSelect
                              ? (ref.watch(multiSelectSelectionProvider)[
                                      currentPath] ??
                                  const <String>{})
                              : null,
                          playNextEnabled:
                              (ref.watch(audioPlayingProvider).valueOrNull ??
                                      false) &&
                                  ref.watch(currentPlayQueueProvider) != null,
                          onPlayNext: (NasFile f) async {
                            final ok =
                                await ref.read(insertAfterCurrentProvider)(f);
                            if (ok && context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('已加入下一曲：${f.name}'),
                                  duration: const Duration(seconds: 2),
                                ),
                              );
                            }
                          },
                          onDownload: (NasFile f) {
                            final conn =
                                ref.read(activeConnectionProvider).valueOrNull;
                            if (conn == null || conn.id == null) return;
                            // ignore: discarded_futures
                            unawaited(
                                _downloadTappedFile(context, ref, conn.id!, f));
                          },
                          onDirectoryTap: (dirPath) {
                            ref
                                .read(navigationStackProvider.notifier)
                                .push(dirPath);
                          },
                          onDirectoryLongPress: (dir) {
                            // ignore: discarded_futures
                            unawaited(showFolderActionSheet(
                              context: context,
                              ref: ref,
                              folder: dir,
                            ));
                          },
                          onFileTap: (tappedFile) async {
                            // MSEL-01-S2：多选模式下 tap 全部归勾选（toggle 幂等
                            // add / remove 成对），播放路径完全旁路。
                            if (multiSelect) {
                              final notifier = ref
                                  .read(multiSelectSelectionProvider.notifier);
                              final selected = ref
                                      .read(multiSelectSelectionProvider)[
                                          currentPath]
                                      ?.contains(tappedFile.path) ??
                                  false;
                              if (selected) {
                                notifier.remove(currentPath, tappedFile.path);
                              } else {
                                notifier.toggle(currentPath, tappedFile.path);
                              }
                              return;
                            }
                            debugPrint(
                                '[Browser] onFileTap: ${tappedFile.path}');
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
                                // REF-19: threshold single-sourced via
                                // ProgressDao.shouldSave (PRG-T03 policy).
                                if (progress != null &&
                                    ProgressDao.shouldSave(
                                        progress.positionMs)) {
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
                                debugPrint(
                                    '[Browser] play: progress resume lookup '
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
                            ref.read(currentPlayQueueProvider.notifier).state =
                                queue;
                            final connId = ref
                                .read(activeConnectionProvider)
                                .valueOrNull
                                ?.id;
                            ref
                                .read(lastQueueConnectionIdProvider.notifier)
                                .state = connId;
                            await goRouter.push('/player');
                          },
                          // MSEL-01-S2 否定面：多选模式下长按禁用（进度恢复
                          // sheet 不弹），tap 全部归勾选。
                          onFileLongPress: multiSelect
                              ? null
                              : (tappedFile) {
                                  // ignore: discarded_futures
                                  unawaited(showFileLongPressSheet(
                                    context: context,
                                    ref: ref,
                                    file: tappedFile,
                                  ));
                                },
                        ),
                      );
                    },
                  ),
          ),

          // MSEL-01-S4 / §8-R2 裁决：底部操作栏为普通 Container 包 SafeArea
          // 置于 Column 尾部（非 BottomAppBar）——布局上天然让位，滚动到底
          // 最后一行不被遮挡。
          if (multiSelect) _MultiSelectBar(currentPath: currentPath),
        ],
      ),
    );
  }
}

// ── SRCH-01-S9: search results view ─────────────────────────────────────────────

/// 搜索结果内容区（panelOpen 分支）：顶部状态行 + 结果列表。
/// 不用 RefreshIndicator 包裹——搜索是只读探索，无下拉刷新语义。
class _SearchResultsView extends ConsumerWidget {
  const _SearchResultsView();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(searchSessionProvider);
    // 门禁表达式与主列表 playNextEnabled 完全一致（onFileTap 参照系）。
    final playNextEnabled =
        (ref.watch(audioPlayingProvider).valueOrNull ?? false) &&
            ref.watch(currentPlayQueueProvider) != null;

    final Widget statusLine;
    if (session.running) {
      statusLine = Row(
        children: [
          Expanded(
            child: Text('已扫 ${session.dirsScanned} 个目录…'),
          ),
          IconButton(
            icon: const Icon(Icons.cancel),
            tooltip: '停止扫描',
            onPressed: () =>
                ref.read(searchSessionProvider.notifier).cancelScan(),
          ),
        ],
      );
    } else if (session.query.isNotEmpty) {
      // 单条 Text 组合：命中数 + 截断提示 + 跳过提示（文案由域层常量拼出）。
      statusLine = Text(
        '命中 ${session.hits.length}'
        '${session.truncated ? '（已扫描前 $kSearchMaxDirs 个目录）' : ''}'
        '${session.skippedDirs > 0 ? '，${session.skippedDirs} 个目录无法读取' : ''}',
      );
    } else {
      statusLine = const SizedBox.shrink();
    }

    final Widget body;
    if (session.hits.isEmpty) {
      // S9 条件面：「无匹配结果」仅「hits 空且 done」渲染；running 期内容区留空。
      body = (session.query.isEmpty || session.running)
          ? const SizedBox.shrink()
          : const Center(child: Text('无匹配结果'));
    } else {
      body = ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: session.hits.length,
        itemBuilder: (context, index) {
          final hit = session.hits[index];
          // trailing 直接暴露 IconButton 本体（门禁断言 tile.trailing as
          // IconButton）；disabled 态 onPressed=null 原生吞点击，无需再包手势。
          final nextIcon = IconButton(
            icon: const Icon(Icons.queue_music),
            onPressed: playNextEnabled
                ? () {
                    // ignore: discarded_futures
                    _queueNext(context, ref, hit);
                  }
                : null,
            tooltip: playNextEnabled ? '加入下一曲' : '请先开始播放后再用此功能',
          );
          return ListTile(
            leading: Icon(_searchLeadingIcon(hit.file),
                color: _searchLeadingColor(hit.file)),
            title: Text(
              hit.file.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              hit.parentDirPath,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: nextIcon,
            onTap: () {
              // ignore: discarded_futures
              _playSearchHit(context, ref, hit);
            },
          );
        },
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: SizedBox(width: double.infinity, child: statusLine),
        ),
        Expanded(child: body),
      ],
    );
  }
}

// Leading 图标与配色沿用 AudioFileListTile 规则（file_list_item.dart）。
IconData _searchLeadingIcon(NasFile file) {
  switch (file.audioType) {
    case AudioFileType.audiobook:
      return Icons.headphones;
    case AudioFileType.music:
      return Icons.music_note_outlined;
    case null:
      return Icons.audio_file_outlined;
  }
}

Color _searchLeadingColor(NasFile file) {
  switch (file.audioType) {
    case AudioFileType.audiobook:
      return Colors.deepOrange;
    case AudioFileType.music:
      return Colors.blue;
    case null:
      return Colors.grey;
  }
}

// ── SRCH-01-S10/S11: hit actions ────────────────────────────────────────────────

/// S10 行点击 = 立即播放。进度查询段完全镜像 onFileTap（conn 判空、BUG-18
/// try/catch、shouldSave 阈值、showProgressResumeDialog 三分支）；建队段以
/// 命中父目录为根跑 BRW-01 收集器后镜像 onFileTap 尾段。
Future<void> _playSearchHit(
  BuildContext context,
  WidgetRef ref,
  SearchHit hit,
) async {
  debugPrint('[Browser] search hit tap: ${hit.file.path}');

  int? startPositionMs;
  final conn = ref.read(activeConnectionProvider).valueOrNull;
  if (conn != null && conn.id != null) {
    try {
      final progress = await ref.read(progressForFileProvider((
        connectionId: conn.id!,
        filePath: hit.file.path,
      )).future);
      if (!context.mounted) return;
      if (progress != null && ProgressDao.shouldSave(progress.positionMs)) {
        final container = ProviderScope.containerOf(context);
        final resume =
            await showProgressResumeDialog(context, container, progress);
        if (resume == true) {
          startPositionMs = progress.positionMs;
        } else if (resume == false) {
          ref.read(clearProgressProvider)(
            connectionId: conn.id!,
            filePath: hit.file.path,
          );
        }
        // resume == null（对话框被直接关闭）→ 不带起始位置播放。
      }
    } catch (e) {
      // 查询失败 → 按无进度从头播放，不中断流程（catch-log 裁决）。
      debugPrint('[Browser] search play: progress resume lookup '
          'failed, playing from beginning: $e');
    }
  }
  if (!context.mounted) return;

  final goRouter = GoRouter.of(context);
  final messenger = ScaffoldMessenger.of(context);

  // 建队收集的 fetchDir 与主列表「从此处播放」（_collectFolder）同款缓存读，
  // 失败面完全一致（spec S10② 镜像）；collectFolderAudio 整体失败语义不变。
  FolderScanResult? collected;
  try {
    collected = await collectFolderAudio(
      rootPath: hit.parentDirPath,
      fetchDir: (p) => ref.read(directoryContentsProvider(p).future),
    );
  } catch (e) {
    debugPrint('[Browser] search play: folder collect failed: '
        '${redactUrlForLog(e.toString())}');
    messenger.showSnackBar(
      const SnackBar(content: Text('无法读取文件夹内容，请检查连接')),
    );
    return;
  }

  final startIndex = collected.files.indexWhere((f) => f.path == hit.file.path);
  if (startIndex < 0) {
    messenger.showSnackBar(
      const SnackBar(content: Text('该文件已不存在')),
    );
    return;
  }

  // 建队镜像 onFileTap 尾段：withMode 只读 playModeProvider；写双 provider
  // 后 push /player；截断时沿用 BRW-01 文案。
  final queue = PlayQueue(
    files: collected.files,
    currentIndex: startIndex,
    startPositionMs: startPositionMs,
  ).withMode(ref.read(playModeProvider));
  ref.read(currentPlayQueueProvider.notifier).state = queue;
  ref.read(lastQueueConnectionIdProvider.notifier).state =
      ref.read(activeConnectionProvider).valueOrNull?.id;
  if (collected.truncated) {
    messenger.showSnackBar(
      const SnackBar(content: Text('文件夹较大，已截取前 $kFolderScanMaxFiles 首')),
    );
  }
  await goRouter.push('/player');
}

/// S11「下一首播」按钮：插队不打断当前曲；false 为防御分支提示。
Future<void> _queueNext(
  BuildContext context,
  WidgetRef ref,
  SearchHit hit,
) async {
  final messenger = ScaffoldMessenger.of(context);
  final ok = await ref.read(insertAfterCurrentProvider)(hit.file);
  if (!context.mounted) return;
  if (ok) {
    messenger.showSnackBar(
      SnackBar(
        content: Text('已加入下一曲：${hit.file.name}'),
        duration: const Duration(seconds: 2),
      ),
    );
  } else {
    messenger.showSnackBar(
      const SnackBar(content: Text('请先开始播放后再用此功能')),
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
  final void Function(NasFile dir)? onDirectoryLongPress;
  final void Function(NasFile file) onFileTap;
  final void Function(NasFile file)? onFileLongPress;
  final void Function(NasFile file)? onPlayNext;
  final void Function(NasFile file)? onDownload;
  final bool playNextEnabled;

  /// MSEL-01：多选模式（AudioFileListTile 行形态切换；目录行不受影响）。
  final bool multiSelect;

  /// 当前目录已勾选 path 集（仅多选模式使用）。
  final Set<String>? checkedPaths;

  const _FileList({
    required this.files,
    this.onDirectoryTap,
    this.onDirectoryLongPress,
    required this.onFileTap,
    this.onFileLongPress,
    this.onPlayNext,
    this.onDownload,
    this.playNextEnabled = false,
    this.multiSelect = false,
    this.checkedPaths,
  });

  @override
  Widget build(BuildContext context) {
    // MSEL-01：多选模式改用非虚拟化滚动列——全部行持续构建/可解析，勾选框
    // 跨滚动稳定（S4 滚动几何门禁依赖行元素持续可解析）；普通模式保持现状
    // ListView 虚拟化（INV1 渲染与交互路径现状等价）。
    if (multiSelect) {
      return SingleChildScrollView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          children: [
            for (var i = 0; i < files.length; i++) ...[
              _buildRow(context, i),
              if (i < files.length - 1) const Divider(height: 1, indent: 72),
            ],
          ],
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: files.length,
      separatorBuilder: (_, __) => const Divider(height: 1, indent: 72),
      itemBuilder: _buildRow,
    );
  }

  Widget _buildRow(BuildContext context, int index) {
    final file = files[index];
    if (file.isDirectory) {
      // B3-2：DirectoryListTile 无勾选位，多选模式下仍可点击导航。
      return DirectoryListTile(
        key: ValueKey(file.path),
        file: file,
        onTap:
            onDirectoryTap != null ? (_) => onDirectoryTap!(file.path) : null,
        onLongPress: onDirectoryLongPress != null
            ? () => onDirectoryLongPress!(file)
            : null,
      );
    }
    return AudioFileListTile(
      key: ValueKey(file.path),
      file: file,
      multiSelect: multiSelect,
      checked: checkedPaths?.contains(file.path) ?? false,
      onTap: (_) {
        // ignore: discarded_futures
        onFileTap(file);
      },
      onLongPress:
          onFileLongPress != null ? () => onFileLongPress!(file) : null,
      onPlayNext: (!multiSelect && onPlayNext != null)
          ? (_) => onPlayNext!(file)
          : null,
      onDownload: (!multiSelect && onDownload != null)
          ? (_) => onDownload!(file)
          : null,
      playNextEnabled: playNextEnabled,
    );
  }
}

// ── Folder-level actions (BRW-01 + DL-01-S8 third entry) ────────────────────────

/// 目录长按菜单（@visibleForTesting 顶层函数）：BRW-01 两项原样 +
/// DL-01-S8 第三项「下载此文件夹」。
Future<void> showFolderActionSheet({
  required BuildContext context,
  required WidgetRef ref,
  required NasFile folder,
}) async {
  showModalBottomSheet<void>(
    context: context,
    builder: (sheetContext) {
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.play_circle_outline),
              title: const Text('从此处播放'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                // ignore: discarded_futures
                _playFromFolder(context, ref, folder);
              },
            ),
            ListTile(
              leading: const Icon(Icons.playlist_add),
              title: const Text('加入播放单…'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                // ignore: discarded_futures
                _addToPlaylistFlow(context, ref, folder);
              },
            ),
            ListTile(
              // SDK 无 Icons.folder_download(_outlined)；取语义最接近的
              // offline-download 图标（与文件项 download_outlined 区分）。
              leading: const Icon(Icons.download_for_offline_outlined),
              title: const Text('下载此文件夹'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                // ignore: discarded_futures
                unawaited(_downloadFolder(context, ref, folder));
              },
            ),
          ],
        ),
      );
    },
  );
}

/// DL-01-S8：扫描整目录音频并入下载队列。复用 BRW-01 的 loading 对话框与
/// collectFolderAudio 整体失败语义；不 push /player、不写队列 provider。
Future<void> _downloadFolder(
  BuildContext context,
  WidgetRef ref,
  NasFile dir,
) async {
  final result = await _scanFolderWithLoading(context, ref, dir);
  if (result == null) return; // 扫描失败：固定文案 SnackBar 已由 scan 显示
  if (!context.mounted) return;
  if (result.files.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('该文件夹没有音频文件')),
    );
    return;
  }
  final connId = ref.read(activeConnectionProvider).valueOrNull?.id;
  if (connId == null) return;
  final messenger = ScaffoldMessenger.of(context);
  final manager = ref.read(downloadManagerProvider);
  await manager.enqueueMany(result.files.map((f) => (connId, f)).toList());
  // 单条 SnackBar 同时承载入队数与截断提示（ScaffoldMessenger 排队展示会
  // 让第二条在测试/短时间内不可见）——截断文案 textContaining 可命中。
  messenger.showSnackBar(
    SnackBar(
      content: Text(
        '已加入 ${result.files.length} 首到下载队列'
        '${result.truncated ? '，已截取前 $kFolderScanMaxFiles 首' : ''}',
      ),
    ),
  );
}

// ── File long-press sheet (BUG-18 progress resume) ─────────────────────────────

/// 文件长按菜单（@visibleForTesting 顶层函数）：
///  • BUG-18 加固保持——进度查询失败 → 静默返回；
///  • BUG-18 原行为——进度为 null → 早退不弹层；
///  • DL-01-S7 v2 裁决（2026-08-25）：下载入口迁至文件行尾按钮，
///    本菜单不再含「下载此文件」项。
Future<void> showFileLongPressSheet({
  required BuildContext context,
  required WidgetRef ref,
  required NasFile file,
}) async {
  final conn = ref.read(activeConnectionProvider).valueOrNull;
  if (conn == null || conn.id == null) return;

  // BUG-18: 同类裸奔点加固（cr-0805 F1 勘察补充）。查询失败 → 无进度可
  // 展示，静默返回（catch-log 裁决，日志照留）。
  PlayProgress? progress;
  try {
    progress = await ref.read(progressForFileProvider((
      connectionId: conn.id!,
      filePath: file.path,
    )).future);
  } catch (e) {
    debugPrint('[Browser] long-press: progress resume lookup '
        'failed: $e');
    return;
  }
  if (!context.mounted) return;
  // 类型提升锚点：局部可变变量在下方 bottom sheet 闭包内不提升，
  // 先落到 stable final 供闭包读取（BUG-18）。
  final resolvedProgress = progress;
  // BUG-18 原行为：无进度 → 早退不弹层（DL-01-S7 v2 回退裁决）。
  if (resolvedProgress == null) return;

  await showModalBottomSheet<void>(
    context: context,
    builder: (sheetContext) {
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                file.name,
                style: Theme.of(context).textTheme.titleMedium,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.red),
              title: const Text('清除播放进度'),
              subtitle: Text(
                '已保存进度 ${resolvedProgress.formattedPosition}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              onTap: () {
                ref.read(clearProgressProvider)(
                  connectionId: resolvedProgress.connectionId,
                  filePath: resolvedProgress.filePath,
                );
                Navigator.of(sheetContext).pop();
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
}

/// DL-01-S7 下载动作：已有 pending/downloading/done 行 → 「已在下载列表中」
/// 不入队；无行或 failed → 入队并提示「已加入下载队列」。fire-and-forget，
/// 泵自行启动；messenger 在 await 前捕获（P14）。
Future<void> _downloadTappedFile(
  BuildContext context,
  WidgetRef ref,
  int connectionId,
  NasFile file,
) async {
  final messenger = ScaffoldMessenger.of(context);
  final dao = ref.read(downloadDaoProvider);
  final existing = await dao.findByLocation(connectionId, file.path);
  if (existing != null && existing.status != DownloadStatus.failed) {
    messenger.showSnackBar(const SnackBar(content: Text('已在下载列表中')));
    return;
  }
  final manager = ref.read(downloadManagerProvider);
  await manager.enqueueMany([(connectionId, file)]);
  messenger.showSnackBar(const SnackBar(content: Text('已加入下载队列')));
}

/// Scans [dir]'s subtree with a non-dismissable loading dialog.
///
/// Returns null (after showing the fixed-error SnackBar) when any layer of
/// [collectFolderAudio] throws; never leaks partial results (BRW-01-S3/S6).
Future<FolderScanResult?> _scanFolderWithLoading(
  BuildContext context,
  WidgetRef ref,
  NasFile dir,
) async {
  final navigator = Navigator.of(context);
  final messenger = ScaffoldMessenger.of(context);
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const AlertDialog(
      content: Row(
        children: [
          CircularProgressIndicator(),
          SizedBox(width: 16),
          Expanded(child: Text('正在扫描文件夹…')),
        ],
      ),
    ),
  );
  try {
    final result = await collectFolderAudio(
      rootPath: dir.path,
      fetchDir: (p) => ref.read(directoryContentsProvider(p).future),
    );
    navigator.pop();
    return result;
  } catch (e) {
    debugPrint('[Browser] folder scan failed: $e');
    navigator.pop();
    messenger.showSnackBar(
      const SnackBar(content: Text('无法读取文件夹内容，请检查连接')),
    );
    return null;
  }
}

Future<void> _playFromFolder(
  BuildContext context,
  WidgetRef ref,
  NasFile dir,
) async {
  final goRouter = GoRouter.of(context);
  final messenger = ScaffoldMessenger.of(context);
  final result = await _scanFolderWithLoading(context, ref, dir);
  if (result == null) return;
  if (!context.mounted) return;
  if (result.files.isEmpty) {
    messenger.showSnackBar(
      const SnackBar(content: Text('该文件夹没有音频文件')),
    );
    return;
  }
  // Mirrors onFileTap queue construction; folder entry always plays from the
  // start of the first track, so startPositionMs stays null (BRW-01-INV3).
  final queue = PlayQueue(files: result.files, currentIndex: 0)
      .withMode(ref.read(playModeProvider));
  ref.read(currentPlayQueueProvider.notifier).state = queue;
  ref.read(lastQueueConnectionIdProvider.notifier).state =
      ref.read(activeConnectionProvider).valueOrNull?.id;
  if (result.truncated) {
    messenger.showSnackBar(
      const SnackBar(content: Text('文件夹较大，已截取前 $kFolderScanMaxFiles 首')),
    );
  }
  await goRouter.push('/player');
}

Future<void> _addToPlaylistFlow(
  BuildContext context,
  WidgetRef ref,
  NasFile dir,
) async {
  final result = await _scanFolderWithLoading(context, ref, dir);
  if (result == null) return;
  if (!context.mounted) return;
  if (result.files.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('该文件夹没有音频文件')),
    );
    return;
  }
  // MSEL-01-S6 单一实现点：picker 面板提取为 widgets/playlist_picker_sheet.dart
  // 顶层函数，文件夹加入（此处）与多选批量加入共用同一实现。
  await showPlaylistPickerSheet(context, ref, result.files, title: dir.name);
}

// ── MSEL-01: multi-select bottom action bar ─────────────────────────────────────

/// MSEL-01-S4 底部操作栏：「已选 N 首」+ [全选] [清除] | [加入播放单] [以此播放]。
/// R2 裁决：普通 Container 包 SafeArea 置于内容区尾部（不用 BottomAppBar）。
class _MultiSelectBar extends ConsumerWidget {
  final String currentPath;

  const _MultiSelectBar({required this.currentPath});

  /// ALG1 序解析当前勾选集（快照经 directoryContentsProvider 读缓存，不发起 IO）。
  List<NasFile> _orderedFiles(WidgetRef ref) => orderedSelectedFiles(
        selections: ref.read(multiSelectSelectionProvider),
        snapshotOf: (dir) =>
            ref.read(directoryContentsProvider(dir)).valueOrNull,
      );

  Future<void> _addToPlaylist(BuildContext context, WidgetRef ref) async {
    final files = _orderedFiles(ref);
    if (files.isEmpty) return;
    final ok = await ref.read(showPlaylistPickerProvider)(context, ref, files);
    // S6：成功回调（true）才退多选并 clear()；关闭面板 ≠ 成功，不得误清。
    if (!ok || !context.mounted) return;
    ref.read(multiSelectModeProvider.notifier).state = false;
    ref.read(multiSelectSelectionProvider.notifier).clear();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count = ref
        .watch(multiSelectSelectionProvider)
        .values
        .fold<int>(0, (sum, s) => sum + s.length);
    final dirSnapshot =
        ref.watch(directoryContentsProvider(currentPath)).valueOrNull;
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: Theme.of(context).dividerColor),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '已选 $count 首',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              TextButton(
                onPressed: () => ref
                    .read(multiSelectSelectionProvider.notifier)
                    .selectAllCurrent(currentPath, dirSnapshot ?? const []),
                child: const Text('全选'),
              ),
              TextButton(
                onPressed: () =>
                    ref.read(multiSelectSelectionProvider.notifier).clear(),
                child: const Text('清除'),
              ),
              TextButton(
                onPressed:
                    count == 0 ? null : () => _addToPlaylist(context, ref),
                child: const Text('加入播放单'),
              ),
              FilledButton(
                onPressed: count == 0
                    ? null
                    : () {
                        // ignore: discarded_futures
                        ref.read(playSelectionProvider)(context);
                      },
                child: const Text('以此播放'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
