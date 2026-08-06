// test/features/home/test_03_home3_test.dart
// TEST-03-HOME3: Tab 索引持久化（spec: docs/features/TEST-03.md）
//
// TEST-03-S3  预置 'home_tab_index'=1 → 启动恢复文件浏览 Tab（Tab 1），
//             且启动时不得重置写回
// TEST-03-S4  切 Tab → SharedPreferences 'home_tab_index' 每次切换都写回
//             （0→1 写 1，1→0 写 0）；未切换时保持初始值
// TEST-03-S5  预置越界 index=5 → graceful 回落 Tab 0，不抛异常
//
// 全部用例 pump 真实 HomeScreen，断言真实 widget 树内容
// （Tab 0 = '还没有播放单，点击 + 新建'，Tab 1 = '此目录为空'），
// 不做本地副本自证。
//
// 生产代码出处（spec 锚定，禁读 lib/）：
//   lib/features/home/home_screen.dart:34-40  savedIndex 恢复 + 越界判定
//   lib/features/home/home_screen.dart:42-46  写回监听器

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:nas_audio_player/features/browser/browser_provider.dart';
import 'package:nas_audio_player/features/home/home_screen.dart';
import 'package:nas_audio_player/features/playlist/playlist_provider.dart';
import 'package:nas_audio_player/shared/models/nas_file.dart';
import 'package:nas_audio_player/shared/models/playlist.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ── Helpers ───────────────────────────────────────────────────────────────────

Widget _buildTestApp({List<Override>? overrides}) {
  final router = GoRouter(
    initialLocation: '/home',
    routes: [
      GoRoute(
        path: '/home',
        builder: (_, __) => const HomeScreen(),
      ),
      GoRoute(
        path: '/settings',
        builder: (_, __) =>
            const Scaffold(body: Center(child: Text('Settings'))),
      ),
    ],
  );
  return ProviderScope(
    overrides: overrides ?? [],
    child: MaterialApp.router(routerConfig: router),
  );
}

List<Override> _defaultOverrides() => [
      playlistListProvider.overrideWith((ref) => Future.value(<Playlist>[])),
      directoryContentsProvider('/')
          .overrideWith((ref) => Future.value(<NasFile>[])),
    ];

/// 预置 mock 存储并返回 [SharedPreferences] 实例，同时注入
/// sharedPreferencesProvider，供 HomeScreen 恢复/写回。
Future<SharedPreferences> _pumpWithPrefs(
  WidgetTester tester, {
  required Map<String, Object> initialValues,
}) async {
  SharedPreferences.setMockInitialValues(initialValues);
  final prefs = await SharedPreferences.getInstance();
  await tester.pumpWidget(_buildTestApp(
    overrides: [
      ..._defaultOverrides(),
      sharedPreferencesProvider.overrideWithValue(prefs),
    ],
  ));
  await tester.pumpAndSettle();
  return prefs;
}

// ═════════════════════════════════════════════════════════════════════════════
// TEST-03-S3: 预置 index=1 启动落浏览器 Tab
// ═════════════════════════════════════════════════════════════════════════════

void main() {
  group('TEST-03-S3: 预置 index=1 启动恢复文件浏览 Tab', () {
    testWidgets('TEST-03-S3: 预置 home_tab_index=1 → TabBarView 展示浏览器内容',
        (WidgetTester tester) async {
      final prefs = await _pumpWithPrefs(
        tester,
        initialValues: {'home_tab_index': 1},
      );

      // Tab 1 浏览器空态可见
      expect(find.text('此目录为空'), findsOneWidget,
          reason: '预置 index=1 时应恢复文件浏览 Tab（浏览器内容可见）');
      // 否定断言：不得默认选 Tab 0
      expect(find.text('还没有播放单，点击 + 新建'), findsNothing,
          reason: '否定断言：预置 index=1 时不得选中 Tab 0');
      // 否定断言：启动是恢复而非重置 —— prefs 值不得被覆盖为 0
      expect(prefs.getInt('home_tab_index'), 1,
          reason: '否定断言：启动恢复后不得重置写回 prefs（应保持 1）');
    });

    testWidgets('TEST-03-S3: 预置 index=0 仍选 Tab 0（行为不回归）',
        (WidgetTester tester) async {
      final prefs = await _pumpWithPrefs(
        tester,
        initialValues: {'home_tab_index': 0},
      );

      expect(find.text('还没有播放单，点击 + 新建'), findsOneWidget,
          reason: '预置 index=0 时应选中播放单 Tab（行为不改变）');
      expect(find.text('此目录为空'), findsNothing, reason: '预置 index=0 时不得显示浏览器内容');
      expect(prefs.getInt('home_tab_index'), 0,
          reason: '预置 index=0 时 prefs 保持 0');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // TEST-03-S4: 切 Tab 后 prefs 写回
  // ═══════════════════════════════════════════════════════════════════════════

  group('TEST-03-S4: 切 Tab 每次切换都写回 prefs', () {
    testWidgets('TEST-03-S4: Tab 0→1 写 1，1→0 写 0，未切换时保持初始值',
        (WidgetTester tester) async {
      final prefs = await _pumpWithPrefs(tester, initialValues: {});

      // 默认 Tab 0
      expect(find.text('还没有播放单，点击 + 新建'), findsOneWidget,
          reason: '前置：无预置值时默认 Tab 0');
      // 否定断言：未切换时 prefs 应保持初始值（不写回）
      expect(prefs.getInt('home_tab_index'), isNull,
          reason: '否定断言：未切换 Tab 时不得写回 prefs（保持初始值）');

      // 切到 Tab 1（文件浏览）
      await tester.tap(find.text('文件浏览器'));
      await tester.pumpAndSettle();
      expect(find.text('此目录为空'), findsOneWidget, reason: '切到 Tab 1 后应展示浏览器内容');
      expect(prefs.getInt('home_tab_index'), 1,
          reason: '切到 Tab 1 后 prefs 必须写回 1（持久化）');

      // 切回 Tab 0（播放单）
      await tester.tap(find.text('播放单'));
      await tester.pumpAndSettle();
      expect(find.text('还没有播放单，点击 + 新建'), findsOneWidget,
          reason: '切回 Tab 0 后应展示播放单内容');
      expect(prefs.getInt('home_tab_index'), 0,
          reason: '切回 Tab 0 后 prefs 必须写回 0（每次切换都持久化）');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // TEST-03-S5: savedIndex 越界回落
  // ═══════════════════════════════════════════════════════════════════════════

  group('TEST-03-S5: 越界 index graceful 回落 Tab 0', () {
    testWidgets('TEST-03-S5: 预置 home_tab_index=5 → 回落 Tab 0、不抛异常',
        (WidgetTester tester) async {
      await _pumpWithPrefs(
        tester,
        initialValues: {'home_tab_index': 5},
      );

      // 否定断言：不得选中越界 Tab 5 —— 应回落到 Tab 0
      expect(find.text('还没有播放单，点击 + 新建'), findsOneWidget,
          reason: '否定断言：越界 index 应回落到 Tab 0（播放单内容可见）');
      expect(find.text('此目录为空'), findsNothing,
          reason: '否定断言：越界 index 不得选中文件浏览 Tab');
      // 否定断言：越界不抛异常 —— pumpAndSettle 已完成即 graceful
    });
  });
}
