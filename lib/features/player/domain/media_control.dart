// lib/features/player/domain/media_control.dart
// REF-12: Pure-Dart media control helpers extracted from
// media_control_model.dart and player_provider.dart.
//
// Contains:
//   - extractTitleFromPath()  — file path → display title (re-exported from
//     shared/media_title.dart, REF-09)
//   - mapHeadphoneAction()    — HeadphoneAction → MediaAction
//   - formatDuration()        — Duration → "MM:SS" / "H:MM:SS"
//
// Zero Flutter dependencies — fully testable in plain Dart.

export '../../../shared/media_title.dart' show extractTitleFromPath;

/// Headphone / headset button click actions.
///
/// These are the physical button interactions that the OS delivers as
/// media-key events.  The mapping to [MediaAction] is defined by
/// [mapHeadphoneAction].
enum HeadphoneAction {
  /// Single press on the headphone button.
  singleClick,

  /// Double press (two clicks in quick succession).
  doubleClick,

  /// Triple press (three clicks in quick succession).
  tripleClick,
}

/// High-level media actions triggered by headphone clicks or notification
/// controls.
///
/// These correspond to the standard BaseAudioHandler methods that
/// audio_service expects:
///   - [togglePlayPause] → play() / pause()
///   - [skipToNext]       → skipToNext()
///   - [skipToPrevious]   → skipToPrevious()
enum MediaAction {
  /// Toggle between play and pause.
  togglePlayPause,

  /// Skip to the next track in the queue.
  skipToNext,

  /// Skip to the previous track in the queue.
  skipToPrevious,
}

/// Maps a headphone button click action to the corresponding [MediaAction].
///
/// Per the PLY-04 design spec (docs/module-player.md section 3.4):
///   - Single click  → play/pause toggle
///   - Double click  → skip to next
///   - Triple click  → skip to previous
MediaAction mapHeadphoneAction(HeadphoneAction action) {
  switch (action) {
    case HeadphoneAction.singleClick:
      return MediaAction.togglePlayPause;
    case HeadphoneAction.doubleClick:
      return MediaAction.skipToNext;
    case HeadphoneAction.tripleClick:
      return MediaAction.skipToPrevious;
  }
}

/// Formats a [Duration] as a human-readable timestamp.
///
/// - Durations under 1 hour: `MM:SS` (e.g. `05:30`)
/// - Durations 1 hour or more: `H:MM:SS` (e.g. `1:23:45`)
/// - Null: `--:--`
String formatDuration(Duration? duration) {
  if (duration == null) return '--:--';
  final totalSeconds = duration.inSeconds;
  final hours = totalSeconds ~/ 3600;
  final minutes = (totalSeconds % 3600) ~/ 60;
  final seconds = totalSeconds % 60;

  final mm = minutes.toString().padLeft(2, '0');
  final ss = seconds.toString().padLeft(2, '0');

  if (hours > 0) {
    return '$hours:$mm:$ss';
  }
  return '$mm:$ss';
}
