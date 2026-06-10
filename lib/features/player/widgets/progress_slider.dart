// lib/features/player/widgets/progress_slider.dart
// Progress bar with current position and total duration labels.
//
// Uses [AudioPlayer.positionStream] and [AudioPlayer.durationStream] for
// reactive updates.  Dragging the slider calls [AudioPlayer.seek] on release.
// PLY-T57~T58.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';

import '../domain/media_control.dart';
import '../player_provider.dart';

/// Progress bar with current position and total duration labels.
///
/// Uses [AudioPlayer.positionStream] and [AudioPlayer.durationStream] for
/// reactive updates.  Dragging the slider calls [AudioPlayer.seek] on release.
/// PLY-T57~T58.
class ProgressSlider extends ConsumerStatefulWidget {
  const ProgressSlider({super.key});

  @override
  ConsumerState<ProgressSlider> createState() => _ProgressSliderState();
}

class _ProgressSliderState extends ConsumerState<ProgressSlider> {
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
                    final wasCompleted =
                        player.processingState == ProcessingState.completed;
                    player.seek(Duration(milliseconds: v.round()));
                    if (wasCompleted) {
                      player.play();
                    }
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
