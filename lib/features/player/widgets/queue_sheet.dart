import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/di/providers.dart'; // REF-05: live 数据源经桥接取
import '../../../shared/models/play_queue.dart';

typedef QueueItemSelect = Future<bool> Function(int index);
typedef QueueItemRemove = void Function(int index);
typedef QueueItemReorder = void Function(int oldIndex, int newIndex);

/// Shared queue sheet used by both the full player and the mini player.
/// REF-05 (cr-20260816-0802 D3): live data source — watches
/// [currentPlayQueueProvider] instead of a constructor snapshot, so deletes
/// refresh the list in place, the '当前' highlight follows the queue, and an
/// emptied queue renders an empty state.
///
/// PLY-01: when [onReorderIndex] is supplied and the queue is reorderable
/// (non-shuffle, more than one track) the list becomes a
/// ReorderableListView with long-press drag handles; shuffle queues keep the
/// plain list plus a hint label (PLY-01-S8/INV3 double gate).
class QueueSheet extends ConsumerWidget {
  final QueueItemSelect onSelectIndex;
  final QueueItemRemove onRemoveIndex;
  final QueueItemReorder? onReorderIndex;
  final String errorMessage;

  const QueueSheet({
    super.key,
    required this.onSelectIndex,
    required this.onRemoveIndex,
    required this.errorMessage,
    this.onReorderIndex,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final queue = ref.watch(currentPlayQueueProvider);
    final maxHeight = MediaQuery.of(context).size.height * 0.7;
    final isShuffle = queue != null && queue.playMode == PlayMode.shuffle;
    final canReorder = onReorderIndex != null &&
        queue != null &&
        !isShuffle &&
        queue.length > 1;
    return SafeArea(
      child: SizedBox(
        height: maxHeight,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Text(
                    queue == null ? '播放队列' : '播放队列 (${queue.length})',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  if (isShuffle)
                    const Text(
                      '随机模式下不可排序',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                ],
              ),
            ),
            const Divider(height: 1),
            if (queue == null || queue.length == 0)
              const Expanded(
                child: Center(child: Text('队列为空')),
              )
            else if (canReorder)
              Expanded(
                child: ReorderableListView.builder(
                  buildDefaultDragHandles: true,
                  itemCount: queue.length,
                  itemBuilder: (context, index) =>
                      _buildTile(context, queue, index),
                  onReorder: (oldIndex, newIndex) {
                    // PLY-01-ALG2: Flutter reports newIndex one past the drop
                    // slot for downward drags; correct before forwarding.
                    if (newIndex > oldIndex) newIndex -= 1;
                    if (newIndex == oldIndex) return;
                    onReorderIndex!(oldIndex, newIndex);
                  },
                  proxyDecorator: (child, index, animation) => Material(
                    elevation: 4,
                    borderRadius: BorderRadius.circular(12),
                    color:
                        Theme.of(context).colorScheme.surfaceContainerHighest,
                    shadowColor: Theme.of(context).colorScheme.shadow,
                    child: child,
                  ),
                ),
              )
            else
              Expanded(
                child: ListView.builder(
                  itemCount: queue.length,
                  itemBuilder: (context, index) =>
                      _buildTile(context, queue, index),
                ),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _buildTile(BuildContext context, PlayQueue queue, int index) {
    final file = queue.files[index];
    final isCurrent = index == queue.currentIndex;
    return ListTile(
      // BUG-25 (cr-20260823-1421 F3): the queue legally holds duplicate paths
      // (insertAfterCurrent does not de-duplicate), so the key must compound
      // the position to stay unique within the list (INV1).
      key: ValueKey('$index:${file.path}'),
      leading: Icon(
        isCurrent ? Icons.play_arrow : Icons.music_note_outlined,
        color: isCurrent ? Theme.of(context).colorScheme.primary : Colors.grey,
      ),
      title: Text(
        file.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
          color: isCurrent ? Theme.of(context).colorScheme.primary : null,
        ),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isCurrent)
            Text(
              '当前',
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
          IconButton(
            onPressed: () {
              onRemoveIndex(index);
            },
            icon: const Icon(Icons.close, size: 18),
            color: Colors.grey,
            tooltip: '从队列移除',
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
      onTap: isCurrent
          ? null
          : () async {
              Navigator.of(context).pop();
              final loaded = await onSelectIndex(index);
              if (!loaded && context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(errorMessage)),
                );
              }
            },
    );
  }
}
