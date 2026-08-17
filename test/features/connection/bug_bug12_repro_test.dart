// test/features/connection/bug_bug12_repro_test.dart
// BUG-12: validateBasePath 是死代码 —— 基础路径字段从未接入 validator
// （spec: docs/features/BUG-12.md §5.4，来源 cr-20260816-0804 B2）
//
// 缺陷：connection_form.dart:224-234 的基础路径 TextFormField 无 validator
// 属性（对比 url 字段 :161、用户名 :175、密码 :200-205 均有）；
// connection_validator.dart:58-76 的 validateBasePath（规则："必须以 / 开头"、
// "不能包含 .."）与 BasePathResult 在 lib/ 下零调用（仅测试直接单测）。
// → 基础路径输入 `x`（无前导 /）或 `/dav/../etc`（含 ..）都通过表单校验，
//   PROPFIND 到拼接路径（webdav_paths.dart segment() 静默补 /、`..` 由
//   服务器归一），若返回 207 → 保存按钮解锁 → 带 .. 的 basePath 持久化。
//
// 门禁（修复前必须 FAIL）：
//   BUG-12-S1: 添加页基础路径输入无前导 / 的值 → 点"测试连接"→ 必须显示
//              "基础路径必须以 / 开头" 内联错误 —— 当前代码 FAIL（校验通过）
//   BUG-12-S2: 基础路径含 .. → 必须显示"基础路径不能包含 .." —— 当前 FAIL

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nas_audio_player/core/network/webdav_client.dart';
import 'package:nas_audio_player/features/connection/connection_provider.dart';
import 'package:nas_audio_player/features/connection/connection_screen.dart';

import '../../helpers/fake_webdav_client.dart';

Widget _buildApp(MockWebDavClient mock) {
  return ProviderScope(
    overrides: [
      webDavClientProvider.overrideWithValue(mock),
    ],
    child: const MaterialApp(home: ConnectionScreen()),
  );
}

Future<void> _fillValidCredentials(WidgetTester tester) async {
  await tester.enterText(find.widgetWithText(TextFormField, '服务器地址 *'),
      'http://192.168.1.100:5005');
  await tester.enterText(find.widgetWithText(TextFormField, '用户名 *'), 'admin');
  await tester.enterText(find.widgetWithText(TextFormField, '密码 *'), 'secret');
}

void main() {
  testWidgets('BUG-12-S1: 基础路径无前导 / 必须被表单校验拦截（当前放行）', (tester) async {
    final mock = MockWebDavClient();
    // 让校验请求"成功"——缺陷态下非法 basePath 一路放行到 PROPFIND。
    mock.returnResult(WebDavValidationResult.success());

    await tester.pumpWidget(_buildApp(mock));
    await tester.pumpAndSettle();

    await _fillValidCredentials(tester);
    // Given: 基础路径输入无前导 / 的非法值。
    await tester.enterText(
        find.widgetWithText(TextFormField, '基础路径（选填）'), 'dav');

    // When: 点"测试连接"（触发表单 validate()）。
    await tester.tap(find.text('测试连接'));
    await tester.pumpAndSettle();

    // Then: 必须出现内联错误"基础路径必须以 / 开头"。
    expect(find.text('基础路径必须以 / 开头'), findsOneWidget,
        reason: 'BUG-12（cr-20260816-0804 B2）：基础路径字段'
            '（connection_form.dart:224-234）无 validator —— validateBasePath'
            '（connection_validator.dart:58-76）在 lib/ 零调用，'
            '"必须以 / 开头"规则形同虚设；缺陷态校验通过直接发 PROPFIND。');
  });

  testWidgets('BUG-12-S2: 基础路径含 .. 必须被表单校验拦截（当前放行）', (tester) async {
    final mock = MockWebDavClient();
    mock.returnResult(WebDavValidationResult.success());

    await tester.pumpWidget(_buildApp(mock));
    await tester.pumpAndSettle();

    await _fillValidCredentials(tester);
    // Given: 基础路径输入含路径穿越段的非法值。
    await tester.enterText(
        find.widgetWithText(TextFormField, '基础路径（选填）'), '/dav/../etc');

    await tester.tap(find.text('测试连接'));
    await tester.pumpAndSettle();

    // Then: 必须出现内联错误"基础路径不能包含 .."。
    expect(find.text('基础路径不能包含 ..'), findsOneWidget,
        reason: 'BUG-12（cr-20260816-0804 B2）：validateBasePath 的'
            '"不能包含 .."规则（connection_validator.dart:69-74）从未被表单'
            '调用 —— 含 .. 的基础路径可直接通过校验并持久化。');
  });
}
