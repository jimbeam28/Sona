// test/features/player/bug_18_stream_wait_test.dart
// BUG-18 门禁测试（spec: docs/features/BUG-18.md §3.1 / §4 / §5.3-5.4）
//
// 缺陷：loadAndPlay 用 60×200ms 轮询等待 player.playing，大 FLAC 经慢速 NAS
// 缓冲超过 12s 即误报加载失败（cr-2026-06-28.md FRAGILE-02）。
// 修复：改为事件驱动等待 player.playerStateStream 发出 playing==true，
// 30s 超时兜底（≥ 原 12s 窗口，spec BUG-18-S1/INV1/INV2）。
//
// 用例：
//   BUG-18-S1a: fast path — player.playing 已为 true → 立即 loaded（不等流事件）
//   BUG-18-S1b: 流在 50ms 发出 playing → 50ms 内 loaded（否定 200ms 轮询间隔）
//   BUG-18-S1c: 流在 16s 发出 playing（> 旧 12s 轮询上限）→ 仍 loaded（U1 慢 NAS）
//   BUG-18-S1d: 流从不发 playing → 13s 仍在等待（INV2）、内层 30s 超时后 stop
//   BUG-18-INV1: 源码扫描 — 旧轮询循环模式不得复活
//
// 修复前（12s 轮询版）：S1b 在 50ms 处断言 FAIL（最早 200ms 才观测到 playing）、
// S1c FAIL（12s 即放弃）、S1d 的 13s 未失败断言 FAIL（12s 已 failed）。
//
// 超时分层说明：loadAndPlay 外层还有 BUG-05 的 SerializedRequestGate 20s
// 任务超时（request_gate.dart），它先于内层 30s 兜底使 loadAndPlay 以
// TimeoutException 结束；内层 30s 超时仍会在其后触发 player.stop() 收尾
// （spec S1 的 stop 语义），S1d 对两者分别断言。

import 'dart:async';
import 'dart:io';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:mockito/mockito.dart';
import 'package:nas_audio_player/features/player/domain/playback_orchestrator.dart';
import 'package:nas_audio_player/features/player/domain/request_gate.dart';
import 'package:nas_audio_player/shared/models/connection_config.dart';
import 'package:nas_audio_player/shared/models/nas_file.dart';
import 'package:nas_audio_player/shared/models/play_queue.dart';

void main() {
  // ── BUG-18-S1a: fast path — 已在播放则立即 loaded ──

  group('BUG-18-S1: stream-based wait (fast path)', () {
    test('player.playing 已为 true → 立即 loaded，空 stream 不阻塞', () {
      FakeAsync().run((async) {
        final env =
            _Env(playing: true, stream: const Stream<PlayerState>.empty());

        TrackLoadStatus? result;
        env.orchestrator.loadAndPlay().then((r) => result = r.status);

        // 不推进任何时间，只 flush 微任务。
        // 否定断言：若无 fast path（只等流事件），空 stream 永不发出
        // playing，30s 内必然 failed —— 立即 loaded 证明走了 fast path。
        async.flushMicrotasks();
        expect(result, equals(TrackLoadStatus.loaded),
            reason: 'BUG-18-S1 边界裁决：player.playing 订阅前已为 true → '
                '立即返回 loaded，不等 stream 事件');
      });
    });
  });

  // ── BUG-18-S1b: 即时响应 — 50ms 内响应流事件（否定 200ms 轮询） ──

  group('BUG-18-S1: stream-based wait (immediate response)', () {
    test('playerStateStream 50ms 发出 playing → 50ms 内 loaded', () {
      FakeAsync().run((async) {
        final controller = StreamController<PlayerState>.broadcast();
        final env = _Env(playing: false, stream: controller.stream);

        TrackLoadStatus? result;
        env.orchestrator.loadAndPlay().then((r) => result = r.status);

        // 推进到 50ms（远小于旧轮询的 200ms 间隔）并发出 playing 事件。
        async.elapse(const Duration(milliseconds: 50));
        controller.add(PlayerState(true, ProcessingState.ready));
        async.flushMicrotasks();

        // 否定断言（INV1）：旧实现每 200ms 才检查一次 player.playing，
        // t=50ms 处不可能 loaded。事件驱动等待必须立即响应。
        expect(result, equals(TrackLoadStatus.loaded),
            reason: 'BUG-18-S1/INV1：收到 playing==true 立即继续，'
                '不得等固定轮询间隔（50ms 内必须完成）');
      });
    });
  });

  // ── BUG-18-S1c: 慢 NAS — 16s 才开始播放（> 旧 12s 上限）仍成功 ──

  group('BUG-18-S1: stream-based wait (slow NAS > 12s)', () {
    test('playerStateStream 16s 发出 playing → loaded（旧 12s 轮询会误报失败）', () {
      FakeAsync().run((async) {
        final controller = StreamController<PlayerState>.broadcast();
        final env = _Env(playing: false, stream: controller.stream);

        TrackLoadStatus? result;
        env.orchestrator.loadAndPlay().then((r) => result = r.status);

        // 大 FLAC 经慢速 NAS 缓冲 16s 才开始播放
        // （选 16s：大于旧 12s 轮询上限，且在外层 gate 20s 任务超时之内）。
        async.elapse(const Duration(seconds: 16));
        expect(result, isNull, reason: '16s 时播放尚未开始，等待必须仍在进行');

        controller.add(PlayerState(true, ProcessingState.ready));
        async.elapse(const Duration(milliseconds: 100));

        // 否定断言：旧实现 12s 即超时 failed；修复后窗口 ≥ 原 12s，
        // 16s 开始的播放必须成功（U1）。
        expect(result, equals(TrackLoadStatus.loaded),
            reason: 'BUG-18 U1：播放开始后正常继续，不因旧 12s 固定窗口失败');
        verifyNever(env.player.stop());
      });
    });
  });

  // ── BUG-18-S1d + INV2: 超时兜底 — 播放永不开始 ──

  group('BUG-18-S1: stream-based wait (timeout fallback)', () {
    test('stream 从不发 playing → 13s 仍等待（INV2）、内层 30s 超时触发 stop', () {
      FakeAsync().run((async) {
        final env =
            _Env(playing: false, stream: const Stream<PlayerState>.empty());

        TrackLoadStatus? result;
        Object? error;
        env.orchestrator.loadAndPlay().then<void>(
          (r) {
            result = r.status;
          },
          onError: (Object e) {
            error = e;
          },
        );

        // INV2：新超时 ≥ 原 12s。13s 处必须仍在等待（旧 12s 轮询早已 failed），
        // 且不得已触发 stop。
        async.elapse(const Duration(seconds: 13));
        expect(result, isNull, reason: '13s 处加载必须仍在进行');
        expect(error, isNull, reason: '13s 处不得有任何错误');
        verifyNever(env.player.stop());

        // t=20s：外层 BUG-05 gate 任务超时先于内层 30s 兜底结束请求。
        async.elapse(const Duration(seconds: 7));
        expect(error, isA<TimeoutException>(),
            reason: '外层 SerializedRequestGate 20s 任务超时（BUG-05 行为，'
                '非本 spec 断言对象，仅说明分层）');
        verifyNever(env.player.stop());

        // t=31s：内层 30s stream 等待超时 → stop 收尾（spec S1 的 stop 语义，
        // 证明内层超时未被缩短为 < 30s 的值）。
        async.elapse(const Duration(seconds: 11));
        verify(env.player.stop()).called(1);
        expect(result, isNull, reason: '内层 failed 结果被 gate 超时掩盖，不得重复产生结果');
      });
    });
  });

  // ── BUG-18-INV1: 源码扫描 — 旧轮询循环不得复活 ──

  group('BUG-18-INV1: 等待机制不依赖固定轮询间隔', () {
    test('playback_orchestrator 不含旧 60×200ms 轮询循环', () {
      final src = File('lib/features/player/domain/playback_orchestrator.dart')
          .readAsStringSync();
      expect(src.contains('for (int i = 0; i < 60'), isFalse,
          reason: '否定断言：不得使用 for 循环 + Future.delayed 轮询 '
              'player.playing（BUG-18 修复前的行为）');
      expect(src, contains('playerStateStream.listen'),
          reason: 'BUG-18-INV1：等待必须基于 playerStateStream 事件驱动');
    });
  });
}

// ═══════════════════════════════════════════════════════════════════════════
// Helpers（与 aud_02_boundary_test.dart 同型的轻量 mock，避免 build_runner）
// ═══════════════════════════════════════════════════════════════════════════

class _LenientMockPlayer extends Mock implements AudioPlayer {
  @override
  Stream<PlayerState> get playerStateStream =>
      super.noSuchMethod(Invocation.getter(#playerStateStream),
              returnValue: Stream<PlayerState>.empty(),
              returnValueForMissingStub: Stream<PlayerState>.empty())
          as Stream<PlayerState>;

  @override
  bool get playing => super.noSuchMethod(Invocation.getter(#playing),
      returnValue: false, returnValueForMissingStub: false) as bool;

  @override
  Duration get position => super.noSuchMethod(Invocation.getter(#position),
      returnValue: Duration.zero,
      returnValueForMissingStub: Duration.zero) as Duration;

  @override
  Future<Duration?> setAudioSource(AudioSource source,
          {bool preload = true,
          int? initialIndex,
          Duration? initialPosition}) =>
      super.noSuchMethod(
              Invocation.method(#setAudioSource, [
                source
              ], {
                #preload: preload,
                if (initialIndex != null) #initialIndex: initialIndex,
                if (initialPosition != null) #initialPosition: initialPosition,
              }),
              returnValue: Future<Duration?>.value(),
              returnValueForMissingStub: Future<Duration?>.value())
          as Future<Duration?>;

  @override
  Future<void> play() => super.noSuchMethod(Invocation.method(#play, []),
      returnValue: Future<void>.value(),
      returnValueForMissingStub: Future<void>.value()) as Future<void>;

  @override
  Future<void> pause() => super.noSuchMethod(Invocation.method(#pause, []),
      returnValue: Future<void>.value(),
      returnValueForMissingStub: Future<void>.value()) as Future<void>;

  @override
  Future<void> stop() => super.noSuchMethod(Invocation.method(#stop, []),
      returnValue: Future<void>.value(),
      returnValueForMissingStub: Future<void>.value()) as Future<void>;

  @override
  Future<void> seek(Duration? position, {int? index}) => super.noSuchMethod(
      Invocation.method(#seek, [position], {if (index != null) #index: index}),
      returnValue: Future<void>.value(),
      returnValueForMissingStub: Future<void>.value()) as Future<void>;

  @override
  Future<void> setSpeed(double speed) =>
      super.noSuchMethod(Invocation.method(#setSpeed, [speed]),
          returnValue: Future<void>.value(),
          returnValueForMissingStub: Future<void>.value()) as Future<void>;
}

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
  int? getLastQueueConnectionId() => 1;
}

/// 组装一个依赖全部打桩的 orchestrator；[playing] / [stream] 控制等待阶段。
class _Env {
  final _LenientMockPlayer player;
  final PlaybackOrchestrator orchestrator;

  _Env._(this.player, this.orchestrator);

  factory _Env({required bool playing, required Stream<PlayerState> stream}) {
    final player = _LenientMockPlayer();
    when(player.playing).thenReturn(playing);
    when(player.playerStateStream).thenAnswer((_) => stream);

    final orchestrator = PlaybackOrchestrator(
      player: player,
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
    orchestrator.queue = PlayQueue(
      files: [
        NasFile(name: 'song.mp3', path: '/music/song.mp3', isDirectory: false)
      ],
      currentIndex: 0,
    );
    return _Env._(player, orchestrator);
  }
}
