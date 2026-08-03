// test/features/coverage/bug_bug32_repro_test.dart
// BUG-32 门禁测试（spec: docs/features/BUG-32.md）
//
// 来源：docs/cr/cr-20260724-0110.md SVC4 + SVC5
//
// SVC4: safeStorageRead 超时曾返回 null，调用方无法区分"无值"与"超时"。
//       修复后超时抛 SecureStorageTimeoutException，无值仍返回 null；
//       4 个调用方均对超时做区分处理（BUG-32-S1 / INV1 / INV2）。
// SVC5: moveTaskToBack 的 MethodChannel Future 曾未处理，原生层
//       PlatformException（Activity 已销毁）会成为未处理异步错误。
//       修复后 unawaited + catchError 吞错（BUG-32-S2 / INV3）。
//
// 时间相关用例使用 fake_async 模拟 5s 超时；MethodChannel 用例通过
// TestDefaultBinaryMessengerBinding mock handler 注入 PlatformException。

import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:nas_audio_player/core/network/webdav_client.dart';
import 'package:nas_audio_player/core/services/audio_source_builder.dart';
import 'package:nas_audio_player/core/services/background_service.dart';
import 'package:nas_audio_player/core/services/storage_utils.dart';
import 'package:nas_audio_player/features/browser/browser_provider.dart';
import 'package:nas_audio_player/features/connection/connection_provider.dart';
import 'package:nas_audio_player/shared/models/connection_config.dart';

import '../../helpers/fake_webdav_client.dart';
import '../../helpers/mock_audio_player.dart';

// ── Fakes ────────────────────────────────────────────────────────────────────

/// Fake [FlutterSecureStorage] whose [read] never completes (hung Keystore).
class _HangingReadStorage extends FlutterSecureStorage {
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
    return Completer<String?>().future;
  }
}

/// Fake [FlutterSecureStorage] whose [write] never completes.
class _HangingWriteStorage extends FlutterSecureStorage {
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
    return Completer<void>().future;
  }
}

/// Fake [FlutterSecureStorage] whose [delete] never completes.
class _HangingDeleteStorage extends FlutterSecureStorage {
  @override
  Future<void> delete({
    required String key,
    IOSOptions? iOptions = IOSOptions.defaultOptions,
    AndroidOptions? aOptions = AndroidOptions.defaultOptions,
    LinuxOptions? lOptions = LinuxOptions.defaultOptions,
    WindowsOptions? wOptions = WindowsOptions.defaultOptions,
    MacOsOptions? mOptions = MacOsOptions.defaultOptions,
    WebOptions? webOptions = WebOptions.defaultOptions,
  }) {
    return Completer<void>().future;
  }
}

/// Fake [FlutterSecureStorage] backed by an in-memory map (null = no value).
class _MapStorage extends FlutterSecureStorage {
  _MapStorage(this._map);
  final Map<String, String> _map;

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
    return _map[key];
  }
}

/// Fake [FlutterSecureStorage] whose [read] throws a non-timeout error.
class _ThrowingReadStorage extends FlutterSecureStorage {
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
    throw Exception('simulated keystore failure');
  }
}

/// A [MockAudioPlayer] that counts touches, so "player was never touched"
/// can be asserted without Mockito argument matchers.
class _SpyAudioPlayer extends MockAudioPlayer {
  int setAudioSourceCalls = 0;
  int seekCalls = 0;

  @override
  Future<Duration?> setAudioSource(AudioSource source,
      {bool preload = true,
      int? initialIndex,
      Duration? initialPosition}) async {
    setAudioSourceCalls++;
    return Duration.zero;
  }

  @override
  Future<void> seek(Duration? position, {int? index}) async {
    seekCalls++;
  }
}

final _conn = ConnectionConfig(
  id: 1,
  name: 'NAS',
  url: 'http://nas.example.com',
  username: 'admin',
  isActive: true,
  createdAt: DateTime(2026, 1, 1),
  updatedAt: DateTime(2026, 1, 1),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ═══════════════════════════════════════════════════════════════════════════
  // BUG-32-S1 / INV1: safeStorageRead 超时抛异常，无值返回 null，两者可区分
  // ═══════════════════════════════════════════════════════════════════════════

  group('BUG-32-S1 / INV1: safeStorageRead timeout vs no-value', () {
    test('S1-T01: read hangs -> throws SecureStorageTimeoutException after 5s',
        () {
      FakeAsync().run((async) {
        Object? error;
        String? value;
        var done = false;

        safeStorageRead(_HangingReadStorage(), key: 'connection_password_1')
            .then((v) {
          value = v;
          done = true;
        }).catchError((e) {
          error = e;
          done = true;
        });

        // 否定断言：5s 前不完成（超时窗未被缩短）。
        async.elapse(const Duration(seconds: 4));
        expect(done, isFalse,
            reason: 'must not complete before the 5s timeout');

        // 否定断言：超时不得返回 null（当前 BUG 的旧行为）。
        async.elapse(const Duration(seconds: 2));
        expect(done, isTrue, reason: 'must complete once the timeout fires');
        expect(value, isNull);
        expect(error, isA<SecureStorageTimeoutException>(),
            reason:
                'timeout must throw the dedicated exception, not return null');
        // 专用异常类型 ≠ TimeoutException → 调用方可精确 catch。
        expect(error, isNot(isA<TimeoutException>()));

        final ex = error! as SecureStorageTimeoutException;
        expect(ex.key, 'connection_password_1');
        expect(ex.timeout, const Duration(seconds: 5));
        expect(ex.toString(), contains('connection_password_1'));
        expect(ex.toString(), contains('5s'));
      });
    });

    test('S1-T02: key does not exist -> returns null, does NOT throw',
        () async {
      // 否定断言：key 不存在时不抛异常（超时才抛）。
      final result = await safeStorageRead(_MapStorage({}), key: 'missing');
      expect(result, isNull);
    });

    test('S1-T03: value present -> returned as-is (regression)', () async {
      final result = await safeStorageRead(
          _MapStorage({'connection_password_1': 'secret'}),
          key: 'connection_password_1');
      expect(result, 'secret');
    });

    test('S1-T04: non-timeout read error -> still returns null (unchanged)',
        () async {
      final result = await safeStorageRead(_ThrowingReadStorage(), key: 'k');
      expect(result, isNull,
          reason: 'only timeout throws; other errors keep the legacy null');
    });

    test(
        'S1-T05 negative: write/delete timeout behavior unchanged '
        '(still rethrow TimeoutException)', () {
      FakeAsync().run((async) {
        Object? writeError;
        Object? deleteError;

        safeStorageWrite(_HangingWriteStorage(), key: 'k', value: 'v')
            .catchError((e) {
          writeError = e;
        });
        safeStorageDelete(_HangingDeleteStorage(), key: 'k').catchError((e) {
          deleteError = e;
        });

        async.elapse(const Duration(seconds: 6));
        expect(writeError, isA<TimeoutException>(),
            reason: 'BUG-32 must not change safeStorageWrite timeout behavior');
        expect(deleteError, isA<TimeoutException>(),
            reason:
                'BUG-32 must not change safeStorageDelete timeout behavior');
        expect(writeError, isNot(isA<SecureStorageTimeoutException>()));
        expect(deleteError, isNot(isA<SecureStorageTimeoutException>()));
      });
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // BUG-32-INV2: 调用方区分"超时"与"无值"
  // ═══════════════════════════════════════════════════════════════════════════

  group('BUG-32-INV2: callers distinguish timeout from no-value', () {
    test(
        'INV2-T01 preloadAudioSource: timeout -> caught, logged, skipped '
        '(no propagation, player untouched)', () {
      FakeAsync().run((async) {
        final player = _SpyAudioPlayer();
        Object? error;
        var done = false;

        preloadAudioSource(
          storage: _HangingReadStorage(),
          connectionId: 1,
          baseUrl: 'http://nas.example.com',
          filePath: '/music/song.mp3',
          username: 'admin',
          player: player,
        ).then((_) {
          done = true;
        }).catchError((e) {
          error = e;
          done = true;
        });

        async.elapse(const Duration(seconds: 6));
        expect(done, isTrue);
        expect(error, isNull,
            reason: 'timeout must be handled inside preloadAudioSource '
                '(log + skip), not propagated to the caller');
        // 否定断言：超时跳过预加载 → player 完全不被触碰。
        expect(player.setAudioSourceCalls, 0);
        expect(player.seekCalls, 0);
      });
    });

    test(
        'INV2-T02 directoryContentsProvider: timeout -> '
        "WebDavException('读取密码超时，请重试'), NOT '密码未保存'", () {
      FakeAsync().run((async) {
        final container = ProviderContainer(overrides: [
          activeConnectionProvider.overrideWith((ref) async => _conn),
          secureStorageProvider.overrideWithValue(_HangingReadStorage()),
          webDavClientProvider.overrideWithValue(MockWebDavClient()),
        ]);

        Object? error;
        var done = false;
        container.read(directoryContentsProvider('/').future).then(
          (_) {
            done = true;
          },
          onError: (Object e) {
            error = e;
            done = true;
          },
        );

        async.elapse(const Duration(seconds: 6));
        expect(done, isTrue);
        expect(error, isA<WebDavException>());
        expect((error! as WebDavException).message, '读取密码超时，请重试',
            reason: 'timeout must surface a retryable message, '
                'not the no-value message');
        container.dispose();
      });
    });

    test(
        'INV2-T03 directoryContentsProvider: no value -> '
        "WebDavException('密码未保存') (unchanged)", () {
      FakeAsync().run((async) {
        final container = ProviderContainer(overrides: [
          activeConnectionProvider.overrideWith((ref) async => _conn),
          secureStorageProvider.overrideWithValue(_MapStorage({})),
          webDavClientProvider.overrideWithValue(MockWebDavClient()),
        ]);

        Object? error;
        var done = false;
        container.read(directoryContentsProvider('/').future).then(
          (_) {
            done = true;
          },
          onError: (Object e) {
            error = e;
            done = true;
          },
        );

        async.flushMicrotasks();
        expect(done, isTrue);
        expect(error, isA<WebDavException>());
        expect((error! as WebDavException).message, '密码未保存');
        container.dispose();
      });
    });

    test(
        'INV2-T04 startupValidationProvider: timeout -> error result with '
        "'读取密码超时，请重试', NOT authError/networkError", () {
      FakeAsync().run((async) {
        final container = ProviderContainer(overrides: [
          activeConnectionProvider.overrideWith((ref) async => _conn),
          secureStorageProvider.overrideWithValue(_HangingReadStorage()),
          webDavClientProvider.overrideWithValue(MockWebDavClient()),
        ]);

        WebDavValidationResult? result;
        var done = false;
        container.read(startupValidationProvider.future).then((r) {
          result = r;
          done = true;
        });

        async.elapse(const Duration(seconds: 6));
        expect(done, isTrue);
        expect(result, isNotNull);
        // 否定断言：超时不得再被当成 authError（无密码）或 networkError。
        expect(result!.status, WebDavValidationStatus.error);
        expect(result!.status, isNot(WebDavValidationStatus.authError));
        expect(result!.status, isNot(WebDavValidationStatus.networkError));
        expect(result!.message, '读取密码超时，请重试');
        expect(result!.isSuccess, isFalse);
        container.dispose();
      });
    });

    test(
        'INV2-T05 startupValidationProvider: no value -> authError '
        '(unchanged)', () {
      FakeAsync().run((async) {
        final container = ProviderContainer(overrides: [
          activeConnectionProvider.overrideWith((ref) async => _conn),
          secureStorageProvider.overrideWithValue(_MapStorage({})),
          webDavClientProvider.overrideWithValue(MockWebDavClient()),
        ]);

        WebDavValidationResult? result;
        var done = false;
        container.read(startupValidationProvider.future).then((r) {
          result = r;
          done = true;
        });

        async.flushMicrotasks();
        expect(done, isTrue);
        expect(result, isNotNull);
        expect(result!.status, WebDavValidationStatus.authError,
            reason: 'genuinely missing password keeps the authError path');
        container.dispose();
      });
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // BUG-32-S2 / INV3: moveTaskToBack fire-and-forget 错误处理
  // ═══════════════════════════════════════════════════════════════════════════

  group('BUG-32-S2 / INV3: moveTaskToBack async error handling', () {
    const channel = MethodChannel('com.example.nas_audio_player/background');

    void setHandler(Future<Object?>? Function(MethodCall call)? handler) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, handler);
      addTearDown(() => TestDefaultBinaryMessengerBinding
          .instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null));
    }

    test(
        'S2-T01: native PlatformException (Activity destroyed) -> swallowed, '
        'no unhandled async error', () async {
      final calls = <MethodCall>[];
      setHandler((call) async {
        calls.add(call);
        throw PlatformException(code: 'ACTIVITY_DESTROYED');
      });

      final unhandled = <Object>[];
      runZonedGuarded(moveTaskToBack, (e, st) => unhandled.add(e));
      await pumpEventQueue(times: 50);

      // 否定断言：Activity 销毁后不产生 unhandled async error。
      expect(unhandled, isEmpty,
          reason: 'catchError must swallow the PlatformException');
      expect(calls, hasLength(1));
      expect(calls.single.method, 'moveTaskToBack');
    });

    test('S2-T02: normal path -> channel invoked, behavior unchanged',
        () async {
      final calls = <MethodCall>[];
      setHandler((call) async {
        calls.add(call);
        return null;
      });

      final unhandled = <Object>[];
      runZonedGuarded(moveTaskToBack, (e, st) => unhandled.add(e));
      await pumpEventQueue(times: 50);

      expect(calls, hasLength(1));
      expect(calls.single.method, 'moveTaskToBack');
      expect(unhandled, isEmpty);
    });

    test(
        'S2-T03: no plugin implementation (non-Android) -> '
        'MissingPluginException swallowed, no-op', () async {
      // 无 mock handler → invokeMethod 以 MissingPluginException 完成。
      setHandler(null);

      final unhandled = <Object>[];
      runZonedGuarded(moveTaskToBack, (e, st) => unhandled.add(e));
      await pumpEventQueue(times: 50);

      expect(unhandled, isEmpty,
          reason: 'non-Android no-op path must not surface an async error');
    });
  });
}
