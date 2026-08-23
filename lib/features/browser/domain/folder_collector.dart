// lib/features/browser/domain/folder_collector.dart
// Pure pre-order DFS collection of audio files under a directory subtree.
// Zero Flutter/Provider/http dependencies — all IO is injected via fetchDir.

import '../../../shared/models/nas_file.dart';

const int kFolderScanMaxFiles = 500;

class FolderScanResult {
  final List<NasFile> files;
  final bool truncated;

  const FolderScanResult({required this.files, required this.truncated});
}

Future<FolderScanResult> collectFolderAudio({
  required String rootPath,
  required Future<List<NasFile>> Function(String path) fetchDir,
  int maxFiles = kFolderScanMaxFiles,
}) async {
  final collected = <NasFile>[];
  var truncated = false;
  Future<void> dfs(String dir) async {
    if (truncated) return;
    final entries = await fetchDir(dir);
    for (final e in entries) {
      if (truncated) return;
      if (e.isDirectory) {
        await dfs(e.path);
      } else if (e.audioType != null) {
        collected.add(e);
        if (collected.length >= maxFiles) {
          truncated = true;
          return;
        }
      }
    }
  }

  await dfs(rootPath);
  return FolderScanResult(files: collected, truncated: truncated);
}
