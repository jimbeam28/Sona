// lib/features/downloads/downloads_screen.dart
// DL-01-S9 offline-download management page (/downloads).
//
// Lists the active connection's download entries with state badges and a
// per-state trailing button matrix (取消 / 重试+删除 / 删除), a storage footer
// (共占用 X + 清空全部 with confirm dialog), and a 1-second poll timer that
// runs only while at least one row is downloading (P13: cancelled in dispose).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/services/download_manager.dart' show DownloadManager;
import '../../shared/di/providers.dart';
import '../../shared/models/download_record.dart';

class DownloadsScreen extends ConsumerStatefulWidget {
  const DownloadsScreen({super.key});

  @override
  ConsumerState<DownloadsScreen> createState() => _DownloadsScreenState();
}

class _DownloadsScreenState extends ConsumerState<DownloadsScreen> {
  static const _refreshInterval = Duration(seconds: 1);

  Timer? _refreshTimer;
  List<DownloadRecord> _rows = const <DownloadRecord>[];
  int _totalBytes = 0;
  bool _loadedOnce = false;

  @override
  void initState() {
    super.initState();
    unawaited(_reload());
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _refreshTimer = null;
    super.dispose();
  }

  Future<void> _reload() async {
    final connectionId = ref.read(activeConnectionProvider).valueOrNull?.id;
    if (connectionId == null) {
      // 无活跃连接：不查询 dao（S9 否定断言）。
      if (!mounted) return;
      setState(() {
        _rows = const <DownloadRecord>[];
        _totalBytes = 0;
        _loadedOnce = true;
      });
      _syncRefreshTimer();
      return;
    }
    final dao = ref.read(downloadDaoProvider);
    final rows = await dao.listByConnection(connectionId);
    final total = await dao.totalBytesByConnection(connectionId);
    if (!mounted) return;
    setState(() {
      _rows = rows;
      _totalBytes = total;
      _loadedOnce = true;
    });
    _syncRefreshTimer();
  }

  /// P13 companion: the periodic refresh only lives while some row is
  /// actually downloading; otherwise it is cancelled promptly.
  void _syncRefreshTimer() {
    final hasDownloading =
        _rows.any((r) => r.status == DownloadStatus.downloading);
    if (hasDownloading && _refreshTimer == null) {
      _refreshTimer = Timer.periodic(_refreshInterval, (_) => _reload());
    } else if (!hasDownloading && _refreshTimer != null) {
      _refreshTimer?.cancel();
      _refreshTimer = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    // Connection switches / first resolution both funnel through here.
    ref.listen(activeConnectionProvider, (previous, next) {
      unawaited(_reload());
    });

    final connection = ref.watch(activeConnectionProvider).valueOrNull;
    final connectionId = connection?.id;

    return Scaffold(
      appBar: AppBar(title: const Text('离线下载管理')),
      body: connectionId == null
          ? const Center(child: Text('请先连接 NAS'))
          : !_loadedOnce
              ? const Center(child: CircularProgressIndicator())
              : _buildList(context, connectionId),
    );
  }

  Widget _buildList(BuildContext context, int connectionId) {
    if (_rows.isEmpty) {
      return const Center(child: Text('暂无下载任务'));
    }
    return ListView.builder(
      itemCount: _rows.length + 1,
      itemBuilder: (context, index) {
        if (index == _rows.length) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Expanded(child: Text('共占用 $_totalBytes B')),
                TextButton(
                  onPressed: () =>
                      unawaited(_confirmClearAll(context, connectionId)),
                  child: const Text('清空全部'),
                ),
              ],
            ),
          );
        }
        final record = _rows[index];
        return _DownloadRow(
          record: record,
          onCancel: () =>
              unawaited(_actThenReload((m) => m.cancel(record.id!))),
          onRetry: () => unawaited(_actThenReload((m) => m.retry(record.id!))),
          onDelete: () =>
              unawaited(_actThenReload((m) => m.deleteEntry(record.id!))),
        );
      },
    );
  }

  Future<void> _actThenReload(
    Future<void> Function(DownloadManager manager) action,
  ) async {
    await action(ref.read(downloadManagerProvider));
    await _reload();
  }

  Future<void> _confirmClearAll(BuildContext context, int connectionId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('清空全部下载任务？'),
        content: const Text('将删除所有下载记录与本地文件，进行中的任务一并取消'),
        actions: [
          // 确认键必须是 AlertDialog 内最后一个 TextButton（S9 定位约定）。
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('清空'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await ref.read(downloadManagerProvider).clearAll(connectionId);
    await _reload();
  }
}

// ── Row ──────────────────────────────────────────────────────────────────────

class _DownloadRow extends StatelessWidget {
  final DownloadRecord record;
  final VoidCallback onCancel;
  final VoidCallback onRetry;
  final VoidCallback onDelete;

  const _DownloadRow({
    required this.record,
    required this.onCancel,
    required this.onRetry,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final trailing = <Widget>[];
    switch (record.status) {
      case DownloadStatus.pending:
      case DownloadStatus.downloading:
        trailing.add(IconButton(
          icon: const Icon(Icons.close),
          tooltip: '取消',
          onPressed: onCancel,
        ));
        break;
      case DownloadStatus.failed:
        // failed 行按钮矩阵 [重试, 删除] —— 重试在前删除在后（S9 定位约定）。
        trailing.add(IconButton(
          icon: const Icon(Icons.refresh),
          tooltip: '重试',
          onPressed: onRetry,
        ));
        trailing.add(IconButton(
          icon: const Icon(Icons.delete_outline),
          tooltip: '删除',
          onPressed: onDelete,
        ));
        break;
      case DownloadStatus.done:
        trailing.add(IconButton(
          icon: const Icon(Icons.delete_outline),
          tooltip: '删除',
          onPressed: onDelete,
        ));
        break;
      default:
        break;
    }

    return ListTile(
      title: Text(
        record.fileName,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: _buildSubtitle(),
      isThreeLine: true,
      trailing: trailing.isEmpty
          ? null
          : Row(mainAxisSize: MainAxisSize.min, children: trailing),
    );
  }

  Widget? _buildSubtitle() {
    final children = <Widget>[
      Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _StatusBadge(status: record.status),
          if (record.status == DownloadStatus.done &&
              record.remoteSize != null) ...[
            const SizedBox(width: 8),
            Text(
              formatDownloadSize(record.remoteSize!),
              style: const TextStyle(color: Colors.grey),
            ),
          ],
        ],
      ),
    ];
    if (record.status == DownloadStatus.downloading) {
      final remote = record.remoteSize;
      final double? value = (remote != null && remote > 0)
          ? record.bytesDownloaded / remote
          : null;
      children.add(const SizedBox(height: 6));
      children.add(LinearProgressIndicator(value: value?.clamp(0.0, 1.0)));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: children,
    );
  }
}

// ── Badge ────────────────────────────────────────────────────────────────────

class _StatusBadge extends StatelessWidget {
  final String status;

  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status) {
      DownloadStatus.pending => ('等待中', Colors.grey),
      DownloadStatus.downloading => ('下载中', Colors.blue),
      DownloadStatus.done => ('已完成', Colors.green),
      DownloadStatus.failed => ('失败', Colors.red),
      _ => (status, Colors.grey),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(label, style: TextStyle(color: color, fontSize: 12)),
    );
  }
}

/// Human-readable byte size (300 → '300 B'; small sizes keep raw numbers).
String formatDownloadSize(int bytes) {
  if (bytes >= 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
  if (bytes >= 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  if (bytes >= 1024) {
    return '${(bytes / 1024).toStringAsFixed(1)} KB';
  }
  return '$bytes B';
}
