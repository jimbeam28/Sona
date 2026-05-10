// lib/features/player/media_control_model.dart
// Lock screen and notification media control models for PLY-04.
//
// Provides pure-logic enums and functions for headphone button mapping,
// notification title extraction, and cover-art display decisions.
// These are fully testable without audio_service, platform channels,
// or native ID3 tag readers.
//
// The actual audio_service wiring (Android foreground service,
// MediaSession callbacks) lives in lib/core/services/audio_handler.dart;
// this module defines the application-level logic that gates those
// behaviours.

import 'package:meta/meta.dart';

// ── Enums ───────────────────────────────────────────────────────────────────────

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
/// These correspond to the standard [BaseAudioHandler] methods that
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

// ── Headphone click mapping ─────────────────────────────────────────────────────

/// Maps a headphone button click action to the corresponding [MediaAction].
///
/// Per the PLY-04 design spec (docs/module-player.md §3.4):
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

// ── Title extraction ────────────────────────────────────────────────────────────

/// Extracts the display title from a file path by taking the last path
/// segment and stripping the file extension.
///
/// This produces the [MediaItem.title] value displayed in the notification
/// and lock-screen controls (PLY-T24).
///
/// Examples:
/// ```dart
/// extractTitleFromPath('/music/01 - Song.mp3')    // → '01 - Song'
/// extractTitleFromPath('/music/有声书.m4b')       // → '有声书'
/// extractTitleFromPath('README')                   // → 'README'
/// extractTitleFromPath('/a/b/c.tar.gz')            // → 'c.tar'
/// extractTitleFromPath('')                         // → ''
/// ```
String extractTitleFromPath(String filePath) {
  final name = filePath.split('/').last;
  final dotIndex = name.lastIndexOf('.');
  if (dotIndex <= 0) return name;
  return name.substring(0, dotIndex);
}

// ── Track metadata for notification / lock screen ───────────────────────────────

/// Immutable value object holding the metadata needed to render the
/// notification and lock-screen media controls.
///
/// The actual ID3 tag reading is performed by a native plugin or the
/// dart metadata package at the I/O boundary; this class models the
/// *decision logic* once the cover-availability flag is known.
///
///   - [hasId3Cover] == true  → notification shows the cover image (PLY-T28)
///   - [hasId3Cover] == false → notification shows the default app icon (PLY-T29)
@immutable
class TrackMetadata {
  /// The full file path (used internally for reference).
  final String filePath;

  /// Whether the file contains an ID3 cover-art tag.
  final bool hasId3Cover;

  const TrackMetadata({
    required this.filePath,
    required this.hasId3Cover,
  });

  // ── Derived properties ────────────────────────────────────────────────────

  /// The display title shown in the notification.
  ///
  /// This is the filename without its extension, i.e. the result of
  /// [extractTitleFromPath] on [filePath].
  String get title => extractTitleFromPath(filePath);

  /// Whether the notification should display the track's cover art.
  ///
  /// True when the file has an embedded ID3 cover image (PLY-T28).
  bool get showCover => hasId3Cover;

  /// Whether the notification should display the default application icon.
  ///
  /// True when no ID3 cover art is available (PLY-T29).
  bool get showDefaultIcon => !hasId3Cover;

  // ── copyWith ──────────────────────────────────────────────────────────────

  TrackMetadata copyWith({
    String? filePath,
    bool? hasId3Cover,
  }) {
    return TrackMetadata(
      filePath: filePath ?? this.filePath,
      hasId3Cover: hasId3Cover ?? this.hasId3Cover,
    );
  }

  // ── Equality ──────────────────────────────────────────────────────────────

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TrackMetadata &&
          filePath == other.filePath &&
          hasId3Cover == other.hasId3Cover;

  @override
  int get hashCode => Object.hash(filePath, hasId3Cover);

  @override
  String toString() =>
      'TrackMetadata(filePath: $filePath, hasId3Cover: $hasId3Cover, '
      'title: $title, showCover: $showCover)';
}
