// test/features/progress/ref_19_threshold_single_source_test.dart
// REF-19 门禁测试（cr-20260823-1421.md D1 用户裁决"修"→ 需求流程）。
//
// 目标：5 秒进度阈值在 lib/ 内有且仅有一个数值定义点
// （progress_policy.dart:13 shouldSave），其余消费方一律经函数引用。
// 现状：browser_screen.dart:142 与 playlist_detail_screen.dart:55 各自
// 硬编码 `>= 5000` —— 本门禁修复前 FAIL、修复后 PASS。

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('REF-19-S1: >= 5000 魔数只允许出现在 progress_policy 定义处', () {
    // REF-19-INV1：「5 秒看过阈值」在 lib/ 内有且仅有一个数值定义点。
    final offenders = <String>[];
    for (final f
        in Directory('lib').listSync(recursive: true).whereType<File>()) {
      if (!f.path.endsWith('.dart')) continue;
      final lines = f.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        if (lines[i].contains('>= 5000') &&
            !f.path.endsWith('progress_policy.dart')) {
          offenders.add('${f.path}:${i + 1}');
        }
      }
    }
    expect(offenders, isEmpty,
        reason: '进度阈值必须单源引用 ProgressDao.shouldSave / '
            'progress_policy，禁止 UI 层复制魔数：$offenders');
  });

  test('REF-19 前置条件：policy 单源定义存在（防门禁空转）', () {
    final policy =
        File('lib/core/contracts/progress_policy.dart').readAsStringSync();
    expect(policy.contains('positionMs >= 5000'), isTrue);
  });
}
