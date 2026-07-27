// test/features/browser/brw_09_test.dart
// BRW-09: 文件列表"下一曲播放"图标 — Browser UI widget 测试
//
// Agent A — 测试先行。只读 spec/docs，禁读 lib/。
// 覆盖 BRW-09-S1, S2, S4 (步骤4 SnackBar), S7 (连点 3 次 SnackBar 3 次),
// S9, INV4 (UI 端无 race)。
//
// 测试当前必然 FAIL（实现不存在），但断言逻辑完整可执行。

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
  group('BRW-09: Browser UI — 下一曲播放图标', () {
    late MockAudioPlayer mockPlayer;
    late PlayQueue queue;

    setUp(() {
      mockPlayer = MockAudioPlayer();
      when(mockPlayer.playing).thenReturn(true);
      when(mockPlayer.processingState).thenReturn(ProcessingState.ready);
      when(mockPlayer.processingStateStream)
          .thenAnswer((_) => Stream<ProcessingState>.empty());
      when(mockPlayer.playingStream)
          .thenAnswer((_) => Stream<bool>.value(true));

      queue = PlayQueue(
        files: [
          testAudio('track_01.mp3', '/music/track_01.mp3'),
          testAudio('track_02.mp3', '/music/track_02.mp3'),
          testAudio('track_03.mp3', '/music/track_03.mp3'),
        ],
        currentIndex: 0,
      );
    });

    Future<void> pumpBrowser(
      WidgetTester tester, {
      List<NasFile> files = const [],
      List<Override> extraOverrides = const [],
    }) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            directoryContentsProvider('/').overrideWith((ref) async => files),
            audioPlayerProvider.overrideWithValue(mockPlayer),
            currentPlayQueueProvider.overrideWith((ref) => queue),
            playModeProvider.overrideWith((ref) => PlayMode.sequential),
            ...extraOverrides,
          ],
          child: const MaterialApp(home: Scaffold(body: BrowserScreen())),
        ),
      );
      await tester.pumpAndSettle();
    }

    // ── S1: 音乐文件 tile 右侧出现"下一曲"图标 ──────────────────────────
    testWidgets('BRW-09-S1: 每个音频 tile 右侧渲染 Icons.queue_music 图标按钮',
        (WidgetTester tester) async {
      await pumpBrowser(
        tester,
        files: [
          testAudio('song_a.mp3', '/music/song_a.mp3'),
          testAudio('song_b.mp3', '/music/song_b.mp3'),
        ],
      );

      // 至少出现 2 个 queue_music 图标（一个 tile 一个）
      expect(find.byIcon(Icons.queue_music), findsNWidgets(2),
          reason: 'S1: 每个音频文件 tile 右侧应有"下一曲"图标');
      // 是 IconButton 包装
      expect(
          find.ancestor(
              of: find.byIcon(Icons.queue_music),
              matching: find.byType(IconButton)),
          findsNWidgets(2),
          reason: 'S1: 下一曲图标应是可点击的 IconButton');
    });

    // ── S2: player.playing=false 时图标 disabled，tooltip 用户提示 ────────
    testWidgets('BRW-09-S2: playing=false 时"下一曲"图标 disabled 且 tooltip 显示提示',
        (WidgetTester tester) async {
      when(mockPlayer.playing).thenReturn(false);
      when(mockPlayer.playingStream)
          .thenAnswer((_) => Stream<bool>.value(false));

      await pumpBrowser(
        tester,
        files: [testAudio('song.mp3', '/music/song.mp3')],
      );

      final iconButtonFinder = find.ancestor(
          of: find.byIcon(Icons.queue_music),
          matching: find.byType(IconButton));
      expect(iconButtonFinder, findsOneWidget);

      final button = tester.widget<IconButton>(iconButtonFinder);
      expect(button.onPressed, isNull,
          reason:
              'S2: playing=false 时 IconButton.onPressed == null (disabled)');
      // tooltip 包含用户文案
      final tooltip = button.tooltip;
      expect(tooltip, isNotNull);
      expect(tooltip!.contains('请先开始播放后再用此功能'), isTrue,
          reason: 'S2: disabled 状态 tooltip 应包含"请先开始播放后再用此功能"');
    });

    // S2 第二条件 — currentPlayQueue == null 时也 disabled
    testWidgets('BRW-09-S2: currentPlayQueue == null 时图标 disabled',
        (WidgetTester tester) async {
      when(mockPlayer.playing).thenReturn(true);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            directoryContentsProvider('/').overrideWith(
                (ref) async => [testAudio('song.mp3', '/music/song.mp3')]),
            audioPlayerProvider.overrideWithValue(mockPlayer),
            currentPlayQueueProvider.overrideWith((ref) => null),
            playModeProvider.overrideWith((ref) => PlayMode.sequential),
          ],
          child: const MaterialApp(home: Scaffold(body: BrowserScreen())),
        ),
      );
      await tester.pumpAndSettle();

      final iconButtonFinder = find.ancestor(
          of: find.byIcon(Icons.queue_music),
          matching: find.byType(IconButton));
      expect(iconButtonFinder, findsOneWidget);
      final button = tester.widget<IconButton>(iconButtonFinder);
      expect(button.onPressed, isNull,
          reason: 'S2: currentPlayQueue==null 时 IconButton 应 disabled');
      expect(button.tooltip, isNotNull);
      expect(button.tooltip!.contains('请先开始播放后再用此功能'), isTrue);
    });

    // ── S4 步骤4: 点击"下一曲"图标 → SnackBar"已加入下一曲：Y" ──────────
    testWidgets('BRW-09-S4 step4: 点击"下一曲"图标弹 SnackBar "已加入下一曲：Y"',
        (WidgetTester tester) async {
      await pumpBrowser(
        tester,
        files: [
          testAudio('song_a.mp3', '/music/song_a.mp3'),
          testAudio('song_b.mp3', '/music/song_b.mp3'),
        ],
      );

      // 点击第二个 tile 的"下一曲"图标
      final iconButtons = find.ancestor(
          of: find.byIcon(Icons.queue_music),
          matching: find.byType(IconButton));
      expect(iconButtons, findsNWidgets(2));

      await tester.tap(iconButtons.at(1));
      await tester.pumpAndSettle();

      // SnackBar 出现且文案对
      expect(
          find.descendant(
              of: find.byType(SnackBar),
              matching: find.textContaining('已加入下一曲')),
          findsOneWidget,
          reason: 'S4 step4: 点击后应弹"已加入下一曲" SnackBar');
      expect(
          find.descendant(
              of: find.byType(SnackBar),
              matching: find.textContaining('song_b.mp3')),
          findsOneWidget,
          reason: 'S4 step4: SnackBar 中应包含被点击的文件名');
    });

    // ── S7: 同一首 Y 连点 3 次 → SnackBar 弹 3 次 ──────────────────────
    testWidgets('BRW-09-S7: 同一首 Y 连点"下一曲"图标 3 次 → SnackBar 出现 3 次',
        (WidgetTester tester) async {
      await pumpBrowser(
        tester,
        files: [testAudio('song.mp3', '/music/song.mp3')],
      );

      final iconButtonFinder = find.ancestor(
          of: find.byIcon(Icons.queue_music),
          matching: find.byType(IconButton));
      expect(iconButtonFinder, findsOneWidget);

      // 每次点击前先用 ScaffoldMessengerState 清掉已有 SnackBar，
      // 用 SnackBar 总文案出现的次数累计统计。
      int snackCount = 0;
      for (var i = 0; i < 3; i++) {
        final smState = tester
            .state<ScaffoldMessengerState>(find.byType(ScaffoldMessenger));
        smState.hideCurrentSnackBar();
        await tester.pumpAndSettle();

        final before = find.byType(SnackBar).evaluate().length;
        await tester.tap(iconButtonFinder);
        await tester.pumpAndSettle();
        final after = find.byType(SnackBar).evaluate().length;
        if (after > before) snackCount++;
      }

      expect(snackCount, equals(3), reason: 'S7: 同一首 Y 连点 3 次，SnackBar 应弹 3 次');

      // 文案仍包含文件名
      expect(find.textContaining('已加入下一曲'), findsOneWidget);
    });

    // ── S9: playing=false 时点击不应触发 insertAfterCurrent ──────────────
    testWidgets(
        'BRW-09-S9: player.playing=false 时点击"下一曲"图表不触发 insertAfterCurrent 且 currentPlayQueueProvider 不变',
        (WidgetTester tester) async {
      when(mockPlayer.playing).thenReturn(false);
      when(mockPlayer.playingStream)
          .thenAnswer((_) => Stream<bool>.value(false));

      // 用一个独立的 state holder 监听 currentPlayQueueProvider 是否变化
      PlayQueue? emittedQueue = queue;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            directoryContentsProvider('/').overrideWith(
                (ref) async => [testAudio('song.mp3', '/music/song.mp3')]),
            audioPlayerProvider.overrideWithValue(mockPlayer),
            currentPlayQueueProvider.overrideWith((ref) {
              // 通过 override 创建一个 listener 把状态读到 emittedQueue
              return emittedQueue;
            }),
            playModeProvider.overrideWith((ref) => PlayMode.sequential),
          ],
          child: const MaterialApp(home: Scaffold(body: BrowserScreen())),
        ),
      );
      await tester.pumpAndSettle();

      // 按钮应 disabled
      final iconButtonFinder = find.ancestor(
          of: find.byIcon(Icons.queue_music),
          matching: find.byType(IconButton));
      expect(iconButtonFinder, findsOneWidget);
      final button = tester.widget<IconButton>(iconButtonFinder);
      expect(button.onPressed, isNull,
          reason: 'S9: playing=false 时按钮 disabled');

      // 尝试 tap —— Flutter 对 disabled 的 IconButton tap 会被忽略无回调
      await tester.tap(iconButtonFinder);
      await tester.pumpAndSettle();

      // 队列不变（无 insert）
      final container =
          ProviderScope.containerOf(tester.element(find.byType(BrowserScreen)));
      final q = container.read(currentPlayQueueProvider);
      expect(q, isNotNull);
      expect(q!.length, equals(3), reason: 'S9: 队列长度未变（未触发 insert）');
      expect(q.files[0].path, equals('/music/track_01.mp3'));
      expect(q.files[1].path, equals('/music/track_02.mp3'));
      expect(q.files[2].path, equals('/music/track_03.mp3'));
      expect(q.currentIndex, equals(0));

      // 不应弹出 SnackBar
      expect(find.byType(SnackBar), findsNothing,
          reason: 'S9 playing=false 不触发任何用户可见反馈');
    });

    // ── INV4 (UI 端): 多次连点同一首图标也应每次都 insertAfterCurrent，
    // 不会因按钮上短暂"已点击"状态丢失引发 race。此处通过连续点击多次
    // + 验证队列长度不断增加来验证无 race 丢点。
    testWidgets('BRW-09-INV4 (UI): 连点同一首 3 次，队列连续 +3 无点丢',
        (WidgetTester tester) async {
      await pumpBrowser(
        tester,
        files: [testAudio('song.mp3', '/music/song.mp3')],
      );

      final iconButtonFinder = find.ancestor(
          of: find.byIcon(Icons.queue_music),
          matching: find.byType(IconButton));
      expect(iconButtonFinder, findsOneWidget);

      // 连点 3 次，每次都 pump 一下让 SnackBar 排队显示/隐藏
      for (var i = 0; i < 3; i++) {
        await tester.tap(iconButtonFinder);
        await tester.pump(const Duration(milliseconds: 50));
      }
      await tester.pumpAndSettle();

      // 队列应增加 3 个 song.mp3 副本
      final container =
          ProviderScope.containerOf(tester.element(find.byType(BrowserScreen)));
      final q = container.read(currentPlayQueueProvider);
      expect(q, isNotNull);
      expect(q!.length, equals(3 + 3), reason: 'INV4: 连点 3 次后队列长度应 +3');
      final songCount =
          q.files.where((f) => f.path == '/music/song.mp3').length;
      expect(songCount, equals(3),
          reason: 'INV4: queue 原本不含 song.mp3，3 次插入 → 3 个 song.mp3 副本');
      expect(q.currentIndex, equals(0),
          reason: 'INV4: 连点过程中 currentIndex 不变（不变量保持）');
    });
  });
}
