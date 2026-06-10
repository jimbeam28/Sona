// lib/features/player/player_screen.dart
// Full player screen — PLY-01.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';

import '../../core/services/storage_utils.dart';
import '../../shared/models/play_queue.dart';
import '../browser/browser_provider.dart';
import '../connection/connection_provider.dart';
import '../timer/timer_provider.dart';
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
      final needsReload = queue != null && !_sourceMatchesQueue(player, queue);
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

    // A-1: wire up the AudioHandler's skip-to-next/previous callbacks.
    final handler = ref.read(audioHandlerProvider);
    if (handler != null) {
      handler.onSkipToNextRequested = _playNext;
      handler.onSkipToPreviousRequested = _playPrevious;
    }
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
    final queue = _container.read(currentPlayQueueProvider);
    if (queue != null) {
      final parentDir = _parentDir(queue.current.path);
      if (parentDir.isNotEmpty) {
        _container.invalidate(loadProgressForDirectoryProvider(parentDir));
      }
    }
    _timerExpiryChecker?.cancel();
    _container.read(cancelPlaybackSubscriptionsProvider)();
    WidgetsBinding.instance.removeObserver(this);

    final handler = _container.read(audioHandlerProvider);
    if (handler != null) {
      handler.onSkipToNextRequested = null;
      handler.onSkipToPreviousRequested = null;
    }

    super.dispose();
  }

  // ── Load & Play ────────────────────────────────────────────────────────

  /// Returns true when the player's loaded source URI matches [queue]'s current file.
  bool _sourceMatchesQueue(AudioPlayer player, PlayQueue queue) {
    final state = player.sequenceState;
    if (state == null) return false;
    final source = state.currentSource;
    if (source is UriAudioSource) {
      final decoded = Uri.decodeComponent(source.uri.path);
      return decoded.endsWith(queue.current.path);
    }
    return false;
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
        debugPrint('[Player] _runSerializedLoad: → superseded');
        _safeSetState(() {
          _loadState = PlayerLoadState.error('加载已被新的播放请求替换');
        });
      } else {
        debugPrint('[Player] _runSerializedLoad: → failed, checking reason');
        final activeConn = ref.read(activeConnectionProvider).valueOrNull;
        if (activeConn == null) {
          debugPrint('[Player] error: no active connection');
          _safeSetState(() {
            _loadState = PlayerLoadState.error('没有活跃的连接', isAuthError: true);
          });
          return;
        }
        final storage = ref.read(secureStorageProvider);
        final pw = await safeStorageRead(storage,
            key: 'connection_password_${activeConn.id}');
        if (pw == null || pw.isEmpty) {
          debugPrint('[Player] error: no password');
          _safeSetState(() {
            _loadState = PlayerLoadState.error('密码未保存', isAuthError: true);
          });
        } else {
          debugPrint('[Player] error: generic load failure');
          _safeSetState(() {
            _loadState = PlayerLoadState.error('加载失败');
          });
        }
      }
    } catch (e, st) {
      debugPrint('[Player] _runSerializedLoad: unexpected error $e\n$st');
      _safeSetState(() {
        _loadState = PlayerLoadState.error('加载失败');
      });
    }
  }

  String _parentDir(String filePath) {
    final idx = filePath.lastIndexOf('/');
    if (idx <= 0) return '/';
    return filePath.substring(0, idx);
  }

  Future<void> _retry() => _loadAndPlay();

  void _playNext() {
    unawaited(_runSerializedLoad(() => ref.read(skipToNextProvider)()));
  }

  void _playPrevious() {
    unawaited(_runSerializedLoad(() => ref.read(skipToPreviousProvider)()));
  }

  void _showQueueSheet(BuildContext context, PlayQueue queue) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => QueueSheet(
        queue: queue,
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
              QueueButton(onTap: () => _showQueueSheet(context, playQueue)),
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
                      Navigator.of(context).pop();
                      Navigator.of(context).pushNamed('/connection');
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
