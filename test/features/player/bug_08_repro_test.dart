// test/features/player/bug_08_repro_test.dart
// BUG-08（cr-20260816-0802 F4）：IAudioPlayer 路径缺 5s 平台调用兜底 ——
// gate 超时后任务继续执行 → UI 报错的同时 ghost 播放且无内层收尾
// （spec: docs/features/BUG-08.md §5.4）
//
// 缺陷：audio_player_adapter.dart:59-75 六动作直传无 timeout（P17 分层表
// 的 5s 平台层只在 audio_handler.dart 六方法存在；loadAndPlay 走 IAudioPlayer
// 通道无兜底）。playback_orchestrator.dart:191-209：setAudioSource 挂起
// >20s → gate 20s 超时抛错（UI 已报"加载超时"）→ 任务继续 → 晚到完成 →
// isLatest 仍 true → play() → ghost 播放，无任何 stop 收尾。
//
// 门禁（修复前必须 FAIL）：
//   T1 AudioPlayerAdapter.setAudioSource 挂起必须 5s 内超时（P17 对齐）
//   T2 adapter.seek 挂起必须 5s 内返回且不抛错（吞错语义，restore 路径安全）
//   T3 orchestrator（经真实 adapter）setAudioSource 挂起 → 5s 内 failed、
//      绝不 play（无 ghost）

import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:nas_audio_player/core/contracts/audio_player_contract.dart';
import 'package:nas_audio_player/core/services/audio_player_adapter.dart';
import 'package:nas_audio_player/features/player/domain/playback_orchestrator.dart';
import 'package:nas_audio_player/features/player/domain/request_gate.dart';
import 'package:nas_audio_player/shared/models/connection_config.dart';
import 'package:nas_audio_player/shared/models/nas_file.dart';
import 'package:nas_audio_player/shared/models/play_queue.dart';

/// 手写 fake：setAudioSource 可挂起可控释放；记录 play 调用次数。
class _HangingPlayer extends Fake implements AudioPlayer, IAudioPlayer {
  Completer<Duration?>? hang;
  Completer<void>? seekHang;
  int playCalls = 0;
  int pauseCalls = 0;
  int stopCalls = 0;

  @override
  Stream<PlayerState> get playerStateStream => const Stream.empty();

  @override
  Stream<Duration> get positionStream => Stream.value(Duration.zero);

  @override
  Stream<Duration?> get durationStream => const Stream.empty();

  @override
  bool get playing => false;

  @override
  Duration get position => Duration.zero;

  @override
  Duration? get duration => null;

  @override
  Future<Duration?> setAudioSource(AudioSource source,
      {bool preload = true, int? initialIndex, Duration? initialPosition}) {
    final h = hang;
    if (h != null) return h.future;
    return Future.value(Duration.zero);
  }

  @override
  Future<void> play() async {
    playCalls++;
  }

  @override
  Future<void> pause() async {
    pauseCalls++;
  }

  @override
  Future<void> stop() async {
    stopCalls++;
  }

  @override
  Future<void> seek(Duration? position, {int? index}) async {
    final h = seekHang;
    if (h != null) return h.future;
  }

  @override
  Future<void> setSpeed(double speed) async {}

  @override
  Future<void> dispose() async {}
}

void main() {
  test('BUG-08-T1: adapter.setAudioSource 挂起必须 5s 内超时（P17 对齐）', () {
    FakeAsync().run((async) {
      final player = _HangingPlayer()..hang = Completer<Duration?>();
      final adapter = AudioPlayerAdapter(player);

      Object? err;
      var state = 'pending';
      adapter
          .setAudioSource(
              AudioSource.uri(Uri.parse('http://localhost:8080/a.mp3')))
          .then((d) {
        state = 'done';
      }, onError: (Object e) {
        err = e;
        state = 'error';
      });

      async.elapse(const Duration(seconds: 6));
      expect(state, 'error',
          reason: 'BUG-08（cr-20260816-0802 F4）：IAudioPlayer 六动作直传'
              '无超时（audio_player_adapter.dart:59-75）。P17 分层表 5s 平台层'
              '必须在 IAudioPlayer 通道同样存在：挂起 6s 仍 pending = 缺陷');
      expect(err, isA<TimeoutException>(),
          reason: 'setAudioSource 超时必须以异常结束（orchestrator catch → '
              'failed，杜绝 ghost 播放）');
    });
  });

  test('BUG-08-T2: adapter.seek 挂起必须 5s 内返回且不抛错（吞错语义）', () {
    FakeAsync().run((async) {
      final player = _HangingPlayer()..seekHang = Completer<void>();
      final adapter = AudioPlayerAdapter(player);

      Object? err;
      var state = 'pending';
      adapter.seek(const Duration(seconds: 30)).then((_) {
        state = 'done';
      }, onError: (Object e) {
        err = e;
        state = 'error';
      });

      async.elapse(const Duration(seconds: 6));
      expect(state, 'done',
          reason: 'BUG-08-T2：seek 超时按 audio_handler 六方法同款裁决静默返回'
              '（P4 平台调用失败不冒泡）——restoreStartupProgressProvider'
              '（player_provider.dart:237）的 seek 不在 try 内，抛错即 unhandled');
      expect(err, isNull, reason: 'seek 不得抛错');
    });
  });

  test('BUG-08-T3: orchestrator 经真实 adapter：挂起 5s 内 failed，绝不 ghost play', () {
    FakeAsync().run((async) {
      final player = _HangingPlayer()..hang = Completer<Duration?>();
      final orchestrator = PlaybackOrchestrator(
        player: AudioPlayerAdapter(player),
        connectionProvider: _StubConnectionProvider(ConnectionConfig(
          id: 1,
          name: 'test',
          url: 'http://localhost:8080',
          username: 'user',
          createdAt: DateTime(2024),
          updatedAt: DateTime(2024),
        )),
        passwordReader: _StubPasswordReader(),
        progressSaver: _StubProgressSaver(),
        defaultSpeedProvider: _StubSpeedProvider(),
        queueConnectionIdProvider: _StubQueueConnIdProvider(),
      );
      addTearDown(orchestrator.dispose);
      orchestrator.queue = PlayQueue(
        files: [
          const NasFile(
              name: 'song.mp3', path: '/music/song.mp3', isDirectory: false)
        ],
        currentIndex: 0,
      );

      Object? err;
      TrackLoadStatus? result;
      orchestrator.loadAndPlay().then<void>(
            (r) => result = r.status,
            onError: (Object e) => err = e,
          );

      // t=7s：adapter 5s 超时 → catch → failed（gate 不再需要 20s）。
      async.elapse(const Duration(seconds: 7));
      expect(result, TrackLoadStatus.failed,
          reason: 'BUG-08-T3：setAudioSource 挂起必须 5s 内 failed（P17 分层：'
              '平台调用 5s < 加载 gate 20s），不得等到 gate 20s 超时抛错');
      expect(err, isNull, reason: '5s 兜底后结果应是正常 failed 而非异常');
      expect(player.playCalls, 0,
          reason: '加载失败路径不得触发 play（ghost 播放面，cr-20260816-0802 '
              'F4 复现路径第 4 步）');

      // 释放挂起（模拟平台晚到完成）→ 仍不得 play。
      player.hang!.complete(Duration.zero);
      async.flushMicrotasks();
      expect(player.playCalls, 0,
          reason: '晚到的 setAudioSource 完成后任务已失败收尾，不得补 play');
    });
  });
}

// ── orchestrator 依赖桩（bug_18 同型）───────────────────────────────────────

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
