// lib/features/connection/connection_list_screen.dart
// CON-04: Connection list UI for switch/edit/delete.
//
// Shows all saved connections and allows the user to switch the active
// connection by tapping a list item.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:go_router/go_router.dart';

import '../../shared/models/connection_config.dart';
import '../browser/browser_provider.dart';
import 'connection_provider.dart';

class ConnectionListScreen extends ConsumerWidget {
  const ConnectionListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final listAsync = ref.watch(connectionListProvider);
    final activeAsync = ref.watch(activeConnectionProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('NAS 连接管理'),
        centerTitle: true,
      ),
      body: listAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              '加载失败：$error',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        ),
        data: (connections) {
          if (connections.isEmpty) {
            return _EmptyState();
          }
          return activeAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (_, __) => _ConnectionListView(
              connections: connections,
              activeId: null,
              onSwitch: (id) => _switchConnection(context, ref, id),
              onDelete: (id) =>
                  _deleteConnection(context, ref, id, connections.length),
            ),
            data: (activeConfig) => _ConnectionListView(
              connections: connections,
              activeId: activeConfig?.id,
              onSwitch: (id) => _switchConnection(context, ref, id),
              onDelete: (id) =>
                  _deleteConnection(context, ref, id, connections.length),
            ),
          );
        },
      ),
    );
  }

  Future<void> _switchConnection(
    BuildContext context,
    WidgetRef ref,
    int id,
  ) async {
    try {
      // Read the target connection for a nicer snackbar message
      final dao = ref.read(connectionDaoProvider);
      final config = await dao.findById(id);

      await ref.read(switchActiveConnectionProvider(id).future);

      // B-1: clear browser cache so the old connection's data isn't shown.
      ref.invalidate(directoryCacheProvider);
      ref.invalidate(navigationStackProvider);

      if (context.mounted) {
        final name = config?.name ?? '连接 $id';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('已切换到「$name」'),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('切换失败：$e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  Future<void> _deleteConnection(
    BuildContext context,
    WidgetRef ref,
    int id,
    int totalCount,
  ) async {
    // CON-T32: protect the last connection — show a warning, not a confirm dialog
    if (totalCount <= 1) {
      if (context.mounted) {
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('无法删除'),
            content: const Text('至少保留一个连接'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('确定'),
              ),
            ],
          ),
        );
      }
      return;
    }

    // Show confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除连接'),
        content: const Text('确定要删除此连接吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) return;

    try {
      await ref.read(deleteConnectionProvider(id).future);

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('连接已删除'),
            behavior: SnackBarBehavior.floating,
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('删除失败：$e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }
}

// ── Connection list view ───────────────────────────────────────────────────────

class _ConnectionListView extends StatelessWidget {
  final List<ConnectionConfig> connections;
  final int? activeId;
  final void Function(int id) onSwitch;
  final void Function(int id) onDelete;

  const _ConnectionListView({
    required this.connections,
    required this.activeId,
    required this.onSwitch,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: connections.length,
      separatorBuilder: (_, __) => const Divider(height: 1, indent: 72),
      itemBuilder: (context, index) {
        final conn = connections[index];
        final isActive = conn.id == activeId;

        final tile = ListTile(
          leading: Icon(
            isActive ? Icons.check_circle : Icons.circle_outlined,
            color: isActive ? Colors.green : Colors.grey.shade400,
            size: 28,
          ),
          title: Row(
            children: [
              Flexible(
                child: Text(
                  conn.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
              ),
              if (isActive) ...[
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: Colors.green.shade200),
                  ),
                  child: Text(
                    '当前',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.green.shade700,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ],
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                conn.url,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.grey.shade600,
                ),
              ),
              Text(
                '${conn.username}  ${conn.basePath}',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
              ),
            ],
          ),
          trailing: PopupMenuButton<String>(
            icon: Icon(Icons.more_vert, color: Colors.grey.shade600),
            onSelected: (value) {
              if (value == 'edit') {
                context.push('/connections/edit/${conn.id}');
              } else if (value == 'delete') {
                onDelete(conn.id!);
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(
                value: 'edit',
                child: Row(
                  children: [
                    Icon(Icons.edit_outlined, size: 20),
                    SizedBox(width: 8),
                    Text('编辑'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'delete',
                child: Row(
                  children: [
                    Icon(Icons.delete_outline, size: 20),
                    SizedBox(width: 8),
                    Text('删除'),
                  ],
                ),
              ),
            ],
          ),
          onTap: isActive ? null : () => onSwitch(conn.id!),
        );

        return Slidable(
          key: ValueKey(conn.id),
          endActionPane: ActionPane(
            motion: const DrawerMotion(),
            children: [
              SlidableAction(
                onPressed: (_) => context.push('/connections/edit/${conn.id}'),
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
                icon: Icons.edit_outlined,
                label: '编辑',
              ),
              SlidableAction(
                onPressed: (_) => onDelete(conn.id!),
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
                icon: Icons.delete_outline,
                label: '删除',
              ),
            ],
          ),
          child: tile,
        );
      },
    );
  }
}

// ── Empty state ─────────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.storage_outlined, size: 64, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            Text(
              '还没有保存的连接',
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey.shade600,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '添加一个 WebDAV 连接即可开始',
              style: TextStyle(fontSize: 14, color: Colors.grey.shade500),
            ),
          ],
        ),
      ),
    );
  }
}
