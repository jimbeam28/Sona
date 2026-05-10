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

// ── Directory contents cache ────────────────────────────────────────────────────

/// In-memory cache for directory contents, keyed by `connectionId:path`.
/// Survives for the lifetime of the provider container (app lifecycle).
/// Cleared on pull-to-refresh via [clearDirectoryCacheProvider].
final directoryCacheProvider =
    StateProvider<Map<String, List<NasFile>>>((ref) => {});

/// Clears the directory contents cache and invalidates the corresponding
/// [directoryContentsProvider] so the next read triggers a fresh network
/// request.
///
/// When [path] is non-null all cache entries whose key ends with `:$path`
/// are removed AND [directoryContentsProvider(path)] is invalidated (used by
/// pull-to-refresh).  When [path] is null the entire cache is wiped but no
/// providers are invalidated.
final clearDirectoryCacheProvider = Provider<void Function(String? path)>((ref) {
  return (String? path) {
    if (path == null) {
      // Clear all cache entries
      ref.read(directoryCacheProvider.notifier).state = {};
    } else {
      // Remove any cache entry for this path across all connections.
      // Keys are "connectionId:path", so we match on the ":$path" suffix.
      final cache = ref.read(directoryCacheProvider);
      final suffix = ':$path';
      final keysToRemove = cache.keys.where((k) => k.endsWith(suffix)).toList();
      if (keysToRemove.isNotEmpty) {
        ref.read(directoryCacheProvider.notifier).update((state) {
          final updated = Map<String, List<NasFile>>.from(state);
          for (final key in keysToRemove) {
            updated.remove(key);
          }
          return updated;
        });
      }
      // Invalidate the contents provider so it re-executes on next read.
      // Without this, Riverpod's internal FutureProvider caching would return
      // the previously-computed result even though our custom cache is empty.
      ref.invalidate(directoryContentsProvider(path));
    }
  };
});

// ── Directory contents ──────────────────────────────────────────────────────────

/// Loads directory contents for the given [path] from the active WebDAV
/// connection, with an in-memory cache.
///
/// On a cache hit the cached list is returned immediately (no network
/// request).  On a cache miss a PROPFIND request is issued and the filtered,
/// sorted result is stored in the cache.
///
/// Throws [WebDavException] on auth failures; other errors are surfaced
/// as [AsyncError] via the FutureProvider.
///
/// Cache is keyed by `connectionId:path` so switching connections does not
/// leak stale entries from the previous connection (BRW-05).
final directoryContentsProvider =
    FutureProvider.family<List<NasFile>, String>((ref, path) async {
  // 1. Resolve the active connection
  final activeConn = await ref.watch(activeConnectionProvider.future);
  if (activeConn == null) {
    throw const WebDavException('没有活跃的连接');
  }

  // 2. Check the in-memory cache
  final cache = ref.read(directoryCacheProvider);
  final cacheKey = '${activeConn.id}:$path';
  if (cache.containsKey(cacheKey)) {
    return cache[cacheKey]!;
  }

  // 3. Read the password from secure storage
  final storage = ref.watch(secureStorageProvider);
  final passwordKey = 'connection_password_${activeConn.id}';
  final password = await storage.read(key: passwordKey);
  if (password == null || password.isEmpty) {
    throw const WebDavException('密码未保存');
  }

  // 4. List the directory
  final client = ref.watch(webDavClientProvider);
  final allEntries = await client.listDirectory(
    url: activeConn.url,
    username: activeConn.username,
    password: password,
    path: path,
  );

  // 5. Filter: exclude self-reference and non-audio files; keep all directories
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

  // 6. Sort: directories first (by name), then files (by name)
  filtered.sort((a, b) {
    if (a.isDirectory && !b.isDirectory) return -1;
    if (!a.isDirectory && b.isDirectory) return 1;
    return a.name.toLowerCase().compareTo(b.name.toLowerCase());
  });

  // 7. Write to cache
  ref.read(directoryCacheProvider.notifier).update((state) {
    return {...state, cacheKey: filtered};
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
