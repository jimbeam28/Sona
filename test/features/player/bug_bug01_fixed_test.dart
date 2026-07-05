// test/features/player/bug_bug01_fixed_test.dart
// BUG-01 §3.2 修复后行为 + §4 不变量测
// dev-exe: dev-plan §5.3 测试覆盖盲点 — S4/S5/S6 + INV1/INV2/INV3

import 'package:flutter_test/flutter_test.dart';
import 'package:nas_audio_player/shared/models/nas_file.dart';
import 'package:nas_audio_player/shared/models/play_queue.dart';
import 'package:nas_audio_player/features/player/domain/play_mode.dart';

NasFile _f(String name) => NasFile(
      name: name,
      path: '/music/$name',
      isDirectory: false,
      audioType: NasFile.classifyType(name),
    );

void main() {
  final files = [_f('a.mp3'), _f('b.mp3'), _f('c.mp3'), _f('d.mp3')];

  group('BUG-01 §3.2 修复后行为', () {
    test('BUG-01-S4: shuffle 字段纳入 == 比对——shuffleOrder 不同 → 不等', () {
      final q1 = PlayQueue(
        files: files,
        currentIndex: 0,
        playMode: PlayMode.shuffle,
        shuffleOrder: const [0, 3, 1, 2],
        shufflePosition: 0,
      );
      final q2 = PlayQueue(
        files: files,
        currentIndex: 0,
        playMode: PlayMode.shuffle,
        shuffleOrder: const [0, 1, 2, 3],
        shufflePosition: 0,
      );
      expect(q1 == q2, isFalse, reason: '否定断言: _shuffleOrder 须出现在 == 中');
    });

    test('BUG-01-S4: shuffle 字段纳入 == 比对——shufflePosition 不同 → 不等', () {
      final q1 = PlayQueue(
        files: files,
        currentIndex: 0,
        playMode: PlayMode.shuffle,
        shuffleOrder: const [0, 1, 2, 3],
        shufflePosition: 0,
      );
      final q2 = PlayQueue(
        files: files,
        currentIndex: 0,
        playMode: PlayMode.shuffle,
        shuffleOrder: const [0, 1, 2, 3],
        shufflePosition: 2,
      );
      expect(q1 == q2, isFalse, reason: '否定断言: _shufflePosition 须出现在 == 中');
    });

    test(
        'BUG-01-S4 非否定: shuffleOrder 与 shufflePosition 同为 null (非 shuffle 模式) 时仍按其它字段相等',
        () {
      final q1 = PlayQueue(
        files: files,
        currentIndex: 0,
        playMode: PlayMode.sequential,
      );
      final q2 = PlayQueue(
        files: files,
        currentIndex: 0,
        playMode: PlayMode.sequential,
      );
      expect(q1 == q2, isTrue,
          reason:
              '非 shuffle 模式下 shuffle 字段为 null，应按 files/currentIndex/... 判等');
    });

    test('BUG-01-S5: shuffle 字段进入 hashCode——shuffleOrder 不同 → hashCode 不同', () {
      final q1 = PlayQueue(
        files: files,
        currentIndex: 0,
        playMode: PlayMode.shuffle,
        shuffleOrder: const [0, 3, 1, 2],
        shufflePosition: 0,
      );
      final q2 = PlayQueue(
        files: files,
        currentIndex: 0,
        playMode: PlayMode.shuffle,
        shuffleOrder: const [0, 1, 2, 3],
        shufflePosition: 0,
      );
      expect(q1.hashCode == q2.hashCode, isFalse,
          reason: 'hashCode 须纳入 _shuffleOrder，避免 Set/Map 去重碰撞回归');
    });

    test('BUG-01-S5: shuffle 字段进入 hashCode——shufflePosition 不同 → hashCode 不同',
        () {
      final q1 = PlayQueue(
        files: files,
        currentIndex: 0,
        playMode: PlayMode.shuffle,
        shuffleOrder: const [0, 1, 2, 3],
        shufflePosition: 0,
      );
      final q2 = PlayQueue(
        files: files,
        currentIndex: 0,
        playMode: PlayMode.shuffle,
        shuffleOrder: const [0, 1, 2, 3],
        shufflePosition: 2,
      );
      expect(q1.hashCode == q2.hashCode, isFalse,
          reason: 'hashCode 须纳入 _shufflePosition');
    });

    test('BUG-01-S6: 非 shuffle 模式回归不变——shuffle 字段为 null 时仍相等', () {
      final q1 = PlayQueue(
        files: files,
        currentIndex: 1,
        startPositionMs: 30000,
        playMode: PlayMode.repeatAll,
      );
      final q2 = PlayQueue(
        files: files,
        currentIndex: 1,
        startPositionMs: 30000,
        playMode: PlayMode.repeatAll,
      );
      expect(q1 == q2, isTrue, reason: '历史行为应保持：非 shuffle 由其它字段判等');
      expect(q1.hashCode, equals(q2.hashCode), reason: '历史行为应保持：hashCode 一致');
    });

    test('BUG-01-S6 非否定: toMap/fromMap 仍能 round-trip 含 shuffle 的 queue', () {
      final q = PlayQueue(
        files: files,
        currentIndex: 0,
        playMode: PlayMode.shuffle,
        shuffleOrder: const [0, 3, 1, 2],
        shufflePosition: 2,
      );
      final m = q.toMap();
      final restored = PlayQueue.fromMap(m, files);
      expect(restored == q, isTrue, reason: 'round-trip 后 shuffle 字段一致，== 应判等');
      expect(restored.hashCode, equals(q.hashCode),
          reason: 'round-trip 后 hashCode 一致');
    });
  });

  group('BUG-01 §4 不变量', () {
    test('BUG-01-INV1: == 比较所有 final 字段（综合）', () {
      final base = PlayQueue(
        files: files,
        currentIndex: 0,
        playMode: PlayMode.shuffle,
        shuffleOrder: const [0, 1, 2, 3],
        shufflePosition: 0,
      );
      expect(base == base, isTrue);
      expect(
          base ==
              PlayQueue(
                files: [_f('a.mp3'), _f('b.mp3'), _f('c.mp3'), _f('x.mp3')],
                currentIndex: 0,
                playMode: PlayMode.shuffle,
                shuffleOrder: const [0, 1, 2, 3],
                shufflePosition: 0,
              ),
          isFalse,
          reason: 'files 不等 → 不等');
      expect(
          base ==
              PlayQueue(
                files: files,
                currentIndex: 1,
                playMode: PlayMode.shuffle,
                shuffleOrder: const [0, 1, 2, 3],
                shufflePosition: 0,
              ),
          isFalse,
          reason: 'currentIndex 不等 → 不等');
      expect(
          base ==
              PlayQueue(
                files: files,
                currentIndex: 0,
                startPositionMs: 1000,
                playMode: PlayMode.shuffle,
                shuffleOrder: const [0, 1, 2, 3],
                shufflePosition: 0,
              ),
          isFalse,
          reason: 'startPositionMs 不等 → 不等');
      expect(
          base ==
              PlayQueue(
                files: files,
                currentIndex: 0,
                playMode: PlayMode.repeatAll,
                shuffleOrder: const [0, 1, 2, 3],
                shufflePosition: 0,
              ),
          isFalse,
          reason: 'playMode 不等 → 不等');
      expect(
          base ==
              PlayQueue(
                files: files,
                currentIndex: 0,
                playMode: PlayMode.shuffle,
                shuffleOrder: const [0, 1, 3, 2],
                shufflePosition: 0,
              ),
          isFalse,
          reason: '_shuffleOrder 不等 → 不等');
      expect(
          base ==
              PlayQueue(
                files: files,
                currentIndex: 0,
                playMode: PlayMode.shuffle,
                shuffleOrder: const [0, 1, 2, 3],
                shufflePosition: 1,
              ),
          isFalse,
          reason: '_shufflePosition 不等 → 不等');
    });

    test('BUG-01-INV2: hashCode 与 == 同步覆盖所有 final 字段', () {
      final base = PlayQueue(
        files: files,
        currentIndex: 0,
        playMode: PlayMode.shuffle,
        shuffleOrder: const [0, 1, 2, 3],
        shufflePosition: 0,
      );
      final allEqual = PlayQueue(
        files: files,
        currentIndex: 0,
        playMode: PlayMode.shuffle,
        shuffleOrder: const [0, 1, 2, 3],
        shufflePosition: 0,
      );
      expect(base == allEqual, isTrue);
      expect(base.hashCode, equals(allEqual.hashCode),
          reason: '相等对象 hashCode 必相等（一致性）');

      final diffShuffle = PlayQueue(
        files: files,
        currentIndex: 0,
        playMode: PlayMode.shuffle,
        shuffleOrder: const [0, 3, 1, 2],
        shufflePosition: 0,
      );
      expect(base == diffShuffle, isFalse);
      expect(base.hashCode, isNot(equals(diffShuffle.hashCode)),
          reason: '不等对象 hashCode 应不同');
    });

    test('BUG-01-INV3: 非空 shuffle 字段相同时视为 shuffle 状态相同', () {
      final q1 = PlayQueue(
        files: files,
        currentIndex: 0,
        playMode: PlayMode.shuffle,
        shuffleOrder: const [3, 1, 0, 2],
        shufflePosition: 1,
      );
      final q2 = PlayQueue(
        files: files,
        currentIndex: 0,
        playMode: PlayMode.shuffle,
        shuffleOrder: const [3, 1, 0, 2],
        shufflePosition: 1,
      );
      expect(q1 == q2, isTrue,
          reason: 'INV3: shuffleOrder 与 shufflePosition 同值 → 状态相同');
      expect(q1.hashCode, equals(q2.hashCode));

      // advanceShuffle 推进后应不等于原始 queue（位置变化）
      final advanced = q1.advanceShuffle();
      expect(advanced, isNotNull);
      expect(advanced == q1, isFalse,
          reason: 'advanceShuffle 后 _shufflePosition 改变 → == 应判不等');
    });
  });
}
