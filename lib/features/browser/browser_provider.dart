// lib/features/browser/browser_provider.dart
// Riverpod providers for the Browser feature.
// Written without code generation — uses StateNotifier / FutureProvider.family
// patterns from flutter_riverpod directly (no @riverpod annotations, no build_runner).

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:just_audio/just_audio.dart';
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

/// Default cache TTL: entries older than 5 minutes are considered stale.
const _cacheTtl = Duration(minutes: 5);

/// In-memory cache for directory contents with TTL, keyed by `connectionId:path`.
/// Each entry stores the file list and the timestamp when it was created.
/// Survives for the lifetime of the provider container (app lifecycle).
/// Cleared on pull-to-refresh via [clearDirectoryCacheProvider].
final directoryCacheProvider =
    StateProvider<Map<String, CacheEntry>>((ref) => {});

/// A cached directory listing with its creation timestamp for TTL checking
/// and last-accessed timestamp for LRU eviction (BUG-03).
class CacheEntry {
  final List<NasFile> files;
  final DateTime createdAt;
  final DateTime lastAccessedAt;
  CacheEntry({
    required this.files,
    required this.createdAt,
    DateTime? lastAccessedAt,
  }) : lastAccessedAt = lastAccessedAt ?? createdAt;
}

/// Clears the directory contents cache and invalidates the corresponding
/// [directoryContentsProvider] so the next read triggers a fresh network
/// request.
///
/// When [path] is non-null all cache entries whose key ends with `:$path`
/// are removed AND [directoryContentsProvider(path)] is invalidated (used by
/// pull-to-refresh).  When [path] is null the entire cache is wiped but no
/// providers are invalidated.
final clearDirectoryCacheProvider =
    Provider<void Function(String? path)>((ref) {
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
          final updated = Map<String, CacheEntry>.from(state);
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

  // 2. Check the in-memory cache with TTL (PRG-03)
  final cache = ref.read(directoryCacheProvider);
  final cacheKey = '${activeConn.id}:$path';
  final cachedEntry = cache[cacheKey];
  if (cachedEntry != null) {
    final age = DateTime.now().difference(cachedEntry.createdAt);
    if (age < _cacheTtl) {
      debugPrint(
          '[Browser] dirContents: cache hit path=$path (age=${age.inSeconds}s)');
      // BUG-03: update lastAccessedAt on cache hit for LRU eviction
      ref.read(directoryCacheProvider.notifier).update((state) {
        final updated = Map<String, CacheEntry>.from(state);
        updated[cacheKey] = CacheEntry(
          files: cachedEntry.files,
          createdAt: cachedEntry.createdAt,
          lastAccessedAt: DateTime.now(),
        );
        return updated;
      });
      return sortFiles(cachedEntry.files, sortOption);
    }
    debugPrint(
        '[Browser] dirContents: cache expired path=$path (age=${age.inSeconds}s)');
  }
  debugPrint('[Browser] dirContents: cache miss path=$path, fetching');

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
    if (entryPath == path ||
        entryPath == requestPath ||
        '$entryPath/' == requestPath) {
      return false;
    }
    // Keep directories, skip non-audio files
    if (entry.isDirectory) return true;
    return entry.audioType != null;
  }).toList();

  debugPrint(
      '[Browser] dirContents: path=$path total=${allEntries.length} filtered=${filtered.length}');

  // 6. Sort with current sort option
  final sorted = sortFiles(filtered, sortOption);

  // 7. Write to cache with TTL (PRG-03: limit to 50 entries, LRU eviction BUG-03)
  ref.read(directoryCacheProvider.notifier).update((state) {
    final now = DateTime.now();
    final updated = {
      ...state,
      cacheKey: CacheEntry(files: sorted, createdAt: now, lastAccessedAt: now),
    };
    if (updated.length > 50) {
      // BUG-03: evict by least-recently-used (oldest lastAccessedAt first)
      final sortedEntries = updated.entries.toList()
        ..sort((a, b) =>
            a.value.lastAccessedAt.compareTo(b.value.lastAccessedAt));
      final keysToRemove =
          sortedEntries.take(updated.length - 50).map((e) => e.key).toList();
      for (final k in keysToRemove) {
        updated.remove(k);
      }
    }
    return updated;
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

/// PLY-04: watches for connection switches and clears the play queue when
/// the active connection no longer matches the queue's origin connection.
///
/// Without this, a phantom mini-player bar appears after switching connections
/// because the queue is still in memory but can't play on the new connection.
final clearQueueOnConnectionSwitchProvider = Provider<void>((ref) {
  ref.listen(activeConnectionProvider, (prev, next) {
    final activeId = next.valueOrNull?.id;
    final queueConnId = ref.read(lastQueueConnectionIdProvider);
    if (activeId != null && queueConnId != null && activeId != queueConnId) {
      debugPrint('[Browser] connection switched, clearing stale queue');
      ref.read(currentPlayQueueProvider.notifier).state = null;
      ref.read(lastQueueConnectionIdProvider.notifier).state = null;
    }
  });
});

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
      debugPrint('[Browser] persistQueue: cleared');
    } else {
      prefs.setString(_queuePrefsKey, jsonEncode(next.toMap()));
      final connId = ref.read(lastQueueConnectionIdProvider);
      if (connId != null) {
        prefs.setInt(_queueConnIdPrefsKey, connId);
      }
      debugPrint(
          '[Browser] persistQueue: saved ${next.length} tracks idx=${next.currentIndex}');
    }
  });
});

/// Pre-loads the audio source for the current track so the mini player bar
/// works immediately after app start.
///
/// BUG-07: Wrapped with a 10-second timeout to prevent startup hang when
/// the NAS is unreachable. On timeout, pre-load is silently skipped.
///
/// Extracted as a top-level function for testability.
@visibleForTesting
Future<void> preloadAudioSource({
  required FlutterSecureStorage storage,
  required int connectionId,
  required String baseUrl,
  required String filePath,
  required String username,
  required AudioPlayer player,
  int? startPositionMs,
}) async {
  final pw = await storage.read(key: 'connection_password_$connectionId')
      .timeout(const Duration(seconds: 10));
  if (pw == null || pw.isEmpty) return;

  debugPrint('[Browser] restoreQueue: pre-loading $filePath');
  final source = AudioSourceBuilder.buildWithBasePath(
    baseUrl: baseUrl,
    filePath: filePath,
    username: username,
    password: pw,
  );
  await player.setAudioSource(source)
      .timeout(const Duration(seconds: 10));
  if (startPositionMs != null) {
    await player.seek(Duration(milliseconds: startPositionMs))
        .timeout(const Duration(seconds: 10));
  }
  debugPrint('[Browser] restoreQueue: pre-load done');
}

/// Reads the persisted queue from SharedPreferences and sets it on
/// [currentPlayQueueProvider].  NasFile objects are reconstructed with
/// minimal metadata (path + name) — enough for playback to work.
final restoreQueueFromPrefsProvider = FutureProvider<void>((ref) async {
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
    final trackCount = files.length;
    debugPrint(
        '[Browser] restoreQueue: $trackCount tracks idx=$currentIndex mode=$mode');
    ref.read(currentPlayQueueProvider.notifier).state = queue;

    // F-2: check whether the connection has changed since the queue was saved.
    final savedConnId = prefs.getInt(_queueConnIdPrefsKey);
    final conn = ref.read(activeConnectionProvider).valueOrNull;
    if (savedConnId != null && conn?.id != savedConnId) {
      // Connection changed — keep the queue for display but skip pre-loading.
      // The user needs to re-browse the directory on the new connection.
      debugPrint('[Browser] restoreQueue: connection changed, skip pre-load');
      return;
    }

    // Pre-load the audio source so the mini player bar's play button works
    // immediately after app start (BUG-6 / BUG-07).
    if (conn != null) {
      try {
        await preloadAudioSource(
          storage: ref.read(secureStorageProvider),
          connectionId: conn.id!,
          baseUrl: conn.url,
          filePath: files[currentIndex].path,
          username: conn.username,
          player: ref.read(audioPlayerProvider),
          startPositionMs: startPositionMs,
        );
      } catch (e) {
        debugPrint('[Browser] restoreQueue: pre-load failed/timeout: $e');
      }
    }
  } catch (e) {
    // H-8: log the error so corrupted data is debuggable.
    debugPrint('restoreQueueFromPrefsProvider: $e');
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

  // PRG-02: load progress for each file in the directory independently.
  final registry = <String, PlayProgress?>{};
  for (final file in contents) {
    if (file.isDirectory) continue;
    try {
      registry[file.path] = await dao.find(activeConn.id!, file.path);
    } catch (_) {
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
