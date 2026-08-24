// lib/features/downloads/downloads_provider.dart
// DL-01 Riverpod glue: DAO / filesystem / manager providers plus the
// local-source resolver consumed by the playback orchestrator (DL-01-S6).
//
// Provider layer only — all behaviour lives in DownloadManager /
// download_dao. dart:io usage is allowed here (file existence check for the
// resolver; INV3 keeps it out of the domain layer).

import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/contracts/database_contract.dart';
import '../../core/database/dao/download_dao.dart';
import '../../core/services/download_manager.dart';
import '../../core/services/storage_utils.dart';
import '../../shared/di/providers.dart';

/// Singleton [IDownloadDao] for the `downloads` table.
final downloadDaoProvider = Provider<IDownloadDao>((ref) => DownloadDao());

/// Production filesystem rooted at `<documents>/downloads`.
final downloadFileSystemProvider =
    Provider<DownloadFileSystem>((ref) => IoDownloadFileSystem());

/// Serial download engine wired to the WebDAV client, the downloads DAO and
/// the app documents filesystem.
///
/// credentialResolver reads the connection password from secure storage with
/// the shared 5s timeout guard; a null/empty password marks that entry failed
/// and the pump continues with the next one.
final downloadManagerProvider = Provider<DownloadManager>((ref) {
  final storage = ref.watch(secureStorageProvider);
  final connectionDao = ref.watch(connectionDaoProvider);
  return DownloadManager(
    client: ref.watch(webDavClientProvider),
    dao: ref.watch(downloadDaoProvider),
    fs: ref.watch(downloadFileSystemProvider),
    credentialResolver: (connectionId) async {
      final password = await safeStorageRead(storage,
          key: 'connection_password_$connectionId');
      if (password == null || password.isEmpty) return null;
      final connection = await connectionDao.findById(connectionId);
      if (connection == null) return null;
      return (username: connection.username, password: password);
    },
  );
});

/// Local-first source resolver injected into PlaybackOrchestrator (DL-01-S6).
///
/// Returns the done record's local path when the file still exists; when the
/// row is done but the file vanished (system cleanup, U6) the record is
/// marked failed and null is returned so playback silently falls back to the
/// remote stream (B5-5). Any DB error propagates — the orchestrator wraps the
/// call in try/catch and continues remotely (BUG-18 同族兜底).
final localSourceResolverProvider =
    Provider<Future<String?> Function(int connectionId, String filePath)>(
        (ref) {
  final dao = ref.watch(downloadDaoProvider);
  return (connectionId, filePath) async {
    final localPath = await dao.findDoneLocalPath(connectionId, filePath);
    if (localPath == null) return null;
    if (File(localPath).existsSync()) return localPath;
    final rec = await dao.findByLocation(connectionId, filePath);
    final id = rec?.id;
    if (id != null) {
      unawaited(dao.setStatus(id, DownloadStatus.failed));
    }
    return null;
  };
});
