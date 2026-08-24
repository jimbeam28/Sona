// lib/shared/models/download_record.dart
// Data model for the `downloads` table (DL-01 离线下载).
//
// [DownloadStatus] is a constant class of String values rather than an enum:
// the status column stores raw TEXT ('pending'/'downloading'/'done'/'failed')
// and callers compare DB rows against these constants directly.

/// State-machine states of a download entry (DL-01-ALG1).
///
/// Transitions (DL-01 spec §6 ALG1):
///   pending    → downloading (pump 选中) / 删除 / failed (启动恢复)
///   downloading→ done (成功) / failed (失败) / 删除
///   done       → 删除（唯一出口：用户删除）
///   failed     → pending (retry / re-enqueue)
class DownloadStatus {
  static const String pending = 'pending';
  static const String downloading = 'downloading';
  static const String done = 'done';
  static const String failed = 'failed';

  DownloadStatus._();
}

/// One row of the `downloads` table.
class DownloadRecord {
  final int? id; // null before first insert (AUTOINCREMENT)
  final int connectionId;
  final String filePath;
  final String fileName;
  final int? remoteSize;
  final String localPath;
  final String status;
  final int bytesDownloaded;
  final int createdAt; // millis since epoch
  final int updatedAt; // millis since epoch

  const DownloadRecord({
    this.id,
    required this.connectionId,
    required this.filePath,
    required this.fileName,
    required this.remoteSize,
    required this.localPath,
    required this.status,
    required this.bytesDownloaded,
    required this.createdAt,
    required this.updatedAt,
  });

  factory DownloadRecord.fromMap(Map<String, Object?> map) {
    return DownloadRecord(
      id: map['id'] as int?,
      connectionId: map['connection_id'] as int,
      filePath: map['file_path'] as String,
      fileName: map['file_name'] as String,
      remoteSize: map['remote_size'] as int?,
      localPath: map['local_path'] as String,
      status: map['status'] as String,
      bytesDownloaded: (map['bytes_downloaded'] as int?) ?? 0,
      createdAt: map['created_at'] as int,
      updatedAt: map['updated_at'] as int,
    );
  }

  Map<String, Object?> toMap() {
    return {
      if (id != null) 'id': id,
      'connection_id': connectionId,
      'file_path': filePath,
      'file_name': fileName,
      'remote_size': remoteSize,
      'local_path': localPath,
      'status': status,
      'bytes_downloaded': bytesDownloaded,
      'created_at': createdAt,
      'updated_at': updatedAt,
    };
  }

  @override
  String toString() => 'DownloadRecord(id: $id, connectionId: $connectionId, '
      'filePath: $filePath, status: $status, '
      'bytesDownloaded: $bytesDownloaded/$remoteSize, localPath: $localPath)';
}
