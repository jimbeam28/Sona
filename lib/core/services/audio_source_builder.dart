// lib/core/services/audio_source_builder.dart
// Utility for building just_audio AudioSource objects configured for
// WebDAV streaming with Basic Authentication headers.
//
// This is a pure-logic layer that can be tested without AudioPlayer
// or platform channels.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

import '../contracts/storage_contract.dart';
import 'storage_utils.dart';

class AudioSourceBuilder {
  /// Builds a [AudioSource] that reads directly from a local file path
  /// (DL-01-S6 offline playback). Kept beside the remote builders so domain
  /// callers never import just_audio themselves.
  static AudioSource file(String path) => AudioSource.file(path);

  /// Builds a Basic Auth header value from [username] and [password].
  ///
  /// Returns the string `'Basic <base64(username:password)>'`.
  /// Conforms to RFC 7617.
  ///
  /// DL-01: no longer @visibleForTesting — WebDavClient.downloadFile reuses
  /// it as its production Authorization source.
  static String buildAuthHeader({
    required String username,
    required String password,
  }) {
    final credentialBytes = utf8.encode('$username:$password');
    final encoded = base64.encode(credentialBytes);
    return 'Basic $encoded';
  }

  /// Builds a [Uri] for a WebDAV audio file with properly encoded path
  /// segments.
  ///
  /// Each path segment is individually percent-encoded via
  /// [Uri.encodeComponent] so that spaces, Chinese characters, brackets,
  /// and other reserved/special characters produce a valid RFC 3986 URI
  /// (PLY-T07).
  ///
  /// [baseUrl] is the connection's normalised URL
  /// (e.g. `http://192.168.1.1:8080`).
  ///
  /// [filePath] is the file's path from the WebDAV listing
  /// (e.g. `/music/my song.mp3`).
  @visibleForTesting
  static Uri buildUri({
    required String baseUrl,
    required String filePath,
  }) {
    // Strip trailing slash from base so the path stays clean
    final base = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;

    final path = filePath.startsWith('/') ? filePath : '/$filePath';

    // Parse the base to extract scheme, host, port
    final baseUri = Uri.parse(base);

    // Split, filter empty segments (leading slash produces one), encode each
    final segments = path
        .split('/')
        .where((s) => s.isNotEmpty)
        .map((s) => Uri.encodeComponent(s))
        .toList();

    final encodedPath = '/${segments.join('/')}';
    return baseUri.replace(path: encodedPath);
  }

  /// Builds a [Uri] that preserves the base path from the connection URL.
  ///
  /// When the connection's own URL has a non-empty path component (e.g.
  /// `http://host/dav/`), this method concatenates [filePath] after that
  /// base path rather than replacing it entirely.
  ///
  /// This is distinct from [buildUri] which replaces the path on the
  /// connection URL entirely.  Use this method when the WebDAV server
  /// serves content relative to the connection URL's own path.
  @visibleForTesting
  static Uri buildUriWithBasePath({
    required String baseUrl,
    required String filePath,
  }) {
    final baseUri = Uri.parse(baseUrl);

    // Build the combined path: baseUri.path + filePath
    final basePath = baseUri.path.endsWith('/')
        ? baseUri.path.substring(0, baseUri.path.length - 1)
        : baseUri.path;
    final relPath = filePath.startsWith('/') ? filePath : '/$filePath';
    final combinedPath = '$basePath$relPath';

    // Encode each segment
    final segments = combinedPath
        .split('/')
        .where((s) => s.isNotEmpty)
        .map((s) => Uri.encodeComponent(s))
        .toList();

    final encodedPath = '/${segments.join('/')}';
    return baseUri.replace(path: encodedPath);
  }

  /// Builds an [AudioSource] for WebDAV streaming with Basic Auth.
  ///
  /// The returned source points at the [filePath] on [baseUrl] and carries
  /// an `Authorization` header so the server can authenticate the request
  /// without exposing credentials in the URL.
  static AudioSource build({
    required String baseUrl,
    required String filePath,
    required String username,
    required String password,
  }) {
    final uri = buildUri(baseUrl: baseUrl, filePath: filePath);
    final authHeader = buildAuthHeader(username: username, password: password);
    return AudioSource.uri(uri, headers: {'Authorization': authHeader});
  }

  /// Same as [build], but preserves the base path from the connection URL.
  ///
  /// Use this variant when the server's WebDAV root is at a sub-path
  /// (e.g. the connection URL is `http://host/dav/` and file paths are
  /// relative to that root).
  static AudioSource buildWithBasePath({
    required String baseUrl,
    required String filePath,
    required String username,
    required String password,
  }) {
    final uri = buildUriWithBasePath(baseUrl: baseUrl, filePath: filePath);
    final authHeader = buildAuthHeader(username: username, password: password);
    return AudioSource.uri(uri, headers: {'Authorization': authHeader});
  }
}

/// Pre-loads audio source for a track so the mini player bar works
/// immediately after app start.
Future<void> preloadAudioSource({
  required ISecureStorage storage,
  required int connectionId,
  required String baseUrl,
  required String filePath,
  required String username,
  required AudioPlayer player,
  int? startPositionMs,
  // BUG-06（cr-20260816-0802 F2）：晚到即弃守卫——每个 player 调用前
  // 检查队列时效性。用户已在 preload 未完成时选了其它曲目 → 放弃剩余
  // 步骤，防止旧曲进度 seek 落到用户新选的曲目上（P14 绕门补口）。
  bool Function()? shouldAbandon,
}) async {
  String? pw;
  try {
    pw = await safeStorageRead(storage,
        key: 'connection_password_$connectionId');
  } on SecureStorageTimeoutException {
    // secret-logs gate: keep the log semantic — never carry credential words.
    debugPrint('[AudioSource] preload: secure storage read timeout, skip');
    return;
  }
  if (pw == null || pw.isEmpty) return;
  if (shouldAbandon?.call() ?? false) return;
  final src = AudioSourceBuilder.buildWithBasePath(
      baseUrl: baseUrl, filePath: filePath, username: username, password: pw);
  await player.setAudioSource(src).timeout(const Duration(seconds: 10));
  // BUG-06（cr-20260816-0802 F2）二道闸：preload 的 setAudioSource 晚到完成
  // 时，比对播放器当前 source 是否仍是本次发出的 src——用户在 preload 挂起
  // 期间已通过加载门选中其它曲目（后发调用先完成）时，旧曲的 seek 必须放弃，
  // 防止把用户新歌的位置拨乱（P14 补口）。仅"以 shouldAbandon 启动的 preload"
  // （启动恢复路径）做此比对；无该参数的既有直接调用方保持旧行为。
  if (shouldAbandon != null && !_sourceStillIssued(player, src)) return;
  if (shouldAbandon?.call() ?? false) return;
  if (startPositionMs != null) {
    await player
        .seek(Duration(milliseconds: startPositionMs))
        .timeout(const Duration(seconds: 10));
  }
}

/// True when [player]'s current source is still the [issued] one (identity:
/// the same object passed to setAudioSource).  A source that cannot be read
/// back (test doubles that don't stub `audioSource`) counts as replaced so the
/// late preload abandons instead of seeking onto the user's track.
bool _sourceStillIssued(AudioPlayer player, AudioSource issued) {
  try {
    return identical(player.audioSource, issued);
  } on Object catch (e) {
    debugPrint('[AudioSource] preload: cannot introspect current source: $e');
    return false;
  }
}
