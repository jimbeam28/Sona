// lib/shared/media_title.dart
// Pure-string helper for deriving display titles from file paths.
//
// Moved from lib/features/player/domain/media_control.dart (REF-09):
// the core layer (audio_handler) consumes this helper, so it must live in
// the shared layer to keep core→feature dependency direction clean.  Zero
// Flutter dependencies.

/// Extracts the display title from a file path by taking the last path
/// segment and stripping the file extension.
///
/// This produces the title value displayed in the notification and
/// lock-screen controls (PLY-T24).
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
