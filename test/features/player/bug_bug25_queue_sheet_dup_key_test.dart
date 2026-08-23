// test/features/player/bug_bug25_queue_sheet_dup_key_test.dart
// BUG-25 门禁测试（来源 cr-20260823-1421.md F3，复核分流 2026-08-23）。
//
// 缺陷：insertAfterCurrent 明确允许队列持有重复 path（play_queue.dart:226-227
// "No de-duplication is performed"），而 QueueSheet 以 ValueKey(file.path)
// 作为同层列表键（queue_sheet.dart:56）。
//
// 断言机制说明：Flutter 对 sliver 惰性列表（ListView.builder）不执行
// MultiChild 路径的 duplicate-key 查重，键冲突表现为元素状态错配而非崩溃，
// 无确定异常信号。故本门禁直接锚定 INV1「同层列表键必须唯一」：提取全部
// ListTile 键断言无重复。修复前键集合缩水（2 ≠ 3）→ FAIL；修复后复合键
// 全部唯一 → PASS。

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nas_audio_player/features/player/widgets/queue_sheet.dart';
import 'package:nas_audio_player/shared/di/providers.dart';
import 'package:nas_audio_player/shared/models/nas_file.dart';
import 'package:nas_audio_player/shared/models/play_queue.dart';

NasFile _file(String name, String path) => NasFile(
    name: name, path: path, isDirectory: false, audioType: AudioFileType.music);

void main() {
  testWidgets('BUG-25-S1: 含重复 path 的队列渲染完整且同层列表键唯一', (tester) async {
    final dupQueue = PlayQueue(
      files: [
        _file('a.mp3', '/a.mp3'),
        _file('a.mp3', '/a.mp3'), // insertAfterCurrent 合法产物：同曲二份
        _file('b.mp3', '/b.mp3'),
      ],
      currentIndex: 0,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentPlayQueueProvider.overrideWith((ref) => dupQueue),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: QueueSheet(
              errorMessage: '无法加载音频，请检查连接配置',
              onSelectIndex: (_) async => true,
              onRemoveIndex: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    // 渲染完整性。
    expect(tester.takeException(), isNull);
    expect(find.byType(ListTile), findsNWidgets(3), reason: '三条队列项全部渲染');
    expect(find.text('当前'), findsOneWidget, reason: '"当前"标记只落在 currentIndex 上');

    // 核心断言（修复前 FAIL）：同层列表键必须唯一。
    final tiles = tester
        .widgetList<ListTile>(find.byType(ListTile))
        .map((w) => w.key)
        .toList();
    expect(tiles.every((k) => k != null), isTrue, reason: 'P13：每个业务条目都必须带键');
    expect(tiles.toSet().length, tiles.length,
        reason: '队列含重复 path 时 ValueKey(file.path) 产生重复键'
            '（实际键集合 $tiles）');
  });
}
