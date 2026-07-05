// test/features/timer/bug_bug03_repro_test.dart
// BUG-03 (cr-B3): TimerService.resume() 用 (ms/60000).ceil() 精度损失
//
// 复现：startDuration(1) 后 elapsed 30s 暂停 → resume。bug 实现里：
//   minutes = (30000 / 60000).ceil() = 1
//   endTime = now + Duration(minutes: 1)   // 60s
// 多恢复 30 秒。修复后应：
//   endTime = now + Duration(milliseconds: 30000)  // 30s 剩余对齐
//
// 用 FakeAsync 控制 DateTime.now() 模拟时间流逝。修复前必须 FAIL；修复后必须 PASS。

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nas_audio_player/features/timer/domain/timer_service.dart';

void main() {
  test('bug_BUG-03: 暂停时剩余 30s → resume 应保留 30s 而非多 30s', () {
    FakeAsync().run((async) {
      final service = TimerService();
      service.startDuration(1); // 60s
      expect(service.state!.mode, equals(TimerMode.duration));

      // Advance real wall clock by 30s, leaving 30s remaining.
      async.elapse(const Duration(seconds: 30));

      // Capture remaining immediately, then pause.
      final beforePause = service.state!.remainingTime!;
      expect(beforePause.inMilliseconds, lessThanOrEqualTo(30000),
          reason: '60s - 30s = ~30s 剩余');
      expect(beforePause.inMilliseconds, greaterThan(25000),
          reason: '剩余应接近 30s（容忍小波动）');

      final paused = service.pause();
      expect(paused, isTrue);
      expect(service.state!.mode, equals(TimerMode.paused));
      final savedMs = service.state!.remainingMs!;
      expect(savedMs, lessThanOrEqualTo(30000));
      expect(savedMs, greaterThan(25000));

      // Resume immediately.
      final resumed = service.resume();
      expect(resumed, isTrue);
      expect(service.state!.mode, equals(TimerMode.duration));
      expect(service.state!.endTime, isNotNull);

      // Advance zero — bug manifests as endTime being ~60s away from
      // now (1 min) instead of remaining ~30s.
      async.elapse(Duration.zero);
      final afterResume = service.state!.remainingTime!;

      // 修复后应保留 ~30s；bug 下会恢复为 ~60s。
      expect(
        afterResume.inMilliseconds,
        lessThan(45000),
        reason: 'resume 后剩余应保留原 remainingMs（~30s），'
            '若用 (ms/60000).ceil() 转 minutes，会把 30s 变成 60s',
      );
    });
  });

  test('bug_BUG-03: 多次 pause/resume 循环不应累积剩余时间', () {
    FakeAsync().run((async) {
      final service = TimerService();
      service.startDuration(1); // 60s
      async.elapse(const Duration(seconds: 30));

      // 暂停 → 立即恢复
      service.pause();
      service.resume();

      // 假时间继续走 25 秒
      async.elapse(const Duration(seconds: 25));

      // 再暂停 → 再恢复
      service.pause();
      service.resume();

      // 此时原来的 60s 应已用去 55s，剩 ~5s
      // bug 下每次恢复都 ceil 到下一分钟，剩余时间会越累越多。
      async.elapse(Duration.zero);
      final remaining = service.state!.remainingTime!;
      expect(
        remaining.inMilliseconds,
        lessThan(20000),
        reason: '60s 总时长用了 55s，剩 ~5s；'
            '若每次 resume 都 ceil 到 1 分钟，剩余会被回退到 60s',
      );
    });
  });
}
