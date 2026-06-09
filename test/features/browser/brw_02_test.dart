// test/features/browser/brw_02_test.dart
// BRW-02: 目录导航（进入/返回）— automated test suite
//
// Unit tests  (BRW-T10~T16): NavigationStackNotifier push/pop/popTo
// Unit test   (BRW-T17): computeBreadcrumbLayout overflow collapse logic

import 'package:flutter_test/flutter_test.dart';
import 'package:nas_audio_player/features/browser/browser_provider.dart';
import 'package:nas_audio_player/features/browser/widgets/breadcrumb_bar.dart'
    show computeBreadcrumbLayout;

// ═════════════════════════════════════════════════════════════════════════════
// Unit tests — BRW-T10~T17
// ═════════════════════════════════════════════════════════════════════════════

void main() {
  // ── Helpers ──────────────────────────────────────────────────────────────────

  /// Creates a [NavigationStackNotifier] and returns it along with its
  /// initial state for convenience.
  NavigationStackNotifier createNotifier() {
    return NavigationStackNotifier();
  }

  // ── BRW-T10: Initial navigation stack state ─────────────────────────────────

  test('BRW-T10: initial stack contains only root path /', () {
    final notifier = createNotifier();

    expect(notifier.state, equals(['/']), reason: '初始导航栈应只包含根路径 /');
    expect(notifier.currentPath, equals('/'), reason: 'currentPath 应返回根路径 /');
    expect(notifier.state.length, equals(1), reason: '栈深度应为 1');
  });

  // ── BRW-T11: Push subdirectory adds to stack ────────────────────────────────

  test('BRW-T11: push() appends directory path and stack size increases', () {
    final notifier = createNotifier();

    notifier.push('/music');

    expect(notifier.state, equals(['/', '/music']),
        reason: 'push /music 后栈应为 [/, /music]');
    expect(notifier.state.length, equals(2), reason: '栈大小应从 1 变为 2');
    expect(notifier.currentPath, equals('/music'),
        reason: 'currentPath 应返回最新路径 /music');
  });

  // ── BRW-T12: Multi-level directory navigation ───────────────────────────────

  test('BRW-T12: push() multiple levels records each in order', () {
    final notifier = createNotifier();

    notifier.push('/music');
    notifier.push('/music/artist');
    notifier.push('/music/artist/album');

    expect(
        notifier.state,
        equals([
          '/',
          '/music',
          '/music/artist',
          '/music/artist/album',
        ]),
        reason: '栈应按进入顺序记录每一级目录');
    expect(notifier.state.length, equals(4), reason: '进入三级子目录后栈深度应为 4');
    expect(notifier.currentPath, equals('/music/artist/album'),
        reason: 'currentPath 应返回最深路径');
  });

  // ── BRW-T13: Breadcrumb popTo truncates stack ───────────────────────────────

  test('BRW-T13: popTo() truncates stack to target, removing subsequent paths',
      () {
    final notifier = createNotifier();

    // Navigate deep
    notifier.push('/music');
    notifier.push('/music/artist');
    notifier.push('/music/artist/album');

    // Pop to /music (breadcrumb navigation)
    notifier.popTo('/music');

    expect(notifier.state, equals(['/', '/music']),
        reason: 'popTo /music 应截断栈，只保留 [/, /music]');
    expect(notifier.currentPath, equals('/music'),
        reason: 'popTo 后 currentPath 应指向目标路径');
    expect(notifier.state.length, equals(2), reason: '截断后栈深度应为 2');
  });

  // ── BRW-T14: Breadcrumb popTo root ──────────────────────────────────────────

  test('BRW-T14: popTo(/) returns stack to only root', () {
    final notifier = createNotifier();

    notifier.push('/music');
    notifier.push('/music/artist');
    notifier.push('/music/artist/album');

    notifier.popTo('/');

    expect(notifier.state, equals(['/']), reason: 'popTo / 应让栈回到只有根路径');
    expect(notifier.currentPath, equals('/'),
        reason: 'popTo 根路径后 currentPath 应为 /');
    expect(notifier.state.length, equals(1), reason: '回到根后栈深度应为 1');
  });

  // ── BRW-T15: Pop at root — stack unchanged ──────────────────────────────────

  test('BRW-T15: pop() at root does nothing, stack unchanged', () {
    final notifier = createNotifier();

    // Stack is at root ['/']
    notifier.pop();

    expect(notifier.state, equals(['/']), reason: '在根路径 pop 不应改变栈');
    expect(notifier.state.length, equals(1), reason: '在根路径 pop 后栈大小仍是 1');
    expect(notifier.currentPath, equals('/'),
        reason: '在根路径 pop 后 currentPath 仍为 /');
  });

  // ── BRW-T16: Pop from subdirectory returns to parent ────────────────────────

  test(
      'BRW-T16: pop() from subdirectory removes last element, returns to parent',
      () {
    final notifier = createNotifier();

    notifier.push('/music');
    expect(notifier.state.length, equals(2));

    notifier.pop();

    expect(notifier.state, equals(['/']), reason: '从 /music pop 应回到根路径');
    expect(notifier.currentPath, equals('/'),
        reason: 'pop 后 currentPath 应回到父目录');
    expect(notifier.state.length, equals(1), reason: 'pop 后栈大小应减少 1');
  });

  // ── BRW-T17: Breadcrumb overflow collapse logic ─────────────────────────────

  group('BRW-T17: computeBreadcrumbLayout overflow collapse', () {
    test('all segments fit — no collapse', () {
      // 3 segments: 根目录(50), music(40), artist(45)
      // Total: 50 + 40 + 45 + 2*16(separators) = 167
      final result = computeBreadcrumbLayout(
        segmentCount: 3,
        measuredWidths: [50, 40, 45],
        availableWidth: 200,
        overflowChipWidth: 36,
        separatorWidth: 16,
      );

      expect(result.visible, equals([0, 1, 2]), reason: '所有段都应可见');
      expect(result.collapsed, isEmpty, reason: '无溢出时 collapsed 应为空');
    });

    test('overflow collapses middle segments, root always visible', () {
      // 5 segments: 根(50)  A(50)  B(50)  C(50)  D(50)
      // Total all: 50*5 + 4*16 = 314, too wide for 200
      // Reserved for root + overflow chip: 50 + 36 + 16 = 102
      // Remaining for right side: 200 - 102 = 98
      // D (50) + C (50+16=66) = 116 > 98, so only D fits
      // C(50+16=66) -> D already took 50, C needs 50+16=66, 50+66=112 > 98
      final result = computeBreadcrumbLayout(
        segmentCount: 5,
        measuredWidths: [50, 50, 50, 50, 50],
        availableWidth: 200,
        overflowChipWidth: 36,
        separatorWidth: 16,
      );

      // root is index 0, D is index 4
      expect(result.visible, contains(0), reason: '根路径(index 0)应始终可见');
      expect(result.visible, contains(4), reason: '最深路径应可见');
      expect(result.collapsed, isNotEmpty, reason: '应有被折叠的段');
      // Segments 1,2,3 should be collapsed
      expect(result.collapsed.toSet(), containsAll([1, 2, 3]),
          reason: '中间的段(索引1-3)应被折叠');

      // visible + collapsed should cover all indices
      final allIndices = {...result.visible, ...result.collapsed};
      expect(allIndices, equals({0, 1, 2, 3, 4}),
          reason: 'visible ∪ collapsed 应覆盖所有索引');
      // No overlap
      final overlap =
          result.visible.toSet().intersection(result.collapsed.toSet());
      expect(overlap, isEmpty, reason: 'visible 与 collapsed 不应有重叠');
    });

    test('no gap between root and rightmost — no overflow needed', () {
      // 3 segments: 根(60), A(40), B(40)
      // Total: 60+40+40 + 2*16 = 172, fits in 200 → no overflow
      final result = computeBreadcrumbLayout(
        segmentCount: 3,
        measuredWidths: [60, 40, 40],
        availableWidth: 200,
        overflowChipWidth: 36,
        separatorWidth: 16,
      );

      expect(result.visible, equals([0, 1, 2]), reason: '总宽度未超出时应全部可见');
      expect(result.collapsed, isEmpty, reason: '总宽度未超出时不应有折叠');
    });

    test('only root and deepest fit — all middle collapsed', () {
      // 6 segments, each 80 wide. Available 200.
      // Root(80) + overflow(36) + separator(16) = 132 reserved
      // Remaining: 68 for rightmost
      // Index 5(80) > 68, can't fit
      // Wait, that means nothing fits on the right.
      // Let me use smaller widths:
      // Root(60) + overflow(36) + sep(16) = 112
      // Remaining: 200 - 112 = 88
      // Index 5(40) fits, index 4(40+16=56) -> 40+56=96 > 88, only 5 fits
      final result = computeBreadcrumbLayout(
        segmentCount: 6,
        measuredWidths: [60, 70, 70, 70, 50, 40],
        availableWidth: 200,
        overflowChipWidth: 36,
        separatorWidth: 16,
      );

      expect(result.visible, contains(0), reason: '根路径应始终可见');
      expect(result.visible, contains(5), reason: '最深路径应可见');
      expect(result.collapsed.toSet(), containsAll([1, 2, 3, 4]),
          reason: '索引 1-4 应被折叠');
      expect(result.visible.length + result.collapsed.length, equals(6),
          reason: '所有段都应被分配');
    });

    test('rightmost adjacent to root — no overflow chip needed', () {
      // 2 segments: 根(50), child(50)
      // Total: 50+50+16 = 116, fits in 200
      final result = computeBreadcrumbLayout(
        segmentCount: 2,
        measuredWidths: [50, 50],
        availableWidth: 200,
        overflowChipWidth: 36,
        separatorWidth: 16,
      );

      expect(result.visible, equals([0, 1]));
      expect(result.collapsed, isEmpty);
    });
  });
}
