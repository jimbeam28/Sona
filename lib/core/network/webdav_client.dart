// lib/core/network/webdav_client.dart
// WebDAV client: validates connectivity by issuing a PROPFIND request,
// and lists directory contents via PROPFIND Depth:1.
// Uses the `http` package directly so we control the method/timeout.

import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../../shared/models/nas_file.dart';
import '../../shared/webdav_paths.dart';

// ── Validation result ─────────────────────────────────────────────────────────

enum WebDavValidationStatus { success, authError, pathNotFound, networkError }

class WebDavValidationResult {
  final WebDavValidationStatus status;
  final String? message; // null when status == success

  const WebDavValidationResult._(this.status, this.message);

  factory WebDavValidationResult.success() =>
      const WebDavValidationResult._(WebDavValidationStatus.success, null);

  factory WebDavValidationResult.authError() => const WebDavValidationResult._(
      WebDavValidationStatus.authError, '用户名或密码错误');

  factory WebDavValidationResult.pathNotFound() =>
      const WebDavValidationResult._(
          WebDavValidationStatus.pathNotFound, '基础路径不存在，请检查路径设置');

  factory WebDavValidationResult.networkError() =>
      const WebDavValidationResult._(
          WebDavValidationStatus.networkError, '无法连接到服务器，请检查地址和网络');

  bool get isSuccess => status == WebDavValidationStatus.success;
}

// ── URL normalisation ─────────────────────────────────────────────────────────

/// Ensures the URL has an http/https scheme and a port number.
///
/// If the user typed a bare IP / hostname (no scheme) we prepend `http://`.
/// If no port is specified, defaults to 5005 (the standard WebDAV port
/// used by many NAS devices).
String normaliseWebDavUrl(String raw) {
  final trimmed = raw.trim();
  String url;
  if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
    url = trimmed;
  } else {
    url = 'http://$trimmed';
  }
  try {
    final uri = Uri.parse(url);
    if (!uri.hasPort && uri.host.isNotEmpty) {
      return uri.replace(port: 5005).toString();
    }
    return url;
  } catch (_) {
    return url;
  }
}

/// Returns true when [url] is a syntactically valid http/https URL with a host.
bool isValidWebDavUrl(String url) {
  try {
    final uri = Uri.parse(url);
    return (uri.scheme == 'http' || uri.scheme == 'https') &&
        uri.host.isNotEmpty;
  } catch (_) {
    return false;
  }
}

/// Matches the `user:password@` userinfo segment between a URL scheme (`://`)
/// and its host. Userinfo can never contain `/`, `?`, `#` or `@`, so an `@`
/// appearing later (e.g. in a path like `/music/a@b.mp3`) is never mistaken
/// for userinfo.
final _urlUserInfoPattern = RegExp(r'(://)[^/?#@]+@');

/// Returns [raw] with any embedded `…://user:password@` userinfo stripped,
/// for safe use in log messages and error text (CON2/NET7).
///
/// Defence in depth: [validateUrl] rejects userinfo URLs at the form gate,
/// but log sites must never leak credentials even if a URL carrying userinfo
/// reaches them anyway — e.g. a legacy DB row read back at startup, a direct
/// client call bypassing the form, or an exception message echoing the
/// request uri. Strings without userinfo are returned unchanged, so normal
/// URL storage/display behaviour is unaffected.
String redactUrlForLog(String raw) =>
    raw.replaceAllMapped(_urlUserInfoPattern, (m) => m[1]!);

// ── Abstract interface ────────────────────────────────────────────────────────

/// Base-path convention (NET1) — shared by [validate] and [listDirectory]:
///
/// The connection root on the server is `url.path` joined with `basePath`
/// (see `resolveWebDavBasePath` in `shared/webdav_paths.dart`). The mount
/// point may live in the URL field or in [validate]'s `basePath` — both are
/// honoured and combined, so [validate] and [listDirectory] always resolve the
/// same location.
///
/// * [validate] probes exactly that joined path.
/// * [listDirectory] is a *path-concatenating* consumer: it prepends `url`'s
///   own path to [listDirectory]'s `path` argument. Callers must therefore
///   pass the *effective* base URL (`webDavEffectiveBaseUrl(url, basePath)`)
///   so the base is applied exactly once. `path` is RELATIVE to the connection
///   root (`/` = root), and the returned `NasFile.path` values are likewise
///   relative (the client strips the base from server hrefs) — so navigation
///   and audio filePaths never re-apply the base.
abstract class WebDavClientInterface {
  /// Validates the WebDAV endpoint by sending a PROPFIND request.
  ///
  /// Probes `url.path` joined with [basePath] (the connection root), so the
  /// location validated is the same one [listDirectory] lists from.
  Future<WebDavValidationResult> validate({
    required String url,
    required String username,
    required String password,
    String basePath = '/',
  });

  /// Lists directory contents via PROPFIND (Depth: 1).
  ///
  /// [url] must be the *effective* base URL
  /// (`webDavEffectiveBaseUrl(conn.url, conn.basePath)`); its path component is
  /// the connection root and is prepended to [path]. [path] is RELATIVE to the
  /// connection root (`/` = root).
  ///
  /// Throws [WebDavException] on auth failures (401) or network errors.
  /// Returns all entries (including the directory self-reference) with
  /// `NasFile.path` RELATIVE to the connection root (the base is stripped from
  /// server hrefs) — the caller is responsible for filtering and sorting.
  Future<List<NasFile>> listDirectory({
    required String url,
    required String username,
    required String password,
    required String path,
  });
}

/// Exception raised by [WebDavClientInterface.listDirectory].
class WebDavException implements Exception {
  final String message;
  final int? statusCode;

  const WebDavException(this.message, {this.statusCode});

  /// 401 / 403 — credentials are invalid.
  bool get isAuthError => statusCode == 401 || statusCode == 403;

  @override
  String toString() => message;
}

// ── Concrete implementation ───────────────────────────────────────────────────

class WebDavClient implements WebDavClientInterface {
  final http.Client _httpClient;
  final Duration _timeout;

  WebDavClient({
    http.Client? httpClient,
    Duration timeout = const Duration(seconds: 5),
  })  : _httpClient = httpClient ?? http.Client(),
        _timeout = timeout;

  @override
  Future<WebDavValidationResult> validate({
    required String url,
    required String username,
    required String password,
    String basePath = '/',
  }) async {
    // CON2/NET7: redact any embedded user:pass@ before it reaches
    // debugPrint (mirrored into LogBuffer by installLogBufferHook).
    debugPrint(
        '[WebDAV] validate: url=${redactUrlForLog(url)} basePath=$basePath');
    // 1. Normalise and validate URL format
    final normalisedUrl = normaliseWebDavUrl(url);
    if (!isValidWebDavUrl(normalisedUrl)) {
      debugPrint('[WebDAV] validate: invalid URL format');
      return WebDavValidationResult.networkError();
    }

    // 2. Build the target URI — probe the connection root, i.e. the URL's own
    //    path joined with basePath (NET1: same location listDirectory uses,
    //    instead of replacing the URL path with basePath).
    Uri targetUri;
    try {
      final base = Uri.parse(normalisedUrl);
      final effectivePath = resolveWebDavBasePath(base.path, basePath);
      targetUri = base.replace(path: effectivePath);
    } catch (_) {
      return WebDavValidationResult.networkError();
    }

    // 3. Build Basic-Auth header using dart:convert base64
    final credentialBytes = utf8.encode('$username:$password');
    final encoded = base64.encode(credentialBytes);
    final authHeader = 'Basic $encoded';

    // 4. Send PROPFIND with timeout
    try {
      final request = http.Request('PROPFIND', targetUri)
        ..headers['Authorization'] = authHeader
        ..headers['Depth'] = '0'
        ..headers['Content-Type'] = 'application/xml';

      final streamedResponse =
          await _httpClient.send(request).timeout(_timeout);

      final result = () {
        switch (streamedResponse.statusCode) {
          case 207:
            return WebDavValidationResult.success();
          case 401:
          case 403:
            return WebDavValidationResult.authError();
          case 404:
            return WebDavValidationResult.pathNotFound();
          default:
            if (streamedResponse.statusCode >= 200 &&
                streamedResponse.statusCode < 300) {
              return WebDavValidationResult.success();
            }
            return WebDavValidationResult.networkError();
        }
      }();
      debugPrint('[WebDAV] validate result: ${result.status}'
          ' (HTTP ${streamedResponse.statusCode})');
      unawaited(streamedResponse.stream.drain<void>().catchError((_) {}));
      return result;
    } on TimeoutException {
      debugPrint('[WebDAV] validate: timeout');
      return WebDavValidationResult.networkError();
    } catch (e) {
      // ClientException messages can echo the request uri — redact before
      // printing so userinfo credentials never leak (NET7 second-order leak).
      debugPrint('[WebDAV] validate error: ${redactUrlForLog(e.toString())}');
      return WebDavValidationResult.networkError();
    }
  }

  // ── Directory listing ────────────────────────────────────────────────────────

  @override
  Future<List<NasFile>> listDirectory({
    required String url,
    required String username,
    required String password,
    required String path,
  }) async {
    debugPrint('[WebDAV] listDirectory: path=$path');
    // 1. Build the target URI
    final normalisedUrl = normaliseWebDavUrl(url);
    Uri targetUri;
    // The connection root carried by the (effective) base URL — prepended to
    // the requested path, and later stripped from returned hrefs so NasFile
    // paths come back relative to the connection root (NET1).
    String basePath = '';
    try {
      final base = Uri.parse(normalisedUrl);
      // Combine base path with the requested directory path
      basePath = base.path.endsWith('/')
          ? base.path.substring(0, base.path.length - 1)
          : base.path;
      final dirPath = path.startsWith('/') ? path : '/$path';
      final combinedPath = '$basePath$dirPath';
      targetUri = base.replace(path: combinedPath);
    } catch (e) {
      throw const WebDavException('无法构建请求地址');
    }

    // 2. Build Basic-Auth header
    final credentialBytes = utf8.encode('$username:$password');
    final encoded = base64.encode(credentialBytes);
    final authHeader = 'Basic $encoded';

    // 3. Send PROPFIND Depth: 1 with timeout
    try {
      final request = http.Request('PROPFIND', targetUri)
        ..headers['Authorization'] = authHeader
        ..headers['Depth'] = '1'
        ..headers['Content-Type'] = 'application/xml';

      final streamedResponse =
          await _httpClient.send(request).timeout(_timeout);

      final body =
          await streamedResponse.stream.bytesToString().timeout(_timeout);

      if (streamedResponse.statusCode == 401 ||
          streamedResponse.statusCode == 403) {
        debugPrint(
            '[WebDAV] listDirectory: auth error (HTTP ${streamedResponse.statusCode})');
        throw WebDavException(
          '用户名或密码错误',
          statusCode: streamedResponse.statusCode,
        );
      }

      if (streamedResponse.statusCode != 207) {
        debugPrint(
            '[WebDAV] listDirectory: bad status ${streamedResponse.statusCode}');
        throw WebDavException(
          '服务器返回异常状态码 ${streamedResponse.statusCode}',
          statusCode: streamedResponse.statusCode,
        );
      }

      final parsed = _parsePropfindResponse(body);
      // NET1: server hrefs are absolute; strip the connection root so callers
      // receive paths relative to the connection root (avoids the self-ref
      // ghost entry and the /dav/dav double-prefix on navigation / playback).
      final decodedBase = basePath.isEmpty ? '' : Uri.decodeFull(basePath);
      final result = decodedBase.isEmpty
          ? parsed
          : parsed.map((f) => _relativisePath(f, decodedBase)).toList();
      debugPrint('[WebDAV] listDirectory: got ${result.length} entries');
      return result;
    } on WebDavException {
      rethrow;
    } on TimeoutException {
      debugPrint('[WebDAV] listDirectory: timeout');
      throw const WebDavException('连接超时');
    } catch (e) {
      // Same second-order leak as validate(): exception text can carry the
      // request uri with userinfo — redact the logged copy (NET7/CON2).
      debugPrint(
          '[WebDAV] listDirectory error: ${redactUrlForLog(e.toString())}');
      throw WebDavException('无法连接到服务器，请检查地址和网络');
    }
  }

  // ── XML parsing ──────────────────────────────────────────────────────────────

  /// Parses a WebDAV PROPFIND 207 Multi-Status XML response body into a list
  /// of [NasFile] entries.
  ///
  /// Handles namespace-prefixed elements (e.g. `<d:href>`, `<D:prop>`)
  /// as well as un-prefixed variants.
  @visibleForTesting
  static List<NasFile> parsePropfindResponse(String xmlBody) {
    return _parsePropfindResponse(xmlBody);
  }

  static List<NasFile> _parsePropfindResponse(String xmlBody) {
    final files = <NasFile>[];

    // Extract each <response> block (namespace-prefix agnostic)
    final responseRegex = RegExp(
        r'<[^>]*response[^>]*>(.*?)</[^>]*response[^>]*>',
        dotAll: true,
        caseSensitive: false);

    for (final match in responseRegex.allMatches(xmlBody)) {
      final responseXml = match.group(1)!;

      // Extract <href>
      final href = _extractXmlContent(responseXml, 'href');
      if (href == null || href.isEmpty) continue;

      // Extract properties
      final propXml = _extractXmlContent(responseXml, 'prop');
      final props = <String, String?>{};
      if (propXml != null) {
        props['displayname'] = _extractXmlContent(propXml, 'displayname');
        props['getcontentlength'] =
            _extractXmlContent(propXml, 'getcontentlength');
        props['getlastmodified'] =
            _extractXmlContent(propXml, 'getlastmodified');
        // resourcetype: check for <collection/> tag
        props['resourcetype'] = _extractXmlContent(propXml, 'resourcetype');
      }

      files.add(NasFile.fromProps(href: href, props: props));
    }

    return files;
  }

  /// Returns [file] with its absolute server path rebased relative to the
  /// connection root by stripping the (URL-decoded) [decodedBase] prefix.
  ///
  /// The directory self-reference (path == base) becomes `/`. Paths not under
  /// the base are returned unchanged (defensive — should not happen for a
  /// well-formed PROPFIND response).
  static NasFile _relativisePath(NasFile file, String decodedBase) {
    final p = file.path;
    String rel;
    if (p == decodedBase) {
      rel = '/';
    } else if (p.startsWith('$decodedBase/')) {
      rel = p.substring(decodedBase.length);
    } else {
      rel = p;
    }
    return NasFile(
      name: file.name,
      path: rel,
      isDirectory: file.isDirectory,
      size: file.size,
      modifiedAt: file.modifiedAt,
      audioType: file.audioType,
    );
  }

  /// Extracts the text content of the first XML element matching [tagName]
  /// (case-insensitive, namespace-prefix agnostic).
  ///
  /// Returns `null` when the element is not found.
  static String? _extractXmlContent(String xml, String tagName) {
    // Match both self-closing and paired tags with any namespace prefix
    final regex = RegExp(
      '<[^>]*$tagName[^>]*>(.*?)</[^>]*$tagName[^>]*>',
      dotAll: true,
      caseSensitive: false,
    );
    final match = regex.firstMatch(xml);
    if (match != null) return _unescapeXmlEntities(match.group(1)?.trim());

    // Also try self-closing tag — return empty string to signal presence
    final selfClosingRegex = RegExp(
      '<[^>]*$tagName[^>]*/>',
      caseSensitive: false,
    );
    if (selfClosingRegex.hasMatch(xml)) return '';

    return null;
  }

  static String? _unescapeXmlEntities(String? text) {
    if (text == null) return null;
    return text
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&apos;', "'")
        .replaceAll('&quot;', '"')
        .replaceAll('&amp;', '&');
  }
}
