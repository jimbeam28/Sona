// test/features/connection/bug_14_repro_test.dart
// CON2/NET7 (docs/cr/cr-20260724-0110) repro + regression guards:
//
//   CON2 — a URL carrying `user:pass@` credentials passed validateUrl(), so
//          the plaintext password landed in the SQLite `connections.url`
//          column (INV6 violation: passwords live only in secure storage).
//   NET7 — every debugPrint site that echoes a URL printed userinfo verbatim;
//          main.dart's installLogBufferHook mirrors debugPrint into LogBuffer
//          (visible at /logs in debug builds), leaking the password.
//
// Fix under test:
//   1. validateUrl rejects any URL whose userinfo component is non-empty and
//      returns a clear message pointing at the username/password fields.
//   2. redactUrlForLog strips `…://user:pass@` from any string before it is
//      printed (defence in depth — log sites must never leak credentials even
//      if a userinfo URL slips past the validation gate, e.g. a legacy DB row).
//
// Pre-fix FAIL evidence: validateUrl('http://admin:secret@…') returned null
// and WebDavClient / ConnectionValidatorNotifier / startupValidationProvider
// echoed the URL with the password in plaintext.

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nas_audio_player/core/database/dao/connection_dao.dart';
import 'package:nas_audio_player/core/network/webdav_client.dart';
import 'package:nas_audio_player/features/connection/connection_provider.dart';
import 'package:nas_audio_player/features/connection/domain/connection_validator.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../helpers/fake_secure_storage.dart';
import '../../helpers/fake_webdav_client.dart';
import '../../helpers/test_database.dart';
import '../../helpers/test_factories.dart';

/// Runs [body] while capturing everything written through [debugPrint].
///
/// Production mirrors debugPrint into LogBuffer (installLogBufferHook in
/// main.dart), so whatever lands in [logs] is exactly what a debug build
/// exposes at /logs.
Future<T> captureDebugPrint<T>(
  Future<T> Function(List<String> logs) body,
) async {
  final logs = <String>[];
  final original = debugPrint;
  debugPrint = (String? message, {int? wrapWidth}) {
    if (message != null) logs.add(message);
  };
  try {
    return await body(logs);
  } finally {
    debugPrint = original;
  }
}

void main() {
  // ═══════════════════════════════════════════════════════════════════════════
  // CON2: the validation gate must reject URLs with embedded credentials
  // ═══════════════════════════════════════════════════════════════════════════

  group('CON2: validateUrl rejects userInfo URLs', () {
    test('http URL with user:pass@ is rejected', () {
      final error = validateUrl('http://admin:secret@nas.example.com');
      expect(error, isNotNull, reason: 'user:pass@ URL 必须被拒绝');
      expect(error, isNot(contains('secret')), reason: '错误文案不得回显用户输入的凭证');
    });

    test('https URL with user:pass@, port and path is rejected', () {
      expect(validateUrl('https://admin:secret@nas.example.com:5006/dav'),
          isNotNull);
    });

    test('scheme-less user:pass@host is rejected after normalisation', () {
      expect(validateUrl('admin:secret@nas.example.com'), isNotNull,
          reason: '裸 user:pass@host 补 http:// 后仍须拒绝');
    });

    test('URL with bare user@ (no password) is rejected too', () {
      expect(validateUrl('http://admin@nas.example.com'), isNotNull);
    });

    test(
        'password containing @ (multi-@ authority) is rejected with the '
        'userinfo-specific message', () {
      // Dart's Uri parser refuses multi-@ authorities outright (tryParse
      // returns null), so the explicit userInfo check cannot see them — the
      // validator must still reject with the credentials-specific message,
      // not fall back to the generic "invalid URL" text (复核修正).
      final error = validateUrl('http://admin:p@ss@nas.example.com');
      expect(error, isNotNull);
      expect(error, contains('用户名'), reason: '多 @ 变体也应提示把凭证填到用户名/密码栏');
      expect(error, contains('密码'));
      expect(error, isNot(contains('p@ss')), reason: '错误文案不得回显凭证');
    });

    test('error message guides user to the username/password fields', () {
      final error = validateUrl('http://admin:secret@nas.example.com');
      expect(error, contains('用户名'));
      expect(error, contains('密码'));
    });

    test('ordinary URLs still pass (no regression)', () {
      expect(validateUrl('http://192.168.1.100:5005'), isNull);
      expect(validateUrl('https://nas.example.com'), isNull);
      expect(validateUrl('192.168.1.100'), isNull, reason: '裸 IP 自动补全');
      expect(validateUrl('http://nas.local:8080'), isNull);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // CON2/NET7: redactUrlForLog — the defence-in-depth redaction helper
  // ═══════════════════════════════════════════════════════════════════════════

  group('CON2/NET7: redactUrlForLog strips userinfo', () {
    test('strips user:pass@ and keeps scheme/host/port/path', () {
      expect(redactUrlForLog('http://admin:secret@nas.example.com:5005/dav'),
          equals('http://nas.example.com:5005/dav'));
    });

    test('strips bare user@', () {
      expect(redactUrlForLog('https://admin@nas.example.com'),
          equals('https://nas.example.com'));
    });

    test('leaves URLs without userinfo untouched', () {
      expect(redactUrlForLog('http://192.168.1.100:5005'),
          equals('http://192.168.1.100:5005'));
      expect(redactUrlForLog('https://nas.example.com/dav'),
          equals('https://nas.example.com/dav'));
    });

    test('does not touch an @ in the path', () {
      expect(redactUrlForLog('https://nas.example.com/music/a@b.mp3'),
          equals('https://nas.example.com/music/a@b.mp3'));
    });

    test('strips userinfo fully when the password itself contains @', () {
      // Multi-@ authority: the strip must reach the LAST @ before the host.
      // Pre-复核修正 the regex stopped at the first @ and leaked the
      // password tail (`http://ss@nas.example.com…`).
      final redacted =
          redactUrlForLog('http://admin:p@ss@nas.example.com:5005/dav');
      expect(redacted, equals('http://nas.example.com:5005/dav'));
      expect(redacted, isNot(contains('ss@')), reason: '密码尾部不得残留在脱敏结果中');
    });

    test('multi-@ userinfo inside exception text is fully redacted', () {
      const text = 'ClientException: uri=http://admin:p@ss@nas.example.com';
      final redacted = redactUrlForLog(text);
      expect(redacted, isNot(contains('ss@')), reason: '首 @ 截断会残留密码尾部 ss@');
      expect(redacted, isNot(contains('admin')));
      expect(redacted, contains('nas.example.com'));
    });

    test('redacts userinfo embedded inside exception text', () {
      const text = 'ClientException: Connection failed, '
          'uri=http://admin:secret@nas.example.com:5005/dav';
      final redacted = redactUrlForLog(text);
      expect(redacted, isNot(contains('secret')));
      expect(redacted, contains('nas.example.com:5005/dav'),
          reason: '脱敏不得破坏 host/port/path 调试信息');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // NET7: log sites must never echo userinfo (even if validation is bypassed)
  // ═══════════════════════════════════════════════════════════════════════════

  group('NET7: WebDavClient.validate log redaction', () {
    test('entry debugPrint is redacted', () async {
      final client = WebDavClient(
        httpClient: MockClient((request) async => http.Response('', 207)),
      );
      await captureDebugPrint((logs) async {
        final result = await client.validate(
          url: 'http://admin:secret@nas.example.com',
          username: 'admin',
          password: 'form-password',
        );
        expect(result.isSuccess, isTrue);
        final all = logs.join('\n');
        expect(all, isNot(contains('secret')),
            reason: 'url 中的密码不得落 debugPrint/LogBuffer');
        expect(all, isNot(contains('form-password')), reason: '表单密码同样不得落日志');
        expect(all, contains('nas.example.com'), reason: 'host 仍应可见以便调试');
      });
    });

    test('entry debugPrint fully redacts multi-@ userinfo (password with @)',
        () async {
      final client = WebDavClient(
        httpClient: MockClient((request) async => http.Response('', 207)),
      );
      await captureDebugPrint((logs) async {
        await client.validate(
          url: 'http://admin:p@ss@nas.example.com',
          username: 'admin',
          password: 'x',
        );
        final all = logs.join('\n');
        expect(all, isNot(contains('ss@')), reason: '密码尾部不得残留（首 @ 截断型脱敏不彻底）');
        expect(all, isNot(contains('admin:p')));
      });
    });

    test('error-path debugPrint redacts exception uri', () async {
      final client = WebDavClient(
        httpClient: MockClient((request) async {
          throw http.ClientException(
              'Socket error uri=http://admin:secret@nas.example.com:5005/dav');
        }),
      );
      await captureDebugPrint((logs) async {
        final result = await client.validate(
          url: 'http://admin:secret@nas.example.com',
          username: 'admin',
          password: 'x',
        );
        expect(result.status, WebDavValidationStatus.networkError);
        expect(logs.join('\n'), isNot(contains('secret')),
            reason: '异常消息中的 uri 凭证须二次脱敏');
      });
    });
  });

  group('NET7: ConnectionValidatorNotifier log redaction', () {
    test('validating debugPrint is redacted', () async {
      final mockClient = MockWebDavClient()
        ..returnResult(WebDavValidationResult.success());
      final notifier = ConnectionValidatorNotifier(mockClient);
      await captureDebugPrint((logs) async {
        await notifier.validate(
          url: 'http://admin:secret@nas.example.com',
          username: 'admin',
          password: 'form-password',
        );
        final all = logs.join('\n');
        expect(all, isNot(contains('secret')));
        expect(all, isNot(contains('form-password')));
      });
    });
  });

  group('NET7: startupValidation log redaction (stored url, per-boot leak)',
      () {
    late Database db;
    late ConnectionDao dao;

    setUpAll(initSqfliteFfi);

    setUp(() async {
      db = await openTestDatabase(TestSchema.connections);
      dao = ConnectionDao();
    });

    tearDown(() async {
      await db.close();
    });

    test('startupValidation debugPrint redacts stored url userinfo', () async {
      // Simulates a legacy row whose url column still carries credentials.
      final id = await dao.insert(
        testConfig(
            isActive: true, url: 'http://admin:secret@nas.example.com:5005'),
        passwordKey: 'connection_password_1',
      );
      final storage = FakeSecureStorage()..setPassword(id, 'stored-pass');
      final mockClient = MockWebDavClient()
        ..returnResult(WebDavValidationResult.success());

      final container = ProviderContainer(overrides: [
        connectionDaoProvider.overrideWithValue(dao),
        secureStorageProvider.overrideWithValue(storage),
        webDavClientProvider.overrideWithValue(mockClient),
      ]);
      addTearDown(container.dispose);

      await captureDebugPrint((logs) async {
        final result = await container.read(startupValidationProvider.future);
        expect(result?.isSuccess, isTrue);
        final all = logs.join('\n');
        expect(all, isNot(contains('secret')),
            reason: '存量 url 中的密码每次启动都会被打进日志，须脱敏');
        expect(all, isNot(contains('stored-pass')));
      });
    });
  });
}
