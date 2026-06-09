// lib/core/network/webdav_client.dart
// WebDAV client: validates connectivity by issuing a PROPFIND request,
// and lists directory contents via PROPFIND Depth:1.
// Uses the `http` package directly so we control the method/timeout.

import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../../shared/models/nas_file.dart';

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
  final uri = Uri.parse(url);
  if (!uri.hasPort && uri.host.isNotEmpty) {
    return uri.replace(port: 5005).toString();
  }
  return url;
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

// ── Abstract interface ────────────────────────────────────────────────────────

abstract class WebDavClientInterface {
  /// Validates the WebDAV endpoint by sending a PROPFIND request.
  Future<WebDavValidationResult> validate({
    required String url,
    required String username,
    required String password,
    String basePath = '/',
  });

  /// Lists directory contents via PROPFIND (Depth: 1).
  ///
  /// Throws [WebDavException] on auth failures (401) or network errors.
  /// Returns all entries (including the directory self-reference) — the
  /// caller is responsible for filtering and sorting.
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
    debugPrint('[WebDAV] validate: url=$url basePath=$basePath');
    // 1. Normalise and validate URL format
    final normalisedUrl = normaliseWebDavUrl(url);
    if (!isValidWebDavUrl(normalisedUrl)) {
      debugPrint('[WebDAV] validate: invalid URL format');
      return WebDavValidationResult.networkError();
    }

    // 2. Build the target URI (base path)
    Uri targetUri;
    try {
      final base = Uri.parse(normalisedUrl);
      final effectivePath = basePath.isEmpty
          ? '/'
          : (basePath.startsWith('/') ? basePath : '/$basePath');
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
      // G-5: drain the response body so the HTTP connection can be reused.
      await streamedResponse.stream.drain<void>();
      return result;
    } on TimeoutException {
      debugPrint('[WebDAV] validate: timeout');
      return WebDavValidationResult.networkError();
    } catch (e) {
      debugPrint('[WebDAV] validate error: $e');
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
    try {
      final base = Uri.parse(normalisedUrl);
      // Combine base path with the requested directory path
      final basePath = base.path.endsWith('/')
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

      final body = await streamedResponse.stream.bytesToString();

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

      final result = _parsePropfindResponse(body);
      debugPrint('[WebDAV] listDirectory: got ${result.length} entries');
      return result;
    } on WebDavException {
      rethrow;
    } on TimeoutException {
      debugPrint('[WebDAV] listDirectory: timeout');
      throw const WebDavException('连接超时');
    } catch (e) {
      debugPrint('[WebDAV] listDirectory error: $e');
      throw WebDavException('无法连接到服务器：$e');
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
    final responseRegex =
        RegExp(r'<[^>]*response[^>]*>(.*?)</[^>]*response[^>]*>', dotAll: true);

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
    if (match != null) return match.group(1)?.trim();

    // Also try self-closing tag — return empty string to signal presence
    final selfClosingRegex = RegExp(
      '<[^>]*$tagName[^>]*/>',
      caseSensitive: false,
    );
    if (selfClosingRegex.hasMatch(xml)) return '';

    return null;
  }
}
