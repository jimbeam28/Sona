// test/features/browser/bug_12_repro_test.dart
// BUG-12 复现测试（来源：docs/cr/cr-20260724-0110.md BRW1 + BRW3 + BRW4 同根）
//
// 缺陷：browser_provider.dart 的 _progressRegistry 唯一写入点在
// loadProgressForDirectoryProvider 内，而全仓该 provider 只有两处 invalidate
// （browser_screen.dart / player_screen.dart），无任何 read/watch/future。
// Riverpod 2.6.1 对从未创建元素的 family 成员 invalidate 是空操作
// → 注册表恒空 → 浏览页点击有进度的文件不弹续播对话框、
// 长按"清除播放进度"永不出现。
//
// 修复：browser 的进度查询迁到 progressForFileProvider（直读 DAO，
// 与 upsert/clear 的 invalidate 天然对齐，一并解掉 BRW3），拆除全局注册表
// （BRW4 竞态随之消失）。
//
// 本测试走真实生产链路（BrowserScreen onFileTap / onFileLongPress
// → progressForFileProvider → ProgressService → ProgressDao），
// 仅叶子数据源注入 fake（sqflite_ffi 的 Future 在 testWidgets FakeAsync
// 区不完成，widget 测试经契约注入 fake 是项目标准做法）。
// 修复前 FAIL（对话框 / 清除菜单不出现），修复后 PASS。

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

/// 叶子 fake：按 (connectionId, filePath) 返回预置进度，纯微任务 Future
/// （testWidgets FakeAsync 区可完成）。
class _FakeProgressDao extends ProgressDao {
  _FakeProgressDao(this._store);
  final Map<String, PlayProgress> _store;

  @override
  Future<PlayProgress?> find(int connectionId, String filePath) async =>
      _store['$connectionId:$filePath'];
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

/// chapter_01 有 30s 进度（过 shouldSave 门槛）；chapter_02 无进度。
final _fakeDao = _FakeProgressDao({
  '1:/audiobooks/chapter_01.mp3': PlayProgress(
    connectionId: 1,
    filePath: '/audiobooks/chapter_01.mp3',
    positionMs: 30000,
    durationMs: 600000,
    lastPlayedAt: DateTime(2026, 7, 24),
  ),
});

List<Override> _overrides() => [
      directoryContentsProvider('/').overrideWith((ref) async => [
            testAudio('chapter_01.mp3', '/audiobooks/chapter_01.mp3'),
            testAudio('chapter_02.mp3', '/audiobooks/chapter_02.mp3'),
          ]),
      activeConnectionProvider.overrideWith((ref) async => _conn),
      progressDaoProvider.overrideWithValue(_fakeDao),
    ];

void main() {
  Future<void> _pumpBrowser(WidgetTester tester) async {
    await tester.pumpWidget(buildTestAppWithPlayerRoute(
      Scaffold(body: BrowserScreen()),
      overrides: _overrides(),
    ));
    await tester.pumpAndSettle();
    expect(find.text('chapter_01.mp3'), findsOneWidget, reason: '前置条件：文件列表已渲染');
  }

  group('BUG-12: 浏览器端进度查询链路（BRW1/BRW3/BRW4 复现）', () {
    testWidgets('点击有进度的文件 → 应弹续播对话框', (tester) async {
      await _pumpBrowser(tester);

      await tester.tap(find.text('chapter_01.mp3'));
      // 不用 pumpAndSettle：对话框有 5s 倒计时 Timer.periodic
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('恢复播放进度'), findsOneWidget,
          reason: 'BUG-12：进度注册表从未被填充，浏览页续播对话框整体失效。'
              '修复后应经 progressForFileProvider 读到 30s 进度并弹框');

      // 收尾：选"继续播放"关闭对话框（顺带验证 /player 正常压栈且不被
      // double-pop 弹掉，与 BUG-10 联动）
      await tester.tap(find.textContaining('继续播放 ('));
      await tester.pumpAndSettle();
      expect(find.text('Player'), findsOneWidget,
          reason: '播放页应正常压栈并保持（不被 double-pop 弹掉）');
    });

    testWidgets('长按有进度的文件 → 应出现"清除播放进度"', (tester) async {
      await _pumpBrowser(tester);

      await tester.longPress(find.text('chapter_01.mp3'));
      await tester.pumpAndSettle();

      expect(find.text('清除播放进度'), findsOneWidget,
          reason: 'BUG-12：注册表恒空 → onFileLongPress 早退，'
              '长按清除进度入口永不出现');
    });

    testWidgets('点击无进度的文件 → 不弹对话框直接播放', (tester) async {
      await _pumpBrowser(tester);

      await tester.tap(find.text('chapter_02.mp3'));
      await tester.pumpAndSettle();

      expect(find.text('恢复播放进度'), findsNothing, reason: '无进度文件应直接进播放流程，不弹对话框');
      expect(find.text('Player'), findsOneWidget, reason: '应正常进入播放页');
    });
  });
}
