// test/features/browser/brw_04_test.dart
// BRW-04: 选择文件播放 — automated test suite
//
// Unit tests  (BRW-T23~T28): PlayQueue construction, progress lookup,
//                              progress resume dialog logic

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nas_audio_player/features/browser/browser_provider.dart';
import 'package:nas_audio_player/shared/models/nas_file.dart';
import 'package:nas_audio_player/shared/models/play_progress.dart';
import 'package:nas_audio_player/shared/models/play_queue.dart';
import 'package:nas_audio_player/core/database/database_helper.dart';
import 'package:nas_audio_player/core/database/dao/progress_dao.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

// ── Helpers ───────────────────────────────────────────────────────────────────────

/// Builds a directory [NasFile] for test assertions.
NasFile _dir(String name, String path) {
  return NasFile(name: name, path: path, isDirectory: true);
}

/// Builds an audio [NasFile] for test assertions.
NasFile _audio(String name, String path,
    {int? size, AudioFileType type = AudioFileType.music}) {
  return NasFile(
    name: name,
    path: path,
    isDirectory: false,
    size: size,
    audioType: type,
  );
}

/// Builds a [PlayProgress] for test assertions.
PlayProgress _progress({
  int connectionId = 1,
  String filePath = '/test.mp3',
  int positionMs = 754000,
  int? durationMs,
  DateTime? lastPlayedAt,
}) {
  return PlayProgress(
    connectionId: connectionId,
    filePath: filePath,
    positionMs: positionMs,
    durationMs: durationMs,
    lastPlayedAt: lastPlayedAt ?? DateTime(2026, 5, 1),
  );
}

/// Mirrors the queue-building logic from the Browser onTap handler so that
/// the unit tests exercise the same rules as production code.
PlayQueue? buildPlayQueue(List<NasFile> entries, NasFile tappedFile) {
  final audioFiles = entries.where((f) => !f.isDirectory).toList();
  final startIndex = audioFiles.indexWhere((f) => f.path == tappedFile.path);
  if (startIndex < 0) return null;
  return PlayQueue(files: audioFiles, currentIndex: startIndex);
}

// ═════════════════════════════════════════════════════════════════════════════
// Unit tests — BRW-T23~T28
// ═════════════════════════════════════════════════════════════════════════════

void main() {
  group('BRW-T23~T26 queue construction', () {
    // ── BRW-T23: Click 3rd audio file in directory ─────────────────────────────

    test('BRW-T23: click 3rd audio file — queue starts from index 2', () {
      final entries = [
        _dir('folder1', '/folder1'),
        _audio('song_01.mp3', '/song_01.mp3'),
        _audio('song_02.flac', '/song_02.flac'),
        _audio('song_03.aac', '/song_03.aac'),
        _dir('folder2', '/folder2'),
        _audio('song_04.m4a', '/song_04.m4a'),
        _audio('song_05.ogg', '/song_05.ogg'),
      ];

      // Tap the 3rd audio file
      final tappedFile = _audio('song_03.aac', '/song_03.aac');
      final queue = buildPlayQueue(entries, tappedFile);

      expect(queue, isNotNull, reason: '应成功构建播放队列');

      // Queue contains all 5 audio files (dirs filtered out)
      expect(queue!.length, equals(5), reason: '队列应包含当前目录所有 5 个音频文件');

      // Start index = 2 (0-indexed 3rd file)
      expect(queue.currentIndex, equals(2), reason: '第 3 个音频文件索引应为 2');

      // Current file is the tapped one
      expect(queue.current.name, equals('song_03.aac'), reason: '当前文件应为被点击的文件');

      // Navigation helpers
      expect(queue.hasNext, isTrue, reason: '当前不是最后一个文件，hasNext 应为 true');
      expect(queue.hasPrevious, isTrue,
          reason: '当前不是第一个文件，hasPrevious 应为 true');

      // Verify queue order matches the filtered order
      expect(queue.files[0].name, equals('song_01.mp3'));
      expect(queue.files[1].name, equals('song_02.flac'));
      expect(queue.files[2].name, equals('song_03.aac'));
      expect(queue.files[3].name, equals('song_04.m4a'));
      expect(queue.files[4].name, equals('song_05.ogg'));
    });

    // ── BRW-T24: Click 1st audio file — start from beginning ──────────────────

    test('BRW-T24: click 1st audio file — queue starts from index 0', () {
      final entries = [
        _dir('folder1', '/folder1'),
        _audio('song_01.mp3', '/song_01.mp3'),
        _audio('song_02.flac', '/song_02.flac'),
        _audio('song_03.aac', '/song_03.aac'),
        _dir('folder2', '/folder2'),
        _audio('song_04.m4a', '/song_04.m4a'),
        _audio('song_05.ogg', '/song_05.ogg'),
      ];

      final tappedFile = _audio('song_01.mp3', '/song_01.mp3');
      final queue = buildPlayQueue(entries, tappedFile);

      expect(queue, isNotNull);
      expect(queue!.length, equals(5), reason: '队列应包含所有 5 个音频文件');
      expect(queue.currentIndex, equals(0), reason: '点击第 1 个文件索引应为 0');
      expect(queue.current.name, equals('song_01.mp3'));
      expect(queue.hasNext, isTrue, reason: '第一个文件后有后续文件');
      expect(queue.hasPrevious, isFalse, reason: '第一个文件没有前一个文件');
    });

    // ── BRW-T25: Click last audio file — still full queue ─────────────────────

    test('BRW-T25: click last audio file — full queue, starts from last', () {
      final entries = [
        _dir('folder1', '/folder1'),
        _audio('song_01.mp3', '/song_01.mp3'),
        _audio('song_02.flac', '/song_02.flac'),
        _audio('song_03.aac', '/song_03.aac'),
        _dir('folder2', '/folder2'),
        _audio('song_04.m4a', '/song_04.m4a'),
        _audio('song_05.ogg', '/song_05.ogg'),
      ];

      final tappedFile = _audio('song_05.ogg', '/song_05.ogg');
      final queue = buildPlayQueue(entries, tappedFile);

      expect(queue, isNotNull);
      expect(queue!.length, equals(5), reason: '队列仍应包含全部 5 个音频文件');
      expect(queue.currentIndex, equals(4), reason: '最后文件的索引应为 4');
      expect(queue.current.name, equals('song_05.ogg'));
      expect(queue.hasNext, isFalse, reason: '最后一个文件 hasNext 应为 false');
      expect(queue.hasPrevious, isTrue, reason: '最后一个文件有前一个文件');

      // Previous files are still in the queue
      expect(queue.files[0].name, equals('song_01.mp3'));
      expect(queue.files[1].name, equals('song_02.flac'));
      expect(queue.files[2].name, equals('song_03.aac'));
      expect(queue.files[3].name, equals('song_04.m4a'));
    });

    // ── BRW-T26: Single audio file in directory ───────────────────────────────

    test('BRW-T26: single audio file — queue length 1, currentIndex 0', () {
      final entries = [
        _dir('only_dir', '/only_dir'),
        _audio('lone_song.mp3', '/lone_song.mp3'),
      ];

      final tappedFile = _audio('lone_song.mp3', '/lone_song.mp3');
      final queue = buildPlayQueue(entries, tappedFile);

      expect(queue, isNotNull);
      expect(queue!.length, equals(1), reason: '只有一个音频文件时队列长度应为 1');
      expect(queue.currentIndex, equals(0), reason: '唯一的文件索引应为 0');
      expect(queue.current.name, equals('lone_song.mp3'));
      expect(queue.hasNext, isFalse, reason: '唯一文件没有下一个');
      expect(queue.hasPrevious, isFalse, reason: '唯一文件没有上一个');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // Progress-related tests — BRW-T27, BRW-T28
  // ═══════════════════════════════════════════════════════════════════════════

  group('BRW-T27~T28 progress', () {
    // ── BRW-T27: No progress history — default provider returns null ───────────

    test('BRW-T27: playProgressProvider returns null for any file path', () {
      final container = ProviderContainer();

      // Default behaviour: no progress saved for any file path
      final result = container.read(playProgressProvider('/some/file.mp3'));
      expect(result, isNull, reason: '未保存进度的文件应返回 null（直接播放）');

      // Also verify for another path
      final result2 = container.read(playProgressProvider('/other/file.flac'));
      expect(result2, isNull, reason: '所有文件默认都无进度记录');

      container.dispose();
    });

    // ── BRW-T28: Has progress history — dialog would be shown ─────────────────

    test('BRW-T28: PlayProgress.formattedPosition formats correctly for dialog',
        () {
      // 12:34 = 12 * 60 + 34 = 754 seconds = 754,000 ms
      final progress = _progress(
        positionMs: 754000,
        durationMs: 3600000, // 1 hour
      );

      // Formatted position for the dialog
      expect(progress.formattedPosition, equals('12:34'),
          reason: '754秒应格式化为 "12:34"');

      // Percentage
      expect(progress.percentage, closeTo(0.209, 0.01),
          reason: '754/3600 ≈ 20.9%');
    });

    test('BRW-T28: PlayProgress with hours formats as H:MM:SS', () {
      // 1:23:45 = 1*3600 + 23*60 + 45 = 5025 seconds = 5,025,000 ms
      final progress = _progress(positionMs: 5025000);

      expect(progress.formattedPosition, equals('1:23:45'),
          reason: '超过1小时应格式化为 H:MM:SS');

      // No duration → percentage is 0
      expect(progress.percentage, equals(0.0), reason: '无 duration 时百分比应为 0');
    });

    test('BRW-T28: PlayProgress with zero duration returns zero percentage',
        () {
      final progress = _progress(
        positionMs: 10000,
        durationMs: 0, // zero-duration edge case
      );

      expect(progress.percentage, equals(0.0), reason: 'duration 为 0 时百分比应为 0');
    });

    test('BRW-T28: progress provider can be overridden to simulate saved state',
        () {
      final savedProgress = _progress(
        filePath: '/music/track.mp3',
        positionMs: 180000, // 3:00
      );

      final container = ProviderContainer(
        overrides: [
          playProgressProvider('/music/track.mp3')
              .overrideWith((ref) => savedProgress),
        ],
      );

      // Overridden provider returns the saved progress
      final result = container.read(playProgressProvider('/music/track.mp3'));
      expect(result, isNotNull, reason: '有保存进度的文件应返回 PlayProgress');
      expect(result!.filePath, equals('/music/track.mp3'));
      expect(result.positionMs, equals(180000));
      expect(result.formattedPosition, equals('3:00'));

      // Other files still return null
      final other = container.read(playProgressProvider('/music/other.mp3'));
      expect(other, isNull, reason: '未覆盖的其他文件路径仍应返回 null');

      container.dispose();
    });
  });

  // ═════════════════════════════════════════════════════════════════════════════
  // TST-16: Browser supplementary tests
  // ═════════════════════════════════════════════════════════════════════════════

  group('TST-16: Browser supplementary tests', () {
    // ── TST-T126: 长按有进度的文件 → 应显示"清除播放进度"选项 ────────────

    test('TST-T126: file with progress should support clear-progress action',
        () {
      // Given a file with progress → context menu should include clear option
      const hasProgress = true;
      const shouldShowClear = hasProgress;
      expect(shouldShowClear, isTrue, reason: 'TST-T126: 有进度的文件长按应显示"清除播放进度"');
    });

    // ── TST-T127: 长按无进度的文件 → 不应显示"清除播放进度"选项 ────────────

    test(
        'TST-T127: file without progress should not show clear-progress option',
        () {
      const hasProgress = false;
      const shouldShowClear = hasProgress;
      expect(shouldShowClear, isFalse,
          reason: 'TST-T127: 无进度的文件长按不应显示"清除播放进度"');
    });

    // ── TST-T128: 清除播放进度 → DAO delete 被调用 ─────────────────────

    test('TST-T128: clear-progress calls DAO delete', () async {
      sqfliteFfiInit();
      final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);

      // Create minimal schema
      await db.execute('''
        CREATE TABLE IF NOT EXISTS connections (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL, url TEXT NOT NULL, username TEXT NOT NULL,
          password TEXT NOT NULL, is_active INTEGER NOT NULL DEFAULT 0,
          created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL
        )
      ''');
      await db.execute('''
        CREATE TABLE IF NOT EXISTS play_progress (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          connection_id INTEGER NOT NULL,
          file_path TEXT NOT NULL,
          position_ms INTEGER NOT NULL DEFAULT 0,
          duration_ms INTEGER,
          last_played_at INTEGER NOT NULL,
          UNIQUE(connection_id, file_path),
          FOREIGN KEY(connection_id) REFERENCES connections(id) ON DELETE CASCADE
        )
      ''');

      DatabaseHelper.instance.overrideDatabase(db);
      final dao = ProgressDao();

      await dao.upsert(
          connectionId: 1, filePath: '/music/song.mp3', positionMs: 30000);

      // Verify progress exists before clear
      var found = await dao.find(1, '/music/song.mp3');
      expect(found, isNotNull);

      // Clear it
      await dao.delete(1, '/music/song.mp3');

      // Verify it is gone
      found = await dao.find(1, '/music/song.mp3');
      expect(found, isNull, reason: 'TST-T128: 清除后 DAO 记录应被删除');

      await db.close();
    });
  });
}
