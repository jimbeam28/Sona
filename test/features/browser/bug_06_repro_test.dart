// test/features/browser/bug_06_repro_test.dart
// BUG-06（cr-20260816-0802 F2）：启动恢复 preload 绕过 SerializedRequestGate
// 直连 AudioPlayer（P14 绕门）→ 晚到的 preload 副作用覆盖用户选择
// （spec: docs/features/BUG-06.md §5.4）
//
// 缺陷：browser_provider.dart:235-242 恢复队列时直连
// preloadAudioSource（audio_source_builder.dart:162-167，setAudioSource/seek
// 各 10s 超时）——不经过 orchestrator 的 SerializedRequestGate（P14 绕门）。
// onboarding.dart:64-67 只 ref.read 不 await 就 go('/browser')，用户在 preload
// 未完成时可点曲。时序：
//   1. preload 的 setAudioSource 挂起（慢 NAS，10s 窗口内不完成）
//   2. 用户点另一首 → loadAndPlay 的 setAudioSource 完成、开始播放
//   3. preload 的 setAudioSource/seek 晚到 → 在用户已选的 source 上 seek 旧曲
//      位置（audio_source_builder.dart:163-167）→ 播放被旧曲进度干扰
//   修复契约：preload 一旦被用户加载取代（晚到即弃），不得再有任何
//   player 副作用（无后续 seek / 无重新 setAudioSource）。
//
// 门禁（修复前必须 FAIL）：
//   T1 preload 晚到后不得再发 seek（当前代码 preload 完成即 seek 旧位置）
//   T2 最终生效的 source 必须是用户选择的（last issued wins 语义）

import 'dart:async';
import 'dart:convert';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:nas_audio_player/core/contracts/audio_player_contract.dart';
import 'package:nas_audio_player/core/contracts/database_contract.dart';
import 'package:nas_audio_player/shared/di/providers.dart';
import 'package:nas_audio_player/shared/models/connection_config.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/fake_secure_storage.dart';

const _qKey = 'last_play_queue';
const _qConnKey = 'last_play_queue_connection_id';

/// 最小 [IConnectionDao] fake：findById(1) 返回测试连接（供
/// restoreQueueFromPrefsProvider 的 _restoredQueueRoot 查询）。
class _FakeConnectionDao implements IConnectionDao {
  @override
  Future<ConnectionConfig?> findById(int id) async =>
      id == 1 ? _connection : null;

  @override
  Future<ConnectionConfig?> findActive() async => _connection;

  @override
  Future<int> insert(ConnectionConfig config, {required String passwordKey}) =>
      Future.value(1);

  @override
  Future<List<ConnectionConfig>> findAll() async => [_connection];

  @override
  Future<String?> findPasswordKey(int id) async => null;

  @override
  Future<int> update(ConnectionConfig config, {required String passwordKey}) =>
      Future.value(1);

  @override
  Future<void> setActive(int id) async {}

  @override
  Future<bool> delete(int id) async => false;

  @override
  Future<bool> deleteWithoutGuard(int id) async => false;

  @override
  Future<int> count() async => 1;
}

final _connection = ConnectionConfig(
  id: 1,
  name: 'test',
  url: 'http://localhost:8080',
  username: 'user',
  createdAt: DateTime(2024),
  updatedAt: DateTime(2024),
);

/// 手写录音 fake（bug_bug19 同型）：记录每个 setAudioSource/seek 的调用时序，
/// 第 1 个 setAudioSource（= preload）可挂起可控释放；"生效 source" 取
/// 最后完成（或最后发出——last issued wins 语义）的调用。
class _RecordingPlayer extends Fake implements AudioPlayer, IAudioPlayer {
  /// 按调用顺序记录 `setAudioSource:<uri>` / `seek:<pos>`。
  final List<String> calls = [];

  /// 第 1 个 setAudioSource 挂起用的门闩（null = 不挂起）。
  Completer<Duration?>? hang;

  int _issued = 0;

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
    final uri =
        source is UriAudioSource ? source.uri.toString() : source.toString();
    calls.add('setAudioSource:$uri');
    _issued++;
    final h = hang;
    if (_issued == 1 && h != null) {
      return h.future;
    }
    return Future.value(Duration.zero);
  }

  @override
  Future<void> seek(Duration? position, {int? index}) async {
    calls.add('seek:${position ?? Duration.zero}');
  }

  @override
  Future<void> play() async {}

  @override
  Future<void> pause() async {}

  @override
  Future<void> stop() async {}

  @override
  Future<void> setSpeed(double speed) async {}

  @override
  Future<void> dispose() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('BUG-06-T1/T2: preload 晚到后不得覆盖用户选择的 source，不得 seek 旧位置', () async {
    SharedPreferences.setMockInitialValues({
      _qKey: jsonEncode({
        'filePaths': ['/music/old_track.mp3'],
        'currentIndex': 0,
        'startPositionMs': 12345,
        'playMode': 'sequential',
      }),
      _qConnKey: 1,
    });
    final prefs = await SharedPreferences.getInstance();

    FakeAsync().run((async) {
      final player = _RecordingPlayer()..hang = Completer<Duration?>();

      final container = ProviderContainer(overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        audioPlayerProvider.overrideWithValue(player),
        connectionDaoProvider.overrideWithValue(_FakeConnectionDao()),
        secureStorageProvider
            .overrideWithValue(FakeSecureStorage()..setPassword(1, 'secret')),
        activeConnectionProvider.overrideWith((ref) async => _connection),
      ]);
      addTearDown(container.dispose);

      // 预热 activeConnectionProvider（FutureProvider 首次 read 才启动；
      // restore 体内 valueOrNull 要求已解析，否则 conn == null 跳过 preload）。
      container.read(activeConnectionProvider.future);
      async.flushMicrotasks();

      // 启动恢复：onboarding.dart:64-67 只 read 不 await 即跳转 —— 模拟不等待。
      final restoreFuture =
          container.read(restoreQueueFromPrefsProvider.future);
      // 等 preload 发完密码读取 + setAudioSource（挂起）。
      for (var i = 0; i < 10; i++) {
        async.flushMicrotasks();
      }
      expect(player.calls.where((c) => c.startsWith('setAudioSource:')),
          hasLength(1),
          reason: '前置：preload 的 setAudioSource 必须已发出并挂起');
      expect(player.calls.first, contains('old_track.mp3'));

      // 用户在浏览器点了另一首：模拟用户加载直接完成（后发调用立即完成）。
      final userUri = Uri.parse('http://localhost:8080/music/user_pick.mp3');
      player.setAudioSource(AudioSource.uri(userUri));
      async.flushMicrotasks();
      expect(player.calls.last, 'setAudioSource:$userUri',
          reason: '前置：用户选择的 source 已是最后生效');

      // preload 的挂起调用终于完成（慢 NAS 恢复，晚到）。
      player.hang!.complete(Duration.zero);
      for (var i = 0; i < 20; i++) {
        async.flushMicrotasks();
      }

      // T1：preload 晚到后不得再有任何 player 副作用（seek 旧曲位置）。
      expect(
        player.calls.where((c) => c.startsWith('seek:')),
        isEmpty,
        reason: 'BUG-06（cr-20260816-0802 F2）：恢复 preload（browser_provider.'
            'dart:235-242 → audio_source_builder.dart:162-167）绕过加载门直达'
            'AudioPlayer（P14 绕门）。用户已选曲后 preload 晚到，若仍执行'
            'startPositionMs seek（audio_source_builder.dart:163-167）会把用户'
            '曲目 seek 到旧曲位置。晚到即弃：不得有任何后续副作用',
      );
      // T2：最后生效的 source 仍是用户选择的（不得被 preload 换回旧曲）。
      expect(player.calls.last, 'setAudioSource:$userUri',
          reason: 'BUG-06-T2：晚到的 preload 不得把播放器 source 换回恢复的旧曲');
      expect(
          player.calls.where((c) => c.contains('old_track.mp3')), hasLength(1),
          reason: 'preload 的 setAudioSource 只应发出一次（旧曲不得二次登场）');

      restoreFuture.ignore();
    });
  });
}
