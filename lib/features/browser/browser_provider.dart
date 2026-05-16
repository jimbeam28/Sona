// lib/features/browser/browser_provider.dart
// Riverpod providers for the Browser feature.
// Written without code generation — uses StateNotifier / FutureProvider.family
// patterns from flutter_riverpod directly (no @riverpod annotations, no build_runner).

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/network/webdav_client.dart';
import '../../core/services/audio_source_builder.dart';
import '../../shared/models/nas_file.dart';
import '../../shared/models/play_progress.dart';
import '../../shared/models/play_queue.dart';
import '../connection/connection_provider.dart';
import '../player/player_provider.dart';
import '../progress/progress_provider.dart';

// ── Sort option ────────────────────────────────────────────────────────────────────

/// Available sort orders for the file/directory list.
enum SortOption {
  /// Sort by name in ascending alphabetical order (A-Z).
  nameAsc,

  /// Sort by name in descending alphabetical order (Z-A).
  nameDesc,

  /// Sort by last-modified time, newest first.
  modifiedDesc,
}

// ── SharedPreferences ──────────────────────────────────────────────────────────────

/// Provider for the [SharedPreferences] instance.
///
/// Defaults to `null` so that tests without a real instance don't crash.
/// In production, override this with [SharedPreferences.getInstance()]
/// (see [main.dart]).
final sharedPreferencesProvider = Provider<SharedPreferences?>((ref) => null);

// ── Sort preference StateNotifier ──────────────────────────────────────────────────

/// Manages the current sort option, persisting changes to [SharedPreferences]
/// so the preference survives app restarts.
///
/// When [SharedPreferences] is unavailable (null) this notifier operates
/// purely in-memory — useful for tests.
class SortOptionNotifier extends StateNotifier<SortOption> {
  final SharedPreferences? _prefs;

  SortOptionNotifier(this._prefs) : super(SortOption.nameAsc) {
    _load();
  }

  static const _key = 'browser_sort_option';

  void _load() {
    if (_prefs == null) return;
    final saved = _prefs.getString(_key);
    if (saved != null) {
      state = SortOption.values.cast<SortOption?>().firstWhere(
            (e) => e!.name == saved,
            orElse: () => SortOption.nameAsc,
          )!;
    }
  }

  /// Updates the sort option and persists it immediately (when [SharedPreferences]
  /// is available).
  void setOption(SortOption option) {
    if (state == option) return;
    state = option;
    _prefs?.setString(_key, option.name);
  }
}

/// The currently active sort option, backed by [SharedPreferences] for
/// persistence across app restarts.
final sortOptionProvider =
    StateNotifierProvider<SortOptionNotifier, SortOption>((ref) {
  final prefs = ref.read(sharedPreferencesProvider);
  return SortOptionNotifier(prefs);
});

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
/// Watches [sortOptionProvider] so that changing the sort order re-sorts the
/// cached data without a new network request.
///
/// Throws [WebDavException] on auth failures; other errors are surfaced
/// as [AsyncError] via the FutureProvider.
///
/// Cache is keyed by `connectionId:path` so switching connections does not
/// leak stale entries from the previous connection (BRW-05).
final directoryContentsProvider =
    FutureProvider.family<List<NasFile>, String>((ref, path) async {
  // 0. Watch sort option — provider re-executes on sort change
  final sortOption = ref.watch(sortOptionProvider);

  // 1. Resolve the active connection
  final activeConn = await ref.watch(activeConnectionProvider.future);
  if (activeConn == null) {
    throw const WebDavException('没有活跃的连接');
  }

  // 2. Check the in-memory cache
  final cache = ref.read(directoryCacheProvider);
  final cacheKey = '${activeConn.id}:$path';
  if (cache.containsKey(cacheKey)) {
    // Re-sort with the current sort option (does not mutate cached list).
    return sortFiles(cache[cacheKey]!, sortOption);
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

  // 6. Sort with current sort option
  final sorted = sortFiles(filtered, sortOption);

  // 7. Write to cache
  ref.read(directoryCacheProvider.notifier).update((state) {
    return {...state, cacheKey: sorted};
  });

  return sorted;
});

// ── Sort helper ────────────────────────────────────────────────────────────────────

/// Returns a new list sorted according to [option].
///
/// Directories always appear before files regardless of the sort option
/// (BRW-T42).  Within each group entries are ordered by the selected criterion.
List<NasFile> sortFiles(List<NasFile> files, SortOption option) {
  final sorted = files.toList();
  sorted.sort((a, b) {
    // Directories always first
    if (a.isDirectory && !b.isDirectory) return -1;
    if (!a.isDirectory && b.isDirectory) return 1;

    // Within the same category, apply the selected sort
    switch (option) {
      case SortOption.nameAsc:
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      case SortOption.nameDesc:
        return b.name.toLowerCase().compareTo(a.name.toLowerCase());
      case SortOption.modifiedDesc:
        final aTime = a.modifiedAt?.millisecondsSinceEpoch ?? 0;
        final bTime = b.modifiedAt?.millisecondsSinceEpoch ?? 0;
        return bTime.compareTo(aTime); // newest first
    }
  });
  return sorted;
}

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

/// The connection ID that was active when the current play queue was created.
///
/// Used by E-2 to detect connection switches: if the active connection changes
/// while a queue is loaded, mini-bar skip/queue operations should warn the user
/// because file paths may not exist on the new connection.
final lastQueueConnectionIdProvider = StateProvider<int?>((ref) => null);

// ── Queue persistence (B-3) ─────────────────────────────────────────────────

const _queuePrefsKey = 'last_play_queue';
const _queueConnIdPrefsKey = 'last_play_queue_connection_id';

/// Saves [queue] to SharedPreferences whenever it changes.
final persistQueueOnChangeProvider = Provider<void>((ref) {
  ref.listen(currentPlayQueueProvider, (prev, next) {
    final prefs = ref.read(sharedPreferencesProvider);
    if (prefs == null) return;
    if (next == null) {
      prefs.remove(_queuePrefsKey);
      prefs.remove(_queueConnIdPrefsKey);
    } else {
      prefs.setString(_queuePrefsKey, jsonEncode(next.toMap()));
      final connId = ref.read(lastQueueConnectionIdProvider);
      if (connId != null) {
        prefs.setInt(_queueConnIdPrefsKey, connId);
      }
    }
  });
});

/// Reads the persisted queue from SharedPreferences and sets it on
/// [currentPlayQueueProvider].  NasFile objects are reconstructed with
/// minimal metadata (path + name) — enough for playback to work.
final restoreQueueFromPrefsProvider =
    FutureProvider<void>((ref) async {
  final prefs = ref.read(sharedPreferencesProvider);
  if (prefs == null) return;
  final raw = prefs.getString(_queuePrefsKey);
  if (raw == null) return;
  try {
    final map = jsonDecode(raw) as Map<String, dynamic>;
    final filePaths = (map['filePaths'] as List<dynamic>?)?.cast<String>();
    if (filePaths == null || filePaths.isEmpty) return;
    final files = filePaths.map((p) {
      final name = p.split('/').last;
      return NasFile(path: p, name: name, isDirectory: false);
    }).toList();
    final currentIndex = (map['currentIndex'] as int?) ?? 0;
    if (currentIndex >= files.length) return;
    final startPositionMs = map['startPositionMs'] as int?;
    final modeName = map['playMode'] as String?;
    final mode = modeName != null
        ? PlayMode.values.firstWhere((m) => m.name == modeName,
            orElse: () => PlayMode.sequential)
        : PlayMode.sequential;
    final queue = PlayQueue(
      files: files,
      currentIndex: currentIndex,
      startPositionMs: startPositionMs,
      playMode: mode,
    );
    ref.read(currentPlayQueueProvider.notifier).state = queue;

    // F-2: check whether the connection has changed since the queue was saved.
    final savedConnId = prefs.getInt(_queueConnIdPrefsKey);
    final conn = ref.read(activeConnectionProvider).valueOrNull;
    if (savedConnId != null && conn?.id != savedConnId) {
      // Connection changed — keep the queue for display but skip pre-loading.
      // The user needs to re-browse the directory on the new connection.
      return;
    }

    // Pre-load the audio source so the mini player bar's play button works
    // immediately after app start (BUG-6).
    if (conn != null) {
      final storage = ref.read(secureStorageProvider);
      final pw =
          await storage.read(key: 'connection_password_${conn.id}');
      if (pw != null && pw.isNotEmpty) {
        final source = AudioSourceBuilder.buildWithBasePath(
          baseUrl: conn.url,
          filePath: files[currentIndex].path,
          username: conn.username,
          password: pw,
        );
        final player = ref.read(audioPlayerProvider);
        await player.setAudioSource(source);
        if (startPositionMs != null) {
          await player.seek(Duration(milliseconds: startPositionMs));
        }
      }
    }
  } catch (_) {
    // Corrupted data — ignore and let the user start fresh.
  }
});

// ── Playback progress lookup ──────────────────────────────────────────────────────

/// In-memory cache of progress records for files in the current directory.
///
/// Populated by [loadProgressForDirectoryProvider] when a directory is loaded.
/// Keyed by file path.  Value is the [PlayProgress] record or `null` when no
/// progress has been saved for that file.
final _progressRegistryProvider =
    StateProvider<Map<String, PlayProgress?>>((ref) => {});

/// Loads progress records for all audio files in [path] from the database
/// and populates [_progressRegistryProvider].
///
/// Triggered alongside [directoryContentsProvider] so the progress bars
/// and resume-dialog logic have data available synchronously.
final loadProgressForDirectoryProvider =
    FutureProvider.family<void, String>((ref, path) async {
  final dao = ref.watch(progressDaoProvider);

  // Resolve the active connection
  final activeConn = ref.read(activeConnectionProvider).valueOrNull;
  if (activeConn == null || activeConn.id == null) return;

  // Get the cached directory contents (must have been loaded already)
  final contents = ref.read(directoryContentsProvider(path)).valueOrNull;
  if (contents == null) return;

  // Query progress for each audio file
  final registry = <String, PlayProgress?>{};
  for (final file in contents) {
    if (file.isDirectory) continue;
    try {
      final progress = await dao.find(activeConn.id!, file.path);
      registry[file.path] = progress;
    } catch (_) {
      // DAO not available (e.g. in test without DB) — skip
      registry[file.path] = null;
    }
  }

  ref.read(_progressRegistryProvider.notifier).state = registry;
});

/// Resolves saved playback progress for a given [filePath].
///
/// Reads from the in-memory registry populated by
/// [loadProgressForDirectoryProvider].  Returns `null` when no progress has
/// been saved, the registry hasn't been loaded yet, or no DAO is available.
///
/// This is a synchronous provider so it can be used in widget callbacks
/// (e.g. `onFileTap`).
final playProgressProvider = Provider.family<PlayProgress?, String>(
  (ref, filePath) {
    final registry = ref.watch(_progressRegistryProvider);
    return registry[filePath];
  },
);
