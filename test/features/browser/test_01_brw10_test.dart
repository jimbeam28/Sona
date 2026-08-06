// test/features/browser/test_01_brw10_test.dart
// TEST-01-S4/S5/S6（BRW10 批量进度查询 + 点击→对话框 + 竞态）— provider test + widget test
//
// 生产行为说明（与 spec 的差异见文件底部 "spec 偏差" 注释）：
// BUG-12 修复后 browser 的进度查询迁到 progressForFileProvider（按
// (connectionId, filePath) 直读 DAO），旧的 loadProgressForDirectoryProvider
// 全局注册表（_progressRegistry）已拆除——"目录批量查询"与"目录切换竞态"在
// 当前生产实现中不复存在，IProgressDao 契约也没有批量方法（见
// test/helpers/fake_progress_dao.dart 的接口面）。本文件按生产行为锚定：
//   S4  逐文件查询语义：ProviderContainer + fake DAO，3 个文件各自读到进度
//   S5  点击带进度文件 → 弹恢复对话框（widget test）
//   S6  per-file family 无污染：慢查询（挂起）文件完成不污染其他文件的查询结果
//
// 覆盖：
//   TEST-01-S4  3 个文件进度可经 provider 查询到（每文件恰好一次 DAO find）
//   TEST-01-S5  点击带进度文件 → 弹"恢复播放进度"对话框；无进度 → 直接播放
//   TEST-01-S6  慢查询文件完成不得污染其他文件/目录的查询结果（竞态回归守护）

import 'dart:async';

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

// ── fakes ─────────────────────────────────────────────────────────────────────

/// 记录 find 调用次数的内存 fake（扩展 ProgressDao，同 bug_12/bug_13 模式）。
class _CountingProgressDao extends ProgressDao {
  _CountingProgressDao(Map<String, PlayProgress> records)
      : _store = Map.of(records);

  final Map<String, PlayProgress> _store;
  int findCalls = 0;

  static String _key(int connectionId, String filePath) =>
      '$connectionId:$filePath';

  @override
  Future<PlayProgress?> find(int connectionId, String filePath) async {
    findCalls++;
    return _store[_key(connectionId, filePath)];
  }
}

/// find 可挂起的 fake：dir A 的文件查询等待 Completer，dir B 的文件立即返回。
class _GatedProgressDao extends ProgressDao {
  _GatedProgressDao(Map<String, PlayProgress> records)
      : _store = Map.of(records);

  final Map<String, PlayProgress> _store;
  final Map<String, Completer<void>> _gates = {};
  final List<String> _pendingKeys = [];

  void gate(String key) {
    final completer = Completer<void>();
    _gates[key] = completer;
    _pendingKeys.add(key);
  }

  void release(String key) {
    final completer = _gates.remove(key);
    if (completer != null && !completer.isCompleted) {
      completer.complete();
    }
  }

  bool isPending(String key) => _gates.containsKey(key);

  static String _key(int connectionId, String filePath) =>
      '$connectionId:$filePath';

  @override
  Future<PlayProgress?> find(int connectionId, String filePath) async {
    final key = _key(connectionId, filePath);
    final gate = _gates[key];
    if (gate != null) {
      await gate.future;
    }
    return _store[key];
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

void main() {
  // ═════════════════════════════════════════════════════════════════════════
  // TEST-01-S4: 目录进度经 provider 查询，3 个文件各自读到进度
  // ═════════════════════════════════════════════════════════════════════════

  group('TEST-01-S4: 进度查询 provider（per-file 语义）', () {
    test('/music 下 3 个文件（a/b 有进度、c 无）→ 各自读到正确值', () async {
      final dao = _CountingProgressDao({
        '1:/music/a.mp3': _progress('/music/a.mp3', 10000),
        '1:/music/b.mp3': _progress('/music/b.mp3', 20000),
        '1:/music/c.mp3': _progress('/music/c.mp3', 30000),
      });
      final container = ProviderContainer(
        overrides: [progressDaoProvider.overrideWithValue(dao)],
      );
      addTearDown(container.dispose);

      final a = await container.read(
          progressForFileProvider((connectionId: 1, filePath: '/music/a.mp3'))
              .future);
      final b = await container.read(
          progressForFileProvider((connectionId: 1, filePath: '/music/b.mp3'))
              .future);
      final c = await container.read(
          progressForFileProvider((connectionId: 1, filePath: '/music/c.mp3'))
              .future);

      expect(a, isNotNull, reason: 'S4: a.mp3 应读到进度');
      expect(a!.positionMs, equals(10000));
      expect(b, isNotNull, reason: 'S4: b.mp3 应读到进度');
      expect(b!.positionMs, equals(20000));
      expect(c, isNotNull, reason: 'S4: c.mp3 应读到进度');
      expect(c!.positionMs, equals(30000));
    });

    test('无进度的文件 → provider 返回 null（部分为 null 语义）', () async {
      final dao = _CountingProgressDao({
        '1:/music/a.mp3': _progress('/music/a.mp3', 10000),
      });
      final container = ProviderContainer(
        overrides: [progressDaoProvider.overrideWithValue(dao)],
      );
      addTearDown(container.dispose);

      final missing = await container.read(progressForFileProvider((
        connectionId: 1,
        filePath: '/music/not_saved.mp3',
      )).future);
      expect(missing, isNull, reason: 'S4: 目录内无进度的文件应返回 null（不阻塞播放）');
    });

    test('每个文件恰好一次 DAO find（无多余查询）', () async {
      final dao = _CountingProgressDao({
        '1:/music/a.mp3': _progress('/music/a.mp3', 10000),
        '1:/music/b.mp3': _progress('/music/b.mp3', 20000),
        '1:/music/c.mp3': _progress('/music/c.mp3', 30000),
      });
      final container = ProviderContainer(
        overrides: [progressDaoProvider.overrideWithValue(dao)],
      );
      addTearDown(container.dispose);

      for (final file in ['/music/a.mp3', '/music/b.mp3', '/music/c.mp3']) {
        await container.read(
            progressForFileProvider((connectionId: 1, filePath: file)).future);
      }

      expect(dao.findCalls, equals(3),
          reason: 'S4: 3 个文件应各触发一次 DAO find（不重复查询同一文件）');
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  // TEST-01-S5: 点击带进度文件 → 弹进度恢复对话框
  // ═════════════════════════════════════════════════════════════════════════

  group('TEST-01-S5: 点击带进度文件 → 弹恢复对话框', () {
    Future<void> pumpBrowser(WidgetTester tester, ProgressDao dao) async {
      await tester.pumpWidget(buildTestAppWithPlayerRoute(
        const Scaffold(body: BrowserScreen()),
        overrides: [
          directoryContentsProvider('/').overrideWith((ref) async => [
                testAudio('a.mp3', '/music/a.mp3'),
                testAudio('b.mp3', '/music/b.mp3'),
              ]),
          activeConnectionProvider.overrideWith((ref) async => _conn),
          progressDaoProvider.overrideWithValue(dao),
        ],
      ));
      await tester.pumpAndSettle();
      expect(find.text('a.mp3'), findsOneWidget, reason: '前置条件：文件列表已渲染');
    }

    testWidgets('点击有进度文件（1:23）→ 弹恢复对话框', (tester) async {
      final dao = _CountingProgressDao({
        '1:/music/a.mp3': _progress('/music/a.mp3', 83000),
      });
      await pumpBrowser(tester, dao);

      await tester.tap(find.text('a.mp3'));
      // 对话框有 5s 倒计时 Timer.periodic，不用 pumpAndSettle（同 bug_12）
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('恢复播放进度'), findsOneWidget,
          reason: 'S5: 点击带进度文件应弹出进度恢复对话框');
      expect(find.text('从头播放'), findsOneWidget, reason: 'S5: 对话框应有"从头播放"选项');
      expect(find.textContaining('继续播放'), findsWidgets,
          reason: 'S5: 对话框应有"继续播放"选项（含倒计时）');

      // 收尾：选"继续播放"关闭对话框（对话框有 5s 倒计时 Timer.periodic）
      await tester.tap(find.textContaining('继续播放'));
      await tester.pumpAndSettle();
      expect(find.text('Player'), findsOneWidget,
          reason: 'S5: 选择继续播放后应正常进入播放页');
    });

    testWidgets('否定断言: 点击无进度文件 → 无对话框，直接播放', (tester) async {
      final dao = _CountingProgressDao({
        '1:/music/a.mp3': _progress('/music/a.mp3', 83000),
      });
      await pumpBrowser(tester, dao);

      await tester.tap(find.text('b.mp3'));
      await tester.pumpAndSettle();

      expect(find.text('恢复播放进度'), findsNothing, reason: 'S5 否定: 无进度文件不得弹对话框');
      expect(find.text('Player'), findsOneWidget,
          reason: 'S5 否定: 无进度文件应直接进入播放页');
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  // TEST-01-S6: 慢查询不污染其他文件/目录的进度（竞态回归守护）
  // ═════════════════════════════════════════════════════════════════════════

  group('TEST-01-S6: 慢查询不污染其他目录进度（per-file 无共享注册表）', () {
    test('dir A 查询挂起期间 dir B 查询立即完成 → B 结果正确', () async {
      final dao = _GatedProgressDao({
        '1:/dir_a/a.mp3': _progress('/dir_a/a.mp3', 11111),
        '1:/dir_b/b.mp3': _progress('/dir_b/b.mp3', 22222),
      })
        ..gate('1:/dir_a/a.mp3');
      final container = ProviderContainer(
        overrides: [progressDaoProvider.overrideWithValue(dao)],
      );
      addTearDown(container.dispose);

      // 目录 A 的查询启动后挂起（模拟慢查询）
      final aFuture = container.read(
          progressForFileProvider((connectionId: 1, filePath: '/dir_a/a.mp3'))
              .future);
      expect(dao.isPending('1:/dir_a/a.mp3'), isTrue,
          reason: 'S6 前置: dir A 查询应处于挂起状态');

      // 快速切到目录 B 并查询其文件——立即完成
      final b = await container.read(progressForFileProvider((
        connectionId: 1,
        filePath: '/dir_b/b.mp3',
      )).future);
      expect(b, isNotNull, reason: 'S6: dir B 查询应立即完成');
      expect(b!.positionMs, equals(22222),
          reason: 'S6: dir B 的进度应属于 dir B 自己的文件');

      // A 的慢查询完成 → 只更新 A 自己的结果，不得污染 B
      dao.release('1:/dir_a/a.mp3');
      final a = await aFuture;
      expect(a, isNotNull, reason: 'S6: dir A 查询完成后应返回自身进度');
      expect(a!.positionMs, equals(11111),
          reason: 'S6: dir A 的进度值必须属于 /dir_a/a.mp3');

      final bAgain = await container.read(progressForFileProvider((
        connectionId: 1,
        filePath: '/dir_b/b.mp3',
      )).future);
      expect(bAgain!.positionMs, equals(22222),
          reason: 'S6 否定: A 查询完成后不得改写 B 的进度（无共享注册表污染）');
    });
  });
}
