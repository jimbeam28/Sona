// test/features/player/bug_remove_track_progress_test.dart
// cr-20260804-1922 §5 O2: removeTrack 删除当前曲时进度「张冠李戴」回归测试.
//
// 缺陷：removeTrack(wasCurrent) 原实现先 `queue = newQueue` 再
// `saveProgress()` — 保存时 saveProgress() 读到的 q.current.path 已经是
// **下一曲**，而 player.position 仍是**被删曲目**的位置 → 被删曲目的播放
// 位置被写到下一曲名下，下次播放下一曲会从错误位置恢复。
//
// 参照系：skipToNext / skipToPrevious / selectQueueIndex / 曲目完成监听器
// 全部是「先 saveProgress() 再重赋 queue」。removeTrack 必须与之一致。
//
// 用例：
//   T01: 三曲队列播第 1 曲，removeTrack(当前曲) → 保存的 filePath == 被删曲目
//        且 positionMs == 被删曲目的播放位置；
//        否定断言：下一曲 path 名下不得收到任何保存（不得被污染）。
//   T02: 中间曲目同理（currentIndex=1 删自己）→ 保存归属被删曲目，
//        否定断言：接替的下一曲（song3）名下无记录。
//   T03: 时序一致性对照 — skipToNext 保存离场曲目（参照系行为不变）。
//   T04: 否定面 — 删除非当前曲不触发任何保存。
//
// Player fake 采用 bug_bug19_repro_test.dart 同款手写 Fake：共享的
// helpers/mock_audio_player.dart 保留非空参数签名，`any` matcher 无法静态
// 赋给 setAudioSource(AudioSource)，故不用 Mockito（同 BUG-19 注记）。

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:nas_audio_player/features/player/domain/playback_orchestrator.dart';
import 'package:nas_audio_player/shared/models/connection_config.dart';
import 'package:nas_audio_player/shared/models/play_queue.dart';

import '../../helpers/test_factories.dart';

// ── Recorded upsert call ─────────────────────────────────────────────────────

typedef SaveCall = ({
  int connectionId,
  String filePath,
  int positionMs,
  int? durationMs
});

/// [ProgressSaver] that records every upsert call (BUG-19 suite 同款).
///
/// `calls.add` 是方法体第一条语句（首个 await 之前），同步记录 —
/// saveProgress() 返回时即可断言。
class _RecordingProgressSaver implements ProgressSaver {
  final List<SaveCall> calls = [];

  @override
  Future<void> upsertProgress({
    required int connectionId,
    required String filePath,
    required int positionMs,
    int? durationMs,
  }) async {
    calls.add((
      connectionId: connectionId,
      filePath: filePath,
      positionMs: positionMs,
      durationMs: durationMs,
    ));
  }
}

// ── Hand-written fakes (no build_runner needed) ─────────────────────────────

class _FakeConnectionProvider implements ActiveConnectionProvider {
  final ConnectionConfig? connection;
  _FakeConnectionProvider(this.connection);

  @override
  ConnectionConfig? get currentConnection => connection;

  @override
  Future<ConnectionConfig?> getActiveConnection() async => connection;
}

class _FakePasswordReader implements PasswordReader {
  @override
  Future<String?> readPassword(int connectionId) async => 'secret';
}

class _FakeSpeedProvider implements DefaultSpeedProvider {
  @override
  double getDefaultSpeed() => 1.0;
}

class _FakeQueueConnIdProvider implements QueueConnectionIdProvider {
  @override
  int? getLastQueueConnectionId() => null;
}

/// Minimal fake [AudioPlayer] (bug_bug19_repro_test.dart 同款).
///
/// Unimplemented members throw via [Fake], so any unexpected player access
/// fails the test loudly.
class _FakePlayer extends Fake implements AudioPlayer {
  int setAudioSourceCalls = 0;
  bool playingStub = true;
  Duration positionStub = const Duration(seconds: 42);
  Duration? durationStub = const Duration(minutes: 3);
  StreamController<ProcessingState>? processingController;
  StreamController<PlayerState>? playerStateController;

  @override
  Stream<ProcessingState> get processingStateStream =>
      processingController?.stream ?? const Stream.empty();

  @override
  Stream<PlayerState> get playerStateStream =>
      playerStateController?.stream ?? const Stream.empty();

  @override
  bool get playing => playingStub;

  @override
  Duration get position => positionStub;

  @override
  Duration? get duration => durationStub;

  @override
  Future<Duration?> setAudioSource(AudioSource source,
      {bool preload = true,
      int? initialIndex,
      Duration? initialPosition}) async {
    setAudioSourceCalls++;
    return Duration.zero;
  }

  @override
  Future<void> play() async {}

  @override
  Future<void> pause() async {}

  @override
  Future<void> stop() async {}

  @override
  Future<void> seek(Duration? position, {int? index}) async {}

  @override
  Future<void> setSpeed(double speed) async {}
}

// ── Test environment ─────────────────────────────────────────────────────────

void main() {
  const removedPath = '/music/song1.mp3';
  const nextPath = '/music/song2.mp3';
  const thirdPath = '/music/song3.mp3';
  const removedPosition = Duration(seconds: 42);
  const trackDuration = Duration(minutes: 3);

  final connection = testConfig(id: 1, isActive: true);

  ({
    PlaybackOrchestrator orchestrator,
    _FakePlayer player,
    _RecordingProgressSaver saver,
    StreamController<ProcessingState> processingController,
    StreamController<PlayerState> playerStateController,
  }) createEnv({required List<String> paths, int currentIndex = 0}) {
    // Broadcast controllers so listeners can re-subscribe across loads.
    final processingController = StreamController<ProcessingState>.broadcast();
    final playerStateController = StreamController<PlayerState>.broadcast();

    final player = _FakePlayer()
      ..positionStub = removedPosition
      ..durationStub = trackDuration
      ..processingController = processingController
      ..playerStateController = playerStateController;

    final saver = _RecordingProgressSaver();
    final orchestrator = PlaybackOrchestrator(
      player: player,
      connectionProvider: _FakeConnectionProvider(connection),
      passwordReader: _FakePasswordReader(),
      progressSaver: saver,
      defaultSpeedProvider: _FakeSpeedProvider(),
      queueConnectionIdProvider: _FakeQueueConnIdProvider(),
    );
    orchestrator.queue = PlayQueue(
      files: paths.map((p) => testAudio(p.split('/').last, p)).toList(),
      currentIndex: currentIndex,
    );

    return (
      orchestrator: orchestrator,
      player: player,
      saver: saver,
      processingController: processingController,
      playerStateController: playerStateController,
    );
  }

  // ═════════════════════════════════════════════════════════════════════════
  // T01: 核心用例 — 删当前曲，进度必须记在被删曲目名下
  // ═════════════════════════════════════════════════════════════════════════

  group('O2-T01: removeTrack(current) saves under the REMOVED track', () {
    test('saved filePath/position belong to the removed track', () async {
      final env =
          createEnv(paths: [removedPath, nextPath, thirdPath], currentIndex: 0);
      addTearDown(env.orchestrator.dispose);
      addTearDown(env.processingController.close);
      addTearDown(env.playerStateController.close);

      await env.orchestrator.removeTrack(0);
      await pumpEventQueue(times: 50);

      // 队列推进本身不受影响。
      expect(env.orchestrator.queue!.length, equals(2));
      expect(env.orchestrator.queue!.current.path, equals(nextPath));
      expect(env.player.setAudioSourceCalls, equals(1), reason: '删当前曲后必须加载下一曲');

      // 保存必须发生且仅一次。
      expect(env.saver.calls, hasLength(1), reason: '删当前曲仍需触发一次保存');
      final save = env.saver.calls.single;
      expect(save.connectionId, equals(1));
      expect(save.filePath, equals(removedPath),
          reason: '进度必须记在**被删曲目**名下（缺陷行为：记到下一曲名下）');
      expect(save.positionMs, equals(removedPosition.inMilliseconds),
          reason: '保存的必须是被删曲目的播放位置');
      expect(save.durationMs, equals(trackDuration.inMilliseconds));

      // 否定断言：下一曲 path 名下不得收到任何保存 ——
      // 缺陷代码会把被删曲目的位置写到 song2 名下，污染其进度记录。
      expect(env.saver.calls.where((c) => c.filePath == nextPath), isEmpty,
          reason: '否定面：下一曲的进度记录不得被本次删除操作写入');
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  // T02: 中间曲目同缺陷形态 — 接替曲目（song3）不得被污染
  // ═════════════════════════════════════════════════════════════════════════

  group('O2-T02: removing a middle current track keeps attribution', () {
    test('save targets song2, successor song3 stays untouched', () async {
      final env =
          createEnv(paths: [removedPath, nextPath, thirdPath], currentIndex: 1);
      addTearDown(env.orchestrator.dispose);
      addTearDown(env.processingController.close);
      addTearDown(env.playerStateController.close);

      await env.orchestrator.removeTrack(1);
      await pumpEventQueue(times: 50);

      // withoutIndex(1) 保持 currentIndex=1 → 接替者是 song3。
      expect(env.orchestrator.queue!.current.path, equals(thirdPath));

      expect(env.saver.calls, hasLength(1));
      expect(env.saver.calls.single.filePath, equals(nextPath),
          reason: '被删曲目是 song2，进度必须记在 song2 名下');
      expect(env.saver.calls.single.positionMs,
          equals(removedPosition.inMilliseconds));

      // 否定断言：接替者 song3 名下无记录。
      expect(env.saver.calls.where((c) => c.filePath == thirdPath), isEmpty,
          reason: '否定面：接替曲目 song3 的进度不得被污染');
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  // T03: 时序一致性对照 — skipToNext 保存离场曲目（参照系）
  // ═════════════════════════════════════════════════════════════════════════

  group('O2-T03: reference ordering — skipToNext saves the outgoing track', () {
    test('removeTrack(current) must match this save-before-advance ordering',
        () async {
      final env =
          createEnv(paths: [removedPath, nextPath, thirdPath], currentIndex: 0);
      addTearDown(env.orchestrator.dispose);
      addTearDown(env.processingController.close);
      addTearDown(env.playerStateController.close);

      final result = await env.orchestrator.skipToNext();

      expect(result.isLoaded, isTrue);
      expect(env.saver.calls, hasLength(1));
      expect(env.saver.calls.single.filePath, equals(removedPath),
          reason: '参照系：skipToNext 先保存离场曲目再重赋 queue');
      expect(env.orchestrator.queue!.current.path, equals(nextPath));
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  // T04: 否定面 — 删除非当前曲不产生任何保存
  // ═════════════════════════════════════════════════════════════════════════

  group('O2-T04: removing a non-current track never saves', () {
    test('no upsert is emitted when the removed track is not playing',
        () async {
      final env =
          createEnv(paths: [removedPath, nextPath, thirdPath], currentIndex: 0);
      addTearDown(env.orchestrator.dispose);
      addTearDown(env.processingController.close);
      addTearDown(env.playerStateController.close);

      await env.orchestrator.removeTrack(2);
      await pumpEventQueue(times: 50);

      expect(env.orchestrator.queue!.length, equals(2));
      expect(env.orchestrator.queue!.current.path, equals(removedPath),
          reason: '当前曲不变');
      expect(env.saver.calls, isEmpty, reason: '否定面：删除非当前曲不得触发进度写入');
      expect(env.player.setAudioSourceCalls, equals(0), reason: '不得重新加载');
    });
  });
}
