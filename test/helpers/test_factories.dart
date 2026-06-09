// test/helpers/test_factories.dart
// Shared test factory functions extracted from multiple test files (REF-04).

import 'package:nas_audio_player/shared/models/connection_config.dart';
import 'package:nas_audio_player/shared/models/nas_file.dart';
import 'package:nas_audio_player/shared/models/play_progress.dart';

// ── NasFile factories ─────────────────────────────────────────────────────────

/// Builds a directory [NasFile] for test assertions.
NasFile testDir(String name, String path, {DateTime? modifiedAt}) {
  return NasFile(
    name: name,
    path: path,
    isDirectory: true,
    modifiedAt: modifiedAt,
  );
}

/// Builds an audio [NasFile] for test assertions.
NasFile testAudio(
  String name,
  String path, {
  int? size,
  DateTime? modifiedAt,
  AudioFileType type = AudioFileType.music,
}) {
  return NasFile(
    name: name,
    path: path,
    isDirectory: false,
    size: size,
    modifiedAt: modifiedAt,
    audioType: type,
  );
}

// ── ConnectionConfig factories ───────────────────────────────────────────────

/// Creates a [ConnectionConfig] with sensible defaults for testing.
ConnectionConfig testConfig({
  int? id,
  String name = 'Test NAS',
  String url = 'http://192.168.1.100:5005',
  String username = 'admin',
  String basePath = '/dav',
  bool isActive = false,
  DateTime? createdAt,
  DateTime? updatedAt,
}) {
  final now = DateTime.now();
  return ConnectionConfig(
    id: id,
    name: name,
    url: url,
    username: username,
    basePath: basePath,
    isActive: isActive,
    createdAt: createdAt ?? now,
    updatedAt: updatedAt ?? now,
  );
}

/// Creates a [ConnectionConfig] with fixed timestamps (2024) for browser tests.
ConnectionConfig testConnection({int id = 1, String name = 'Test'}) {
  return ConnectionConfig(
    id: id,
    name: name,
    url: 'http://192.168.1.1:8080',
    username: 'admin',
    basePath: '/',
    isActive: true,
    createdAt: DateTime(2024),
    updatedAt: DateTime(2024),
  );
}

// ── PlayProgress factory ─────────────────────────────────────────────────────

/// Builds a [PlayProgress] for test assertions.
PlayProgress testProgress({
  int? id,
  int connectionId = 1,
  String filePath = '/music/test.mp3',
  int positionMs = 30000,
  int? durationMs = 120000,
  DateTime? lastPlayedAt,
}) {
  return PlayProgress(
    id: id,
    connectionId: connectionId,
    filePath: filePath,
    positionMs: positionMs,
    durationMs: durationMs,
    lastPlayedAt: lastPlayedAt ?? DateTime(2024, 1, 15, 10, 0, 0),
  );
}
