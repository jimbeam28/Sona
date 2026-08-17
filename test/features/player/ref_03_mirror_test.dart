// test/features/player/ref_03_mirror_test.dart
// REF-03 (docs/features/REF-03.md §5.4 门禁) — 后台播放状态机去镜像：
// handler `_config` 唯一生产真身，BackgroundPlaybackNotifier 缩为只读镜像。
//
// 覆盖: REF-03-S2 / S5 / S8 / REF-03-INV1 / REF-03-INV2。
//
//   S2  — onConfigChanged → syncFromHandler 接线（backgroundPlaybackSyncProvider）
//   S5  — notifier 只暴露 syncFromHandler（编译期符号面，本文件只消费保留面）
//   S8  — 触发 handler 状态变化 → backgroundPlaybackProvider.state == handler.config
//   INV1 — handler 驱动，notifier 只读镜像（不反向驱动 handler）
//   INV2 — 容器存活期间镜像恒等于最近一次 onConfigChanged 推送的 config
//
// 装配风格仿 bug_01_repro_test.dart / audio_handler_test.dart：
// MockAudioPlayer + 真实 NasAudioHandler + ProviderContainer override
// audioHandlerProvider，eager-read backgroundPlaybackSyncProvider 触发接线。

import 'dart:async';
import 'dart:io';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:mockito/mockito.dart';
import 'package:nas_audio_player/core/services/audio_handler.dart';
import 'package:nas_audio_player/features/player/player_provider.dart';

import '../../helpers/mock_audio_player.dart';

/// 与 audio_handler_test.dart makeHandler 相同的装配。
NasAudioHandler makeHandler(MockAudioPlayer player) {
  when(player.playerStateStream)
      .thenAnswer((_) => const Stream<PlayerState>.empty());
  when(player.positionStream).thenAnswer((_) => const Stream<Duration>.empty());
  when(player.durationStream)
      .thenAnswer((_) => const Stream<Duration?>.empty());
  when(player.position).thenReturn(Duration.zero);
  when(player.bufferedPosition).thenReturn(Duration.zero);
  when(player.speed).thenReturn(1.0);
  return NasAudioHandler(player);
}

void main() {
  // ═══════════════════════════════════════════════════════════════════════════
  // REF-03-S2/S8：onConfigChanged → syncFromHandler 单向镜像链路
  // ═══════════════════════════════════════════════════════════════════════════

  group(
      'REF-03-S2/S8: handler _config → backgroundPlaybackSyncProvider → '
      'notifier 镜像一致', () {
    test(
        'S8: handler.pause() 后 backgroundPlaybackProvider 状态 == handler.config',
        () {
      FakeAsync().run((async) {
        final player = MockAudioPlayer();
        when(player.pause()).thenAnswer((_) async {});
        final handler = makeHandler(player);

        final container = ProviderContainer(overrides: [
          audioHandlerProvider.overrideWith((ref) => handler),
        ]);
        addTearDown(container.dispose);

        // eager-read 触发接线（home_screen.dart:80 同款）。
        container.read(backgroundPlaybackSyncProvider);

        // 初始镜像：handler.config.initial == provider 状态。
        expect(container.read(backgroundPlaybackProvider), handler.config,
            reason: '接线后镜像初始状态应等于 handler.config');

        // 触发 handler 状态变化：pause → config 转 paused + 推送镜像。
        handler.pause();
        async.flushMicrotasks();

        expect(handler.config.playbackState, BackgroundPlaybackState.paused,
            reason: 'handler 真身状态机应转入 paused');
        expect(container.read(backgroundPlaybackProvider), handler.config,
            reason: 'S8: 镜像 provider 状态恒等于 handler.config');

        handler.dispose();
      });
    });

    test('S8: handler.play() 后镜像跟随 playing', () {
      FakeAsync().run((async) {
        final player = MockAudioPlayer();
        when(player.play()).thenAnswer((_) async {});
        final handler = makeHandler(player);

        final container = ProviderContainer(overrides: [
          audioHandlerProvider.overrideWith((ref) => handler),
        ]);
        addTearDown(container.dispose);
        container.read(backgroundPlaybackSyncProvider);

        handler.play();
        async.flushMicrotasks();

        expect(handler.config.playbackState, BackgroundPlaybackState.playing);
        expect(container.read(backgroundPlaybackProvider), handler.config,
            reason: '镜像跟随 playing');

        handler.dispose();
      });
    });

    test('S8: handler.stop() 后镜像跟随 stopped', () {
      FakeAsync().run((async) {
        final player = MockAudioPlayer();
        when(player.stop()).thenAnswer((_) async {});
        final handler = makeHandler(player);

        final container = ProviderContainer(overrides: [
          audioHandlerProvider.overrideWith((ref) => handler),
        ]);
        addTearDown(container.dispose);
        container.read(backgroundPlaybackSyncProvider);

        handler.stop();
        async.flushMicrotasks();

        expect(handler.config.playbackState, BackgroundPlaybackState.stopped);
        expect(container.read(backgroundPlaybackProvider), handler.config,
            reason: '镜像跟随 stopped');

        handler.dispose();
      });
    });

    test('S8(否定): 容器存活期间 onConfigChanged 不得被置 null（镜像持续）', () {
      FakeAsync().run((async) {
        final player = MockAudioPlayer();
        when(player.pause()).thenAnswer((_) async {});
        final handler = makeHandler(player);

        final container = ProviderContainer(overrides: [
          audioHandlerProvider.overrideWith((ref) => handler),
        ]);
        addTearDown(container.dispose);
        container.read(backgroundPlaybackSyncProvider);

        // 二次变化仍应镜像（回调未被清除）。
        handler.pause();
        async.flushMicrotasks();
        expect(handler.config.playbackState, BackgroundPlaybackState.paused);

        handler.play();
        async.flushMicrotasks();
        expect(handler.config.playbackState, BackgroundPlaybackState.playing);
        expect(container.read(backgroundPlaybackProvider), handler.config,
            reason: 'INV2: 容器存活期间镜像持续跟随多次 config 变化');

        handler.dispose();
      });
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // REF-03-S5 / INV1：notifier 只读镜像——只暴露 syncFromHandler
  // ═══════════════════════════════════════════════════════════════════════════

  // 测试工作目录 = 仓库根目录（flutter test 在项目根执行）。
  String readAsString(String relPath) => File(relPath).readAsStringSync();

  group('REF-03-S5/INV1: notifier 只读镜像（符号面 + 语义）', () {
    test('INV1: notifier 实例仅保留 syncFromHandler 单入口（编译期）', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(backgroundPlaybackProvider.notifier);
      // 直接验证 syncFromHandler 存在且可调用（删除后唯一方法）。
      expect(notifier.syncFromHandler, isA<Function>());

      // syncFromHandler 把任意 config 镜像进去（只读镜像语义）。
      const target = BackgroundPlaybackConfig(
        backgroundEnabled: false,
        isInForeground: false,
        playbackState: BackgroundPlaybackState.paused,
        audioFocus: AudioFocusState.gained,
      );
      notifier.syncFromHandler(target);
      expect(container.read(backgroundPlaybackProvider), target,
          reason: 'S5: syncFromHandler 单向镜像，state 恒等于被推送 config');
    });

    test('INV1: 无任何删除符号残留（mapLifecycleState 等已从 export 移除）', () {
      // 编译期符号断言：player_provider.dart 不再导出 mapLifecycleState /
      // backgroundPlaybackEnabledProvider。若导出存在，下列引用无法编译——
      // 测试文件不在 lib 内，这里用 Dart 反射式 string 检查源码面。
      final providerSource =
          readAsString('lib/features/player/player_provider.dart');
      expect(providerSource, isNot(contains('mapLifecycleState')),
          reason: 'mapLifecycleState 导出已移除');
      expect(
          providerSource, isNot(contains('backgroundPlaybackEnabledProvider')),
          reason: 'backgroundPlaybackEnabledProvider 定义已删除');

      final notifierSource =
          readAsString('lib/features/player/background_playback_notifier.dart');
      // 死面驱动方法不得再有方法声明（方法名后跟 `(` 且前置 void/类签名）。
      for (final dead in [
        'void onAppLifecycleChange(',
        'void onMediaControl(',
        'void onAudioFocusChange(',
        'void startPlayback(',
        'void pausePlayback(',
        'void stopPlayback(',
        'void setBackgroundEnabled(',
      ]) {
        expect(notifierSource, isNot(contains(dead)),
            reason: '死面驱动方法 "$dead" 已从 notifier 删除');
      }
      // mapLifecycleState 顶层函数已删除。
      expect(notifierSource,
          isNot(contains('AppLifecyclePhase mapLifecycleState(')),
          reason: 'mapLifecycleState 已删除');
    });

    test('INV2: 镜像状态不可反向驱动 handler（notifier 无状态转移方法）', () {
      // 编译期 symbol 面：BackgroundPlaybackNotifier 类只有 syncFromHandler
      // 一个 public method —— 反向驱动方法已删除。
      final notifierSource =
          readAsString('lib/features/player/background_playback_notifier.dart');
      final methods = RegExp(
              r'^\s+(final|void|Future|bool|int|String|List|Set|Map|BackgroundPlaybackConfig|Stream|double|DateTime|AppLifecyclePhase|AudioFocusState|PlayQueue|Timer|T)\w*\s+(\w+)\(',
              multiLine: true)
          .allMatches(notifierSource)
          .map((m) => m.group(2))
          .toList();
      // 除构造函数外，仅 syncFromHandler 一个 public method。
      final publicMethods =
          methods.where((m) => m != 'syncFromHandler').toList();
      expect(publicMethods, isEmpty, reason: 'INV1: notifier 只读镜像，不得再有其它驱动方法');
    });
  });
}
