// lib/features/browser/browser_provider.dart — thin glue: deps + state only.

import 'dart:async';
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
import 'domain/folder_searcher.dart';
import 'domain/navigation_stack.dart';

export 'domain/cache_policy.dart';
export 'domain/directory_service.dart'
    show SortOption, SortOptionNotifier, sortFiles;
export 'domain/navigation_stack.dart';
export '../../core/services/audio_source_builder.dart' show preloadAudioSource;
export '../../shared/di/providers.dart' show sharedPreferencesProvider;

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

final clearDirectoryCacheProvider =
    Provider<int Function(int? connectionId, String? path)>((ref) {
  return (int? connectionId, String? path) {
    if (path == null) {
      // 全量清除：与修复前语义一致（REF-06-S2），connectionId 忽略。
      final count = ref.read(directoryCacheProvider).length;
      ref.read(directoryCacheProvider.notifier).state = {};
      ref.invalidate(directoryContentsProvider);
      return count;
    }
    // REF-06: 连接 id 非空 → 精确全等匹配（cr-20260816-0803 D1）；
    // 连接 id 为空 → 降级旧后缀匹配（保守回退，生产调用方不走此形状）。
    final exactKey = connectionId == null ? null : '$connectionId:$path';
    final toRemove = exactKey == null
        ? ref
            .read(directoryCacheProvider)
            .keys
            .where((k) => k.endsWith(':$path'))
            .toList()
        : (ref.read(directoryCacheProvider).containsKey(exactKey)
            ? [exactKey]
            : <String>[]);
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
            startPositionMs: posMs,
            // BUG-06：晚到即弃——preload 期间用户已选其它曲目（队列 current
            // 变）或清空队列 → 放弃剩余步骤。preload 与用户加载共用同一播放器
            // 且无串行化（P14），守卫以"恢复的曲目是否仍是当前曲目"为准绳。
            shouldAbandon: () {
              final q = ref.read(currentPlayQueueProvider);
              return q == null ||
                  q.length == 0 ||
                  q.current.path != files[idx].path;
            });
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

// ── SRCH-01: folder search session ────────────────────────────────────────────

/// Immutable UI state of the search panel + the latest/running scan.
class SearchSessionState {
  final bool panelOpen; // 搜索面板是否激活
  final int dirsScanned;
  final bool running; // 订阅未结束
  final bool truncated;
  final int skippedDirs;
  final List<SearchHit> hits;
  final String query; // 当前生效 query（trim 后）；空 = 从未发起扫描

  const SearchSessionState({
    this.panelOpen = false,
    this.dirsScanned = 0,
    this.running = false,
    this.truncated = false,
    this.skippedDirs = 0,
    this.hits = const [],
    this.query = '',
  });

  SearchSessionState copyWith({
    bool? panelOpen,
    int? dirsScanned,
    bool? running,
    bool? truncated,
    int? skippedDirs,
    List<SearchHit>? hits,
    String? query,
  }) {
    return SearchSessionState(
      panelOpen: panelOpen ?? this.panelOpen,
      dirsScanned: dirsScanned ?? this.dirsScanned,
      running: running ?? this.running,
      truncated: truncated ?? this.truncated,
      skippedDirs: skippedDirs ?? this.skippedDirs,
      hits: hits ?? this.hits,
      query: query ?? this.query,
    );
  }
}

/// Owns the debounce Timer and the single active scan StreamSubscription.
///
/// Lifecycle rules（spec §3.2）:
///   - closePanel：全清复位（连接切换同款语义）。
///   - cancelScan：只停扫描，面板与已落位字段冻结。
///   - blank query：停流并复位为「已打开但零结果零扫描」态（S5 字面语义）。
///   - 同一时刻至多一条活跃流：_startScan 先取消旧订阅，且启动即清空上一轮命中。
class SearchSessionNotifier extends AutoDisposeNotifier<SearchSessionState> {
  static const _debounceDuration = Duration(milliseconds: 500);

  Timer? _debounce;
  StreamSubscription<SearchEvent>? _sub;
  bool _disposed = false;

  @override
  SearchSessionState build() {
    ref.onDispose(() {
      _disposed = true;
      _debounce?.cancel();
      _sub?.cancel();
    });
    return const SearchSessionState();
  }

  void openPanel() {
    state = state.copyWith(panelOpen: true);
  }

  /// S7 全清：连带取消 debounce 与订阅，状态整体复位为关闭态。
  void closePanel() {
    _debounce?.cancel();
    _sub?.cancel();
    state = const SearchSessionState(panelOpen: false);
  }

  /// S7 冻结式取消：仅 running=false；panelOpen/hits/dirsScanned 等保持不变，
  /// 迟到的流事件被归约器门禁丢弃。
  void cancelScan() {
    _debounce?.cancel();
    _sub?.cancel();
    state = state.copyWith(running: false);
  }

  /// S5 debounce 入口。空白 query 停流并整体复位为开面板初值
  /// （「已打开但零结果零扫描」态），连带吞掉挂起的 debounce timer。
  void onQueryChanged(String raw) {
    _debounce?.cancel();
    final q = raw.trim();
    if (q.isEmpty) {
      _sub?.cancel();
      state = const SearchSessionState(panelOpen: true);
      return;
    }
    _debounce = Timer(_debounceDuration, () => _startScan(q));
  }

  void _startScan(String q) {
    if (_disposed) return;
    // S5 否定断言：新扫描启动前旧订阅必须被取消——同一时刻至多一条活跃流。
    _sub?.cancel();
    // hits 属于当前 query 的活跃流（S6 归约前提）：新一轮扫描启动即清空
    // 上一轮命中，杜绝跨 query 结果累积。
    state = state.copyWith(
      running: true,
      dirsScanned: 0,
      truncated: false,
      skippedDirs: 0,
      hits: const [],
      query: q,
    );
    final rootPath = ref.read(navigationStackProvider).last;
    _sub = searchFolderSubtree(
      rootPath: rootPath,
      query: q,
      fetchDir: (p) => ref.read(directoryContentsProvider(p).future),
    ).listen(_onEvent);
  }

  /// S6 事件归约：尾追保序不去重、计数更新、终态落位；
  /// `_disposed || !state.running` 门禁防御迟到事件（S7-cancel / 换 query）。
  void _onEvent(SearchEvent event) {
    if (_disposed || !state.running) return;
    switch (event) {
      case HitFound(:final hit):
        state = state.copyWith(hits: [...state.hits, hit]);
      case ScanProgress(:final dirsScanned):
        state = state.copyWith(dirsScanned: dirsScanned);
      case ScanDone(:final truncated, :final skippedDirs):
        state = state.copyWith(
          running: false,
          truncated: truncated,
          skippedDirs: skippedDirs,
        );
    }
  }
}

final searchSessionProvider =
    AutoDisposeNotifierProvider<SearchSessionNotifier, SearchSessionState>(
        SearchSessionNotifier.new);
