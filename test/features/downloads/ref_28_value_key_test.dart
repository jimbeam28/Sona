// test/features/downloads/ref_28_value_key_test.dart
//
// ═══════════════════════════════════════════════════════════════════════════
// dev-exe Agent A · 测试先行 · 此时无实现，FAIL 预期
// ═══════════════════════════════════════════════════════════════════════════
//
// REF-28-S1 门禁测试（docs/features/REF-28.md §5.4 指定位置）。
// 下载管理页（DL-01-S9）每行 _DownloadRow 必须以 DownloadRecord.id 为
// ValueKey 值（spec §3 REF-28-S1 Then 字面），而非列表下标。
//
// 机械结构照抄 dl_01_download_test.dart DL-01-S9 组（_makeWidgetEnv /
// _downloadsOverrides / _drainRefreshTimers 样式），键断言所需真实 id 一律
// 从 dao 读回（findByLocation / listByConnection），禁止猜测。

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nas_audio_player/core/contracts/database_contract.dart';
import 'package:nas_audio_player/core/database/dao/download_dao.dart';
import 'package:nas_audio_player/core/network/webdav_client.dart';
import 'package:nas_audio_player/core/services/download_manager.dart';
import 'package:nas_audio_player/features/connection/connection_provider.dart';
import 'package:nas_audio_player/features/downloads/downloads_provider.dart';
import 'package:nas_audio_player/features/downloads/downloads_screen.dart';
import 'package:nas_audio_player/shared/models/connection_config.dart';
import 'package:nas_audio_player/shared/models/nas_file.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../helpers/test_database.dart';
import '../../helpers/widget_helpers.dart';

// ═══════════════════════════════════════════════════════════════════════════
// 共享夹具（机械结构照抄 dl_01_download_test.dart DL-01-S9 组）
// ═══════════════════════════════════════════════════════════════════════════

final _t0 = DateTime(2026, 8, 23);
final _ts = _t0.millisecondsSinceEpoch;

final _conn = ConnectionConfig(
  id: 1,
  name: 'NAS',
  url: 'http://nas.example.com',
  username: 'admin',
  isActive: true,
  createdAt: _t0,
  updatedAt: _t0,
);

/// 构造一条 DownloadRecord（测试播种用，id 由 DB 自增分配）。
DownloadRecord _rec(String path, String status,
    {int? updatedAt, String? local}) {
  return DownloadRecord(
    connectionId: 1,
    filePath: path,
    fileName: path.split('/').last,
    remoteSize: 100,
    localPath: local ?? '/nonexistent${path.replaceAll('/', '_')}',
    status: status,
    bytesDownloaded: 0,
    createdAt: _ts,
    updatedAt: updatedAt ?? _ts,
  );
}

/// 引擎假客户端：downloadFile 永久挂起（UI 渲染测试不需要真下载完成）。
class _FakeDownloadClient implements WebDavClientInterface {
  _FakeDownloadClient({this.hangByDefault = false});
  final bool hangByDefault;

  @override
  Future<void> downloadFile({
    required String url,
    required String filePath,
    required String username,
    required String password,
    required String saveTo,
    void Function(int received, int? total)? onProgress,
  }) async {
    if (hangByDefault) {
      await Completer<void>().future;
    }
  }

  @override
  Future<List<NasFile>> listDirectory({
    required String url,
    required String username,
    required String password,
    required String path,
  }) =>
      throw UnimplementedError('listDirectory not needed for download tests');

  @override
  Future<WebDavValidationResult> validate({
    required String url,
    required String username,
    required String password,
    String basePath = '/',
  }) =>
      throw UnimplementedError('validate not needed for download tests');
}

/// DownloadFileSystem 注入端口的真实临时目录实现。
class _TempDirFs implements DownloadFileSystem {
  final String root;
  _TempDirFs(this.root);

  @override
  Future<void> ensureReady() async {}

  @override
  String get downloadRoot => root;

  @override
  bool exists(String path) => File(path).existsSync();

  @override
  void delete(String path) {
    try {
      final f = File(path);
      if (f.existsSync()) f.deleteSync();
    } catch (_) {
      // 尽力而为（契约：吞异常不抛）
    }
  }
}

class _WidgetEnv {
  _WidgetEnv({
    required this.db,
    required this.dao,
    required this.fs,
    required this.tempDir,
  });

  final Database db;
  final DownloadDao dao;
  final _TempDirFs fs;
  final Directory tempDir;
}

Future<_WidgetEnv> _makeWidgetEnv() async {
  final db = await openTestDatabase(TestSchema.full);
  await seedConnection(db);
  addTearDown(db.close);
  // 机械适配：testWidgets 的 FakeAsync 区内真实异步 IO（createTemp）永不完成，
  // 须用同步变体（teardown 的递归删除在 body 外执行，可保留 async）。
  final tempDir = Directory.systemTemp.createTempSync('ref28_dl');
  addTearDown(() async {
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });
  return _WidgetEnv(
    db: db,
    dao: DownloadDao(),
    fs: _TempDirFs('${tempDir.path}/downloads'),
    tempDir: tempDir,
  );
}

/// DL-01-S9 组的四 overrides 装配（activeConnection / downloadDao /
/// downloadFileSystem / downloadManager）。
List<Override> _downloadsOverrides(_WidgetEnv env) => [
      activeConnectionProvider.overrideWith((ref) async => _conn),
      downloadDaoProvider.overrideWithValue(env.dao),
      downloadFileSystemProvider.overrideWithValue(env.fs),
      downloadManagerProvider.overrideWith((ref) => DownloadManager(
            client: _FakeDownloadClient(hangByDefault: true),
            dao: env.dao,
            fs: env.fs,
          )),
    ];

// ═══════════════════════════════════════════════════════════════════════════
// 测试主体
// ═══════════════════════════════════════════════════════════════════════════

void main() {
  setUpAll(() => initSqfliteFfi());

  testWidgets('REF-28-S1: 下载管理页行键值 = DownloadRecord.id（业务主键）', (tester) async {
    final env = await _makeWidgetEnv();

    // 播种两行；updatedAt 错开使展示序确定（listByConnection 按 updated_at DESC）
    // done 行配真实本地成品（照 DL-01-S9 播种样式，行渲染语义与既有组一致）。
    final donePath = '${env.tempDir.path}/b_done_local.mp3';
    File(donePath)
      ..parent.createSync(recursive: true)
      ..writeAsStringSync('done-bytes', flush: true);
    await env.dao
        .upsert(_rec('/a.mp3', DownloadStatus.pending, updatedAt: _ts));
    await env.dao.upsert(_rec('/b.mp3', DownloadStatus.done,
        updatedAt: _ts - 1000, local: donePath));

    // 从 dao 读回真实 id（不能猜）：首行 = listByConnection().first
    final rows = await env.dao.listByConnection(1);
    expect(rows.map((r) => r.filePath).toList(), ['/a.mp3', '/b.mp3'],
        reason: '前置：展示序由 updated_at DESC 决定，首行为 /a.mp3');
    final firstId = rows.first.id!;
    expect(firstId, isNotNull, reason: '前置：正常 DB 行恒有自增 id');

    await tester.pumpWidget(buildTestApp(
      DownloadsScreen(),
      overrides: _downloadsOverrides(env),
    ));
    await tester.pumpAndSettle();
    final container =
        ProviderScope.containerOf(tester.element(find.byType(DownloadsScreen)));
    addTearDown(container.dispose);

    expect(find.text('a.mp3'), findsOneWidget, reason: '前置：首行 /a.mp3 已渲染');
    expect(find.text('b.mp3'), findsOneWidget, reason: '前置：次行 /b.mp3 已渲染');

    expect(find.byKey(ValueKey<int?>(firstId)), findsOneWidget,
        reason: 'REF-28-S1 Then：首行 _DownloadRow 键值必须为 record.id（$firstId，'
            'downloads 表主键，int? 型——与实现 ValueKey(record.id) 同型匹配），'
            '而不是列表下标——行元素按业务身份匹配');

    // 收尾排水（照 DL-01-S9）：清空 downloads 行并驱动两秒虚拟时钟，
    // 让「仅有 downloading 时运行」的 Timer.periodic 有机会自我取消（P13）。
    await env.db.delete('downloads');
    await tester.pump(const Duration(seconds: 2));
    await tester.pump(const Duration(seconds: 2));
  });
}
