// test/features/coverage/ref_01_domain_pure_test.dart
// REF-01: Domain 层 Flutter 依赖清理 — 静态断言（REF-01-INV1 / INV2）。
//
// 断言 6 个 domain 文件的 import 列表不包含 Flutter 框架与平台插件包，
// 以及 arch-baseline.txt 中对应 legacy debt 记录已删除。
// 测试先行阶段（实现未落地）本文件预期 FAIL。
//
// 注意：本文件用 dart:io 读 lib/ 文件文本，仅检查 import 列表，
// 不读取、不依赖任何实现细节。

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 违规包关键字清单（spec §2.2 A1-A6）。
const List<String> _forbiddenMarkers = [
  'package:flutter/',
  'flutter_secure_storage',
  'just_audio',
  'shared_preferences',
];

/// 6 个 domain 文件 → 各自必须清除的违规 import（spec §2.1）。
const Map<String, List<String>> _domainFiles = {
  'lib/features/settings/domain/settings_service.dart': ['package:flutter/'],
  'lib/features/connection/domain/connection_service.dart': [
    'flutter_secure_storage'
  ],
  'lib/features/player/domain/request_gate.dart': ['just_audio'],
  'lib/features/player/domain/playback_orchestrator.dart': ['just_audio'],
  'lib/features/player/domain/speed_manager.dart': ['shared_preferences'],
  'lib/features/browser/domain/directory_service.dart': ['shared_preferences'],
};

/// 提取文件的 import 行（去注释/去引号后的整行文本）。
List<String> _importLines(File file) {
  final source = file.readAsStringSync();
  return source
      .split('\n')
      .where((line) => line.trimLeft().startsWith('import '))
      .toList();
}

void main() {
  group('REF-01-INV1: 6 个 domain 文件无 Flutter/平台插件 import', () {
    for (final entry in _domainFiles.entries) {
      final filePath = entry.key;
      final mustNotImport = entry.value;

      test('$filePath 存在且 import 列表干净', () {
        final file = File(filePath);
        expect(file.existsSync(), isTrue,
            reason: '$filePath 不存在 —— REF-01 实现未落地（测试先行阶段预期失败）');

        final imports = _importLines(file).join('\n');
        for (final marker in mustNotImport) {
          expect(imports, isNot(contains(marker)),
              reason:
                  '$filePath 仍 import 含 "$marker" 的包 —— REF-01 实现未落地（预期失败）');
        }
      });
    }

    test('全量扫描: 6 个 domain 文件均不 import 任何违规包', () {
      for (final filePath in _domainFiles.keys) {
        final file = File(filePath);
        expect(file.existsSync(), isTrue,
            reason: '$filePath 不存在 —— REF-01 实现未落地（测试先行阶段预期失败）');

        final imports = _importLines(file).join('\n');
        for (final marker in _forbiddenMarkers) {
          expect(imports, isNot(contains(marker)),
              reason: '$filePath 不得 import 含 "$marker" 的包');
        }
      }
    });
  });

  group('REF-01-INV2: arch-baseline.txt 6 条 domain-flutter 记录已删除', () {
    test('arch-baseline.txt 不再包含 6 个 domain 文件条目', () {
      final baseline = File('docs/dev/arch-baseline.txt');
      expect(baseline.existsSync(), isTrue,
          reason: 'docs/dev/arch-baseline.txt 应存在');
      final content = baseline.readAsStringSync();
      for (final filePath in _domainFiles.keys) {
        expect(content, isNot(contains(filePath)),
            reason:
                'arch-baseline.txt 仍含 $filePath 债务条目 —— REF-01 实现未落地（预期失败）');
      }
    });
  });
}
