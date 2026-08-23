import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:mockito/mockito.dart';
import 'package:nas_audio_player/features/player/domain/play_mode.dart';
import 'package:nas_audio_player/features/player/domain/playback_orchestrator.dart';
import 'package:nas_audio_player/features/player/player_provider.dart';
import 'package:nas_audio_player/features/player/widgets/queue_sheet.dart';
import 'package:nas_audio_player/shared/di/providers.dart';
import 'package:nas_audio_player/shared/models/connection_config.dart';
import 'package:nas_audio_player/shared/models/play_queue.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/mock_audio_player.dart';
import '../../helpers/test_factories.dart';

const _qKey = 'last_play_queue';
const _qConnKey = 'last_play_queue_connection_id';

PlayQueue _queue(
  List<String> names, {
  int currentIndex = 0,
  PlayMode playMode = PlayMode.sequential,
  int? startPositionMs,
  List<int>? shuffleOrder,
  int? shufflePosition,
}) {
  return PlayQueue(
    files: names.map((n) => testAudio(n, '/music/$n')).toList(),
    currentIndex: currentIndex,
    startPositionMs: startPositionMs,
    playMode: playMode,
    shuffleOrder: shuffleOrder,
    shufflePosition: shufflePosition,
  );
}

List<String> _names(PlayQueue q) => q.files.map((f) => f.name).toList();

List<String> _paths(PlayQueue q) => q.files.map((f) => f.path).toList();

List<int>? _persistedOrder(PlayQueue q) =>
    (q.toMap()['shuffleOrder'] as List<dynamic>?)?.cast<int>();

int? _persistedPosition(PlayQueue q) => q.toMap()['shufflePosition'] as int?;

class _FixedConnection implements ActiveConnectionProvider {
  final ConnectionConfig? connection;
  _FixedConnection(this.connection);

  @override
  ConnectionConfig? get currentConnection => connection;

  @override
  Future<ConnectionConfig?> getActiveConnection() async => connection;
}

class _NoPassword implements PasswordReader {
  @override
  Future<String?> readPassword(int connectionId) async => 'secret';
}

class _RecordingProgressSaver implements ProgressSaver {
  final List<String> calls = [];

  @override
  Future<void> upsertProgress({
    required int connectionId,
    required String filePath,
    required int positionMs,
    int? durationMs,
  }) async {
    calls.add(filePath);
  }
}

class _Speed1 implements DefaultSpeedProvider {
  @override
  double getDefaultSpeed() => 1.0;
}

class _NoQueueConn implements QueueConnectionIdProvider {
  @override
  int? getLastQueueConnectionId() => null;
}

class _RecordingPlayer extends MockAudioPlayer {
  int setAudioSourceCalls = 0;
  Completer<Duration?>? hang;

  @override
  Future<Duration?> setAudioSource(
    AudioSource source, {
    bool preload = true,
    int? initialIndex,
    Duration? initialPosition,
  }) {
    setAudioSourceCalls++;
    final h = hang;
    if (h != null) return h.future;
    return Future<Duration?>.value(Duration.zero);
  }
}

class _SpyOrchestrator extends PlaybackOrchestrator {
  _SpyOrchestrator()
      : super(
          player: MockAudioPlayer(),
          connectionProvider: _FixedConnection(null),
          passwordReader: _NoPassword(),
          progressSaver: _RecordingProgressSaver(),
          defaultSpeedProvider: _Speed1(),
          queueConnectionIdProvider: _NoQueueConn(),
        );

  final List<List<int>> moves = [];
  bool result = true;

  @override
  Future<bool> moveTrack(int from, int to) async {
    moves.add([from, to]);
    return result;
  }
}

({
  PlaybackOrchestrator orchestrator,
  _RecordingPlayer player,
  _RecordingProgressSaver saver,
  List<PlayQueue?> changes,
}) _makeOrch({
  required List<String> names,
  int currentIndex = 0,
  PlayMode playMode = PlayMode.sequential,
  bool seedQueue = true,
}) {
  final player = _RecordingPlayer();
  final saver = _RecordingProgressSaver();
  final changes = <PlayQueue?>[];
  final orchestrator = PlaybackOrchestrator(
    player: player,
    connectionProvider: _FixedConnection(testConfig(id: 1, isActive: true)),
    passwordReader: _NoPassword(),
    progressSaver: saver,
    defaultSpeedProvider: _Speed1(),
    queueConnectionIdProvider: _NoQueueConn(),
  );
  if (seedQueue) {
    orchestrator.queue =
        _queue(names, currentIndex: currentIndex, playMode: playMode);
  }
  orchestrator.onQueueChanged = changes.add;
  return (
    orchestrator: orchestrator,
    player: player,
    saver: saver,
    changes: changes,
  );
}

Future<void> _pumpSheet(
  WidgetTester tester,
  PlayQueue queue, {
  void Function(int oldIndex, int newIndex)? onReorderIndex,
  Future<bool> Function(int index)? onSelectIndex,
  List<Override> extraOverrides = const [],
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        currentPlayQueueProvider.overrideWith((ref) => queue),
        ...extraOverrides,
      ],
      child: MaterialApp(
        home: Scaffold(
          body: QueueSheet(
            errorMessage: '加载失败',
            onSelectIndex: onSelectIndex ?? ((_) async => true),
            onRemoveIndex: (_) {},
            onReorderIndex: onReorderIndex,
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

ReorderableListView _listView(WidgetTester tester) =>
    tester.widget<ReorderableListView>(find.byType(ReorderableListView));

Future<void> _waitFor(bool Function() cond) async {
  for (var i = 0; i < 200 && !cond(); i++) {
    await pumpEventQueue();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PLY-01 模型层: PlayQueue.move', () {
    test('PLY-01-S1: move 基础重排返回新实例，原队列不变且不触碰播放器', () {
      final player = MockAudioPlayer();
      final q = _queue(['a.mp3', 'b.mp3', 'c.mp3', 'd.mp3'],
          currentIndex: 2, startPositionMs: 12345);

      final moved = q.move(0, 3);

      expect(identical(moved, q), isFalse, reason: '值对象语义: 返回新实例');
      expect(_names(moved), ['b.mp3', 'c.mp3', 'd.mp3', 'a.mp3']);
      expect(moved.currentIndex, 1, reason: '当前曲 C 跟随平移');
      expect(_names(q), ['a.mp3', 'b.mp3', 'c.mp3', 'd.mp3'],
          reason: '否定断言: 原 queue 对象不变');
      expect(q.currentIndex, 2);
      expect(_paths(moved).length, 4, reason: '否定断言: files.length 不变');
      expect(moved.startPositionMs, 12345);
      expect(moved.playMode, q.playMode);
      expect(_persistedOrder(moved), _persistedOrder(q));
      expect(_persistedPosition(moved), _persistedPosition(q));
      verifyZeroInteractions(player);
    });

    test('PLY-01-S2: move 当前曲自身，指针跟随移动后的位置', () {
      final q = _queue(['a.mp3', 'b.mp3', 'c.mp3', 'd.mp3'], currentIndex: 1);

      final moved = q.move(1, 3);

      expect(_names(moved), ['a.mp3', 'c.mp3', 'd.mp3', 'b.mp3']);
      expect(moved.currentIndex, 3, reason: '指针跟随 B 到队尾');
      expect(moved.current.name, 'b.mp3');
      expect(moved.currentIndex, isNot(1), reason: '否定断言: 不指向移动前位置');
    });

    test('PLY-01-S3: from==to/越界/单曲队列 → identical 短路且不抛异常', () {
      final q = _queue(['a.mp3', 'b.mp3', 'c.mp3', 'd.mp3'], currentIndex: 1);

      expect(() {
        expect(identical(q.move(1, 1), q), isTrue, reason: 'from==to 幂等');
        expect(identical(q.move(-1, 0), q), isTrue, reason: 'from 越界下界');
        expect(identical(q.move(0, -1), q), isTrue, reason: 'to 越界下界');
        expect(identical(q.move(0, 4), q), isTrue, reason: 'to 越界上界');
        expect(identical(q.move(4, 0), q), isTrue, reason: 'from 越界上界');
      }, returnsNormally, reason: '否定断言: 防御分支不得抛异常');

      expect(identical(q.move(1, 1), q), isTrue,
          reason: '否定断言: 不新建 PlayQueue 实例');

      final single = _queue(['a.mp3']);
      expect(identical(single.move(0, 0), single), isTrue,
          reason: 'length<=1 单曲短路');
    });

    test('PLY-01-S4: shuffle 队列（非空排列）模型级拒绝且排列字段不变', () {
      final q = _queue(['a.mp3', 'b.mp3', 'c.mp3', 'd.mp3'],
          currentIndex: 1,
          playMode: PlayMode.shuffle,
          shuffleOrder: const [2, 0, 3, 1],
          shufflePosition: 3);

      final moved = q.move(0, 2);

      expect(identical(moved, q), isTrue, reason: '返回 identical(this)');
      expect(_names(q), ['a.mp3', 'b.mp3', 'c.mp3', 'd.mp3'],
          reason: '否定断言: files 顺序不变');
      expect(q.currentIndex, 1);
      expect(_persistedOrder(q), const [2, 0, 3, 1],
          reason: '否定断言: shuffleOrder 不变');
      expect(_persistedPosition(q), 3, reason: '否定断言: shufflePosition 不变');
    });

    test('PLY-01-S4: shuffle 队列（空排列）同样模型级拒绝', () {
      final q = _queue(['a.mp3', 'b.mp3'],
          currentIndex: 0, playMode: PlayMode.shuffle);

      expect(identical(q.move(0, 1), q), isTrue);
      expect(_names(q), ['a.mp3', 'b.mp3']);
      expect(q.playMode, PlayMode.shuffle);
    });
  });

  group('PLY-01-ALG1: move 映射黄金样例表（spec §6）', () {
    test('PLY-01-ALG1: [A,B,C,D] c=2 move(0,3) → [B,C,D,A] c=1', () {
      final moved = _queue(['A', 'B', 'C', 'D'], currentIndex: 2).move(0, 3);
      expect(_names(moved), ['B', 'C', 'D', 'A'], reason: 'C 前移一格');
      expect(moved.currentIndex, 1);
    });

    test('PLY-01-ALG1: [A,B,C,D] c=2 move(3,0) → [D,A,B,C] c=3', () {
      final moved = _queue(['A', 'B', 'C', 'D'], currentIndex: 2).move(3, 0);
      expect(_names(moved), ['D', 'A', 'B', 'C'], reason: 'C 后移一格');
      expect(moved.currentIndex, 3);
    });

    test('PLY-01-ALG1: [A,B,C,D] c=1 move(1,3) → [A,C,D,B] c=3', () {
      final moved = _queue(['A', 'B', 'C', 'D'], currentIndex: 1).move(1, 3);
      expect(_names(moved), ['A', 'C', 'D', 'B'], reason: '当前曲自身跟随 (S2)');
      expect(moved.currentIndex, 3);
    });

    test('PLY-01-ALG1: [A,B,C,D] c=0 move(0,2) → [B,C,A,D] c=2', () {
      final moved = _queue(['A', 'B', 'C', 'D'], currentIndex: 0).move(0, 2);
      expect(_names(moved), ['B', 'C', 'A', 'D'], reason: '当前曲自身向前');
      expect(moved.currentIndex, 2);
    });

    test('PLY-01-ALG1: [A,B] c=1 move(0,1) → [B,A] c=0', () {
      final moved = _queue(['A', 'B'], currentIndex: 1).move(0, 1);
      expect(_names(moved), ['B', 'A']);
      expect(moved.currentIndex, 0);
    });

    test('PLY-01-ALG1: [A,B,C] c=1 move(1,1) → identical (幂等)', () {
      final q = _queue(['A', 'B', 'C'], currentIndex: 1);
      expect(identical(q.move(1, 1), q), isTrue);
    });

    test('PLY-01-ALG1: [A] c=0 move(0,0) → identical (单曲短路)', () {
      final q = _queue(['A']);
      expect(identical(q.move(0, 0), q), isTrue);
    });
  });

  group('PLY-01 编排层: PlaybackOrchestrator.moveTrack', () {
    test('PLY-01-S5: 顺序/repeatOne/repeatAll 任一模式下纯顺序变更', () async {
      for (final mode in [
        PlayMode.sequential,
        PlayMode.repeatOne,
        PlayMode.repeatAll,
      ]) {
        final env = _makeOrch(
          names: ['a.mp3', 'b.mp3', 'c.mp3', 'd.mp3'],
          currentIndex: 1,
          playMode: mode,
        );
        addTearDown(env.orchestrator.dispose);

        final ok = await env.orchestrator.moveTrack(0, 3);

        expect(ok, isTrue, reason: 'mode=$mode 返回 true');
        expect(_names(env.orchestrator.queue!),
            ['b.mp3', 'c.mp3', 'd.mp3', 'a.mp3'],
            reason: 'mode=$mode 队列经 setter 写回');
        expect(env.orchestrator.queue!.currentIndex, 0, reason: 'mode=$mode');
        expect(env.changes, hasLength(1),
            reason: 'mode=$mode setter 触发 onQueueChanged 同步一次');
        expect(
            _names(env.changes.single!), ['b.mp3', 'c.mp3', 'd.mp3', 'a.mp3']);
        expect(env.changes.single!.currentIndex, 0);
        expect(env.saver.calls, isEmpty,
            reason: '否定断言 mode=$mode: 不调用 saveProgress');
        expect(env.player.setAudioSourceCalls, 0,
            reason: '否定断言 mode=$mode: 不调用 setAudioSource');
        verifyNever(env.player.play());
        verifyNever(env.player.pause());
        verifyNever(env.player.stop());
        verifyNever(env.player.seek(any));
      }
    });

    test('PLY-01-S6: 队列为 null → false 且 onQueueChanged 不触发', () async {
      final env = _makeOrch(names: [], seedQueue: false);
      addTearDown(env.orchestrator.dispose);

      final ok = await env.orchestrator.moveTrack(0, 1);

      expect(ok, isFalse);
      expect(env.orchestrator.queue, isNull, reason: 'queue 字段不变');
      expect(env.changes, isEmpty, reason: '否定断言: onQueueChanged 不被触发');
    });

    test('PLY-01-S6: from/to 越界 → false 队列不变且无回调', () async {
      final env = _makeOrch(
          names: ['a.mp3', 'b.mp3', 'c.mp3', 'd.mp3'], currentIndex: 0);
      addTearDown(env.orchestrator.dispose);

      for (final (from, to) in [(-1, 2), (0, -1), (0, 4), (4, 0)]) {
        final ok = await env.orchestrator.moveTrack(from, to);
        expect(ok, isFalse, reason: '($from,$to) 越界返回 false');
        expect(_names(env.orchestrator.queue!),
            ['a.mp3', 'b.mp3', 'c.mp3', 'd.mp3'],
            reason: '($from,$to) queue 字段不变');
        expect(env.orchestrator.queue!.currentIndex, 0, reason: '($from,$to)');
      }
      expect(env.changes, isEmpty, reason: '否定断言: onQueueChanged 不被触发');
    });

    test('PLY-01-S6: queue.playMode == shuffle → false 队列不变且无回调', () async {
      final env = _makeOrch(
        names: ['a.mp3', 'b.mp3', 'c.mp3'],
        currentIndex: 1,
        playMode: PlayMode.shuffle,
      );
      addTearDown(env.orchestrator.dispose);

      final ok = await env.orchestrator.moveTrack(0, 2);

      expect(ok, isFalse);
      expect(_names(env.orchestrator.queue!), ['a.mp3', 'b.mp3', 'c.mp3'],
          reason: 'queue 字段不变');
      expect(env.orchestrator.queue!.playMode, PlayMode.shuffle);
      expect(env.changes, isEmpty, reason: '否定断言: onQueueChanged 不被触发');
    });
  });

  group('PLY-01 UI 层: QueueSheet 拖动渲染', () {
    testWidgets('PLY-01-S7: 顺序模式启用 ReorderableListView 且键/高亮/删除按钮保持',
        (tester) async {
      var reorderCalls = 0;
      await _pumpSheet(
        tester,
        _queue(['a.mp3', 'b.mp3', 'c.mp3', 'd.mp3'], currentIndex: 1),
        onReorderIndex: (_, __) => reorderCalls++,
      );

      expect(find.byType(ReorderableListView), findsOneWidget);
      final lv = _listView(tester);
      expect(lv.buildDefaultDragHandles, isTrue, reason: '整行长按拖起（默认句柄）');
      expect(lv.proxyDecorator, isNotNull, reason: '拖动中行加视觉高亮');

      final tiles = tester.widgetList<ListTile>(find.byType(ListTile)).toList();
      expect(tiles, hasLength(4));
      expect(tiles.every((t) => t.key is ValueKey<String>), isTrue);
      final keyValues =
          tiles.map((t) => (t.key as ValueKey<String>).value).toList();
      expect(
          keyValues,
          [
            '0:/music/a.mp3',
            '1:/music/b.mp3',
            '2:/music/c.mp3',
            '3:/music/d.mp3',
          ],
          reason: "否定断言: 键保持 '\$index:\${path}' 复合形态（BUG-25 不回归）");

      expect(find.text('当前'), findsOneWidget);
      final currentTile = tester.widget<ListTile>(
        find.ancestor(of: find.text('当前'), matching: find.byType(ListTile)),
      );
      expect((currentTile.title as Text).data, 'b.mp3', reason: "'当前' 高亮行为不变");
      expect(currentTile.onTap, isNull, reason: '点击当前条目仍为 no-op');
      expect(find.byIcon(Icons.close), findsNWidgets(4),
          reason: 'trailing 删除按钮不变');
      expect(reorderCalls, 0, reason: '渲染本身不得触发重排回调');
    });

    testWidgets('PLY-01-S7: 既有 onTap 切歌行为保持', (tester) async {
      final selected = <int>[];
      await _pumpSheet(
        tester,
        _queue(['a.mp3', 'b.mp3', 'c.mp3', 'd.mp3'], currentIndex: 1),
        onReorderIndex: (_, __) {},
        onSelectIndex: (i) async {
          selected.add(i);
          return true;
        },
      );

      await tester.tap(find.text('c.mp3'));
      await tester.pump();

      expect(selected, [2], reason: 'onTap 切歌转发 live index 不变');
    });

    testWidgets('PLY-01-S8: shuffle 渲染 ListView 分支并提示不可排序，重排入口全关',
        (tester) async {
      var providerCalls = 0;
      final reordered = <List<int>>[];
      await _pumpSheet(
        tester,
        _queue(['a.mp3', 'b.mp3', 'c.mp3', 'd.mp3'],
            currentIndex: 1,
            playMode: PlayMode.shuffle,
            shuffleOrder: const [1, 0, 3, 2],
            shufflePosition: 0),
        onReorderIndex: (o, n) => reordered.add([o, n]),
        extraOverrides: [
          moveTrackFromQueueProvider.overrideWith(
            (ref) => (int from, int to) async {
              providerCalls++;
              return false;
            },
          ),
        ],
      );

      expect(find.byType(ReorderableListView), findsNothing,
          reason: '保持现有 ListView.builder 分支（不可拖动）');
      expect(find.byType(ListView), findsOneWidget);
      expect(find.text('随机模式下不可排序'), findsOneWidget);

      await tester.longPress(find.text('c.mp3'));
      await tester.pump();

      expect(find.byType(ReorderableListView), findsNothing);
      expect(reordered, isEmpty, reason: '否定断言: onReorderIndex 回调不会被触发');
      expect(providerCalls, 0, reason: '否定断言: moveTrackFromQueueProvider 不被调用');
    });

    testWidgets('PLY-01-S9: 缺省 onReorderIndex 时三参构造照常渲染且不启用拖动', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentPlayQueueProvider.overrideWith(
              (ref) => _queue(['a.mp3', 'b.mp3', 'c.mp3']),
            ),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: QueueSheet(
                errorMessage: '加载失败',
                onSelectIndex: (_) async => true,
                onRemoveIndex: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(tester.takeException(), isNull,
          reason: '既有三参数签名不变（编译期即验证可选追加参数向后兼容）');
      expect(find.byType(ListTile), findsNWidgets(3));
      expect(find.byType(ReorderableListView), findsNothing,
          reason: '默认 null = 不启用拖动');
    });
  });

  group('PLY-01-ALG2: onReorder Flutter 语义校正', () {
    testWidgets('PLY-01-ALG2: old=0,new=3 下拖校正为 (0,2)', (tester) async {
      final forwarded = <List<int>>[];
      await _pumpSheet(
        tester,
        _queue(['a.mp3', 'b.mp3', 'c.mp3', 'd.mp3']),
        onReorderIndex: (o, n) => forwarded.add([o, n]),
      );

      _listView(tester).onReorder(0, 3);
      await tester.pump();

      expect(
          forwarded,
          [
            [0, 2]
          ],
          reason: 'newIndex > oldIndex 时先减 1 再转发');
    });

    testWidgets('PLY-01-ALG2: old=3,new=0 上拖保持 (3,0)', (tester) async {
      final forwarded = <List<int>>[];
      await _pumpSheet(
        tester,
        _queue(['a.mp3', 'b.mp3', 'c.mp3', 'd.mp3']),
        onReorderIndex: (o, n) => forwarded.add([o, n]),
      );

      _listView(tester).onReorder(3, 0);
      await tester.pump();

      expect(
          forwarded,
          [
            [3, 0]
          ],
          reason: '上拖不做校正');
    });

    testWidgets('PLY-01-ALG2: old==new no-op 不调用 moveTrack', (tester) async {
      final forwarded = <List<int>>[];
      await _pumpSheet(
        tester,
        _queue(['a.mp3', 'b.mp3', 'c.mp3', 'd.mp3']),
        onReorderIndex: (o, n) => forwarded.add([o, n]),
      );

      expect(() => _listView(tester).onReorder(1, 1), returnsNormally);
      await tester.pump();

      expect(forwarded, isEmpty, reason: 'old==new 不产生任何转发（no-op）');
    });
  });

  group('PLY-01 接线与持久化', () {
    testWidgets('PLY-01-S9: 弹窗宿主完成合法拖动经 onReorderIndex 转发', (tester) async {
      final forwarded = <List<int>>[];
      final q = _queue(['a.mp3', 'b.mp3', 'c.mp3', 'd.mp3']);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [currentPlayQueueProvider.overrideWith((ref) => q)],
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => Center(
                  child: ElevatedButton(
                    onPressed: () {
                      showModalBottomSheet<void>(
                        context: context,
                        isScrollControlled: true,
                        builder: (_) => QueueSheet(
                          errorMessage: '加载失败',
                          onSelectIndex: (_) async => true,
                          onRemoveIndex: (_) {},
                          onReorderIndex: (o, n) => forwarded.add([o, n]),
                        ),
                      );
                    },
                    child: const Text('Open Queue'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open Queue'));
      await tester.pumpAndSettle();

      expect(find.byType(ReorderableListView), findsOneWidget);
      _listView(tester).onReorder(1, 3);
      await tester.pump();

      expect(
          forwarded,
          [
            [1, 2]
          ],
          reason: '策略说明: QueueSheet 对新参数的消费与转发用本弹窗宿主验证；'
              '两处生产入口的接线另由源码存在性断言锚定');
    });

    test('PLY-01-S9: 两处入口源码均接线 onReorderIndex → moveTrackFromQueueProvider',
        () {
      final playerScreen =
          File('lib/features/player/player_screen.dart').readAsStringSync();
      expect(playerScreen.contains('onReorderIndex'), isTrue,
          reason: 'player_screen 入口接线存在');
      expect(playerScreen.contains('moveTrackFromQueueProvider'), isTrue,
          reason: 'player_screen 入口委托编排层 provider');

      final miniBar = File('lib/features/player/widgets/mini_player_bar.dart')
          .readAsStringSync();
      expect(miniBar.contains('onReorderIndex'), isTrue,
          reason: 'mini_player_bar 入口接线存在');
      expect(miniBar.contains('moveTrackFromQueueProvider'), isTrue,
          reason: 'mini_player_bar 入口委托编排层 provider');
    });

    test('PLY-01-S10: moveTrack 成功后 _qKey 快照更新为重排结果，connection 归属不变', () async {
      SharedPreferences.setMockInitialValues({
        _qKey: jsonEncode({
          'filePaths': ['/music/a.mp3', '/music/b.mp3', '/music/c.mp3'],
          'currentIndex': 0,
          'playMode': 'sequential',
        }),
        _qConnKey: 1,
      });
      final prefs = await SharedPreferences.getInstance();
      final container = ProviderContainer(overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        activeConnectionProvider
            .overrideWith((ref) async => testConfig(id: 1, isActive: true)),
        audioPlayerProvider.overrideWithValue(MockAudioPlayer()),
      ]);
      addTearDown(container.dispose);
      container.read(persistQueueOnChangeProvider);

      final env =
          _makeOrch(names: ['a.mp3', 'b.mp3', 'c.mp3'], currentIndex: 0);
      addTearDown(env.orchestrator.dispose);
      var syncingFromOrchestrator = false;
      env.orchestrator.onQueueChanged = (q) {
        syncingFromOrchestrator = true;
        container.read(currentPlayQueueProvider.notifier).state = q;
        syncingFromOrchestrator = false;
      };
      container.read(currentPlayQueueProvider.notifier).state =
          env.orchestrator.queue;
      container.listen<PlayQueue?>(currentPlayQueueProvider, (_, next) {
        if (!syncingFromOrchestrator) env.orchestrator.queue = next;
      });
      await pumpEventQueue();
      expect(container.read(currentPlayQueueProvider), isNotNull, reason: '前置');

      final ok = await env.orchestrator.moveTrack(0, 2);
      expect(ok, isTrue);
      await pumpEventQueue();

      final raw = prefs.getString(_qKey);
      expect(raw, isNotNull);
      final written = jsonDecode(raw!) as Map<String, dynamic>;
      expect(written['filePaths'],
          ['/music/b.mp3', '/music/c.mp3', '/music/a.mp3'],
          reason: '重排后的 filePaths 落盘（下次冷启动恢复该顺序）');
      expect(written['currentIndex'], 2);
      expect(prefs.getInt(_qConnKey), 1,
          reason: '否定断言: lastQueueConnectionId 不因重排变化；'
              '既有 ref.listen 全量写覆盖即满足落盘，无需新增持久化代码');
    });
  });

  group('PLY-01 并发安全', () {
    test('PLY-01-S11: in-flight 加载挂起期间 moveTrack 即时生效且不打断加载', () async {
      final env = _makeOrch(
        names: ['a.mp3', 'b.mp3', 'c.mp3', 'd.mp3'],
        currentIndex: 0,
      );
      addTearDown(env.orchestrator.dispose);
      final hang = Completer<Duration?>();
      env.player.hang = hang;
      when(env.player.duration).thenReturn(const Duration(minutes: 3));
      when(env.player.playing).thenReturn(true);

      final loading = env.orchestrator.selectQueueIndex(3);
      await _waitFor(() => env.player.setAudioSourceCalls == 1);
      expect(env.player.setAudioSourceCalls, 1,
          reason: '前置: X(d) 的加载已发出并挂起在 setAudioSource');
      expect(env.orchestrator.queue!.currentIndex, 3,
          reason: '前置: 目标曲 X 已定位为当前曲');
      final savesBeforeMove = env.saver.calls.length;

      final ok = await env.orchestrator.moveTrack(0, 1);
      expect(ok, isTrue, reason: '重排立即生效');
      expect(_names(env.orchestrator.queue!),
          ['b.mp3', 'a.mp3', 'c.mp3', 'd.mp3']);
      expect(env.orchestrator.queue!.currentIndex, 3, reason: 'X 仍为目标当前曲');
      expect(env.saver.calls.length, savesBeforeMove,
          reason: '否定断言: moveTrack 不产生进度写入');

      hang.complete(Duration.zero);
      final result = await loading;
      expect(result.isLoaded, isTrue,
          reason: 'X 的加载继续以 X 为目标完成（不被 superseded，gate 未被 bump）');
      expect(env.player.setAudioSourceCalls, 1,
          reason: '否定断言: X 的加载不得被替换或重复发起');
    });
  });

  group('PLY-01 不变量', () {
    test('PLY-01-INV1: move 纯重排——files 集合与四个元字段恒不变', () {
      final q = _queue(['a.mp3', 'b.mp3', 'c.mp3', 'd.mp3'],
          currentIndex: 2,
          playMode: PlayMode.repeatAll,
          startPositionMs: 45678);

      final moved = q.move(0, 3);

      expect(_paths(moved).toSet(), _paths(q).toSet(), reason: 'files 元素集合不变');
      expect(_paths(moved).length, 4, reason: 'files 数量不变');
      expect(moved.playMode, PlayMode.repeatAll);
      expect(moved.startPositionMs, 45678);
      expect(_persistedOrder(moved), isNull);
      expect(_persistedPosition(moved), isNull);
      expect(moved.currentIndex, 1, reason: '可变的只有元素顺序与 currentIndex 导出值');
    });

    test('PLY-01-INV2: moveTrackFromQueueProvider 唯一委托 orchestrator.moveTrack',
        () async {
      final spy = _SpyOrchestrator();
      addTearDown(spy.dispose);
      final container = ProviderContainer(overrides: [
        playbackOrchestratorProvider.overrideWithValue(spy),
      ]);
      addTearDown(container.dispose);

      final ok = await container.read(moveTrackFromQueueProvider)(0, 2);
      expect(ok, isTrue);
      spy.result = false;
      final ok2 = await container.read(moveTrackFromQueueProvider)(1, 1);
      expect(ok2, isFalse, reason: '编排层返回值透传，不吞并不改写');
      expect(
          spy.moves,
          [
            [0, 2],
            [1, 1],
          ],
          reason: 'provider 只做参数转发，单一写源 = orchestrator.moveTrack');
    });

    test('PLY-01-INV2: UI 与持久化桥接层不得直调 PlayQueue.move', () {
      for (final path in [
        'lib/features/player/widgets/queue_sheet.dart',
        'lib/features/player/player_screen.dart',
        'lib/features/player/widgets/mini_player_bar.dart',
        'lib/features/browser/browser_provider.dart',
      ]) {
        final src = File(path).readAsStringSync();
        expect(src.contains('.move('), isFalse,
            reason: '$path 出现直连模型重排即违反单一写源纪律'
                '（唯一合法调用方 = playback_orchestrator.moveTrack）');
      }
    });

    testWidgets('PLY-01-INV3: shuffle 双闸——模型 identical + UI 无拖动入口',
        (tester) async {
      var providerCalls = 0;
      final q = _queue(['a.mp3', 'b.mp3', 'c.mp3', 'd.mp3'],
          currentIndex: 1,
          playMode: PlayMode.shuffle,
          shuffleOrder: const [3, 2, 1, 0],
          shufflePosition: 2);

      expect(identical(q.move(0, 2), q), isTrue, reason: '模型闸 (S4)');

      await _pumpSheet(
        tester,
        q,
        onReorderIndex: (o, n) {},
        extraOverrides: [
          moveTrackFromQueueProvider.overrideWith(
            (ref) => (int from, int to) async {
              providerCalls++;
              return false;
            },
          ),
        ],
      );

      expect(find.byType(ReorderableListView), findsNothing,
          reason: 'UI 闸 (S8)');
      expect(find.text('随机模式下不可排序'), findsOneWidget);
      expect(providerCalls, 0, reason: '任意 UI 入口都无法改变 shuffle 队列顺序');
    });
  });
}
