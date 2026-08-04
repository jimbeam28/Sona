// test/features/connection/bug_bug24_repro_test.dart
// BUG-24: 连接编辑健壮性（CON5 + CON6 + CON7 + CON8）— spec §5.4 门禁测试.
//
// 复核背景：3d6bc26 只落地了 CON5 的一半（_originalConfig?.copyWith + 错误
// SnackBar，缺 spec 要求的"按 id 现查兜底"），CON6（update 回滚）与 CON8
// （测试连接空密码回读 storage）完全缺失；CON7（delete best-effort）已在
// 596a63b 落地。本套件守护修复后的全部 S/INV：
//
// BUG-24-S1-T01: 首帧捕获失败（list 未解析）→ 保存按 id 现查兜底成功，
//                不崩溃、不落"无法获取连接信息"降级路径
// BUG-24-S1-T02: 捕获成功的正常路径不变 — 只改显示名直接可存（S10），
//                不触发任何验证请求
// BUG-24-S4-T01: 密码留空点测试连接 → 用 secure_storage 已存密码发验证
// BUG-24-S4-T02: 密码非空点测试连接 → 用表单密码（行为不变）
// BUG-24-S2-T01: 改密码保存时 DAO 失败 → storage 回滚旧密码 + rethrow
// BUG-24-S2-T02: 改密码正常路径 → storage 新密码 + DAO 更新
// BUG-24-S2-T03: password 为 null → 不写 storage（行为不变）
// BUG-24-S2-T04: 边界 — 旧密码读取失败 → 回滚写 null（可接受降级）
// BUG-24-S3-T01: DAO 删除成功 + storage 删除失败 → delete() 不 rethrow
// BUG-24-S3-T02: 正常删除路径不变 — DB 行与密码 key 均移除
// BUG-24-S3-T03: storage 删除失败 → 清理失败必须落日志（O7 复核：禁止静默
//                吞错，同 CON1/BUG-19/LIST6 判据），日志不含密码明文
// BUG-24-S3-T04: 清理失败日志含连接 id 与异常信息（可诊断性）
//
// 否定断言（对应 spec §3.1）：
//   - S1: _originalConfig 为 null 不抛 Null check operator error
//   - S2: DAO 失败后 storage 不保留新密码
//   - S3: storage 删除失败不向用户报"删除失败"（不 rethrow）
//   - S4: 空密码不用空串发验证请求（storage 有值时）

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:nas_audio_player/core/database/dao/connection_dao.dart';
import 'package:nas_audio_player/core/network/webdav_client.dart';
import 'package:nas_audio_player/features/connection/connection_edit_screen.dart';
import 'package:nas_audio_player/features/connection/connection_provider.dart';
import 'package:nas_audio_player/features/connection/domain/connection_service.dart';
import 'package:nas_audio_player/shared/models/connection_config.dart';

import '../../helpers/fake_secure_storage.dart';
import '../../helpers/fake_webdav_client.dart';
import '../../helpers/test_factories.dart';

// ── Test doubles ─────────────────────────────────────────────────────────────

/// In-memory [ConnectionDao] whose `findAll` can be suspended on a gate so
/// the edit screen's first frame sees an unresolved list (the exact CON5
/// capture-failure window). Extends the concrete [ConnectionDao] because
/// [ConnectionService] depends on the concrete type; all methods are
/// overridden so the real [DatabaseHelper] singleton is never touched.
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
/// which password the probe went out with (BUG-24-S4).
class _RecordingWebDavClient extends MockWebDavClient {
  final List<({String url, String username, String password})> validateCalls =
      [];

  @override
  Future<WebDavValidationResult> validate({
    required String url,
    required String username,
    required String password,
    String basePath = '/',
  }) async {
    validateCalls.add((url: url, username: username, password: password));
    return super.validate(
        url: url, username: username, password: password, basePath: basePath);
  }
}

/// In-memory [ConnectionDao] for service-level tests that records update
/// calls and can be rigged to fail.
class _RecordingDao extends ConnectionDao {
  final List<({ConnectionConfig config, String passwordKey})> updateCalls = [];
  final List<int> deleteCalls = [];
  bool failUpdate = false;
  bool deleteReturnsWasActive = true;

  @override
  Future<int> update(ConnectionConfig config,
      {required String passwordKey}) async {
    if (failUpdate) throw Exception('DB busy (SQLITE_BUSY)');
    updateCalls.add((config: config, passwordKey: passwordKey));
    return 1;
  }

  @override
  Future<bool> delete(int id) async {
    deleteCalls.add(id);
    return deleteReturnsWasActive;
  }
}

/// Captures everything written through [debugPrint] during [body].
///
/// Mirrors the capture helper in bug_bug19_repro_test.dart (BUG-19 gate).
/// Restores the original printer in `finally` (flutter_test verifies
/// foundation debug variables between tests).
Future<List<String>> captureLogs(Future<void> Function() body) async {
  final logs = <String>[];
  final originalDebugPrint = debugPrint;
  debugPrint = (message, {wrapWidth}) => logs.add(message ?? '');
  try {
    await body();
  } finally {
    debugPrint = originalDebugPrint;
  }
  return logs;
}

// ── Widget scaffolding (mirrors bug_15_repro_test.dart) ─────────────────────

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
  // BUG-24-S1: _originalConfig null-safe — 按 id 现查兜底（CON5）
  // ═══════════════════════════════════════════════════════════════════════════

  group('BUG-24-S1: _originalConfig 捕获失败的兜底', () {
    testWidgets('S1-T01: 首帧 list 未解析捕获失败 → 保存按 id 现查兜底成功，不崩溃', (tester) async {
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

      // Navigate while the list is still unresolved → the postFrame capture
      // in initState sees valueOrNull == null and gives up (CON5 window).
      // NOTE: no pumpAndSettle while the gate is open — the loading spinner
      // animates forever; pump explicit frames instead.
      await tester.tap(find.text('进入页面'));
      await tester.pump(); // start the route push
      await tester.pump(); // build the edit page (capture attempt happens here)
      expect(find.byType(CircularProgressIndicator), findsOneWidget,
          reason: 'list 未解析时编辑页应处于加载态（捕获窗口）');

      // Now the list resolves — the form renders, but _originalConfig was
      // never captured.
      dao.findAllGate!.complete();
      await tester.pumpAndSettle();
      expect(find.byType(ConnectionEditScreen), findsOneWidget);

      // Change only the display name. _needsRevalidation's safety net
      // (_originalConfig == null → true) forces a validation pass first.
      await tester.enterText(
          find.widgetWithText(TextFormField, '显示名称（选填）'), 'Renamed NAS');
      await tester.tap(find.text('测试连接'));
      await tester.pumpAndSettle();
      expect(find.text('连接成功！'), findsOneWidget);

      // Pre-fix this crashed on `_originalConfig!` (original bug) or degraded
      // to the error SnackBar without saving (3d6bc26 half-fix). Post-fix the
      // by-id lookup in the current list supplies the original config.
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();

      expect(find.text('无法获取连接信息，请重试'), findsNothing,
          reason: 'list 已解析时现查兜底必须命中，不得落入错误提示');
      expect(dao.rows.single.name, equals('Renamed NAS'),
          reason: 'S1：捕获失败时保存必须经现查兜底落库');
      expect(dao.rows.single.url, equals('http://192.168.1.100:5005'),
          reason: '未修改的字段必须保持原值');

      // Password field was empty → save must pass null (keep stored password)
      // — the BUG-24-INV4 save-side semantics, unchanged.
      final pw = await storage.read(key: 'connection_password_1');
      expect(pw, equals('stored-pass'), reason: '空密码保存不得触碰已存密码');
    });

    testWidgets('S1-T02: 捕获成功的正常路径不变 — 只改显示名直接可存（S10）', (tester) async {
      final dao = _GateableDao()..seed(_seedConfig()); // no gate → captured
      final storage = FakeSecureStorage()..setPassword(1, 'stored-pass');
      final client = _RecordingWebDavClient()
        ..returnResult(WebDavValidationResult.success());

      final container = ProviderContainer(
        overrides: _overrides(dao: dao, storage: storage, client: client),
      );
      addTearDown(container.dispose);

      // Pre-warm the list provider exactly like production (the connection
      // list screen has already resolved it) so the edit screen's first frame
      // sees AsyncData and the postFrame capture succeeds.
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

      await tester.enterText(
          find.widgetWithText(TextFormField, '显示名称（选填）'), 'Renamed NAS');

      // No credential field changed → no re-validation needed → save enabled
      // immediately (S10); save must go through without any probe.
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();

      expect(client.validateCalls, isEmpty, reason: '只改显示名不得触发任何验证请求（S10）');
      expect(dao.rows.single.name, equals('Renamed NAS'));
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // BUG-24-S4: 测试连接空密码 → 回读 secure_storage（CON8）
  // ═══════════════════════════════════════════════════════════════════════════

  group('BUG-24-S4: 测试连接与保存的密码语义一致', () {
    testWidgets('S4-T01: 密码留空点测试连接 → 用已存密码发验证请求', (tester) async {
      final dao = _GateableDao()..seed(_seedConfig());
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
      await tester.tap(find.text('进入页面'));
      await tester.pumpAndSettle();

      // Leave the password field empty ("留空保持不变") and test.
      await tester.tap(find.text('测试连接'));
      await tester.pumpAndSettle();

      expect(client.validateCalls, hasLength(1));
      expect(client.validateCalls.single.password, equals('stored-pass'),
          reason: 'S4：空密码必须回读 storage，不得用空串发验证请求');
      expect(find.text('连接成功！'), findsOneWidget);
    });

    testWidgets('S4-T02: 密码非空点测试连接 → 用表单密码（行为不变）', (tester) async {
      final dao = _GateableDao()..seed(_seedConfig());
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
      await tester.tap(find.text('进入页面'));
      await tester.pumpAndSettle();

      await tester.enterText(
          find.widgetWithText(TextFormField, '密码（留空保持不变）'), 'new-pass');
      await tester.tap(find.text('测试连接'));
      await tester.pumpAndSettle();

      expect(client.validateCalls, hasLength(1));
      expect(client.validateCalls.single.password, equals('new-pass'),
          reason: '密码字段非空时必须用表单密码（不回读 storage）');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // BUG-24-S2: update() 原子性回滚（CON6）— 服务级
  // ═══════════════════════════════════════════════════════════════════════════

  group('BUG-24-S2: update() 对齐 save() 原子性', () {
    test('S2-T01: storage 写成功后 DAO 失败 → 回滚旧密码 + rethrow', () async {
      final dao = _RecordingDao()..failUpdate = true;
      final storage = FakeSecureStorage()..setPassword(7, 'old-pw');
      final service = ConnectionService(dao, storage);

      await expectLater(
        service.update(config: testConfig(id: 7), password: 'new-pw'),
        throwsA(isA<Exception>()),
        reason: 'DAO 失败必须向上抛出（UI 报保存失败）',
      );

      // 否定断言：DAO 失败后 storage 不得保留新密码。
      final pw = await storage.read(key: 'connection_password_7');
      expect(pw, equals('old-pw'), reason: 'S2：必须回滚到旧密码，状态一致');
    });

    test('S2-T02: 改密码正常路径 → storage 新密码 + DAO 更新', () async {
      final dao = _RecordingDao();
      final storage = FakeSecureStorage()..setPassword(7, 'old-pw');
      final service = ConnectionService(dao, storage);

      final config = testConfig(id: 7, name: 'Renamed');
      await service.update(config: config, password: 'new-pw');

      expect(await storage.read(key: 'connection_password_7'), equals('new-pw'),
          reason: '正常路径新密码必须落 storage');
      expect(dao.updateCalls, hasLength(1));
      expect(
          dao.updateCalls.single.passwordKey, equals('connection_password_7'));
      expect(dao.updateCalls.single.config.name, equals('Renamed'));
    });

    test('S2-T03: password 为 null → 不写 storage（行为不变）', () async {
      final dao = _RecordingDao();
      final storage = FakeSecureStorage()..setPassword(7, 'old-pw');
      final service = ConnectionService(dao, storage);

      await service.update(config: testConfig(id: 7), password: null);

      expect(await storage.read(key: 'connection_password_7'), equals('old-pw'),
          reason: '否定断言：password 为 null 时不得触碰 storage');
      expect(dao.updateCalls, hasLength(1), reason: 'DAO 更新照常进行');
    });

    test('S2-T04: 边界 — 旧密码读取失败 → 回滚写 null（可接受降级）', () async {
      final dao = _RecordingDao()..failUpdate = true;
      // read throws → safeStorageRead degrades to null → rollback clears key.
      final storage = ReadThrowingFakeSecureStorage()..setPassword(7, 'old-pw');
      final service = ConnectionService(dao, storage);

      await expectLater(
        service.update(config: testConfig(id: 7), password: 'new-pw'),
        throwsA(isA<Exception>()),
      );

      // spec 边界裁决：旧密码读取失败 → 回滚写 null → 密码丢失可接受
      // （DAO 也失败了，用户需重试）。
      expect(storage.peek('connection_password_7'), isNull,
          reason: '读取失败时回滚写 null，不得遗留半新半旧状态');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // BUG-24-S3: delete() storage 清理 best-effort（CON7）— 服务级
  // ═══════════════════════════════════════════════════════════════════════════

  group('BUG-24-S3: delete() storage 清理降级 best-effort', () {
    test('S3-T01: DAO 成功 + storage 删除失败 → delete() 完成不 rethrow', () async {
      final dao = _RecordingDao()..deleteReturnsWasActive = true;
      final storage = DeleteThrowingFakeSecureStorage()..setPassword(3, 'pw');
      final service = ConnectionService(dao, storage);

      // 否定断言：storage 删除失败不得 rethrow（UI 不得报"删除失败"）。
      final wasActive = await service.delete(3);

      expect(wasActive, isTrue);
      expect(dao.deleteCalls, equals([3]), reason: 'DB 删除照常完成');
      // 孤儿 key 残留为 spec 明确接受（id AUTOINCREMENT 不复用）。
      expect(await storage.read(key: 'connection_password_3'), equals('pw'));
    });

    test('S3-T02: 正常路径不变 — DB 行与密码 key 均移除', () async {
      final dao = _RecordingDao()..deleteReturnsWasActive = false;
      final storage = FakeSecureStorage()..setPassword(5, 'pw');
      final service = ConnectionService(dao, storage);

      final wasActive = await service.delete(5);

      expect(wasActive, isFalse);
      expect(dao.deleteCalls, equals([5]));
      expect(await storage.read(key: 'connection_password_5'), isNull,
          reason: '正常路径密码 key 必须被清理');
    });

    // ── O7 复核（cr-20260804-1922 §5）：catch-log 判据 ─────────────────────
    // 禁止静默吞错：密码清理失败必须落日志（同 CON1 复核修正 d0f43c4 /
    // BUG-19 复核修正 0607ee3 / LIST6 判据「catch 可接受的前提是有日志」）。
    // 行为不变：delete() 仍不 rethrow（BUG-24-S3 既有裁决，见 S3-T01）。

    test(
        'S3-T03: storage 删除失败 → 清理失败落日志且 delete() 仍成功；'
        '日志不含密码明文', () async {
      final dao = _RecordingDao()..deleteReturnsWasActive = true;
      const secret = 'sup3r-s3cret-p@ssw0rd';
      final storage = DeleteThrowingFakeSecureStorage()..setPassword(9, secret);
      final service = ConnectionService(dao, storage);

      var wasActive = false;
      final logs = await captureLogs(() async {
        wasActive = await service.delete(9);
      });

      // 行为不变：删连接主流程不因密码清理失败而失败（既有裁决）。
      expect(wasActive, isTrue);
      expect(dao.deleteCalls, equals([9]));

      // catch-log 判据：catch 必须留下能定位到连接的日志。
      expect(
        logs.where((l) => l.contains('id=9')),
        isNotEmpty,
        reason: 'storage 清理失败必须落日志，禁止静默吞错'
            '（同 CON1/BUG-19/LIST6 判据）',
      );

      // 否定断言：日志不得泄漏密码明文。
      for (final log in logs) {
        expect(log.contains(secret), isFalse, reason: '日志不得包含密码明文');
      }
    });

    test('S3-T04: 清理失败日志同时含连接 id 与异常信息（可诊断性）', () async {
      final dao = _RecordingDao()..deleteReturnsWasActive = false;
      final storage = DeleteThrowingFakeSecureStorage();
      final service = ConnectionService(dao, storage);

      final logs = await captureLogs(() async {
        await service.delete(4);
      });

      expect(
        logs.where((l) =>
            l.contains('id=4') &&
            l.contains('Simulated secure storage delete failure')),
        isNotEmpty,
        reason: '日志须同时定位连接（id）与携带异常信息，否则无法诊断',
      );
    });
  });
}
