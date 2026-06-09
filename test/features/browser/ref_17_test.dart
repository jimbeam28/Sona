// test/features/browser/ref_17_test.dart
// Tests for NavigationStackNotifier extracted to domain/navigation_stack.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:nas_audio_player/features/browser/domain/navigation_stack.dart';

void main() {
  group('NavigationStackNotifier', () {
    late NavigationStackNotifier notifier;

    setUp(() {
      notifier = NavigationStackNotifier();
    });

    tearDown(() {
      notifier.dispose();
    });

    // REF-17-T01: push appends path
    test('push appends path to the stack', () {
      expect(notifier.state, ['/']);

      notifier.push('/music');
      expect(notifier.state, ['/', '/music']);
      expect(notifier.currentPath, '/music');

      notifier.push('/music/rock');
      expect(notifier.state, ['/', '/music', '/music/rock']);
      expect(notifier.currentPath, '/music/rock');
    });

    // REF-17-T02: pop removes top of stack
    test('pop removes the topmost entry', () {
      notifier.push('/music');
      notifier.push('/music/rock');

      notifier.pop();
      expect(notifier.state, ['/', '/music']);
      expect(notifier.currentPath, '/music');

      notifier.pop();
      expect(notifier.state, ['/']);
      expect(notifier.currentPath, '/');
    });

    // REF-17-T03: popTo truncates to target
    test('popTo truncates stack back to the target path', () {
      notifier.push('/music');
      notifier.push('/music/rock');
      notifier.push('/music/rock/album');

      notifier.popTo('/music');
      expect(notifier.state, ['/', '/music']);
      expect(notifier.currentPath, '/music');
    });

    test('popTo resets to root when path is not in stack', () {
      notifier.push('/music');
      notifier.push('/music/rock');

      notifier.popTo('/nonexistent');
      expect(notifier.state, ['/']);
      expect(notifier.currentPath, '/');
    });

    // REF-17-T04: pop at root does nothing
    test('pop at root directory does nothing', () {
      expect(notifier.state, ['/']);

      notifier.pop();
      expect(notifier.state, ['/']);
      expect(notifier.currentPath, '/');
    });

    test('initial state is root', () {
      expect(notifier.state, ['/']);
      expect(notifier.currentPath, '/');
    });
  });
}
