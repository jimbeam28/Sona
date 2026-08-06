// test/features/browser/test_01_brw11_test.dart
// TEST-01-S7/S8/S9（BRW11 playing 态响应式翻转 + INV4 真实竞态）— widget test
//
// 生产行为说明（与 spec 的差异见文件底部 "spec 偏差" 注释）：
// spec 中的 "playingStateProvider" 在当前生产实现中对应 audioPlayingProvider
// （browser_provider.dart 的 StreamProvider，接线 audioPlayer.playingStream +
// 初始 playing 值）。播放能力图标（"下一曲" queue_music IconButton）的
// onPressed 绑定该 provider：playing=false → onPressed null（禁用），
// playing=true → 非 null（启用）。本文件按生产接线测试响应式翻转（同
// bug_06_playing_stream_test.dart 模式：不 override audioPlayingProvider，
// 用 StreamController 在 build 后驱动 playingStream）。
//
// 覆盖：
//   TEST-01-S7  初始 playing=false → 图标禁用；翻转 true → 启用
//   TEST-01-S8  初始 playing=true → 图标启用；翻转 false → 禁用
//   TEST-01-S9  无进度文件快速连点 5 次 → 播放逻辑（loadAndPlay）仅触发一次

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:just_audio/just_audio.dart';
import 'package:mockito/mockito.dart';
import 'package:nas_audio_player/core/database/dao/progress_dao.dart';
import 'package:nas_audio_player/features/player/player_screen.dart';
import 'package:nas_audio_player/shared/di/providers.dart';
import 'package:nas_audio_player/shared/models/connection_config.dart';
import 'package:nas_audio_player/shared/models/nas_file.dart';
import 'package:nas_audio_player/shared/models/play_progress.dart';
import 'package:nas_audio_player/shared/models/play_queue.dart';

import '../../helpers/fake_secure_storage.dart';
import '../../helpers/mock_audio_player.dart';
import '../../helpers/test_factories.dart';

/// 无进度 DAO fake（onFileTap 查询直接返回 null，走直接播放分支）。
class _NoProgressDao extends ProgressDao {
  @override
  Future<PlayProgress?> find(int connectionId, String filePath) async => null;
}

final _conn = ConnectionConfig(
  id: 1,
  name: 'NAS',
  url: 'http://nas.example.com',
  username: 'admin',
  isActive: true,
  createdAt: DateTime(2026, 1, 1),
  updatedAt: DateTime(2026, 1, 1),
);

void main() {
  group('TEST-01-S7/S8: "下一曲"图标启用态响应 playing 翻转', () {
    late MockAudioPlayer mockPlayer;
    late StreamController<bool> playingController;
    late PlayQueue queue;

    setUp(() {
      mockPlayer = MockAudioPlayer();
      playingController = StreamController<bool>();
      when(mockPlayer.playing).thenReturn(false);
      when(mockPlayer.processingState).thenReturn(ProcessingState.ready);
      when(mockPlayer.processingStateStream)
          .thenAnswer((_) => const Stream<ProcessingState>.empty());
      // 关键：playingStream 接可控 StreamController，build 后逐个发射
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
            // 不 override audioPlayingProvider —— 走生产 StreamProvider 接线
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

    testWidgets('TEST-01-S7: 初始 playing=false 禁用 → 翻转为 true 启用',
        (tester) async {
      await pumpBrowser(tester);

      // 初始 playing=false（stream 未发射事件 → ?? false 兜底）→ 图标禁用
      var button = tester.widget<IconButton>(playNextIconButton());
      expect(button.onPressed, isNull,
          reason: 'S7: 初始 playing=false 时图标 onPressed 应为 null（禁用）');
      expect(button.tooltip, contains('请先开始播放后再用此功能'),
          reason: 'S7: 禁用态 tooltip 应提示先开始播放');

      // 翻转 playing=true（经响应式源 playingStream 驱动，mock 实例不变）
      playingController.add(true);
      await tester.pumpAndSettle();

      button = tester.widget<IconButton>(playNextIconButton());
      expect(button.onPressed, isNotNull,
          reason: 'S7: 翻转为 true 后图标应立即启用（响应 playingStream 变化）');
      expect(button.tooltip, equals('加入下一曲'),
          reason: 'S7: 启用态 tooltip 应为"加入下一曲"');
    });

    testWidgets('TEST-01-S8: 初始 playing=true 启用 → 翻转为 false 禁用',
        (tester) async {
      // 预置 playing=true（模拟 just_audio BehaviorSubject 回放当前值语义）
      playingController.add(true);
      await pumpBrowser(tester);

      var button = tester.widget<IconButton>(playNextIconButton());
      expect(button.onPressed, isNotNull, reason: 'S8: 初始 playing=true 时图标应启用');
      expect(button.tooltip, equals('加入下一曲'));

      // 翻转 playing=false → 立即禁用
      playingController.add(false);
      await tester.pumpAndSettle();

      button = tester.widget<IconButton>(playNextIconButton());
      expect(button.onPressed, isNull,
          reason: 'S8: 翻转为 false 后图标应立即禁用（响应 playingStream 变化）');
      expect(button.tooltip, contains('请先开始播放后再用此功能'));
    });

    testWidgets('TEST-01-S7/S8 否定: 翻转不破坏启用态图标的行为', (tester) async {
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

      // 初始 false → 点击不触发插入
      await tester.tap(playNextIconButton());
      await tester.pumpAndSettle();
      expect(insertCalls, hasLength(0),
          reason: 'S7 否定: playing=false 时点击不得触发插入');

      // 翻转 true → 点击触发一次插入（启用态行为正常）
      playingController.add(true);
      await tester.pumpAndSettle();
      await tester.tap(playNextIconButton());
      await tester.pumpAndSettle();
      expect(insertCalls, hasLength(1),
          reason: 'S7/S8 否定: 翻转后启用态图标应正常触发插入（其他行为不变）');
    });
  });

  group('TEST-01-S9: 无进度文件快速连点 5 次 → 播放逻辑仅触发一次', () {
    late MockAudioPlayer mockPlayer;

    setUp(() {
      mockPlayer = MockAudioPlayer();
      when(mockPlayer.playing).thenReturn(true);
      when(mockPlayer.processingState).thenReturn(ProcessingState.ready);
      when(mockPlayer.processingStateStream)
          .thenAnswer((_) => const Stream<ProcessingState>.empty());
      when(mockPlayer.playingStream)
          .thenAnswer((_) => Stream<bool>.value(true));
      // PlayerScreen 构建所需 getter（同 bug_bug32 INV2-T06 的 stub 集）
      when(mockPlayer.sequenceState).thenReturn(null);
      when(mockPlayer.duration).thenReturn(const Duration(minutes: 4));
      when(mockPlayer.position).thenReturn(Duration.zero);
      when(mockPlayer.playerStateStream).thenAnswer(
          (_) => Stream.value(PlayerState(false, ProcessingState.ready)));
      when(mockPlayer.speedStream).thenAnswer((_) => Stream.value(1.0));
    });

    testWidgets('快速连点 5 次（<100ms 间隔）→ loadAndPlay 仅触发一次', (tester) async {
      int loadAndPlayCalls = 0;

      final router = GoRouter(
        initialLocation: '/',
        routes: [
          GoRoute(
            path: '/',
            builder: (_, __) => const Scaffold(body: BrowserScreen()),
          ),
          GoRoute(
            path: '/player',
            builder: (_, __) => const PlayerScreen(),
          ),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            directoryContentsProvider('/').overrideWith((ref) async => [
                  testAudio('a.mp3', '/music/a.mp3'),
                ]),
            activeConnectionProvider.overrideWith((ref) async => _conn),
            audioPlayerProvider.overrideWithValue(mockPlayer),
            audioHandlerProvider.overrideWith((ref) => null),
            playModeProvider.overrideWith((ref) => PlayMode.sequential),
            seekStepSettingProvider.overrideWith((ref) => 15),
            loadAndPlayProvider.overrideWithValue(() async {
              loadAndPlayCalls++;
              return const TrackLoadResult.loaded();
            }),
            progressDaoProvider.overrideWithValue(_NoProgressDao()),
            secureStorageProvider.overrideWithValue(
                FakeSecureStorage()..setPassword(1, 'secret')),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();

      // 预热 activeConnection（同 bug_13/ply_13：PlayerScreen 的
      // _runSerializedLoad 需 valueOrNull 非空；在同一个容器内读，
      // 避免跨 scope override 不匹配）
      final container =
          ProviderScope.containerOf(tester.element(find.byType(BrowserScreen)));
      await container.read(activeConnectionProvider.future);
      await tester.pump();
      await tester.pumpAndSettle();

      // 限定在 BrowserScreen 内找 tile（/player 压栈后 PlayerScreen 也可能渲染同名文本）
      final tileFinder = find.descendant(
          of: find.byType(BrowserScreen), matching: find.text('a.mp3'));
      expect(tileFinder, findsOneWidget, reason: '前置条件：文件列表已渲染');

      // 快速连点 5 次，每次间隔 10ms（<100ms）
      for (var i = 0; i < 5; i++) {
        await tester.tap(tileFinder);
        await tester.pump(const Duration(milliseconds: 10));
      }
      await tester.pumpAndSettle();

      expect(loadAndPlayCalls, equals(1),
          reason: 'S9: 快速连点 5 次播放逻辑应只触发一次'
              '（SerializedRequestGate 串行化/路由去重）');

      // 否定断言: UI 不冻结——pumpAndSettle 正常完成且仅压入一个播放页
      expect(find.byType(PlayerScreen), findsOneWidget,
          reason: 'S9 否定: 连点后应只有一个播放页实例（异步处理，不阻塞 UI）');
    });
  });
}
