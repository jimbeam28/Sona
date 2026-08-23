// test/shared/bug_bug24_shuffle_without_index_test.dart
// BUG-24 门禁测试（来源 cr-20260823-1421.md F2，复核分流 2026-08-23）。
//
// 缺陷：PlayQueue.withoutIndex（play_queue.dart:205-214）在 shuffle 模式下
// 置 shuffleOrder/shufflePosition 为 null → 构造器重洗新排列且指针归 0，
// 与 currentIndex 脱钩。违反同文件 withMode 文档声明的不变量
// `shuffleOrder[pos] == currentIndex`（withIndex BUG-04-S4 / fromMap
// BUG-14 均维护之）。
//
// 锚定方式（仅公开 API；模型层 advanceShuffle 到排列尾即返回 null，重洗在
// 编排层，故「走满一轮覆盖其余各曲」以如下可观察命题编码）：
//   P1 完备置换——retreat 到排列头后全量遍历，恰好覆盖剩余索引各一次；
//   P2 映射保序——该遍历的文件路径序列 = 删除前序列去掉被删文件（否定断言
//      「不得整体重洗」）；
//   P3 不重访——从删后队列原位前向推进，绝不出现当前曲。
// 修复前重洗+指针归 0 违反 P2/P3 → FAIL；修复后全部 PASS。
//
// 测试自修记录（dev-exe 2026-08-23，非改断言放行实现）：初版门禁有两处
// 与 spec 自身矛盾的创作错误——(a) 前置队列用裸构造器生成（指针锚槽位 0、
// 排列随机），不满足 §3.1 Given「order[pos] == currentIndex」；(b) 以
// advanceShuffle 单向遍历断言「访问其余三曲」，但指针锚定后位于排列中部，
// 数学上不可达（最多访问尾部若干槽）。本版改为显式构造满足 Given 的锚定
// 队列，并按上述 P1-P3 重述；sequential 回归守卫对齐 §3.1 S0。

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:nas_audio_player/shared/models/nas_file.dart';
import 'package:nas_audio_player/shared/models/play_queue.dart';

List<NasFile> _files(int n) => List.generate(
      n,
      (i) => NasFile(
          name: 'f$i.mp3',
          path: '/f$i.mp3',
          isDirectory: false,
          audioType: AudioFileType.music),
    );

/// 构造满足 §3.1 Given 的 shuffle 队列：排列由种子生成，
/// 指针锚定在 currentIndex 的槽位（order[pos] == currentIndex）。
PlayQueue _anchoredShuffleQueue(int n, int current, int seed,
    {int? startPositionMs}) {
  final order = PlayQueue.generateShuffleOrder(n, Random(seed));
  return PlayQueue(
    files: _files(n),
    currentIndex: current,
    startPositionMs: startPositionMs,
    playMode: PlayMode.shuffle,
    shuffleOrder: order,
    shufflePosition: order.indexOf(current),
  );
}

/// 从 [start] 出发反复 advanceShuffle 直到耗尽，返回访问的 index 序列
/// （不含 start 自身）。仅使用公开 API。
List<int> walkForward(PlayQueue start) {
  final visited = <int>[];
  PlayQueue? cur = start;
  while (true) {
    cur = cur?.advanceShuffle();
    if (cur == null) break;
    visited.add(cur.currentIndex);
  }
  return visited;
}

/// retreat 到排列头部后做全量遍历，返回完整排列的 index 序列
/// （含头部自身）。
List<int> fullPermutation(PlayQueue q) {
  var cur = q;
  while (true) {
    final prev = cur.retreatShuffle();
    if (prev == null) break;
    cur = prev;
  }
  return [cur.currentIndex, ...walkForward(cur)];
}

void main() {
  group('BUG-24-S1: withoutIndex 在 shuffle 模式下保持排列指针不变量', () {
    for (final seed in List<int>.generate(20, (i) => i + 1)) {
      test('seed=$seed：删除非当前曲后本轮不重访当前曲', () {
        final q0 = _anchoredShuffleQueue(4, 2, seed);

        // 前置条件：Given 队列本身满足不变量（P1 完备置换）。
        expect(fullPermutation(q0), unorderedEquals([0, 1, 2, 3]));

        final q1 = q0.withoutIndex(1); // 删非当前曲 f1

        expect(q1.playMode, PlayMode.shuffle);
        expect(q1.length, 3);
        expect(q1.current.path, '/f2.mp3');
        // P1+P2：排列为剩余索引的完备置换且逻辑轮次未被重洗。
        final beforePaths =
            fullPermutation(q0).map((i) => q0.files[i].path).toList();
        final afterPaths =
            fullPermutation(q1).map((i) => q1.files[i].path).toList();
        expect(afterPaths, beforePaths.where((p) => p != '/f1.mp3').toList(),
            reason: 'P2 映射保序：新排列 = 旧排列剔除被删曲（不得整体重洗）');
        expect(afterPaths.toSet(),
            unorderedEquals(['/f0.mp3', '/f2.mp3', '/f3.mp3']),
            reason: 'P1 完备置换：恰好覆盖其余三曲各一次');
        // P3 核心否定断言（修复前 FAIL）：当前曲不得在本轮内被重访。
        final forward = walkForward(q1);
        expect(forward, isNot(contains(1)),
            reason: 'shuffle 不变量被破坏：当前曲 f2 在删除后的本轮内被重访'
                '（指针与 currentIndex 脱钩）');
        expect(forward.every((i) => i >= 0 && i <= 2), isTrue);
      });
    }
    for (final seed in List<int>.generate(20, (i) => i + 1)) {
      test('seed=$seed：删除当前曲后接替者成为锚点（BUG-24-S2）', () {
        final q0 = _anchoredShuffleQueue(4, 2, seed, startPositionMs: 45000);

        final q2 = q0.withoutIndex(2); // 删当前曲 f2 → f3 移入 index 2

        expect(q2.length, 3);
        expect(q2.current.path, '/f3.mp3',
            reason: '末曲被删时接替者是前一位（既有语义，aud_01 已锚定）');
        expect(q2.startPositionMs, isNull,
            reason: '删当前曲清 startPositionMs（既有语义保留）');
        // P1：完备置换。
        expect(fullPermutation(q2).toSet(), unorderedEquals([0, 1, 2]));
        // P3 核心否定断言（修复前 FAIL）：接替者 f3（新当前曲）不得被重访。
        final forward = walkForward(q2);
        expect(forward, isNot(contains(2)),
            reason: '接替者成为新当前曲后不得在本轮内被重访（修复前 FAIL）');
      });
    }

    test('BUG-24 否定面：sequential 模式行为零变更（回归守卫，§3.1 S0）', () {
      final q = PlayQueue(files: _files(3), currentIndex: 1);
      final after = q.withoutIndex(0);
      expect(after.playMode, PlayMode.sequential);
      expect(after.advanceShuffle(), isNull, reason: 'sequential 下不得凭空生成排列');
      // S0 既有语义（aud_01 PLY-G06 锚定）：前曲删除减一，仍指向同一逻辑曲目。
      expect(after.currentIndex, 0);
      expect(after.current.path, '/f1.mp3');
    });

    test('BUG-24 边界：n-1 == 1 维持单曲无排列约定', () {
      final q = _anchoredShuffleQueue(2, 0, 7);
      final after = q.withoutIndex(1);
      expect(after.length, 1);
      expect(after.advanceShuffle(), isNull, reason: '单曲残留场景维持现状约定：无排列可推进');
    });

    test('BUG-24-INV1: 删任意一曲后指针仍锚定当前曲槽位（advance/retreat 互逆）', () {
      const seed = 11;
      for (final victim in [0, 1, 3]) {
        final q0 = _anchoredShuffleQueue(4, 2, seed);
        final q1 = q0.withoutIndex(victim);
        expect(q1.playMode, PlayMode.shuffle, reason: 'victim=$victim');
        var cur = q1;
        while (true) {
          final next = cur.advanceShuffle();
          if (next == null) break;
          final back = next.retreatShuffle();
          expect(back?.currentIndex, cur.currentIndex,
              reason: 'victim=$victim：advance/retreat 必须互逆（指针锚定完好）');
          cur = next;
        }
      }
    });

    test('BUG-24-ALG1: 映射保序——删除队首后其余曲目保持原轮次相对顺序', () {
      for (final seed in List<int>.generate(20, (i) => i + 1)) {
        final q0 = _anchoredShuffleQueue(4, 2, seed);
        final pathsBefore =
            fullPermutation(q0).map((i) => q0.files[i].path).toList();
        final q1 = q0.withoutIndex(0); // 删队首，全部旧索引 -1
        final pathsAfter =
            fullPermutation(q1).map((i) => q1.files[i].path).toList();
        expect(
          pathsAfter,
          pathsBefore.where((p) => p != '/f0.mp3').toList(),
          reason: 'seed=$seed：删除 f0 后其余曲目保持原轮次相对顺序（不得整体重洗）',
        );
      }
    });
  });
}
