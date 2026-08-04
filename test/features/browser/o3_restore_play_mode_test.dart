// test/features/browser/o3_restore_play_mode_test.dart
// cr-20260804-1922 §5 O3: 恢复的播放队列 playMode 休眠 — 回归门禁测试
//
// 问题：重启恢复持久化队列时（restoreQueueFromPrefsProvider 写
// PlayQueue.fromMap(...)，含 playMode/shuffleOrder/shufflePosition），
// playModeProvider 初值恒为 PlayMode.sequential，orchestrator.playMode
// 又从它同步（player_provider.dart playbackOrchestratorProvider）→
// 恢复出来的 shuffle 排列处于休眠态：队列数据里有 shuffle 顺序，但
// 播放模式显示/行为仍是顺序播放，直到用户手动切换模式才生效。
// 与「恢复上次退出状态」的产品预期不符。
//
// 修复：恢复队列时按 PlayQueue.playMode 回写 playModeProvider
// （browser_provider.dart restoreQueueFromPrefsProvider 内，队列写入之后；
// orchestrator.playMode 经既有 ref.listen 同步，不另起平行通道）。
//
// 用例：
//   O3-S1  shuffle 队列恢复 → playModeProvider == shuffle 且
//          orchestrator.playMode == shuffle
//   O3-S2  旧数据无 playMode 字段 → sequential（否定断言：不抛错、
//          不误设 shuffle）
//   O3-S3  sequential 队列恢复 → sequential 不变
//   O3-S4  repeatAll 队列恢复 → repeatAll（非 shuffle 特例）
//   O3-S5  幂等：重复触发恢复不改变状态
//   O3-S6  orchestrator 先于恢复构建（ref.listen 路径）仍同步
//   O3-S7  行为锚：恢复 shuffle 后 skipToNext 走 advanceShuffle 路径
//          （排列推进），而非 nextIndex 顺序路径 —— 证明 shuffle 真的
//          活了，不是只改显示

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nas_audio_player/features/browser/browser_provider.dart';
import 'package:nas_audio_player/features/connection/connection_provider.dart';
import 'package:nas_audio_player/shared/di/providers.dart';
import 'package:nas_audio_player/shared/models/connection_config.dart';
import 'package:nas_audio_player/shared/models/play_queue.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/mock_audio_player.dart';

const _qKey = 'last_play_queue';

/// 4 首曲目的 shuffle 队列 JSON：当前 index 0，排列 [0,2,3,1]，位置 0。
/// 该排列下两条路径的"下一首"不同——行为锚的判别基础：
///   advanceShuffle 路径 → order[1] = 2
///   sequential nextIndex 路径 → currentIndex + 1 = 1
Map<String, dynamic> _shuffleQueueJson() => {
      'filePaths': [
        '/music/track_01.mp3',
        '/music/track_02.mp3',
        '/music/track_03.mp3',
        '/music/track_04.mp3',
      ],
      'currentIndex': 0,
      'startPositionMs': null,
      'playMode': 'shuffle',
      'shuffleOrder': [0, 2, 3, 1],
      'shufflePosition': 0,
    };

/// Boots a container with [prefs] injected; active connection stubbed to
/// null（跳过 preload 分支，orchestrator.loadAndPlay 在连接为空时短路
/// failed，不触碰播放器）；audioPlayerProvider 用 mock 避免真实
/// just_audio 平台通道。
ProviderContainer makeContainer(SharedPreferences prefs) {
  final container = ProviderContainer(overrides: [
    sharedPreferencesProvider.overrideWithValue(prefs),
    activeConnectionProvider
        .overrideWith((ref) async => null as ConnectionConfig?),
    audioPlayerProvider.overrideWithValue(MockAudioPlayer()),
  ]);
  addTearDown(container.dispose);
  return container;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ═══════════════════════════════════════════════════════════════════════
  // O3-S1 — shuffle 队列恢复 → 模式同步（核心 RED 用例）
  // ═══════════════════════════════════════════════════════════════════════
  group('O3-S1: shuffle 队列恢复后 playModeProvider 与 orchestrator 同步', () {
    test('恢复 shuffle 队列 → playModeProvider == shuffle', () async {
      SharedPreferences.setMockInitialValues({
        _qKey: jsonEncode(_shuffleQueueJson()),
      });
      final prefs = await SharedPreferences.getInstance();
      final container = makeContainer(prefs);

      await container.read(restoreQueueFromPrefsProvider.future);

      final queue = container.read(currentPlayQueueProvider);
      expect(queue, isNotNull, reason: '前置: 队列必须被恢复');
      expect(queue!.playMode, equals(PlayMode.shuffle),
          reason: '前置: 队列自身 playMode 为 shuffle');

      // 修复前：playModeProvider 初值恒 sequential → 休眠
      expect(container.read(playModeProvider), equals(PlayMode.shuffle),
          reason: 'O3-S1: 恢复必须回写 playModeProvider，shuffle 不得休眠');
    });

    test('恢复 shuffle 队列 → orchestrator.playMode == shuffle', () async {
      SharedPreferences.setMockInitialValues({
        _qKey: jsonEncode(_shuffleQueueJson()),
      });
      final prefs = await SharedPreferences.getInstance();
      final container = makeContainer(prefs);

      await container.read(restoreQueueFromPrefsProvider.future);
      final orchestrator = container.read(playbackOrchestratorProvider);

      expect(orchestrator.playMode, equals(PlayMode.shuffle),
          reason: 'O3-S1: orchestrator.playMode 经既有同步机制跟随，'
              '恢复的 shuffle 必须生效');
      expect(orchestrator.queue, isNotNull, reason: '前置: 队列已同步到 orchestrator');
      expect(orchestrator.queue!.playMode, equals(PlayMode.shuffle));
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // O3-S2/S3/S4 — 旧数据兼容与各模式恢复
  // ═══════════════════════════════════════════════════════════════════════
  group('O3-S2/S3/S4: 旧数据与各模式恢复', () {
    test('O3-S2: 旧数据无 playMode 字段 → sequential，不抛错、不误设 shuffle', () async {
      final legacy = _shuffleQueueJson()..remove('playMode');
      SharedPreferences.setMockInitialValues({
        _qKey: jsonEncode(legacy),
      });
      final prefs = await SharedPreferences.getInstance();
      final container = makeContainer(prefs);

      await container.read(restoreQueueFromPrefsProvider.future);

      final queue = container.read(currentPlayQueueProvider);
      expect(queue, isNotNull, reason: 'O3-S2: 缺字段不得阻止队列恢复');
      expect(queue!.playMode, equals(PlayMode.sequential),
          reason: 'O3-S2: 旧数据缺 playMode → sequential 默认');
      expect(container.read(playModeProvider), equals(PlayMode.sequential),
          reason: 'O3-S2: playModeProvider 保持 sequential 默认');
      // 否定断言: 不得因存在 shuffleOrder 就误判为 shuffle
      expect(container.read(playModeProvider), isNot(PlayMode.shuffle));
    });

    test('O3-S3: sequential 队列恢复 → sequential 不变', () async {
      SharedPreferences.setMockInitialValues({
        _qKey: jsonEncode({
          'filePaths': ['/music/a.mp3', '/music/b.mp3'],
          'currentIndex': 0,
          'playMode': 'sequential',
        }),
      });
      final prefs = await SharedPreferences.getInstance();
      final container = makeContainer(prefs);

      await container.read(restoreQueueFromPrefsProvider.future);

      expect(container.read(currentPlayQueueProvider), isNotNull);
      expect(container.read(playModeProvider), equals(PlayMode.sequential),
          reason: 'O3-S3: sequential 恢复后保持 sequential');
    });

    test('O3-S4: repeatAll 队列恢复 → repeatAll（非 shuffle 特例）', () async {
      SharedPreferences.setMockInitialValues({
        _qKey: jsonEncode({
          'filePaths': ['/music/a.mp3', '/music/b.mp3'],
          'currentIndex': 0,
          'playMode': 'repeatAll',
        }),
      });
      final prefs = await SharedPreferences.getInstance();
      final container = makeContainer(prefs);

      await container.read(restoreQueueFromPrefsProvider.future);

      expect(container.read(playModeProvider), equals(PlayMode.repeatAll),
          reason: 'O3-S4: 恢复按 PlayQueue.playMode 回写，不限 shuffle');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // O3-S5 — 幂等：重复触发恢复不改变状态
  // ═══════════════════════════════════════════════════════════════════════
  group('O3-S5: 幂等性', () {
    test('invalidate 后重复触发恢复 → 队列与模式不变', () async {
      SharedPreferences.setMockInitialValues({
        _qKey: jsonEncode(_shuffleQueueJson()),
      });
      final prefs = await SharedPreferences.getInstance();
      final container = makeContainer(prefs);
      // 激活持久化写监听，验证重复恢复不产生回写振荡
      container.read(persistQueueOnChangeProvider);

      await container.read(restoreQueueFromPrefsProvider.future);
      final firstQueue = container.read(currentPlayQueueProvider)!;
      final firstMode = container.read(playModeProvider);
      final firstRaw = prefs.getString(_qKey);

      // 重复触发（模拟恢复 provider 被 invalidate 后重建）
      container.invalidate(restoreQueueFromPrefsProvider);
      await container.read(restoreQueueFromPrefsProvider.future);

      expect(container.read(playModeProvider), equals(firstMode),
          reason: 'O3-S5: 重复恢复后模式不变');
      expect(container.read(currentPlayQueueProvider), equals(firstQueue),
          reason: 'O3-S5: 重复恢复后队列不变（PlayQueue == 判等）');
      expect(prefs.getString(_qKey), equals(firstRaw),
          reason: 'O3-S5: 重复恢复不改变持久化内容');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // O3-S6 — orchestrator 先于恢复构建（ref.listen 路径同样同步）
  // ═══════════════════════════════════════════════════════════════════════
  group('O3-S6: orchestrator 先构建的时序', () {
    test('orchestrator 先于恢复构建 → 恢复后模式仍同步（listener 路径）', () async {
      SharedPreferences.setMockInitialValues({
        _qKey: jsonEncode(_shuffleQueueJson()),
      });
      final prefs = await SharedPreferences.getInstance();
      final container = makeContainer(prefs);

      // 先构建 orchestrator（注册 playModeProvider/queue 的 ref.listen），
      // 再触发恢复——两种构建顺序都必须同步成功。
      final orchestrator = container.read(playbackOrchestratorProvider);
      expect(orchestrator.playMode, equals(PlayMode.sequential),
          reason: '前置: 恢复前为默认 sequential');

      await container.read(restoreQueueFromPrefsProvider.future);
      await Future<void>.delayed(Duration.zero);

      expect(container.read(playModeProvider), equals(PlayMode.shuffle),
          reason: 'O3-S6: 恢复回写 playModeProvider');
      expect(orchestrator.playMode, equals(PlayMode.shuffle),
          reason: 'O3-S6: 既有 ref.listen 同步 orchestrator.playMode');
      expect(orchestrator.queue, isNotNull,
          reason: 'O3-S6: 队列同步到 orchestrator');
      expect(orchestrator.queue!.playMode, equals(PlayMode.shuffle));
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // O3-S7 — 行为锚：恢复的 shuffle 真的活了（advanceShuffle 路径）
  // ═══════════════════════════════════════════════════════════════════════
  group('O3-S7: 行为锚 — skipToNext 走 advanceShuffle 路径', () {
    test('恢复 shuffle 后 skipToNext 按排列推进（order[1]=2），而非顺序 +1', () async {
      SharedPreferences.setMockInitialValues({
        _qKey: jsonEncode(_shuffleQueueJson()),
      });
      final prefs = await SharedPreferences.getInstance();
      final container = makeContainer(prefs);
      await container.read(activeConnectionProvider.future);

      await container.read(restoreQueueFromPrefsProvider.future);
      final orchestrator = container.read(playbackOrchestratorProvider);

      await orchestrator.skipToNext();

      final queue = container.read(currentPlayQueueProvider);
      expect(queue, isNotNull);
      // 排列 [0,2,3,1] 位置 0 → advanceShuffle 推进到位置 1 → order[1] = 2
      expect(queue!.currentIndex, equals(2),
          reason: 'O3-S7 行为锚: shuffle 激活时下一首 = 排列下一位（index 2）');
      expect(queue.current.path, equals('/music/track_03.mp3'));
      // 否定断言: 未修复时 orchestrator.playMode == sequential →
      // nextIndex(0,4,sequential) = 1 —— 不得落在顺序路径结果上
      expect(queue.currentIndex, isNot(1),
          reason: '否定断言: 不得走 sequential 的 currentIndex+1 路径');
      expect(orchestrator.queue!.playMode, equals(PlayMode.shuffle),
          reason: '推进后队列仍处 shuffle 模式');
    });
  });
}
