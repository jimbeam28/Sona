// lib/features/playlist/playlist_provider.dart
// Riverpod providers for the Playlist feature.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/database/dao/playlist_dao.dart';
import '../../shared/models/nas_file.dart';
import '../../shared/models/playlist.dart';

// ── Sort enums ─────────────────────────────────────────────────────────────

enum PlaylistSortOption { createdAsc, createdDesc, nameAsc, nameDesc }

enum TrackSortOption { addedAsc, nameAsc, nameDesc }

// ── Infrastructure ─────────────────────────────────────────────────────────

final playlistDaoProvider = Provider<PlaylistDao>((ref) => PlaylistDao());

// ── Sort state ─────────────────────────────────────────────────────────────

final playlistSortProvider =
    StateProvider<PlaylistSortOption>((ref) => PlaylistSortOption.createdAsc);

final trackSortProvider =
    StateProvider<TrackSortOption>((ref) => TrackSortOption.addedAsc);

// ── Sort helpers ───────────────────────────────────────────────────────────

int _playlistSortCompare(Playlist a, Playlist b, PlaylistSortOption sort) {
  switch (sort) {
    case PlaylistSortOption.createdAsc:
      return a.createdAt.compareTo(b.createdAt);
    case PlaylistSortOption.createdDesc:
      return b.createdAt.compareTo(a.createdAt);
    case PlaylistSortOption.nameAsc:
      return a.name.compareTo(b.name);
    case PlaylistSortOption.nameDesc:
      return b.name.compareTo(a.name);
  }
}

int _trackSortCompare(PlaylistTrack a, PlaylistTrack b, TrackSortOption sort) {
  switch (sort) {
    case TrackSortOption.addedAsc:
      return a.addedAt.compareTo(b.addedAt);
    case TrackSortOption.nameAsc:
      return a.fileName.compareTo(b.fileName);
    case TrackSortOption.nameDesc:
      return b.fileName.compareTo(a.fileName);
  }
}

// ── Data providers ─────────────────────────────────────────────────────────

final playlistListProvider = FutureProvider<List<Playlist>>((ref) async {
  final dao = ref.watch(playlistDaoProvider);
  final sort = ref.watch(playlistSortProvider);
  final playlists = await dao.findAllPlaylists();
  playlists.sort((a, b) => _playlistSortCompare(a, b, sort));
  return playlists;
});

final playlistTracksProvider =
    FutureProvider.family<List<PlaylistTrack>, int>((ref, playlistId) async {
  final dao = ref.watch(playlistDaoProvider);
  final sort = ref.watch(trackSortProvider);
  final tracks = await dao.findTracksForPlaylist(playlistId);
  tracks.sort((a, b) => _trackSortCompare(a, b, sort));
  return tracks;
});

// ── Mutation providers ─────────────────────────────────────────────────────

final createPlaylistProvider =
    Provider<Future<void> Function(String name)>((ref) {
  final dao = ref.watch(playlistDaoProvider);
  return (String name) async {
    final now = DateTime.now();
    await dao.insertPlaylist(Playlist(
      name: name,
      createdAt: now,
      updatedAt: now,
    ));
    ref.invalidate(playlistListProvider);
  };
});

final deletePlaylistProvider =
    Provider<Future<void> Function(int id)>((ref) {
  final dao = ref.watch(playlistDaoProvider);
  return (int id) async {
    await dao.deletePlaylist(id);
    ref.invalidate(playlistListProvider);
  };
});

final addTracksToPlaylistProvider =
    Provider<Future<void> Function(int playlistId, List<NasFile> files)>((ref) {
  final dao = ref.watch(playlistDaoProvider);
  return (int playlistId, List<NasFile> files) async {
    final now = DateTime.now();
    final tracks = <PlaylistTrack>[];
    for (final file in files) {
      final exists = await dao.trackExists(playlistId, file.path);
      if (!exists) {
        tracks.add(PlaylistTrack(
          playlistId: playlistId,
          filePath: file.path,
          fileName: file.name,
          addedAt: now,
        ));
      }
    }
    if (tracks.isNotEmpty) {
      await dao.addTracks(tracks);
    }
    ref.invalidate(playlistTracksProvider(playlistId));
  };
});

final removeTracksFromPlaylistProvider =
    Provider<Future<void> Function(int playlistId, List<int> trackIds)>((ref) {
  final dao = ref.watch(playlistDaoProvider);
  return (int playlistId, List<int> trackIds) async {
    await dao.removeTracks(trackIds);
    ref.invalidate(playlistTracksProvider(playlistId));
  };
});
