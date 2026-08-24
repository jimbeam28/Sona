// lib/features/browser/domain/folder_searcher.dart
// SRCH-01: pre-order DFS subtree search producing a hit-event stream.
// Pure Dart — zero UI/framework dependencies; all IO is injected via fetchDir.
//
// 语义声明（spec §3.0）：与 folder_collector 的整体失败语义相反，单层
// fetchDir 抛错记入 skippedDirs 并继续扫描（搜索是只读探索，丢全部命中
// 代价过高）。两处不得互相"统一"。

import 'dart:async';

import '../../../shared/models/nas_file.dart';

const int kSearchMaxDirs = 200;

class SearchHit {
  final NasFile file;
  final String parentDirPath;
  const SearchHit({required this.file, required this.parentDirPath});
}

/// 搜索进度事件流：命中增量推送，scan 终止时给终态事件。
sealed class SearchEvent {}

class HitFound extends SearchEvent {
  final SearchHit hit;
  HitFound(this.hit);

  // 便捷透传：订阅方常直接读命中文件与所在目录（spec §3.1 形态兼容）。
  NasFile get file => hit.file;
  String get parentDirPath => hit.parentDirPath;
}

class ScanProgress extends SearchEvent {
  final int dirsScanned;
  ScanProgress(this.dirsScanned);
}

class ScanDone extends SearchEvent {
  final bool truncated; // 达到 kSearchMaxDirs
  final int skippedDirs; // 单层读取失败被跳过的目录数
  ScanDone({required this.truncated, required this.skippedDirs});
}

/// 大小写不敏感子串匹配，仅作用于文件名。
bool matchesQuery(String fileName, String query) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return false;
  return fileName.toLowerCase().contains(q);
}

/// DFS 先序扫描 rootPath 子树，产出命中事件流。
/// 单层失败跳过不中断（见 §3.0）；[isCancelled] 每层轮询，返回 true 即停止。
Stream<SearchEvent> searchFolderSubtree({
  required String rootPath,
  required String query,
  required Future<List<NasFile>> Function(String path) fetchDir,
  bool Function()? isCancelled,
  int maxDirs = kSearchMaxDirs,
}) async* {
  var dirsScanned = 0;
  var skipped = 0;
  var truncated = false;
  final stack = <String>[rootPath];
  while (stack.isNotEmpty && !truncated) {
    if (isCancelled != null && isCancelled()) return;
    final dir = stack.removeLast();
    List<NasFile> entries;
    try {
      entries = await fetchDir(dir);
    } catch (_) {
      skipped++;
      continue;
    }
    dirsScanned++;
    final subDirs = <NasFile>[];
    for (final e in entries) {
      if (e.isDirectory) {
        subDirs.add(e);
      } else if (e.audioType != null && matchesQuery(e.name, query)) {
        yield HitFound(SearchHit(file: e, parentDirPath: dir));
      }
    }
    for (final d in subDirs.reversed) {
      stack.add(d.path);
    }
    yield ScanProgress(dirsScanned);
    if (dirsScanned >= maxDirs && stack.isNotEmpty) truncated = true;
  }
  yield ScanDone(truncated: truncated, skippedDirs: skipped);
}
