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

final sortOptionProvider =
    StateNotifierProvider<SortOptionNotifier, SortOption>(
        (ref) => SortOptionNotifier(ref.read(sharedPreferencesProvider)));

final directoryCacheProvider =
    StateProvider<Map<String, CacheEntry<List<NasFile>>>>((ref) => {});

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
  final cached = ref.read(directoryCacheProvider)[cacheKey];
  if (cached != null &&
      const CachePolicy<List<NasFile>>().isAlive(cached, DateTime.now())) {
    ref.read(directoryCacheProvider.notifier).update((s) {
      final u = Map<String, CacheEntry<List<NasFile>>>.from(s);
      u[cacheKey] = cached.accessedAt(DateTime.now());
      return u;
    });
    return sortFiles(cached.value, sortOption);
  }
  final storage = ref.watch(secureStorageProvider);
  final pw =
      await safeStorageRead(storage, key: 'connection_password_${conn.id}');
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
          CacheEntry<List<NasFile>>(value: sorted, createdAt: DateTime.now())));
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

final restoreQueueFromPrefsProvider = FutureProvider<void>((ref) async {
  final prefs = ref.read(sharedPreferencesProvider);
  if (prefs == null) return;
  final raw = prefs.getString(_qKey);
  if (raw == null) return;
  try {
    final m = jsonDecode(raw) as Map<String, dynamic>;
    final paths = (m['filePaths'] as List<dynamic>?)?.cast<String>();
    if (paths == null || paths.isEmpty) return;
    final files = paths
        .map((p) =>
            NasFile(path: p, name: p.split('/').last, isDirectory: false))
        .toList();
    final idx = (m['currentIndex'] as int?) ?? 0;
    if (idx >= files.length) return;
    final posMs = m['startPositionMs'] as int?;
    ref.read(currentPlayQueueProvider.notifier).state =
        PlayQueue.fromMap(m, files);
    final savedConnId = prefs.getInt(_qConnKey);
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
