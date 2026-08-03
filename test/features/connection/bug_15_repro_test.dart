// test/features/connection/bug_15_repro_test.dart
// CON1 (docs/cr/cr-20260724-0110) repro + regression guards:
//
//   CON1 — ConnectionScreen._onSave / ConnectionEditScreen._onSave called
//          `ref.invalidate(activeConnectionProvider/connectionListProvider)`
//          AFTER `await saver.save(...)` / `await updater.update(...)` with no
//          `mounted` guard. If the user leaves the page inside the 1~2s
//          save/update window, Riverpod 2.6.1's ConsumerStatefulElement
//          throws `StateError('Cannot use "ref" after the widget was
//          disposed.')` (consumer.dart _assertNotDisposed), which the
//          `catch (e) { if (mounted) ... }` block silently swallows.
//          Consequence: the DB write has landed, but both derived providers
//          (non-autoDispose, no other refresher) keep their stale cached
//          values for the rest of the session → the app keeps using the old
//          connection; a user re-entering the credentials creates a duplicate
//          row (self-heals only on restart).
//
// Fix under test:
//   The refresh duty moves down to the provider layer: connectionSaverProvider
//   / connectionUpdaterProvider now return wrappers that invalidate
//   activeConnectionProvider + connectionListProvider via the container-level
//   provider ref right after the service call succeeds — exactly like
//   switchActiveConnectionProvider / deleteConnectionProvider already do.
//   Widgets no longer call ref.invalidate; a disposed element can never
//   poison the refresh. Real save/update failures still rethrow into the
//   widget's catch → the error SnackBar is preserved.
//
// Pre-fix FAIL evidence: after "tap save → back out → complete the DAO gate"
// both activeConnectionProvider and connectionListProvider still resolved to
// their pre-save cached values (null / old URL), even though the DAO row was
// written — the staleness assertions below failed.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:nas_audio_player/core/database/dao/connection_dao.dart';
import 'package:nas_audio_player/core/network/webdav_client.dart';
import 'package:nas_audio_player/features/connection/connection_edit_screen.dart';
import 'package:nas_audio_player/features/connection/connection_provider.dart';
import 'package:nas_audio_player/features/connection/connection_screen.dart';
import 'package:nas_audio_player/shared/models/connection_config.dart';

import '../../helpers/fake_secure_storage.dart';
import '../../helpers/fake_webdav_client.dart';

// ── Test double ──────────────────────────────────────────────────────────────

/// In-memory [ConnectionDao] whose `insert` / `update` can be suspended on a
/// [Completer], simulating the real 1~2s DB-write window during which the
/// user can leave the page.
///
/// Extends the concrete [ConnectionDao] because [ConnectionService] depends
/// on the concrete type. All methods are overridden so the real
/// [DatabaseHelper] singleton is never touched.
class _GateableDao extends ConnectionDao {
  final List<ConnectionConfig> rows = [];
  int _nextId = 0;

  /// When non-null, `insert` awaits this before writing (add-screen window).
  Completer<void>? insertGate;

  /// When non-null, `update` awaits this before writing (edit-screen window).
  Completer<void>? updateGate;

  void seed(ConnectionConfig config) {
    rows.add(config);
    final id = config.id;
    if (id != null && id >= _nextId) _nextId = id + 1;
  }

  @override
  Future<int> insert(ConnectionConfig config,
      {required String passwordKey}) async {
    if (insertGate != null) await insertGate!.future;
    final id = ++_nextId;
    rows.add(config.copyWith(id: id));
    return id;
  }

  @override
  Future<int> update(ConnectionConfig config,
      {required String passwordKey}) async {
    if (updateGate != null) await updateGate!.future;
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

  /// Rollback path in [ConnectionService.save] — plain removal, no
  /// last-connection guard (that guard is a user-facing delete concern).
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

/// [FakeSecureStorage] whose [write] suspends on [writeGate] and then throws
/// — opens a failure window AFTER the user has been able to leave the page
/// (edit path: [ConnectionService.update] writes storage before the DAO).
class _GateableThrowingStorage extends FakeSecureStorage {
  Completer<void>? writeGate;

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
    if (writeGate != null) await writeGate!.future;
    throw Exception('Simulated secure storage write failure');
  }
}

// ── Shared widget scaffolding ───────────────────────────────────────────────

/// Builds a GoRouter app with a launcher page at `/` plus the given extra
/// routes, wrapped in an [UncontrolledProviderScope] driven by [container]
/// so the test can read provider state directly after the page is gone.
Widget _buildApp({
  required ProviderContainer container,
  required List<GoRoute> extraRoutes,
}) {
  final router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        builder: (context, __) => Scaffold(
          body: Center(
            child: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => context.push(extraRoutes.first.path),
                child: const Text('进入页面'),
              ),
            ),
          ),
        ),
      ),
      ...extraRoutes,
    ],
  );
  return UncontrolledProviderScope(
    container: container,
    child: MaterialApp.router(routerConfig: router),
  );
}

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

void main() {
  // ═══════════════════════════════════════════════════════════════════════════
  // CON1-A: 添加页 — save 进行中退出页面，provider 仍须刷新到新连接
  // ═══════════════════════════════════════════════════════════════════════════

  testWidgets('CON1-A: 保存途中退出添加页 → providers 最终反映新连接（不被 dispose 吞掉）',
      (tester) async {
    final dao = _GateableDao()..insertGate = Completer<void>();
    final storage = FakeSecureStorage();
    final client = MockWebDavClient()
      ..returnResult(WebDavValidationResult.success());

    final container = ProviderContainer(
      overrides: _overrides(dao: dao, storage: storage, client: client),
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(_buildApp(
      container: container,
      extraRoutes: [
        GoRoute(
            path: '/connection', builder: (_, __) => const ConnectionScreen()),
        GoRoute(
            path: '/browser',
            builder: (_, __) =>
                const Scaffold(body: Center(child: Text('Browser 页')))),
      ],
    ));
    await tester.pumpAndSettle();

    // Pre-warm the derived providers exactly as the running app does
    // (app shell / browser watch them) so they hold a cached value that only
    // an invalidate can refresh — this is what goes permanently stale in the
    // bug scenario.
    expect(await container.read(activeConnectionProvider.future), isNull);
    expect(await container.read(connectionListProvider.future), isEmpty);

    // Navigate to the add-connection page.
    await tester.tap(find.text('进入页面'));
    await tester.pumpAndSettle();
    expect(find.byType(ConnectionScreen), findsOneWidget);

    // Fill the form and pass the connection test → save enabled.
    await tester.enterText(find.widgetWithText(TextFormField, '服务器地址 *'),
        'http://192.168.1.200:5005');
    await tester.enterText(
        find.widgetWithText(TextFormField, '用户名 *'), 'admin');
    await tester.enterText(
        find.widgetWithText(TextFormField, '密码 *'), 'secret');
    await tester.tap(find.text('测试连接'));
    await tester.pumpAndSettle();
    expect(find.text('连接成功！'), findsOneWidget);

    // Tap "保存" — dao.insert now hangs on the gate: the save is in-flight.
    await tester.tap(find.text('保存'));
    await tester.pump();
    expect(find.text('保存中…'), findsOneWidget, reason: '保存应已进入进行中状态');

    // The user leaves the page inside the save window (system back).
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.byType(ConnectionScreen), findsNothing,
        reason: '页面应已退出并 dispose');

    // The DB write completes AFTER the page is gone.
    dao.insertGate!.complete();
    await tester.pump();
    await tester.pumpAndSettle();

    // The save itself succeeded — the row landed.
    expect(dao.rows, hasLength(1), reason: 'save() 应已落库');

    // ── Key assertions: derived providers must reflect the new connection.
    // Pre-fix these resolved to the stale cached values (null / []), because
    // the widget-level ref.invalidate threw StateError and was swallowed.
    final active = await container.read(activeConnectionProvider.future);
    expect(active, isNotNull, reason: '退出页面后活跃连接仍须刷新（BUG：永久持旧 null 值）');
    expect(active!.url, equals('http://192.168.1.200:5005'));
    expect(active.isActive, isTrue);

    final list = await container.read(connectionListProvider.future);
    expect(list, hasLength(1), reason: '退出页面后连接列表仍须刷新（BUG：永久持旧空列表）');
    expect(list.single.url, equals('http://192.168.1.200:5005'));
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // CON1-B: 编辑页 — update 进行中退出页面，活跃连接 provider 仍须刷新到新 URL
  // ═══════════════════════════════════════════════════════════════════════════

  testWidgets('CON1-B: 更新途中退出编辑页 → providers 最终反映新 URL（UI 旧值 / DB 新值分裂不再出现）',
      (tester) async {
    final now = DateTime(2026, 7, 24);
    final dao = _GateableDao()
      ..seed(ConnectionConfig(
        id: 1,
        name: 'Home NAS',
        url: 'http://192.168.1.100:5005',
        username: 'admin',
        basePath: '/',
        isActive: true,
        createdAt: now,
        updatedAt: now,
      ))
      ..updateGate = Completer<void>();
    final storage = FakeSecureStorage()..setPassword(1, 'stored-pass');
    final client = MockWebDavClient()
      ..returnResult(WebDavValidationResult.success());

    final container = ProviderContainer(
      overrides: _overrides(dao: dao, storage: storage, client: client),
    );
    addTearDown(container.dispose);

    // Pre-warm so the edit screen pre-fills from data on its first frame
    // (and so the derived providers hold a cacheable stale value).
    final activeBefore = await container.read(activeConnectionProvider.future);
    expect(activeBefore!.url, equals('http://192.168.1.100:5005'));
    await container.read(connectionListProvider.future);

    await tester.pumpWidget(_buildApp(
      container: container,
      extraRoutes: [
        GoRoute(
            path: '/edit',
            builder: (_, __) => const ConnectionEditScreen(connectionId: 1)),
      ],
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('进入页面'));
    await tester.pumpAndSettle();
    expect(find.byType(ConnectionEditScreen), findsOneWidget);

    // Change the URL (a credential-relevant field → re-validation required).
    await tester.enterText(
        find.widgetWithText(TextFormField, 'http://192.168.1.100:5005'),
        'http://192.168.1.150:5005');
    await tester.pump();

    // Re-validate, then tap "保存" — dao.update hangs on the gate.
    await tester.tap(find.text('测试连接'));
    await tester.pumpAndSettle();
    expect(find.text('连接成功！'), findsOneWidget);

    await tester.tap(find.text('保存'));
    await tester.pump();
    expect(find.text('保存中…'), findsOneWidget, reason: '更新应已进入进行中状态');

    // Leave the page inside the update window.
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.byType(ConnectionEditScreen), findsNothing,
        reason: '页面应已退出并 dispose');

    // The DB write completes AFTER the page is gone.
    dao.updateGate!.complete();
    await tester.pump();
    await tester.pumpAndSettle();

    expect(dao.rows.single.url, equals('http://192.168.1.150:5005'),
        reason: 'update() 应已落库');

    // ── Key assertions: the active connection provider must carry the NEW
    // url. Pre-fix it kept resolving to the stale cached old url (UI 旧值、
    // DB 新值), so playback kept hitting the wrong server until restart.
    final active = await container.read(activeConnectionProvider.future);
    expect(active, isNotNull);
    expect(active!.url, equals('http://192.168.1.150:5005'),
        reason: '退出页面后活跃连接仍须刷新到新 URL（BUG：永久持旧 URL）');

    final list = await container.read(connectionListProvider.future);
    expect(list.single.url, equals('http://192.168.1.150:5005'),
        reason: '退出页面后连接列表仍须刷新到新 URL');
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // Regression guard: 真实保存失败的错误提示不得被修复一并吞掉
  // ═══════════════════════════════════════════════════════════════════════════

  testWidgets('CON1 回归：真实保存失败仍弹错误 SnackBar 且回滚 DB 行', (tester) async {
    final dao = _GateableDao(); // no gate — fails fast on storage write
    final storage = ThrowingFakeSecureStorage();
    final client = MockWebDavClient()
      ..returnResult(WebDavValidationResult.success());

    final container = ProviderContainer(
      overrides: _overrides(dao: dao, storage: storage, client: client),
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(_buildApp(
      container: container,
      extraRoutes: [
        GoRoute(
            path: '/connection', builder: (_, __) => const ConnectionScreen()),
      ],
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('进入页面'));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextFormField, '服务器地址 *'),
        'http://192.168.1.200:5005');
    await tester.enterText(
        find.widgetWithText(TextFormField, '用户名 *'), 'admin');
    await tester.enterText(
        find.widgetWithText(TextFormField, '密码 *'), 'secret');
    await tester.tap(find.text('测试连接'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    // The real failure must still surface to the user (catch not over-broad).
    expect(find.textContaining('保存失败'), findsOneWidget,
        reason: 'secure storage 写入失败必须仍有错误提示，不能被 CON1 修复吞掉');
    // …and the service-level rollback removed the half-written row.
    expect(dao.rows, isEmpty, reason: 'storage 写入失败应回滚已插入的连接行');
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // CON1-C / CON1-D: 失败发生在页面 dispose "之后" — 错误到不了 UI，但不得
  //                   静默丢失：必须落日志（复核补强，审计判据"可接受须有日志"）
  // ═══════════════════════════════════════════════════════════════════════════

  testWidgets('CON1-C: dispose 后保存失败 → 错误写入日志，不静默吞错，DB 无残留行', (tester) async {
    final dao = _GateableDao()..insertGate = Completer<void>();
    final storage = ThrowingFakeSecureStorage();
    final client = MockWebDavClient()
      ..returnResult(WebDavValidationResult.success());

    final container = ProviderContainer(
      overrides: _overrides(dao: dao, storage: storage, client: client),
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(_buildApp(
      container: container,
      extraRoutes: [
        GoRoute(
            path: '/connection', builder: (_, __) => const ConnectionScreen()),
      ],
    ));
    await tester.pumpAndSettle();

    // Pre-warm so the derived providers hold a cached value that a wrongful
    // failure-path invalidate would disturb.
    expect(await container.read(activeConnectionProvider.future), isNull);
    expect(await container.read(connectionListProvider.future), isEmpty);

    await tester.tap(find.text('进入页面'));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextFormField, '服务器地址 *'),
        'http://192.168.1.200:5005');
    await tester.enterText(
        find.widgetWithText(TextFormField, '用户名 *'), 'admin');
    await tester.enterText(
        find.widgetWithText(TextFormField, '密码 *'), 'secret');
    await tester.tap(find.text('测试连接'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('保存'));
    await tester.pump();
    expect(find.text('保存中…'), findsOneWidget);

    // Leave the page inside the save window; the failure lands AFTER dispose.
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.byType(ConnectionScreen), findsNothing,
        reason: '页面应已退出并 dispose');

    // The failure completes after the page is gone: insert lands, storage
    // write throws, service rolls the row back. Capture debugPrint around
    // the gate completion so the post-dispose error path is assertable
    // (restored in finally — flutter_test verifies foundation debug vars).
    final logs = <String>[];
    final originalDebugPrint = debugPrint;
    debugPrint = (message, {wrapWidth}) => logs.add(message ?? '');
    try {
      dao.insertGate!.complete();
      await tester.pump();
      await tester.pumpAndSettle();
    } finally {
      debugPrint = originalDebugPrint;
    }

    // The error must not vanish silently just because the UI is gone.
    expect(
      logs.where((l) => l.contains('save failed after page disposed')),
      isNotEmpty,
      reason: 'dispose 后保存失败必须有日志，不得静默吞错',
    );
    // …the rollback still ran — no half-written row lingers.
    expect(dao.rows, isEmpty, reason: 'storage 写入失败应回滚已插入的连接行');
    // …and the failure path must not have refreshed derived providers to
    // phantom state (no invalidate on failure).
    expect(await container.read(activeConnectionProvider.future), isNull);
    expect(await container.read(connectionListProvider.future), isEmpty);
  });

  testWidgets('CON1-D: dispose 后更新失败 → 错误写入日志，DB 保持旧值', (tester) async {
    final now = DateTime(2026, 7, 24);
    final dao = _GateableDao()
      ..seed(ConnectionConfig(
        id: 1,
        name: 'Home NAS',
        url: 'http://192.168.1.100:5005',
        username: 'admin',
        basePath: '/',
        isActive: true,
        createdAt: now,
        updatedAt: now,
      ));
    // ConnectionService.update writes storage BEFORE the DAO, so the
    // suspension window + failure point must both sit on the storage write.
    final storage = _GateableThrowingStorage()..writeGate = Completer<void>();
    final client = MockWebDavClient()
      ..returnResult(WebDavValidationResult.success());

    final container = ProviderContainer(
      overrides: _overrides(dao: dao, storage: storage, client: client),
    );
    addTearDown(container.dispose);

    // Pre-warm so the edit screen pre-fills from data on its first frame.
    final activeBefore = await container.read(activeConnectionProvider.future);
    expect(activeBefore!.url, equals('http://192.168.1.100:5005'));
    await container.read(connectionListProvider.future);

    await tester.pumpWidget(_buildApp(
      container: container,
      extraRoutes: [
        GoRoute(
            path: '/edit',
            builder: (_, __) => const ConnectionEditScreen(connectionId: 1)),
      ],
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('进入页面'));
    await tester.pumpAndSettle();
    expect(find.byType(ConnectionEditScreen), findsOneWidget);

    // Change the URL and provide a new password so the update path performs
    // a secure-storage write (the injected failure point).
    await tester.enterText(
        find.widgetWithText(TextFormField, 'http://192.168.1.100:5005'),
        'http://192.168.1.150:5005');
    await tester.enterText(
        find.widgetWithText(TextFormField, '密码（留空保持不变）'), 'new-pass');
    await tester.pump();

    await tester.tap(find.text('测试连接'));
    await tester.pumpAndSettle();
    expect(find.text('连接成功！'), findsOneWidget);

    await tester.tap(find.text('保存'));
    await tester.pump();
    expect(find.text('保存中…'), findsOneWidget);

    // Leave the page inside the update window.
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.byType(ConnectionEditScreen), findsNothing,
        reason: '页面应已退出并 dispose');

    // The failure completes after the page is gone: the storage gate opens
    // and the write throws before any DB update runs. Capture debugPrint
    // around the gate completion (restored in finally — flutter_test
    // verifies foundation debug vars).
    final logs = <String>[];
    final originalDebugPrint = debugPrint;
    debugPrint = (message, {wrapWidth}) => logs.add(message ?? '');
    try {
      storage.writeGate!.complete();
      await tester.pump();
      await tester.pumpAndSettle();
    } finally {
      debugPrint = originalDebugPrint;
    }

    // The error must not vanish silently just because the UI is gone.
    expect(
      logs.where((l) => l.contains('update failed after page disposed')),
      isNotEmpty,
      reason: 'dispose 后更新失败必须有日志，不得静默吞错',
    );
    // …the DB row kept the OLD url (update never ran).
    expect(dao.rows.single.url, equals('http://192.168.1.100:5005'),
        reason: 'storage 写入失败前不得改库');
    // …and derived providers still resolve to the old config (no phantom
    // refresh on the failure path).
    final active = await container.read(activeConnectionProvider.future);
    expect(active!.url, equals('http://192.168.1.100:5005'));
  });
}
