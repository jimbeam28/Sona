import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:nas_audio_player/features/timer/domain/fade_policy.dart';
import 'package:nas_audio_player/features/timer/domain/timer_service.dart';
import 'package:nas_audio_player/shared/di/providers.dart';

import '../../helpers/mock_audio_player.dart';
import '../../helpers/widget_helpers.dart';

DateTime _fakeNow = DateTime(2026, 8, 23, 12);

DateTime _now() => _fakeNow;

void _resetClock() => _fakeNow = DateTime(2026, 8, 23, 12);

void _advance(Duration d) => _fakeNow = _fakeNow.add(d);

class _InjectableTimerNotifier extends TimerStateNotifier {
  void inject(TimerState? timerState) => state = timerState;
}

class _FadeProbePlayer extends MockAudioPlayer {
  final List<double> writtenVolumes = <double>[];

  void arm() {
    for (final v in const [0.0, 0.5, 1.0]) {
      when(setVolume(v)).thenAnswer((_) async {
        writtenVolumes.add(v);
      });
    }
  }
}

_FadeProbePlayer _player = _FadeProbePlayer();

_InjectableTimerNotifier _notifierOf(ProviderContainer container) =>
    container.read(timerStateProvider.notifier) as _InjectableTimerNotifier;

ProviderContainer _fadeContainer() {
  return ProviderContainer(
    overrides: [
      timerStateProvider.overrideWith(_InjectableTimerNotifier.new),
      timerServiceProvider.overrideWithValue(TimerService(now: _now)),
      audioPlayerProvider.overrideWith((ref) => _player),
      ...noopRemainingTimeOverride(),
    ],
  );
}

Future<void> _tick(ProviderContainer container) =>
    container.read(timerTickWithFadeProvider)();

Future<void> _driveToFading(ProviderContainer container) async {
  container.read(startDurationTimerProvider)(1);
  _advance(const Duration(seconds: 55));
  await _tick(container);
}

List<String> _libFilesContaining(String needle) {
  final hits = <String>[];
  for (final entity in Directory('lib').listSync(recursive: true)) {
    if (entity is File &&
        entity.path.endsWith('.dart') &&
        entity.readAsStringSync().contains(needle)) {
      hits.add(entity.path.replaceAll('\\', '/'));
    }
  }
  return hits;
}

void main() {
  setUp(() {
    _resetClock();
    _player = _FadeProbePlayer();
    _player.arm();
  });

  group('TMR-01-S1: 契约扩展 IAudioPlayer.setVolume', () {
    test('TMR-01-S1: setVolume 可经 mock 显式 stub 并 verify', () async {
      final player = MockAudioPlayer();
      when(player.setVolume(0.5)).thenAnswer((_) async {});
      await player.setVolume(0.5);
      verify(player.setVolume(0.5)).called(1);
    });

    test('TMR-01-S1 否定: 未显式 stub 时走 returnValueForMissingStub 兜底不抛错', () async {
      final player = MockAudioPlayer();
      await player.setVolume(0.25);
      verify(player.setVolume(0.25)).called(1);
    });
  });

  group('TMR-01-S2: 淡出曲线', () {
    test('TMR-01-S2: 窗口内线性衰减、窗口上沿与窗口外恒 1.0、归零点 0.0', () {
      expect(fadeVolumeForRemaining(const Duration(seconds: 9)),
          closeTo(0.9, 0.0001));
      expect(fadeVolumeForRemaining(const Duration(seconds: 5)), 0.5);
      expect(fadeVolumeForRemaining(const Duration(seconds: 1)),
          closeTo(0.1, 0.0001));
      expect(fadeVolumeForRemaining(const Duration(milliseconds: 250)),
          closeTo(0.025, 0.0001),
          reason: '毫秒级线性插值');
      expect(fadeVolumeForRemaining(kTimerFadeWindow), 1.0,
          reason: '恰在窗口上沿仍视为未进入淡出');
      expect(fadeVolumeForRemaining(const Duration(minutes: 30)), 1.0);
      expect(fadeVolumeForRemaining(Duration.zero), 0.0);
      expect(fadeVolumeForRemaining(null), 1.0);
    });
  });

  group('TMR-01-ALG1: fadeVolumeForRemaining 黄金表', () {
    test('TMR-01-ALG1: §6 黄金表逐行', () {
      expect(fadeVolumeForRemaining(null), 1.0);
      expect(fadeVolumeForRemaining(const Duration(minutes: 10)), 1.0);
      expect(fadeVolumeForRemaining(kTimerFadeWindow), 1.0,
          reason: '恰 10s 边界：仍视为未进入淡出');
      expect(fadeVolumeForRemaining(const Duration(seconds: 5)), 0.5);
      expect(fadeVolumeForRemaining(const Duration(seconds: 1)),
          closeTo(0.1, 0.0001));
      expect(fadeVolumeForRemaining(const Duration(milliseconds: 500)),
          closeTo(0.05, 0.0001));
      expect(fadeVolumeForRemaining(Duration.zero), 0.0);
      expect(fadeVolumeForRemaining(const Duration(milliseconds: -1)), 0.0);
    });

    test('TMR-01-ALG1 性质: 输出恒在 [0,1] 区间且 >10s 与 null 同为恰好 1.0', () {
      final inputs = [
        null,
        const Duration(hours: -1),
        const Duration(milliseconds: -1),
        Duration.zero,
        const Duration(milliseconds: 1),
        const Duration(milliseconds: 500),
        const Duration(seconds: 1),
        const Duration(seconds: 5),
        const Duration(milliseconds: 9999),
        kTimerFadeWindow,
        const Duration(milliseconds: 10001),
        const Duration(seconds: 11),
        const Duration(minutes: 1),
        const Duration(minutes: 10),
      ];
      for (final d in inputs) {
        final v = fadeVolumeForRemaining(d);
        expect(v, inInclusiveRange(0.0, 1.0), reason: '输入 $d 输出 $v 越界');
      }
      expect(fadeVolumeForRemaining(const Duration(seconds: 11)), 1.0,
          reason: 'remaining > 10s 与 null 同样返回恰好 1.0');
      expect(fadeVolumeForRemaining(null), 1.0);
      expect(fadeVolumeForRemaining(const Duration(milliseconds: -60000)), 0.0,
          reason: '深度过期钳到 0.0 不产生负数');
    });
  });

  group('TMR-01-S3: 到期单 tick 静默停止', () {
    test(
        'TMR-01-S3: 到期单 tick 依次 setVolume(0.0)→pause→setVolume(1.0)，'
        '后续 tick 无任何新调用且不 stop()', () async {
      final container = _fadeContainer();
      addTearDown(container.dispose);

      await _driveToFading(container);
      expect(_player.writtenVolumes, [0.5]);
      verify(_player.setVolume(0.5)).called(1);

      _advance(const Duration(seconds: 5));
      await _tick(container);

      verifyInOrder([
        _player.setVolume(0.0),
        _player.pause(),
        _player.setVolume(1.0),
      ]);
      expect(_player.writtenVolumes, [0.5, 0.0, 1.0]);
      expect(container.read(timerStateProvider), isNull, reason: '到期后定时器状态被清空');
      verifyNever(_player.stop());

      await _tick(container);
      verifyNoMoreInteractions(_player);
    });
  });

  group('TMR-01-S4: 窗口外零副作用', () {
    test('TMR-01-S4: 定时器未激活（state 为 null）时 tick 零副作用', () async {
      final container = _fadeContainer();
      addTearDown(container.dispose);

      expect(container.read(timerStateProvider), isNull);
      await _tick(container);
      verifyZeroInteractions(_player);
    });

    test('TMR-01-S4: afterCurrent 模式下 tick 零副作用', () async {
      final container = _fadeContainer();
      addTearDown(container.dispose);

      container.read(startAfterCurrentProvider)();
      expect(container.read(timerStateProvider)!.mode, TimerMode.afterCurrent);
      await _tick(container);
      await _tick(container);
      verifyZeroInteractions(_player);
      expect(container.read(timerStateProvider)!.mode, TimerMode.afterCurrent,
          reason: 'afterCurrent 状态不被 duration 型 tick 误清');
    });

    test('TMR-01-S4: duration 剩余 >10s 时 tick 零副作用且不清态', () async {
      final container = _fadeContainer();
      addTearDown(container.dispose);

      container.read(startDurationTimerProvider)(1);
      await _tick(container);
      verifyZeroInteractions(_player);
      expect(container.read(timerStateProvider), isNotNull,
          reason: '未到期 tick 不得清除定时器状态');
      expect(container.read(timerStateProvider)!.mode, TimerMode.duration);
    });
  });

  group('TMR-01-S5: 打断后的收敛恢复', () {
    test('TMR-01-S5: 淡出写到中间值后取消定时器，下一 tick 写回 setVolume(1.0) 此后稳态零副作用',
        () async {
      final container = _fadeContainer();
      addTearDown(container.dispose);

      await _driveToFading(container);
      expect(_player.writtenVolumes, [0.5]);
      verify(_player.setVolume(0.5)).called(1);

      container.read(cancelTimerProvider)();
      expect(container.read(timerStateProvider), isNull);

      await _tick(container);
      expect(_player.writtenVolumes, [0.5, 1.0]);
      verify(_player.setVolume(1.0)).called(1);
      verifyNever(_player.pause());

      await _tick(container);
      expect(_player.writtenVolumes, hasLength(2),
          reason: '稳态 tick 不再产生新的音量写入');
      verifyNoMoreInteractions(_player);
    });
  });

  group('TMR-01-S6: 四驱动点统一换线与幂等', () {
    test('TMR-01-S6: 同一容器连续两次到期 tick，pause 恰好执行 1 次（幂等闸）', () async {
      final container = _fadeContainer();
      addTearDown(container.dispose);

      container.read(startDurationTimerProvider)(1);
      _advance(const Duration(minutes: 1));

      await _tick(container);
      await _tick(container);

      verify(_player.pause()).called(1);
      verify(_player.setVolume(0.0)).called(1);
      verify(_player.setVolume(1.0)).called(1);
      verifyNoMoreInteractions(_player);
    });

    test(
        'TMR-01-S6: home/player 两屏源码均接线 timerTickWithFadeProvider 且 '
        'checkTimerExpiryProvider 生产调用点归零', () {
      final home =
          File('lib/features/home/home_screen.dart').readAsStringSync();
      final playerScreen =
          File('lib/features/player/player_screen.dart').readAsStringSync();

      expect(home.contains('timerTickWithFadeProvider'), isTrue,
          reason: 'home_screen 驱动点已换线到合并 tick');
      expect(playerScreen.contains('timerTickWithFadeProvider'), isTrue,
          reason: 'player_screen 驱动点已换线到合并 tick');
      expect(home.contains('checkTimerExpiryProvider'), isFalse,
          reason: 'home_screen 对旧 expiry 通路的生产引用归零');
      expect(playerScreen.contains('checkTimerExpiryProvider'), isFalse,
          reason: 'player_screen 对旧 expiry 通路的生产引用归零');
    });
  });

  group('TMR-01-S7: di 导出登记', () {
    test('TMR-01-S7: shared/di/providers.dart 登记三符号并新增 fade_policy 导出行', () {
      final di = File('lib/shared/di/providers.dart').readAsStringSync();
      expect(di.contains('fadeVolumeForRemaining'), isTrue,
          reason: 'timer 段导出 fadeVolumeForRemaining');
      expect(di.contains('kTimerFadeWindow'), isTrue,
          reason: 'timer 段导出 kTimerFadeWindow');
      expect(di.contains('timerTickWithFadeProvider'), isTrue,
          reason: 'player 段导出 timerTickWithFadeProvider');
      expect(di.contains('fade_policy'), isTrue,
          reason: 'providers.dart 含指向 domain/fade_policy.dart 的 export 行');
    });
  });

  group('TMR-01-INV1: 音量写权唯一', () {
    test('TMR-01-INV1: lib/ 中 setVolume 引用仅存在于契约声明/适配器透传/编排放三处', () {
      const allowedSuffixes = [
        'features/player/player_provider.dart',
        'core/contracts/audio_player_contract.dart',
        'core/services/audio_player_adapter.dart',
      ];
      final hits = _libFilesContaining('setVolume(');
      expect(hits, contains('lib/features/player/player_provider.dart'),
          reason: '唯一音量写点位于 timerTickWithFadeProvider 编排闭包');
      final unexpected =
          hits.where((p) => !allowedSuffixes.any(p.endsWith)).toList();
      expect(unexpected, isEmpty,
          reason: 'INV1 单一写权：除 S1 规定的契约抽象方法声明与适配器透传行外，'
              'lib/ 不得出现任何其它 setVolume 引用；违规文件: $unexpected');
    });
  });

  group('TMR-01-INV2: 非激活稳态音量为 1.0', () {
    test('TMR-01-INV2: 取消后 tick 收敛到只写 1.0，稳态连续 tick 零交互', () async {
      final container = _fadeContainer();
      addTearDown(container.dispose);

      await _driveToFading(container);
      container.read(cancelTimerProvider)();
      await _tick(container);
      verify(_player.setVolume(1.0)).called(1);

      clearInteractions(_player);
      for (var i = 0; i < 3; i++) {
        await _tick(container);
      }
      verifyZeroInteractions(_player);
    });
  });

  group('TMR-01-INV3: afterCurrent/paused 永不写 <1.0', () {
    test('TMR-01-INV3: afterCurrent 模式多次 tick 从未出现 <1.0 的 setVolume 参数',
        () async {
      final container = _fadeContainer();
      addTearDown(container.dispose);

      container.read(startAfterCurrentProvider)();
      for (var i = 0; i < 3; i++) {
        await _tick(container);
      }
      expect(container.read(timerStateProvider)!.mode, TimerMode.afterCurrent,
          reason: '前置确认: tick 执行于 afterCurrent 活跃态而非空转');
      expect(_player.writtenVolumes.where((v) => v < 1.0), isEmpty,
          reason: 'afterCurrent 全程不得写出 <1.0 的音量');
      verifyNever(_player.pause());
    });

    test('TMR-01-INV3: paused 冻结在窗口内多次 tick 从未出现 <1.0 的 setVolume 参数',
        () async {
      final container = _fadeContainer();
      addTearDown(container.dispose);

      container.read(startDurationTimerProvider)(1);
      _advance(const Duration(seconds: 56));
      container.read(timerServiceProvider).pause();
      _notifierOf(container).inject(container.read(timerServiceProvider).state);

      final st = container.read(timerStateProvider)!;
      expect(st.mode, TimerMode.paused);
      expect(st.remainingTime!.inMilliseconds, lessThanOrEqualTo(10000),
          reason: '前置确认: 冻结剩余确已落在淡出窗口内');

      for (var i = 0; i < 3; i++) {
        await _tick(container);
      }
      expect(_player.writtenVolumes.where((v) => v < 1.0), isEmpty,
          reason: 'paused 冻结窗口内全程不得写出 <1.0 的音量');
      verifyNever(_player.pause());
      expect(container.read(timerStateProvider)!.mode, TimerMode.paused,
          reason: 'paused 状态不被 tick 误清');
    });
  });

  group('TMR-01-INV4: 到期副作用顺序不变量', () {
    test(
        'TMR-01-INV4: 副作用顺序恒为 setVolume(0.0)→pause→setVolume(1.0)，'
        'pause 前 0 写保证最后一刻无声', () async {
      final container = _fadeContainer();
      addTearDown(container.dispose);

      await _driveToFading(container);
      _advance(const Duration(seconds: 5));
      await _tick(container);

      verifyInOrder([
        _player.setVolume(0.0),
        _player.pause(),
        _player.setVolume(1.0),
      ]);
    });
  });
}
