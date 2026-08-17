// test/features/playlist/bug_bug15_repro_test.dart
// BUG-15: 新建播放单 fire-and-forget 无错误处理，DB 失败成未捕获异常
// （spec: docs/features/BUG-15.md §5.4，来源 cr-20260816-0804 F2）
//
// 缺陷：playlist_list_screen.dart:166-170（_CreatePlaylistDialogState 创建
// 按钮）— `ref.read(createPlaylistProvider)(name); Navigator.of(context).pop();`
// 不 await、无 try/catch。对比同文件删除路径 :71-88 有完整
// try/catch + SnackBar + debugPrint（BUG-25-S3 纪律）；add_tracks 路径
// add_tracks_browser.dart:102-116 也有 .catchError。
// → insert 抛异常时 Future 无人 await → unhandled async exception
//   （debug 崩测试 zone / release 走 FlutterError.onError），用户无反馈，
//   对话框已关。
//
// 门禁（修复前必须 FAIL）：
//   BUG-15-S1: 创建播放单 DB 写入失败 → 必须显示"创建失败"SnackBar 且
//              无未捕获异常 —— 当前代码 unhandled async exception 使
//              testWidgets 失败

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nas_audio_player/features/playlist/playlist_list_screen.dart';
import 'package:nas_audio_player/features/playlist/playlist_provider.dart';
import 'package:nas_audio_player/shared/models/playlist.dart';

void main() {
  testWidgets('BUG-15-S1: 创建播放单失败 → 显示"创建失败"SnackBar、无未捕获异常（当前缺失）',
      (tester) async {
    // Given: 播放单列表为空，createPlaylistProvider 注入 DB 写失败。
    await tester.pumpWidget(ProviderScope(
      overrides: [
        playlistListProvider.overrideWith((ref) async => <Playlist>[]),
        createPlaylistProvider.overrideWith(
          (ref) => (String name) async {
            throw Exception('模拟 DB 写入失败');
          },
        ),
      ],
      child: const MaterialApp(home: Scaffold(body: PlaylistListScreen())),
    ));
    await tester.pumpAndSettle();

    // When: 用户新建播放单并输入名称后点"创建"。
    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '测试单');
    await tester.tap(find.text('创建'));
    await tester.pumpAndSettle();

    // Then: 必须显示错误 SnackBar（与删除路径 BUG-25-S3 同款纪律），
    // 且不得有未捕获异常泄漏到测试 zone。
    expect(find.textContaining('创建失败'), findsOneWidget,
        reason: 'BUG-15（cr-20260816-0804 F2）：playlist_list_screen.dart:'
            '166-170 创建播放单 fire-and-forget —— `ref.read('
            'createPlaylistProvider)(name)` 不 await、无 try/catch，DB 写失败'
            '成 unhandled async exception（本测试在缺陷态因该未捕获异常'
            '直接失败），用户无任何反馈。必须与删除路径（:71-88，'
            'BUG-25-S3）同款：await + try/catch + 失败 log + SnackBar。');
  });
}
