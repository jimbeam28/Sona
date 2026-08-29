import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nas_audio_player/core/database/dao/playlist_dao.dart';
import 'package:nas_audio_player/core/database/dao/progress_dao.dart';
import 'package:nas_audio_player/core/network/webdav_client.dart';
import 'package:nas_audio_player/features/browser/browser_provider.dart';
import 'package:nas_audio_player/features/browser/browser_screen.dart';
import 'package:nas_audio_player/features/browser/domain/folder_collector.dart';
import 'package:nas_audio_player/features/browser/widgets/file_list_item.dart';
import 'package:nas_audio_player/features/connection/connection_provider.dart';
import 'package:nas_audio_player/features/player/player_provider.dart';
import 'package:nas_audio_player/features/playlist/domain/playlist_service.dart'
    as playlist_domain;
import 'package:nas_audio_player/features/playlist/playlist_provider.dart';
import 'package:nas_audio_player/features/progress/progress_provider.dart';
import 'package:nas_audio_player/shared/models/connection_config.dart';
import 'package:nas_audio_player/shared/models/nas_file.dart';
import 'package:nas_audio_player/shared/models/play_progress.dart';
import 'package:nas_audio_player/shared/models/playlist.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/fake_secure_storage.dart';
import '../../helpers/mock_audio_player.dart';
import '../../helpers/test_factories.dart';
import '../../helpers/widget_helpers.dart';

final _now = DateTime(2026, 8, 23);

final _conn = ConnectionConfig(
  id: 1,
  name: 'NAS',
  url: 'http://nas.example.com',
  username: 'admin',
  isActive: true,
  createdAt: _now,
  updatedAt: _now,
);

Playlist _playlist({int id = 7, String name = 'Rock'}) => Playlist(
      id: id,
      name: name,
      trackCount: 0,
      createdAt: _now,
      updatedAt: _now,
    );

NasFile _aud(String name, String parent) => testAudio(name, '$parent/$name');

class _Tree {
  final Map<String, List<NasFile>> listings = {};
  final Map<String, Object> errors = {};
  final Map<String, Completer<List<NasFile>>> _gates = {};
  final List<String> calls = [];

  void put(String path, List<NasFile> entries) => listings[path] = entries;

  void fail(String path, Object error) => errors[path] = error;

  Completer<List<NasFile>> gate(String path) =>
      _gates.putIfAbsent(path, Completer<List<NasFile>>.new);

  Future<List<NasFile>> fetch(String path) async {
    calls.add(path);
    final pending = _gates[path];
    if (pending != null) return pending.future;
    final error = errors[path];
    if (error != null) throw error;
    return listings[path] ?? const <NasFile>[];
  }

  Override get override =>
      directoryContentsProvider.overrideWith((ref, path) => fetch(path));

  // BUG-33（cr F1）：扫描会话 fetchDir 改走 webDavClientProvider（不经缓存）——
  // 同一棵树经适配器供给 webDav 端口；主列表浏览仍走 directoryContentsProvider。
  Override get webDavOverride =>
      webDavClientProvider.overrideWithValue(_TreeScanDavClient(this));

  /// 扫描会话装配（BUG-33）：secureStorage 密码 + 活跃连接。
  Override get scanStorageOverride => secureStorageProvider
      .overrideWithValue(FakeSecureStorage()..setPassword(_conn.id ?? 1, 'pw'));
}

/// BUG-33：把 [Tree] 的 fetch 供给 WebDAV 端口（扫描直连路径）。
class _TreeScanDavClient implements WebDavClientInterface {
  _TreeScanDavClient(this._tree);
  final _Tree _tree;

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

class _NoProgressDao extends ProgressDao {
  @override
  Future<PlayProgress?> find(int connectionId, String filePath) async => null;

  @override
  Future<void> delete(int connectionId, String filePath) async {}
}

class _RecordingPlaylistService extends playlist_domain.PlaylistService {
  _RecordingPlaylistService() : super(dao: PlaylistDao());

  final createdNames = <String>[];
  int nextId = 42;

  @override
  Future<int> createPlaylist(String name) async {
    createdNames.add(name);
    return nextId;
  }
}

Future<List<Override>> _baseOverrides(_Tree tree) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  return [
    tree.override,
    tree.webDavOverride,
    tree.scanStorageOverride,
    activeConnectionProvider.overrideWith((ref) async => _conn),
    sharedPreferencesProvider.overrideWithValue(prefs),
    audioPlayerProvider.overrideWithValue(MockAudioPlayer()),
    progressDaoProvider.overrideWithValue(_NoProgressDao()),
  ];
}

Future<ProviderContainer> _pumpBrowser(
  WidgetTester tester,
  List<Override> overrides,
) async {
  await tester.pumpWidget(buildTestAppWithPlayerRoute(
    const Scaffold(body: BrowserScreen()),
    overrides: overrides,
  ));
  await tester.pumpAndSettle();
  return ProviderScope.containerOf(tester.element(find.byType(BrowserScreen)));
}

Future<void> _openFolderMenu(WidgetTester tester, String dirName) async {
  await tester.longPress(find.text(dirName));
  await tester.pumpAndSettle();
}

void main() {
  group('BRW-01 domain: collectFolderAudio', () {
    test('BRW-01-S1: 先序遍历保持每层顺序，目录与非音频条目不收录', () async {
      final tree = _Tree()
        ..put('/root', [
          _aud('B.mp3', '/root'),
          testDir('A', '/root/A'),
          const NasFile(
              name: 'note.txt', path: '/root/note.txt', isDirectory: false),
          _aud('C.mp3', '/root'),
        ])
        ..put('/root/A', [_aud('A1.mp3', '/root/A')]);

      final result =
          await collectFolderAudio(rootPath: '/root', fetchDir: tree.fetch);

      expect(result.files.map((f) => f.name).toList(),
          ['B.mp3', 'A1.mp3', 'C.mp3']);
      expect(result.truncated, isFalse);
      expect(result.files.every((f) => !f.isDirectory), isTrue,
          reason: '否定断言：目录条目不得出现在结果中');
      expect(result.files.every((f) => f.audioType != null), isTrue,
          reason: '否定断言：audioType == null 的文件不得出现');
      expect(result.files.map((f) => f.name), isNot(contains('note.txt')),
          reason: '否定断言：非音频文件 note.txt 不得收录');
      expect(tree.calls, ['/root', '/root/A'],
          reason: 'fetchDir 调用次序必须为 root → 子目录A（先序，非广度优先）');
      expect(tree.calls, hasLength(2));
    });

    test('BRW-01-S2: 收满即停，截断后不再发起多余 fetchDir 且不抛异常', () async {
      final tree = _Tree()
        ..put('/r', [testDir('A', '/r/A'), testDir('B', '/r/B')])
        ..put(
            '/r/A',
            List.generate(500,
                (i) => _aud('a${i.toString().padLeft(3, '0')}.mp3', '/r/A')))
        ..put(
            '/r/B',
            List.generate(100,
                (i) => _aud('b${i.toString().padLeft(3, '0')}.mp3', '/r/B')));

      final result =
          await collectFolderAudio(rootPath: '/r', fetchDir: tree.fetch);

      expect(result.files.length, equals(500));
      expect(result.files.length, lessThanOrEqualTo(kFolderScanMaxFiles));
      expect(result.truncated, isTrue);
      expect(tree.calls, ['/r', '/r/A'],
          reason: 'A 层收满 500 后必须停止，B 目录不得再发起 fetchDir');
      expect(tree.calls.contains('/r/B'), isFalse);
    });

    test('BRW-01-S3: 任一层 WebDavException 原样上抛，多层混合首层数据不泄漏', () async {
      final tree = _Tree()
        ..put('/r', [testDir('good', '/r/good'), testDir('bad', '/r/bad')])
        ..put('/r/good', [_aud('x.mp3', '/r/good')])
        ..fail('/r/bad', const WebDavException('没有活跃的连接'));

      await expectLater(
        collectFolderAudio(rootPath: '/r', fetchDir: tree.fetch),
        throwsA(isA<WebDavException>()
            .having((e) => e.message, 'message', '没有活跃的连接')),
      );
      expect(tree.calls, ['/r', '/r/good', '/r/bad']);

      final rootFail = _Tree()..fail('/only', const WebDavException('网络连接超时'));
      await expectLater(
        collectFolderAudio(rootPath: '/only', fetchDir: rootFail.fetch),
        throwsA(isA<WebDavException>()),
      );
    });

    test('BRW-01-ALG1 行1: root=[B.mp3, dirA(A1.mp3), C.mp3] → [B, A1, C]',
        () async {
      final tree = _Tree()
        ..put('/root', [
          _aud('B.mp3', '/root'),
          testDir('A', '/root/A'),
          _aud('C.mp3', '/root'),
        ])
        ..put('/root/A', [_aud('A1.mp3', '/root/A')]);

      final result =
          await collectFolderAudio(rootPath: '/root', fetchDir: tree.fetch);

      expect(result.files.map((f) => f.path).toList(),
          ['/root/B.mp3', '/root/A/A1.mp3', '/root/C.mp3']);
      expect(result.truncated, isFalse);
      expect(tree.calls, ['/root', '/root/A']);
    });

    test('BRW-01-ALG1 行2: root=[dirX(X.mp3), B.mp3] → [X, B]（严格先序）', () async {
      final tree = _Tree()
        ..put('/r', [testDir('X', '/r/X'), _aud('B.mp3', '/r')])
        ..put('/r/X', [_aud('X.mp3', '/r/X')]);

      final result =
          await collectFolderAudio(rootPath: '/r', fetchDir: tree.fetch);

      expect(
          result.files.map((f) => f.path).toList(), ['/r/X/X.mp3', '/r/B.mp3'],
          reason: '子目录内容必须先于同层后续音频——严格先序裁决');
      expect(result.truncated, isFalse);
      expect(tree.calls, ['/r', '/r/X']);
    });

    test('BRW-01-ALG1 行3: 600 音频扁平树 maxFiles=500 → 前 500 个按层序 truncated=true',
        () async {
      final tree = _Tree()
        ..put(
            '/flat',
            List.generate(600,
                (i) => _aud('f${i.toString().padLeft(3, '0')}.mp3', '/flat')));

      final result =
          await collectFolderAudio(rootPath: '/flat', fetchDir: tree.fetch);

      expect(result.files.length, equals(500));
      expect(result.truncated, isTrue);
      for (var i = 0; i < result.files.length; i++) {
        expect(result.files[i].path,
            equals('/flat/f${i.toString().padLeft(3, '0')}.mp3'));
      }
      expect(tree.calls, ['/flat']);
    });

    test('BRW-01-ALG1 行4: root 仅含空目录 → [] truncated=false', () async {
      final tree = _Tree()
        ..put('/', [testDir('empty', '/empty')])
        ..put('/empty', <NasFile>[]);

      final result =
          await collectFolderAudio(rootPath: '/', fetchDir: tree.fetch);

      expect(result.files, isEmpty);
      expect(result.truncated, isFalse);
      expect(tree.calls, ['/', '/empty']);
    });

    test('BRW-01-ALG1 行5: root=[note.txt, dirA] → note.txt 不收录', () async {
      final tree = _Tree()
        ..put('/', [
          const NasFile(
              name: 'note.txt', path: '/note.txt', isDirectory: false),
          testDir('A', '/A'),
        ])
        ..put('/A', <NasFile>[]);

      final result =
          await collectFolderAudio(rootPath: '/', fetchDir: tree.fetch);

      expect(result.files, isEmpty,
          reason: 'audioType == null 的 note.txt 不得收录');
      expect(result.truncated, isFalse);
    });

    test('BRW-01-ALG1 行6: 第 2 层 fetchDir 抛 WebDavException → 异常上抛无结果',
        () async {
      final tree = _Tree()
        ..put('/', [testDir('bad', '/bad')])
        ..fail('/bad', const WebDavException('第 2 层失败'));

      await expectLater(
        collectFolderAudio(rootPath: '/', fetchDir: tree.fetch),
        throwsA(isA<WebDavException>()
            .having((e) => e.message, 'message', '第 2 层失败')),
      );
      expect(tree.calls, ['/', '/bad']);
    });

    test('BRW-01-INV2: folder_collector.dart 纯遍历编排，零 Flutter/http/riverpod 依赖',
        () async {
      final src = await File(
              '${Directory.current.path}/lib/features/browser/domain/folder_collector.dart')
          .readAsString();
      expect(src.contains('package:flutter/'), isFalse,
          reason: 'INV2：domain 层不得依赖 Flutter');
      expect(src.contains('package:http'), isFalse,
          reason: 'INV2：一切 IO 经 fetchDir 注入，不得直连 http');
      expect(src.contains('riverpod'), isFalse,
          reason: 'INV2：纯 Dart 编排不得依赖 riverpod');
    });

    test('BRW-01-INV4: kFolderScanMaxFiles == 500 常量唯一来源', () {
      expect(kFolderScanMaxFiles, equals(500));
    });
  });

  group('BRW-01 di 导出登记', () {
    test('BRW-01-S9: lib/shared/di/providers.dart 含 playlistServiceProvider 导出',
        () async {
      final src =
          await File('${Directory.current.path}/lib/shared/di/providers.dart')
              .readAsString();
      expect(src.contains('playlistServiceProvider'), isTrue,
          reason: 'S9：di show 清单必须补导出 playlistServiceProvider');
    });
  });

  group('BRW-01 widget: 目录长按菜单与两条流程', () {
    testWidgets('BRW-01-S4: 长按目录行弹出「从此处播放」「加入播放单…」，文件长按路径不受扰', (tester) async {
      final tree = _Tree()
        ..put('/', [
          testDir('Music', '/Music'),
          testAudio('top.mp3', '/top.mp3'),
        ]);

      await _pumpBrowser(tester, await _baseOverrides(tree));

      await _openFolderMenu(tester, 'Music');

      expect(find.text('从此处播放'), findsOneWidget);
      expect(find.text('加入播放单…'), findsOneWidget);
      expect(find.byIcon(Icons.play_circle_outline), findsOneWidget);
      expect(find.byIcon(Icons.playlist_add), findsOneWidget);

      final tile =
          tester.widget<DirectoryListTile>(find.byType(DirectoryListTile));
      expect(tile.onLongPress, isNotNull,
          reason: 'BrowserScreen 必须把目录长按回调接线到 DirectoryListTile');

      await tester.tapAt(const Offset(20, 20));
      await tester.pumpAndSettle();
      expect(find.text('从此处播放'), findsNothing);

      await tester.longPress(find.text('top.mp3'));
      await tester.pumpAndSettle();
      expect(find.text('从此处播放'), findsNothing,
          reason: '文件长按（进度恢复路径）不得出现文件夹菜单项');
    });

    testWidgets('BRW-01-S4 否定面: 目录行 onTap 进子目录行为不变', (tester) async {
      final tree = _Tree()
        ..put('/', [testDir('Music', '/Music')])
        ..put('/Music', [testAudio('inner.mp3', '/Music/inner.mp3')]);

      await _pumpBrowser(tester, await _baseOverrides(tree));

      await tester.tap(find.text('Music'));
      await tester.pumpAndSettle();

      expect(find.text('inner.mp3'), findsOneWidget,
          reason: '目录行点击仍进入子目录渲染其内容');
      expect(find.text('从此处播放'), findsNothing, reason: '普通点击不得触发文件夹菜单');
    });

    testWidgets('BRW-01-S4 否定面: DirectoryListTile 无 onLongPress 时长按无响应',
        (tester) async {
      var taps = 0;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: DirectoryListTile(
            file: testDir('D', '/D'),
            onTap: (file) => taps++,
          ),
        ),
      ));
      await tester.pumpAndSettle();

      await tester.longPress(find.text('D'));
      await tester.pumpAndSettle();

      expect(taps, 0, reason: '长按不得误触 onTap');
      expect(find.text('从此处播放'), findsNothing);
      expect(find.byType(BottomSheet), findsNothing);
      expect(find.byType(Dialog), findsNothing);
    });

    testWidgets('BRW-01-S5: 从此处播放 → loading 出现并消失 → 写队列/连接 id 并进播放器',
        (tester) async {
      final tree = _Tree()
        ..put('/', [testDir('Music', '/Music')])
        ..gate('/Music');
      final overrides = await _baseOverrides(tree);

      final container = await _pumpBrowser(tester, overrides);
      expect(container.read(currentPlayQueueProvider), isNull);

      await _openFolderMenu(tester, 'Music');
      await tester.tap(find.text('从此处播放'));
      await tester.pump();

      expect(find.text('正在扫描文件夹…'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      tree.gate('/Music').complete([
        testAudio('a.mp3', '/Music/a.mp3'),
        testAudio('b.mp3', '/Music/b.mp3'),
      ]);
      await tester.pumpAndSettle();

      expect(find.text('Player'), findsOneWidget, reason: '成功后必须 push /player');
      expect(tree.calls, ['/', '/Music']);

      final queue = container.read(currentPlayQueueProvider);
      expect(queue, isNotNull);
      expect(queue!.files.map((f) => f.path).toList(),
          ['/Music/a.mp3', '/Music/b.mp3'],
          reason: '队列必须等于收集结果');
      expect(queue.currentIndex, equals(0));
      expect(container.read(lastQueueConnectionIdProvider), equals(_conn.id));

      expect(find.byType(Dialog), findsNothing, reason: 'loading 对话框必须关闭');
      expect(find.text('正在扫描文件夹…'), findsNothing);
      expect(find.text('恢复播放进度'), findsNothing, reason: '否定断言：文件夹入口不得弹进度恢复对话框');
      expect(find.textContaining('已截取'), findsNothing);
    });

    testWidgets('BRW-01-S5: 超过上限截断 → SnackBar 提示 500 且队列只有 500 首',
        (tester) async {
      final tree = _Tree()
        ..put('/', [testDir('Big', '/Big')])
        ..put(
            '/Big',
            List.generate(
                600,
                (i) => testAudio('f${i.toString().padLeft(3, '0')}.mp3',
                    '/Big/f${i.toString().padLeft(3, '0')}.mp3')));
      final overrides = await _baseOverrides(tree);

      final container = await _pumpBrowser(tester, overrides);

      await _openFolderMenu(tester, 'Big');
      await tester.tap(find.text('从此处播放'));
      await tester.pumpAndSettle();

      expect(find.text('Player'), findsOneWidget);
      expect(find.textContaining('已截取前 500 首'), findsOneWidget,
          reason: 'truncated == true 必须提示截取上限');

      final queue = container.read(currentPlayQueueProvider);
      expect(queue, isNotNull);
      expect(queue!.files.length, equals(500));
      expect(queue.files.first.path, equals('/Big/f000.mp3'));
      expect(queue.files.last.path, equals('/Big/f499.mp3'));
    });

    testWidgets('BRW-01-S5 否定面: 空收集结果 → SnackBar 提示且不建队不导航', (tester) async {
      final tree = _Tree()
        ..put('/', [testDir('Empty', '/Empty')])
        ..put('/Empty', <NasFile>[]);
      final overrides = await _baseOverrides(tree);

      final container = await _pumpBrowser(tester, overrides);

      await _openFolderMenu(tester, 'Empty');
      await tester.tap(find.text('从此处播放'));
      await tester.pumpAndSettle();

      expect(find.text('该文件夹没有音频文件'), findsOneWidget);
      expect(find.text('Player'), findsNothing, reason: '空结果不得进入播放器');
      expect(container.read(currentPlayQueueProvider), isNull,
          reason: '空结果不得建队');
      expect(container.read(lastQueueConnectionIdProvider), isNull);
      expect(find.byType(Dialog), findsNothing);
    });

    testWidgets('BRW-01-S6: 扫描中途失败 → 固定文案 SnackBar、loading 无残留、不导航不建队',
        (tester) async {
      final tree = _Tree()
        ..put('/', [testDir('Music', '/Music')])
        ..gate('/Music');
      final overrides = await _baseOverrides(tree);

      final container = await _pumpBrowser(tester, overrides);

      await _openFolderMenu(tester, 'Music');
      await tester.tap(find.text('从此处播放'));
      await tester.pump();
      expect(find.byType(Dialog), findsOneWidget, reason: '前置：loading 对话框在弹');

      tree.gate('/Music').completeError(const WebDavException('没有活跃的连接'));
      await tester.pumpAndSettle();

      expect(find.text('无法读取文件夹内容，请检查连接'), findsOneWidget,
          reason: '失败反馈必须是固定文案，不得把原始异常给用户');
      expect(find.text('没有活跃的连接'), findsNothing,
          reason: '脱敏纪律：WebDAV 异常原文不得直接展示');
      expect(find.byType(Dialog), findsNothing, reason: 'catch 分支同样要关 loading');
      expect(find.byType(CircularProgressIndicator), findsNothing,
          reason: 'loading 无残留遮罩');
      expect(find.text('Player'), findsNothing, reason: '失败不得 push /player');
      expect(container.read(currentPlayQueueProvider), isNull,
          reason: '失败路径下 currentPlayQueueProvider 不得被写');
      expect(container.read(lastQueueConnectionIdProvider), isNull,
          reason: '失败路径下 lastQueueConnectionIdProvider 不得被写');
    });

    testWidgets('BRW-01-INV3: 文件夹入口产生的队列 startPositionMs 恒为 null',
        (tester) async {
      final tree = _Tree()
        ..put('/', [testDir('Music', '/Music')])
        ..put('/Music', [testAudio('only.mp3', '/Music/only.mp3')]);
      final overrides = await _baseOverrides(tree);

      final container = await _pumpBrowser(tester, overrides);

      await _openFolderMenu(tester, 'Music');
      await tester.tap(find.text('从此处播放'));
      await tester.pumpAndSettle();

      final queue = container.read(currentPlayQueueProvider);
      expect(queue, isNotNull);
      expect(queue!.startPositionMs, isNull);
      expect(queue.toMap()['startPositionMs'], isNull,
          reason: 'INV3：toMap 序列化层面 startPositionMs 也必须为 null（从第一首开头播）');
      expect(find.text('恢复播放进度'), findsNothing);
    });

    testWidgets('BRW-01-S7: 扫描后选择已有播放单 → addTracks 收到 (id, files) 并提示已添加 N 首',
        (tester) async {
      final tree = _Tree()
        ..put('/', [testDir('Music', '/Music')])
        ..put('/Music', [
          testAudio('a.mp3', '/Music/a.mp3'),
          testAudio('b.mp3', '/Music/b.mp3'),
        ]);
      final overrides = await _baseOverrides(tree);

      int? capturedPlaylistId;
      List<NasFile>? capturedFiles;
      overrides.addAll([
        playlistListProvider.overrideWith(
            (ref) => Future.value([_playlist(id: 7, name: 'Rock')])),
        addTracksToPlaylistProvider.overrideWith((ref) => (playlistId, files) {
              capturedPlaylistId = playlistId;
              capturedFiles = List.of(files);
              return Future.value();
            }),
      ]);

      await _pumpBrowser(tester, overrides);

      await _openFolderMenu(tester, 'Music');
      await tester.tap(find.text('加入播放单…'));
      await tester.pumpAndSettle();

      expect(find.text('Rock'), findsOneWidget, reason: '第二面板必须列出既有播放单');

      await tester.tap(find.text('Rock'));
      await tester.pumpAndSettle();

      expect(capturedPlaylistId, equals(7));
      expect(capturedFiles!.map((f) => f.path).toList(),
          ['/Music/a.mp3', '/Music/b.mp3']);
      expect(find.text('已添加 2 首'), findsOneWidget);
      expect(find.text('Rock'), findsNothing, reason: '全部面板应关闭');
      expect(find.byType(BottomSheet), findsNothing);
    });

    testWidgets('BRW-01-S7: playlistListProvider error 态 → 错误渲染且新建入口可用',
        (tester) async {
      final tree = _Tree()
        ..put('/', [testDir('Music', '/Music')])
        ..put('/Music', [testAudio('a.mp3', '/Music/a.mp3')]);
      final overrides = await _baseOverrides(tree);

      overrides.addAll([
        playlistListProvider.overrideWith((ref) async {
          throw Exception('数据库锁住');
        }),
        addTracksToPlaylistProvider.overrideWith((ref) => (playlistId, files) {
              return Future.value();
            }),
      ]);

      await _pumpBrowser(tester, overrides);

      await _openFolderMenu(tester, 'Music');
      await tester.tap(find.text('加入播放单…'));
      await tester.pumpAndSettle();

      expect(find.text('Rock'), findsNothing, reason: 'error 态不得渲染数据列表');
      expect(find.text('还没有播放单'), findsNothing, reason: 'error 态不得误显示空列表文案');
      expect(find.text('新建播放单'), findsOneWidget, reason: 'error 态下新建入口仍可用');
    });

    testWidgets('BRW-01-S7 否定面: 播放单列表为空 → 「还没有播放单」+ 新建入口可用', (tester) async {
      final tree = _Tree()
        ..put('/', [testDir('Music', '/Music')])
        ..put('/Music', [testAudio('a.mp3', '/Music/a.mp3')]);
      final overrides = await _baseOverrides(tree);

      overrides.addAll([
        playlistListProvider.overrideWith((ref) => Future.value(<Playlist>[])),
        addTracksToPlaylistProvider.overrideWith((ref) => (playlistId, files) {
              return Future.value();
            }),
      ]);

      await _pumpBrowser(tester, overrides);

      await _openFolderMenu(tester, 'Music');
      await tester.tap(find.text('加入播放单…'));
      await tester.pumpAndSettle();

      expect(find.text('还没有播放单'), findsOneWidget);
      expect(find.text('新建播放单'), findsOneWidget);
    });

    testWidgets('BRW-01-S8: 新建即加入 —— 空名禁用确认，service 直连取新 id 加入',
        (tester) async {
      final tree = _Tree()
        ..put('/', [testDir('Music', '/Music')])
        ..put('/Music', [
          testAudio('a.mp3', '/Music/a.mp3'),
          testAudio('b.mp3', '/Music/b.mp3'),
        ]);
      final overrides = await _baseOverrides(tree);

      final service = _RecordingPlaylistService();
      var createProviderCalled = false;
      int? capturedPlaylistId;
      List<NasFile>? capturedFiles;
      overrides.addAll([
        playlistListProvider.overrideWith((ref) => Future.value(<Playlist>[])),
        playlistServiceProvider.overrideWithValue(service),
        createPlaylistProvider.overrideWith((ref) => (String name) async {
              createProviderCalled = true;
            }),
        addTracksToPlaylistProvider.overrideWith((ref) => (playlistId, files) {
              capturedPlaylistId = playlistId;
              capturedFiles = List.of(files);
              return Future.value();
            }),
      ]);

      await _pumpBrowser(tester, overrides);

      await _openFolderMenu(tester, 'Music');
      await tester.tap(find.text('加入播放单…'));
      await tester.pumpAndSettle();
      expect(find.text('还没有播放单'), findsOneWidget);

      await tester.tap(find.text('新建播放单'));
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsOneWidget);

      final confirmFinder = find.ancestor(
          of: find.text('创建'),
          matching: find.byWidgetPredicate((w) => w is ButtonStyleButton));
      expect(confirmFinder, findsOneWidget);
      expect(tester.widget<ButtonStyleButton>(confirmFinder).onPressed, isNull,
          reason: '输入 trim 后为空串时确认按钮必须禁用');

      await tester.tap(find.text('创建'));
      await tester.pump();
      expect(service.createdNames, isEmpty, reason: '空名确认不得调用 createPlaylist');
      expect(createProviderCalled, isFalse);
      expect(find.byType(TextField), findsOneWidget, reason: '对话框保持打开');

      await tester.enterText(find.byType(TextField), ' My Mix ');
      await tester.pump();
      await tester.tap(find.text('创建'));
      await tester.pumpAndSettle();

      expect(service.createdNames, [' My Mix '],
          reason: 'createPlaylist 必须经 service 直连被调；名称仅做空串校验，前后空格原样入库（REF-07）');
      expect(capturedPlaylistId, equals(42),
          reason: 'addTracks 必须收到 service 返回的新 id');
      expect(capturedFiles!.map((f) => f.path).toList(),
          ['/Music/a.mp3', '/Music/b.mp3']);
      expect(find.text('已添加 2 首'), findsOneWidget);
      expect(find.byType(TextField), findsNothing, reason: '对话框应关闭');
      expect(find.text('还没有播放单'), findsNothing, reason: '面板应关闭');
      expect(createProviderCalled, isFalse,
          reason: '否定断言：不得使用丢 id 的 createPlaylistProvider');
    });
  });
}
