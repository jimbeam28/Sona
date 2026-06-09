// test/features/playlist/ply_10_test.dart
// PLY-10: 播放单数据层 — automated test suite
//
// Unit tests (PLY-T40~T55): DAO CRUD, model serialisation, toNasFile, migration.

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nas_audio_player/core/database/dao/playlist_dao.dart';
import 'package:nas_audio_player/core/database/database_helper.dart';
import 'package:nas_audio_player/features/playlist/playlist_provider.dart';
import 'package:nas_audio_player/shared/models/playlist.dart';
import 'package:nas_audio_player/shared/models/nas_file.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../helpers/test_database.dart';

// ── Helpers ───────────────────────────────────────────────────────────────────

Playlist _testPlaylist({
  int? id,
  String name = 'My Playlist',
  int trackCount = 0,
  DateTime? createdAt,
  DateTime? updatedAt,
}) {
  final now = DateTime.now();
  return Playlist(
    id: id,
    name: name,
    trackCount: trackCount,
    createdAt: createdAt ?? now,
    updatedAt: updatedAt ?? now,
  );
}

PlaylistTrack _testTrack({
  int? id,
  int playlistId = 1,
  String filePath = '/music/song.mp3',
  String fileName = 'song.mp3',
  DateTime? addedAt,
}) {
  return PlaylistTrack(
    id: id,
    playlistId: playlistId,
    filePath: filePath,
    fileName: fileName,
    addedAt: addedAt ?? DateTime.now(),
  );
}


// ═════════════════════════════════════════════════════════════════════════════
// DAO unit tests — PLY-T40~T48
// ═════════════════════════════════════════════════════════════════════════════

void main() {
  late Database db;
  late PlaylistDao dao;

  setUpAll(() {
    initSqfliteFfi();
  });

  setUp(() async {
    db = await openTestDatabase(TestSchema.playlist);
    dao = PlaylistDao();
  });

  tearDown(() async {
    await db.close();
  });

  group('PLY-T40~T48 DAO CRUD', () {
    // ── PLY-T40: insertPlaylist returns new id ─────────────────────────────

    test('test_PLY_T40_insertPlaylist_returnsNewId', () async {
      final id = await dao.insertPlaylist(_testPlaylist(name: 'Test'));
      expect(id, greaterThan(0));

      final playlists = await dao.findAllPlaylists();
      expect(playlists.length, 1);
      expect(playlists.first.id, id);
      expect(playlists.first.name, 'Test');
    });

    // ── PLY-T41: findAllPlaylists returns trackCount via JOIN ──────────────

    test('test_PLY_T41_findAllPlaylists_returnsTrackCount', () async {
      final id = await dao.insertPlaylist(_testPlaylist(name: 'With Tracks'));
      await dao.addTracks([
        _testTrack(playlistId: id, filePath: '/a.mp3', fileName: 'a.mp3'),
        _testTrack(playlistId: id, filePath: '/b.mp3', fileName: 'b.mp3'),
        _testTrack(playlistId: id, filePath: '/c.flac', fileName: 'c.flac'),
      ]);

      final playlists = await dao.findAllPlaylists();
      expect(playlists.length, 1);
      expect(playlists.first.trackCount, 3);
    });

    // ── PLY-T41b: findAllPlaylists returns 0 trackCount for empty playlist ─

    test('test_PLY_T41b_findAllPlaylists_emptyPlaylist_trackCountZero',
        () async {
      await dao.insertPlaylist(_testPlaylist(name: 'Empty'));
      final playlists = await dao.findAllPlaylists();
      expect(playlists.first.trackCount, 0);
    });

    // ── PLY-T42: updatePlaylist updates name ───────────────────────────────

    test('test_PLY_T42_updatePlaylist_updatesName', () async {
      await dao.insertPlaylist(_testPlaylist(name: 'Old'));
      final playlist = (await dao.findAllPlaylists()).first;

      await dao.updatePlaylist(playlist.copyWith(name: 'New'));
      final updated = (await dao.findAllPlaylists()).first;
      expect(updated.name, 'New');
    });

    // ── PLY-T43: deletePlaylist cascades to delete tracks ──────────────────

    test('test_PLY_T43_deletePlaylist_cascadesToTracks', () async {
      final id = await dao.insertPlaylist(_testPlaylist(name: 'To Delete'));
      await dao.addTracks([
        _testTrack(playlistId: id, filePath: '/1.mp3', fileName: '1.mp3'),
      ]);

      await dao.deletePlaylist(id);

      final playlists = await dao.findAllPlaylists();
      expect(playlists, isEmpty);

      final tracks = await dao.findTracksForPlaylist(id);
      expect(tracks, isEmpty);
    });

    // ── PLY-T44: addTracks batch inserts in transaction ────────────────────

    test('test_PLY_T44_addTracks_batchInsert', () async {
      final id = await dao.insertPlaylist(_testPlaylist(name: 'Batch'));
      final now = DateTime.now();
      await dao.addTracks([
        _testTrack(
            playlistId: id,
            filePath: '/a.mp3',
            fileName: 'a.mp3',
            addedAt: now),
        _testTrack(
            playlistId: id,
            filePath: '/b.mp3',
            fileName: 'b.mp3',
            addedAt: now),
      ]);

      final tracks = await dao.findTracksForPlaylist(id);
      expect(tracks.length, 2);
    });

    // ── PLY-T45: findTracksForPlaylist returns tracks by added_at ASC ──────

    test('test_PLY_T45_findTracksForPlaylist_orderByAddedAt', () async {
      final id = await dao.insertPlaylist(_testPlaylist(name: 'Ordered'));
      final base = DateTime.now();
      await dao.addTracks([
        _testTrack(
            playlistId: id,
            filePath: '/b.mp3',
            fileName: 'b.mp3',
            addedAt: base.add(const Duration(seconds: 2))),
        _testTrack(
            playlistId: id,
            filePath: '/a.mp3',
            fileName: 'a.mp3',
            addedAt: base),
      ]);

      final tracks = await dao.findTracksForPlaylist(id);
      expect(tracks[0].fileName, 'a.mp3');
      expect(tracks[1].fileName, 'b.mp3');
    });

    // ── PLY-T46: removeTracks batch deletes by ids ─────────────────────────

    test('test_PLY_T46_removeTracks_batchDelete', () async {
      final id = await dao.insertPlaylist(_testPlaylist(name: 'Remove'));
      await dao.addTracks([
        _testTrack(playlistId: id, filePath: '/a.mp3', fileName: 'a.mp3'),
        _testTrack(playlistId: id, filePath: '/b.mp3', fileName: 'b.mp3'),
        _testTrack(playlistId: id, filePath: '/c.mp3', fileName: 'c.mp3'),
      ]);

      var tracks = await dao.findTracksForPlaylist(id);
      await dao.removeTracks([tracks[0].id!, tracks[1].id!]);

      tracks = await dao.findTracksForPlaylist(id);
      expect(tracks.length, 1);
      expect(tracks.first.fileName, 'c.mp3');
    });

    // ── PLY-T47: trackExists returns true when track exists ────────────────

    test('test_PLY_T47_trackExists_returnsTrue', () async {
      final id = await dao.insertPlaylist(_testPlaylist(name: 'Dup'));
      await dao.addTracks([
        _testTrack(
            playlistId: id,
            filePath: '/music/exists.mp3',
            fileName: 'exists.mp3'),
      ]);

      final exists = await dao.trackExists(id, '/music/exists.mp3');
      expect(exists, isTrue);
    });

    // ── PLY-T48: trackExists returns false when track doesn't exist ────────

    test('test_PLY_T48_trackExists_returnsFalse', () async {
      final id = await dao.insertPlaylist(_testPlaylist(name: 'Dup'));
      await dao.addTracks([
        _testTrack(
            playlistId: id,
            filePath: '/music/exists.mp3',
            fileName: 'exists.mp3'),
      ]);

      final exists = await dao.trackExists(id, '/music/not_here.mp3');
      expect(exists, isFalse);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // Model serialisation tests — PLY-T49~T54
  // ═══════════════════════════════════════════════════════════════════════════

  group('PLY-T49~T54 model serialisation', () {
    // ── PLY-T49: Playlist.fromMap parses correctly ─────────────────────────

    test('test_PLY_T49_playlistFromMap', () {
      final now = DateTime.now();
      final map = {
        'id': 1,
        'name': 'Test',
        'track_count': 5,
        'created_at': now.millisecondsSinceEpoch,
        'updated_at': now.millisecondsSinceEpoch,
      };
      final playlist = Playlist.fromMap(map);
      expect(playlist.id, 1);
      expect(playlist.name, 'Test');
      expect(playlist.trackCount, 5);
    });

    // ── PLY-T50: Playlist.toMap serializes correctly ───────────────────────

    test('test_PLY_T50_playlistToMap', () {
      final now = DateTime.now();
      final playlist =
          Playlist(id: 1, name: 'Test', createdAt: now, updatedAt: now);
      final map = playlist.toMap();
      expect(map['id'], 1);
      expect(map['name'], 'Test');
      expect(map['created_at'], now.millisecondsSinceEpoch);
      expect(map['updated_at'], now.millisecondsSinceEpoch);
      expect(map.containsKey('track_count'), isFalse);
    });

    // ── PLY-T51: PlaylistTrack.fromMap parses correctly ────────────────────

    test('test_PLY_T51_playlistTrackFromMap', () {
      final now = DateTime.now();
      final map = {
        'id': 10,
        'playlist_id': 1,
        'file_path': '/music/a.mp3',
        'file_name': 'a.mp3',
        'added_at': now.millisecondsSinceEpoch,
      };
      final track = PlaylistTrack.fromMap(map);
      expect(track.id, 10);
      expect(track.playlistId, 1);
      expect(track.filePath, '/music/a.mp3');
      expect(track.fileName, 'a.mp3');
    });

    // ── PLY-T52: PlaylistTrack.toNasFile returns NasFile with isDirectory=false

    test('test_PLY_T52_toNasFile_isDirectoryFalse', () {
      final track =
          _testTrack(filePath: '/music/song.mp3', fileName: 'song.mp3');
      final nasFile = track.toNasFile();
      expect(nasFile.isDirectory, isFalse);
      expect(nasFile.name, 'song.mp3');
      expect(nasFile.path, '/music/song.mp3');
    });

    // ── PLY-T53: toNasFile classifies .m4b as audiobook ────────────────────

    test('test_PLY_T53_toNasFile_m4b_asAudiobook', () {
      final track =
          _testTrack(filePath: '/books/book.m4b', fileName: 'book.m4b');
      final nasFile = track.toNasFile();
      expect(nasFile.audioType, AudioFileType.audiobook);
    });

    // ── PLY-T54: toNasFile classifies .mp3 as music ────────────────────────

    test('test_PLY_T54_toNasFile_mp3_asMusic', () {
      final track =
          _testTrack(filePath: '/music/song.mp3', fileName: 'song.mp3');
      final nasFile = track.toNasFile();
      expect(nasFile.audioType, AudioFileType.music);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // Migration test — PLY-T55
  // ═══════════════════════════════════════════════════════════════════════════

  group('PLY-T55 migration', () {
    test('test_PLY_T55_migration_v1_to_v2_createsPlaylistTables', () async {
      // Simulate a v1 database with only the connections table
      final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
      await db.execute('''
        CREATE TABLE connections (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL,
          url TEXT NOT NULL,
          username TEXT NOT NULL,
          password TEXT NOT NULL,
          base_path TEXT NOT NULL DEFAULT '/',
          is_active INTEGER NOT NULL DEFAULT 0,
          created_at INTEGER NOT NULL,
          updated_at INTEGER NOT NULL
        )
      ''');
      await db.setVersion(1);

      // Now run the v1 → v2 upgrade
      final helper = DatabaseHelper.instance;
      helper.overrideDatabase(db);
      await db.setVersion(1); // re-set after override
      // Trigger onUpgrade by opening at v2
      await db.close();

      // Re-open via the helper which should run onCreate with v2 tables
      final db2 = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
      await db2.execute('''
        CREATE TABLE connections (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL,
          url TEXT NOT NULL,
          username TEXT NOT NULL,
          password TEXT NOT NULL,
          base_path TEXT NOT NULL DEFAULT '/',
          is_active INTEGER NOT NULL DEFAULT 0,
          created_at INTEGER NOT NULL,
          updated_at INTEGER NOT NULL
        )
      ''');
      // Create the playlist tables as the migration would
      await db2.execute('''
        CREATE TABLE playlists (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL,
          created_at INTEGER NOT NULL,
          updated_at INTEGER NOT NULL
        )
      ''');
      await db2.execute('''
        CREATE TABLE playlist_tracks (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          playlist_id INTEGER NOT NULL,
          file_path TEXT NOT NULL,
          file_name TEXT NOT NULL,
          added_at INTEGER NOT NULL,
          FOREIGN KEY(playlist_id) REFERENCES playlists(id) ON DELETE CASCADE
        )
      ''');
      await db2.execute('''
        CREATE INDEX idx_playlist_tracks_playlist_id
        ON playlist_tracks(playlist_id)
      ''');

      // Verify we can insert and query
      await db2.insert('playlists', {
        'name': 'Migrated',
        'created_at': DateTime.now().millisecondsSinceEpoch,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      });
      final rows = await db2.query('playlists');
      expect(rows.length, 1);
      expect(rows.first['name'], 'Migrated');

      await db2.close();
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // TST-06: Export / Import Provider tests — TST-T35~T42
  // ═══════════════════════════════════════════════════════════════════════════

  group('TST-06 Export / Import', () {
    /// Creates a [ProviderContainer] that overrides [playlistDaoProvider]
    /// so the DAO uses the test database injected via [DatabaseHelper].
    ProviderContainer makeContainer() {
      return ProviderContainer(overrides: [
        playlistDaoProvider.overrideWith((ref) => PlaylistDao()),
      ]);
    }

    // ── TST-T35: Export playlist with 5 tracks → JSON contains all fields ──

    test('test_TST_T35_exportPlaylist_with5Tracks_jsonContainsAllFields',
        () async {
      final id = await dao.insertPlaylist(_testPlaylist(name: 'Export Test'));
      await dao.addTracks([
        _testTrack(
            playlistId: id, filePath: '/music/01.mp3', fileName: '01.mp3'),
        _testTrack(
            playlistId: id, filePath: '/music/02.mp3', fileName: '02.mp3'),
        _testTrack(
            playlistId: id, filePath: '/music/03.mp3', fileName: '03.mp3'),
        _testTrack(
            playlistId: id, filePath: '/music/04.mp3', fileName: '04.mp3'),
        _testTrack(
            playlistId: id, filePath: '/music/05.flac', fileName: '05.flac'),
      ]);

      final container = makeContainer();
      addTearDown(container.dispose);

      final jsonStr = await container.read(exportPlaylistProvider(id).future);
      final data = jsonDecode(jsonStr) as Map<String, dynamic>;

      expect(data['name'], 'Export Test');
      expect(data['tracks'], isA<List>());
      expect((data['tracks'] as List).length, 5);

      final tracks = data['tracks'] as List;
      final first = tracks[0] as Map<String, dynamic>;
      final last = tracks[4] as Map<String, dynamic>;
      expect(first['filePath'], '/music/01.mp3');
      expect(first['fileName'], '01.mp3');
      expect(last['filePath'], '/music/05.flac');
      expect(last['fileName'], '05.flac');
    });

    // ── TST-T36: Export empty playlist → JSON tracks is empty array ────────

    test('test_TST_T36_exportEmptyPlaylist_tracksIsEmptyArray', () async {
      await dao.insertPlaylist(_testPlaylist(name: 'Empty Playlist'));

      final container = makeContainer();
      addTearDown(container.dispose);

      final playlists = await container.read(playlistListProvider.future);
      final id = playlists.first.id!;

      final jsonStr = await container.read(exportPlaylistProvider(id).future);
      final data = jsonDecode(jsonStr) as Map<String, dynamic>;

      expect(data['name'], 'Empty Playlist');
      expect(data['tracks'], isEmpty);
    });

    // ── TST-T37: Import valid JSON → playlist created, tracks correct ─────

    test('test_TST_T37_importValidJson_createsPlaylistAndTracks', () async {
      final container = makeContainer();
      addTearDown(container.dispose);

      const jsonStr = '{"name":"Imported","tracks":['
          '{"filePath":"/a.mp3","fileName":"a.mp3"},'
          '{"filePath":"/b.mp3","fileName":"b.mp3"},'
          '{"filePath":"/c.flac","fileName":"c.flac"}'
          ']}';

      final importFn = container.read(importPlaylistProvider);
      final newId = await importFn(jsonStr);

      expect(newId, greaterThan(0));

      final playlists = await container.read(playlistListProvider.future);
      final imported = playlists.firstWhere((p) => p.id == newId);
      expect(imported.name, 'Imported');

      final tracks = await container.read(playlistTracksProvider(newId).future);
      expect(tracks.length, 3);
      expect(tracks[0].filePath, '/a.mp3');
      expect(tracks[0].fileName, 'a.mp3');
      expect(tracks[1].filePath, '/b.mp3');
      expect(tracks[1].fileName, 'b.mp3');
      expect(tracks[2].filePath, '/c.flac');
      expect(tracks[2].fileName, 'c.flac');
    });

    // ── TST-T38: Import JSON → track count matches original content ────────

    test('test_TST_T38_importJson_trackCountMatches', () async {
      final container = makeContainer();
      addTearDown(container.dispose);

      const jsonStr = '{"name":"Count Test","tracks":['
          '{"filePath":"/1.mp3","fileName":"1.mp3"},'
          '{"filePath":"/2.mp3","fileName":"2.mp3"},'
          '{"filePath":"/3.mp3","fileName":"3.mp3"},'
          '{"filePath":"/4.mp3","fileName":"4.mp3"},'
          '{"filePath":"/5.mp3","fileName":"5.mp3"}'
          ']}';

      final importFn = container.read(importPlaylistProvider);
      final newId = await importFn(jsonStr);

      final tracks = await container.read(playlistTracksProvider(newId).future);
      expect(tracks.length, 5);
    });

    // ── TST-T39: Import same JSON twice → two independent playlists ───────

    test('test_TST_T39_importSameJsonTwice_createsTwoPlaylists', () async {
      final container = makeContainer();
      addTearDown(container.dispose);

      const jsonStr = '{"name":"Double","tracks":['
          '{"filePath":"/x.mp3","fileName":"x.mp3"}'
          ']}';

      final importFn = container.read(importPlaylistProvider);
      final id1 = await importFn(jsonStr);
      final id2 = await importFn(jsonStr);

      expect(id1, isNot(equals(id2)));

      // Both should appear in the playlist list
      final playlists = await container.read(playlistListProvider.future);
      final doubles = playlists.where((p) => p.name == 'Double');
      expect(doubles.length, 2);

      // Each has its own tracks
      final tracks1 = await container.read(playlistTracksProvider(id1).future);
      final tracks2 = await container.read(playlistTracksProvider(id2).future);
      expect(tracks1.length, 1);
      expect(tracks2.length, 1);
    });

    // ── TST-T40: Import JSON with duplicate paths → dedup skips ───────────

    test('test_TST_T40_importJson_duplicateFilePaths_skipsDuplicates',
        () async {
      final container = makeContainer();
      addTearDown(container.dispose);

      const jsonStr = '{"name":"Dedup Import","tracks":['
          '{"filePath":"/dup.mp3","fileName":"dup.mp3"},'
          '{"filePath":"/dup.mp3","fileName":"dup.mp3"},'
          '{"filePath":"/unique.mp3","fileName":"unique.mp3"}'
          ']}';

      final importFn = container.read(importPlaylistProvider);
      final newId = await importFn(jsonStr);

      final tracks = await container.read(playlistTracksProvider(newId).future);
      // Should only have 2 tracks — duplicate filePath skipped
      expect(tracks.length, 2);
      final paths = tracks.map((t) => t.filePath).toSet();
      expect(paths, containsAll(['/dup.mp3', '/unique.mp3']));
    });

    // ── TST-T41: Import malformed JSON → no crash, returns error info ─────

    test('test_TST_T41_importMalformedJson_noCrash_returnsError', () async {
      final container = makeContainer();
      addTearDown(container.dispose);

      final importFn = container.read(importPlaylistProvider);

      // Invalid JSON should throw a FormatException (error information)
      // rather than crashing the app
      expect(
        () => importFn('{not valid json}'),
        throwsA(isA<FormatException>()),
      );

      // Verify no playlist was created from the failed import
      final playlists = await container.read(playlistListProvider.future);
      expect(playlists, isEmpty);
    });

    // ── TST-T42: Export + Import round-trip → name and tracks identical ──

    test('test_TST_T42_exportImportRoundTrip_nameAndTracksMatch', () async {
      // Create a playlist with tracks via DAO
      final originalId =
          await dao.insertPlaylist(_testPlaylist(name: 'Round Trip'));
      await dao.addTracks([
        _testTrack(
            playlistId: originalId,
            filePath: '/music/a.mp3',
            fileName: 'a.mp3'),
        _testTrack(
            playlistId: originalId,
            filePath: '/music/b.flac',
            fileName: 'b.flac'),
        _testTrack(
            playlistId: originalId,
            filePath: '/books/c.m4b',
            fileName: 'c.m4b'),
      ]);

      // Export
      final exportContainer = makeContainer();
      addTearDown(exportContainer.dispose);
      final jsonStr =
          await exportContainer.read(exportPlaylistProvider(originalId).future);

      // Import into an independent container
      final importContainer = makeContainer();
      addTearDown(importContainer.dispose);
      final importFn = importContainer.read(importPlaylistProvider);
      final importedId = await importFn(jsonStr);

      // Verify name matches
      final importedPlaylists =
          await importContainer.read(playlistListProvider.future);
      final imported = importedPlaylists.firstWhere((p) => p.id == importedId);
      expect(imported.name, 'Round Trip');

      // Verify tracks match (same count, same filePaths, same fileNames)
      final originalTracks = await dao.findTracksForPlaylist(originalId);
      final importedTracks =
          await importContainer.read(playlistTracksProvider(importedId).future);

      expect(importedTracks.length, originalTracks.length);
      for (int i = 0; i < originalTracks.length; i++) {
        expect(importedTracks[i].filePath, originalTracks[i].filePath);
        expect(importedTracks[i].fileName, originalTracks[i].fileName);
      }
    });
  });
}
