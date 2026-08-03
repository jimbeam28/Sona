// test/features/playlist/bug_bug25_repro_test.dart
// BUG-25: 播放单健壮性（LIST3 + LIST5 + LIST6 + LIST7 + LIST8）— spec §5.4
// 门禁测试.
//
// 复核背景：3d6bc26 落地了 LIST5（全选 whereType<int>）与 LIST7
// （showDialog 前 mounted 检查）；LIST3（importPlaylist 健壮性）与 LIST1
// 相关排序修复夹带在 596a63b；LIST6（fire-and-forget 错误处理）与 LIST8
// （对话框 controller dispose）缺失，本次复核补齐。本套件守护全部 S/INV：
//
// BUG-25-S1-T01: 顶层为数组 → FormatException（非 TypeError）+ 不留孤儿单
// BUG-25-S1-T02: track 元素非 Map → 跳过，不抛 NoSuchMethodError，正常建单
// BUG-25-S1-T03: name/filePath/fileName 非字符串 → is 检查兜底，不抛 TypeError
// BUG-25-S1-T04: tracks 非数组 → 按空列表处理（spec 边界裁决），不抛异常
// BUG-25-S1-T05: 非法 JSON → FormatException（回归）+ 不留孤儿单
// BUG-25-S1-T06: 合法 JSON 正常导入行为不变（回归 + 去重 + 顺序）
// BUG-25-S2-T01: 含 null id 曲目全选 → 跳过 null id 项不崩溃（LIST5 第三入口）
// BUG-25-S2-T02: 全部 id 非空的全选行为不变
// BUG-25-S3-T01: 滑动删单 DB 失败 → SnackBar + 日志，不静默（playlist_list_screen）
// BUG-25-S3-T02: 添加曲目 DB 失败 → SnackBar + 日志，弹窗不关（add_tracks_browser）
// BUG-25-S4-T01: progress future 完成后页面已退出 → 不在 defunct context 弹框
// BUG-25-S4-T02: mounted 为 true 时正常弹进度恢复对话框（行为不变）
// BUG-25-S5-T01: 新建对话框关闭后 TextEditingController 被 dispose
// BUG-25-S5-T02: 重命名对话框关闭后 TextEditingController 被 dispose
//
// 否定断言（对应 spec §3.1）：
//   - S1: 不抛 TypeError/NoSuchMethodError；解析失败不残留孤儿播放单
//   - S2: 全选不抛 Null check operator error
//   - S3: DB 失败不产生 unhandled Future rejection、不停留无反馈
//   - S4: 不在 widget 卸载后调用 showDialog
//   - S5: 对话框关闭后不保留 controller

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:nas_audio_player/features/browser/browser_provider.dart';
import 'package:nas_audio_player/features/connection/connection_provider.dart';
import 'package:nas_audio_player/features/playlist/domain/playlist_service.dart';
import 'package:nas_audio_player/features/playlist/playlist_detail_screen.dart';
import 'package:nas_audio_player/features/playlist/playlist_list_screen.dart';
import 'package:nas_audio_player/features/playlist/playlist_provider.dart';
import 'package:nas_audio_player/features/progress/progress_provider.dart';
import 'package:nas_audio_player/shared/models/connection_config.dart';
import 'package:nas_audio_player/shared/models/nas_file.dart';
import 'package:nas_audio_player/shared/models/play_progress.dart';
import 'package:nas_audio_player/shared/models/playlist.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../helpers/test_database.dart';
import '../../helpers/test_factories.dart';
import '../../helpers/widget_helpers.dart';

// ── Shared fixtures ─────────────────────────────────────────────────────────

final _now = DateTime(2026, 8, 4);

Playlist _playlist({int id = 1, String name = 'Test Playlist'}) => Playlist(
      id: id,
      name: name,
      trackCount: 0,
      createdAt: _now,
      updatedAt: _now,
    );

PlaylistTrack _track({
  int? id = 1,
  int playlistId = 1,
  required String filePath,
  required String fileName,
}) =>
    PlaylistTrack(
      id: id,
      playlistId: playlistId,
      filePath: filePath,
      fileName: fileName,
      addedAt: _now,
    );

final _conn = ConnectionConfig(
  id: 1,
  name: 'Test Conn',
  url: 'http://test.local',
  username: 'testuser',
  createdAt: _now,
  updatedAt: _now,
);

/// Captures everything written through [debugPrint] during [body].
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

void main() {
  // ═══════════════════════════════════════════════════════════════════════════
  // BUG-25-S1: importPlaylist JSON 健壮性 + 孤儿播放单消除（LIST3）
  // ═══════════════════════════════════════════════════════════════════════════

  group('BUG-25-S1: importPlaylist 健壮性', () {
    late Database db;
    late PlaylistService service;

    setUpAll(() {
      sqfliteFfiInit();
    });

    setUp(() async {
      db = await openTestDatabase(TestSchema.playlist);
      service = PlaylistService();
    });

    tearDown(() async {
      await db.close();
    });

    test('S1-T01: 顶层为数组 → FormatException（非 TypeError）+ 无孤儿单', () async {
      Object? caught;
      try {
        await service.importPlaylist('[1,2]');
      } catch (e) {
        caught = e;
      }
      expect(caught, isNotNull, reason: '结构错 JSON 必须抛异常');
      expect(caught, isA<FormatException>(), reason: '必须抛承诺的 FormatException');
      expect(caught, isNot(isA<TypeError>()), reason: '否定断言：不得抛原始 TypeError');
      expect(caught, isNot(isA<NoSuchMethodError>()),
          reason: '否定断言：不得抛原始 NoSuchMethodError');
      expect(await service.findAllPlaylists(), isEmpty,
          reason: '否定断言：解析失败不得残留孤儿播放单');
    });

    test('S1-T02: track 元素非 Map → 跳过不抛错，正常建单', () async {
      final id = await service.importPlaylist('{"name":"X","tracks":[1]}');
      expect(id, greaterThan(0));
      final playlists = await service.findAllPlaylists();
      expect(playlists.single.name, equals('X'));
      expect(await service.findTracksForPlaylist(id), isEmpty,
          reason: '非 Map track 元素被跳过 — 不得抛 NoSuchMethodError');
    });

    test('S1-T03: name/filePath/fileName 非字符串 → is 检查兜底不抛 TypeError', () async {
      final id = await service.importPlaylist('{"name":123,"tracks":['
          '{"filePath":"/a.mp3","fileName":"a.mp3"},'
          '{"filePath":1,"fileName":"bad-fp.mp3"},'
          '{"fileName":"no-fp.mp3"}'
          ']}');
      final playlists = await service.findAllPlaylists();
      expect(playlists.single.name, equals('导入的播放单'),
          reason: 'name 非字符串 → 默认名（不得抛 TypeError）');
      final tracks = await service.findTracksForPlaylist(id);
      expect(tracks, hasLength(1),
          reason: '仅合法 filePath 的 track 入库，其余 is 检查跳过');
      expect(tracks.single.filePath, equals('/a.mp3'));
      expect(tracks.single.fileName, equals('a.mp3'));
    });

    test('S1-T04: tracks 字段非数组 → 按空列表处理（spec 边界裁决）', () async {
      final id =
          await service.importPlaylist('{"name":"NoList","tracks":"oops"}');
      final playlists = await service.findAllPlaylists();
      expect(playlists.single.name, equals('NoList'));
      expect(await service.findTracksForPlaylist(id), isEmpty);
    });

    test('S1-T05: 非法 JSON → FormatException（回归）+ 无孤儿单', () async {
      await expectLater(
        service.importPlaylist('{not valid json}'),
        throwsA(isA<FormatException>()),
      );
      expect(await service.findAllPlaylists(), isEmpty);
    });

    test('S1-T06: 合法 JSON 正常导入行为不变（去重 + 顺序）', () async {
      final id = await service.importPlaylist('{"name":"Imported","tracks":['
          '{"filePath":"/a.mp3","fileName":"a.mp3"},'
          '{"filePath":"/a.mp3","fileName":"a.mp3"},'
          '{"filePath":"/b.mp3","fileName":"b.mp3"}'
          ']}');
      final playlists = await service.findAllPlaylists();
      expect(playlists.single.name, equals('Imported'));
      final tracks = await service.findTracksForPlaylist(id);
      expect(
          tracks.map((t) => t.filePath).toList(), equals(['/a.mp3', '/b.mp3']),
          reason: '去重生效且保持导入顺序（addedAt 单调）');
      expect(tracks.every((t) => t.playlistId == id), isTrue);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // BUG-25-S2: 全选按钮 null id 防御（LIST5 — BUG-08 漏掉的第三入口）
  // ═══════════════════════════════════════════════════════════════════════════

  group('BUG-25-S2: 全选 null id 防御', () {
    testWidgets('S2-T01: 含 null id 曲目全选 → 跳过 null id 项不崩溃', (tester) async {
      await tester.pumpWidget(buildTestAppWithPlayerRoute(
        const PlaylistDetailScreen(playlistId: 1),
        overrides: [
          playlistTracksProvider(1).overrideWith((ref) => Future.value([
                _track(id: 1, filePath: '/music/a.mp3', fileName: 'a.mp3'),
                _track(id: null, filePath: '/music/b.mp3', fileName: 'b.mp3'),
                _track(id: 2, filePath: '/music/c.mp3', fileName: 'c.mp3'),
              ])),
          playlistListProvider
              .overrideWith((ref) => Future.value([_playlist()])),
          // ListView 分支 — 与选择模式一致的渲染路径
          trackSortProvider.overrideWith((ref) => TrackSortOption.nameAsc),
        ],
      ));
      await tester.pumpAndSettle();

      // Long-press enters selection mode (the BUG-08-guarded entry).
      await tester.longPress(find.text('a.mp3'));
      await tester.pump();
      expect(find.text('已选 1 首'), findsOneWidget);

      // Pre-fix this tapped `tracks.map((t) => t.id!)` → "Null check operator
      // used on a null value" on the null-id track. Post-fix whereType<int>
      // filters it out.
      await tester.tap(find.byIcon(Icons.select_all));
      await tester.pump();
      expect(find.text('已选 2 首'), findsOneWidget,
          reason: 'null id 项必须被跳过，只选非空 id 曲目');
    });

    testWidgets('S2-T02: 全部 id 非空的全选行为不变', (tester) async {
      await tester.pumpWidget(buildTestAppWithPlayerRoute(
        const PlaylistDetailScreen(playlistId: 1),
        overrides: [
          playlistTracksProvider(1).overrideWith((ref) => Future.value([
                _track(id: 1, filePath: '/music/a.mp3', fileName: 'a.mp3'),
                _track(id: 2, filePath: '/music/b.mp3', fileName: 'b.mp3'),
                _track(id: 3, filePath: '/music/c.mp3', fileName: 'c.mp3'),
              ])),
          playlistListProvider
              .overrideWith((ref) => Future.value([_playlist()])),
          trackSortProvider.overrideWith((ref) => TrackSortOption.nameAsc),
        ],
      ));
      await tester.pumpAndSettle();

      await tester.longPress(find.text('a.mp3'));
      await tester.pump();
      await tester.tap(find.byIcon(Icons.select_all));
      await tester.pump();
      expect(find.text('已选 3 首'), findsOneWidget, reason: '否定断言：正常曲目全选行为不变');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // BUG-25-S3: fire-and-forget Future 补错误处理（LIST6）
  // ═══════════════════════════════════════════════════════════════════════════

  group('BUG-25-S3: 变更调用错误处理', () {
    testWidgets('S3-T01: 滑动删单 DB 失败 → SnackBar + 日志，不静默', (tester) async {
      final deletedIds = <int>[];
      await tester.pumpWidget(buildTestApp(
        const PlaylistListScreen(),
        overrides: [
          playlistListProvider.overrideWith(
              (ref) => Future.value([_playlist(name: 'Delete Me')])),
          deletePlaylistProvider.overrideWithValue((id) async {
            deletedIds.add(id);
            throw Exception('DB busy (SQLITE_BUSY)');
          }),
        ],
      ));
      await tester.pumpAndSettle();

      // Swipe left to reveal the delete action (ply_12 pattern).
      await tester.drag(find.text('Delete Me'), const Offset(-500, 0));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.delete_outline));
      await tester.pumpAndSettle();

      // Confirm in the dialog — the provider throws. Pre-fix the fire-and-
      // forget call became an unhandled Future rejection with zero feedback;
      // post-fix the user gets a SnackBar and the error is logged.
      final logs = await captureLogs(() async {
        await tester.tap(find.descendant(
            of: find.byType(AlertDialog), matching: find.text('删除')));
        await tester.pump();
        await tester.pumpAndSettle();
      });

      expect(deletedIds, equals([1]), reason: '删除调用必须真正发出');
      expect(find.textContaining('删除失败'), findsOneWidget,
          reason: 'DB 失败必须有可观测提示，不得静默');
      expect(
          logs.where((l) => l.contains('[Playlist] delete failed')), isNotEmpty,
          reason: '项目纪律：catch 必须记日志，不得静默吞错');
      expect(find.text('Delete Me'), findsOneWidget, reason: '删除失败后播放单仍在列表中');
    });

    testWidgets('S3-T02: 添加曲目 DB 失败 → SnackBar + 日志，弹窗不关', (tester) async {
      final addedFor = <int>[];
      await tester.pumpWidget(buildTestApp(
        const PlaylistDetailScreen(playlistId: 1),
        overrides: [
          playlistTracksProvider(1).overrideWith((ref) => Future.value([
                _track(id: 1, filePath: '/music/a.mp3', fileName: 'a.mp3'),
              ])),
          playlistListProvider
              .overrideWith((ref) => Future.value([_playlist()])),
          trackSortProvider.overrideWith((ref) => TrackSortOption.nameAsc),
          directoryContentsProvider('/').overrideWith((ref) => Future.value([
                const NasFile(
                    name: 'new.mp3',
                    path: '/music/new.mp3',
                    isDirectory: false),
              ])),
          addTracksToPlaylistProvider.overrideWithValue((pid, files) async {
            addedFor.add(pid);
            throw Exception('DB busy (SQLITE_BUSY)');
          }),
        ],
      ));
      await tester.pumpAndSettle();

      // Open the add-tracks bottom sheet and select the single audio file.
      await tester.tap(find.byIcon(Icons.add));
      await tester.pumpAndSettle();
      expect(find.text('添加曲目'), findsOneWidget);
      await tester.tap(find.text('new.mp3'));
      await tester.pump();
      expect(find.text('确认 (1)'), findsOneWidget);

      // Confirm — the provider throws. Pre-fix: unhandled rejection + the
      // sheet stayed open with no feedback. Post-fix: SnackBar + log, sheet
      // stays open for retry.
      final logs = await captureLogs(() async {
        await tester.tap(find.text('确认 (1)'));
        await tester.pump();
        await tester.pumpAndSettle();
      });

      expect(addedFor, equals([1]), reason: '添加调用必须真正发出');
      expect(find.textContaining('添加失败'), findsOneWidget,
          reason: 'DB 失败必须有可观测提示，不得静默');
      expect(logs.where((l) => l.contains('[Playlist] addTracks failed')),
          isNotEmpty,
          reason: '项目纪律：catchError 必须记日志，不得静默吞错');
      expect(find.text('确认 (1)'), findsOneWidget,
          reason: '失败时弹窗不得关闭（未调 Navigator.pop），用户可重试');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // BUG-25-S4: _playTrackAtIndex showDialog 前 mounted 检查（LIST7）
  // ═══════════════════════════════════════════════════════════════════════════

  group('BUG-25-S4: showDialog 前 mounted 检查', () {
    testWidgets('S4-T01: progress future 完成时页面已退出 → 不在 defunct context 弹框',
        (tester) async {
      final gate = Completer<PlayProgress?>();
      final container = ProviderContainer(overrides: [
        playlistTracksProvider(1).overrideWith((ref) => Future.value([
              _track(id: 1, filePath: '/music/p.mp3', fileName: 'p.mp3'),
            ])),
        playlistListProvider.overrideWith((ref) => Future.value([_playlist()])),
        trackSortProvider.overrideWith((ref) => TrackSortOption.nameAsc),
        activeConnectionProvider.overrideWith((ref) => Future.value(_conn)),
        progressForFileProvider((connectionId: 1, filePath: '/music/p.mp3'))
            .overrideWith((ref) => gate.future),
      ]);
      addTearDown(container.dispose);
      // Pre-heat so valueOrNull is populated when the track is tapped.
      await container.read(activeConnectionProvider.future);

      final router = GoRouter(
        initialLocation: '/',
        routes: [
          GoRoute(
            path: '/',
            builder: (context, __) => Scaffold(
              body: Center(
                child: Builder(
                  builder: (context) => ElevatedButton(
                    onPressed: () => context.push('/detail'),
                    child: const Text('进入页面'),
                  ),
                ),
              ),
            ),
          ),
          GoRoute(
            path: '/detail',
            builder: (_, __) => const PlaylistDetailScreen(playlistId: 1),
          ),
          GoRoute(
            path: '/player',
            builder: (_, __) =>
                const Scaffold(body: Center(child: Text('Player'))),
          ),
        ],
      );
      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(routerConfig: router),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('进入页面'));
      await tester.pumpAndSettle();
      expect(find.byType(PlaylistDetailScreen), findsOneWidget);

      // Tap the track — _playTrackAtIndex now suspends on the gated progress
      // future.
      await tester.tap(find.text('p.mp3'));
      await tester.pump();

      // Leave the page inside the await window.
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byType(PlaylistDetailScreen), findsNothing,
          reason: '页面应已退出并 dispose');

      // The future completes AFTER dispose. Pre-fix the continuation called
      // showProgressResumeDialog on the defunct context (throws); post-fix
      // `if (!context.mounted) return;` short-circuits it.
      gate.complete(testProgress(
          connectionId: 1, filePath: '/music/p.mp3', positionMs: 120000));
      await tester.pump();
      await tester.pumpAndSettle();

      expect(find.text('恢复播放进度'), findsNothing, reason: '页面已退出，对话框不得弹出');
      expect(find.text('Player'), findsNothing, reason: '不得继续进入播放页');
    });

    testWidgets('S4-T02: mounted 为 true 时正常弹进度恢复对话框（行为不变）', (tester) async {
      await tester.pumpWidget(buildTestAppWithPlayerRoute(
        const PlaylistDetailScreen(playlistId: 1),
        overrides: [
          playlistTracksProvider(1).overrideWith((ref) => Future.value([
                _track(id: 1, filePath: '/music/p.mp3', fileName: 'p.mp3'),
              ])),
          playlistListProvider
              .overrideWith((ref) => Future.value([_playlist()])),
          trackSortProvider.overrideWith((ref) => TrackSortOption.nameAsc),
          activeConnectionProvider.overrideWith((ref) => Future.value(_conn)),
          progressForFileProvider((connectionId: 1, filePath: '/music/p.mp3'))
              .overrideWith((ref) => Future.value(testProgress(
                  connectionId: 1,
                  filePath: '/music/p.mp3',
                  positionMs: 120000))),
        ],
      ));
      await tester.pumpAndSettle();

      // Pre-heat activeConnectionProvider so valueOrNull is populated.
      final container = ProviderScope.containerOf(
          tester.element(find.byType(PlaylistDetailScreen)));
      container.read(activeConnectionProvider);
      await tester.pump();

      await tester.tap(find.text('p.mp3'));
      await tester.pump();
      await tester.pump();
      await tester.pump();

      expect(find.text('恢复播放进度'), findsOneWidget,
          reason: '否定断言：mounted 检查不得阻断正常恢复流程');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // BUG-25-S5: 对话框 TextEditingController dispose（LIST8）
  // ═══════════════════════════════════════════════════════════════════════════
  //
  // Verification method: ChangeNotifier dispatches ObjectCreated /
  // ObjectDisposed events through MemoryAllocations (always on in debug).
  // The tests assert every TextEditingController created while a dialog opens
  // receives its ObjectDisposed event after the dialog closes.

  group('BUG-25-S5: 对话框 controller dispose', () {
    late List<TextEditingController> created;
    late List<TextEditingController> disposed;
    late ObjectEventListener listener;

    setUp(() {
      created = [];
      disposed = [];
      listener = (ObjectEvent event) {
        final object = event.object;
        if (object is! TextEditingController) return;
        if (event is ObjectCreated) created.add(object);
        if (event is ObjectDisposed) disposed.add(object);
      };
      FlutterMemoryAllocations.instance.addListener(listener);
    });

    tearDown(() {
      FlutterMemoryAllocations.instance.removeListener(listener);
    });

    testWidgets('S5-T01: 新建对话框关闭后 controller 被 dispose', (tester) async {
      await tester.pumpWidget(buildTestApp(
        const PlaylistListScreen(),
        overrides: [
          playlistListProvider
              .overrideWith((ref) => Future.value([_playlist()])),
        ],
      ));
      await tester.pumpAndSettle();

      final createdBefore = created.length;
      await tester.tap(find.byIcon(Icons.add));
      await tester.pumpAndSettle();
      expect(find.text('新建播放单'), findsOneWidget);

      final dialogControllers = created.skip(createdBefore).toList();
      expect(dialogControllers, isNotEmpty,
          reason: '对话框必须创建了 TextEditingController（测试前提）');

      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();

      for (final controller in dialogControllers) {
        expect(disposed, contains(controller),
            reason: '否定断言：对话框关闭后 controller 不得继续存活（泄漏）');
      }
    });

    testWidgets('S5-T02: 重命名对话框关闭后 controller 被 dispose', (tester) async {
      await tester.pumpWidget(buildTestAppWithPlayerRoute(
        const PlaylistDetailScreen(playlistId: 1),
        overrides: [
          playlistTracksProvider(1).overrideWith((ref) => Future.value([
                _track(id: 1, filePath: '/music/a.mp3', fileName: 'a.mp3'),
              ])),
          playlistListProvider
              .overrideWith((ref) => Future.value([_playlist()])),
          trackSortProvider.overrideWith((ref) => TrackSortOption.nameAsc),
        ],
      ));
      await tester.pumpAndSettle();

      final createdBefore = created.length;
      await tester.tap(find.byIcon(Icons.edit_outlined));
      await tester.pumpAndSettle();
      expect(find.text('重命名播放单'), findsOneWidget);

      final dialogControllers = created.skip(createdBefore).toList();
      expect(dialogControllers, isNotEmpty,
          reason: '对话框必须创建了 TextEditingController（测试前提）');

      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();

      for (final controller in dialogControllers) {
        expect(disposed, contains(controller),
            reason: '否定断言：对话框关闭后 controller 不得继续存活（泄漏）');
      }
    });
  });
}
