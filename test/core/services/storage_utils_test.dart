// test/core/services/storage_utils_test.dart
// TEST-08-S7/S8（SVC10）：safeStorageDelete 测试
// （spec: docs/features/TEST-08.md §3.1/§5.4）
//
// SVC10: storage_utils.dart:38-48 safeStorageDelete 零测试覆盖——
// bug_10_test.dart 测试头声称覆盖 delete，但实际仅有 read/write 用例。
//
// TEST-08-S7: 正常删除 → key 移除，无异常
// TEST-08-S8: delete 挂起超过 5s → TimeoutException（TEST-08-INV2 rethrow）
//
// 装配：FakeSecureStorage（test/helpers）+ 本地挂起 fake（镜像
// bug_bug32_repro_test.dart 的 _HangingDeleteStorage）；超时用 fake_async
// 推进 5s（storage_utils 无超时参数注入，固定 5s 超时）。

import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nas_audio_player/core/contracts/storage_contract.dart';
import 'package:nas_audio_player/core/services/storage_utils.dart';

import '../../helpers/fake_secure_storage.dart';

/// Fake [ISecureStorage] whose [delete] never completes（挂起的 Keystore）。
class _HangingDeleteStorage implements ISecureStorage {
  @override
  Future<String?> read({required String key}) async => null;
  @override
  Future<void> write({required String key, required String? value}) async {}

  @override
  Future<bool> containsKey({required String key}) async => false;
  @override
  Future<void> delete({required String key}) {
    return Completer<void>().future;
  }
}

void main() {
  // ── TEST-08-S7: safeStorageDelete 正常删除 ─────────────────────────────────

  group('TEST-08-S7: safeStorageDelete 正常删除', () {
    test('TEST-08-S7: 删除后 key 被移除且不抛异常', () async {
      final storage = FakeSecureStorage()..stub('test_key', 'secret');
      expect(storage.peek('test_key'), 'secret');

      // 正常删除路径不得抛异常（当前 SVC10 问题：零测试覆盖）。
      await safeStorageDelete(storage, key: 'test_key');

      expect(storage.peek('test_key'), isNull,
          reason: '删除成功后 key 必须从 storage 中移除');
    });

    test('TEST-08-S7(否定): 不改变 read/write 行为（回归）', () async {
      final storage = FakeSecureStorage();
      // 先写后删：write 必须仍可用。
      await safeStorageWrite(storage, key: 'test_key', value: 'v');
      expect(storage.peek('test_key'), 'v');

      await safeStorageDelete(storage, key: 'test_key');
      expect(storage.peek('test_key'), isNull);

      // read 行为不受影响：删除后返回 null（无值），不抛异常。
      expect(await safeStorageRead(storage, key: 'test_key'), isNull);
    });
  });

  // ── TEST-08-S8: safeStorageDelete 超时 → TimeoutException ─────────────────

  group('TEST-08-S8: safeStorageDelete 超时', () {
    test('TEST-08-S8: delete 挂起超过 5s → TimeoutException（rethrow）', () {
      FakeAsync().run((async) {
        Object? error;
        var done = false;

        safeStorageDelete(_HangingDeleteStorage(), key: 'test_key')
            .catchError((Object e) {
          error = e;
          done = true;
        });

        // 否定断言：5s 前不得完成（超时窗未被缩短）。
        async.elapse(const Duration(seconds: 4));
        expect(done, isFalse, reason: '挂起的 delete 不得在 5s 超时前完成');

        async.elapse(const Duration(seconds: 2));
        expect(done, isTrue, reason: '超过 5s 必须完成');
        // 否定断言（TEST-08-INV2）：超时必须抛 TimeoutException，
        // 不得静默成功、不得返回 void。
        expect(error, isA<TimeoutException>(),
            reason: '超时必须以 TimeoutException 形式 rethrow（与 '
                'safeStorageWrite 一致）');
      });
    });

    test('TEST-08-S8(否定): 非超时错误不改变（delete 抛错 → 原样传播）', () {
      FakeAsync().run((async) {
        Object? error;
        var done = false;

        final throwing = _ThrowingDeleteStorage();
        safeStorageDelete(throwing, key: 'test_key').catchError((Object e) {
          error = e;
          done = true;
        });

        async.flushMicrotasks();
        expect(done, isTrue);
        expect(error, isA<Exception>(), reason: '非超时错误必须原样传播，不被吞掉');
      });
    });
  });
}

/// Fake [ISecureStorage] whose [delete] throws a non-timeout error。
class _ThrowingDeleteStorage implements ISecureStorage {
  @override
  Future<String?> read({required String key}) async => null;
  @override
  Future<void> write({required String key, required String? value}) async {}

  @override
  Future<bool> containsKey({required String key}) async => false;
  @override
  Future<void> delete({required String key}) async {
    throw Exception('simulated keystore delete failure');
  }
}
