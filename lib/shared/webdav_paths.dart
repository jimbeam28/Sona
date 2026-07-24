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
