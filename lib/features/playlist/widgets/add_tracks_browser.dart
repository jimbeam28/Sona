// lib/features/playlist/widgets/add_tracks_browser.dart
// Bottom sheet for browsing WebDAV directories and adding tracks to a playlist.

// ignore_for_file: use_build_context_synchronously

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/webdav_client.dart';
import '../../../shared/models/nas_file.dart';
import '../../browser/browser_provider.dart';
import '../../browser/widgets/breadcrumb_bar.dart';
import '../playlist_provider.dart';

/// Opens the add-tracks browser as a modal bottom sheet.
///
/// Uses a [ProviderScope] override to inject an independent
/// [NavigationStackNotifier] so it does not share navigation state
/// with the main browser tab.
void showAddTracksBrowser(BuildContext context, int playlistId) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (_) => ProviderScope(
      overrides: [
        navigationStackProvider
            .overrideWith((ref) => NavigationStackNotifier()),
      ],
      child: _AddTracksBrowserSheet(playlistId: playlistId),
    ),
  );
}

class _AddTracksBrowserSheet extends ConsumerStatefulWidget {
  final int playlistId;

  const _AddTracksBrowserSheet({required this.playlistId});

  @override
  ConsumerState<_AddTracksBrowserSheet> createState() =>
      _AddTracksBrowserSheetState();
}

class _AddTracksBrowserSheetState
    extends ConsumerState<_AddTracksBrowserSheet> {
  final Set<String> _selectedPaths = {};

  @override
  Widget build(BuildContext context) {
    final navStack = ref.watch(navigationStackProvider);
    final currentPath = navStack.last;
    final contentsAsync = ref.watch(directoryContentsProvider(currentPath));

    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return Column(
          children: [
            // Header bar
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      '添加曲目',
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                  ),
                  TextButton(
                    onPressed: () {
                      final allPaths = _allAudioPaths(contentsAsync);
                      if (_selectedPaths.length == allPaths.length &&
                          allPaths.isNotEmpty) {
                        setState(() => _selectedPaths.clear());
                      } else {
                        setState(() => _selectedPaths.addAll(allPaths));
                      }
                    },
                    child: Text(_selectAllLabel(contentsAsync)),
                  ),
                  FilledButton(
                    onPressed: _selectedPaths.isEmpty
                        ? null
                        : () {
                            final files = _selectedPaths
                                .map((p) => NasFile(
                                      name: p.split('/').last,
                                      path: p,
                                      isDirectory: false,
                                    ))
                                .toList();
                            ref
                                .read(addTracksToPlaylistProvider)
                                (widget.playlistId, files)
                                .then((_) {
                              if (mounted) Navigator.of(context).pop();
                            });
                          },
                    child: Text('确认 (${_selectedPaths.length})'),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            // Breadcrumb
            const BreadcrumbBar(),
            const Divider(height: 1),
            // Directory contents
            Expanded(
              child: contentsAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (error, _) => Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.error_outline,
                            size: 48,
                            color: Theme.of(context).colorScheme.error),
                        const SizedBox(height: 16),
                        Text(
                          error is WebDavException
                              ? error.message
                              : '加载失败：$error',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              color: Theme.of(context).colorScheme.error),
                        ),
                        const SizedBox(height: 24),
                        OutlinedButton.icon(
                          onPressed: () => ref.invalidate(
                              directoryContentsProvider(currentPath)),
                          icon: const Icon(Icons.refresh),
                          label: const Text('重试'),
                        ),
                      ],
                    ),
                  ),
                ),
                data: (files) {
                  if (files.isEmpty) {
                    return const Center(
                      child:
                          Text('此目录为空', style: TextStyle(color: Colors.grey)),
                    );
                  }
                  return ListView.separated(
                    controller: scrollController,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: files.length,
                    separatorBuilder: (_, __) =>
                        const Divider(height: 1, indent: 56),
                    itemBuilder: (context, index) {
                      final file = files[index];
                      if (file.isDirectory) {
                        return ListTile(
                          leading:
                              const Icon(Icons.folder, color: Colors.amber),
                          title: Text(file.name),
                          onTap: () => ref
                              .read(navigationStackProvider.notifier)
                              .push(file.path),
                        );
                      }
                      final selected = _selectedPaths.contains(file.path);
                      return ListTile(
                        leading: Checkbox(
                          value: selected,
                          onChanged: (_) {
                            setState(() {
                              if (selected) {
                                _selectedPaths.remove(file.path);
                              } else {
                                _selectedPaths.add(file.path);
                              }
                            });
                          },
                        ),
                        title: Text(file.name,
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                        onTap: () {
                          setState(() {
                            if (selected) {
                              _selectedPaths.remove(file.path);
                            } else {
                              _selectedPaths.add(file.path);
                            }
                          });
                        },
                      );
                    },
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  String _selectAllLabel(AsyncValue<List<NasFile>> contentsAsync) {
    final allPaths = _allAudioPaths(contentsAsync);
    if (_selectedPaths.length == allPaths.length && allPaths.isNotEmpty) {
      return '取消全选';
    }
    return '全选';
  }

  Set<String> _allAudioPaths(AsyncValue<List<NasFile>> contentsAsync) {
    final files = contentsAsync.valueOrNull;
    if (files == null) return {};
    return files.where((f) => !f.isDirectory).map((f) => f.path).toSet();
  }
}
