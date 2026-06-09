// lib/features/browser/browser_provider.dart — thin glue: deps + state only.

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/network/webdav_client.dart';
import '../../core/services/audio_source_builder.dart';
import '../../core/services/storage_utils.dart';
import '../../shared/models/nas_file.dart';
import '../../shared/models/play_progress.dart';
import '../../shared/models/play_queue.dart';
import '../connection/connection_provider.dart';
import '../player/player_provider.dart';
import '../progress/progress_provider.dart';
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

final clearDirectoryCacheProvider =
    Provider<void Function(String? path)>((ref) {
  return (String? path) {
    if (path == null) {
      ref.read(directoryCacheProvider.notifier).state = {};
    } else {
      final suffix = ':$path';
      final toRemove = ref.read(directoryCacheProvider).keys
          .where((k) => k.endsWith(suffix)).toList();
      if (toRemove.isNotEmpty) {
        ref.read(directoryCacheProvider.notifier).update((s) {
          final u = Map<String, CacheEntry<List<NasFile>>>.from(s);
          for (final k in toRemove) { u.remove(k); }
          return u;
        });
      }
      ref.invalidate(directoryContentsProvider(path));
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
  final pw = await safeStorageRead(storage, key: 'connection_password_${conn.id}');
  if (pw == null || pw.isEmpty) throw const WebDavException('密码未保存');
  final entries = await ref.watch(webDavClientProvider).listDirectory(
      url: conn.url, username: conn.username, password: pw, path: path);
  final reqPath = path.endsWith('/') ? path : '$path/';
  final filtered = entries.where((e) {
    if (e.path == path || e.path == reqPath || '${e.path}/' == reqPath) return false;
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
      prefs..remove(_qKey)..remove(_qConnKey);
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
    final files = paths.map((p) =>
        NasFile(path: p, name: p.split('/').last, isDirectory: false)).toList();
    final idx = (m['currentIndex'] as int?) ?? 0;
    if (idx >= files.length) return;
    final posMs = m['startPositionMs'] as int?;
    final modeName = m['playMode'] as String?;
    final mode = modeName != null
        ? PlayMode.values.firstWhere((m) => m.name == modeName,
            orElse: () => PlayMode.sequential)
        : PlayMode.sequential;
    ref.read(currentPlayQueueProvider.notifier).state = PlayQueue(
        files: files, currentIndex: idx, startPositionMs: posMs, playMode: mode);
    final savedConnId = prefs.getInt(_qConnKey);
    final conn = ref.read(activeConnectionProvider).valueOrNull;
    if (savedConnId != null && conn?.id != savedConnId) return;
    if (conn != null) {
      try {
        await preloadAudioSource(
            storage: ref.read(secureStorageProvider),
            connectionId: conn.id!, baseUrl: conn.url,
            filePath: files[idx].path, username: conn.username,
            player: ref.read(audioPlayerProvider), startPositionMs: posMs);
      } catch (e) {
        debugPrint('[Browser] restoreQueue: pre-load failed: $e');
      }
    }
  } catch (e) {
    debugPrint('restoreQueueFromPrefsProvider: $e');
  }
});

final _progressRegistry = StateProvider<Map<String, PlayProgress?>>((ref) => {});

final loadProgressForDirectoryProvider =
    FutureProvider.family<void, String>((ref, path) async {
  final dao = ref.watch(progressDaoProvider);
  final conn = ref.read(activeConnectionProvider).valueOrNull;
  if (conn == null || conn.id == null) return;
  final contents = ref.read(directoryContentsProvider(path)).valueOrNull;
  if (contents == null) return;
  final reg = <String, PlayProgress?>{};
  for (final f in contents) {
    if (f.isDirectory) continue;
    try { reg[f.path] = await dao.find(conn.id!, f.path); }
    catch (_) { reg[f.path] = null; }
  }
  ref.read(_progressRegistry.notifier).state = reg;
});

final playProgressProvider = Provider.family<PlayProgress?, String>(
    (ref, filePath) => ref.watch(_progressRegistry)[filePath]);
