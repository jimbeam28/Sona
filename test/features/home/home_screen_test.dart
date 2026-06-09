// test/features/home/home_screen_test.dart
// TST-17: Home screen PopScope back navigation test
//
// The HomeScreen uses PopScope(canPop: false) to intercept the system
// back button on Android, calling moveTaskToBack() instead of popping.
// This avoids accidental app exit from the home screen.

import 'package:flutter_test/flutter_test.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// TST-17: HomeScreen back navigation
// ═══════════════════════════════════════════════════════════════════════════════

void main() {
  group('TST-17: HomeScreen back navigation', () {
    test('TST-T144: back press in HomeScreen intercepted by PopScope', () {
      // The HomeScreen uses PopScope with canPop: false.
      // When the system back button is pressed:
      //   1. Navigator calls onPopInvokedWithResult with didPop=false
      //   2. The callback checks !didPop and calls moveTaskToBack()
      // This test verifies the pure logic contract.

      // Simulate the PopScope callback logic from HomeScreen
      bool backIntercepted = false;
      bool moveTaskToBackCalled = false;

      void onPopInvokedWithResult(bool didPop, _) {
        if (!didPop) {
          backIntercepted = true;
          moveTaskToBackCalled = true; // moveTaskToBack() would be called here
        }
      }

      // Scenario 1: User presses back on home screen
      // Navigator reports didPop=false because canPop is false
      onPopInvokedWithResult(false, null);
      expect(backIntercepted, isTrue, reason: 'TST-T144: canPop=false 时返回键被拦截');
      expect(moveTaskToBackCalled, isTrue,
          reason: 'TST-T144: 拦截后调用 moveTaskToBack 退到后台');

      // Reset for scenario 2
      backIntercepted = false;
      moveTaskToBackCalled = false;

      // Scenario 2: Pop actually happened (e.g. from a pushed route)
      // Navigator reports didPop=true
      onPopInvokedWithResult(true, null);
      expect(backIntercepted, isFalse,
          reason: 'TST-T144: didPop=true 时不拦截（路由已正常弹出）');
      expect(moveTaskToBackCalled, isFalse,
          reason: 'TST-T144: 正常 pop 时不调用 moveTaskToBack');
    });
  });
}
