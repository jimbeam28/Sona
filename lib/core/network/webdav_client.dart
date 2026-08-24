// lib/core/network/webdav_client.dart
// WebDAV client: validates connectivity by issuing a PROPFIND request,
// and lists directory contents via PROPFIND Depth:1.
// Uses the `http` package directly so we control the method/timeout.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart' show IOClient;
import '../../shared/models/nas_file.dart';
import '../../shared/webdav_paths.dart';
import '../services/audio_source_builder.dart';

// ── Validation result ─────────────────────────────────────────────────────────

enum WebDavValidationStatus {
  success,
  authError,
  pathNotFound,
  networkError,
  error,
}

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

  /// Generic failure carrying a custom user-facing [message] (e.g. the
  /// secure-storage read timeout during startup validation, BUG-32).
  factory WebDavValidationResult.error(String message) =>
      WebDavValidationResult._(WebDavValidationStatus.error, message);

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
/// and its host. The authority ends at the first `/`, `?` or `#`, so an `@`
/// appearing later (e.g. in a path like `/music/a@b.mp3` or a query string)
/// is never mistaken for userinfo. The match is greedy up to the LAST `@`
/// inside the authority: RFC 3986 userinfo cannot contain a literal `@`, but
/// malformed input (e.g. a password typed with a raw `@`,
/// `http://admin:p@ss@host`) must still be stripped completely — a
/// first-`@` match would leak the password tail (复核修正).
final _urlUserInfoPattern = RegExp(r'(://)[^/?#]*@');

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

  /// Streams [filePath] from the server to a local file (DL-01-S3).
  ///
  /// [url] is the effective base URL; [filePath] is relative to it. The body
  /// is written chunk-by-chunk to `<saveTo>.part` and atomically renamed to
  /// [saveTo] on success, so a partial download can never masquerade as a
  /// finished file (INV5). No overall request timeout applies (B5-7 大文件友好);
  /// instead a silence of [chunkIdleTimeout] between chunks is treated as a
  /// dead link and fails the transfer.
  ///
  /// Contract:
  /// ① GET with Uri encoding identical to buildUriWithBasePath; Authorization
  ///   header reuses AudioSourceBuilder.buildAuthHeader;
  /// ② send() without an overall timeout;
  /// ③ non-2xx → WebDavException family mapping (401/403 auth, 404 kept as
  ///   statusCode, redirect/5xx actionable messages);
  /// ④ per-chunk write + monotonic onProgress(received, total?) where total
  ///   comes from Content-Length (null when absent);
  /// ⑤ success: delete pre-existing final file, then rename .part → final;
  /// ⑥ any failure: best-effort .part cleanup (deletion errors are logged
  ///   only); the pre-existing final file is never touched.
  Future<void> downloadFile({
    required String url,
    required String filePath,
    required String username,
    required String password,
    required String saveTo,
    void Function(int received, int? total)? onProgress,
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

/// Escapes any process-global [HttpOverrides] (flutter_test installs one that
/// turns every HttpClient into a constant-400 mock) so the download engine
/// always talks to real sockets. The base implementation returns a plain
/// `_HttpClient`, i.e. the untouched dart:io client.
class _RealHttpOverrides extends HttpOverrides {
  // Intentionally empty: the base implementation returns a plain dart:io
  // HttpClient, bypassing any process-global mock overrides.
}

class WebDavClient implements WebDavClientInterface {
  final http.Client _httpClient;
  final Duration _timeout;

  /// Max silence between response chunks during [downloadFile] before the
  /// transfer is declared a dead link (DL-01-S3④; default 30 s).
  final Duration _chunkIdleTimeout;

  WebDavClient({
    http.Client? httpClient,
    Duration timeout = const Duration(seconds: 5),
    Duration chunkIdleTimeout = const Duration(seconds: 30),
  })  : _httpClient = httpClient ?? http.Client(),
        _timeout = timeout,
        _chunkIdleTimeout = chunkIdleTimeout;

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
            // NET6/BUG-23-S4: 3xx (http.Client.send does not follow
            // redirects) and 5xx are reachable-server errors — reporting them
            // as "cannot connect" points the user at the wrong fix.
            if (streamedResponse.statusCode >= 300 &&
                streamedResponse.statusCode < 400) {
              return const WebDavValidationResult._(
                WebDavValidationStatus.networkError,
                '服务器重定向，请检查地址是否应为 https',
              );
            }
            if (streamedResponse.statusCode >= 500) {
              return const WebDavValidationResult._(
                WebDavValidationStatus.networkError,
                '服务器内部错误，请稍后重试',
              );
            }
            return WebDavValidationResult.networkError();
        }
      }();
      debugPrint('[WebDAV] validate result: ${result.status}'
          ' (HTTP ${streamedResponse.statusCode})');
      unawaited(streamedResponse.stream.drain<void>().catchError((Object e) {
        // Connection-hygiene cleanup after the result is final — failure is
        // harmless but must not vanish silently (catch-log criterion).
        // Redact: exception messages can echo the request uri (same
        // rationale as the validate error log below).
        debugPrint(
            '[WebDAV] validate drain failed: ${redactUrlForLog(e.toString())}');
      }));
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
        // NET6/BUG-23-S4: 3xx/5xx get actionable messages; other non-207
        // statuses keep the bare-code fallback.
        final message = switch (streamedResponse.statusCode) {
          >= 300 && < 400 => '服务器重定向，请检查地址是否应为 https',
          >= 500 => '服务器内部错误，请稍后重试',
          _ => '服务器返回异常状态码 ${streamedResponse.statusCode}',
        };
        throw WebDavException(
          message,
          statusCode: streamedResponse.statusCode,
        );
      }

      final parsed = _parsePropfindResponse(body);
      // NET1: server hrefs are absolute; strip the connection root so callers
      // receive paths relative to the connection root (avoids the self-ref
      // ghost entry and the /dav/dav double-prefix on navigation / playback).
      final decodedBase = basePath.isEmpty ? '' : Uri.decodeFull(basePath);
      // REF-01: 无条件 relativise —— 根挂载时绝对 URL href 也要剥 authority
      // （cr-20260816-0801 D1）。targetUri 的 authority 是"本服务器"判定基准。
      final result = parsed
          .map((f) => _relativisePath(f, decodedBase, targetUri))
          .toList();
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
      throw const WebDavException('无法连接到服务器，请检查地址和网络');
    }
  }

  // ── File download (DL-01-S3) ───────────────────────────────────────────────

  @override
  Future<void> downloadFile({
    required String url,
    required String filePath,
    required String username,
    required String password,
    required String saveTo,
    void Function(int received, int? total)? onProgress,
  }) async {
    debugPrint('[WebDAV] downloadFile: path=$filePath');
    // ① Build the target URI — same encoding rules as
    //    AudioSourceBuilder.buildUriWithBasePath (base path + encoded segments).
    final normalisedUrl = normaliseWebDavUrl(url);
    Uri targetUri;
    try {
      final base = Uri.parse(normalisedUrl);
      final basePath = base.path.endsWith('/')
          ? base.path.substring(0, base.path.length - 1)
          : base.path;
      final relPath = filePath.startsWith('/') ? filePath : '/$filePath';
      final combinedPath = '$basePath$relPath';
      final segments = combinedPath
          .split('/')
          .where((s) => s.isNotEmpty)
          .map((s) => Uri.encodeComponent(s))
          .toList();
      targetUri = base.replace(path: '/${segments.join('/')}');
    } catch (_) {
      throw const WebDavException('无法构建请求地址');
    }

    // Authorization reuses the shared Basic-Auth builder.
    final authHeader = AudioSourceBuilder.buildAuthHeader(
        username: username, password: password);

    // ② Send WITHOUT an overall timeout (large-file friendly, B5-7/P17).
    //
    // 测试环境逃生门：flutter_test 的 TestWidgetsFlutterBinding 会安装全局
    // HttpOverrides，把进程内一切 HttpClient 变成恒 400 的 mock。下载引擎
    // 需要真实 socket（S3 用本机 HttpServer 做假源），故为每次下载在脱离
    // overrides 的 zone 内构建独立 client，用毕即关。
    IOClient? scopedClient;
    http.StreamedResponse streamedResponse;
    try {
      final request = http.Request('GET', targetUri)
        ..headers['Authorization'] = authHeader;
      scopedClient = HttpOverrides.runWithHttpOverrides<IOClient>(
        IOClient.new,
        _RealHttpOverrides(),
      );
      streamedResponse = await scopedClient.send(request);
    } catch (e) {
      scopedClient?.close();
      // Exception text can echo the request uri — redact before logging.
      debugPrint(
          '[WebDAV] downloadFile error: ${redactUrlForLog(e.toString())}');
      throw const WebDavException('无法连接到服务器，请检查地址和网络');
    }

    // ③ Non-2xx → family mapping identical to listDirectory.
    final statusCode = streamedResponse.statusCode;
    if (statusCode == 401 || statusCode == 403) {
      debugPrint('[WebDAV] downloadFile: auth error (HTTP $statusCode)');
      throw WebDavException('用户名或密码错误', statusCode: statusCode);
    }
    if (statusCode < 200 || statusCode >= 300) {
      debugPrint('[WebDAV] downloadFile: bad status $statusCode');
      final message = switch (statusCode) {
        >= 300 && < 400 => '服务器重定向，请检查地址是否应为 https',
        >= 500 => '服务器内部错误，请稍后重试',
        _ => '服务器返回异常状态码 $statusCode',
      };
      throw WebDavException(message, statusCode: statusCode);
    }

    final total = streamedResponse.contentLength; // null when absent (chunked)

    try {
      // ④ Stream to <saveTo>.part with per-chunk progress + idle watchdog.
      final partFile = File('$saveTo.part');
      IOSink? sink;
      var received = 0;
      try {
        await partFile.parent.create(recursive: true);
        sink = partFile.openWrite();
        await for (final chunk
            in streamedResponse.stream.timeout(_chunkIdleTimeout)) {
          sink.add(chunk);
          received += chunk.length;
          onProgress?.call(received, total);
        }
        await sink.flush();
        await sink.close();
        sink = null;

        // ⑤ Success: remove a pre-existing final file first, then rename the
        //    .part into place (double insurance on top of POSIX overwrite).
        final finalFile = File(saveTo);
        if (await finalFile.exists()) {
          await finalFile.delete();
        }
        await partFile.rename(saveTo);
        debugPrint(
            '[WebDAV] downloadFile done: path=$filePath bytes=$received');
      } on TimeoutException {
        await _cleanupPartFile(partFile, sink);
        throw const WebDavException('下载超时：服务器停止传输数据');
      } catch (e) {
        // ⑥ Any failure path: best-effort .part cleanup, log only.
        await _cleanupPartFile(partFile, sink);
        debugPrint(
            '[WebDAV] downloadFile failed: ${redactUrlForLog(e.toString())}');
        throw const WebDavException('下载失败，请检查网络后重试');
      }
    } finally {
      scopedClient.close();
    }
  }

  /// Best-effort `.part` removal used by every failure branch of
  /// [downloadFile]; deletion errors are logged and swallowed (S3⑥).
  Future<void> _cleanupPartFile(File partFile, IOSink? sink) async {
    try {
      await sink?.flush();
    } catch (_) {}
    try {
      await sink?.close();
    } catch (_) {}
    try {
      if (await partFile.exists()) {
        await partFile.delete();
      }
    } catch (e) {
      debugPrint('[WebDAV] downloadFile: cleanup .part failed: $e');
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
  static NasFile _relativisePath(
      NasFile file, String decodedBase, Uri requestUri) {
    final p = file.path;
    // REF-01: 绝对 URL href 先剥 authority（host 同本连接才剥），再走既有前缀剥离。
    final pathOnly = _stripHrefAuthority(p, requestUri);
    final base = pathOnly ?? p; // null → 非绝对 URL 或外部 host，保持原样
    String rel;
    if (base == decodedBase) {
      rel = '/';
    } else if (base.startsWith('$decodedBase/')) {
      rel = base.substring(decodedBase.length);
    } else {
      rel = base;
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

  /// REF-01: 返回 [hrefPath] 的路径形态（剥掉 scheme+authority），当且仅当
  /// [hrefPath] 是绝对 URL（scheme 非空且 host 非空）且其 host 与 [requestUri]
  /// 的 host 相同（大小写不敏感）。端口与 scheme 不参与判定（反代/端口改写
  /// 场景下服务器可能以不同端口/scheme 自报，下游重拼 URL 用连接 URL 的
  /// 端口与 scheme，剥掉 authority 后拼接仍正确）。非绝对 URL 或 host 不同
  /// 返回 null —— 调用方保持原样（外部引用不被相对化吞掉）。
  /// 剥后 path 为空（根自引用 `http://host:5005`）→ 归一为 '/'。
  static String? _stripHrefAuthority(String hrefPath, Uri requestUri) {
    final uri = Uri.tryParse(hrefPath);
    if (uri == null || uri.scheme.isEmpty || uri.host.isEmpty) return null;
    if (uri.host.toLowerCase() != requestUri.host.toLowerCase()) return null;
    final path = uri.path;
    return path.isEmpty ? '/' : path;
  }

  /// Extracts the text content of the first XML element matching [tagName]
  /// (case-insensitive, namespace-prefix agnostic).
  ///
  /// Returns `null` when the element is not found.
  static String? _extractXmlContent(String xml, String tagName) {
    // Match both self-closing and paired tags with any namespace prefix.
    // NET5/BUG-23-S3: `\b` word boundaries stop substring false-positives
    // (`prop` must not match `<propstat>`, `href` must not match `<xhref>`),
    // and RegExp.escape guards against regex metacharacters in [tagName].
    final escapedTag = RegExp.escape(tagName);
    final regex = RegExp(
      '<[^>]*\\b$escapedTag\\b[^>]*>(.*?)</[^>]*\\b$escapedTag\\b[^>]*>',
      dotAll: true,
      caseSensitive: false,
    );
    final match = regex.firstMatch(xml);
    if (match != null) return _unescapeXmlEntities(match.group(1)?.trim());

    // Also try self-closing tag — return empty string to signal presence
    final selfClosingRegex = RegExp(
      '<[^>]*\\b$escapedTag\\b[^>]*/>',
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
