// test/features/playlist/ref_26_test.dart
// REF-26: PlaylistService — domain service tests
//
// Unit tests for the PlaylistService class extracted from playlist_provider.dart.
// Uses sqflite_ffi in-memory database for isolation.
//
// REF-26-T01: 创建播放单
// REF-26-T02: 添加曲目去重
// REF-26-T03: 导出 JSON 格式正确
// REF-26-T04: 导入去重 + 容错

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:nas_audio_player/core/database/dao/playlist_dao.dart';
import 'package:nas_audio_player/features/playlist/domain/playlist_service.dart';
import 'package:nas_audio_player/shared/models/nas_file.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../helpers/test_database.dart';

// ── Helpers ───────────────────────────────────────────────────────────────────

NasFile _testNasFile({
  required String name,
  required String path,
}) {
  return NasFile(
    name: name,
    path: path,
    isDirectory: false,
    audioType: NasFile.isAudioFile(name) ? NasFile.classifyType(name) : null,
  );
}

// ═════════════════════════════════════════════════════════════════════════════
// REF-26: PlaylistService tests
// ═════════════════════════════════════════════════════════════════════════════

void main() {
  late Database db;
  late PlaylistDao dao;
  late PlaylistService service;

  setUpAll(() {
    initSqfliteFfi();
  });

  setUp(() async {
    db = await openTestDatabase(TestSchema.playlist);
    dao = PlaylistDao();
    service = PlaylistService(dao: dao);
  });

  tearDown(() async {
    await db.close();
  });

  // ── REF-26-T01: 创建播放单 ─────────────────────────────────────────────

  group('REF-26-T01 createPlaylist', () {
    test('test_REF26_T01_createPlaylist_returnsId', () async {
      final id = await service.createPlaylist('Test Playlist');
      expect(id, greaterThan(0));
    });

    test('test_REF26_T01_createPlaylist_persistsInDatabase', () async {
      final id = await service.createPlaylist('My Playlist');

      final playlists = await service.findAllPlaylists();
      expect(playlists.length, 1);
      expect(playlists.first.id, id);
      expect(playlists.first.name, 'My Playlist');
    });

    test('test_REF26_T01_createMultiplePlaylists_allPersist', () async {
      await service.createPlaylist('First');
      await service.createPlaylist('Second');
      await service.createPlaylist('Third');

      final playlists = await service.findAllPlaylists();
      expect(playlists.length, 3);
      final names = playlists.map((p) => p.name).toSet();
      expect(names, containsAll(['First', 'Second', 'Third']));
    });

    test('test_REF26_T01_deletePlaylist_removesFromDatabase', () async {
      final id = await service.createPlaylist('To Delete');
      await service.deletePlaylist(id);

      final playlists = await service.findAllPlaylists();
      expect(playlists, isEmpty);
    });

    test('test_REF26_T01_updatePlaylist_renamesPlaylist', () async {
      await service.createPlaylist('Old Name');
      final playlist = (await service.findAllPlaylists()).first;

      await service.updatePlaylist(playlist.copyWith(name: 'New Name'));

      final updated = (await service.findAllPlaylists()).first;
      expect(updated.name, 'New Name');
    });
  });

  // ── REF-26-T02: 添加曲目去重 ───────────────────────────────────────────

  group('REF-26-T02 addTracksToPlaylist dedup', () {
    test('test_REF26_T02_addTracks_noDuplicates_allInserted', () async {
      final id = await service.createPlaylist('No Dups');
      final files = [
        _testNasFile(name: 'a.mp3', path: '/music/a.mp3'),
        _testNasFile(name: 'b.mp3', path: '/music/b.mp3'),
        _testNasFile(name: 'c.flac', path: '/music/c.flac'),
      ];

      await service.addTracksToPlaylist(id, files);

      final tracks = await service.findTracksForPlaylist(id);
      expect(tracks.length, 3);
    });

    test('test_REF26_T02_addTracks_withDuplicates_skipsExisting', () async {
      final id = await service.createPlaylist('With Dups');

      // First batch
      await service.addTracksToPlaylist(id, [
        _testNasFile(name: 'a.mp3', path: '/music/a.mp3'),
        _testNasFile(name: 'b.mp3', path: '/music/b.mp3'),
      ]);

      // Second batch with overlapping file
      await service.addTracksToPlaylist(id, [
        _testNasFile(name: 'b.mp3', path: '/music/b.mp3'),
        _testNasFile(name: 'c.mp3', path: '/music/c.mp3'),
      ]);

      final tracks = await service.findTracksForPlaylist(id);
      expect(tracks.length, 3);
      final paths = tracks.map((t) => t.filePath).toSet();
      expect(
          paths, containsAll(['/music/a.mp3', '/music/b.mp3', '/music/c.mp3']));
    });

    test('test_REF26_T02_addTracks_allDuplicates_noNewTracks', () async {
      final id = await service.createPlaylist('All Dups');

      await service.addTracksToPlaylist(id, [
        _testNasFile(name: 'a.mp3', path: '/music/a.mp3'),
      ]);

      // Try to add the same file again
      await service.addTracksToPlaylist(id, [
        _testNasFile(name: 'a.mp3', path: '/music/a.mp3'),
      ]);

      final tracks = await service.findTracksForPlaylist(id);
      expect(tracks.length, 1);
    });

    test('test_REF26_T02_addTracks_emptyFileList_noTracksAdded', () async {
      final id = await service.createPlaylist('Empty Add');

      await service.addTracksToPlaylist(id, []);

      final tracks = await service.findTracksForPlaylist(id);
      expect(tracks, isEmpty);
    });

    test('test_REF26_T02_removeTracks_removesSpecifiedTracks', () async {
      final id = await service.createPlaylist('Remove Test');
      await service.addTracksToPlaylist(id, [
        _testNasFile(name: 'a.mp3', path: '/music/a.mp3'),
        _testNasFile(name: 'b.mp3', path: '/music/b.mp3'),
        _testNasFile(name: 'c.mp3', path: '/music/c.mp3'),
      ]);

      final tracks = await service.findTracksForPlaylist(id);
      await service.removeTracks([tracks[0].id!, tracks[1].id!]);

      final remaining = await service.findTracksForPlaylist(id);
      expect(remaining.length, 1);
      expect(remaining.first.fileName, 'c.mp3');
    });
  });

  // ── REF-26-T03: 导出 JSON 格式正确 ────────────────────────────────────

  group('REF-26-T03 exportPlaylist', () {
    test('test_REF26_T03_export_withTracks_jsonFormatCorrect', () async {
      final id = await service.createPlaylist('Export Test');
      await service.addTracksToPlaylist(id, [
        _testNasFile(name: '01.mp3', path: '/music/01.mp3'),
        _testNasFile(name: '02.flac', path: '/music/02.flac'),
        _testNasFile(name: '03.m4b', path: '/books/03.m4b'),
      ]);

      final jsonStr = await service.exportPlaylist(id);
      final data = jsonDecode(jsonStr) as Map<String, dynamic>;

      expect(data['name'], 'Export Test');
      expect(data['tracks'], isA<List>());

      final tracks = data['tracks'] as List;
      expect(tracks.length, 3);

      expect(tracks[0]['filePath'], '/music/01.mp3');
      expect(tracks[0]['fileName'], '01.mp3');
      expect(tracks[1]['filePath'], '/music/02.flac');
      expect(tracks[1]['fileName'], '02.flac');
      expect(tracks[2]['filePath'], '/books/03.m4b');
      expect(tracks[2]['fileName'], '03.m4b');
    });

    test('test_REF26_T03_export_emptyPlaylist_tracksIsEmptyArray', () async {
      final id = await service.createPlaylist('Empty Export');

      final jsonStr = await service.exportPlaylist(id);
      final data = jsonDecode(jsonStr) as Map<String, dynamic>;

      expect(data['name'], 'Empty Export');
      expect(data['tracks'], isEmpty);
    });

    test('test_REF26_T03_export_nonExistentPlaylist_throws', () async {
      expect(
        () => service.exportPlaylist(9999),
        throwsA(isA<Exception>()),
      );
    });

    test('test_REF26_T03_export_jsonIsPrettyPrinted', () async {
      final id = await service.createPlaylist('Pretty');
      await service.addTracksToPlaylist(id, [
        _testNasFile(name: 'a.mp3', path: '/a.mp3'),
      ]);

      final jsonStr = await service.exportPlaylist(id);

      // Pretty-printed JSON should contain newlines and indentation
      expect(jsonStr, contains('\n'));
      expect(jsonStr, contains('  '));
    });
  });

  // ── REF-26-T04: 导入去重 + 容错 ───────────────────────────────────────

  group('REF-26-T04 importPlaylist', () {
    test('test_REF26_T04_import_validJson_createsPlaylistAndTracks', () async {
      const jsonStr = '{"name":"Imported","tracks":['
          '{"filePath":"/a.mp3","fileName":"a.mp3"},'
          '{"filePath":"/b.mp3","fileName":"b.mp3"},'
          '{"filePath":"/c.flac","fileName":"c.flac"}'
          ']}';

      final newId = await service.importPlaylist(jsonStr);
      expect(newId, greaterThan(0));

      final playlists = await service.findAllPlaylists();
      final imported = playlists.firstWhere((p) => p.id == newId);
      expect(imported.name, 'Imported');

      final tracks = await service.findTracksForPlaylist(newId);
      expect(tracks.length, 3);
      expect(tracks[0].filePath, '/a.mp3');
      expect(tracks[0].fileName, 'a.mp3');
      expect(tracks[1].filePath, '/b.mp3');
      expect(tracks[1].fileName, 'b.mp3');
      expect(tracks[2].filePath, '/c.flac');
      expect(tracks[2].fileName, 'c.flac');
    });

    test('test_REF26_T04_import_duplicateFilePaths_skipsDuplicates', () async {
      const jsonStr = '{"name":"Dedup Import","tracks":['
          '{"filePath":"/dup.mp3","fileName":"dup.mp3"},'
          '{"filePath":"/dup.mp3","fileName":"dup.mp3"},'
          '{"filePath":"/unique.mp3","fileName":"unique.mp3"}'
          ']}';

      final newId = await service.importPlaylist(jsonStr);

      final tracks = await service.findTracksForPlaylist(newId);
      expect(tracks.length, 2);
      final paths = tracks.map((t) => t.filePath).toSet();
      expect(paths, containsAll(['/dup.mp3', '/unique.mp3']));
    });

    test('test_REF26_T04_import_missingName_defaultsToImported', () async {
      const jsonStr = '{"tracks":[{"filePath":"/a.mp3","fileName":"a.mp3"}]}';

      final newId = await service.importPlaylist(jsonStr);

      final playlists = await service.findAllPlaylists();
      final imported = playlists.firstWhere((p) => p.id == newId);
      expect(imported.name, '导入的播放单');
    });

    test('test_REF26_T04_import_missingTracks_emptyPlaylist', () async {
      const jsonStr = '{"name":"No Tracks"}';

      final newId = await service.importPlaylist(jsonStr);

      final playlists = await service.findAllPlaylists();
      expect(playlists.first.name, 'No Tracks');

      final tracks = await service.findTracksForPlaylist(newId);
      expect(tracks, isEmpty);
    });

    test('test_REF26_T04_import_emptyFilePath_skipsTrack', () async {
      const jsonStr = '{"name":"Empty Path","tracks":['
          '{"filePath":"","fileName":"empty.mp3"},'
          '{"filePath":"/valid.mp3","fileName":"valid.mp3"}'
          ']}';

      final newId = await service.importPlaylist(jsonStr);

      final tracks = await service.findTracksForPlaylist(newId);
      expect(tracks.length, 1);
      expect(tracks.first.filePath, '/valid.mp3');
    });

    test('test_REF26_T04_import_malformedJson_throwsFormatException', () async {
      expect(
        () => service.importPlaylist('{not valid json}'),
        throwsA(isA<FormatException>()),
      );
    });

    test('test_REF26_T04_import_malformedJson_noPlaylistCreated', () async {
      try {
        await service.importPlaylist('{not valid json}');
      } catch (_) {
        // expected
      }

      final playlists = await service.findAllPlaylists();
      expect(playlists, isEmpty);
    });

    test('test_REF26_T04_import_emptyJson_noCrash', () async {
      const jsonStr = '{}';

      final newId = await service.importPlaylist(jsonStr);

      final playlists = await service.findAllPlaylists();
      expect(playlists.first.name, '导入的播放单');

      final tracks = await service.findTracksForPlaylist(newId);
      expect(tracks, isEmpty);
    });

    test('test_REF26_T04_import_exportRoundTrip_dataMatches', () async {
      // Create a playlist with tracks
      final originalId = await service.createPlaylist('Round Trip');
      await service.addTracksToPlaylist(originalId, [
        _testNasFile(name: 'a.mp3', path: '/music/a.mp3'),
        _testNasFile(name: 'b.flac', path: '/music/b.flac'),
        _testNasFile(name: 'c.m4b', path: '/books/c.m4b'),
      ]);

      // Export
      final jsonStr = await service.exportPlaylist(originalId);

      // Import
      final importedId = await service.importPlaylist(jsonStr);

      // Verify name matches
      final playlists = await service.findAllPlaylists();
      final imported = playlists.firstWhere((p) => p.id == importedId);
      expect(imported.name, 'Round Trip');

      // Verify tracks match
      final originalTracks = await service.findTracksForPlaylist(originalId);
      final importedTracks = await service.findTracksForPlaylist(importedId);

      expect(importedTracks.length, originalTracks.length);
      for (int i = 0; i < originalTracks.length; i++) {
        expect(importedTracks[i].filePath, originalTracks[i].filePath);
        expect(importedTracks[i].fileName, originalTracks[i].fileName);
      }
    });
  });
}
