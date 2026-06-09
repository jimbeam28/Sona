// test/features/browser/bug_07_test.dart
// BUG-07: App 启动恢复队列时 setAudioSource/seek 无超时导致启动卡住
//
// Tests verify that the pre-load sequence has a 10-second timeout, so
// NAS unavailability does not block app startup.
//
// The timeout logic lives in [preloadAudioSource], which is tested directly
// as a pure async function (no Riverpod provider lifecycle involved).

import 'dart:async';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:nas_audio_player/features/browser/browser_provider.dart';

import 'bug_07_test.mocks.dart';

// ── Generate mocks ──────────────────────────────────────────────────────────

@GenerateMocks([AudioPlayer])
void main() {
  // ── Helpers ──────────────────────────────────────────────────────────────────

  /// Fake secure storage that resolves immediately with [password].
  FlutterSecureStorage fakeStorage(String? password) {
    return _FakeSecureStorage(password: password);
  }

  /// Fake secure storage that never completes (hangs).
  FlutterSecureStorage hangingStorage() {
    return _HangingSecureStorage();
  }

  /// Returns a mock [AudioPlayer] whose [setAudioSource] never completes.
  MockAudioPlayer hangingPlayer() {
    final player = MockAudioPlayer();
    final completer = Completer<Duration?>();
    when(player.setAudioSource(any,
        preload: anyNamed('preload'),
        initialPosition: anyNamed('initialPosition'),
        initialIndex: anyNamed('initialIndex'),
    )).thenAnswer((_) => completer.future);
    return player;
  }

  /// Returns a mock [AudioPlayer] whose [setAudioSource] and [seek] complete
  /// immediately.
  MockAudioPlayer workingPlayer() {
    final player = MockAudioPlayer();
    when(player.setAudioSource(any,
        preload: anyNamed('preload'),
        initialPosition: anyNamed('initialPosition'),
        initialIndex: anyNamed('initialIndex'),
    )).thenAnswer((_) async => Duration.zero);
    when(player.seek(any)).thenAnswer((_) async {});
    return player;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Test cases — BUG-07-T01, T02, T03
  // ═══════════════════════════════════════════════════════════════════════════

  group('BUG-07: preloadAudioSource timeout', () {
    // ── BUG-07-T01: setAudioSource hangs -> 10s timeout -> function completes
    //    without throwing (queue restoration continues)
    //
    // Scenario: setAudioSource never completes. The timeout should fire after
    // 10 seconds and the function should throw a TimeoutException, which the
    // caller catches.

    test(
        'BUG-07-T01: setAudioSource hangs -> timeout after 10s -> throws TimeoutException',
        () async {
      final storage = fakeStorage('test-password');
      final player = hangingPlayer();

      // preloadAudioSource should throw TimeoutException after ~10 seconds.
      final future = preloadAudioSource(
        storage: storage,
        connectionId: 1,
        baseUrl: 'http://192.168.1.1:8080',
        filePath: '/music/song.mp3',
        username: 'admin',
        player: player,
        startPositionMs: 5000,
      );

      // Expect a TimeoutException within 15 seconds.
      expect(
        future,
        throwsA(isA<TimeoutException>()),
        reason: 'setAudioSource hang should trigger 10s timeout',
      );

      // Wait for the timeout to fire (with a generous test-level timeout).
      try {
        await future.timeout(const Duration(seconds: 15));
      } catch (_) {
        // Expected: TimeoutException from .timeout or from the pre-load.
      }

      // Verify setAudioSource was called (pre-load was attempted).
      verify(player.setAudioSource(any,
          preload: anyNamed('preload'),
          initialPosition: anyNamed('initialPosition'),
          initialIndex: anyNamed('initialIndex'),
      )).called(1);

      // seek should NOT have been called because setAudioSource hung and
      // the timeout fired before it could reach the seek call.
      verifyNever(player.seek(any));
    });

    // ── BUG-07-T02: Normal startup -> pre-load succeeds -> mini player bar
    //    immediately available (regression)
    //
    // Scenario: Both storage.read and setAudioSource/seek complete normally.
    // The function returns without error.

    test('BUG-07-T02: normal startup -> pre-load succeeds -> regression',
        () async {
      final storage = fakeStorage('test-password');
      final player = workingPlayer();

      // Should complete without error.
      await preloadAudioSource(
        storage: storage,
        connectionId: 1,
        baseUrl: 'http://192.168.1.1:8080',
        filePath: '/music/song.mp3',
        username: 'admin',
        player: player,
        startPositionMs: 5000,
      ).timeout(const Duration(seconds: 5));

      // setAudioSource was called once
      verify(player.setAudioSource(any,
          preload: anyNamed('preload'),
          initialPosition: anyNamed('initialPosition'),
          initialIndex: anyNamed('initialIndex'),
      )).called(1);

      // seek was called because startPositionMs != null
      verify(player.seek(const Duration(milliseconds: 5000))).called(1);
    });

    // ── BUG-07-T03: NAS unreachable -> storage.read hangs -> safeStorageRead
    //    returns null after 5s -> pre-load skipped silently
    //
    // Scenario: storage.read itself hangs (NAS infrastructure unreachable).
    // safeStorageRead has a 5-second timeout that returns null, so
    // preloadAudioSource sees null password and returns without error.

    test('BUG-07-T03: NAS unreachable -> storage.read hangs -> '
        'pre-load skipped silently', () async {
      final storage = hangingStorage();
      final player = workingPlayer();

      // preloadAudioSource should complete without error because
      // safeStorageRead returns null after 5s timeout, and null password
      // means pre-load is skipped.
      await preloadAudioSource(
        storage: storage,
        connectionId: 1,
        baseUrl: 'http://192.168.1.1:8080',
        filePath: '/music/song.mp3',
        username: 'admin',
        player: player,
      );

      // Player was never touched because storage.read returned null.
      verifyNever(player.setAudioSource(any,
          preload: anyNamed('preload'),
          initialPosition: anyNamed('initialPosition'),
          initialIndex: anyNamed('initialIndex'),
      ));
      verifyNever(player.seek(any));
    });

    // ── BUG-07-T04: No password stored -> pre-load skipped silently
    //
    // Scenario: storage.read returns null (no password saved). The function
    // should return without attempting to load the audio source.

    test('BUG-07-T04: no password -> pre-load skipped silently', () async {
      final storage = fakeStorage(null);
      final player = workingPlayer();

      // Should complete without error and without calling the player.
      await preloadAudioSource(
        storage: storage,
        connectionId: 1,
        baseUrl: 'http://192.168.1.1:8080',
        filePath: '/music/song.mp3',
        username: 'admin',
        player: player,
      ).timeout(const Duration(seconds: 5));

      // Player was never touched because there was no password.
      verifyNever(player.setAudioSource(any,
          preload: anyNamed('preload'),
          initialPosition: anyNamed('initialPosition'),
          initialIndex: anyNamed('initialIndex'),
      ));
      verifyNever(player.seek(any));
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

/// Fake [FlutterSecureStorage] that never completes (simulates hung storage).
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
