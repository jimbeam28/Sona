// test/features/connection/bug_bug11_repro_test.dart
// BUG-11: 全 UI 无"添加第二个连接"入口
// （spec: docs/features/BUG-11.md §5.4，来源 cr-20260816-0804 B1）
//
// 缺陷：connection_list_screen.dart:24-63 的 AppBar 无 actions、列表项仅有
// 编辑/删除/切换（:259-291 PopupMenu 只有 edit/delete），/connection 路由
// （router.dart:27-31）全 lib 仅 onboarding.dart:42/53/106 可达——而
// onboarding 仅在 connections.isEmpty 时显示 CTA（onboarding.dart:29-30）。
// 设置页 settings_screen.dart:51 副标题承诺"添加、编辑或切换连接"，但进入
// 列表页后无任何"添加"入口；_EmptyState（:333-361）文案"添加一个 WebDAV
// 连接即可开始"也无按钮。
//
// 门禁（修复前必须 FAIL）：
//   BUG-11-S1: 已有 ≥1 个连接时渲染 ConnectionListScreen，AppBar 必须出现
//              tooltip='添加连接' 的添加入口 —— 当前代码 FAIL（无此按钮）

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nas_audio_player/core/database/dao/connection_dao.dart';
import 'package:nas_audio_player/features/connection/connection_list_screen.dart';
import 'package:nas_audio_player/features/connection/connection_provider.dart';
import 'package:nas_audio_player/shared/models/connection_config.dart';

import '../../helpers/fake_secure_storage.dart';
import '../../helpers/fake_webdav_client.dart';

/// 纯 async 内存 DAO（同 test_02_con11 的 gateable fake，widget 测试
/// FakeAsync zone 不阻塞真实 sqflite-ffi isolate 事件）。
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

ConnectionConfig _conn(int id, String name) => ConnectionConfig(
      id: id,
      name: name,
      url: 'http://nas$id.local:5005',
      username: 'admin',
      basePath: '/dav',
      isActive: id == 1,
      createdAt: DateTime(2026, 7, 24),
      updatedAt: DateTime(2026, 7, 24),
    );

void main() {
  testWidgets('BUG-11-S1: 已有连接时连接管理页必须提供"添加连接"入口（当前缺失）', (tester) async {
    // Given: 已有 ≥1 个保存的连接（多连接是受支持状态——
    // deleteConnectionProvider / setActive 唯一约束证明）。
    final dao = _InMemoryDao()
      ..seed(_conn(1, 'NAS-1'))
      ..seed(_conn(2, 'NAS-2'));
    final storage = FakeSecureStorage()
      ..setPassword(1, 'pw1')
      ..setPassword(2, 'pw2');
    final client = MockWebDavClient();

    final container = ProviderContainer(
      overrides: [
        connectionDaoProvider.overrideWithValue(dao),
        secureStorageProvider.overrideWithValue(storage),
        webDavClientProvider.overrideWithValue(client),
        // 保持 hermetic：无背景 PROPFIND。
        startupValidationProvider.overrideWith((ref) async => null),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: Scaffold(body: ConnectionListScreen()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 前置：列表渲染出连接（页面确实进入了"有数据"分支）。
    expect(find.text('NAS-1'), findsOneWidget);
    expect(find.text('NAS-2'), findsOneWidget);

    // Then: 必须存在 tooltip='添加连接' 的 AppBar 入口（点击跳 /connection）。
    expect(find.byTooltip('添加连接'), findsOneWidget,
        reason: 'BUG-11（cr-20260816-0804 B1）：连接管理页无"添加连接"入口，'
            'AppBar（connection_list_screen.dart:25-28）无 actions、列表项'
            'PopupMenu（:259-291）仅有编辑/删除 —— 已有 ≥1 个连接时'
            '/connection 路由不可达（onboarding 空表 CTA 是唯一入口），'
            '设置页副标题"添加、编辑或切换连接"（settings_screen.dart:51）'
            '成为空头承诺。');
  });

  testWidgets('BUG-11-S2: 空态 _EmptyState 也必须提供"添加"入口（当前缺失）', (tester) async {
    final dao = _InMemoryDao();
    final storage = FakeSecureStorage();
    final client = MockWebDavClient();

    final container = ProviderContainer(
      overrides: [
        connectionDaoProvider.overrideWithValue(dao),
        secureStorageProvider.overrideWithValue(storage),
        webDavClientProvider.overrideWithValue(client),
        startupValidationProvider.overrideWith((ref) async => null),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: Scaffold(body: ConnectionListScreen()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 前置：空态文案已显示（说明走的是 _EmptyState 分支）。
    expect(find.text('还没有保存的连接'), findsOneWidget);
    expect(find.text('添加一个 WebDAV 连接即可开始'), findsOneWidget);

    // Then: 空态必须提供"添加连接"按钮（文案已承诺"添加…即可开始"）。
    expect(find.text('添加连接'), findsWidgets,
        reason: 'BUG-11（cr-20260816-0804 B1）：_EmptyState'
            '（connection_list_screen.dart:333-361）文案"添加一个 WebDAV '
            '连接即可开始"却无任何添加按钮 —— 空态下进入添加页的唯一入口'
            '只在 onboarding（onboarding.dart:106），列表页空态成了死胡同。');
  });
}
