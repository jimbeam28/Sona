// test/features/connection/test_02_con13_test.dart
// TEST-02-S6/S7 (CON13): 真函数调用 + 空壳测试改写
//
// S6 — ConnectionScreen 输入含 userInfo 的 URL → 点测试 → 真 validateUrl
//      拒绝（错误文案可见），webDavClient.validate 不被调用。
// S7 — con_01_test.dart:62-95,125-135,636-744 的本地重定义/字面量/自证
//      空壳，在此文件用真函数 + 真实 widget 树补等价覆盖：
//        * CON-T01/T02/T03/T07 → 真 validateUrl / validateRequired /
//          validateBasePath（connection_validator.dart，非本地副本）
//        * TST-T124/125（SlidableAction 字面量）→ ConnectionListScreen 真实
//          widget 树中的 SlidableAction（icon/label 断言）
//        * TST-T145（字面量列表）→ 真实列表渲染两条连接
//        * TST-T146（const 赋值自证）→ 编辑页真实预填原始配置
//        * TST-T147（本地状态机自证）→ 真实 URL 变更重置验证门：未验证保存
//          被拦截（SnackBar + update 未调），重新验证后保存成功
//
// 注：不改 con_01_test.dart 既有内容（空壳删除与否交主会话裁决）。

import 'package:flutter/material.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:nas_audio_player/core/database/dao/connection_dao.dart';
import 'package:nas_audio_player/core/network/webdav_client.dart';
import 'package:nas_audio_player/features/connection/connection_edit_screen.dart';
import 'package:nas_audio_player/features/connection/connection_list_screen.dart';
import 'package:nas_audio_player/features/connection/connection_provider.dart';
import 'package:nas_audio_player/features/connection/connection_screen.dart';
import 'package:nas_audio_player/features/connection/domain/connection_validator.dart';
import 'package:nas_audio_player/shared/models/connection_config.dart';

import '../../helpers/fake_secure_storage.dart';
import '../../helpers/fake_webdav_client.dart';
import '../../helpers/test_factories.dart';

// ── Test doubles ─────────────────────────────────────────────────────────────

/// [MockWebDavClient] that records every `validate` call so tests can assert
/// the validation gate blocked the request entirely.
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

/// In-memory [ConnectionDao] for widget tests. All methods are overridden with
/// pure-async bodies so the widget test's FakeAsync zone never blocks on real
/// sqflite-ffi isolate events.
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

/// Minimal ConnectionScreen wrapper（镜像 con_01 buildTestApp）。
Widget _buildConnectionScreenApp(
  MockWebDavClient client, {
  List<Override> overrides = const [],
}) {
  return ProviderScope(
    overrides: [
      webDavClientProvider.overrideWithValue(client),
      startupValidationProvider.overrideWith((ref) async => null),
      ...overrides,
    ],
    child: const MaterialApp(home: ConnectionScreen()),
  );
}

Widget _buildEditApp({
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

List<Override> _editOverrides({
  required ConnectionDao dao,
  required FakeSecureStorage storage,
  required MockWebDavClient client,
}) =>
    [
      connectionDaoProvider.overrideWithValue(dao),
      secureStorageProvider.overrideWithValue(storage),
      webDavClientProvider.overrideWithValue(client),
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
  // ═══════════════════════════════════════════════════════════════════════════
  // TEST-02-S6: ConnectionScreen 输入 userInfo URL → 校验拦截（CON2）
  // ═══════════════════════════════════════════════════════════════════════════

  group('TEST-02-S6: userInfo URL 被校验拦截，validate 未调', () {
    testWidgets('TEST-02-S6: URL 含用户名密码 → 错误文案 + 不发验证请求', (tester) async {
      final client = _RecordingWebDavClient()
        ..returnResult(WebDavValidationResult.success());

      await tester.pumpWidget(_buildConnectionScreenApp(client));
      await tester.pumpAndSettle();

      // Given: 填好用户名/密码（避免必填错误干扰断言），URL 含 userInfo。
      await tester.enterText(find.widgetWithText(TextFormField, '服务器地址 *'),
          'http://admin:pass@nas.local');
      await tester.enterText(
          find.widgetWithText(TextFormField, '用户名 *'), 'admin');
      await tester.enterText(
          find.widgetWithText(TextFormField, '密码 *'), 'secret');

      // When: 点击"测试连接"。
      await tester.tap(find.text('测试连接'));
      await tester.pumpAndSettle();

      // Then: 真 validateUrl 拒绝 → 展示 userInfo 专属错误文案
      // （生产实际文案经 widget 树实证；spec 写的 'URL 不应包含用户名密码'
      // 与生产不一致 — 以代码为准；bug_14 锚定不含凭证回显）。
      expect(
          find.text('服务器地址不能包含账号密码（user:pass@），请在用户名和密码栏分别填写'), findsOneWidget,
          reason: 'TEST-02-S6: URL 含 userInfo 必须展示专属错误文案（真 validateUrl）');
      final errorTexts = tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data ?? '')
          .toList();
      expect(errorTexts.any((s) => s.contains('admin:pass')), isFalse,
          reason: 'TEST-02-S6: 错误文案不得回显 URL 内嵌的凭证');
      // 否定断言：校验失败 → 不调用 webDavClient.validateConnection()。
      expect(client.validateCallCount, equals(0),
          reason: 'TEST-02-S6: URL 含 userInfo 时不得发验证请求'
              '（CON13：若表单用的是本地旧副本，此断言变红）');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // TEST-02-S7: 空壳测试改写 — 真函数（CON-T01/T02/T03/T07 等价）
  // ═══════════════════════════════════════════════════════════════════════════

  group('TEST-02-S7: 真函数调用（替代 con_01 本地重定义）', () {
    test('TEST-02-S7: 空 URL → 真 validateUrl 返回必填错误（CON-T01 等价）', () {
      expect(validateUrl(''), equals('请输入服务器地址'),
          reason: 'S7: 必须调 connection_validator.dart 的真 validateUrl，'
              '不得重定义局部副本');
      expect(validateUrl(null), equals('请输入服务器地址'));
      expect(validateUrl('http://192.168.1.1'), isNull, reason: '有效地址不应触发错误');
    });

    test('TEST-02-S7: 空用户名 → 真 validateRequired 返回必填错误（CON-T02 等价）', () {
      expect(validateRequired('', '用户名'), equals('请输入用户名'),
          reason: 'S7: 必须调真 validateRequired');
    });

    test('TEST-02-S7: 空密码 → 真 validateRequired 返回必填错误（CON-T03 等价）', () {
      expect(validateRequired('', '密码'), equals('请输入密码'),
          reason: 'S7: 必须调真 validateRequired');
    });

    test('TEST-02-S7: 空 basePath → 真 validateBasePath 默认 /（CON-T07 等价）', () {
      expect(validateBasePath('').normalised, equals('/'),
          reason: 'S7: 必须调真 validateBasePath，不得本地 resolveBasePath');
      expect(validateBasePath('   ').normalised, equals('/'));
      expect(validateBasePath('/dav').normalised, equals('/dav'));
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // TEST-02-S7: 空壳测试改写 — 真实 widget 树（TST-T124/125/145）
  // ═══════════════════════════════════════════════════════════════════════════

  group('TEST-02-S7: ConnectionListScreen 真实树（TST-T124/125/145 改写）', () {
    Widget buildListApp() {
      final conn1 = testConfig(id: 1, name: 'Home NAS', isActive: true);
      final conn2 = testConfig(id: 2, name: 'Office NAS', isActive: false);
      return ProviderScope(
        overrides: [
          connectionListProvider
              .overrideWith((ref) => Future.value([conn1, conn2])),
          activeConnectionProvider.overrideWith((ref) => Future.value(conn1)),
        ],
        child: const MaterialApp(
          home: Scaffold(body: ConnectionListScreen()),
        ),
      );
    }

    testWidgets(
        'TEST-02-S7: 真实树中编辑/删除 SlidableAction 属性正确'
        '（TST-T124/125 改写）', (tester) async {
      await tester.pumpWidget(buildListApp());
      await tester.pumpAndSettle();

      // Slidable 的 action pane 是懒构建的：滑动行才出现 SlidableAction。
      await tester.drag(find.text('Home NAS'), const Offset(-300, 0));
      await tester.pumpAndSettle();

      final actions = tester
          .widgetList<SlidableAction>(find.byType(SlidableAction))
          .toList();
      expect(actions, isNotEmpty,
          reason: 'S7: 连接列表真实树必须渲染 SlidableAction（不再构造字面量）');

      final editAction = actions.firstWhere((a) => a.label == '编辑');
      expect(editAction.icon, equals(Icons.edit_outlined),
          reason: 'S7/TST-T124: 真实编辑按钮图标应为 edit_outlined');
      final deleteAction = actions.firstWhere((a) => a.label == '删除');
      expect(deleteAction.icon, equals(Icons.delete_outline),
          reason: 'S7/TST-T125: 真实删除按钮图标应为 delete_outline');
    });

    testWidgets('TEST-02-S7: 有连接时列表真实渲染两条连接（TST-T145 改写）', (tester) async {
      await tester.pumpWidget(buildListApp());
      await tester.pumpAndSettle();

      expect(find.text('Home NAS'), findsOneWidget,
          reason: 'S7/TST-T145: 真实列表应渲染连接 1');
      expect(find.text('Office NAS'), findsOneWidget,
          reason: 'S7/TST-T145: 真实列表应渲染连接 2');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // TEST-02-S7: 空壳测试改写 — 编辑页真实行为（TST-T146/147 改写）
  // ═══════════════════════════════════════════════════════════════════════════

  group('TEST-02-S7: ConnectionEditScreen 真实行为（TST-T146/147 改写）', () {
    testWidgets('TEST-02-S7: 编辑页真实预填原始配置（TST-T146 改写）', (tester) async {
      final dao = _InMemoryDao()..seed(_seedConfig());
      final storage = FakeSecureStorage()..setPassword(1, 'stored-pass');
      final client = MockWebDavClient()
        ..returnResult(WebDavValidationResult.success());

      final container = ProviderContainer(
        overrides: _editOverrides(dao: dao, storage: storage, client: client),
      );
      addTearDown(container.dispose);
      await container.read(connectionListProvider.future);

      await tester.pumpWidget(_buildEditApp(
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

      expect(find.widgetWithText(TextFormField, 'http://192.168.1.100:5005'),
          findsOneWidget,
          reason: 'S7/TST-T146: URL 字段应预填原始值');
      expect(find.widgetWithText(TextFormField, 'Home NAS'), findsOneWidget,
          reason: 'S7/TST-T146: 名称字段应预填原始值');
      expect(find.widgetWithText(TextFormField, 'admin'), findsOneWidget,
          reason: 'S7/TST-T146: 用户名字段应预填原始值');
    });

    testWidgets(
        'TEST-02-S7: URL 变更重置验证器 → 保存被门控，'
        '重新验证后正常保存（TST-T147 改写）', (tester) async {
      final dao = _InMemoryDao()..seed(_seedConfig());
      final storage = FakeSecureStorage()..setPassword(1, 'stored-pass');
      final client = _RecordingWebDavClient()
        ..returnResult(WebDavValidationResult.success());

      final container = ProviderContainer(
        overrides: _editOverrides(dao: dao, storage: storage, client: client),
      );
      addTearDown(container.dispose);
      await container.read(connectionListProvider.future);

      await tester.pumpWidget(_buildEditApp(
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

      // Given: 首次验证成功（状态 success）。
      await tester.tap(find.text('测试连接'));
      await tester.pumpAndSettle();
      expect(find.text('连接成功！'), findsOneWidget);

      // When: 修改 URL（凭证字段变更 → 验证器必须重置为 idle）。
      await tester.enterText(
          find.widgetWithText(TextFormField, 'http://192.168.1.100:5005'),
          'http://10.0.0.1:8080');
      await tester.pump();

      // Then: 验证器已重置（成功横幅消失），保存按钮被 S12 门控禁用。
      expect(find.text('连接成功！'), findsNothing,
          reason: 'S7/TST-T147: URL 变更后验证器必须重置（成功态清空）');
      final saveBtn =
          tester.widget<FilledButton>(find.widgetWithText(FilledButton, '保存'));
      expect(saveBtn.onPressed, isNull,
          reason: 'S7/TST-T147: 已验证过又改凭证 → 保存按钮必须禁用'
              '（生产行为：已验证→再变更走禁用门；未验证→变更走 SnackBar 门，'
              '见 TEST-02-S4。两者都拦截 update）');

      // 否定断言：未重新验证时 update 不得被调用（URL 不得落库）。
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(dao.rows.single.url, equals('http://192.168.1.100:5005'),
          reason: 'S7/TST-T147: 被拦截时 update 不得被调用（URL 不得落库）');

      // 否定断言：重新验证通过后保存应正常（验证后行为不变）。
      await tester.tap(find.text('测试连接'));
      await tester.pumpAndSettle();
      expect(find.text('连接成功！'), findsOneWidget);
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(dao.rows.single.url, equals('http://10.0.0.1:8080'),
          reason: 'S7/TST-T147: 重新验证通过后保存必须正常落库');
    });
  });
}
