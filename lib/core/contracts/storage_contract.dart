// lib/core/contracts/storage_contract.dart
// Abstract interface wrapping FlutterSecureStorage.
//
// This contract decouples the domain/presentation layers from the concrete
// flutter_secure_storage implementation, enabling fakes/mocks for testing
// without platform channels.

/// Abstract interface for secure key-value storage.
///
/// Mirrors the subset of [FlutterSecureStorage] methods used by the
/// application so that services and providers can depend on this interface
/// rather than the concrete class.
abstract class ISecureStorage {
  /// Reads the value for [key], or `null` if not found.
  Future<String?> read({required String key});

  /// Writes [value] under [key].
  Future<void> write({required String key, required String? value});

  /// Deletes the entry for [key].
  Future<void> delete({required String key});

  /// Returns `true` if an entry for [key] exists.
  Future<bool> containsKey({required String key});
}
