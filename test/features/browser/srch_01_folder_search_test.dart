// test/features/browser/srch_01_folder_search_test.dart
// SRCH-01 文件搜索 门禁测试（spec §5.4 指定位置，Agent A 先行测试）。
// 唯一事实来源：docs/features/SRCH-01.md + test/helpers。

import 'dart:async';
import 'dart:io';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:mockito/mockito.dart';
import 'package:nas_audio_player/core/database/dao/progress_dao.dart';
import 'package:nas_audio_player/core/network/webdav_client.dart';
import 'package:nas_audio_player/features/browser/browser_provider.dart';
import 'package:nas_audio_player/features/browser/browser_screen.dart';
import 'package:nas_audio_player/features/browser/domain/folder_searcher.dart';
import 'package:nas_audio_player/features/connection/connection_provider.dart';
import 'package:nas_audio_player/features/player/player_provider.dart';
import 'package:nas_audio_player/features/progress/progress_provider.dart';
import 'package:nas_audio_player/shared/models/nas_file.dart';
import 'package:nas_audio_player/shared/models/play_progress.dart';
import 'package:nas_audio_player/shared/models/play_queue.dart';

import '../../helpers/fake_secure_storage.dart';
import '../../helpers/mock_audio_player.dart';
import '../../helpers/test_factories.dart';
import '../../helpers/widget_helpers.dart';

NasFile _plain(String name, String path) =>
    NasFile(name: name, path: path, isDirectory: false);

class _ScanDavClient implements WebDavClientInterface {
  _ScanDavClient(this._tree);
  final _SearchTree _tree;

  @override
  Future<List<NasFile>> listDirectory({
    required String url,
    required String username,
    required String password,
    required String path,
  }) =>
      _tree.fetch(path);

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

class _SearchTree {
  final Map<String, List<NasFile>> listings = {};
  final Map<String, Object> errors = {};
  final Map<String, Completer<List<NasFile>>> _gates = {};
  final List<String> calls = [];

  void put(String path, List<NasFile> entries) => listings[path] = entries;

  void fail(String path, Object error) => errors[path] = error;

  Completer<List<NasFile>> gate(String path) {
    final c = Completer<List<NasFile>>();
    _gates[path] = c;
    return c;
  }

  // hold：路径级挂起，每次 fetch 都产出新的未完成 future（可多路持有）。
  // 与 gate（单槽、首次消费）不同——widget 测试中主列表初始 build 会先吃掉
  // gate 槽位，扫描轮需要独立挂起时用 hold。
  final _holds = <String>{};
  final heldFutures = <Completer<List<NasFile>>>[];
  void hold(String path) => _holds.add(path);

  Future<List<NasFile>> fetch(String path) async {
    calls.add(path);
    final g = _gates.remove(path);
    if (g != null) return g.future;
    if (_holds.contains(path)) {
      final c = Completer<List<NasFile>>();
      heldFutures.add(c);
      return c.future;
    }
    final e = errors[path];
    if (e != null) throw e;
    return listings[path] ?? const <NasFile>[];
  }

  Override get override =>
      directoryContentsProvider.overrideWith((ref, path) => fetch(path));

  // BUG-33（cr F1）：扫描会话的 fetchDir 已从 directoryContentsProvider 移到
  // 直接走 webDavClientProvider——同一棵树经 _ScanDavClient 适配器供给 webDav
  // 端口（主列表浏览仍走 directoryContentsProvider 的 tree.override）。
  Override get webDavOverride =>
      webDavClientProvider.overrideWithValue(_ScanDavClient(this));

  /// 扫描会话装配（BUG-33）：secureStorage 密码 + 活跃连接，与
  /// buildScanFetchDir 的依赖集合一一对应。
  Override get scanStorageOverride => secureStorageProvider.overrideWithValue(
      FakeSecureStorage()..setPassword(testConnection().id ?? 1, 'pw'));
}

class _ScanRecord {
  final events = <SearchEvent>[];
  int errorCount = 0;
}

Future<_ScanRecord> _drain(Stream<SearchEvent> stream) async {
  final rec = _ScanRecord();
  await stream
      .listen(
        rec.events.add,
        onError: (Object _) => rec.errorCount++,
      )
      .asFuture<void>();
  return rec;
}

_SearchTree _wideTree({bool failingFirst = false}) {
  final tree = _SearchTree();
  tree.put('/w', [
    if (failingFirst) testDir('bad', '/w/bad'),
    for (var i = 0; i < 204; i++) testDir('d$i', '/w/d$i'),
  ]);
  for (var i = 0; i < 204; i++) {
    tree.put('/w/d$i', [testAudio('w$i.mp3', '/w/d$i/w$i.mp3')]);
  }
  if (failingFirst) {
    tree.fail('/w/bad', const WebDavException('没有活跃的连接'));
  }
  return tree;
}

class _MapProgressDao extends ProgressDao {
  _MapProgressDao(this._store);

  final Map<(int, String), PlayProgress> _store;

  @override
  Future<PlayProgress?> find(int connectionId, String filePath) async =>
      _store[(connectionId, filePath)];

  @override
  Future<void> delete(int connectionId, String filePath) async {
    _store.remove((connectionId, filePath));
  }
}

(MockAudioPlayer, StreamController<bool>) _makePlayer() {
  final player = MockAudioPlayer();
  final controller = StreamController<bool>();
  when(player.playing).thenReturn(false);
  when(player.processingState).thenReturn(ProcessingState.ready);
  when(player.processingStateStream)
      .thenAnswer((_) => Stream<ProcessingState>.empty());
  when(player.playingStream).thenAnswer((_) => controller.stream);
  return (player, controller);
}

void main() {
  // 搜索扫描根路径 = navigationStackProvider.last（spec 定死）。
  // provider/widget 组把测试树挂在非 '/' 路径时用此夹具把导航栈顶推到对应根。
  Override navRoot(String path) => navigationStackProvider.overrideWith((ref) {
        final n = NavigationStackNotifier();
        n.push(path);
        return n;
      });

  group('SRCH-01 domain: folder_searcher（纯 Dart，无 widget binding）', () {
    test('SRCH-01-S1: query=AB 大小写不敏感子串仅命中音频文件名，目录与非音频零命中', () async {
      const root = '/s1';
      final tree = _SearchTree()
        ..put(root, [
          testAudio('ab.mp3', '$root/ab.mp3'),
          testAudio('ABC.flac', '$root/ABC.flac'),
          testAudio('cd.mp3', '$root/cd.mp3'),
          _plain('x.txt', '$root/x.txt'),
          _plain('ab.txt', '$root/ab.txt'),
          testDir('ab', '$root/ab'),
        ])
        ..put('$root/ab', <NasFile>[]);

      final rec = await _drain(searchFolderSubtree(
        rootPath: root,
        query: 'AB',
        fetchDir: tree.fetch,
      ));

      final hits = rec.events.whereType<HitFound>().toList();
      expect(hits.map((h) => h.file.name), ['ab.mp3', 'ABC.flac']);
      expect(hits.map((h) => h.parentDirPath), everyElement(root));
      expect(rec.errorCount, 0);
      expect(rec.events.whereType<ScanDone>().single.truncated, isFalse);

      expect(hits.map((h) => h.file.name), isNot(contains('cd.mp3')),
          reason: '否定断言：不含子串的音频不命中');
      expect(hits.map((h) => h.file.name), isNot(contains('x.txt')),
          reason: '否定断言：不含子串的非音频不命中');
      expect(hits.map((h) => h.file.name), isNot(contains('ab.txt')),
          reason: '否定断言：audioType == null 的匹配名文件不命中');
      expect(hits.any((h) => h.file.isDirectory), isFalse,
          reason: '否定断言：名为 ab 的目录不产生 HitFound（目录名不参与匹配）');

      final blank = await _drain(searchFolderSubtree(
        rootPath: root,
        query: '   ',
        fetchDir: tree.fetch,
      ));
      expect(blank.events.whereType<HitFound>(), isEmpty,
          reason: '否定断言：query 全空白 → matchesQuery 恒 false 零命中');
      expect(blank.events.whereType<ScanDone>(), isNotEmpty);
    });

    test('SRCH-01-S2: 250 目录缺省 maxDirs=200 → truncated=true 第 201 个起零 fetchDir',
        () async {
      const root = '/t';
      final tree = _SearchTree()
        ..put(
            root, [for (var i = 0; i < 250; i++) testDir('d$i', '$root/d$i')]);
      for (var i = 0; i < 250; i++) {
        tree.put('$root/d$i', [testAudio('h$i.mp3', '$root/d$i/h$i.mp3')]);
      }

      final rec = await _drain(searchFolderSubtree(
        rootPath: root,
        query: 'h',
        fetchDir: tree.fetch,
      ));

      final done = rec.events.whereType<ScanDone>().single;
      expect(done.truncated, isTrue);
      expect(done.skippedDirs, 0);
      expect(tree.calls, hasLength(200));
      expect(tree.calls.first, root);
      expect(tree.calls.last, '$root/d198');
      expect(tree.calls, isNot(contains('$root/d199')),
          reason: '否定断言：truncated 后第 201~250 目录 fetchDir 零调用');
      final hitParents =
          rec.events.whereType<HitFound>().map((h) => h.parentDirPath).toSet();
      expect(hitParents.contains('$root/d199'), isFalse,
          reason: '否定断言：命中只来自前 200 个已扫目录');
      expect(hitParents.length, 199);
    });

    test('SRCH-01-S2: 恰好 200 目录扫完且栈空 → truncated=false', () async {
      const root = '/e';
      final tree = _SearchTree()
        ..put(
            root, [for (var i = 0; i < 199; i++) testDir('d$i', '$root/d$i')]);
      for (var i = 0; i < 199; i++) {
        tree.put('$root/d$i', <NasFile>[]);
      }

      final rec = await _drain(searchFolderSubtree(
        rootPath: root,
        query: 'h',
        fetchDir: tree.fetch,
      ));

      final done = rec.events.whereType<ScanDone>().single;
      expect(done.truncated, isFalse, reason: '恰好扫完栈空属正常完成不算截断');
      expect(tree.calls, hasLength(200));
    });

    test('SRCH-01-S3: 单层 fetchDir 抛 WebDavException 跳过不影响整体，流正常结束不 error',
        () async {
      const root = '/s3';
      final tree = _SearchTree()
        ..put(
            root, [testDir('bad', '$root/bad'), testDir('good', '$root/good')])
        ..fail('$root/bad', const WebDavException('没有活跃的连接'))
        ..put('$root/good', [testAudio('ok.mp3', '$root/good/ok.mp3')]);

      final rec = await _drain(searchFolderSubtree(
        rootPath: root,
        query: 'ok',
        fetchDir: tree.fetch,
      ));

      expect(rec.errorCount, 0,
          reason: '否定断言：流不发出错误事件（§3.0 与 BRW-01 整体失败语义相反）');
      expect(
          rec.events.whereType<HitFound>().map((h) => h.file.name), ['ok.mp3'],
          reason: '其余命中全部送达');
      final done = rec.events.whereType<ScanDone>().single;
      expect(done.skippedDirs, 1);
      expect(done.truncated, isFalse);
      expect(rec.events.whereType<ScanProgress>().map((p) => p.dirsScanned),
          [1, 2],
          reason: '否定断言：失败层不计入 dirsScanned（只含成功层）');
    });

    test('SRCH-01-S4: 第 2 层被取消 → 该层起零 fetchDir 零事件且不发 ScanDone', () async {
      const root = '/c4';
      final tree = _SearchTree()
        ..put(root, [testDir('a', '$root/a'), testDir('b', '$root/b')])
        ..put('$root/a', [testAudio('am.mp3', '$root/a/am.mp3')])
        ..put('$root/b', [testAudio('bm.mp3', '$root/b/bm.mp3')]);

      final fetched = <String>[];
      Future<List<NasFile>> fetch(String p) async {
        fetched.add(p);
        return tree.fetch(p);
      }

      bool isCancelled() => fetched.length >= 1;

      final rec = await _drain(searchFolderSubtree(
        rootPath: root,
        query: 'm',
        fetchDir: fetch,
        isCancelled: isCancelled,
      ));

      expect(fetched, [root], reason: '取消生效层起零 fetchDir 调用');
      expect(rec.events.whereType<ScanDone>(), isEmpty,
          reason: '否定断言：取消后不发 ScanDone（订阅方据此区分取消与完成）');
      // spec S4「第 k 层起零事件」：根层无音频，取消后子层从未扫描，
      // 不可能产生任何 HitFound（原期望 ['am.mp3'] 与 fetched==[root] 互斥）。
      expect(rec.events.whereType<HitFound>(), isEmpty);
      expect(rec.events.last, isA<ScanProgress>());
    });

    test('SRCH-01-S4: 启动即取消 → 零 fetchDir 零事件', () async {
      const root = '/c0';
      final tree = _SearchTree()..put(root, <NasFile>[]);

      final rec = await _drain(searchFolderSubtree(
        rootPath: root,
        query: 'x',
        fetchDir: tree.fetch,
        isCancelled: () => true,
      ));

      expect(rec.events, isEmpty);
      expect(tree.calls, isEmpty);
    });

    test(
        'SRCH-01-ALG1: 黄金样例 query=b → 命中序[ab.flac,bb.mp3] fetch 序[root,dA,dC,dB]',
        () async {
      const root = '/alg';
      final tree = _SearchTree()
        ..put(root, [
          testAudio('a1.mp3', '$root/a1.mp3'),
          testDir('dA', '$root/dA'),
          testAudio('ab.flac', '$root/ab.flac'),
          testDir('dB', '$root/dB'),
        ])
        ..put('$root/dA', [
          testAudio('aa.mp3', '$root/dA/aa.mp3'),
          testDir('dC', '$root/dA/dC')
        ])
        ..put('$root/dA/dC', [testAudio('cc.mp3', '$root/dA/dC/cc.mp3')])
        ..put('$root/dB', [testAudio('bb.mp3', '$root/dB/bb.mp3')]);

      final rec = await _drain(searchFolderSubtree(
        rootPath: root,
        query: 'b',
        fetchDir: tree.fetch,
      ));

      expect(rec.events.whereType<HitFound>().map((h) => h.file.name).toList(),
          ['ab.flac', 'bb.mp3'],
          reason: '先序分组命中序');
      expect(tree.calls, ['$root', '$root/dA', '$root/dA/dC', '$root/dB'],
          reason: 'fetch 序与 §6 步骤表逐字一致');
      final done = rec.events.whereType<ScanDone>().single;
      expect(done.truncated, isFalse);
      expect(done.skippedDirs, 0);
    });

    test('SRCH-01-ALG1 变体1: dA 层抛普通 Exception → 命中不变 skippedDirs=1', () async {
      const root = '/algv1';
      final tree = _SearchTree()
        ..put(root, [
          testAudio('a1.mp3', '$root/a1.mp3'),
          testDir('dA', '$root/dA'),
          testAudio('ab.flac', '$root/ab.flac'),
          testDir('dB', '$root/dB'),
        ])
        ..fail('$root/dA', Exception('dA boom'))
        ..put('$root/dB', [testAudio('bb.mp3', '$root/dB/bb.mp3')]);

      final rec = await _drain(searchFolderSubtree(
        rootPath: root,
        query: 'b',
        fetchDir: tree.fetch,
      ));

      expect(rec.errorCount, 0);
      expect(rec.events.whereType<HitFound>().map((h) => h.file.name).toList(),
          ['ab.flac', 'bb.mp3']);
      expect(rec.events.whereType<ScanDone>().single.skippedDirs, 1);
      expect(tree.calls, contains('$root/dA'));
    });

    test('SRCH-01-ALG1 变体2: maxDirs=2 扫完 dA 即 truncated=true 且 dB 未 fetch',
        () async {
      const root = '/algv2';
      final tree = _SearchTree()
        ..put(root, [
          testAudio('a1.mp3', '$root/a1.mp3'),
          testDir('dA', '$root/dA'),
          testAudio('ab.flac', '$root/ab.flac'),
          testDir('dB', '$root/dB'),
        ])
        ..put('$root/dA', [testDir('dC', '$root/dA/dC')])
        ..put('$root/dA/dC', [testAudio('cc.mp3', '$root/dA/dC/cc.mp3')])
        ..put('$root/dB', [testAudio('bb.mp3', '$root/dB/bb.mp3')]);

      final rec = await _drain(searchFolderSubtree(
        rootPath: root,
        query: 'b',
        fetchDir: tree.fetch,
        maxDirs: 2,
      ));

      expect(rec.events.whereType<HitFound>().map((h) => h.file.name).toList(),
          ['ab.flac']);
      expect(tree.calls, ['$root', '$root/dA'], reason: '边界档：dB 未 fetch');
      final done = rec.events.whereType<ScanDone>().single;
      expect(done.truncated, isTrue);
      expect(done.skippedDirs, 0);
    });

    test('SRCH-01-ALG1 边界: matchesQuery 空 query / 纯空白 / 大小写混合直接单测', () {
      expect(matchesQuery('ab.mp3', ''), isFalse);
      expect(matchesQuery('ab.mp3', '   '), isFalse);
      expect(matchesQuery('ab.mp3', 'AB'), isTrue);
      expect(matchesQuery('AB.mp3', 'aB'), isTrue);
      expect(matchesQuery('ABC.flac', 'b'), isTrue);
      expect(matchesQuery('cd.mp3', 'AB'), isFalse);
    });

    test(
        'SRCH-01-INV3: folder_searcher.dart 纯 Dart 零 Flutter/provider 依赖（本组全部为无 binding 的纯 test）',
        () async {
      final src = await File(
              '${Directory.current.path}/lib/features/browser/domain/folder_searcher.dart')
          .readAsString();
      expect(src.contains('package:flutter/'), isFalse,
          reason: 'INV3：domain 层不得依赖 Flutter');
      expect(src.contains('riverpod'), isFalse,
          reason: 'INV3：fetchDir/isCancelled 注入，零 provider 依赖');
    });
  });

  group(
      'SRCH-01 provider: searchSessionProvider（ProviderContainer + fakeAsync）',
      () {
    test('SRCH-01-S5: 连续输入间隔小于 500ms 仅最后一次触发一次扫描', () {
      fakeAsync((async) {
        final tree = _SearchTree()
          ..put('/leaf', [
            testAudio('晴天版.mp3', '/leaf/晴天版.mp3'),
            testAudio('rain.mp3', '/leaf/rain.mp3'),
          ]);
        final container = ProviderContainer(overrides: [
          tree.override,
          tree.webDavOverride,
          tree.scanStorageOverride,
          activeConnectionProvider
              .overrideWith((ref) async => testConnection()),
          navRoot('/leaf'),
        ]);
        container.listen(searchSessionProvider, (prev, next) {});
        final notifier = container.read(searchSessionProvider.notifier);

        notifier.openPanel();
        notifier.onQueryChanged('晴');
        async.elapse(const Duration(milliseconds: 100));
        notifier.onQueryChanged('晴天');
        async.elapse(const Duration(milliseconds: 100));
        notifier.onQueryChanged('晴天版');
        expect(tree.calls, isEmpty,
            reason: '否定断言：每次 keystroke 都立即发起新扫描（错）——最后一次输入后 500ms 内零 fetchDir');
        async.elapse(const Duration(milliseconds: 600));

        expect(tree.calls, ['/leaf'], reason: '只有最后一次输入触发且仅一次 startScan');
        final s = container.read(searchSessionProvider);
        expect(s.hits.map((h) => h.file.name), ['晴天版.mp3']);
        expect(s.running, isFalse);
        container.dispose();
      });
    });

    test('SRCH-01-S5: trim 后空白 query 取消进行中扫描、零新 fetchDir 且忽略迟到命中', () {
      fakeAsync((async) {
        final tree = _SearchTree()
          ..put('/g', [testAudio('abc_hit.mp3', '/g/abc_hit.mp3')]);
        final container = ProviderContainer(overrides: [
          tree.override,
          tree.webDavOverride,
          tree.scanStorageOverride,
          activeConnectionProvider
              .overrideWith((ref) async => testConnection()),
          navRoot('/g'),
        ]);
        container.listen(searchSessionProvider, (prev, next) {});
        final notifier = container.read(searchSessionProvider.notifier);

        final gate = tree.gate('/g');
        notifier.openPanel();
        notifier.onQueryChanged('abc');
        async.elapse(const Duration(milliseconds: 600));
        var s = container.read(searchSessionProvider);
        expect(s.running, isTrue);
        expect(tree.calls, ['/g']);

        notifier.onQueryChanged('   ');
        async.elapse(const Duration(milliseconds: 600));
        expect(tree.calls, ['/g'],
            reason: '否定断言：空 query 发起 fetchDir（错）——未新增任何调用');
        s = container.read(searchSessionProvider);
        expect(s.panelOpen, isTrue);
        expect(s.running, isFalse);
        expect(s.hits, isEmpty);
        expect(s.dirsScanned, 0);
        expect(s.truncated, isFalse);
        expect(s.skippedDirs, 0);

        gate.complete([testAudio('late.mp3', '/g/late.mp3')]);
        async.elapse(const Duration(milliseconds: 50));
        expect(container.read(searchSessionProvider).hits, isEmpty,
            reason: '已取消订阅的迟到事件被忽略');
        container.dispose();
      });
    });

    test('SRCH-01-S6: 换 query 重扫 → 终态只含新 query 命中，跨 query 零累积', () {
      fakeAsync((async) {
        final tree = _SearchTree()
          ..put('/sw', [
            testAudio('sunny1.mp3', '/sw/sunny1.mp3'),
            testAudio('sunny2.mp3', '/sw/sunny2.mp3'),
            testAudio('rainy.mp3', '/sw/rainy.mp3'),
          ]);
        final container = ProviderContainer(overrides: [
          tree.override,
          tree.webDavOverride,
          tree.scanStorageOverride,
          activeConnectionProvider
              .overrideWith((ref) async => testConnection()),
          navRoot('/sw'),
        ]);
        container.listen(searchSessionProvider, (prev, next) {});
        final notifier = container.read(searchSessionProvider.notifier);

        notifier.openPanel();
        notifier.onQueryChanged('sun');
        async.elapse(const Duration(milliseconds: 600));
        expect(
            container.read(searchSessionProvider).hits.map((h) => h.file.name),
            ['sunny1.mp3', 'sunny2.mp3'],
            reason: '前置：第一轮扫描完成且产生命中');

        notifier.onQueryChanged('rain');
        async.elapse(const Duration(milliseconds: 600));
        final s = container.read(searchSessionProvider);
        expect(s.running, isFalse);
        expect(s.query, 'rain');
        expect(s.hits.map((h) => h.file.name), ['rainy.mp3'],
            reason: '新一轮扫描启动即清空上一轮命中——终态只含当前 query 的结果');
        expect(s.hits.map((h) => h.file.name), isNot(contains('sunny1.mp3')),
            reason: '否定断言：上一轮命中不残留');
        expect(s.dirsScanned, 1, reason: 'dirsScanned 按新一轮重计');
        container.dispose();
      });
    });

    test('SRCH-01-S5: 有命中状态下输入空白 → 复位为已打开零结果零扫描态且挂起 debounce 被吞', () {
      fakeAsync((async) {
        final tree = _SearchTree()
          ..put('/bz', [testAudio('hit_bz.mp3', '/bz/hit_bz.mp3')]);
        final container = ProviderContainer(overrides: [
          tree.override,
          tree.webDavOverride,
          tree.scanStorageOverride,
          activeConnectionProvider
              .overrideWith((ref) async => testConnection()),
          navRoot('/bz'),
        ]);
        container.listen(searchSessionProvider, (prev, next) {});
        final notifier = container.read(searchSessionProvider.notifier);

        notifier.openPanel();
        notifier.onQueryChanged('bz');
        async.elapse(const Duration(milliseconds: 600));
        expect(container.read(searchSessionProvider).hits, hasLength(1),
            reason: '前置：第一轮扫描完成且产生命中');

        // 先武装一个 pending debounce（'ab'），再立即输入空白——
        // 空白分支必须连带取消该 timer，旧 query 永不发起扫描。
        notifier.onQueryChanged('ab');
        notifier.onQueryChanged('   ');
        async.elapse(const Duration(milliseconds: 700));
        expect(tree.calls, ['/bz'],
            reason: '否定断言：空白后挂起的 debounce 不触发任何新 fetchDir');

        final s = container.read(searchSessionProvider);
        expect(s.panelOpen, isTrue);
        expect(s.running, isFalse);
        expect(s.hits, isEmpty, reason: 'S5 字面：回到「零结果」态');
        expect(s.dirsScanned, 0);
        expect(s.truncated, isFalse);
        expect(s.skippedDirs, 0);
        expect(s.query, '');
        container.dispose();
      });
    });

    test('SRCH-01-S5: 新扫描启动前旧订阅被取消——同一时刻至多一条活跃流', () {
      fakeAsync((async) {
        final tree = _SearchTree()
          ..put('/r', [testAudio('seed.mp3', '/r/seed.mp3')]);
        final container = ProviderContainer(overrides: [
          tree.override,
          tree.webDavOverride,
          tree.scanStorageOverride,
          activeConnectionProvider
              .overrideWith((ref) async => testConnection()),
          navRoot('/r'),
        ]);
        container.listen(searchSessionProvider, (prev, next) {});
        final notifier = container.read(searchSessionProvider.notifier);

        final gate1 = tree.gate('/r');
        notifier.openPanel();
        notifier.onQueryChanged('aa');
        async.elapse(const Duration(milliseconds: 600));
        expect(tree.calls, ['/r']);

        // 导航深入子目录后换 query 重扫：扫描根随栈顶变化（spec 定死
        // root=navigationStack.last），第二轮路径缓存未暖 → 独立挂起槽。
        // （ref.read 缓存语义下同路径二扫会命中已完成 future，无法再挂起。）
        container.read(navigationStackProvider.notifier).push('/r/deep');
        final gate2 = tree.gate('/r/deep');
        notifier.onQueryChanged('bb');
        async.elapse(const Duration(milliseconds: 600));
        expect(tree.calls, ['/r', '/r/deep'], reason: '两轮各发起一次 fetchDir');

        gate1.complete([testAudio('old_aa.mp3', '/r/old_aa.mp3')]);
        async.elapse(const Duration(milliseconds: 50));
        expect(container.read(searchSessionProvider).hits, isEmpty,
            reason: '否定断言：startScan 前必须取消旧订阅，第一轮迟到数据不得到达');

        gate2.complete([testAudio('new_bb.mp3', '/r/deep/new_bb.mp3')]);
        async.elapse(const Duration(milliseconds: 50));
        expect(
            container.read(searchSessionProvider).hits.map((h) => h.file.name),
            ['new_bb.mp3']);
        container.dispose();
      });
    });

    test('SRCH-01-S6: 事件归约——hits 尾追保序不去重、dirsScanned 更新、ScanDone 落位', () {
      fakeAsync((async) {
        final tree = _SearchTree()
          ..put('/m', [
            testAudio('m1.mp3', '/m/m1.mp3'),
            testDir('sub', '/m/sub'),
            testAudio('m2_x.mp3', '/m/m2_x.mp3'),
            testAudio('m2_x.mp3', '/m/copy/m2_x.mp3'),
          ])
          ..put('/m/sub', [testAudio('target_b.mp3', '/m/sub/target_b.mp3')]);
        // query='_'：恰好命中 m2_x.mp3×2 与 target_b.mp3（三者含下划线，
        // m1.mp3 不含被排除）——原 'b' 与期望命中集数学上不相容。
        final container = ProviderContainer(overrides: [
          tree.override,
          tree.webDavOverride,
          tree.scanStorageOverride,
          activeConnectionProvider
              .overrideWith((ref) async => testConnection()),
          navRoot('/m'),
        ]);
        final states = <SearchSessionState>[];
        container.listen(
            searchSessionProvider, (prev, next) => states.add(next));
        final notifier = container.read(searchSessionProvider.notifier);

        notifier.openPanel();
        notifier.onQueryChanged('_');
        async.elapse(const Duration(milliseconds: 600));

        final s = container.read(searchSessionProvider);
        expect(s.hits.map((h) => h.file.name).toList(),
            ['m2_x.mp3', 'm2_x.mp3', 'target_b.mp3'],
            reason: '收集序即展示序，不去重不去序');
        expect(s.hits.map((h) => h.file.path).toSet().length, 3,
            reason: '同名不同路径的两条命中都保留');
        expect(s.dirsScanned, 2);
        expect(s.running, isFalse);
        expect(s.truncated, isFalse);
        expect(s.skippedDirs, 0);
        // 增量归约可见：§3.1 规约序下本层 HitFound 先于该层 ScanProgress
        // 到达，故 dirsScanned==1 的快照里本层命中已全部尾追到位。
        final layer1HitSeqs = states
            .where((st) => st.running && st.dirsScanned == 1)
            .map((st) => st.hits.map((h) => h.file.name).toList())
            .toList();
        expect(layer1HitSeqs, contains(equals(['m2_x.mp3', 'm2_x.mp3'])),
            reason: '规约序（spec §3.1）：计数落位时本层命中已逐条尾追齐全');
        container.dispose();
      });
    });

    test('SRCH-01-S6: running==false 后到达的事件被忽略（防御迟到事件）', () {
      fakeAsync((async) {
        final tree = _SearchTree()
          ..put('/m', [
            testAudio('m2_x.mp3', '/m/m2_x.mp3'),
            testDir('sub', '/m/sub'),
          ])
          ..put('/m/sub', [testAudio('target_b.mp3', '/m/sub/target_b.mp3')]);
        final container = ProviderContainer(overrides: [
          tree.override,
          tree.webDavOverride,
          tree.scanStorageOverride,
          activeConnectionProvider
              .overrideWith((ref) async => testConnection()),
          navRoot('/m'),
        ]);
        container.listen(searchSessionProvider, (prev, next) {});
        final notifier = container.read(searchSessionProvider.notifier);

        notifier.openPanel();
        notifier.onQueryChanged('_');
        async.elapse(const Duration(milliseconds: 600));
        final baseline =
            container.read(searchSessionProvider).hits.map((h) => h.file.path);
        expect(baseline, hasLength(2));

        // 深入新目录后换 query：新路径缓存未暖，首层 fetch 可挂起。
        // （ref.read 缓存语义下同路径二扫直接吃已完成 future。）
        tree.put('/m/deep', [testAudio('zzz_a.mp3', '/m/deep/zzz_a.mp3')]);
        container.read(navigationStackProvider.notifier).push('/m/deep');
        final gate = tree.gate('/m/deep');
        notifier.onQueryChanged('zzz');
        async.elapse(const Duration(milliseconds: 600));
        expect(container.read(searchSessionProvider).running, isTrue);

        notifier.onQueryChanged('   ');
        async.elapse(const Duration(milliseconds: 600));
        expect(container.read(searchSessionProvider).running, isFalse);

        gate.complete([testAudio('zzz_a.mp3', '/m/zzz_a.mp3')]);
        async.elapse(const Duration(milliseconds: 50));
        expect(container.read(searchSessionProvider).running, isFalse);
        // 换 query 启动新扫描时已清空上一轮命中（S6 归约前提）；迟到的
        // zzz 命中若未被 running 门禁丢弃，此处将出现 ['zzz_a.mp3']。
        expect(
            container.read(searchSessionProvider).hits.map((h) => h.file.name),
            isEmpty,
            reason: '否定断言：running==false 后迟到的 HitFound 不再改变状态');
        container.dispose();
      });
    });

    test('SRCH-01-S7: cancelScan 冻结状态；closePanel 全清并连带取消 debounce', () {
      fakeAsync((async) {
        final tree = _SearchTree()
          ..put('/c', [testAudio('cx.mp3', '/c/cx.mp3')]);
        final container = ProviderContainer(overrides: [
          tree.override,
          tree.webDavOverride,
          tree.scanStorageOverride,
          activeConnectionProvider
              .overrideWith((ref) async => testConnection()),
          navRoot('/c'),
        ]);
        container.listen(searchSessionProvider, (prev, next) {});
        final notifier = container.read(searchSessionProvider.notifier);

        final gate = tree.gate('/c');
        notifier.openPanel();
        notifier.onQueryChanged('x');
        async.elapse(const Duration(milliseconds: 600));
        expect(container.read(searchSessionProvider).running, isTrue);

        notifier.cancelScan();
        async.elapse(const Duration(milliseconds: 10));
        var s = container.read(searchSessionProvider);
        expect(s.running, isFalse);
        expect(s.panelOpen, isTrue, reason: 'cancelScan 只停扫描不收面板');

        gate.complete([testAudio('cx.mp3', '/c/cx.mp3')]);
        async.elapse(const Duration(milliseconds: 50));
        s = container.read(searchSessionProvider);
        expect(s.hits, isEmpty, reason: '否定断言：取消后 hits 残留显示（错）');
        expect(s.dirsScanned, 0, reason: '否定断言：取消后 dirsScanned 残留（错）');

        notifier.onQueryChanged('y');
        notifier.closePanel();
        async.elapse(const Duration(milliseconds: 700));
        expect(tree.calls, ['/c'],
            reason: 'closePanel 连带取消 debounce——y 从未触发扫描');

        s = container.read(searchSessionProvider);
        expect(s.panelOpen, isFalse);
        expect(s.hits, isEmpty);
        expect(s.dirsScanned, 0);
        expect(s.running, isFalse);
        expect(s.truncated, isFalse);
        expect(s.skippedDirs, 0);
        container.dispose();
      });
    });

    test('SRCH-01-INV2: 扫描全程只读——currentPlayQueue/lastQueueConnectionId 零写入',
        () {
      fakeAsync((async) {
        final tree = _SearchTree()
          ..put('/ro', [testAudio('ro_hit.mp3', '/ro/ro_hit.mp3')]);
        final container = ProviderContainer(overrides: [
          tree.override,
          tree.webDavOverride,
          tree.scanStorageOverride,
          activeConnectionProvider
              .overrideWith((ref) async => testConnection()),
          navRoot('/ro'),
        ]);
        container.listen(searchSessionProvider, (prev, next) {});
        final q0 = container.read(currentPlayQueueProvider);
        final c0 = container.read(lastQueueConnectionIdProvider);
        final notifier = container.read(searchSessionProvider.notifier);

        notifier.openPanel();
        notifier.onQueryChanged('ro');
        async.elapse(const Duration(milliseconds: 700));

        expect(container.read(searchSessionProvider).hits, hasLength(1),
            reason: '前置：扫描确实完成并产生命中');
        expect(identical(container.read(currentPlayQueueProvider), q0), isTrue,
            reason: 'INV2：队列写入仅发生于 S10 用户显式动作');
        expect(container.read(lastQueueConnectionIdProvider), c0 ?? null,
            reason: 'INV2：搜索自身不写连接 id');
        container.dispose();
      });
    });
  });

  group('SRCH-01 widget: BrowserScreen 搜索面板', () {
    Finder _cancelScanIcon() => find.byWidgetPredicate(
        (w) => w is Icon && (w.icon == Icons.cancel || w.icon == Icons.stop));

    Future<(ProviderContainer, StreamController<bool>)> _pumpBrowser(
      WidgetTester tester, {
      required _SearchTree tree,
      Map<(int, String), PlayProgress> progressStore = const {},
      List<Override> extra = const [],
    }) async {
      final (player, controller) = _makePlayer();
      await tester.pumpWidget(buildTestAppWithPlayerRoute(
        Scaffold(body: BrowserScreen()),
        overrides: [
          tree.override,
          tree.webDavOverride,
          tree.scanStorageOverride,
          activeConnectionProvider
              .overrideWith((ref) async => testConnection()),
          progressDaoProvider.overrideWithValue(_MapProgressDao(progressStore)),
          audioPlayerProvider.overrideWithValue(player),
          playModeProvider.overrideWith((ref) => PlayMode.sequential),
          ...extra,
        ],
      ));
      addTearDown(controller.close);
      await tester.pumpAndSettle();
      final container =
          ProviderScope.containerOf(tester.element(find.byType(BrowserScreen)));
      return (container, controller);
    }

    Future<void> _openPanel(WidgetTester tester) async {
      await tester.tap(find.byIcon(Icons.search));
      await tester.pumpAndSettle();
    }

    Future<void> _typeOnly(WidgetTester tester, String text) async {
      await tester.enterText(find.byType(TextField), text);
      await tester.pump();
    }

    Future<void> _query(WidgetTester tester, String text) async {
      await _typeOnly(tester, text);
      await tester.pump(const Duration(milliseconds: 600));
    }

    testWidgets('SRCH-01-S8: 放大镜入口开合搜索面板，关闭态主列表照常渲染', (tester) async {
      final tree = _SearchTree()
        ..put('/', [testAudio('keep.mp3', '/keep.mp3')]);
      await _pumpBrowser(tester, tree: tree);

      expect(find.byIcon(Icons.search), findsOneWidget);
      expect(find.byType(TextField), findsNothing, reason: '否定断言：初始态无搜索输入框');
      expect(find.textContaining('已扫'), findsNothing);
      expect(find.text('keep.mp3'), findsOneWidget);

      await _openPanel(tester);
      expect(find.byType(TextField), findsOneWidget);

      await tester.tap(find.byIcon(Icons.search));
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsNothing, reason: '再点收起');
      expect(find.text('keep.mp3'), findsOneWidget, reason: '收起后回到普通浏览主列表');
    });

    testWidgets('SRCH-01-INV1: 面板关闭初始渲染快照——主列表与注入数据一致且无搜索 UI', (tester) async {
      final tree = _SearchTree()
        ..put('/', [
          testAudio('alpha.mp3', '/alpha.mp3'),
          testDir('Beta', '/Beta'),
        ])
        ..put('/Beta', [testAudio('beta_inner.mp3', '/Beta/beta_inner.mp3')]);
      await _pumpBrowser(tester, tree: tree);

      expect(find.text('alpha.mp3'), findsOneWidget);
      expect(find.text('Beta'), findsOneWidget);
      expect(find.text('beta_inner.mp3'), findsNothing);
      expect(find.byType(TextField), findsNothing);
      expect(find.textContaining('命中'), findsNothing);
      expect(find.text('无匹配结果'), findsNothing);
      expect(find.textContaining(RegExp(r'\d+\s*个目录无法读取')), findsNothing);
    });

    testWidgets('SRCH-01-S9: done 干净态——命中行 title/subtitle/trailing 形态齐全',
        (tester) async {
      final tree = _SearchTree()
        ..put('/', [
          testAudio('sunny_d.mp3', '/sunny_d.mp3'),
          testAudio('rain.mp3', '/rain.mp3'),
          testDir('Sub', '/Sub'),
        ])
        ..put('/Sub', [testAudio('deep_sunny.mp3', '/Sub/deep_sunny.mp3')]);
      final (container, _) = await _pumpBrowser(tester, tree: tree);

      await _openPanel(tester);
      await _query(tester, 'sun');
      await tester.pumpAndSettle();

      expect(find.textContaining(RegExp('命中\\s*2')), findsOneWidget);
      expect(find.textContaining(RegExp(r'\d+\s*个目录无法读取')), findsNothing);
      expect(find.textContaining(RegExp('已扫描前\\s*${kSearchMaxDirs}\\s*个目录')),
          findsNothing);

      final tile =
          tester.widget<ListTile>(find.widgetWithText(ListTile, 'sunny_d.mp3'));
      expect((tile.title! as Text).data, 'sunny_d.mp3');
      expect((tile.subtitle! as Text).data, '/');
      final trailing = tile.trailing! as IconButton;
      expect(((trailing.icon as Icon).icon), Icons.queue_music);
      expect(trailing.onPressed, isNull, reason: '无队列时 trailing 置灰');

      final tile2 = tester
          .widget<ListTile>(find.widgetWithText(ListTile, 'deep_sunny.mp3'));
      expect((tile2.subtitle! as Text).data, '/Sub');

      expect(find.byType(RefreshIndicator), findsNothing,
          reason: '否定断言：结果区不出现下拉刷新');
      expect(find.text('Sub'), findsNothing, reason: '否定断言：目录条目不混入结果');
      expect(container.read(searchSessionProvider).running, isFalse);
    });

    testWidgets('SRCH-01-S9: truncated 态状态行补充已扫描前 200 个目录', (tester) async {
      final tree = _wideTree();
      final (container, _) =
          await _pumpBrowser(tester, tree: tree, extra: [navRoot('/w')]);

      await _openPanel(tester);
      await _query(tester, 'w');
      await tester.pumpAndSettle();

      expect(find.textContaining(RegExp('已扫描前\\s*$kSearchMaxDirs\\s*个目录')),
          findsOneWidget);
      expect(find.textContaining(RegExp('命中\\s*199')), findsOneWidget);
      expect(find.textContaining(RegExp(r'\d+\s*个目录无法读取')), findsNothing);
      final s = container.read(searchSessionProvider);
      expect(s.truncated, isTrue);
      expect(s.skippedDirs, 0);
    });

    testWidgets('SRCH-01-S9: skippedDirs>0 态状态行补充 N 个目录无法读取', (tester) async {
      const skipped = 1;
      final tree = _SearchTree()
        ..put('/', [testDir('bad', '/bad'), testDir('good', '/good')])
        ..fail('/bad', const WebDavException('没有活跃的连接'))
        ..put('/good', [testAudio('skip_s.mp3', '/good/skip_s.mp3')]);
      final (container, _) = await _pumpBrowser(tester, tree: tree);

      await _openPanel(tester);
      await _query(tester, 's');
      await tester.pumpAndSettle();

      expect(
          find.textContaining(RegExp('${skipped}\\s*个目录无法读取')), findsOneWidget);
      expect(find.textContaining(RegExp('命中\\s*1')), findsOneWidget);
      expect(find.textContaining(RegExp('已扫描前\\s*${kSearchMaxDirs}\\s*个目录')),
          findsNothing);
      expect(container.read(searchSessionProvider).truncated, isFalse);
      expect(container.read(searchSessionProvider).skippedDirs, skipped);
    });

    testWidgets('SRCH-01-S9: truncated+skipped 四象限组合两段文案同时出现', (tester) async {
      final tree = _wideTree(failingFirst: true);
      final (container, _) =
          await _pumpBrowser(tester, tree: tree, extra: [navRoot('/w')]);

      await _openPanel(tester);
      await _query(tester, 'w');
      await tester.pumpAndSettle();

      expect(find.textContaining(RegExp('已扫描前\\s*$kSearchMaxDirs\\s*个目录')),
          findsOneWidget);
      expect(find.textContaining(RegExp('1\\s*个目录无法读取')), findsOneWidget);
      expect(find.textContaining(RegExp('命中\\s*199')), findsOneWidget);
      expect(container.read(searchSessionProvider).truncated, isTrue);
      expect(container.read(searchSessionProvider).skippedDirs, 1);
    });

    testWidgets('SRCH-01-S9: running 态显示已扫 N 个目录与取消钮，取消后迟到事件冻结状态',
        (tester) async {
      final tree = _SearchTree()
        ..put('/', <NasFile>[])
        ..hold('/');
      final (container, _) = await _pumpBrowser(tester, tree: tree);

      await _openPanel(tester);
      await _typeOnly(tester, 'zzz');
      await tester.pump(const Duration(milliseconds: 600));

      expect(find.textContaining(RegExp('已扫')), findsOneWidget);
      expect(_cancelScanIcon(), findsOneWidget, reason: 'running 态有取消钮');
      expect(container.read(searchSessionProvider).running, isTrue);
      expect(find.text('无匹配结果'), findsNothing,
          reason: 'S9 条件面：居中文案仅「hits 空且 done」渲染，running 期不得出现');

      await tester.tap(_cancelScanIcon());
      await tester.pump();
      expect(container.read(searchSessionProvider).running, isFalse);

      // 迟到数据补齐所有挂起 fetch——已取消订阅，事件必须被整体忽略。
      final lateAudio = [testAudio('zzz_late.mp3', '/zzz_late.mp3')];
      for (final c in List.of(tree.heldFutures)) {
        c.complete(lateAudio);
      }
      await tester.pump(const Duration(milliseconds: 100));
      final s = container.read(searchSessionProvider);
      expect(s.hits, isEmpty, reason: '取消后迟到命中被冻结在零结果');
      expect(s.dirsScanned, 0);
    });

    testWidgets('SRCH-01-S9: 空 hits 且 done → 居中无匹配结果', (tester) async {
      final tree = _SearchTree()..put('/', <NasFile>[]);
      final (container, _) = await _pumpBrowser(tester, tree: tree);

      await _openPanel(tester);
      await _query(tester, 'anything');
      await tester.pumpAndSettle();

      expect(find.text('无匹配结果'), findsOneWidget);
      expect(container.read(searchSessionProvider).running, isFalse);
    });

    testWidgets(
        'SRCH-01-S10: 带进度行点击 → 真实恢复对话框续播 → 队列=父目录全集 startPositionMs=60000 进播放页',
        (tester) async {
      final tree = _SearchTree()
        ..put('/', [testDir('Music', '/Music')])
        ..put('/Music', [
          testAudio('other.mp3', '/Music/other.mp3'),
          testAudio('sun.mp3', '/Music/sun.mp3'),
        ]);
      final store = {
        (1, '/Music/sun.mp3'):
            testProgress(filePath: '/Music/sun.mp3', positionMs: 60000),
      };
      final (container, _) =
          await _pumpBrowser(tester, tree: tree, progressStore: store);

      await _openPanel(tester);
      await _query(tester, 'sun');
      await tester.pumpAndSettle();
      expect(find.text('sun.mp3'), findsOneWidget);

      await tester.tap(find.text('sun.mp3'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('恢复播放进度'), findsOneWidget, reason: '真实对话框不被 mock');

      // '继续' 同时出现在对话框正文（是否从此处继续？）与按钮上——
      // 收窄到含「继续播放」文案的 TextButton。
      await tester.tap(find.ancestor(
          of: find.textContaining(RegExp('继续播放')),
          matching: find.byType(TextButton)));
      await tester.pumpAndSettle();

      expect(find.text('Player'), findsOneWidget, reason: 'push /player');
      final queue = container.read(currentPlayQueueProvider);
      expect(queue, isNotNull);
      expect(queue!.files.map((f) => f.path).toList(),
          ['/Music/other.mp3', '/Music/sun.mp3'],
          reason: '队列=命中父目录收集的全部音频');
      expect(queue.currentIndex, 1, reason: '从命中曲开始播');
      expect(queue.startPositionMs, 60000);
      expect(container.read(lastQueueConnectionIdProvider), 1);
      expect(container.read(playModeProvider), PlayMode.sequential,
          reason: '否定断言：不修改 playModeProvider（只读）');
    });

    testWidgets(
        'SRCH-01-S10: 恢复对话框直接关闭（resume==null 盲点补偿）→ startPositionMs 保持 null',
        (tester) async {
      final tree = _SearchTree()
        ..put('/', [testDir('Music', '/Music')])
        ..put('/Music', [
          testAudio('other.mp3', '/Music/other.mp3'),
          testAudio('sun.mp3', '/Music/sun.mp3'),
        ]);
      final store = {
        (1, '/Music/sun.mp3'):
            testProgress(filePath: '/Music/sun.mp3', positionMs: 60000),
      };
      final (container, _) =
          await _pumpBrowser(tester, tree: tree, progressStore: store);

      await _openPanel(tester);
      await _query(tester, 'sun');
      await tester.pumpAndSettle();

      await tester.tap(find.text('sun.mp3'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('恢复播放进度'), findsOneWidget);

      // showProgressResumeDialog 为 barrierDismissible:false —— barrier 点击
      // 物理无效；以系统返回键等价手势（maybePop）触发 resume==null 路径。
      tester.state<NavigatorState>(find.byType(Navigator)).maybePop();
      await tester.pumpAndSettle();
      expect(find.text('恢复播放进度'), findsNothing);
      expect(find.text('Player'), findsOneWidget);

      final queue = container.read(currentPlayQueueProvider);
      expect(queue, isNotNull);
      expect(queue!.startPositionMs, isNull);
      expect(queue.currentIndex, 1);
    });

    testWidgets('SRCH-01-S10: 恢复对话框选「从头播放」→ 清进度记录且 startPositionMs 保持 null',
        (tester) async {
      final tree = _SearchTree()
        ..put('/', [testDir('Music', '/Music')])
        ..put('/Music', [
          testAudio('other.mp3', '/Music/other.mp3'),
          testAudio('sun.mp3', '/Music/sun.mp3'),
        ]);
      final store = {
        (1, '/Music/sun.mp3'):
            testProgress(filePath: '/Music/sun.mp3', positionMs: 60000),
      };
      final (container, _) =
          await _pumpBrowser(tester, tree: tree, progressStore: store);

      await _openPanel(tester);
      await _query(tester, 'sun');
      await tester.pumpAndSettle();

      await tester.tap(find.text('sun.mp3'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('恢复播放进度'), findsOneWidget);

      await tester.tap(find.widgetWithText(TextButton, '从头播放'));
      await tester.pumpAndSettle();

      expect(find.text('恢复播放进度'), findsNothing);
      expect(find.text('Player'), findsOneWidget);
      final queue = container.read(currentPlayQueueProvider);
      expect(queue, isNotNull);
      expect(queue!.startPositionMs, isNull,
          reason: 'resume==false → 不带起始位置从头播');
      expect(queue.currentIndex, 1);
      expect(store.containsKey((1, '/Music/sun.mp3')), isFalse,
          reason: 'S10① false 分支：clearProgressProvider 已删除进度记录');
    });

    testWidgets('SRCH-01-S10: 点击时文件已消失（startIndex<0）→ SnackBar 该文件已不存在且不导航不建队',
        (tester) async {
      final tree = _SearchTree()
        ..put('/', [testDir('Music', '/Music')])
        ..put('/Music', [
          testAudio('other.mp3', '/Music/other.mp3'),
          testAudio('sun.mp3', '/Music/sun.mp3'),
        ]);
      final (container, _) = await _pumpBrowser(tester, tree: tree);

      await _openPanel(tester);
      await _query(tester, 'sun');
      await tester.pumpAndSettle();

      tree.put('/Music', [testAudio('other.mp3', '/Music/other.mp3')]);
      // ref.read 缓存语义（spec S10② 镜像 _collectFolder）：删除要经重新
      // fetch 才对收集可见——invalidate 等价于「点击与收集之间缓存已过期/
      // 用户下拉刷新过」的真实时序。
      container.invalidate(directoryContentsProvider('/Music'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      await tester.tap(find.text('sun.mp3'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pumpAndSettle();

      expect(find.textContaining('该文件已不存在'), findsOneWidget);
      expect(find.text('Player'), findsNothing, reason: '不导航');
      expect(container.read(currentPlayQueueProvider), isNull, reason: '不建队');
      expect(container.read(playModeProvider), PlayMode.sequential);
    });

    testWidgets('SRCH-01-S10: collectFolderAudio 整体失败 → 固定文案 SnackBar 且不写队列不导航',
        (tester) async {
      final tree = _SearchTree()
        ..put('/', [testDir('Music', '/Music')])
        ..put('/Music', [testAudio('sun.mp3', '/Music/sun.mp3')]);
      final (container, _) = await _pumpBrowser(tester, tree: tree);

      await _openPanel(tester);
      await _query(tester, 'sun');
      await tester.pumpAndSettle();

      tree.fail('/Music', const WebDavException('没有活跃的连接'));
      // 同上：失败注入需经重新 fetch 才进入 collect 路径。
      container.invalidate(directoryContentsProvider('/Music'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      await tester.tap(find.text('sun.mp3'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pumpAndSettle();

      expect(find.text('无法读取文件夹内容，请检查连接'), findsOneWidget,
          reason: 'catch-log 裁决：固定文案脱敏');
      expect(find.textContaining('没有活跃的连接'), findsNothing,
          reason: '否定断言：WebDAV 异常原文不得直接展示');
      expect(find.text('Player'), findsNothing);
      expect(container.read(currentPlayQueueProvider), isNull);
      expect(container.read(lastQueueConnectionIdProvider), isNull);
    });

    testWidgets(
        'SRCH-01-S11: 有队列+playing=true 点音符 → insert 收到命中 NasFile 并提示已加入下一曲',
        (tester) async {
      final tree = _SearchTree()
        ..put('/', [testAudio('queue_s.mp3', '/queue_s.mp3')]);
      final insertCalls = <NasFile>[];
      final preset = PlayQueue(
        files: [testAudio('cur.mp3', '/cur.mp3')],
        currentIndex: 0,
      );
      final (container, controller) = await _pumpBrowser(
        tester,
        tree: tree,
        extra: [
          currentPlayQueueProvider.overrideWith((ref) => preset),
          insertAfterCurrentProvider.overrideWithValue((NasFile f) async {
            insertCalls.add(f);
            return true;
          }),
        ],
      );

      controller.add(true);
      await tester.pumpAndSettle();
      await _openPanel(tester);
      await _query(tester, 'que');
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.queue_music));
      await tester.pumpAndSettle();

      expect(insertCalls.single.path, '/queue_s.mp3',
          reason: 'insertAfterCurrent 收到的就是命中的 NasFile');
      expect(find.textContaining('已加入下一曲：queue_s.mp3'), findsOneWidget);
      expect(
          identical(container.read(currentPlayQueueProvider), preset), isTrue,
          reason: '插队不改写队列 provider 本体，不打断当前曲');
    });

    testWidgets('SRCH-01-S11: 无队列时音符按钮 onPressed==null 置灰点击无反应',
        (tester) async {
      final tree = _SearchTree()
        ..put('/', [testAudio('queue_s.mp3', '/queue_s.mp3')]);
      await _pumpBrowser(tester, tree: tree);

      await _openPanel(tester);
      await _query(tester, 'que');
      await tester.pumpAndSettle();

      final btn = tester.widget<IconButton>(find.ancestor(
          of: find.byIcon(Icons.queue_music),
          matching: find.byType(IconButton)));
      expect(btn.onPressed, isNull,
          reason: '否定断言：disabled 态 onPressed 为 null 而非弹提示');
      if (btn.tooltip != null) {
        expect(btn.tooltip, contains('请先开始播放后再用此功能'));
      }

      await tester.tap(find.byIcon(Icons.queue_music));
      await tester.pumpAndSettle();
      expect(find.textContaining('已加入下一曲'), findsNothing);
    });

    testWidgets('SRCH-01-S11: 防御分支——enabled 但返回 false → 提示请先开始播放',
        (tester) async {
      final tree = _SearchTree()
        ..put('/', [testAudio('queue_s.mp3', '/queue_s.mp3')]);
      final preset = PlayQueue(
        files: [testAudio('cur.mp3', '/cur.mp3')],
        currentIndex: 0,
      );
      final (_, controller) = await _pumpBrowser(
        tester,
        tree: tree,
        extra: [
          currentPlayQueueProvider.overrideWith((ref) => preset),
          insertAfterCurrentProvider
              .overrideWithValue((NasFile f) async => false),
        ],
      );

      controller.add(true);
      await tester.pumpAndSettle();
      await _openPanel(tester);
      await _query(tester, 'que');
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.queue_music));
      await tester.pumpAndSettle();

      expect(find.textContaining('请先开始播放后再用此功能'), findsOneWidget);
      expect(find.textContaining('已加入下一曲'), findsNothing);
    });

    testWidgets('SRCH-01-S7: 连接切换 → 面板全清复位且进行中扫描订阅被取消', (tester) async {
      final tree = _SearchTree()
        ..put('/', <NasFile>[])
        ..hold('/');
      final (player, controller) = _makePlayer();
      final connIdHolder = StateProvider<int>((ref) => 1);
      await tester.pumpWidget(buildTestAppWithPlayerRoute(
        Scaffold(body: BrowserScreen()),
        overrides: [
          tree.override,
          tree.webDavOverride,
          tree.scanStorageOverride,
          activeConnectionProvider.overrideWith((ref) async {
            final id = ref.watch(connIdHolder);
            return testConnection(id: id);
          }),
          progressDaoProvider.overrideWithValue(_MapProgressDao(const {})),
          audioPlayerProvider.overrideWithValue(player),
          playModeProvider.overrideWith((ref) => PlayMode.sequential),
        ],
      ));
      addTearDown(controller.close);
      await tester.pumpAndSettle();
      final container =
          ProviderScope.containerOf(tester.element(find.byType(BrowserScreen)));

      await _openPanel(tester);
      await _typeOnly(tester, 'zzz');
      await tester.pump(const Duration(milliseconds: 600));
      expect(container.read(searchSessionProvider).running, isTrue,
          reason: '前置：扫描已启动且挂起在首层 fetch');

      // 切换活跃连接 id → browser_screen 的 ref.listen 触发 closePanel 全清。
      container.read(connIdHolder.notifier).state = 2;
      await tester.pumpAndSettle();

      var s = container.read(searchSessionProvider);
      expect(s.panelOpen, isFalse, reason: '连接切换必须收起面板（U9：回到普通浏览）');
      expect(s.hits, isEmpty, reason: '否定断言：连接切换分支 dirsScanned/hits 全清');
      expect(s.dirsScanned, 0);
      expect(s.running, isFalse);
      expect(s.truncated, isFalse);
      expect(s.skippedDirs, 0);
      expect(s.query, '');

      // 迟到数据补齐所有挂起 fetch——订阅已随 closePanel 取消，整体忽略。
      for (final c in List.of(tree.heldFutures)) {
        c.complete([testAudio('late_after_switch.mp3', '/late.mp3')]);
      }
      await tester.pump(const Duration(milliseconds: 100));
      s = container.read(searchSessionProvider);
      expect(s.hits, isEmpty, reason: '否定断言：切换后迟到的命中零残留（sub 已取消）');
    });

    testWidgets('SRCH-01-INV4: kSearchMaxDirs==200 且截断文案引用常量而非手写 200',
        (tester) async {
      expect(kSearchMaxDirs, 200);
      final tree = _wideTree();
      await _pumpBrowser(tester, tree: tree, extra: [navRoot('/w')]);

      await _openPanel(tester);
      await _query(tester, 'w');
      await tester.pumpAndSettle();

      expect(find.textContaining(RegExp('已扫描前\\s*$kSearchMaxDirs\\s*个目录')),
          findsOneWidget,
          reason: 'UI 文案由域层常量拼出，expect 中不出现手写 200');
    });
  });
}
