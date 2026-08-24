// lib/features/browser/domain/multi_select_ordering.dart
// MSEL-01-ALG1: 跨目录勾选集 → 播放顺序解析（纯 Dart 可独立单测，无 UI / 状态层依赖）。
//
// 组间序 = selections 键插入序（Dart Map 字面量 / Map() 默认为插入序
// LinkedHashMap，语言级保证，spec §8-R1）；组内序 = snapshotOf(dir) 快照按选中
// path 过滤后的相对序；快照不可用（null，缓存 TTL/LRU 淘汰或未命中）→ 该组回退
// 完整 path 字典序。任一选中 path 在结果中恰好出现一次（全局去重），无遗漏。

import '../../../shared/models/nas_file.dart';

/// Resolves the multi-select store into a play-ordered [NasFile] list (ALG1).
///
/// [selections] maps directory path → selected file paths; its key iteration
/// order defines group order. [snapshotOf] returns the directory's current
/// sorted listing snapshot (or null when evicted/missing). Selected paths not
/// present in a hit snapshot (e.g. deleted remotely) degrade to lexicographic
/// order at the end of their group so no selection is ever dropped.
///
/// 纯函数：快照解析经 snapshotOf 回调注入，无任何框架依赖（INV2）。
List<NasFile> orderedSelectedFiles({
  required Map<String, Set<String>> selections,
  required List<NasFile>? Function(String dirPath) snapshotOf,
}) {
  final result = <NasFile>[];
  final emitted = <String>{};

  void emit(String path, NasFile? template) {
    if (emitted.add(path)) {
      result.add(template ??
          NasFile(path: path, name: path.split('/').last, isDirectory: false));
    }
  }

  for (final dirPath in selections.keys) {
    final selected = selections[dirPath];
    if (selected == null || selected.isEmpty) continue;
    final snapshot = snapshotOf(dirPath);
    if (snapshot == null) {
      for (final path in selected.toList()..sort()) {
        emit(path, null);
      }
      continue;
    }
    for (final file in snapshot) {
      if (selected.contains(file.path)) {
        emit(file.path, file);
      }
    }
    // 快照命中但缺条目的选中 path（远端已删除等）：回退字典序补齐，保证无遗漏。
    final snapshotPaths = {for (final f in snapshot) f.path};
    final missing = selected.where((p) => !snapshotPaths.contains(p)).toList()
      ..sort();
    for (final path in missing) {
      emit(path, null);
    }
  }
  return result;
}
