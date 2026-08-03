// test/features/player/bug_bug21_repro_test.dart
// BUG-21: autoSave/pauseSave provider 缺 ref.onDispose 资源泄漏 —
// spec §5.4 门禁测试（docs/features/BUG-21.md）。
//
// CR 来源: docs/cr/cr-2026-06-28.md FRAGILE-07 (F7)
//
// 覆盖:
// BUG-21-S1-T01: 正常播放 10s 周期自动保存行为不变；显式 cancel 路径不变
// BUG-21-S1-T02: ProviderContainer dispose（U1）→ Timer 被 cancel，
//                不再触发保存，无 zone 未捕获错误
// BUG-21-S2-T01: 暂停保存行为不变（playing→paused 触发保存）；
//                显式 cancel 路径不变
// BUG-21-S2-T02: ProviderContainer dispose（U1）→ 订阅被 cancel，
//                dispose 后的暂停事件不再触发保存，无 zone 未捕获错误
// BUG-21-INV1-T01: 源码扫描 — 全部创建 Timer/StreamSubscription 的
//                  start provider 均有 ref.onDispose 清理
// BUG-21-INV1-T02: 否定断言 — onDispose 内不得 ref.read：
//                  ProviderContainer.dispose() 先把容器标记为 disposed 再逐个
//                  dispose element（riverpod 2.6 container.dart），此时
//                  ref.read 抛 StateError 且 runGuarded 吞掉后上报 zone，
//                  cancel 根本不会执行 → 泄漏照旧（复核实验证实）
// BUG-21-INV2-T01: onDispose 在 Provider body 层注册（return 之前），
//                  三个 start provider 模式一致
//
// 注: S1-T02/S2-T02 走 reconnectPlaybackListenersProvider 入口，dispose 时
// startProcessingListenerProvider 的 element 同样存活 —— 若任一 start
// provider 的 onDispose 仍用 ref.read，handleUncaughtError 会使测试失败。

import 'dart:async';
import 'dart:io';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:mockito/mockito.dart';
import 'package:nas_audio_player/features/player/player_provider.dart';

import '../../helpers/mock_audio_player.dart';

// ── 测试环境 ────────────────────────────────────────────────────────────────

({
  ProviderContainer container,
  MockAudioPlayer player,
  StreamController<ProcessingState> processingController,
  StreamController<PlayerState> playerStateController,
  List<String> saves,
}) _createEnv() {
  final processingController = StreamController<ProcessingState>.broadcast();
  final playerStateController = StreamController<PlayerState>.broadcast();
  final player = MockAudioPlayer();
  when(player.processingStateStream)
      .thenAnswer((_) => processingController.stream);
  when(player.playerStateStream)
      .thenAnswer((_) => playerStateController.stream);
  when(player.playing).thenReturn(true);

  final saves = <String>[];
  final container = ProviderContainer(
    overrides: [
      audioPlayerProvider.overrideWithValue(player),
      saveProgressProvider.overrideWithValue(() => saves.add('save')),
    ],
  );
  return (
    container: container,
    player: player,
    processingController: processingController,
    playerStateController: playerStateController,
    saves: saves,
  );
}

/// 提取 [name] provider 定义的源码片段（到下一个顶层 final 声明为止），
/// 供 INV1/INV2 源码扫描用例使用。
String _providerBody(String src, String name) {
  final start = src.indexOf('final $name = Provider');
  expect(start, greaterThanOrEqualTo(0), reason: '$name 定义必须存在');
  final nextTopLevel = RegExp(r'^final ', multiLine: true)
      .allMatches(src)
      .map((m) => m.start)
      .where((i) => i > start)
      .toList();
  final end = nextTopLevel.isEmpty ? src.length : nextTopLevel.first;
  return src.substring(start, end);
}

void main() {
  // ═════════════════════════════════════════════════════════════════════════
  // BUG-21-S1: _startAutoSaveProvider dispose 时取消定时器
  // ═════════════════════════════════════════════════════════════════════════

  group('BUG-21-S1-T01: 正常 10s 自动保存行为不变', () {
    test('周期保存持续生效；显式 cancel 路径不变', () {
      FakeAsync().run((async) {
        final env = _createEnv();

        // reconnect 入口同时启动 processing listener / autoSave / pauseSave
        env.container.read(reconnectPlaybackListenersProvider)();
        async.flushMicrotasks();
        expect(env.saves, isEmpty, reason: '启动本身不触发保存');

        async.elapse(const Duration(seconds: 10));
        expect(env.saves, hasLength(1), reason: '10s 自动保存必须触发（U2）');

        async.elapse(const Duration(seconds: 20));
        expect(env.saves, hasLength(3), reason: '周期保存持续生效');

        // 显式 cancel 路径（_cancelAutoSaveProvider）行为不变
        env.container.read(cancelPlaybackSubscriptionsProvider)();
        async.elapse(const Duration(seconds: 30));
        expect(env.saves, hasLength(3), reason: '显式 cancel 后定时器停止');

        // dispose 不得抛错（回归: onDispose 内 ref.read 会经 runGuarded
        // 上报 zone 未捕获错误并使测试失败）
        env.container.dispose();
        async.elapse(const Duration(seconds: 30));
        expect(env.saves, hasLength(3));
      });
    });
  });

  group('BUG-21-S1-T02: ProviderContainer dispose 取消定时器', () {
    test('dispose 后 Timer 不再触发，且不访问已释放 provider', () {
      FakeAsync().run((async) {
        final env = _createEnv();
        env.container.read(reconnectPlaybackListenersProvider)();
        async.flushMicrotasks();

        async.elapse(const Duration(seconds: 10));
        expect(env.saves, hasLength(1), reason: 'dispose 前自动保存正常');

        // U1: ProviderScope dispose（等价 container.dispose）
        env.container.dispose();

        // 否定断言: dispose 后不得继续触发 Timer.periodic。
        // 回归说明: 若 onDispose 用 ref.read(...)，dispose 时 StateError
        // 在 cancel 之前抛出（容器已标记 disposed），定时器继续存活，
        // 下方 elapse 会继续产生保存（复核前实测 60s 内再触发 6 次）。
        async.elapse(const Duration(seconds: 60));
        expect(env.saves, hasLength(1),
            reason: '否定: dispose 后 Timer 必须已被 cancel，不得继续触发');
      });
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  // BUG-21-S2: _startPauseSaveProvider dispose 时取消订阅
  // ═════════════════════════════════════════════════════════════════════════

  group('BUG-21-S2-T01: 暂停保存行为不变', () {
    test('playing→paused 触发保存；显式 cancel 后不再接收事件', () {
      FakeAsync().run((async) {
        final env = _createEnv();
        env.container.read(reconnectPlaybackListenersProvider)();
        async.flushMicrotasks();

        env.playerStateController.add(PlayerState(true, ProcessingState.ready));
        async.flushMicrotasks();
        expect(env.saves, isEmpty, reason: '保持播放状态不触发保存');

        env.playerStateController
            .add(PlayerState(false, ProcessingState.ready));
        async.flushMicrotasks();
        expect(env.saves, hasLength(1), reason: '暂停转换必须触发保存');

        // 显式 cancel 路径（_cancelPauseSaveProvider）行为不变：
        // 镜像 StateProvider 仍被 cancel provider 消费，必须保持同步
        env.container.read(cancelPlaybackSubscriptionsProvider)();
        env.playerStateController.add(PlayerState(true, ProcessingState.ready));
        env.playerStateController
            .add(PlayerState(false, ProcessingState.ready));
        async.flushMicrotasks();
        expect(env.saves, hasLength(1), reason: '显式 cancel 后不再接收事件');

        env.container.dispose(); // 不得抛错
      });
    });
  });

  group('BUG-21-S2-T02: ProviderContainer dispose 取消订阅', () {
    test('dispose 后暂停事件不再触发保存，且不访问已释放 provider', () {
      FakeAsync().run((async) {
        final env = _createEnv();
        env.container.read(reconnectPlaybackListenersProvider)();
        async.flushMicrotasks();

        env.playerStateController.add(PlayerState(true, ProcessingState.ready));
        async.flushMicrotasks();
        expect(env.saves, isEmpty);

        // U1: ProviderScope dispose
        env.container.dispose();

        // 否定断言: dispose 后不得继续接收 playerStateStream 事件。
        // 回归说明: 若订阅未取消，回调内 ref.read(saveProgressProvider)
        // 会在已 dispose 的容器上抛 StateError（zone 未捕获错误使测试失败）。
        env.playerStateController
            .add(PlayerState(false, ProcessingState.ready));
        async.flushMicrotasks();
        expect(env.saves, isEmpty,
            reason: '否定: dispose 后订阅必须已被 cancel，'
                '暂停事件不得触发保存');
      });
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  // BUG-21-INV1 / INV2: onDispose 覆盖与模式一致性（源码扫描）
  // ═════════════════════════════════════════════════════════════════════════

  group('BUG-21-INV1/INV2: onDispose 覆盖与模式一致性', () {
    const startProviders = [
      '_startAutoSaveProvider',
      '_startPauseSaveProvider',
      'startProcessingListenerProvider',
    ];

    late String src;
    setUpAll(() {
      src = File('lib/features/player/player_provider.dart').readAsStringSync();
    });

    test('BUG-21-INV1: 全部 start provider 均有 ref.onDispose 清理', () {
      for (final name in startProviders) {
        final body = _providerBody(src, name);
        expect(body, contains('ref.onDispose('),
            reason: '$name 缺少 ref.onDispose 资源清理（BUG-21-INV1）');
      }
    });

    test('BUG-21-INV1 否定: onDispose 内不得 ref.read', () {
      // ProviderContainer.dispose() 先置 _disposed=true 再 dispose element，
      // onDispose 内 ref.read 会抛 StateError 且 cancel 不会执行，
      // 泄漏照旧并引入 dispose 异常 —— 即本复核修正的缺陷模式。
      expect(RegExp(r'ref\.onDispose\([^)]*ref\.read').hasMatch(src), isFalse,
          reason: '否定: onDispose 内禁止 ref.read'
              '（container dispose 时抛 StateError，cancel 不会执行）');
    });

    test('BUG-21-INV2: onDispose 在 Provider body 层注册（return 之前）', () {
      for (final name in startProviders) {
        final body = _providerBody(src, name);
        final disposeAt = body.indexOf('ref.onDispose(');
        final returnAt = body.indexOf('return');
        expect(disposeAt, greaterThanOrEqualTo(0), reason: '$name 缺 onDispose');
        expect(returnAt, greaterThan(disposeAt),
            reason: '$name 的 onDispose 必须在 Provider body 层注册'
                '（return 之前），与 Provider 生命周期绑定（BUG-21-INV2）');
      }
    });
  });
}
