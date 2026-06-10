// test/features/connection/con_03_test.dart
// CON-03: 连接配置持久化 — automated test suite
//
// Unit tests (CON-T18~T24): DAO CRUD operations, active-connection toggling,
// password reference-key verification, and update behaviour.
//
// Uses sqflite_common_ffi for an in-memory SQLite database so tests run
// without a physical device or emulator.

import 'package:flutter_test/flutter_test.dart';
import 'package:nas_audio_player/core/database/dao/connection_dao.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../helpers/test_database.dart';
import '../../helpers/test_factories.dart';

// ── Helpers ───────────────────────────────────────────────────────────────────

// testConfig() is imported from test_factories.dart as testConfig().

// ═════════════════════════════════════════════════════════════════════════════
// DAO unit tests — CON-T18~T24
// ═════════════════════════════════════════════════════════════════════════════

void main() {
  late Database db;
  late ConnectionDao dao;

  setUpAll(() {
    initSqfliteFfi();
  });

  setUp(() async {
    db = await openTestDatabase(TestSchema.connections);
    dao = ConnectionDao();
  });

  tearDown(() async {
    await db.close();
  });

  group('CON-T18~T24 connection config persistence', () {
    // ── CON-T18: Insert new connection config ───────────────────────────────

    test('test_CON_T18_insertNewConnectionConfig', () async {
      final config = testConfig(
        name: 'My NAS',
        url: 'http://192.168.1.100:5005',
        username: 'admin',
        basePath: '/dav',
      );

      final id = await dao.insert(config, passwordKey: 'test_key');

      expect(id, isNotNull, reason: '插入后应返回自动生成的 ID');
      expect(id, greaterThan(0), reason: '自增 ID 应大于 0');

      final retrieved = await dao.findById(id);
      expect(retrieved, isNotNull, reason: '应能通过 ID 查询到刚插入的记录');

      expect(retrieved!.name, equals('My NAS'), reason: '名称应与插入时一致');
      expect(retrieved.url, equals('http://192.168.1.100:5005'),
          reason: 'URL 应与插入时一致');
      expect(retrieved.username, equals('admin'), reason: '用户名应与插入时一致');
      expect(retrieved.basePath, equals('/dav'), reason: 'basePath 应与插入时一致');
      expect(retrieved.isActive, isFalse, reason: '新插入的连接默认不应为活跃状态');
    });

    // ── CON-T19: Query active connection (empty database) ────────────────────

    test('test_CON_T19_queryActiveConnection_emptyDatabase_returnsNull',
        () async {
      final result = await dao.findActive();
      expect(result, isNull, reason: '数据库为空时查询活跃连接应返回 null');
    });

    // ── CON-T20: Query active connection (is_active=1 record exists) ────────

    test('test_CON_T20_queryActiveConnection_whenActiveExists', () async {
      final config = testConfig(
        name: 'Active NAS',
        url: 'http://192.168.1.100:5005',
        username: 'admin',
        basePath: '/dav',
      );

      final id = await dao.insert(config, passwordKey: 'key');
      await dao.setActive(id);

      final active = await dao.findActive();

      expect(active, isNotNull, reason: '存在活跃连接时应返回 ConnectionConfig 对象');
      expect(active!.id, equals(id), reason: '返回的连接 ID 应与设置为活跃的一致');
      expect(active.isActive, isTrue, reason: '返回的连接 isActive 应为 true');
      expect(active.name, equals('Active NAS'), reason: '返回的连接名称应与插入时一致');
    });

    // ── CON-T21: Set one connection as active (multiple exist) ──────────────

    test('test_CON_T21_setActive_togglesCorrectly', () async {
      final config1 = testConfig(
        name: 'NAS 1',
        url: 'http://192.168.1.100:5005',
      );
      final config2 = testConfig(
        name: 'NAS 2',
        url: 'http://192.168.1.101:5005',
      );

      final id1 = await dao.insert(config1, passwordKey: 'key1');
      final id2 = await dao.insert(config2, passwordKey: 'key2');

      // Set first connection as active
      await dao.setActive(id1);
      var conn1 = await dao.findById(id1);
      var conn2 = await dao.findById(id2);
      expect(conn1!.isActive, isTrue, reason: 'setActive(id1) 后，连接 1 应为活跃');
      expect(conn2!.isActive, isFalse, reason: 'setActive(id1) 后，连接 2 应为非活跃');

      // Toggle: set second connection as active
      await dao.setActive(id2);
      conn1 = await dao.findById(id1);
      conn2 = await dao.findById(id2);
      expect(conn1!.isActive, isFalse, reason: 'setActive(id2) 后，连接 1 应变为非活跃');
      expect(conn2!.isActive, isTrue, reason: 'setActive(id2) 后，连接 2 应变为活跃');
    });

    // ── CON-T22: Query all connections list ─────────────────────────────────

    test('test_CON_T22_queryAllConnections_orderedByCreatedAt', () async {
      // Use explicit timestamps so ordering is deterministic.
      final configs = [
        testConfig(
          name: 'NAS A',
          url: 'http://a.example.com',
          createdAt: DateTime(2024, 1, 1, 10, 0, 0),
          updatedAt: DateTime(2024, 1, 1, 10, 0, 0),
        ),
        testConfig(
          name: 'NAS B',
          url: 'http://b.example.com',
          createdAt: DateTime(2024, 1, 2, 10, 0, 0),
          updatedAt: DateTime(2024, 1, 2, 10, 0, 0),
        ),
        testConfig(
          name: 'NAS C',
          url: 'http://c.example.com',
          createdAt: DateTime(2024, 1, 3, 10, 0, 0),
          updatedAt: DateTime(2024, 1, 3, 10, 0, 0),
        ),
      ];

      for (final c in configs) {
        await dao.insert(c, passwordKey: 'key');
      }

      final all = await dao.findAll();

      expect(all.length, equals(3), reason: '应返回全部 3 条连接记录');
      expect(all[0].name, equals('NAS A'),
          reason: '第一条应按 created_at 排序为 NAS A');
      expect(all[1].name, equals('NAS B'),
          reason: '第二条应按 created_at 排序为 NAS B');
      expect(all[2].name, equals('NAS C'),
          reason: '第三条应按 created_at 排序为 NAS C');
    });

    // ── CON-T23: Password not stored as plaintext ───────────────────────────

    test('test_CON_T23_passwordStoredAsReferenceKey_notPlaintext', () async {
      final config = testConfig();
      const refKey = 'connection_password_1';

      await dao.insert(config, passwordKey: refKey);

      // Query the raw database directly to inspect the password column.
      final rows = await db.query('connections');
      expect(rows.length, equals(1), reason: '应有一条记录被插入');

      final passwordValue = rows.first['password'] as String;
      expect(passwordValue, equals(refKey),
          reason: 'password 列应存储引用密钥(reference key)');
      expect(passwordValue, isNot(equals('my_secret_password')),
          reason: 'password 列不应存储明文密码');
    });

    // ── CON-T24: Update existing connection's URL field ─────────────────────

    test('test_CON_T24_updateConnectionUrl', () async {
      final config = testConfig(
        name: 'My NAS',
        url: 'http://old.example.com:5005',
        username: 'admin',
        basePath: '/dav',
      );

      final id = await dao.insert(config, passwordKey: 'key');

      // Retrieve the original to capture its updatedAt.
      final original = await dao.findById(id);
      expect(original, isNotNull);
      final originalUpdatedAtMs = original!.updatedAt.millisecondsSinceEpoch;

      // Small delay guarantees a different updated_at timestamp.
      await Future<void>.delayed(const Duration(milliseconds: 5));

      final modified = original.copyWith(url: 'http://new.example.com:8080');
      await dao.update(modified, passwordKey: 'key');

      final updated = await dao.findById(id);
      expect(updated, isNotNull, reason: '更新后仍应能查到记录');
      expect(updated!.url, equals('http://new.example.com:8080'),
          reason: 'URL 应更新为新值');
      expect(updated.name, equals('My NAS'), reason: '未修改的字段应保持不变');
      expect(updated.username, equals('admin'), reason: '未修改的字段应保持不变');
      expect(updated.basePath, equals('/dav'), reason: '未修改的字段应保持不变');
      expect(
        updated.updatedAt.millisecondsSinceEpoch,
        greaterThan(originalUpdatedAtMs),
        reason: 'updated_at 字段应刷新为更新时的时间戳',
      );
    });
  });
}
