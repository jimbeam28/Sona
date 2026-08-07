// test/features/settings/log_viewer_test.dart
// TST-14: Log buffer and log viewer tests — TST-T107 through TST-T113.
//
// Covers LogBuffer (ring-buffer semantics, capacity enforcement, clear) and
// LogViewerScreen (widget rendering, empty state, entry rendering).

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

  // ═══════════════════════════════════════════════════════════════════════════
  // TEST-11 (SET3): LogViewer 行为测试 — 过滤 / 复制全部 / 清空
  // 注意：LogBuffer 为单例跨测试共享，每个用例开头先 clear()
  // ═══════════════════════════════════════════════════════════════════════════

  group('TEST-11: LogViewer 行为测试', () {
    /// 按 tooltip 文本定位 IconButton（不依赖 Tooltip 与 IconButton 的树嵌套）。
    IconButton iconButtonByTooltip(WidgetTester tester, String tooltip) =>
        tester.widget<IconButton>(find
            .byWidgetPredicate((w) => w is IconButton && w.tooltip == tooltip));

    testWidgets('TEST-11-S1: 过滤关键字缩小日志列表', (tester) async {
      LogBuffer.instance.clear();
      LogBuffer.instance.add('[Player] started');
      LogBuffer.instance.add('[Browser] loaded');
      LogBuffer.instance.add('[Player] stopped');

      await tester.pumpWidget(wrapLogViewer());
      await tester.pump();

      // Given: 过滤为空时显示全部（否定断言：不过滤时不隐藏任何条目）
      expect(find.byType(SelectableText), findsNWidgets(3),
          reason: '过滤为空时应显示全部 3 条日志');
      expect(find.textContaining('共 3 条'), findsOneWidget,
          reason: '不过滤时计数应显示 3 条');

      // When: 在过滤输入框输入 'Player'
      await tester.enterText(find.byType(TextField), 'Player');
      await tester.pump();

      // Then: 仅 2 条可见，'[Browser] loaded' 不显示，计数 '共 2 条'
      expect(find.byType(SelectableText), findsNWidgets(2),
          reason: '过滤 "Player" 后应只剩 2 条日志可见');
      expect(find.textContaining('[Player] started'), findsOneWidget,
          reason: '"[Player] started" 应仍可见');
      expect(find.textContaining('[Player] stopped'), findsOneWidget,
          reason: '"[Player] stopped" 应仍可见');
      expect(find.textContaining('[Browser] loaded'), findsNothing,
          reason: '"[Browser] loaded" 不应出现在过滤后的列表');
      expect(find.textContaining('共 2 条'), findsOneWidget,
          reason: '过滤后计数应显示 "共 2 条"');

      // And: 过滤是纯视图操作，不改变 LogBuffer 数据源（TEST-11-INV1）
      expect(LogBuffer.instance.entries.length, equals(3),
          reason: '过滤不应修改 LogBuffer（entries 仍为 3 条）');

      // And: 清空过滤 → 3 条全可见
      await tester.enterText(find.byType(TextField), '');
      await tester.pump();
      expect(find.byType(SelectableText), findsNWidgets(3),
          reason: '清空过滤后应恢复显示全部 3 条');
      expect(find.textContaining('[Browser] loaded'), findsOneWidget,
          reason: '清空过滤后 "[Browser] loaded" 应重新显示');

      // And: 大小写不敏感（小写 'player' 同样匹配 2 条）
      await tester.enterText(find.byType(TextField), 'player');
      await tester.pump();
      expect(find.byType(SelectableText), findsNWidgets(2),
          reason: '小写 "player" 应同样匹配（大小写不敏感），仍显示 2 条');
    });

    testWidgets('TEST-11-S2: 复制全部 → SnackBar + 剪贴板内容匹配', (tester) async {
      LogBuffer.instance.clear();
      LogBuffer.instance.add('[Player] started');
      LogBuffer.instance.add('[Browser] loaded');

      // Mock Clipboard：拦截 SystemChannels.platform 的 'Clipboard.setData'
      String? copiedText;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform,
              (MethodCall call) async {
        if (call.method == 'Clipboard.setData') {
          copiedText =
              (call.arguments as Map<dynamic, dynamic>)['text'] as String?;
        }
        return null;
      });
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, null);
      });

      await tester.pumpWidget(wrapLogViewer());
      await tester.pump();

      // 记录渲染出的 formatted 文本（作为剪贴板预期内容）
      final rendered = tester
          .widgetList<SelectableText>(find.byType(SelectableText))
          .map((w) => w.data ?? '')
          .toList();
      expect(rendered, hasLength(2), reason: '前置：2 条日志应渲染 2 个条目');

      // When: 按"复制全部"
      await tester.tap(find.byTooltip('复制全部'));
      await tester.pump();

      // Then: 出现 SnackBar '已复制 2 行'
      expect(find.text('已复制 2 行'), findsOneWidget,
          reason: '复制后应出现 SnackBar "已复制 2 行"');

      // And: 剪贴板内容 = 2 条 formatted 文本以 '\n' 分隔
      expect(copiedText, isNotNull, reason: '应调用 Clipboard.setData');
      expect(copiedText, equals(rendered.join('\n')),
          reason: '剪贴板文本应与可见日志的 formatted 文本以 \\n 分隔一致');
      expect(copiedText, contains('[Player] started'),
          reason: '剪贴板应包含 "[Player] started"');
      expect(copiedText, contains('[Browser] loaded'),
          reason: '剪贴板应包含 "[Browser] loaded"');

      // And: 复制只读，不清除 LogBuffer
      expect(LogBuffer.instance.entries.length, equals(2),
          reason: '复制不应清除 LogBuffer（仍为 2 条）');

      // 否定断言：空日志时"复制全部"按钮 disabled（TEST-11-INV2）
      await tester.pumpWidget(const SizedBox());
      LogBuffer.instance.clear();
      await tester.pumpWidget(wrapLogViewer());
      await tester.pump();
      expect(iconButtonByTooltip(tester, '复制全部').onPressed, isNull,
          reason: 'TEST-11-INV2: 日志为空时复制按钮应 disabled');
      expect(find.text('暂无日志'), findsOneWidget, reason: '空日志时应显示 "暂无日志" 占位');
    });

    testWidgets('TEST-11-S3: 清空 → LogBuffer 空 + 空状态 + 按钮 disabled',
        (tester) async {
      LogBuffer.instance.clear();
      LogBuffer.instance.add('[Player] started');
      LogBuffer.instance.add('[Browser] loaded');
      LogBuffer.instance.add('[Player] stopped');

      await tester.pumpWidget(wrapLogViewer());
      await tester.pump();
      expect(find.byType(SelectableText), findsNWidgets(3),
          reason: '前置：3 条日志应渲染 3 个条目');

      // When: 按"清空"
      await tester.tap(find.byTooltip('清空'));
      await tester.pump();

      // Then: LogBuffer 为空（clear() 必须实际执行）
      expect(LogBuffer.instance.entries.isEmpty, isTrue,
          reason: '清空后 LogBuffer.entries 应为空');

      // And: UI 显示 '暂无日志' 占位，不再渲染日志条目
      expect(find.text('暂无日志'), findsOneWidget, reason: '清空后应显示 "暂无日志" 占位文本');
      expect(find.byType(SelectableText), findsNothing,
          reason: '清空后不应再渲染任何日志条目');

      // And: '复制全部' 和 '清空' 按钮均 disabled（TEST-11-INV2）
      expect(iconButtonByTooltip(tester, '清空').onPressed, isNull,
          reason: 'TEST-11-INV2: 日志为空时清空按钮应 disabled');
      expect(iconButtonByTooltip(tester, '复制全部').onPressed, isNull,
          reason: 'TEST-11-INV2: 日志为空时复制按钮应 disabled');
    });
  });
}
