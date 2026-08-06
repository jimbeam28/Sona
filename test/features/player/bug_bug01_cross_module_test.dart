// test/features/player/bug_bug01_cross_module_test.dart
// BUG-01 §7 跨模块回归补强（dev-check round_1 返工）
//
// 靶点（docs/dev/check_log.md BUG-01 round_1）：
//   1. PLY 联动：切 shuffle 序列后 `o.queue` 应同步到 orchestrator
//      spec 行：BUG-01 §7 第 1 条 "切 shuffle 序列后 o.queue 应同步到 orchestrator"
//   2. PRG 联动：persist 不短路——shuffle 字段纳入 == 后仍要写 prefs
//      spec 行：BUG-01 §7 第 2 条 "新增 == 后须确认 persist 不短路"
//
// 这两条都是端到端ProviderContainer 测：真跑 ref.listen(currentPlayQueueProvider)
// + persistQueueOnChangeProvider，验证 BUG-01 修复后 == 不再吃掉 shuffle 变化。

import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:mockito/mockito.dart';
import 'package:nas_audio_player/features/browser/browser_provider.dart';
import 'package:nas_audio_player/features/player/player_provider.dart';
import 'package:nas_audio_player/shared/di/providers.dart';
import 'package:nas_audio_player/shared/models/connection_config.dart';
import 'package:nas_audio_player/shared/models/nas_file.dart';
import 'package:nas_audio_player/shared/models/play_queue.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/mock_audio_player.dart';
import '../../helpers/test_factories.dart';

NasFile _f(String name) => NasFile(
      name: name,
      path: '/music/$name',
      isDirectory: false,
      audioType: NasFile.classifyType(name),
    );

void main() {
  group('BUG-01 §7 跨模块回归（dev-check round_1 返工）', () {
    late MockAudioPlayer mockPlayer;
    late StreamController<ProcessingState> processingController;
    late ProviderContainer container;
    late ConnectionConfig testConn;
    late SharedPreferences prefs;

    final files = [_f('a.mp3'), _f('b.mp3'), _f('c.mp3'), _f('d.mp3')];

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();

      mockPlayer = MockAudioPlayer();
      processingController = StreamController<ProcessingState>.broadcast();

      when(mockPlayer.processingStateStream)
          .thenAnswer((_) => processingController.stream);
      when(mockPlayer.position).thenReturn(const Duration(seconds: 30));
      when(mockPlayer.duration).thenReturn(const Duration(minutes: 3));
      when(mockPlayer.playing).thenReturn(true);

      testConn = testConfig(id: 1, isActive: true);

      container = ProviderContainer(
        overrides: [
          audioPlayerProvider.overrideWithValue(mockPlayer),
          activeConnectionProvider
              .overrideWith((ref) => Future.value(testConn)),
          sharedPreferencesProvider.overrideWith((ref) => prefs),
          onTrackCompletedProvider.overrideWithValue(() => false),
          saveProgressProvider.overrideWithValue(() {}),
          loadAndPlayProvider.overrideWithValue(() async {
            return const TrackLoadResult.loaded();
          }),
        ],
      );
      // 触发 persistQueueOnChangeProvider 的 ref.listen 注册（must read）
      container.read(persistQueueOnChangeProvider);
      // 触发 playbackOrchestratorProvider 的 ref.listen 注册
      container.read(playbackOrchestratorProvider);
    });

    tearDown(() {
      processingController.close();
      container.dispose();
    });

    // ── PLY-REG: 切 shuffle 序列后 o.queue 应同步到 orchestrator ───────────
    test(
        'BUG-01 §7 PLY-REG: advanceShuffle 后写入 provider，orchestrator.queue 同步到新队列',
        () async {
      await container.read(activeConnectionProvider.future);

      // 1) 初始 shuffle 队列
      final q1 = PlayQueue(
        files: files,
        currentIndex: 0,
        playMode: PlayMode.shuffle,
        shuffleOrder: const [0, 3, 1, 2],
        shufflePosition: 0,
      );
      container.read(currentPlayQueueProvider.notifier).state = q1;

      final o = container.read(playbackOrchestratorProvider);
      expect(o.queue, isNotNull,
          reason: 'PLY-REG step1: 初始写入后 orchestrator.queue 已同步');
      expect(o.queue == q1, isTrue,
          reason: 'PLY-REG step1: orchestrator.queue == q1 (== 已纳入 shuffle)');

      // 2) 推进 shuffle 得到一个不同的 q2（shufflePosition 变化）
      final q2 = q1.advanceShuffle();
      expect(q2, isNotNull, reason: 'advanceShuffle 在边界内应返回非空');
      expect(q2 == q1, isFalse,
          reason:
              'PLY-REG step2: advanceShuffle 后 q2 != q1 (shufflePosition 变化)');
      expect(q2!.toMap()['shufflePosition'], equals(1),
          reason: 'PLY-REG step2: shufflePosition 从 0 → 1');

      // 3) 写入触发 ref.listen 同步路径
      container.read(currentPlayQueueProvider.notifier).state = q2;

      // 关键断言：orchestrator.queue 应被同步到 q2，而不是仍指 q1
      expect(o.queue == q2, isTrue,
          reason:
              'PLY-REG step3: == 修复后 ref.listen 真把 q2 同步进 orchestrator.queue');
      expect(o.queue!.toMap()['shufflePosition'], equals(1),
          reason: 'PLY-REG step3: orchestrator 看到的 shuffle 序列已推进');

      // 否定断言：orchestrator 不应仍停在旧 shuffle 状态
      expect(o.queue == q1, isFalse,
          reason: '否定: orchestrator.queue 不应仍指 q1（旧 shuffle 状态）');
    });

    // ── PRG-REG: persist 不短路——shuffle 字段变化也触发 prefs 写入 ─────────
    test('BUG-01 §7 PRG-REG: shuffle 序列变化触发 persist 写入 prefs（不短路）', () async {
      await container.read(activeConnectionProvider.future);

      // 1) 初始 shuffle 队列写入 → prefs 应被写入 {last_play_queue: ...}
      final q1 = PlayQueue(
        files: files,
        currentIndex: 0,
        playMode: PlayMode.shuffle,
        shuffleOrder: const [0, 3, 1, 2],
        shufflePosition: 0,
      );
      container.read(currentPlayQueueProvider.notifier).state = q1;

      // 给 Riverpod listener 一个微任务调度机会
      await Future<void>.delayed(Duration.zero);

      final raw1 = prefs.getString('last_play_queue');
      expect(raw1, isNotNull,
          reason: 'PRG-REG step1: q1 写入后 prefs[last_play_queue] 非空');
      final map1 = jsonDecode(raw1!) as Map<String, dynamic>;
      expect(map1['shufflePosition'], equals(0),
          reason: 'PRG-REG step1: 序列化保留 shufflePosition=0');

      // 2) 推进 shuffle 后写入 q2 → prefs 应被覆盖为新的 shufflePosition
      final q2 = q1.advanceShuffle()!;
      expect(q2.toMap()['shufflePosition'], equals(1));
      container.read(currentPlayQueueProvider.notifier).state = q2;

      await Future<void>.delayed(Duration.zero);

      final raw2 = prefs.getString('last_play_queue');
      expect(raw2, isNotNull,
          reason: 'PRG-REG step2: q2 写入后 prefs[last_play_queue] 仍非空');
      expect(raw2, isNot(equals(raw1)),
          reason: 'PRG-REG step2: == 不短路——shuffle 字段变化触发的 prefs 写入是新值，不是旧值');
      final map2 = jsonDecode(raw2!) as Map<String, dynamic>;
      expect(map2['shufflePosition'], equals(1),
          reason: 'PRG-REG step2: 序列化后 shufflePosition=1（确认 persist 未短路）');

      // 否定断言：q1 == q2 在 BUG-01 修复前会 true，listener 会因 == 判等
      // 跳过这个写动作，prefs 不会变。这里断言：
      //   - q1 != q2（== 已修）
      //   - prefs 真被覆盖（persist 未短路）
      expect(q1 == q2, isFalse,
          reason: '否定: q1 == q2 在 BUG-01 修复前为 true（导致 persist 短路）');
    });

    // ── PRG-REG 否定: 非 shuffle 模式不应被本次修复干扰 ───────────────────
    test('BUG-01 §7 PRG-REG 否定: 非 shuffle 模式 persist 仍按既有路径写入', () async {
      await container.read(activeConnectionProvider.future);

      final q = PlayQueue(
        files: files,
        currentIndex: 2,
        playMode: PlayMode.sequential,
        // shuffleOrder / shufflePosition = null
      );
      container.read(currentPlayQueueProvider.notifier).state = q;

      await Future<void>.delayed(Duration.zero);

      final raw = prefs.getString('last_play_queue');
      expect(raw, isNotNull, reason: '否定: 非 shuffle 模式 persist 仍写入');
      final map = jsonDecode(raw!) as Map<String, dynamic>;
      expect(map['shuffleOrder'], isNull,
          reason: '否定: 非 shuffle 模式 shuffleOrder 序列化为 null');
      expect(map['shufflePosition'], isNull,
          reason: '否定: 非 shuffle 模式 shufflePosition 序列化为 null');
      expect(map['currentIndex'], equals(2),
          reason: '否定: 非 shuffle 模式 currentIndex 字段仍正常写入');
    });
  });
}
