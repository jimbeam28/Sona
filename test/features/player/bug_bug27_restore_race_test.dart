// test/features/player/bug_bug27_restore_race_test.dart
// BUG-27 门禁测试（来源 cr-20260823-1421.md F5，复核分流 2026-08-23）。
//
// 缺陷：restoreStartupProgressProvider（player_provider.dart:216-236）在读
// currentPlayQueueProvider（:218）与写回/seek（:229-234）之间横跨
// latestPlayedProgressProvider.future 异步间隙，写回前不复核 provider 当前值。
// 用户在窗口内点选其它文件时，恢复流程用旧队列派生值覆盖新队列并错位 seek。
// BUG-06 已在 preloadAudioSource 侧加 shouldAbandon 双闸，本路径是同族
// hazard 的未设防兄弟路径。
//
// 门禁：可控 Completer 的 fake DAO 确定性制造窗口——恢复流程停在 DAO await
// 上时模拟用户写入新队列，随后完成进度查询。期望：用户队列原样保留
// （identical）且不对 player 发起恢复 seek。

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:nas_audio_player/core/contracts/database_contract.dart';
import 'package:nas_audio_player/shared/di/providers.dart';
import 'package:nas_audio_player/shared/models/connection_config.dart';
import 'package:nas_audio_player/shared/models/nas_file.dart';
import 'package:nas_audio_player/shared/models/play_progress.dart';
import 'package:nas_audio_player/shared/models/play_queue.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/fake_secure_storage.dart';
import '../../helpers/mock_audio_player.dart';

class _ParkedDao extends Mock implements IProgressDao {
  final Completer<PlayProgress?> latest = Completer<PlayProgress?>();
  int findLatestCalls = 0;

  @override
  Future<PlayProgress?> findLatest() {
    findLatestCalls++;
    return latest.future;
  }
}

/// restore 路径经 connectionDaoProvider.findById 解析持久化队列的归属连接
///（browser_provider.dart:182）——必须 fake 掉，否则触碰真实 sqflite 工厂。
class _StubConnDao extends Mock implements IConnectionDao {
  final ConnectionConfig conn;
  _StubConnDao(this.conn);

  @override
  Future<ConnectionConfig?> findById(int? id) async => conn;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('BUG-27-S1: 恢复窗口内的用户选曲不得被启动恢复覆盖/错位 seek', () async {
    SharedPreferences.setMockInitialValues({
      'last_play_queue': '{"filePaths":["/a.mp3"],"currentIndex":0,'
          '"startPositionMs":null,"playMode":"sequential"}',
      'last_play_queue_connection_id': 1,
    });
    final prefs = await SharedPreferences.getInstance();

    final storage = FakeSecureStorage()..setPassword(1, 'pw');
    final dao = _ParkedDao();
    final player = MockAudioPlayer();
    // restoreStartupProgress 的 seek 守卫读取 audioSource（无 try 包裹），
    // 不 stub 会以 MissingStubError 抢占失败信号。
    when(player.audioSource).thenReturn(null);

    final now = DateTime.now();
    final conn = ConnectionConfig(
        id: 1,
        name: 'nas',
        url: 'http://192.168.1.50:5005',
        username: 'admin',
        basePath: '/',
        isActive: true,
        createdAt: now,
        updatedAt: now);

    final container = ProviderContainer(overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      audioPlayerProvider.overrideWithValue(player),
      activeConnectionProvider.overrideWith((ref) async => conn),
      secureStorageProvider.overrideWithValue(storage),
      progressDaoProvider.overrideWithValue(dao),
      connectionDaoProvider.overrideWithValue(_StubConnDao(conn)),
    ]);
    addTearDown(container.dispose);

    final restoreFuture = container.read(restoreStartupProgressProvider.future);
    Object? restoreError;
    restoreFuture.then((_) {}, onError: (Object e, StackTrace _) {
      restoreError = e;
    });

    // 泵微任务直到恢复流程停在进度查询的 completer 上。
    for (var i = 0; i < 30 && dao.findLatestCalls == 0; i++) {
      await Future<void>.delayed(Duration.zero);
    }
    expect(dao.findLatestCalls, greaterThanOrEqualTo(1),
        reason: '前置条件：恢复流程已推进到进度查询 await（竞态窗口打开）');

    // 竞态窗口内的用户操作：点选另一文件建队。
    final userQueue = PlayQueue(files: [
      NasFile(
          name: 'b.mp3',
          path: '/b.mp3',
          isDirectory: false,
          audioType: AudioFileType.music),
    ], currentIndex: 0);
    container.read(currentPlayQueueProvider.notifier).state = userQueue;

    // 进度返回：与恢复队列当前曲同路径同连接 → r != q 成立（触发写回分支）。
    dao.latest.complete(PlayProgress(
      connectionId: 1,
      filePath: '/a.mp3',
      positionMs: 30000,
      durationMs: 180000,
      lastPlayedAt: DateTime.now(),
    ));

    for (var i = 0; i < 20; i++) {
      await Future<void>.delayed(Duration.zero);
    }
    expect(restoreError, isNull, reason: '恢复流程本身不得抛错');

    // 核心断言（修复前 FAIL）：用户队列原样保留。
    expect(container.read(currentPlayQueueProvider), same(userQueue),
        reason: '启动恢复不得覆盖竞态窗口内用户的选曲');
    // 否定断言：不得对 player 发起恢复 seek。
    verifyNever(player.seek(any));
  });
}
