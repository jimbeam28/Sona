// test/features/player/play_mode_queue_writeback_test.dart
// 配套缺陷修复: 模式切换不回写队列 playMode 字段 — 回归门禁测试
//
// 问题: PlayQueue.withMode 在 lib/ 内零调用方。用户在 UI 切换播放模式时
// （PlayModeControl → nextPlayModeProvider → playModeProvider）只更新
// playModeProvider 与 orchestrator.playMode，不回写队列的 playMode 字段。
// 队列持久化（persistQueueOnChangeProvider → PlayQueue.toMap()）因此恒写
// 创建队列时的值（通常 sequential）→ 用户切 shuffle → 退出 → 重启，
// 0fb11dc 的恢复链路忠实地把持久化的 sequential 写回 playModeProvider →
// 模式选择丢失。端到端「恢复上次退出状态」不成立。
//
// 修复: nextPlayModeProvider 写完 playModeProvider 后，若队列存在且
// q.playMode != 新模式，以 q.withMode(n) 回写 currentPlayQueueProvider，
// persistQueueOnChange 自然捕获。withMode 语义补齐:
//   - 进入 shuffle: 生成新 Fisher-Yates 排列，指针定位到当前曲在排列中
//     的槽位（order[pos] == currentIndex，与 BUG-04-S4 withIndex /
//     BUG-14 fromMap 归一化 / _regenerateShuffleQueue 的既定不变量一致）
//   - 离开 shuffle: 清空排列与指针（维持「shuffleOrder != null ⟺
//     playMode == shuffle」模型不变量; 裁决: 清空而非保留 —— 持久化的
//     sequential 队列不得携带陈旧排列，toMap/fromMap round-trip 无歧义，
//     再切回 shuffle 总是全新一轮，与新建 shuffle 语义一致）
//   - 同模式: 返回 this（幂等; 防止重复点击把进行中的一轮排列重洗）
//
// 用例:
//   M1  withMode sequential→shuffle: 排列生成 + 指针锚定当前曲
//   M2  withMode shuffle→sequential: 排列清空
//   M3  withMode 同模式: identical 幂等，进行中的排列不被重洗
//   M4  单曲队列切 shuffle: 无排列（files.length<=1），不抛错
//   M5  PlayMode 全值 4×4 穷举: 字段保持 + 排列进出规则
//   S1  核心 RED: 切 shuffle → persistQueueOnChange → prefs playMode=="shuffle"
//   S2  非 shuffle 特例: 切 repeatOne → 队列与 prefs 同步
//   S3  shuffle → sequential: 队列回写 + prefs 无 shuffleOrder
//   S4  无队列切模式: 不抛错，prefs 不落队列
//   S5  整轮循环幂等: 4 次切换回到 sequential，队列 == 原队列
//   S6  orchestrator 双同步: queue.playMode 与 orchestrator.playMode 一致
//   E1  端到端锚: 切 shuffle → 持久化 → 「重启」恢复 == shuffle（含排列、
//       指针），且 skipToNext 走 shuffle 路径（判别: currentIndex 为末位时
//       sequential 无下一首，shuffle 必前进 → 零偶然判别）

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nas_audio_player/shared/di/providers.dart';
import 'package:nas_audio_player/shared/models/connection_config.dart';
import 'package:nas_audio_player/shared/models/nas_file.dart';
import 'package:nas_audio_player/shared/models/play_queue.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/mock_audio_player.dart';
import '../../helpers/test_factories.dart';

const _qKey = 'last_play_queue';

List<NasFile> _files(int n) => List.generate(
    n, (i) => testAudio('track_${i + 1}.mp3', '/music/track_${i + 1}.mp3'));

/// sequential 队列; [currentIndex] 默认末位 —— 端到端行为锚的判别基础:
/// 末位上 sequential 无下一首（nextIndex == null），shuffle 必前进。
PlayQueue _sequentialQueue({int n = 4, int? currentIndex}) =>
    PlayQueue(files: _files(n), currentIndex: currentIndex ?? n - 1);

ProviderContainer makeContainer(SharedPreferences prefs) {
  final container = ProviderContainer(overrides: [
    sharedPreferencesProvider.overrideWithValue(prefs),
    activeConnectionProvider
        .overrideWith((ref) async => null as ConnectionConfig?),
    audioPlayerProvider.overrideWithValue(MockAudioPlayer()),
  ]);
  addTearDown(container.dispose);
  return container;
}

/// 从 toMap() 读排列（私有字段的行为观测通道，与 BUG-14 测试同款）。
List<int>? persistedOrder(PlayQueue q) =>
    (q.toMap()['shuffleOrder'] as List<dynamic>?)?.cast<int>();
int? persistedPosition(PlayQueue q) => q.toMap()['shufflePosition'] as int?;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ═══════════════════════════════════════════════════════════════════════
  // M1~M5 — withMode 模型语义
  // ═══════════════════════════════════════════════════════════════════════
  group('M1: withMode sequential→shuffle 生成排列且指针锚定当前曲', () {
    test('排列是全排列，shufflePosition 指向当前曲的槽位', () {
      final queue = PlayQueue(files: _files(4), currentIndex: 2);

      final shuffled = queue.withMode(PlayMode.shuffle);

      expect(shuffled.playMode, equals(PlayMode.shuffle));
      expect(shuffled.currentIndex, equals(2), reason: '当前曲不变');
      expect(shuffled.files, equals(queue.files), reason: '曲目列表不变');
      final order = persistedOrder(shuffled);
      expect(order, isNotNull, reason: '进入 shuffle 必须生成排列');
      expect(order!.toList()..sort(), equals([0, 1, 2, 3]),
          reason: '排列必须是 0..n-1 的 Fisher-Yates 全排列');
      final pos = persistedPosition(shuffled);
      expect(pos, isNotNull);
      expect(order[pos!], equals(2),
          reason: 'M1 不变量: order[shufflePosition] == currentIndex —— '
              '与 BUG-04-S4/BUG-14/_regenerateShuffleQueue 的既定语义一致，'
              '不得重蹈指针失配');
    });
  });

  group('M2: withMode shuffle→sequential 清空排列（裁决: 清空不保留）', () {
    test('排列与指针被清空，toMap 不再携带 shuffle 字段', () {
      final shuffleQueue = PlayQueue(
        files: _files(4),
        currentIndex: 1,
        playMode: PlayMode.shuffle,
        shuffleOrder: const [2, 0, 3, 1],
        shufflePosition: 3,
      );

      final sequential = shuffleQueue.withMode(PlayMode.sequential);

      expect(sequential.playMode, equals(PlayMode.sequential));
      expect(sequential.currentIndex, equals(1), reason: '当前曲不变');
      expect(sequential.toMap().containsKey('shuffleOrder'), isFalse,
          reason: '离开 shuffle 清空排列 —— 持久化的 sequential 队列'
              '不得携带陈旧排列');
      expect(sequential.toMap().containsKey('shufflePosition'), isFalse);
      // 否定断言: 不得保留旧排列
      expect(persistedOrder(sequential), isNull);
    });
  });

  group('M3: withMode 同模式幂等', () {
    test('返回 this —— 进行中的一轮排列不得被重洗', () {
      final shuffleQueue = PlayQueue(
        files: _files(4),
        currentIndex: 0,
        playMode: PlayMode.shuffle,
        shuffleOrder: const [0, 2, 3, 1],
        shufflePosition: 1,
      );

      final same = shuffleQueue.withMode(PlayMode.shuffle);

      expect(identical(same, shuffleQueue), isTrue,
          reason: 'M3: 同模式重复切换必须幂等返回 this，'
              '重复点击不得把进行中的排列重洗');
      expect(persistedOrder(same), equals([0, 2, 3, 1]));
      expect(persistedPosition(same), equals(1));
    });

    test('sequential 同模式同样幂等', () {
      final queue = PlayQueue(files: _files(3), currentIndex: 0);
      expect(identical(queue.withMode(PlayMode.sequential), queue), isTrue);
    });
  });

  group('M4: 单曲队列切 shuffle 不生成排列、不抛错', () {
    test('files.length <= 1 → 无排列（与构造器新建 shuffle 队列语义一致）', () {
      final queue = PlayQueue(files: _files(1), currentIndex: 0);

      final shuffled = queue.withMode(PlayMode.shuffle);

      expect(shuffled.playMode, equals(PlayMode.shuffle));
      expect(persistedOrder(shuffled), isNull,
          reason: '单曲队列无排列可生成（构造器同款 files.length > 1 条件）');
      expect(persistedPosition(shuffled), isNull);
      // 单曲 shuffle 的下一首语义: 无下一首（与 nextIndex 边界一致）
      expect(shuffled.nextShuffleIndex(), isNull);
    });
  });

  group('M5: PlayMode 全值 4×4 穷举', () {
    for (final from in PlayMode.values) {
      for (final to in PlayMode.values) {
        test('$from → $to', () {
          final queue = from == PlayMode.shuffle
              ? PlayQueue(
                  files: _files(4),
                  currentIndex: 1,
                  playMode: PlayMode.shuffle,
                  shuffleOrder: const [1, 3, 0, 2],
                  shufflePosition: 0,
                )
              : PlayQueue(
                  files: _files(4),
                  currentIndex: 1,
                  playMode: from,
                );

          final result = queue.withMode(to);

          expect(result.playMode, equals(to), reason: '模式字段必须生效');
          expect(result.files, equals(queue.files), reason: '曲目不变');
          expect(result.currentIndex, equals(1), reason: '当前曲指针不变');
          if (from == to) {
            expect(identical(result, queue), isTrue, reason: '同模式幂等');
          } else if (to == PlayMode.shuffle) {
            final order = persistedOrder(result)!;
            expect(order.toList()..sort(), equals([0, 1, 2, 3]),
                reason: '进入 shuffle 生成全排列');
            expect(order[persistedPosition(result)!], equals(1),
                reason: '指针锚定当前曲');
          } else {
            expect(persistedOrder(result), isNull,
                reason: '离开/不进入 shuffle 不得携带排列');
            expect(persistedPosition(result), isNull);
          }
        });
      }
    }
  });

  // ═══════════════════════════════════════════════════════════════════════
  // S1~S6 — Provider 层: nextPlayModeProvider → 队列回写 → 持久化捕获
  // ═══════════════════════════════════════════════════════════════════════
  group('S1: 核心 RED — 切 shuffle 后持久化的 playMode 必须是 shuffle', () {
    test('sequential 队列 → 切到 shuffle → prefs JSON playMode=="shuffle"',
        () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final container = makeContainer(prefs);
      container.read(persistQueueOnChangeProvider); // 激活持久化监听

      final queue = _sequentialQueue();
      container.read(currentPlayQueueProvider.notifier).state = queue;
      expect(container.read(playModeProvider), equals(PlayMode.sequential));

      // sequential → repeatOne → repeatAll → shuffle
      final cycle = container.read(nextPlayModeProvider);
      cycle();
      cycle();
      final n = cycle();
      expect(n, equals(PlayMode.shuffle), reason: '前置: 已切到 shuffle');

      final q = container.read(currentPlayQueueProvider);
      expect(q, isNotNull);
      // 修复前: 队列 playMode 恒为创建时的 sequential → 本断言 FAIL
      expect(q!.playMode, equals(PlayMode.shuffle),
          reason: 'S1: 模式切换必须回写队列 playMode 字段');
      final order = persistedOrder(q);
      expect(order, isNotNull, reason: 'S1: 队列必须携带生成的排列');
      expect(order!.toList()..sort(), equals([0, 1, 2, 3]));
      expect(order[persistedPosition(q)!], equals(q.currentIndex),
          reason: 'S1: 指针锚定当前曲');

      // 端到端持久化锚: persistQueueOnChange 捕获队列变更 → toMap 落 prefs
      final raw = prefs.getString(_qKey);
      expect(raw, isNotNull, reason: '前置: 队列已持久化');
      final written = jsonDecode(raw!) as Map<String, dynamic>;
      // 核心 RED 断言 —— 修复前恒为 'sequential'
      expect(written['playMode'], equals('shuffle'),
          reason: 'S1 核心: 持久化的 playMode 必须反映用户切换后的模式，'
              '修复前恒为创建队列时的 sequential');
      expect(
          (written['shuffleOrder'] as List<dynamic>).cast<int>(), equals(order),
          reason: 'S1: 排列一并持久化');
      expect(written['shufflePosition'], equals(persistedPosition(q)));
    });
  });

  group('S2: 非 shuffle 模式同样回写（repeatOne）', () {
    test('切 repeatOne → 队列 playMode 与 prefs 同步', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final container = makeContainer(prefs);
      container.read(persistQueueOnChangeProvider);

      container.read(currentPlayQueueProvider.notifier).state =
          _sequentialQueue();
      container.read(nextPlayModeProvider)(); // sequential → repeatOne

      final q = container.read(currentPlayQueueProvider)!;
      expect(q.playMode, equals(PlayMode.repeatOne),
          reason: 'S2: 回写不限于 shuffle');
      expect(persistedOrder(q), isNull, reason: '非 shuffle 不生成排列');
      final written =
          jsonDecode(prefs.getString(_qKey)!) as Map<String, dynamic>;
      expect(written['playMode'], equals('repeatOne'));
    });
  });

  group('S3: shuffle → sequential 回写且排列清空', () {
    test('再切一次回到 sequential → prefs 无 shuffleOrder', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final container = makeContainer(prefs);
      container.read(persistQueueOnChangeProvider);

      container.read(currentPlayQueueProvider.notifier).state =
          _sequentialQueue();
      final cycle = container.read(nextPlayModeProvider);
      cycle();
      cycle();
      cycle(); // → shuffle
      expect(container.read(currentPlayQueueProvider)!.playMode,
          equals(PlayMode.shuffle),
          reason: '前置: 已处 shuffle');
      cycle(); // → sequential

      final q = container.read(currentPlayQueueProvider)!;
      expect(q.playMode, equals(PlayMode.sequential),
          reason: 'S3: shuffle → sequential 回写');
      final written =
          jsonDecode(prefs.getString(_qKey)!) as Map<String, dynamic>;
      expect(written['playMode'], equals('sequential'));
      expect(written.containsKey('shuffleOrder'), isFalse,
          reason: 'S3: 离开 shuffle 后持久化不得携带陈旧排列');
      expect(written.containsKey('shufflePosition'), isFalse);
    });
  });

  group('S4: 无队列切模式不抛错', () {
    test('纯切模式: provider 照常更新，无队列可写不抛错、prefs 不落队列', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final container = makeContainer(prefs);
      container.read(persistQueueOnChangeProvider);

      expect(container.read(currentPlayQueueProvider), isNull,
          reason: '前置: 无播放队列');

      final cycle = container.read(nextPlayModeProvider);
      final modes = <PlayMode>[];
      expect(() {
        for (int i = 0; i < 4; i++) {
          modes.add(cycle());
        }
      }, returnsNormally, reason: 'S4: 无队列不得抛错');
      expect(
          modes,
          equals([
            PlayMode.repeatOne,
            PlayMode.repeatAll,
            PlayMode.shuffle,
            PlayMode.sequential,
          ]),
          reason: 'S4: playModeProvider 照常循环');
      expect(container.read(currentPlayQueueProvider), isNull,
          reason: 'S4: 无队列切模式不得凭空造队列');
      expect(prefs.getString(_qKey), isNull, reason: 'S4: 无队列不得触发队列持久化');
    });
  });

  group('S5: 整轮循环幂等 — 4 次切换回到原状态', () {
    test('sequential 队列循环一整圈 → 队列与原队列判等', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final container = makeContainer(prefs);
      container.read(persistQueueOnChangeProvider);

      final original = _sequentialQueue();
      container.read(currentPlayQueueProvider.notifier).state = original;

      final cycle = container.read(nextPlayModeProvider);
      for (int i = 0; i < 4; i++) {
        cycle();
      }

      expect(container.read(playModeProvider), equals(PlayMode.sequential));
      final q = container.read(currentPlayQueueProvider)!;
      expect(q, equals(original),
          reason: 'S5 幂等: 一整圈后队列回到与原队列 == 判等的状态'
              '（files/currentIndex/playMode/无排列）');
      expect(q.currentIndex, equals(original.currentIndex),
          reason: 'S5: 模式切换不得移动当前曲指针');
    });
  });

  group('S6: orchestrator 双同步', () {
    test('切 shuffle 后 orchestrator.queue.playMode 与 playMode 一致', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final container = makeContainer(prefs);
      final orchestrator = container.read(playbackOrchestratorProvider);

      container.read(currentPlayQueueProvider.notifier).state =
          _sequentialQueue();
      final cycle = container.read(nextPlayModeProvider);
      cycle();
      cycle();
      cycle(); // → shuffle

      expect(orchestrator.playMode, equals(PlayMode.shuffle),
          reason: 'S6: orchestrator.playMode 经既有 ref.listen 同步');
      expect(orchestrator.queue, isNotNull);
      expect(orchestrator.queue!.playMode, equals(PlayMode.shuffle),
          reason: 'S6: 回写后的队列经队列同步通道进入 orchestrator，'
              '两侧模式不得分裂');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // E1 — 端到端锚: 切换 → 持久化 → 「重启」恢复 → shuffle 活着
  // ═══════════════════════════════════════════════════════════════════════
  group('E1: 端到端 — 切 shuffle → 退出 → 重启恢复 == shuffle', () {
    test('恢复链路读回 shuffle（模式 + 排列 + 指针），且 skipToNext 走排列', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      // ── 第一段: 「上次会话」切到 shuffle 并持久化 ──────────────────
      final session1 = makeContainer(prefs);
      session1.read(persistQueueOnChangeProvider);
      // currentIndex = 3（末位）: sequential 语义下无下一首，shuffle 语义下
      // 必前进 → skipToNext 结果成为零偶然的模式判别锚。
      session1.read(currentPlayQueueProvider.notifier).state =
          _sequentialQueue(n: 4, currentIndex: 3);
      final cycle = session1.read(nextPlayModeProvider);
      cycle();
      cycle();
      cycle(); // → shuffle
      final persisted =
          jsonDecode(prefs.getString(_qKey)!) as Map<String, dynamic>;
      expect(persisted['playMode'], equals('shuffle'),
          reason: '前置（即 S1 核心）: 持久化模式为 shuffle');
      session1.dispose();

      // ── 第二段: 「重启」恢复（0fb11dc 链路）────────────────────────
      final session2 = makeContainer(prefs);
      await session2.read(restoreQueueFromPrefsProvider.future);

      final restored = session2.read(currentPlayQueueProvider);
      expect(restored, isNotNull, reason: '前置: 队列被恢复');
      expect(restored!.playMode, equals(PlayMode.shuffle),
          reason: 'E1: 恢复的队列模式为 shuffle');
      expect(session2.read(playModeProvider), equals(PlayMode.shuffle),
          reason: 'E1: 0fb11dc 链路把持久化模式写回 playModeProvider —— '
              '现在写回的不再是恒 sequential');
      final order = (persisted['shuffleOrder'] as List<dynamic>).cast<int>();
      final pos = persisted['shufflePosition'] as int;
      expect(persistedOrder(restored), equals(order),
          reason: 'E1: 恢复保留持久化排列（不重洗）');
      expect(persistedPosition(restored), equals(pos), reason: 'E1: 恢复保留持久化指针');
      expect(restored.currentIndex, equals(3), reason: 'E1: 当前曲不变');

      // ── 行为锚: shuffle 真的活了 ───────────────────────────────────
      final orchestrator = session2.read(playbackOrchestratorProvider);
      await orchestrator.skipToNext();
      final advanced = session2.read(currentPlayQueueProvider)!;
      // 末位 currentIndex=3: sequential 的 nextIndex == null → 队列不得前进;
      // shuffle 排列推进/重洗都必然离开末位 → 非 3 即证明模式活着。
      expect(advanced.currentIndex, isNot(3),
          reason: 'E1 行为锚: 末位上 sequential 无下一首，'
              'skipToNext 能前进即证明 shuffle 生效（零偶然判别）');
      expect(advanced.playMode, equals(PlayMode.shuffle),
          reason: 'E1: 前进后仍处 shuffle 模式');
    });
  });
}
