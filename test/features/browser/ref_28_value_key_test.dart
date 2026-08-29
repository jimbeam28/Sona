// test/features/browser/ref_28_value_key_test.dart
//
// ═══════════════════════════════════════════════════════════════════════════
// dev-exe Agent A · 测试先行 · 此时无实现，FAIL 预期
// ═══════════════════════════════════════════════════════════════════════════
//
// REF-28-S2 门禁测试（docs/features/REF-28.md §5.4 指定位置）。
// 搜索命中 ListTile（SRCH-01）必须以 hit.file.path（命中文件相对连接根的
// 路径）为 ValueKey 值（spec §3 REF-28-S2 Then 字面），而非列表下标。
//
// 渲染 harness 机械结构照抄 srch_01_folder_search_test.dart 搜索面板 widget
// 组（_SearchTree → directoryContentsProvider 覆写 / _MapProgressDao /
// _makePlayer / 打开面板 → 输入 query），搜索面板结构零改动。

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:mockito/mockito.dart';
import 'package:nas_audio_player/core/database/dao/progress_dao.dart';
import 'package:nas_audio_player/core/network/webdav_client.dart';
import 'package:nas_audio_player/features/browser/browser_provider.dart';
import 'package:nas_audio_player/features/browser/browser_screen.dart';
import 'package:nas_audio_player/features/connection/connection_provider.dart';
import 'package:nas_audio_player/features/player/player_provider.dart';
import 'package:nas_audio_player/features/progress/progress_provider.dart';
import 'package:nas_audio_player/shared/models/nas_file.dart';
import 'package:nas_audio_player/shared/models/play_progress.dart';
import 'package:nas_audio_player/shared/models/play_queue.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/fake_secure_storage.dart';
import '../../helpers/mock_audio_player.dart';
import '../../helpers/test_factories.dart';
import '../../helpers/widget_helpers.dart';

// ═══════════════════════════════════════════════════════════════════════════
// 共享夹具（机械结构照抄 srch_01_folder_search_test.dart 搜索面板组）
// ═══════════════════════════════════════════════════════════════════════════

/// 假目录树：同时供给主列表（directoryContentsProvider）与扫描会话
/// （webDavClientProvider，BUG-33 后扫描直连 webDav 端口）。
class _SearchTree {
  final Map<String, List<NasFile>> listings = {};
  final List<String> calls = [];

  void put(String path, List<NasFile> entries) => listings[path] = entries;

  Future<List<NasFile>> fetch(String path) async {
    calls.add(path);
    return listings[path] ?? const <NasFile>[];
  }

  Override get override =>
      directoryContentsProvider.overrideWith((ref, path) => fetch(path));

  Override get webDavOverride =>
      webDavClientProvider.overrideWithValue(_TreeScanDavClient(this));

  Override get scanStorageOverride => secureStorageProvider.overrideWithValue(
      FakeSecureStorage()..setPassword(testConnection().id ?? 1, 'pw'));
}

class _TreeScanDavClient implements WebDavClientInterface {
  _TreeScanDavClient(this._tree);
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

// ═══════════════════════════════════════════════════════════════════════════
// 测试主体
// ═══════════════════════════════════════════════════════════════════════════

void main() {
  testWidgets('REF-28-S2: 搜索命中行键值 = hit.file.path（相对连接根路径）', (tester) async {
    // 目录树：根 / 下两级目录 a/b，命中文件相对连接根（basePath=/）路径
    // /a/b/hit.mp3 —— spec 语义取 hit.file.path，同一连接内唯一。
    final tree = _SearchTree()
      ..put('/', [testDir('a', '/a')])
      ..put('/a', [testDir('b', '/a/b')])
      ..put('/a/b', [testAudio('hit.mp3', '/a/b/hit.mp3')]);

    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    final (player, controller) = _makePlayer();
    await tester.pumpWidget(buildTestAppWithPlayerRoute(
      Scaffold(body: BrowserScreen()),
      overrides: [
        tree.override,
        tree.webDavOverride,
        tree.scanStorageOverride,
        activeConnectionProvider.overrideWith((ref) async => testConnection()),
        progressDaoProvider.overrideWithValue(_MapProgressDao(const {})),
        audioPlayerProvider.overrideWithValue(player),
        playModeProvider.overrideWith((ref) => PlayMode.sequential),
        sharedPreferencesProvider.overrideWithValue(prefs),
      ],
    ));
    addTearDown(controller.close);
    await tester.pumpAndSettle();
    final container =
        ProviderScope.containerOf(tester.element(find.byType(BrowserScreen)));
    addTearDown(container.dispose);
    // 监听保活：显式订阅 searchSessionProvider（widget 外再保一路，防 autoDispose）
    container.listen(searchSessionProvider, (prev, next) {});

    // 打开面板 → 输入 query（面板内 onChanged → onQueryChanged，500ms debounce）
    await tester.tap(find.byIcon(Icons.search));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'hit');
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();

    expect(tree.calls, contains('/a/b'), reason: '前置：扫描确实到达含命中文件的目录 /a/b');
    expect(find.textContaining(RegExp('命中\\s*1')), findsOneWidget,
        reason: '前置：扫描完成且恰一条命中');
    expect(find.widgetWithText(ListTile, 'hit.mp3'), findsOneWidget,
        reason: '前置：命中行已渲染为 ListTile（srch_01 同款定位）');

    expect(find.byKey(const ValueKey('/a/b/hit.mp3')), findsOneWidget,
        reason: 'REF-28-S2 Then：搜索命中 ListTile 键值必须为 hit.file.path'
            '（相对连接根路径 /a/b/hit.mp3），而不是列表下标');
  });
}
