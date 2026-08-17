// test/features/connection/bug_bug16_repro_test.dart
// BUG-16: 切换连接时 widget 层 invalidate 无 mounted 守卫 + catch 无日志
// （spec: docs/features/BUG-16.md §5.4，来源 cr-20260816-0804 F3）
//
// 缺陷：connection_list_screen.dart:76-101 _switchConnection：
//   await ref.read(switchActiveConnectionProvider(id).future);
//   ref.invalidate(directoryCacheProvider);      // :79
//   ref.invalidate(navigationStackProvider);     // :80  ← 在 :82 mounted 检查之前
//   if (context.mounted) { ... SnackBar ... }
//   } catch (e) {
//     if (context.mounted) { ... SnackBar ... }  // :92-101 unmounted 无日志
//   }
// 用户在 setActive 事务期间 pop 列表页 → 完成后 widget 级 invalidate 在
// defunct 元素上抛 StateError（connection_provider.dart:250-256 CON1 注释
// 记录同类风险）→ 被 catch 吞掉（unmounted 无 UI 无日志）→ directoryCache
// 与 navigationStack 保留旧连接状态 → 新活动连接下首次浏览按旧路径
// PROPFIND → 404（CON3/BUG-16 同类）。
//
// 门禁（修复前必须 FAIL）：
//   BUG-16-S1: 切换 in-flight 期间用户退出列表页 → 完成后浏览器状态必须
//              仍被复位（cache 清空、导航栈回根）—— 当前代码 widget 层
//              invalidate 随页面销毁丢失 → 状态残留 → FAIL

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nas_audio_player/core/database/dao/connection_dao.dart';
import 'package:nas_audio_player/features/browser/browser_provider.dart';
import 'package:nas_audio_player/features/connection/connection_list_screen.dart';
import 'package:nas_audio_player/features/connection/connection_provider.dart';
import 'package:nas_audio_player/shared/di/providers.dart';
import 'package:nas_audio_player/shared/models/connection_config.dart';
import 'package:nas_audio_player/shared/models/nas_file.dart';

import '../../helpers/fake_secure_storage.dart';
import '../../helpers/fake_webdav_client.dart';

/// 内存 DAO（同 test_02_con11），额外支持 setActive 门闩：
/// 挂起切换事务，模拟"切换 in-flight 期间用户退出页面"。
class _GatedInMemoryDao extends ConnectionDao {
  final List<ConnectionConfig> rows = [];
  int _nextId = 0;
  Completer<void>? setActiveGate;

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
    final gate = setActiveGate;
    if (gate != null) await gate.future;
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

CacheEntry<List<NasFile>> _cacheEntry(NasFile file) =>
    CacheEntry<List<NasFile>>(
      value: [file],
      createdAt: DateTime.now(),
    );

void main() {
  testWidgets('BUG-16-S1: 切换 in-flight 期间退出列表页 → 浏览器状态仍须复位（当前残留）',
      (tester) async {
    final dao = _GatedInMemoryDao()
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
        startupValidationProvider.overrideWith((ref) async => null),
      ],
    );
    addTearDown(container.dispose);

    // Given: 浏览器已缓存旧连接的目录（新旧连接的条目都在）、导航栈深度 3。
    const testFile =
        NasFile(name: 'song.mp3', path: '/music/song.mp3', isDirectory: false);
    container.read(directoryCacheProvider.notifier).state = {
      '1:/music': _cacheEntry(testFile),
      '2:/books': _cacheEntry(testFile),
    };
    container.read(navigationStackProvider.notifier).push('/music');
    container.read(navigationStackProvider.notifier).push('/books');
    expect(container.read(navigationStackProvider),
        equals(['/', '/music', '/books']));

    // When: 用户点 NAS-2 切换（setActive 挂起）→ 立刻退出列表页。
    final gate = Completer<void>();
    dao.setActiveGate = gate;

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: Scaffold(body: ConnectionListScreen()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('NAS-2'));
    await tester.pump(); // 切换 in-flight

    // 退出页面（模拟用户 pop 返回）。
    await tester
        .pumpWidget(const MaterialApp(home: Scaffold(body: SizedBox())));

    // 切换事务此刻才完成。
    gate.complete();
    await tester.pumpAndSettle();

    // Then: 即使页面已销毁，浏览器状态也必须被复位（cache 清空、
    // 导航栈回根）—— 不得保留旧连接深层路径。
    expect(container.read(directoryCacheProvider), isEmpty,
        reason: 'BUG-16（cr-20260816-0804 F3）：_switchConnection 的 widget 级'
            'invalidate（connection_list_screen.dart:79-80）在 :82 mounted 检查'
            '之前 —— 页面销毁后 invalidate 在 defunct 元素上抛 StateError，'
            '被 :92-101 catch 吞掉（unmounted 无日志），directoryCache 残留'
            '旧连接数据（5 分钟 TTL 内会展示旧服务器旧路径的列表）。');
    expect(container.read(navigationStackProvider), equals(['/']),
        reason: 'BUG-16：navigationStack 残留旧连接深层路径 → 新活动连接下'
            '首次浏览按旧路径 PROPFIND 得 404（CON3/BUG-16 同类）。浏览器'
            '状态复位必须并入 provider 层（resetBrowserStateOnActiveConnection'
            'Change 钩子，connection_provider.dart:322-325），不随页面生命周期。');
  });
}
