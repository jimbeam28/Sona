// test/features/player/bug_bug01_repro_test.dart
// BUG-01 (cr-B1): PlayQueue.== / hashCode 漏比 _shuffleOrder / _shufflePosition
//
// 复现：两个 PlayQueue 仅 shuffle 序列不同时被 == 视为相等。
// 这会导致 Riverpod StateProvider 通过 == 判定无变化，listener 不通知，
// UI 无法重建。修复前必须 FAIL；修复后必须 PASS。

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
  test('bug_BUG-01: shuffle 序列不同的 PlayQueue 应判为不等', () {
    final files = [_f('a.mp3'), _f('b.mp3'), _f('c.mp3'), _f('d.mp3')];

    // 显式构造两个不同的 shuffle 序列 —— Fisher-Yates 同种子会得到相同序列，
    // 这里强制覆盖 _shuffleOrder / _shufflePosition 取不同值。
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

    expect(q1 == q2, isFalse,
        reason: '若 == 漏比 shuffle 字段，两个不同序列将被判为相等 → '
            'Riverpod listener 不通知，shuffle 顺序切换时 UI 不重建');
  });

  test('bug_BUG-01: shufflePosition 不同的 PlayQueue 应判为不等', () {
    final files = [_f('a.mp3'), _f('b.mp3'), _f('c.mp3'), _f('d.mp3')];
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
      shuffleOrder: const [0, 3, 1, 2],
      shufflePosition: 2,
    );

    expect(q1 == q2, isFalse,
        reason: 'shufflePosition 不同代表当前在 shuffle 序列中的不同位置，'
            '应判为不等');
  });

  test('bug_BUG-01: shuffle 序列不同的 hashCode 应不同', () {
    final files = [_f('a.mp3'), _f('b.mp3'), _f('c.mp3'), _f('d.mp3')];
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
        reason: 'hashCode 若不纳入 shuffle 字段，相同 hashCode 容易碰撞，'
            'Set/Map 中的去重依赖 hashCode');
  });
}
