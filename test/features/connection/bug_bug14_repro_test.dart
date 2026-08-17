// test/features/connection/bug_bug14_repro_test.dart
// BUG-14: 验证请求 in-flight 期间改字段，过期结果覆盖 reset，保存门被绕过
// （spec: docs/features/BUG-14.md §5.4，来源 cr-20260816-0804 F1）
//
// 缺陷：connection_provider.dart:118-142 ConnectionValidatorNotifier.validate
// 无请求版本号/字段快照：
//   state = ValidationLoading();
//   final result = await _client.validate(...);
//   state = result.isSuccess ? ValidationSuccess() : ValidationError(...);
// 两个屏幕的 _onFieldChanged（connection_screen.dart:151-155 /
// connection_edit_screen.dart:189-196）只调 validator.reset()（→ Idle），
// 表单字段在验证期间不禁用（connection_screen.dart:86 只禁用按钮）。
// → 填 URL A → 点测试连接（Loading，请求 in-flight）→ 改 URL 为 B
//   （reset → Idle）→ in-flight 请求（针对 A）返回成功 → state 被无条件
//   置为 ValidationSuccess → 保存按钮解锁（:103 只看当前 state）→ 以对 A
//   的验证结果放行 B 的保存（CON-01/CON-T28 语义被绕过）。
//
// 门禁（修复前必须 FAIL）：
//   BUG-14-S1: reset 之后 in-flight 验证完成，不得把 state 置为 Success
//              —— 当前代码无条件落地 → FAIL
//   BUG-14-S2: reset 之后 in-flight 验证失败，同样不得落地 —— 当前 FAIL

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nas_audio_player/core/network/webdav_client.dart';
import 'package:nas_audio_player/features/connection/connection_provider.dart';

import '../../helpers/fake_webdav_client.dart';

void main() {
  test('BUG-14-S1: reset 后 in-flight 验证成功不得把 state 置为 Success', () async {
    final client = MockWebDavClient();
    final completer = Completer<WebDavValidationResult>();
    client.hangUntilCompleted(completer);

    final container = ProviderContainer(
      overrides: [webDavClientProvider.overrideWithValue(client)],
    );
    addTearDown(container.dispose);

    final notifier = container.read(connectionValidatorProvider.notifier);

    // Given: 用户填 URL A 并点"测试连接"（请求 in-flight）。
    final pending = notifier.validate(
      url: 'http://nas-a.local:5005',
      username: 'admin',
      password: 'pw',
    );
    expect(
        container.read(connectionValidatorProvider), isA<ValidationLoading>());

    // When: 验证期间用户把 URL 改成 B（_onFieldChanged → reset → Idle）。
    notifier.reset();
    expect(container.read(connectionValidatorProvider), isA<ValidationIdle>(),
        reason: '前置：改字段后状态必须回到 Idle');

    // 针对 A 的 in-flight 请求此刻才返回成功。
    completer.complete(WebDavValidationResult.success());
    await pending;

    // Then: 对 A 的验证结果不得落地为 Success —— 保存门（:103
    // (isValidated && !_isSaving)）不得被过期结果解锁。
    expect(container.read(connectionValidatorProvider), isA<ValidationIdle>(),
        reason: 'BUG-14（cr-20260816-0804 F1）：validate 完成回调无条件覆盖'
            'state（connection_provider.dart:137-141）——reset 之后 in-flight '
            '完成仍把 state 置为 ValidationSuccess，以对 A 的验证结果放行 B '
            '的保存（connection_screen.dart:151-155 只调 reset，:103 保存门'
            '只看当前 state），未验证连接直接落库。');
  });

  test('BUG-14-S2: reset 后 in-flight 验证失败也不得覆盖 reset 状态', () async {
    final client = MockWebDavClient();
    final completer = Completer<WebDavValidationResult>();
    client.hangUntilCompleted(completer);

    final container = ProviderContainer(
      overrides: [webDavClientProvider.overrideWithValue(client)],
    );
    addTearDown(container.dispose);

    final notifier = container.read(connectionValidatorProvider.notifier);

    final pending = notifier.validate(
      url: 'http://nas-a.local:5005',
      username: 'admin',
      password: 'pw',
    );
    expect(
        container.read(connectionValidatorProvider), isA<ValidationLoading>());

    notifier.reset();
    expect(container.read(connectionValidatorProvider), isA<ValidationIdle>());

    completer.complete(WebDavValidationResult.networkError());
    await pending;

    // 失败结果同样不得落地（当前代码会覆盖为 ValidationError）。
    expect(container.read(connectionValidatorProvider), isA<ValidationIdle>(),
        reason: 'BUG-14：validate 完成回调对失败分支（:139-141）同样无过期'
            '判别 —— 用户改字段后看到的是针对旧字段的错误提示。');
  });
}
