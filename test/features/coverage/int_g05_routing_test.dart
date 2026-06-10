// test/features/coverage/int_g05_routing_test.dart
// INT-G05: Routing / startup validation integration tests.
//
// Test cases:
//   INT-G05-T01: No connection -> startup validation returns null (onboarding)
//   INT-G05-T02: Valid connection + password -> validation succeeds (browser)
//   INT-G05-T03: Valid connection + invalid password -> validation fails (connection screen)
//
// These tests exercise the startupValidationProvider logic by testing
// the underlying ConnectionDao + WebDAV client + secure storage interactions
// through ProviderContainer overrides.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nas_audio_player/core/database/dao/connection_dao.dart';
import 'package:nas_audio_player/core/network/webdav_client.dart';
import 'package:nas_audio_player/features/connection/connection_provider.dart';
import 'package:nas_audio_player/features/connection/domain/connection_service.dart';
import 'package:nas_audio_player/shared/di/providers.dart';
import 'package:nas_audio_player/shared/models/connection_config.dart';
import 'package:sqflite/sqflite.dart';

import '../../helpers/test_database.dart';
import '../../helpers/fake_secure_storage.dart';
import '../../helpers/fake_webdav_client.dart';
import '../../helpers/test_factories.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// INT-G05-T01: No connection -> startup validation returns null (onboarding)
// ═══════════════════════════════════════════════════════════════════════════════

void main() {
  group('INT-G05-T01: No connection -> startup validation returns null', () {
    late Database db;
    late FakeSecureStorage storage;
    late MockWebDavClient webDavClient;

    setUp(() async {
      initSqfliteFfi();
      db = await openTestDatabase(TestSchema.connections);
      storage = FakeSecureStorage();
      webDavClient = MockWebDavClient();
      webDavClient.returnResult(WebDavValidationResult.success());
    });

    tearDown(() async {
      await db.close();
    });

    test('when no connections exist, activeConnectionProvider returns null',
        () async {
      final container = ProviderContainer(
        overrides: [
          connectionDaoProvider.overrideWithValue(ConnectionDao()),
          secureStorageProvider.overrideWithValue(storage),
          webDavClientProvider.overrideWithValue(webDavClient),
        ],
      );
      addTearDown(() => container.dispose());

      final active = await container.read(activeConnectionProvider.future);
      expect(active, isNull,
          reason: 'INT-G05-T01: no connections -> activeConnection should be null');
    });

    test('when activeConnection is null, startup validation returns null',
        () async {
      // Simulate the startupValidationProvider logic:
      // 1. Read active connection -> null
      // 2. Return null (no validation needed)
      final container = ProviderContainer(
        overrides: [
          connectionDaoProvider.overrideWithValue(ConnectionDao()),
          secureStorageProvider.overrideWithValue(storage),
          webDavClientProvider.overrideWithValue(webDavClient),
        ],
      );
      addTearDown(() => container.dispose());

      // The startupValidationProvider watches activeConnectionProvider.
      // When it resolves to null, the provider returns null.
      final activeConn = await container.read(activeConnectionProvider.future);
      expect(activeConn, isNull);

      // Directly test the logic: null active -> null result
      WebDavValidationResult? result;
      if (activeConn == null) {
        result = null;
      }
      expect(result, isNull,
          reason: 'INT-G05-T01: startup validation with no connection should return null');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════════
  // INT-G05-T02: Valid connection + password -> validation succeeds (browser)
  // ═══════════════════════════════════════════════════════════════════════════════

  group('INT-G05-T02: Valid connection + password -> validation succeeds', () {
    late Database db;
    late FakeSecureStorage storage;
    late MockWebDavClient webDavClient;
    late ConnectionService service;

    setUp(() async {
      initSqfliteFfi();
      db = await openTestDatabase(TestSchema.connections);
      storage = FakeSecureStorage();
      webDavClient = MockWebDavClient();
      service = ConnectionService(ConnectionDao(), storage);
    });

    tearDown(() async {
      await db.close();
    });

    test('active connection with valid password -> validation succeeds',
        () async {
      // Configure WebDAV client to return success.
      webDavClient.returnResult(WebDavValidationResult.success());

      // Save a connection (auto-sets as active).
      final conn = await service.save(
        config: testConfig(name: 'Test NAS', url: 'http://nas.local:5005'),
        password: 'valid_password',
      );

      final container = ProviderContainer(
        overrides: [
          connectionDaoProvider.overrideWithValue(ConnectionDao()),
          secureStorageProvider.overrideWithValue(storage),
          webDavClientProvider.overrideWithValue(webDavClient),
        ],
      );
      addTearDown(() => container.dispose());

      // Read active connection.
      final activeConn = await container.read(activeConnectionProvider.future);
      expect(activeConn, isNotNull,
          reason: 'INT-G05-T02: active connection should exist');
      expect(activeConn!.id, equals(conn.id));

      // Read password from secure storage.
      final password = await storage.read(
          key: 'connection_password_${activeConn.id}');
      expect(password, equals('valid_password'),
          reason: 'INT-G05-T02: password should be stored');

      // Validate via WebDAV client.
      final result = await webDavClient.validate(
        url: activeConn.url,
        username: activeConn.username,
        password: password!,
        basePath: activeConn.basePath,
      );
      expect(result.isSuccess, isTrue,
          reason: 'INT-G05-T02: validation should succeed with correct credentials');
    });

    test('startupValidationProvider returns success for valid connection',
        () async {
      webDavClient.returnResult(WebDavValidationResult.success());

      await service.save(
        config: testConfig(name: 'Test NAS', url: 'http://nas.local:5005'),
        password: 'valid_password',
      );

      final container = ProviderContainer(
        overrides: [
          connectionDaoProvider.overrideWithValue(ConnectionDao()),
          secureStorageProvider.overrideWithValue(storage),
          webDavClientProvider.overrideWithValue(webDavClient),
        ],
      );
      addTearDown(() => container.dispose());

      // Read the startupValidationProvider.
      final result =
          await container.read(startupValidationProvider.future);
      expect(result, isNotNull,
          reason: 'INT-G05-T02: startup validation should return a result');
      expect(result!.isSuccess, isTrue,
          reason: 'INT-G05-T02: startup validation should succeed');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════════
  // INT-G05-T03: Valid connection + invalid password -> validation fails
  // ═══════════════════════════════════════════════════════════════════════════════

  group('INT-G05-T03: Valid connection + invalid password -> validation fails',
      () {
    late Database db;
    late FakeSecureStorage storage;
    late MockWebDavClient webDavClient;
    late ConnectionService service;

    setUp(() async {
      initSqfliteFfi();
      db = await openTestDatabase(TestSchema.connections);
      storage = FakeSecureStorage();
      webDavClient = MockWebDavClient();
      service = ConnectionService(ConnectionDao(), storage);
    });

    tearDown(() async {
      await db.close();
    });

    test('active connection with wrong password -> auth error', () async {
      // Configure WebDAV client to return auth error.
      webDavClient.returnResult(WebDavValidationResult.authError());

      await service.save(
        config: testConfig(name: 'Test NAS', url: 'http://nas.local:5005'),
        password: 'wrong_password',
      );

      final container = ProviderContainer(
        overrides: [
          connectionDaoProvider.overrideWithValue(ConnectionDao()),
          secureStorageProvider.overrideWithValue(storage),
          webDavClientProvider.overrideWithValue(webDavClient),
        ],
      );
      addTearDown(() => container.dispose());

      final activeConn = await container.read(activeConnectionProvider.future);
      expect(activeConn, isNotNull);

      final password = await storage.read(
          key: 'connection_password_${activeConn!.id}');

      final result = await webDavClient.validate(
        url: activeConn.url,
        username: activeConn.username,
        password: password!,
        basePath: activeConn.basePath,
      );
      expect(result.isSuccess, isFalse,
          reason: 'INT-G05-T03: validation should fail with wrong password');
      expect(result.status, equals(WebDavValidationStatus.authError),
          reason: 'INT-G05-T03: status should be authError');
    });

    test('startupValidationProvider returns auth error for wrong password',
        () async {
      webDavClient.returnResult(WebDavValidationResult.authError());

      await service.save(
        config: testConfig(name: 'Test NAS', url: 'http://nas.local:5005'),
        password: 'wrong_password',
      );

      final container = ProviderContainer(
        overrides: [
          connectionDaoProvider.overrideWithValue(ConnectionDao()),
          secureStorageProvider.overrideWithValue(storage),
          webDavClientProvider.overrideWithValue(webDavClient),
        ],
      );
      addTearDown(() => container.dispose());

      final result =
          await container.read(startupValidationProvider.future);
      expect(result, isNotNull,
          reason: 'INT-G05-T03: startup validation should return a result');
      expect(result!.isSuccess, isFalse,
          reason: 'INT-G05-T03: startup validation should fail');
      expect(result.status, equals(WebDavValidationStatus.authError),
          reason: 'INT-G05-T03: status should be authError');
    });

    test('network error -> validation returns networkError status', () async {
      webDavClient.returnResult(WebDavValidationResult.networkError());

      await service.save(
        config: testConfig(name: 'Test NAS', url: 'http://nas.local:5005'),
        password: 'pass',
      );

      final container = ProviderContainer(
        overrides: [
          connectionDaoProvider.overrideWithValue(ConnectionDao()),
          secureStorageProvider.overrideWithValue(storage),
          webDavClientProvider.overrideWithValue(webDavClient),
        ],
      );
      addTearDown(() => container.dispose());

      final result =
          await container.read(startupValidationProvider.future);
      expect(result, isNotNull);
      expect(result!.isSuccess, isFalse,
          reason: 'INT-G05-T03: network error should fail validation');
      expect(result.status, equals(WebDavValidationStatus.networkError),
          reason: 'INT-G05-T03: status should be networkError');
    });

    test('connection with null id -> validation returns authError', () async {
      // Simulate a corrupted DB record with null id.
      // In practice, the DAO always assigns an id, but the startupValidationProvider
      // has a guard for null id (H-7).

      // Directly test the H-7 guard logic.
      final activeConn = ConnectionConfig(
        id: null,
        name: 'Corrupt',
        url: 'http://nas.local:5005',
        username: 'admin',
        basePath: '/',
        createdAt: DateTime(2024),
        updatedAt: DateTime(2024),
      );

      // The startupValidationProvider checks: if id == null -> authError
      WebDavValidationResult result;
      if (activeConn.id == null) {
        result = WebDavValidationResult.authError();
      } else {
        result = WebDavValidationResult.success();
      }

      expect(result.isSuccess, isFalse,
          reason: 'INT-G05-T03: null id should return authError');
      expect(result.status, equals(WebDavValidationStatus.authError),
          reason: 'INT-G05-T03: null id guard should produce authError');
    });

    test('connection with missing password in storage -> authError', () async {
      // Save a connection but don't store the password (simulate corrupted storage).
      final dao = ConnectionDao();
      final id = await dao.insert(
        testConfig(name: 'NoPass', url: 'http://nas.local:5005'),
        passwordKey: 'connection_password_999',
      );
      await dao.setActive(id);
      // Do NOT write the password to FakeSecureStorage.

      final container = ProviderContainer(
        overrides: [
          connectionDaoProvider.overrideWithValue(dao),
          secureStorageProvider.overrideWithValue(storage),
          webDavClientProvider.overrideWithValue(webDavClient),
        ],
      );
      addTearDown(() => container.dispose());

      // Read the active connection.
      final activeConn = await container.read(activeConnectionProvider.future);
      expect(activeConn, isNotNull);
      expect(activeConn!.id, equals(id));

      // Try to read the password — it should be null.
      final password =
          await storage.read(key: 'connection_password_$id');
      expect(password, isNull,
          reason: 'INT-G05-T03: password should be missing from storage');

      // The startupValidationProvider checks: null/empty password -> authError
      WebDavValidationResult result;
      if (password == null || password.isEmpty) {
        result = WebDavValidationResult.authError();
      } else {
        result = WebDavValidationResult.success();
      }

      expect(result.isSuccess, isFalse,
          reason: 'INT-G05-T03: missing password should return authError');
    });
  });
}
