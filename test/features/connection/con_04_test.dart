// test/features/connection/con_04_test.dart
// CON-04: 切换当前连接 — automated test suite
//
// Unit tests (CON-T25~T27): DAO-level setActive toggling, provider-level
// cache invalidation, and activeConnectionProvider update after switch.
//
// Uses sqflite_common_ffi for an in-memory SQLite database so tests run
// without a physical device or emulator.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nas_audio_player/core/database/dao/connection_dao.dart';
import 'package:nas_audio_player/features/connection/connection_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../helpers/test_database.dart';
import '../../helpers/test_factories.dart';

// ── Helpers ───────────────────────────────────────────────────────────────────

// testConfig() is imported from test_factories.dart as testConfig().

/// Builds a [ProviderContainer] that overrides [connectionDaoProvider] with
/// the supplied [dao].
ProviderContainer _makeContainer(ConnectionDao dao) {
  return ProviderContainer(
    overrides: [
      connectionDaoProvider.overrideWithValue(dao),
    ],
  );
}

// ═════════════════════════════════════════════════════════════════════════════
// Unit tests — CON-T25~T27
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

  group('CON-T25 switch active connection (DAO)', () {
    // ── CON-T25: setActive toggles is_active correctly ──────────────────────

    test('test_CON_T25_setActiveSwitchesCorrectly', () async {
      // Insert two connections
      final config1 = testConfig(
        name: 'NAS Alpha',
        url: 'http://192.168.1.100:5005',
      );
      final config2 = testConfig(
        name: 'NAS Beta',
        url: 'http://192.168.1.101:5005',
      );

      final id1 = await dao.insert(config1, passwordKey: 'key1');
      final id2 = await dao.insert(config2, passwordKey: 'key2');

      // Set first connection as active
      await dao.setActive(id1);

      var conn1 = await dao.findById(id1);
      var conn2 = await dao.findById(id2);

      expect(conn1!.isActive, isTrue, reason: 'setActive(id1) 后连接 1 应为活跃');
      expect(conn2!.isActive, isFalse, reason: 'setActive(id1) 后连接 2 应为非活跃');

      // Switch active to second connection — this is the CON-04 use case
      await dao.setActive(id2);

      conn1 = await dao.findById(id1);
      conn2 = await dao.findById(id2);

      expect(conn1!.isActive, isFalse, reason: 'setActive(id2) 后连接 1 应变为非活跃');
      expect(conn2!.isActive, isTrue, reason: 'setActive(id2) 后连接 2 应变为活跃');

      // Verify findActive returns the correct (new) active connection
      final active = await dao.findActive();
      expect(active, isNotNull, reason: '切换后应存在一个活跃连接');
      expect(active!.id, equals(id2), reason: 'findActive 应返回新切换的连接');
      expect(active.name, equals('NAS Beta'), reason: '活跃连接名称应为 NAS Beta');
    });
  });

  group('CON-T26~T27 provider-level switch', () {
    // ── CON-T26: switchActiveConnectionProvider invalidates
    //    activeConnectionProvider ───────────────────────────────────────────

    test('test_CON_T26_switchInvalidatesActiveConnectionProvider', () async {
      // Insert two connections
      final config1 = testConfig(
        name: 'NAS Alpha',
        url: 'http://192.168.1.100:5005',
      );
      final config2 = testConfig(
        name: 'NAS Beta',
        url: 'http://192.168.1.101:5005',
      );

      final id1 = await dao.insert(config1, passwordKey: 'key1');
      final id2 = await dao.insert(config2, passwordKey: 'key2');

      // Set first as active
      await dao.setActive(id1);

      final container = _makeContainer(dao);
      addTearDown(container.dispose);

      // Read active connection provider — should return config1
      final first = await container.read(activeConnectionProvider.future);
      expect(first, isNotNull, reason: '应存在活跃连接');
      expect(first!.id, equals(id1), reason: '初始活跃连接应为 NAS Alpha');

      // Switch active connection via the switchActiveConnectionProvider
      await container.read(switchActiveConnectionProvider(id2).future);

      // After switch, the activeConnectionProvider was invalidated.
      // Re-reading should return the new active connection.
      final second = await container.read(activeConnectionProvider.future);
      expect(second, isNotNull, reason: '切换后应存在活跃连接');
      expect(second!.id, equals(id2), reason: '切换后活跃连接应为 NAS Beta');
      expect(second.name, equals('NAS Beta'), reason: '切换后活跃连接名称应为 NAS Beta');

      // Also verify connectionListProvider was invalidated and updated
      final list = await container.read(connectionListProvider.future);
      final activeInList = list.where((c) => c.isActive).toList();
      expect(activeInList.length, equals(1), reason: '列表中应有且仅有一个活跃连接');
      expect(activeInList.first.id, equals(id2),
          reason: '列表中活跃连接的 ID 应为新切换的目标');
    });

    // ── CON-T27: activeConnectionProvider returns new connection after
    //    switching via setActive ────────────────────────────────────────────

    test('test_CON_T27_activeConnectionProviderUpdatesAfterSwitch', () async {
      // Insert two connections
      final config1 = testConfig(
        name: 'NAS Alpha',
        url: 'http://192.168.1.100:5005',
      );
      final config2 = testConfig(
        name: 'NAS Beta',
        url: 'http://192.168.1.101:5005',
      );

      final id1 = await dao.insert(config1, passwordKey: 'key1');
      final id2 = await dao.insert(config2, passwordKey: 'key2');

      // Set first as active
      await dao.setActive(id1);

      final container = _makeContainer(dao);
      addTearDown(container.dispose);

      // Watch activeConnectionProvider — first read returns config1
      final first = await container.read(activeConnectionProvider.future);
      expect(first!.id, equals(id1), reason: '初始活跃连接 ID 应为 id1');
      expect(first.name, equals('NAS Alpha'), reason: '初始活跃连接名称应为 NAS Alpha');

      // Simulate CON-04 switch: call setActive on the second connection,
      // then invalidate providers (just like switchActiveConnectionProvider does)
      await dao.setActive(id2);

      // Invalidate so the provider picks up the change
      container.invalidate(activeConnectionProvider);
      container.invalidate(connectionListProvider);

      // Re-read — should now return config2
      final second = await container.read(activeConnectionProvider.future);
      expect(second, isNotNull, reason: 'invalidate 后应重新读取到活跃连接');
      expect(second!.id, equals(id2), reason: 'invalidate 后活跃连接 ID 应为 id2');
      expect(second.name, equals('NAS Beta'),
          reason: 'invalidate 后活跃连接名称应为 NAS Beta');
      expect(second.isActive, isTrue, reason: '返回的连接 isActive 应为 true');
    });
  });
}
