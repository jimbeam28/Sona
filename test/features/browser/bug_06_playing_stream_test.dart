// test/features/browser/bug_06_playing_stream_test.dart
// BUG-06 门禁测试："下一曲"图标启用态响应播放状态（stream-based
// audioPlayingProvider）。
//
// 覆盖 BUG-06-S1（playingStream 响应式启用/禁用）、BUG-06-S2（playing=false
// 点击不触发 insertAfterCurrentProvider）、BUG-06-INV1（enabled 态与
// AudioPlayer.playing 实时同步）。
//
// 与 brw_09_test 的关键区别（cr-20260724-0110 BRW11 指出的响应性盲区）：
// 不在 pump 前静态打桩 playing 后一次断言，而是 pump 真实 BrowserScreen 且
// 不 override audioPlayingProvider（走生产 StreamProvider 接线），用
// StreamController 在 build 之后驱动 playingStream 发射 true/false，断言图标
// onPressed 实时翻转。audioPlayerProvider 的 mock 实例全程不变——证明重建由
// stream 事件驱动而非实例变化（BUG-06-S1 否定断言）。

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:mockito/mockito.dart';
import 'package:nas_audio_player/features/browser/browser_provider.dart';
import 'package:nas_audio_player/features/browser/browser_screen.dart';
import 'package:nas_audio_player/features/player/player_provider.dart';
import 'package:nas_audio_player/shared/models/nas_file.dart';
import 'package:nas_audio_player/shared/models/play_queue.dart';

import '../../helpers/mock_audio_player.dart';
import '../../helpers/test_factories.dart';

void main() {
  group('BUG-06: "下一曲"图标启用态响应播放状态', () {
    late MockAudioPlayer mockPlayer;
    late StreamController<bool> playingController;
    late PlayQueue queue;

    setUp(() {
      mockPlayer = MockAudioPlayer();
      playingController = StreamController<bool>();
      when(mockPlayer.playing).thenReturn(false);
      when(mockPlayer.processingState).thenReturn(ProcessingState.ready);
      when(mockPlayer.processingStateStream)
          .thenAnswer((_) => Stream<ProcessingState>.empty());
      // 关键：playingStream 接可控的 StreamController，
      // 测试在 build 之后逐个发射 playing 状态。
      when(mockPlayer.playingStream)
          .thenAnswer((_) => playingController.stream);

      queue = PlayQueue(
        files: [
          testAudio('track_01.mp3', '/music/track_01.mp3'),
          testAudio('track_02.mp3', '/music/track_02.mp3'),
        ],
        currentIndex: 0,
      );
    });

    tearDown(() => playingController.close());

    Future<void> pumpBrowser(
      WidgetTester tester, {
      List<Override> extraOverrides = const [],
    }) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            directoryContentsProvider('/').overrideWith(
                (ref) async => [testAudio('song.mp3', '/music/song.mp3')]),
            audioPlayerProvider.overrideWithValue(mockPlayer),
            // 不 override audioPlayingProvider —— 走生产 StreamProvider 接线。
            currentPlayQueueProvider.overrideWith((ref) => queue),
            playModeProvider.overrideWith((ref) => PlayMode.sequential),
            ...extraOverrides,
          ],
          child: const MaterialApp(home: Scaffold(body: BrowserScreen())),
        ),
      );
      await tester.pumpAndSettle();
    }

    Finder playNextIconButton() => find.ancestor(
        of: find.byIcon(Icons.queue_music), matching: find.byType(IconButton));

    testWidgets(
        'BUG-06-S1/U1: 初始 playing=false 灰禁 → stream 发 true 立即变亮 → 再发 false 立即变灰',
        (WidgetTester tester) async {
      await pumpBrowser(tester);

      // 初始 playing=false：图标灰禁
      var button = tester.widget<IconButton>(playNextIconButton());
      expect(button.onPressed, isNull,
          reason: 'S1: playing=false 时图标应禁用（onPressed == null）');
      expect(button.tooltip, contains('请先开始播放后再用此功能'));

      // 模拟"迷你栏点播放"：playingStream 发射 true（mock 实例不变）
      playingController.add(true);
      await tester.pumpAndSettle();

      button = tester.widget<IconButton>(playNextIconButton());
      expect(button.onPressed, isNotNull,
          reason: 'S1/U1: playing 翻转为 true 后图标应立即启用');
      expect(button.tooltip, equals('加入下一曲'));

      // 模拟"迷你栏暂停"：playingStream 发射 false
      playingController.add(false);
      await tester.pumpAndSettle();

      button = tester.widget<IconButton>(playNextIconButton());
      expect(button.onPressed, isNull,
          reason: 'S1/U2: playing 翻转为 false 后图标应立即禁用');
      expect(button.tooltip, contains('请先开始播放后再用此功能'));
    });

    testWidgets(
        'BUG-06-S2/BRW-09-S9: playing=true 点击触发 insert（正控）→ playing=false 后点击不触发 insertAfterCurrentProvider',
        (WidgetTester tester) async {
      final insertCalls = <NasFile>[];
      await pumpBrowser(
        tester,
        extraOverrides: [
          insertAfterCurrentProvider.overrideWithValue((NasFile f) async {
            insertCalls.add(f);
            return true;
          }),
        ],
      );

      // 先启播并点击一次——正控：证明本测试的点击链路能捕获 provider 调用
      playingController.add(true);
      await tester.pumpAndSettle();
      await tester.tap(playNextIconButton());
      await tester.pumpAndSettle();
      expect(insertCalls, hasLength(1),
          reason: 'S2 正控: playing=true 时点击应触发一次 insertAfterCurrent');
      expect(
          find.descendant(
              of: find.byType(SnackBar),
              matching: find.textContaining('已加入下一曲')),
          findsOneWidget,
          reason: 'S2 正控: playing=true 时点击应弹 SnackBar');

      // 暂停后图标禁用，点击不触发任何 provider 调用
      playingController.add(false);
      await tester.pumpAndSettle();
      final button = tester.widget<IconButton>(playNextIconButton());
      expect(button.onPressed, isNull, reason: 'S2: playing=false 时按钮禁用');

      await tester.tap(playNextIconButton());
      await tester.pumpAndSettle();

      expect(insertCalls, hasLength(1),
          reason: 'S2 否定断言: playing=false 点击不得再触发 insertAfterCurrentProvider');
      final container =
          ProviderScope.containerOf(tester.element(find.byType(BrowserScreen)));
      final q = container.read(currentPlayQueueProvider);
      expect(q, isNotNull);
      expect(q!.length, equals(2), reason: 'S2: 队列长度不变（未发生插入）');
      expect(q.currentIndex, equals(0));
    });

    testWidgets('BUG-06-S1 边界: stream 未发首个事件时图标默认灰禁（?? false 兜底）',
        (WidgetTester tester) async {
      // playingController 不发射任何事件 → audioPlayingProvider 处于
      // AsyncLoading，valueOrNull == null → `?? false` 安全默认。
      await pumpBrowser(tester);

      expect(playNextIconButton(), findsOneWidget,
          reason: '边界: 首事件到达前图标仍应渲染（不得崩溃/消失）');
      final button = tester.widget<IconButton>(playNextIconButton());
      expect(button.onPressed, isNull, reason: '边界: stream 首事件到达前默认禁用（安全默认值）');
      expect(button.tooltip, contains('请先开始播放后再用此功能'));

      // 首事件到达后立即按实际值渲染
      playingController.add(true);
      await tester.pumpAndSettle();
      final after = tester.widget<IconButton>(playNextIconButton());
      expect(after.onPressed, isNotNull, reason: '边界: 首事件 true 后启用');
    });

    testWidgets('BUG-06-INV1: enabled 态与 playing 实时同步（true→false→true 多次翻转）',
        (WidgetTester tester) async {
      // 预置 playing=true（单订阅 controller 在 listen 前缓存，模拟
      // just_audio BehaviorSubject 回放当前值语义）
      playingController.add(true);
      await pumpBrowser(tester);

      IconButton button() => tester.widget<IconButton>(playNextIconButton());

      expect(button().onPressed, isNotNull,
          reason: 'INV1: 初始 playing=true 应启用');

      playingController.add(false);
      await tester.pumpAndSettle();
      expect(button().onPressed, isNull, reason: 'INV1: 第 1 次暂停应禁用');

      playingController.add(true);
      await tester.pumpAndSettle();
      expect(button().onPressed, isNotNull, reason: 'INV1: 第 2 次播放应启用');

      playingController.add(false);
      await tester.pumpAndSettle();
      expect(button().onPressed, isNull, reason: 'INV1: 第 2 次暂停应禁用');

      playingController.add(true);
      await tester.pumpAndSettle();
      expect(button().onPressed, isNotNull, reason: 'INV1: 第 3 次播放应启用');
    });
  });
}
