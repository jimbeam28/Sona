// test/features/downloads/dl_01_download_test.dart
//
// ═══════════════════════════════════════════════════════════════════════════
// dev-exe Agent A · 测试先行 · 此时无实现，FAIL 预期
// ═══════════════════════════════════════════════════════════════════════════
//
// DL-01 离线下载门禁测试（docs/features/DL-01.md §5.4 指定位置）。
//
// ID 覆盖索引：
//   DL-01-S1  DB v3 迁移（全新安装 + 升级路径 v2→v3 / v1→v3）
//   DL-01-S2  IDownloadDao 十方法契约行为
//   DL-01-S3  downloadFile 流式下载引擎（本机 HttpServer 假源）
//   DL-01-S4  sanitizeBaseName / resolveCollision 纯函数策略
//   DL-01-S5  DownloadManager 串行泵（dedupe / cancel / retry / 节流）
//   DL-01-S6  orchestrator 本地优先加载（含 §8-R2 AudioSource.file 冒烟）
//   DL-01-S7  文件长按菜单「下载此文件」widget 测试
//   DL-01-S8  目录菜单第三项「下载此文件夹」widget 测试
//   DL-01-S9  /downloads 管理页 widget 测试
//   DL-01-S10 recoverOrphanDownloads 启动孤儿恢复
//   DL-01-INV1~INV5 / DL-01-ALG1 / DL-01-ALG2
//
// §5.3 盲点补偿锚点：
//   S9 节流刷新 → DL-01-S5 双档 throttle 用例（标题带 §5.3/S9 字样）
//   S6 superseded 竞态 → DL-01-S6 第 4 例
//   S3 chunk 超时 → DL-01-S3 最后一例
//
// 实现方注意（Agent A 在契约外做的机械假设；偏差时只许机械适配定位方式，
// 不许改断言语义）：
//   * S9 行尾按钮按「ListTile + IconButton」惯例定位（重试=首个、删除=末个）；
//     清空全部确认对话框的确认键取 AlertDialog 内最后一个 TextButton。
//   * S7/S9 中泵会因 enqueueMany 自动启动：挂起型 fake client 下行稳定处于
//     downloading；严格 pending-at-rest 语义已在 S5 用 head-block 技术钉死。
//   * S3 用本机 HttpServer 充当假 NAS（纯 dart:io，规避 package:http import）。
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:mockito/mockito.dart';
import 'package:nas_audio_player/core/database/dao/download_dao.dart';
import 'package:nas_audio_player/core/database/dao/progress_dao.dart';
import 'package:nas_audio_player/core/contracts/database_contract.dart';
import 'package:nas_audio_player/core/database/database_helper.dart';
import 'package:nas_audio_player/core/network/webdav_client.dart';
import 'package:nas_audio_player/core/services/audio_source_builder.dart';
import 'package:nas_audio_player/core/services/download_manager.dart';
import 'package:nas_audio_player/features/browser/browser_provider.dart';
import 'package:nas_audio_player/features/browser/browser_screen.dart';
import 'package:nas_audio_player/features/connection/connection_provider.dart';
import 'package:nas_audio_player/features/downloads/domain/download_policy.dart';
import 'package:nas_audio_player/features/downloads/downloads_provider.dart';
import 'package:nas_audio_player/features/downloads/downloads_screen.dart';
import 'package:nas_audio_player/features/player/domain/playback_orchestrator.dart';
import 'package:nas_audio_player/features/player/player_provider.dart';
import 'package:nas_audio_player/features/progress/progress_provider.dart';
import 'package:nas_audio_player/shared/models/connection_config.dart';
import 'package:nas_audio_player/shared/models/nas_file.dart';
import 'package:nas_audio_player/shared/models/play_progress.dart';
import 'package:nas_audio_player/shared/models/play_queue.dart';
import 'package:shared_preferences/shared_preferences.dart';
// 机械修正：包内库文件名为 sqflite_ffi.dart（sqflite_common_ffi.dart 不存在）。
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../helpers/mock_audio_player.dart';
import '../../helpers/test_database.dart';
import '../../helpers/test_factories.dart';
import '../../helpers/widget_helpers.dart';

// ═══════════════════════════════════════════════════════════════════════════
// 共享夹具
// ═══════════════════════════════════════════════════════════════════════════

final _t0 = DateTime(2026, 8, 23);
final _ts = _t0.millisecondsSinceEpoch;
final _tsOld = _t0.subtract(const Duration(hours: 1)).millisecondsSinceEpoch;

final _conn = ConnectionConfig(
  id: 1,
  name: 'NAS',
  url: 'http://nas.example.com',
  username: 'admin',
  isActive: true,
  createdAt: _t0,
  updatedAt: _t0,
);

/// 构造一条 DownloadRecord（测试播种用）。
DownloadRecord _rec(
  String path,
  String status, {
  int connectionId = 1,
  int remote = 100,
  int bytes = 0,
  String? local,
  int? updatedAt,
}) {
  return DownloadRecord(
    connectionId: connectionId,
    filePath: path,
    fileName: path.split('/').last,
    remoteSize: remote,
    localPath: local ?? '/nonexistent${path.replaceAll('/', '_')}',
    status: status,
    bytesDownloaded: bytes,
    createdAt: _ts,
    updatedAt: updatedAt ?? _ts,
  );
}

/// 轮询直到异步条件成立或超时（真实时间，配合挂起型 fake 引擎使用）。
Future<void> _waitUntilAsync(Future<bool> Function() cond,
    {int maxMs = 3000, String? reason}) async {
  var waited = 0;
  while (!await cond() && waited < maxMs) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
    waited += 10;
  }
  expect(await cond(), isTrue, reason: reason ?? '轮询等待超时（${maxMs}ms）');
}

/// 递归列出目录下全部普通文件路径（目录不存在返回空表）。
List<String> _allFilesUnder(String dirPath) {
  final dir = Directory(dirPath);
  if (!dir.existsSync()) return const <String>[];
  return dir
      .listSync(recursive: true)
      .whereType<File>()
      .map((f) => f.path)
      .toList(growable: false);
}

// ── FakeDownloadClient：WebDavClientInterface 的可编程假实现 ──────────────────

/// 单条下载脚本：进度刻度 → 挂起门 → 错误注入。
class _ScriptedDownload {
  /// 依次回调 onProgress(tick, null)，每刻之间隔一个事件循环轮次。
  final List<int> progressTicks;

  /// 非 null 时挂起直到测试放行（模拟大文件传输中）。
  final Completer<void>? hangGate;

  /// 非 null 时在挂起之后抛出（模拟失败路径）。
  final Object? error;

  const _ScriptedDownload({
    this.progressTicks = const <int>[],
    this.hangGate,
    this.error,
  });
}

/// 引擎假客户端（INV4：一切网络 IO 经此端口注入）。
///
/// 成品产物模拟：先写出 `<saveTo>.part`（模拟传输落盘），成功路径再 rename
/// 成成品——与生产 .part 原子语义同构，使 cancel/deleteEntry 的「.part 兜底
/// 清理」断言有真实残留物可查。
class _FakeDownloadClient implements WebDavClientInterface {
  final Map<String, _ScriptedDownload> scripts;
  final bool hangByDefault;

  final calledUrls = <String>[];
  final calledPaths = <String>[];
  int currentConcurrent = 0;
  int maxConcurrent = 0;

  _FakeDownloadClient({
    Map<String, _ScriptedDownload>? scripts,
    this.hangByDefault = false,
  }) : scripts = scripts ?? <String, _ScriptedDownload>{};

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
    calledPaths.add(filePath);
    currentConcurrent++;
    if (currentConcurrent > maxConcurrent) maxConcurrent = currentConcurrent;
    try {
      // 先落 .part（模拟传输开始写盘）
      final part = File('$saveTo.part');
      part.parent.createSync(recursive: true);
      part.writeAsStringSync('partial:$filePath', flush: true);

      final script = scripts[filePath];
      for (final tick in script?.progressTicks ?? const <int>[]) {
        onProgress?.call(tick, null);
        await Future<void>.delayed(Duration.zero);
      }
      final gate = script?.hangGate;
      if (gate != null) {
        await gate.future;
      } else if (hangByDefault && script == null) {
        await Completer<void>().future; // UI 测试：永久挂起防真下载完成
      }
      final error = script?.error;
      if (error != null) throw error;

      // 成功路径：.part → 成品（原子改名语义）
      final target = File(saveTo);
      if (part.existsSync()) {
        await part.rename(target.path);
      } else {
        target.writeAsStringSync('data:$filePath', flush: true);
      }
    } finally {
      currentConcurrent--;
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

// ── TempDirFs：DownloadFileSystem 注入端口的真实临时目录实现 ─────────────────

class _TempDirFs implements DownloadFileSystem {
  final String root;
  _TempDirFs(this.root);

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

// ── Manager 测试环境 ─────────────────────────────────────────────────────────

typedef _ManagerEnv = ({
  DownloadManager manager,
  _FakeDownloadClient client,
  _TempDirFs fs,
  DownloadDao dao,
  Directory tempDir,
});

Future<_ManagerEnv> _makeManagerEnv({
  Duration progressThrottle = const Duration(milliseconds: 250),
  String Function()? remoteUrlResolver,
  Map<String, _ScriptedDownload>? scripts,
  bool hangByDefault = false,
}) async {
  final db = await openTestDatabase(TestSchema.downloads);
  await seedConnection(db);
  addTearDown(db.close);
  final tempDir = await Directory.systemTemp.createTemp('dl01_mgr');
  addTearDown(() async {
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });
  final dao = DownloadDao();
  final client =
      _FakeDownloadClient(scripts: scripts, hangByDefault: hangByDefault);
  final fs = _TempDirFs('${tempDir.path}/downloads');
  final manager = DownloadManager(
    client: client,
    dao: dao,
    fs: fs,
    progressThrottle: progressThrottle,
    remoteUrlResolver: remoteUrlResolver,
  );
  return (
    manager: manager,
    client: client,
    fs: fs,
    dao: dao,
    tempDir: tempDir,
  );
}

// ── Widget 测试环境（S7/S8/S9 共用） ─────────────────────────────────────────

class _WidgetEnv {
  _WidgetEnv({
    required this.db,
    required this.dao,
    required this.client,
    required this.fs,
    required this.tempDir,
  });

  final Database db;
  final DownloadDao dao;
  final _FakeDownloadClient client;
  final _TempDirFs fs;
  final Directory tempDir;
}

Future<_WidgetEnv> _makeWidgetEnv() async {
  final db = await openTestDatabase(TestSchema.full);
  await seedConnection(db);
  addTearDown(db.close);
  // 机械适配：testWidgets 的 FakeAsync 区内真实异步 IO（createTemp）永不完成，
  // 须用同步变体（teardown 的递归删除在 body 外执行，可保留 async）。
  final tempDir = Directory.systemTemp.createTempSync('dl01_ui');
  addTearDown(() async {
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });
  return _WidgetEnv(
    db: db,
    dao: DownloadDao(),
    client: _FakeDownloadClient(hangByDefault: true),
    fs: _TempDirFs('${tempDir.path}/downloads'),
    tempDir: tempDir,
  );
}

// ── S1 迁移辅助 ───────────────────────────────────────────────────────────────

const _downloadsColumns = [
  'id',
  'connection_id',
  'file_path',
  'file_name',
  'remote_size',
  'local_path',
  'status',
  'bytes_downloaded',
  'created_at',
  'updated_at',
];

/// 动态探测 NOT NULL 无默认列并最小化插入一行哨兵（用于列结构未硬编码的
/// playlists / playlist_tracks 表——只关心「行数迁移前后零改动」）。
// 机械适配：返回新行 id 并支持列值覆盖——playlist_tracks.playlist_id 的
// 最小哨兵值 0 不满足 FK（父表自增从 1 起），须显式引用真实父行。
Future<int> _insertMinimalSentinel(
  Database db,
  String table, {
  Map<String, Object?> overrides = const <String, Object?>{},
}) async {
  final cols = await db.rawQuery('PRAGMA table_info($table)');
  final row = <String, Object?>{};
  for (final c in cols) {
    final name = c['name'] as String;
    final notNull = (c['notnull'] as int?) == 1;
    final pk = (c['pk'] as int?) ?? 0;
    if (pk > 0 || !notNull) continue;
    final type = ((c['type'] as String?) ?? '').toUpperCase();
    if (type.contains('INT') ||
        type.contains('REAL') ||
        type.contains('DOUB')) {
      row[name] = 0;
    } else {
      row[name] = '';
    }
  }
  row.addAll(overrides);
  return db.insert(table, row);
}

/// 四张旧表的 {行数, 列集合} 快照（升级前后比对，证明零改动）。
Future<Map<String, ({int count, List<String> columns})>> _legacySnapshot(
    Database db) async {
  final out = <String, ({int count, List<String> columns})>{};
  for (final t in const [
    'connections',
    'play_progress',
    'playlists',
    'playlist_tracks',
  ]) {
    final countRows = await db.rawQuery('SELECT COUNT(*) AS c FROM $t');
    final count = countRows.first['c'] as int;
    final cols = (await db.rawQuery('PRAGMA table_info($t)'))
        .map((r) => r['name'] as String)
        .toList()
      ..sort();
    out[t] = (count: count, columns: cols);
  }
  return out;
}

// ── S3 本机假 NAS 服务器 ─────────────────────────────────────────────────────

class _LocalServer {
  HttpServer? _server;
  final recordedAuth = <String?>[];
  final recordedMethods = <String>[];
  final recordedRangeHeaders = <String?>[];
  final recordedIfModifiedSince = <String?>[];

  String get baseUrl => 'http://127.0.0.1:${_server!.port}';

  Future<void> start(
    Future<void> Function(HttpRequest request, HttpResponse response) handler,
  ) async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server!.listen((request) async {
      recordedAuth.add(request.headers.value(HttpHeaders.authorizationHeader));
      recordedMethods.add(request.method);
      recordedRangeHeaders.add(request.headers.value(HttpHeaders.rangeHeader));
      recordedIfModifiedSince
          .add(request.headers.value(HttpHeaders.ifModifiedSinceHeader));
      try {
        await handler(request, request.response);
      } catch (_) {
        // 服务端视角：客户端中途断开等 IO 抖动一律吞掉
      }
    });
  }

  Future<void> close() async {
    await _server?.close(force: true);
    _server = null;
  }
}

// ── S6 orchestrator 内联 fake（依赖抽象类均在 playback_orchestrator.dart 内
//    定义，单方法接口测试内 inline 实现——同 aud_05 / bug_bug04 先例） ────────

class _RecConnProvider implements ActiveConnectionProvider {
  @override
  ConnectionConfig? get currentConnection => _conn;

  @override
  Future<ConnectionConfig?> getActiveConnection() async => _conn;
}

class _RecPasswordReader implements PasswordReader {
  _RecPasswordReader(this.log);

  final List<String> log;
  int calls = 0;

  @override
  Future<String?> readPassword(int connectionId) async {
    calls++;
    log.add('readPassword');
    return 'secret';
  }
}

class _RecProgressSaver implements ProgressSaver {
  // 刻意不记 log：loadAndPlay 是否内部保存进度与本组断言无关，
  // 共享 log 只承载 readPassword/setAudioSource/seek/resolver 标记。
  @override
  Future<void> upsertProgress({
    required int connectionId,
    required String filePath,
    required int positionMs,
    int? durationMs,
  }) async {}
}

class _ConstSpeedProvider implements DefaultSpeedProvider {
  @override
  double getDefaultSpeed() => 1.0;
}

class _NullQueueConnIdProvider implements QueueConnectionIdProvider {
  @override
  int? getLastQueueConnectionId() => null;
}

typedef _OrchRig = ({
  MockAudioPlayer player,
  List<AudioSource> sources,
  List<String> log,
  _RecPasswordReader reader,
  PlaybackOrchestrator orchestrator,
});

/// 机械适配：hand-written MockAudioPlayer 的参数为非空类型，而 mockito 5.6
/// 起参数匹配器（any/argThat）均为 Null 静态类型、无法传入非空参数位。
/// 改为覆写这两个方法直接捕获/吞掉（语义与原 when(setAudioSource(any)) /
/// when(setSpeed(any)) 完全等价：记录全部调用并返回固定值）。
class _RecordingAudioPlayer extends MockAudioPlayer {
  final List<AudioSource> sources;
  final List<String> log;

  _RecordingAudioPlayer(this.sources, this.log);

  @override
  Future<Duration?> setAudioSource(
    AudioSource source, {
    bool preload = true,
    int? initialIndex,
    Duration? initialPosition,
  }) async {
    sources.add(source);
    log.add('setAudioSource');
    return Duration.zero;
  }

  @override
  Future<void> setSpeed(double speed) async {}
}

/// 组装 MockAudioPlayer + 编排器（可选注入 localSourceResolver 端口）。
/// 调用序经共享 log 列表精确锁定（INV1 断言载体）。
_OrchRig _makeOrchRig({
  Future<String?> Function(int connectionId, String filePath)?
      localSourceResolver,
}) {
  final sources = <AudioSource>[];
  final log = <String>[];
  final reader = _RecPasswordReader(log);
  final player = _RecordingAudioPlayer(sources, log);
  when(player.playerStateStream).thenAnswer((_) => const Stream.empty());
  when(player.processingStateStream).thenAnswer((_) => const Stream.empty());
  when(player.playing).thenReturn(true);
  when(player.position).thenReturn(Duration.zero);
  when(player.duration).thenReturn(null);
  when(player.seek(any)).thenAnswer((_) async {
    log.add('seek');
  });
  when(player.play()).thenAnswer((_) async {});
  when(player.pause()).thenAnswer((_) async {});
  when(player.stop()).thenAnswer((_) async {});
  final orchestrator = PlaybackOrchestrator(
    player: player,
    connectionProvider: _RecConnProvider(),
    passwordReader: reader,
    progressSaver: _RecProgressSaver(),
    defaultSpeedProvider: _ConstSpeedProvider(),
    queueConnectionIdProvider: _NullQueueConnIdProvider(),
    localSourceResolver: localSourceResolver,
  );
  return (
    player: player,
    sources: sources,
    log: log,
    reader: reader,
    orchestrator: orchestrator,
  );
}

/// 本地/远程源判定锚点：AudioSource.file / AudioSource.uri 产物均为
/// ProgressiveAudioSource，uri.scheme 区分 file 与 http(s)。
Uri _sourceUri(AudioSource source) => (source as ProgressiveAudioSource).uri;

PlayQueue _makeQueue({String path = '/music/song.mp3', int? startPositionMs}) {
  return PlayQueue(
    files: [testAudio('song.mp3', path)],
    currentIndex: 0,
    startPositionMs: startPositionMs,
    playMode: PlayMode.sequential,
  );
}

// ── Browser widget harness（机械结构照 brw_01：_Tree/fetch/_pumpBrowser） ────

class _Tree {
  final Map<String, List<NasFile>> listings = {};
  final Map<String, Completer<List<NasFile>>> _gates = {};
  final List<String> calls = [];

  void put(String path, List<NasFile> entries) => listings[path] = entries;

  Completer<List<NasFile>> gate(String path) =>
      _gates.putIfAbsent(path, Completer<List<NasFile>>.new);

  Future<List<NasFile>> fetch(String path) async {
    calls.add(path);
    final pending = _gates[path];
    if (pending != null) return pending.future;
    return listings[path] ?? const <NasFile>[];
  }

  Override get override =>
      directoryContentsProvider.overrideWith((ref, path) => fetch(path));
}

class _NoProgressDao extends ProgressDao {
  @override
  Future<PlayProgress?> find(int connectionId, String filePath) async => null;

  @override
  Future<void> delete(int connectionId, String filePath) async {}
}

Future<List<Override>> _browserOverrides(_Tree tree, _WidgetEnv env,
    {ProgressDao? progressDao}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  return [
    tree.override,
    activeConnectionProvider.overrideWith((ref) async => _conn),
    sharedPreferencesProvider.overrideWithValue(prefs),
    audioPlayerProvider.overrideWithValue(MockAudioPlayer()),
    progressDaoProvider.overrideWithValue(progressDao ?? _NoProgressDao()),
    downloadDaoProvider.overrideWithValue(env.dao),
    downloadFileSystemProvider.overrideWithValue(env.fs),
    downloadManagerProvider.overrideWith((ref) => DownloadManager(
          client: env.client,
          dao: env.dao,
          fs: env.fs,
        )),
  ];
}

Future<ProviderContainer> _pumpBrowser(
  WidgetTester tester,
  List<Override> overrides,
) async {
  await tester.pumpWidget(buildTestAppWithPlayerRoute(
    const Scaffold(body: BrowserScreen()),
    overrides: overrides,
  ));
  await tester.pumpAndSettle();
  return ProviderScope.containerOf(tester.element(find.byType(BrowserScreen)));
}

// ═══════════════════════════════════════════════════════════════════════════
// 测试主体
// ═══════════════════════════════════════════════════════════════════════════

void main() {
  setUpAll(() => initSqfliteFfi());

  // ───────────────────────────────────────────────────────────────────────
  // DL-01-S1 DB v3 迁移
  // ───────────────────────────────────────────────────────────────────────
  group('DL-01-S1 downloads 表迁移', () {
    test(
        'DL-01-S1: 全新安装 v3 schema 含 downloads 表、idx_downloads_conn 索引与 UNIQUE(connection_id,file_path) 约束',
        () async {
      final db = await openTestDatabase(TestSchema.full);
      addTearDown(db.close);

      // 表存在（sqlite_master 权威查询）
      final tables = (await db
              .rawQuery("SELECT name FROM sqlite_master WHERE type='table'"))
          .map((r) => r['name'] as String)
          .toList();
      expect(tables, contains('downloads'), reason: 'v3 全新建库必须有 downloads 表');

      // 列集合与 spec §3.1 DDL 一致（无序比较，恰好十个）
      final cols = (await db.rawQuery('PRAGMA table_info(downloads)'))
          .map((r) => r['name'] as String)
          .toList()
        ..sort();
      final expected = [..._downloadsColumns]..sort();
      expect(cols, equals(expected), reason: 'downloads 列集合必须逐列匹配 spec DDL');

      // 索引存在
      final indexes = (await db
              .rawQuery("SELECT name FROM sqlite_master WHERE type='index'"))
          .map((r) => r['name'] as String)
          .toList();
      expect(indexes, contains('idx_downloads_conn'),
          reason:
              'CREATE INDEX idx_downloads_conn ON downloads(connection_id, status)');

      // UNIQUE(connection_id,file_path)：DDL 层裸 SQL 重复插入必须被拒
      // （冲突吸收语义归 S2 的 upsert 测，这里只锁约束本身存在）
      await seedConnection(db);
      await db.insert('downloads', {
        'connection_id': 1,
        'file_path': '/dup.mp3',
        'file_name': 'dup.mp3',
        'remote_size': 1,
        'local_path': '/x',
        'status': 'pending',
        'bytes_downloaded': 0,
        'created_at': _ts,
        'updated_at': _ts,
      });
      await expectLater(
        db.insert('downloads', {
          'connection_id': 1,
          'file_path': '/dup.mp3',
          'file_name': 'dup.mp3',
          'remote_size': 1,
          'local_path': '/y',
          'status': 'done',
          'bytes_downloaded': 0,
          'created_at': _ts,
          'updated_at': _ts,
        }),
        throwsA(isA<Exception>()),
        reason: 'UNIQUE(connection_id,file_path) 必须在 DDL 层拒绝重复键',
      );
    });

    test('DL-01-S1: 升级路径 v2→v3 —— downloads 表重建，四张旧表行数与列集合零改动', () async {
      final db = await openTestDatabase(TestSchema.full);
      addTearDown(db.close);

      // 播种四张旧表哨兵数据行
      await seedConnection(db);
      await db.insert('play_progress', {
        'connection_id': 1,
        'file_path': '/p.mp3',
        'position_ms': 1000,
        'duration_ms': 2000,
        'last_played_at': _ts,
      });
      final playlistId = await _insertMinimalSentinel(db, 'playlists');
      await _insertMinimalSentinel(db, 'playlist_tracks',
          overrides: {'playlist_id': playlistId});

      final before = await _legacySnapshot(db);
      expect(before['playlists']!.count, 1, reason: '前置：哨兵行已入 playlists');
      expect(before['playlist_tracks']!.count, 1,
          reason: '前置：哨兵行已入 playlist_tracks');

      // 把 v3 库伪装成 v2：拆掉 v3 新增对象并降 user_version
      await db.execute('DROP INDEX IF EXISTS idx_downloads_conn');
      await db.execute('DROP TABLE IF EXISTS downloads');
      await db.setVersion(2);

      // 手工触发生产升级段（@visibleForTesting 入口）
      await DatabaseHelper.instance.runUpgradePathForTest(db, 2);

      final after = await _legacySnapshot(db);
      // 否定断言：四张旧表零改动（行数 + 列集合）
      // 机械适配：record 内嵌 List 走恒等相等，跨快照必不等；改为逐表深度
      // 比对（断言意图不变：行数与列集合零改动）。
      for (final entry in before.entries) {
        expect(after[entry.key]!.count, entry.value.count,
            reason: '${entry.key} 行数在升级前后必须完全一致');
        expect(after[entry.key]!.columns, entry.value.columns,
            reason: '${entry.key} 列集合在升级前后必须完全一致');
      }

      // downloads 表与索引重建到位
      final tables = (await db
              .rawQuery("SELECT name FROM sqlite_master WHERE type='table'"))
          .map((r) => r['name'] as String)
          .toList();
      expect(tables, contains('downloads'));
      final indexes = (await db
              .rawQuery("SELECT name FROM sqlite_master WHERE type='index'"))
          .map((r) => r['name'] as String)
          .toList();
      expect(indexes, contains('idx_downloads_conn'),
          reason: '升级段必须重建 idx_downloads_conn');
    });

    test('DL-01-S1: 升级路径 v1→v3 守卫顺序执行两段同样产出 downloads 且旧表零改动', () async {
      final db = await openTestDatabase(TestSchema.full);
      addTearDown(db.close);

      await seedConnection(db);
      await db.insert('play_progress', {
        'connection_id': 1,
        'file_path': '/old.mp3',
        'position_ms': 0,
        'duration_ms': null,
        'last_played_at': _ts,
      });
      final playlistId = await _insertMinimalSentinel(db, 'playlists');
      await _insertMinimalSentinel(db, 'playlist_tracks',
          overrides: {'playlist_id': playlistId});

      final before = await _legacySnapshot(db);

      await db.execute('DROP INDEX IF EXISTS idx_downloads_conn');
      await db.execute('DROP TABLE IF EXISTS downloads');
      await db.setVersion(1);

      // oldVersion=1：<3 段与 <2 段应顺序执行（守卫式迁移），终态一致
      await DatabaseHelper.instance.runUpgradePathForTest(db, 1);

      final after = await _legacySnapshot(db);
      // 机械适配：同上，逐表深度比对（意图不变：v1 起点升级不得扰动旧表）。
      for (final entry in before.entries) {
        expect(after[entry.key]!.count, entry.value.count,
            reason: '${entry.key} 行数零改动（v1 起点）');
        expect(after[entry.key]!.columns, entry.value.columns,
            reason: '${entry.key} 列集合零改动（v1 起点）');
      }

      final tables = (await db
              .rawQuery("SELECT name FROM sqlite_master WHERE type='table'"))
          .map((r) => r['name'] as String)
          .toList();
      expect(tables, contains('downloads'));
    });
  });

  // ───────────────────────────────────────────────────────────────────────
  // DL-01-S2 IDownloadDao 契约行为
  // ───────────────────────────────────────────────────────────────────────
  group('DL-01-S2 IDownloadDao 契约行为', () {
    Future<({Database db, DownloadDao dao})> _daoEnv() async {
      final db = await openTestDatabase(TestSchema.downloads);
      await seedConnection(db);
      addTearDown(db.close);
      return (db: db, dao: DownloadDao());
    }

    test('DL-01-S2: upsert 新行插入全字段并读回一致', () async {
      // 机械修正：本 Dart 版本对 `(:dao) = await …` 单字段 getter 模式推断
      // 有缺陷，需显式解构另一字段（语义等价，无断言改动）。
      final (db: _, :dao) = await _daoEnv();
      await dao.upsert(
          _rec('/a.mp3', DownloadStatus.pending, remote: 123, bytes: 45));

      final rec = await dao.findByLocation(1, '/a.mp3');
      expect(rec, isNotNull);
      expect(rec!.id, isNotNull, reason: '新行应有自增 id');
      expect(rec.connectionId, 1);
      expect(rec.filePath, '/a.mp3');
      expect(rec.fileName, 'a.mp3');
      expect(rec.remoteSize, 123);
      expect(rec.localPath, '/nonexistent_a.mp3');
      expect(rec.status, DownloadStatus.pending);
      expect(rec.bytesDownloaded, 45);
      expect(rec.createdAt, _ts);
      expect(rec.updatedAt, _ts);
    });

    test(
        'DL-01-S2: upsert UNIQUE 命中只更新 status/bytes_downloaded/updated_at——不产生第二行且其余列不被覆盖',
        () async {
      // 机械修正：本 Dart 版本对 `(:dao) = await …` 单字段 getter 模式推断
      // 有缺陷，需显式解构另一字段（语义等价，无断言改动）。
      final (db: _, :dao) = await _daoEnv();
      await dao.upsert(_rec('/a.mp3', DownloadStatus.pending,
          remote: 10, bytes: 3, updatedAt: _tsOld));

      // 同 (connection_id,file_path) 再次 upsert：故意携带不同的 fileName /
      // remoteSize / createdAt，证明这些列【不会】被覆盖
      await dao.upsert(DownloadRecord(
        connectionId: 1,
        filePath: '/a.mp3',
        fileName: 'SHOULD-NOT-OVERWRITE.mp3',
        remoteSize: 999,
        localPath: '/should-not-overwrite',
        status: DownloadStatus.downloading,
        bytesDownloaded: 77,
        createdAt: _ts,
        updatedAt: _ts,
      ));

      final all = await dao.listByConnection(1);
      expect(all, hasLength(1), reason: '否定断言：UNIQUE 命中不得产生第二行');
      final rec = all.single;
      expect(rec.status, DownloadStatus.downloading);
      expect(rec.bytesDownloaded, 77);
      expect(rec.updatedAt, _ts, reason: 'updated_at 必须被刷新');
      expect(rec.fileName, 'a.mp3',
          reason: '否定断言：upsert 只更新 status/bytes/updated_at，fileName 不动');
      expect(rec.remoteSize, 10, reason: '否定断言：remoteSize 不动');
      expect(rec.createdAt, _tsOld, reason: '否定断言：createdAt 保持首插值');
    });

    test('DL-01-S2: findByLocation 未命中返回 null，命中返回整行', () async {
      // 机械修正：本 Dart 版本对 `(:dao) = await …` 单字段 getter 模式推断
      // 有缺陷，需显式解构另一字段（语义等价，无断言改动）。
      final (db: _, :dao) = await _daoEnv();
      expect(await dao.findByLocation(1, '/none.mp3'), isNull,
          reason: '否定断言：未命中返回 null 不抛错');
      await dao.upsert(_rec('/hit.mp3', DownloadStatus.pending));
      final rec = await dao.findByLocation(1, '/hit.mp3');
      expect(rec, isNotNull);
      expect(rec!.filePath, '/hit.mp3');
      expect(rec.status, DownloadStatus.pending);
    });

    test('DL-01-S2: findDoneLocalPath 四态矩阵——仅 done 返回 local_path（INV5 三重闸之一）',
        () async {
      // 机械修正：本 Dart 版本对 `(:dao) = await …` 单字段 getter 模式推断
      // 有缺陷，需显式解构另一字段（语义等价，无断言改动）。
      final (db: _, :dao) = await _daoEnv();

      await dao.upsert(_rec('/pending.mp3', DownloadStatus.pending,
          local: '/local/pending.mp3'));
      await dao.upsert(_rec('/downloading.mp3', DownloadStatus.downloading,
          local: '/local/downloading.mp3', bytes: 50));
      await dao.upsert(_rec('/failed.mp3', DownloadStatus.failed,
          local: '/local/failed.mp3'));
      await dao.upsert(
          _rec('/done.mp3', DownloadStatus.done, local: '/local/done.mp3'));

      expect(await dao.findDoneLocalPath(1, '/done.mp3'), '/local/done.mp3',
          reason: '唯一合法入口：rename 成品后的 done 记录');
      // 否定面：半成品/失败一律 null（部分下载绝不参与播放）
      expect(await dao.findDoneLocalPath(1, '/pending.mp3'), isNull);
      expect(await dao.findDoneLocalPath(1, '/downloading.mp3'), isNull,
          reason: 'INV5：downloading 半截文件不可达播放器');
      expect(await dao.findDoneLocalPath(1, '/failed.mp3'), isNull);
      expect(await dao.findDoneLocalPath(2, '/done.mp3'), isNull,
          reason: '跨连接隔离');
    });

    test('DL-01-S2: updateProgress 仅 status==downloading 时生效，其余状态 no-op',
        () async {
      // 机械修正：本 Dart 版本对 `(:dao) = await …` 单字段 getter 模式推断
      // 有缺陷，需显式解构另一字段（语义等价，无断言改动）。
      final (db: _, :dao) = await _daoEnv();

      Future<int> idOf(String path) async =>
          (await dao.findByLocation(1, path))!.id!;

      await dao.upsert(_rec('/p.mp3', DownloadStatus.pending));
      await dao.upsert(_rec('/d.mp3', DownloadStatus.downloading));
      await dao.upsert(_rec('/done.mp3', DownloadStatus.done));
      await dao.upsert(_rec('/f.mp3', DownloadStatus.failed));

      await dao.updateProgress(await idOf('/d.mp3'), 4096);
      expect((await dao.findByLocation(1, '/d.mp3'))!.bytesDownloaded, 4096,
          reason: '正向控制：downloading 态写 bytes 生效');

      await dao.updateProgress(await idOf('/p.mp3'), 999);
      await dao.updateProgress(await idOf('/done.mp3'), 999);
      await dao.updateProgress(await idOf('/f.mp3'), 999);
      // 否定面：非 downloading 态一律 no-op
      expect((await dao.findByLocation(1, '/p.mp3'))!.bytesDownloaded, 0,
          reason: '否定断言：pending 态 updateProgress 不生效');
      expect((await dao.findByLocation(1, '/done.mp3'))!.bytesDownloaded, 0,
          reason: '否定断言：done 态 updateProgress 不生效');
      expect((await dao.findByLocation(1, '/f.mp3'))!.bytesDownloaded, 0,
          reason: '否定断言：failed 态 updateProgress 不生效');
    });

    test(
        'DL-01-S2: setStatus 通用状态迁移——bytes 非 null 时同步更新 bytes_downloaded 与 updated_at',
        () async {
      // 机械修正：本 Dart 版本对 `(:dao) = await …` 单字段 getter 模式推断
      // 有缺陷，需显式解构另一字段（语义等价，无断言改动）。
      final (db: _, :dao) = await _daoEnv();
      await dao
          .upsert(_rec('/s.mp3', DownloadStatus.pending, updatedAt: _tsOld));

      await dao.setStatus(
          (await dao.findByLocation(1, '/s.mp3'))!.id!, DownloadStatus.done,
          bytes: 555);

      final rec = (await dao.findByLocation(1, '/s.mp3'))!;
      expect(rec.status, DownloadStatus.done);
      expect(rec.bytesDownloaded, 555);
      expect(rec.updatedAt, greaterThan(_tsOld), reason: 'updated_at 必须刷新');
    });

    test('DL-01-S2: listByConnection 按 updated_at DESC 排序', () async {
      // 机械修正：本 Dart 版本对 `(:dao) = await …` 单字段 getter 模式推断
      // 有缺陷，需显式解构另一字段（语义等价，无断言改动）。
      final (db: _, :dao) = await _daoEnv();
      await dao.upsert(
          _rec('/first.mp3', DownloadStatus.done, updatedAt: _ts - 300));
      await dao
          .upsert(_rec('/newest.mp3', DownloadStatus.pending, updatedAt: _ts));
      await dao.upsert(_rec('/middle.mp3', DownloadStatus.downloading,
          updatedAt: _ts - 100));

      final rows = await dao.listByConnection(1);
      expect(rows.map((r) => r.filePath).toList(),
          ['/newest.mp3', '/middle.mp3', '/first.mp3'],
          reason: 'ORDER BY updated_at DESC');
    });

    test('DL-01-S2: totalBytesByConnection 空表返回 0 不抛错；只累计 done 行的 remote_size',
        () async {
      // 机械修正：本 Dart 版本对 `(:dao) = await …` 单字段 getter 模式推断
      // 有缺陷，需显式解构另一字段（语义等价，无断言改动）。
      final (db: _, :dao) = await _daoEnv();
      expect(await dao.totalBytesByConnection(1), 0, reason: '否定断言：空表返回 0 不抛错');

      await dao.upsert(_rec('/d1.mp3', DownloadStatus.done, remote: 300));
      await dao.upsert(_rec('/d2.mp3', DownloadStatus.done, remote: 200));
      await dao
          .upsert(_rec('/dl.mp3', DownloadStatus.downloading, remote: 9999));
      await dao.upsert(_rec('/p.mp3', DownloadStatus.pending, remote: 8888));
      await dao.upsert(_rec('/f.mp3', DownloadStatus.failed, remote: 7777));

      expect(await dao.totalBytesByConnection(1), 500,
          reason: 'SUM(remote_size) WHERE status=done：非 done 一律不计入');
    });

    test('DL-01-S2: deleteById / deleteByConnection 删除语义', () async {
      // 机械修正：本 Dart 版本对 `(:dao) = await …` 单字段 getter 模式推断
      // 有缺陷，需显式解构另一字段（语义等价，无断言改动）。
      final (db: _, :dao) = await _daoEnv();
      await dao.upsert(_rec('/a.mp3', DownloadStatus.pending));
      await dao.upsert(_rec('/b.mp3', DownloadStatus.done));

      await dao.deleteById((await dao.findByLocation(1, '/a.mp3'))!.id!);
      expect(await dao.findByLocation(1, '/a.mp3'), isNull);
      expect(await dao.listByConnection(1), hasLength(1));

      await dao.deleteByConnection(1);
      expect(await dao.listByConnection(1), isEmpty,
          reason: 'deleteByConnection 清空该连接全部行');
    });

    test(
        'DL-01-S2: markAllNonDoneFailed 只动 pending/downloading——done/failed 原样不动（updatedAt 亦不变）',
        () async {
      // 机械修正：本 Dart 版本对 `(:dao) = await …` 单字段 getter 模式推断
      // 有缺陷，需显式解构另一字段（语义等价，无断言改动）。
      final (db: _, :dao) = await _daoEnv();
      await dao
          .upsert(_rec('/p.mp3', DownloadStatus.pending, updatedAt: _ts - 40));
      await dao.upsert(_rec('/dl.mp3', DownloadStatus.downloading,
          updatedAt: _ts - 30, bytes: 12));
      await dao
          .upsert(_rec('/done.mp3', DownloadStatus.done, updatedAt: _ts - 20));
      await dao
          .upsert(_rec('/f.mp3', DownloadStatus.failed, updatedAt: _ts - 10));

      await dao.markAllNonDoneFailed(1);

      final byPath = <String, DownloadRecord>{
        for (final r in await dao.listByConnection(1)) r.filePath: r,
      };
      expect(byPath['/p.mp3']!.status, DownloadStatus.failed);
      expect(byPath['/dl.mp3']!.status, DownloadStatus.failed);
      expect(byPath['/p.mp3']!.updatedAt, greaterThan(_ts - 40),
          reason: '被转换行的 updated_at 必须刷新');
      expect(byPath['/dl.mp3']!.updatedAt, greaterThan(_ts - 30));
      // 否定面：done 是终态、failed 已是终态——状态与时间戳都不许动
      expect(byPath['/done.mp3']!.status, DownloadStatus.done,
          reason: '否定断言：done 不受恢复影响');
      expect(byPath['/done.mp3']!.updatedAt, _ts - 20);
      expect(byPath['/f.mp3']!.status, DownloadStatus.failed);
      expect(byPath['/f.mp3']!.updatedAt, _ts - 10,
          reason: '否定断言：failed 行 updated_at 不变');
    });
  });

  // ───────────────────────────────────────────────────────────────────────
  // DL-01-S3 downloadFile 流式下载引擎
  // ───────────────────────────────────────────────────────────────────────
  group('DL-01-S3 downloadFile 引擎', () {
    const username = 'admin';
    const password = 'dl-secret';
    final body = 'hello-dl01-chunked-body'.codeUnits; // 纯 ASCII ≈ 字节

    test('DL-01-S3 黄金路径: 分块落盘内容一致、无 .part 残留、onProgress 单调递增且 ≤ total、请求头符合契约',
        () async {
      final server = _LocalServer();
      addTearDown(server.close);
      await server.start((req, res) async {
        res.headers.contentLength = body.length;
        for (var i = 0; i < body.length; i += 4) {
          final end = i + 4 <= body.length ? i + 4 : body.length;
          res.add(body.sublist(i, end));
          await res.flush();
        }
        await res.close();
      });

      final dir = await Directory.systemTemp.createTemp('dl01_s3_gold');
      addTearDown(() async {
        try {
          await dir.delete(recursive: true);
        } catch (_) {}
      });
      final saveTo = '${dir.path}/song.mp3';

      final received = <int>[];
      final totals = <int?>[];
      final client =
          WebDavClient(chunkIdleTimeout: const Duration(seconds: 30));
      await client.downloadFile(
        url: server.baseUrl,
        filePath: '/music/song.mp3',
        username: username,
        password: password,
        saveTo: saveTo,
        onProgress: (r, t) {
          received.add(r);
          totals.add(t);
        },
      );

      // 落盘内容一致
      expect(File(saveTo).readAsBytesSync(), body, reason: '分块下载后成品字节必须与源一致');
      // 否定断言：成功路径不留 .part 残留
      expect(File('$saveTo.part').existsSync(), isFalse,
          reason: 'S3⑤：成功路径不留 .part 残留');

      // onProgress 单调递增且 ≤ total，末次到达 total
      expect(received, isNotEmpty);
      for (var i = 1; i < received.length; i++) {
        expect(received[i], greaterThanOrEqualTo(received[i - 1]),
            reason: 'received 必须单调不减（$i 处 ${received[i - 1]}→${received[i]}）');
      }
      for (final r in received) {
        expect(r, lessThanOrEqualTo(body.length), reason: 'received ≤ total');
      }
      expect(received.last, body.length);
      expect(totals, everyElement(body.length),
          reason: 'total 来自 Content-Length 响应头');

      // 请求头契约
      expect(server.recordedMethods.single, 'GET', reason: 'method GET');
      expect(
        server.recordedAuth.single,
        AudioSourceBuilder.buildAuthHeader(
            username: username, password: password),
        reason: 'Authorization 必须复用 AudioSourceBuilder.buildAuthHeader',
      );
      // 否定断言：不带 Range / If-Modified-Since（B5-3 无续传 / B5-6 零新鲜度）
      expect(server.recordedRangeHeaders.single, isNull,
          reason: '否定断言：请求不带 Range 头');
      expect(server.recordedIfModifiedSince.single, isNull,
          reason: '否定断言：请求不带 If-Modified-Since 头');
    });

    test('DL-01-S3: Content-Length 缺失时 total 为 null，received 单调到达完整长度',
        () async {
      final server = _LocalServer();
      addTearDown(server.close);
      await server.start((req, res) async {
        // 不设 Content-Length → HttpServer 自动走 chunked 编码
        res.add(body);
        await res.flush();
        await res.close();
      });

      final dir = await Directory.systemTemp.createTemp('dl01_s3_nolen');
      addTearDown(() async {
        try {
          await dir.delete(recursive: true);
        } catch (_) {}
      });
      final saveTo = '${dir.path}/song.mp3';

      final received = <int>[];
      final totals = <int?>[];
      final client = WebDavClient();
      await client.downloadFile(
        url: server.baseUrl,
        filePath: '/music/song.mp3',
        username: username,
        password: password,
        saveTo: saveTo,
        onProgress: (r, t) {
          received.add(r);
          totals.add(t);
        },
      );

      expect(totals, everyElement(isNull),
          reason: 'Content-Length 缺失时 onProgress 的 total 可为 null');
      expect(received.last, body.length, reason: 'received 最终到达完整长度');
      expect(File(saveTo).readAsBytesSync(), body);
    });

    test(
        'DL-01-S3: 401 → WebDavException.isAuthError 且 statusCode==401；成品未被触碰、无 .part（否定断言收口）',
        () async {
      final server = _LocalServer();
      addTearDown(server.close);
      await server.start((req, res) async {
        res.statusCode = 401;
        await res.close();
      });

      final dir = await Directory.systemTemp.createTemp('dl01_s3_401');
      addTearDown(() async {
        try {
          await dir.delete(recursive: true);
        } catch (_) {}
      });
      final saveTo = '${dir.path}/song.mp3';
      // 预置成品哨兵：失败路径绝不允许触碰既有成品
      File(saveTo).writeAsStringSync('untouched', flush: true);

      Object? caught;
      final client = WebDavClient();
      try {
        await client.downloadFile(
          url: server.baseUrl,
          filePath: '/music/song.mp3',
          username: username,
          password: password,
          saveTo: saveTo,
        );
      } catch (e) {
        caught = e;
      }

      final ex = caught as WebDavException;
      expect(ex.isAuthError, isTrue, reason: '401 按 webdav_client 同族映射为认证错误');
      expect(ex.statusCode, 401);
      expect(File(saveTo).readAsStringSync(), 'untouched',
          reason: '否定断言：失败路径 final 文件未被触碰');
      expect(File('$saveTo.part').existsSync(), isFalse,
          reason: 'S3⑥：失败路径尽力清理 .part');
    });

    test('DL-01-S3: 404 → WebDavException.statusCode==404（非认证同族映射）', () async {
      final server = _LocalServer();
      addTearDown(server.close);
      await server.start((req, res) async {
        res.statusCode = 404;
        await res.close();
      });

      Object? caught;
      final client = WebDavClient();
      try {
        await client.downloadFile(
          url: server.baseUrl,
          filePath: '/missing.mp3',
          username: username,
          password: password,
          saveTo: '${Directory.systemTemp.path}/never.mp3',
        );
      } catch (e) {
        caught = e;
      }

      final ex = caught as WebDavException;
      expect(ex.statusCode, 404);
    });

    test('DL-01-S3: 传输中途断流 → 抛错且 .part 被清、final 不存在（INV5 半成品不可达）', () async {
      final server = _LocalServer();
      addTearDown(server.close);
      await server.start((req, res) async {
        // 宣称 100 字节只发 5 字节就关闭 → 客户端流式读必然报错
        res.headers.contentLength = 100;
        res.add('short'.codeUnits);
        await res.flush();
        await res.close();
      });

      final dir = await Directory.systemTemp.createTemp('dl01_s3_trunc');
      addTearDown(() async {
        try {
          await dir.delete(recursive: true);
        } catch (_) {}
      });
      final saveTo = '${dir.path}/song.mp3';

      Object? caught;
      final client = WebDavClient();
      try {
        await client.downloadFile(
          url: server.baseUrl,
          filePath: '/music/song.mp3',
          username: username,
          password: password,
          saveTo: saveTo,
        );
      } catch (e) {
        caught = e;
      }
      expect(caught, isNotNull, reason: '中途断流必须以异常结束，不得静默产出短文件');

      expect(File(saveTo).existsSync(), isFalse, reason: 'INV5：半截数据绝不冒充成品');
      expect(File('$saveTo.part').existsSync(), isFalse,
          reason: 'S3⑥：失败路径尽力删除 .part');
    });

    test(
        'DL-01-S3 §5.3 盲点补偿: chunk 间静默超过 chunkIdleTimeout → 抛死链 WebDavException 且清理 .part',
        () async {
      final server = _LocalServer();
      addTearDown(server.close);
      await server.start((req, res) async {
        res.headers.contentLength = body.length;
        res.add(body.sublist(0, 4));
        await res.flush();
        // 故意停摆远超 50ms 阈值再发下一块（客户端此刻应已判死链退出）
        await Future<void>.delayed(const Duration(milliseconds: 400));
        try {
          res.add(body.sublist(4));
          await res.flush();
          await res.close();
        } catch (_) {
          // 客户端可能已断开
        }
      });

      final dir = await Directory.systemTemp.createTemp('dl01_s3_idle');
      addTearDown(() async {
        try {
          await dir.delete(recursive: true);
        } catch (_) {}
      });
      final saveTo = '${dir.path}/song.mp3';

      Object? caught;
      final client =
          WebDavClient(chunkIdleTimeout: const Duration(milliseconds: 50));
      try {
        await client.downloadFile(
          url: server.baseUrl,
          filePath: '/music/song.mp3',
          username: username,
          password: password,
          saveTo: saveTo,
        );
      } catch (e) {
        caught = e;
      }

      expect(caught, isA<WebDavException>(),
          reason: 'chunk 静默超过 chunkIdleTimeout 视为死链 → WebDavException');
      expect(File(saveTo).existsSync(), isFalse, reason: '死链不得留下成品');
      expect(File('$saveTo.part').existsSync(), isFalse, reason: '.part 必须清理');
    }, timeout: const Timeout(Duration(seconds: 10)));
  });

  // ───────────────────────────────────────────────────────────────────────
  // DL-01-S4 文件名策略纯函数
  // ───────────────────────────────────────────────────────────────────────
  group('DL-01-S4 sanitizeBaseName / resolveCollision 纯函数策略', () {
    test('DL-01-S4 黄金: basename 提取、九个非法字符替换为下划线、空名/全点名整体替换为 file', () {
      // 普通名原样
      expect(sanitizeBaseName('music/song.mp3'), 'song.mp3');
      expect(sanitizeBaseName('song.mp3'), 'song.mp3');

      // 九个非法字符 \ / : * ? " < > | 各替换为 '_'（split+map 实现）
      expect(
        sanitizeBaseName(r'a\b:c*d?e"f<g>h|i.txt'),
        'a_b_c_d_e_f_g_h_i.txt',
        reason: '非法字符集逐一替换为下划线',
      );

      // 空名 / 全点名 → file
      expect(sanitizeBaseName('dir/'), 'file', reason: 'basename 为空串 → file');
      expect(sanitizeBaseName(''), 'file');
      expect(sanitizeBaseName('...'), 'file', reason: '全为点 → file');
      expect(sanitizeBaseName('..'), 'file');
      expect(sanitizeBaseName('.'), 'file');
    });

    test(
        'DL-01-S4 边界: 120 截断恒保留最后一段扩展名——恰好 120 不截、121 截、带扩展名按「116 stem + 扩展名」补齐',
        () {
      // 恰好 120：原样
      final exactly120 = 'M' * 120;
      expect(sanitizeBaseName(exactly120), exactly120);

      // 121 无扩展名：截到 120
      expect(sanitizeBaseName('N' * 121), 'N' * 120);

      // 带扩展名：总长截到 120 且扩展名恒保留（stem 116 + '.mp3'）
      final longNamed = 'L' * 130 + '.mp3'; // 134
      final truncated = sanitizeBaseName(longNamed);
      expect(truncated, 'L' * 116 + '.mp3');
      expect(truncated.length, 120);
      expect(truncated.endsWith('.mp3'), isTrue, reason: '扩展名恒保留');

      final oCase = sanitizeBaseName('O' * 118 + '.mp3'); // 122
      expect(oCase, 'O' * 116 + '.mp3');
      expect(oCase.endsWith('.mp3'), isTrue);
    });

    test('DL-01-S4 否定面: 输出永不含路径分隔符（防目录穿越）', () {
      const hostile = [
        '../evil.mp3',
        'a/b/c.mp3',
        r'a\b\c.mp3',
        '/abs/path/x.flac',
        '..\\..\\win.mp3',
      ];
      for (final input in hostile) {
        final out = sanitizeBaseName(input);
        expect(out.contains('/'), isFalse,
            reason: '输出 "$out"（输入 "$input"）不含正斜杠');
        expect(out.contains('\\'), isFalse,
            reason: '输出 "$out"（输入 "$input"）不含反斜杠');
        // resolveCollision 产物同样不得含分隔符
        final resolved = resolveCollision('/any/dir', out, (_) => false);
        expect(resolved.contains('/'), isFalse);
        expect(resolved.contains('\\'), isFalse);
      }
    });

    test(
        'DL-01-S4 INV: download_policy.dart 为零 dart:io / 零字面正则的纯函数文件（existsProbe 注入探针）',
        () async {
      final src = await File(
              '${Directory.current.path}/lib/features/downloads/domain/download_policy.dart')
          .readAsString();
      expect(src.contains('dart:io'), isFalse,
          reason: '否定断言：策略函数不得 import dart:io（IO 经 existsProbe 注入）');
      expect(src.contains('RegExp'), isFalse,
          reason: 'spec 要求 split 条件映射实现，禁止字面正则避免转义错误');
    });
  });

  // ───────────────────────────────────────────────────────────────────────
  // DL-01-S5 DownloadManager 串行泵
  // ───────────────────────────────────────────────────────────────────────
  group('DL-01-S5 DownloadManager 串行泵', () {
    test(
        'DL-01-S5: enqueueMany 插入 pending 行并返回实际入队数（fileName/remoteSize 映射自 NasFile）',
        () async {
      final env = await _makeManagerEnv(hangByDefault: true);
      final n = await env.manager.enqueueMany([
        (1, testAudio('one.mp3', '/one.mp3', size: 111)),
        (1, testAudio('two.mp3', '/two.mp3', size: 222)),
      ]);
      expect(n, 2);

      final rows = await env.dao.listByConnection(1);
      expect(rows, hasLength(2));
      final byPath = {for (final r in rows) r.filePath: r};
      expect(byPath['/one.mp3']!.status, DownloadStatus.pending);
      expect(byPath['/one.mp3']!.fileName, 'one.mp3');
      expect(byPath['/one.mp3']!.remoteSize, 111);
      expect(byPath['/two.mp3']!.remoteSize, 222);
    });

    test(
        'DL-01-S5 dedupe: pending/downloading/done skip 不写库，failed 允许重入队回 pending',
        () async {
      // head-block：更早的 G 挂住泵，使本用例的目标行稳定停在入队后的状态
      final gateG = Completer<void>();
      final env = await _makeManagerEnv(scripts: {
        '/g_blocker.mp3': _ScriptedDownload(hangGate: gateG),
      });
      await env.dao.upsert(
          _rec('/g_blocker.mp3', DownloadStatus.pending, updatedAt: _tsOld));

      await env.dao
          .upsert(_rec('/p.mp3', DownloadStatus.pending, updatedAt: _ts - 4));
      await env.dao.upsert(_rec('/dl.mp3', DownloadStatus.downloading,
          updatedAt: _ts - 3, bytes: 42));
      await env.dao
          .upsert(_rec('/done.mp3', DownloadStatus.done, updatedAt: _ts - 2));
      await env.dao
          .upsert(_rec('/f.mp3', DownloadStatus.failed, updatedAt: _ts - 1));

      final before = await env.dao.listByConnection(1);
      expect(before, hasLength(5));

      final enqueued = await env.manager.enqueueMany([
        (1, testAudio('p.mp3', '/p.mp3')),
        (1, testAudio('dl.mp3', '/dl.mp3')),
        (1, testAudio('done.mp3', '/done.mp3')),
        (1, testAudio('f.mp3', '/f.mp3')),
      ]);
      expect(enqueued, 1, reason: '只有 failed 行允许重新入队');

      final after = {
        for (final r in await env.dao.listByConnection(1)) r.filePath: r
      };
      expect(after, hasLength(5), reason: '否定断言：不产生重复行');
      expect(after['/p.mp3']!.status, DownloadStatus.pending,
          reason: 'skip：pending 行不被改写');
      expect(after['/dl.mp3']!.status, DownloadStatus.downloading);
      expect(after['/dl.mp3']!.bytesDownloaded, 42, reason: 'skip：字节计数不动');
      expect(after['/done.mp3']!.status, DownloadStatus.done);
      expect(after['/f.mp3']!.status, DownloadStatus.pending,
          reason: 'failed 重入队回 pending');

      gateG.complete(); // 收尾放行，泵安静退出
    });

    test('DL-01-INV2: 串行泵任意时刻至多一条 downloading（maxConcurrent==1）', () async {
      final env = await _makeManagerEnv();
      await env.manager.enqueueMany([
        (1, testAudio('a.mp3', '/a.mp3')),
        (1, testAudio('b.mp3', '/b.mp3')),
        (1, testAudio('c.mp3', '/c.mp3')),
      ]);
      await env.manager.pump();

      expect(env.client.maxConcurrent, 1,
          reason: 'INV2：任意时刻至多一条下载（fake 并发计数器峰值必为 1）');
      expect(env.client.calledPaths, hasLength(3));
      final statuses =
          (await env.dao.listByConnection(1)).map((r) => r.status).toList();
      expect(statuses, everyElement(DownloadStatus.done));
    });

    test('DL-01-S5: 单条失败不阻断后续——首条 failed 次条 done，调用序保持 FIFO', () async {
      final env = await _makeManagerEnv(scripts: {
        '/bad.mp3': _ScriptedDownload(error: WebDavException('网络炸了')),
      });
      await env.manager.enqueueMany([
        (1, testAudio('bad.mp3', '/bad.mp3')),
        (1, testAudio('good.mp3', '/good.mp3')),
      ]);
      await env.manager.pump();

      final byPath = {
        for (final r in await env.dao.listByConnection(1)) r.filePath: r
      };
      expect(byPath['/bad.mp3']!.status, DownloadStatus.failed);
      expect(byPath['/good.mp3']!.status, DownloadStatus.done,
          reason: '单条失败不得阻断循环，后续任务照常完成');
      expect(env.client.calledPaths, ['/bad.mp3', '/good.mp3'],
          reason: 'FIFO：backlog 按最早入队序处理');
    });

    test(
        'DL-01-S5 §5.3/S9 补偿: progressThrottle=1 天——节流窗口内多次 onProgress 仅首次落库 updateProgress',
        () async {
      final gate = Completer<void>();
      final env = await _makeManagerEnv(
        progressThrottle: const Duration(days: 1),
        scripts: {
          '/throttled.mp3':
              _ScriptedDownload(progressTicks: [100, 200, 300], hangGate: gate),
        },
      );
      await env.dao.upsert(_rec('/throttled.mp3', DownloadStatus.pending));
      unawaited(env.manager.pump());

      await _waitUntilAsync(() async => env.client.calledPaths.isNotEmpty);
      // 给三个刻度的回调与首写留出事件循环轮次
      await Future<void>.delayed(const Duration(milliseconds: 60));

      final mid = await env.dao.findByLocation(1, '/throttled.mp3');
      expect(mid!.bytesDownloaded, 100,
          reason: '首回调立即写库，窗口内后续回调全部丢弃（250ms 节流的极端化验证）');

      gate.completeError(WebDavException('收尾失败路径'));
      await _waitUntilAsync(() async =>
          (await env.dao.findByLocation(1, '/throttled.mp3'))!.status ==
          DownloadStatus.failed);
      final end = await env.dao.findByLocation(1, '/throttled.mp3');
      expect(end!.bytesDownloaded, 100,
          reason: '失败 setStatus 不携带 bytes，进度保持末次落库值');
    });

    test(
        'DL-01-S5 §5.3/S9 补偿: progressThrottle=Duration.zero——每次回调都落库，bytes 停在末回调值',
        () async {
      final gate = Completer<void>();
      final env = await _makeManagerEnv(
        progressThrottle: Duration.zero,
        scripts: {
          '/unthrottled.mp3':
              _ScriptedDownload(progressTicks: [100, 200, 300], hangGate: gate),
        },
      );
      await env.dao.upsert(_rec('/unthrottled.mp3', DownloadStatus.pending));
      unawaited(env.manager.pump());

      await _waitUntilAsync(() async => env.client.calledPaths.isNotEmpty);
      await Future<void>.delayed(const Duration(milliseconds: 60));

      final mid = await env.dao.findByLocation(1, '/unthrottled.mp3');
      expect(mid!.bytesDownloaded, 300,
          reason: '零窗口：每个回调都触发 updateProgress，最终停在末回调值');

      gate.completeError(WebDavException('收尾失败路径'));
      await _waitUntilAsync(() async =>
          (await env.dao.findByLocation(1, '/unthrottled.mp3'))!.status ==
          DownloadStatus.failed);
    });

    test('DL-01-S5: cancel(downloading)——行删除、泵续跑下一条、.part 残留清理', () async {
      final gateF = Completer<void>();
      final env = await _makeManagerEnv(scripts: {
        '/cancelme.mp3': _ScriptedDownload(hangGate: gateF),
      });
      await env.manager.enqueueMany([
        (1, testAudio('cancelme.mp3', '/cancelme.mp3')),
        (1, testAudio('after.mp3', '/after.mp3')),
      ]);
      await _waitUntilAsync(() async => env.client.calledPaths.isNotEmpty);

      final victim = await env.dao.findByLocation(1, '/cancelme.mp3');
      expect(victim!.status, DownloadStatus.downloading, reason: '前置：泵已选中该条');
      expect(
        _allFilesUnder(env.fs.downloadRoot).where((p) => p.endsWith('.part')),
        isNotEmpty,
        reason: '前置：传输中确实存在 .part 残留物',
      );

      await env.manager.cancel(victim.id!);

      expect(await env.dao.findByLocation(1, '/cancelme.mp3'), isNull,
          reason: '取消后行被删除');
      expect(
        _allFilesUnder(env.fs.downloadRoot).where((p) => p.endsWith('.part')),
        isEmpty,
        reason: 'S5 否定断言：取消后 .part 残留被清理',
      );

      gateF.complete(); // 放行挂起的 fake 传输（行已删，结果被丢弃）
      await _waitUntilAsync(
          () async =>
              (await env.dao.findByLocation(1, '/after.mp3'))?.status ==
              DownloadStatus.done,
          reason: '取消当前后泵必须继续处理下一条');
      expect(env.client.maxConcurrent, 1);
    });

    test('DL-01-S5: cancel(done)——行删除且本地成品文件一并删除', () async {
      final env = await _makeManagerEnv();
      await env.manager.enqueueMany([(1, testAudio('done.mp3', '/done.mp3'))]);
      await env.manager.pump();

      final rec = await env.dao.findByLocation(1, '/done.mp3');
      expect(rec!.status, DownloadStatus.done);
      expect(File(rec.localPath).existsSync(), isTrue,
          reason: '前置：fake 引擎产物已落盘');

      await env.manager.cancel(rec.id!);

      expect(await env.dao.findByLocation(1, '/done.mp3'), isNull);
      expect(File(rec.localPath).existsSync(), isFalse,
          reason: 'done 条目的 cancel 同时删除本地文件');
    });

    test('DL-01-S5: retry(failed)——重入队并被泵完成至 done', () async {
      final gate = Completer<void>();
      final env = await _makeManagerEnv(scripts: {
        '/retryme.mp3': _ScriptedDownload(hangGate: gate),
      });
      await env.dao.upsert(_rec('/retryme.mp3', DownloadStatus.failed));
      final id = (await env.dao.findByLocation(1, '/retryme.mp3'))!.id!;

      unawaited(env.manager.retry(id));
      // retry 先置 pending 再 pump：观察到 downloading 即证明经过了 pending
      await _waitUntilAsync(() async =>
          (await env.dao.findByLocation(1, '/retryme.mp3'))?.status ==
          DownloadStatus.downloading);

      gate.complete();
      await _waitUntilAsync(() async =>
          (await env.dao.findByLocation(1, '/retryme.mp3'))?.status ==
          DownloadStatus.done);
      expect(env.client.calledPaths, ['/retryme.mp3']);
    });

    test('DL-01-S5: 泵活跃期间 enqueue 只插行不并发下载，当前完成后继续', () async {
      final gateFirst = Completer<void>();
      final env = await _makeManagerEnv(scripts: {
        '/slow.mp3': _ScriptedDownload(hangGate: gateFirst),
      });
      await env.manager.enqueueMany([(1, testAudio('slow.mp3', '/slow.mp3'))]);
      await _waitUntilAsync(() async => env.client.currentConcurrent == 1);

      final n = await env.manager
          .enqueueMany([(1, testAudio('late.mp3', '/late.mp3'))]);
      expect(n, 1, reason: '活跃期间 enqueue 正常插行');
      expect(env.client.currentConcurrent, 1, reason: '否定断言：enqueue 不得引发并发下载');
      expect(env.client.maxConcurrent, 1, reason: 'INV2 在动态入队场景下同样成立');
      expect(env.client.calledPaths, isNot(contains('/late.mp3')));

      gateFirst.complete();
      await _waitUntilAsync(
          () async =>
              (await env.dao.findByLocation(1, '/late.mp3'))?.status ==
              DownloadStatus.done,
          reason: '当前完成后泵继续消化新入队条目');
    });

    test('DL-01-S5: remoteUrlResolver 注入——默认占位基址，自定义 resolver 原样透传给 client',
        () async {
      // 默认（未传 resolver）：占位基址
      final envDefault = await _makeManagerEnv();
      await envDefault.dao.upsert(_rec('/u1.mp3', DownloadStatus.pending));
      await envDefault.manager.pump();
      expect(envDefault.client.calledUrls.single, 'http://localhost',
          reason: '默认 null resolver 使用占位基址（URL 注记裁决）');

      // 自定义 resolver
      final envCustom = await _makeManagerEnv(
          remoteUrlResolver: () => 'http://nas.example.com:5005/dav');
      await envCustom.dao.upsert(_rec('/u2.mp3', DownloadStatus.pending));
      await envCustom.manager.pump();
      expect(
          envCustom.client.calledUrls.single, 'http://nas.example.com:5005/dav',
          reason: '自定义 resolver 产出的有效基址原样透传');
    });

    test(
        'DL-01-INV4 收口: 整个引擎（manager+pump+成败两路）全程只用注入端口跑通——fake client/fs + 真 dao',
        () async {
      final env = await _makeManagerEnv(scripts: {
        '/fail.mp3': _ScriptedDownload(error: WebDavException('注入失败')),
      });
      final n = await env.manager.enqueueMany([
        (1, testAudio('fail.mp3', '/fail.mp3')),
        (1, testAudio('ok.mp3', '/ok.mp3', size: 64)),
      ]);
      expect(n, 2);
      await env.manager.pump();

      final byPath = {
        for (final r in await env.dao.listByConnection(1)) r.filePath: r
      };
      expect(byPath['/fail.mp3']!.status, DownloadStatus.failed);
      expect(byPath['/ok.mp3']!.status, DownloadStatus.done);

      // fake 调用计数收口：网络 IO 全部命中注入端口，且严格串行
      expect(env.client.calledPaths, ['/fail.mp3', '/ok.mp3']);
      expect(env.client.maxConcurrent, 1);
      // 文件 IO 也全部经 fs 端口落在临时根内
      expect(
          _allFilesUnder(env.fs.downloadRoot).where((p) => p.endsWith('.part')),
          isEmpty,
          reason: '成功 rename 后无 .part 残留');
      expect(File(byPath['/ok.mp3']!.localPath).readAsStringSync(),
          'partial:/ok.mp3',
          reason: '成品内容由注入端口写入，可全量断言');
    });
  });

  // ───────────────────────────────────────────────────────────────────────
  // DL-01-S6 orchestrator 本地优先加载
  // ───────────────────────────────────────────────────────────────────────
  group('DL-01-S6 orchestrator 本地优先加载', () {
    test(
        'DL-01-S6: 本地命中——setAudioSource 收到 file:// 源、跳过密码读取与远程建源、startPositionMs 同样生效、返回 loaded',
        () async {
      final rig = _makeOrchRig(localSourceResolver: (connId, filePath) async {
        expect(connId, 1);
        expect(filePath, '/music/song.mp3');
        return '/data/local/song.mp3';
      });
      rig.orchestrator.queue = _makeQueue(startPositionMs: 5000);

      final result = await rig.orchestrator.loadAndPlay();

      expect(result.isLoaded, isTrue);
      expect(rig.sources, hasLength(1));
      expect(_sourceUri(rig.sources.single).scheme, 'file',
          reason: '本地命中走 AudioSource.file 直读');
      expect(_sourceUri(rig.sources.single).path, '/data/local/song.mp3');
      expect(rig.log, ['setAudioSource', 'seek'],
          reason: '否定断言：本地命中时不读密码、不走远程建源（log 中无 readPassword）');
      expect(rig.reader.calls, 0, reason: '否定断言：免一次 secure storage 密码读取');
      verify(rig.player.seek(const Duration(milliseconds: 5000))).called(1);
    });

    test(
        'DL-01-INV1: 无本地命中时 loadAndPlay 与现状逐字节等价——readPassword → setAudioSource(http) → seek 顺序不变',
        () async {
      final rig = _makeOrchRig(); // 默认 resolver=null → 远程路径
      rig.orchestrator.queue = _makeQueue(startPositionMs: 7000);

      final result = await rig.orchestrator.loadAndPlay();

      expect(result.isLoaded, isTrue);
      expect(rig.log, ['readPassword', 'setAudioSource', 'seek'],
          reason: 'INV1：远程路径调用序列与 DL-01 之前的现状完全一致');
      expect(rig.sources, hasLength(1));
      expect(_sourceUri(rig.sources.single).scheme, 'http',
          reason: '远程建源产物为 http 源');
      expect(rig.reader.calls, 1);
      verify(rig.player.seek(const Duration(milliseconds: 7000))).called(1);
    });

    test('DL-01-S6: resolver 抛错（DB 异常）→ 记日志后按 null 继续远程路径，播放不中断', () async {
      final rig = _makeOrchRig(localSourceResolver: (_, __) async {
        throw Exception('数据库锁住');
      });
      rig.orchestrator.queue = _makeQueue(startPositionMs: 0);

      final result = await rig.orchestrator.loadAndPlay();

      expect(result.isLoaded, isTrue, reason: 'resolver 异常不得中断播放（BUG-18 同族兜底）');
      expect(rig.log, ['readPassword', 'setAudioSource', 'seek'],
          reason: '兜底走完整远程路径');
      expect(_sourceUri(rig.sources.single).scheme, 'http');
    });

    test(
        'DL-01-S6 §5.3 盲点补偿: resolver 挂起期间第二次 loadAndPlay 使其过期 → 第一次返回 superseded 且未触达 setAudioSource',
        () async {
      final gate = Completer<String?>();
      var resolverCalls = 0;
      // 机械修正：Dart 禁止局部变量在其自身初始化器中被引用；改用 late 赋值，
      // 闭包首次运行时 rig 必已完成赋值（语义不变）。
      late final _OrchRig rig;
      rig = _makeOrchRig(localSourceResolver: (_, __) {
        resolverCalls++;
        if (resolverCalls == 1) {
          rig.log.add('resolver-hang');
          return gate.future;
        }
        return Future<String?>.value(null);
      });

      rig.orchestrator.queue =
          _makeQueue(path: '/music/first.mp3', startPositionMs: 0);
      final first = rig.orchestrator.loadAndPlay();
      await _waitUntilAsync(() async => rig.log.contains('resolver-hang'));

      rig.orchestrator.queue =
          _makeQueue(path: '/music/second.mp3', startPositionMs: 0);
      final second = await rig.orchestrator.loadAndPlay();

      expect(second.isLoaded, isTrue, reason: '第二次请求正常完成远程路径');
      expect(
          rig.log, ['resolver-hang', 'readPassword', 'setAudioSource', 'seek'],
          reason: '第一次请求停在 resolver，不得贡献任何后续调用');

      gate.complete('/data/local/first.mp3');
      final firstResult = await first;

      expect(firstResult.isLoaded, isFalse);
      expect(firstResult.status, TrackLoadStatus.superseded,
          reason: 'resolver await 之后 _gate.isLatest 复查：恢复后第一次必须被判过期');
      expect(rig.sources, hasLength(1), reason: '否定断言：全程仅第二次触达 setAudioSource');
    });

    test('DL-01-S6 §8-R2 冒烟: AudioSource.file 构造可用（编译期 API 存在性验证，不需真播）', () {
      expect(AudioSource.file('/tmp/x.mp3'), isA<AudioSource>());
    });
  });

  // ───────────────────────────────────────────────────────────────────────
  // DL-01-S7 文件长按「下载此文件」
  // ───────────────────────────────────────────────────────────────────────
  group('DL-01-S7 文件长按菜单下载项', () {
    testWidgets('DL-01-S7 U1: 无进度文件长按必弹层——含「下载此文件」，点击提示已加入下载队列并落库',
        (tester) async {
      final tree = _Tree()..put('/', [testAudio('song.mp3', '/song.mp3')]);
      final env = await _makeWidgetEnv();
      final container =
          await _pumpBrowser(tester, await _browserOverrides(tree, env));

      await tester.longPress(find.text('song.mp3'));
      await tester.pumpAndSettle();

      expect(find.text('下载此文件'), findsOneWidget,
          reason: 'U1：本 spec 改为查到无进度也必弹层（不再拦截）');
      expect(find.byIcon(Icons.download_outlined), findsOneWidget);

      await tester.tap(find.text('下载此文件'));
      await tester.pumpAndSettle();

      expect(find.textContaining('已加入下载队列'), findsOneWidget);
      final dao = container.read(downloadDaoProvider);
      final rec = await dao.findByLocation(1, '/song.mp3');
      expect(rec, isNotNull, reason: '点击后必须经 manager 入队落库');
      expect(rec!.connectionId, 1);
      expect(rec.filePath, '/song.mp3');
      expect(
          rec.status, anyOf(DownloadStatus.pending, DownloadStatus.downloading),
          reason: '泵自动启动后可能已转 downloading；关键是行已入队');
    });

    testWidgets('DL-01-S7 U8: 重复长按同一文件 → 「已在下载列表中」，行数不变', (tester) async {
      final tree = _Tree()..put('/', [testAudio('song.mp3', '/song.mp3')]);
      final env = await _makeWidgetEnv();
      await _pumpBrowser(tester, await _browserOverrides(tree, env));

      // 第一次：正常入队
      await tester.longPress(find.text('song.mp3'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('下载此文件'));
      await tester.pumpAndSettle();
      expect(find.textContaining('已加入下载队列'), findsOneWidget);

      // 关掉 SnackBar 层后再次长按
      // 机械适配：SnackBar 由定时器自动退出，背景 tapAt 并不会关闭它；改为
      // 推进虚拟时间让其自然消失（意图不变：清空 SnackBar 层）。
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
      await tester.longPress(find.text('song.mp3'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('下载此文件'));
      await tester.pumpAndSettle();

      expect(find.textContaining('已在下载列表中'), findsOneWidget,
          reason: 'U8：已有 pending/downloading/done 行 → 提示已在列表中');
      expect(find.textContaining('已加入下载队列'), findsNothing,
          reason: '否定断言：重复入队不得再提示已加入');
      final rows = await env.dao.listByConnection(1);
      expect(rows, hasLength(1), reason: '否定断言：不重复建行');
    });

    testWidgets('DL-01-S7: 已有 failed 行允许再入队——状态脱离 failed（U8 边界）',
        (tester) async {
      final tree = _Tree()..put('/', [testAudio('song.mp3', '/song.mp3')]);
      final env = await _makeWidgetEnv();
      await env.dao.upsert(_rec('/song.mp3', DownloadStatus.failed));
      await _pumpBrowser(tester, await _browserOverrides(tree, env));

      await tester.longPress(find.text('song.mp3'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('下载此文件'));
      await tester.pumpAndSettle();

      expect(find.textContaining('已在下载列表中'), findsNothing,
          reason: 'failed 不属于「已在下载列表」拦截范围');
      final rec = await env.dao.findByLocation(1, '/song.mp3');
      expect(rec!.status, isNot(DownloadStatus.failed),
          reason: 'failed 允许重下：入队后脱离 failed（挂起型泵下稳定于 downloading）');
    });

    testWidgets('DL-01-S7 否定面: 清除播放进度项行为零变化——两项并存，清除后提示固定文案且进度行删除',
        (tester) async {
      final tree = _Tree()..put('/', [testAudio('song.mp3', '/song.mp3')]);
      final env = await _makeWidgetEnv();
      final progressDao = ProgressDao();
      await progressDao.rawInsertForTest(
          testProgress(connectionId: 1, filePath: '/song.mp3'));

      await _pumpBrowser(
          tester, await _browserOverrides(tree, env, progressDao: progressDao));

      await tester.longPress(find.text('song.mp3'));
      await tester.pumpAndSettle();

      expect(find.text('清除播放进度'), findsOneWidget,
          reason: '进度存在时才渲染清除项（BUG-18 加固保持）');
      expect(find.text('下载此文件'), findsOneWidget, reason: '新增常驻下载项与清除项并存');

      await tester.tap(find.text('清除播放进度'));
      await tester.pumpAndSettle();

      expect(find.textContaining('播放进度已清除'), findsOneWidget, reason: '既有行为零变化');
      expect(await progressDao.find(1, '/song.mp3'), isNull, reason: '进度行确被清除');
    });
  });

  // ───────────────────────────────────────────────────────────────────────
  // DL-01-S8 目录菜单第三项「下载此文件夹」
  // ───────────────────────────────────────────────────────────────────────
  group('DL-01-S8 目录菜单下载项', () {
    testWidgets('DL-01-S8 U2: 菜单第三项「下载此文件夹」——扫描后整目录入队，提示已加入 N 首，不导航不写队列',
        (tester) async {
      final tree = _Tree()
        ..put('/', [testDir('Music', '/Music')])
        ..gate('/Music');
      final env = await _makeWidgetEnv();
      final container =
          await _pumpBrowser(tester, await _browserOverrides(tree, env));

      await tester.longPress(find.text('Music'));
      await tester.pumpAndSettle();

      // BRW-01 两项原样 + 第三项新增
      expect(find.text('从此处播放'), findsOneWidget);
      expect(find.text('加入播放单…'), findsOneWidget);
      expect(find.text('下载此文件夹'), findsOneWidget);
      // SDK 无 Icons.folder_download(_outlined)（机械适配）：与实现侧一致
      // 取 download_for_offline_outlined。
      expect(find.byIcon(Icons.download_for_offline_outlined), findsOneWidget);

      await tester.tap(find.text('下载此文件夹'));
      await tester.pump();
      expect(find.text('正在扫描文件夹…'), findsOneWidget,
          reason: '复用 BRW-01 loading 对话框');

      tree.gate('/Music').complete([
        testAudio('a.mp3', '/Music/a.mp3'),
        testAudio('b.mp3', '/Music/b.mp3'),
      ]);
      await tester.pumpAndSettle();

      expect(find.textContaining('已加入 2 首'), findsOneWidget);
      final rows = await env.dao.listByConnection(1);
      expect(rows, hasLength(2));
      expect(
          rows.every((r) =>
              r.status == DownloadStatus.pending ||
              r.status == DownloadStatus.downloading),
          isTrue);

      // 否定断言：不 push /player、不写队列 provider
      expect(find.text('Player'), findsNothing, reason: '否定断言：不 push /player');
      expect(container.read(currentPlayQueueProvider), isNull,
          reason: '否定断言：不写 currentPlayQueueProvider');
      expect(find.byType(Dialog), findsNothing, reason: 'loading 对话框已关');
    });

    testWidgets('DL-01-S8: 空文件夹 → 「该文件夹没有音频文件」，不入队', (tester) async {
      final tree = _Tree()
        ..put('/', [testDir('Empty', '/Empty')])
        ..put('/Empty', <NasFile>[]);
      final env = await _makeWidgetEnv();
      final container =
          await _pumpBrowser(tester, await _browserOverrides(tree, env));

      await tester.longPress(find.text('Empty'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('下载此文件夹'));
      await tester.pumpAndSettle();

      expect(find.text('该文件夹没有音频文件'), findsOneWidget);
      expect(await env.dao.listByConnection(1), isEmpty, reason: '空集不入队');
      expect(container.read(currentPlayQueueProvider), isNull);
    });

    testWidgets('DL-01-S8: 扫描失败 → 固定文案「无法读取文件夹内容，请检查连接」（脱敏），不入队不导航',
        (tester) async {
      final tree = _Tree()
        ..put('/', [testDir('Broken', '/Broken')])
        ..gate('/Broken');
      final env = await _makeWidgetEnv();
      final container =
          await _pumpBrowser(tester, await _browserOverrides(tree, env));

      await tester.longPress(find.text('Broken'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('下载此文件夹'));
      await tester.pump();

      tree.gate('/Broken').completeError(const WebDavException('没有活跃的连接'));
      await tester.pumpAndSettle();

      expect(find.text('无法读取文件夹内容，请检查连接'), findsOneWidget,
          reason: 'BRW-01 S6 同款固定文案');
      expect(find.text('没有活跃的连接'), findsNothing, reason: '脱敏纪律：异常原文不得展示');
      expect(await env.dao.listByConnection(1), isEmpty);
      expect(container.read(currentPlayQueueProvider), isNull);
      expect(find.text('Player'), findsNothing);
    });

    testWidgets('DL-01-S8: 600 音频目录 → 入队前 500 首并提示「已截取前 500 首」',
        (tester) async {
      final tree = _Tree()
        ..put('/', [testDir('Big', '/Big')])
        ..put(
            '/Big',
            List.generate(
                600,
                (i) => testAudio('f${i.toString().padLeft(3, '0')}.mp3',
                    '/Big/f${i.toString().padLeft(3, '0')}.mp3')));
      final env = await _makeWidgetEnv();
      await _pumpBrowser(tester, await _browserOverrides(tree, env));

      await tester.longPress(find.text('Big'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('下载此文件夹'));
      await tester.pumpAndSettle();

      expect(find.textContaining('已截取前 500 首'), findsOneWidget,
          reason: 'truncated 照常提示 BRW-01 S5⑥ 同款截断文案');
      final rows = await env.dao.listByConnection(1);
      expect(rows, hasLength(500), reason: '截断后只入队前 500 首');
    });
  });

  // ───────────────────────────────────────────────────────────────────────
  // DL-01-S9 /downloads 管理页
  // ───────────────────────────────────────────────────────────────────────
  group('DL-01-S9 /downloads 管理页', () {
    /// 定位某行 ListTile 内的 IconButton（机械假设：行尾按钮矩阵为 IconButton；
    /// failed 行 [重试, 删除]、done 行 [删除]、downloading/pending 行 [取消]）。
    Finder _rowButtons(String fileNameText) {
      final tile = find
          .ancestor(
              of: find.text(fileNameText), matching: find.byType(ListTile))
          .first;
      return find.descendant(of: tile, matching: find.byType(IconButton));
    }

    /// 播种四种状态行（done 行配真实临时成品文件）。
    Future<String> _seedFourStatuses(_WidgetEnv env) async {
      final donePath = '${env.tempDir.path}/c_done_local.mp3';
      File(donePath)
        ..parent.createSync(recursive: true)
        ..writeAsStringSync('done-bytes', flush: true);
      await env.dao.upsert(_rec('/a.mp3', DownloadStatus.pending, remote: 100));
      await env.dao.upsert(
          _rec('/b.mp3', DownloadStatus.downloading, remote: 1000, bytes: 400));
      await env.dao.upsert(
          _rec('/c.mp3', DownloadStatus.done, remote: 300, local: donePath));
      await env.dao.upsert(_rec('/d.mp3', DownloadStatus.failed, remote: 50));
      return donePath;
    }

    List<Override> _downloadsOverrides(_WidgetEnv env,
        {required ConnectionConfig? conn}) {
      return [
        activeConnectionProvider.overrideWith((ref) async => conn),
        downloadDaoProvider.overrideWithValue(env.dao),
        downloadFileSystemProvider.overrideWithValue(env.fs),
        downloadManagerProvider.overrideWith((ref) => DownloadManager(
              client: env.client,
              dao: env.dao,
              fs: env.fs,
            )),
      ];
    }

    /// 收尾排水：清空 downloads 行并驱动两秒虚拟时钟，
    /// 让「仅有 downloading 时运行」的 Timer.periodic 有机会自我取消（P13）。
    Future<void> _drainRefreshTimers(
        WidgetTester tester, _WidgetEnv env) async {
      await env.db.delete('downloads');
      await tester.pump(const Duration(seconds: 2));
      await tester.pump(const Duration(seconds: 2));
    }

    testWidgets('DL-01-S9 U3: 四种状态徽章齐备——等待中/下载中/已完成(大小)/失败各一行，底部显示共占用',
        (tester) async {
      final env = await _makeWidgetEnv();
      await _seedFourStatuses(env);
      await tester.pumpWidget(buildTestApp(
        DownloadsScreen(),
        overrides: _downloadsOverrides(env, conn: _conn),
      ));
      await tester.pumpAndSettle();

      expect(find.text('等待中'), findsOneWidget);
      expect(find.text('下载中'), findsOneWidget);
      expect(find.text('已完成'), findsOneWidget);
      expect(find.text('失败'), findsOneWidget);
      expect(find.textContaining('300'), findsWidgets,
          reason: 'done 行显示大小（remote_size=300）');
      expect(find.byType(LinearProgressIndicator), findsWidgets,
          reason: '下载中行渲染进度条');
      expect(find.textContaining('共占用 300'), findsOneWidget,
          reason: '底部 totalBytesByConnection：仅 done 行 300 计入');

      await _drainRefreshTimers(tester, env);
    });

    testWidgets('DL-01-S9 U9: 删除已完成条目——行消失且本地成品文件一并删除', (tester) async {
      final env = await _makeWidgetEnv();
      final donePath = await _seedFourStatuses(env);
      await tester.pumpWidget(buildTestApp(
        DownloadsScreen(),
        overrides: _downloadsOverrides(env, conn: _conn),
      ));
      await tester.pumpAndSettle();

      // 机械假设：done 行按钮矩阵 [删除]=末位
      await tester.tap(_rowButtons('c.mp3').last, warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(find.text('c.mp3'), findsNothing, reason: '行从列表消失');
      expect(File(donePath).existsSync(), isFalse, reason: 'U9：本地文件一起删');
      expect(await env.dao.findByLocation(1, '/c.mp3'), isNull);

      await _drainRefreshTimers(tester, env);
    });

    testWidgets('DL-01-S9: 失败条目重试 → 状态脱离 failed（head-block 下为等待中）',
        (tester) async {
      final env = await _makeWidgetEnv();
      await _seedFourStatuses(env);
      await tester.pumpWidget(buildTestApp(
        DownloadsScreen(),
        overrides: _downloadsOverrides(env, conn: _conn),
      ));
      await tester.pumpAndSettle();

      // 机械假设：failed 行按钮矩阵 [重试, 删除]，取首个=重试
      await tester.tap(_rowButtons('d.mp3').first, warnIfMissed: false);
      await tester.pumpAndSettle();

      final rec = await env.dao.findByLocation(1, '/d.mp3');
      expect(rec!.status,
          anyOf(DownloadStatus.pending, DownloadStatus.downloading),
          reason: 'retry 后脱离 failed（DB 扫描型泵会先吃掉更早的 pending 头任务，'
              '目标行停留等待中；内存 backlog 型则为下载中）');
      expect(find.text('失败'), findsNothing);

      await _drainRefreshTimers(tester, env);
    });

    testWidgets('DL-01-S9 U4: 取消——downloading 与 pending 条目均可从列表移除',
        (tester) async {
      final env = await _makeWidgetEnv();
      await _seedFourStatuses(env);
      await tester.pumpWidget(buildTestApp(
        DownloadsScreen(),
        overrides: _downloadsOverrides(env, conn: _conn),
      ));
      await tester.pumpAndSettle();

      // 机械假设：downloading 行按钮矩阵 [取消]
      await tester.tap(_rowButtons('b.mp3').first, warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(find.text('b.mp3'), findsNothing);
      expect(await env.dao.findByLocation(1, '/b.mp3'), isNull);

      // 机械假设：pending 行按钮矩阵 [取消]
      await tester.tap(_rowButtons('a.mp3').first, warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(find.text('a.mp3'), findsNothing);
      expect(await env.dao.findByLocation(1, '/a.mp3'), isNull);

      await _drainRefreshTimers(tester, env);
    });

    testWidgets('DL-01-S9: 清空全部——确认对话框后全部行消失、本地文件删净、dao 清空', (tester) async {
      final env = await _makeWidgetEnv();
      final donePath = await _seedFourStatuses(env);
      await tester.pumpWidget(buildTestApp(
        DownloadsScreen(),
        overrides: _downloadsOverrides(env, conn: _conn),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.textContaining('清空'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget, reason: '必须弹出二次确认对话框');

      final confirm = find
          .descendant(
              of: find.byType(AlertDialog),
              matching: find.byWidgetPredicate((w) => w is TextButton))
          .last;
      await tester.tap(confirm, warnIfMissed: false);
      await tester.pumpAndSettle();

      for (final name in ['a.mp3', 'b.mp3', 'c.mp3', 'd.mp3']) {
        expect(find.text(name), findsNothing, reason: '$name 行已消失');
      }
      expect(await env.dao.listByConnection(1), isEmpty);
      expect(File(donePath).existsSync(), isFalse, reason: '本地文件删净');
    });

    testWidgets('DL-01-S9: 无活跃连接 → 「请先连接 NAS」空态，不渲染任务行', (tester) async {
      final env = await _makeWidgetEnv();
      await _seedFourStatuses(env);
      await tester.pumpWidget(buildTestApp(
        DownloadsScreen(),
        overrides: _downloadsOverrides(env, conn: null),
      ));
      await tester.pumpAndSettle();

      expect(find.text('请先连接 NAS'), findsOneWidget);
      expect(find.text('等待中'), findsNothing, reason: '否定断言：无活跃连接不查询不渲染');
    });
  });

  // ───────────────────────────────────────────────────────────────────────
  // DL-01-S10 启动孤儿恢复
  // ───────────────────────────────────────────────────────────────────────
  group('DL-01-S10 recoverOrphanDownloads 启动孤儿恢复', () {
    test('DL-01-S10: pending/downloading → failed，done/failed 不动（done 终态否定断言）',
        () async {
      final db = await openTestDatabase(TestSchema.full);
      addTearDown(db.close);
      await seedConnection(db);
      await db.insert('downloads', {
        'connection_id': 1,
        'file_path': '/p.mp3',
        'file_name': 'p.mp3',
        'remote_size': 1,
        'local_path': '/x1',
        'status': 'pending',
        'bytes_downloaded': 0,
        'created_at': _ts,
        'updated_at': _ts,
      });
      await db.insert('downloads', {
        'connection_id': 1,
        'file_path': '/dl.mp3',
        'file_name': 'dl.mp3',
        'remote_size': 1,
        'local_path': '/x2',
        'status': 'downloading',
        'bytes_downloaded': 33,
        'created_at': _ts,
        'updated_at': _ts,
      });
      await db.insert('downloads', {
        'connection_id': 1,
        'file_path': '/done.mp3',
        'file_name': 'done.mp3',
        'remote_size': 1,
        'local_path': '/x3',
        'status': 'done',
        'bytes_downloaded': 99,
        'created_at': _ts,
        'updated_at': _ts,
      });
      await db.insert('downloads', {
        'connection_id': 1,
        'file_path': '/f.mp3',
        'file_name': 'f.mp3',
        'remote_size': 1,
        'local_path': '/x4',
        'status': 'failed',
        'bytes_downloaded': 0,
        'created_at': _ts,
        'updated_at': _ts,
      });

      await recoverOrphanDownloads();

      final rows = await db.query('downloads');
      final byPath = {for (final r in rows) r['file_path'] as String: r};
      expect(byPath['/p.mp3']!['status'], DownloadStatus.failed,
          reason: 'B5-8：杀 App 时排队的任务重启后标失败');
      expect(byPath['/dl.mp3']!['status'], DownloadStatus.failed);
      expect(byPath['/done.mp3']!['status'], DownloadStatus.done,
          reason: '否定断言：done 记录不受影响（终态）');
      expect(byPath['/f.mp3']!['status'], DownloadStatus.failed);
    });

    test('DL-01-S10: 空 downloads 表恢复一遍不抛错', () async {
      final db = await openTestDatabase(TestSchema.full);
      addTearDown(db.close);
      await seedConnection(db);

      await expectLater(recoverOrphanDownloads(), completes);
    });

    test('DL-01-S10: DB 打不开（句柄已关闭）→ catch-log 静默返回，App 照常启动', () async {
      final db = await openTestDatabase(TestSchema.downloads);
      addTearDown(() => DatabaseHelper.instance.resetForTest());
      await db.close(); // 句柄仍挂在 DatabaseHelper 上但已不可用

      // 绝不抛出：内部 catch 后 debugPrint 静默返回
      await expectLater(recoverOrphanDownloads(), completes);
    });
  });

  // ───────────────────────────────────────────────────────────────────────
  // DL-01-INV3 / INV5
  // ───────────────────────────────────────────────────────────────────────
  group('DL-01 不变量专项', () {
    test(
        'DL-01-INV3: playback_orchestrator.dart 保持零 dart:io——文件存在性封装于 provider 层 resolver',
        () async {
      final src = await File(
              '${Directory.current.path}/lib/features/player/domain/playback_orchestrator.dart')
          .readAsString();
      expect(src.contains('dart:io'), isFalse,
          reason: 'INV3：domain 只见 String? 路径，File 存在性检查在 provider 层');
      // resolver 抛错兜底行为已在 'DL-01-S6: resolver 抛错…' 用例复验（同组互证）。
    });

    test(
        'DL-01-INV5 收口: 半成品不可达——downloading 行（local_path 已填、bytes 半截）findDoneLocalPath 返回 null',
        () async {
      final db = await openTestDatabase(TestSchema.downloads);
      addTearDown(db.close);
      await seedConnection(db);
      final dao = DownloadDao();

      await dao.upsert(_rec('/half.mp3', DownloadStatus.downloading,
          local: '${Directory.systemTemp.path}/half.mp3', bytes: 512));

      expect(await dao.findDoneLocalPath(1, '/half.mp3'), isNull,
          reason: 'INV5：三重闸之 Dao 层——非 done 一律 null（S3 失败路径的 '
              'final 不存在断言已在 DL-01-S3 断流用例复验）');
    });
  });

  // ───────────────────────────────────────────────────────────────────────
  // DL-01-ALG1 状态机迁移表穷举
  // ───────────────────────────────────────────────────────────────────────
  group('DL-01-ALG1 download-state-machine', () {
    test('DL-01-ALG1: 迁移表逐格锁定——每格结果唯一，done 是终态（唯一出口用户删除），failed 双路回 pending',
        () async {
      // ── 格1 pending + enqueue(同path) = skip ────────────────────────────
      {
        final gateG = Completer<void>();
        final env = await _makeManagerEnv(scripts: {
          '/g.mp3': _ScriptedDownload(hangGate: gateG),
        });
        await env.dao
            .upsert(_rec('/g.mp3', DownloadStatus.pending, updatedAt: _tsOld));
        await env.dao
            .upsert(_rec('/f.mp3', DownloadStatus.pending, updatedAt: _ts));
        final returned =
            await env.manager.enqueueMany([(1, testAudio('f.mp3', '/f.mp3'))]);
        expect(returned, 0, reason: '格1：pending+enqueue → skip（返回 0）');
        final f = await env.dao.findByLocation(1, '/f.mp3');
        expect(f!.status, DownloadStatus.pending, reason: '格1：状态保持 pending');
        expect(await env.dao.listByConnection(1), hasLength(2),
            reason: '格1：不产生第二行');
        gateG.complete();
      }

      // ── 格2 pending + pump选中 = downloading ────────────────────────────
      {
        final gate = Completer<void>();
        final env = await _makeManagerEnv(scripts: {
          '/f.mp3': _ScriptedDownload(hangGate: gate),
        });
        await env.dao.upsert(_rec('/f.mp3', DownloadStatus.pending));
        unawaited(env.manager.pump());
        await _waitUntilAsync(() async => env.client.calledPaths.isNotEmpty);
        expect((await env.dao.findByLocation(1, '/f.mp3'))!.status,
            DownloadStatus.downloading,
            reason: '格2：泵选中即转 downloading');
        gate.complete();
      }

      // ── 格3 downloading + 下载成功 = done ──────────────────────────────
      {
        final env = await _makeManagerEnv();
        await env.dao.upsert(_rec('/f.mp3', DownloadStatus.pending));
        await env.manager.pump();
        expect((await env.dao.findByLocation(1, '/f.mp3'))!.status,
            DownloadStatus.done,
            reason: '格3：成功终态 done');
      }

      // ── 格4 downloading + 下载失败 = failed ────────────────────────────
      {
        final env = await _makeManagerEnv(scripts: {
          '/f.mp3': _ScriptedDownload(error: WebDavException('boom')),
        });
        await env.dao.upsert(_rec('/f.mp3', DownloadStatus.pending));
        await env.manager.pump();
        expect((await env.dao.findByLocation(1, '/f.mp3'))!.status,
            DownloadStatus.failed,
            reason: '格4：失败转 failed');
      }

      // ── 格5 pending + cancel = 删除 ─────────────────────────────────────
      {
        final gateG = Completer<void>();
        final env = await _makeManagerEnv(scripts: {
          '/g.mp3': _ScriptedDownload(hangGate: gateG),
        });
        await env.dao
            .upsert(_rec('/g.mp3', DownloadStatus.pending, updatedAt: _tsOld));
        await env.dao
            .upsert(_rec('/f.mp3', DownloadStatus.pending, updatedAt: _ts));
        unawaited(env.manager.pump());
        await _waitUntilAsync(() async => env.client.calledPaths.isNotEmpty,
            reason: '格5 前置：G 占住泵');
        final fid = (await env.dao.findByLocation(1, '/f.mp3'))!.id!;
        await env.manager.cancel(fid);
        expect(await env.dao.findByLocation(1, '/f.mp3'), isNull,
            reason: '格5：pending+cancel → 行删除');
        gateG.complete();
      }

      // ── 格6 downloading + cancel = 删除 + .part 清理 ────────────────────
      {
        final gate = Completer<void>();
        final env = await _makeManagerEnv(scripts: {
          '/f.mp3': _ScriptedDownload(hangGate: gate),
        });
        await env.dao.upsert(_rec('/f.mp3', DownloadStatus.pending));
        unawaited(env.manager.pump());
        await _waitUntilAsync(() async => env.client.calledPaths.isNotEmpty);
        final fid = (await env.dao.findByLocation(1, '/f.mp3'))!.id!;
        await env.manager.cancel(fid);
        expect(await env.dao.findByLocation(1, '/f.mp3'), isNull,
            reason: '格6：downloading+cancel → 行删除');
        expect(
          _allFilesUnder(env.fs.downloadRoot).where((p) => p.endsWith('.part')),
          isEmpty,
          reason: '格6：.part 残留同时清理',
        );
        gate.complete();
      }

      // ── 格7 done + cancel = 删除 + 删文件 ──────────────────────────────
      {
        final env = await _makeManagerEnv();
        await env.dao.upsert(_rec('/f.mp3', DownloadStatus.pending));
        await env.manager.pump();
        final rec = await env.dao.findByLocation(1, '/f.mp3');
        expect(File(rec!.localPath).existsSync(), isTrue,
            reason: '格7 前置：成品已落盘');
        await env.manager.cancel(rec.id!);
        expect(await env.dao.findByLocation(1, '/f.mp3'), isNull,
            reason: '格7：done+cancel → 行删除');
        expect(File(rec.localPath).existsSync(), isFalse,
            reason: '格7：done 唯一出口是用户删除，本地文件随之删除');
      }

      // ── 格8 failed + retry = pending（经泵选中可观测为 downloading） ────
      {
        final gate = Completer<void>();
        final env = await _makeManagerEnv(scripts: {
          '/f.mp3': _ScriptedDownload(hangGate: gate),
        });
        await env.dao.upsert(_rec('/f.mp3', DownloadStatus.failed));
        final fid = (await env.dao.findByLocation(1, '/f.mp3'))!.id!;
        unawaited(env.manager.retry(fid));
        await _waitUntilAsync(
            () async =>
                (await env.dao.findByLocation(1, '/f.mp3'))?.status ==
                DownloadStatus.downloading,
            reason: '格8：failed+retry 回 pending 后被泵选中（transient pending 不可采样，'
                '以 downloading 证明重入队链路）');
        gate.complete();
        await _waitUntilAsync(() async =>
            (await env.dao.findByLocation(1, '/f.mp3'))?.status ==
            DownloadStatus.done);
      }

      // ── 格9 启动恢复 non-done → failed；done 不动 ───────────────────────
      {
        final env = await _makeManagerEnv();
        await env.dao
            .upsert(_rec('/p.mp3', DownloadStatus.pending, updatedAt: _tsOld));
        await env.dao.upsert(
            _rec('/dl.mp3', DownloadStatus.downloading, updatedAt: _tsOld));
        await env.dao
            .upsert(_rec('/done.mp3', DownloadStatus.done, updatedAt: _tsOld));
        await env.dao
            .upsert(_rec('/f.mp3', DownloadStatus.failed, updatedAt: _tsOld));

        await recoverOrphanDownloads();

        final byPath = {
          for (final r in await env.dao.listByConnection(1)) r.filePath: r
        };
        expect(byPath['/p.mp3']!.status, DownloadStatus.failed, reason: '格9a');
        expect(byPath['/dl.mp3']!.status, DownloadStatus.failed, reason: '格9b');
        expect(byPath['/done.mp3']!.status, DownloadStatus.done,
            reason: '格9c：done+恢复=不动（终态否定断言）');
        expect(byPath['/f.mp3']!.status, DownloadStatus.failed, reason: '格9d');
      }

      // ── 格10 failed + enqueue = 重新入队 pending ─────────────────────────
      {
        final gateG = Completer<void>();
        final env = await _makeManagerEnv(scripts: {
          '/g.mp3': _ScriptedDownload(hangGate: gateG),
        });
        await env.dao
            .upsert(_rec('/g.mp3', DownloadStatus.pending, updatedAt: _tsOld));
        await env.dao
            .upsert(_rec('/f.mp3', DownloadStatus.failed, updatedAt: _ts));
        final returned =
            await env.manager.enqueueMany([(1, testAudio('f.mp3', '/f.mp3'))]);
        expect(returned, 1, reason: '格10：failed+enqueue 允许重入队');
        expect((await env.dao.findByLocation(1, '/f.mp3'))!.status,
            DownloadStatus.pending,
            reason: '格10：重入队后回 pending');
        gateG.complete();
      }

      // ── 格11 done + enqueue(同path) = skip（提示已在） ────────────────────
      {
        final gateG = Completer<void>();
        final env = await _makeManagerEnv(scripts: {
          '/g.mp3': _ScriptedDownload(hangGate: gateG),
        });
        await env.dao
            .upsert(_rec('/g.mp3', DownloadStatus.pending, updatedAt: _tsOld));
        await env.dao
            .upsert(_rec('/f.mp3', DownloadStatus.done, updatedAt: _ts));
        final returned =
            await env.manager.enqueueMany([(1, testAudio('f.mp3', '/f.mp3'))]);
        expect(returned, 0, reason: '格11：done+enqueue → skip');
        expect((await env.dao.findByLocation(1, '/f.mp3'))!.status,
            DownloadStatus.done,
            reason: '格11：done 保持不动');
        gateG.complete();
      }
    });
  });

  // ───────────────────────────────────────────────────────────────────────
  // DL-01-ALG2 resolveCollision 冲突命名
  // ───────────────────────────────────────────────────────────────────────
  group('DL-01-ALG2 resolveCollision', () {
    test('DL-01-ALG2 黄金样例: song.mp3 冲突两次 → song_3.mp3，existsProbe 调用序逐个锁定', () {
      final calls = <String>[];
      bool probe(String candidateName) {
        calls.add(candidateName);
        return candidateName == 'song.mp3' || candidateName == 'song_2.mp3';
      }

      final result = resolveCollision('/docs', 'song.mp3', probe);

      expect(result, 'song_3.mp3', reason: 'spec §6 ALG2 黄金样例产物');
      expect(calls, ['song.mp3', 'song_2.mp3', 'song_3.mp3'],
          reason: 'existsProbe 收到裸候选文件名，调用序 [原名, _2, _3]');
    });

    test('DL-01-ALG2 变体: a.b.c.mp3 → a.b.c_2.mp3（后缀插在扩展名前）+ _9 耗尽后进位探测 _10',
        () {
      final multiDot =
          resolveCollision('/d', 'a.b.c.mp3', (n) => n == 'a.b.c.mp3');
      expect(multiDot, 'a.b.c_2.mp3', reason: '后缀必须插在「最后一个 .」起的扩展名之前');

      final calls = <String>[];
      final taken = <String>{
        'n.mp3',
        'n_2.mp3',
        'n_3.mp3',
        'n_4.mp3',
        'n_5.mp3',
        'n_6.mp3',
        'n_7.mp3',
        'n_8.mp3',
        'n_9.mp3',
      };
      final carried = resolveCollision('/d', 'n.mp3', (n) {
        calls.add(n);
        return taken.contains(n);
      });
      expect(carried, 'n_10.mp3');
      expect(calls.last, 'n_10.mp3', reason: '_2.._999 依序尝试，_9 后自然进位 _10');
    });

    test(
        'DL-01-ALG2 无冲突: 原样返回 baseName 且探针恰好调用一次；999 全冲突 → StateError 且探针恰好 999 次',
        () {
      var freeCalls = 0;
      final free = resolveCollision('/d', 'free.mp3', (_) {
        freeCalls++;
        return false;
      });
      expect(free, 'free.mp3', reason: '无冲突返回 baseName 本身');
      expect(freeCalls, 1);

      var exhaustedCalls = 0;
      expect(
        () => resolveCollision('/d', 'f.mp3', (_) {
          exhaustedCalls++;
          return true;
        }),
        throwsA(isA<StateError>()),
        reason: '防御分支：_2.._999 全部冲突时抛 StateError',
      );
      expect(exhaustedCalls, 999, reason: '探测次数恰为 原名1 + 后缀998 = 999');
    });

    test('DL-01-ALG2 否定面: 返回值永不含路径分隔符——目录穿越输入经 sanitize 后同样安全', () {
      const hostileBases = ['../x.mp3', r'a\b.mp3', 'sub/dir.mp3'];
      for (final base in hostileBases) {
        final safeBase = sanitizeBaseName(base);
        final resolved = resolveCollision('/any/dir', safeBase, (_) => false);
        expect(resolved.contains('/'), isFalse,
            reason: '"$base" 的解析产物 "$resolved" 不含正斜杠');
        expect(resolved.contains('\\'), isFalse,
            reason: '"$base" 的解析产物 "$resolved" 不含反斜杠');
      }

      final conflicted =
          resolveCollision('/any/dir', 's.mp3', (n) => !n.contains('_10'));
      expect(conflicted, 's_10.mp3');
      expect(conflicted.contains('/'), isFalse, reason: '冲突重命名产物同样不含分隔符');
      // finalDir 参数仅为签名完整性保留：返回值是裸文件名，不拼接目录
      expect(conflicted.startsWith('/any/dir'), isFalse,
          reason: '返回值必须是裸文件名，由调用方自行 join finalDir');
    });
  });
}
