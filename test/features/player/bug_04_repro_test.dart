// test/features/player/bug_04_repro_test.dart
// BUG-04（cr-20260816-0802 B2）：setMediaItemFromPath 自 D-1 重构后零生产
// 调用方 → 通知栏/锁屏永远无曲名
// （spec: docs/features/BUG-04.md §5.4）
//
// 缺陷：audio_handler.dart:170-178 setMediaItemFromPath 是唯一 MediaItem
// 构造点，但 lib/ 生产代码无任何调用；player_provider.dart:130 是唯一
// mediaItem 写操作且只写 null。加载成功后通知栏 mediaItem 恒为 null →
// 通知栏/锁屏无曲名，_onDurationChanged（audio_handler.dart:162-166）的
// 时长更新也因 mediaItem.value == null 永不生效。
//
// 门禁（修复前必须 FAIL）：
//   T1 加载成功后 handler.mediaItem 必须收到含曲名的 MediaItem
//   T2 队列变更（切歌）后 mediaItem 必须跟随更新
//   T3 队列清空时 mediaItem 保持 null 推送（现有行为不变）

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:mockito/mockito.dart';
import 'package:nas_audio_player/core/services/audio_handler.dart';
import 'package:nas_audio_player/features/browser/browser_provider.dart';
import 'package:nas_audio_player/features/connection/connection_provider.dart';
import 'package:nas_audio_player/features/player/player_provider.dart';
import 'package:nas_audio_player/features/progress/progress_provider.dart';
import 'package:nas_audio_player/features/timer/timer_provider.dart';
import 'package:nas_audio_player/shared/models/connection_config.dart';
import 'package:nas_audio_player/shared/models/play_queue.dart';

import '../../helpers/fake_secure_storage.dart';
import '../../helpers/mock_audio_player.dart';
import '../../helpers/test_factories.dart';

void main() {
  test('BUG-04-T1: 加载成功后通知栏 mediaItem 必须携带曲名', () async {
    final player = MockAudioPlayer();
    when(player.playing).thenReturn(true);
    when(player.positionStream)
        .thenAnswer((_) => Stream.value(const Duration(seconds: 30)));
    when(player.durationStream)
        .thenAnswer((_) => Stream.value(const Duration(minutes: 4)));
    when(player.speedStream).thenAnswer((_) => const Stream<double>.empty());
    when(player.processingStateStream)
        .thenAnswer((_) => const Stream<ProcessingState>.empty());

    final handler = NasAudioHandler(player);
    addTearDown(handler.dispose);

    final container = ProviderContainer(overrides: [
      audioPlayerProvider.overrideWithValue(player),
      audioHandlerProvider.overrideWithValue(handler),
      onTrackCompletedProvider.overrideWithValue(() => false),
      secureStorageProvider
          .overrideWithValue(FakeSecureStorage()..setPassword(1, 'secret')),
      activeConnectionProvider.overrideWith((ref) async => ConnectionConfig(
            id: 1,
            name: 'test',
            url: 'http://localhost:8080',
            username: 'user',
            createdAt: DateTime(2024),
            updatedAt: DateTime(2024),
          )),
      upsertProgressProvider.overrideWithValue((
          {required int connectionId,
          required String filePath,
          required int positionMs,
          int? durationMs}) async {}),
    ]);
    addTearDown(container.dispose);

    container.read(currentPlayQueueProvider.notifier).state = PlayQueue(
      files: [testAudio('Test Song.mp3', '/music/Test Song.mp3')],
      currentIndex: 0,
    );

    final r = await container.read(loadAndPlayProvider)();
    expect(r.isLoaded, isTrue, reason: '前置：加载必须成功');

    expect(handler.mediaItem.value, isNotNull,
        reason: 'BUG-04（cr-20260816-0802 B2）：加载成功后必须推送 mediaItem，'
            '通知栏/锁屏才能显示曲名。当前生产代码唯一 mediaItem 写点是'
            'player_provider.dart:130（只写 null），setMediaItemFromPath'
            '（audio_handler.dart:170-178）零生产调用');
    expect(handler.mediaItem.value!.title, 'Test Song',
        reason: 'mediaItem 标题必须取自当前曲目路径'
            '（extractTitleFromPath → Test Song）');
    expect(handler.mediaItem.value!.id, '/music/Test Song.mp3');
  });

  test('BUG-04-T2: 队列切换后 mediaItem 必须跟随新曲目', () async {
    final player = MockAudioPlayer();
    when(player.playing).thenReturn(true);
    when(player.positionStream)
        .thenAnswer((_) => Stream.value(const Duration(seconds: 30)));
    when(player.durationStream)
        .thenAnswer((_) => Stream.value(const Duration(minutes: 4)));
    when(player.speedStream).thenAnswer((_) => const Stream<double>.empty());
    when(player.processingStateStream)
        .thenAnswer((_) => const Stream<ProcessingState>.empty());

    final handler = NasAudioHandler(player);
    addTearDown(handler.dispose);

    final container = ProviderContainer(overrides: [
      audioPlayerProvider.overrideWithValue(player),
      audioHandlerProvider.overrideWithValue(handler),
      onTrackCompletedProvider.overrideWithValue(() => false),
      secureStorageProvider
          .overrideWithValue(FakeSecureStorage()..setPassword(1, 'secret')),
      activeConnectionProvider.overrideWith((ref) async => ConnectionConfig(
            id: 1,
            name: 'test',
            url: 'http://localhost:8080',
            username: 'user',
            createdAt: DateTime(2024),
            updatedAt: DateTime(2024),
          )),
      upsertProgressProvider.overrideWithValue((
          {required int connectionId,
          required String filePath,
          required int positionMs,
          int? durationMs}) async {}),
    ]);
    addTearDown(container.dispose);

    // 队列经 orchestrator 队列变更回调（player_provider.dart:121-131
    // onQueueChanged）推送 —— 切歌时 mediaItem 必须跟随。
    container.read(currentPlayQueueProvider.notifier).state = PlayQueue(
      files: [
        testAudio('Song A.mp3', '/music/Song A.mp3'),
        testAudio('Song B.flac', '/music/Song B.flac'),
      ],
      currentIndex: 0,
    );
    await container.read(loadAndPlayProvider)();
    expect(handler.mediaItem.value?.title, 'Song A');

    container.read(currentPlayQueueProvider.notifier).state = PlayQueue(
      files: [
        testAudio('Song A.mp3', '/music/Song A.mp3'),
        testAudio('Song B.flac', '/music/Song B.flac'),
      ],
      currentIndex: 1,
    );
    await container.read(loadAndPlayProvider)();
    expect(handler.mediaItem.value?.title, 'Song B',
        reason: 'BUG-04-T2：切到第 2 首后通知栏曲名必须跟随'
            '（cr 修复建议：mini bar/queue 变更时同步更新）');
  });

  test('BUG-04-T3: 队列清空时 mediaItem 推送 null（现有行为不变）', () async {
    final player = MockAudioPlayer();
    when(player.playing).thenReturn(true);
    when(player.positionStream)
        .thenAnswer((_) => Stream.value(const Duration(seconds: 30)));
    when(player.durationStream)
        .thenAnswer((_) => Stream.value(const Duration(minutes: 4)));
    when(player.speedStream).thenAnswer((_) => const Stream<double>.empty());
    when(player.processingStateStream)
        .thenAnswer((_) => const Stream<ProcessingState>.empty());

    final handler = NasAudioHandler(player);
    addTearDown(handler.dispose);

    final container = ProviderContainer(overrides: [
      audioPlayerProvider.overrideWithValue(player),
      audioHandlerProvider.overrideWithValue(handler),
      onTrackCompletedProvider.overrideWithValue(() => false),
      secureStorageProvider
          .overrideWithValue(FakeSecureStorage()..setPassword(1, 'secret')),
      activeConnectionProvider.overrideWith((ref) async => ConnectionConfig(
            id: 1,
            name: 'test',
            url: 'http://localhost:8080',
            username: 'user',
            createdAt: DateTime(2024),
            updatedAt: DateTime(2024),
          )),
      upsertProgressProvider.overrideWithValue((
          {required int connectionId,
          required String filePath,
          required int positionMs,
          int? durationMs}) async {}),
    ]);
    addTearDown(container.dispose);

    container.read(currentPlayQueueProvider.notifier).state = PlayQueue(
      files: [testAudio('Song A.mp3', '/music/Song A.mp3')],
      currentIndex: 0,
    );
    await container.read(loadAndPlayProvider)();
    expect(handler.mediaItem.value, isNotNull);

    // orchestrator 队列置 null（removeTrack 清空路径 → onQueueChanged(null)
    // → player_provider.dart:130 推送 null）。
    container.read(currentPlayQueueProvider.notifier).state = null;
    await pumpEventQueue();
    expect(handler.mediaItem.value, isNull,
        reason: 'BUG-04-T3（否定面）：队列清空后通知栏必须清空曲目信息'
            '（现有 player_provider.dart:130 行为不得被修复破坏）');
  });
}
