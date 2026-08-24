// test/features/browser/msel_01_multi_select_test.dart
// MSEL-01 浏览器批量多选 门禁测试（spec §5.4 指定位置，Agent A 先行测试）。
// 唯一事实来源：docs/features/MSEL-01.md + test/helpers。
//
// ── API 契约登记（Agent A 定义，实现方照单实现）──────────────────────────
//
// [browser_provider.dart 新增]
//   final multiSelectModeProvider = StateProvider<bool>((ref) => false);
//     面包屑区 Icons.checklist IconButton 为模式开关：tap 进入，再 tap 退出
//     （退出时必须 clear() 选择存储，spec S1）。
//
//   class MultiSelectSelectionNotifier
//       extends Notifier<Map<String, Set<String>>> {
//     // state：dirPath -> 该目录已选 filePath 集（LinkedHashMap 插入序 =
//     // 目录首次进入顺序，ALG1 组间序依据，spec §8-R1）。
//     @override
//     Map<String, Set<String>> build() => {};
//     void toggle(String dirPath, String filePath);        // 组不存在则追加
//     void selectAllCurrent(String dirPath, List<NasFile> files);
//         // 仅收录音频条目（目录/非音频过滤），幂等合并进既有组
//     void clear();                                        // 清空全部组
//     int get selectedCount;                               // 派生：所有组并集大小
//   }
//   final multiSelectSelectionProvider =
//       NotifierProvider<MultiSelectSelectionNotifier, Map<String, Set<String>>>(
//           MultiSelectSelectionNotifier.new);
//
//   // S6 注入接缝（spec §5.3「mock picker 函数注入回调断言」）：
//   typedef ShowPlaylistPicker = Future<bool> Function(
//       BuildContext context, WidgetRef ref, List<NasFile> files);
//   // 默认实现委托 BRW-01 顶层函数 _showPlaylistPickerSheet(context, ref, files)
//   //（单一实现点约束，本功能零复制粘贴 picker 逻辑）。
//   // 返回值语义：true = 本次面板操作完成了一次「添加曲目」（含新建后添加）；
//   //             false = 用户关闭面板/未选择/取消。widget 据 true 才退多选并 clear()。
//   final showPlaylistPickerProvider = Provider<ShowPlaylistPicker>((ref) => ...);
//
//   // S5 动作接缝（供 §5.3 盲点补偿的 notifier 级防御分支直调）：
//   typedef PlaySelectionAction = Future<void> Function(BuildContext context);
//   // 默认实现（镜像 onFileTap :182-192 尾段）：读 orderedSelectedFiles →
//   // store 空直接 return（零写入）；活跃连接 id 为 null 直接 return（零写入）；
//   // 否则 PlayQueue(files, currentIndex: 0).withMode(ref.read(playModeProvider))
//   // 写 currentPlayQueueProvider + lastQueueConnectionIdProvider，
//   // push '/player'，成功后 multiSelectMode=false + clear()。startPositionMs 恒 null。
//   final playSelectionProvider = Provider<PlaySelectionAction>((ref) => ...);
//
// [lib/features/browser/domain/multi_select_ordering.dart 新增]
//   List<NasFile> orderedSelectedFiles({
//     required Map<String, Set<String>> selections,
//     required List<NasFile>? Function(String dirPath) snapshotOf,
//   });
//   // ALG1 纯函数：组间序 = selections 键插入序；组内序 = snapshotOf(dir)
//   // 快照按选中 path 过滤后的相对序；快照为 null（缓存淘汰/未命中）该组回退
//   // path 字典序。任一选中 path 在结果中恰好出现一次（全局去重），无遗漏。
//   // 零 Flutter / riverpod 依赖（INV2）。

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nas_audio_player/core/database/dao/progress_dao.dart';
import 'package:nas_audio_player/features/browser/browser_provider.dart';
import 'package:nas_audio_player/features/browser/browser_screen.dart';
import 'package:nas_audio_player/features/browser/domain/multi_select_ordering.dart';
import 'package:nas_audio_player/features/connection/connection_provider.dart';
import 'package:nas_audio_player/features/player/player_provider.dart';
import 'package:nas_audio_player/features/progress/progress_provider.dart';
import 'package:nas_audio_player/shared/models/nas_file.dart';
import 'package:nas_audio_player/shared/models/play_progress.dart';
import 'package:nas_audio_player/shared/models/play_queue.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/mock_audio_player.dart';
import '../../helpers/test_factories.dart';
import '../../helpers/widget_helpers.dart';

// ═══════════════════════════════════════════════════════════════════════
// Fixtures
// ═══════════════════════════════════════════════════════════════════════

NasFile _aud(String path) => testAudio(path.split('/').last, path);

List<String> _paths(List<NasFile> files) => files.map((f) => f.path).toList();

/// 目录树桩：path -> listing，记录 fetch 调用（与 brw_01/srch_01 同款）。
class _Tree {
  final Map<String, List<NasFile>> listings = {};
  final List<String> calls = [];

  void put(String path, List<NasFile> entries) => listings[path] = entries;

  Future<List<NasFile>> fetch(String path) async {
    calls.add(path);
    return listings[path] ?? const <NasFile>[];
  }

  Override get override =>
      directoryContentsProvider.overrideWith((ref, path) => fetch(path));
}

class _MapProgressDao extends ProgressDao {
  _MapProgressDao(this._store);

  final Map<(int, String), PlayProgress> _store;

  @override
  Future<PlayProgress?> find(int connectionId, String filePath) async =>
      _store[(connectionId, filePath)];

  @override
  Future<void> delete(int connectionId, String filePath) async {
    _store.remove((connectionId, filePath));
  }
}

Future<List<Override>> _baseOverrides(
  _Tree tree, {
  Map<(int, String), PlayProgress> progress = const {},
  ConnectionConfig? Function() connection = testConnection,
}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  return [
    tree.override,
    activeConnectionProvider.overrideWith((ref) async => connection()),
    sharedPreferencesProvider.overrideWithValue(prefs),
    audioPlayerProvider.overrideWithValue(MockAudioPlayer()),
    progressDaoProvider.overrideWithValue(_MapProgressDao(progress)),
    playModeProvider.overrideWith((ref) => PlayMode.sequential),
  ];
}

Future<ProviderContainer> _pumpBrowser(
  WidgetTester tester,
  List<Override> overrides,
) async {
  await tester.pumpWidget(buildTestAppWithPlayerRoute(
    Scaffold(body: BrowserScreen()),
    overrides: overrides,
  ));
  await tester.pumpAndSettle();
  return ProviderScope.containerOf(tester.element(find.byType(BrowserScreen)));
}

/// 面包屑区 Icons.checklist 按钮 = 多选模式开关（契约锚点）。
Future<void> _toggleMode(WidgetTester tester) async {
  await tester.tap(find.byIcon(Icons.checklist));
  await tester.pumpAndSettle();
}

Finder _counter(int n) => find.textContaining(RegExp('已选\\s*$n\\s*首'));

ListTile _rowTile(WidgetTester tester, String name) =>
    tester.widget<ListTile>(find.widgetWithText(ListTile, name));

ButtonStyleButton _button(WidgetTester tester, String label) =>
    tester.widget<ButtonStyleButton>(find.ancestor(
        of: find.text(label),
        matching: find.byWidgetPredicate((w) => w is ButtonStyleButton)));

int _storedCount(Map<String, Set<String>> store) =>
    store.values.fold(0, (sum, s) => sum + s.length);

void main() {
  // ═════════════════════════════════════════════════════════════════════
  // domain: orderedSelectedFiles（MSEL-01-ALG1 纯函数，无 widget binding）
  // ═════════════════════════════════════════════════════════════════════

  group('MSEL-01 domain: orderedSelectedFiles（ALG1）', () {
    final a1 = _aud('/dirA/a1.mp3');
    final a2 = _aud('/dirA/a2.mp3');
    final a3 = _aud('/dirA/a3.mp3');

    test(
        'MSEL-01-ALG1: 黄金样例 store={dirA:{a2,a1},dirB:{b1}} dirA 快照命中 dirB 未命中 → [a1,a2,b1]',
        () {
      final store = <String, Set<String>>{
        '/dirA': {'/dirA/a2.mp3', '/dirA/a1.mp3'},
        '/dirB': {'/dirB/b1.mp3'},
      };
      List<NasFile>? snapshotOf(String dir) =>
          dir == '/dirA' ? [a1, a2, a3] : null;

      final out =
          orderedSelectedFiles(selections: store, snapshotOf: snapshotOf);

      expect(_paths(out), ['/dirA/a1.mp3', '/dirA/a2.mp3', '/dirB/b1.mp3'],
          reason: '§6 黄金样例：dirA 组内按快照相对序（非点选序），dirB 组回退字典序，'
              '组间按 store 键插入序（U7 顺序稳定可预期）');
    });

    test('MSEL-01-ALG1 变体1: 先 dirB 后 dirA 进入 → [b1, a1]（组间序跟进入顺序，不按路径名）', () {
      final store = <String, Set<String>>{
        '/dirB': {'/dirB/b1.mp3'},
        '/dirA': {'/dirA/a1.mp3'},
      };
      List<NasFile>? snapshotOf(String dir) =>
          dir == '/dirA' ? [a1, a2, a3] : null;

      final out =
          orderedSelectedFiles(selections: store, snapshotOf: snapshotOf);

      expect(_paths(out), ['/dirB/b1.mp3', '/dirA/a1.mp3'],
          reason: '§6 规则 b 反例：字典序 /dirA < /dirB，但键插入序是 dirB 在前');
    });

    test('MSEL-01-ALG1 变体2: 快照含未选 a3 → 不出现；每个选中 path 恰好一次、无遗漏', () {
      final store = <String, Set<String>>{
        '/dirA': {'/dirA/a2.mp3', '/dirA/a1.mp3'},
      };
      final out = orderedSelectedFiles(
        selections: store,
        snapshotOf: (_) => [a1, a2, a3],
      );

      expect(_paths(out), ['/dirA/a1.mp3', '/dirA/a2.mp3'],
          reason: '过滤正确性：快照中的 a3 未被勾选不得出现');
      expect(_paths(out).toSet().length, out.length,
          reason: '否定断言：任一选中 path 在结果中恰好出现一次');
      expect(_paths(out).toSet(), store.values.expand((s) => s).toSet(),
          reason: '否定断言：无选中 path 遗漏（输出集合 == 选中集合）');
    });

    test('MSEL-01-ALG1 边界: 空 store → 空结果', () {
      final out =
          orderedSelectedFiles(selections: const {}, snapshotOf: (_) => null);
      expect(out, isEmpty);
    });

    test('MSEL-01-ALG1 边界: 全组快照失效（TTL/LRU 淘汰）→ 各组回退 path 字典序', () {
      final store = <String, Set<String>>{
        '/x': {'/x/c.mp3', '/x/a.mp3', '/x/b.mp3'},
        '/y': {'/y/z.mp3', '/y/y0.mp3'},
      };
      final out =
          orderedSelectedFiles(selections: store, snapshotOf: (_) => null);

      expect(
          _paths(out),
          [
            '/x/a.mp3',
            '/x/b.mp3',
            '/x/c.mp3',
            '/y/y0.mp3',
            '/y/z.mp3',
          ],
          reason: '规则 c：快照不可用 → 组内按完整 path 字典序，组间仍按键插入序 '
              '（/x 组整体先于 /y 组）');
    });

    test('MSEL-01-ALG1 边界: 快照内重复 path 条目 / 跨组同 path → 结果恰好一次（全局去重）', () {
      final weird = [a1, _aud('/dirA/a1.mp3'), a2];
      final out1 = orderedSelectedFiles(
        selections: {
          '/dirA': {'/dirA/a1.mp3', '/dirA/a2.mp3'},
        },
        snapshotOf: (_) => weird,
      );
      expect(_paths(out1), ['/dirA/a1.mp3', '/dirA/a2.mp3'],
          reason: '异常快照数据（同 path 双条目）不得导致结果重复');

      final out2 = orderedSelectedFiles(
        selections: {
          '/g1': {'/sh/f.mp3'},
          '/g2': {'/sh/f.mp3'},
        },
        snapshotOf: (_) => null,
      );
      expect(_paths(out2), ['/sh/f.mp3'],
          reason: '跨组出现同一 path（异常数据）时全局仍恰好一次（§6 否定断言字面义）');
    });

    test('MSEL-01-S8: 排序快照变化重解析组内序，但已存选择集合本身不变（不丢不重）', () {
      final store = <String, Set<String>>{
        '/dirA': {'/dirA/a1.mp3', '/dirA/a2.mp3'},
      };
      // 旧排序（nameAsc）快照与新排序（nameDesc）快照下分别解析：
      final oldOrder =
          orderedSelectedFiles(selections: store, snapshotOf: (_) => [a1, a2]);
      final newOrder =
          orderedSelectedFiles(selections: store, snapshotOf: (_) => [a2, a1]);

      expect(_paths(oldOrder), ['/dirA/a1.mp3', '/dirA/a2.mp3']);
      expect(_paths(newOrder), ['/dirA/a2.mp3', '/dirA/a1.mp3'],
          reason: 'S8：组内序按新的排序快照解析');
      expect(store.keys.toList(), ['/dirA']);
      expect(store['/dirA'], {'/dirA/a1.mp3', '/dirA/a2.mp3'},
          reason: '否定断言：改排序不导致已存勾选丢失或重复');
    });

    test(
        'MSEL-01-INV2: multi_select_ordering.dart 纯 Dart 零 Flutter/riverpod 依赖',
        () async {
      final src = await File(
              '${Directory.current.path}/lib/features/browser/domain/multi_select_ordering.dart')
          .readAsString();
      expect(src.contains('package:flutter/'), isFalse,
          reason: 'INV2：排序解析策略必须是可独立测试的纯 Dart 函数');
      expect(src.contains('riverpod'), isFalse,
          reason: 'INV2：快照解析经 snapshotOf 回调注入，零 provider 依赖');
    });
  });

  // ═════════════════════════════════════════════════════════════════════
  // provider: 勾选存储 notifier（ProviderContainer，无 widget binding）
  // ═════════════════════════════════════════════════════════════════════

  group('MSEL-01 provider: 勾选存储 notifier', () {
    test('MSEL-01-S2: 同组重复 toggle 计数不重复；不同目录同名文件（不同 path）独立计数', () {
      final container = makeContainer(const []);
      addTearDown(container.dispose);
      final n = container.read(multiSelectSelectionProvider.notifier);

      n.toggle('/d1', '/d1/x.mp3');
      n.toggle('/d1', '/d1/x.mp3');
      expect(n.selectedCount, 1, reason: '否定断言：同一 (目录, file.path) 不会在组内重复出现');

      n.toggle('/d2', '/d2/x.mp3');
      expect(n.selectedCount, 2, reason: '不同目录的同名文件是不同 path，各自独立计数');
      final store = container.read(multiSelectSelectionProvider);
      expect(store['/d1'], {'/d1/x.mp3'});
      expect(store['/d2'], {'/d2/x.mp3'});
    });

    test('MSEL-01-S3: store 键序 = 目录首次进入顺序；向既有组 append 不重排键序', () {
      final container = makeContainer(const []);
      addTearDown(container.dispose);
      final n = container.read(multiSelectSelectionProvider.notifier);

      n.toggle('/dirA', '/dirA/A1.mp3');
      n.toggle('/dirB', '/dirB/B1.mp3');
      expect(container.read(multiSelectSelectionProvider).keys.toList(),
          ['/dirA', '/dirB'],
          reason: 'S3：键序 = [dirA, dirB]（dirA 先入，插入序语言保证）');

      n.toggle('/dirA', '/dirA/A2.mp3');
      expect(container.read(multiSelectSelectionProvider).keys.toList(),
          ['/dirA', '/dirB'],
          reason: '否定断言：返回 dirA 再勾 A2 时 dirA 组仍排在 dirB 前（append 进既有组不改键序）');
      expect(n.selectedCount, 3);

      n.clear();
      expect(container.read(multiSelectSelectionProvider), isEmpty,
          reason: 'clear() 清空全部组（S1/S5/S7 复用入口）');
      expect(n.selectedCount, 0);
    });
  });

  // ═════════════════════════════════════════════════════════════════════
  // widget: BrowserScreen 多选模式 UI 与底栏
  // ═════════════════════════════════════════════════════════════════════

  group('MSEL-01 widget: 进入/退出与勾选交互', () {
    testWidgets(
        'MSEL-01-S1: 点 checklist 进入多选 → 音频行 leading 变 Checkbox、trailing 消失、底栏浮出',
        (tester) async {
      final tree = _Tree()
        ..put('/', [
          testDir('Music', '/Music'),
          _aud('/top.mp3'),
        ]);
      await _pumpBrowser(tester, await _baseOverrides(tree));

      await _toggleMode(tester);

      expect(find.byType(Checkbox), findsOneWidget, reason: '进入后音频行出现勾选框（U1）');
      final tile = _rowTile(tester, 'top.mp3');
      expect(tile.leading, isA<Checkbox>(),
          reason: 'S1：AudioFileListTile leading 变 Checkbox');
      expect(tile.trailing, isNull, reason: 'S1/S2：trailing next-play 整体消失');
      expect(
          find.descendant(
              of: find.widgetWithText(ListTile, 'top.mp3'),
              matching: find.byType(IconButton)),
          findsNothing,
          reason: 'S2 否定断言：行内不再有任何 IconButton（onPlayNext 入口不复存在）');
      expect(_counter(0), findsOneWidget, reason: '底栏浮出且计数从 0 起');
      expect(find.text('全选'), findsOneWidget);
      expect(find.text('清除'), findsOneWidget);
      expect(find.text('加入播放单'), findsOneWidget);
      expect(find.text('以此播放'), findsOneWidget);
    });

    testWidgets('MSEL-01-S1 否定面: 退出即清空——重进无幽灵选择', (tester) async {
      final tree = _Tree()..put('/', [_aud('/top.mp3')]);
      final container = await _pumpBrowser(tester, await _baseOverrides(tree));

      await _toggleMode(tester);
      await tester.tap(find.text('top.mp3'));
      await tester.pumpAndSettle();
      expect(_counter(1), findsOneWidget, reason: '前置：已选 1 首');

      await _toggleMode(tester); // 再点 = 退出
      expect(container.read(multiSelectModeProvider), isFalse);
      expect(container.read(multiSelectSelectionProvider), isEmpty,
          reason: 'S1：退出多选模式即清空全部选择（防幽灵选择裁决）');
      expect(find.byType(Checkbox), findsNothing);
      expect(_counter(1), findsNothing);
      expect(find.text('以此播放'), findsNothing, reason: '底栏随退出消失');

      await _toggleMode(tester); // 重进
      expect(container.read(multiSelectSelectionProvider), isEmpty,
          reason: '否定断言：退出后重进选择必为空');
      expect(_counter(0), findsOneWidget);
      expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, isFalse,
          reason: '重进后勾选框视觉为未选中');
    });

    testWidgets('MSEL-01-S1 否定面: 多选模式下目录行无 Checkbox（目录不可选）', (tester) async {
      final tree = _Tree()
        ..put('/', [
          testDir('Music', '/Music'),
          _aud('/top.mp3'),
        ]);
      await _pumpBrowser(tester, await _baseOverrides(tree));

      await _toggleMode(tester);

      expect(find.byType(Checkbox), findsOneWidget, reason: '唯一勾选框属于音频行');
      expect(
          find.descendant(
              of: find.widgetWithText(ListTile, 'Music'),
              matching: find.byType(Checkbox)),
          findsNothing,
          reason: 'B3-2：DirectoryListTile 无勾选位，仅音频文件可选');
      expect(_rowTile(tester, 'Music').leading, isNot(isA<Checkbox>()));
    });

    testWidgets('MSEL-01-INV1: 多选关闭时浏览器渲染与交互路径现状等价', (tester) async {
      final tree = _Tree()
        ..put('/', [
          testDir('Music', '/Music'),
          _aud('/top.mp3'),
        ]);
      final progress = {
        (1, '/top.mp3'): testProgress(filePath: '/top.mp3', positionMs: 60000),
      };
      final container = await _pumpBrowser(
          tester, await _baseOverrides(tree, progress: progress));

      // 渲染等价：无勾选框、无底栏、trailing 在位
      expect(find.byType(Checkbox), findsNothing);
      expect(find.text('全选'), findsNothing);
      expect(find.text('以此播放'), findsNothing);
      expect(find.textContaining('已选'), findsNothing);
      final tile = _rowTile(tester, 'top.mp3');
      expect(tile.trailing, isNotNull, reason: 'INV1：next-play trailing 保持现状');
      expect(tile.leading, isNot(isA<Checkbox>()));

      // 交互路径等价：文件长按仍弹「清除播放进度」菜单（现状行为，
      // 回归网钉死：bug_12_repro_test / test_01_brw09_test / brw_04 TST-T126；
      // 「恢复播放进度」是 tap 续播对话框标题，见 progress_dialog.dart）
      await tester.longPress(find.text('top.mp3'));
      await tester.pumpAndSettle();
      expect(find.text('清除播放进度'), findsOneWidget,
          reason: 'INV1：非多选态长按交互与现状完全一致（长按=清除进度菜单）');
      expect(find.text('恢复播放进度'), findsNothing,
          reason: 'INV1 否定面：长按不得触发 tap 路径的续播对话框');

      // 关闭对话框后目录导航等价
      tester.state<NavigatorState>(find.byType(Navigator)).maybePop();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Music'));
      await tester.pumpAndSettle();
      expect(container.read(multiSelectModeProvider), isFalse);
    });
  });

  group('MSEL-01 widget: 勾选与跨目录累积', () {
    testWidgets('MSEL-01-S2: tap 音频行切换勾选、Checkbox 视觉同步、底栏计数实时更新',
        (tester) async {
      final tree = _Tree()..put('/', [_aud('/top.mp3')]);
      final container = await _pumpBrowser(tester, await _baseOverrides(tree));

      await _toggleMode(tester);
      expect(_counter(0), findsOneWidget);

      await tester.tap(find.text('top.mp3'));
      await tester.pumpAndSettle();
      expect(_counter(1), findsOneWidget, reason: 'U2：底栏计数实时变');
      expect((_rowTile(tester, 'top.mp3').leading! as Checkbox).value, isTrue,
          reason: 'S2：Checkbox 视觉同步');
      expect(_storedCount(container.read(multiSelectSelectionProvider)), 1);

      await tester.tap(find.text('top.mp3'));
      await tester.pumpAndSettle();
      expect(_counter(0), findsOneWidget);
      expect((_rowTile(tester, 'top.mp3').leading! as Checkbox).value, isFalse);
      expect(_storedCount(container.read(multiSelectSelectionProvider)), 0);
    });

    testWidgets('MSEL-01-S2 否定面: 多选模式下长按不弹进度恢复 sheet', (tester) async {
      final tree = _Tree()..put('/', [_aud('/top.mp3')]);
      final progress = {
        (1, '/top.mp3'): testProgress(filePath: '/top.mp3', positionMs: 60000),
      };
      await _pumpBrowser(
          tester, await _baseOverrides(tree, progress: progress));

      await _toggleMode(tester);
      await tester.longPress(find.text('top.mp3'));
      await tester.pumpAndSettle();

      expect(find.text('恢复播放进度'), findsNothing,
          reason: 'S2 否定断言：多选模式下 onLongPress 被禁用（tap 全部归勾选）');
      expect(find.byType(BottomSheet), findsNothing);
      expect(find.byType(Dialog), findsNothing);
    });

    testWidgets('MSEL-01-S3: 跨子目录勾选累积——进入子目录勾选、面包屑返回不丢、模式全程保持', (tester) async {
      final tree = _Tree()
        ..put('/', [
          testDir('Music', '/Music'),
          _aud('/top.mp3'),
        ])
        ..put('/Music', [
          _aud('/Music/inner1.mp3'),
          _aud('/Music/inner2.mp3'),
        ]);
      final container = await _pumpBrowser(tester, await _baseOverrides(tree));

      await _toggleMode(tester);

      // 根目录勾 1 首
      await tester.tap(find.text('top.mp3'));
      await tester.pumpAndSettle();
      expect(_counter(1), findsOneWidget);

      // 导航进子目录（push）：模式与选择保留
      await tester.tap(find.text('Music'));
      await tester.pumpAndSettle();
      expect(find.text('全选'), findsOneWidget, reason: 'U3：多选模式在子目录中保持');
      expect(_counter(1), findsOneWidget, reason: '否定断言：导航 push 不清空选择');

      // 子目录再勾 1 首：计数累计
      await tester.tap(find.text('inner1.mp3'));
      await tester.pumpAndSettle();
      expect(_counter(2), findsOneWidget, reason: 'U3：底栏计数累计');

      // 面包屑返回根目录（pop）：已勾的不丢
      await tester.tap(find.text('根目录'));
      await tester.pumpAndSettle();
      expect(_counter(2), findsOneWidget, reason: 'U3：返回上级计数仍为 2');
      expect((_rowTile(tester, 'top.mp3').leading! as Checkbox).value, isTrue,
          reason: 'U3：A1 仍勾选');
      expect(_storedCount(container.read(multiSelectSelectionProvider)), 2,
          reason: '否定断言：导航 pop 不清空选择');
      expect(container.read(multiSelectModeProvider), isTrue);
    });
  });

  group('MSEL-01 widget: 底部操作栏', () {
    testWidgets(
        'MSEL-01-S4: N==0 时「加入播放单」「以此播放」disabled（onPressed null）；N>0 enabled',
        (tester) async {
      final tree = _Tree()..put('/', [_aud('/top.mp3')]);
      await _pumpBrowser(tester, await _baseOverrides(tree));

      await _toggleMode(tester);
      expect(_button(tester, '加入播放单').onPressed, isNull,
          reason: 'S4：N==0 时加入播放单不可用');
      expect(_button(tester, '以此播放').onPressed, isNull,
          reason: 'S4：N==0 时以此播放不可达（S5 空防御的前置门禁）');

      await tester.tap(find.text('top.mp3'));
      await tester.pumpAndSettle();
      expect(_button(tester, '加入播放单').onPressed, isNotNull);
      expect(_button(tester, '以此播放').onPressed, isNotNull);
    });

    testWidgets('MSEL-01-S4: 「全选」并入当前目录全部音频且对目录条目零效果、重复点击幂等', (tester) async {
      final tree = _Tree()
        ..put('/', [
          testDir('Music', '/Music'),
          _aud('/a.mp3'),
          _aud('/b.mp3'),
          _aud('/c.mp3'),
        ]);
      final container = await _pumpBrowser(tester, await _baseOverrides(tree));

      await _toggleMode(tester);
      await tester.tap(find.text('全选'));
      await tester.pumpAndSettle();

      expect(_counter(3), findsOneWidget);
      var store = container.read(multiSelectSelectionProvider);
      expect(_storedCount(store), 3);
      expect(store.values.expand((s) => s).contains('/Music'), isFalse,
          reason: '否定断言：「全选」对目录条目零效果');

      await tester.tap(find.text('全选'));
      await tester.pumpAndSettle();
      store = container.read(multiSelectSelectionProvider);
      expect(_counter(3), findsOneWidget);
      expect(_storedCount(store), 3, reason: 'S4：已选的跳过，幂等不重复');
    });

    testWidgets('MSEL-01-S4: 「清除」清空 store 但不退出多选模式', (tester) async {
      final tree = _Tree()..put('/', [_aud('/a.mp3'), _aud('/b.mp3')]);
      final container = await _pumpBrowser(tester, await _baseOverrides(tree));

      await _toggleMode(tester);
      await tester.tap(find.text('a.mp3'));
      await tester.tap(find.text('b.mp3'));
      await tester.pumpAndSettle();
      expect(_counter(2), findsOneWidget, reason: '前置：已选 2 首');

      await tester.tap(find.text('清除'));
      await tester.pumpAndSettle();

      expect(container.read(multiSelectSelectionProvider), isEmpty,
          reason: 'S4：「清除」清空 store');
      expect(container.read(multiSelectModeProvider), isTrue,
          reason: '否定断言：「清除」不改变 multiSelectMode');
      expect(find.text('全选'), findsOneWidget, reason: '底栏仍在（模式未退）');
      expect(_counter(0), findsOneWidget);
      expect(find.byType(Checkbox), findsWidgets);
      for (final cb in tester.widgetList<Checkbox>(find.byType(Checkbox))) {
        expect(cb.value, isFalse, reason: '勾选框视觉全部复位');
      }
    });

    testWidgets('MSEL-01-S4 盲点补偿: 底栏（Container+SafeArea）不遮最后一行——滚动到底几何断言',
        (tester) async {
      final tree = _Tree()
        ..put('/', [for (var i = 0; i < 30; i++) _aud('/f$i.mp3')]);
      await _pumpBrowser(tester, await _baseOverrides(tree));

      await _toggleMode(tester);

      final barArea = find.ancestor(
          of: find.textContaining('已选'), matching: find.byType(SafeArea));
      expect(barArea, findsOneWidget,
          reason: '§8-R2 裁决：底栏为普通 Container 包 SafeArea 置于内容区尾部');

      // 滚动到列表末尾
      final scrollable = find
          .ancestor(of: find.text('f0.mp3'), matching: find.byType(Scrollable))
          .first;
      await tester.scrollUntilVisible(find.text('f29.mp3'), 200,
          scrollable: scrollable);
      await tester.pumpAndSettle();

      final barTop = tester.getTopLeft(barArea).dy;
      final lastBottom = tester.getBottomRight(find.text('f29.mp3')).dy;
      expect(lastBottom <= barTop, isTrue,
          reason: 'S4 否定断言：操作栏不遮最后一行（列表底部留有让位空间，§5.3 盲点补偿）');
    });
  });

  group('MSEL-01 widget: 以此播放（S5/INV3）', () {
    testWidgets(
        'MSEL-01-S5: 以此播放 → 按 ALG1 序（非点选序）建队 currentIndex=0、withMode(shuffle)、写队列与连接 id、退模式并清空、进播放器',
        (tester) async {
      final tree = _Tree()
        ..put('/', [
          _aud('/a.mp3'),
          _aud('/b.mp3'),
          _aud('/c.mp3'),
        ]);
      final overrides = await _baseOverrides(tree);
      overrides.add(playModeProvider.overrideWith((ref) => PlayMode.shuffle));
      final container = await _pumpBrowser(tester, overrides);

      await _toggleMode(tester);
      // 故意先点 c 再点 a：队列顺序必须按列表快照序，而非点选序（B3-5）
      await tester.tap(find.text('c.mp3'));
      await tester.tap(find.text('a.mp3'));
      await tester.pumpAndSettle();
      expect(_counter(2), findsOneWidget);

      await tester.tap(find.text('以此播放'));
      await tester.pumpAndSettle();

      expect(find.text('Player'), findsOneWidget, reason: '③ push /player');

      final queue = container.read(currentPlayQueueProvider);
      expect(queue, isNotNull, reason: '② 镜像 onFileTap 尾段写队列');
      expect(_paths(queue!.files), ['/a.mp3', '/c.mp3'],
          reason: '① files = orderedSelectedFiles（ALG1 序）：先点 c 后点 a，'
              '队列仍按列表快照相对序');
      expect(queue.currentIndex, 0, reason: '② currentIndex 恒 0（纯集合建队）');
      expect(queue.playMode, PlayMode.shuffle,
          reason: '② PlayQueue(...).withMode(ref.read(playModeProvider))：'
              '构造器默认 sequential，字段为 shuffle 即证明 withMode 被消费');
      expect(queue.startPositionMs, isNull, reason: 'startPositionMs 恒 null');
      expect(container.read(lastQueueConnectionIdProvider), 1,
          reason: '② 镜像写 lastQueueConnectionIdProvider');

      expect(container.read(playModeProvider), PlayMode.shuffle,
          reason: '否定断言：不修改 playModeProvider（只读消费）');
      expect(container.read(multiSelectModeProvider), isFalse,
          reason: '③ 成功后退出多选模式');
      expect(container.read(multiSelectSelectionProvider), isEmpty,
          reason: '③ 成功后 clear()');
    });

    testWidgets('MSEL-01-INV3: 队列写入唯一形态——startPositionMs 恒 null（含 toMap 序列化层）',
        (tester) async {
      final tree = _Tree()..put('/', [_aud('/only.mp3')]);
      final progress = {
        (1, '/only.mp3'):
            testProgress(filePath: '/only.mp3', positionMs: 42000),
      };
      final container = await _pumpBrowser(
          tester, await _baseOverrides(tree, progress: progress));

      await _toggleMode(tester);
      await tester.tap(find.text('only.mp3'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('以此播放'));
      await tester.pumpAndSettle();

      final queue = container.read(currentPlayQueueProvider);
      expect(queue, isNotNull);
      expect(queue!.startPositionMs, isNull,
          reason: 'INV3：即使被选文件存在进度记录也不查进度（文件夹入口语义族）');
      expect(queue.toMap()['startPositionMs'], isNull,
          reason: 'INV3：序列化层面同样恒 null（brw_01-INV3 同款断言）');
      expect(find.text('恢复播放进度'), findsNothing, reason: '否定断言：不弹进度恢复对话框');
    });

    testWidgets(
        'MSEL-01-S5 否定面: 活跃连接 id 为 null（竞态窗口）→ 点以此播放直接 return 零写入、不导航、状态保持',
        (tester) async {
      final tree = _Tree()..put('/', [_aud('/a.mp3')]);
      // testConfig() 无 id：镜像 onFileTap 读 conn.id 的空窗（o3 同款手法）
      final container = await _pumpBrowser(
          tester, await _baseOverrides(tree, connection: testConfig));

      await _toggleMode(tester);
      await tester.tap(find.text('a.mp3'));
      await tester.pumpAndSettle();
      expect(_counter(1), findsOneWidget, reason: '前置：N>=1 按钮可达');

      await tester.tap(find.text('以此播放'));
      await tester.pumpAndSettle();

      expect(find.text('Player'), findsNothing, reason: '不导航');
      expect(container.read(currentPlayQueueProvider), isNull,
          reason: '否定断言：currentPlayQueueProvider 零写入');
      expect(container.read(lastQueueConnectionIdProvider), isNull,
          reason: '否定断言：lastQueueConnectionIdProvider 零写入');
      expect(container.read(multiSelectModeProvider), isTrue,
          reason: '否定断言：直接 return，连模式标志也不改写');
      expect(_storedCount(container.read(multiSelectSelectionProvider)), 1,
          reason: '否定断言：选择存储原样保留');
    });

    testWidgets('MSEL-01-S5 否定面: store 为空的防御性调用 → 直接 return 零写入',
        (tester) async {
      final tree = _Tree()..put('/', [_aud('/a.mp3')]);
      final container = await _pumpBrowser(tester, await _baseOverrides(tree));
      expect(container.read(currentPlayQueueProvider), isNull);
      expect(container.read(lastQueueConnectionIdProvider), isNull);

      // 绕过 disabled 按钮直调接缝（S4 已证按钮不可达；此处验证防御分支本身）
      final context = tester.element(find.byType(BrowserScreen));
      await container.read(playSelectionProvider)(context);
      await tester.pumpAndSettle();

      expect(find.text('Player'), findsNothing);
      expect(container.read(currentPlayQueueProvider), isNull,
          reason: '否定断言：空 store 防御触发不写任何 provider');
      expect(container.read(lastQueueConnectionIdProvider), isNull);
    });
  });

  group('MSEL-01 widget: 加入播放单（S6 接缝注入）', () {
    testWidgets('MSEL-01-S6: 成功添加 → picker 收到 ALG1 序 files、成功后退多选并清空',
        (tester) async {
      final tree = _Tree()
        ..put('/', [_aud('/a.mp3'), _aud('/b.mp3'), _aud('/c.mp3')]);
      final overrides = await _baseOverrides(tree);

      final pickedCalls = <List<NasFile>>[];
      overrides.add(showPlaylistPickerProvider
          .overrideWithValue((context, ref, files) async {
        pickedCalls.add(List.of(files));
        return true; // 模拟用户在面板中完成了一次添加
      }));
      final container = await _pumpBrowser(tester, overrides);

      await _toggleMode(tester);
      await tester.tap(find.text('c.mp3'));
      await tester.tap(find.text('a.mp3'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('加入播放单'));
      await tester.pumpAndSettle();

      expect(pickedCalls, hasLength(1), reason: 'picker 被恰好转调一次');
      expect(_paths(pickedCalls.single), ['/a.mp3', '/c.mp3'],
          reason: '传入 picker 的 files 已按 ALG1 序就绪（先点 c 后点 a）');
      expect(container.read(multiSelectModeProvider), isFalse,
          reason: 'S6：成功回调后退出多选模式');
      expect(container.read(multiSelectSelectionProvider), isEmpty,
          reason: 'S6：成功回调后 clear()');
      expect(find.text('全选'), findsNothing, reason: '底栏随之消失');
    });

    testWidgets('MSEL-01-S6 否定面: 用户关闭面板（false）≠ 成功 → 保持多选态与选择不变',
        (tester) async {
      final tree = _Tree()..put('/', [_aud('/a.mp3'), _aud('/b.mp3')]);
      final overrides = await _baseOverrides(tree);

      var pickerInvocations = 0;
      overrides.add(showPlaylistPickerProvider
          .overrideWithValue((context, ref, files) async {
        pickerInvocations++;
        return false; // 用户关闭面板未选
      }));
      final container = await _pumpBrowser(tester, overrides);

      await _toggleMode(tester);
      await tester.tap(find.text('a.mp3'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('加入播放单'));
      await tester.pumpAndSettle();

      expect(pickerInvocations, 1);
      expect(container.read(multiSelectModeProvider), isTrue,
          reason: 'S6：用户关闭面板 → 保持多选态不变');
      expect(_storedCount(container.read(multiSelectSelectionProvider)), 1,
          reason: '否定断言：关闭面板不得误清选择');
      expect(_counter(1), findsOneWidget);
      expect((_rowTile(tester, 'a.mp3').leading! as Checkbox).value, isTrue);
    });
  });

  group('MSEL-01 widget: 连接切换清理（S7）', () {
    testWidgets('MSEL-01-S7: 活跃连接变更 → 自动退多选并清空 store 零残留', (tester) async {
      final tree = _Tree()..put('/', [_aud('/a.mp3'), _aud('/b.mp3')]);
      final connIdHolder = StateProvider<int>((ref) => 1);
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      await tester.pumpWidget(buildTestAppWithPlayerRoute(
        Scaffold(body: BrowserScreen()),
        overrides: [
          tree.override,
          activeConnectionProvider.overrideWith((ref) async {
            final id = ref.watch(connIdHolder);
            return testConnection(id: id);
          }),
          progressDaoProvider.overrideWithValue(_MapProgressDao(const {})),
          sharedPreferencesProvider.overrideWithValue(prefs),
          audioPlayerProvider.overrideWithValue(MockAudioPlayer()),
          playModeProvider.overrideWith((ref) => PlayMode.sequential),
        ],
      ));
      await tester.pumpAndSettle();
      final container =
          ProviderScope.containerOf(tester.element(find.byType(BrowserScreen)));

      await _toggleMode(tester);
      await tester.tap(find.text('a.mp3'));
      await tester.tap(find.text('b.mp3'));
      await tester.pumpAndSettle();
      expect(_counter(2), findsOneWidget, reason: '前置：多选态 + 非空选择');

      // 切换活跃连接 id（clearQueueOnConnectionSwitchProvider 同款联动点）
      container.read(connIdHolder.notifier).state = 2;
      await tester.pumpAndSettle();

      expect(container.read(multiSelectModeProvider), isFalse,
          reason: 'U9/S7：连接切换自动退出多选');
      expect(container.read(multiSelectSelectionProvider), isEmpty,
          reason: 'S7：store 清空');
      expect(find.byType(Checkbox), findsNothing, reason: '否定断言：切换后不残留任何勾选');
      expect(find.text('全选'), findsNothing, reason: '否定断言：底栏不残留');
      expect(find.textContaining('已选'), findsNothing);
    });
  });

  group('MSEL-01 INV4 架构约束源码扫描', () {
    test('MSEL-01-INV4: 本功能新增代码零 playlist 符号导入，播放单写入只经 BRW-01 picker 单点',
        () async {
      final providerSrc = await File(
              '${Directory.current.path}/lib/features/browser/browser_provider.dart')
          .readAsString();
      expect(providerSrc.contains('features/playlist'), isFalse,
          reason: 'INV4：browser_provider.dart 不得新增 playlist feature 导入'
              '（跨 feature 一律经 shared/di 桥或 picker 接缝）');
      expect(providerSrc.contains('addTracksToPlaylistProvider'), isFalse);
      expect(providerSrc.contains('createPlaylist'), isFalse);
      expect(providerSrc.contains('playlistServiceProvider'), isFalse);
      expect(providerSrc.contains('showPlaylistPickerProvider'), isTrue,
          reason: 'S6 接缝必须注册在 browser_provider.dart（默认实现委托 BRW-01 '
              '_showPlaylistPickerSheet 单一实现点）');

      final domainSrc = await File(
              '${Directory.current.path}/lib/features/browser/domain/multi_select_ordering.dart')
          .readAsString();
      expect(domainSrc.contains('playlist'), isFalse,
          reason: 'INV4：排序纯函数与播放单域零耦合');
    });
  });
}
