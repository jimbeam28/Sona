// test/features/browser/bug_18_repro_test.dart
// BUG-18 复现测试（来源：docs/cr/cr-20260816-0805-progress-timer-settings.md F1）
//
// 缺陷：browser_screen.dart onFileTap 恢复进度查询（116-120）裸奔无 try/catch
// （对比同功能另一调用方 playlist_detail_screen.dart:48-75 有 catch-log 加固；
// 写路径 upsert/clear 也已被 BUG-09 加固为 try-catch + debugPrint）。
// DAO 读进度抛错时（SQLite 读异常，如 DB 文件损坏/IO 错误）：
// 未处理异步异常上抛（debug 红屏/zone 错误）→ 队列不建、/player 不跳，
// 点击静默失效。
//
// 本测试走真实生产链路（BrowserScreen onFileTap / onFileLongPress
// → progressForFileProvider → ProgressService → ProgressDao），
// 仅叶子数据源注入抛错 fake（同 bug_12_repro_test.dart 模式）。
// 修复前：本测试 FAIL —— takeException 捕获未处理异常 + 不跳 Player + 无失败日志。
// 修复后：本测试 PASS —— 异常被捕获记日志、按无进度继续播放（仍进 /player）。

import 'package:flutter/foundation.dart';
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

/// 读进度必抛错的叶子 fake（模拟 SQLite 读异常，如 DB 文件损坏/IO 错误）。
class _ThrowingProgressDao extends ProgressDao {
  @override
  Future<PlayProgress?> find(int connectionId, String filePath) async {
    throw Exception('simulated DB read failure: $filePath');
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

List<Override> _overrides() => [
      directoryContentsProvider('/').overrideWith((ref) async => [
            testAudio('chapter_01.mp3', '/audiobooks/chapter_01.mp3'),
            testAudio('chapter_02.mp3', '/audiobooks/chapter_02.mp3'),
          ]),
      activeConnectionProvider.overrideWith((ref) async => _conn),
      progressDaoProvider.overrideWithValue(_ThrowingProgressDao()),
    ];

/// Runs [body] while capturing everything written through [debugPrint]
/// （同 bug_bug10_repro_test.dart:25-38 模式——生产把 debugPrint 镜像进
/// LogBuffer，落进 [logs] 的即 debug 构建在 /logs 可见的内容）。
Future<T> captureDebugPrint<T>(
  Future<T> Function(List<String> logs) body,
) async {
  final logs = <String>[];
  final original = debugPrint;
  debugPrint = (String? message, {int? wrapWidth}) {
    if (message != null) logs.add(message);
  };
  try {
    return await body(logs);
  } finally {
    debugPrint = original;
  }
}

void main() {
  Future<void> _pumpBrowser(WidgetTester tester) async {
    await tester.pumpWidget(buildTestAppWithPlayerRoute(
      Scaffold(body: BrowserScreen()),
      overrides: _overrides(),
    ));
    await tester.pumpAndSettle();
    expect(find.text('chapter_01.mp3'), findsOneWidget, reason: '前置条件：文件列表已渲染');
  }

  group('BUG-18: 浏览器恢复进度查询异常路径（cr-0805 F1）', () {
    testWidgets('DAO 读进度抛错 → 点击仍进播放页（按无进度播放），无未处理异常', (tester) async {
      await _pumpBrowser(tester);

      await tester.tap(find.text('chapter_01.mp3'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // 缺陷断言（修复前 FAIL）：未处理异步异常上抛（debug 红屏/zone 错误）
      final exc = tester.takeException();
      expect(exc, isNull,
          reason: '修复目标：恢复进度查询抛错必须被 try/catch 捕获，'
              '不得作为未处理异步异常上抛（修复前：takeException 非空）');

      // 修复目标：按无进度继续播放 → 仍进播放页
      await tester.pumpAndSettle();
      expect(find.text('Player'), findsOneWidget,
          reason: '修复目标：查询失败时按无进度播放，仍应进入播放页'
              '（修复前：await 抛错中断 onFileTap，不跳 /player，点击静默失效）');
    });

    testWidgets('DAO 读进度抛错 → debugPrint 记失败日志（catch-log 裁决）', (tester) async {
      await captureDebugPrint((logs) async {
        await _pumpBrowser(tester);

        await tester.tap(find.text('chapter_01.mp3'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        tester.takeException();

        await tester.pumpAndSettle();
        expect(find.text('Player'), findsOneWidget, reason: '前置：进入播放页');

        expect(logs.join('\n'),
            contains('[Browser] play: progress resume lookup failed'),
            reason: '修复目标：失败路径必须 debugPrint 记录（catch-log 裁决，'
                'SCHEMA.md §5 + playlist_detail_screen.dart:73-74 同款；'
                '修复前该路径无任何日志）');
      });
    });

    testWidgets('长按路径（onFileLongPress）查询抛错同样不抛未处理异常', (tester) async {
      await _pumpBrowser(tester);

      await tester.longPress(find.text('chapter_01.mp3'));
      await tester.pumpAndSettle();

      final exc = tester.takeException();
      expect(exc, isNull,
          reason: '修复目标：onFileLongPress 的进度查询同样被捕获'
              '（勘察发现 browser_screen.dart:167-170 同类裸奔点，'
              '修复前 takeException 非空）');
    });
  });
}
