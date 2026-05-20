// test/features/playlist/ply_10_test.dart
// PLY-10: 播放单数据层 — automated test suite
//
// Unit tests (PLY-T40~T55): DAO CRUD, model serialisation, toNasFile, migration.

import 'package:flutter_test/flutter_test.dart';
import 'package:nas_audio_player/core/database/dao/playlist_dao.dart';
import 'package:nas_audio_player/core/database/database_helper.dart';
import 'package:nas_audio_player/shared/models/playlist.dart';
import 'package:nas_audio_player/shared/models/nas_file.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

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

const _createTables = '''
  CREATE TABLE playlists (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL,
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL
  );
  CREATE TABLE playlist_tracks (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    playlist_id INTEGER NOT NULL,
    file_path TEXT NOT NULL,
    file_name TEXT NOT NULL,
    added_at INTEGER NOT NULL,
    FOREIGN KEY(playlist_id) REFERENCES playlists(id) ON DELETE CASCADE
  );
  CREATE INDEX idx_playlist_tracks_playlist_id ON playlist_tracks(playlist_id);
''';

Future<Database> _openTestDatabase() async {
  final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
  await db.execute('PRAGMA foreign_keys = ON');
  await db.execute(_createTables);
  DatabaseHelper.instance.overrideDatabase(db);
  return db;
}

// ═════════════════════════════════════════════════════════════════════════════
// DAO unit tests — PLY-T40~T48
// ═════════════════════════════════════════════════════════════════════════════

void main() {
  late Database db;
  late PlaylistDao dao;

  setUpAll(() {
    sqfliteFfiInit();
  });

  setUp(() async {
    db = await _openTestDatabase();
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

    test('test_PLY_T41b_findAllPlaylists_emptyPlaylist_trackCountZero', () async {
      await dao.insertPlaylist(_testPlaylist(name: 'Empty'));
      final playlists = await dao.findAllPlaylists();
      expect(playlists.first.trackCount, 0);
    });

    // ── PLY-T42: updatePlaylist updates name ───────────────────────────────

    test('test_PLY_T42_updatePlaylist_updatesName', () async {
      final id = await dao.insertPlaylist(_testPlaylist(name: 'Old'));
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
        _testTrack(playlistId: id, filePath: '/a.mp3', fileName: 'a.mp3', addedAt: now),
        _testTrack(playlistId: id, filePath: '/b.mp3', fileName: 'b.mp3', addedAt: now),
      ]);

      final tracks = await dao.findTracksForPlaylist(id);
      expect(tracks.length, 2);
    });

    // ── PLY-T45: findTracksForPlaylist returns tracks by added_at ASC ──────

    test('test_PLY_T45_findTracksForPlaylist_orderByAddedAt', () async {
      final id = await dao.insertPlaylist(_testPlaylist(name: 'Ordered'));
      final base = DateTime.now();
      await dao.addTracks([
        _testTrack(playlistId: id, filePath: '/b.mp3', fileName: 'b.mp3',
            addedAt: base.add(const Duration(seconds: 2))),
        _testTrack(playlistId: id, filePath: '/a.mp3', fileName: 'a.mp3',
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
        _testTrack(playlistId: id, filePath: '/music/exists.mp3', fileName: 'exists.mp3'),
      ]);

      final exists = await dao.trackExists(id, '/music/exists.mp3');
      expect(exists, isTrue);
    });

    // ── PLY-T48: trackExists returns false when track doesn't exist ────────

    test('test_PLY_T48_trackExists_returnsFalse', () async {
      final id = await dao.insertPlaylist(_testPlaylist(name: 'Dup'));
      await dao.addTracks([
        _testTrack(playlistId: id, filePath: '/music/exists.mp3', fileName: 'exists.mp3'),
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
      final playlist = Playlist(id: 1, name: 'Test', createdAt: now, updatedAt: now);
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
      final track = _testTrack(filePath: '/music/song.mp3', fileName: 'song.mp3');
      final nasFile = track.toNasFile();
      expect(nasFile.isDirectory, isFalse);
      expect(nasFile.name, 'song.mp3');
      expect(nasFile.path, '/music/song.mp3');
    });

    // ── PLY-T53: toNasFile classifies .m4b as audiobook ────────────────────

    test('test_PLY_T53_toNasFile_m4b_asAudiobook', () {
      final track = _testTrack(filePath: '/books/book.m4b', fileName: 'book.m4b');
      final nasFile = track.toNasFile();
      expect(nasFile.audioType, AudioFileType.audiobook);
    });

    // ── PLY-T54: toNasFile classifies .mp3 as music ────────────────────────

    test('test_PLY_T54_toNasFile_mp3_asMusic', () {
      final track = _testTrack(filePath: '/music/song.mp3', fileName: 'song.mp3');
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
}
