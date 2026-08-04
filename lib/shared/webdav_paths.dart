// lib/shared/webdav_paths.dart
// Pure-Dart helpers that resolve a WebDAV connection's on-server base path
// from its URL + basePath.
//
// NET1 background: historically `WebDavClient.validate` REPLACED the URL's own
// path with `basePath` while `WebDavClient.listDirectory` and
// `AudioSourceBuilder.buildWithBasePath` CONCATENATED the URL's own path and
// ignored `basePath` entirely. The two conventions contradicted each other, so
// whichever field a user put the mount point in (URL field vs "基础路径" field),
// the browse / playback path resolved a different location than validate
// probed — producing 404s and ghost directories.
//
// These helpers are the single source of truth for "what is the connection
// root on the server". Every HTTP-boundary consumer (validate / listDirectory
// / audio source) applies the base exactly once via the convention below.
//
// Convention
// ──────────
// * The connection root on the server is `url.path` joined with `basePath`
//   (see [resolveWebDavBasePath]). Either field may carry part of the mount
//   point; both are honoured and combined — neither is silently dropped.
// * `WebDavClient.validate` probes exactly that joined path.
// * `WebDavClient.listDirectory` / `AudioSourceBuilder.buildWithBasePath` are
//   "path-concatenating" consumers: they prepend the base URL's own path to
//   the relative path they receive. Callers therefore hand them the
//   *effective* base URL ([webDavEffectiveBaseUrl]) whose path already equals
//   the joined root, so the base is applied exactly once.
// * Paths returned by `listDirectory` (and thus navigation paths, queue
//   filePaths and audio filePaths) are RELATIVE to the connection root
//   (`/` = root); `listDirectory` strips the base from server hrefs.

/// Joins the URL's own path component ([urlPath]) with the configured
/// [basePath] into a single server-absolute base path.
///
/// The result always starts with `/` and never carries a trailing slash; the
/// connection root is returned as `/`.
///
/// ```dart
/// resolveWebDavBasePath('/dav', '/')      // → '/dav'   (mount point in URL)
/// resolveWebDavBasePath('', '/dav')       // → '/dav'   (mount point in basePath)
/// resolveWebDavBasePath('', '/')          // → '/'      (server root)
/// resolveWebDavBasePath('/dav', 'music')  // → '/dav/music'
/// ```
String resolveWebDavBasePath(String urlPath, String basePath) {
  String segment(String raw) {
    var s = raw.trim();
    if (s.isEmpty || s == '/') return '';
    if (!s.startsWith('/')) s = '/$s';
    while (s.length > 1 && s.endsWith('/')) {
      s = s.substring(0, s.length - 1);
    }
    return s; // '' or '/seg/seg'
  }

  final joined = '${segment(urlPath)}${segment(basePath)}';
  return joined.isEmpty ? '/' : joined;
}

/// Returns [url] with its path replaced by the effective connection root
/// (`url.path` joined with [basePath]).
///
/// Pass the result to the path-concatenating consumers
/// (`WebDavClient.listDirectory`, `AudioSourceBuilder.buildWithBasePath`) so
/// they apply the connection base exactly once, regardless of whether the
/// mount point lives in the URL field or the basePath field.
String webDavEffectiveBaseUrl(String url, String basePath) {
  final uri = Uri.parse(url);
  final effective = resolveWebDavBasePath(uri.path, basePath);
  return uri.replace(path: effective).toString();
}

/// Returns the server-absolute connection root for a stored connection
/// config pair, in the same (URL-decoded) form that persisted file paths
/// carry.
///
/// This is [resolveWebDavBasePath] applied to `Uri.parse(url).path` and
/// [basePath], then URL-decoded — mirroring how
/// `WebDavClient.listDirectory` decodes the base before stripping it from
/// server hrefs. Never throws: a malformed [url] degrades to an empty
/// `url.path`, and an undecodable result falls back to the encoded form.
///
/// Use the return value as the `basePath` argument of
/// [normalizeStoredPath] (cr-20260804-1922 O1).
String webDavConnectionRoot(String url, String basePath) {
  String root;
  try {
    root = resolveWebDavBasePath(Uri.parse(url).path, basePath);
  } catch (_) {
    root = resolveWebDavBasePath('', basePath);
  }
  try {
    return Uri.decodeFull(root);
  } catch (_) {
    return root;
  }
}

/// Normalises a persisted file path read back from legacy storage
/// (cr-20260804-1922 §5 O1).
///
/// Background: before NET1 (commit 431d444) `WebDavClient.listDirectory`
/// returned server-ABSOLUTE hrefs, so queues persisted to prefs,
/// `play_progress.file_path` and `playlist_tracks.file_path` rows written by
/// pre-NET1 builds carry the connection root as a prefix
/// (e.g. `/dav/music/a.mp3`). NET1 made every HTTP-boundary consumer apply
/// the base exactly once via [webDavEffectiveBaseUrl], so feeding those
/// legacy paths back into `listDirectory` / `buildWithBasePath` doubles the
/// prefix (`/dav/dav/music/a.mp3` → 404).
///
/// [basePath] is the server-absolute connection root of the connection the
/// stored path belongs to — compute it with [webDavConnectionRoot]. It is
/// normalised here (leading `/` ensured, trailing `/` stripped), so callers
/// may pass either form.
///
/// Semantics (identical to `WebDavClient._relativisePath`, so normalised
/// values are indistinguishable from current `listDirectory` output):
/// * root empty or `/` (server-root mount) → [stored] returned unchanged —
///   the legacy absolute form already equals the connection-root-relative
///   form;
/// * `stored == root` (a directory self-reference) → `/`;
/// * `stored` starts with `root + '/'` → the root prefix is stripped,
///   keeping the leading `/` (boundary-safe: root `/mus` never matches
///   `/music/...`);
/// * otherwise → [stored] returned unchanged (correct data is never
///   corrupted).
///
/// Idempotent for every unambiguous path: normalising twice equals
/// normalising once. The single remaining ambiguity is inherent to
/// read-time normalisation — a *relative* path whose first segment equals
/// the root's last segment (root `/dav`, relative `/dav/x.mp3`) is
/// indistinguishable from a legacy path without a server round-trip; no
/// stored data produced by this app is known to hit that case.
String normalizeStoredPath(String stored, {required String basePath}) {
  var root = basePath.trim();
  if (!root.startsWith('/')) root = '/$root';
  while (root.length > 1 && root.endsWith('/')) {
    root = root.substring(0, root.length - 1);
  }
  if (root == '/') return stored;
  if (stored == root) return '/';
  if (stored.startsWith('$root/')) return stored.substring(root.length);
  return stored;
}
