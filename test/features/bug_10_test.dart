// test/features/bug_10_test.dart
// BUG-10: SecureStorage 全局无超时保护
//
// Tests verify that safeStorageRead / safeStorageWrite / safeStorageDelete
// enforce a 5-second timeout, preventing indefinite hangs on broken Android
// KeyStore or OS-upgrade scenarios.
//
// Uses fake_async to simulate time progression for timeout tests.

import 'dart:async';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fake_async/fake_async.dart';
import 'package:nas_audio_player/core/services/storage_utils.dart';

void main() {
  // ═══════════════════════════════════════════════════════════════════════════
  // Test cases — BUG-10-T01 ~ T04
  // ═══════════════════════════════════════════════════════════════════════════

  group('BUG-10: SecureStorage timeout protection', () {
    // ── BUG-10-T01: storage.read hangs -> 5 seconds later returns null ──────

    test('BUG-10-T01: storage.read hangs -> returns null after 5s timeout',
        () {
      FakeAsync().run((async) {
        final storage = _HangingSecureStorage();

        // safeStorageRead should complete (not hang) after 5 seconds.
        String? result;
        var completed = false;

        safeStorageRead(storage, key: 'test_key').then((value) {
          result = value;
          completed = true;
        });

        // Not yet completed — timeout hasn't fired.
        async.elapse(const Duration(seconds: 4));
        expect(completed, isFalse,
            reason: 'Should not complete before 5s timeout');

        // Elapse past the 5-second timeout.
        async.elapse(const Duration(seconds: 2));
        expect(completed, isTrue, reason: 'Should complete after 5s timeout');
        expect(result, isNull,
            reason: 'safeStorageRead should return null on timeout');
      });
    });

    // ── BUG-10-T02: storage.write hangs -> 5 seconds later throws ──────────

    test('BUG-10-T02: storage.write hangs -> throws after 5s timeout', () {
      FakeAsync().run((async) {
        final storage = _HangingWriteSecureStorage();

        Object? caughtError;
        var completed = false;

        safeStorageWrite(storage, key: 'test_key', value: 'test_value')
            .then((_) {
          completed = true;
        }).catchError((e) {
          caughtError = e;
          completed = true;
        });

        // Not yet completed.
        async.elapse(const Duration(seconds: 4));
        expect(completed, isFalse,
            reason: 'Should not complete before 5s timeout');

        // Elapse past the 5-second timeout.
        async.elapse(const Duration(seconds: 2));
        expect(completed, isTrue, reason: 'Should complete after 5s timeout');
        expect(caughtError, isA<TimeoutException>(),
            reason: 'Should throw TimeoutException');
      });
    });

    // ── BUG-10-T03: normal read -> no timeout -> returns correct value ──────

    test('BUG-10-T03: normal read -> returns correct value (regression)',
        () async {
      final storage = _FakeSecureStorage(password: 'my_secret');

      final result = await safeStorageRead(storage, key: 'test_key');

      expect(result, equals('my_secret'),
          reason: 'Should return the stored password');
    });

    // ── BUG-10-T04: normal write -> no timeout -> write succeeds ────────────

    test('BUG-10-T04: normal write -> completes without error (regression)',
        () async {
      final storage = _FakeWriteSecureStorage();

      // Should complete without throwing.
      await safeStorageWrite(storage, key: 'test_key', value: 'test_value');

      expect(storage.lastWrittenKey, equals('test_key'));
      expect(storage.lastWrittenValue, equals('test_value'));
    });
  });
}

// ── Manual fakes ─────────────────────────────────────────────────────────────

/// Fake [FlutterSecureStorage] that resolves immediately with a preset password.
class _FakeSecureStorage extends FlutterSecureStorage {
  final String? password;

  _FakeSecureStorage({this.password});

  @override
  Future<String?> read({
    required String key,
    IOSOptions? iOptions = IOSOptions.defaultOptions,
    AndroidOptions? aOptions = AndroidOptions.defaultOptions,
    LinuxOptions? lOptions = LinuxOptions.defaultOptions,
    WindowsOptions? wOptions = WindowsOptions.defaultOptions,
    MacOsOptions? mOptions = MacOsOptions.defaultOptions,
    WebOptions? webOptions = WebOptions.defaultOptions,
  }) async {
    return password;
  }
}

/// Fake [FlutterSecureStorage] that records write calls and completes immediately.
class _FakeWriteSecureStorage extends FlutterSecureStorage {
  String? lastWrittenKey;
  String? lastWrittenValue;

  @override
  Future<void> write({
    required String key,
    required String? value,
    IOSOptions? iOptions = IOSOptions.defaultOptions,
    AndroidOptions? aOptions = AndroidOptions.defaultOptions,
    LinuxOptions? lOptions = LinuxOptions.defaultOptions,
    WindowsOptions? wOptions = WindowsOptions.defaultOptions,
    MacOsOptions? mOptions = MacOsOptions.defaultOptions,
    WebOptions? webOptions = WebOptions.defaultOptions,
  }) async {
    lastWrittenKey = key;
    lastWrittenValue = value;
  }
}

/// Fake [FlutterSecureStorage] whose [read] never completes (simulates hung storage).
class _HangingSecureStorage extends FlutterSecureStorage {
  @override
  Future<String?> read({
    required String key,
    IOSOptions? iOptions = IOSOptions.defaultOptions,
    AndroidOptions? aOptions = AndroidOptions.defaultOptions,
    LinuxOptions? lOptions = LinuxOptions.defaultOptions,
    WindowsOptions? wOptions = WindowsOptions.defaultOptions,
    MacOsOptions? mOptions = MacOsOptions.defaultOptions,
    WebOptions? webOptions = WebOptions.defaultOptions,
  }) {
    // Return a future that never completes.
    return Completer<String?>().future;
  }
}

/// Fake [FlutterSecureStorage] whose [write] never completes (simulates hung storage).
class _HangingWriteSecureStorage extends FlutterSecureStorage {
  @override
  Future<void> write({
    required String key,
    required String? value,
    IOSOptions? iOptions = IOSOptions.defaultOptions,
    AndroidOptions? aOptions = AndroidOptions.defaultOptions,
    LinuxOptions? lOptions = LinuxOptions.defaultOptions,
    WindowsOptions? wOptions = WindowsOptions.defaultOptions,
    MacOsOptions? mOptions = MacOsOptions.defaultOptions,
    WebOptions? webOptions = WebOptions.defaultOptions,
  }) {
    // Return a future that never completes.
    return Completer<void>().future;
  }
}
