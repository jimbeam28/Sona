// test/features/player/ref_04_superseded_test.dart
// REF-04 (docs/features/REF-04.md §5.4 门禁) — superseded 加载结果不再渲染为
// 错误态：静默合并 + 自动收敛到最新请求。
//
// 覆盖: REF-04-S2 / S3 / S4 / S5 / REF-04-INV1 / REF-04-INV2。
//
//   S2  — 缺陷态（'加载已被新的播放请求替换'）不再出现（INV1: 文案消失）
//   S3  — 外部驱动 superseded（token 仍最新）路径
//   S4  — 对齐 → 直接 ready 且不重发；未对齐 → 保持 loading + 自动重发收敛
//   S5  — loaded/failed 分支行为不变（回归护栏）
//   INV1 — superseded 永不渲染 error；'加载已被新的播放请求替换' 从代码库消失
//   INV2 — 不永久 loading：重发收敛 / 15s UI 超时兜底
//
// 装配风格仿 ply_14_test.dart：ProviderScope + MockAudioPlayer + override
// currentPlayQueueProvider / loadAndPlayProvider。

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:mockito/mockito.dart';
import 'package:nas_audio_player/features/player/player_screen.dart';
import 'package:nas_audio_player/shared/di/providers.dart';
import 'package:nas_audio_player/shared/models/play_queue.dart';

import '../../helpers/mock_audio_player.dart';
import '../../helpers/test_factories.dart';

PlayQueue _queue() => PlayQueue(
      files: [
        testAudio('Test Song.mp3', '/music/Test Song.mp3'),
        testAudio('Song 2.flac', '/music/Song 2.flac'),
      ],
      currentIndex: 0,
    );

/// 基础装配：player 无 source（sequenceState null、processingState idle、
/// playing false）→ postFrame 走 _loadAndPlay → 触发 loadAndPlayProvider。
Widget _buildTestApp({
  required MockAudioPlayer player,
  required PlayQueue queue,
  Future<TrackLoadResult> Function()? loadOverride,
}) {
  return ProviderScope(
    overrides: [
      audioPlayerProvider.overrideWith((ref) => player),
      audioHandlerProvider.overrideWith((ref) => null),
      currentPlayQueueProvider.overrideWith((ref) => queue),
      seekStepSettingProvider.overrideWith((ref) => 15),
      loadAndPlayProvider.overrideWith(
        (ref) => loadOverride ?? () async => const TrackLoadResult.loaded(),
      ),
    ],
    child: const MaterialApp(home: PlayerScreen()),
  );
}

Future<void> _pumpInitial(WidgetTester tester, Widget app) async {
  await tester.pumpWidget(app);
  await tester.pump(); // post-frame callback 触发 _loadAndPlay
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump(const Duration(milliseconds: 100));
}

void main() {
  late MockAudioPlayer player;

  setUp(() {
    player = MockAudioPlayer();
    when(player.playerStateStream)
        .thenAnswer((_) => const Stream<PlayerState>.empty());
    when(player.positionStream).thenAnswer(
        (_) => Stream.value(const Duration(minutes: 1, seconds: 30)));
    when(player.durationStream)
        .thenAnswer((_) => Stream.value(const Duration(minutes: 4)));
    when(player.speedStream).thenAnswer((_) => const Stream<double>.empty());
    when(player.processingStateStream)
        .thenAnswer((_) => const Stream<ProcessingState>.empty());
    when(player.playing).thenReturn(false);
    when(player.processingState).thenReturn(ProcessingState.idle);
    when(player.position).thenReturn(const Duration(seconds: 90));
    when(player.duration).thenReturn(const Duration(minutes: 4));
    when(player.sequenceState).thenReturn(null);
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // REF-04-S2/S4/INV1：未对齐 superseded → 保持 loading + 自动重发收敛到 ready
  // ═══════════════════════════════════════════════════════════════════════════

  group('REF-04-S2/S4: 未对齐 superseded → loading + 重发收敛 ready', () {
    testWidgets('首次 superseded（player 无 source）→ 仍显示加载中，随后重发完成显示 ready',
        (WidgetTester tester) async {
      // 第一次调用返回 superseded，第二次（自动重发）返回 loaded。
      var calls = 0;
      final app = _buildTestApp(
        player: player,
        queue: _queue(),
        loadOverride: () async {
          calls++;
          return calls == 1
              ? const TrackLoadResult.superseded()
              : const TrackLoadResult.loaded();
        },
      );

      await _pumpInitial(tester, app);

      // 未对齐 superseded → 保持 loading（不闪错误态）；自动重发第二次加载完成 → ready。
      expect(find.text('正在加载音频...'), findsNothing,
          reason: '重发已完成后应进入 ready，不再处于加载中');
      expect(find.text('Test Song.mp3'), findsWidgets,
          reason: 'ready 后应显示当前曲目名（AppBar + 正文）');
      expect(calls, 2, reason: '未对齐 superseded 应自动重发一次并收敛');
      // INV1: 缺陷文案不得出现。
      expect(find.text('加载已被新的播放请求替换'), findsNothing);
      expect(find.text('重试'), findsNothing,
          reason: '否定断言: superseded 不得渲染重试按钮路径');
    });

    testWidgets('superseded 期间保持"正在加载音频..."（不闪现错误画面）',
        (WidgetTester tester) async {
      // 用 Completer 控制：第一次调用返回 superseded，第二次（自动重发）
      // 挂起——观察加载态后完成第二次收敛到 ready。
      var calls = 0;
      final second = Completer<TrackLoadResult>();
      final app = _buildTestApp(
        player: player,
        queue: _queue(),
        loadOverride: () {
          calls++;
          if (calls == 1)
            return Future.value(const TrackLoadResult.superseded());
          return second.future;
        },
      );

      await tester.pumpWidget(app);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // superseded 后进入自动重发（第二次请求挂起）→ 保持 loading。
      expect(calls, 2, reason: '第一次返回 superseded 后已触发自动重发');
      expect(find.text('正在加载音频...'), findsOneWidget,
          reason: 'superseded 后保持 loading，不渲染错误画面');
      expect(find.text('加载已被新的播放请求替换'), findsNothing);
      expect(find.text('重试'), findsNothing);

      // 完成第二次重发 → 收敛到 ready。
      second.complete(const TrackLoadResult.loaded());
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));

      expect(calls, 2, reason: '未对齐 superseded 自动重发一次');
      expect(find.text('Test Song.mp3'), findsWidgets, reason: '重发完成后进入 ready');
      expect(find.text('正在加载音频...'), findsNothing);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // REF-04-S4：已对齐 superseded → 直接 ready，不重发
  // ═══════════════════════════════════════════════════════════════════════════

  group('REF-04-S4: 已对齐 superseded → 直接 ready 不重发', () {
    testWidgets('加载期间外部请求已落地（sequenceState 匹配 + ready）→ 直接 ready',
        (WidgetTester tester) async {
      // 首次 _loadAndPlay 之前 sequenceState=null → postFrame 走加载路径；
      // 在加载请求返回 superseded 前，外部请求已落地：把 sequenceState 供成
      // 匹配当前队列的 UriAudioSource + processingState ready。
      final source = AudioSource.uri(
        Uri.parse('http://nas.local:5005/music/Test Song.mp3'),
      );
      final seqState = SequenceState(
        [source],
        0,
        const [],
        false,
        LoopMode.off,
      );

      // 用例内把 player 状态翻转为"已对齐"。
      void setAligned() {
        when(player.sequenceState).thenReturn(seqState);
        when(player.processingState).thenReturn(ProcessingState.ready);
      }

      var calls = 0;
      final app = _buildTestApp(
        player: player,
        queue: _queue(),
        loadOverride: () async {
          calls++;
          // 第二次触发前外部请求已完成（对齐态）。首次加载返回 superseded。
          setAligned();
          return const TrackLoadResult.superseded();
        },
      );

      await _pumpInitial(tester, app);

      expect(calls, 1, reason: '对齐则直接 ready，不得触发第二次加载请求（防闪断）');
      expect(find.text('Test Song.mp3'), findsWidgets,
          reason: '对齐 superseded → ready，显示当前曲目');
      expect(find.text('正在加载音频...'), findsNothing);
      expect(find.text('加载已被新的播放请求替换'), findsNothing);
      expect(find.text('重试'), findsNothing);
    });

    testWidgets('暂停中（processingState ready、playing=false）仍判定对齐 → 直接 ready',
        (WidgetTester tester) async {
      final source = AudioSource.uri(
        Uri.parse('http://nas.local:5005/music/Test Song.mp3'),
      );
      final seqState =
          SequenceState([source], 0, const [], false, LoopMode.off);
      var calls = 0;
      final app = _buildTestApp(
        player: player,
        queue: _queue(),
        loadOverride: () async {
          calls++;
          // 对齐判定只看 processingState != idle，不看 playing。
          when(player.sequenceState).thenReturn(seqState);
          when(player.processingState).thenReturn(ProcessingState.ready);
          when(player.playing).thenReturn(false);
          return const TrackLoadResult.superseded();
        },
      );

      await _pumpInitial(tester, app);

      expect(calls, 1, reason: 'playing=false 不影响对齐判定（不因暂停重发）');
      expect(find.text('Test Song.mp3'), findsWidgets);
      expect(find.text('正在加载音频...'), findsNothing);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // REF-04-S4/INV2：持续打断（每次重发都 superseded）→ 15s UI 超时兜底 error
  // ═══════════════════════════════════════════════════════════════════════════

  group('REF-04-INV2: 持续 superseded 由 15s UI 超时兜底', () {
    testWidgets('重发请求挂起 15s → error(加载超时，请重试)，不永久 loading',
        (WidgetTester tester) async {
      var calls = 0;
      final hang = Completer<TrackLoadResult>();
      final app = _buildTestApp(
        player: player,
        queue: _queue(),
        loadOverride: () async {
          calls++;
          if (calls == 1) return const TrackLoadResult.superseded();
          // 重发后请求挂起（模拟持续被打断的最新请求仍在途）→ 15s UI 超时兜底。
          return hang.future;
        },
      );

      await _pumpInitial(tester, app);

      // 第二次请求挂起中（重发后最新请求）→ 仍在 loading，未闪错误。
      expect(find.text('正在加载音频...'), findsOneWidget,
          reason: '重发请求在途时保持 loading');

      // 推进 15s → UI 超时 → error('加载超时，请重试')。
      await tester.pump(const Duration(seconds: 15));
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('加载超时，请重试'), findsOneWidget,
          reason: 'INV2: 15s UI 超时兜底错误态，不永久 loading');
      expect(find.text('正在加载音频...'), findsNothing, reason: '超时后不得停留在 loading');
      expect(calls, 2);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // REF-04-S5/INV1：loaded 正常路径不变；文案从代码库消失
  // ═══════════════════════════════════════════════════════════════════════════

  group('REF-04-S5/INV1: 正常 loaded 与缺陷文案消失', () {
    testWidgets('loaded 一次成功 → ready，不触发重发', (WidgetTester tester) async {
      var calls = 0;
      final app = _buildTestApp(
        player: player,
        queue: _queue(),
        loadOverride: () async {
          calls++;
          return const TrackLoadResult.loaded();
        },
      );

      await _pumpInitial(tester, app);

      expect(calls, 1);
      expect(find.text('Test Song.mp3'), findsWidgets);
      expect(find.text('正在加载音频...'), findsNothing);
    });

    testWidgets('INV1: 缺陷文案不在任何路径（代码库字符串检查）', (WidgetTester tester) async {
      final source =
          File('lib/features/player/player_screen.dart').readAsStringSync();
      expect(source, isNot(contains('加载已被新的播放请求替换')),
          reason: 'INV1: superseded 错误文案必须从代码库消失');
    });
  });
}
