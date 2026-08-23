// test/features/player/bug_bug21_completed_seek_test.dart
// BUG-21: 末曲播完（nextIndex==null）分支缺 seek(0)，播放器滞留 completed 态
// —— Android 上进度条拖动无响应，必须先按播放键（P2 部分合规）。
// cr 来源: docs/cr/cr-20260822-2051.md F2
//
// P2 规避条款（docs/dev/platform-pitfalls.md）:
//   "nextIndex == null 分支必须显式 seek(0) + pause()"
//   现状 player_provider.dart:327-331 只有 pause()，无 seek(0)。
//
// 覆盖:
// BUG-21-S1-T01: 单曲队列播完 → completed 处理显式 seek(Duration.zero) + pause
//                （seek 断言修复前 FAIL）
// BUG-21-S2-T01: 否定断言 —— completed 处理不推进队列、不触发加载

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:mockito/mockito.dart';
import 'package:nas_audio_player/shared/di/providers.dart';
import 'package:nas_audio_player/shared/models/nas_file.dart';
import 'package:nas_audio_player/shared/models/play_queue.dart';

import '../../helpers/mock_audio_player.dart';

void main() {
  late MockAudioPlayer player;
  late StreamController<ProcessingState> processingCtrl;
  late ProviderContainer container;

  setUp(() {
    processingCtrl = StreamController<ProcessingState>.broadcast();
    player = MockAudioPlayer();
    when(player.processingStateStream).thenAnswer((_) => processingCtrl.stream);
    when(player.playerStateStream)
        .thenAnswer((_) => const Stream<PlayerState>.empty());
    when(player.playing).thenReturn(false);
    // 生产回调会真实调用这两个方法，必须打桩避免 MissingStubError
    when(player.pause()).thenAnswer((_) async {});
    when(player.seek(any)).thenAnswer((_) async {});

    final queue = PlayQueue(
      files: [NasFile(name: 'a.mp3', path: '/a.mp3', isDirectory: false)],
      currentIndex: 0,
    );
    container = ProviderContainer(overrides: [
      audioPlayerProvider.overrideWithValue(player),
      currentPlayQueueProvider.overrideWith((ref) => queue),
    ]);
  });

  tearDown(() async {
    container.dispose(); // 经 ref.onDispose 取消监听器/定时器（BUG-21 机制）
    await processingCtrl.close();
  });

  group('BUG-21-S1 修复门禁（修复前 FAIL）', () {
    test('BUG-21-S1-T01: 无下一曲的 completed 处理必须 seek(0) + pause', () async {
      container.read(reconnectPlaybackListenersProvider)();
      await Future<void>.delayed(Duration.zero);

      processingCtrl.add(ProcessingState.completed);
      await Future<void>.delayed(Duration.zero);

      // 既有行为：末曲结束显式 pause（P2 第三项，已落实）
      verify(player.pause()).called(1);
      // 修复点断言（P2 第一项）：nq==null 分支必须显式 seek(0)，
      // 使播放器退出 completed 态，进度条拖动在 Android 上恢复可用
      verify(player.seek(Duration.zero)).called(1);
    });
  });

  group('BUG-21-S2 否定断言', () {
    test('BUG-21-S2-T01: completed 处理不推进队列、不触发加载', () async {
      container.read(reconnectPlaybackListenersProvider)();
      await Future<void>.delayed(Duration.zero);

      final before = container.read(currentPlayQueueProvider);
      clearInteractions(player);

      processingCtrl.add(ProcessingState.completed);
      await Future<void>.delayed(Duration.zero);

      expect(container.read(currentPlayQueueProvider), same(before),
          reason: '否定: 无下一曲时队列不得变化');
      // 否定“触发加载”：加载成功路径必以 play 收尾、且队列保持同一对象。
      // （mockito 5 的 any/argThat 静态返回 Null，无法用于强类型 AudioSource 形参）
      verifyNever(player.play());
    });
  });
}
