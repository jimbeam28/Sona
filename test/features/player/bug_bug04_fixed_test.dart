// test/features/player/bug_bug04_fixed_test.dart
// BUG-04: Shuffle 排列一致性缺陷簇 — spec 门禁测试（修复后断言）
//
// 来源：docs/features/BUG-04.md（cr-20260724-0110 PLY1 / PLY3 / MDL4）
// 用户裁决（2026-07-24）：PLY3 shuffle 排列耗尽策略 → 重洗新一轮。
//
// BUG-04-S1  insertAfterCurrent 在 shuffle 模式下重映射排列（不重生成、
//            不丢曲、新文件不入本轮排列）
// BUG-04-S2  advanceShuffle 返回 null（排列耗尽）时重洗新一轮
// BUG-04-S3  skipToPrevious 在排列头部时重洗，指针落末尾
// BUG-04-S4  withIndex 在 shuffle 模式下重定位 shufflePosition
// BUG-04-INV1 排列中索引始终有效（< files.length）
// BUG-04-INV2 确定性：同排列同位置/同种子 → 同结果
// BUG-04-INV3 withIndex 后 shufflePosition 指向 newIndex 在排列中的位置
// BUG-04-ALG1 remapShuffleOrder 算法样例
// BUG-04-ALG2 regenerateShuffle 算法样例

import 'dart:async';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:nas_audio_player/features/player/domain/playback_orchestrator.dart';
import 'package:nas_audio_player/shared/models/connection_config.dart';
import 'package:nas_audio_player/shared/models/nas_file.dart';
import 'package:nas_audio_player/shared/models/play_queue.dart';

import '../../helpers/test_factories.dart';

// ── Hand-written fakes (no build_runner needed, pattern: bug_bug19) ─────────

class _FakeConnectionProvider implements ActiveConnectionProvider {
  ConnectionConfig? connection;

  @override
  ConnectionConfig? get currentConnection => connection;

  @override
  Future<ConnectionConfig?> getActiveConnection() async => connection;
}

class _FakePasswordReader implements PasswordReader {
  @override
  Future<String?> readPassword(int connectionId) async => 'secret';
}

class _FakeProgressSaver implements ProgressSaver {
  int calls = 0;

  @override
  Future<void> upsertProgress({
    required int connectionId,
    required String filePath,
    required int positionMs,
    int? durationMs,
  }) async {
    calls++;
  }
}

class _FakeSpeedProvider implements DefaultSpeedProvider {
  @override
  double getDefaultSpeed() => 1.0;
}

class _FakeQueueConnIdProvider implements QueueConnectionIdProvider {
  @override
  int? getLastQueueConnectionId() => null;
}

/// Minimal fake [AudioPlayer]; unimplemented members throw via [Fake].
class _FakePlayer extends Fake implements AudioPlayer {
  int setAudioSourceCalls = 0;

  @override
  Stream<ProcessingState> get processingStateStream => const Stream.empty();

  @override
  Stream<PlayerState> get playerStateStream => const Stream.empty();

  @override
  bool get playing => true;

  @override
  Duration get position => const Duration(seconds: 5);

  @override
  Duration? get duration => const Duration(minutes: 3);

  @override
  Future<Duration?> setAudioSource(AudioSource source,
      {bool preload = true,
      int? initialIndex,
      Duration? initialPosition}) async {
    setAudioSourceCalls++;
    return Duration.zero;
  }

  @override
  Future<void> play() async {}

  @override
  Future<void> pause() async {}

  @override
  Future<void> stop() async {}

  @override
  Future<void> seek(Duration? position, {int? index}) async {}

  @override
  Future<void> setSpeed(double speed) async {}
}

// ── Helpers ──────────────────────────────────────────────────────────────────

List<NasFile> makeFiles(int count) => List.generate(
    count,
    (i) => testAudio('track_${(i + 1).toString().padLeft(2, '0')}.mp3',
        '/music/track_${(i + 1).toString().padLeft(2, '0')}.mp3'));

/// Explicitly seeded shuffle queue: order/position are constructor-injected so
/// assertions are exact (no dependence on the RNG).
PlayQueue shuffleQueue(
  int fileCount,
  List<int> order,
  int position, {
  int? currentIndex,
}) {
  return PlayQueue(
    files: makeFiles(fileCount),
    currentIndex: currentIndex ?? order[position],
    playMode: PlayMode.shuffle,
    shuffleOrder: order,
    shufflePosition: position,
  );
}

List<int> persistedOrder(PlayQueue q) =>
    (q.toMap()['shuffleOrder'] as List).cast<int>();

int persistedPosition(PlayQueue q) => q.toMap()['shufflePosition'] as int;

({
  PlaybackOrchestrator orchestrator,
  _FakePlayer player,
  _FakeProgressSaver saver
}) createOrchestrator({Random? random}) {
  final connection = ConnectionConfig(
    id: 1,
    name: 'test',
    url: 'http://localhost:8080',
    username: 'user',
    createdAt: DateTime(2024),
    updatedAt: DateTime(2024),
  );
  final player = _FakePlayer();
  final saver = _FakeProgressSaver();
  final orchestrator = PlaybackOrchestrator(
    player: player,
    connectionProvider: _FakeConnectionProvider()..connection = connection,
    passwordReader: _FakePasswordReader(),
    progressSaver: saver,
    defaultSpeedProvider: _FakeSpeedProvider(),
    queueConnectionIdProvider: _FakeQueueConnIdProvider(),
    random: random,
  );
  orchestrator.playMode = PlayMode.shuffle;
  return (orchestrator: orchestrator, player: player, saver: saver);
}

void main() {
  // ═══════════════════════════════════════════════════════════════════════
  // BUG-04-S1 / ALG1 — insertAfterCurrent 重映射 shuffle 排列
  // ═══════════════════════════════════════════════════════════════════════
  group('BUG-04-S1: insertAfterCurrent remaps shuffle order', () {
    test('ALG1 典型: order=[0,2,3,1], ci=0 → [0,3,4,2]，新文件不入排列', () {
      final q = shuffleQueue(4, [0, 2, 3, 1], 0); // 播 A，排列 A→C→D→B
      final x = testAudio('X.mp3', '/music/X.mp3');

      final inserted = q.insertAfterCurrent(x);

      // files=[A,X,B,C,D]
      expect(inserted.length, equals(5));
      expect(inserted.files[1].path, equals('/music/X.mp3'),
          reason: 'X 插入到 currentIndex+1');
      expect(inserted.currentIndex, equals(0), reason: '否定断言: ci 不变');

      // 重映射: >ci 的索引 +1 → [0,3,4,2]
      expect(persistedOrder(inserted), equals([0, 3, 4, 2]),
          reason: 'ALG1: >currentIndex 的索引 +1，逐元素重映射');
      // 否定断言：新文件（index 1）不入排列
      expect(persistedOrder(inserted).contains(1), isFalse,
          reason: '否定断言: 新文件不入本轮 shuffle 排列');
      // 否定断言：不丢曲——原 4 首全部仍在排列中（按新索引 {0,2,3,4}）
      expect(List<int>.from(persistedOrder(inserted))..sort(),
          equals([0, 2, 3, 4]),
          reason: '否定断言: 原有曲目无一丢失（重映射后恰为原曲的新索引集）');
      // 否定断言：不是重生成——重生成会得到 {0,1,2,3,4} 的全排列（含 1）
      expect(persistedOrder(inserted).length, equals(4),
          reason: '否定断言: 不重生成整个排列（长度仍为原排列长度）');
    });

    test('ALG1: order=[0,2,3,1], ci=2 → [0,2,4,1]', () {
      final q = shuffleQueue(4, [0, 2, 3, 1], 2, currentIndex: 2);
      final inserted = q.insertAfterCurrent(testAudio('X.mp3', '/music/X.mp3'));
      expect(persistedOrder(inserted), equals([0, 2, 4, 1]));
      expect(inserted.currentIndex, equals(2));
      expect(persistedOrder(inserted).contains(3), isFalse,
          reason: '新文件位于 index 3，不入排列');
    });

    test('ALG1: sequential（order=null）→ 仍为 null，行为不变', () {
      final q = PlayQueue(files: makeFiles(4), currentIndex: 1);
      expect(q.toMap().containsKey('shuffleOrder'), isFalse,
          reason: '前置: sequential 队列无排列');

      final inserted = q.insertAfterCurrent(testAudio('X.mp3', '/music/X.mp3'));

      expect(inserted.toMap().containsKey('shuffleOrder'), isFalse,
          reason: '否定断言: sequential 模式插入不生成排列');
      expect(inserted.length, equals(5));
      expect(inserted.currentIndex, equals(1));
    });

    test('ALG1: order=[0], ci=0（单曲）→ [0]，无 >0 索引需 +1', () {
      final q = shuffleQueue(1, [0], 0);
      final inserted = q.insertAfterCurrent(testAudio('X.mp3', '/music/X.mp3'));
      expect(persistedOrder(inserted), equals([0]), reason: '单曲排列重映射后不变');
      expect(inserted.length, equals(2));
      expect(persistedOrder(inserted).contains(1), isFalse,
          reason: '新文件（index 1）不入排列');
    });

    test('ALG1: ci 位于队尾时插入——无索引需 +1，排列不变', () {
      // order=[2,0,3,1]，ci=3（order 中索引值最大者之一）
      final q = shuffleQueue(4, [2, 0, 3, 1], 2, currentIndex: 3);
      final inserted = q.insertAfterCurrent(testAudio('X.mp3', '/music/X.mp3'));
      expect(inserted.files[4].path, equals('/music/X.mp3'),
          reason: 'ci 队尾 → 新文件插入末尾');
      expect(persistedOrder(inserted), equals([2, 0, 3, 1]),
          reason: '无 >ci 的索引，排列逐元素不变');
    });

    test('连续两次 insertAfterCurrent — 每次独立重映射，累积正确', () {
      final q = shuffleQueue(4, [0, 2, 3, 1], 0, currentIndex: 1); // 播 B
      final y = testAudio('Y.mp3', '/music/Y.mp3');

      final twice = q.insertAfterCurrent(y).insertAfterCurrent(y);

      // files=[A,B,Y,Y,C,D]（两份 Y 在 index 2,3）
      expect(twice.length, equals(6));
      // 第一次重映射 [0,2,3,1]→[0,3,4,1]；第二次 [0,3,4,1]→[0,4,5,1]
      expect(persistedOrder(twice), equals([0, 4, 5, 1]));
      expect(persistedOrder(twice).contains(2), isFalse,
          reason: '第 1 份 Y 不入排列');
      expect(persistedOrder(twice).contains(3), isFalse,
          reason: '第 2 份 Y 不入排列');
      expect(
          List<int>.from(persistedOrder(twice))..sort(), equals([0, 1, 4, 5]),
          reason: '原 4 曲全部保留（新索引 0,1,4,5）');
    });

    test('INV1: 重映射后排列索引全部有效（< files.length）', () {
      var q = shuffleQueue(5, [4, 0, 3, 1, 2], 1);
      for (var i = 0; i < 3; i++) {
        q = q.insertAfterCurrent(testAudio('Y$i.mp3', '/music/Y$i.mp3'));
        for (final idx in persistedOrder(q)) {
          expect(idx >= 0 && idx < q.length, isTrue,
              reason: 'INV1: 插入后排列索引 $idx 必须在 files 范围内');
        }
      }
    });

    test('重映射后 advanceShuffle 走到的是"逻辑上的下一曲"（PLY1 复现逆转）', () {
      // cr PLY1 复现路径: files=[A,B,C,D] 播 A，order=[0,2,3,1]（A→C→D→B）
      // 修复前: insertAfterCurrent(X) 后解码循环变 A→B→C→X，D 被永久跳过。
      // 修复后: 下一曲必须是 C（重映射后 order[1]）。
      final q = shuffleQueue(4, [0, 2, 3, 1], 0);
      final inserted = q.insertAfterCurrent(testAudio('X.mp3', '/music/X.mp3'));

      final next = inserted.advanceShuffle();
      expect(next, isNotNull, reason: '排列未耗尽，advance 必须成功');
      // files=[A,X,B,C,D] → C 的新索引是 3
      expect(next!.currentIndex, equals(3),
          reason: '下一曲必须是 C（index 3），不得是被错位的 B');
      expect(next.current.path, equals('/music/track_03.mp3'));

      // 走完整个排列: A→C→D→B，恰好每曲一次，无 X、无丢曲
      final visited = <String>[inserted.current.path];
      var cur = inserted;
      while (true) {
        final n = cur.advanceShuffle();
        if (n == null) break;
        visited.add(n.current.path);
        cur = n;
      }
      expect(
          visited,
          equals([
            '/music/track_01.mp3', // A
            '/music/track_03.mp3', // C
            '/music/track_04.mp3', // D
            '/music/track_02.mp3', // B
          ]),
          reason: '否定断言: 不丢曲（D 不被跳过）、X 不意外入列、不错位');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // BUG-04-S4 / INV3 — withIndex 重定位 shufflePosition
  // ═══════════════════════════════════════════════════════════════════════
  group('BUG-04-S4: withIndex relocates shufflePosition', () {
    test('MDL4 复现逆转: 点 C(index 2) 后 shufflePosition 重定位', () {
      // cr MDL4 场景: order=[0,2,1,3]（A→C→B→D）pos=0（播 A）→ withIndex(2)
      // → pos = indexOf(2) in order = 1（注: BUG-04 spec §3.3 样例的 "=2"
      // 为笔误，[0,2,1,3] 中值 2 的位置是 1）
      final q = shuffleQueue(4, [0, 2, 1, 3], 0);

      final selected = q.withIndex(2);

      expect(persistedPosition(selected), equals(1),
          reason: 'INV3: shufflePosition == shuffleOrder.indexOf(newIndex)');
      expect(persistedOrder(selected), equals([0, 2, 1, 3]),
          reason: '否定断言: 不重生成排列（仅重定位指针）');
      // 下一首 = order[2] = 1（B）——排列 A→C→B→D 中 C 之后是 B，不得重播 C
      expect(selected.nextShuffleIndex(), equals(1),
          reason: 'MDL4: 下一首必须是排列中该曲之后的那首，不重播刚选的曲');
      expect(selected.previousShuffleIndex(), equals(0),
          reason: '上一首 = order[0] = A');
    });

    test('排列内每个索引 withIndex 后 pos 都指向其排列位置', () {
      const order = [0, 2, 1, 3];
      final q = shuffleQueue(4, order, 0);
      for (var i = 0; i < 4; i++) {
        expect(persistedPosition(q.withIndex(i)), equals(order.indexOf(i)),
            reason: 'INV3: withIndex($i) 后 pos == indexOf($i)');
      }
    });

    test('newIndex 不在排列中（插入曲）→ 降级为排列末尾', () {
      // insertAfterCurrent 的曲目不入排列；手动选它时指针降级末尾（spec S4
      // 否定断言），下一首 advanceShuffle 报告本轮耗尽 → 编排层重洗新一轮。
      final q = shuffleQueue(4, [0, 2, 3, 1], 0);
      final withX = q.insertAfterCurrent(testAudio('X.mp3', '/music/X.mp3'));
      // files=[A,X,B,C,D], order=[0,3,4,2]; X 在 index 1，不在排列中

      final selected = withX.withIndex(1);

      expect(persistedPosition(selected), equals(3),
          reason: '否定断言: 不在排列中时降级为排列末尾（length-1=3）');
      expect(selected.advanceShuffle(), isNull,
          reason: '指针在末尾 → advanceShuffle 报告本轮耗尽');
      expect(persistedOrder(selected), equals([0, 3, 4, 2]),
          reason: '否定断言: 排列本身不变');
    });

    test('withIndex(currentIndex) — pos 不变（indexOf 返回原位置）', () {
      final q = shuffleQueue(4, [3, 0, 2, 1], 2); // 播 order[2]=2
      expect(persistedPosition(q.withIndex(q.currentIndex)), equals(2));
    });

    test('sequential 模式 withIndex — 无 shuffle 字段（行为不变）', () {
      final q = PlayQueue(files: makeFiles(4), currentIndex: 0);
      final moved = q.withIndex(2);
      expect(moved.currentIndex, equals(2));
      expect(moved.toMap().containsKey('shuffleOrder'), isFalse);
      expect(moved.toMap().containsKey('shufflePosition'), isFalse);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // BUG-04-S2 / ALG2 — 排列耗尽重洗新一轮（computeNextQueue + skipToNext）
  // ═══════════════════════════════════════════════════════════════════════
  group('BUG-04-S2: exhausted permutation reshuffles a fresh round', () {
    test('computeNextQueue 在排列末位 → 重洗: pos=0、首曲≠刚播完曲目', () {
      final env = createOrchestrator(random: Random(20260724));
      // order=[0,2,3,1] pos=3（末位）→ 当前曲 = order[3] = 1（B）
      env.orchestrator.queue = shuffleQueue(4, [0, 2, 3, 1], 3);

      final next = env.orchestrator.computeNextQueue();

      expect(next, isNotNull, reason: 'shuffle 耗尽不得停止播放（重洗新一轮）');
      final order = persistedOrder(next!);
      expect(List<int>.from(order)..sort(), equals([0, 1, 2, 3]),
          reason: '新排列是全体索引的一个置换（每曲每轮恰好一次）');
      expect(order[0], isNot(equals(1)), reason: '否定断言: 新排列不以刚播完的曲目开头（不重播）');
      expect(next.currentIndex, equals(order[0]), reason: '重洗后当前曲 = 新排列第一首');
      expect(persistedPosition(next), equals(0),
          reason: 'shufflePosition 复位为 0');
      expect(next.startPositionMs, isNull);
      // 否定断言: 不降级随机盲选——随机盲选会携带旧排列 [0,2,3,1]
      expect(order, isNot(equals([0, 2, 3, 1])),
          reason: '否定断言: 不携带旧排列（种子 20260724 下新排列≠旧排列）');
    });

    test('否定断言（多种子扫描）: 重洗产物永远不是"旧排列+随机位置"', () {
      // 修复前的盲选回落: q.withIndex(randomNi) 携带旧排列 [0,2,3,1]，
      // pos=indexOf(ni)∈{0,1,2}。扫描多个种子：只要出现一个新排列 ≠ 旧排列，
      // 即证明走的是重洗而非盲选（盲选下排列恒等于旧排列）。
      final oldOrder = [0, 2, 3, 1];
      var sawNewOrder = false;
      for (var seed = 0; seed < 15; seed++) {
        final env = createOrchestrator(random: Random(seed));
        env.orchestrator.queue = shuffleQueue(4, oldOrder, 3);
        final next = env.orchestrator.computeNextQueue()!;
        final order = persistedOrder(next);
        expect(order[0], isNot(equals(1)), reason: 'seed $seed: 首曲排除');
        expect(persistedPosition(next), equals(0),
            reason: 'seed $seed: pos 复位 0');
        expect(next.currentIndex, equals(order[0]));
        if (order.toString() != oldOrder.toString()) sawNewOrder = true;
      }
      expect(sawNewOrder, isTrue, reason: '否定断言: 15 个种子下至少一次产生新排列——排除盲选回落');
    });

    test('排列中段 completed → advanceShuffle 原排列推进，不重洗', () {
      final env = createOrchestrator(random: Random(1));
      env.orchestrator.queue = shuffleQueue(4, [0, 2, 3, 1], 0); // pos 0

      final next = env.orchestrator.computeNextQueue();

      expect(next, isNotNull);
      expect(persistedOrder(next!), equals([0, 2, 3, 1]),
          reason: '未耗尽时不得重洗——排列原样推进');
      expect(next.currentIndex, equals(2), reason: 'order[1] = 2（C）');
      expect(persistedPosition(next), equals(1));
    });

    test('ALG2: n=2, excludeIndex=1 → order[0] 唯一非 exclude 选择', () {
      final env = createOrchestrator(random: Random(7));
      env.orchestrator.queue = shuffleQueue(2, [0, 1], 1); // 播 index 1，末位

      final next = env.orchestrator.computeNextQueue();

      expect(next, isNotNull);
      expect(persistedOrder(next!), equals([0, 1]),
          reason: 'n=2 排除 index 1 后唯一合法排列');
      expect(next.currentIndex, equals(0));
      expect(persistedPosition(next), equals(0));
    });

    test('ALG2: n=1 — 重洗后排列=[0]，仍播同一首（边界裁决）', () {
      final env = createOrchestrator(random: Random(7));
      env.orchestrator.queue = shuffleQueue(1, [0], 0);

      final next = env.orchestrator.computeNextQueue();

      expect(next, isNotNull, reason: '单曲 shuffle 耗尽仍重洗续播');
      expect(persistedOrder(next!), equals([0]));
      expect(next.currentIndex, equals(0));
      expect(persistedPosition(next), equals(0));
    });

    test('skipToNext 在排列末位 → 重洗并加载新曲（端到端）', () async {
      final env = createOrchestrator(random: Random(20260724));
      env.orchestrator.queue = shuffleQueue(4, [0, 2, 3, 1], 3); // 播 B(1)

      final result =
          await env.orchestrator.skipToNext(registerListeners: false);

      expect(result.isLoaded, isTrue, reason: '重洗后必须成功加载新曲');
      final q = env.orchestrator.queue!;
      final order = persistedOrder(q);
      expect(List<int>.from(order)..sort(), equals([0, 1, 2, 3]));
      expect(order[0], isNot(equals(1)), reason: '不重播刚播完的曲目');
      expect(q.currentIndex, equals(order[0]));
      expect(persistedPosition(q), equals(0));
      expect(env.player.setAudioSourceCalls, equals(1));
      expect(env.saver.calls, equals(1), reason: '切歌前保存进度');
    });

    test('INV2: 同种子同队列 → 重洗结果确定一致', () {
      final envA = createOrchestrator(random: Random(99));
      final envB = createOrchestrator(random: Random(99));
      envA.orchestrator.queue = shuffleQueue(5, [4, 1, 0, 2, 3], 4);
      envB.orchestrator.queue = shuffleQueue(5, [4, 1, 0, 2, 3], 4);

      final nextA = envA.orchestrator.computeNextQueue()!;
      final nextB = envB.orchestrator.computeNextQueue()!;

      expect(persistedOrder(nextA), equals(persistedOrder(nextB)),
          reason: 'INV2: 种子相同 → 重洗排列相同');
      expect(nextA.currentIndex, equals(nextB.currentIndex));
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // BUG-04-S3 — skipToPrevious 在排列头部重洗，指针落末尾
  // ═══════════════════════════════════════════════════════════════════════
  group('BUG-04-S3: skipToPrevious at permutation head reshuffles', () {
    test('排列头部 previous → 重洗，pos=末尾，currentIndex=order[末尾]', () async {
      final env = createOrchestrator(random: Random(20260724));
      // order=[0,2,3,1] pos=0 → 当前曲 = order[0] = 0（A），retreat 返回 null
      env.orchestrator.queue = shuffleQueue(4, [0, 2, 3, 1], 0);

      final result =
          await env.orchestrator.skipToPrevious(registerListeners: false);

      expect(result.isLoaded, isTrue, reason: '头部 previous 不得失败');
      final q = env.orchestrator.queue!;
      final order = persistedOrder(q);
      expect(List<int>.from(order)..sort(), equals([0, 1, 2, 3]),
          reason: '新排列是全体索引的置换');
      expect(order[0], isNot(equals(0)), reason: '排除刚播完/正在播的曲目作为新排列首曲');
      expect(persistedPosition(q), equals(order.length - 1),
          reason: 'S3: shufflePosition 放到末尾');
      expect(q.currentIndex, equals(order[order.length - 1]),
          reason: 'S3: currentIndex = 排列最后一首');
      // 否定断言: 不降级 previousIndex 随机——随机盲选会携带旧排列
      expect(order, isNot(equals([0, 2, 3, 1])),
          reason: '否定断言: 不携带旧排列（种子 20260724 下新排列≠旧排列）');
      // 从新位置可以倒退遍历整个新轮次（retreat 链不抛、不空）
      var cur = q;
      final walked = <int>[cur.currentIndex];
      while (true) {
        final p = cur.retreatShuffle();
        if (p == null) break;
        walked.add(p.currentIndex);
        cur = p;
      }
      expect(walked.length, equals(4), reason: '末尾起步可倒退走完整个新轮次');
    });

    test('排列中段 previous → retreatShuffle 原排列倒退，不重洗', () async {
      final env = createOrchestrator(random: Random(1));
      env.orchestrator.queue = shuffleQueue(4, [0, 2, 3, 1], 2); // 播 D(3)

      final result =
          await env.orchestrator.skipToPrevious(registerListeners: false);

      expect(result.isLoaded, isTrue);
      final q = env.orchestrator.queue!;
      expect(persistedOrder(q), equals([0, 2, 3, 1]), reason: '未到头不得重洗');
      expect(q.currentIndex, equals(2), reason: 'retreat → order[1] = 2');
      expect(persistedPosition(q), equals(1));
    });

    test('n=1 头部 previous → 重洗排列=[0]，pos=0，仍播同一首', () async {
      final env = createOrchestrator(random: Random(7));
      env.orchestrator.queue = shuffleQueue(1, [0], 0);

      final result =
          await env.orchestrator.skipToPrevious(registerListeners: false);

      expect(result.isLoaded, isTrue);
      final q = env.orchestrator.queue!;
      expect(persistedOrder(q), equals([0]));
      expect(q.currentIndex, equals(0));
      expect(persistedPosition(q), equals(0));
    });
  });
}
