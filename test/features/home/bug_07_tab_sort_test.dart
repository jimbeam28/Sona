// test/features/home/bug_07_tab_sort_test.dart
// BUG-07: AppBar 排序菜单不随 Tab 切换刷新 — spec 门禁测试
//
// spec: docs/features/BUG-07.md（来源 cr-20260724-0110.md HOME1）
//   BUG-07-S1   Tab 切换触发 AppBar actions 重建（U1: 切到浏览 Tab 出浏览排序项；
//               U2: 切回播放单 Tab 恢复播放单排序项）
//   BUG-07-INV1 AppBar 排序菜单始终对应当前活跃 Tab
//
// 否定断言：
//   - 切 Tab 后排序菜单不得残留上一个 Tab 的排序项（cr HOME1 复现路径）
//   - Tab 切换不丢失已选排序项（排序状态持久化不受影响）
//
// 所有用例 pump 真实 HomeScreen 并驱动真实 Tab 切换（tap + swipe 两条路径），
// 断言 AppBar 弹出菜单实际内容，不做回调副本自证。

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:nas_audio_player/features/browser/browser_provider.dart';
import 'package:nas_audio_player/features/home/home_screen.dart';
import 'package:nas_audio_player/features/playlist/playlist_provider.dart';
import 'package:nas_audio_player/shared/models/nas_file.dart';
import 'package:nas_audio_player/shared/models/playlist.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ── Helpers ───────────────────────────────────────────────────────────────────

Widget _buildTestApp({List<Override>? overrides}) {
  final router = GoRouter(
    initialLocation: '/home',
    routes: [
      GoRoute(
        path: '/home',
        builder: (_, __) => const HomeScreen(),
      ),
      GoRoute(
        path: '/settings',
        builder: (_, __) =>
            const Scaffold(body: Center(child: Text('Settings'))),
      ),
    ],
  );
  return ProviderScope(
    overrides: overrides ?? [],
    child: MaterialApp.router(routerConfig: router),
  );
}

List<Override> _defaultOverrides() => [
      playlistListProvider.overrideWith((ref) => Future.value(<Playlist>[])),
      directoryContentsProvider('/')
          .overrideWith((ref) => Future.value(<NasFile>[])),
    ];

/// Opens the AppBar sort popup menu (both tabs render Icons.sort).
Future<void> _openSortMenu(WidgetTester tester) async {
  await tester.tap(find.byIcon(Icons.sort));
  await tester.pumpAndSettle();
}

/// Closes the popup menu by tapping the modal barrier (bottom-left corner,
/// away from the AppBar-anchored menu).
Future<void> _closePopupMenu(WidgetTester tester) async {
  await tester.tapAt(const Offset(10, 590));
  await tester.pumpAndSettle();
}

// ═════════════════════════════════════════════════════════════════════════════
// BUG-07-S1: Tab 切换触发 AppBar actions 重建
// ═════════════════════════════════════════════════════════════════════════════

void main() {
  group('BUG-07-S1: tab switch rebuilds AppBar sort menu', () {
    // ── U1: Tab 0 → Tab 1 菜单切换为浏览器排序项 ───────────────────────────

    testWidgets('U1: 切到文件浏览 Tab 后排序菜单展示浏览器排序项，不残留播放单排序项',
        (WidgetTester tester) async {
      await tester.pumpWidget(_buildTestApp(overrides: _defaultOverrides()));
      await tester.pumpAndSettle();

      // Baseline on tab 0: playlist sort menu.
      await _openSortMenu(tester);
      expect(find.text('创建时间升序'), findsOneWidget, reason: 'Tab 0 排序菜单应含播放单排序项');
      expect(find.text('修改时间'), findsNothing, reason: 'Tab 0 排序菜单不得含浏览器专属排序项');
      await _closePopupMenu(tester);

      // Real tab switch via TabBar tap.
      await tester.tap(find.text('文件浏览器'));
      await tester.pumpAndSettle();

      await _openSortMenu(tester);
      expect(find.text('修改时间'), findsOneWidget,
          reason: 'Tab 1 排序菜单应展示浏览器排序项（BUG-07-S1）');
      expect(find.text('创建时间升序'), findsNothing,
          reason: '切 Tab 后不得残留播放单排序项（cr HOME1 复现路径）');
    });

    // ── U2: Tab 1 → Tab 0 菜单恢复播放单排序项 ─────────────────────────────

    testWidgets('U2: 切回播放单 Tab 后排序菜单恢复播放单排序项', (WidgetTester tester) async {
      await tester.pumpWidget(_buildTestApp(overrides: _defaultOverrides()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('文件浏览器'));
      await tester.pumpAndSettle();
      await _openSortMenu(tester);
      expect(find.text('修改时间'), findsOneWidget);
      await _closePopupMenu(tester);

      await tester.tap(find.text('播放单'));
      await tester.pumpAndSettle();

      await _openSortMenu(tester);
      expect(find.text('创建时间升序'), findsOneWidget,
          reason: '切回 Tab 0 排序菜单应恢复播放单排序项（BUG-07-S1 U2）');
      expect(find.text('修改时间'), findsNothing, reason: '切回 Tab 0 后不得残留浏览器专属排序项');
    });

    // ── swipe 路径：TabBarView 拖动同样触发菜单刷新 ────────────────────────

    testWidgets('swipe 切 Tab 后排序菜单同样刷新（controller.index 直设路径）',
        (WidgetTester tester) async {
      await tester.pumpWidget(_buildTestApp(overrides: _defaultOverrides()));
      await tester.pumpAndSettle();

      await tester.drag(find.byType(TabBarView), const Offset(-500, 0));
      await tester.pumpAndSettle();

      await _openSortMenu(tester);
      expect(find.text('修改时间'), findsOneWidget,
          reason: '滑动切到 Tab 1 后排序菜单应为浏览器排序项');
      expect(find.text('创建时间升序'), findsNothing, reason: '滑动切 Tab 后不得残留播放单排序项');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // BUG-07-INV1: 菜单对应活跃 Tab，且切换不丢失已选排序项
  // ═══════════════════════════════════════════════════════════════════════════

  group('BUG-07-INV1: sort menu tracks active tab without losing selection',
      () {
    testWidgets('已选播放单排序项在 Tab 往返切换后保持（勾选 + provider 状态）',
        (WidgetTester tester) async {
      await tester.pumpWidget(_buildTestApp(overrides: _defaultOverrides()));
      await tester.pumpAndSettle();

      // Select 名称升序 in the playlist sort menu.
      await _openSortMenu(tester);
      await tester.tap(find.text('名称升序'));
      await tester.pumpAndSettle();

      final container =
          ProviderScope.containerOf(tester.element(find.byType(HomeScreen)));
      expect(container.read(playlistSortProvider), PlaylistSortOption.nameAsc,
          reason: '选中项应写入 playlistSortProvider');

      // Round trip: tab 1 then back to tab 0.
      await tester.tap(find.text('文件浏览器'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('播放单'));
      await tester.pumpAndSettle();

      await _openSortMenu(tester);
      expect(container.read(playlistSortProvider), PlaylistSortOption.nameAsc,
          reason: 'Tab 切换不得丢失已选排序项（BUG-07-S1 否定断言）');
      final selectedItem = find.ancestor(
        of: find.text('名称升序'),
        matching: find.byType(PopupMenuItem<PlaylistSortOption>),
      );
      expect(
          find.descendant(of: selectedItem, matching: find.byIcon(Icons.check)),
          findsOneWidget,
          reason: '往返切换后勾选仍应在已选项上（INV1）');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // BUG-07-S1 否定断言: 持久化不受 setState 修复影响
  // ═══════════════════════════════════════════════════════════════════════════

  group('BUG-07-S1 negative: persistence unaffected by rebuild fix', () {
    testWidgets('Tab 索引写回与浏览器排序持久化在修复后保持不变', (WidgetTester tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      await tester.pumpWidget(_buildTestApp(overrides: [
        ..._defaultOverrides(),
        sharedPreferencesProvider.overrideWithValue(prefs),
      ]));
      await tester.pumpAndSettle();

      // Tab index write-back (HOM-01) still happens alongside the setState.
      await tester.tap(find.text('文件浏览器'));
      await tester.pumpAndSettle();
      expect(prefs.getInt('home_tab_index'), 1,
          reason: '监听器内 prefs 持久化必须保持（spec 边界决策）');

      // Browser sort selection persists via SortOptionNotifier.setOption.
      await _openSortMenu(tester);
      await tester.tap(find.text('修改时间'));
      await tester.pumpAndSettle();
      expect(prefs.getString('browser_sort_option'), 'modifiedDesc',
          reason: '浏览器排序持久化不受 Tab 重建影响');

      // Round trip keeps the runtime selection as well.
      await tester.tap(find.text('播放单'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('文件浏览器'));
      await tester.pumpAndSettle();

      final container =
          ProviderScope.containerOf(tester.element(find.byType(HomeScreen)));
      expect(container.read(sortOptionProvider), SortOption.modifiedDesc,
          reason: 'Tab 往返切换不得丢失已选浏览器排序项');

      await _openSortMenu(tester);
      final selectedItem = find.ancestor(
        of: find.text('修改时间'),
        matching: find.byType(PopupMenuItem<SortOption>),
      );
      expect(
          find.descendant(of: selectedItem, matching: find.byIcon(Icons.check)),
          findsOneWidget,
          reason: '往返切换后勾选仍应在已选项上（INV1）');
    });
  });
}
