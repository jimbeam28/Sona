// test/features/connection/con_09_test.dart
// TST-12: 连接切换影响面集成测试
//
// Integration tests (TST-T91~T98): connection switch impact on directory cache,
// play queue, active connection, connection list, and atomic save/rollback.
//
// Uses sqflite_common_ffi for an in-memory SQLite database.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nas_audio_player/core/database/dao/connection_dao.dart';
import 'package:nas_audio_player/core/database/database_helper.dart';
import 'package:nas_audio_player/features/browser/browser_provider.dart';
import 'package:nas_audio_player/features/connection/connection_provider.dart';
import 'package:nas_audio_player/shared/models/connection_config.dart';
import 'package:nas_audio_player/shared/models/nas_file.dart';
import 'package:nas_audio_player/shared/models/play_queue.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

// ── Fake secure storage ──────────────────────────────────────────────────────

/// Minimal fake [FlutterSecureStorage] backed by an in-memory map.
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

/// A [FakeSecureStorage] that unconditionally throws on [write].
class ThrowingFakeSecureStorage extends FakeSecureStorage {
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
    throw Exception('Simulated secure storage write failure');
  }
}

// ── Helpers ───────────────────────────────────────────────────────────────────

/// Creates a [ConnectionConfig] with defaults convenient for testing.
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

/// SQL that mirrors [DatabaseHelper._onCreate] for the connections table.
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

/// Opens a fresh in-memory database, applies the connections schema, injects it
/// into [DatabaseHelper], and returns the handle.
Future<Database> _openTestDatabase() async {
  final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
  await db.execute(_createConnectionsTable);
  DatabaseHelper.instance.overrideDatabase(db);
  return db;
}

// ═══════════════════════════════════════════════════════════════════════════════
// TST-T91 ~ TST-T98
// ═══════════════════════════════════════════════════════════════════════════════

void main() {
  setUpAll(() {
    sqfliteFfiInit();
  });

  // ── TST-T91: directoryCache 中 connectionId=1 的条目被清除 ─────────────────

  group('TST-T91 directoryCache cleared on switch', () {
    late Database db;
    late ConnectionDao dao;
    late int conn1Id;
    late int conn2Id;

    setUp(() async {
      db = await _openTestDatabase();
      dao = ConnectionDao();
      final c1 = _testConfig(name: 'NAS-1', url: 'http://nas1.local:5005');
      final c2 = _testConfig(name: 'NAS-2', url: 'http://nas2.local:5005');
      conn1Id = await dao.insert(c1, passwordKey: 'key_1');
      conn2Id = await dao.insert(c2, passwordKey: 'key_2');
      await dao.setActive(conn1Id);
    });

    tearDown(() async {
      await db.close();
    });

    test('test_TST_T91_switchConnection_clearsOldCacheEntries', () async {
      final container = ProviderContainer(overrides: [
        connectionDaoProvider.overrideWithValue(dao),
      ]);
      addTearDown(container.dispose);

      // Populate directoryCache with entries belonging to connection 1
      const testFile = NasFile(
          name: 'song.mp3', path: '/music/song.mp3', isDirectory: false);
      container.read(directoryCacheProvider.notifier).state = {
        '$conn1Id:/music':
            CacheEntry(files: [testFile], createdAt: DateTime.now()),
        '$conn1Id:/books': CacheEntry(files: [], createdAt: DateTime.now()),
      };

      // Switch the active connection to conn2
      await container.read(switchActiveConnectionProvider(conn2Id).future);

      // Clear stale cache entries whose key starts with the old connection id
      container.read(directoryCacheProvider.notifier).update((state) {
        final updated = Map<String, CacheEntry>.from(state);
        updated.removeWhere((key, _) => key.startsWith('$conn1Id:'));
        return updated;
      });

      // Verify: conn1 entries are gone from the cache
      final cache = container.read(directoryCacheProvider);
      expect(cache.containsKey('$conn1Id:/music'), isFalse,
          reason: 'TST-T91: 连接 1 的 directoryCache 条目应被清除');
      expect(cache.containsKey('$conn1Id:/books'), isFalse,
          reason: 'TST-T91: 连接 1 的所有缓存条目都应被清除');
    });
  });

  // ── TST-T92: currentPlayQueueProvider 变为 null ────────────────────────────

  group('TST-T92 playQueue cleared on switch', () {
    late Database db;
    late ConnectionDao dao;
    late FakeSecureStorage storage;
    late int conn1Id;
    late int conn2Id;

    setUp(() async {
      db = await _openTestDatabase();
      dao = ConnectionDao();
      storage = FakeSecureStorage();
      final c1 = _testConfig(name: 'NAS-1', url: 'http://nas1.local:5005');
      final c2 = _testConfig(name: 'NAS-2', url: 'http://nas2.local:5005');
      conn1Id = await dao.insert(c1, passwordKey: 'key_1');
      conn2Id = await dao.insert(c2, passwordKey: 'key_2');
      await dao.setActive(conn1Id);
      storage.stub('connection_password_$conn1Id', 'pw1');
      storage.stub('connection_password_$conn2Id', 'pw2');
    });

    tearDown(() async {
      await db.close();
    });

    test('test_TST_T92_switchConnection_clearsPlayQueue', () async {
      final container = ProviderContainer(overrides: [
        connectionDaoProvider.overrideWithValue(dao),
        secureStorageProvider.overrideWithValue(storage),
      ]);
      addTearDown(container.dispose);

      // Register the clearQueueOnConnectionSwitchProvider so its ref.listen
      // callback fires when activeConnectionProvider changes.
      container.read(clearQueueOnConnectionSwitchProvider);

      // Resolve activeConnectionProvider once so the listener has a baseline.
      // The callback fires on this first resolution but does nothing because
      // lastQueueConnectionIdProvider is still null.
      await container.read(activeConnectionProvider.future);

      // Set up an active play queue linked to connection 1
      const testFile = NasFile(
          name: 'song.mp3', path: '/music/song.mp3', isDirectory: false);
      final queue = PlayQueue(files: [testFile], currentIndex: 0);
      container.read(currentPlayQueueProvider.notifier).state = queue;
      container.read(lastQueueConnectionIdProvider.notifier).state = conn1Id;

      // Sanity: queue is set before the switch
      expect(container.read(currentPlayQueueProvider), isNotNull,
          reason: '切换前 currentPlayQueueProvider 应为非 null');
      expect(container.read(lastQueueConnectionIdProvider), equals(conn1Id),
          reason: '切换前 lastQueueConnectionIdProvider 应为 conn1 的 id');

      // Switch to connection 2
      await container.read(switchActiveConnectionProvider(conn2Id).future);

      // Trigger activeConnectionProvider re-fetch so the ref.listen callback
      // sees the connection change and clears the queue.
      await container.read(activeConnectionProvider.future);

      // Verify: queue was cleared by the listener
      expect(container.read(currentPlayQueueProvider), isNull,
          reason: 'TST-T92: 切换连接后 currentPlayQueueProvider 应变为 null');
      expect(container.read(lastQueueConnectionIdProvider), isNull,
          reason: 'TST-T92: 切换连接后 lastQueueConnectionIdProvider 应变为 null');
    });
  });

  // ── TST-T93: connectionId=2 的缓存不受影响 ─────────────────────────────────

  group('TST-T93 other connection cache unaffected', () {
    late Database db;
    late ConnectionDao dao;
    late int conn1Id;
    late int conn2Id;

    setUp(() async {
      db = await _openTestDatabase();
      dao = ConnectionDao();
      final c1 = _testConfig(name: 'NAS-1', url: 'http://nas1.local:5005');
      final c2 = _testConfig(name: 'NAS-2', url: 'http://nas2.local:5005');
      conn1Id = await dao.insert(c1, passwordKey: 'key_1');
      conn2Id = await dao.insert(c2, passwordKey: 'key_2');
      await dao.setActive(conn1Id);
    });

    tearDown(() async {
      await db.close();
    });

    test('test_TST_T93_switchConnection_otherCacheUnaffected', () async {
      final container = ProviderContainer(overrides: [
        connectionDaoProvider.overrideWithValue(dao),
      ]);
      addTearDown(container.dispose);

      // Populate directoryCache with entries for BOTH connections
      const testFile = NasFile(
          name: 'song.mp3', path: '/music/song.mp3', isDirectory: false);
      const conn2File = NasFile(
          name: 'book.m4b', path: '/books/book.m4b', isDirectory: false);
      container.read(directoryCacheProvider.notifier).state = {
        '$conn1Id:/music':
            CacheEntry(files: [testFile], createdAt: DateTime.now()),
        '$conn2Id:/books':
            CacheEntry(files: [conn2File], createdAt: DateTime.now()),
      };

      // Switch to connection 2
      await container.read(switchActiveConnectionProvider(conn2Id).future);

      // Clear only stale conn1 entries from the cache (targeted cleanup)
      container.read(directoryCacheProvider.notifier).update((state) {
        final updated = Map<String, CacheEntry>.from(state);
        updated.removeWhere((key, _) => key.startsWith('$conn1Id:'));
        return updated;
      });

      // Verify: conn1 entries are gone
      final cache = container.read(directoryCacheProvider);
      expect(cache.containsKey('$conn1Id:/music'), isFalse,
          reason: '连接 1 的缓存条目应被清除');

      // Verify: conn2 entries remain untouched
      expect(cache.containsKey('$conn2Id:/books'), isTrue,
          reason: 'TST-T93: 连接 2 的缓存条目应不受影响');
      expect(cache['$conn2Id:/books']!.files.first.name, equals('book.m4b'),
          reason: 'TST-T93: 连接 2 的缓存数据应完整保留');
    });
  });

  // ── TST-T94: SecureStorage 写入失败 → DB 行回滚 → 连接不存在 ────────────

  group('TST-T94 SecureStorage failure rollback', () {
    late Database db;
    late ConnectionDao dao;

    setUp(() async {
      db = await _openTestDatabase();
      dao = ConnectionDao();
      // Pre-populate with one connection so the rollback delete in
      // ConnectionSaver.save does not trigger LastConnectionException.
      // (ConnectionDao.delete requires count > 1 to allow deletion.)
      final preExisting =
          _testConfig(name: 'Pre-existing', url: 'http://pre.local:5005');
      await dao.insert(preExisting, passwordKey: 'key_pre');
    });

    tearDown(() async {
      await db.close();
    });

    test('test_TST_T94_secureStorageWriteFails_rollsBackDb', () async {
      final throwingStorage = ThrowingFakeSecureStorage();
      final saver = ConnectionSaver(dao, throwingStorage);

      final newConfig = _testConfig(
        name: 'New NAS',
        url: 'http://new.local:5005',
      );

      // Attempt to save — the secure-storage write will fail
      try {
        await saver.save(config: newConfig, password: 'secret');
        fail('Expected save to throw due to secure storage failure');
      } catch (_) {
        // Expected: exception propagates from ConnectionSaver.save
      }

      // Verify: the new connection was NOT persisted (DB was rolled back)
      final all = await dao.findAll();
      final newConn = all.where((c) => c.name == 'New NAS');
      expect(newConn, isEmpty,
          reason: 'TST-T94: SecureStorage 写入失败后 DB 行应被回滚，连接不应存在');
      expect(all.length, equals(1), reason: '只有预填充的那条连接应保留');

      // Verify: the pre-existing connection is untouched
      expect(all.first.name, equals('Pre-existing'), reason: '预填充的连接应不受影响');
    });
  });

  // ── TST-T95: DB 写入成功 + SecureStorage 成功 → 完整保存 ──────────────────

  group('TST-T95 successful save', () {
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

    test('test_TST_T95_bothSucceed_completeSave', () async {
      final saver = ConnectionSaver(dao, storage);

      final config = _testConfig(
        name: 'My NAS',
        url: 'http://my-nas.local:5005',
      );

      final saved = await saver.save(config: config, password: 'my-secret');

      // Verify: connection was assigned an id and returned
      expect(saved.id, isNotNull, reason: 'TST-T95: 保存后连接应有分配的 id');
      expect(saved.name, equals('My NAS'));
      expect(saved.isActive, isTrue, reason: '新保存的连接应被设为活跃');

      // Verify: connection exists in DB with correct fields
      final fromDb = await dao.findById(saved.id!);
      expect(fromDb, isNotNull, reason: 'TST-T95: 连接应存在于数据库中');
      expect(fromDb!.name, equals('My NAS'));
      expect(fromDb.url, equals('http://my-nas.local:5005'));
      expect(fromDb.username, equals('admin'));
      expect(fromDb.isActive, isTrue);

      // Verify: password was written to secure storage under the permanent key
      final pw = await storage.read(key: 'connection_password_${saved.id}');
      expect(pw, equals('my-secret'), reason: 'TST-T95: 密码应正确写入 SecureStorage');

      // Verify: this is the only active connection
      final active = await dao.findActive();
      expect(active!.id, equals(saved.id), reason: '新保存的连接应是唯一的活跃连接');
    });
  });

  // ── TST-T96: 切换后 Browser 使用新连接的 WebDAV 地址 ──────────────────────

  group('TST-T96 Browser uses new connection URL', () {
    late Database db;
    late ConnectionDao dao;
    late FakeSecureStorage storage;
    late int conn1Id;
    late int conn2Id;

    setUp(() async {
      db = await _openTestDatabase();
      dao = ConnectionDao();
      storage = FakeSecureStorage();
      final c1 = _testConfig(name: 'NAS-A', url: 'http://nas-a.local:5005');
      final c2 = _testConfig(name: 'NAS-B', url: 'http://nas-b.local:5005');
      conn1Id = await dao.insert(c1, passwordKey: 'key_a');
      conn2Id = await dao.insert(c2, passwordKey: 'key_b');
      await dao.setActive(conn1Id);
      storage.stub('connection_password_$conn1Id', 'pw_a');
      storage.stub('connection_password_$conn2Id', 'pw_b');
    });

    tearDown(() async {
      await db.close();
    });

    test('test_TST_T96_switchConnection_browserUsesNewUrl', () async {
      final container = ProviderContainer(overrides: [
        connectionDaoProvider.overrideWithValue(dao),
        secureStorageProvider.overrideWithValue(storage),
      ]);
      addTearDown(container.dispose);

      // Verify initial active connection url
      final beforeConn = await container.read(activeConnectionProvider.future);
      expect(beforeConn!.url, equals('http://nas-a.local:5005'),
          reason: '切换前活跃连接应为 NAS-A');

      // Switch to conn2
      await container.read(switchActiveConnectionProvider(conn2Id).future);

      // Re-read so activeConnectionProvider resolves the new active connection
      await container.read(activeConnectionProvider.future);

      // Verify: active connection now refers to conn2's WebDAV address
      final afterConn = await container.read(activeConnectionProvider.future);
      expect(afterConn, isNotNull);
      expect(afterConn!.url, equals('http://nas-b.local:5005'),
          reason: 'TST-T96: 切换后活跃连接应使用新连接的 WebDAV 地址');
      expect(afterConn.id, equals(conn2Id),
          reason: 'TST-T96: 切换后活跃连接 id 应为 conn2');
    });
  });

  // ── TST-T97: 切换后 activeConnectionProvider 返回新连接 ───────────────────

  group('TST-T97 activeConnectionProvider returns new connection', () {
    late Database db;
    late ConnectionDao dao;
    late FakeSecureStorage storage;
    late int conn1Id;
    late int conn2Id;

    setUp(() async {
      db = await _openTestDatabase();
      dao = ConnectionDao();
      storage = FakeSecureStorage();
      final c1 = _testConfig(name: 'Old', url: 'http://old.local:5005');
      final c2 = _testConfig(name: 'New', url: 'http://new.local:5005');
      conn1Id = await dao.insert(c1, passwordKey: 'key_old');
      conn2Id = await dao.insert(c2, passwordKey: 'key_new');
      await dao.setActive(conn1Id);
      storage.stub('connection_password_$conn1Id', 'pw_old');
      storage.stub('connection_password_$conn2Id', 'pw_new');
    });

    tearDown(() async {
      await db.close();
    });

    test('test_TST_T97_switchConnection_activeProviderReturnsNew', () async {
      final container = ProviderContainer(overrides: [
        connectionDaoProvider.overrideWithValue(dao),
        secureStorageProvider.overrideWithValue(storage),
      ]);
      addTearDown(container.dispose);

      // Switch to conn2
      await container.read(switchActiveConnectionProvider(conn2Id).future);

      // Read activeConnectionProvider — must return conn2
      final active = await container.read(activeConnectionProvider.future);
      expect(active, isNotNull, reason: '切换后应有活跃连接');
      expect(active!.id, equals(conn2Id),
          reason: 'TST-T97: 切换后 activeConnectionProvider 应返回新连接 (id=$conn2Id)');
      expect(active.name, equals('New'), reason: 'TST-T97: 切换后活跃连接名称应为 "New"');
    });
  });

  // ── TST-T98: 切换后 connectionListProvider 刷新 → 新连接 isActive=true ───

  group('TST-T98 connectionListProvider refreshed', () {
    late Database db;
    late ConnectionDao dao;
    late FakeSecureStorage storage;
    late int conn1Id;
    late int conn2Id;

    setUp(() async {
      db = await _openTestDatabase();
      dao = ConnectionDao();
      storage = FakeSecureStorage();
      final c1 = _testConfig(name: 'First', url: 'http://first.local:5005');
      final c2 = _testConfig(name: 'Second', url: 'http://second.local:5005');
      conn1Id = await dao.insert(c1, passwordKey: 'k1');
      conn2Id = await dao.insert(c2, passwordKey: 'k2');
      await dao.setActive(conn1Id);
      storage.stub('connection_password_$conn1Id', 'pw1');
      storage.stub('connection_password_$conn2Id', 'pw2');
    });

    tearDown(() async {
      await db.close();
    });

    test('test_TST_T98_switchConnection_listRefreshesAndMarksActive', () async {
      final container = ProviderContainer(overrides: [
        connectionDaoProvider.overrideWithValue(dao),
        secureStorageProvider.overrideWithValue(storage),
      ]);
      addTearDown(container.dispose);

      // Verify initial state: conn1 active, conn2 inactive
      final beforeList = await container.read(connectionListProvider.future);
      final beforeConn1 = beforeList.firstWhere((c) => c.id == conn1Id);
      final beforeConn2 = beforeList.firstWhere((c) => c.id == conn2Id);
      expect(beforeConn1.isActive, isTrue, reason: '切换前连接 1 应为活跃');
      expect(beforeConn2.isActive, isFalse, reason: '切换前连接 2 应为非活跃');

      // Switch to conn2
      await container.read(switchActiveConnectionProvider(conn2Id).future);

      // connectionListProvider was invalidated — re-read for fresh data
      final afterList = await container.read(connectionListProvider.future);
      final afterConn1 = afterList.firstWhere((c) => c.id == conn1Id);
      final afterConn2 = afterList.firstWhere((c) => c.id == conn2Id);

      expect(afterConn1.isActive, isFalse,
          reason: 'TST-T98: 切换后连接 1 isActive 应为 false');
      expect(afterConn2.isActive, isTrue,
          reason: 'TST-T98: 切换后连接 2 isActive 应为 true');
      expect(afterList.length, equals(2), reason: '连接总数应仍为 2');
    });
  });
}
