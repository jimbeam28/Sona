// lib/features/settings/log_viewer_screen.dart
// Log viewer (on-device debug log inspection).
//
// Reads the in-memory ring buffer captured by `installLogBufferHook` in
// main.dart and renders it as a scrollable, filterable list.  Useful when
// running on a real device where flutter logs are not accessible.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/services/log_buffer.dart';

class LogViewerScreen extends StatefulWidget {
  const LogViewerScreen({super.key});

  @override
  State<LogViewerScreen> createState() => _LogViewerScreenState();
}

class _LogViewerScreenState extends State<LogViewerScreen> {
  String _filter = '';
  bool _autoScroll = true;
  final ScrollController _controller = ScrollController();

  @override
  void initState() {
    super.initState();
    LogBuffer.instance.addListener(_onLogChanged);
  }

  @override
  void dispose() {
    LogBuffer.instance.removeListener(_onLogChanged);
    _controller.dispose();
    super.dispose();
  }

  void _onLogChanged() {
    if (!mounted) return;
    setState(() {});
    if (_autoScroll && _controller.hasClients) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_controller.hasClients) return;
        _controller.jumpTo(_controller.position.maxScrollExtent);
      });
    }
  }

  List<LogEntry> get _visible {
    final all = LogBuffer.instance.entries;
    if (_filter.isEmpty) return all;
    final needle = _filter.toLowerCase();
    return all
        .where((e) => e.message.toLowerCase().contains(needle))
        .toList(growable: false);
  }

  Future<void> _copyAll() async {
    final text = _visible.map((e) => e.formatted).join('\n');
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已复制 ${_visible.length} 行')),
    );
  }

  void _clear() {
    LogBuffer.instance.clear();
  }

  @override
  Widget build(BuildContext context) {
    final visible = _visible;

    return Scaffold(
      appBar: AppBar(
        title: const Text('运行日志'),
        centerTitle: true,
        actions: [
          IconButton(
            tooltip: _autoScroll ? '关闭自动滚动' : '开启自动滚动',
            icon: Icon(_autoScroll
                ? Icons.vertical_align_bottom
                : Icons.vertical_align_center),
            onPressed: () => setState(() => _autoScroll = !_autoScroll),
          ),
          IconButton(
            tooltip: '复制全部',
            icon: const Icon(Icons.copy_all_outlined),
            onPressed: visible.isEmpty ? null : _copyAll,
          ),
          IconButton(
            tooltip: '清空',
            icon: const Icon(Icons.delete_outline),
            onPressed: visible.isEmpty ? null : _clear,
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: TextField(
              decoration: const InputDecoration(
                isDense: true,
                prefixIcon: Icon(Icons.filter_alt_outlined),
                hintText: '过滤关键字（如 [Player] 或 setAudioSource）',
                border: OutlineInputBorder(),
              ),
              onChanged: (v) => setState(() => _filter = v),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '共 ${visible.length} 条 / 缓存上限 ${LogBuffer.maxEntries}',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: Colors.grey),
              ),
            ),
          ),
          const Divider(height: 8),
          Expanded(
            child: visible.isEmpty
                ? const Center(
                    child: Text('暂无日志', style: TextStyle(color: Colors.grey)),
                  )
                : ListView.builder(
                    controller: _controller,
                    itemCount: visible.length,
                    itemBuilder: (context, index) {
                      final e = visible[index];
                      return Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 2),
                        child: SelectableText(
                          e.formatted,
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 12,
                            height: 1.3,
                          ),
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
