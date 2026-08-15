// test/features/connection/bug_bug10_repro_test.dart
// BUG-10 (docs/features/BUG-10.md) — 删除活跃连接后不复位导航栈 — spec §5.4 门禁测试.
//
// 复核背景（af084af / cr-20260804-1922）：生产修复 596a63b 已落地且正确
// （connection_service.dart delete 返回 wasActive；connection_provider.dart
// deleteConnectionProvider 捕获 wasActive 并条件性调
// resetBrowserStateOnActiveConnectionChange(ref)，钩子 invalidate
// directoryCacheProvider + navigationStackProvider），但 spec §5.4 原指定的门禁
// 文件从未创建——con_06_test 只断言删除+密码清理，无浏览器重置断言，回退
// `if (wasActive)` 分支既有测试照样绿（§5.3 两态门禁欠账）。
//
// 本套件守护修复后的全部 S/INV：
//
// BUG-10-S1 正向（T01）: 活跃连接 A 浏览到 3 层深 → 删除 A → B 自动激活 →
//                       directoryCacheProvider 清空 + navigationStackProvider
//                       复位到根 + 重新浏览发新 PROPFIND（回退 `if (wasActive)`
//                       分支 → 命中 TTL 旧缓存不发请求 → 本用例红）
// BUG-10-S1 否定（T02）: 删除**非活跃**连接 → 浏览器状态原样保留
//                       （directoryCache 同一实例 + 条目保留 + 导航栈不变 +
//                       重新浏览命中缓存不发 PROPFIND；回退分支 → 误清缓存 → 红）
// BUG-10-INV1（T03）: 切换/编辑/删除三入口（connection_list_screen.dart:78-80 /
//                    connection_provider.dart:316 / :355-357 同钩子）在同一
//                    container 内依次驱动，各自断言浏览器状态被重置
//
// 否定断言（对应 spec §3.1）：
//   - 不遗留旧连接的目录缓存
//   - 不遗留旧连接的导航栈（浏览器不停留深层路径）
//   - 不影响非活跃连接删除时的浏览器状态

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nas_audio_player/core/database/dao/connection_dao.dart';
import 'package:nas_audio_player/core/network/webdav_client.dart';
import 'package:nas_audio_player/features/browser/browser_provider.dart';
import 'package:nas_audio_player/features/connection/connection_list_screen.dart';
import 'package:nas_audio_player/features/connection/connection_provider.dart';
import 'package:nas_audio_player/shared/models/connection_config.dart';
import 'package:nas_audio_player/shared/models/nas_file.dart';

import '../../helpers/fake_secure_storage.dart';
import '../../helpers/fake_webdav_client.dart';
import '../../helpers/test_database.dart';
import '../../helpers/test_factories.dart';

// ── Test double ──────────────────────────────────────────────────────────────

/// In-memory [ConnectionDao] for the INV1 widget test. All methods are
/// overridden with pure-async bodies so the widget test's FakeAsync zone never
/// blocks on real sqflite-ffi isolate events (same rationale as bug_15/bug_16
/// gateable fakes, mirroring test_02_con11_test.dart).
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
  required WebDavClientInterface client,
}) =>
    [
      connectionDaoProvider.overrideWithValue(dao),
      secureStorageProvider.overrideWithValue(storage),
      webDavClientProvider.overrideWithValue(client),
      // Keep the test hermetic: no background PROPFIND on active changes.
      startupValidationProvider.overrideWith((ref) async => null),
    ];

/// Fresh-TTL cache entry（5 分钟 TTL 窗口内命中缓存，不发 PROPFIND）。
CacheEntry<List<NasFile>> _cacheEntry(NasFile file) =>
    CacheEntry<List<NasFile>>(
      value: [file],
      createdAt: DateTime.now(),
    );

void main() {
  setUpAll(() {
    initSqfliteFfi();
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // BUG-10-S1 正向：删除活跃连接 → 浏览器状态重置（真实 ffi DAO + 真实
  // directoryContentsProvider 链路，CON3-A 同款驱动方式）
  // ═══════════════════════════════════════════════════════════════════════════

  test('BUG-10-S1: 删除活跃连接 A 后目录缓存清空、导航栈复位到根、目录按新连接重新加载', () async {
    final db = await openTestDatabase(TestSchema.connections);
    addTearDown(db.close);
    final dao = ConnectionDao();

    // 活跃连接 A（id=1）+ 非活跃连接 B（id=2）
    final idA = await dao.insert(
      testConfig(name: 'NAS-A', url: 'http://nas-a.local:5005'),
      passwordKey: 'key_a',
    );
    final idB = await dao.insert(
      testConfig(name: 'NAS-B', url: 'http://nas-b.local:5005'),
      passwordKey: 'key_b',
    );
    await dao.setActive(idA);
    expect((await dao.findActive())!.id, equals(idA), reason: '前置：A 应为活跃连接');

    final storage = FakeSecureStorage()
      ..setPassword(idA, 'pw-a')
      ..setPassword(idB, 'pw-b');
    final spy = SpyWebDavClient()
      ..returnResult([testAudio('old.mp3', '/music/old.mp3')]);

    final container = ProviderContainer(
      overrides: _overrides(dao: dao, storage: storage, client: spy),
    );
    addTearDown(container.dispose);

    // U1：连接 A 浏览到 3 层深（/music 已缓存，栈含深层路径）。
    final first =
        await container.read(directoryContentsProvider('/music').future);
    expect(first.single.name, equals('old.mp3'),
        reason: '前置：A 配置下浏览 /music 应取到 A 的目录列表');
    expect(spy.listDirectoryCallCount, equals(1),
        reason: '前置：首次浏览应发一次 PROPFIND');
    expect(container.read(directoryCacheProvider), isNotEmpty,
        reason: '前置：浏览后缓存应有条目（TTL 5 分钟内）');
    container.read(navigationStackProvider.notifier).push('/music');
    container.read(navigationStackProvider.notifier).push('/music/album');
    expect(container.read(navigationStackProvider),
        equals(['/', '/music', '/music/album']),
        reason: '前置：导航栈应处于 3 层深');

    // When：删除活跃连接 A → DAO 自动激活 B（CON-T34）。
    await container.read(deleteConnectionProvider(idA).future);

    // Then ── 核心断言（回退 connection_provider.dart:355-357 的 if (wasActive)
    // 分支 → 缓存不清/栈不复位 → 本用例红）────────────────────────────
    expect(container.read(directoryCacheProvider), isEmpty,
        reason: 'BUG-10-S1: 删除活跃连接后目录缓存必须清空'
            '（不得遗留旧连接 A 的缓存条目）');
    expect(container.read(navigationStackProvider), equals(['/']),
        reason: 'BUG-10-S1: 删除活跃连接后导航栈必须复位到根'
            '（不得停留 A 的深层路径，否则对新连接发旧路径 PROPFIND 得 404）');

    // 前置：B 已自动激活。
    final active = (await container.read(activeConnectionProvider.future))!;
    expect(active.id, equals(idB), reason: '删除活跃连接后应自动激活 B');

    // 行为级：缓存清空后重新浏览 /music 必须再发 PROPFIND 并取到新列表。
    // （回退修复 → 命中 5 分钟 TTL 旧缓存 → count 仍为 1 → 断言红）
    spy.returnResult([testAudio('new.mp3', '/music/new.mp3')]);
    final second =
        await container.read(directoryContentsProvider('/music').future);
    expect(spy.listDirectoryCallCount, equals(2),
        reason: 'BUG-10-S1: 缓存清空后重新浏览应再发 PROPFIND（不得命中旧缓存）');
    expect(second.single.name, equals('new.mp3'),
        reason: 'BUG-10-S1: 应展示新连接 B 配置的目录内容（不得返回旧列表）');
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // BUG-10-S1 否定：删除非活跃连接 → 浏览器状态原样保留（回退 `if (wasActive)`
  // 分支 → 误清缓存/误复位导航栈 → 本用例红，两态门禁）
  // ═══════════════════════════════════════════════════════════════════════════

  test('BUG-10-S1 否定: 删除非活跃连接 B 不触发浏览器重置（缓存对象同一实例、导航栈原样保留）', () async {
    final db = await openTestDatabase(TestSchema.connections);
    addTearDown(db.close);
    final dao = ConnectionDao();

    final idA = await dao.insert(
      testConfig(name: 'NAS-A', url: 'http://nas-a.local:5005'),
      passwordKey: 'key_a',
    );
    final idB = await dao.insert(
      testConfig(name: 'NAS-B', url: 'http://nas-b.local:5005'),
      passwordKey: 'key_b',
    );
    await dao.setActive(idA);

    final storage = FakeSecureStorage()
      ..setPassword(idA, 'pw-a')
      ..setPassword(idB, 'pw-b');
    final spy = SpyWebDavClient()
      ..returnResult([testAudio('song.mp3', '/music/song.mp3')]);

    final container = ProviderContainer(
      overrides: _overrides(dao: dao, storage: storage, client: spy),
    );
    addTearDown(container.dispose);

    // Given：浏览器处于 A 的深层状态——缓存含 A 的条目（新鲜 TTL），栈深 3 层。
    // 直写 state 预置缓存（set_01_test 同款手法），并记住同一实例以便"原样"断言。
    final armed = {
      '$idA:/music': _cacheEntry(testAudio('song.mp3', '/music/song.mp3')),
      '$idA:/books': _cacheEntry(testAudio('book.mp3', '/books/book.mp3')),
    };
    container.read(directoryCacheProvider.notifier).state = armed;
    final cacheBefore = container.read(directoryCacheProvider);
    expect(cacheBefore, isNotEmpty, reason: '前置：删除前缓存必须非空');
    container.read(navigationStackProvider.notifier).push('/music');
    container.read(navigationStackProvider.notifier).push('/books');
    expect(container.read(navigationStackProvider),
        equals(['/', '/music', '/books']),
        reason: '前置：导航栈应处于 3 层深');

    // When：删除非活跃连接 B（真实 DAO 返回 wasActive=false，CON-T33）。
    await container.read(deleteConnectionProvider(idB).future);

    // Then ── 否定断言：浏览器状态必须原样保留 ────────────────────────────
    expect(container.read(directoryCacheProvider), same(cacheBefore),
        reason: '否定: 删除非活跃连接不得触碰 directoryCacheProvider 状态'
            '（invalidate/重建会产生新实例）');
    expect(container.read(directoryCacheProvider).containsKey('$idA:/music'),
        isTrue,
        reason: '否定: 旧连接 A 的缓存条目必须原样保留');
    expect(container.read(directoryCacheProvider).containsKey('$idA:/books'),
        isTrue,
        reason: '否定: 旧连接 A 的缓存条目必须原样保留');
    expect(container.read(navigationStackProvider),
        equals(['/', '/music', '/books']),
        reason: '否定: 导航栈必须原样保留（不得复位到根）');

    // 前置：删除完成且活跃连接不受影响。
    expect(await dao.findById(idB), isNull, reason: '前置：B 应已被删除');
    final active = (await container.read(activeConnectionProvider.future))!;
    expect(active.id, equals(idA), reason: '前置：活跃连接 A 应不受影响');

    // 行为级否定：重新浏览 /music 命中 TTL 缓存，不发新 PROPFIND
    // （缓存若被误清 → 重新 PROPFIND → count 变 1 → 断言红）。
    final cached =
        await container.read(directoryContentsProvider('/music').future);
    expect(spy.listDirectoryCallCount, equals(0),
        reason: '否定: 删除非活跃连接后重新浏览应命中缓存，不得发 PROPFIND');
    expect(cached.single.name, equals('song.mp3'), reason: '否定: 命中缓存应返回原列表');
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // BUG-10-INV1：活跃连接变更（切换/编辑/删除）三入口均触发浏览器状态重置。
  // 同一 container 内依次驱动三入口（widget 层切换 + provider 层编辑/删除），
  // 各自断言缓存清空 + 导航栈复位到根。切换/编辑路径既有覆盖（con11 /
  // bug_16），本用例补齐删除路径并对比同钩子语义。
  // ═══════════════════════════════════════════════════════════════════════════

  testWidgets('BUG-10-INV1: 切换/编辑/删除三入口均触发浏览器状态重置（删除路径同钩子）', (tester) async {
    final dao = _InMemoryDao()
      ..seed(ConnectionConfig(
        id: 1,
        name: 'NAS-A',
        url: 'http://nas-a.local:5005',
        username: 'admin',
        basePath: '/dav',
        isActive: true,
        createdAt: DateTime(2026, 7, 24),
        updatedAt: DateTime(2026, 7, 24),
      ))
      ..seed(ConnectionConfig(
        id: 2,
        name: 'NAS-B',
        url: 'http://nas-b.local:5005',
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

    const file =
        NasFile(name: 'song.mp3', path: '/music/song.mp3', isDirectory: false);

    // 把浏览器拨到"深层状态"：缓存非空 + 栈深 2 层。
    void armBrowser() {
      container.read(directoryCacheProvider.notifier).state = {
        '1:/music': _cacheEntry(file),
        '2:/music': _cacheEntry(file),
      };
      container.read(navigationStackProvider.notifier).push('/music');
      expect(container.read(directoryCacheProvider), isNotEmpty,
          reason: '前置：arm 后缓存必须非空（否则断言失去意义）');
      expect(container.read(navigationStackProvider), equals(['/', '/music']),
          reason: '前置：arm 后导航栈必须处于深层');
    }

    void expectReset(String entry) {
      expect(container.read(directoryCacheProvider), isEmpty,
          reason: 'INV1: $entry 后目录缓存必须清空');
      expect(container.read(navigationStackProvider), equals(['/']),
          reason: 'INV1: $entry 后导航栈必须复位到根');
    }

    // ── 入口 1：切换（connection_list_screen.dart:78-80 widget 层 invalidate）──
    armBrowser();
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(
        home: Scaffold(body: ConnectionListScreen()),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('NAS-B'));
    await tester.pumpAndSettle();
    expectReset('切换');
    expect(
        (await container.read(activeConnectionProvider.future))!.id, equals(2),
        reason: '前置：切换后活跃连接应为 B');

    // ── 入口 2：编辑（connection_provider.dart:316 update 路径同钩子）──
    armBrowser();
    final active = (await container.read(activeConnectionProvider.future))!;
    await container.read(connectionUpdaterProvider).update(
          config: active.copyWith(url: 'http://nas-b-new.local:5005'),
        );
    expectReset('编辑');
    expect((await dao.findById(2))!.url, equals('http://nas-b-new.local:5005'),
        reason: '前置：编辑应已落库');

    // ── 入口 3：删除（BUG-10 修复目标，connection_provider.dart:355-357）──
    armBrowser();
    await container.read(deleteConnectionProvider(2).future);
    expectReset('删除');
    expect(await dao.findById(2), isNull, reason: '前置：连接 B 应已被删除');
  });
}
