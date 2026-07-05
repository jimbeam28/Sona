// test/shared/play_queue_insert_test.dart
// BRW-09: PlayQueue.insertAfterCurrent 纯函数单元测试
//
// Agent A — 测试先行。只读 docs/features/BRW-09.md 与 test/ 既有 helper；
// 禁止读 lib/ 。本文件覆盖 BRW-09-S3, S4(队列插入部分), S5, S6, S7, S8,
// INV1, INV2, INV3, ALG-insertAfterCurrent，及 §7 跨模块回归 PLY-REG-2, PLY-REG-3。
//
// 注意：实现尚未存在，测试必然 FAIL（缺 insertAfterCurrent 方法）。断言逻辑完整。

import 'package:flutter_test/flutter_test.dart';
import 'package:nas_audio_player/shared/models/play_queue.dart';

import '../helpers/test_factories.dart';

void main() {
  group('BRW-09: PlayQueue.insertAfterCurrent 纯函数', () {
    // ── 辅助构造一个典型队列 ──────────────────────────────────────────────
    PlayQueue buildQueue(int count, int currentIndex, {PlayMode? mode}) {
      final files = List.generate(count, (i) {
        final n = (i + 1).toString().padLeft(2, '0');
        return testAudio('track_$n.mp3', '/music/track_$n.mp3');
      });
      return PlayQueue(
        files: files,
        currentIndex: currentIndex,
        playMode: mode ?? PlayMode.sequential,
      );
    }

    // ── ALG 典型：ci 在中间插入 Y ─────────────────────────────────────────
    test('BRW-09-ALG-insertAfterCurrent (典型): ci 中间位置插入 Y 在 currentIndex+1',
        () {
      final queue = buildQueue(5, 2); // currentIndex=2 → 当前 track_03
      final y = testAudio('Y.mp3', '/music/Y.mp3');

      final newQueue = queue.insertAfterCurrent(y);

      // INV1: currentIndex 不变
      expect(newQueue.currentIndex, equals(2),
          reason: 'INV1: insertAfterCurrent 不改变 currentIndex');
      // 长度 +1
      expect(newQueue.length, equals(6), reason: '插入后队列长度应 +1');
      // 插入位置 = ci+1 = 3
      expect(newQueue.files[3].path, equals('/music/Y.mp3'),
          reason: 'ALG: Y 应插入到 currentIndex+1 位置');
      // 原位置元素相对顺序保持
      expect(newQueue.files[0].path, equals('/music/track_01.mp3'));
      expect(newQueue.files[1].path, equals('/music/track_02.mp3'));
      expect(newQueue.files[2].path, equals('/music/track_03.mp3'));
      expect(newQueue.files[4].path, equals('/music/track_04.mp3'),
          reason: '原 index 3 元素后移到 4');
      expect(newQueue.files[5].path, equals('/music/track_05.mp3'));
      // 当前曲目仍是原 X
      expect(newQueue.current.path, equals('/music/track_03.mp3'),
          reason: 'insertAfterCurrent 后当前曲目不变');
    });

    // ── ALG 边界：ci == N-1 队尾，插入位置 = files.length ─────────────────
    test('BRW-09-S8: ci == N-1 队尾时插入位置 = files.length', () {
      final queue = buildQueue(3, 2); // currentIndex 指向最后一个
      final y = testAudio('Y.mp3', '/music/Y.mp3');

      final newQueue = queue.insertAfterCurrent(y);

      expect(newQueue.currentIndex, equals(2),
          reason: 'INV1: 队尾插入仍不改变 currentIndex');
      expect(newQueue.length, equals(4));
      expect(newQueue.files[3].path, equals('/music/Y.mp3'),
          reason: 'S8: 队尾插入新元素位于原 files.length');
      expect(newQueue.files[0].path, equals('/music/track_01.mp3'));
      expect(newQueue.files[1].path, equals('/music/track_02.mp3'));
      expect(newQueue.files[2].path, equals('/music/track_03.mp3'));
      expect(newQueue.current.path, equals('/music/track_03.mp3'));
    });

    // ── ALG 异常：空队列（PlayQueue 是纯函数，不感知 playing 状态）
    // spec §6 异常"Q==null → orchestrator 返回 false"由 UI/orchestrator 层负责；
    // 纯 PlayQueue 本身不接收 null 队列。这里测"队列长度 0 时 insertAfterCurrent
    // 按 currentIndex+1=1 插入"——但 List.insert(1, file) 在长度 0 时会 RangeError。
    // 故选择解读：空队列本身不应被调用 insertAfterCurrent（由 UI 禁用），
    // 本测试仅断言"非空但 currentIndex=0 时插入到 index 1"作为最小化边界。
    test('BRW-09-ALG-insertAfterCurrent (边界): 单元素队列 ci=0 插入到 index 1', () {
      final queue = buildQueue(1, 0);
      final y = testAudio('Y.mp3', '/music/Y.mp3');

      final newQueue = queue.insertAfterCurrent(y);

      expect(newQueue.currentIndex, equals(0),
          reason: 'INV1: 单元素队列插入仍不改变 currentIndex');
      expect(newQueue.length, equals(2));
      expect(newQueue.files[1].path, equals('/music/Y.mp3'),
          reason: '单元素队列 ci=0 → 插入位置 1');
      expect(newQueue.current.path, equals('/music/track_01.mp3'));
    });

    // ── S3: shuffle 模式下仍按 files 顺序在 ci+1 插入 ────────────────────
    test('BRW-09-S3: shuffle 模式下 insertAfterCurrent 仍按 files 顺序插入', () {
      final queue = buildQueue(5, 2, mode: PlayMode.shuffle);
      final y = testAudio('Y.mp3', '/music/Y.mp3');

      final newQueue = queue.insertAfterCurrent(y);

      // INV2: playMode 不变；新队列按 files 索引在 ci+1 插入，与 shuffle 序列无关
      expect(newQueue.playMode, equals(PlayMode.shuffle),
          reason: 'INV2: insertAfterCurrent 不改变 playMode');
      expect(newQueue.currentIndex, equals(2));
      expect(newQueue.files[3].path, equals('/music/Y.mp3'),
          reason: 'S3: shuffle 模式下仍按 files 顺序在 currentIndex+1 插入 Y');
      // 行为性验证：插入后仍能正常执行 advanceShuffle（shuffle 数据有效）
      // _shuffleOrder 为私有字段，此处通过行为间接验证其未损坏：
      // 调用 advanceShuffle 不抛异常并返回新队列，间接表明 shuffle 序列未被打乱。
      expect(() => newQueue.advanceShuffle(), returnsNormally,
          reason: 'INV2 (行为): 插入后 advanceShuffle 应正常工作，shuffle 数据未损坏');
    });

    // ── INV1: 不改变 currentIndex 只改 files ─────────────────────────────
    test('BRW-09-INV1: insertAfterCurrent 不改变 currentIndex，只改 files', () {
      final queue = buildQueue(4, 1);
      final y = testAudio('Y.mp3', '/music/Y.mp3');

      final newQueue = queue.insertAfterCurrent(y);

      expect(newQueue.currentIndex, equals(1), reason: 'INV1: currentIndex 不变');
      expect(newQueue.length, equals(queue.length + 1),
          reason: 'INV1: files 列表变化（+1）');
      // 原队列不应被原地修改
      expect(queue.length, equals(4), reason: 'INV1: 原队列保持不变（不可变值语义）');
      expect(queue.currentIndex, equals(1));
    });

    // ── INV2: 不感知 playMode ────────────────────────────────────────────
    test('BRW-09-INV2: insertAfterCurrent 在 repeatAll/repeatOne 模式行为一致', () {
      final y = testAudio('Y.mp3', '/music/Y.mp3');

      for (final mode in [
        PlayMode.sequential,
        PlayMode.repeatAll,
        PlayMode.repeatOne,
        PlayMode.shuffle,
      ]) {
        final queue = buildQueue(4, 1, mode: mode);
        final newQueue = queue.insertAfterCurrent(y);

        expect(newQueue.currentIndex, equals(1),
            reason: 'INV2 ($mode): currentIndex 不变');
        expect(newQueue.files[2].path, equals('/music/Y.mp3'),
            reason: 'INV2 ($mode): Y 插入位置与 playMode 无关');
        expect(newQueue.playMode, equals(mode),
            reason: 'INV2 ($mode): playMode 保留');
        expect(newQueue.length, equals(5), reason: 'INV2 ($mode): 长度 +1 一致');
      }
    });

    // ── S5: 重复曲目不去重，原位不动 ─────────────────────────────────────
    test('BRW-09-S5: Y 与队列已有元素重复——不去重，原位不动', () {
      final queue = buildQueue(4, 1); // files: track_01..track_04
      // 取队列中已存在的 track_04 作为 Y
      final y = queue.files[3]; // track_04

      final newQueue = queue.insertAfterCurrent(y);

      expect(newQueue.length, equals(5), reason: 'S5: 队列长度 +1（不去重）');
      // INV3: 新副本插入 ci+1=2
      expect(newQueue.files[2].path, equals('/music/track_04.mp3'),
          reason: 'S5: 新副本插入到 currentIndex+1=2 位置');
      // 原位 track_04 仍在（现在 index 4）
      expect(newQueue.files[4].path, equals('/music/track_04.mp3'),
          reason: 'S5: 原位 Y 不动，仍保留在原位（已后移到 4）');
      // 出现两份 track_04
      final matches =
          newQueue.files.where((f) => f.path == '/music/track_04.mp3').length;
      expect(matches, equals(2), reason: 'S5: 队列中应有两份 Y 副本');
      // 校验原位元素位置相对顺序：原 track_04 副本现在位于 index 4（> 原本索引 3）
      expect(newQueue.files[4].path, equals('/music/track_04.mp3'),
          reason: 'S5: 原 track_04 副本位于 index 4（原位后移）');
    });

    // ── S6: Y 就是当前在播曲——下一曲再来一份 ────────────────────────────
    test('BRW-09-S6: 点击当前在播曲的"下一曲"图标——下一首再来一份当前曲', () {
      final queue = buildQueue(4, 1); // 当前 track_02
      final current = queue.current; // track_02

      final newQueue = queue.insertAfterCurrent(current);

      expect(newQueue.currentIndex, equals(1),
          reason: 'S6/INV1: currentIndex 不变仍指原 X');
      expect(newQueue.length, equals(5));
      // 新副本插入位置 ci+1=2 是同一首 X
      expect(newQueue.files[2].path, equals('/music/track_02.mp3'),
          reason: 'S6: 下一首位置插入 X 副本（X 将连播两遍）');
      expect(newQueue.current.path, equals('/music/track_02.mp3'),
          reason: 'S6: 当前仍是原 X');
      // 两份 track_02
      final count =
          newQueue.files.where((f) => f.path == '/music/track_02.mp3').length;
      expect(count, equals(2), reason: 'S6: 队列中存在两份 X 副本，不报错');
    });

    // ── S7: 连点同一首 Y 3 次 ────────────────────────────────────────────
    test('BRW-09-S7: 连续 insertAfterCurrent(Y) 三次，依次插入 ci+1..+3', () {
      final queue = buildQueue(4, 1); // 当前 track_02
      final y = testAudio('Y.mp3', '/music/Y.mp3');

      var q = queue;
      for (var i = 0; i < 3; i++) {
        q = q.insertAfterCurrent(y);
      }

      expect(q.currentIndex, equals(1),
          reason: 'S7/INV1: 多次插入 currentIndex 不变');
      expect(q.length, equals(7), reason: 'S7: 长度 4 + 3 = 7');
      // INV3: 每次插入到 ci+1 的当前位置 → 三份 Y 连续占据 index 2,3,4
      expect(q.files[2].path, equals('/music/Y.mp3'),
          reason: 'S7: 第 1 份 Y 在 index 2');
      expect(q.files[3].path, equals('/music/Y.mp3'),
          reason: 'S7: 第 2 份 Y 在 index 3');
      expect(q.files[4].path, equals('/music/Y.mp3'),
          reason: 'S7: 第 3 份 Y 在 index 4');
      // 原后续元素后移到 5,6
      expect(q.files[5].path, equals('/music/track_03.mp3'),
          reason: 'S7: 原 index 2 后移到 5');
      expect(q.files[6].path, equals('/music/track_04.mp3'),
          reason: 'S7: 原 index 3 后移到 6');
    });

    // ── INV3: 一次插入一次——不去重、不移动、不替换原位元素 ────────────────
    test('BRW-09-INV3: insertAfterCurrent 不替换原位元素，只插入', () {
      final queue = buildQueue(4, 1);
      final y = testAudio('Y.mp3', '/music/Y.mp3');

      final newQueue = queue.insertAfterCurrent(y);

      // 原位 4 个元素都应仍在（按相对顺序），新队列包含原 files 全部元素
      for (int i = 0; i < queue.files.length; i++) {
        final originalPath = queue.files[i].path;
        expect(newQueue.files.any((f) => f.path == originalPath), isTrue,
            reason: 'INV3: 原元素 $originalPath 仍在队列中（未被替换/移动消失）');
      }
      // 不去重已在 S5 测；不移动：原 ci 前的元素位置完全不变
      expect(newQueue.files[0].path, equals('/music/track_01.mp3'),
          reason: 'INV3: ci 之前的元素不动');
      expect(newQueue.files[1].path, equals('/music/track_02.mp3'),
          reason: 'INV3: 当前曲 X 不动');
    });

    // ── §7 PLY-REG-2: 含重复元素时 removeTrack(0) 只删第一个副本 ──────────
    test('BRW-09 PLY-REG-2: 队列含重复元素时 withoutIndex 只删第一个匹配即停', () {
      // 构造 [A, Y, Y, Y, B]，当前 ci=0（A）
      final files = [
        testAudio('A.mp3', '/music/A.mp3'),
        testAudio('Y.mp3', '/music/Y.mp3'),
        testAudio('Y.mp3', '/music/Y.mp3'),
        testAudio('Y.mp3', '/music/Y.mp3'),
        testAudio('B.mp3', '/music/B.mp3'),
      ];
      final queue = PlayQueue(files: files, currentIndex: 0);

      // 删除 index 1（第一个 Y）
      final removed = queue.withoutIndex(1);

      expect(removed.length, equals(4), reason: 'PLY-REG-2: 删一个元素长度 -1');
      expect(removed.files[0].path, equals('/music/A.mp3'));
      expect(removed.files[1].path, equals('/music/Y.mp3'),
          reason: 'PLY-REG-2: 第二个 Y 现在在 index 1（只删第一份）');
      expect(removed.files[2].path, equals('/music/Y.mp3'),
          reason: 'PLY-REG-2: 第三份 Y 仍在');
      expect(removed.files[3].path, equals('/music/B.mp3'));
      // 仍存在两份 Y
      final yCount =
          removed.files.where((f) => f.path == '/music/Y.mp3').length;
      expect(yCount, equals(2), reason: 'PLY-REG-2: 删除后仍保留 2 份 Y（只删第一个匹配即停）');
    });

    // ── §7 PLY-REG-3: 含插入副本的 queue toMap/fromMap 互通 ───────────────
    test('BRW-09 PLY-REG-3: 含重复副本的 queue toMap/fromMap 不丢重复元素', () {
      final base = buildQueue(3, 0); // [track_01, track_02, track_03]
      final y = testAudio('Y.mp3', '/music/Y.mp3');

      // 连续插入 2 份 Y → [track_01, Y, Y, track_02, track_03]
      final withDup = base.insertAfterCurrent(y).insertAfterCurrent(y);

      final map = withDup.toMap();
      expect(map['filePaths'], isA<List>());
      expect((map['filePaths'] as List).length, equals(5),
          reason: 'PLY-REG-3: 序列化保留 5 个路径（含重复）');

      final restored = PlayQueue.fromMap(map, withDup.files);

      expect(restored.length, equals(5), reason: 'PLY-REG-3: round-trip 长度一致');
      // 重复副本应被原样保留
      final yCount =
          restored.files.where((f) => f.path == '/music/Y.mp3').length;
      expect(yCount, equals(2), reason: 'PLY-REG-3: round-trip 后仍保留 2 份 Y');
      expect(restored.currentIndex, equals(0));
      // 顺序一致
      expect(restored.files[1].path, equals('/music/Y.mp3'));
      expect(restored.files[2].path, equals('/music/Y.mp3'));
      expect(restored.files[3].path, equals('/music/track_02.mp3'));
      expect(restored.files[4].path, equals('/music/track_03.mp3'));
    });
  });
}
