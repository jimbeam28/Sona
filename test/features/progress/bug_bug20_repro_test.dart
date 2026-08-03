// test/features/progress/bug_bug20_repro_test.dart
// BUG-20 门禁测试（spec docs/features/BUG-20.md §5.4 指定文件）。
//
// 锚定 cr-2026-06-28 FRAGILE-06 / cr-20260724-0110 PRG6（同根因）：
// 修复前 shouldClear 使用固定 10000ms 清除窗口，durationMs=12000 时阈值
// 12000-10000=2000，任何过 shouldSave 门槛（>=5000ms）的位置必然同时
// shouldClear=true → 10s < duration <= 15s 的文件进度保存后立即被清除，
// 永远存不下进度。修复改为动态窗口：
//   window = clamp(ceil(durationMs * 0.1), 1000, 10000)
//   shouldClear = positionMs > durationMs - window
// G-3 保护（durationMs <= 10000 → false）不变，长文件窗口封顶 10000ms
// 向后兼容。
//
// 双态门禁：修复前（固定窗口）BUG-20-S1 / INV1 用例 FAIL，修复后 PASS。

import 'package:flutter_test/flutter_test.dart';
import 'package:nas_audio_player/core/database/dao/progress_dao.dart';
import 'package:nas_audio_player/features/progress/domain/progress_policy.dart'
    as policy;

void main() {
  // ═══════════════════════════════════════════════════════════════════════════
  // BUG-20-S1: shouldClear 阈值与 shouldSave 不冲突
  // ═══════════════════════════════════════════════════════════════════════════

  group('BUG-20-S1: shouldClear 阈值与 shouldSave 不冲突', () {
    test('U1/U2 核心场景：durationMs=12000, positionMs=6000 → 保存且不清除', () {
      // spec §3.1 Given/When/Then：12s 文件播放到 6s 退出，进度必须能存下。
      expect(policy.shouldSave(6000), isTrue,
          reason: 'BUG-20-S1: 6000 >= 5000 → 应触发保存');
      expect(policy.shouldClear(6000, 12000), isFalse,
          reason: 'BUG-20-S1: 修复前 6000 > 12000-10000=2000 → true，'
              '保存后立即被清除；修复后 window=1200, 6000 <= 10800 → false');
    });

    test('positionMs=5000（保存门槛）处 12s 文件不清除', () {
      // spec §6 ALG1：positionMs=5000, durationMs=12000 → shouldSave=true,
      // shouldClear=false → 保存成功。修复前 5000 > 2000 → true（断崖）。
      expect(policy.shouldSave(5000), isTrue);
      expect(policy.shouldClear(5000, 12000), isFalse);
    });

    test('否定断言：10-15s 全范围保存窗口闭合，无断崖', () {
      // 10s < duration <= 15s 的每一个时长，[5000, duration-window] 保存
      // 窗口必须非空：保存门槛 5000 处一律不得清除（修复前 duration=10001
      // 时阈值=1，>=2ms 即清除 → 窗口被完全吞掉）。
      for (var durationMs = 10001; durationMs <= 15000; durationMs += 97) {
        expect(policy.shouldSave(5000), isTrue);
        expect(policy.shouldClear(5000, durationMs), isFalse,
            reason: 'BUG-20-S1: durationMs=$durationMs 在保存门槛 5000 处'
                '不得清除（修复前断崖）');
      }
    });

    test('否定断言：durationMs=600000 清除窗口仍为 10000ms（向后兼容）', () {
      // spec §3.1 否定断言：不改变 >30s 长文件行为。window=clamp(60000,
      // 1000, 10000)=10000 → 阈值 590000，与修复前完全一致。
      expect(policy.shouldClear(590000, 600000), isFalse,
          reason: 'BUG-20-S1: 590000 == 600000-10000 → 边界不清除');
      expect(policy.shouldClear(590001, 600000), isTrue,
          reason: 'BUG-20-S1: 590001 > 590000 → 清除');
    });

    test('否定断言：durationMs <= 10000 的 G-3 保护不变', () {
      // spec §3.1 否定断言：<=10s 文件 shouldClear 始终 false。
      expect(policy.shouldClear(9999, 10000), isFalse);
      expect(policy.shouldClear(10000, 10000), isFalse);
      expect(policy.shouldClear(5000, 5000), isFalse);
      expect(policy.shouldClear(9998, 9999), isFalse);
      expect(policy.shouldClear(0, 0), isFalse);
      expect(policy.shouldClear(999999, null), isFalse,
          reason: 'BUG-20-S1: null duration 保护同样不变');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // BUG-20-INV1: shouldSave 与 shouldClear 无矛盾重叠（保存窗口内不共存）
  // ═══════════════════════════════════════════════════════════════════════════

  group('BUG-20-INV1: 保存窗口内 shouldSave 与 shouldClear 不共存', () {
    test('durationMs=12000: [5000, 10800] 全段保存窗口内不得清除', () {
      // window=1200 → 阈值 10800。保存窗口 [5000, 10800] 内逐点扫描：
      // shouldSave=true 且 shouldClear=false（修复前 5000..12000 全段
      // shouldClear=true，窗口空集）。
      for (var positionMs = 5000; positionMs <= 10800; positionMs += 50) {
        expect(policy.shouldSave(positionMs), isTrue);
        expect(policy.shouldClear(positionMs, 12000), isFalse,
            reason: 'BUG-20-INV1: positionMs=$positionMs 在保存窗口内'
                '不得同时清除');
      }
    });

    test('durationMs=10001: [5000, 9000] 保存窗口内不得清除', () {
      // window=ceil(10001*0.1)=1001 → 阈值 9000（spec §3.1 边界裁决）。
      for (var positionMs = 5000; positionMs <= 9000; positionMs += 50) {
        expect(policy.shouldClear(positionMs, 10001), isFalse,
            reason: 'BUG-20-INV1: positionMs=$positionMs, durationMs=10001');
      }
    });

    test('durationMs=15000: [5000, 13500] 保存窗口内不得清除', () {
      // window=1500 → 阈值 13500（spec §3.1 边界裁决）。
      for (var positionMs = 5000; positionMs <= 13500; positionMs += 50) {
        expect(policy.shouldClear(positionMs, 15000), isFalse,
            reason: 'BUG-20-INV1: positionMs=$positionMs, durationMs=15000');
      }
    });

    test('清除只发生在近尾窗口（position > duration-window），无悬空态', () {
      // shouldClear=true 必然蕴含 shouldSave=true（阈值 > 5000）：不存在
      // "既不该存又不该清"之外的悬空位置；近尾清除区由 DAO clear-wins
      // 裁决（听完即清，语义不变）。
      // durationMs=12000 → 尾窗 (10800, 12000]。
      expect(policy.shouldClear(10801, 12000), isTrue);
      expect(policy.shouldSave(10801), isTrue);
      expect(policy.shouldClear(12000, 12000), isTrue);
      // durationMs=10001 → 尾窗 (9000, 10001]。
      expect(policy.shouldClear(9001, 10001), isTrue);
      expect(policy.shouldClear(9000, 10001), isFalse);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // BUG-20-INV2: <=10s 文件行为不变（G-3 保护回归）
  // ═══════════════════════════════════════════════════════════════════════════

  group('BUG-20-INV2: <=10s 文件行为不变', () {
    test('durationMs=10000 边界：任意位置（含贴尾/等于时长）均不清除', () {
      expect(policy.shouldClear(0, 10000), isFalse);
      expect(policy.shouldClear(5000, 10000), isFalse);
      expect(policy.shouldClear(9999, 10000), isFalse);
      expect(policy.shouldClear(10000, 10000), isFalse);
    });

    test('durationMs=5000/8000：近尾位置也不清除', () {
      expect(policy.shouldClear(4999, 5000), isFalse);
      expect(policy.shouldClear(5000, 5000), isFalse);
      expect(policy.shouldClear(7999, 8000), isFalse);
      expect(policy.shouldClear(8000, 8000), isFalse);
    });

    test('shouldSave 门槛不受 BUG-20 修复影响', () {
      expect(policy.shouldSave(4999), isFalse);
      expect(policy.shouldSave(5000), isTrue);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // BUG-20-ALG1: spec §6 算法样例逐条
  // ═══════════════════════════════════════════════════════════════════════════

  group('BUG-20-ALG1: spec §6 算法样例', () {
    test('(6000, 12000) → false（window=1200, 6000 > 10800? No）', () {
      expect(policy.shouldClear(6000, 12000), isFalse);
    });

    test('(11000, 12000) → true（window=1200, 11000 > 10800? Yes）', () {
      expect(policy.shouldClear(11000, 12000), isTrue);
    });

    test('(590000, 600000) → false；(590001, 600000) → true（window=10000）', () {
      expect(policy.shouldClear(590000, 600000), isFalse);
      expect(policy.shouldClear(590001, 600000), isTrue);
    });

    test('(9000, 10000) → false（G-3 保护，durationMs <= 10000）', () {
      expect(policy.shouldClear(9000, 10000), isFalse);
    });

    test('(9000, 10001) → false（window=1001, 9000 > 9000? No）', () {
      expect(policy.shouldClear(9000, 10001), isFalse);
    });

    test('(9001, 10001) → true（window=1001, 9001 > 9000? Yes）', () {
      expect(policy.shouldClear(9001, 10001), isTrue);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // spec §3.1 边界裁决：动态窗口公式逐档
  // ═══════════════════════════════════════════════════════════════════════════

  group('spec §3.1 边界裁决：window = clamp(ceil(d*0.1), 1000, 10000)', () {
    test('durationMs=50000 → window=5000，clear 阈值 45000', () {
      expect(policy.shouldClear(45000, 50000), isFalse);
      expect(policy.shouldClear(45001, 50000), isTrue);
    });

    test('durationMs=60000 → window=6000，clear 阈值 54000', () {
      expect(policy.shouldClear(54000, 60000), isFalse);
      expect(policy.shouldClear(54001, 60000), isTrue);
    });

    test('durationMs=100000 起窗口封顶 10000（与修复前一致）', () {
      expect(policy.shouldClear(90000, 100000), isFalse);
      expect(policy.shouldClear(90001, 100000), isTrue);
    });

    test('durationMs=11000 → window=1100，clear 阈值 9900', () {
      expect(policy.shouldClear(9900, 11000), isFalse);
      expect(policy.shouldClear(9901, 11000), isTrue);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // spec §7 跨模块影响：DAO 静态委托与 policy 一致
  // ═══════════════════════════════════════════════════════════════════════════

  group('spec §7: ProgressDao.shouldClear/shouldSave 委托一致', () {
    test('DAO 委托路径对 BUG-20 关键值与 policy 同判', () {
      // ProgressDao.upsert 经静态委托调用 policy（progress_dao.dart:172-178），
      // 生产保存链路 saveProgress → upsert → shouldClear 与 policy 一致。
      expect(ProgressDao.shouldSave(6000), policy.shouldSave(6000));
      for (final (positionMs, durationMs) in [
        (6000, 12000), // U2 场景：保存不清除
        (5000, 10001), // 保存门槛 + 最短断崖时长
        (10801, 12000), // 近尾清除
        (590001, 600000), // 长文件向后兼容
        (9999, 10000), // G-3 边界
      ]) {
        expect(ProgressDao.shouldClear(positionMs, durationMs),
            policy.shouldClear(positionMs, durationMs),
            reason: 'DAO 委托偏离 policy: ($positionMs, $durationMs)');
      }
      expect(ProgressDao.shouldClear(6000, 12000), isFalse);
    });
  });
}
