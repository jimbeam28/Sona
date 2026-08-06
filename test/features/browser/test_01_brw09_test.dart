// test/features/browser/test_01_brw09_test.dart
// TEST-01-S1/S2/S3（BRW9 长按菜单交互）— widget test
//
// 背景（BUG-12 修复后）：浏览器进度查询走 progressForFileProvider（直读 DAO），
// 旧的 playProgressProvider 注册表已拆除。长按菜单逻辑在 browser_screen.dart
// onFileLongPress：`if (progress == null) return;` → 有进度才追加"清除播放进度"。
//
// 走真实生产链路（BrowserScreen → progressForFileProvider → ProgressService →
// ProgressDao），仅叶子 DAO 注入内存 fake（同 bug_12/bug_13_repro_test 项目标准）。
//
// 覆盖：
//   TEST-01-S1  有进度 → 长按弹菜单含"清除播放进度" + 否定断言
//   TEST-01-S2  无进度 → 长按不弹"清除播放进度" + 否定断言
//   TEST-01-S3  点"清除播放进度" → DAO delete 被调 + provider 刷新为 null + 只影响目标文件

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nas_audio_player/core/database/dao/progress_dao.dart';
import 'package:nas_audio_player/features/browser/browser_provider.dart';
import 'package:nas_audio_player/features/browser/browser_screen.dart';
import 'package:nas_audio_player/features/connection/connection_provider.dart';
import 'package:nas_audio_player/features/progress/progress_provider.dart';
import 'package:nas_audio_player/shared/models/connection_config.dart';
import 'package:nas_audio_player/shared/models/play_progress.dart';

import '../../helpers/test_factories.dart';
import '../../helpers/widget_helpers.dart';

/// 叶子 fake：内存 store 的 ProgressDao，记录 delete 调用参数
/// （sqflite_ffi 的 Future 在 testWidgets FakeAsync 区不完成，
/// widget 测试经契约注入 fake 是项目标准做法）。
class _RecordingProgressDao extends ProgressDao {
  _RecordingProgressDao(Map<String, PlayProgress> records)
      : _store = Map.of(records);

  final Map<String, PlayProgress> _store;
  final List<(int, String)> deletedCalls = [];

  static String _key(int connectionId, String filePath) =>
      '$connectionId:$filePath';

  @override
  Future<PlayProgress?> find(int connectionId, String filePath) async =>
      _store[_key(connectionId, filePath)];

  @override
  Future<void> delete(int connectionId, String filePath) async {
    deletedCalls.add((connectionId, filePath));
    _store.remove(_key(connectionId, filePath));
  }
}

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

const _fileA = '/music/a.mp3';
const _fileB = '/music/b.mp3';

/// 目录含两个音频文件；a.mp3 有进度（83s = 1:23），b.mp3 无进度。
_RecordingProgressDao _twoFileDao() => _RecordingProgressDao({
      '1:$_fileA': _progress(_fileA, 83000),
    });

Future<void> _pumpBrowser(WidgetTester tester, ProgressDao dao) async {
  await tester.pumpWidget(buildTestAppWithPlayerRoute(
    const Scaffold(body: BrowserScreen()),
    overrides: [
      directoryContentsProvider('/').overrideWith((ref) async => [
            testAudio('a.mp3', _fileA),
            testAudio('b.mp3', _fileB),
          ]),
      activeConnectionProvider.overrideWith((ref) async => _conn),
      progressDaoProvider.overrideWithValue(dao),
    ],
  ));
  await tester.pumpAndSettle();
  expect(find.text('a.mp3'), findsOneWidget, reason: '前置条件：文件列表已渲染');
}

void main() {
  group('TEST-01-S1: 长按有进度的文件 → 弹出含"删除进度"的菜单', () {
    testWidgets('有进度文件长按 → 菜单出现"清除播放进度"', (tester) async {
      final dao = _twoFileDao();
      await _pumpBrowser(tester, dao);

      await tester.longPress(find.text('a.mp3'));
      await tester.pumpAndSettle();

      expect(find.text('清除播放进度'), findsOneWidget,
          reason: 'S1: 有进度的文件长按应弹出含"清除播放进度"的菜单');
    });

    testWidgets('否定断言: 长按只弹菜单，不触发 onTap 播放/导航', (tester) async {
      final dao = _twoFileDao();
      await _pumpBrowser(tester, dao);

      await tester.longPress(find.text('a.mp3'));
      await tester.pumpAndSettle();

      // 长按不得触发播放路径：不压 /player、不弹续播对话框
      expect(find.text('Player'), findsNothing,
          reason: 'S1 否定: 长按不得触发 onTap 的文件播放逻辑');
      expect(find.text('恢复播放进度'), findsNothing,
          reason: 'S1 否定: 长按不得触发点击文件才有的进度恢复对话框');
    });

    testWidgets('否定断言: 点击行为不受长按影响——点击仍走正常播放路径', (tester) async {
      final dao = _twoFileDao();
      await _pumpBrowser(tester, dao);

      // 先长按打开菜单，再点击 tile（点击 tile 文本在菜单上仍可命中）
      await tester.longPress(find.text('a.mp3'));
      await tester.pumpAndSettle();
      expect(find.text('清除播放进度'), findsOneWidget);

      // 关闭菜单后点击 a.mp3 → 有进度 → 弹恢复对话框（正常播放路径）
      await tester.tapAt(const Offset(20, 20)); // 点菜单外区域关闭
      await tester.pumpAndSettle();
      expect(find.text('清除播放进度'), findsNothing, reason: '菜单应已关闭');

      await tester.tap(find.text('a.mp3'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('恢复播放进度'), findsOneWidget,
          reason: 'S1 否定: 点击 tile 应触发正常播放路径（有进度 → 弹恢复对话框）');

      // 收尾：选"继续播放"关闭对话框（对话框有 5s 倒计时 Timer.periodic）
      await tester.tap(find.textContaining('继续播放'));
      await tester.pumpAndSettle();
      expect(find.text('Player'), findsOneWidget,
          reason: 'S1 否定: 确认对话框后应进入播放页');
    });
  });

  group('TEST-01-S2: 长按无进度的文件 → 不弹"删除进度"菜单', () {
    testWidgets('无进度文件长按 → 无"清除播放进度"选项', (tester) async {
      final dao = _twoFileDao();
      await _pumpBrowser(tester, dao);

      await tester.longPress(find.text('b.mp3'));
      await tester.pumpAndSettle();

      expect(find.text('清除播放进度'), findsNothing,
          reason: 'S2: 无进度的文件长按不得出现"清除播放进度"选项'
              '（if (progress == null) return 拦截）');
    });

    testWidgets('否定断言: 长按不触发 onTap 播放/导航', (tester) async {
      final dao = _twoFileDao();
      await _pumpBrowser(tester, dao);

      await tester.longPress(find.text('b.mp3'));
      await tester.pumpAndSettle();

      expect(find.text('Player'), findsNothing,
          reason: 'S2 否定: 长按无进度文件也不得触发文件播放逻辑');
      expect(find.text('恢复播放进度'), findsNothing, reason: 'S2 否定: 长按不得触发恢复对话框');
    });

    testWidgets('否定断言: 点击无进度文件仍直接播放（无弹窗）', (tester) async {
      final dao = _twoFileDao();
      await _pumpBrowser(tester, dao);

      await tester.tap(find.text('b.mp3'));
      await tester.pumpAndSettle();

      expect(find.text('恢复播放进度'), findsNothing,
          reason: 'S2 否定: 点击无进度文件应直接进入播放流程，不弹对话框');
      expect(find.text('Player'), findsOneWidget,
          reason: 'S2 否定: 点击行为不变——正常进入播放页');
    });
  });

  group('TEST-01-S3: 点击"清除播放进度" → DAO delete + provider 刷新为 null', () {
    testWidgets('点"清除播放进度" → delete(1, /music/a.mp3) 被调一次且仅此一次',
        (tester) async {
      final dao = _twoFileDao();
      await _pumpBrowser(tester, dao);

      await tester.longPress(find.text('a.mp3'));
      await tester.pumpAndSettle();
      expect(find.text('清除播放进度'), findsOneWidget);

      await tester.tap(find.text('清除播放进度'));
      await tester.pumpAndSettle();

      expect(dao.deletedCalls, hasLength(1),
          reason: 'S3: 点击"清除播放进度"应调用一次 DAO delete');
      expect(dao.deletedCalls.single, (1, _fileA),
          reason: 'S3: delete 参数应为 (connectionId=1, filePath=/music/a.mp3)');
    });

    testWidgets('删除后 progressForFileProvider 刷新为 null（provider 状态同步）',
        (tester) async {
      final dao = _twoFileDao();
      await _pumpBrowser(tester, dao);

      await tester.longPress(find.text('a.mp3'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('清除播放进度'));
      await tester.pumpAndSettle();

      final container =
          ProviderScope.containerOf(tester.element(find.byType(BrowserScreen)));
      final result = await container.read(
          progressForFileProvider((connectionId: 1, filePath: _fileA)).future);
      expect(result, isNull,
          reason: 'S3: 清除后进度 provider 应刷新为 null（invalidate 生效）');
    });

    testWidgets('否定断言: 只删除目标文件，其他文件进度不受影响', (tester) async {
      final dao = _twoFileDao().._store['1:$_fileB'] = _progress(_fileB, 60000);
      await _pumpBrowser(tester, dao);

      await tester.longPress(find.text('a.mp3'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('清除播放进度'));
      await tester.pumpAndSettle();

      final container =
          ProviderScope.containerOf(tester.element(find.byType(BrowserScreen)));
      final bResult = await container.read(
          progressForFileProvider((connectionId: 1, filePath: _fileB)).future);
      expect(bResult, isNotNull, reason: 'S3 否定: 仅删除被点击文件的进度，b.mp3 的进度不得被波及');
      expect(bResult!.positionMs, equals(60000));

      // a.mp3 已删
      final aResult = await container.read(
          progressForFileProvider((connectionId: 1, filePath: _fileA)).future);
      expect(aResult, isNull, reason: 'S3: 目标文件进度应已被删除');
    });

    testWidgets('否定断言: 菜单在点击后关闭，不阻塞浏览页', (tester) async {
      final dao = _twoFileDao();
      await _pumpBrowser(tester, dao);

      await tester.longPress(find.text('a.mp3'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('清除播放进度'));
      await tester.pumpAndSettle();

      expect(find.text('清除播放进度'), findsNothing, reason: 'S3 否定: 点击菜单项后菜单应关闭');
      expect(find.text('a.mp3'), findsOneWidget,
          reason: 'S3 否定: 浏览页保持可用，文件列表仍渲染');
    });
  });
}
