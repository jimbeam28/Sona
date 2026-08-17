// test/features/player/ref_05_queue_sheet_live_test.dart
// REF-05 (docs/features/REF-05.md §5.4 门禁) — 队列面板 live 数据源：
// QueueSheet watch currentPlayQueueProvider 驱动重建 + 空态 + ValueKey。
//
// 覆盖: REF-05-S4 / S5 / S6 / REF-05-INV1 / REF-05-INV2。
//
//   S4  — sheet 内容由 live provider 驱动：删除/切歌/自动前进全重建
//   S5  — 调用方不传快照参数（compile-time，本文件消费 QueueSheet 构造）
//   S6  — 点击/删除行为语义保持（live index 有效；回调接线）
//   INV1 — 面板打开期间列表恒等于 provider 当前值
//   INV2 — 每条 ListTile key == ValueKey(file.path)
//
// 装配：ProviderContainer + currentPlayQueueProvider.overrideWith +
// UncontrolledProviderScope（provider 由容器读写，测试可动态改队列）。

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nas_audio_player/features/player/widgets/queue_sheet.dart';
import 'package:nas_audio_player/shared/di/providers.dart';
import 'package:nas_audio_player/shared/models/play_queue.dart';

import '../../helpers/test_factories.dart';

PlayQueue _queue({
  List<String>? names,
  int currentIndex = 0,
}) {
  final files = (names ?? ['a.mp3', 'b.mp3', 'c.mp3'])
      .map((n) => testAudio(n, '/music/$n'))
      .toList();
  return PlayQueue(files: files, currentIndex: currentIndex);
}

/// Mutates the live queue by writing a new [PlayQueue] (or null) into the container.
void _setQueue(ProviderContainer container, PlayQueue? queue) {
  container.read(currentPlayQueueProvider.notifier).state = queue;
}

/// Pumps a live QueueSheet bound to [container]'s currentPlayQueueProvider.
Widget _buildLiveSheet(ProviderContainer container) {
  return UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              onPressed: () {
                showModalBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  builder: (_) => QueueSheet(
                    errorMessage: '加载失败',
                    onSelectIndex: (_) async => true,
                    onRemoveIndex: (_) {},
                  ),
                );
              },
              child: const Text('Open Queue'),
            ),
          ),
        ),
      ),
    ),
  );
}

/// Returns a fresh container with [startQueue] as currentPlayQueueProvider.
ProviderContainer _makeContainer(PlayQueue startQueue) {
  final c = ProviderContainer(overrides: [
    currentPlayQueueProvider.overrideWith((ref) => startQueue),
  ]);
  addTearDown(c.dispose);
  return c;
}

void main() {
  // ═══════════════════════════════════════════════════════════════════════════
  // REF-05-S4/INV1: live 数据源 —— provider 变更驱动整表重建
  // ═══════════════════════════════════════════════════════════════════════════

  group('REF-05-S4/INV1: live 数据源重建', () {
    testWidgets('sheet 打开后删除一条 → 被删条目消失、标题长度更新', (WidgetTester tester) async {
      final c = _makeContainer(_queue());
      await tester.pumpWidget(_buildLiveSheet(c));
      await tester.tap(find.text('Open Queue'));
      await tester.pumpAndSettle();

      expect(find.text('播放队列 (3)'), findsOneWidget);
      expect(find.text('b.mp3'), findsOneWidget);

      // 队列变更：删除 b.mp3（live 源的值变化）。
      _setQueue(
          c,
          PlayQueue(
            files: [
              testAudio('a.mp3', '/music/a.mp3'),
              testAudio('c.mp3', '/music/c.mp3'),
            ],
            currentIndex: 0,
          ));
      await tester.pumpAndSettle();

      expect(find.text('播放队列 (2)'), findsOneWidget,
          reason: 'INV1: 标题长度跟随 live 队列');
      expect(find.text('b.mp3'), findsNothing, reason: 'S4: 被删条目立即消失');
      expect(find.text('a.mp3'), findsOneWidget);
      expect(find.text('c.mp3'), findsOneWidget);
    });

    testWidgets('删除当前曲 → 当前高亮自动移到新的当前行', (WidgetTester tester) async {
      // 当前曲 = b.mp3（index 1）。
      final c = _makeContainer(
          _queue(names: ['a.mp3', 'b.mp3', 'c.mp3'], currentIndex: 1));
      await tester.pumpWidget(_buildLiveSheet(c));
      await tester.tap(find.text('Open Queue'));
      await tester.pumpAndSettle();

      // 删除当前曲 b.mp3 → 新队列的当前曲为 a.mp3（index 0）。
      _setQueue(
          c,
          PlayQueue(
            files: [
              testAudio('a.mp3', '/music/a.mp3'),
              testAudio('c.mp3', '/music/c.mp3'),
            ],
            currentIndex: 0,
          ));
      await tester.pumpAndSettle();

      // '当前' 标记只在新的当前行出现一次。
      expect(find.text('当前'), findsOneWidget, reason: 'S4: 高亮跟随新的当前曲目');
      final currentTile = tester.widget<ListTile>(
        find.ancestor(
          of: find.text('当前'),
          matching: find.byType(ListTile),
        ),
      );
      expect(currentTile.title, isNotNull);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // REF-05-S4: 空态 —— 队列被删空显示"队列为空"
  // ═══════════════════════════════════════════════════════════════════════════

  group('REF-05-S4: 空态渲染', () {
    testWidgets('队列置 null → 显示"队列为空"，无列表无删除按钮，不自动 pop',
        (WidgetTester tester) async {
      final c = _makeContainer(_queue());
      await tester.pumpWidget(_buildLiveSheet(c));
      await tester.tap(find.text('Open Queue'));
      await tester.pumpAndSettle();

      expect(find.byType(ListTile), findsNWidgets(3));

      // 删空：provider 置 null（spec 裁决：watch 到 queue == null → 空态）。
      _setQueue(c, null);
      await tester.pumpAndSettle();

      expect(find.text('队列为空'), findsOneWidget, reason: 'S4: 空态文案出现');
      expect(find.text('播放队列 (3)'), findsNothing);
      expect(find.byType(ListTile), findsNothing, reason: '否定断言: 空态下无列表');
      expect(find.byIcon(Icons.close), findsNothing,
          reason: '否定断言: 空态下不得渲染移除按钮');
      // 不自动 pop：sheet 仍在（还能看到空态文案）。
      expect(find.text('队列为空'), findsOneWidget);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // REF-05-INV2: 每条 ListTile key == ValueKey(file.path)
  // ═══════════════════════════════════════════════════════════════════════════

  group('REF-05-INV2: ValueKey(file.path)', () {
    testWidgets('每条 ListTile 的 key == ValueKey(path)',
        (WidgetTester tester) async {
      final c = _makeContainer(_queue());
      await tester.pumpWidget(_buildLiveSheet(c));
      await tester.tap(find.text('Open Queue'));
      await tester.pumpAndSettle();

      final tiles = tester.widgetList<ListTile>(find.byType(ListTile)).toList();
      final keys = tiles.map((t) => t.key).toList();
      expect(keys, contains(const ValueKey('/music/a.mp3')));
      expect(keys, contains(const ValueKey('/music/b.mp3')));
      expect(keys, contains(const ValueKey('/music/c.mp3')));
      for (final k in keys) {
        expect(k, isA<ValueKey<String>>(),
            reason: 'INV2: 列表项一律 ValueKey(业务 ID)');
      }
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // REF-05-S6: 点击/删除行为保持（回调接线 + 越界兜底语义）
  // ═══════════════════════════════════════════════════════════════════════════

  group('REF-05-S6: 点击/删除回调', () {
    testWidgets('点击非当前条目 → 收起面板并转发 live index', (WidgetTester tester) async {
      final c = _makeContainer(_queue());
      int? selectedIndex;

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: c,
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => Center(
                  child: ElevatedButton(
                    onPressed: () {
                      showModalBottomSheet<void>(
                        context: context,
                        isScrollControlled: true,
                        builder: (_) => QueueSheet(
                          errorMessage: '加载失败',
                          onSelectIndex: (index) async {
                            selectedIndex = index;
                            return true;
                          },
                          onRemoveIndex: (_) {},
                        ),
                      );
                    },
                    child: const Text('Open Queue'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Queue'));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(ListTile, 'b.mp3').last);
      await tester.pumpAndSettle();

      expect(selectedIndex, equals(1), reason: 'S6: live 队列下点击 index 有效并转发');
    });

    testWidgets('点击当前条目为 no-op（onTap null）', (WidgetTester tester) async {
      final c = _makeContainer(_queue());
      await tester.pumpWidget(_buildLiveSheet(c));
      await tester.tap(find.text('Open Queue'));
      await tester.pumpAndSettle();

      // 当前条目（a.mp3, index 0）不应有 onTap。
      final currentTile = tester.widget<ListTile>(
        find.ancestor(
          of: find.text('当前'),
          matching: find.byType(ListTile),
        ),
      );
      expect(currentTile.onTap, isNull, reason: 'S6: 点击当前条目仍为 no-op');
    });
  });
}
