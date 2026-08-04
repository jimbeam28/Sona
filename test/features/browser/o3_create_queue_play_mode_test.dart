// test/features/browser/o3_create_queue_play_mode_test.dart
// playMode 持久化链路最后一个缺口: 建队入口恒以 sequential 建队 — 回归门禁测试
//
// 问题: 队列创建入口（browser_screen.dart onFileTap 的 PlayQueue(...)）不读
// playModeProvider，恒以构造器默认 sequential 建队。若用户先切到 shuffle
// 再点击文件建队: 播放行为是 shuffle（orchestrator.playMode 从
// playModeProvider 同步），但新建队列对象的 playMode 字段是 sequential →
// persistQueueOnChange 落盘 sequential → 重启后 0fb11dc 恢复链路忠实恢复
// sequential → 模式丢失。与切模式链路的 f3cb8eb（nextPlayModeProvider 回写
// q.withMode）同族。
//
// 修复: 建队点按当前 playModeProvider 的值创建队列——「sequential 建队 →
// withMode(当前模式)」复用 f3cb8eb 的同一机制（进 shuffle 生成排列且指针
// 锚定当前曲 order[pos]==currentIndex; 同模式幂等; 单曲/空选不生成排列），
// 不在创建点手写排列生成。
//
// 用例（走真实生产链路 BrowserScreen onFileTap，仅叶子注入 mock/fake）:
//   C1  核心 RED: 切 shuffle → 浏览页点文件建队 → 队列 playMode==shuffle、
//       排列合法（order[pos]==currentIndex 不变量）、prefs playMode=="shuffle"
//   C2  sequential 默认建队行为不变（否定断言: 不生成排列）
//   C3  repeatAll 下建队 → 模式字段同步、不生成排列
//   C4  单曲目录 + shuffle 建队 → 退化语义与 withMode 一致（无排列、不抛错）
//   C5  点中间曲目 → 指针锚定被点的曲目（当前曲 = 用户点的那首）
//   C6  端到端: shuffle 建队 → 持久化 → 重启恢复仍是 shuffle（串起 0fb11dc），
//       行为锚: 末位建队恢复后 skipToNext 必前进（sequential 末位无下一首）

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nas_audio_player/shared/di/providers.dart';
import 'package:nas_audio_player/shared/models/connection_config.dart';
import 'package:nas_audio_player/shared/models/play_queue.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/mock_audio_player.dart';
import '../../helpers/test_factories.dart';
import '../../helpers/widget_helpers.dart';

const _qKey = 'last_play_queue';

/// 无 id 的连接: onFileTap 的进度查询分支（conn.id != null）整体跳过，
/// 测试聚焦建队模式同步本身; 连接 id 相关的持久化归一由 net1_legacy_* 覆盖。
final _conn = testConfig();

List<Override> _overrides(SharedPreferences prefs) => [
      directoryContentsProvider('/').overrideWith((ref) async => [
            testAudio('track_01.mp3', '/music/track_01.mp3'),
            testAudio('track_02.mp3', '/music/track_02.mp3'),
            testAudio('track_03.mp3', '/music/track_03.mp3'),
            testAudio('track_04.mp3', '/music/track_04.mp3'),
          ]),
      activeConnectionProvider.overrideWith((ref) async => _conn),
      sharedPreferencesProvider.overrideWithValue(prefs),
      audioPlayerProvider.overrideWithValue(MockAudioPlayer()),
    ];

/// 「重启」会话: 与 o3_restore_play_mode_test 同款 container ——
/// activeConnection 置 null 跳过 preload 分支，restore 只消费 prefs。
ProviderContainer _restoreContainer(SharedPreferences prefs) {
  final container = ProviderContainer(overrides: [
    sharedPreferencesProvider.overrideWithValue(prefs),
    activeConnectionProvider
        .overrideWith((ref) async => null as ConnectionConfig?),
    audioPlayerProvider.overrideWithValue(MockAudioPlayer()),
  ]);
  addTearDown(container.dispose);
  return container;
}

/// 从 toMap() 读排列（私有字段的行为观测通道，与 BUG-14 / writeback 测试同款）。
List<int>? persistedOrder(PlayQueue q) =>
    (q.toMap()['shuffleOrder'] as List<dynamic>?)?.cast<int>();
int? persistedPosition(PlayQueue q) => q.toMap()['shufflePosition'] as int?;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<ProviderContainer> pumpBrowser(
      WidgetTester tester, SharedPreferences prefs) async {
    await tester.pumpWidget(buildTestAppWithPlayerRoute(
      const Scaffold(body: BrowserScreen()),
      overrides: _overrides(prefs),
    ));
    await tester.pumpAndSettle();
    expect(find.text('track_01.mp3'), findsOneWidget, reason: '前置: 文件列表已渲染');
    return ProviderScope.containerOf(
        tester.element(find.byType(BrowserScreen)));
  }

  // ═══════════════════════════════════════════════════════════════════════
  // C1 — 核心 RED: shuffle 下建队 → 队列与持久化都必须是 shuffle
  // ═══════════════════════════════════════════════════════════════════════
  group('C1: 切 shuffle → 浏览页建队 → 队列与 prefs 均为 shuffle', () {
    testWidgets('队列 playMode==shuffle、排列合法、prefs playMode=="shuffle"',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final container = await pumpBrowser(tester, prefs);

      // 用户先切到 shuffle（PlayModeControl 同款入口，此刻无队列纯切模式）
      final cycle = container.read(nextPlayModeProvider);
      cycle();
      cycle();
      final mode = cycle(); // sequential → repeatOne → repeatAll → shuffle
      expect(mode, equals(PlayMode.shuffle), reason: '前置: 已切到 shuffle');
      expect(container.read(playModeProvider), equals(PlayMode.shuffle));

      // 点击第 2 个文件建队
      await tester.tap(find.text('track_02.mp3'));
      await tester.pumpAndSettle();

      final queue = container.read(currentPlayQueueProvider);
      expect(queue, isNotNull, reason: '前置: 建队成功');
      // 核心 RED —— 修复前: 建队恒 sequential
      expect(queue!.playMode, equals(PlayMode.shuffle),
          reason: 'C1 核心: 建队必须按当前 playModeProvider 的模式，'
              '修复前恒为构造器默认 sequential');
      expect(queue.currentIndex, equals(1), reason: '起始曲目 = 被点的文件，不变');
      expect(queue.current.path, equals('/music/track_02.mp3'));
      expect(queue.startPositionMs, isNull, reason: '无进度 → 不携带续播位置');

      // 排列合法: 全排列 + order[pos] == currentIndex 不变量（withMode 语义）
      final order = persistedOrder(queue);
      expect(order, isNotNull, reason: 'C1: shuffle 建队必须携带合法排列');
      expect(order!.toList()..sort(), equals([0, 1, 2, 3]),
          reason: 'C1: 排列必须是 0..n-1 的全排列');
      final pos = persistedPosition(queue);
      expect(pos, isNotNull);
      expect(order[pos!], equals(queue.currentIndex),
          reason: 'C1 不变量: order[shufflePosition] == currentIndex —— '
              '指针锚定当前曲，与 withMode/withIndex/BUG-14 既定语义一致');

      // 持久化锚: persistQueueOnChange 捕获建队 → prefs JSON 必须是 shuffle
      final raw = prefs.getString(_qKey);
      expect(raw, isNotNull, reason: '前置: 建队已触发持久化');
      final written = jsonDecode(raw!) as Map<String, dynamic>;
      // 核心 RED —— 修复前恒为 'sequential'
      expect(written['playMode'], equals('shuffle'),
          reason: 'C1 核心: 持久化的 playMode 必须反映建队时的用户模式，'
              '否则重启恢复（0fb11dc 链路忠实读回）丢失 shuffle');
      expect(
          (written['shuffleOrder'] as List<dynamic>).cast<int>(), equals(order),
          reason: 'C1: 排列一并持久化');
      expect(written['shufflePosition'], equals(pos));
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // C2 — sequential 默认建队行为不变（否定断言）
  // ═══════════════════════════════════════════════════════════════════════
  group('C2: sequential 下建队行为不变', () {
    testWidgets('默认模式建队 → 无排列、prefs playMode=="sequential"', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final container = await pumpBrowser(tester, prefs);
      expect(container.read(playModeProvider), equals(PlayMode.sequential),
          reason: '前置: 默认 sequential');

      await tester.tap(find.text('track_02.mp3'));
      await tester.pumpAndSettle();

      final queue = container.read(currentPlayQueueProvider);
      expect(queue, isNotNull);
      expect(queue!.playMode, equals(PlayMode.sequential));
      expect(queue.currentIndex, equals(1));
      // 否定断言: sequential 建队不得生成排列
      expect(persistedOrder(queue), isNull,
          reason: 'C2 否定: sequential 建队不得携带排列');
      expect(persistedPosition(queue), isNull);

      final written =
          jsonDecode(prefs.getString(_qKey)!) as Map<String, dynamic>;
      expect(written['playMode'], equals('sequential'));
      expect(written.containsKey('shuffleOrder'), isFalse,
          reason: 'C2 否定: 持久化不得携带排列字段');
      expect(written.containsKey('shufflePosition'), isFalse);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // C3 — 非 shuffle 模式（repeatAll）同样按当前模式建队
  // ═══════════════════════════════════════════════════════════════════════
  group('C3: repeatAll 下建队', () {
    testWidgets('模式字段同步、不生成排列', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final container = await pumpBrowser(tester, prefs);

      container.read(nextPlayModeProvider)(); // sequential → repeatOne
      final mode = container.read(nextPlayModeProvider)(); // → repeatAll
      expect(mode, equals(PlayMode.repeatAll), reason: '前置: 已切到 repeatAll');

      await tester.tap(find.text('track_01.mp3'));
      await tester.pumpAndSettle();

      final queue = container.read(currentPlayQueueProvider);
      expect(queue, isNotNull);
      expect(queue!.playMode, equals(PlayMode.repeatAll),
          reason: 'C3: 建队模式同步不限于 shuffle');
      expect(queue.currentIndex, equals(0));
      expect(persistedOrder(queue), isNull, reason: 'C3: 非 shuffle 不生成排列');

      final written =
          jsonDecode(prefs.getString(_qKey)!) as Map<String, dynamic>;
      expect(written['playMode'], equals('repeatAll'));
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // C4 — 边界: 单曲目录 + shuffle 建队
  // ═══════════════════════════════════════════════════════════════════════
  group('C4: 单曲目录 shuffle 建队（退化语义与 withMode 一致）', () {
    testWidgets('playMode==shuffle 但无排列、不抛错', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      await tester.pumpWidget(buildTestAppWithPlayerRoute(
        const Scaffold(body: BrowserScreen()),
        overrides: [
          directoryContentsProvider('/').overrideWith((ref) async => [
                testAudio('lone.mp3', '/music/lone.mp3'),
              ]),
          activeConnectionProvider.overrideWith((ref) async => _conn),
          sharedPreferencesProvider.overrideWithValue(prefs),
          audioPlayerProvider.overrideWithValue(MockAudioPlayer()),
        ],
      ));
      await tester.pumpAndSettle();
      final container =
          ProviderScope.containerOf(tester.element(find.byType(BrowserScreen)));

      final cycle = container.read(nextPlayModeProvider);
      cycle();
      cycle();
      cycle(); // → shuffle

      await tester.tap(find.text('lone.mp3'));
      await tester.pumpAndSettle();

      final queue = container.read(currentPlayQueueProvider);
      expect(queue, isNotNull, reason: 'C4: 单曲建队不抛错');
      expect(queue!.playMode, equals(PlayMode.shuffle),
          reason: 'C4: 模式字段仍必须同步为 shuffle');
      expect(queue.currentIndex, equals(0));
      expect(persistedOrder(queue), isNull,
          reason: 'C4: files.length <= 1 → 无排列可生成'
              '（与 withMode/构造器 files.length > 1 条件一致）');
      expect(persistedPosition(queue), isNull);

      final written =
          jsonDecode(prefs.getString(_qKey)!) as Map<String, dynamic>;
      expect(written['playMode'], equals('shuffle'));
      expect(written.containsKey('shuffleOrder'), isFalse);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // C5 — 点中间曲目: 指针锚定被点的曲目（当前曲 = 用户点的那首）
  // ═══════════════════════════════════════════════════════════════════════
  group('C5: shuffle 建队指针锚定被点曲目', () {
    testWidgets('点第 3 首 → order[pos] == currentIndex == 2', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final container = await pumpBrowser(tester, prefs);

      final cycle = container.read(nextPlayModeProvider);
      cycle();
      cycle();
      cycle(); // → shuffle

      await tester.tap(find.text('track_03.mp3'));
      await tester.pumpAndSettle();

      final queue = container.read(currentPlayQueueProvider);
      expect(queue, isNotNull);
      expect(queue!.currentIndex, equals(2), reason: 'C5: 起始曲目为被点的第 3 首');
      expect(queue.playMode, equals(PlayMode.shuffle));
      final order = persistedOrder(queue);
      expect(order, isNotNull);
      expect(order![persistedPosition(queue)!], equals(2),
          reason: 'C5: 排列指针必须锚定被点的曲目（当前曲 = 队列中用户点的那首，'
              '不是队列首曲）');
      // 重复运行多次排列可变，但锚定不变量恒成立（结构断言，无偶然性）
      expect(order.toSet().length, equals(4), reason: 'C5: 排列无重复元素');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // C6 — 端到端: shuffle 建队 → 持久化 → 重启恢复仍 shuffle（串起 0fb11dc）
  // ═══════════════════════════════════════════════════════════════════════
  group('C6: 端到端 — shuffle 建队 → 重启恢复 == shuffle', () {
    testWidgets('恢复链路读回 shuffle（模式+排列+指针），skipToNext 走排列', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final container = await pumpBrowser(tester, prefs);

      // ── 第一段: 「上次会话」切 shuffle 后点末位文件建队 ─────────────
      final cycle = container.read(nextPlayModeProvider);
      cycle();
      cycle();
      cycle(); // → shuffle

      // 点末位文件: 末位上 sequential 无下一首，shuffle 必前进 →
      // 恢复后 skipToNext 结果成为零偶然的模式判别锚（E1 同款）
      await tester.tap(find.text('track_04.mp3'));
      await tester.pumpAndSettle();

      final queue = container.read(currentPlayQueueProvider);
      expect(queue, isNotNull);
      expect(queue!.currentIndex, equals(3), reason: '前置: 末位建队');
      expect(queue.playMode, equals(PlayMode.shuffle),
          reason: '前置（即 C1 核心）: 建队模式为 shuffle');
      final order = persistedOrder(queue);
      final pos = persistedPosition(queue);
      final persisted =
          jsonDecode(prefs.getString(_qKey)!) as Map<String, dynamic>;
      expect(persisted['playMode'], equals('shuffle'),
          reason: '前置: 已落盘 shuffle');

      // ── 第二段: 「重启」恢复（0fb11dc 链路）────────────────────────
      final session2 = _restoreContainer(prefs);
      await session2.read(restoreQueueFromPrefsProvider.future);

      final restored = session2.read(currentPlayQueueProvider);
      expect(restored, isNotNull, reason: '前置: 队列被恢复');
      expect(restored!.playMode, equals(PlayMode.shuffle),
          reason: 'C6: 恢复的队列模式为 shuffle（修复前建队落 sequential，'
              '这里忠实恢复 sequential → 模式丢失）');
      expect(session2.read(playModeProvider), equals(PlayMode.shuffle),
          reason: 'C6: 0fb11dc 链路把持久化模式写回 playModeProvider');
      expect(persistedOrder(restored), equals(order),
          reason: 'C6: 恢复保留建队时的排列（不重洗）');
      expect(persistedPosition(restored), equals(pos), reason: 'C6: 恢复保留指针');
      expect(restored.currentIndex, equals(3), reason: 'C6: 当前曲不变');

      // ── 行为锚: shuffle 真的活了 ───────────────────────────────────
      final orchestrator = session2.read(playbackOrchestratorProvider);
      await orchestrator.skipToNext();
      final advanced = session2.read(currentPlayQueueProvider)!;
      // 末位 currentIndex=3: sequential 的 nextIndex == null → 队列不得前进;
      // shuffle 排列推进/重洗都必然离开末位 → 非 3 即证明模式活着。
      expect(advanced.currentIndex, isNot(3),
          reason: 'C6 行为锚: 末位上 sequential 无下一首，'
              'skipToNext 能前进即证明恢复的 shuffle 生效（零偶然判别）');
      expect(advanced.playMode, equals(PlayMode.shuffle));
    });
  });
}
