// lib/features/browser/browser_provider.dart
// Riverpod providers for the Browser feature.
// Written without code generation — uses StateNotifier / FutureProvider.family
// patterns from flutter_riverpod directly (no @riverpod annotations, no build_runner).

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/webdav_client.dart';
import '../../shared/models/connection_config.dart';
import '../../shared/models/nas_file.dart';
import '../../shared/models/play_progress.dart';
import '../../shared/models/play_queue.dart';
import '../connection/connection_provider.dart';

// ── Directory contents ──────────────────────────────────────────────────────────

/// Loads directory contents for the given [path] from the active WebDAV
/// connection.
///
/// The returned list is filtered (directories + supported audio files only)
/// and sorted (directories first, then case-insensitive by name ascending).
///
/// Throws [WebDavException] on auth failures; other errors are surfaced
/// as [AsyncError] via the FutureProvider.
final directoryContentsProvider =
    FutureProvider.family<List<NasFile>, String>((ref, path) async {
  // 1. Resolve the active connection
  final activeConn = await ref.watch(activeConnectionProvider.future);
  if (activeConn == null) {
    throw const WebDavException('没有活跃的连接');
  }

  // 2. Read the password from secure storage
  final storage = ref.watch(secureStorageProvider);
  final passwordKey = 'connection_password_${activeConn.id}';
  final password = await storage.read(key: passwordKey);
  if (password == null || password.isEmpty) {
    throw const WebDavException('密码未保存');
  }

  // 3. List the directory
  final client = ref.watch(webDavClientProvider);
  final allEntries = await client.listDirectory(
    url: activeConn.url,
    username: activeConn.username,
    password: password,
    path: path,
  );

  // 4. Filter: exclude self-reference and non-audio files; keep all directories
  final requestPath = path.endsWith('/') ? path : '$path/';
  final filtered = allEntries.where((entry) {
    // Skip the directory's own self-reference entry
    final entryPath = entry.path;
    if (entryPath == path || entryPath == requestPath ||
        '$entryPath/' == requestPath) {
      return false;
    }
    // Keep directories, skip non-audio files
    if (entry.isDirectory) return true;
    return entry.audioType != null;
  }).toList();

  // 5. Sort: directories first (by name), then files (by name)
  filtered.sort((a, b) {
    if (a.isDirectory && !b.isDirectory) return -1;
    if (!a.isDirectory && b.isDirectory) return 1;
    return a.name.toLowerCase().compareTo(b.name.toLowerCase());
  });

  return filtered;
});

// ── Navigation stack ────────────────────────────────────────────────────────────

/// Manages the directory navigation history.
///
/// The stack always contains at least one entry (the root "/").
/// Pushing a path appends it; popping removes the last entry but never
/// empties the stack past the root.
class NavigationStackNotifier extends StateNotifier<List<String>> {
  NavigationStackNotifier() : super(['/']);

  /// Navigate into the directory at [path] by pushing it onto the stack.
  void push(String path) {
    state = [...state, path];
  }

  /// Pop back to the parent directory.
  /// Does nothing when already at the root level.
  void pop() {
    if (state.length > 1) {
      state = [...state]..removeLast();
    }
  }

  /// Pop the stack back until [path] is at the top, then stop.
  /// If [path] is not in the stack, resets to root.
  void popTo(String path) {
    final index = state.indexOf(path);
    if (index >= 0) {
      state = state.sublist(0, index + 1);
    } else {
      state = ['/'];
    }
  }

  /// Returns the current (topmost) path.
  String get currentPath => state.last;
}

final navigationStackProvider =
    StateNotifierProvider<NavigationStackNotifier, List<String>>((ref) {
  return NavigationStackNotifier();
});

// ── Play queue ────────────────────────────────────────────────────────────────────

/// The play queue that the Player module should start playing.
///
/// Set by the Browser module when the user taps an audio file (BRW-04).
/// The Player page reads this provider to know what to play.
final currentPlayQueueProvider = StateProvider<PlayQueue?>((ref) => null);

// ── Playback progress lookup ──────────────────────────────────────────────────────

/// Resolves saved playback progress for a given [filePath].
///
/// Returns `null` when no progress has been saved for the file (the common
/// case for first-time playback).  This provider will be expanded when the
/// Progress module implements actual database lookups.
final playProgressProvider = Provider.family<PlayProgress?, String>(
  (ref, filePath) => null,
);
