// test/features/browser/bug_bug31_repro_test.dart
// BUG-31 门禁测试（spec: docs/features/BUG-31.md；来源 BRW5 + BRW8，
// cr-20260724-0110.md §1.2）
//
// BRW5：DirectoryListTile/AudioFileListTile 未传 ValueKey（P13），列表替换
// 时按位置复用导致动画/状态错配。修复：一律 ValueKey(file.path)（S1）。
// BRW8：TTL"当前时刻"硬编码 DateTime.now()，provider 与 domain 均不可注入
// 时钟（P16），测试被迫用真实等待。修复：directoryContentsProvider 经
// browserClockProvider 注入时钟（S2/S3）。
//
// 用例：
//   BUG-31-S1/INV1: widget 测试 — 两种 tile 的 key 均为 ValueKey(file.path)
//   BUG-31-S2:      browserClockProvider 注入时钟驱动 TTL（无真实等待）
//   BUG-31-S3:      directoryContentsProvider 经 browserClockProvider 注入
//   BUG-31-INV2:    默认行为不变 — 未注入时钟时 directoryContentsProvider
//                   正常走真实时钟
//
// 修复前 FAIL：S1 断言 key 为 null；S2/S3 无注入口无法编译（或注入无效，
// 过期判定走真实 DateTime.now() → 6min 假推进后仍命中缓存，refetch 计数不变）。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nas_audio_player/core/network/webdav_client.dart';
import 'package:nas_audio_player/features/browser/browser_provider.dart';
import 'package:nas_audio_player/features/browser/browser_screen.dart';
import 'package:nas_audio_player/features/browser/widgets/file_list_item.dart';
import 'package:nas_audio_player/features/connection/connection_provider.dart';
import 'package:nas_audio_player/shared/models/connection_config.dart';
import 'package:nas_audio_player/shared/models/nas_file.dart';

import '../../helpers/fake_secure_storage.dart';
import '../../helpers/fake_webdav_client.dart';
import '../../helpers/test_factories.dart';
import '../../helpers/widget_helpers.dart';

final _conn = ConnectionConfig(
  id: 1,
  name: 'NAS',
  url: 'http://nas.example.com',
  username: 'admin',
  isActive: true,
  createdAt: DateTime(2026, 1, 1),
  updatedAt: DateTime(2026, 1, 1),
);

void main() {
  // ── BUG-31-S1 / INV1: 列表 tile 必须携带 ValueKey(file.path) ──

  group('BUG-31-S1: 文件列表项使用 ValueKey(file.path)', () {
    testWidgets('DirectoryListTile / AudioFileListTile 的 key 为业务路径',
        (tester) async {
      await tester.pumpWidget(buildTestAppWithPlayerRoute(
        Scaffold(body: BrowserScreen()),
        overrides: [
          directoryContentsProvider('/').overrideWith((ref) async => [
                testDir('sub', '/music/sub'),
                testAudio('song.mp3', '/music/song.mp3'),
              ]),
          activeConnectionProvider.overrideWith((ref) async => _conn),
        ],
      ));
      await tester.pumpAndSettle();

      final dirFinder = find.byType(DirectoryListTile);
      expect(dirFinder, findsOneWidget, reason: '前置条件：目录 tile 已渲染');
      expect(tester.widget<DirectoryListTile>(dirFinder).key,
          equals(ValueKey('/music/sub')),
          reason: 'BUG-31-S1（P13）：DirectoryListTile 必须带 '
              'ValueKey(file.path)，否则列表替换按位置复用致状态错配');

      final audioFinder = find.byType(AudioFileListTile);
      expect(audioFinder, findsOneWidget, reason: '前置条件：音频 tile 已渲染');
      expect(tester.widget<AudioFileListTile>(audioFinder).key,
          equals(ValueKey('/music/song.mp3')),
          reason: 'BUG-31-S1（P13）：AudioFileListTile 必须带 '
              'ValueKey(file.path)');
    });
  });

  // ── BUG-31-S2: browserClockProvider 注入时钟 ──

  group('BUG-31-S2: directoryContentsProvider 时钟注入', () {
    test('注入时钟驱动 TTL 过期判定（无真实等待）', () async {
      final client = _CountingClient([
        testDir('sub', '/music/sub'),
        testAudio('a.mp3', '/music/a.mp3'),
      ]);
      final storage = FakeSecureStorage()..setPassword(1, 'secret');
      final sortNotifier = SortOptionNotifier(null);
      var now = DateTime(2026, 1, 1, 12, 0, 0);

      final container = makeContainer([
        activeConnectionProvider.overrideWith((ref) async => _conn),
        secureStorageProvider.overrideWithValue(storage),
        webDavClientProvider.overrideWithValue(client),
        browserClockProvider.overrideWithValue(() => now),
        sortOptionProvider.overrideWith((ref) => sortNotifier),
      ]);
      addTearDown(container.dispose);

      // T0：首次加载走网络并写缓存。
      await container.read(directoryContentsProvider('/music').future);
      expect(client.callCount, 1, reason: 'T0 首次加载必须请求网络');

      // T0：缓存存活 → 命中，不再请求网络。
      container.invalidate(directoryContentsProvider('/music'));
      await container.read(directoryContentsProvider('/music').future);
      expect(client.callCount, 1);

      // T0+4m59s：仍在 TTL 内（5min，严格 <）。
      now = DateTime(2026, 1, 1, 12, 4, 59);
      container.invalidate(directoryContentsProvider('/music'));
      await container.read(directoryContentsProvider('/music').future);
      expect(client.callCount, 1, reason: '4m59s 处缓存必须仍存活');

      // T0+5m：到期边界 → 重新请求。
      now = DateTime(2026, 1, 1, 12, 5, 0);
      container.invalidate(directoryContentsProvider('/music'));
      await container.read(directoryContentsProvider('/music').future);
      expect(client.callCount, 2, reason: '5m 边界缓存过期必须重新加载');

      // resortCached 同样受注入时钟约束：缓存存活时切换排序只重排缓存，
      // 不请求网络（provider 形态：sortOption 变化 → 依赖重建 → 走缓存分支）。
      sortNotifier.setOption(SortOption.nameDesc);
      final resorted =
          await container.read(directoryContentsProvider('/music').future);
      expect(client.callCount, 2, reason: '缓存存活（12:05:00 刚 refetch）时重排不得请求网络');
      expect(resorted, hasLength(2),
          reason: 'resortCached 语义：缓存值被重新排序返回，而非 null');

      now = DateTime(2026, 1, 1, 12, 10, 1);
      container.invalidate(directoryContentsProvider('/music'));
      await container.read(directoryContentsProvider('/music').future);
      expect(client.callCount, 3,
          reason: '注入时钟超过 TTL 后缓存必须判过期（resortCached 语义）');
    });

    test('BUG-31-INV2: 未注入时钟默认 DateTime.now，行为不变', () async {
      final client = _CountingClient([
        testAudio('a.mp3', '/music/a.mp3'),
      ]);
      final storage = FakeSecureStorage()..setPassword(1, 'secret');

      final container = makeContainer([
        activeConnectionProvider.overrideWith((ref) async => _conn),
        secureStorageProvider.overrideWithValue(storage),
        webDavClientProvider.overrideWithValue(client),
      ]);
      addTearDown(container.dispose);

      // 首次加载 → 网络请求。
      await container.read(directoryContentsProvider('/music').future);
      expect(client.callCount, 1);
      // 立即重读：真实时钟下 5min TTL 必然存活 → 命中缓存。
      container.invalidate(directoryContentsProvider('/music'));
      await container.read(directoryContentsProvider('/music').future);
      expect(client.callCount, 1, reason: '默认时钟行为与修复前一致（现有 ref_19 用例不受影响）');
    });
  });

  // ── BUG-31-S3: directoryContentsProvider 经 browserClockProvider 注入 ──

  group('BUG-31-S3: directoryContentsProvider 时钟注入', () {
    test('覆盖 browserClockProvider 可确定性验证 TTL 过期', () async {
      final spy = SpyWebDavClient()
        ..returnResult([
          testDir('sub', '/sub'),
          testAudio('a.mp3', '/a.mp3'),
        ]);
      final storage = FakeSecureStorage()..setPassword(1, 'secret');
      var now = DateTime(2026, 1, 1, 12, 0, 0);

      final container = makeContainer([
        activeConnectionProvider.overrideWith((ref) async => _conn),
        secureStorageProvider.overrideWithValue(storage),
        webDavClientProvider.overrideWithValue(spy),
        browserClockProvider.overrideWithValue(() => now),
      ]);
      addTearDown(container.dispose);

      // T0：首次加载 → 网络请求 + 缓存条目 createdAt 使用注入时钟。
      final files = await container.read(directoryContentsProvider('/').future);
      expect(files.length, 2);
      expect(spy.listDirectoryCallCount, 1);
      expect(container.read(directoryCacheProvider)['1:/']?.createdAt,
          equals(DateTime(2026, 1, 1, 12, 0, 0)),
          reason: 'BUG-31-S3：CacheEntry.createdAt 必须来自注入时钟');

      // T0+1min：TTL 内 → invalidate 重建后仍命中缓存，不 refetch。
      now = DateTime(2026, 1, 1, 12, 1, 0);
      container.invalidate(directoryContentsProvider('/'));
      await container.read(directoryContentsProvider('/').future);
      expect(spy.listDirectoryCallCount, 1, reason: 'TTL 内必须命中缓存');

      // T0+6min：注入时钟越过 5min TTL → 必须 refetch。
      // 修复前 provider 硬编码 DateTime.now()，无真实时间流逝 →
      // 缓存仍被误判存活，listDirectoryCallCount 停在 1 → 本断言 FAIL。
      now = DateTime(2026, 1, 1, 12, 6, 0);
      container.invalidate(directoryContentsProvider('/'));
      await container.read(directoryContentsProvider('/').future);
      expect(spy.listDirectoryCallCount, 2,
          reason: 'BUG-31-S3：过期判定必须使用注入时钟（P16）');
      expect(container.read(directoryCacheProvider)['1:/']?.createdAt,
          equals(DateTime(2026, 1, 1, 12, 6, 0)),
          reason: 'refetch 后新缓存条目的 createdAt 同样来自注入时钟');
    });
  });
}

// ═══════════════════════════════════════════════════════════════════════════
// Helpers
// ═══════════════════════════════════════════════════════════════════════════

/// 记录 listDirectory 调用次数的最小 fake。
class _CountingClient implements WebDavClientInterface {
  _CountingClient(this._entries);
  final List<NasFile> _entries;
  int callCount = 0;

  @override
  Future<List<NasFile>> listDirectory({
    required String url,
    required String username,
    required String password,
    required String path,
  }) async {
    callCount++;
    return _entries;
  }

  @override
  Future<WebDavValidationResult> validate({
    required String url,
    required String username,
    required String password,
    String basePath = '/',
  }) async {
    return WebDavValidationResult.success();
  }
}
