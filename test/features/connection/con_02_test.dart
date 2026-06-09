// test/features/connection/con_02_test.dart
// CON-02: WebDAV connection validation — automated test suite
//
// Unit tests (CON-T10~T17): validation result handling, URL format check,
// startup auto-validation, and re-entry guard.

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:nas_audio_player/core/database/dao/connection_dao.dart';
import 'package:nas_audio_player/core/network/webdav_client.dart';
import 'package:nas_audio_player/features/connection/connection_provider.dart';
import 'package:nas_audio_player/shared/models/connection_config.dart';
import 'package:nas_audio_player/shared/models/nas_file.dart';

// ── Mocks ────────────────────────────────────────────────────────────────────────

/// Hand-rolled mock that returns configurable [WebDavValidationResult] values.
/// Tracks call count (for CON-T17) and supports hanging via [Completer].
class MockWebDavClient implements WebDavClientInterface {
  WebDavValidationResult? _result;
  Completer<WebDavValidationResult>? _completer;
  int callCount = 0;

  /// Configure a fixed result to return on every [validate] call.
  void setResult(WebDavValidationResult r) {
    _result = r;
    _completer = null;
  }

  /// Make [validate] hang until [c] is completed.
  void hang(Completer<WebDavValidationResult> c) {
    _completer = c;
    _result = null;
  }

  @override
  Future<WebDavValidationResult> validate({
    required String url,
    required String username,
    required String password,
    String basePath = '/',
  }) async {
    callCount++;
    if (_completer != null) return _completer!.future;
    return _result ?? WebDavValidationResult.networkError();
  }

  @override
  Future<List<NasFile>> listDirectory({
    required String url,
    required String username,
    required String password,
    required String path,
  }) async {
    throw UnimplementedError('listDirectory not needed for CON-02 tests');
  }
}

/// Minimal fake [ConnectionDao] that returns a pre-set active config.
/// Unused methods throw [UnimplementedError].
class FakeConnectionDao implements ConnectionDao {
  final ConnectionConfig? activeConfig;
  FakeConnectionDao({this.activeConfig});

  @override
  Future<ConnectionConfig?> findActive() async => activeConfig;

  @override
  Future<int> insert(ConnectionConfig config, {required String passwordKey}) =>
      throw UnimplementedError('insert not needed for CON-02 tests');

  @override
  Future<List<ConnectionConfig>> findAll() =>
      throw UnimplementedError('findAll not needed for CON-02 tests');

  @override
  Future<ConnectionConfig?> findById(int id) =>
      throw UnimplementedError('findById not needed for CON-02 tests');

  @override
  Future<String?> findPasswordKey(int id) =>
      throw UnimplementedError('findPasswordKey not needed for CON-02 tests');

  @override
  Future<int> update(ConnectionConfig config, {required String passwordKey}) =>
      throw UnimplementedError('update not needed for CON-02 tests');

  @override
  Future<void> setActive(int id) =>
      throw UnimplementedError('setActive not needed for CON-02 tests');

  @override
  Future<bool> delete(int id) =>
      throw UnimplementedError('delete not needed for CON-02 tests');

  @override
  Future<int> count() =>
      throw UnimplementedError('count not needed for CON-02 tests');
}

/// Minimal fake [FlutterSecureStorage] backed by an in-memory map.
class FakeSecureStorage extends FlutterSecureStorage {
  final Map<String, String> _store = {};

  void stub(String key, String value) => _store[key] = value;

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
}

/// HTTP client that throws on [send] — used to verify no network request is
/// made for invalid URLs (CON-T14).
class _ThrowingHttpClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    throw AssertionError('HTTP request should not be sent for invalid URL');
  }
}

// ── Helpers ──────────────────────────────────────────────────────────────────────

/// Builds a [ProviderContainer] that overrides [webDavClientProvider] with [mock].
ProviderContainer makeContainer(MockWebDavClient mock) {
  return ProviderContainer(
    overrides: [
      webDavClientProvider.overrideWithValue(mock),
    ],
  );
}

/// Sample active connection config used in startup-validation tests.
final _testConfig = ConnectionConfig(
  id: 1,
  name: 'Test NAS',
  url: 'http://192.168.1.100:5005',
  username: 'admin',
  basePath: '/dav',
  isActive: true,
  createdAt: DateTime(2024, 1, 1),
  updatedAt: DateTime(2024, 1, 1),
);

// ═══════════════════════════════════════════════════════════════════════════════════
// Unit tests — CON-T10~T17
// ═══════════════════════════════════════════════════════════════════════════════════

void main() {
  // ── CON-T10~T14: validation result handling ─────────────────────────────────

  group('CON-T10~T14 connection validation', () {
    // ── CON-T10: valid address + correct credentials → success ────────────────

    test('test_CON_T10_validAddress_correctCredentials_returnsSuccess',
        () async {
      final mock = MockWebDavClient();
      mock.setResult(WebDavValidationResult.success());

      final container = makeContainer(mock);
      addTearDown(container.dispose);

      await container.read(connectionValidatorProvider.notifier).validate(
            url: 'http://192.168.1.100:5005',
            username: 'admin',
            password: 'secret',
          );

      final state = container.read(connectionValidatorProvider);
      expect(state, isA<ValidationSuccess>(), reason: '有效地址+正确凭据应返回成功状态');
    });

    // ── CON-T11: correct address + wrong credentials → 401 error ──────────────

    test('test_CON_T11_validAddress_wrongCredentials_returnsAuthError',
        () async {
      final mock = MockWebDavClient();
      mock.setResult(WebDavValidationResult.authError());

      final container = makeContainer(mock);
      addTearDown(container.dispose);

      await container.read(connectionValidatorProvider.notifier).validate(
            url: 'http://192.168.1.100:5005',
            username: 'admin',
            password: 'wrong',
          );

      final state = container.read(connectionValidatorProvider);
      expect(state, isA<ValidationError>(), reason: '用户名或密码错误时应返回错误状态');
      expect(
        (state as ValidationError).message,
        equals('用户名或密码错误'),
        reason: '错误信息应为用户名或密码错误',
      );
    });

    // ── CON-T12: correct address + wrong base path → 404 error ────────────────

    test('test_CON_T12_validAddress_wrongBasePath_returnsPathNotFound',
        () async {
      final mock = MockWebDavClient();
      mock.setResult(WebDavValidationResult.pathNotFound());

      final container = makeContainer(mock);
      addTearDown(container.dispose);

      await container.read(connectionValidatorProvider.notifier).validate(
            url: 'http://192.168.1.100:5005',
            username: 'admin',
            password: 'secret',
            basePath: '/nonexistent',
          );

      final state = container.read(connectionValidatorProvider);
      expect(state, isA<ValidationError>(), reason: '基础路径不存在时应返回错误状态');
      expect(
        (state as ValidationError).message,
        equals('基础路径不存在，请检查路径设置'),
        reason: '错误信息应为基础路径不存在的提示',
      );
    });

    // ── CON-T13: unreachable address → request timeout → network error ────────

    test('test_CON_T13_unreachableAddress_returnsNetworkError', () async {
      final mock = MockWebDavClient();
      mock.setResult(WebDavValidationResult.networkError());

      final container = makeContainer(mock);
      addTearDown(container.dispose);

      await container.read(connectionValidatorProvider.notifier).validate(
            url: 'http://10.255.255.1:9999',
            username: 'admin',
            password: 'secret',
          );

      final state = container.read(connectionValidatorProvider);
      expect(state, isA<ValidationError>(), reason: '无法连接时应返回错误状态');
      expect(
        (state as ValidationError).message,
        equals('无法连接到服务器，请检查地址和网络'),
        reason: '错误信息应为无法连接的网络错误提示',
      );
    });

    // ── CON-T14: invalid URL format → no network request made ─────────────────

    test('test_CON_T14_invalidUrlFormat_noNetworkRequest', () async {
      // Use the REAL WebDavClient with a throwing HTTP client so that if
      // _httpClient.send() is ever called the test fails immediately.
      final webdav = WebDavClient(httpClient: _ThrowingHttpClient());
      final container = ProviderContainer(
        overrides: [
          webDavClientProvider.overrideWithValue(webdav),
        ],
      );
      addTearDown(container.dispose);

      // An empty URL normalises to "http://" which fails isValidWebDavUrl.
      // The real WebDavClient.validate() returns networkError() without
      // calling _httpClient.send() — which would throw.
      await container.read(connectionValidatorProvider.notifier).validate(
            url: '',
            username: 'admin',
            password: 'secret',
          );

      final state = container.read(connectionValidatorProvider);
      expect(state, isA<ValidationError>(), reason: '格式非法时应返回错误状态');
      expect(
        (state as ValidationError).message,
        equals('无法连接到服务器，请检查地址和网络'),
        reason: '格式非法时错误信息应为网络错误提示',
      );
    });
  });

  // ── CON-T15~T16: startup auto-validation ────────────────────────────────────

  group('CON-T15~T16 startup auto-validation', () {
    // ── CON-T15: app startup auto-validate → returns 207 (success) ────────────

    test('test_CON_T15_startupValidation_returnsSuccess', () async {
      final dao = FakeConnectionDao(activeConfig: _testConfig);

      final storage = FakeSecureStorage();
      storage.stub('connection_password_1', 'secret');

      final client = MockWebDavClient();
      client.setResult(WebDavValidationResult.success());

      final container = ProviderContainer(
        overrides: [
          connectionDaoProvider.overrideWithValue(dao),
          secureStorageProvider.overrideWithValue(storage),
          webDavClientProvider.overrideWithValue(client),
        ],
      );
      addTearDown(container.dispose);

      final result = await container.read(startupValidationProvider.future);

      expect(result, isNotNull, reason: '存在活跃连接时应返回验证结果');
      expect(result!.isSuccess, isTrue, reason: '有效连接启动验证应返回成功');
      expect(result.status, equals(WebDavValidationStatus.success),
          reason: '验证状态应为success');
    });

    // ── CON-T16: app startup auto-validate → returns 401 (auth error) ─────────

    test('test_CON_T16_startupValidation_returnsAuthError', () async {
      final dao = FakeConnectionDao(activeConfig: _testConfig);

      final storage = FakeSecureStorage();
      storage.stub('connection_password_1', 'secret');

      final client = MockWebDavClient();
      client.setResult(WebDavValidationResult.authError());

      final container = ProviderContainer(
        overrides: [
          connectionDaoProvider.overrideWithValue(dao),
          secureStorageProvider.overrideWithValue(storage),
          webDavClientProvider.overrideWithValue(client),
        ],
      );
      addTearDown(container.dispose);

      final result = await container.read(startupValidationProvider.future);

      expect(result, isNotNull, reason: '存在活跃连接时应返回验证结果');
      expect(result!.isSuccess, isFalse, reason: '认证失败时验证结果应为非成功');
      expect(result.status, equals(WebDavValidationStatus.authError),
          reason: '验证状态应为authError');
      expect(result.message, equals('用户名或密码错误'), reason: '错误信息应为用户名或密码错误');
    });
  });

  // ── CON-T17: re-entry guard during loading ──────────────────────────────────

  group('CON-T17 re-entry guard', () {
    test('test_CON_T17_duplicateClickDuringLoading_isIgnored', () async {
      final completer = Completer<WebDavValidationResult>();
      final mock = MockWebDavClient();
      mock.hang(completer);

      final container = makeContainer(mock);
      addTearDown(container.dispose);

      // First call — start validation, don't await (it hangs on the completer)
      final firstFuture =
          container.read(connectionValidatorProvider.notifier).validate(
                url: 'http://192.168.1.100:5005',
                username: 'admin',
                password: 'secret',
              );

      // After the synchronous part of the first call, state should be loading
      expect(
        container.read(connectionValidatorProvider),
        isA<ValidationLoading>(),
        reason: '首次验证发起后状态应为loading',
      );

      // Second call — should be a no-op due to the re-entry guard
      await container.read(connectionValidatorProvider.notifier).validate(
            url: 'http://192.168.1.100:5005',
            username: 'admin',
            password: 'secret',
          );

      // Complete the first (only) validate call
      completer.complete(WebDavValidationResult.success());
      await firstFuture;

      // Verify the client was called exactly once
      expect(mock.callCount, equals(1), reason: 'loading状态下再次点击应忽略，客户端只被调用一次');

      // Verify final state is success
      expect(
        container.read(connectionValidatorProvider),
        isA<ValidationSuccess>(),
        reason: '验证完成后状态应为成功',
      );
    });
  });
}
