// test/features/connection/test_02_con11_test.dart
// TEST-02-S1/S2 (CON11): 切换连接清浏览器缓存（directoryCache + navigationStack）
//
// 生产行为锚定（cr-20260724-0110 CON11 + bug_16_repro_test.dart 注释确认）：
//   switchActiveConnectionProvider 本身**不**清理浏览器状态——清理动作在
//   widget 层 connection_list_screen.dart:79-80（onSwitch 里 invalidate
//   directoryCacheProvider + navigationStackProvider）。
//   实证：纯 provider 层调用 switchActiveConnectionProvider 后缓存与导航栈
//   均原样保留（probe 验证后删除）。因此 S1/S2 锚定为 widget 测试——真实
//   渲染 ConnectionListScreen、点选非活跃连接，断言共享容器内浏览器状态
//   被清空/复位。删掉 :79-80 两行 invalidate 本文件即红（守卫真实行为）。
//
// 否定断言（spec §3.1）：
//   - 切换后不得残留旧缓存（directoryCacheProvider 应整体清空）
//   - 切换后不得残留旧导航栈（navigationStackProvider 应复位为仅根目录）
//   - 切换前缓存/导航栈状态不受影响（前置断言）

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nas_audio_player/core/database/dao/connection_dao.dart';
import 'package:nas_audio_player/features/browser/browser_provider.dart';
import 'package:nas_audio_player/features/connection/connection_list_screen.dart';
import 'package:nas_audio_player/features/connection/connection_provider.dart';
import 'package:nas_audio_player/shared/models/connection_config.dart';
import 'package:nas_audio_player/shared/models/nas_file.dart';

import '../../helpers/fake_secure_storage.dart';
import '../../helpers/fake_webdav_client.dart';

// ── Test double ──────────────────────────────────────────────────────────────

/// In-memory [ConnectionDao] for widget tests. All methods are overridden with
/// pure-async bodies so the widget test's FakeAsync zone never blocks on real
/// sqflite-ffi isolate events (same rationale as bug_15/bug_16 gateable fakes).
class _InMemoryDao extends ConnectionDao {
  final List<ConnectionConfig> rows = [];
  int _nextId = 0;

  void seed(ConnectionConfig config) {
    rows.add(config);
    final id = config.id;
    if (id != null && id >= _nextId) _nextId = id + 1;
  }

  @override
  Future<int> insert(ConnectionConfig config,
      {required String passwordKey}) async {
    final id = ++_nextId;
    rows.add(config.copyWith(id: id));
    return id;
  }

  @override
  Future<int> update(ConnectionConfig config,
      {required String passwordKey}) async {
    final idx = rows.indexWhere((r) => r.id == config.id);
    if (idx < 0) return 0;
    rows[idx] = config;
    return 1;
  }

  @override
  Future<void> setActive(int id) async {
    for (var i = 0; i < rows.length; i++) {
      rows[i] = rows[i].copyWith(isActive: rows[i].id == id);
    }
  }

  @override
  Future<List<ConnectionConfig>> findAll() async => List.of(rows);

  @override
  Future<ConnectionConfig?> findActive() async {
    for (final r in rows) {
      if (r.isActive) return r;
    }
    return null;
  }

  @override
  Future<ConnectionConfig?> findById(int id) async {
    for (final r in rows) {
      if (r.id == id) return r;
    }
    return null;
  }

  @override
  Future<String?> findPasswordKey(int id) async => 'connection_password_$id';

  @override
  Future<bool> delete(int id) async {
    final idx = rows.indexWhere((r) => r.id == id);
    if (idx < 0) return false;
    rows.removeAt(idx);
    return true;
  }

  @override
  Future<int> count() async => rows.length;
}

// ── Shared scaffolding ───────────────────────────────────────────────────────

List<Override> _overrides({
  required ConnectionDao dao,
  required FakeSecureStorage storage,
  required MockWebDavClient client,
}) =>
    [
      connectionDaoProvider.overrideWithValue(dao),
      secureStorageProvider.overrideWithValue(storage),
      webDavClientProvider.overrideWithValue(client),
      // Keep the test hermetic: no background PROPFIND on active changes.
      startupValidationProvider.overrideWith((ref) async => null),
    ];

/// Renders [ConnectionListScreen] in an [UncontrolledProviderScope] driven by
/// [container] so the test can read provider state directly after the switch.
Widget _buildListApp(ProviderContainer container) {
  return UncontrolledProviderScope(
    container: container,
    child: const MaterialApp(
      home: Scaffold(body: ConnectionListScreen()),
    ),
  );
}

CacheEntry<List<NasFile>> _cacheEntry(NasFile file) =>
    CacheEntry<List<NasFile>>(
      value: [file],
      createdAt: DateTime.now(),
    );

void main() {
  group('TEST-02-S1: 切换连接后 directoryCacheProvider 被清空', () {
    testWidgets('TEST-02-S1: 切换连接 → 目录缓存清空（invalidate 生效）', (tester) async {
      final dao = _InMemoryDao()
        ..seed(ConnectionConfig(
          id: 1,
          name: 'NAS-1',
          url: 'http://nas1.local:5005',
          username: 'admin',
          basePath: '/dav',
          isActive: true,
          createdAt: DateTime(2026, 7, 24),
          updatedAt: DateTime(2026, 7, 24),
        ))
        ..seed(ConnectionConfig(
          id: 2,
          name: 'NAS-2',
          url: 'http://nas2.local:5005',
          username: 'admin',
          basePath: '/dav',
          isActive: false,
          createdAt: DateTime(2026, 7, 24),
          updatedAt: DateTime(2026, 7, 24),
        ));
      final storage = FakeSecureStorage()
        ..setPassword(1, 'pw1')
        ..setPassword(2, 'pw2');
      final client = MockWebDavClient();

      final container = ProviderContainer(
        overrides: _overrides(dao: dao, storage: storage, client: client),
      );
      addTearDown(container.dispose);

      // Given: 活跃连接 A（id=1），浏览器已缓存目录（新旧连接的条目都在）。
      const testFile = NasFile(
          name: 'song.mp3', path: '/music/song.mp3', isDirectory: false);
      container.read(directoryCacheProvider.notifier).state = {
        '1:/music': _cacheEntry(testFile),
        '2:/books': _cacheEntry(testFile),
      };
      expect(container.read(directoryCacheProvider), isNotEmpty,
          reason: '前置：切换前缓存必须非空（否则测试失去意义）');

      await tester.pumpWidget(_buildListApp(container));
      await tester.pumpAndSettle();
      expect(find.text('NAS-1'), findsOneWidget);
      expect(find.text('NAS-2'), findsOneWidget);

      // When: 用户切换到连接 B（id=2）。
      await tester.tap(find.text('NAS-2'));
      await tester.pumpAndSettle();

      // Then: directoryCacheProvider 被清空（invalidate 后重建为空 Map）。
      expect(container.read(directoryCacheProvider), isEmpty,
          reason: 'TEST-02-S1: 切换连接后目录缓存必须清空'
              '（CON11：删掉 connection_list_screen.dart:79-80 invalidate 本断言变红）');

      // 行为级：活跃连接已切到 B。
      final active = await container.read(activeConnectionProvider.future);
      expect(active, isNotNull);
      expect(active!.id, equals(2), reason: '切换后活跃连接应为 NAS-2');
    });
  });

  group('TEST-02-S2: 切换连接后 navigationStackProvider 复位', () {
    testWidgets('TEST-02-S2: 切换连接 → 导航栈复位为仅含根目录', (tester) async {
      final dao = _InMemoryDao()
        ..seed(ConnectionConfig(
          id: 1,
          name: 'NAS-1',
          url: 'http://nas1.local:5005',
          username: 'admin',
          basePath: '/dav',
          isActive: true,
          createdAt: DateTime(2026, 7, 24),
          updatedAt: DateTime(2026, 7, 24),
        ))
        ..seed(ConnectionConfig(
          id: 2,
          name: 'NAS-2',
          url: 'http://nas2.local:5005',
          username: 'admin',
          basePath: '/dav',
          isActive: false,
          createdAt: DateTime(2026, 7, 24),
          updatedAt: DateTime(2026, 7, 24),
        ));
      final storage = FakeSecureStorage()
        ..setPassword(1, 'pw1')
        ..setPassword(2, 'pw2');
      final client = MockWebDavClient();

      final container = ProviderContainer(
        overrides: _overrides(dao: dao, storage: storage, client: client),
      );
      addTearDown(container.dispose);

      // Given: 活跃连接 A，导航栈深度 3（A 深层路径）。
      container.read(navigationStackProvider.notifier).push('/music');
      container.read(navigationStackProvider.notifier).push('/books');
      expect(container.read(navigationStackProvider),
          equals(['/', '/music', '/books']),
          reason: '前置：导航栈应处于深层（深度 3）');

      await tester.pumpWidget(_buildListApp(container));
      await tester.pumpAndSettle();

      // When: 用户切换到连接 B（id=2）。
      await tester.tap(find.text('NAS-2'));
      await tester.pumpAndSettle();

      // Then: navigationStackProvider 复位为仅含根目录。
      expect(container.read(navigationStackProvider), equals(['/']),
          reason: 'TEST-02-S2: 切换连接后导航栈必须复位到根'
              '（CON11：残留深层路径会对新连接发 PROPFIND 得 404）');
      // 否定断言：目录缓存同样被清（与 S1 联动，invalidate 两行缺一不可）。
      expect(container.read(directoryCacheProvider), isEmpty,
          reason: 'TEST-02-S2: 切换连接后目录缓存必须同时清空');
    });
  });
}
