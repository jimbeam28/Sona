// test/features/connection/test_02_con12_test.dart
// TEST-02-S3/S4/S5 (CON12): ConnectionEditScreen widget 测试
//
// 覆盖 spec §3.2：
//   S3 — 只改名称直接保存（S10）：update 被调、validate 未调、pop 回列表
//   S4 — 改 URL 未验证点保存（S12 门控）：弹 SnackBar、update 未调
//   S5 — 首帧 connectionListProvider 未解析（INV7）：渲染不崩溃、数据到达后
//        保存成功（BUG-24-S1 兜底：_originalConfig 捕获失败 → 按 id 现查）
//
// 装配模式镜像 bug_15/bug_16/bug_bug24：in-memory DAO（纯 async，避免
// FakeAsync 阻塞 ffi isolate）+ FakeSecureStorage + 录制 validate 的 client +
// UncontrolledProviderScope 共享容器 + GoRouter。

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:nas_audio_player/core/database/dao/connection_dao.dart';
import 'package:nas_audio_player/core/network/webdav_client.dart';
import 'package:nas_audio_player/features/connection/connection_edit_screen.dart';
import 'package:nas_audio_player/features/connection/connection_provider.dart';
import 'package:nas_audio_player/shared/models/connection_config.dart';

import '../../helpers/fake_secure_storage.dart';
import '../../helpers/fake_webdav_client.dart';

// ── Test doubles ─────────────────────────────────────────────────────────────

/// In-memory [ConnectionDao] whose `findAll` can be suspended on a gate so the
/// edit screen's first frame sees an unresolved list (TEST-02-S5 window).
/// Extends the concrete [ConnectionDao] because [ConnectionService] depends on
/// the concrete type; all methods are overridden so the real [DatabaseHelper]
/// singleton is never touched.
class _GateableDao extends ConnectionDao {
  final List<ConnectionConfig> rows = [];
  int _nextId = 0;

  /// When non-null, `findAll` awaits this before returning (first-frame
  /// capture-failure window).
  Completer<void>? findAllGate;

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
  Future<List<ConnectionConfig>> findAll() async {
    final gate = findAllGate;
    if (gate != null) await gate.future;
    return List.of(rows);
  }

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

/// [MockWebDavClient] that records every `validate` call so tests can assert
/// that name-only saves never trigger a validation request.
class _RecordingWebDavClient extends MockWebDavClient {
  int validateCallCount = 0;

  @override
  Future<WebDavValidationResult> validate({
    required String url,
    required String username,
    required String password,
    String basePath = '/',
  }) async {
    validateCallCount++;
    return super.validate(
        url: url, username: username, password: password, basePath: basePath);
  }
}

// ── Shared scaffolding (mirrors bug_15/bug_bug24) ────────────────────────────

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

ConnectionConfig _seedConfig() => ConnectionConfig(
      id: 1,
      name: 'Home NAS',
      url: 'http://192.168.1.100:5005',
      username: 'admin',
      basePath: '/',
      isActive: true,
      createdAt: DateTime(2026, 7, 24),
      updatedAt: DateTime(2026, 7, 24),
    );

void main() {
  group('TEST-02-S3: 编辑页只改名称直接保存（S10）', () {
    testWidgets('TEST-02-S3: 只改名称 → 直接 update 不验证 → pop 回列表', (tester) async {
      final dao = _GateableDao()..seed(_seedConfig());
      final storage = FakeSecureStorage()..setPassword(1, 'stored-pass');
      final client = _RecordingWebDavClient()
        ..returnResult(WebDavValidationResult.success());

      final container = ProviderContainer(
        overrides: _overrides(dao: dao, storage: storage, client: client),
      );
      addTearDown(container.dispose);

      // Pre-warm the list provider exactly like production so the edit
      // screen's first frame sees AsyncData and the postFrame capture
      // succeeds.
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

      // Given: 原始连接 name='Home NAS'（URL 未改）。When: 修改名称。
      await tester.enterText(
          find.widgetWithText(TextFormField, '显示名称（选填）'), 'My NAS');
      await tester.pump();

      // Then: 直接保存 — 不触发任何验证请求。
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();

      expect(client.validateCallCount, equals(0),
          reason: 'TEST-02-S3: 只改名称不得触发 validateConnection（跳过验证）');
      expect(dao.rows.single.name, equals('My NAS'),
          reason: 'TEST-02-S3: 直接调用 connectionService.update() 应落库');
      expect(dao.rows.single.url, equals('http://192.168.1.100:5005'),
          reason: '未修改的字段必须保持原值');
      expect(find.byType(ConnectionEditScreen), findsNothing,
          reason: 'TEST-02-S3: 保存成功后应 pop 回连接列表');
    });
  });

  group('TEST-02-S4: 改 URL 未验证点保存（S12 门控）', () {
    testWidgets('TEST-02-S4: 未验证 → 弹 SnackBar 且 update 未调', (tester) async {
      final dao = _GateableDao()..seed(_seedConfig());
      final storage = FakeSecureStorage()..setPassword(1, 'stored-pass');
      final client = _RecordingWebDavClient()
        ..returnResult(WebDavValidationResult.success());

      final container = ProviderContainer(
        overrides: _overrides(dao: dao, storage: storage, client: client),
      );
      addTearDown(container.dispose);

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

      // When: 修改 URL 为 'http://new-nas.local:5005'，不点"验证连接"，
      // 直接点"保存"。
      await tester.enterText(
          find.widgetWithText(TextFormField, 'http://192.168.1.100:5005'),
          'http://new-nas.local:5005');
      await tester.pump();
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();

      // Then: 弹 SnackBar 提示先验证（生产实际文案：'请先测试连接后再保存'；
      // spec §3.2 写的 '请先验证连接' 与生产不一致 — 以代码为准）。
      expect(find.text('请先测试连接后再保存'), findsOneWidget,
          reason: 'TEST-02-S4: 未验证就点保存必须弹提示（S12 门控，生产文案）');
      // And: 不调用 connectionService.update()。
      expect(dao.rows.single.url, equals('http://192.168.1.100:5005'),
          reason: 'TEST-02-S4: 未验证不得调用 update（URL 不得落库）');
      expect(dao.rows.single.name, equals('Home NAS'));
      expect(find.byType(ConnectionEditScreen), findsOneWidget,
          reason: '未验证保存失败时编辑页不应被 pop');
    });
  });

  group('TEST-02-S5: 首帧列表未解析时的捕获兜底（INV7）', () {
    testWidgets('TEST-02-S5: 首帧未解析不崩溃 → 数据到达后保存成功', (tester) async {
      final dao = _GateableDao()
        ..seed(_seedConfig())
        ..findAllGate = Completer<void>();
      final storage = FakeSecureStorage()..setPassword(1, 'stored-pass');
      final client = _RecordingWebDavClient()
        ..returnResult(WebDavValidationResult.success());

      final container = ProviderContainer(
        overrides: _overrides(dao: dao, storage: storage, client: client),
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(_buildApp(
        container: container,
        extraRoutes: [
          GoRoute(
              path: '/edit',
              builder: (_, __) => const ConnectionEditScreen(connectionId: 1)),
        ],
      ));
      await tester.pumpAndSettle();

      // 首帧 connectionListProvider 未解析（findAll 挂起）→ 渲染不崩溃。
      // NOTE: gate 打开期间不能用 pumpAndSettle（loading spinner 永不 settle）。
      await tester.tap(find.text('进入页面'));
      await tester.pump(); // start the route push
      await tester.pump(); // build the edit page (capture attempt happens here)
      expect(find.byType(CircularProgressIndicator), findsOneWidget,
          reason: 'TEST-02-S5: 首帧未解析时应处于加载态而非崩溃');

      // 数据到达 → 表单渲染。
      dao.findAllGate!.complete();
      await tester.pumpAndSettle();
      expect(find.byType(ConnectionEditScreen), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing,
          reason: '数据到达后加载态应结束');

      // 修改名称后保存（捕获失败 → 生产兜底：需先过验证门，再按 id 现查）。
      await tester.enterText(
          find.widgetWithText(TextFormField, '显示名称（选填）'), 'Renamed NAS');
      await tester.tap(find.text('测试连接'));
      await tester.pumpAndSettle();
      expect(find.text('连接成功！'), findsOneWidget);

      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();

      // 否定断言：不得落入"无法获取连接信息"降级路径，不得崩溃。
      expect(find.text('无法获取连接信息，请重试'), findsNothing,
          reason: 'TEST-02-S5: 捕获失败时保存必须经现查兜底命中');
      expect(dao.rows.single.name, equals('Renamed NAS'),
          reason: 'TEST-02-S5: 首帧未解析时保存仍须成功落库');
      expect(dao.rows.single.url, equals('http://192.168.1.100:5005'),
          reason: '未修改的字段必须保持原值');
      expect(find.byType(ConnectionEditScreen), findsNothing,
          reason: 'TEST-02-S5: 保存成功后应 pop');
    });
  });
}
