// test/core/services/background_service_test.dart
// TEST-08-S1/S2（SVC8）：moveTaskToBack MethodChannel 调用测试
// （spec: docs/features/TEST-08.md §3.1/§5.4）
//
// SVC8: background_service.dart 零测试覆盖。moveTaskToBack 通过
// MethodChannel 'com.example.nas_audio_player/background' 调用原生层，
// 非 Android 平台为 no-op（MissingPluginException 吞掉）。
//
// TEST-08-S1: moveTaskToBack 成功调用 MethodChannel
// TEST-08-S2: PlatformException（Activity 已销毁）→ 不产生 unhandled
//             async error（BUG-32 修复验证，TEST-08-INV1）
//
// 与 bug_bug32_repro_test.dart 的 BUG-32-S2 组互不冲突：本文件按 TEST-08
// 场景编号独立组织，复用同一 mock channel 装配模式
// （TestDefaultBinaryMessengerBinding.setMockMethodCallHandler）。

import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nas_audio_player/core/services/background_service.dart';

/// moveTaskToBack 的 MethodChannel（background_service.dart，
/// 与 test_03_home2_test.dart / bug_bug32_repro_test.dart 同源）。
const _backgroundChannel =
    MethodChannel('com.example.nas_audio_player/background');

/// 注册 mock handler 并记录调用；tearDown 时清理。
void _mockBackgroundChannel(Future<Object?> Function(MethodCall call)? handler,
    List<MethodCall> calls) {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_backgroundChannel, (call) async {
    calls.add(call);
    return handler?.call(call);
  });
  addTearDown(() => TestDefaultBinaryMessengerBinding
      .instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_backgroundChannel, null));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ── TEST-08-S1: moveTaskToBack 成功调用 ────────────────────────────────────

  group('TEST-08-S1: moveTaskToBack invokes the MethodChannel', () {
    test('TEST-08-S1: channel receives moveTaskToBack call, no unhandled error',
        () async {
      final calls = <MethodCall>[];
      _mockBackgroundChannel(null, calls);

      final unhandled = <Object>[];
      runZonedGuarded(moveTaskToBack, (e, st) => unhandled.add(e));
      await pumpEventQueue(times: 50);

      expect(calls, hasLength(1),
          reason: 'moveTaskToBack 必须调用 MethodChannel（不得静默 no-op）');
      expect(calls.single.method, 'moveTaskToBack',
          reason: '调用方法名应为 moveTaskToBack');
      // 否定断言：成功路径不产生 unhandled error。
      expect(unhandled, isEmpty);
    });
  });

  // ── TEST-08-S2: PlatformException → 不崩溃 ─────────────────────────────────

  group('TEST-08-S2: PlatformException does not crash (BUG-32)', () {
    test(
        'TEST-08-S2: native PlatformException (Activity destroyed) -> '
        'swallowed, no unhandled async error', () async {
      final calls = <MethodCall>[];
      _mockBackgroundChannel((call) async {
        throw PlatformException(code: 'ACTIVITY_DESTROYED');
      }, calls);

      final unhandled = <Object>[];
      runZonedGuarded(moveTaskToBack, (e, st) => unhandled.add(e));
      await pumpEventQueue(times: 50);

      // 否定断言（TEST-08-INV1）：PlatformException 不产生 unhandled error。
      expect(unhandled, isEmpty,
          reason: 'BUG-32 catchError 必须吞掉 PlatformException');
      expect(calls, hasLength(1));
      expect(calls.single.method, 'moveTaskToBack');
    });

    test(
        'TEST-08-S2(否定): 非 Android（无 plugin）→ MissingPluginException '
        '吞掉，no-op', () async {
      // 不注册 mock handler → invokeMethod 以 MissingPluginException 完成。
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_backgroundChannel, null);
      addTearDown(() => TestDefaultBinaryMessengerBinding
          .instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_backgroundChannel, null));

      final unhandled = <Object>[];
      runZonedGuarded(moveTaskToBack, (e, st) => unhandled.add(e));
      await pumpEventQueue(times: 50);

      expect(unhandled, isEmpty,
          reason: '非 Android no-op 路径不得产生 unhandled async error');
    });
  });
}
