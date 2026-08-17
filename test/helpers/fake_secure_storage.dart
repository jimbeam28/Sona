// test/helpers/fake_secure_storage.dart
// Shared FakeSecureStorage for tests (REF-02 / REF-01-A2).
//
// Merged from con_09_test.dart, brw_05_test.dart, brw_06_test.dart.
// REF-01-A2: implements ISecureStorage (contract layer) instead of extending
// the FlutterSecureStorage concrete class — domain layer 零 Flutter 依赖。

import 'dart:async';

import 'package:nas_audio_player/core/contracts/storage_contract.dart';

/// Minimal fake [ISecureStorage] backed by an in-memory map.
class FakeSecureStorage implements ISecureStorage {
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
  Future<String?> read({required String key}) async {
    return _store[key];
  }

  @override
  Future<void> write({required String key, required String? value}) async {
    if (value != null) {
      _store[key] = value;
    } else {
      _store.remove(key);
    }
  }

  @override
  Future<void> delete({required String key}) async {
    _store.remove(key);
  }

  @override
  Future<bool> containsKey({required String key}) async {
    return _store.containsKey(key);
  }
}

/// A [FakeSecureStorage] that unconditionally throws on [write].
class ThrowingFakeSecureStorage extends FakeSecureStorage {
  @override
  Future<void> write({required String key, required String? value}) async {
    throw Exception('Simulated secure storage write failure');
  }
}

/// A [FakeSecureStorage] that unconditionally throws on [delete]
/// (BUG-24-S3: simulates the secure-storage cleanup timeout/failure).
class DeleteThrowingFakeSecureStorage extends FakeSecureStorage {
  @override
  Future<void> delete({required String key}) async {
    throw Exception('Simulated secure storage delete failure');
  }
}

/// A [FakeSecureStorage] that unconditionally throws on [read]
/// (BUG-24-S2 boundary: old-password read failure must degrade to null,
/// never abort the update).
class ReadThrowingFakeSecureStorage extends FakeSecureStorage {
  @override
  Future<String?> read({required String key}) async {
    throw Exception('Simulated secure storage read failure');
  }
}

/// A [FakeSecureStorage] whose selected methods never complete
/// (simulates a hung Keystore / flutter_secure_storage).
///
/// Configure per-method hanging via [hangRead] / [hangWrite] / [hangDelete]
/// (default false = delegate to the normal in-memory implementation).
/// Call counters increment on every invocation (hanging or not) — asserted
/// by callers such as svc_storage_utils_test.
class HangingFakeSecureStorage extends FakeSecureStorage {
  HangingFakeSecureStorage({
    this.hangRead = false,
    this.hangWrite = false,
    this.hangDelete = false,
  });

  final bool hangRead;
  final bool hangWrite;
  final bool hangDelete;

  int readCalls = 0;
  int writeCalls = 0;
  int deleteCalls = 0;

  @override
  Future<String?> read({required String key}) {
    readCalls++;
    if (hangRead) {
      return Completer<String?>().future;
    }
    return super.read(key: key);
  }

  @override
  Future<void> write({required String key, required String? value}) {
    writeCalls++;
    if (hangWrite) {
      return Completer<void>().future;
    }
    return super.write(key: key, value: value);
  }

  @override
  Future<void> delete({required String key}) {
    deleteCalls++;
    if (hangDelete) {
      return Completer<void>().future;
    }
    return super.delete(key: key);
  }
}
