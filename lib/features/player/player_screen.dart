// lib/features/player/player_screen.dart
// Full player screen — PLY-01 音频流式播放.
//
// Reads the current play queue from [currentPlayQueueProvider], resolves
// WebDAV credentials from the active connection, builds a just_audio
// AudioSource with Basic Auth headers, loads it, and plays the audio
// stream.
//
// Handles loading, ready, and error states.  On auth errors (401) the
// user is prompted to check their connection credentials.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';

import '../../core/services/timer_service.dart';
import '../../shared/models/play_queue.dart';
import '../browser/browser_provider.dart';
import '../connection/connection_provider.dart';
import '../progress/progress_provider.dart';
import '../settings/settings_provider.dart';
import '../timer/timer_provider.dart';
import '../timer/widgets/timer_button.dart';
import 'player_provider.dart';
import 'widgets/queue_sheet.dart';

/// The full-screen audio player.
///
/// The screen is pushed via the `/player` route after the user taps an
/// audio file in the Browser (BRW-04).  It expects [currentPlayQueueProvider]
/// to be non-null.
class PlayerScreen extends ConsumerStatefulWidget {
  const PlayerScreen({super.key});

  @override
  ConsumerState<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends ConsumerState<PlayerScreen>
    with WidgetsBindingObserver {
  /// Tracks the source-load lifecycle: idle -> loading -> ready / error.
  PlayerLoadState _loadState = PlayerLoadState.idle;
  int _loadRequestToken = 0;
  late ProviderContainer _container;

  Timer? _timerExpiryChecker;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Defer the async load to the next frame so that build() runs first
    // and the loading spinner appears immediately.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final player = ref.read(audioPlayerProvider);
      final queue = ref.read(currentPlayQueueProvider);
      debugPrint(
        '[Player] postFrameCallback: queue=${queue?.current.path}, '
        'hasSource=${player.sequenceState != null}',
      );
      // Check if the player's loaded source still matches the current queue
      // entry.  When the user swipes back from the player and taps a different
      // song, the queue is updated but the player still holds the old source.
      final needsReload = queue != null && !_sourceMatchesQueue(player, queue);
      if (!needsReload &&
          (player.playing || player.processingState == ProcessingState.ready)) {
        debugPrint('[Player] skipping load — source matches and player ready');
        setState(() => _loadState = PlayerLoadState.ready);
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

  // ── PRG-01 trigger ④: save progress when app goes to background ───────────
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    debugPrint('[Player] lifecycle: $state');
    if (state == AppLifecycleState.paused) {
      _saveProgress();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _container = ProviderScope.containerOf(context);
  }

  @override
  void dispose() {
    // PRG-01 trigger ⑤: save progress on page destroy.
    _saveProgressWithContainer(_container);
    // E-1: invalidate the progress cache so the Browser sees the latest
    // position if the user taps the same file again after coming back.
    final queue = _container.read(currentPlayQueueProvider);
    if (queue != null) {
      final parentDir = _parentDir(queue.current.path);
      if (parentDir.isNotEmpty) {
        _container.invalidate(loadProgressForDirectoryProvider(parentDir));
      }
    }
    _timerExpiryChecker?.cancel();
    // D-1: cancel background listeners managed by providers.
    _container.read(cancelPlaybackSubscriptionsProvider)();
    WidgetsBinding.instance.removeObserver(this);

    // A-1: clear handler callbacks to prevent stale references.
    final handler = _container.read(audioHandlerProvider);
    if (handler != null) {
      handler.onSkipToNextRequested = null;
      handler.onSkipToPreviousRequested = null;
    }

    super.dispose();
  }

  // ── Load & Play ──────────────────────────────────────────────────────────────

  /// Returns true when the [player]'s currently loaded source URI contains
  /// [queue]'s current file path — i.e. the player hasn't drifted from the
  /// queue entry the UI is displaying.
  bool _sourceMatchesQueue(AudioPlayer player, PlayQueue queue) {
    final state = player.sequenceState;
    if (state == null) return false;
    final source = state.currentSource;
    if (source is UriAudioSource) {
      // I-7: use decoded-path comparison to avoid substring false matches
      // (e.g. /song.mp3 incorrectly matching /folder/song.mp3).
      final decoded = Uri.decodeComponent(source.uri.path);
      return decoded.endsWith(queue.current.path);
    }
    return false;
  }

  Future<void> _loadAndPlay() async {
    await _runSerializedLoad(() => ref.read(loadAndPlayProvider)());
  }

  /// Like [setState] but catches errors when the element is defunct despite
  /// [mounted] returning `true` — a known Flutter edge case during async
  /// callbacks after the widget is removed from the tree.
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

    debugPrint('[Player] _runSerializedLoad: setting loading, file=${queue.current.path}');
    _safeSetState(() => _loadState = PlayerLoadState.loading);
    final requestToken = ++_loadRequestToken;

    try {
      late final TrackLoadResult loaded;
      try {
        loaded = await request().timeout(const Duration(seconds: 15));
      } on TimeoutException {
        debugPrint('[Player] _runSerializedLoad: TIMEOUT token=$requestToken mounted=$mounted');
        if (!mounted || requestToken != _loadRequestToken) return;
        _safeSetState(() {
          _loadState = PlayerLoadState.error('加载超时，请重试');
        });
        return;
      }

      debugPrint('[Player] _runSerializedLoad: result=${loaded.status} token=$requestToken');
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
        final pw =
            await storage.read(key: 'connection_password_${activeConn.id}');
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

  /// Returns the parent directory path of [filePath], or '/' if at root.
  String _parentDir(String filePath) {
    final idx = filePath.lastIndexOf('/');
    if (idx <= 0) return '/';
    return filePath.substring(0, idx);
  }

  /// Retry loading after an error.
  Future<void> _retry() => _loadAndPlay();

  /// Advance to the next track based on the current play mode.
  void _playNext() {
    unawaited(_runSerializedLoad(() => ref.read(skipToNextProvider)()));
  }

  /// Skip to the previous track based on the current play mode.
  void _playPrevious() {
    unawaited(_runSerializedLoad(() => ref.read(skipToPreviousProvider)()));
  }

  // ── Queue sheet (B-2) ──────────────────────────────────────────────────

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

  // ── Progress auto-save (PRG-01) ─────────────────────────────────────────

  /// Saves the current playback position to the database.
  ///
  /// Guards against null queue, null connection, and missing connection id.
  /// Called from five trigger points:
  /// ① 10-second periodic timer, ② pause, ③ track change,
  /// ④ app background, ⑤ dispose.
  void _saveProgress() {
    _saveProgressWithContainer(_container);
  }

  void _saveProgressWithContainer(ProviderContainer container) {
    final queue = container.read(currentPlayQueueProvider);
    final conn = container.read(activeConnectionProvider).valueOrNull;
    if (queue == null || conn?.id == null) return;
    final player = container.read(audioPlayerProvider);
    container.read(upsertProgressProvider)(
      connectionId: conn!.id!,
      filePath: queue.current.path,
      positionMs: player.position.inMilliseconds,
      durationMs: player.duration?.inMilliseconds,
    );
  }

  // ── Build ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final queue = ref.watch(currentPlayQueueProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _loadState.status == PlayerLoadStatus.ready
              ? queue?.current.name ?? '播放器'
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

  // ── Loading ──────────────────────────────────────────────────────────────────

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

  // ── Ready / Playing ──────────────────────────────────────────────────────────

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
          const _NowPlayingIcon(),
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
              const _SpeedControl(),
              const _TimerControl(),
              const _PlayModeControl(),
              _QueueButton(onTap: () => _showQueueSheet(context, playQueue)),
            ],
          ),
          const SizedBox(height: 16),
          // Progress slider with integrated time display
          const _ProgressSlider(),
          const SizedBox(height: 16),
          // Playback controls: previous, skip back, play/pause, skip forward, next
          _PlaybackControls(
            onPrevious: _playPrevious,
            onNext: _playNext,
          ),
          const Spacer(),
        ],
      ),
    );
  }

  // ── Error ────────────────────────────────────────────────────────────────────

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

// ── Now Playing Icon ───────────────────────────────────────────────────────────

/// Animated music icon that pulses while playing.
class _NowPlayingIcon extends ConsumerWidget {
  const _NowPlayingIcon();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final player = ref.watch(audioPlayerProvider);

    return StreamBuilder<PlayerState>(
      stream: player.playerStateStream,
      builder: (context, snapshot) {
        final isPlaying = snapshot.data?.playing ?? false;
        return Icon(
          Icons.music_note,
          size: 120,
          color: isPlaying
              ? Theme.of(context).colorScheme.primary
              : Colors.grey[400],
        );
      },
    );
  }
}

// ── Progress Slider ────────────────────────────────────────────────────────────

/// Progress bar with current position and total duration labels.
///
/// Uses [AudioPlayer.positionStream] and [AudioPlayer.durationStream] for
/// reactive updates.  Dragging the slider calls [AudioPlayer.seek] on release.
/// PLY-T57~T58.
class _ProgressSlider extends ConsumerStatefulWidget {
  const _ProgressSlider();

  @override
  ConsumerState<_ProgressSlider> createState() => _ProgressSliderState();
}

class _ProgressSliderState extends ConsumerState<_ProgressSlider> {
  /// Whether the user is currently dragging the slider.
  bool _isDragging = false;

  /// Temporary position used while dragging to avoid position-stream jitter.
  double _dragValue = 0;

  @override
  Widget build(BuildContext context) {
    final player = ref.watch(audioPlayerProvider);

    return Column(
      children: [
        // Slider
        StreamBuilder<Duration>(
          stream: player.positionStream,
          builder: (context, posSnapshot) {
            final position = posSnapshot.data ?? Duration.zero;

            return StreamBuilder<Duration?>(
              stream: player.durationStream,
              builder: (context, durSnapshot) {
                final duration = durSnapshot.data;
                if (duration == null || duration == Duration.zero) {
                  return const Slider(
                    value: 0,
                    onChanged: null, // disabled until we know the duration
                  );
                }

                final maxMs = duration.inMilliseconds.toDouble();
                final rawValue = _isDragging
                    ? _dragValue
                    : position.inMilliseconds.toDouble().clamp(0, maxMs);
                final double value = rawValue.toDouble();

                return Slider(
                  value: value,
                  min: 0,
                  max: maxMs,
                  onChanged: (v) {
                    setState(() {
                      _isDragging = true;
                      _dragValue = v;
                    });
                  },
                  onChangeEnd: (v) {
                    setState(() => _isDragging = false);
                    player.seek(Duration(milliseconds: v.round()));
                  },
                );
              },
            );
          },
        ),
        // Time labels
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            StreamBuilder<Duration>(
              stream: player.positionStream,
              builder: (context, snapshot) {
                return Text(
                  formatDuration(snapshot.data ?? Duration.zero),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                );
              },
            ),
            StreamBuilder<Duration?>(
              stream: player.durationStream,
              builder: (context, snapshot) {
                return Text(
                  formatDuration(snapshot.data),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                );
              },
            ),
          ],
        ),
      ],
    );
  }
}

// ── Playback Controls ──────────────────────────────────────────────────────────

/// Row of playback controls: previous, skip backward, play/pause, skip forward, next.
/// PLY-T55~T56.
class _PlaybackControls extends ConsumerWidget {
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  const _PlaybackControls({
    this.onPrevious,
    this.onNext,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final player = ref.watch(audioPlayerProvider);
    final seekStep = ref.watch(seekStepProvider);
    final queue = ref.watch(currentPlayQueueProvider);
    final mode = ref.watch(playModeProvider);

    final prevIdx = queue != null
        ? PlayQueue.previousIndex(queue.currentIndex, queue.length, mode)
        : null;
    final nextIdx = queue != null
        ? PlayQueue.nextIndex(queue.currentIndex, queue.length, mode)
        : null;

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // Previous track
        _buildSkipButton(
          icon: Icons.skip_previous,
          tooltip: '上一首',
          enabled: prevIdx != null,
          onPressed: prevIdx != null ? onPrevious : null,
        ),
        const SizedBox(width: 8),
        // Skip backward
        _buildSeekButton(
          seconds: seekStep,
          tooltip: '后退 ${seekStep}s',
          onPressed: () {
            final position = player.position;
            final skipTarget = skipBackward(position, seconds: seekStep);
            player.seek(skipTarget);
          },
        ),
        const SizedBox(width: 24),
        // Play / Pause
        StreamBuilder<PlayerState>(
          stream: player.playerStateStream,
          builder: (context, snapshot) {
            final isPlaying = snapshot.data?.playing ?? false;
            return IconButton.filled(
              onPressed: () {
                if (isPlaying) {
                  player.pause();
                } else {
                  player.play();
                }
              },
              iconSize: 64,
              icon: Icon(isPlaying ? Icons.pause : Icons.play_arrow),
              style: IconButton.styleFrom(
                minimumSize: const Size(80, 80),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(40),
                ),
              ),
            );
          },
        ),
        const SizedBox(width: 24),
        // Skip forward
        _buildSeekButton(
          seconds: seekStep,
          tooltip: '前进 ${seekStep}s',
          isForward: true,
          onPressed: () {
            final position = player.position;
            final duration = player.duration ?? Duration.zero;
            final skipTarget =
                skipForward(position, duration, seconds: seekStep);
            player.seek(skipTarget);
          },
        ),
        const SizedBox(width: 8),
        // Next track
        _buildSkipButton(
          icon: Icons.skip_next,
          tooltip: '下一首',
          enabled: nextIdx != null,
          onPressed: nextIdx != null ? onNext : null,
        ),
      ],
    );
  }

  Widget _buildSeekButton({
    required int seconds,
    String? tooltip,
    bool enabled = true,
    bool isForward = false,
    VoidCallback? onPressed,
  }) {
    return InkWell(
      onTap: enabled ? onPressed : null,
      borderRadius: BorderRadius.circular(24),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildSeekIcon(
              seconds: seconds,
              isForward: isForward,
              enabled: enabled,
            ),
            Text(
              '${seconds}s',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: enabled ? null : Colors.grey,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSeekIcon({
    required int seconds,
    required bool isForward,
    required bool enabled,
  }) {
    final color = enabled ? null : Colors.grey;
    final icon = Icon(Icons.replay, size: 28, color: color);

    if (isForward) {
      return Transform(
        alignment: Alignment.center,
        transform: Matrix4.diagonal3Values(-1, 1, 1),
        child: icon,
      );
    }

    return icon;
  }

  Widget _buildSkipButton({
    required IconData icon,
    String? tooltip,
    bool enabled = true,
    VoidCallback? onPressed,
  }) {
    return IconButton(
      onPressed: onPressed,
      iconSize: 36,
      icon: Icon(icon),
      tooltip: tooltip,
      color: enabled ? null : Colors.grey,
      disabledColor: Colors.grey,
    );
  }
}

// ── Speed Control ──────────────────────────────────────────────────────────────

/// Speed display button with speed selector dialog.
/// PLY-T17.
class _SpeedControl extends ConsumerWidget {
  const _SpeedControl();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final player = ref.watch(audioPlayerProvider);

    return StreamBuilder<double>(
      stream: player.speedStream,
      builder: (context, snapshot) {
        final currentSpeed = snapshot.data ?? 1.0;

        return OutlinedButton.icon(
          onPressed: () =>
              _showSpeedSelector(context, ref, player, currentSpeed),
          icon: const Icon(Icons.speed, size: 20),
          label: Text('${currentSpeed}x'),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          ),
        );
      },
    );
  }

  void _showSpeedSelector(
    BuildContext context,
    WidgetRef ref,
    AudioPlayer player,
    double currentSpeed,
  ) {
    showModalBottomSheet<double>(
      context: context,
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  '播放速度',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const Divider(height: 1),
              ...speedOptions.map((speed) {
                final isSelected = (speed - currentSpeed).abs() < 0.01;
                return ListTile(
                  leading: isSelected
                      ? Icon(Icons.check,
                          color: Theme.of(context).colorScheme.primary)
                      : const SizedBox(width: 24),
                  title: Text('${speed}x'),
                  trailing: isSelected
                      ? Text('当前',
                          style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(context).colorScheme.primary,
                          ))
                      : null,
                  onTap: () {
                    player.setSpeed(speed);
                    ref.read(currentSpeedProvider.notifier).state = speed;
                    // F-4: if "remember speed" is on, update the default too.
                    if (ref.read(rememberSpeedProvider)) {
                      ref.read(setDefaultSpeedProvider)(speed);
                    }
                    Navigator.of(ctx).pop();
                  },
                );
              }),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }
}

// ── Play Mode Control (PLY-06) ──────────────────────────────────────────────────

/// Play mode toggle button that cycles through modes and shows the
/// corresponding icon.
///
/// Modes cycle: sequential → repeatOne → repeatAll → shuffle → sequential …
class _PlayModeControl extends ConsumerWidget {
  const _PlayModeControl();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(playModeProvider);
    final nextMode = ref.watch(nextPlayModeProvider);

    return IconButton(
      onPressed: nextMode,
      icon: Icon(iconForPlayMode(mode)),
      iconSize: 20,
      tooltip: labelForPlayMode(mode),
      visualDensity: VisualDensity.compact,
    );
  }
}

// ── Queue button ──────────────────────────────────────────────────────────────

class _QueueButton extends StatelessWidget {
  final VoidCallback onTap;

  const _QueueButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onTap,
      icon: const Icon(Icons.queue_music),
      iconSize: 20,
      tooltip: '播放列表',
      visualDensity: VisualDensity.compact,
    );
  }
}

// ── Timer control ───────────────────────────────────────────────────────────

class _TimerControl extends ConsumerWidget {
  const _TimerControl();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(timerStateProvider);
    final isActive = state != null;
    final isAfterCurrent = state?.mode == TimerMode.afterCurrent;

    String? displayText;
    if (isAfterCurrent) {
      displayText = TimerService.afterCurrentLabel;
    } else if (isActive) {
      displayText = ref.watch(formattedRemainingProvider);
    }

    if (isActive && displayText != null) {
      return TextButton.icon(
        onPressed: () => _showTimerSheet(context, true),
        icon: Icon(Icons.timer, size: 18,
            color: Theme.of(context).colorScheme.primary),
        label: Text(
          displayText,
          style: TextStyle(
            fontFamily: 'monospace',
            fontSize: 13,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      );
    }

    return IconButton(
      onPressed: () => _showTimerSheet(context, false),
      icon: const Icon(Icons.timer),
      iconSize: 20,
      tooltip: '定时停止',
      visualDensity: VisualDensity.compact,
    );
  }

  void _showTimerSheet(BuildContext context, bool isActive) {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => TimerBottomSheet(isActive: isActive),
    );
  }
}
