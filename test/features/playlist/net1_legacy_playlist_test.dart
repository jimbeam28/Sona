// test/features/playlist/net1_legacy_playlist_test.dart
// cr-20260804-1922 §5 O1: NET1 遗留 playlist_tracks 绝对路径 — 读取时归一化
//
// NET1（431d444）之前添加的播放单曲目 file_path 是服务端绝对路径
//（含连接根前缀）。播放单无连接归属列（playlists 表无 connection_id），
// 归一化上下文取当前激活连接（is_active=1）；拿不到连接时原样返回。
// playlist_tracks 无自然重写点 → 只做读取时归一，不新增强制回写。
//
// 本文件验证：
//   S1 findTracksForPlaylist 返回归一 filePath（构建播放队列链路）
//   S2 归一后经 buildUriWithBasePath 构造的 URL 无双重前缀
//   S3 trackExists 双形态匹配 → 批添加去重不因 legacy 行失效
//   S4 导出链路同样归一（findTracksForPlaylist 单点收口）
//   否定断言：无激活连接（connections 表缺失）→ 原样返回不抛错；
//             根为 `/` 时不被改动；不匹配前缀不被改动

import 'package:flutter_test/flutter_test.dart';
import 'package:nas_audio_player/core/database/dao/playlist_dao.dart';
import 'package:nas_audio_player/core/services/audio_source_builder.dart';
import 'package:nas_audio_player/features/playlist/domain/playlist_service.dart';
import 'package:nas_audio_player/shared/models/nas_file.dart';
import 'package:nas_audio_player/shared/models/play_queue.dart';
import 'package:nas_audio_player/shared/webdav_paths.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../helpers/test_database.dart';

const _url = 'http://nas.local:5005';
const _basePath = '/dav';
const _legacyPath = '/dav/music/a.mp3'; // NET1 前存储形态（服务端绝对）
const _canonicalPath = '/music/a.mp3'; // NET1 后规范形态（相对连接根）

Future<Database> openWithActiveSubPathConnection() async {
  final db = await openTestDatabase(TestSchema.full);
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

Future<int> seedPlaylistWithLegacyTrack(Database db) async {
  final playlistId = await db.insert('playlists', {
    'name': '旧播放单',
    'created_at': 0,
    'updated_at': 0,
  });
  await db.insert('playlist_tracks', {
    'playlist_id': playlistId,
    'file_path': _legacyPath,
    'file_name': 'a.mp3',
    'added_at': 1,
  });
  return playlistId;
}

void main() {
  setUpAll(initSqfliteFfi);

  group('O1-S1: findTracksForPlaylist 读取时归一', () {
    test('legacy 曲目返回归一 filePath', () async {
      final db = await openWithActiveSubPathConnection();
      addTearDown(db.close);
      final playlistId = await seedPlaylistWithLegacyTrack(db);
      final dao = PlaylistDao();

      final tracks = await dao.findTracksForPlaylist(playlistId);

      expect(tracks, hasLength(1));
      expect(tracks.first.filePath, equals(_canonicalPath),
          reason: 'S1: legacy 前缀 /dav 必须被剥离');
      expect(tracks.first.fileName, equals('a.mp3'), reason: '归一不得破坏其他字段');
    });
  });

  group('O1-S2: 归一后构建播放队列 URL 无双重前缀', () {
    test('toNasFile → PlayQueue → buildUriWithBasePath 连接根恰好一次', () async {
      final db = await openWithActiveSubPathConnection();
      addTearDown(db.close);
      final playlistId = await seedPlaylistWithLegacyTrack(db);
      final dao = PlaylistDao();

      final tracks = await dao.findTracksForPlaylist(playlistId);
      // 与 playlist_detail_screen._playTrackAtIndex 相同的构建链路
      final nasFiles = tracks.map((t) => t.toNasFile()).toList();
      final queue = PlayQueue(files: nasFiles, currentIndex: 0);

      final uri = AudioSourceBuilder.buildUriWithBasePath(
        baseUrl: webDavEffectiveBaseUrl(_url, _basePath),
        filePath: queue.current.path,
      );

      expect(uri.path, equals('/dav/music/a.mp3'),
          reason: '否定断言: 连接根不得被拼两次（未修复时 /dav/dav/...）');
      expect(uri.path.contains('/dav/dav/'), isFalse);
    });
  });

  group('O1-S3: trackExists 双形态匹配（去重不因 legacy 行失效）', () {
    test('legacy 行存在时按 canonical 路径判定已存在', () async {
      final db = await openWithActiveSubPathConnection();
      addTearDown(db.close);
      final playlistId = await seedPlaylistWithLegacyTrack(db);
      final service = PlaylistService(dao: PlaylistDao());

      // 批添加同一文件（浏览链路给的是 canonical 路径）→ 不得产生重复
      await service.addTracksToPlaylist(playlistId, [
        NasFile(name: 'a.mp3', path: _canonicalPath, isDirectory: false),
      ]);

      final tracks = await service.findTracksForPlaylist(playlistId);
      expect(tracks, hasLength(1), reason: 'S3: legacy 行必须被去重命中，不得出现重复曲目');
    });
  });

  group('O1-S4: 导出链路同归一（findTracksForPlaylist 单点收口）', () {
    test('exportPlaylist 输出 canonical 路径', () async {
      final db = await openWithActiveSubPathConnection();
      addTearDown(db.close);
      final playlistId = await seedPlaylistWithLegacyTrack(db);
      final service = PlaylistService(dao: PlaylistDao());

      final json = await service.exportPlaylist(playlistId);

      expect(json.contains('"filePath": "$_canonicalPath"'), isTrue,
          reason: 'S4: 导出必须归一（与读取同口）');
      expect(json.contains('/dav/dav'), isFalse);
      expect(json.contains('"filePath": "$_legacyPath"'), isFalse);
    });
  });

  group('O1 否定断言', () {
    test('无 connections 表（playlist-only schema）→ 原样返回不抛错', () async {
      final db = await openTestDatabase(TestSchema.playlist);
      addTearDown(db.close);
      final playlistId = await db.insert('playlists', {
        'name': '孤立播放单',
        'created_at': 0,
        'updated_at': 0,
      });
      await db.insert('playlist_tracks', {
        'playlist_id': playlistId,
        'file_path': _legacyPath,
        'file_name': 'a.mp3',
        'added_at': 1,
      });
      final dao = PlaylistDao();

      final tracks = await dao.findTracksForPlaylist(playlistId);

      expect(tracks, hasLength(1));
      expect(tracks.first.filePath, equals(_legacyPath),
          reason: '否定断言: 拿不到连接上下文时原样返回（不 crash）');
    });

    test('激活连接根为 `/` → 路径不被改动', () async {
      final db = await openTestDatabase(TestSchema.full);
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
      final playlistId = await db.insert('playlists', {
        'name': '根挂载播放单',
        'created_at': 0,
        'updated_at': 0,
      });
      await db.insert('playlist_tracks', {
        'playlist_id': playlistId,
        'file_path': '/music/a.mp3',
        'file_name': 'a.mp3',
        'added_at': 1,
      });
      final dao = PlaylistDao();

      final tracks = await dao.findTracksForPlaylist(playlistId);

      expect(tracks.first.filePath, equals('/music/a.mp3'),
          reason: '否定断言: 根挂载时路径不被改动');
    });

    test('无激活连接行（表存在但无 is_active=1）→ 原样返回', () async {
      final db = await openTestDatabase(TestSchema.full);
      addTearDown(db.close);
      await db.insert('connections', {
        'id': 1,
        'name': 'Inactive NAS',
        'url': _url,
        'username': 'admin',
        'password': 'pw-ref-key',
        'base_path': _basePath,
        'is_active': 0,
        'created_at': 0,
        'updated_at': 0,
      });
      final playlistId = await seedPlaylistWithLegacyTrack(db);
      final dao = PlaylistDao();

      final tracks = await dao.findTracksForPlaylist(playlistId);

      expect(tracks.first.filePath, equals(_legacyPath),
          reason: '否定断言: 无激活连接时原样返回');
    });

    test('不匹配激活连接根前缀的路径不被改动', () async {
      final db = await openWithActiveSubPathConnection();
      addTearDown(db.close);
      final playlistId = await db.insert('playlists', {
        'name': '其他路径播放单',
        'created_at': 0,
        'updated_at': 0,
      });
      await db.insert('playlist_tracks', {
        'playlist_id': playlistId,
        'file_path': '/other/b.mp3',
        'file_name': 'b.mp3',
        'added_at': 1,
      });
      final dao = PlaylistDao();

      final tracks = await dao.findTracksForPlaylist(playlistId);

      expect(tracks.first.filePath, equals('/other/b.mp3'),
          reason: '否定断言: 不匹配前缀不得被改动');
    });
  });
}
