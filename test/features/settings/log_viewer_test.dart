// test/features/settings/log_viewer_test.dart
// TST-14: Log buffer and log viewer tests — TST-T107 through TST-T113.
//
// Covers LogBuffer (ring-buffer semantics, capacity enforcement, clear) and
// LogViewerScreen (widget rendering, empty state, entry rendering).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:nas_audio_player/core/services/log_buffer.dart';
import 'package:nas_audio_player/features/settings/log_viewer_screen.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// Helpers
// ═══════════════════════════════════════════════════════════════════════════════

/// Wraps [LogViewerScreen] in a [MaterialApp] and [Scaffold] for widget tests.
Widget wrapLogViewer() {
  return const MaterialApp(
    home: Scaffold(body: LogViewerScreen()),
  );
}

// ═══════════════════════════════════════════════════════════════════════════════
// TST-14: Log buffer and log viewer
// ═══════════════════════════════════════════════════════════════════════════════

void main() {
  group('TST-14: Log buffer and log viewer', () {
    setUp(() {
      LogBuffer.instance.clear();
    });
    tearDown(() {
      LogBuffer.instance.clear();
    });

    // ═══════════════════════════════════════════════════════════════════════════
    // TST-T107 ~ TST-T108: LogBuffer unit tests
    // ═══════════════════════════════════════════════════════════════════════════

    group('TST-T107 ~ TST-T108: LogBuffer unit tests', () {
      test('TST-T107: LogBuffer 写入 1 条 → 读取包含该条', () {
        LogBuffer.instance.add('hello world');

        final entries = LogBuffer.instance.entries;
        expect(entries.length, equals(1), reason: '写入 1 条后 entries 长度应为 1');
        expect(entries[0].message, equals('hello world'),
            reason: '应能读取到写入的消息内容');
      });

      test('TST-T108: LogBuffer 写入 1001 条 → 最旧 1 条被移除 → size=1000', () {
        // Add 1001 messages (indices 0..1000)
        for (int i = 0; i < 1001; i++) {
          LogBuffer.instance.add('message $i');
        }

        final entries = LogBuffer.instance.entries;
        expect(entries.length, equals(1000), reason: '超过上限 1000 后应保持在 1000 条');

        // The oldest entry (message 0) should have been evicted
        expect(entries.first.message, equals('message 1'),
            reason: '最旧的 "message 0" 应已被移除，第一条变为 "message 1"');

        // The newest entry should still be present
        expect(entries.last.message, equals('message 1000'),
            reason: '最新的消息 "message 1000" 应仍在缓冲区中');
      });

      test('TST-T108b: LogBuffer maxEntries 常量 = 1000', () {
        expect(LogBuffer.maxEntries, equals(1000),
            reason: 'maxEntries 常量应为 1000');
      });
    });

    // ═══════════════════════════════════════════════════════════════════════════
    // TST-T109 ~ TST-T112: LogViewerScreen widget tests
    // ═══════════════════════════════════════════════════════════════════════════

    group('TST-T109 ~ TST-T112: LogViewerScreen widget tests', () {
      testWidgets('TST-T109: LogViewerScreen 渲染日志列表', (tester) async {
        LogBuffer.instance.add('alpha log');
        LogBuffer.instance.add('beta log');

        await tester.pumpWidget(wrapLogViewer());
        await tester.pump();

        // AppBar title should read "运行日志"
        expect(find.text('运行日志'), findsOneWidget, reason: 'AppBar 标题应为"运行日志"');

        // Two log entries rendered as SelectableText widgets in the ListView
        expect(find.byType(SelectableText), findsNWidgets(2),
            reason: '2 条日志应有 2 个 SelectableText widget');

        // Entry count display
        expect(find.text('共 2 条 / 缓存上限 1000'), findsOneWidget,
            reason: '应显示 "共 2 条 / 缓存上限 1000"');
      });

      testWidgets('TST-T110: 空日志 → 显示 "暂无日志" 空状态', (tester) async {
        await tester.pumpWidget(wrapLogViewer());
        await tester.pump();

        // Empty state text
        expect(find.text('暂无日志'), findsOneWidget, reason: '无日志时应显示"暂无日志"');
        expect(find.text('共 0 条 / 缓存上限 1000'), findsOneWidget,
            reason: '无日志时应显示 "共 0 条 / 缓存上限 1000"');

        // No SelectableText when empty
        expect(find.byType(SelectableText), findsNothing,
            reason: '空状态不应有 SelectableText widget');
      });

      testWidgets('TST-T111: 新日志条目追加到列表底部', (tester) async {
        LogBuffer.instance.add('first entry');
        LogBuffer.instance.add('second entry');
        LogBuffer.instance.add('third entry');

        await tester.pumpWidget(wrapLogViewer());
        await tester.pump();

        // All 3 entries should be rendered
        expect(find.byType(SelectableText), findsNWidgets(3),
            reason: '3 条日志应有 3 个 SelectableText widget');

        // Verify each entry content is present
        expect(find.textContaining('first entry'), findsOneWidget,
            reason: '第一条日志应存在于列表中');
        expect(find.textContaining('second entry'), findsOneWidget,
            reason: '第二条日志应存在于列表中');
        expect(find.textContaining('third entry'), findsOneWidget,
            reason: '第三条日志（最后一条）应存在于列表中');

        // Count display should show 3
        expect(find.text('共 3 条 / 缓存上限 1000'), findsOneWidget,
            reason: '应显示 "共 3 条 / 缓存上限 1000"');
      });

      testWidgets('TST-T112: 日志条目正确渲染', (tester) async {
        LogBuffer.instance.add('test log content');

        await tester.pumpWidget(wrapLogViewer());
        await tester.pump();

        // Should find a SelectableText widget for the log entry
        expect(find.byType(SelectableText), findsOneWidget,
            reason: '1 条日志应有 1 个 SelectableText');

        final selectableText =
            tester.widget<SelectableText>(find.byType(SelectableText));

        // Verify monospace font family and fontSize=12
        expect(selectableText.style?.fontFamily, equals('monospace'),
            reason: '日志条目应使用 monospace 等宽字体');
        expect(selectableText.style?.fontSize, equals(12),
            reason: '日志条目字体大小应为 12');

        // Verify the formatted text contains the message
        final text = selectableText.data ?? '';
        expect(text, contains('test log content'), reason: '渲染的文本应包含日志消息内容');

        // Verify timestamp format: HH:mm:ss.mmm
        // The formatted string is "HH:mm:ss.mmm  message" (two spaces)
        final parts = text.split('  ');
        expect(parts.length, greaterThanOrEqualTo(2),
            reason: 'formatted 文本应包含时间戳（用两个空格分隔）');

        final timePart = parts[0];
        final timeRegex = RegExp(r'^\d{2}:\d{2}:\d{2}\.\d{3}$');
        expect(timeRegex.hasMatch(timePart), isTrue,
            reason: '时间戳应为 HH:mm:ss.mmm 格式，实际为: $timePart');
      });

      testWidgets('TST-T112b: LogViewerScreen 包含过滤输入框和操作按钮', (tester) async {
        LogBuffer.instance.add('some log');

        await tester.pumpWidget(wrapLogViewer());
        await tester.pump();

        // Filter TextField with hint text
        final textFieldFinder = find.byType(TextField);
        expect(textFieldFinder, findsOneWidget, reason: '应有一个过滤输入框');
        final textField = tester.widget<TextField>(textFieldFinder);
        expect(textField.decoration?.hintText,
            equals('过滤关键字（如 [Player] 或 setAudioSource）'),
            reason: '过滤输入框应有 hintText');

        // Auto-scroll toggle button (initially on)
        expect(find.byTooltip('关闭自动滚动'), findsOneWidget, reason: '应有自动滚动切换按钮');

        // Copy-all button
        expect(find.byTooltip('复制全部'), findsOneWidget, reason: '应有复制全部按钮');

        // Clear button
        expect(find.byTooltip('清空'), findsOneWidget, reason: '应有清空按钮');
      });
    });

    // ═══════════════════════════════════════════════════════════════════════════
    // TST-T113: LogBuffer.clear()
    // ═══════════════════════════════════════════════════════════════════════════

    group('TST-T113: LogBuffer.clear()', () {
      test('TST-T113: LogBuffer.clear() → 所有条目清除', () {
        LogBuffer.instance.add('msg one');
        LogBuffer.instance.add('msg two');
        LogBuffer.instance.add('msg three');

        expect(LogBuffer.instance.entries.length, equals(3),
            reason: '添加 3 条后长度应为 3');

        LogBuffer.instance.clear();

        expect(LogBuffer.instance.entries.isEmpty, isTrue,
            reason: 'clear() 后 entries 应为空');
      });

      testWidgets('TST-T113b: clear() 后 LogViewerScreen 显示空状态', (tester) async {
        LogBuffer.instance.add('some log entry');
        LogBuffer.instance.clear();

        await tester.pumpWidget(wrapLogViewer());
        await tester.pump();

        expect(find.text('暂无日志'), findsOneWidget,
            reason: 'clear() 后应显示"暂无日志"空状态');
        expect(find.text('共 0 条 / 缓存上限 1000'), findsOneWidget,
            reason: 'clear() 后应显示 "共 0 条 / 缓存上限 1000"');
        expect(find.byType(SelectableText), findsNothing,
            reason: 'clear() 后不应有日志条目渲染');
      });
    });
  });
}
