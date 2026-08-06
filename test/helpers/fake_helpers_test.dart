// test/helpers/fake_helpers_test.dart
// TEST-07 (docs/features/TEST-07.md §5.4) — helper 行为确认:
//
//   S6 — MockWebDavClient 默认 listDirectory 返回空列表（注释已修正，NET10）+ 错误注入生效
//   S7 — FakeSecureStorage.containsKey 走内存 map，不抛 MissingPluginException（CTR7）

import 'package:flutter_test/flutter_test.dart';
import 'package:nas_audio_player/core/network/webdav_client.dart';

import 'fake_secure_storage.dart';
import 'fake_webdav_client.dart';

void main() {
  group('TEST-07-S6: MockWebDavClient 错误注入', () {
    test('默认 listDirectory 返回空列表（注释修正后与实际一致）', () async {
      final client = MockWebDavClient();

      final result = await client.listDirectory(
        url: 'http://nas.example.com',
        username: 'u',
        password: 'p',
        path: '/',
      );

      expect(result, isEmpty,
          reason: '否定断言(NET10): 注释声称的默认行为必须是实际行为——返回空列表而非抛异常');
    });

    test('配置 listDirectoryError 后 listDirectory 抛出 WebDavException', () async {
      final client = MockWebDavClient()
        ..listDirectoryError =
            const WebDavException('注入的网络错误', statusCode: 500);

      await expectLater(
        client.listDirectory(
          url: 'http://nas.example.com',
          username: 'u',
          password: 'p',
          path: '/',
        ),
        throwsA(isA<WebDavException>()
            .having((e) => e.message, 'message', '注入的网络错误')
            .having((e) => e.statusCode, 'statusCode', 500)),
      );

      // 错误注入不得改变 validate 既有行为（未配置 handler → networkError）
      final validateResult = await client.validate(
        url: 'http://nas.example.com',
        username: 'u',
        password: 'p',
      );
      expect(validateResult.status, WebDavValidationStatus.networkError);
    });
  });

  group('TEST-07-S7: FakeSecureStorage.containsKey', () {
    test('已存 key 返回 true，未存 key 返回 false（内存实现，无平台通道）', () async {
      final storage = FakeSecureStorage()..setPassword(1, 'secret');

      expect(await storage.containsKey(key: 'connection_password_1'), isTrue);
      expect(await storage.containsKey(key: 'nonexistent'), isFalse,
          reason: '否定断言(CTR7): 不存在的 key 必须返回 false，不得抛 MissingPluginException');
    });
  });
}
