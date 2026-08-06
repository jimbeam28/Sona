// lib/features/browser/browser_provider.dart — thin glue: deps + state only.

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/network/webdav_client.dart';
import '../../core/services/audio_source_builder.dart';
import '../../core/services/storage_utils.dart';
import '../../shared/models/nas_file.dart';
import '../../shared/models/play_queue.dart';
import '../../shared/webdav_paths.dart';
import '../../shared/di/providers.dart';
import 'domain/cache_policy.dart';
import 'domain/directory_service.dart';
import 'domain/navigation_stack.dart';

export 'domain/cache_policy.dart';
export 'domain/directory_service.dart' show SortOption, SortOptionNotifier;
export 'domain/navigation_stack.dart';
export '../../core/services/audio_source_builder.dart' show preloadAudioSource;

List<NasFile> sortFiles(List<NasFile> files, SortOption option) =>
    DirectoryService.sortFiles(files, option);

final sharedPreferencesProvider = Provider<SharedPreferences?>((ref) => null);

/// REF-01-A6: SharedPreferences-backed [ISortOptionPersist] — keeps the
/// domain layer free of platform-plugin imports.
class SharedPreferencesSortOptionPersist implements ISortOptionPersist {
  final SharedPreferences? _prefs;
  SharedPreferencesSortOptionPersist(this._prefs);

  static const _key = 'browser_sort_option';

  @override
  String? readSortOption() => _prefs?.getString(_key);

  @override
  void writeSortOption(String name) => _prefs?.setString(_key, name);
}

final sortOptionProvider =
    StateNotifierProvider<SortOptionNotifier, SortOption>((ref) =>
        SortOptionNotifier(SharedPreferencesSortOptionPersist(
            ref.read(sharedPreferencesProvider))));

final directoryCacheProvider =
    StateProvider<Map<String, CacheEntry<List<NasFile>>>>((ref) => {});

/// Clock used for directory-cache TTL checks (BUG-31-S3).
///
/// Production uses [DateTime.now]; tests override this provider with a
/// fixed/mutable clock to verify TTL expiry deterministically (P16).
final browserClockProvider =
    Provider<DateTime Function()>((ref) => DateTime.now);

final clearDirectoryCacheProvider = Provider<int Function(String? path)>((ref) {
  return (String? path) {
    if (path == null) {
      final count = ref.read(directoryCacheProvider).length;
      ref.read(directoryCacheProvider.notifier).state = {};
      ref.invalidate(directoryContentsProvider);
      return count;
    } else {
      final suffix = ':$path';
      final toRemove = ref
          .read(directoryCacheProvider)
          .keys
          .where((k) => k.endsWith(suffix))
          .toList();
      if (toRemove.isNotEmpty) {
        ref.read(directoryCacheProvider.notifier).update((s) {
          final u = Map<String, CacheEntry<List<NasFile>>>.from(s);
          for (final k in toRemove) {
            u.remove(k);
          }
          return u;
        });
      }
      ref.invalidate(directoryContentsProvider(path));
      return toRemove.length;
    }
  };
});

final directoryContentsProvider =
    FutureProvider.family<List<NasFile>, String>((ref, path) async {
  final sortOption = ref.watch(sortOptionProvider);
  final conn = await ref.watch(activeConnectionProvider.future);
  if (conn == null) throw const WebDavException('没有活跃的连接');
  final cacheKey = '${conn.id}:$path';
  final clock = ref.read(browserClockProvider);
  final cached = ref.read(directoryCacheProvider)[cacheKey];
  if (cached != null &&
      const CachePolicy<List<NasFile>>().isAlive(cached, clock())) {
    ref.read(directoryCacheProvider.notifier).update((s) {
      final u = Map<String, CacheEntry<List<NasFile>>>.from(s);
      u[cacheKey] = cached.accessedAt(clock());
      return u;
    });
    return sortFiles(cached.value, sortOption);
  }
  final storage = ref.watch(secureStorageProvider);
  final pw = await () async {
    try {
      return await safeStorageRead(storage,
          key: 'connection_password_${conn.id}');
    } on SecureStorageTimeoutException {
      throw const WebDavException('读取密码超时，请重试');
    }
  }();
  if (pw == null || pw.isEmpty) throw const WebDavException('密码未保存');
  // NET1: pass the effective base URL so listDirectory applies the connection
  // base (url.path joined with basePath) exactly once.
  final entries = await ref.watch(webDavClientProvider).listDirectory(
      url: webDavEffectiveBaseUrl(conn.url, conn.basePath),
      username: conn.username,
      password: pw,
      path: path);
  final reqPath = path.endsWith('/') ? path : '$path/';
  final filtered = entries.where((e) {
    if (e.path == path || e.path == reqPath || '${e.path}/' == reqPath)
      return false;
    return e.isDirectory || e.audioType != null;
  }).toList();
  final sorted = sortFiles(filtered, sortOption);
  ref.read(directoryCacheProvider.notifier).update((s) =>
      const CachePolicy<List<NasFile>>().put(s, cacheKey,
          CacheEntry<List<NasFile>>(value: sorted, createdAt: clock())));
  return sorted;
});

final navigationStackProvider =
    StateNotifierProvider<NavigationStackNotifier, List<String>>(
        (ref) => NavigationStackNotifier());

final currentPlayQueueProvider = StateProvider<PlayQueue?>((ref) => null);
final lastQueueConnectionIdProvider = StateProvider<int?>((ref) => null);

final clearQueueOnConnectionSwitchProvider = Provider<void>((ref) {
  ref.listen(activeConnectionProvider, (prev, next) {
    final activeId = next.valueOrNull?.id;
    final qConnId = ref.read(lastQueueConnectionIdProvider);
    if (activeId != null && qConnId != null && activeId != qConnId) {
      ref.read(currentPlayQueueProvider.notifier).state = null;
      ref.read(lastQueueConnectionIdProvider.notifier).state = null;
    }
  });
});

const _qKey = 'last_play_queue';
const _qConnKey = 'last_play_queue_connection_id';

final persistQueueOnChangeProvider = Provider<void>((ref) {
  ref.listen(currentPlayQueueProvider, (prev, next) {
    final prefs = ref.read(sharedPreferencesProvider);
    if (prefs == null) return;
    if (next == null) {
      prefs
        ..remove(_qKey)
        ..remove(_qConnKey);
    } else {
      prefs.setString(_qKey, jsonEncode(next.toMap()));
      final c = ref.read(lastQueueConnectionIdProvider);
      if (c != null) prefs.setInt(_qConnKey, c);
    }
  });
});

/// Connection root used to normalise legacy persisted queue filePaths
/// (cr-20260804-1922 O1): the queue's OWN stored connection first (the
/// queue belongs to that connection even when another one is active), the
/// active connection as fallback when no connectionId was stored. Returns
/// `null` when unavailable → paths are restored unchanged (never throw).
Future<String?> _restoredQueueRoot(Ref ref, int? savedConnId) async {
  if (savedConnId != null) {
    final conn = await ref.read(connectionDaoProvider).findById(savedConnId);
    if (conn == null) return null;
    return webDavConnectionRoot(conn.url, conn.basePath);
  }
  final conn = ref.read(activeConnectionProvider).valueOrNull;
  if (conn == null) return null;
  return webDavConnectionRoot(conn.url, conn.basePath);
}

final restoreQueueFromPrefsProvider = FutureProvider<void>((ref) async {
  // Yield before mutating any other provider: the synchronous prefix of a
  // FutureProvider body runs during its own build, and Riverpod forbids
  // modifying other providers while an element is building (P11).  Without
  // this yield the `currentPlayQueueProvider.state = ...` below trips the
  // debug assertion and the whole restore degrades to AsyncError — i.e. the
  // persisted queue (incl. BUG-14's shuffle state) would never load in
  // debug builds.
  await null;
  final prefs = ref.read(sharedPreferencesProvider);
  if (prefs == null) return;
  final raw = prefs.getString(_qKey);
  if (raw == null) return;
  try {
    final m = jsonDecode(raw) as Map<String, dynamic>;
    final paths = (m['filePaths'] as List<dynamic>?)?.cast<String>();
    if (paths == null || paths.isEmpty) return;
    // NET1 legacy (O1): pre-NET1 builds persisted server-absolute filePaths.
    // Strip the owning connection's root so the restored paths match current
    // listDirectory output and buildWithBasePath applies the base exactly
    // once (no /dav/dav double prefix). The next persistQueueOnChange write
    // stores the normalised values back naturally.
    final savedConnId = prefs.getInt(_qConnKey);
    final root = await _restoredQueueRoot(ref, savedConnId);
    final normalized = root == null
        ? paths
        : paths.map((p) => normalizeStoredPath(p, basePath: root)).toList();
    final files = normalized
        .map((p) =>
            NasFile(path: p, name: p.split('/').last, isDirectory: false))
        .toList();
    final idx = (m['currentIndex'] as int?) ?? 0;
    if (idx >= files.length) return;
    final posMs = m['startPositionMs'] as int?;
    final restoredQueue = PlayQueue.fromMap(m, files);
    ref.read(currentPlayQueueProvider.notifier).state = restoredQueue;
    // O3 (cr-20260804-1922 §5): restore the persisted playMode as well —
    // playModeProvider's initial value is always sequential, so without this
    // write a persisted shuffle/repeat queue comes back dormant (the shuffle
    // permutation is restored but behaviour stays sequential until the user
    // manually cycles the mode). Idempotent: equal-value writes are no-ops,
    // and this runs after the `await null` yield above, outside any provider
    // build phase (BUG-14/P11). orchestrator.playMode follows via the
    // existing ref.listen sync in playbackOrchestratorProvider — no second
    // sync channel. Queues persisted before playMode existed lack the field
    // → fromMap defaults to sequential → this write is a no-op.
    ref.read(playModeProvider.notifier).state = restoredQueue.playMode;
    final conn = ref.read(activeConnectionProvider).valueOrNull;
    if (savedConnId != null && conn?.id != savedConnId) return;
    if (conn != null) {
      try {
        await preloadAudioSource(
            storage: ref.read(secureStorageProvider),
            connectionId: conn.id!,
            baseUrl: webDavEffectiveBaseUrl(conn.url, conn.basePath),
            filePath: files[idx].path,
            username: conn.username,
            player: ref.read(audioPlayerProvider),
            startPositionMs: posMs);
      } catch (e) {
        debugPrint('[Browser] restoreQueue: pre-load failed: $e');
      }
    }
  } catch (e) {
    debugPrint('restoreQueueFromPrefsProvider: $e');
  }
});

// BUG-12 (2026-07-24): the _progressRegistry / loadProgressForDirectoryProvider
// / playProgressProvider trio was removed.  The registry was never populated:
// its only trigger sites were invalidates, and Riverpod 2.6.1 invalidate on a
// never-created family element is a no-op — so browser-side resume dialogs and
// the long-press clear entry never fired.  Browser progress queries now read
// progressForFileProvider directly (progress feature), which the upsert/clear
// write paths already invalidate (P10 single subscription source).
