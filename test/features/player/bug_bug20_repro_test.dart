// test/features/player/bug_bug20_repro_test.dart
// BUG-20: 退出全屏播放页后自动保存/暂停保存监听被取消 —— 后台收听进度丢失窗口。
// cr 来源: docs/cr/cr-20260822-2051.md F1
//
// 复现语义（用户链路）:
//   加载成功启动监听器 → 打开全屏播放页再退出（PlayerScreen.dispose）→
//   后台继续播放 → 通知栏暂停 / 10s 自动保存应持续持久化进度；
//   实际(修复前): dispose 调 cancelPlaybackSubscriptionsProvider 杀掉两个监听器，
//   进度从此不再保存。
//
// 脚手架修订（2026-08-23，dev-exe round-1，见 BUG-20.md §2/§5.4）:
//   生产语义的"退出播放页"= pop 路由，应用级 ProviderScope 容器存活。
//   故用外部 ProviderContainer + UncontrolledProviderScope 承载页面，
//   退页 = 仅替换路由子树；整树 pumpWidget(SizedBox) 会连带销毁容器、
//   触发 ref.onDispose 合法清理（INV1 自身机制），无法区分两类 dispose。
//   断言逐字未动。
//
// 覆盖:
// BUG-20-S1-T01: 对照组 —— 页面存活期间暂停保存与自动保存均正常（恒真锚定）
// BUG-20-S2-T01: 退出页面后，playing→paused 暂停转换仍必须触发保存（修复前 FAIL）
// BUG-20-S3-T01: 退出页面后，10s 周期自动保存仍必须持续触发（修复前 FAIL）

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:mockito/mockito.dart';
import 'package:nas_audio_player/features/player/player_screen.dart';
import 'package:nas_audio_player/shared/di/providers.dart';
import 'package:nas_audio_player/shared/models/nas_file.dart';
import 'package:nas_audio_player/shared/models/play_queue.dart';

import '../../helpers/mock_audio_player.dart';

NasFile _audio(String name, String path) =>
    NasFile(name: name, path: path, isDirectory: false);

/// 与 ply_14_test 同款装配：loadAndPlayProvider 覆写为直接成功，
/// 使 PlayerScreen 走真实的生产路径启动三类监听器
/// （_startPlaybackListeners，player_provider.dart:342-347），
/// 但不依赖连接/密码等外部依赖。
ProviderContainer _makeContainer(
  MockAudioPlayer player,
  PlayQueue queue,
  List<String> saves,
) {
  return ProviderContainer(overrides: [
    audioPlayerProvider.overrideWith((ref) => player),
    audioHandlerProvider.overrideWith((ref) => null),
    currentPlayQueueProvider.overrideWith((ref) => queue),
    seekStepSettingProvider.overrideWith((ref) => 15),
    loadAndPlayProvider.overrideWith(
      (ref) => () async => const TrackLoadResult.loaded(),
    ),
    saveProgressProvider.overrideWithValue(() => saves.add('save')),
  ]);
}

/// 容器保活的根 scope：退页只换 [home]，监听器生命周期归容器（INV1）。
Widget _scope(ProviderContainer container,
        {Widget home = const PlayerScreen()}) =>
    UncontrolledProviderScope(
        container: container, child: MaterialApp(home: home));

Future<void> _pumpReady(WidgetTester tester, Widget app) async {
  await tester.pumpWidget(app);
  await tester.pump(); // postFrame 回调触发 _loadAndPlay
  await tester.pump(const Duration(milliseconds: 100)); // 异步续体 + rebuild
  await tester.pump(const Duration(milliseconds: 100)); // 流数据送达 + rebuild

  // 覆写的 loadAndPlayProvider 会绕过 _runLoadOrchestrated 的监听器启动分支，
  // 故经生产快路径入口（player_screen initState fast-path 同款）显式启动三类监听器。
  final ctx = tester.element(find.byType(PlayerScreen));
  final container = ProviderScope.containerOf(ctx);
  container.read(reconnectPlaybackListenersProvider)();
  await tester.pump();
}

void main() {
  late MockAudioPlayer player;
  late StreamController<PlayerState> stateCtrl;

  setUp(() {
    player = MockAudioPlayer();
    stateCtrl = StreamController<PlayerState>.broadcast();
    when(player.playerStateStream).thenAnswer((_) => stateCtrl.stream);
    when(player.processingStateStream)
        .thenAnswer((_) => const Stream<ProcessingState>.empty());
    when(player.positionStream)
        .thenAnswer((_) => Stream.value(const Duration(minutes: 1)));
    when(player.durationStream)
        .thenAnswer((_) => Stream.value(const Duration(minutes: 4)));
    when(player.speedStream).thenAnswer((_) => Stream.value(1.0));
    when(player.playing).thenReturn(true);
    when(player.processingState).thenReturn(ProcessingState.ready);
    when(player.position).thenReturn(const Duration(minutes: 1));
    when(player.duration).thenReturn(const Duration(minutes: 4));
    when(player.sequenceState).thenReturn(null);
  });

  tearDown(() {
    stateCtrl.close();
  });

  final queue = PlayQueue(
    files: [_audio('Chapter.mp3', '/books/Chapter.mp3')],
    currentIndex: 0,
  );

  group('BUG-20-S1-T01 对照组: 页面存活期间保存机制正常', () {
    testWidgets('暂停转换与自动保存均正常记账', (tester) async {
      final saves = <String>[];
      final container = _makeContainer(player, queue, saves);
      await _pumpReady(tester, _scope(container));

      stateCtrl.add(PlayerState(true, ProcessingState.ready));
      await tester.pump();
      expect(saves, isEmpty, reason: '保持播放不触发保存');

      stateCtrl.add(PlayerState(false, ProcessingState.ready));
      await tester.pump();
      expect(saves, hasLength(1), reason: '页面存活时暂停转换必须触发保存');
      expect(saves, hasLength(1), reason: '页面存活时暂停转换必须触发保存');

      await tester.pump(const Duration(seconds: 10));
      expect(saves, hasLength(2), reason: '页面存活时 10s 自动保存必须触发');

      // 体末先退页再销毁容器：框架收尾卸载时页面不得读已死容器，
      // 容器销毁同步取消 autosave/pausesave（INV1 清理机制）
      await tester.pumpWidget(_scope(container, home: const Scaffold()));
      await tester.pump();
      container.dispose();
    });
  });

  group('BUG-20-S2 修复门禁（修复前 FAIL）', () {
    testWidgets('BUG-20-S2-T01: 退出页面后，暂停仍必须持久化进度', (tester) async {
      final saves = <String>[];
      final container = _makeContainer(player, queue, saves);
      await _pumpReady(tester, _scope(container));

      // 页面内一次暂停（确认监听器活着）
      stateCtrl.add(PlayerState(false, ProcessingState.ready));
      await tester.pump();
      expect(saves, hasLength(1));

      // 打开过播放页后退出：仅卸载页面路由（模拟生产 pop），容器保活，
      // 触发真实 PlayerScreen.dispose（修复前此处含破坏性取消）
      await tester.pumpWidget(_scope(container, home: const Scaffold()));
      await tester.pump();

      // 后台继续收听后经通知栏暂停：resume 再 pause
      stateCtrl.add(PlayerState(true, ProcessingState.ready));
      await tester.pump();
      stateCtrl.add(PlayerState(false, ProcessingState.ready));
      await tester.pump();

      // 期望: 1(页面内) + 1(dispose 收尾) + 1(后台暂停) = 3
      // 实际(修复前): dispose 已杀 pause-save 订阅 → 停在 2
      expect(saves, hasLength(3), reason: '退出播放页后通知栏暂停必须仍然持久化进度');

      await tester.pumpWidget(_scope(container, home: const Scaffold()));
      await tester.pump();
      container.dispose();
    });

    testWidgets('BUG-20-S3-T01: 退出页面后，10s 自动保存仍必须持续', (tester) async {
      final saves = <String>[];
      final container = _makeContainer(player, queue, saves);
      await _pumpReady(tester, _scope(container));

      await tester.pump(const Duration(seconds: 10));
      expect(saves, hasLength(1), reason: '退出前自动保存正常');

      await tester.pumpWidget(_scope(container, home: const Scaffold()));
      await tester.pump();
      // dispose 收尾保存，修复前后都存在
      expect(saves.length, greaterThanOrEqualTo(2));

      // 后台继续收听 20s：应有两个自动保存周期
      await tester.pump(const Duration(seconds: 20));
      // 期望: 2 + 2 = 4；实际(修复前): 定时器已被 dispose 取消 → 停在 2
      expect(saves.length, greaterThanOrEqualTo(4),
          reason: '退出播放页后 10s 自动保存必须继续生效');

      await tester.pumpWidget(_scope(container, home: const Scaffold()));
      await tester.pump();
      container.dispose();
    });
  });
}
