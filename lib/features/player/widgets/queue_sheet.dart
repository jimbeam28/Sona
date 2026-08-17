import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/di/providers.dart'; // REF-05: live 数据源经桥接取

typedef QueueItemSelect = Future<bool> Function(int index);
typedef QueueItemRemove = void Function(int index);

/// Shared queue sheet used by both the full player and the mini player.
/// REF-05 (cr-20260816-0802 D3): live data source — watches
/// [currentPlayQueueProvider] instead of a constructor snapshot, so deletes
/// refresh the list in place, the '当前' highlight follows the queue, and an
/// emptied queue renders an empty state.
class QueueSheet extends ConsumerWidget {
  final QueueItemSelect onSelectIndex;
  final QueueItemRemove onRemoveIndex;
  final String errorMessage;

  const QueueSheet({
    super.key,
    required this.onSelectIndex,
    required this.onRemoveIndex,
    required this.errorMessage,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final queue = ref.watch(currentPlayQueueProvider);
    final maxHeight = MediaQuery.of(context).size.height * 0.7;
    return SafeArea(
      child: SizedBox(
        height: maxHeight,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                queue == null ? '播放队列' : '播放队列 (${queue.length})',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            const Divider(height: 1),
            if (queue == null || queue.length == 0)
              const Expanded(
                child: Center(child: Text('队列为空')),
              )
            else
              Expanded(
                child: ListView.builder(
                  itemCount: queue.length,
                  itemBuilder: (context, index) {
                    final file = queue.files[index];
                    final isCurrent = index == queue.currentIndex;
                    return ListTile(
                      key: ValueKey(file.path),
                      leading: Icon(
                        isCurrent
                            ? Icons.play_arrow
                            : Icons.music_note_outlined,
                        color: isCurrent
                            ? Theme.of(context).colorScheme.primary
                            : Colors.grey,
                      ),
                      title: Text(
                        file.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight:
                              isCurrent ? FontWeight.bold : FontWeight.normal,
                          color: isCurrent
                              ? Theme.of(context).colorScheme.primary
                              : null,
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
                  },
                ),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
