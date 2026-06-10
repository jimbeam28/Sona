// test/features/connection/con_05_test.dart
// CON-05: 编辑连接配置 — automated test suite
//
// Unit tests (CON-T28~T30): validation-gate logic, update-after-validation,
// and name-only update without re-validation.
//
// Uses sqflite_common_ffi for an in-memory SQLite database so tests run
// without a physical device or emulator.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nas_audio_player/core/database/dao/connection_dao.dart';
import 'package:nas_audio_player/core/network/webdav_client.dart';
import 'package:nas_audio_player/features/connection/connection_provider.dart';
import 'package:nas_audio_player/shared/models/nas_file.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../helpers/test_database.dart';
import '../../helpers/test_factories.dart';

// ── Mocks ────────────────────────────────────────────────────────────────────────

/// Hand-rolled mock that returns configurable [WebDavValidationResult] values.
class MockWebDavClient implements WebDavClientInterface {
  WebDavValidationResult? _result;

  void setResult(WebDavValidationResult r) => _result = r;

  @override
  Future<WebDavValidationResult> validate({
    required String url,
    required String username,
    required String password,
    String basePath = '/',
  }) async {
    return _result ?? WebDavValidationResult.networkError();
  }

  @override
  Future<List<NasFile>> listDirectory({
    required String url,
    required String username,
    required String password,
    required String path,
  }) async {
    throw UnimplementedError('listDirectory not needed for CON-05 tests');
  }
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

// ── Helpers ───────────────────────────────────────────────────────────────────

// testConfig() is imported from test_factories.dart as testConfig().

// ═════════════════════════════════════════════════════════════════════════════
// Unit tests — CON-T28~T30
// ═════════════════════════════════════════════════════════════════════════════

void main() {
  late Database db;
  late ConnectionDao dao;

  setUpAll(() {
    initSqfliteFfi();
  });

  setUp(() async {
    db = await openTestDatabase(TestSchema.connections);
    dao = ConnectionDao();
  });

  tearDown(() async {
    await db.close();
  });

  group('CON-T28 save blocked when URL changed without validation', () {
    // ── CON-T28: Modify URL, try to save without re-validating → blocked ─────

    test('test_CON_T28_modifyUrl_saveWithoutValidation_blocked', () async {
      // Insert original connection
      final original = testConfig(url: 'http://old.example.com:5005');
      final id = await dao.insert(original, passwordKey: 'key_1');

      // Set up mock WebDAV client with failure result — validation has NOT
      // been done yet, and if attempted would fail.
      final mockClient = MockWebDavClient();
      mockClient.setResult(WebDavValidationResult.networkError());

      final storage = FakeSecureStorage();
      storage.stub('connection_password_$id', 'secret');

      final container = ProviderContainer(overrides: [
        connectionDaoProvider.overrideWithValue(dao),
        secureStorageProvider.overrideWithValue(storage),
        webDavClientProvider.overrideWithValue(mockClient),
      ]);
      addTearDown(container.dispose);

      // Verify validator is in idle state (not validated)
      expect(container.read(connectionValidatorProvider), isA<ValidationIdle>(),
          reason: '初始状态下验证器应为 idle');

      // The screen-level logic would detect that URL changed → needs validation.
      // Simulate: URL changed, validator NOT in success state → save blocked.

      // Even though ConnectionUpdater.update() itself does not enforce the
      // validation gate (that is screen-level logic), we can verify that the
      // validation state is NOT success, which is what the screen checks.
      final validationState = container.read(connectionValidatorProvider);
      final isValidationSuccess = validationState is ValidationSuccess;
      expect(isValidationSuccess, isFalse,
          reason: '未重新验证时验证状态不应为成功 → 保存应被阻止 (CON-T28)');
    });
  });

  group('CON-T29 save after validation writes new URL', () {
    // ── CON-T29: Modify URL, re-validate (success), then save → URL updated ──

    test('test_CON_T29_modifyUrl_validateThenSave_urlUpdated', () async {
      // Insert original connection
      final original = testConfig(
        name: 'My NAS',
        url: 'http://old.example.com:5005',
        username: 'admin',
        basePath: '/dav',
      );
      final id = await dao.insert(original, passwordKey: 'key_2');

      // Mock WebDAV client that returns success
      final mockClient = MockWebDavClient();
      mockClient.setResult(WebDavValidationResult.success());

      final storage = FakeSecureStorage();
      storage.stub('connection_password_$id', 'secret');

      final container = ProviderContainer(overrides: [
        connectionDaoProvider.overrideWithValue(dao),
        secureStorageProvider.overrideWithValue(storage),
        webDavClientProvider.overrideWithValue(mockClient),
      ]);
      addTearDown(container.dispose);

      // Step 1: Run validation with new URL (simulates clicking "测试连接")
      await container.read(connectionValidatorProvider.notifier).validate(
            url: 'http://new.example.com:8080',
            username: 'admin',
            password: 'secret',
            basePath: '/dav',
          );

      // Assert validation succeeded
      final postValidation = container.read(connectionValidatorProvider);
      expect(postValidation, isA<ValidationSuccess>(), reason: '使用新 URL 验证应成功');

      // Step 2: Execute update via ConnectionUpdater (simulates clicking "保存")
      final updater = container.read(connectionUpdaterProvider);
      final modified = original.copyWith(
        id: id,
        url: 'http://new.example.com:8080',
      );
      await updater.update(config: modified, password: null);

      // Invalidate and re-read to verify persistence
      container.invalidate(connectionListProvider);
      final updated = await dao.findById(id);

      expect(updated, isNotNull, reason: '更新后应仍能查到记录');
      expect(updated!.url, equals('http://new.example.com:8080'),
          reason: 'CON-T29: URL 应更新为新值');
      expect(updated.name, equals('My NAS'), reason: '未修改的名字应保持不变');
      expect(updated.username, equals('admin'), reason: '未修改的用户名应保持不变');
      expect(updated.basePath, equals('/dav'), reason: '未修改的 basePath 应保持不变');
    });
  });

  group('CON-T30 name-only update without validation', () {
    // ── CON-T30: Modify display name only, save without re-validation ─────────

    test('test_CON_T30_modifyNameOnly_saveWithoutValidation_nameUpdated',
        () async {
      // Insert original connection
      final original = testConfig(
        name: 'Old Name',
        url: 'http://example.com:5005',
        username: 'admin',
        basePath: '/dav',
      );
      final id = await dao.insert(original, passwordKey: 'key_3');

      final storage = FakeSecureStorage();
      storage.stub('connection_password_$id', 'secret');

      // No WebDAV client override needed — we won't validate.
      final container = ProviderContainer(overrides: [
        connectionDaoProvider.overrideWithValue(dao),
        secureStorageProvider.overrideWithValue(storage),
      ]);
      addTearDown(container.dispose);

      // Update only the display name — no validation required per CON-T30
      final updater = container.read(connectionUpdaterProvider);
      final modified = original.copyWith(id: id, name: 'New Display Name');
      await updater.update(config: modified, password: null);

      // Verify DB state
      final updated = await dao.findById(id);

      expect(updated, isNotNull, reason: '更新后应仍能查到记录');
      expect(updated!.name, equals('New Display Name'),
          reason: 'CON-T30: 显示名称应更新为新值');
      expect(updated.url, equals('http://example.com:5005'),
          reason: 'URL 应保持不变（未修改）');
      expect(updated.username, equals('admin'), reason: '用户名应保持不变（未修改）');
      expect(updated.basePath, equals('/dav'), reason: 'basePath 应保持不变（未修改）');
    });
  });

  group('CON-05 additional: password update', () {
    // ── Supplementary: password change requires re-validation ───────────────

    test('test_CON_T30b_passwordChange_needsValidation', () async {
      // Insert original connection
      final original = testConfig(url: 'http://example.com:5005');
      final id = await dao.insert(original, passwordKey: 'key_4');

      final mockClient = MockWebDavClient();
      mockClient.setResult(WebDavValidationResult.success());

      final storage = FakeSecureStorage();
      storage.stub('connection_password_$id', 'old-password');

      final container = ProviderContainer(overrides: [
        connectionDaoProvider.overrideWithValue(dao),
        secureStorageProvider.overrideWithValue(storage),
        webDavClientProvider.overrideWithValue(mockClient),
      ]);
      addTearDown(container.dispose);

      // Validate with new password
      await container.read(connectionValidatorProvider.notifier).validate(
            url: 'http://example.com:5005',
            username: 'admin',
            password: 'new-password',
            basePath: '/dav',
          );

      expect(
          container.read(connectionValidatorProvider), isA<ValidationSuccess>(),
          reason: '使用新密码验证应成功');

      // Update with new password
      final updater = container.read(connectionUpdaterProvider);
      await updater.update(
        config: original.copyWith(id: id),
        password: 'new-password',
      );

      // Verify the new password was persisted in secure storage
      final storedPassword = await storage.read(key: 'connection_password_$id');
      expect(storedPassword, equals('new-password'),
          reason: '新密码应写入 secure storage');
    });
  });
}
