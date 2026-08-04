// test/features/browser/net1_legacy_queue_restore_test.dart
// cr-20260804-1922 §5 O1: NET1 遗留持久化队列绝对路径 — 读取时归一化
//
// NET1（431d444）之前持久化的播放队列 filePaths 是服务端绝对路径
//（含连接根前缀，如 `/dav/music/a.mp3`）；NET1 之后播放 URL 按
//「有效 base URL（连接根）+ 相对路径」拼接。旧队列恢复后若路径未归一，
// buildWithBasePath 会把连接根拼两次（/dav/dav/music/a.mp3）→ 404。
//
// 本文件验证：
//   S1 恢复链路按队列存储的 connectionId 查连接根，剥离 legacy 前缀
//   S2 归一后经 buildUriWithBasePath 构造的 URL 无双重前缀（核心 RED 用例）
//   S3 下次队列保存写回归一值（自然写回点）
//   否定断言：basePath 为空（服务端根挂载）时路径不被改动；
//             无连接上下文时路径原样保留（不抛错）

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nas_audio_player/core/services/audio_source_builder.dart';
import 'package:nas_audio_player/features/browser/browser_provider.dart';
import 'package:nas_audio_player/features/connection/connection_provider.dart';
import 'package:nas_audio_player/shared/models/connection_config.dart';
import 'package:nas_audio_player/shared/webdav_paths.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../helpers/test_database.dart';

const _qKey = 'last_play_queue';
const _qConnKey = 'last_play_queue_connection_id';

const _url = 'http://nas.local:5005';
const _basePath = '/dav';

/// 队列归属连接（id=1）：挂载点 /dav（子路径挂载）。
Future<Database> seedSubPathConnection() async {
  final db = await openTestDatabase(TestSchema.connections);
  await db.insert('connections', {
    'id': 1,
    'name': 'SubPath NAS',
    'url': _url,
    'username': 'admin',
    'password': 'pw-ref-key',
    'base_path': _basePath,
    'is_active': 1,
    'created_at': 0,
    'updated_at': 0,
  });
  return db;
}

/// Boots [restoreQueueFromPrefsProvider] against [prefs].
/// activeConnectionProvider stubbed to null → preload 分支跳过，
/// 归一化必须来自队列存储的 connectionId → DB 连接查询。
Future<ProviderContainer> restoreContainer(SharedPreferences prefs) async {
  final container = ProviderContainer(overrides: [
    sharedPreferencesProvider.overrideWithValue(prefs),
    activeConnectionProvider
        .overrideWith((ref) async => null as ConnectionConfig?),
  ]);
  addTearDown(container.dispose);
  await container.read(restoreQueueFromPrefsProvider.future);
  return container;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(initSqfliteFfi);

  group('O1-S1: legacy 队列恢复时按存储连接剥离 basePath 前缀', () {
    test('legacy 绝对路径恢复后归一为相对连接根形态', () async {
      final db = await seedSubPathConnection();
      addTearDown(db.close);

      SharedPreferences.setMockInitialValues({
        _qKey: jsonEncode({
          'filePaths': [
            '/dav/music/track_01.mp3',
            '/dav/music/track_02.mp3',
          ],
          'currentIndex': 0,
          'startPositionMs': 12345,
          'playMode': 'sequential',
        }),
        _qConnKey: 1,
      });
      final prefs = await SharedPreferences.getInstance();

      final container = await restoreContainer(prefs);
      final queue = container.read(currentPlayQueueProvider);

      expect(queue, isNotNull, reason: '队列必须被恢复');
      expect(queue!.files.map((f) => f.path).toList(),
          equals(['/music/track_01.mp3', '/music/track_02.mp3']),
          reason: 'S1: legacy 前缀 /dav 必须被剥离');
      expect(queue.startPositionMs, equals(12345),
          reason: '恢复不得破坏 startPosition');
    });
  });

  group('O1-S2: 归一后播放 URL 无双重前缀（核心 RED 用例）', () {
    test('buildUriWithBasePath 构造的 URL 恰好包含连接根一次', () async {
      final db = await seedSubPathConnection();
      addTearDown(db.close);

      SharedPreferences.setMockInitialValues({
        _qKey: jsonEncode({
          'filePaths': ['/dav/music/track_01.mp3'],
          'currentIndex': 0,
          'playMode': 'sequential',
        }),
        _qConnKey: 1,
      });
      final prefs = await SharedPreferences.getInstance();

      final container = await restoreContainer(prefs);
      final queue = container.read(currentPlayQueueProvider);
      expect(queue, isNotNull);

      // 与 PlaybackOrchestrator.loadAndPlay 相同的拼接方式
      final uri = AudioSourceBuilder.buildUriWithBasePath(
        baseUrl: webDavEffectiveBaseUrl(_url, _basePath),
        filePath: queue!.current.path,
      );

      // 未修复时：/dav/dav/music/track_01.mp3（双重前缀 → 404）
      expect(uri.path, equals('/dav/music/track_01.mp3'),
          reason: '否定断言: 连接根不得被拼两次');
      expect(uri.path.contains('/dav/dav/'), isFalse);
    });
  });

  group('O1-S3: 下次队列保存写回归一值（自然写回点）', () {
    test('恢复后队列再持久化 → prefs 中为相对连接根路径', () async {
      final db = await seedSubPathConnection();
      addTearDown(db.close);

      SharedPreferences.setMockInitialValues({
        _qKey: jsonEncode({
          'filePaths': ['/dav/music/track_01.mp3'],
          'currentIndex': 0,
          'playMode': 'sequential',
        }),
        _qConnKey: 1,
      });
      final prefs = await SharedPreferences.getInstance();

      final container = await restoreContainer(prefs);
      // 激活写监听（与 browser_screen 的 ref.watch 等价）
      container.read(persistQueueOnChangeProvider);
      // 触发一次真实状态变更（模拟队列任意变更后的监听回写）
      final queue = container.read(currentPlayQueueProvider)!;
      container.read(currentPlayQueueProvider.notifier).state =
          queue.withStartPosition(999);

      final raw = prefs.getString(_qKey);
      expect(raw, isNotNull);
      final written = jsonDecode(raw!) as Map<String, dynamic>;
      expect(written['startPositionMs'], equals(999), reason: '前置: 监听回写确实发生');
      expect(written['filePaths'], equals(['/music/track_01.mp3']),
          reason: '写回: 下次保存天然写归一值');
    });
  });

  group('O1 否定断言', () {
    test('连接根为 `/`（无子路径挂载）→ legacy 即相对根路径，不被改动', () async {
      final db = await openTestDatabase(TestSchema.connections);
      addTearDown(db.close);
      await db.insert('connections', {
        'id': 1,
        'name': 'Root NAS',
        'url': _url,
        'username': 'admin',
        'password': 'pw-ref-key',
        'base_path': '/',
        'is_active': 1,
        'created_at': 0,
        'updated_at': 0,
      });

      SharedPreferences.setMockInitialValues({
        _qKey: jsonEncode({
          'filePaths': ['/music/track_01.mp3'],
          'currentIndex': 0,
          'playMode': 'sequential',
        }),
        _qConnKey: 1,
      });
      final prefs = await SharedPreferences.getInstance();

      final container = await restoreContainer(prefs);
      final queue = container.read(currentPlayQueueProvider);

      expect(queue, isNotNull);
      expect(queue!.current.path, equals('/music/track_01.mp3'),
          reason: '否定断言: 根挂载时路径不得被改动');
    });

    test('存储的 connectionId 查无连接 → 原样返回不抛错', () async {
      final db = await openTestDatabase(TestSchema.connections);
      addTearDown(db.close);
      // 不插任何连接行

      SharedPreferences.setMockInitialValues({
        _qKey: jsonEncode({
          'filePaths': ['/dav/music/track_01.mp3'],
          'currentIndex': 0,
          'playMode': 'sequential',
        }),
        _qConnKey: 999,
      });
      final prefs = await SharedPreferences.getInstance();

      final container = await restoreContainer(prefs);
      final queue = container.read(currentPlayQueueProvider);

      expect(queue, isNotNull, reason: '队列仍被恢复（不 crash）');
      expect(queue!.current.path, equals('/dav/music/track_01.mp3'),
          reason: '否定断言: 拿不到连接上下文时原样返回');
    });

    test('不匹配连接根前缀的路径不被改动', () async {
      final db = await seedSubPathConnection();
      addTearDown(db.close);

      SharedPreferences.setMockInitialValues({
        _qKey: jsonEncode({
          'filePaths': ['/other/track_01.mp3'],
          'currentIndex': 0,
          'playMode': 'sequential',
        }),
        _qConnKey: 1,
      });
      final prefs = await SharedPreferences.getInstance();

      final container = await restoreContainer(prefs);
      final queue = container.read(currentPlayQueueProvider);

      expect(queue, isNotNull);
      expect(queue!.current.path, equals('/other/track_01.mp3'),
          reason: '否定断言: 不匹配前缀不得被改动');
    });
  });
}
