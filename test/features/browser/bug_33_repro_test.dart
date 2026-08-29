// test/features/browser/bug_33_repro_test.dart
// F1 复现门禁：扫描类操作逐层放大 secure-storage 读（cr-20260826-0027 F1，Minor）。
//
// 本测试在 dev-plan 阶段先写（Bug 硬门禁），修复前必须 FAIL：
//   生产搜索扫描（SRCH-01）经 searchSessionProvider → _startScan →
//   searchFolderSubtree(fetchDir: directoryContentsProvider) 逐层抓取目录，
//   每一层未命中缓存都会触发一次 safeStorageRead（browser_provider.dart:114-122）
//   ——整棵子树扫描 = 层数次密码读取。期望一次扫描会话至多读一次密码。
//
// 断言：一次深子树搜索扫描中 secure storage 读取次数 == 1。
// 当前：3 层子树 → 3 次读取 → FAIL。
// 修复后（扫描会话内 memoize 密码 / 走不经缓存的轻量 fetchDir）→ 1 次 → PASS。
//
// dev-exe 增补（spec §5.3 盲点补偿）：
//   - BUG-33-S2 否定面：扫描不向 directoryCacheProvider 写入任何新条目（INV1），
//     用户浏览路径缓存不被扫描挤掉。
//   - BUG-33-ALG1：同一会话多次 fetchDir→listDirectory 收到同一次解析密码（INV2）。

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nas_audio_player/core/network/webdav_client.dart';
import 'package:nas_audio_player/features/browser/browser_provider.dart';
import 'package:nas_audio_player/features/connection/connection_provider.dart';
import 'package:nas_audio_player/shared/models/nas_file.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/fake_secure_storage.dart';
import '../../helpers/test_factories.dart';

/// 逐层目录树假 WebDAV client（仅 listDirectory 需要）。
class _TreeDavClient implements WebDavClientInterface {
  final Map<String, List<NasFile>> listings = {};

  /// 每次 listDirectory 收到的 password 实参（ALG1 断言同会话密码一致）。
  final List<String> passwords = [];

  void put(String path, List<NasFile> entries) => listings[path] = entries;

  @override
  Future<List<NasFile>> listDirectory({
    required String url,
    required String username,
    required String password,
    required String path,
  }) async {
    passwords.add(password);
    return listings[path] ?? const <NasFile>[];
  }

  @override
  Future<WebDavValidationResult> validate({
    required String url,
    required String username,
    required String password,
    String basePath = '/',
  }) =>
      throw UnimplementedError('not needed');

  @override
  Future<void> downloadFile({
    required String url,
    required String filePath,
    required String username,
    required String password,
    required String saveTo,
    void Function(int received, int? total)? onProgress,
  }) =>
      throw UnimplementedError('not needed');
}

Future<void> _waitUntil(
  Future<bool> Function() cond, {
  int maxMs = 5000,
  String? reason,
}) async {
  var waited = 0;
  while (!await cond() && waited < maxMs) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
    waited += 10;
  }
  expect(await cond(), isTrue, reason: reason ?? '轮询等待超时（${maxMs}ms）');
}

/// 三层全未命中缓存的扫描会话夹具：容器 + 密码存储 + 假 WebDAV client。
/// tearDown 注册 container.dispose / sub.close（与复现测试同序）。
Future<(ProviderContainer, HangingFakeSecureStorage, _TreeDavClient)>
    _setupScanHarness(ConnectionConfig conn) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();

  final storage = HangingFakeSecureStorage()..setPassword(1, 'pw');
  final client = _TreeDavClient()
    ..put('/', [testDir('a', '/a')])
    ..put('/a', [testDir('b', '/a/b')])
    ..put('/a/b', [testAudio('hit.mp3', '/a/b/hit.mp3')]);

  final container = ProviderContainer(overrides: [
    activeConnectionProvider.overrideWith((ref) async => conn),
    secureStorageProvider.overrideWithValue(storage),
    webDavClientProvider.overrideWithValue(client),
    sharedPreferencesProvider.overrideWithValue(prefs),
  ]);
  // AutoDispose notifier 需监听保持存活，否则扫描途中被回收。
  final sub = container.listen(searchSessionProvider, (_, __) {});
  addTearDown(container.dispose);
  addTearDown(sub.close);
  return (container, storage, client);
}

/// 驱动搜索扫描到完整结束（命中落位且 running 置 false）。
Future<void> _runScanToDone(ProviderContainer container) async {
  final notifier = container.read(searchSessionProvider.notifier);
  notifier.openPanel();
  notifier.onQueryChanged('hit');
  // debounce 500ms 后 _startScan 启动扫描；fake 全同步完成，running 翻转窗口
  // 极短，改用「扫描完整结束」判定：hits 落位且 running 置 false。
  await _waitUntil(
    () async {
      final s = container.read(searchSessionProvider);
      return !s.running && s.hits.isNotEmpty;
    },
    reason: '搜索扫描应完整结束（命中落位且 running 置 false）',
  );
}

void main() {
  final now = DateTime(2026, 8, 26);
  final conn = ConnectionConfig(
    id: 1,
    name: 'NAS',
    url: 'http://nas.example.com',
    username: 'admin',
    basePath: '/',
    isActive: true,
    createdAt: now,
    updatedAt: now,
  );

  test('F1: 一次深子树搜索扫描只允许一次 secure storage 密码读取', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    final storage = HangingFakeSecureStorage()..setPassword(1, 'pw');
    final client = _TreeDavClient()
      ..put('/', [testDir('a', '/a')])
      ..put('/a', [testDir('b', '/a/b')])
      ..put('/a/b', [testAudio('hit.mp3', '/a/b/hit.mp3')]);

    final container = ProviderContainer(overrides: [
      activeConnectionProvider.overrideWith((ref) async => conn),
      secureStorageProvider.overrideWithValue(storage),
      webDavClientProvider.overrideWithValue(client),
      sharedPreferencesProvider.overrideWithValue(prefs),
    ]);
    addTearDown(container.dispose);
    // AutoDispose notifier 需监听保持存活，否则扫描途中被回收。
    final sub = container.listen(searchSessionProvider, (_, __) {});
    addTearDown(sub.close);

    final notifier = container.read(searchSessionProvider.notifier);
    notifier.openPanel();
    notifier.onQueryChanged('hit');
    // debounce 500ms 后 _startScan 启动扫描；fake 全同步完成，running 翻转窗口
    // 极短，改用「扫描确有进展」判定：dirsScanned 增长或命中落位即算完成。
    await _waitUntil(
      () async {
        final s = container.read(searchSessionProvider);
        return s.dirsScanned > 0 || s.hits.isNotEmpty;
      },
      reason: '搜索扫描应完成（ScanProgress/ScanDone 落位）',
    );

    expect(storage.readCalls, 1, reason: '整棵子树扫描（3 层未命中缓存）只允许一次密码读取');
  });

  test('BUG-33-S2: 扫描不向 directoryCacheProvider 写入新条目（用户浏览路径缓存不被挤掉）', () async {
    final (container, _, _) = await _setupScanHarness(conn);

    // 扫描前取快照：常规浏览写下的缓存条目基线（本用例空容器 → 0 条）。
    final cacheBefore = container.read(directoryCacheProvider).length;

    await _runScanToDone(container);
    expect(container.read(searchSessionProvider).hits, hasLength(1),
        reason: '前置：扫描确实完整结束并产生命中');

    final cacheAfter = container.read(directoryCacheProvider).length;
    expect(cacheAfter, cacheBefore,
        reason:
            'S2 否定断言：扫描不向 directoryCacheProvider 写入任何新条目（INV1）——用户浏览路径缓存不被挤掉');
  });

  test('BUG-33-ALG1: 同一会话多次 fetchDir→listDirectory 收到同一次解析密码（readCalls==1）',
      () async {
    final (container, storage, client) = await _setupScanHarness(conn);

    await _runScanToDone(container);
    expect(container.read(searchSessionProvider).hits, hasLength(1),
        reason: '前置：扫描确实完整结束并产生命中');

    expect(client.passwords.length, greaterThanOrEqualTo(2),
        reason: '前置：扫描跨多层目录调用 listDirectory（≥2 次）');
    expect(client.passwords.toSet(), {'pw'},
        reason: 'ALG1：同一会话内所有 listDirectory 收到同一次解析的密码（密码一致复用）');
    expect(storage.readCalls, 1, reason: 'ALG1：整会话密码读取恰一次，不随层数增长（INV2）');
  });
}
