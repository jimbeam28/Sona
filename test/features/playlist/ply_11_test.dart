// test/features/playlist/ply_11_test.dart
// PLY-11: 播放单 Provider 层 — automated test suite
//
// Unit tests (PLY-T56~T59): mutation providers, sort providers, data providers.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nas_audio_player/core/database/dao/playlist_dao.dart';
import 'package:nas_audio_player/core/database/database_helper.dart';
import 'package:nas_audio_player/features/playlist/playlist_provider.dart';
import 'package:nas_audio_player/shared/models/nas_file.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../helpers/test_database.dart';

// ── Helpers ───────────────────────────────────────────────────────────────────


/// Creates a [ProviderContainer] that overrides [playlistDaoProvider] so the
/// DAO uses the test database injected via [DatabaseHelper].
ProviderContainer _makeContainer() {
  return ProviderContainer(overrides: [
    playlistDaoProvider.overrideWith((ref) => PlaylistDao()),
  ]);
}

// ═════════════════════════════════════════════════════════════════════════════
// Provider unit tests — PLY-T56~T59
// ═════════════════════════════════════════════════════════════════════════════

void main() {
  late Database db;

  setUpAll(() {
    initSqfliteFfi();
  });

  setUp(() async {
    db = await openTestDatabase(TestSchema.playlist);
  });

  tearDown(() async {
    await db.close();
  });

  // ── PLY-T56: createPlaylistProvider ────────────────────────────────────

  group('PLY-T56 createPlaylistProvider', () {
    test('creates playlist and refreshes list', () async {
      final container = _makeContainer();
      addTearDown(container.dispose);

      final create = container.read(createPlaylistProvider);
      await create('My Playlist');

      final list = await container.read(playlistListProvider.future);
      expect(list.length, 1);
      expect(list.first.name, 'My Playlist');
    });

    test('creating second playlist also appears in list', () async {
      final container = _makeContainer();
      addTearDown(container.dispose);

      final create = container.read(createPlaylistProvider);
      await create('First');
      await create('Second');

      final list = await container.read(playlistListProvider.future);
      expect(list.length, 2);
    });
  });

  // ── PLY-T57: deletePlaylistProvider ────────────────────────────────────

  group('PLY-T57 deletePlaylistProvider', () {
    test('deletes playlist and refreshes list', () async {
      final container = _makeContainer();
      addTearDown(container.dispose);

      final create = container.read(createPlaylistProvider);
      await create('To Delete');

      var list = await container.read(playlistListProvider.future);
      final id = list.first.id!;

      final del = container.read(deletePlaylistProvider);
      await del(id);

      list = await container.read(playlistListProvider.future);
      expect(list, isEmpty);
    });
  });

  // ── PLY-T58: addTracksToPlaylistProvider ───────────────────────────────

  group('PLY-T58 addTracksToPlaylistProvider', () {
    test('adds tracks and refreshes track list', () async {
      final container = _makeContainer();
      addTearDown(container.dispose);

      final create = container.read(createPlaylistProvider);
      await create('With Tracks');
      final playlists = await container.read(playlistListProvider.future);
      final id = playlists.first.id!;

      final addTracks = container.read(addTracksToPlaylistProvider);
      await addTracks(id, [
        const NasFile(name: 'a.mp3', path: '/music/a.mp3', isDirectory: false),
        const NasFile(
            name: 'b.flac', path: '/music/b.flac', isDirectory: false),
      ]);

      final tracks = await container.read(playlistTracksProvider(id).future);
      expect(tracks.length, 2);
      expect(tracks[0].fileName, 'a.mp3');
      expect(tracks[1].fileName, 'b.flac');
    });

    test('deduplicates — skips files already in playlist', () async {
      final container = _makeContainer();
      addTearDown(container.dispose);

      final create = container.read(createPlaylistProvider);
      await create('Dedup');
      final playlists = await container.read(playlistListProvider.future);
      final id = playlists.first.id!;

      final addTracks = container.read(addTracksToPlaylistProvider);
      await addTracks(id, [
        const NasFile(name: 'a.mp3', path: '/music/a.mp3', isDirectory: false),
      ]);
      // Add same file again
      await addTracks(id, [
        const NasFile(name: 'a.mp3', path: '/music/a.mp3', isDirectory: false),
        const NasFile(name: 'b.mp3', path: '/music/b.mp3', isDirectory: false),
      ]);

      final tracks = await container.read(playlistTracksProvider(id).future);
      expect(tracks.length, 2); // 'a.mp3' not duplicated
    });
  });

  // ── PLY-T59: removeTracksFromPlaylistProvider ──────────────────────────

  group('PLY-T59 removeTracksFromPlaylistProvider', () {
    test('removes tracks and refreshes track list', () async {
      final container = _makeContainer();
      addTearDown(container.dispose);

      final create = container.read(createPlaylistProvider);
      await create('Remove');
      final playlists = await container.read(playlistListProvider.future);
      final id = playlists.first.id!;

      final addTracks = container.read(addTracksToPlaylistProvider);
      await addTracks(id, [
        const NasFile(name: 'a.mp3', path: '/music/a.mp3', isDirectory: false),
        const NasFile(name: 'b.mp3', path: '/music/b.mp3', isDirectory: false),
        const NasFile(name: 'c.mp3', path: '/music/c.mp3', isDirectory: false),
      ]);

      var tracks = await container.read(playlistTracksProvider(id).future);
      final toRemove = [tracks[0].id!, tracks[2].id!];

      final removeTracks = container.read(removeTracksFromPlaylistProvider);
      await removeTracks(id, toRemove);

      tracks = await container.read(playlistTracksProvider(id).future);
      expect(tracks.length, 1);
      expect(tracks.first.fileName, 'b.mp3');
    });
  });

  // ── Sort provider tests ────────────────────────────────────────────────

  group('Sort providers', () {
    test('playlistSortProvider defaults to createdAsc', () {
      final container = _makeContainer();
      addTearDown(container.dispose);
      expect(
          container.read(playlistSortProvider), PlaylistSortOption.createdAsc);
    });

    test('trackSortProvider defaults to addedAsc', () {
      final container = _makeContainer();
      addTearDown(container.dispose);
      expect(container.read(trackSortProvider), TrackSortOption.addedAsc);
    });

    test('playlistListProvider sorts by name ascending', () async {
      final container = _makeContainer();
      addTearDown(container.dispose);

      final create = container.read(createPlaylistProvider);
      await create('Charlie');
      await create('Alpha');
      await create('Bravo');

      container.read(playlistSortProvider.notifier).state =
          PlaylistSortOption.nameAsc;

      final list = await container.read(playlistListProvider.future);
      expect(list[0].name, 'Alpha');
      expect(list[1].name, 'Bravo');
      expect(list[2].name, 'Charlie');
    });

    test('playlistListProvider sorts by name descending', () async {
      final container = _makeContainer();
      addTearDown(container.dispose);

      final create = container.read(createPlaylistProvider);
      await create('Alpha');
      await create('Bravo');
      await create('Charlie');

      container.read(playlistSortProvider.notifier).state =
          PlaylistSortOption.nameDesc;

      final list = await container.read(playlistListProvider.future);
      expect(list[0].name, 'Charlie');
      expect(list[1].name, 'Bravo');
      expect(list[2].name, 'Alpha');
    });

    test('playlistTracksProvider sorts by name ascending', () async {
      final container = _makeContainer();
      addTearDown(container.dispose);

      final create = container.read(createPlaylistProvider);
      await create('Sort');
      final playlists = await container.read(playlistListProvider.future);
      final id = playlists.first.id!;

      final addTracks = container.read(addTracksToPlaylistProvider);
      await addTracks(id, [
        const NasFile(name: 'z.mp3', path: '/z.mp3', isDirectory: false),
        const NasFile(name: 'a.mp3', path: '/a.mp3', isDirectory: false),
        const NasFile(name: 'm.mp3', path: '/m.mp3', isDirectory: false),
      ]);

      container.read(trackSortProvider.notifier).state =
          TrackSortOption.nameAsc;

      final tracks = await container.read(playlistTracksProvider(id).future);
      expect(tracks[0].fileName, 'a.mp3');
      expect(tracks[1].fileName, 'm.mp3');
      expect(tracks[2].fileName, 'z.mp3');
    });

    test('playlistTracksProvider sorts by name descending', () async {
      final container = _makeContainer();
      addTearDown(container.dispose);

      final create = container.read(createPlaylistProvider);
      await create('Sort');
      final playlists = await container.read(playlistListProvider.future);
      final id = playlists.first.id!;

      final addTracks = container.read(addTracksToPlaylistProvider);
      await addTracks(id, [
        const NasFile(name: 'a.mp3', path: '/a.mp3', isDirectory: false),
        const NasFile(name: 'm.mp3', path: '/m.mp3', isDirectory: false),
        const NasFile(name: 'z.mp3', path: '/z.mp3', isDirectory: false),
      ]);

      container.read(trackSortProvider.notifier).state =
          TrackSortOption.nameDesc;

      final tracks = await container.read(playlistTracksProvider(id).future);
      expect(tracks[0].fileName, 'z.mp3');
      expect(tracks[1].fileName, 'm.mp3');
      expect(tracks[2].fileName, 'a.mp3');
    });
  });
}
