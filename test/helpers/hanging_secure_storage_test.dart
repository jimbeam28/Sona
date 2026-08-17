// test/helpers/hanging_secure_storage_test.dart
// REF-14 门禁测试（spec docs/features/REF-14.md §5.4 指定文件）。
//
// 锚定共享 HangingFakeSecureStorage 变体行为：
//   - S4 存在且 per-method 可配（extends FakeSecureStorage + ISecureStorage）
//   - S5 hangRead=true：read 永不完成，其余方法正常
//   - S6 hangWrite/hangDelete 各自挂起，其余正常
//   - S7 计数器对挂起与非挂起调用都 +1
//   - INV1 挂起方法返回的 Future 永不完成
//   - INV2 计数器在挂起短路之前递增

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:nas_audio_player/core/contracts/storage_contract.dart';

import 'fake_secure_storage.dart';

void main() {
  group('REF-14: HangingFakeSecureStorage', () {
    test('REF-14-S4: 类存在、extends FakeSecureStorage、per-method 可配', () {
      final storage = HangingFakeSecureStorage(
          hangRead: true, hangWrite: false, hangDelete: false);

      expect(storage, isA<FakeSecureStorage>());
      expect(storage, isA<ISecureStorage>());
      expect(storage.hangRead, isTrue);
      expect(storage.hangWrite, isFalse);
      expect(storage.hangDelete, isFalse);

      // 默认参数形态：三参均可省略
      final defaults = HangingFakeSecureStorage();
      expect(defaults.hangRead, isFalse);
      expect(defaults.hangWrite, isFalse);
      expect(defaults.hangDelete, isFalse);
    });

    test('REF-14-S4 否定: 未修改既有 Throwing 变体行为', () {
      expect(() => ThrowingFakeSecureStorage().write(key: 'k', value: 'v'),
          throwsException);
      expect(() => DeleteThrowingFakeSecureStorage().delete(key: 'k'),
          throwsException);
      expect(() => ReadThrowingFakeSecureStorage().read(key: 'k'),
          throwsException);
    });

    test('REF-14-S5: hangRead=true → read 永不完成，其余方法正常', () async {
      final storage = HangingFakeSecureStorage(hangRead: true);

      // read 永不完成 → timeout 抛 TimeoutException
      await expectLater(
        storage.read(key: 'k').timeout(const Duration(milliseconds: 1)),
        throwsA(isA<TimeoutException>()),
      );

      // 其余方法正常完成
      await storage.write(key: 'k', value: 'v');
      expect(await storage.containsKey(key: 'k'), isTrue);
      await storage.delete(key: 'k');
      expect(await storage.containsKey(key: 'k'), isFalse);
    });

    test('REF-14-S5 否定: hangRead=false 时 read 正常完成', () async {
      final storage = HangingFakeSecureStorage(hangRead: false);
      final result = await storage.read(key: 'missing');
      expect(result, isNull, reason: 'map 无值时返回 null');
    });

    test('REF-14-S6: hangWrite=true → write 永不完成，read 正常', () async {
      final storage = HangingFakeSecureStorage(hangWrite: true);

      await expectLater(
        storage
            .write(key: 'k', value: 'v')
            .timeout(const Duration(milliseconds: 1)),
        throwsA(isA<TimeoutException>()),
      );

      // 挂起 write 不得写进内存 map
      expect(storage.peek('k'), isNull, reason: '挂起 write 不得写入 map');
      expect(await storage.read(key: 'k'), isNull);
    });

    test('REF-14-S6: hangDelete=true → delete 永不完成，read/write 正常', () async {
      final storage = HangingFakeSecureStorage(hangDelete: true);

      // 先写入一个值
      await storage.write(key: 'k', value: 'v');
      expect(storage.peek('k'), 'v');

      await expectLater(
        storage.delete(key: 'k').timeout(const Duration(milliseconds: 1)),
        throwsA(isA<TimeoutException>()),
      );

      // 挂起 delete 不得触发 map 移除
      expect(storage.peek('k'), 'v', reason: '挂起 delete 不得移除 map 条目');
      expect(await storage.read(key: 'k'), 'v');
    });

    test('REF-14-S6 否定: 非挂起 write/delete 必须完成并生效', () async {
      final storage = HangingFakeSecureStorage();
      await storage.write(key: 'k', value: 'v');
      expect(storage.peek('k'), 'v');
      await storage.delete(key: 'k');
      expect(storage.peek('k'), isNull);
    });

    test('REF-14-S7: 计数器每次调用 +1（含挂起与非挂起）', () async {
      final storage = HangingFakeSecureStorage(hangRead: true);

      await expectLater(
        storage.read(key: 'a').timeout(const Duration(milliseconds: 1)),
        throwsA(isA<TimeoutException>()),
      );
      await expectLater(
        storage.read(key: 'b').timeout(const Duration(milliseconds: 1)),
        throwsA(isA<TimeoutException>()),
      );
      await storage.write(key: 'c', value: 'v');
      await storage.delete(key: 'c');

      expect(storage.readCalls, 2, reason: '挂起 read 两次也计数');
      expect(storage.writeCalls, 1);
      expect(storage.deleteCalls, 1);
    });

    test('REF-14-S7 否定: 未调用的方法计数器保持 0', () async {
      final storage = HangingFakeSecureStorage(hangRead: true);
      await storage
          .read(key: 'a')
          .timeout(const Duration(milliseconds: 1))
          .catchError((Object _) => null);
      expect(storage.writeCalls, 0);
      expect(storage.deleteCalls, 0);
    });

    test('REF-14-INV1: 挂起方法返回的 Future 永不完成（任意等待）', () async {
      final storage = HangingFakeSecureStorage(hangRead: true);
      var completed = false;
      storage.read(key: 'k').then((_) => completed = true);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(completed, isFalse, reason: 'INV1: 挂起 Future 必须永不完成');
    });

    test('REF-14-INV2: 计数器在挂起短路之前递增（挂起调用也计数）', () {
      final storage = HangingFakeSecureStorage(hangRead: true);
      expect(storage.readCalls, 0);
      storage.read(key: 'k');
      expect(storage.readCalls, 1, reason: 'INV2: 挂起调用也计数（短路前递增）');
    });
  });
}
