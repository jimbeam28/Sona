import 'package:flutter/material.dart';

import '../../../shared/models/play_queue.dart';

typedef QueueItemSelect = Future<bool> Function(int index);

/// Shared queue sheet used by both the full player and the mini player.
class QueueSheet extends StatelessWidget {
  final PlayQueue queue;
  final QueueItemSelect onSelectIndex;
  final String errorMessage;

  const QueueSheet({
    super.key,
    required this.queue,
    required this.onSelectIndex,
    required this.errorMessage,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        minChildSize: 0.35,
        maxChildSize: 0.9,
        builder: (context, scrollController) {
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  '播放队列 (${queue.length})',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: ListView.builder(
                  controller: scrollController,
                  itemCount: queue.length,
                  itemBuilder: (context, index) {
                    final file = queue.files[index];
                    final isCurrent = index == queue.currentIndex;
                    return ListTile(
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
                      trailing: isCurrent
                          ? Text(
                              '当前',
                              style: TextStyle(
                                fontSize: 12,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                            )
                          : null,
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
          );
        },
      ),
    );
  }
}
