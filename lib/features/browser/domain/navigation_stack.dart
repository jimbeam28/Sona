// lib/features/browser/domain/navigation_stack.dart
// Pure-Dart navigation stack for the Browser feature.
// Zero Flutter dependencies — only depends on dart:async for StateNotifier.

import 'package:state_notifier/state_notifier.dart';

/// Manages the directory navigation history.
///
/// The stack always contains at least one entry (the root "/").
/// Pushing a path appends it; popping removes the last entry but never
/// empties the stack past the root.
class NavigationStackNotifier extends StateNotifier<List<String>> {
  NavigationStackNotifier() : super(['/']);

  /// Navigate into the directory at [path] by pushing it onto the stack.
  void push(String path) {
    state = [...state, path];
  }

  /// Pop back to the parent directory.
  /// Does nothing when already at the root level.
  void pop() {
    if (state.length > 1) {
      state = [...state]..removeLast();
    }
  }

  /// Pop the stack back until [path] is at the top, then stop.
  /// If [path] is not in the stack, resets to root.
  void popTo(String path) {
    final index = state.indexOf(path);
    if (index >= 0) {
      state = state.sublist(0, index + 1);
    } else {
      state = ['/'];
    }
  }

  /// Returns the current (topmost) path.
  String get currentPath => state.last;
}
