// test/features/browser/bug_bug10_repro_test.dart
// BUG-10 复现测试（来源：docs/cr/cr-20260816-0803-browser-home.md F1）
//
// 缺陷：浏览器错误视图对非 WebDavException 暴露原始异常文本
// （browser_screen.dart:57-59 `'加载失败：$error'`），与 BUG-23-S5 裁决
// （用户可见文案固定、原始异常仅经 debugPrint 进 LogBuffer）相悖。
//
// 修复前：本测试 FAIL —— 页面显示 '加载失败：<原始异常 toString>'，且
// debugPrint 无原始异常日志。
// 修复后：本测试 PASS —— 固定文案 '加载失败，请稍后重试' + 日志含原始异常。

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nas_audio_player/core/network/webdav_client.dart';
import 'package:nas_audio_player/features/browser/browser_provider.dart';
import 'package:nas_audio_player/features/browser/browser_screen.dart';

/// Runs [body] while capturing everything written through [debugPrint]
/// （同 bug_bug23_repro_test.dart:40-53 模式——生产把 debugPrint 镜像进
/// LogBuffer，落进 [logs] 的即 debug 构建在 /logs 可见的内容）。
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
  group('BUG-10: 错误视图对非 WebDavException 不得暴露原始异常文本', () {
    testWidgets('非 WebDavException → 显示固定兜底文案，原始文本不进用户可见消息',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            directoryContentsProvider('/').overrideWith(
              (ref) async => throw const SocketException(
                  'OS Error: Connection refused, errno = 111'),
            ),
          ],
          child: const MaterialApp(home: Scaffold(body: BrowserScreen())),
        ),
      );
      await tester.pumpAndSettle();

      // 修复目标：固定兜底文案
      expect(find.text('加载失败，请稍后重试'), findsOneWidget,
          reason: '非 WebDavException 必须显示固定兜底文案'
              '（修复前：显示 "加载失败：<原始异常>"）');
      // 否定断言：原始异常文本不得泄漏到用户可见消息
      expect(find.textContaining('errno'), findsNothing,
          reason: '否定断言：errno 细节不得出现在错误视图');
      expect(find.textContaining('Connection refused'), findsNothing,
          reason: '否定断言：原始异常消息不得出现在错误视图');
      expect(find.textContaining('SocketException'), findsNothing,
          reason: '否定断言：异常类型名不得出现在错误视图');
      expect(find.textContaining('加载失败：'), findsNothing,
          reason: '否定断言：不得沿用 "加载失败：\$error" 插值形态');
    });

    testWidgets('原始异常文本经 debugPrint 进 LogBuffer（可追溯性）',
        (WidgetTester tester) async {
      await captureDebugPrint((logs) async {
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              directoryContentsProvider('/').overrideWith(
                (ref) async => throw const SocketException(
                    'OS Error: Connection refused, errno = 111'),
              ),
            ],
            child: const MaterialApp(home: Scaffold(body: BrowserScreen())),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('加载失败，请稍后重试'), findsOneWidget, reason: '前置：固定兜底文案显示');
        expect(logs.join('\n'), contains('Connection refused'),
            reason: '原始异常必须经 debugPrint 进 LogBuffer 保留可追溯性'
                '（BUG-23-S5 同款裁决，修复前该分支无任何日志）');
      });
    });

    // ═════════════════════════════════════════════════════════════════════════
    // BUG-10-S1: WebDavException → 显示 error.message（现有行为锚定，不得回归）
    // ═════════════════════════════════════════════════════════════════════════

    testWidgets('WebDavException → 仍显示其 message（BRW-01 错误面回归）',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            directoryContentsProvider('/').overrideWith(
              (ref) async => throw const WebDavException('没有活跃的连接'),
            ),
          ],
          child: const MaterialApp(home: Scaffold(body: BrowserScreen())),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('没有活跃的连接'), findsOneWidget,
          reason: 'WebDavException 分支语义不变：显示 error.message');
      expect(find.text('加载失败，请稍后重试'), findsNothing,
          reason: '否定断言：WebDavException 不得被固定兜底文案覆盖');
    });
  });
}
