// test/features/connection/con_06_test.dart
// CON-06: 删除连接配置 — automated test suite
//
// Unit tests (CON-T31~T34): cascade delete, last-connection protection,
// non-active delete, active delete with auto-activate.
//
// Uses sqflite_common_ffi for an in-memory SQLite database.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nas_audio_player/core/database/dao/connection_dao.dart';
import 'package:nas_audio_player/core/database/database_helper.dart';
import 'package:nas_audio_player/features/connection/connection_provider.dart';
import 'package:nas_audio_player/shared/models/connection_config.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

// ── Fake storage ──────────────────────────────────────────────────────────────────

/// Minimal fake [FlutterSecureStorage] backed by an in-memory map.
/// Overrides [delete] in addition to [read] and [write] so that the
/// delete provider can remove password entries during tests.
class FakeSecureStorage extends FlutterSecureStorage {
  final Map<String, String> _store = {};

  void stub(String key, String value) => _store[key] = value;

  @override
  Future<String?> read({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WindowsOptions? wOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
  }) async {
    return _store[key];
  }

  @override
  Future<void> write({
    required String key,
    required String? value,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WindowsOptions? wOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
  }) async {
    if (value != null) {
      _store[key] = value;
    } else {
      _store.remove(key);
    }
  }

  @override
  Future<void> delete({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WindowsOptions? wOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
  }) async {
    _store.remove(key);
  }
}

// ── Helpers ───────────────────────────────────────────────────────────────────────

/// Creates a [ConnectionConfig] with sensible defaults for testing.
ConnectionConfig _testConfig({
  int? id,
  String name = 'Test NAS',
  String url = 'http://192.168.1.100:5005',
  String username = 'admin',
  String basePath = '/dav',
  bool isActive = false,
  DateTime? createdAt,
  DateTime? updatedAt,
}) {
  final now = DateTime.now();
  return ConnectionConfig(
    id: id,
    name: name,
    url: url,
    username: username,
    basePath: basePath,
    isActive: isActive,
    createdAt: createdAt ?? now,
    updatedAt: updatedAt ?? now,
  );
}

/// SQL that mirrors [DatabaseHelper._onCreate].
const _createConnectionsTable = '''
  CREATE TABLE connections (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    name        TEXT NOT NULL,
    url         TEXT NOT NULL,
    username    TEXT NOT NULL,
    password    TEXT NOT NULL,
    base_path   TEXT NOT NULL DEFAULT '/',
    is_active   INTEGER NOT NULL DEFAULT 0,
    created_at  INTEGER NOT NULL,
    updated_at  INTEGER NOT NULL
  )
''';

/// SQL for the play_progress table used in CON-T31 cascade-delete tests.
const _createPlayProgressTable = '''
  CREATE TABLE play_progress (
    id            INTEGER PRIMARY KEY AUTOINCREMENT,
    connection_id INTEGER NOT NULL,
    file_path     TEXT NOT NULL,
    position_ms   INTEGER NOT NULL DEFAULT 0,
    updated_at    INTEGER NOT NULL
  )
''';

/// Opens a fresh in-memory database, applies the connections schema, injects it
/// into [DatabaseHelper], and returns the handle.
Future<Database> _openTestDatabase() async {
  final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
  await db.execute(_createConnectionsTable);
  DatabaseHelper.instance.overrideDatabase(db);
  return db;
}

/// Creates the play_progress table in [db] and returns [db] for chaining.
Future<Database> _withPlayProgressTable(Database db) async {
  await db.execute(_createPlayProgressTable);
  return db;
}

// ═════════════════════════════════════════════════════════════════════════════════
// Unit tests — CON-T31~T34
// ═════════════════════════════════════════════════════════════════════════════════

void main() {
  setUpAll(() {
    sqfliteFfiInit();
  });

  group('CON-T31 cascade delete to play_progress', () {
    late Database db;
    late ConnectionDao dao;

    setUp(() async {
      db = await _openTestDatabase();
      await _withPlayProgressTable(db);
      dao = ConnectionDao();
    });

    tearDown(() async {
      await db.close();
    });

    // ── CON-T31: Delete connection cascades to play_progress records ────────────

    test('test_CON_T31_deleteConnection_cascadesToPlayProgress', () async {
      // Insert two connections (need >=2 so delete is allowed)
      final c1 = _testConfig(name: 'NAS-1');
      final c2 = _testConfig(name: 'NAS-2');
      final id1 = await dao.insert(c1, passwordKey: 'key_1');
      final id2 = await dao.insert(c2, passwordKey: 'key_2');

      // Insert some play_progress records for both connections
      final now = DateTime.now().millisecondsSinceEpoch;
      await db.insert('play_progress', {
        'connection_id': id1,
        'file_path': '/music/song1.mp3',
        'position_ms': 120000,
        'updated_at': now,
      });
      await db.insert('play_progress', {
        'connection_id': id1,
        'file_path': '/music/song2.mp3',
        'position_ms': 45000,
        'updated_at': now,
      });
      await db.insert('play_progress', {
        'connection_id': id2,
        'file_path': '/music/song3.mp3',
        'position_ms': 0,
        'updated_at': now,
      });

      // Delete connection 1
      await dao.delete(id1);

      // Assert: connection 1 is gone from connections table
      final conn1 = await dao.findById(id1);
      expect(conn1, isNull, reason: 'CON-T31: 连接 1 应从 connections 表中删除');

      // Assert: connection 2 still exists
      final conn2 = await dao.findById(id2);
      expect(conn2, isNotNull, reason: '连接 2 应仍然存在');

      // Assert: play_progress records for connection 1 are removed
      final rows1 = await db
          .query('play_progress', where: 'connection_id = ?', whereArgs: [id1]);
      expect(rows1, isEmpty, reason: 'CON-T31: 连接 1 的 play_progress 记录应全部级联删除');

      // Assert: play_progress records for connection 2 remain
      final rows2 = await db
          .query('play_progress', where: 'connection_id = ?', whereArgs: [id2]);
      expect(rows2.length, equals(1), reason: '连接 2 的 play_progress 记录应不受影响');
    });
  });

  group('CON-T32 last connection protection', () {
    late Database db;
    late ConnectionDao dao;

    setUp(() async {
      db = await _openTestDatabase();
      dao = ConnectionDao();
    });

    tearDown(() async {
      await db.close();
    });

    // ── CON-T32: Only one connection left, try to delete → rejected ─────────────

    test('test_CON_T32_onlyOneConnection_deleteRejected', () async {
      // Insert a single connection
      final c1 = _testConfig(name: 'Only NAS');
      final id = await dao.insert(c1, passwordKey: 'key_only');

      // Attempt to delete — must throw LastConnectionException
      expect(
        () async => dao.delete(id),
        throwsA(isA<LastConnectionException>()),
        reason: 'CON-T32: 只剩一个连接时删除应抛出 LastConnectionException',
      );

      // Assert: the connection still exists
      final conn = await dao.findById(id);
      expect(conn, isNotNull, reason: 'CON-T32: 连接应仍然存在（未被删除）');
      expect(conn!.name, equals('Only NAS'));
    });
  });

  group('CON-T33 delete non-active connection', () {
    late Database db;
    late ConnectionDao dao;

    setUp(() async {
      db = await _openTestDatabase();
      dao = ConnectionDao();
    });

    tearDown(() async {
      await db.close();
    });

    // ── CON-T33: Delete non-active connection, active unaffected ─────────────────

    test('test_CON_T33_deleteNonActiveConnection_activeUnaffected', () async {
      // Insert two connections
      final c1 = _testConfig(name: 'NAS-Active', isActive: true);
      final c2 = _testConfig(name: 'NAS-Inactive', isActive: false);
      final id1 = await dao.insert(c1, passwordKey: 'key_a');
      final id2 = await dao.insert(c2, passwordKey: 'key_b');

      // Manually set id1 as active (insert ignores isActive param in test setup)
      await dao.setActive(id1);

      // Delete the non-active connection (id2)
      final wasActive = await dao.delete(id2);

      // Assert: the deleted connection was NOT active
      expect(wasActive, isFalse, reason: 'CON-T33: 删除非活跃连接时返回值应为 false');

      // Assert: connection 2 is gone
      final conn2 = await dao.findById(id2);
      expect(conn2, isNull, reason: '连接 2 应已被删除');

      // Assert: connection 1 is still the active connection
      final active = await dao.findActive();
      expect(active, isNotNull, reason: '活跃连接应仍然存在');
      expect(active!.id, equals(id1), reason: 'CON-T33: 活跃连接应不受影响');
      expect(active.name, equals('NAS-Active'));
    });
  });

  group('CON-T34 delete active connection auto-activates another', () {
    late Database db;
    late ConnectionDao dao;

    setUp(() async {
      db = await _openTestDatabase();
      dao = ConnectionDao();
    });

    tearDown(() async {
      await db.close();
    });

    // ── CON-T34: Delete active connection → auto-activate another ───────────────

    test('test_CON_T34_deleteActiveConnection_autoActivateAnother', () async {
      // Insert two connections
      final c1 = _testConfig(name: 'NAS-1', isActive: true);
      final c2 = _testConfig(name: 'NAS-2', isActive: false);
      final id1 = await dao.insert(c1, passwordKey: 'key_1');
      final id2 = await dao.insert(c2, passwordKey: 'key_2');

      // Set id1 as the active connection
      await dao.setActive(id1);

      // Verify active before delete
      final activeBefore = await dao.findActive();
      expect(activeBefore!.id, equals(id1), reason: '删除前连接 1 应为活跃');

      // Delete the active connection (id1)
      final wasActive = await dao.delete(id1);

      // Assert: the deleted connection WAS active
      expect(wasActive, isTrue, reason: 'CON-T34: 删除活跃连接时返回值应为 true');

      // Assert: connection 1 is gone
      final conn1 = await dao.findById(id1);
      expect(conn1, isNull, reason: '连接 1 应已被删除');

      // Assert: connection 2 is now the active connection
      final activeAfter = await dao.findActive();
      expect(activeAfter, isNotNull, reason: 'CON-T34: 删除活跃连接后应有其他连接被自动激活');
      expect(activeAfter!.id, equals(id2), reason: 'CON-T34: 应自动将连接 2 设为活跃连接');
      expect(activeAfter.name, equals('NAS-2'));
    });
  });

  // ── Provider integration test ───────────────────────────────────────────────────

  group('CON-06 provider integration', () {
    late Database db;
    late ConnectionDao dao;
    late FakeSecureStorage storage;

    setUp(() async {
      db = await _openTestDatabase();
      dao = ConnectionDao();
      storage = FakeSecureStorage();
    });

    tearDown(() async {
      await db.close();
    });

    test('test_CON_06_deleteProvider_clearsPasswordAndInvalidates', () async {
      // Insert two connections
      final c1 = _testConfig(name: 'NAS-A');
      final c2 = _testConfig(name: 'NAS-B');
      final id1 = await dao.insert(c1, passwordKey: 'key_1');
      final id2 = await dao.insert(c2, passwordKey: 'key_2');

      // Stub passwords in secure storage
      storage.stub('connection_password_$id1', 'secret1');
      storage.stub('connection_password_$id2', 'secret2');

      final container = ProviderContainer(overrides: [
        connectionDaoProvider.overrideWithValue(dao),
        secureStorageProvider.overrideWithValue(storage),
      ]);
      addTearDown(container.dispose);

      // Verify password exists before delete
      final pwBefore = await storage.read(key: 'connection_password_$id1');
      expect(pwBefore, equals('secret1'), reason: '删除前密码应存在于 secure storage');

      // Execute delete via provider
      await container.read(deleteConnectionProvider(id1).future);

      // Assert: connection is gone from DB
      final conn = await dao.findById(id1);
      expect(conn, isNull, reason: '删除后连接应从数据库消失');

      // Assert: password is removed from secure storage
      final pwAfter = await storage.read(key: 'connection_password_$id1');
      expect(pwAfter, isNull, reason: '删除连接后密码应从 secure storage 中清除');

      // Assert: connection 2 still has its password
      final pw2 = await storage.read(key: 'connection_password_$id2');
      expect(pw2, equals('secret2'), reason: '其他连接的密码不应受影响');

      // Assert: connection list is updated (invalidate worked)
      final list = await container.read(connectionListProvider.future);
      expect(list.length, equals(1));
      expect(list.first.id, equals(id2));
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // CON-03: LastConnectionException provider catch (CON-FIX-T07~T08)
  // ═══════════════════════════════════════════════════════════════════════════

  group('CON-03 LastConnectionException provider catch', () {
    late Database db;
    late ConnectionDao dao;
    late FakeSecureStorage storage;

    setUp(() async {
      db = await _openTestDatabase();
      dao = ConnectionDao();
      storage = FakeSecureStorage();
    });

    tearDown(() async {
      await db.close();
    });

    // ── CON-FIX-T07: 删除非最后一个连接 → 正常删除 ────────────────────────

    test('CON-FIX-T07: delete non-last connection succeeds via provider',
        () async {
      final c1 = _testConfig(name: 'Keep');
      final c2 = _testConfig(name: 'Remove');
      final id1 = await dao.insert(c1, passwordKey: 'k1');
      final id2 = await dao.insert(c2, passwordKey: 'k2');

      storage.stub('connection_password_$id1', 'pw1');
      storage.stub('connection_password_$id2', 'pw2');

      final container = ProviderContainer(overrides: [
        connectionDaoProvider.overrideWithValue(dao),
        secureStorageProvider.overrideWithValue(storage),
      ]);
      addTearDown(container.dispose);

      // Delete non-last connection (2 remain after insert, so safe)
      await container.read(deleteConnectionProvider(id2).future);

      // Verify: deleted
      expect(await dao.findById(id2), isNull);
      // Verify: other connection still exists
      expect(await dao.findById(id1), isNotNull);
      // Verify: provider didn't throw
      final state = container.read(deleteConnectionProvider(id2));
      expect(state.hasError, isFalse, reason: '删除非最后一个连接不应触发错误');
    });

    // ── CON-FIX-T08: 只有一个连接时删除 → provider catch 异常 → 不 crash ──

    test('CON-FIX-T08: deleting last connection → provider surfaces error',
        () async {
      final c1 = _testConfig(name: 'Sole');
      final id = await dao.insert(c1, passwordKey: 'k');

      storage.stub('connection_password_$id', 'pw');

      final container = ProviderContainer(overrides: [
        connectionDaoProvider.overrideWithValue(dao),
        secureStorageProvider.overrideWithValue(storage),
      ]);
      addTearDown(container.dispose);

      // Attempt to delete the sole connection via provider
      // The provider should catch LastConnectionException and surface it
      try {
        await container.read(deleteConnectionProvider(id).future);
        fail('Expected deleteConnectionProvider to throw');
      } catch (e) {
        expect(e, isA<LastConnectionException>(),
            reason: '应抛出 LastConnectionException');
      }

      // Connection still exists (not deleted)
      expect(await dao.findById(id), isNotNull, reason: '最后一个连接应仍然存在');
    });
  });
}
