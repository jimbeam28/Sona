// lib/core/services/download_filename_policy.dart
// Pure filename sanitisation / collision resolution for DL-01 offline
// downloads.
//
// Zero dart:io — file-existence probing is injected via [resolveCollision]'s
// existsProbe parameter so the strategy stays unit-testable and reusable from
// both the core engine and the feature layer.
//
// The nine illegal filename characters are replaced with a conditional
// split+map mapping (spec §3.3 S4 forbids literal regexes here to avoid
// escaping bugs).

/// Hard cap for a downloaded file's base name; the last path segment's
/// extension is always preserved across truncation.
const int kMaxDownloadBaseNameLength = 120;

const Set<String> _illegalFilenameChars = {
  '\\',
  '/',
  ':',
  '*',
  '?',
  '"',
  '<',
  '>',
  '|',
};

bool _isIllegalFilenameChar(String ch) => _illegalFilenameChars.contains(ch);

bool _isDotOnly(String s) => s.split('').every(_isDot);

bool _isDot(String ch) => ch == '.';

/// Reduces [filePath] to a safe local base name:
///
/// 1. basename extraction (last `/` segment);
/// 2. each of the nine illegal characters `\ / : * ? " < > |` becomes `_`
///    (split+map, no pattern literals);
/// 3. an empty or all-dots result is replaced wholesale by `file`;
/// 4. names longer than 120 chars are truncated to exactly 120 while keeping
///    the extension that follows the LAST `.` (stem 116 + `.mp3` style).
///
/// The result never contains a path separator, so directory-traversal inputs
/// collapse to flat file names.
String sanitizeBaseName(String filePath) {
  var base = filePath.split('/').last;
  base =
      base.split('').map((ch) => _isIllegalFilenameChar(ch) ? '_' : ch).join();

  if (base.isEmpty || _isDotOnly(base)) {
    return 'file';
  }

  if (base.length > kMaxDownloadBaseNameLength) {
    final dotIndex = base.lastIndexOf('.');
    if (dotIndex > 0) {
      final ext = base.substring(dotIndex);
      final stemKeep =
          (kMaxDownloadBaseNameLength - ext.length).clamp(0, dotIndex);
      base = base.substring(0, stemKeep) + ext;
    } else {
      base = base.substring(0, kMaxDownloadBaseNameLength);
    }
  }
  return base;
}

/// Returns a non-existing name inside [finalDir] for [baseName].
///
/// [existsProbe] receives BARE candidate file names (`song.mp3`, `song_2.mp3`,
/// …) and reports whether the candidate already exists; callers join it with
/// [finalDir] themselves. With no conflict [baseName] is returned unchanged
/// and the probe is called exactly once. On conflict the suffix `_2`..`_999`
/// is inserted BEFORE the extension (the segment following the LAST `.`).
/// Exhausting all 998 suffixed candidates throws [StateError] (defensive
/// branch — never expected in practice).
String resolveCollision(
  String finalDir,
  String baseName,
  bool Function(String candidateName) existsProbe,
) {
  if (!existsProbe(baseName)) {
    return baseName;
  }
  final dotIndex = baseName.lastIndexOf('.');
  final stem = dotIndex > 0 ? baseName.substring(0, dotIndex) : baseName;
  final ext = dotIndex > 0 ? baseName.substring(dotIndex) : '';
  for (var n = 2; n <= 999; n++) {
    final candidate = '${stem}_$n$ext';
    if (!existsProbe(candidate)) {
      return candidate;
    }
  }
  throw StateError(
      'resolveCollision exhausted _2.._999 for "$baseName" in "$finalDir"');
}
