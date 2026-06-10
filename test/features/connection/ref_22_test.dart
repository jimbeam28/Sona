// test/features/connection/ref_22_test.dart
// REF-22: Unit tests for lib/features/connection/domain/connection_service.dart
//
// Pure Dart tests — no Flutter/Riverpod dependency.
// Uses sqflite_common_ffi for an in-memory SQLite database.

import 'package:flutter_test/flutter_test.dart';
import 'package:nas_audio_player/core/database/dao/connection_dao.dart';
import 'package:nas_audio_player/features/connection/domain/connection_service.dart';

import '../../helpers/fake_secure_storage.dart';
import '../../helpers/test_database.dart';
import '../../helpers/test_factories.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    initSqfliteFfi();
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // REF-22-T01: Save success → DB + SecureStorage both written
  // ═══════════════════════════════════════════════════════════════════════════

  group('REF-22-T01: save success', () {
    late Database db;
    late ConnectionDao dao;
    late FakeSecureStorage storage;
    late ConnectionService service;

    setUp(() async {
      db = await openTestDatabase(TestSchema.connections);
      dao = ConnectionDao();
      storage = FakeSecureStorage();
      service = ConnectionService(dao, storage);
    });

    tearDown(() async {
      await db.close();
    });

    test('save writes to both DB and SecureStorage', () async {
      final config = testConfig(
        name: 'My NAS',
        url: 'http://my-nas.local:5005',
      );

      final saved = await service.save(config: config, password: 'my-secret');

      // Returned config has id and isActive=true
      expect(saved.id, isNotNull, reason: '保存后应返回带 id 的配置');
      expect(saved.isActive, isTrue, reason: '新保存的连接应为活跃状态');

      // DB: connection exists with correct fields
      final fromDb = await dao.findById(saved.id!);
      expect(fromDb, isNotNull, reason: '连接应存在于数据库中');
      expect(fromDb!.name, equals('My NAS'));
      expect(fromDb.url, equals('http://my-nas.local:5005'));
      expect(fromDb.username, equals('admin'));
      expect(fromDb.isActive, isTrue);

      // SecureStorage: password stored under permanent key
      final pw = await storage.read(key: 'connection_password_${saved.id}');
      expect(pw, equals('my-secret'), reason: '密码应写入 SecureStorage');

      // Active connection: this is the only active one
      final active = await dao.findActive();
      expect(active!.id, equals(saved.id), reason: '新保存的连接应为唯一活跃连接');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // REF-22-T02: SecureStorage failure → DB rollback
  // ═══════════════════════════════════════════════════════════════════════════

  group('REF-22-T02: SecureStorage failure → DB rollback', () {
    late Database db;
    late ConnectionDao dao;
    late ConnectionService service;

    setUp(() async {
      db = await openTestDatabase(TestSchema.connections);
      dao = ConnectionDao();
      // Pre-populate with one connection so the rollback delete does not
      // trigger LastConnectionException.
      final preExisting =
          testConfig(name: 'Pre-existing', url: 'http://pre.local:5005');
      await dao.insert(preExisting, passwordKey: 'key_pre');
    });

    tearDown(() async {
      await db.close();
    });

    test('secure storage write failure rolls back DB insert', () async {
      final throwingStorage = ThrowingFakeSecureStorage();
      service = ConnectionService(dao, throwingStorage);

      final newConfig = testConfig(
        name: 'New NAS',
        url: 'http://new.local:5005',
      );

      // Attempt to save — secure storage write will fail
      try {
        await service.save(config: newConfig, password: 'secret');
        fail('Expected save to throw due to secure storage failure');
      } catch (_) {
        // Expected
      }

      // Verify: the new connection was NOT persisted (DB was rolled back)
      final all = await dao.findAll();
      final newConn = all.where((c) => c.name == 'New NAS');
      expect(newConn, isEmpty, reason: 'SecureStorage 失败后 DB 行应回滚，连接不应存在');
      expect(all.length, equals(1), reason: '只有预填充的连接应保留');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // REF-22-T03: Delete last connection → LastConnectionException
  // ═══════════════════════════════════════════════════════════════════════════

  group('REF-22-T03: delete last connection → LastConnectionException', () {
    late Database db;
    late ConnectionDao dao;
    late FakeSecureStorage storage;
    late ConnectionService service;

    setUp(() async {
      db = await openTestDatabase(TestSchema.connections);
      dao = ConnectionDao();
      storage = FakeSecureStorage();
      service = ConnectionService(dao, storage);
    });

    tearDown(() async {
      await db.close();
    });

    test('deleting the only connection throws LastConnectionException',
        () async {
      // Insert a single connection
      final config =
          testConfig(name: 'Only NAS', url: 'http://only.local:5005');
      final id = await dao.insert(config, passwordKey: 'key_only');
      storage.stub('connection_password_$id', 'pw');

      // Attempt to delete — should throw
      expect(
        () => service.delete(id),
        throwsA(isA<LastConnectionException>()),
        reason: '删除最后一个连接应抛出 LastConnectionException',
      );

      // Verify: connection still exists
      final remaining = await dao.findAll();
      expect(remaining.length, equals(1), reason: '连接应仍然存在');
      expect(remaining.first.name, equals('Only NAS'));
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // REF-22-T04: Delete active connection → auto-activate another
  // ═══════════════════════════════════════════════════════════════════════════

  group('REF-22-T04: delete active connection → auto-activate another', () {
    late Database db;
    late ConnectionDao dao;
    late FakeSecureStorage storage;
    late ConnectionService service;
    late int conn1Id;
    late int conn2Id;

    setUp(() async {
      db = await openTestDatabase(TestSchema.connections);
      dao = ConnectionDao();
      storage = FakeSecureStorage();
      service = ConnectionService(dao, storage);

      final c1 = testConfig(name: 'NAS-1', url: 'http://nas1.local:5005');
      final c2 = testConfig(name: 'NAS-2', url: 'http://nas2.local:5005');
      conn1Id = await dao.insert(c1, passwordKey: 'key_1');
      conn2Id = await dao.insert(c2, passwordKey: 'key_2');
      await dao.setActive(conn1Id);
      storage.setPassword(conn1Id, 'pw1');
      storage.setPassword(conn2Id, 'pw2');
    });

    tearDown(() async {
      await db.close();
    });

    test('deleting active connection auto-activates remaining one', () async {
      // Verify conn1 is active before delete
      final before = await dao.findActive();
      expect(before!.id, equals(conn1Id), reason: 'conn1 应为活跃连接');

      // Delete conn1 (which is active)
      await service.delete(conn1Id);

      // Verify: conn2 is now active
      final after = await dao.findActive();
      expect(after, isNotNull, reason: '删除活跃连接后应自动激活另一个');
      expect(after!.id, equals(conn2Id), reason: 'conn2 应被自动设为活跃连接');
      expect(after.name, equals('NAS-2'));

      // Verify: conn1's password was removed from secure storage
      final deletedPw = await storage.read(key: 'connection_password_$conn1Id');
      expect(deletedPw, isNull, reason: '已删除连接的密码应从 SecureStorage 中移除');

      // Verify: conn2's password is still present
      final keptPw = await storage.read(key: 'connection_password_$conn2Id');
      expect(keptPw, equals('pw2'), reason: '未删除连接的密码应保留');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // REF-22-T05: Switch connection → transaction guarantees single active
  // ═══════════════════════════════════════════════════════════════════════════

  group('REF-22-T05: switch connection → single active', () {
    late Database db;
    late ConnectionDao dao;
    late FakeSecureStorage storage;
    late ConnectionService service;
    late int conn1Id;
    late int conn2Id;

    setUp(() async {
      db = await openTestDatabase(TestSchema.connections);
      dao = ConnectionDao();
      storage = FakeSecureStorage();
      service = ConnectionService(dao, storage);

      final c1 = testConfig(name: 'First', url: 'http://first.local:5005');
      final c2 = testConfig(name: 'Second', url: 'http://second.local:5005');
      conn1Id = await dao.insert(c1, passwordKey: 'k1');
      conn2Id = await dao.insert(c2, passwordKey: 'k2');
      await dao.setActive(conn1Id);
    });

    tearDown(() async {
      await db.close();
    });

    test('setActive switches active connection transactionally', () async {
      // Before: conn1 is active
      final beforeActive = await dao.findActive();
      expect(beforeActive!.id, equals(conn1Id), reason: '切换前 conn1 应为活跃');

      final beforeList = await dao.findAll();
      final beforeConn2 = beforeList.firstWhere((c) => c.id == conn2Id);
      expect(beforeConn2.isActive, isFalse, reason: '切换前 conn2 应为非活跃');

      // Switch to conn2
      await service.setActive(conn2Id);

      // After: conn2 is active, conn1 is not
      final afterActive = await dao.findActive();
      expect(afterActive, isNotNull, reason: '切换后应有活跃连接');
      expect(afterActive!.id, equals(conn2Id), reason: '切换后 conn2 应为活跃连接');

      final afterList = await dao.findAll();
      final afterConn1 = afterList.firstWhere((c) => c.id == conn1Id);
      final afterConn2 = afterList.firstWhere((c) => c.id == conn2Id);
      expect(afterConn1.isActive, isFalse, reason: '切换后 conn1 应变为非活跃');
      expect(afterConn2.isActive, isTrue, reason: '切换后 conn2 应变为活跃');

      // Exactly one active connection
      final activeCount = afterList.where((c) => c.isActive).length;
      expect(activeCount, equals(1), reason: '事务保证任意时刻只有一个活跃连接');
    });

    test('switching back restores original active', () async {
      // Switch to conn2
      await service.setActive(conn2Id);
      final after1 = await dao.findActive();
      expect(after1!.id, equals(conn2Id));

      // Switch back to conn1
      await service.setActive(conn1Id);
      final after2 = await dao.findActive();
      expect(after2!.id, equals(conn1Id), reason: '再次切换应回到 conn1');

      // Only conn1 is active
      final list = await dao.findAll();
      final activeCount = list.where((c) => c.isActive).length;
      expect(activeCount, equals(1), reason: '仍只有一个活跃连接');
    });
  });
}
