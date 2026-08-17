// test/features/player/bug_02_repro_test.dart
// BUG-02: skip 回调绑定 PlayerScreen dispose —— 退出播放页后通知栏按钮永久
// 失效（P8 违规）
// （spec: docs/features/BUG-02.md §5.4，来源 cr-20260816-0801 F1）
//
// 修复：接线从 player_screen.dart initState/dispose 提升到应用级 Provider
// backgroundPlaybackSyncProvider（player_provider.dart），随
// HomeScreen build 的 eager-read 触发（home_screen.dart:80）。
// PlayerScreen dispose 不再触碰 skip 回调 —— 回调生命周期 = 应用容器
// 生命周期，退出播放页后通知栏/耳机"下一首/上一首"仍有效。
// platform-pitfalls P8 明文：播放生命周期监听器严禁绑定任何页面的 dispose。
//
// 门禁测试（修复后必须 PASS）：
//   BUG-02-S1: 播放/播放器存活时 skip 回调已接线（应用级接线生效）
//   BUG-02-S2: PlayerScreen dispose 后 handler.onSkipToNextRequested /
//              onSkipToPreviousRequested 仍非 null（回调归编排层持有，
//              不随页面销毁）—— 修复前（dispose 置 null）FAIL

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:mockito/mockito.dart';
import 'package:nas_audio_player/core/services/audio_handler.dart';
import 'package:nas_audio_player/features/player/player_screen.dart';
import 'package:nas_audio_player/features/player/player_provider.dart';
import 'package:nas_audio_player/shared/di/providers.dart';
import 'package:nas_audio_player/shared/models/play_queue.dart';

import '../../helpers/mock_audio_player.dart';
import '../../helpers/test_factories.dart';

/// 与 ply_14_test.dart _buildTestApp 相同的装配，唯一区别：audioHandlerProvider
/// 注入真实 NasAudioHandler（而非 null），由应用级接线（provider 层）驱动。
///
/// BUG-02 修复后接线发生在应用级 Provider（backgroundPlaybackSyncProvider），
/// 触发点 = HomeScreen build 的 eager-read（home_screen.dart:80），应用容器
/// 存活即接线存活。本测试 fixture 用 [UncontrolledProviderScope] 持有独立
/// [ProviderContainer]，复刻生产端"容器随应用存活、页面随路由进出"的语义
/// （同仓库 con_* / bug_bug16 装配风格）。
Widget _buildTestApp({
  required ProviderContainer container,
  required PlayQueue queue,
}) {
  return UncontrolledProviderScope(
    container: container,
    child: const _ApplicationScope(child: MaterialApp(home: PlayerScreen())),
  );
}

/// 复刻 home_screen.dart:80 的 eager-read：接线一旦发生即随应用容器存活，
/// 不依赖任何页面挂载/销毁。
class _ApplicationScope extends ConsumerWidget {
  const _ApplicationScope({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.read(backgroundPlaybackSyncProvider);
    return child;
  }
}

List<Override> _overrides({
  required MockAudioPlayer player,
  required NasAudioHandler handler,
  required PlayQueue queue,
}) =>
    [
      audioPlayerProvider.overrideWith((ref) => player),
      audioHandlerProvider.overrideWith((ref) => handler),
      currentPlayQueueProvider.overrideWith((ref) => queue),
      seekStepSettingProvider.overrideWith((ref) => 15),
      loadAndPlayProvider.overrideWith(
        (ref) => () async => const TrackLoadResult.loaded(),
      ),
    ];

void main() {
  // 2 首曲目、当前第 0 首（ply_14 同款 defaultQueue）。
  final defaultQueue = PlayQueue(
    files: [
      testAudio('Test Song.mp3', '/music/Test Song.mp3'),
      testAudio('Song 2.flac', '/music/Song 2.flac'),
    ],
    currentIndex: 0,
  );

  late MockAudioPlayer player;
  late NasAudioHandler handler;

  setUp(() {
    player = MockAudioPlayer();
    when(player.positionStream).thenAnswer(
        (_) => Stream.value(const Duration(minutes: 1, seconds: 30)));
    when(player.durationStream)
        .thenAnswer((_) => Stream.value(const Duration(minutes: 4)));
    when(player.playerStateStream).thenAnswer(
        (_) => Stream.value(PlayerState(true, ProcessingState.ready)));
    when(player.speedStream).thenAnswer((_) => Stream<double>.empty());
    when(player.processingStateStream)
        .thenAnswer((_) => const Stream<ProcessingState>.empty());
    when(player.playing).thenReturn(true);
    when(player.processingState).thenReturn(ProcessingState.ready);
    when(player.position).thenReturn(const Duration(minutes: 1, seconds: 30));
    when(player.duration).thenReturn(const Duration(minutes: 4));
    when(player.sequenceState).thenReturn(null);
    handler = NasAudioHandler(player);
  });

  tearDown(() {
    handler.dispose();
  });

  testWidgets('BUG-02-S1: 播放器存活时 skip 回调已接线', (tester) async {
    final container = ProviderContainer(
        overrides:
            _overrides(player: player, handler: handler, queue: defaultQueue));
    addTearDown(container.dispose);

    await tester
        .pumpWidget(_buildTestApp(container: container, queue: defaultQueue));
    await tester.pump(); // Post-frame callback fires
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));

    expect(handler.onSkipToNextRequested, isNotNull,
        reason: '应用级接线（backgroundPlaybackSyncProvider，player_provider.dart）'
            '必须已生效');
    expect(handler.onSkipToPreviousRequested, isNotNull,
        reason: '应用级接线必须同时覆盖上一首回调');
  });

  testWidgets(
      'BUG-02-S2: PlayerScreen dispose 后 skip 回调必须保留'
      '（不得随页面销毁置 null）', (tester) async {
    final container = ProviderContainer(
        overrides:
            _overrides(player: player, handler: handler, queue: defaultQueue));
    addTearDown(container.dispose);

    await tester
        .pumpWidget(_buildTestApp(container: container, queue: defaultQueue));
    await tester.pump(); // Post-frame callback fires
    await tester.pump(const Duration(milliseconds: 100));

    // 前置：接线已发生。
    expect(handler.onSkipToNextRequested, isNotNull);

    // 模拟退出播放页：同一应用容器下换掉子路由 → PlayerScreen.dispose 执行，
    // 但容器（ProviderScope 等价物）存活，应用级接线不得被释放。
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: Scaffold(body: SizedBox())),
    ));

    expect(handler.onSkipToNextRequested, isNotNull,
        reason: 'BUG-02（P8 违规修复）：退出播放页后 skip 回调仍由应用级接线'
            '持有，不得被 PlayerScreen dispose 置 null'
            '（接线在 backgroundPlaybackSyncProvider，不随页面销毁，'
            'cr-20260816-0801 F1）');
    expect(handler.onSkipToPreviousRequested, isNotNull, reason: '同上门首回调');
  });
}
