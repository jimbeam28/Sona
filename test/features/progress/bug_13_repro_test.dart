// test/features/progress/bug_13_repro_test.dart
// BUG-13 门禁测试（来源：docs/cr/cr-20260724-0110.md PRG3；spec：docs/features/BUG-13.md）
//
// 注意编号：test/core/bug_13_repro_test.dart 是 cr 走查编号体系的 NET1
// （basePath 约定），与本文件不同源——本文件对应 docs/features/BUG-13.md。
//
// 缺陷：progress_dialog.dart 注释声明"从头播放 — delete the progress record"，
// 但两个调用方（browser_screen.dart onFileTap / playlist_detail_screen.dart
// _playTrackAtIndex）只消费对话框返回值、不删记录。选"从头播放"后短期退出再进，
// 旧进度仍在（periodic 保存被 shouldSave<5000 跳过不覆盖）→ 对话框反复弹出。
//
// 修复：两调用方的 resume == false 分支经 clearProgressProvider 删除
// (connectionId, filePath) 精确匹配的单条记录（spec §3.1 BUG-13-S1）。
//
// 本测试走真实生产链路（BrowserScreen / PlaylistDetailScreen → 真实对话框 →
// 调用方 resume == false 分支 → clearProgressProvider → ProgressService →
// ProgressDao），仅叶子 DAO 注入内存 fake（sqflite_ffi 的 Future 在
// testWidgets FakeAsync 区不完成，widget 测试经叶子注入 fake 是项目标准做法，
// 同 bug_12_repro_test.dart）。
//
// 覆盖 BUG-13-S1 全部断言面：
//   正向：选"从头播放"→ F 的进度记录被删（两调用方各一条）；
//   否定：不清除其他文件的进度记录；选"继续播放"不删记录；
//         clear 失败静默继续、不阻塞播放流程；
//   边界裁决：对话框被非按钮方式关闭（resume == null）→ 从头播放但不删记录。
//
// 修复前 FAIL（记录未被删），修复后 PASS。

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nas_audio_player/core/database/dao/progress_dao.dart';
import 'package:nas_audio_player/features/browser/browser_provider.dart';
import 'package:nas_audio_player/features/browser/browser_screen.dart';
import 'package:nas_audio_player/features/connection/connection_provider.dart';
import 'package:nas_audio_player/features/playlist/playlist_detail_screen.dart';
import 'package:nas_audio_player/features/playlist/playlist_provider.dart';
import 'package:nas_audio_player/features/progress/progress_provider.dart';
import 'package:nas_audio_player/shared/models/connection_config.dart';
import 'package:nas_audio_player/shared/models/play_progress.dart';
import 'package:nas_audio_player/shared/models/playlist.dart';

import '../../helpers/test_factories.dart';
import '../../helpers/widget_helpers.dart';

// ── 叶子 fake：内存 store 的 ProgressDao（find/delete 纯微任务 Future）────────

class _FakeProgressDao extends ProgressDao {
  _FakeProgressDao(Map<String, PlayProgress> records)
      : _store = Map.of(records);

  final Map<String, PlayProgress> _store;

  static String _key(int connectionId, String filePath) =>
      '$connectionId:$filePath';

  @override
  Future<PlayProgress?> find(int connectionId, String filePath) async =>
      _store[_key(connectionId, filePath)];

  @override
  Future<void> delete(int connectionId, String filePath) async {
    _store.remove(_key(connectionId, filePath));
  }
}

/// delete 模拟 DB 异常——验证 spec 裁决"clear 失败静默继续，不阻塞播放"。
class _ThrowingDeleteDao extends _FakeProgressDao {
  _ThrowingDeleteDao(super.records);

  @override
  Future<void> delete(int connectionId, String filePath) async {
    throw StateError('simulated DB failure on delete');
  }
}

// ── 共享测试数据 ──────────────────────────────────────────────────────────────

final _conn = ConnectionConfig(
  id: 1,
  name: 'NAS',
  url: 'http://nas.example.com',
  username: 'admin',
  isActive: true,
  createdAt: DateTime(2026, 1, 1),
  updatedAt: DateTime(2026, 1, 1),
);

PlayProgress _progress(String filePath, int positionMs) => PlayProgress(
      connectionId: 1,
      filePath: filePath,
      positionMs: positionMs,
      durationMs: 600000,
      lastPlayedAt: DateTime(2026, 7, 24),
    );

const _fileA = '/audiobooks/chapter_01.mp3';
const _fileB = '/audiobooks/chapter_02.mp3';

_FakeProgressDao _twoFileDao() => _FakeProgressDao({
      '1:$_fileA': _progress(_fileA, 30000),
      '1:$_fileB': _progress(_fileB, 60000),
    });

// ── 调用方 1：BrowserScreen ───────────────────────────────────────────────────

Future<void> _pumpBrowser(WidgetTester tester, ProgressDao dao) async {
  await tester.pumpWidget(buildTestAppWithPlayerRoute(
    const Scaffold(body: BrowserScreen()),
    overrides: [
      directoryContentsProvider('/').overrideWith((ref) async => [
            testAudio('chapter_01.mp3', _fileA),
            testAudio('chapter_02.mp3', _fileB),
          ]),
      activeConnectionProvider.overrideWith((ref) async => _conn),
      progressDaoProvider.overrideWithValue(dao),
    ],
  ));
  await tester.pumpAndSettle();
  expect(find.text('chapter_01.mp3'), findsOneWidget, reason: '前置条件：文件列表已渲染');
}

/// 点击 chapter_01 并等待恢复对话框出现。
Future<void> _tapFileAndAwaitDialog(WidgetTester tester) async {
  await tester.tap(find.text('chapter_01.mp3'));
  // 不用 pumpAndSettle：对话框有 5s 倒计时 Timer.periodic
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
  expect(find.text('恢复播放进度'), findsOneWidget, reason: '前置条件：30s 进度应触发恢复对话框');
}

// ── 调用方 2：PlaylistDetailScreen ────────────────────────────────────────────

const _trackA = '/music/track_a.mp3';
const _trackB = '/music/track_b.mp3';

final _now = DateTime(2026, 7, 24);
final _playlist = Playlist(
  id: 1,
  name: 'Test Playlist',
  trackCount: 2,
  createdAt: _now,
  updatedAt: _now,
);

Future<void> _pumpPlaylist(WidgetTester tester, ProgressDao dao) async {
  await tester.pumpWidget(buildTestAppWithPlayerRoute(
    const PlaylistDetailScreen(playlistId: 1),
    overrides: [
      playlistTracksProvider(1).overrideWith((ref) => Future.value([
            PlaylistTrack(
              id: 1,
              playlistId: 1,
              filePath: _trackA,
              fileName: 'track_a.mp3',
              addedAt: _now,
            ),
            PlaylistTrack(
              id: 2,
              playlistId: 1,
              filePath: _trackB,
              fileName: 'track_b.mp3',
              addedAt: _now,
            ),
          ])),
      playlistListProvider
          .overrideWith((ref) => Future.value(<Playlist>[_playlist])),
      activeConnectionProvider.overrideWith((ref) async => _conn),
      progressDaoProvider.overrideWithValue(dao),
    ],
  ));
  await tester.pumpAndSettle();

  // PlaylistDetailScreen 的 build 不 watch activeConnectionProvider，
  // 需预热使 _playTrackAtIndex 里 valueOrNull 非空（同 ply_13_test TST-T20）。
  final container = ProviderScope.containerOf(
    tester.element(find.byType(PlaylistDetailScreen)),
  );
  container.read(activeConnectionProvider);
  await tester.pump();

  expect(find.text('track_a.mp3'), findsOneWidget, reason: '前置条件：曲目列表已渲染');
}

void main() {
  // ═══════════════════════════════════════════════════════════════════════════
  // Group 1: BUG-13-S1 调用方 1（browser_screen.dart onFileTap）
  // ═══════════════════════════════════════════════════════════════════════════

  group('BUG-13-S1 调用方 1：浏览页"从头播放"删除进度记录', () {
    testWidgets('选"从头播放"→ F 记录被删、其他文件不受影响、从头进播放', (tester) async {
      final dao = _twoFileDao();
      await _pumpBrowser(tester, dao);

      // 前置：两条记录都在
      expect(await dao.find(1, _fileA), isNotNull);
      expect(await dao.find(1, _fileB), isNotNull);

      await _tapFileAndAwaitDialog(tester);

      // 点"从头播放"（resume == false 分支）
      await tester.tap(find.text('从头播放'));
      await tester.pumpAndSettle();

      // 正向断言：F 的进度记录被删（cr PRG3 声明的副作用真正执行）
      expect(await dao.find(1, _fileA), isNull,
          reason: 'BUG-13：选"从头播放"后调用方必须经 clearProgressProvider '
              '删除该文件的进度记录，否则 5 秒内退出再进会反复弹旧进度对话框');

      // 否定断言：其他文件的进度记录不受影响（BUG-11 按文件模型）
      expect(await dao.find(1, _fileB), isNotNull,
          reason: '删除必须精确匹配 (connection_id, file_path)，'
              '不得波及其他文件的进度记录');

      // 否定断言：不阻塞播放流程——正常进入播放页且从头播放
      expect(find.text('Player'), findsOneWidget, reason: '播放流程不应被清除动作阻塞');
      final container = ProviderScope.containerOf(
        tester.element(find.text('Player')),
      );
      final queue = container.read(currentPlayQueueProvider);
      expect(queue, isNotNull);
      expect(queue!.startPositionMs, isNull, reason: '"从头播放"不得携带保存位置');

      // provider 状态同步：invalidate 后再查应为 null，其他文件仍可查到
      expect(
        await container.read(
            progressForFileProvider((connectionId: 1, filePath: _fileA))
                .future),
        isNull,
        reason: 'clearProgressProvider 成功后应 invalidate '
            'progressForFileProvider，浏览器再次查询不得读到已删记录',
      );
      expect(
        await container.read(
            progressForFileProvider((connectionId: 1, filePath: _fileB))
                .future),
        isNotNull,
        reason: '其他文件的进度查询不受影响',
      );
    });

    testWidgets('选"继续播放"→ 记录保留且从保存位置播放（删除只发生在 false 分支）', (tester) async {
      final dao = _twoFileDao();
      await _pumpBrowser(tester, dao);
      await _tapFileAndAwaitDialog(tester);

      await tester.tap(find.textContaining('继续播放'));
      await tester.pumpAndSettle();

      expect(await dao.find(1, _fileA), isNotNull,
          reason: '选"继续播放"（resume == true）不得删除进度记录');
      expect(find.text('Player'), findsOneWidget);
      final container = ProviderScope.containerOf(
        tester.element(find.text('Player')),
      );
      expect(container.read(currentPlayQueueProvider)!.startPositionMs,
          equals(30000),
          reason: '继续播放应携带保存位置');
    });

    testWidgets('clear 失败静默继续——播放不被阻塞（spec 边界裁决）', (tester) async {
      final dao = _ThrowingDeleteDao({'1:$_fileA': _progress(_fileA, 30000)});
      await _pumpBrowser(tester, dao);
      await _tapFileAndAwaitDialog(tester);

      // delete 抛异常——clearProgressProvider 内部 catch，不得向上传播
      await tester.tap(find.text('从头播放'));
      await tester.pumpAndSettle();

      expect(find.text('Player'), findsOneWidget,
          reason: 'spec 否定断言：clear 失败静默继续从头播放，不得阻塞播放流程');
      // 删除确实未成功（诚实断言 spec 裁决的代价：记录残留但播放不受影响）
      expect(await dao.find(1, _fileA), isNotNull,
          reason: 'delete 抛异常时记录残留是 spec 接受的静默代价');
    });

    testWidgets('对话框被非按钮方式关闭（resume == null）→ 从头播放但不删记录', (tester) async {
      final dao = _twoFileDao();
      await _pumpBrowser(tester, dao);
      await _tapFileAndAwaitDialog(tester);

      // 模拟系统返回键关闭对话框：showDialog 以 null 结束，非按钮触发
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(find.text('恢复播放进度'), findsNothing, reason: '对话框应已关闭');
      expect(await dao.find(1, _fileA), isNotNull,
          reason: 'spec 边界裁决：resume == null（用户未明确选择）'
              '不进入任何分支，从头播放但不删记录');
      expect(find.text('Player'), findsOneWidget, reason: '仍应从头进入播放');
      final container = ProviderScope.containerOf(
        tester.element(find.text('Player')),
      );
      expect(container.read(currentPlayQueueProvider)!.startPositionMs, isNull);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // Group 2: BUG-13-S1 调用方 2（playlist_detail_screen.dart _playTrackAtIndex）
  // ═══════════════════════════════════════════════════════════════════════════

  group('BUG-13-S1 调用方 2：播放单详情页"从头播放"删除进度记录', () {
    testWidgets('选"从头播放"→ F 记录被删、其他曲目不受影响、从头进播放', (tester) async {
      final dao = _FakeProgressDao({
        '1:$_trackA': _progress(_trackA, 30000),
        '1:$_trackB': _progress(_trackB, 60000),
      });
      await _pumpPlaylist(tester, dao);

      expect(await dao.find(1, _trackA), isNotNull);
      expect(await dao.find(1, _trackB), isNotNull);

      await tester.tap(find.text('track_a.mp3'));
      // 倒计时 Timer.periodic 在跑，逐步 pump（同 ply_13_test TST-T21）
      await tester.pump();
      await tester.pump();
      await tester.pump();
      expect(find.text('恢复播放进度'), findsOneWidget,
          reason: '前置条件：30s 进度应触发恢复对话框');

      await tester.tap(find.text('从头播放'));
      await tester.pump(); // Navigator.pop(false) → then(dismiss)
      await tester.pump(); // resume == false 分支 → clear → push /player
      await tester.pump(); // 构建 player 路由

      expect(await dao.find(1, _trackA), isNull,
          reason: 'BUG-13：播放单调用方的 resume == false 分支同样必须删记录'
              '（d4856ec 修复点）');
      expect(await dao.find(1, _trackB), isNotNull, reason: '不得波及其他曲目的进度记录');

      expect(find.text('Player'), findsOneWidget, reason: '播放流程不被阻塞');
      final container = ProviderScope.containerOf(
        tester.element(find.text('Player')),
      );
      expect(container.read(currentPlayQueueProvider)!.startPositionMs, isNull,
          reason: '"从头播放"不得携带保存位置');
    });
  });
}
