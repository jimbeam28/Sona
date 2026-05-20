// lib/shared/models/playlist.dart
// Data models for playlists and their tracks.

import 'nas_file.dart';

class Playlist {
  final int? id;
  final String name;
  final int trackCount;
  final DateTime createdAt;
  final DateTime updatedAt;

  const Playlist({
    this.id,
    required this.name,
    this.trackCount = 0,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Playlist.fromMap(Map<String, dynamic> map) {
    return Playlist(
      id: map['id'] as int?,
      name: map['name'] as String,
      trackCount: (map['track_count'] as int?) ?? 0,
      createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(map['updated_at'] as int),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'name': name,
      'created_at': createdAt.millisecondsSinceEpoch,
      'updated_at': updatedAt.millisecondsSinceEpoch,
    };
  }

  Playlist copyWith({
    int? id,
    String? name,
    int? trackCount,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Playlist(
      id: id ?? this.id,
      name: name ?? this.name,
      trackCount: trackCount ?? this.trackCount,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  String toString() =>
      'Playlist(id: $id, name: $name, trackCount: $trackCount)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Playlist &&
          id == other.id &&
          name == other.name &&
          trackCount == other.trackCount;

  @override
  int get hashCode => Object.hash(id, name, trackCount);
}

class PlaylistTrack {
  final int? id;
  final int playlistId;
  final String filePath;
  final String fileName;
  final DateTime addedAt;

  const PlaylistTrack({
    this.id,
    required this.playlistId,
    required this.filePath,
    required this.fileName,
    required this.addedAt,
  });

  factory PlaylistTrack.fromMap(Map<String, dynamic> map) {
    return PlaylistTrack(
      id: map['id'] as int?,
      playlistId: map['playlist_id'] as int,
      filePath: map['file_path'] as String,
      fileName: map['file_name'] as String,
      addedAt: DateTime.fromMillisecondsSinceEpoch(map['added_at'] as int),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'playlist_id': playlistId,
      'file_path': filePath,
      'file_name': fileName,
      'added_at': addedAt.millisecondsSinceEpoch,
    };
  }

  NasFile toNasFile() {
    return NasFile(
      name: fileName,
      path: filePath,
      isDirectory: false,
      audioType: NasFile.isAudioFile(fileName)
          ? NasFile.classifyType(fileName)
          : null,
    );
  }

  @override
  String toString() =>
      'PlaylistTrack(id: $id, playlistId: $playlistId, fileName: $fileName)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PlaylistTrack &&
          id == other.id &&
          playlistId == other.playlistId &&
          filePath == other.filePath &&
          fileName == other.fileName;

  @override
  int get hashCode => Object.hash(id, playlistId, filePath, fileName);
}
