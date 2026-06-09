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

import 'domain/media_control.dart';

export 'domain/media_control.dart'
    show HeadphoneAction, MediaAction, mapHeadphoneAction, extractTitleFromPath;

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
