// test/features/browser/bug_14_repro_test.dart
// BUG-14: PlayQueue shuffle 状态只写不读（重启丢序列）— spec 门禁测试
//
// 来源：docs/features/BUG-14.md（cr-20260724-0110 MDL1）。
// 修复前：restoreQueueFromPrefsProvider 手工重建 PlayQueue 只读
// filePaths/currentIndex/startPositionMs/playMode，不传
// shuffleOrder/shufflePosition → 重启后序列 100% 丢失，"下一首"可重播同曲。
//
// BUG-14-S1   恢复路径传递 shuffleOrder 和 shufflePosition（不重随机）
// BUG-14-S2   恢复路径改用 PlayQueue.fromMap（不手工重建遗漏字段）
// BUG-14-INV1 toMap → fromMap round-trip 保留所有字段（含 shuffle）
// BUG-14-INV2 恢复路径与持久化路径字段一致（写 → 读回 全链路）
// + fromMap OOB/非法索引防御（BUG-14-S1 否定断言）：过滤越界元素、
//   归一失配的 shufflePosition——不 crash、降级合理。

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nas_audio_player/features/browser/browser_provider.dart';
import 'package:nas_audio_player/features/connection/connection_provider.dart';
import 'package:nas_audio_player/shared/models/connection_config.dart';
import 'package:nas_audio_player/shared/models/nas_file.dart';
import 'package:nas_audio_player/shared/models/play_queue.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/test_factories.dart';

// ── Helpers ──────────────────────────────────────────────────────────────────

const _qKey = 'last_play_queue';

List<NasFile> makeFiles(int count) => List.generate(
    count,
    (i) => testAudio('track_${(i + 1).toString().padLeft(2, '0')}.mp3',
        '/music/track_${(i + 1).toString().padLeft(2, '0')}.mp3'));

List<int> persistedOrder(PlayQueue q) =>
    (q.toMap()['shuffleOrder'] as List).cast<int>();

int persistedPosition(PlayQueue q) => q.toMap()['shufflePosition'] as int;

/// Boots [restoreQueueFromPrefsProvider] against [prefs] with the active
/// connection stubbed to null (skips the preload branch).
Future<PlayQueue?> restoreFrom(SharedPreferences prefs) async {
  final container = ProviderContainer(overrides: [
    sharedPreferencesProvider.overrideWithValue(prefs),
    activeConnectionProvider
        .overrideWith((ref) async => null as ConnectionConfig?),
  ]);
  addTearDown(container.dispose);
  await container.read(restoreQueueFromPrefsProvider.future);
  return container.read(currentPlayQueueProvider);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ═══════════════════════════════════════════════════════════════════════
  // BUG-14-S1 / S2 — 生产恢复路径读回 shuffle 状态
  // ═══════════════════════════════════════════════════════════════════════
  group('BUG-14-S1/S2: restoreQueueFromPrefsProvider reads shuffle state', () {
    test('MDL1 复现逆转: 重启恢复后序列与位置不变，"下一首"接续序列', () async {
      // cr MDL1 复现路径: 队列 [A,B,C,D] shuffle 正播 D（index 3），
      // order=[2,0,3,1] pos=2 → 重启 → 序列与位置必须原样恢复。
      SharedPreferences.setMockInitialValues({
        _qKey: jsonEncode({
          'filePaths': [
            '/music/track_01.mp3',
            '/music/track_02.mp3',
            '/music/track_03.mp3',
            '/music/track_04.mp3',
          ],
          'currentIndex': 3,
          'startPositionMs': 12345,
          'playMode': 'shuffle',
          'shuffleOrder': [2, 0, 3, 1],
          'shufflePosition': 2,
        }),
      });
      final prefs = await SharedPreferences.getInstance();

      final queue = await restoreFrom(prefs);

      expect(queue, isNotNull, reason: 'S1: 队列必须被恢复');
      expect(queue!.currentIndex, equals(3), reason: '当前曲 D 不变');
      expect(queue.startPositionMs, equals(12345));
      expect(queue.playMode, equals(PlayMode.shuffle));
      // 否定断言: 不忽略 JSON 中的 shuffle 字段、不重新随机生成排列
      expect(persistedOrder(queue), equals([2, 0, 3, 1]),
          reason: '否定断言: 排列原样读回，不得重随机');
      // 否定断言: shufflePosition 不得被重置为 0
      expect(persistedPosition(queue), equals(2),
          reason: '否定断言: 排列位置原样读回，不得复位 0');

      // BUG-14 U1: 按"下一首" → 播放 order 中 D 之后的曲目（order[3]=1 → B），
      // 而不是重播 D、也不是随机盲选
      final next = queue.advanceShuffle();
      expect(next, isNotNull, reason: '序列未耗尽，advance 必须成功');
      expect(next!.currentIndex, equals(1),
          reason: 'U1: 下一首 = order[3] = index 1（B），不重播同曲');
      expect(next.current.path, equals('/music/track_02.mp3'));
    });

    test('S2: 恢复经 PlayQueue.fromMap — sequential 队列同样不受影响', () async {
      SharedPreferences.setMockInitialValues({
        _qKey: jsonEncode({
          'filePaths': ['/music/a.mp3', '/music/b.mp3'],
          'currentIndex': 1,
          'startPositionMs': null,
          'playMode': 'sequential',
        }),
      });
      final prefs = await SharedPreferences.getInstance();

      final queue = await restoreFrom(prefs);

      expect(queue, isNotNull);
      expect(queue!.currentIndex, equals(1));
      expect(queue.playMode, equals(PlayMode.sequential));
      expect(queue.toMap().containsKey('shuffleOrder'), isFalse);
    });

    test('守卫保留: currentIndex 越界 → 不恢复（不 crash）', () async {
      SharedPreferences.setMockInitialValues({
        _qKey: jsonEncode({
          'filePaths': ['/music/a.mp3', '/music/b.mp3'],
          'currentIndex': 5,
          'playMode': 'shuffle',
          'shuffleOrder': [0, 1],
          'shufflePosition': 0,
        }),
      });
      final prefs = await SharedPreferences.getInstance();

      final queue = await restoreFrom(prefs);

      expect(queue, isNull, reason: 'idx >= files.length 守卫必须保留');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // BUG-14-INV1 / INV2 — round-trip 与写读路径一致
  // ═══════════════════════════════════════════════════════════════════════
  group('BUG-14-INV1/INV2: round-trip & write/read path consistency', () {
    test('INV1: toMap → jsonEncode/Decode → fromMap 保留全部字段（含 shuffle）', () {
      final original = PlayQueue(
        files: makeFiles(4),
        currentIndex: 3,
        startPositionMs: 45000,
        playMode: PlayMode.shuffle,
        shuffleOrder: const [2, 0, 3, 1],
        shufflePosition: 2,
      );

      final decoded =
          jsonDecode(jsonEncode(original.toMap())) as Map<String, dynamic>;
      final restored = PlayQueue.fromMap(decoded, original.files);

      expect(restored, equals(original),
          reason: 'INV1: round-trip 后 == 判等（含 shuffleOrder/Position）');
      expect(restored.hashCode, equals(original.hashCode));
      expect(persistedOrder(restored), equals([2, 0, 3, 1]));
      expect(persistedPosition(restored), equals(2));
    });

    test('INV2: persistQueueOnChangeProvider 写 → restore 读回 全链路一致', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      final original = PlayQueue(
        files: makeFiles(4),
        currentIndex: 0,
        playMode: PlayMode.shuffle,
        shuffleOrder: const [0, 2, 3, 1],
        shufflePosition: 0,
      );

      // 写路径: provider 层监听队列变更 → toMap 落 prefs
      final writer = ProviderContainer(overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
      ]);
      addTearDown(writer.dispose);
      writer.read(persistQueueOnChangeProvider); // 激活监听
      writer.read(currentPlayQueueProvider.notifier).state = original;

      final raw = prefs.getString(_qKey);
      expect(raw, isNotNull, reason: 'INV2: 队列已持久化');
      final written = jsonDecode(raw!) as Map<String, dynamic>;
      expect(written['shuffleOrder'], equals([0, 2, 3, 1]),
          reason: 'INV2: 写路径含 shuffleOrder');
      expect(written['shufflePosition'], equals(0),
          reason: 'INV2: 写路径含 shufflePosition');

      // 读路径: 重启恢复 → 与写前队列完全一致
      final restored = await restoreFrom(prefs);
      expect(restored, isNotNull);
      expect(persistedOrder(restored!), equals([0, 2, 3, 1]));
      expect(persistedPosition(restored), equals(0));
      expect(restored.currentIndex, equals(0));
      expect(restored.playMode, equals(PlayMode.shuffle));
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // fromMap OOB / 非法索引防御（BUG-14-S1 否定断言 3）
  // ═══════════════════════════════════════════════════════════════════════
  group('fromMap OOB defence (files shrunk between persist and restore)', () {
    test('越界/负数索引被过滤，合法索引保留', () {
      final map = <String, dynamic>{
        'filePaths': null,
        'currentIndex': 0,
        'playMode': 'shuffle',
        'shuffleOrder': [0, 5, 3, 1, -1],
        'shufflePosition': 1,
      };

      final restored = PlayQueue.fromMap(map, makeFiles(4));

      expect(persistedOrder(restored), equals([0, 3, 1]),
          reason: '5 与 -1 被过滤，其余按原序保留');
      expect(persistedPosition(restored), equals(1),
          reason: 'pos 仍在过滤后排列范围内 → 原样保留');
    });

    test('过滤致排列缩短 → shufflePosition 失配时重定位，不 RangeError', () {
      // 持久化时 4 首: order=[2,0,3,1] pos=3（播 index 1）；恢复时 files
      // 只剩 3 首 → 3 被过滤 → 排列 [2,0,1]，pos=3 越界。
      final map = <String, dynamic>{
        'currentIndex': 1,
        'playMode': 'shuffle',
        'shuffleOrder': [2, 0, 3, 1],
        'shufflePosition': 3,
      };

      final restored = PlayQueue.fromMap(map, makeFiles(3));

      expect(persistedOrder(restored), equals([2, 0, 1]));
      // 降级: 当前曲 index 1 仍在排列中 → 重定位到其位置
      expect(persistedPosition(restored), equals(2),
          reason: '降级: pos 重定位到 currentIndex 在排列中的位置');
      // 否定断言: 两个方向的导航都不得抛 RangeError
      expect(() => restored.advanceShuffle(), returnsNormally);
      expect(() => restored.retreatShuffle(), returnsNormally);
      final retreated = restored.retreatShuffle();
      expect(retreated, isNotNull, reason: '重定位后仍可倒退导航');
      expect(retreated!.currentIndex, equals(0));
    });

    test('失配且当前曲不在排列中 → 降级为排列末尾', () {
      // order 过滤后仅剩 [1]；currentIndex=0 不在其中。
      final map = <String, dynamic>{
        'currentIndex': 0,
        'playMode': 'shuffle',
        'shuffleOrder': [3, 1],
        'shufflePosition': 1,
      };

      final restored = PlayQueue.fromMap(map, makeFiles(2));

      expect(persistedOrder(restored), equals([1]));
      expect(persistedPosition(restored), equals(0),
          reason: '降级: indexOf(ci) == -1 → 排列末尾（length-1=0）');
      expect(() => restored.advanceShuffle(), returnsNormally);
      expect(() => restored.retreatShuffle(), returnsNormally);
    });

    test('全部索引越界 → 空排列保留（不置 null），导航惰性不 crash', () {
      final map = <String, dynamic>{
        'currentIndex': 0,
        'playMode': 'shuffle',
        'shuffleOrder': [7, 8],
        'shufflePosition': 0,
      };

      final restored = PlayQueue.fromMap(map, makeFiles(3));

      expect(persistedOrder(restored), isEmpty,
          reason: 'spec 边界裁决: 过滤后空列表保留，不置 null');
      expect(restored.advanceShuffle(), isNull, reason: '空排列 advance 惰性');
      expect(restored.retreatShuffle(), isNull, reason: '空排列 retreat 惰性');
      expect(() => restored.nextShuffleIndex(), returnsNormally);
    });

    test('order 缺失但 pos 残留 → 归一化，构造器重生成排列后 pos 不失配', () {
      final map = <String, dynamic>{
        'currentIndex': 0,
        'playMode': 'shuffle',
        'shufflePosition': 2,
      };

      final restored = PlayQueue.fromMap(map, makeFiles(4));

      // order null → 构造器重新生成排列；残留 pos 必须被归一化，不得带着
      // 旧 pos 落进新随机排列造成失配。
      final order = persistedOrder(restored);
      final pos = persistedPosition(restored);
      expect(List<int>.from(order)..sort(), equals([0, 1, 2, 3]));
      expect(pos >= 0 && pos < order.length, isTrue, reason: 'pos 必须在新排列范围内');
      expect(pos, equals(0), reason: '归一化: order 缺失时 pos 复位 0');
    });
  });
}
