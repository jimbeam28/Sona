// test/features/coverage/svc_storage_utils_test.dart
// SVC10 补充：safeStorageRead 错误降级路径（storage_utils 主测试在
// test/core/services/storage_utils_test.dart，本文件按 TEST-08 §5.4
// 门禁路径登记，覆盖 read 的错误/超时降级语义）。

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nas_audio_player/core/services/storage_utils.dart';

import '../../helpers/fake_secure_storage.dart';

void main() {
  group('SVC10 (REF-14-S10): safeStorageRead 错误/超时降级', () {
    test('read 抛异常 → 返回 null 并落日志（不向上抛）', () async {
      final storage = ReadThrowingFakeSecureStorage();
      final result = await safeStorageRead(storage, key: 'test_key');
      expect(result, isNull, reason: 'read 失败应降级为 null，不得向上抛');
    });

    test('read 超时 5s → 抛 SecureStorageTimeoutException', () {
      fakeAsync((async) {
        final storage = HangingFakeSecureStorage(hangRead: true);
        Object? error;
        safeStorageRead(storage, key: 'test_key').then((v) {
          error = 'unexpected success';
        }, onError: (Object e) {
          error = e;
        });

        async.elapse(const Duration(seconds: 4));
        expect(error, isNull, reason: '4s 时尚未超时');
        expect(storage.readCalls, equals(1));

        async.elapse(const Duration(seconds: 2));
        expect(error, isA<SecureStorageTimeoutException>(),
            reason: '5s 超时后抛 SecureStorageTimeoutException');
      });
    });
  });
}
