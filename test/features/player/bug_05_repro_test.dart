// test/features/player/bug_05_repro_test.dart
// BUG-05（cr-20260816-0802 B3）：loadAndPlay 静默 catch 违反 catch-log 裁决
// （spec: docs/features/BUG-05.md §5.4）
//
// 缺陷：playback_orchestrator.dart:241-243 的 catch 吞掉 loadAndPlay 任务内
// 全部异常（连接 5s 超时、setAudioSource/seek/setSpeed 平台错误等），无
// debugLog/LogBuffer。SCHEMA.md §5 裁决：「任何 catch / catchError 必须先留
// 日志才允许吞掉异常」——豁免清单仅 audio_handler 六方法（BUG-17）与
// connection delete（BUG-24），本处不在豁免内。同文件 saveProgress
// （:407-413）已示范正确写法。
//
// 门禁（修复前必须 FAIL）：
//   1. loadAndPlay 失败（异常路径）必须有日志（含 "[Player]" 前缀字样）
//   2. 返回值仍为 failed（吞错语义不变）
//   3. 日志不得含凭证（secret-logs 门禁）

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:nas_audio_player/core/contracts/audio_player_contract.dart';
import 'package:nas_audio_player/features/player/domain/playback_orchestrator.dart';
import 'package:nas_audio_player/features/player/domain/request_gate.dart';
import 'package:nas_audio_player/shared/models/connection_config.dart';
import 'package:nas_audio_player/shared/models/nas_file.dart';
import 'package:nas_audio_player/shared/models/play_queue.dart';

// ── 依赖桩（bug_bug19_repro_test.dart 同型）───────────────────────────────

class _ThrowingPasswordReader implements PasswordReader {
  @override
  Future<String?> readPassword(int connectionId) async =>
      throw Exception('simulated storage failure');
}

class _StubConnectionProvider implements ActiveConnectionProvider {
  final ConnectionConfig? connection;
  _StubConnectionProvider(this.connection);

  @override
  Future<ConnectionConfig?> getActiveConnection() async => connection;

  @override
  ConnectionConfig? get currentConnection => connection;
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

class _StubPlayer implements IAudioPlayer {
  @override
  Stream<PlayerState> get playerStateStream => const Stream.empty();
  @override
  Stream<Duration> get positionStream => const Stream.empty();
  @override
  Stream<Duration?> get durationStream => const Stream.empty();
  @override
  Stream<ProcessingState> get processingStateStream => const Stream.empty();
  @override
  bool get playing => false;
  @override
  Duration get position => Duration.zero;
  @override
  Duration? get duration => null;
  @override
  Duration get bufferedPosition => Duration.zero;
  @override
  double get speed => 1.0;
  @override
  AudioSource? get audioSource => null;
  @override
  Future<Duration?> setAudioSource(AudioSource source) async => null;
  @override
  Future<void> play() async {}
  @override
  Future<void> pause() async {}
  @override
  Future<void> stop() async {}
  @override
  Future<void> seek(Duration position) async {}
  @override
  Future<void> setSpeed(double speed) async {}
  @override
  Future<void> dispose() async {}
}

void main() {
  /// Captures everything written through [debugPrint] during [body].
  Future<List<String>> captureLogs(Future<void> Function() body) async {
    final logs = <String>[];
    final originalDebugPrint = debugPrint;
    debugPrint = (message, {wrapWidth}) => logs.add(message ?? '');
    try {
      await body();
    } finally {
      debugPrint = originalDebugPrint;
    }
    return logs;
  }

  test('BUG-05: loadAndPlay 异常路径失败必须有日志（catch-log 裁决）', () async {
    final orchestrator = PlaybackOrchestrator(
      player: _StubPlayer(),
      connectionProvider: _StubConnectionProvider(ConnectionConfig(
        id: 1,
        name: 'test',
        url: 'http://localhost:8080',
        username: 'user',
        createdAt: DateTime(2024),
        updatedAt: DateTime(2024),
      )),
      passwordReader: _ThrowingPasswordReader(),
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

    TrackLoadResult? result;
    final logs = await captureLogs(() async {
      result = await orchestrator.loadAndPlay();
    });

    expect(result!.isLoaded, isFalse, reason: '前置：异常路径必须返回 failed（吞错语义不变）');
    expect(
      logs.where((l) => l.contains('[Player]')),
      isNotEmpty,
      reason: 'BUG-05（cr-20260816-0802 B3）：catch（playback_orchestrator.dart:'
          '241-243）必须先留日志才允许吞掉异常 —— 对照 saveProgress 正确写法'
          '（:407-413 debugLog("[Player] saveProgress failed: \$e")）。'
          '当前静默 catch → 日志为空',
    );
    expect(
      logs.where((l) => l.contains('secret') || l.contains('user:')),
      isEmpty,
      reason: 'secret-logs 门禁：日志不得含凭证（本用例密码读取抛错未落值，'
          '防御性断言）',
    );
  });
}
