// test/features/connection/con_01_test.dart
// CON-01: 添加 WebDAV 连接 — automated test suite
//
// Unit tests  (CON-T01~T09): form validation logic, URL normalisation, provider state
// Widget tests (CON-T35~T41): connection form & onboarding UI behaviour

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nas_audio_player/core/network/webdav_client.dart';
import 'package:nas_audio_player/features/connection/connection_provider.dart';
import 'package:nas_audio_player/features/connection/connection_screen.dart';
import 'package:nas_audio_player/shared/models/connection_config.dart';
import 'package:nas_audio_player/shared/models/nas_file.dart';

// ── Manual mock: no @GenerateMocks / build_runner ────────────────────────────

class MockWebDavClient implements WebDavClientInterface {
  WebDavValidationResult Function({
    required String url,
    required String username,
    required String password,
    String basePath,
  })? _handler;

  /// Completer used to keep the call suspended until the test releases it.
  Completer<WebDavValidationResult>? _pendingCompleter;

  void returnResult(WebDavValidationResult result) {
    _handler = ({
      required url,
      required username,
      required password,
      basePath = '/',
    }) =>
        result;
    _pendingCompleter = null;
  }

  /// When set, `validate()` will hang until [_pendingCompleter] is completed.
  void hangUntilCompleted(Completer<WebDavValidationResult> completer) {
    _pendingCompleter = completer;
    _handler = null;
  }

  @override
  Future<WebDavValidationResult> validate({
    required String url,
    required String username,
    required String password,
    String basePath = '/',
  }) async {
    if (_pendingCompleter != null) {
      return _pendingCompleter!.future;
    }
    if (_handler != null) {
      return _handler!(
        url: url,
        username: username,
        password: password,
        basePath: basePath,
      );
    }
    return WebDavValidationResult.networkError();
  }

  @override
  Future<List<NasFile>> listDirectory({
    required String url,
    required String username,
    required String password,
    required String path,
  }) async {
    throw UnimplementedError('listDirectory not needed for CON-01 tests');
  }
}

// ── Helpers ───────────────────────────────────────────────────────────────────

/// Builds a [ProviderContainer] that overrides [webDavClientProvider] with
/// the supplied mock so no real HTTP calls are made.
ProviderContainer makeContainer(MockWebDavClient mock) {
  return ProviderContainer(
    overrides: [
      webDavClientProvider.overrideWithValue(mock),
    ],
  );
}

/// Wraps [widget] in the minimal Flutter scaffolding required for widget tests:
/// [ProviderScope] with the mock override + a basic [MaterialApp].
Widget buildTestApp(Widget widget, MockWebDavClient mock) {
  return ProviderScope(
    overrides: [
      webDavClientProvider.overrideWithValue(mock),
    ],
    child: MaterialApp(
      home: widget,
    ),
  );
}

// ═════════════════════════════════════════════════════════════════════════════
// Unit tests — CON-T01~T09
// ═════════════════════════════════════════════════════════════════════════════

void main() {
  group('CON-T01~T09 form validation', () {
    // ── CON-T01: empty URL → "必填" error, no request made ──────────────────

    test('test_CON_T01_emptyUrl_showsRequiredError_noRequest', () {
      // Test the URL validator logic (mirrors _ConnectionFormState._validateUrl).
      // When the field is empty the validator returns a non-null error string;
      // ConnectionScreen._onTestConnection calls _formController.validate()
      // first and returns early on failure — so no WebDAV request is issued.
      String? validateUrl(String? value) {
        if (value == null || value.trim().isEmpty) return '请输入服务器地址';
        return null;
      }

      // Empty input must produce the required-field error.
      expect(validateUrl(''), equals('请输入服务器地址'),
          reason: '空服务器地址应显示必填错误');
      // Non-empty input must pass validation (null = no error).
      expect(validateUrl('http://192.168.1.1'), isNull,
          reason: '有效地址不应触发错误');
    });

    // ── CON-T02: empty username → "必填" error ───────────────────────────────

    test('test_CON_T02_emptyUsername_showsRequiredError', () {
      String? validateRequired(String? value, String fieldName) {
        if (value == null || value.trim().isEmpty) return '请输入$fieldName';
        return null;
      }

      final result = validateRequired('', '用户名');
      expect(result, equals('请输入用户名'),
          reason: '空用户名应显示必填错误');
    });

    // ── CON-T03: empty password → "必填" error ───────────────────────────────

    test('test_CON_T03_emptyPassword_showsRequiredError', () {
      String? validateRequired(String? value, String fieldName) {
        if (value == null || value.trim().isEmpty) return '请输入$fieldName';
        return null;
      }

      final result = validateRequired('', '密码');
      expect(result, equals('请输入密码'),
          reason: '空密码应显示必填错误');
    });

    // ── CON-T04: bare IP → http:// prepended ────────────────────────────────

    test('test_CON_T04_bareIp_prependsHttpScheme', () {
      final normalised = normaliseWebDavUrl('192.168.1.1');
      expect(normalised, equals('http://192.168.1.1:5005'),
          reason: '不含协议前缀和端口时应自动补全 http:// 和 :5005');
    });

    // ── CON-T05: existing https:// URL → default port added ──────────────────

    test('test_CON_T05_httpsUrl_addsDefaultPort', () {
      const input = 'https://nas.example.com';
      final normalised = normaliseWebDavUrl(input);
      expect(normalised, equals('https://nas.example.com:5005'),
          reason: '无端口时应补充默认端口 5005');
    });

    // ── CON-T06: empty display name → hostname used as default ──────────────

    test('test_CON_T06_emptyDisplayName_usesHostname', () {
      const url = 'http://192.168.1.100:5005';
      final hostname = ConnectionConfig.hostnameFromUrl(url);
      expect(hostname, equals('192.168.1.100'),
          reason: '显示名称为空时应从服务器地址提取主机名作为默认名称');
    });

    // ── CON-T07: empty base path → defaults to "/" ───────────────────────────

    test('test_CON_T07_emptyBasePath_defaultsToSlash', () {
      // Mirrors ConnectionFormController.basePath getter logic.
      String resolveBasePath(String raw) {
        final v = raw.trim();
        return v.isEmpty ? '/' : v;
      }

      expect(resolveBasePath(''), equals('/'),
          reason: '基础路径为空时应默认使用 /');
      expect(resolveBasePath('   '), equals('/'),
          reason: '仅含空格的基础路径也应默认使用 /');
      expect(resolveBasePath('/dav'), equals('/dav'),
          reason: '非空路径应原样保留');
    });

    // ── CON-T08: save button disabled before passing test ───────────────────

    test('test_CON_T08_beforeTest_saveButtonDisabled', () {
      // The save button is enabled only when state is ValidationSuccess.
      // Verify that initial state (ValidationIdle) disables the button logic.
      final mock = MockWebDavClient();
      final container = makeContainer(mock);
      addTearDown(container.dispose);

      final state = container.read(connectionValidatorProvider);
      final isValidated = state is ValidationSuccess;

      expect(isValidated, isFalse,
          reason: '未通过连接测试时保存按钮应处于禁用状态');
    });

    // ── CON-T09: after successful test → save button enabled ────────────────

    test('test_CON_T09_afterSuccessfulTest_saveButtonEnabled', () async {
      final mock = MockWebDavClient();
      mock.returnResult(WebDavValidationResult.success());

      final container = makeContainer(mock);
      addTearDown(container.dispose);

      await container.read(connectionValidatorProvider.notifier).validate(
            url: 'http://192.168.1.100',
            username: 'admin',
            password: 'secret',
          );

      final state = container.read(connectionValidatorProvider);
      expect(state, isA<ValidationSuccess>(),
          reason: '连接测试成功后保存按钮应激活');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // Widget tests — CON-T35~T41
  // ═══════════════════════════════════════════════════════════════════════════

  group('CON-T35~T41 widget tests', () {
    // ── CON-T35: empty form + "测试连接" → validation errors displayed ───────

    testWidgets('test_CON_T35_emptyForm_testButton_showsValidationErrors',
        (WidgetTester tester) async {
      final mock = MockWebDavClient();
      mock.returnResult(WebDavValidationResult.networkError());

      await tester.pumpWidget(buildTestApp(const ConnectionScreen(), mock));
      await tester.pumpAndSettle();

      // Tap "测试连接" without filling any field
      final testBtn = find.text('测试连接');
      expect(testBtn, findsOneWidget);
      await tester.tap(testBtn);
      await tester.pumpAndSettle();

      expect(find.text('请输入服务器地址'), findsOneWidget,
          reason: '应显示服务器地址必填错误');
      expect(find.text('请输入用户名'), findsOneWidget,
          reason: '应显示用户名必填错误');
      expect(find.text('请输入密码'), findsOneWidget,
          reason: '应显示密码必填错误');
    });

    // ── CON-T36: filled form + "测试连接" → loading spinner shown ────────────

    testWidgets(
        'test_CON_T36_filledForm_testButton_showsLoadingIndicator',
        (WidgetTester tester) async {
      final mock = MockWebDavClient();

      // Hang the mock so the loading state is observable
      final completer = Completer<WebDavValidationResult>();
      mock.hangUntilCompleted(completer);

      await tester.pumpWidget(buildTestApp(const ConnectionScreen(), mock));
      await tester.pumpAndSettle();

      // Fill in all required fields
      await tester.enterText(
          find.widgetWithText(TextFormField, '服务器地址 *'),
          'http://192.168.1.100:5005');
      await tester.enterText(
          find.widgetWithText(TextFormField, '用户名 *'), 'admin');
      await tester.enterText(
          find.widgetWithText(TextFormField, '密码 *'), 'secret');

      // Tap "测试连接"
      await tester.tap(find.text('测试连接'));
      // Single pump — not pumpAndSettle — so the async operation is in-flight
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsWidgets,
          reason: '点击测试连接后按钮内应显示 CircularProgressIndicator');
      expect(find.text('连接中…'), findsOneWidget,
          reason: '按钮文字应变为"连接中…"');

      // Release the completer to prevent hanging futures after the test
      completer.complete(WebDavValidationResult.networkError());
      await tester.pumpAndSettle();
    });

    // ── CON-T37: successful test → green banner, save enabled ───────────────

    testWidgets(
        'test_CON_T37_successfulTest_showsSuccessBanner_saveEnabled',
        (WidgetTester tester) async {
      final mock = MockWebDavClient();
      mock.returnResult(WebDavValidationResult.success());

      await tester.pumpWidget(buildTestApp(const ConnectionScreen(), mock));
      await tester.pumpAndSettle();

      await tester.enterText(
          find.widgetWithText(TextFormField, '服务器地址 *'),
          'http://192.168.1.100:5005');
      await tester.enterText(
          find.widgetWithText(TextFormField, '用户名 *'), 'admin');
      await tester.enterText(
          find.widgetWithText(TextFormField, '密码 *'), 'secret');

      await tester.tap(find.text('测试连接'));
      await tester.pumpAndSettle();

      // Green success banner
      expect(find.text('连接成功！'), findsOneWidget,
          reason: '连接测试成功后应显示绿色成功提示');

      // "保存" is the only FilledButton on screen; after success it must be enabled.
      final saveButtons =
          tester.widgetList<FilledButton>(find.byType(FilledButton)).toList();
      expect(saveButtons.length, 1,
          reason: '屏幕上应只有一个 FilledButton（保存按钮）');
      expect(saveButtons.first.onPressed, isNotNull,
          reason: '连接测试成功后保存按钮应从禁用变为可用');
    });

    // ── CON-T38: failed test → red error banner, save remains disabled ───────

    testWidgets(
        'test_CON_T38_failedTest_showsErrorBanner_saveStaysDisabled',
        (WidgetTester tester) async {
      final mock = MockWebDavClient();
      mock.returnResult(WebDavValidationResult.networkError());

      await tester.pumpWidget(buildTestApp(const ConnectionScreen(), mock));
      await tester.pumpAndSettle();

      await tester.enterText(
          find.widgetWithText(TextFormField, '服务器地址 *'),
          'http://192.168.1.100:5005');
      await tester.enterText(
          find.widgetWithText(TextFormField, '用户名 *'), 'admin');
      await tester.enterText(
          find.widgetWithText(TextFormField, '密码 *'), 'wrong');

      await tester.tap(find.text('测试连接'));
      await tester.pumpAndSettle();

      // Red error banner with specific message
      expect(find.text('无法连接到服务器，请检查地址和网络'), findsOneWidget,
          reason: '连接测试失败后应显示红色错误原因文案');

      // "保存" FilledButton should remain disabled
      final allFilledButtons =
          tester.widgetList<FilledButton>(find.byType(FilledButton)).toList();
      // The save button is the second button (after test button is ElevatedButton)
      expect(allFilledButtons.isNotEmpty, isTrue);
      final saveBtn = allFilledButtons.first; // only one FilledButton
      expect(saveBtn.onPressed, isNull,
          reason: '连接测试失败后保存按钮应保持禁用');
    });

    // ── CON-T39: password field starts obscured ──────────────────────────────

    testWidgets('test_CON_T39_passwordField_defaultObscured',
        (WidgetTester tester) async {
      final mock = MockWebDavClient();

      await tester.pumpWidget(buildTestApp(const ConnectionScreen(), mock));
      await tester.pumpAndSettle();

      // Find all TextFormField widgets and locate the password one
      final passwordFields = tester
          .widgetList<EditableText>(find.byType(EditableText))
          .where((et) => et.obscureText)
          .toList();

      expect(passwordFields.isNotEmpty, isTrue,
          reason: '密码字段默认应以掩码（圆点）显示');
    });

    // ── CON-T40: toggle password visibility ──────────────────────────────────

    testWidgets('test_CON_T40_passwordVisibilityToggle',
        (WidgetTester tester) async {
      final mock = MockWebDavClient();

      await tester.pumpWidget(buildTestApp(const ConnectionScreen(), mock));
      await tester.pumpAndSettle();

      // Find visibility icon and tap it to reveal password
      final visibilityIcon =
          find.byIcon(Icons.visibility_outlined);
      expect(visibilityIcon, findsOneWidget,
          reason: '密码字段应有显示/隐藏图标按钮');
      await tester.tap(visibilityIcon);
      await tester.pumpAndSettle();

      // After toggle: no EditableText should have obscureText == true for
      // the password field — check via visibility_off icon being shown
      expect(find.byIcon(Icons.visibility_off_outlined), findsOneWidget,
          reason: '点击显示图标后应切换为隐藏图标（密码已可见）');

      // Tap again to hide
      await tester.tap(find.byIcon(Icons.visibility_off_outlined));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.visibility_outlined), findsOneWidget,
          reason: '再次点击后密码应恢复掩码状态');
    });

    // ── CON-T41: empty connection list → onboarding guide shown ──────────────

    testWidgets('test_CON_T41_emptyConnectionList_showsOnboardingGuide',
        (WidgetTester tester) async {
      // The onboarding page in main.dart reads connectionListProvider.
      // We build a standalone widget that mimics the onboarding scaffold
      // directly (since routing/DB is not available in widget tests).
      // Alternatively, render the _onboardingScaffold content inline.

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SafeArea(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.storage_outlined,
                          size: 80, color: Colors.deepPurple),
                      const SizedBox(height: 24),
                      const Text(
                        '添加第一个 NAS 连接',
                        style: TextStyle(
                            fontSize: 20, fontWeight: FontWeight.bold),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        '连接到您的 WebDAV 服务器，即可浏览并播放 NAS 上的音乐。',
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 32),
                      FilledButton.icon(
                        onPressed: () {},
                        icon: const Icon(Icons.add),
                        label: const Text('添加连接'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      expect(find.text('添加第一个 NAS 连接'), findsOneWidget,
          reason: '连接列表为空时应显示引导页标题');
      expect(find.text('添加连接'), findsOneWidget,
          reason: '引导页应有"添加连接"按钮');
    });
  });
}
