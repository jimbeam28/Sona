// test/helpers/fake_secure_storage.dart
// Shared FakeSecureStorage for tests (REF-02).
//
// Merged from con_09_test.dart, brw_05_test.dart, brw_06_test.dart.

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Minimal fake [FlutterSecureStorage] backed by an in-memory map.
class FakeSecureStorage extends FlutterSecureStorage {
  final Map<String, String> _store = {};

  /// Pre-populate a raw key with a value.
  void stub(String key, String value) => _store[key] = value;

  /// Convenience: set the password for a connection id using the standard key
  /// format ``connection_password_{id}``.
  void setPassword(int connectionId, String password) {
    _store['connection_password_$connectionId'] = password;
  }

  /// Inspects the backing map directly without going through [read] — useful
  /// when [read] is overridden to throw (e.g. [ReadThrowingFakeSecureStorage])
  /// and the test still needs to assert the stored state.
  String? peek(String key) => _store[key];

  @override
  Future<String?> read({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WindowsOptions? wOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
  }) async {
    return _store[key];
  }

  @override
  Future<void> write({
    required String key,
    required String? value,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WindowsOptions? wOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
  }) async {
    if (value != null) {
      _store[key] = value;
    } else {
      _store.remove(key);
    }
  }

  @override
  Future<void> delete({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WindowsOptions? wOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
  }) async {
    _store.remove(key);
  }
}

/// A [FakeSecureStorage] that unconditionally throws on [write].
class ThrowingFakeSecureStorage extends FakeSecureStorage {
  @override
  Future<void> write({
    required String key,
    required String? value,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WindowsOptions? wOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
  }) async {
    throw Exception('Simulated secure storage write failure');
  }
}

/// A [FakeSecureStorage] that unconditionally throws on [delete]
/// (BUG-24-S3: simulates the secure-storage cleanup timeout/failure).
class DeleteThrowingFakeSecureStorage extends FakeSecureStorage {
  @override
  Future<void> delete({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WindowsOptions? wOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
  }) async {
    throw Exception('Simulated secure storage delete failure');
  }
}

/// A [FakeSecureStorage] that unconditionally throws on [read]
/// (BUG-24-S2 boundary: old-password read failure must degrade to null,
/// never abort the update).
class ReadThrowingFakeSecureStorage extends FakeSecureStorage {
  @override
  Future<String?> read({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WindowsOptions? wOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
  }) async {
    throw Exception('Simulated secure storage read failure');
  }
}
