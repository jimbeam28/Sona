// lib/core/services/download_manager.dart
// DL-01 offline-download engine: serial queue pump over the `downloads` table.
//
// Design notes:
//  • INV4 — every IO goes through injected ports: [WebDavClientInterface],
//    [IDownloadDao], [DownloadFileSystem]. The engine is fully testable with
//    a fake client/fs plus the real DAO.
//  • INV2 — strictly serial: at most one entry is downloading at any time.
//    The pump re-scans the table after each entry, so entries enqueued while
//    the pump is busy are picked up afterwards, never in parallel.
//  • The pump is DB-scanning (sanctioned by DL-01-S9's retry expectation:
//    「DB 扫描型泵会先吃掉更早的 pending 头任务」): each iteration selects the
//    oldest pending row across connections via [IDownloadDao.listPending].
//  • Cancellation is cooperative: cancel(id) flags the id and deletes the
//    row/artifacts; the in-flight transfer aborts at its next progress tick
//    (internal cancellation cleans up but never marks the entry failed).
//  • B5-8 — [recoverOrphanDownloads] marks leftover pending/downloading rows
//    failed at app start; recovery never pumps (retry is user-driven).

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../contracts/database_contract.dart';
import '../database/database_helper.dart';
import '../database/dao/download_dao.dart';
import '../network/webdav_client.dart';
import '../../shared/models/nas_file.dart';
import 'download_filename_policy.dart';

/// One enqueue request: the owning connection id plus the remote file.
typedef DownloadRequest = (int connectionId, NasFile file);

/// Credential bundle handed to the WebDAV engine.
typedef DownloadCredentials = ({String username, String password});

/// Resolves credentials for [connectionId]; returning null marks the entry
/// failed and the pump moves on.
typedef DownloadCredentialResolver = Future<DownloadCredentials?> Function(
    int connectionId);

// ── File-system port ─────────────────────────────────────────────────────────

/// Filesystem abstraction for the download root (INV4 port).
abstract class DownloadFileSystem {
  /// Waits until [downloadRoot] is safe to read (F2/check-log R1: closes the
  /// async warm-up race where an early pump read a not-yet-resolved root and
  /// got a StateError → spurious failed row). No-op for eagerly-ready impls.
  Future<void> ensureReady();

  /// Absolute path of the downloads root directory.
  String get downloadRoot;

  /// Whether a local file exists at [path] (collision probe).
  bool exists(String path);

  /// Best-effort deletion of the local file at [path]; never throws.
  void delete(String path);
}

/// Production [DownloadFileSystem] rooted at `<documents>/downloads`.
class IoDownloadFileSystem implements DownloadFileSystem {
  String? _root;
  Future<void>? _warmingUp;

  /// Resolves the real application documents directory asynchronously; the
  /// root becomes available shortly after construction. [ensureReady] awaits
  /// the same warm-up, so callers never observe a half-initialised root.
  IoDownloadFileSystem() {
    _warmingUp = _resolveDefaultRoot().then((root) => _root = root);
  }

  /// Test/preview constructor with a known root.
  @visibleForTesting
  IoDownloadFileSystem.atRoot(this._root);

  static Future<String> _resolveDefaultRoot() async {
    final docs = await getApplicationDocumentsDirectory();
    return p.join(docs.path, 'downloads');
  }

  @override
  Future<void> ensureReady() {
    if (_root != null) return Future<void>.value();
    return _warmingUp ??= _resolveDefaultRoot().then((root) => _root = root);
  }

  @override
  String get downloadRoot {
    final root = _root;
    if (root == null) {
      throw StateError('IoDownloadFileSystem download root not ready yet');
    }
    return root;
  }

  @override
  bool exists(String path) => File(path).existsSync();

  @override
  void delete(String path) {
    try {
      final file = File(path);
      if (file.existsSync()) {
        file.deleteSync();
      }
    } catch (e) {
      debugPrint('[Download] fs delete failed: $path ($e)');
    }
  }
}

// ── Engine ───────────────────────────────────────────────────────────────────

/// Internal abort signal raised when a transfer hits a user-cancelled id.
class _DownloadCancelled implements Exception {}

/// Immutable snapshot of the entry currently being processed.
class _QueueEntry {
  final int id;
  final int connectionId;
  final NasFile file;

  const _QueueEntry({
    required this.id,
    required this.connectionId,
    required this.file,
  });
}

class DownloadManager {
  final WebDavClientInterface _client;
  final IDownloadDao _dao;
  final DownloadFileSystem _fs;

  /// Minimum interval between progress-driven DB writes (DL-01-S9 节流).
  final Duration _progressThrottle;

  /// Produces the effective base URL for downloads; null → placeholder
  /// ('http://localhost', URL 注记裁决).
  final String Function()? _remoteUrlResolver;

  /// Resolves per-connection credentials; null resolver → empty credentials.
  final DownloadCredentialResolver? _credentialResolver;

  Future<void>? _pumpRunning;

  /// Ids the user asked to cancel; consulted from the progress callback.
  final Set<int> _cancelRequested = <int>{};

  /// The entry currently being transferred (for cancel-time artifact cleanup).
  int? _currentId;
  String? _currentSaveTo;

  DownloadManager({
    required WebDavClientInterface client,
    required IDownloadDao dao,
    required DownloadFileSystem fs,
    Duration progressThrottle = const Duration(milliseconds: 250),
    String Function()? remoteUrlResolver,
    DownloadCredentialResolver? credentialResolver,
  })  : _client = client,
        _dao = dao,
        _fs = fs,
        _progressThrottle = progressThrottle,
        _remoteUrlResolver = remoteUrlResolver,
        _credentialResolver = credentialResolver;

  // ── Enqueue ────────────────────────────────────────────────────────────────

  /// Inserts [items] as pending rows and returns how many were actually
  /// written. An item whose (connectionId, path) row already exists and is
  /// NOT failed is skipped (ALG1: pending/downloading/done → skip); a failed
  /// row is re-enqueued back to pending. Kicks off [pump] when done.
  Future<int> enqueueMany(List<DownloadRequest> items) async {
    var enqueued = 0;
    for (final (connectionId, file) in items) {
      final existing = await _dao.findByLocation(connectionId, file.path);
      if (existing != null && existing.status != DownloadStatus.failed) {
        continue;
      }
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      await _dao.upsert(DownloadRecord(
        connectionId: connectionId,
        filePath: file.path,
        fileName: file.name,
        remoteSize: file.size,
        localPath: '',
        status: DownloadStatus.pending,
        bytesDownloaded: 0,
        createdAt: nowMs,
        updatedAt: nowMs,
      ));
      enqueued++;
    }
    unawaited(pump());
    return enqueued;
  }

  // ── Serial pump ────────────────────────────────────────────────────────────

  /// Processes pending rows one at a time until none remain. Re-entrant calls
  /// while a pump is active await the running drain instead of starting a
  /// parallel one (INV2); the running loop naturally picks up rows inserted
  /// in the meantime (rescans between entries).
  Future<void> pump() => _pumpRunning ??= _drainPump();

  Future<void> _drainPump() async {
    try {
      while (true) {
        final next = await _nextPendingEntry();
        if (next == null) break;
        try {
          await _transfer(next);
        } on _DownloadCancelled {
          // User cancellation: row already deleted, artifacts cleaned along
          // the cancel paths — deliberately NOT marked failed.
        } catch (e) {
          debugPrint(
              '[Download] entry failed: ${redactUrlForLog(e.toString())}');
          if (!_cancelRequested.contains(next.id)) {
            try {
              await _dao.setStatus(next.id, DownloadStatus.failed);
            } catch (e2) {
              debugPrint('[Download] mark-failed write failed: $e2');
            }
          }
        } finally {
          _currentId = null;
          _currentSaveTo = null;
          _cancelRequested.remove(next.id);
        }
      }
    } catch (e) {
      // Never let a pump crash escape as an unhandled async error (e.g. a DB
      // handle closing mid-run during teardown).
      debugPrint('[Download] pump aborted: ${redactUrlForLog(e.toString())}');
    } finally {
      _pumpRunning = null;
    }
  }

  /// Oldest pending row across all connections (updated_at ASC, id ASC).
  Future<_QueueEntry?> _nextPendingEntry() async {
    final rows = await _dao.listPending();
    if (rows.isEmpty) return null;
    final rec = rows.first;
    final id = rec.id;
    if (id == null) return null;
    return _QueueEntry(
      id: id,
      connectionId: rec.connectionId,
      file: NasFile(
        name: rec.fileName,
        path: rec.filePath,
        isDirectory: false,
        size: rec.remoteSize,
      ),
    );
  }

  Future<void> _transfer(_QueueEntry entry) async {
    final id = entry.id;

    await _dao.setStatus(id, DownloadStatus.downloading, bytes: 0);

    // Row deleted (cancelled) between selection and start → drop silently.
    final fresh = await _dao.findById(id);
    if (fresh == null || _cancelRequested.contains(id)) return;

    // F2/check-log R1: root warm-up must be settled before any path math.
    await _fs.ensureReady();
    final dir = p.join(_fs.downloadRoot, '${entry.connectionId}');
    final baseName = sanitizeBaseName(entry.file.path);
    final uniqueName = resolveCollision(
      dir,
      baseName,
      (candidate) => _fs.exists(p.join(dir, candidate)),
    );
    final saveTo = p.join(dir, uniqueName);
    _currentId = id;
    _currentSaveTo = saveTo;

    var username = '';
    var password = '';
    if (_credentialResolver != null) {
      final credentials = await _credentialResolver(entry.connectionId);
      if (_cancelRequested.contains(id)) throw _DownloadCancelled();
      if (credentials == null) {
        debugPrint('[Download] auth unavailable for connection '
            '${entry.connectionId} — marking failed');
        await _dao.setStatus(id, DownloadStatus.failed);
        return;
      }
      username = credentials.username;
      password = credentials.password;
    }

    final baseUrl = _remoteUrlResolver?.call() ?? 'http://localhost';

    // First progress callback always lands (epoch anchor); later callbacks
    // are throttled into one DB write per window.
    var lastWriteAt = DateTime.fromMillisecondsSinceEpoch(0);
    try {
      await _client.downloadFile(
        url: baseUrl,
        filePath: entry.file.path,
        username: username,
        password: password,
        saveTo: saveTo,
        onProgress: (receivedBytes, total) {
          if (_cancelRequested.contains(id)) {
            throw _DownloadCancelled();
          }
          final now = DateTime.now();
          if (now.difference(lastWriteAt) >= _progressThrottle) {
            lastWriteAt = now;
            unawaited(_dao.updateProgress(id, receivedBytes));
          }
        },
      );
    } on _DownloadCancelled {
      _cleanupTransferArtifacts(saveTo);
      rethrow;
    } catch (e) {
      // Failure path: clear whatever the engine left behind (.part), keep the
      // pre-existing final file semantics owned by the engine.
      _cleanupTransferArtifacts(saveTo);
      rethrow;
    }

    if (_cancelRequested.contains(id)) {
      // Transfer completed but the user cancelled meanwhile — discard.
      _cleanupTransferArtifacts(saveTo);
      throw _DownloadCancelled();
    }

    await _dao.setStatus(
      id,
      DownloadStatus.done,
      bytes: entry.file.size,
      localPath: saveTo,
    );
  }

  void _cleanupTransferArtifacts(String saveTo) {
    _fs.delete('$saveTo.part');
    _fs.delete(saveTo);
  }

  // ── User actions ───────────────────────────────────────────────────────────

  /// Cancels the entry with [id]:
  ///  • downloading → flag the id (engine aborts at next progress tick) and
  ///    delete the row plus local artifacts (.part included);
  ///  • pending     → delete the row;
  ///  • done        → delete the row and the finished local file.
  Future<void> cancel(int id) async {
    _cancelRequested.add(id);
    final liveSaveTo = _currentId == id ? _currentSaveTo : null;
    await deleteEntry(id);
    if (liveSaveTo != null) {
      _cleanupTransferArtifacts(liveSaveTo);
    }
  }

  /// Retries a failed entry: failed → pending, then kicks the pump. Rows in
  /// any other state are ignored (ALG1: retry only leaves failed).
  Future<void> retry(int id) async {
    final rec = await _dao.findById(id);
    if (rec == null || rec.status != DownloadStatus.failed) return;
    await _dao.setStatus(id, DownloadStatus.pending);
    unawaited(pump());
  }

  /// Deletes the row with [id] plus its local artifacts (finished file and
  /// any `.part` residue); deletions are best-effort and never throw.
  Future<void> deleteEntry(int id) async {
    final rec = await _dao.findById(id);
    await _dao.deleteById(id);
    if (rec != null) {
      _fs.delete(rec.localPath);
      _fs.delete('${rec.localPath}.part');
    }
  }

  /// Removes every entry of [connectionId]: local files and `.part` residues
  /// first, then the rows.
  ///
  /// F1/check-log R1 (S9 否定断言「进行中任务一并取消」): in-flight transfers
  /// are flagged into [_cancelRequested] BEFORE the rows go away, so the
  /// engine aborts at its next progress tick / post-transfer re-check,
  /// discards artifacts via [_cleanupTransferArtifacts] and skips the
  /// failed-marking — same cooperative-cancel semantics as [cancel]. Without
  /// this, a surviving transfer would rename its `.part` onto disk after the
  /// row is gone, leaving an invisible orphan file.
  Future<void> clearAll(int connectionId) async {
    final rows = await _dao.listByConnection(connectionId);
    for (final rec in rows) {
      if (rec.status == DownloadStatus.downloading && rec.id != null) {
        _cancelRequested.add(rec.id!);
      }
      _fs.delete(rec.localPath);
      _fs.delete('${rec.localPath}.part');
    }
    await _dao.deleteByConnection(connectionId);
  }
}

// ── Startup orphan recovery (DL-01-S10 / B5-8) ───────────────────────────────

/// Marks every pending/downloading row of every connection as failed.
///
/// Runs fire-and-forget before runApp; any failure (DB unavailable etc.) is
/// logged and swallowed so startup never blocks or crashes. Deliberately does
/// NOT pump — resuming after a restart requires an explicit user retry.
Future<void> recoverOrphanDownloads() async {
  try {
    final db = await DatabaseHelper.instance.database;
    final rows =
        await db.rawQuery('SELECT DISTINCT connection_id FROM downloads');
    final dao = DownloadDao();
    for (final row in rows) {
      final connectionId = row['connection_id'];
      if (connectionId is int) {
        await dao.markAllNonDoneFailed(connectionId);
      }
    }
  } catch (e) {
    debugPrint('[Download] recoverOrphanDownloads skipped: $e');
  }
}
