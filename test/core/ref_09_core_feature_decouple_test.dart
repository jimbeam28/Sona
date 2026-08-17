// test/core/ref_09_core_feature_decouple_test.dart
// REF-09 门禁测试（spec docs/features/REF-09.md §5.4 指定文件）。
//
// 锚定数据层反向依赖解耦（core→feature 零依赖）：
//   - S7 progress_policy 迁至 core/contracts，DAO 委托语义逐字节不变
//   - S8 extractTitleFromPath 下沉 shared，audio_handler 直连 shared
//   - S9 cross-imports.sh 新增 core→feature 方向检查
//   - INV1 lib/core 下任何 .dart 不得 import 解析到 lib/features/** 的文件
//   - INV2 progress_policy 单源常驻 core/contracts
//   - INV3 extractTitleFromPath 唯一定义在 shared

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _libPath(String rel) {
  return '${Directory.current.path}/lib/$rel';
}

void main() {
  group('REF-09: core→feature 解耦', () {
    test('REF-09-S7: progress_dao.dart 不再 import features/ 路径', () {
      final content = File(_libPath('core/database/dao/progress_dao.dart'))
          .readAsStringSync();

      expect(content, isNot(contains('features/progress')),
          reason: 'progress_dao 不得再出现 features/progress 字样的 import');
      expect(content, contains("import '../../contracts/progress_policy.dart'"),
          reason: 'progress_dao 应 import core/contracts/progress_policy.dart');
      expect(content, contains('as progress_policy'),
          reason: '保留 as progress_policy 别名');
    });

    test('REF-09-S7: 旧 progress_policy 路径不存在，新路径存在', () {
      expect(
          File(_libPath('features/progress/domain/progress_policy.dart'))
              .existsSync(),
          isFalse,
          reason: '旧 features 路径的 progress_policy.dart 必须删除');
      expect(File(_libPath('core/contracts/progress_policy.dart')).existsSync(),
          isTrue,
          reason: '新 core/contracts 路径的 progress_policy.dart 必须存在');
    });

    test('REF-09-S7: shouldSave/shouldClear 阈值语义保持（5000/10000/clamp）', () {
      final content = File(_libPath('core/contracts/progress_policy.dart'))
          .readAsStringSync();

      expect(content, contains('positionMs >= 5000'),
          reason: 'shouldSave 阈值 5000 不得改');
      expect(content, contains('durationMs <= 10000'),
          reason: 'shouldClear 短文件保护 10000 不得改');
      expect(content, contains('.clamp(1000, 10000)'),
          reason: '动态窗口 clamp(1000,10000) 不得改');
    });

    test('REF-09-S8: audio_handler.dart 不再 import features/ 路径', () {
      final content =
          File(_libPath('core/services/audio_handler.dart')).readAsStringSync();

      expect(content, isNot(contains("features/player")),
          reason: 'audio_handler 不得再 import 任何 features/ 路径');
      expect(content, contains("import '../../shared/media_title.dart'"),
          reason: 'audio_handler 应直连 shared/media_title.dart');
    });

    test('REF-09-S8: media_control.dart re-export extractTitleFromPath', () {
      final content =
          File(_libPath('features/player/domain/media_control.dart'))
              .readAsStringSync();

      expect(
          content,
          contains(
              "export '../../../shared/media_title.dart' show extractTitleFromPath;"),
          reason:
              'media_control.dart 必须 re-export shared 的 extractTitleFromPath');
    });

    test('REF-09-S8: extractTitleFromPath 唯一定义在 shared（无第二份实现）', () {
      final shared =
          File(_libPath('shared/media_title.dart')).readAsStringSync();
      final mediaControl =
          File(_libPath('features/player/domain/media_control.dart'))
              .readAsStringSync();

      expect(shared, contains('String extractTitleFromPath(String filePath)'),
          reason: 'shared/media_title.dart 是 extractTitleFromPath 唯一定义');
      expect(mediaControl,
          isNot(contains('String extractTitleFromPath(String filePath)')),
          reason: 'media_control.dart 不得再含本地实现（应经 re-export 引用）');
    });

    test('REF-09-ALG1-crossImportResolve: core 层 import 解析语义', () {
      // 主流程（修复后）：core 层经 ../../contracts 与 shared 引用，不落 features/
      expect(
          File(_libPath('core/database/dao/progress_dao.dart'))
              .readAsStringSync(),
          contains("import '../../contracts/progress_policy.dart'"));
      expect(
          File(_libPath('core/services/audio_handler.dart')).readAsStringSync(),
          contains("import '../../shared/media_title.dart'"));

      // 反向（违规态）：core→features 解析即 core-feature 违规（S9 检查命中）
      final script = File(
              '${Directory.current.path}/.claude/plugins/sona-dev/scripts/cross-imports.sh')
          .readAsStringSync();
      expect(script, contains('lib/features/*'),
          reason: 'ALG1: check_core_feature 必须以 lib/features/* 为违规判定目标');
      expect(script, contains('lib/core/'),
          reason: 'ALG1: check_core_feature 必须扫描 lib/core/ 源');
    });

    test('REF-09-INV1: lib/core 下不得 import 解析到 lib/features/** 的文件', () {
      // 全 lib/core 扫描：收集所有 import 语句并断言不含 features 相对/包路径
      final coreDir = Directory(_libPath('core'));
      final offenders = <String>[];
      coreDir.listSync(recursive: true).whereType<File>().where((f) {
        return f.path.endsWith('.dart');
      }).forEach((f) {
        final lines = f.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          final line = lines[i];
          if (line.trimLeft().startsWith('import') &&
              (line.contains('features/') ||
                  line.contains('package:nas_audio_player/features/'))) {
            offenders.add('${f.path}:${i + 1}: $line');
          }
        }
      });

      expect(offenders, isEmpty,
          reason: 'lib/core 下任何 import 不得落 lib/features/（INV1）');
    });

    test('REF-09-INV2: progress_policy 单源（features 旧路径无文件）', () {
      expect(
          File(_libPath('features/progress/domain/progress_policy.dart'))
              .existsSync(),
          isFalse,
          reason: 'INV2: progress_policy 单源常驻 core/contracts');
      expect(File(_libPath('core/contracts/progress_policy.dart')).existsSync(),
          isTrue);
    });

    test('REF-09-INV3: extractTitleFromPath 唯一定义在 shared（跨目录 grep）', () {
      // 全 lib 扫描出现 "String extractTitleFromPath(String filePath) {"
      // 的文件必须只有 shared/media_title.dart 一处
      final matches = <String>[];
      Directory('${Directory.current.path}/lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))
          .forEach((f) {
        final content = f.readAsStringSync();
        if (content.contains('String extractTitleFromPath(String filePath)')) {
          matches.add(f.path);
        }
      });

      expect(matches, hasLength(1),
          reason: 'extractTitleFromPath 必须全 lib 唯一实现');
      expect(matches.single, endsWith('shared/media_title.dart'));
    });

    test('REF-09-S9: cross-imports.sh 含 core-feature 方向检查', () {
      final script = File(
              '${Directory.current.path}/.claude/plugins/sona-dev/scripts/cross-imports.sh')
          .readAsStringSync();

      expect(script, contains('check_core_feature'),
          reason: 'cross-imports.sh 必须定义 check_core_feature');
      expect(script, contains('core-feature)'),
          reason: 'cross-imports.sh 必须支持 core-feature kind');
      expect(script, contains('check_core_feature\n        ;;'),
          reason: 'all 模式必须并入 check_core_feature');
    });
  });
}
