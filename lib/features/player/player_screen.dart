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

import '../../core/network/webdav_client.dart';
import '../../core/services/audio_source_builder.dart';
import '../../shared/models/play_queue.dart';
import '../browser/browser_provider.dart';
import '../connection/connection_provider.dart';
import '../progress/progress_provider.dart';
import '../timer/timer_provider.dart';
import 'player_provider.dart';

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

  Timer? _timerExpiryChecker;
  StreamSubscription? _processingSubscription;
  Timer? _autoSaveTimer;
  StreamSubscription? _playerStateSubscription;
  bool _wasPlaying = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Defer the async load to the next frame so that build() runs first
    // and the loading spinner appears immediately.
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadAndPlay());

    // TMR-05: check for duration-timer expiry every second.
    _timerExpiryChecker = Timer.periodic(const Duration(seconds: 1), (_) {
      final expired = ref.read(checkTimerExpiryProvider)();
      if (expired && mounted) {
        final player = ref.read(audioPlayerProvider);
        player.pause();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('定时停止已触发')),
        );
      }
    });
  }

  // ── PRG-01 trigger ④: save progress when app goes to background ───────────
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _saveProgress();
    }
  }

  @override
  void dispose() {
    // PRG-01 trigger ⑤: save progress on page destroy.
    _saveProgress();
    _timerExpiryChecker?.cancel();
    _processingSubscription?.cancel();
    _autoSaveTimer?.cancel();
    _playerStateSubscription?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // ── Load & Play ──────────────────────────────────────────────────────────────

  Future<void> _loadAndPlay() async {
    final queue = ref.read(currentPlayQueueProvider);
    if (queue == null || queue.length == 0) {
      setState(() {
        _loadState = PlayerLoadState.error('没有选择播放文件');
      });
      return;
    }

    setState(() => _loadState = PlayerLoadState.loading);

    try {
      // 1. Resolve active connection
      final activeConn = await ref.read(activeConnectionProvider.future);
      if (activeConn == null) {
        setState(() {
          _loadState = PlayerLoadState.error('没有活跃的连接',
              isAuthError: true);
        });
        return;
      }

      // 2. Read password from secure storage
      final storage = ref.read(secureStorageProvider);
      final password =
          await storage.read(key: 'connection_password_${activeConn.id}');
      if (password == null || password.isEmpty) {
        setState(() {
          _loadState = PlayerLoadState.error('密码未保存',
              isAuthError: true);
        });
        return;
      }

      // 3. Build the AudioSource with Basic Auth
      final source = AudioSourceBuilder.build(
        baseUrl: activeConn.url,
        filePath: queue.current.path,
        username: activeConn.username,
        password: password,
      );

      // 4. Load into the player
      final player = ref.read(audioPlayerProvider);
      await player.setAudioSource(source);

      // 5. Seek to resume position if present
      if (queue.startPositionMs != null) {
        await player.seek(Duration(milliseconds: queue.startPositionMs!));
      }

      setState(() => _loadState = PlayerLoadState.ready);

      // 6. Start playback
      await player.play();

      // TMR-02: listen for track completion to trigger "stop after current".
      await _processingSubscription?.cancel();
      _processingSubscription = player.processingStateStream.listen((state) {
        if (state == ProcessingState.completed) {
          final triggered = ref.read(onTrackCompletedProvider)();
          if (triggered) {
            player.pause();
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('定时停止已触发')),
              );
            }
          } else {
            _playNext();
          }
        }
      });

      // PRG-01 trigger ①: auto-save progress every 10 seconds.
      _autoSaveTimer?.cancel();
      _autoSaveTimer = Timer.periodic(const Duration(seconds: 10), (_) {
        _saveProgress();
      });

      // PRG-01 trigger ②: save progress immediately on pause.
      _wasPlaying = true;
      await _playerStateSubscription?.cancel();
      _playerStateSubscription = player.playerStateStream.listen((state) {
        final playing = state.playing;
        if (_wasPlaying && !playing) {
          _saveProgress();
        }
        _wasPlaying = playing;
      });
    } on WebDavException catch (e) {
      setState(() {
        _loadState = PlayerLoadState.error(
          e.message,
          isAuthError: e.isAuthError,
        );
      });
    } catch (e) {
      setState(() {
        _loadState = PlayerLoadState.error('加载失败: $e');
      });
    }
  }

  /// Retry loading after an error.
  Future<void> _retry() => _loadAndPlay();

  /// Advance to the next track based on the current play mode.
  void _playNext() {
    final queue = ref.read(currentPlayQueueProvider);
    final mode = ref.read(playModeProvider);
    if (queue == null) return;
    final nextIdx = PlayQueue.nextIndex(queue.currentIndex, queue.length, mode);
    if (nextIdx == null) return;
    // PRG-01 trigger ③: save current progress before switching tracks.
    _saveProgress();
    final nextQueue = queue.withIndex(nextIdx);
    ref.read(currentPlayQueueProvider.notifier).state = nextQueue;
    _loadAndPlay();
  }

  /// Skip to the previous track based on the current play mode.
  void _playPrevious() {
    final queue = ref.read(currentPlayQueueProvider);
    final mode = ref.read(playModeProvider);
    if (queue == null) return;
    final prevIdx =
        PlayQueue.previousIndex(queue.currentIndex, queue.length, mode);
    if (prevIdx == null) return;
    _saveProgress();
    final prevQueue = queue.withIndex(prevIdx);
    ref.read(currentPlayQueueProvider.notifier).state = prevQueue;
    _loadAndPlay();
  }

  // ── Progress auto-save (PRG-01) ─────────────────────────────────────────

  /// Saves the current playback position to the database.
  ///
  /// Guards against null queue, null connection, and missing connection id.
  /// Called from five trigger points:
  /// ① 10-second periodic timer, ② pause, ③ track change,
  /// ④ app background, ⑤ dispose.
  void _saveProgress() {
    final queue = ref.read(currentPlayQueueProvider);
    final conn = ref.read(activeConnectionProvider).valueOrNull;
    if (queue == null || conn?.id == null) return;
    final player = ref.read(audioPlayerProvider);
    ref.read(upsertProgressProvider)(
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
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: const [
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
          const SizedBox(height: 24),
          // Progress slider with integrated time display
          const _ProgressSlider(),
          const SizedBox(height: 16),
          // Playback controls: previous, skip back, play/pause, skip forward, next
          _PlaybackControls(
            onPrevious: _playPrevious,
            onNext: _playNext,
          ),
          const SizedBox(height: 16),
          // Speed control
          const _SpeedControl(),
          const SizedBox(height: 16),
          const _PlayModeControl(),
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
  const _NowPlayingIcon({super.key});

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

  const _PlaybackControls({this.onPrevious, this.onNext});

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
        _buildSkipButton(
          icon: Icons.replay_10,
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
        _buildSkipButton(
          icon: Icons.forward_30,
          tooltip: '前进 ${seekStep}s',
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
          onPressed: () => _showSpeedSelector(context, player, currentSpeed),
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

    return OutlinedButton.icon(
      onPressed: nextMode,
      icon: Icon(iconForPlayMode(mode), size: 20),
      label: Text(labelForPlayMode(mode)),
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      ),
    );
  }
}
