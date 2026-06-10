// lib/features/playlist/playlist_provider.dart
// Riverpod providers for the Playlist feature.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/database/dao/playlist_dao.dart';
import '../../shared/models/nas_file.dart';
import '../../shared/models/playlist.dart';
import 'domain/playlist_service.dart';

// ── Sort enums ─────────────────────────────────────────────────────────────

enum PlaylistSortOption { createdAsc, createdDesc, nameAsc, nameDesc }

enum TrackSortOption { addedAsc, nameAsc, nameDesc }

// ── Infrastructure ─────────────────────────────────────────────────────────

final playlistDaoProvider = Provider<PlaylistDao>((ref) => PlaylistDao());

final playlistServiceProvider = Provider<PlaylistService>((ref) {
  return PlaylistService(dao: ref.read(playlistDaoProvider));
});

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
  final service = ref.watch(playlistServiceProvider);
  return (String name) async {
    await service.createPlaylist(name);
    ref.invalidate(playlistListProvider);
  };
});

final deletePlaylistProvider = Provider<Future<void> Function(int id)>((ref) {
  final service = ref.watch(playlistServiceProvider);
  return (int id) async {
    await service.deletePlaylist(id);
    ref.invalidate(playlistListProvider);
  };
});

final updatePlaylistProvider =
    Provider<Future<void> Function(Playlist playlist)>((ref) {
  final service = ref.watch(playlistServiceProvider);
  return (Playlist playlist) async {
    await service.updatePlaylist(playlist);
    ref.invalidate(playlistListProvider);
  };
});

final addTracksToPlaylistProvider =
    Provider<Future<void> Function(int playlistId, List<NasFile> files)>((ref) {
  final service = ref.watch(playlistServiceProvider);
  return (int playlistId, List<NasFile> files) async {
    await service.addTracksToPlaylist(playlistId, files);
    ref.invalidate(playlistTracksProvider(playlistId));
    ref.invalidate(playlistListProvider);
  };
});

final reorderPlaylistTrackProvider =
    Provider<Future<void> Function(int playlistId, int oldIndex, int newIndex)>(
        (ref) {
  final service = ref.watch(playlistServiceProvider);
  return (int playlistId, int oldIndex, int newIndex) async {
    if (ref.read(trackSortProvider) != TrackSortOption.addedAsc) return;
    await service.reorderTrack(playlistId, oldIndex, newIndex);
    ref.invalidate(playlistTracksProvider(playlistId));
  };
});

final removeTracksFromPlaylistProvider =
    Provider<Future<void> Function(int playlistId, List<int> trackIds)>((ref) {
  final service = ref.watch(playlistServiceProvider);
  return (int playlistId, List<int> trackIds) async {
    await service.removeTracks(trackIds);
    ref.invalidate(playlistTracksProvider(playlistId));
    ref.invalidate(playlistListProvider);
  };
});

// ── PLS-05: Export / Import ─────────────────────────────────────────────────

/// Exports a playlist to a JSON string containing name, track list.
final exportPlaylistProvider =
    FutureProvider.family<String, int>((ref, playlistId) async {
  final service = ref.read(playlistServiceProvider);
  return service.exportPlaylist(playlistId);
});

/// Imports a playlist from a JSON string. Returns the created playlist ID.
final importPlaylistProvider =
    Provider<Future<int> Function(String jsonString)>((ref) {
  final service = ref.watch(playlistServiceProvider);
  return (String jsonString) async {
    final playlistId = await service.importPlaylist(jsonString);
    ref.invalidate(playlistListProvider);
    return playlistId;
  };
});
