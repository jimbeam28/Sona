// test/features/connection/bug_16_repro_test.dart
// CON3 (docs/cr/cr-20260724-0110) repro + regression guards:
//
//   CON3 — editing the ACTIVE connection (changing url / basePath) left the
//          browser's directory cache and navigation stack untouched. The
//          cache key is `'${conn.id}:$path'` (browser_provider.dart) — the
//          edit keeps the connection id — so within the 5-minute TTL
//          directoryContentsProvider kept serving listings fetched from the
//          OLD server / OLD basePath (up to 5 minutes of stale content), and
//          a deep navigationStack path was PROPFIND-ed against the new
//          basePath → 404. Before this fix the only production path that
//          cleared browser state was connection *switching*
//          (connection_list_screen.dart widget layer); the edit-save path
//          (connection_edit_screen.dart → connectionUpdaterProvider) only
//          invalidated activeConnectionProvider / connectionListProvider
//          (CON1), never the browser providers.
//
// Fix under test:
//   A unified, reusable provider-layer hook —
//   resetBrowserStateOnActiveConnectionChange(ref) in connection_provider.dart
//   — invalidates directoryCacheProvider + navigationStackProvider (same
//   actions as the switch path, reached through the shared/di bridge per
//   REF-31; CON4 will extend the same hook for delete). The edit-save path
//   plugs in via _UpdateAndRefreshUpdater: after super.update succeeds it
//   refreshes the derived connection providers (CON1) AND resets browser
//   state (CON3). Widgets never clear providers themselves.
//
// Pre-fix FAIL evidence: after "browse /music → edit active connection url/
// basePath → save", directoryCacheProvider still held the stale entry,
// navigationStackProvider still pointed at the deep path, and re-reading
// directoryContentsProvider('/music') hit the TTL cache — no new PROPFIND,
// old server's listing returned.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:nas_audio_player/core/database/dao/connection_dao.dart';
import 'package:nas_audio_player/core/network/webdav_client.dart';
import 'package:nas_audio_player/features/browser/browser_provider.dart';
import 'package:nas_audio_player/features/connection/connection_edit_screen.dart';
import 'package:nas_audio_player/features/connection/connection_provider.dart';
import 'package:nas_audio_player/shared/models/connection_config.dart';

import '../../helpers/fake_secure_storage.dart';
import '../../helpers/fake_webdav_client.dart';
import '../../helpers/test_database.dart';
import '../../helpers/test_factories.dart';

// ── Test double ──────────────────────────────────────────────────────────────

/// In-memory [ConnectionDao] for widget tests.
///
/// Extends the concrete [ConnectionDao] because [ConnectionService] depends
/// on the concrete type. All methods are overridden with pure-async bodies so
/// the widget test's FakeAsync zone never blocks on real sqflite-ffi isolate
/// events (same rationale as bug_15's gateable fake). The real ffi DAO still
/// covers the provider-layer test (CON3-A) below.
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

void main() {
  setUpAll(() {
    initSqfliteFfi();
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // CON3-A: provider layer — updating the active connection must reset
  //         browser state (cache cleared, nav stack reset, next directory
  //         read goes out with the new config instead of hitting TTL cache).
  //         Uses the REAL ffi DAO — plain test(), no FakeAsync involved.
  // ═══════════════════════════════════════════════════════════════════════════

  test('CON3-A: 编辑活跃连接 url/basePath 后目录缓存清空、导航栈复位、目录按新配置重新加载', () async {
    final db = await openTestDatabase(TestSchema.connections);
    addTearDown(db.close);
    final dao = ConnectionDao();

    // Active connection A: the "old" server / base path.
    final connId = await dao.insert(
      testConfig(name: 'Old NAS', url: 'http://nas-old.local:5005'),
      passwordKey: 'key_old',
    );
    await dao.setActive(connId);

    final storage = FakeSecureStorage()..setPassword(connId, 'pw-old');
    final spy = SpyWebDavClient()
      ..returnResult([testAudio('old.mp3', '/music/old.mp3')]);

    final container = ProviderContainer(
      overrides: _overrides(dao: dao, storage: storage, client: spy),
    );
    addTearDown(container.dispose);

    // 1. Browse /music under the old config — cache entry '$connId:/music'
    //    lands with a fresh 5-minute TTL.
    final first =
        await container.read(directoryContentsProvider('/music').future);
    expect(first.single.name, equals('old.mp3'));
    expect(spy.listDirectoryCallCount, equals(1), reason: '首次浏览应发一次 PROPFIND');
    expect(container.read(directoryCacheProvider), isNotEmpty,
        reason: '浏览后缓存应有条目（TTL 5 分钟内）');

    // 2. The user navigated deep — stack now ['/', '/music'].
    container.read(navigationStackProvider.notifier).push('/music');
    expect(container.read(navigationStackProvider), equals(['/', '/music']));

    // 3. Edit-save the active connection: new server + new base path.
    //    This is exactly what connection_edit_screen.dart does on "保存".
    final active = (await container.read(activeConnectionProvider.future))!;
    expect(active.id, equals(connId));
    await container.read(connectionUpdaterProvider).update(
          config: active.copyWith(
            url: 'http://nas-new.local:5005',
            basePath: '/media',
          ),
        );
    expect(
        (await dao.findById(connId))!.url, equals('http://nas-new.local:5005'),
        reason: '前置：update 应已落库');

    // 4. ── Key assertions (FAIL pre-fix) ─────────────────────────────────
    //    BUG: pre-fix the stale entry survived and the stack still pointed
    //    at /music, which does not exist under the new basePath '/media'.
    expect(container.read(directoryCacheProvider), isEmpty,
        reason: 'CON3: 编辑活跃连接后目录缓存必须清空'
            '（BUG：id 不变 → 缓存键命中 → 5 分钟 TTL 内继续展示旧服务器内容）');
    expect(container.read(navigationStackProvider), equals(['/']),
        reason: 'CON3: 导航栈必须复位到根'
            '（BUG：深层路径对新 basePath 发 PROPFIND 得 404）');

    // 5. ── Behaviour-level: the next directory read must miss the cache,
    //    issue a fresh PROPFIND and serve the NEW server's listing.
    //    Pre-fix it hit the TTL cache: count stayed 1, old.mp3 returned.
    spy.returnResult([testAudio('new.mp3', '/music/new.mp3')]);
    final second =
        await container.read(directoryContentsProvider('/music').future);
    expect(spy.listDirectoryCallCount, equals(2),
        reason: 'CON3: 缓存清空后重新浏览应再发 PROPFIND（BUG：命中旧缓存不请求）');
    expect(second.single.name, equals('new.mp3'),
        reason: 'CON3: 应展示新配置服务器的目录内容（BUG：TTL 内一直返回旧列表）');
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // CON3-B: end-to-end — the edit SCREEN's save-success path must wire into
  //         the same hook (browse → edit url → 测试连接 → 保存 → browser state
  //         reset, verified after the edit page has popped / disposed)
  // ═══════════════════════════════════════════════════════════════════════════

  testWidgets('CON3-B: 编辑页保存成功返回后浏览器缓存/导航栈已复位（端到端）', (tester) async {
    final dao = _InMemoryDao()
      ..seed(ConnectionConfig(
        id: 1,
        name: 'Old NAS',
        url: 'http://nas-old.local:5005',
        username: 'admin',
        basePath: '/dav',
        isActive: true,
        createdAt: DateTime(2026, 7, 24),
        updatedAt: DateTime(2026, 7, 24),
      ));
    final storage = FakeSecureStorage()..setPassword(1, 'pw-old');
    final client = MockWebDavClient()
      ..returnResult(WebDavValidationResult.success())
      ..returnListResult([testAudio('old.mp3', '/music/old.mp3')]);

    final container = ProviderContainer(
      overrides: _overrides(dao: dao, storage: storage, client: client),
    );
    addTearDown(container.dispose);

    // Pre-warm exactly as the running app does: the browser tab has already
    // listed /music (cache entry with live TTL) and the user is deep in it.
    await container.read(activeConnectionProvider.future);
    await container.read(connectionListProvider.future);
    final first =
        await container.read(directoryContentsProvider('/music').future);
    expect(first.single.name, equals('old.mp3'));
    container.read(navigationStackProvider.notifier).push('/music');

    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(
          path: '/',
          builder: (context, __) => Scaffold(
            body: Center(
              child: Builder(
                builder: (context) => ElevatedButton(
                  onPressed: () => context.push('/edit'),
                  child: const Text('进入页面'),
                ),
              ),
            ),
          ),
        ),
        GoRoute(
          path: '/edit',
          builder: (_, __) => const ConnectionEditScreen(connectionId: 1),
        ),
      ],
    );
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(routerConfig: router),
    ));
    await tester.pumpAndSettle();

    // Enter the edit page, change the URL (credential-relevant → re-validation
    // required), validate, save.
    await tester.tap(find.text('进入页面'));
    await tester.pumpAndSettle();
    expect(find.byType(ConnectionEditScreen), findsOneWidget);

    await tester.enterText(
      find.widgetWithText(TextFormField, 'http://nas-old.local:5005'),
      'http://nas-new.local:5005',
    );
    await tester.pump();
    await tester.tap(find.text('测试连接'));
    await tester.pumpAndSettle();
    expect(find.text('连接成功！'), findsOneWidget);

    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(find.byType(ConnectionEditScreen), findsNothing,
        reason: '保存成功后编辑页应已 pop');
    expect(dao.rows.single.url, equals('http://nas-new.local:5005'),
        reason: '前置：update 应已落库');

    // ── Key assertions (FAIL pre-fix): the edit-save success path must have
    // reset browser state even though the widget never touches providers.
    expect(container.read(directoryCacheProvider), isEmpty,
        reason: 'CON3: 编辑页保存成功后目录缓存必须清空'
            '（BUG：5 分钟 TTL 内浏览 Tab 继续展示旧服务器内容）');
    expect(container.read(navigationStackProvider), equals(['/']),
        reason: 'CON3: 编辑页保存成功后导航栈必须复位到根');

    // Behaviour-level: the browser tab now shows the new server's content.
    client.returnListResult([testAudio('new.mp3', '/music/new.mp3')]);
    final second =
        await container.read(directoryContentsProvider('/music').future);
    expect(second.single.name, equals('new.mp3'),
        reason: 'CON3: 返回浏览 Tab 后应展示新配置的内容（BUG：命中旧缓存）');
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // Regression guard: a FAILED update must NOT wipe browser state — the
  // reset lives strictly on the success path (after super.update resolves),
  // mirroring the CON1 wrapper contract.
  // ═══════════════════════════════════════════════════════════════════════════

  test('CON3 回归：更新失败（密码轮换写 secure storage 抛错）不清浏览器状态', () async {
    final db = await openTestDatabase(TestSchema.connections);
    addTearDown(db.close);
    final dao = ConnectionDao();

    final connId = await dao.insert(
      testConfig(name: 'NAS', url: 'http://nas.local:5005'),
      passwordKey: 'key_x',
    );
    await dao.setActive(connId);

    final storage = ThrowingFakeSecureStorage()..setPassword(connId, 'pw');
    final spy = SpyWebDavClient()
      ..returnResult([testAudio('song.mp3', '/music/song.mp3')]);

    final container = ProviderContainer(
      overrides: _overrides(dao: dao, storage: storage, client: spy),
    );
    addTearDown(container.dispose);

    await container.read(directoryContentsProvider('/music').future);
    container.read(navigationStackProvider.notifier).push('/music');

    final active = (await container.read(activeConnectionProvider.future))!;

    // Password rotation → secure storage write throws inside super.update.
    await expectLater(
      container.read(connectionUpdaterProvider).update(
            config: active.copyWith(url: 'http://nas-new.local:5005'),
            password: 'rotated-pw',
          ),
      throwsA(anything),
      reason: 'storage 写入失败必须向上传播（CON1 错误路径保留）',
    );

    // Browser state must be untouched on the failure path.
    expect(container.read(directoryCacheProvider), isNotEmpty,
        reason: '更新失败时不得清缓存（复位只发生在成功路径）');
    expect(container.read(navigationStackProvider), equals(['/', '/music']),
        reason: '更新失败时不得复位导航栈');
  });
}
