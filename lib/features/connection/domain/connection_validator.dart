// lib/features/connection/domain/connection_validator.dart
// Pure validation functions for connection form fields.
// Extracted from connection_form.dart and connection_provider.dart
// to enable independent unit testing without Flutter dependencies.

import '../../../core/network/webdav_client.dart';

/// Validates the WebDAV server URL field.
///
/// Returns an error message string when validation fails, or `null` when the
/// value is valid.
///
/// Rules:
/// - Must not be null or empty (after trimming).
/// - After normalisation (auto-prepend `http://` + default port 5005),
///   the URL must pass [isValidWebDavUrl].
String? validateUrl(String? value) {
  if (value == null || value.trim().isEmpty) return '请输入服务器地址';
  final normalised = normaliseWebDavUrl(value.trim());
  if (!isValidWebDavUrl(normalised)) {
    return '请输入有效的服务器地址（如 http://192.168.1.100:5005 或 http://nas.example.com）';
  }
  return null;
}

/// Validates that a required text field is not null or empty.
///
/// [fieldName] is inserted into the error message, e.g. "用户名" produces
/// "请输入用户名".
String? validateRequired(String? value, String fieldName) {
  if (value == null || value.trim().isEmpty) return '请输入$fieldName';
  return null;
}

/// Validates and normalises the base path field.
///
/// Returns a [BasePathResult] containing the normalised value and an optional
/// error message.
///
/// Rules:
/// - Empty / whitespace-only values default to `/'`.
/// - Non-empty values must start with `'/'`.
/// - Must not contain `..` (path traversal guard).
BasePathResult validateBasePath(String? value) {
  final trimmed = (value ?? '').trim();
  if (trimmed.isEmpty) {
    return const BasePathResult(normalised: '/');
  }
  if (!trimmed.startsWith('/')) {
    return BasePathResult(
      normalised: '/$trimmed',
      error: '基础路径必须以 / 开头',
    );
  }
  if (trimmed.contains('..')) {
    return BasePathResult(
      normalised: trimmed,
      error: '基础路径不能包含 ..',
    );
  }
  return BasePathResult(normalised: trimmed);
}

/// Validates a DDNS hostname or IP address.
///
/// Returns an error message string when validation fails, or `null` when the
/// value is a plausible hostname / IP.
///
/// Rules:
/// - Must not be null or empty.
/// - Must not contain spaces or scheme prefixes (`http://` etc.).
/// - Each label must be alphanumeric (plus hyphen), 1-63 chars, and the
///   total length must not exceed 253 characters.
/// - An IPv4 address (four dot-separated 0-255 numbers) is also accepted.
String? validateDdnsHostname(String? value) {
  if (value == null || value.trim().isEmpty) return '请输入域名或 IP 地址';
  final trimmed = value.trim();

  // Reject scheme prefixes — the user should enter a bare hostname.
  if (trimmed.contains('://')) {
    return '请输入域名或 IP 地址，不要包含 http:// 等协议前缀';
  }

  // Reject spaces.
  if (trimmed.contains(' ')) return '域名或 IP 地址不能包含空格';

  // Quick IPv4 check: four dot-separated numbers 0-255.
  final ipv4Parts = trimmed.split('.');
  if (ipv4Parts.length == 4 &&
      ipv4Parts.every((p) {
        final n = int.tryParse(p);
        return n != null && n >= 0 && n <= 255;
      })) {
    return null; // valid IPv4
  }

  // Hostname label validation (RFC 952 / RFC 1123 simplified).
  if (trimmed.length > 253) return '域名过长（最多 253 个字符）';
  final labelRegex = RegExp(r'^[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?$');
  final labels = trimmed.split('.');
  for (final label in labels) {
    if (label.isEmpty || !labelRegex.hasMatch(label)) {
      return '域名格式不正确（每段只能包含字母、数字和连字符）';
    }
  }

  return null;
}

/// Result of [validateBasePath].
class BasePathResult {
  /// The normalised base path (always starts with `/`, never empty).
  final String normalised;

  /// An error message if validation failed, or `null` if valid.
  final String? error;

  const BasePathResult({required this.normalised, this.error});

  bool get isValid => error == null;

  @override
  String toString() => 'BasePathResult(normalised: $normalised, error: $error)';
}
