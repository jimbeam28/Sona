// test/features/timer/bug_bug03_fixed_test.dart
// BUG-03 §3.2 修复后行为 + §4 不变量 + §6 算法样例
// 用 TimerService 的 now 注入模拟时间流逝

import 'package:flutter_test/flutter_test.dart';
import 'package:nas_audio_player/features/timer/domain/timer_service.dart';

void main() {
  DateTime fakeNow = DateTime(2026, 1, 1, 0, 0, 0);

  DateTime now() => fakeNow;
  void elapse(Duration d) => fakeNow = fakeNow.add(d);
  void reset() => fakeNow = DateTime(2026, 1, 1, 0, 0, 0);

  setUp(reset);

  group('BUG-03 §3.2 修复后行为', () {
    test('BUG-03-S3: resume 直接以 remainingMs 毫秒精度算 endTime', () {
      reset();
      final service = TimerService(now: now);
      service.startDuration(1); // 60s
      elapse(const Duration(seconds: 30));
      service.pause();
      final res = service.resume();
      expect(res, isTrue);
      final remaining = service.state!.remainingTime!;
      expect(remaining.inMilliseconds, equals(30000),
          reason: 'INV1: resume 后 endTime-now == saved remainingMs');
    });

    test('BUG-03-S3 否定: 不调用 startDuration / 不重新创建 timer', () {
      reset();
      final service = TimerService(now: now);
      service.startDuration(1);
      elapse(const Duration(seconds: 30));
      service.pause();
      final startedAtBefore = service.state!.startedAt;
      service.resume();
      expect(service.state!.startedAt, equals(startedAtBefore),
          reason: '否定: resume 不应改变 startedAt');
      expect(service.state!.mode, equals(TimerMode.duration),
          reason: '否定: 直接 paused → duration 切换，不经过 startDuration');
    });

    test('BUG-03-S4: 多次 pause/resume 不累积误差', () {
      reset();
      final service = TimerService(now: now);
      service.startDuration(1);
      elapse(const Duration(seconds: 30));
      service.pause();
      service.resume();
      elapse(const Duration(seconds: 25));
      service.pause();
      service.resume();
      final remaining = service.state!.remainingTime!;
      expect(remaining.inMilliseconds, equals(5000),
          reason: 'S4: 60s 用 55s 剩 5s');
    });

    test('BUG-03-S4 否定: 剩余不应超过原始 duration', () {
      reset();
      final service = TimerService(now: now);
      service.startDuration(1);
      elapse(const Duration(seconds: 20));
      // pause-resume 5 次
      for (var i = 0; i < 5; i++) {
        service.pause();
        service.resume();
      }
      final remaining = service.state!.remainingTime!;
      expect(remaining.inMilliseconds, lessThanOrEqualTo(40000),
          reason: '否定: 5 次 pause/resume 不应使用时长缩水或增长');
    });

    test('BUG-03-S5: mode==duration 时 resume 返回 false 不影响 state', () {
      reset();
      final service = TimerService(now: now);
      service.startDuration(1);
      final beforeMode = service.state!.mode;
      final beforeEndTime = service.state!.endTime;
      final beforeStartedAt = service.state!.startedAt;
      final res = service.resume();
      expect(res, isFalse, reason: 'S5: 非 paused → false');
      expect(service.state!.mode, equals(beforeMode), reason: '否定: 不重新计算 mode');
      expect(service.state!.endTime, equals(beforeEndTime),
          reason: '否定: 不重新计算 endTime');
      expect(service.state!.startedAt, equals(beforeStartedAt),
          reason: '否定: 不清理 startedAt');
    });

    test('BUG-03-S5: afterCurrent 模式 resume 也返回 false', () {
      reset();
      final service = TimerService(now: now);
      service.startAfterCurrent();
      final beforeState = service.state;
      final res = service.resume();
      expect(res, isFalse);
      expect(service.state, equals(beforeState),
          reason: 'afterCurrent 不受 resume 影响');
    });
  });

  group('BUG-03 §4 不变量', () {
    test('BUG-03-INV1: resume 后 endTime - now == saved remainingMs (±1ms)', () {
      reset();
      final service = TimerService(now: now);
      service.startDuration(2);
      elapse(const Duration(seconds: 47, milliseconds: 350));
      service.pause();
      final savedMs = service.state!.remainingMs!;
      service.resume();
      final remaining = service.state!.remainingTime!;
      expect((remaining.inMilliseconds - savedMs).abs(), lessThanOrEqualTo(1),
          reason: 'INV1: 误差 <= 1ms');
    });

    test('BUG-03-INV2: 累计时长守恒，startedAt 不依赖 pause 次数', () {
      reset();
      final service = TimerService(now: now);
      service.startDuration(1);
      elapse(const Duration(seconds: 10));
      service.pause();
      service.resume();
      elapse(const Duration(seconds: 15));
      service.pause();
      service.resume();
      elapse(const Duration(seconds: 20));
      // 用了 45s，还剩 15s
      final remaining = service.state!.remainingTime!;
      expect(remaining.inMilliseconds, equals(15000),
          reason: 'INV2: pause/resume 不累积，依 wall clock 计时');
    });

    test('BUG-03-INV3: resume 在非 paused 模式下 no-op', () {
      reset();
      final service = TimerService(now: now);
      // idle
      expect(service.resume(), isFalse, reason: 'INV3: idle → no-op');
      // duration
      service.startDuration(1);
      expect(service.resume(), isFalse, reason: 'INV3: duration → no-op');
      // afterCurrent
      service.startAfterCurrent();
      expect(service.resume(), isFalse, reason: 'INV3: afterCurrent → no-op');
    });
  });

  group('BUG-03 §6 算法样例', () {
    test('ALG remainingMs=30000 → endTime = now + 30s', () {
      reset();
      final service = TimerService(now: now);
      service.startDuration(1);
      elapse(const Duration(seconds: 30));
      service.pause();
      expect(service.state!.remainingMs, equals(30000));
      service.resume();
      expect(service.state!.remainingTime!.inMilliseconds, equals(30000));
    });

    test('ALG remainingMs=1 → endTime = now + 1ms', () {
      reset();
      final service = TimerService(now: now);
      service.startDuration(1);
      final elapsed = Duration(minutes: 1) - const Duration(milliseconds: 1);
      elapse(elapsed);
      service.pause();
      expect(service.state!.remainingMs, equals(1));
      // 快进 1ms 不必要，直接 resume 测
      service.resume();
      expect(service.state!.remainingTime!.inMilliseconds, equals(1),
          reason: 'ALG: 1ms 边界');
    });

    test('ALG remainingMs=60000 → endTime = now + 60s', () {
      reset();
      final service = TimerService(now: now);
      service.startDuration(1);
      // 立即 pause 触发 remainingMs ~= 60000
      service.pause();
      service.resume();
      expect(service.state!.remainingTime!.inMilliseconds, equals(60000));
    });

    test('ALG remainingMs=60001 → 毫秒级精度保留', () {
      reset();
      final service = TimerService(now: now);
      service.startDuration(2); // 120000ms
      // 走 59999 ms → 剩 120000 - 59999 = 60001 ms
      elapse(const Duration(seconds: 59, milliseconds: 999));
      service.pause();
      expect(service.state!.remainingMs, equals(60001),
          reason: '当前 remainingMs = 120000 - 59999 = 60001');
      service.resume();
      // bug 实现会把 60001ms ceil 到 120000ms（2 分钟），修复后应保留 60001ms
      expect(service.state!.remainingTime!.inMilliseconds, equals(60001),
          reason: 'ALG: 60001ms 不再被丢到 120s');
    });

    test('ALG remainingMs=0 → endTime = now + 0ms 立即过期', () {
      reset();
      final service = TimerService(now: now);
      service.startDuration(1);
      elapse(const Duration(minutes: 1));
      service.pause();
      expect(service.state!.remainingMs, equals(0));
      service.resume();
      expect(service.state!.remainingTime!.inMilliseconds, equals(0),
          reason: 'ALG: 0ms → 立即过期');
      expect(service.state!.isExpired, isTrue);
    });

    test('ALG state != paused → false, state 不变', () {
      reset();
      final service = TimerService(now: now);
      service.startDuration(1);
      final before = service.state;
      expect(service.resume(), isFalse);
      expect(identical(service.state, before), isTrue);
    });
  });
}
