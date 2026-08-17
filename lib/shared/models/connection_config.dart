// lib/shared/models/connection_config.dart
// Data model for WebDAV connection configuration.
// Password is NOT stored here — it is kept in flutter_secure_storage.
// 相等性规则与登记：见 equality_registry.dart（REF-02）

class ConnectionConfig {
  final int? id;
  final String name;
  final String url;
  final String username;
  final String basePath;
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;

  const ConnectionConfig({
    this.id,
    required this.name,
    required this.url,
    required this.username,
    this.basePath = '/',
    this.isActive = false,
    required this.createdAt,
    required this.updatedAt,
  });

  /// Extracts hostname from the URL to use as default display name.
  static String hostnameFromUrl(String url) {
    try {
      final uri = Uri.parse(url);
      return uri.host.isNotEmpty ? uri.host : url;
    } catch (_) {
      return url;
    }
  }

  /// Converts a database row map to [ConnectionConfig].
  /// The `password` column in the row contains the secure-storage reference key,
  /// NOT the plaintext password — it is ignored here.
  factory ConnectionConfig.fromMap(Map<String, dynamic> map) {
    return ConnectionConfig(
      id: map['id'] as int?,
      name: map['name'] as String,
      url: map['url'] as String,
      username: map['username'] as String,
      basePath: (map['base_path'] as String?) ?? '/',
      isActive: (map['is_active'] as int) == 1,
      createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(map['updated_at'] as int),
    );
  }

  /// Converts this model to a database row map.
  /// [passwordKey] is the flutter_secure_storage reference key (not plaintext).
  Map<String, dynamic> toMap({required String passwordKey}) {
    return {
      if (id != null) 'id': id,
      'name': name,
      'url': url,
      'username': username,
      'password': passwordKey, // stores secure storage key reference
      'base_path': basePath,
      'is_active': isActive ? 1 : 0,
      'created_at': createdAt.millisecondsSinceEpoch,
      'updated_at': updatedAt.millisecondsSinceEpoch,
    };
  }

  ConnectionConfig copyWith({
    int? id,
    String? name,
    String? url,
    String? username,
    String? basePath,
    bool? isActive,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return ConnectionConfig(
      id: id ?? this.id,
      name: name ?? this.name,
      url: url ?? this.url,
      username: username ?? this.username,
      basePath: basePath ?? this.basePath,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ConnectionConfig &&
          id == other.id &&
          name == other.name &&
          url == other.url &&
          username == other.username &&
          basePath == other.basePath &&
          isActive == other.isActive &&
          createdAt == other.createdAt &&
          updatedAt == other.updatedAt;

  @override
  int get hashCode => Object.hash(
      id, name, url, username, basePath, isActive, createdAt, updatedAt);

  @override
  String toString() =>
      'ConnectionConfig(id: $id, name: $name, url: $url, username: $username, '
      'basePath: $basePath, isActive: $isActive)';
}
