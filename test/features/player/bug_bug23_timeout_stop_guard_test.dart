// test/features/player/bug_bug23_timeout_stop_guard_test.dart
// BUG-23 门禁测试（来源 cr-20260823-1421.md F1，复核分流 2026-08-23）。
//
// 缺陷：PlaybackOrchestrator.loadAndPlay 内层 30s completer 超时兜底
// （playback_orchestrator.dart:229-231）直接 `await player.stop()`，
// 无 `_gate.isLatest(requestId)` 时效守卫。gate 20s 超时释放后任务仍在跑，
// 若用户重试触发新请求 B，旧任务 A 在自身 30s 截止处的 stop() 会打断 B 的
// 加载现场。对照同文件 removeTrack BUG-27-S1 确立的约定："stop 前必须
// beginRequest 使 in-flight 任务失效"。
//
// 场景（cr F1 条件化复现的确定性收缩）：
//   t=0    请求 A 启动，playerStateStream 从不发 playing → A 挂在 play-wait
//   t=20s  gate 超时 → futureA 抛 TimeoutException（P17 外层语义，保留）
//   t=20s+ 请求 B 启动（gate 已空闲），mock setAudioSource 立即完成 → B 进入 play-wait
//   t=30s  A 内层 completer 超时
//          期望：A 不调用 player.stop()（B 是 latest）
//          实际（修复前）：无条件 stop() → 本测试 FAIL
//   t=31s  stream 发出 playing=true → B 正常 loaded
//
// INV 锚定（BUG-23-INV1）：共享 AudioPlayer 的任何 stop 收尾动作执行前
// 必须确认自己仍是 gate 的 latest 请求（removeTrack BUG-27-S1 同款纪律）。

import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:mockito/mockito.dart';
import 'package:nas_audio_player/core/contracts/audio_player_contract.dart';
import 'package:nas_audio_player/features/player/domain/playback_orchestrator.dart';
import 'package:nas_audio_player/features/player/domain/request_gate.dart';
import 'package:nas_audio_player/shared/models/connection_config.dart';
import 'package:nas_audio_player/shared/models/nas_file.dart';
import 'package:nas_audio_player/shared/models/play_queue.dart';

import '../../helpers/mock_audio_player.dart';

// ── Stubs（bug_18_stream_wait_test 同型）─────────────────────────────────────

class _StubConnectionProvider implements ActiveConnectionProvider {
  final ConnectionConfig? connection;
  _StubConnectionProvider(this.connection);

  @override
  Future<ConnectionConfig?> getActiveConnection() async => connection;

  @override
  ConnectionConfig? get currentConnection => connection;
}

class _StubPasswordReader implements PasswordReader {
  @override
  Future<String?> readPassword(int connectionId) async => 'secret';
}

class _StubProgressSaver implements ProgressSaver {
  @override
  Future<void> upsertProgress({
    required int connectionId,
    required String filePath,
    required int positionMs,
    int? durationMs,
  }) async {}
}

class _StubSpeedProvider implements DefaultSpeedProvider {
  @override
  double getDefaultSpeed() => 1.0;
}

class _StubQueueConnIdProvider implements QueueConnectionIdProvider {
  @override
  int? getLastQueueConnectionId() => null;
}

void main() {
  test('BUG-23-S1: 被取代的超时任务在 30s 兜底处不得 stop 后继请求的加载现场', () {
    fakeAsync((async) {
      final player = MockAudioPlayer();
      final stateCtrl = StreamController<PlayerState>();
      // 门禁自修（dev-exe 2026-08-23，非改断言）：A/B 两请求先后订阅同一
      // mock 流，单订阅 stream 二次 listen 抛 'already been listened to'
      // → 被 orchestrator catch 吞为 failed。广播视图必须只建一次
      // （getter 内每次 asBroadcastStream() 会各自包装同一单订阅源）。
      // （修复前该路径不可达：旧实现在下方 verifyNever(stop) 处先失败。）
      final stateStream = stateCtrl.stream.asBroadcastStream();
      when(player.playerStateStream).thenAnswer((_) => stateStream);

      final orch = PlaybackOrchestrator(
        player: player,
        connectionProvider: _StubConnectionProvider(_conn()),
        passwordReader: _StubPasswordReader(),
        progressSaver: _StubProgressSaver(),
        defaultSpeedProvider: _StubSpeedProvider(),
        queueConnectionIdProvider: _StubQueueConnIdProvider(),
      );
      orch.queue = PlayQueue(files: [
        NasFile(
            name: 'a.mp3',
            path: '/a.mp3',
            isDirectory: false,
            audioType: AudioFileType.music),
        NasFile(
            name: 'b.mp3',
            path: '/b.mp3',
            isDirectory: false,
            audioType: AudioFileType.music),
      ], currentIndex: 0);

      // ── 请求 A ──
      Object? errorA;
      final futureA = orch.loadAndPlay();
      futureA.then((_) {}, onError: (Object e, StackTrace _) {
        errorA = e;
      });

      // t=20s：gate 超时释放（外层语义保留，A 的公开 future 以 TimeoutException 结束）
      async.elapse(const Duration(seconds: 20));
      expect(errorA, isA<TimeoutException>(),
          reason: '前置条件：gate 20s 必须先把 TimeoutException 抛给调用方'
              '（P17 分层表外层语义）');

      // ── 请求 B（gate 已空闲，立即运行；setAudioSource mock 立即完成）──
      TrackLoadResult? resultB;
      final futureB = orch.loadAndPlay();
      futureB.then((r) {
        resultB = r;
      }, onError: (Object e, StackTrace _) {});

      // t=30s：A 的内层 30s completer 超时。
      // 期望：A 已被 B 取代 → 不得触碰共享 player（不 stop）。
      async.elapse(const Duration(seconds: 10));
      verifyNever(player.stop());

      // t=31s：playing=true 到达 → B 正常 loaded（B 的加载现场未被破坏）。
      stateCtrl.add(PlayerState(true, ProcessingState.ready));
      async.elapse(const Duration(milliseconds: 100));
      expect(resultB, isNotNull);
      expect(resultB!.isLoaded, isTrue, reason: '后继请求 B 必须正常完成加载');

      // 全程否定断言：整个交错窗口内 stop() 零调用。
      verifyNever(player.stop());
      stateCtrl.close();
    });
  });
}

ConnectionConfig _conn() {
  final now = DateTime.now();
  return ConnectionConfig(
    id: 1,
    name: 'nas',
    url: 'http://192.168.1.50:5005',
    username: 'admin',
    basePath: '/',
    isActive: true,
    createdAt: now,
    updatedAt: now,
  );
}
