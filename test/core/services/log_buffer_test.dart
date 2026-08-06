// test/core/services/log_buffer_test.dart
// REF-08: installLogBufferHook 幂等化（SVC7）— 多次调用不产生嵌套包装、
// 每条 debugPrint 消息仅被 LogBuffer 记录一次。

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nas_audio_player/core/services/log_buffer.dart';

void main() {
  group('REF-08: installLogBufferHook 幂等', () {
    test('REF-08-S1: 单次调用后 debugPrint 消息进入 LogBuffer', () {
      LogBuffer.instance.clear();
      final original = debugPrint;
      addTearDown(() {
        debugPrint = original;
      });

      installLogBufferHook();
      debugPrint('single-hook message');

      final entries = LogBuffer.instance.entries;
      expect(entries, hasLength(1), reason: '单次安装应记录一条');
      expect(entries.first.message, contains('single-hook message'));
    });

    test('REF-08-S1: 两次调用后单条消息仅记录一次（不嵌套包装）', () {
      LogBuffer.instance.clear();
      final original = debugPrint;
      addTearDown(() {
        debugPrint = original;
      });

      installLogBufferHook();
      installLogBufferHook();
      debugPrint('double-hook message');

      final entries = LogBuffer.instance.entries;
      expect(entries, hasLength(1),
          reason: 'REF-08-INV1/INV2: 多次调用不得嵌套包装，单条消息只记录一次');
      expect(entries.first.message, contains('double-hook message'));
    });

    test('REF-08-S1: 三次调用后仍只有一层包装', () {
      LogBuffer.instance.clear();
      final original = debugPrint;
      addTearDown(() {
        debugPrint = original;
      });

      installLogBufferHook();
      installLogBufferHook();
      installLogBufferHook();
      debugPrint('triple-hook message');
      debugPrint('second message');

      expect(LogBuffer.instance.entries, hasLength(2),
          reason: '两条消息各记录一次，共 2 条，而非 2/4/6 条（嵌套）');
    });

    test('REF-08-S1: null 消息不写入 LogBuffer（原行为不变）', () {
      LogBuffer.instance.clear();
      final original = debugPrint;
      addTearDown(() {
        debugPrint = original;
      });

      installLogBufferHook();
      debugPrint(null);

      expect(LogBuffer.instance.entries, isEmpty,
          reason: 'null 消息不应进 LogBuffer');
    });
  });
}
