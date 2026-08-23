// test/core/bug_bug26_pubspec_state_notifier_test.dart
// BUG-26 门禁测试（来源 cr-20260823-1421.md F4，复核分流 2026-08-23）。
//
// 缺陷：lib/features/browser/domain/directory_service.dart:5 与
// navigation_stack.dart:5 直接 import package:state_notifier，但 pubspec.yaml
// dependencies 未声明该包（analyze depend_on_referenced_packages ×2）——
// 编译依赖 flutter_riverpod 的传递暴露，riverpod 升级若移除传递导出即断裂。
//
// 门禁：直接 import 的包必须在 pubspec dependencies 显式声明。
// 结构断言（BUG-18-INV1 源码扫描同款先例）。

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final domainDir = Directory('lib/features/browser/domain');
  final importingFiles = domainDir
      .listSync()
      .whereType<File>()
      .where((f) =>
          f.readAsStringSync().contains("import 'package:state_notifier"))
      .map((f) => f.path)
      .toList();

  test('BUG-26 前置条件：domain 层确有 state_notifier 直接 import（非空）', () {
    expect(importingFiles, isNotEmpty,
        reason: '若未来 domain 不再 import state_notifier，'
            '本门禁的声明要求随之失效，应一并删除本测试');
  });

  test('BUG-26-S1: state_notifier 必须显式声明于 pubspec dependencies', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    // 只看主依赖段（dev_dependencies 声明不满足运行期直引语义）。
    final mainDeps =
        pubspec.split(RegExp(r'^dev_dependencies:', multiLine: true)).first;
    final declared = RegExp(r'^\s+state_notifier\s*:\s*\S', multiLine: true)
        .hasMatch(mainDeps);
    expect(declared, isTrue,
        reason: 'directory_service/navigation_stack 直接 import '
            'package:state_notifier（$importingFiles），'
            '不得依赖 riverpod 的传递暴露');
  });
}
