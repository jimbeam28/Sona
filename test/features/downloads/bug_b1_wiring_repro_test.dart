// test/features/downloads/bug_b1_wiring_repro_test.dart
// B1 复现门禁：生产 downloadManagerProvider 未接线 remoteUrlResolver →
// 真实下载 GET http://localhost 必失败（cr-20260826-0027 B1，Critical）。
//
// 本测试在 dev-plan 阶段先写（Bug 硬门禁），修复前必须 FAIL：
//   断言生产装配的 manager 使用的下载 URL == 该条连接的有效 base URL
//   （webDavEffectiveBaseUrl(conn.url, conn.basePath)）。
// 当前生产 downloads_provider.dart:36-48 未传 remoteUrlResolver →
// download_manager.dart:302 回退占位基址 'http://localhost' → 断言 FAIL。
// 修复后（provider 按 entry.connectionId 解析连接有效基址）→ 断言 PASS。
//
// 注：本测试同时是 T1（provider 级装配回归锚）的载体——直接 build 真实
// downloadManagerProvider，不走 overrideWith 自构。

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nas_audio_player/core/contracts/database_contract.dart';
import 'package:nas_audio_player/core/database/dao/connection_dao.dart';
import 'package:nas_audio_player/core/database/dao/download_dao.dart';
import 'package:nas_audio_player/core/network/webdav_client.dart';
import 'package:nas_audio_player/core/services/download_manager.dart';
import 'package:nas_audio_player/features/connection/connection_provider.dart';
import 'package:nas_audio_player/features/downloads/downloads_provider.dart';
import 'package:nas_audio_player/shared/models/nas_file.dart';
import 'package:nas_audio_player/shared/webdav_paths.dart';

import '../../helpers/fake_secure_storage.dart';
import '../../helpers/test_database.dart';
import '../../helpers/test_factories.dart';

/// 记录 downloadFile 收到的 url 的 WebDavClientInterface 假实现。
class _UrlRecordingClient implements WebDavClientInterface {
  final List<String> calledUrls = [];

  @override
  Future<void> downloadFile({
    required String url,
    required String filePath,
    required String username,
    required String password,
    required String saveTo,
    void Function(int received, int? total)? onProgress,
  }) async {
    calledUrls.add(url);
    final f = File(saveTo)..parent.createSync(recursive: true);
    f.writeAsStringSync('ok:$filePath', flush: true);
  }

  @override
  Future<List<NasFile>> listDirectory({
    required String url,
    required String username,
    required String password,
    required String path,
  }) =>
      throw UnimplementedError('not needed');

  @override
  Future<WebDavValidationResult> validate({
    required String url,
    required String username,
    required String password,
    String basePath = '/',
  }) =>
      throw UnimplementedError('not needed');
}

/// 轮询直至异步条件成立或超时（B1 下载泵异步完成）。
Future<void> _waitUntil(
  Future<bool> Function() cond, {
  int maxMs = 3000,
  String? reason,
}) async {
  var waited = 0;
  while (!await cond() && waited < maxMs) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
    waited += 10;
  }
  expect(await cond(), isTrue, reason: reason ?? '轮询等待超时（${maxMs}ms）');
}

void main() {
  setUpAll(initSqfliteFfi);

  test('B1: 生产 downloadManagerProvider 下载 URL == 连接有效 base URL', () async {
    final db = await openTestDatabase(TestSchema.downloads);
    await seedConnection(db, id: 1);
    addTearDown(db.close);

    final tempDir = await Directory.systemTemp.createTemp('b1_repro');
    addTearDown(() async {
      try {
        await tempDir.delete(recursive: true);
      } catch (_) {}
    });

    final client = _UrlRecordingClient();
    final storage = FakeSecureStorage()..setPassword(1, 'pw');
    final fs = IoDownloadFileSystem.atRoot('${tempDir.path}/downloads');

    final container = ProviderContainer(overrides: [
      webDavClientProvider.overrideWithValue(client),
      secureStorageProvider.overrideWithValue(storage),
      connectionDaoProvider.overrideWithValue(ConnectionDao()),
      downloadDaoProvider.overrideWithValue(DownloadDao()),
      downloadFileSystemProvider.overrideWithValue(fs),
    ]);
    addTearDown(container.dispose);

    // 读真实生产装配（不 override downloadManagerProvider 自身）。
    final manager = container.read(downloadManagerProvider);
    await manager.enqueueMany([
      (1, testAudio('a.mp3', '/music/a.mp3')),
    ]);

    await _waitUntil(() async {
      final rec = await DownloadDao().findByLocation(1, '/music/a.mp3');
      return rec?.status == DownloadStatus.done;
    }, reason: '下载应完成');

    // 种子连接的 url=http://nas.local:5005, base_path='/'（test_database.dart:126-127）。
    final expected = webDavEffectiveBaseUrl('http://nas.local:5005', '/');
    expect(client.calledUrls, isNotEmpty, reason: 'downloadFile 应被调用');
    expect(client.calledUrls.single, expected,
        reason: '生产装配必须按连接解析 effective base URL，而非占位基址');
  });
}
