// lib/shared/models/nas_file.dart
// Data model for NAS file / directory entries returned by WebDAV PROPFIND.

/// Audio file type classification used for display icons in the browser.
enum AudioFileType { music, audiobook }

/// Represents a file or directory entry on the NAS filesystem.
class NasFile {
  final String name;
  final String path;
  final bool isDirectory;
  final int? size; // bytes, null for directories
  final DateTime? modifiedAt;
  final AudioFileType? audioType; // music / audiobook / null for directories

  const NasFile({
    required this.name,
    required this.path,
    required this.isDirectory,
    this.size,
    this.modifiedAt,
    this.audioType,
  });

  // ── Supported audio extensions ────────────────────────────────────────────────

  static const supportedExtensions = {
    '.mp3',
    '.flac',
    '.aac',
    '.m4a',
    '.m4b',
    '.ogg',
    '.opus',
    '.wav',
  };

  // ── Audio file detection ──────────────────────────────────────────────────────

  /// Returns true when [filename] has a supported audio extension.
  static bool isAudioFile(String filename) {
    final lower = filename.toLowerCase();
    return supportedExtensions.any((ext) => lower.endsWith(ext));
  }

  /// Classifies an audio filename as [AudioFileType.music] or
  /// [AudioFileType.audiobook].
  ///
  /// .m4b files and files whose name contains "有声书" or "audiobook"
  /// are classified as audiobooks; everything else as music.
  static AudioFileType classifyType(String filename) {
    final lower = filename.toLowerCase();
    if (lower.endsWith('.m4b') ||
        lower.contains('有声书') ||
        lower.contains('audiobook')) {
      return AudioFileType.audiobook;
    }
    return AudioFileType.music;
  }

  // ── Factory: build from raw PROPFIND properties ───────────────────────────────

  /// Creates a [NasFile] from a parsed PROPFIND `<response>` entry.
  ///
  /// [href] is the URL-decoded path string from the `<href>` element.
  /// [props] is a map of property names (lowercase, no namespace) to their
  /// text content.  Recognised keys:
  ///   - `displayname`   → file/directory display name
  ///   - `getcontentlength` → file size in bytes (string of digits)
  ///   - `getlastmodified`  → RFC 1123 date string (e.g. "Mon, 01 Jan 2024 …")
  ///   - `resourcetype`    → contains `<collection` if directory
  ///
  /// When [displayname] is absent, the name is derived from the last segment
  /// of [href].
  factory NasFile.fromProps({
    required String href,
    required Map<String, String?> props,
  }) {
    // Decode URL-encoded characters in href (e.g. %20 → space)
    String decodedHref;
    try {
      decodedHref = Uri.decodeFull(href);
    } catch (_) {
      decodedHref = href;
    }

    // Strip trailing slash for directories so name extraction is consistent
    final cleanHref = decodedHref.endsWith('/') && decodedHref.length > 1
        ? decodedHref.substring(0, decodedHref.length - 1)
        : decodedHref;

    // Determine name
    final rawName = props['displayname'];
    final name = (rawName != null && rawName.isNotEmpty)
        ? rawName
        : cleanHref.split('/').last;

    // Determine if directory
    final resType = props['resourcetype'] ?? '';
    final isDirectory = resType.contains('collection');

    // Parse size
    int? size;
    final sizeStr = props['getcontentlength'];
    if (sizeStr != null) {
      size = int.tryParse(sizeStr);
    }

    // Parse modification date
    DateTime? modifiedAt;
    final dateStr = props['getlastmodified'];
    if (dateStr != null) {
      modifiedAt = _parseRfc1123(dateStr);
    }

    // Classify audio type
    final audioType =
        (!isDirectory && isAudioFile(name)) ? classifyType(name) : null;

    return NasFile(
      name: name,
      path: cleanHref,
      isDirectory: isDirectory,
      size: size,
      modifiedAt: modifiedAt,
      audioType: audioType,
    );
  }

  // ── Helpers ────────────────────────────────────────────────────────────────────

  /// Parses an RFC 1123 date string (e.g. "Mon, 01 Jan 2024 00:00:00 GMT")
  /// into a UTC [DateTime].  Returns `null` on parse failure.
  static DateTime? _parseRfc1123(String raw) {
    // Try standard HTTP-date format: "Mon, 01 Jan 2024 00:00:00 GMT"
    const months = {
      'jan': 1,
      'feb': 2,
      'mar': 3,
      'apr': 4,
      'may': 5,
      'jun': 6,
      'jul': 7,
      'aug': 8,
      'sep': 9,
      'oct': 10,
      'nov': 11,
      'dec': 12,
    };
    try {
      final parts = raw.trim().split(' ');
      if (parts.length >= 6) {
        // RFC 1123: day-of-week, day, month, year, time, GMT
        final day = int.parse(parts[1]);
        final month = months[parts[2].toLowerCase()]!;
        final year = int.parse(parts[3]);
        final timeParts = parts[4].split(':');
        final hour = int.parse(timeParts[0]);
        final minute = int.parse(timeParts[1]);
        final second = int.parse(timeParts[2]);
        return DateTime.utc(year, month, day, hour, minute, second);
      }
    } catch (_) {
      // Fall through to ISO 8601 attempt
    }
    // Fall back to ISO 8601 (e.g. "2024-01-01T00:00:00Z")
    try {
      return DateTime.parse(raw);
    } catch (_) {
      return null;
    }
  }

  // ── copyWith ──────────────────────────────────────────────────────────────────

  NasFile copyWith({
    String? name,
    String? path,
    bool? isDirectory,
    int? size,
    DateTime? modifiedAt,
    AudioFileType? audioType,
    bool clearSize = false,
    bool clearModifiedAt = false,
    bool clearAudioType = false,
  }) {
    return NasFile(
      name: name ?? this.name,
      path: path ?? this.path,
      isDirectory: isDirectory ?? this.isDirectory,
      size: clearSize ? null : (size ?? this.size),
      modifiedAt: clearModifiedAt ? null : (modifiedAt ?? this.modifiedAt),
      audioType: clearAudioType ? null : (audioType ?? this.audioType),
    );
  }

  @override
  String toString() =>
      'NasFile(name: $name, path: $path, isDirectory: $isDirectory, '
      'size: $size, audioType: $audioType)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NasFile &&
          name == other.name &&
          path == other.path &&
          isDirectory == other.isDirectory &&
          size == other.size &&
          audioType == other.audioType;

  @override
  int get hashCode => Object.hash(name, path, isDirectory, size, audioType);
}
