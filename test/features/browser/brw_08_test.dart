// test/features/browser/brw_08_test.dart
// BRW-08: BreadcrumbBar interaction — automated test suite
//
// Widget tests (TST-T55~T58, TST-T62~T63): breadcrumb rendering, tap navigation,
//   segment count, rapid clicks
// Unit tests  (TST-T59~T61): overflow layout, navigation stack pop

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nas_audio_player/features/browser/browser_provider.dart';
import 'package:nas_audio_player/features/browser/browser_screen.dart';
import 'package:nas_audio_player/features/browser/widgets/breadcrumb_bar.dart';

import '../../helpers/test_factories.dart';

// ── Helpers ───────────────────────────────────────────────────────────────────────

// testDir() and testAudio() are imported from test_factories.dart as
// testDir() and testAudio().

/// Creates a [NavigationStackNotifier] pre-populated with [paths].
/// The notifier always starts with '/' in its constructor; [paths] should
/// include '/' as the first element for clarity.
NavigationStackNotifier _notifierWithPaths(List<String> paths) {
  final n = NavigationStackNotifier();
  for (int i = 1; i < paths.length; i++) {
    n.push(paths[i]);
  }
  return n;
}

// Common multi-level path constants for the /music/artist/album scenario.
// Directory names ("MusicDir", "ArtistDir", "AlbumDir") are intentionally
// different from the breadcrumb segment names ("music", "artist", "album")
// so that find.text() in tests does not match file-list entries.
const _root = '/';
const _l1 = '/music';
const _l2 = '/music/artist';
const _l3 = '/music/artist/album';

/// Returns overrides that simulate a 4-level navigation stack
/// (/, /music, /music/artist, /music/artist/album) with mock directory
/// contents for each level.
List<Override> _multiLevelOverrides(NavigationStackNotifier notifier) {
  return [
    navigationStackProvider.overrideWith((ref) => notifier),
    directoryContentsProvider(_root).overrideWith((ref) async => [
          testDir('MusicDir', _l1),
        ]),
    directoryContentsProvider(_l1).overrideWith((ref) async => [
          testDir('ArtistDir', _l2),
        ]),
    directoryContentsProvider(_l2).overrideWith((ref) async => [
          testDir('AlbumDir', _l3),
        ]),
    directoryContentsProvider(_l3).overrideWith((ref) async => [
          testAudio('track01.mp3', '$_l3/track01.mp3'),
        ]),
  ];
}

// ═════════════════════════════════════════════════════════════════════════════
// Widget tests — TST-T55~T58: breadcrumb rendering and tap navigation
// ═════════════════════════════════════════════════════════════════════════════

void main() {
  group('TST-T55~T58 breadcrumb rendering and navigation', () {
    // ── TST-T55: Root directory → breadcrumb shows "根目录" ─────────────────────

    testWidgets('TST-T55: root directory shows 根目录 breadcrumb',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            directoryContentsProvider(_root).overrideWith((ref) async => [
                  testDir('MusicDir', _l1),
                ]),
          ],
          child: const MaterialApp(home: Scaffold(body: BrowserScreen())),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('根目录'), findsOneWidget, reason: '根目录面包屑应显示"根目录"');
    });

    // ── TST-T56: /music/artist/album → shows full breadcrumb path ─────────────

    testWidgets(
        'TST-T56: /music/artist/album shows full breadcrumb path '
        '(根目录 > music > artist > album)', (WidgetTester tester) async {
      final notifier = _notifierWithPaths([_root, _l1, _l2, _l3]);

      await tester.pumpWidget(
        ProviderScope(
          overrides: _multiLevelOverrides(notifier),
          child: const MaterialApp(home: Scaffold(body: BrowserScreen())),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('根目录'), findsOneWidget, reason: '面包屑应包含根目录');
      expect(find.text('music'), findsOneWidget, reason: '面包屑应包含 music 段');
      expect(find.text('artist'), findsOneWidget, reason: '面包屑应包含 artist 段');
      expect(find.text('album'), findsOneWidget, reason: '面包屑应包含 album 段');
    });

    // ── TST-T57: Click "music" → popTo(/music) → dir switches to /music ─────

    testWidgets(
        'TST-T57: click music breadcrumb → popTo(/music) '
        '→ directory switches to /music', (WidgetTester tester) async {
      final notifier = _notifierWithPaths([_root, _l1, _l2, _l3]);

      await tester.pumpWidget(
        ProviderScope(
          overrides: _multiLevelOverrides(notifier),
          child: const MaterialApp(home: Scaffold(body: BrowserScreen())),
        ),
      );
      await tester.pumpAndSettle();

      // Tap "music" segment in the breadcrumb bar
      await tester.tap(find.text('music'));
      await tester.pumpAndSettle();

      // Navigation stack should be truncated to /music
      expect(notifier.state.length, equals(2),
          reason: 'popTo(/music) 后 stack 长度应为 2');
      expect(notifier.state.last, equals(_l1), reason: '当前路径应为 /music');
    });

    // ── TST-T58: Click "根目录" → popTo(/) → back to root ─────────────────────

    testWidgets(
        'TST-T58: click 根目录 breadcrumb → popTo(/) '
        '→ back to root', (WidgetTester tester) async {
      final notifier = _notifierWithPaths([_root, _l1, _l2, _l3]);

      await tester.pumpWidget(
        ProviderScope(
          overrides: _multiLevelOverrides(notifier),
          child: const MaterialApp(home: Scaffold(body: BrowserScreen())),
        ),
      );
      await tester.pumpAndSettle();

      // Tap "根目录" segment in the breadcrumb bar
      await tester.tap(find.text('根目录'));
      await tester.pumpAndSettle();

      // Navigation stack should be back to root only
      expect(notifier.state.length, equals(1),
          reason: 'popTo(/) 后 stack 长度应为 1');
      expect(notifier.state.last, equals(_root), reason: '当前路径应为根目录 /');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // Unit tests — TST-T59: overflow collapse layout
  // ═══════════════════════════════════════════════════════════════════════════

  group('TST-T59: overflow collapse layout', () {
    // ── TST-T59a: All segments fit — no overflow ──────────────────────────────

    test('TST-T59a: all segments fit within available width — no overflow', () {
      final layout = computeBreadcrumbLayout(
        segmentCount: 3,
        measuredWidths: [50, 50, 50],
        availableWidth: 300,
      );
      expect(layout.visible, equals([0, 1, 2]), reason: '所有段都应可见');
      expect(layout.collapsed, isEmpty, reason: '无溢出时不应有折叠段');
    });

    // ── TST-T59b: Overflow — middle segments collapsed, root and last visible ──

    test(
        'TST-T59b: overflow — middle segments collapsed, '
        'root and last visible', () {
      // 4 segments: widths [60, 80, 70, 60], availableWidth=260
      // Total: 60+16+80+16+70+16+60 = 318 > 260 → overflow needed.
      // Reserved left: root(60) + overflow chip(36) + sep(16) = 112
      // Remaining for right: 260 - 112 = 148
      // Index 3 (60): 60 <= 148 → rightVisible=[3], rightUsed=60
      // Index 2 (70+16=86): 60+86=146 <= 148 → rightVisible=[2,3], rightUsed=146
      // Index 1 (80+16=96): 146+96=242 > 148 ✗ → break
      // rightVisible.first=2 ≠ 1 → collapsed=[1], visible=[0,2,3]
      final layout = computeBreadcrumbLayout(
        segmentCount: 4,
        measuredWidths: [60, 80, 70, 60],
        availableWidth: 260,
      );
      expect(layout.visible, contains(0), reason: '根目录(索引 0)应始终可见');
      expect(layout.visible, contains(3), reason: '最深目录(索引 3)应始终可见');
      expect(layout.collapsed, isNotEmpty, reason: '窄宽度下中间段应折叠');
      expect(layout.collapsed, contains(1), reason: '索引 1 应被折叠到 "…" 中');
    });

    // ── TST-T59c: Only root visible when right segments are all too wide ─────

    test('TST-T59c: only root visible when right segments are all too wide',
        () {
      // 3 segments: widths [40, 200, 200], availableWidth=250
      // Total: 40+16+200+16+200 = 472 > 250
      // Reserved left: 40 + 36 + 16 = 92
      // Remaining for right: 250 - 92 = 158
      // Index 2 (200) doesn't fit → rightVisible=[] → visible=[0], collapsed=[1,2]
      final layout = computeBreadcrumbLayout(
        segmentCount: 3,
        measuredWidths: [40, 200, 200],
        availableWidth: 250,
      );
      expect(layout.visible, equals([0]), reason: '仅根目录可见');
      expect(layout.collapsed, equals([1, 2]), reason: '所有非根段应折叠');
    });

    // ── TST-T59d: 5-level path — root and last level always visible ───────────

    test('TST-T59d: 5-level overflow — root and deepest level always visible',
        () {
      final layout = computeBreadcrumbLayout(
        segmentCount: 5,
        measuredWidths: [40, 80, 90, 80, 60],
        availableWidth: 300,
      );
      // Invariant: root (index 0) must always be visible
      expect(layout.visible, contains(0), reason: '根目录(索引 0)应始终可见');
      // Invariant: deepest level (index 4) should be visible when possible
      expect(layout.visible, contains(4), reason: '最深层级(索引 4)应始终可见');
      // Middle segments may be collapsed
      expect(layout.collapsed.isNotEmpty || layout.visible.length < 5, isTrue,
          reason: '窄宽度下应有折叠或隐藏段');
    });

    // ── TST-T59e: Single segment (only root) — no overflow ────────────────────

    test('TST-T59e: single segment (only root) — no overflow', () {
      final layout = computeBreadcrumbLayout(
        segmentCount: 1,
        measuredWidths: [40],
        availableWidth: 30,
      );
      expect(layout.visible, equals([0]), reason: '单段时应可见');
      expect(layout.collapsed, isEmpty, reason: '单段时不应有折叠，即使宽度不足');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // Unit tests — TST-T60~T61: navigation stack pop (PopScope logic)
  // ═══════════════════════════════════════════════════════════════════════════

  group('TST-T60~T61: navigation stack pop', () {
    // ── TST-T60: pop() in sub-directory → back to parent ──────────────────────

    test('TST-T60: pop() in sub-directory goes back to parent directory', () {
      final notifier = NavigationStackNotifier();
      notifier.push('/music');
      notifier.push('/music/artist');
      expect(notifier.state.length, equals(3), reason: 'push 两次后应有 3 层');
      expect(notifier.state.last, equals('/music/artist'),
          reason: '当前应在 artist 子目录');

      // Simulate PopScope onPopInvokedWithResult callback: pop() the nav stack
      notifier.pop();

      expect(notifier.state.length, equals(2), reason: 'pop() 后 stack 长度应为 2');
      expect(notifier.state.last, equals('/music'),
          reason: 'pop() 后应回到上级目录 /music');
    });

    // ── TST-T61: pop() at root does nothing (PopScope allows exit) ────────────

    test('TST-T61: pop() at root does nothing — root is preserved', () {
      final notifier = NavigationStackNotifier();
      expect(notifier.state.length, equals(1), reason: '初始 stack 只有根目录');
      expect(notifier.state.last, equals('/'), reason: '当前路径为根目录');

      // PopScope.canPop = (navStack.length <= 1) is true, so the system back
      // would bypass the onPopInvokedWithResult handler.  But if the handler
      // were called, notifier.pop() should be a no-op:
      notifier.pop();

      expect(notifier.state.length, equals(1), reason: '根目录不应被移除，pop() 是空操作');
      expect(notifier.state.last, equals('/'), reason: '根目录 pop 后仍为根目录');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // Widget tests — TST-T62~T63: segment count and rapid clicks
  // ═══════════════════════════════════════════════════════════════════════════

  group('TST-T62~T63: segment count and rapid clicks', () {
    // ── TST-T62: Breadcrumb segment count == navigationStack.length ──────────

    testWidgets(
        'TST-T62: breadcrumb segment count matches navigationStack.length',
        (WidgetTester tester) async {
      // Use distinct directory names ("FolderA", "FolderB") so that
      // find.text() on breadcrumb segment names never matches a file-list
      // entry.
      const a = '/a';
      const ab = '/a/b';
      final notifier = _notifierWithPaths([_root, a, ab]);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            navigationStackProvider.overrideWith((ref) => notifier),
            directoryContentsProvider(_root).overrideWith((ref) async => [
                  testDir('FolderA', a),
                ]),
            directoryContentsProvider(a).overrideWith((ref) async => [
                  testDir('FolderB', ab),
                ]),
            directoryContentsProvider(ab).overrideWith((ref) async => [
                  testAudio('song.mp3', '$ab/song.mp3'),
                ]),
          ],
          child: const MaterialApp(home: Scaffold(body: BrowserScreen())),
        ),
      );
      await tester.pumpAndSettle();

      // 3 levels → 3 breadcrumb segments visible
      expect(notifier.state.length, equals(3));
      expect(find.text('根目录'), findsOneWidget);
      expect(find.text('a'), findsOneWidget);
      expect(find.text('b'), findsOneWidget);

      // Navigate up: pop() → stack drops to 2
      notifier.pop();
      await tester.pumpAndSettle();

      expect(notifier.state.length, equals(2), reason: 'pop 后 stack 长度应为 2');
      expect(find.text('根目录'), findsOneWidget, reason: '根目录应始终可见');
      expect(find.text('a'), findsOneWidget, reason: '/a 段应可见');
      // 'b' segment should be gone from breadcrumb.  File-list items use
      // "FolderB" so find.text('b') does not match them.
      expect(find.text('b'), findsNothing, reason: 'pop 后 b 段应消失');
    });

    // ── TST-T63: Rapid consecutive clicks on different breadcrumbs ──────────

    testWidgets(
        'TST-T63: rapid consecutive clicks on different breadcrumbs '
        '— each popTo is correct', (WidgetTester tester) async {
      final notifier = _notifierWithPaths([_root, _l1, _l2, _l3]);

      await tester.pumpWidget(
        ProviderScope(
          overrides: _multiLevelOverrides(notifier),
          child: const MaterialApp(home: Scaffold(body: BrowserScreen())),
        ),
      );
      await tester.pumpAndSettle();

      // Initial state: 4 levels deep at album
      expect(notifier.state.length, equals(4));
      expect(notifier.state.last, equals(_l3));

      // Click "artist" → popTo to /music/artist (3 levels)
      await tester.tap(find.text('artist'));
      await tester.pumpAndSettle();
      expect(notifier.state.length, equals(3),
          reason: '点击 artist 后 stack 长度应为 3');
      expect(notifier.state.last, equals(_l2), reason: '当前路径应为 /music/artist');

      // Click "music" → popTo to /music (2 levels)
      await tester.tap(find.text('music'));
      await tester.pumpAndSettle();
      expect(notifier.state.length, equals(2),
          reason: '点击 music 后 stack 长度应为 2');
      expect(notifier.state.last, equals(_l1), reason: '当前路径应为 /music');

      // Click "根目录" → popTo to / (1 level)
      await tester.tap(find.text('根目录'));
      await tester.pumpAndSettle();
      expect(notifier.state.length, equals(1), reason: '点击根目录后 stack 长度应为 1');
      expect(notifier.state.last, equals(_root), reason: '当前路径应为根目录 /');
    });
  });
}
