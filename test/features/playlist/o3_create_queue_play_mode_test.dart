// test/features/playlist/o3_create_queue_play_mode_test.dart
// playMode 持久化链路最后一个缺口: 播放单详情建队入口恒以 sequential 建队
// — 回归门禁测试（与 browser 侧 o3_create_queue_play_mode_test.dart 同款）
//
// 问题: playlist_detail_screen.dart _playTrackAtIndex 的 PlayQueue(...) 不读
// playModeProvider，恒以构造器默认 sequential 建队。若用户先切到 shuffle
// 再点播放单曲目建队: 播放行为是 shuffle，但队列 playMode 字段是 sequential
// → persistQueueOnChange 落盘 sequential → 重启后 0fb11dc 恢复链路忠实恢复
// sequential → 模式丢失。与切模式链路的 f3cb8eb 同族。
//
// 修复: 建队点按当前 playModeProvider 的值创建队列——复用 withMode 机制
//（进 shuffle 生成排列且指针锚定当前曲; 同模式幂等; 单曲不生成排列）。
//
// 用例（走真实生产链路 PlaylistDetailScreen track tap，仅叶子注入 mock）:
//   P1  核心 RED: 切 shuffle → 播放单详情点曲目建队 → 队列 playMode==shuffle、
//       排列合法（order[pos]==currentIndex 不变量）、prefs playMode=="shuffle"
//   P2  sequential 默认建队行为不变（否定断言: 不生成排列）
//   P3  单曲播放单 + shuffle 建队 → 退化语义与 withMode 一致（无排列、不抛错）
//   P4  端到端: shuffle 建队 → 持久化 → 重启恢复仍是 shuffle（串起 0fb11dc）

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nas_audio_player/features/playlist/playlist_detail_screen.dart';
import 'package:nas_audio_player/shared/di/providers.dart';
import 'package:nas_audio_player/shared/models/connection_config.dart';
import 'package:nas_audio_player/shared/models/play_queue.dart';
import 'package:nas_audio_player/shared/models/playlist.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/mock_audio_player.dart';
import '../../helpers/test_factories.dart';
import '../../helpers/widget_helpers.dart';

const _qKey = 'last_play_queue';

/// 无 id 的连接: _playTrackAtIndex 的进度查询分支（conn.id != null）整体
/// 跳过，测试聚焦建队模式同步本身。
final _conn = testConfig();

final _now = DateTime(2026, 8, 5);

PlaylistTrack _track(int id, String name) => PlaylistTrack(
      id: id,
      playlistId: 1,
      filePath: '/music/$name',
      fileName: name,
      addedAt: _now,
    );

final _playlist = Playlist(
  id: 1,
  name: '测试播放单',
  trackCount: 4,
  createdAt: _now,
  updatedAt: _now,
);

List<Override> _overrides(
        SharedPreferences prefs, List<PlaylistTrack> tracks) =>
    [
      playlistTracksProvider(1).overrideWith((ref) => Future.value(tracks)),
      playlistListProvider.overrideWith((ref) => Future.value([_playlist])),
      activeConnectionProvider.overrideWith((ref) async => _conn),
      sharedPreferencesProvider.overrideWithValue(prefs),
      audioPlayerProvider.overrideWithValue(MockAudioPlayer()),
    ];

/// 「重启」会话: 与 o3_restore_play_mode_test 同款 container。
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

/// 从 toMap() 读排列（私有字段的行为观测通道）。
List<int>? persistedOrder(PlayQueue q) =>
    (q.toMap()['shuffleOrder'] as List<dynamic>?)?.cast<int>();
int? persistedPosition(PlayQueue q) => q.toMap()['shufflePosition'] as int?;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<ProviderContainer> pumpDetail(WidgetTester tester,
      SharedPreferences prefs, List<PlaylistTrack> tracks) async {
    await tester.pumpWidget(buildTestAppWithPlayerRoute(
      const PlaylistDetailScreen(playlistId: 1),
      overrides: _overrides(prefs, tracks),
    ));
    await tester.pumpAndSettle();
    expect(find.text(tracks.first.fileName), findsOneWidget,
        reason: '前置: 曲目列表已渲染');
    return ProviderScope.containerOf(
        tester.element(find.byType(PlaylistDetailScreen)));
  }

  // ═══════════════════════════════════════════════════════════════════════
  // P1 — 核心 RED: shuffle 下播放单建队 → 队列与持久化都必须是 shuffle
  // ═══════════════════════════════════════════════════════════════════════
  group('P1: 切 shuffle → 播放单详情建队 → 队列与 prefs 均为 shuffle', () {
    testWidgets('队列 playMode==shuffle、排列合法、prefs playMode=="shuffle"',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final container = await pumpDetail(tester, prefs, [
        _track(1, 'a.mp3'),
        _track(2, 'b.mp3'),
        _track(3, 'c.mp3'),
        _track(4, 'd.mp3'),
      ]);

      // persistQueueOnChange 在生产由 BrowserScreen watch 保活; 播放单详情
      // 隔离测试中手动激活同一 provider（建队持久化捕获机制本身不变）。
      container.read(persistQueueOnChangeProvider);

      // 用户先切到 shuffle（PlayModeControl 同款入口，此刻无队列纯切模式）
      final cycle = container.read(nextPlayModeProvider);
      cycle();
      cycle();
      final mode = cycle(); // sequential → repeatOne → repeatAll → shuffle
      expect(mode, equals(PlayMode.shuffle), reason: '前置: 已切到 shuffle');

      // 点第 2 首建队
      await tester.tap(find.text('b.mp3'));
      await tester.pumpAndSettle();

      final queue = container.read(currentPlayQueueProvider);
      expect(queue, isNotNull, reason: '前置: 建队成功');
      // 核心 RED —— 修复前: 建队恒 sequential
      expect(queue!.playMode, equals(PlayMode.shuffle),
          reason: 'P1 核心: 建队必须按当前 playModeProvider 的模式，'
              '修复前恒为构造器默认 sequential');
      expect(queue.currentIndex, equals(1), reason: '起始曲目 = 被点的曲目，不变');
      expect(queue.current.path, equals('/music/b.mp3'));
      expect(queue.startPositionMs, isNull, reason: '无进度 → 不携带续播位置');

      // 排列合法: 全排列 + order[pos] == currentIndex 不变量（withMode 语义）
      final order = persistedOrder(queue);
      expect(order, isNotNull, reason: 'P1: shuffle 建队必须携带合法排列');
      expect(order!.toList()..sort(), equals([0, 1, 2, 3]),
          reason: 'P1: 排列必须是 0..n-1 的全排列');
      final pos = persistedPosition(queue);
      expect(pos, isNotNull);
      expect(order[pos!], equals(queue.currentIndex),
          reason: 'P1 不变量: order[shufflePosition] == currentIndex');

      // 持久化锚: prefs JSON 必须是 shuffle
      final raw = prefs.getString(_qKey);
      expect(raw, isNotNull, reason: '前置: 建队已触发持久化');
      final written = jsonDecode(raw!) as Map<String, dynamic>;
      // 核心 RED —— 修复前恒为 'sequential'
      expect(written['playMode'], equals('shuffle'),
          reason: 'P1 核心: 持久化的 playMode 必须反映建队时的用户模式');
      expect((written['shuffleOrder'] as List<dynamic>).cast<int>(),
          equals(order));
      expect(written['shufflePosition'], equals(pos));
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // P2 — sequential 默认建队行为不变（否定断言）
  // ═══════════════════════════════════════════════════════════════════════
  group('P2: sequential 下建队行为不变', () {
    testWidgets('默认模式建队 → 无排列、prefs playMode=="sequential"', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final container = await pumpDetail(tester, prefs, [
        _track(1, 'a.mp3'),
        _track(2, 'b.mp3'),
      ]);
      container.read(persistQueueOnChangeProvider);
      expect(container.read(playModeProvider), equals(PlayMode.sequential),
          reason: '前置: 默认 sequential');

      await tester.tap(find.text('b.mp3'));
      await tester.pumpAndSettle();

      final queue = container.read(currentPlayQueueProvider);
      expect(queue, isNotNull);
      expect(queue!.playMode, equals(PlayMode.sequential));
      expect(queue.currentIndex, equals(1));
      // 否定断言: sequential 建队不得生成排列
      expect(persistedOrder(queue), isNull,
          reason: 'P2 否定: sequential 建队不得携带排列');
      expect(persistedPosition(queue), isNull);

      final written =
          jsonDecode(prefs.getString(_qKey)!) as Map<String, dynamic>;
      expect(written['playMode'], equals('sequential'));
      expect(written.containsKey('shuffleOrder'), isFalse,
          reason: 'P2 否定: 持久化不得携带排列字段');
      expect(written.containsKey('shufflePosition'), isFalse);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // P3 — 边界: 单曲播放单 + shuffle 建队
  // ═══════════════════════════════════════════════════════════════════════
  group('P3: 单曲播放单 shuffle 建队（退化语义与 withMode 一致）', () {
    testWidgets('playMode==shuffle 但无排列、不抛错', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final container = await pumpDetail(tester, prefs, [
        _track(1, 'lone.mp3'),
      ]);
      container.read(persistQueueOnChangeProvider);

      final cycle = container.read(nextPlayModeProvider);
      cycle();
      cycle();
      cycle(); // → shuffle

      await tester.tap(find.text('lone.mp3'));
      await tester.pumpAndSettle();

      final queue = container.read(currentPlayQueueProvider);
      expect(queue, isNotNull, reason: 'P3: 单曲建队不抛错');
      expect(queue!.playMode, equals(PlayMode.shuffle),
          reason: 'P3: 模式字段仍必须同步为 shuffle');
      expect(queue.currentIndex, equals(0));
      expect(persistedOrder(queue), isNull,
          reason: 'P3: files.length <= 1 → 无排列可生成'
              '（与 withMode/构造器 files.length > 1 条件一致）');
      expect(persistedPosition(queue), isNull);

      final written =
          jsonDecode(prefs.getString(_qKey)!) as Map<String, dynamic>;
      expect(written['playMode'], equals('shuffle'));
      expect(written.containsKey('shuffleOrder'), isFalse);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // P4 — 端到端: shuffle 建队 → 持久化 → 重启恢复仍 shuffle（串起 0fb11dc）
  // ═══════════════════════════════════════════════════════════════════════
  group('P4: 端到端 — shuffle 建队 → 重启恢复 == shuffle', () {
    testWidgets('恢复链路读回 shuffle（模式+排列+指针），skipToNext 走排列', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final container = await pumpDetail(tester, prefs, [
        _track(1, 'a.mp3'),
        _track(2, 'b.mp3'),
        _track(3, 'c.mp3'),
        _track(4, 'd.mp3'),
      ]);
      container.read(persistQueueOnChangeProvider);

      // ── 第一段: 「上次会话」切 shuffle 后点末位曲目建队 ─────────────
      final cycle = container.read(nextPlayModeProvider);
      cycle();
      cycle();
      cycle(); // → shuffle

      // 点末位: 末位上 sequential 无下一首，shuffle 必前进 → 零偶然判别锚
      await tester.tap(find.text('d.mp3'));
      await tester.pumpAndSettle();

      final queue = container.read(currentPlayQueueProvider);
      expect(queue, isNotNull);
      expect(queue!.currentIndex, equals(3), reason: '前置: 末位建队');
      expect(queue.playMode, equals(PlayMode.shuffle),
          reason: '前置（即 P1 核心）: 建队模式为 shuffle');
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
          reason: 'P4: 恢复的队列模式为 shuffle（修复前建队落 sequential，'
              '忠实恢复后模式丢失）');
      expect(session2.read(playModeProvider), equals(PlayMode.shuffle),
          reason: 'P4: 0fb11dc 链路把持久化模式写回 playModeProvider');
      expect(persistedOrder(restored), equals(order),
          reason: 'P4: 恢复保留建队时的排列（不重洗）');
      expect(persistedPosition(restored), equals(pos), reason: 'P4: 恢复保留指针');
      expect(restored.currentIndex, equals(3), reason: 'P4: 当前曲不变');

      // ── 行为锚: shuffle 真的活了 ───────────────────────────────────
      final orchestrator = session2.read(playbackOrchestratorProvider);
      await orchestrator.skipToNext();
      final advanced = session2.read(currentPlayQueueProvider)!;
      expect(advanced.currentIndex, isNot(3),
          reason: 'P4 行为锚: 末位上 sequential 无下一首，'
              'skipToNext 能前进即证明恢复的 shuffle 生效（零偶然判别）');
      expect(advanced.playMode, equals(PlayMode.shuffle));
    });
  });
}
