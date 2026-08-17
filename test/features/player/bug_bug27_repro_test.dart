// test/features/player/bug_bug27_repro_test.dart
// BUG-27: 播放器健壮性（PLY5 ghost playback + PLY4 死 listener 清理）—
// spec §5.4 门禁测试（docs/features/BUG-27.md）。
//
// 缺陷来源: docs/cr/cr-20260724-0110.md PLY4 + PLY5
//
// 覆盖:
//   BUG-27-S1-T01: gate 挂起（弱网 setAudioSource 未返回）时移除最后一曲使
//                  队列清空 → stop 被调、queue 置 null；挂起恢复后 gate 任务
//                  走 superseded，**never** player.play()（否定断言）。
//                  未修代码（空队列分支不调 _gate.beginRequest()）上本用例
//                  FAIL：任务恢复后 isLatest 仍为 true → 继续 play = ghost
//                  playback（RED 锚点，实证见 dev 记录）。
//   BUG-27-S1-T02: gate 空闲时移除最后一曲 → 正常 stop 无副作用，且
//                  beginRequest 不破坏 gate 后续使用（新队列可正常加载）。
//   BUG-27-S1-T03: 非空队列移除当前曲 → 先保存被删曲目再加载下一曲
//                  （a4beb92 时序回归护栏，行为不变）。
//   BUG-27-S1-T04: 非空队列移除非当前曲 → 仅更新队列，不 stop 不重载。
//   BUG-27-INV1:   源码扫描 — removeTrack 空队列分支在 player.stop() 之前
//                  调用 _gate.beginRequest()。
//   BUG-27-INV2:   源码扫描 — orchestrator 无 listener 死代码残留
//                  （registerListeners / _processingSub / _pauseSaveSub /
//                  _autoSaveTimer / _completing / _start*Listener 等）。
//   BUG-27-INV3:   源码扫描 — computeNextQueue() 保留且被 provider 层调用。
//   BUG-27-S2:     源码扫描 — player_provider.dart 调用处无
//                  registerListeners 参数残留。

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:nas_audio_player/core/contracts/audio_player_contract.dart';
import 'package:nas_audio_player/features/player/domain/playback_orchestrator.dart';
import 'package:nas_audio_player/features/player/domain/request_gate.dart';
import 'package:nas_audio_player/shared/models/connection_config.dart';
import 'package:nas_audio_player/shared/models/nas_file.dart';
import 'package:nas_audio_player/shared/models/play_queue.dart';

void main() {
  // ═════════════════════════════════════════════════════════════════════════
  // BUG-27-S1: 空队列 stop 通过 gate 作废 pending 请求
  // ═════════════════════════════════════════════════════════════════════════

  group('BUG-27-S1: 空队列 stop 作废 gate 内挂起请求（ghost playback 防护）', () {
    test('T01: gate 挂在 setAudioSource → 移除最后一曲 → 恢复后 superseded 且不 play',
        () async {
      final env = _Env();
      // 弱网模拟：setAudioSource 挂起在 completer 上，永不主动返回。
      final sourceGate = Completer<Duration?>();
      env.player.hangSetAudioSourceOn = sourceGate;

      env.orchestrator.queue = _queue(['/music/only.mp3']);

      // loadAndPlay 进 gate，任务挂起在 setAudioSource。
      final loadFuture = env.orchestrator.loadAndPlay();
      await pumpEventQueue(times: 50);
      expect(
          env.player.callLog.where((c) => c == 'setAudioSource'), hasLength(1),
          reason: 'gate 任务必须已进入并挂在 setAudioSource 上');
      expect(env.player.callLog, isNot(contains('play')),
          reason: '挂起期间 play 尚未发生');

      // 用户移除最后一曲 → 队列清空。
      await env.orchestrator.removeTrack(0);

      expect(env.player.callLog.where((c) => c == 'stop'), hasLength(1),
          reason: '空队列必须停止播放');
      expect(env.orchestrator.queue, isNull, reason: '队列清空后 queue 置 null');

      // 弱网恢复：挂起的 setAudioSource 返回。
      sourceGate.complete(Duration.zero);
      final result = await loadFuture;

      // 核心断言：beginRequest() 已递增 requestId → 任务恢复后 isLatest==false
      // → superseded。未修代码上此处为 loaded（ghost playback），用例 FAIL。
      expect(result.status, equals(TrackLoadStatus.superseded),
          reason: 'BUG-27-S1：空队列 stop 必须先 _gate.beginRequest() 作废 '
              'pending 请求，挂起任务恢复后不得继续加载流程');
      // 否定断言：任何时刻都不得触发播放（ghost playback 的直接证据）。
      expect(env.player.callLog, isNot(contains('play')),
          reason: '否定：被作废的 gate 任务 never player.play()');
      // 否定断言：不得发生第二次加载尝试。
      expect(
          env.player.callLog.where((c) => c == 'setAudioSource'), hasLength(1),
          reason: '否定：superseded 任务不得重新 setAudioSource');
    });

    test('T02: gate 空闲时清空队列 → 正常 stop，且 gate 后续可用', () async {
      final env = _Env();
      env.orchestrator.queue = _queue(['/music/only.mp3']);

      await env.orchestrator.removeTrack(0);

      expect(env.player.callLog.where((c) => c == 'stop'), hasLength(1),
          reason: 'gate 空闲时移除最后一曲仍正常 stop');
      expect(env.orchestrator.queue, isNull);
      expect(env.player.callLog, isNot(contains('setAudioSource')),
          reason: '否定：空队列路径不得触发加载');
      expect(env.player.callLog, isNot(contains('play')),
          reason: '否定：空队列路径不得触发播放');

      // beginRequest 在 gate 空闲时仅递增 ID，不得破坏 gate 后续使用。
      env.orchestrator.queue = _queue(['/music/next.mp3']);
      final result = await env.orchestrator.loadAndPlay();
      expect(result.status, equals(TrackLoadStatus.loaded),
          reason: '清空后重新加载必须正常（gate 未被空闲 beginRequest 破坏）');
    });

    test('T03: 非空队列移除当前曲 → 先保存被删曲目再加载下一曲（时序不变）', () async {
      final env = _Env();
      env.orchestrator.queue = _queue(['/music/song1.mp3', '/music/song2.mp3']);

      await env.orchestrator.removeTrack(0);

      // 非空队列行为不变：stop 不发生，进度先记在被删曲目名下再加载下一曲。
      expect(env.player.callLog, isNot(contains('stop')),
          reason: '否定：非空队列移除不得 stop');
      expect(env.saver.calls, hasLength(1), reason: '删当前曲仍触发一次保存');
      expect(env.saver.calls.single.filePath, '/music/song1.mp3',
          reason: '保存必须记在被删曲目名下（a4beb92 时序）');
      expect(
          env.player.callLog.where((c) => c == 'setAudioSource'), hasLength(1),
          reason: '删当前曲后必须加载下一曲');
      expect(env.orchestrator.queue!.current.path, '/music/song2.mp3');
    });

    test('T04: 非空队列移除非当前曲 → 仅更新队列', () async {
      final env = _Env();
      env.orchestrator.queue =
          _queue(['/music/song1.mp3', '/music/song2.mp3', '/music/song3.mp3']);

      await env.orchestrator.removeTrack(2);

      expect(env.orchestrator.queue!.length, equals(2));
      expect(env.orchestrator.queue!.current.path, '/music/song1.mp3',
          reason: '当前曲不受影响');
      expect(env.player.callLog, isNot(contains('stop')),
          reason: '否定：移除非当前曲不得 stop');
      expect(env.player.callLog, isNot(contains('setAudioSource')),
          reason: '否定：移除非当前曲不得重载');
      expect(env.saver.calls, isEmpty, reason: '否定：移除非当前曲不保存');
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  // BUG-27-INV1/INV2/INV3 + S2: 源码扫描
  // ═════════════════════════════════════════════════════════════════════════

  group('BUG-27-INV1: 空队列 stop 前 beginRequest（源码扫描）', () {
    test('removeTrack 空队列分支：_gate.beginRequest() 位于 player.stop() 之前', () {
      final src = File('lib/features/player/domain/playback_orchestrator.dart')
          .readAsStringSync();

      // BUG-07（2026-08-17 §7 补记）：removeTrack 签名按 spec 改为
      // Future<TrackLoadResult?>，扫描字面量同步；测试意图（beginRequest 先于
      // player.stop）不变。
      final removeTrackAt =
          src.indexOf('Future<TrackLoadResult?> removeTrack(');
      expect(removeTrackAt, greaterThanOrEqualTo(0),
          reason: 'removeTrack 方法必须存在');
      final emptyBranchAt = src.indexOf('newQueue.length == 0', removeTrackAt);
      expect(emptyBranchAt, greaterThan(removeTrackAt),
          reason: 'removeTrack 必须有空队列分支');
      final beginAt = src.indexOf('_gate.beginRequest()', emptyBranchAt);
      expect(beginAt, greaterThan(emptyBranchAt),
          reason: 'BUG-27-INV1：空队列分支必须调用 _gate.beginRequest()');
      final stopAt = src.indexOf('player.stop()', emptyBranchAt);
      expect(stopAt, greaterThan(beginAt),
          reason: 'BUG-27-INV1：beginRequest 必须先于 player.stop()'
              '（先作废 pending 请求再停播）');
    });
  });

  group('BUG-27-INV2/S2: orchestrator 无 listener 死代码残留（源码扫描）', () {
    late String orchestratorSrc;
    late String providerSrc;
    setUpAll(() {
      orchestratorSrc =
          File('lib/features/player/domain/playback_orchestrator.dart')
              .readAsStringSync();
      providerSrc =
          File('lib/features/player/player_provider.dart').readAsStringSync();
    });

    test('INV2: orchestrator 无 registerListeners 参数与死 listener 代码', () {
      const forbidden = [
        'registerListeners',
        '_processingSub',
        '_pauseSaveSub',
        '_autoSaveTimer',
        '_completing',
        '_startProcessingListener',
        '_startAutoSave',
        '_cancelAutoSave',
        '_startPauseSaveListener',
        '_cancelPauseSave',
      ];
      for (final token in forbidden) {
        expect(orchestratorSrc.contains(token), isFalse,
            reason: 'BUG-27-INV2：orchestrator 不得残留 "$token"'
                '（死 listener 代码，生产线从不生效）');
      }
    });

    test('S2: provider 调用处无 registerListeners 参数残留', () {
      expect(providerSrc.contains('registerListeners'), isFalse,
          reason: 'BUG-27-S2：player_provider.dart 不得再传递 '
              'registerListeners 参数');
    });

    test('INV3: computeNextQueue 保留且被 provider 层使用', () {
      expect(orchestratorSrc, contains('computeNextQueue'),
          reason: 'BUG-27-INV3：computeNextQueue() 被 provider 层平行 '
              'listener 使用，不得随死代码删除');
      expect(providerSrc, contains('computeNextQueue()'),
          reason: 'BUG-27-INV3：provider 层必须仍调用 computeNextQueue()');
    });
  });
}

// ═══════════════════════════════════════════════════════════════════════════
// Helpers（与 bug_18 / bug_bug19 同型的手写 fake，避免 build_runner）
// ═══════════════════════════════════════════════════════════════════════════

NasFile _file(String path) => NasFile(
      name: path.split('/').last,
      path: path,
      isDirectory: false,
    );

PlayQueue _queue(List<String> paths, {int currentIndex = 0}) => PlayQueue(
      files: paths.map(_file).toList(),
      currentIndex: currentIndex,
    );

/// 记录全部交互的 fake player；[hangSetAudioSourceOn] 非空时
/// setAudioSource 挂起在该 completer 上（弱网模拟）。
///
/// `extends Fake` 使任何未实现的成员访问大声失败 —— 若被作废的 gate 任务
/// 意外走到 play/seek 等调用，测试会立即暴露。
class _FakePlayer extends Fake implements AudioPlayer, IAudioPlayer {
  final List<String> callLog = [];
  Completer<Duration?>? hangSetAudioSourceOn;
  bool playingStub = true;

  @override
  Stream<ProcessingState> get processingStateStream => const Stream.empty();

  @override
  Stream<PlayerState> get playerStateStream => const Stream.empty();

  @override
  bool get playing => playingStub;

  @override
  Duration get position => Duration.zero;

  @override
  Duration? get duration => null;

  @override
  Future<Duration?> setAudioSource(AudioSource source,
      {bool preload = true, int? initialIndex, Duration? initialPosition}) {
    callLog.add('setAudioSource');
    final gate = hangSetAudioSourceOn;
    if (gate != null) return gate.future;
    return Future.value(Duration.zero);
  }

  @override
  Future<void> play() async => callLog.add('play');

  @override
  Future<void> pause() async => callLog.add('pause');

  @override
  Future<void> stop() async => callLog.add('stop');

  @override
  Future<void> seek(Duration? position, {int? index}) async =>
      callLog.add('seek');

  @override
  Future<void> setSpeed(double speed) async => callLog.add('setSpeed');
}

class _RecordingProgressSaver implements ProgressSaver {
  final List<({int connectionId, String filePath})> calls = [];

  @override
  Future<void> upsertProgress({
    required int connectionId,
    required String filePath,
    required int positionMs,
    int? durationMs,
  }) async {
    calls.add((connectionId: connectionId, filePath: filePath));
  }
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

class _StubSpeedProvider implements DefaultSpeedProvider {
  @override
  double getDefaultSpeed() => 1.0;
}

class _StubQueueConnIdProvider implements QueueConnectionIdProvider {
  @override
  int? getLastQueueConnectionId() => 1;
}

class _Env {
  final _FakePlayer player = _FakePlayer();
  final _RecordingProgressSaver saver = _RecordingProgressSaver();
  late final PlaybackOrchestrator orchestrator;

  _Env() {
    orchestrator = PlaybackOrchestrator(
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
      progressSaver: saver,
      defaultSpeedProvider: _StubSpeedProvider(),
      queueConnectionIdProvider: _StubQueueConnIdProvider(),
    );
  }
}
