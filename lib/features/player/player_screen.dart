// lib/features/player/player_screen.dart
// Full player screen — PLY-01.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:just_audio/just_audio.dart';

import '../../core/services/storage_utils.dart';
import '../../shared/di/providers.dart';

import 'domain/player_screen_logic.dart';
import 'player_provider.dart';
import 'widgets/now_playing_icon.dart';
import 'widgets/play_mode_control.dart';
import 'widgets/playback_controls.dart';
import 'widgets/progress_slider.dart';
import 'widgets/queue_button.dart';
import 'widgets/queue_sheet.dart';
import 'widgets/speed_control.dart';
import 'widgets/timer_control.dart';

/// The full-screen audio player — pushed via `/player` route.
class PlayerScreen extends ConsumerStatefulWidget {
  const PlayerScreen({super.key});

  @override
  ConsumerState<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends ConsumerState<PlayerScreen>
    with WidgetsBindingObserver {
  PlayerLoadState _loadState = PlayerLoadState.idle;
  int _loadRequestToken = 0;
  late ProviderContainer _container;

  Timer? _timerExpiryChecker;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final player = ref.read(audioPlayerProvider);
      final queue = ref.read(currentPlayQueueProvider);
      debugPrint(
        '[Player] postFrameCallback: queue=${queue?.current.path}, '
        'hasSource=${player.sequenceState != null}',
      );
      final currentSourcePath = _extractCurrentSourcePath(player);
      final needsReload =
          queue != null && !sourceMatchesQueue(currentSourcePath, queue);
      if (!needsReload &&
          (player.playing || player.processingState == ProcessingState.ready)) {
        debugPrint('[Player] skipping load — source matches and player ready');
        setState(() => _loadState = PlayerLoadState.ready);
        ref.read(reconnectPlaybackListenersProvider)();
      } else {
        debugPrint('[Player] calling _loadAndPlay, needsReload=$needsReload');
        _loadAndPlay();
      }
    });

    // TMR-05: check for duration-timer expiry every second.
    _timerExpiryChecker = Timer.periodic(const Duration(seconds: 1), (_) {
      final expired = ref.read(checkTimerExpiryProvider)();
      if (expired && mounted) {
        ref.read(audioPlayerProvider).pause();
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    debugPrint('[Player] lifecycle: $state');
    if (state == AppLifecycleState.paused) {
      _saveProgress();
    } else if (state == AppLifecycleState.resumed) {
      // TMR-02: check timer expiry immediately on resume.
      final expired = ref.read(checkTimerExpiryProvider)();
      if (expired) {
        ref.read(audioPlayerProvider).pause();
      }
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _container = ProviderScope.containerOf(context);
  }

  @override
  void dispose() {
    _saveProgressWithContainer(_container);
    // BUG-12: the old loadProgressForDirectoryProvider invalidate here was
    // removed with the progress registry — browser progress queries now read
    // progressForFileProvider, invalidated by the write paths themselves.
    _timerExpiryChecker?.cancel();
    // BUG-20 (cr-20260822-2051 F1): autosave/pausesave listeners are owned by
    // the app-level container (ref.onDispose, INV1) — a page State's dispose
    // must not touch them, or background listening loses progress persistence.
    WidgetsBinding.instance.removeObserver(this);

    super.dispose();
  }

  // ── Load & Play ────────────────────────────────────────────────────────

  /// Extracts the decoded URI path of the currently loaded audio source,
  /// or `null` if no source is loaded.
  String? _extractCurrentSourcePath(AudioPlayer player) {
    final state = player.sequenceState;
    if (state == null) return null;
    final source = state.currentSource;
    if (source is UriAudioSource) {
      return Uri.decodeComponent(source.uri.path);
    }
    return null;
  }

  Future<void> _loadAndPlay() async {
    await _runSerializedLoad(() => ref.read(loadAndPlayProvider)());
  }

  /// Safe setState that catches defunct-element errors during async callbacks.
  void _safeSetState(VoidCallback fn) {
    try {
      if (mounted) setState(fn);
    } catch (_) {
      // Element._lifecycleState == defunct, ignore.
    }
  }

  Future<void> _runSerializedLoad(
    Future<TrackLoadResult> Function() request,
  ) async {
    final queue = ref.read(currentPlayQueueProvider);
    if (queue == null || queue.length == 0) {
      debugPrint('[Player] _runSerializedLoad: queue is null/empty');
      _safeSetState(() {
        _loadState = PlayerLoadState.error('没有选择播放文件');
      });
      return;
    }

    debugPrint(
        '[Player] _runSerializedLoad: setting loading, file=${queue.current.path}');
    _safeSetState(() => _loadState = PlayerLoadState.loading);
    final requestToken = ++_loadRequestToken;

    try {
      late final TrackLoadResult loaded;
      try {
        loaded = await request().timeout(const Duration(seconds: 15));
      } on TimeoutException {
        debugPrint(
            '[Player] _runSerializedLoad: TIMEOUT token=$requestToken mounted=$mounted');
        if (!mounted || requestToken != _loadRequestToken) return;
        _safeSetState(() {
          _loadState = PlayerLoadState.error('加载超时，请重试');
        });
        return;
      }

      debugPrint(
          '[Player] _runSerializedLoad: result=${loaded.status} token=$requestToken');
      if (!mounted || requestToken != _loadRequestToken) return;

      if (loaded.isLoaded) {
        debugPrint('[Player] _runSerializedLoad: → ready');
        _safeSetState(() => _loadState = PlayerLoadState.ready);
      } else if (loaded.isSuperseded) {
        // REF-04 (cr-20260816-0802 D2): superseded 是 gate 串行化的正常竞态结果，
        // 不渲染错误态。若播放器已与当前队列对齐（外部请求已落地，如通知栏 skip/
        // 自动切歌/删除当前曲），直接转 ready 避免闪断；否则保持 loading 并自动
        // 重发加载，使页面状态收敛到 gate 的最新请求。
        debugPrint('[Player] _runSerializedLoad: → superseded');
        final p = ref.read(audioPlayerProvider);
        final cur = ref.read(currentPlayQueueProvider);
        if (cur != null && cur.length > 0) {
          final src = _extractCurrentSourcePath(p);
          final aligned = p.sequenceState != null &&
              sourceMatchesQueue(src, cur) &&
              p.processingState != ProcessingState.idle;
          if (aligned) {
            _safeSetState(() => _loadState = PlayerLoadState.ready);
          } else {
            debugPrint(
                '[Player] superseded: player not aligned, re-running load');
            unawaited(_loadAndPlay());
          }
        }
        // queue null/empty: 保持 loading，页面 build 层自动 pop（build 空队列兜底）。
      } else {
        debugPrint('[Player] _runSerializedLoad: → failed, checking reason');
        final activeConn = ref.read(activeConnectionProvider).valueOrNull;
        bool hasPassword = false;
        if (activeConn != null) {
          final storage = ref.read(secureStorageProvider);
          try {
            final pw = await safeStorageRead(storage,
                key: 'connection_password_${activeConn.id}');
            hasPassword = pw != null && pw.isNotEmpty;
          } on SecureStorageTimeoutException {
            // secret-logs gate: semantic log only, no credential words.
            debugPrint('[Player] secure storage read timeout');
            hasPassword = false;
          }
        }
        final reason = classifyLoadFailure(
          hasActiveConnection: activeConn != null,
          hasPassword: hasPassword,
        );
        debugPrint('[Player] error: $reason');
        _safeSetState(() {
          _loadState = PlayerLoadState.error(
            errorMessageForLoadFailure(reason),
            isAuthError: isAuthError(reason),
          );
        });
      }
    } catch (e, st) {
      debugPrint('[Player] _runSerializedLoad: unexpected error $e\n$st');
      _safeSetState(() {
        _loadState = PlayerLoadState.error('加载失败');
      });
    }
  }

  Future<void> _retry() => _loadAndPlay();

  void _playNext() {
    unawaited(_runSerializedLoad(() => ref.read(skipToNextProvider)()));
  }

  void _playPrevious() {
    unawaited(_runSerializedLoad(() => ref.read(skipToPreviousProvider)()));
  }

  void _showQueueSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => QueueSheet(
        errorMessage: '无法加载音频，请检查连接配置',
        onSelectIndex: (index) async {
          unawaited(
            _runSerializedLoad(() => ref.read(selectQueueIndexProvider)(index)),
          );
          return true;
        },
        onRemoveIndex: (index) {
          ref.read(removeTrackFromQueueProvider)(index);
        },
      ),
    );
  }

  void _saveProgress() {
    _saveProgressWithContainer(_container);
  }

  void _saveProgressWithContainer(ProviderContainer container) {
    container.read(saveProgressProvider)();
  }

  @override
  Widget build(BuildContext context) {
    final queue = ref.watch(currentPlayQueueProvider);

    if (queue == null || queue.length == 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }
      });
      return const Scaffold(body: SizedBox.shrink());
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _loadState.status == PlayerLoadStatus.ready
              ? queue.current.name
              : '播放器',
        ),
        centerTitle: true,
      ),
      body: _buildBody(queue),
    );
  }

  Widget _buildBody(playQueue) {
    switch (_loadState.status) {
      case PlayerLoadStatus.idle:
        return const Center(child: CircularProgressIndicator());
      case PlayerLoadStatus.loading:
        return _buildLoading();
      case PlayerLoadStatus.ready:
        return _buildReady(playQueue);
      case PlayerLoadStatus.error:
        return _buildError();
    }
  }

  Widget _buildLoading() {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 16),
          Text('正在加载音频...'),
        ],
      ),
    );
  }

  Widget _buildReady(playQueue) {
    final fileName = playQueue?.current.name ?? '未知文件';
    final index = playQueue?.currentIndex ?? 0;
    final total = playQueue?.length ?? 1;

    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Spacer(),
          // Large music icon
          const NowPlayingIcon(),
          const SizedBox(height: 24),
          // File name
          Text(
            fileName,
            style: Theme.of(context).textTheme.titleLarge,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 8),
          // Queue position
          Text(
            '${index + 1} / $total',
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: Colors.grey),
          ),
          const SizedBox(height: 16),
          // Speed + Timer + Play mode + Queue — grouped above the progress bar
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              const SpeedControl(),
              const TimerControl(),
              const PlayModeControl(),
              QueueButton(onTap: () => _showQueueSheet(context)),
            ],
          ),
          const SizedBox(height: 16),
          // Progress slider with integrated time display
          const ProgressSlider(),
          const SizedBox(height: 16),
          // Playback controls: previous, skip back, play/pause, skip forward, next
          PlaybackControls(
            onPrevious: _playPrevious,
            onNext: _playNext,
          ),
          const Spacer(),
        ],
      ),
    );
  }

  Widget _buildError() {
    final isAuth = _loadState.isAuthError;
    final message = _loadState.errorMessage ?? '未知错误';

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isAuth ? Icons.lock_outline : Icons.error_outline,
              size: 80,
              color: isAuth ? Colors.orange : Colors.red,
            ),
            const SizedBox(height: 16),
            Text(
              message,
              style: Theme.of(context).textTheme.bodyLarge,
              textAlign: TextAlign.center,
            ),
            if (isAuth) ...[
              const SizedBox(height: 8),
              Text(
                '请检查连接配置中的用户名和密码',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: Colors.grey),
              ),
            ],
            const SizedBox(height: 24),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                OutlinedButton.icon(
                  onPressed: _retry,
                  icon: const Icon(Icons.refresh),
                  label: const Text('重试'),
                ),
                if (isAuth) ...[
                  const SizedBox(width: 16),
                  FilledButton.icon(
                    onPressed: () {
                      context.pop();
                      context.push('/connection');
                    },
                    icon: const Icon(Icons.settings),
                    label: const Text('检查连接'),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
