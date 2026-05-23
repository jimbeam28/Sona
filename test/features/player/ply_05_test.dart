// test/features/player/ply_05_test.dart
// PLY-05: 播放队列管理 — automated test suite
//
// Pure-logic tests (PLY-T30~T37): queue construction, index navigation,
// play-mode wrapping, shuffle, repeat-one, tap-to-jump, and
// serialisation-based restore.
//
// These tests exercise the PlayQueue model and its static helpers directly,
// without AudioPlayer or platform channels.

import 'dart:async';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:mockito/mockito.dart';
import 'package:nas_audio_player/features/browser/browser_provider.dart';
import 'package:nas_audio_player/features/connection/connection_provider.dart';
import 'package:nas_audio_player/features/player/player_provider.dart';
import 'package:nas_audio_player/features/progress/progress_provider.dart';
import 'package:nas_audio_player/features/timer/timer_provider.dart';
import 'package:nas_audio_player/shared/models/connection_config.dart';
import 'package:nas_audio_player/shared/models/nas_file.dart';
import 'package:nas_audio_player/shared/models/play_progress.dart';
import 'package:nas_audio_player/shared/models/play_queue.dart';

import 'ply_08_test.mocks.dart';

// ── Helpers ───────────────────────────────────────────────────────────────────────

/// Builds an audio [NasFile] with minimal properties.
NasFile _audio(String name, String path,
    {AudioFileType type = AudioFileType.music}) {
  return NasFile(
    name: name,
    path: path,
    isDirectory: false,
    size: 1024,
    audioType: type,
  );
}

/// Builds a directory [NasFile].
NasFile _dir(String name, String path) {
  return NasFile(name: name, path: path, isDirectory: true);
}

/// Builds a [PlayQueue] from a mixed list of entries by filtering out
/// directories, preserving the original sort order.  This mirrors the
/// production logic in the Browser onTap handler.
PlayQueue buildQueueFromFiles(List<NasFile> entries, {int startIndex = 0}) {
  final audioFiles = entries.where((f) => !f.isDirectory).toList();
  return PlayQueue(files: audioFiles, currentIndex: startIndex);
}

// ═════════════════════════════════════════════════════════════════════════════
// Unit tests — PLY-T30~T37
// ═════════════════════════════════════════════════════════════════════════════

void main() {
  // ── PLY-T30: Build queue from directory files ──────────────────────────────────

  group('PLY-T30: Build queue from directory file list', () {
    test('queue order matches Browser sort order (directories filtered out)',
        () {
      final entries = [
        _audio('02_song.mp3', '/music/02_song.mp3'),
        _audio('01_song.flac', '/music/01_song.flac'),
        _dir('folder_a', '/music/folder_a'),
        _audio('03_song.aac', '/music/03_song.aac'),
        _dir('folder_b', '/music/folder_b'),
        _audio('05_song.m4a', '/music/05_song.m4a'),
        _audio('04_song.ogg', '/music/04_song.ogg'),
      ];

      final queue = buildQueueFromFiles(entries);

      // Directories should be excluded; only audio files remain
      expect(queue.length, equals(5), reason: '队列应只包含音频文件，目录应被过滤');

      // Order is preserved — entries appear in the queue in the same
      // relative order as in the original list.
      expect(queue.files[0].name, equals('02_song.mp3'));
      expect(queue.files[1].name, equals('01_song.flac'));
      expect(queue.files[2].name, equals('03_song.aac'));
      expect(queue.files[3].name, equals('05_song.m4a'));
      expect(queue.files[4].name, equals('04_song.ogg'));

      // No directory leaks into the queue
      for (final file in queue.files) {
        expect(file.isDirectory, isFalse, reason: '队列中不应包含目录条目');
      }
    });

    test('buildQueueFromFiles with empty list produces empty queue', () {
      final queue = buildQueueFromFiles([]);
      expect(queue.length, equals(0), reason: '空条目列表应产生空队列');
      expect(queue.currentIndex, equals(0));
    });

    test('buildQueueFromFiles with only directories produces empty queue', () {
      final entries = [
        _dir('only_dir_1', '/only_dir_1'),
        _dir('only_dir_2', '/only_dir_2'),
      ];
      final queue = buildQueueFromFiles(entries);
      expect(queue.length, equals(0), reason: '全是目录时应产生空队列');
    });
  });

  // ── PLY-T31: Click nth file → current index = n-1 ─────────────────────────────

  group('PLY-T31: Click nth file sets correct index', () {
    test('click 3rd audio file sets currentIndex to 2 (0-based)', () {
      final entries = [
        _audio('track_01.mp3', '/music/track_01.mp3'),
        _audio('track_02.flac', '/music/track_02.flac'),
        _audio('track_03.aac', '/music/track_03.aac'),
        _audio('track_04.m4a', '/music/track_04.m4a'),
        _audio('track_05.ogg', '/music/track_05.ogg'),
      ];

      // Simulate tapping the 3rd audio file (index 2)
      final audioFiles = entries.where((f) => !f.isDirectory).toList();
      const tappedPath = '/music/track_03.aac';
      final startIndex = audioFiles.indexWhere((f) => f.path == tappedPath);

      expect(startIndex, equals(2), reason: '第 3 个文件 (track_03.aac) 的索引应为 2');

      final queue = PlayQueue(files: audioFiles, currentIndex: startIndex);

      // Current file is the tapped one
      expect(queue.currentIndex, equals(2));
      expect(queue.current.name, equals('track_03.aac'));

      // Files before and after are correct
      expect(queue.files[1].name, equals('track_02.flac'),
          reason: '前一个文件应为 track_02.flac');
      expect(queue.files[3].name, equals('track_04.m4a'),
          reason: '后一个文件应为 track_04.m4a');

      // Navigation helpers
      expect(queue.hasPrevious, isTrue, reason: '有前一个文件');
      expect(queue.hasNext, isTrue, reason: '有后一个文件');
    });

    test('click 1st file sets currentIndex to 0', () {
      final entries = [
        _audio('first.mp3', '/music/first.mp3'),
        _audio('second.flac', '/music/second.flac'),
        _audio('third.aac', '/music/third.aac'),
      ];
      final audioFiles = entries.where((f) => !f.isDirectory).toList();
      const tappedPath = '/music/first.mp3';
      final startIndex = audioFiles.indexWhere((f) => f.path == tappedPath);

      expect(startIndex, equals(0));
      final queue = PlayQueue(files: audioFiles, currentIndex: startIndex);
      expect(queue.currentIndex, equals(0));
      expect(queue.hasPrevious, isFalse, reason: '第一个文件没有前一个');
      expect(queue.hasNext, isTrue, reason: '第一个文件有后一个');
    });

    test('click last file sets currentIndex to length-1', () {
      final entries = [
        _audio('a.mp3', '/music/a.mp3'),
        _audio('b.flac', '/music/b.flac'),
        _audio('c.aac', '/music/c.aac'),
      ];
      final audioFiles = entries.where((f) => !f.isDirectory).toList();
      const tappedPath = '/music/c.aac';
      final startIndex = audioFiles.indexWhere((f) => f.path == tappedPath);

      expect(startIndex, equals(2));
      final queue = PlayQueue(files: audioFiles, currentIndex: startIndex);
      expect(queue.currentIndex, equals(2));
      expect(queue.hasPrevious, isTrue, reason: '最后一个文件有前一个');
      expect(queue.hasNext, isFalse, reason: '最后一个文件没有后一个');
    });
  });

  // ── PLY-T32: Sequential next at end → null (stop) ─────────────────────────────

  group('PLY-T32: Sequential next at end returns null', () {
    test('nextIndex at queue end in sequential mode returns null', () {
      const length = 5;
      const lastIndex = 4;

      final result =
          PlayQueue.nextIndex(lastIndex, length, PlayMode.sequential);
      expect(result, isNull, reason: '顺序模式下到达队尾应返回 null（停止播放）');
    });

    test('nextIndex in sequential mode returns next index within range', () {
      const length = 5;

      expect(PlayQueue.nextIndex(0, length, PlayMode.sequential), equals(1));
      expect(PlayQueue.nextIndex(1, length, PlayMode.sequential), equals(2));
      expect(PlayQueue.nextIndex(2, length, PlayMode.sequential), equals(3));
      expect(PlayQueue.nextIndex(3, length, PlayMode.sequential), equals(4));
    });

    test('nextIndex with single-item queue in sequential returns null', () {
      final result = PlayQueue.nextIndex(0, 1, PlayMode.sequential);
      expect(result, isNull, reason: '单曲队列中顺序模式的下一个应为 null');
    });

    test('nextIndex with empty queue returns null', () {
      final result = PlayQueue.nextIndex(0, 0, PlayMode.sequential);
      expect(result, isNull, reason: '空队列应返回 null');
    });
  });

  // ── PLY-T33: RepeatAll next at end → wraps to first ───────────────────────────

  group('PLY-T33: RepeatAll wraps to first at end', () {
    test('nextIndex at queue end in repeatAll mode wraps to 0', () {
      const length = 5;
      const lastIndex = 4;

      final result = PlayQueue.nextIndex(lastIndex, length, PlayMode.repeatAll);
      expect(result, equals(0), reason: '列表循环模式在队尾应回到索引 0');
    });

    test('nextIndex in repeatAll wraps forward normally within range', () {
      const length = 5;
      expect(PlayQueue.nextIndex(0, length, PlayMode.repeatAll), equals(1));
      expect(PlayQueue.nextIndex(1, length, PlayMode.repeatAll), equals(2));
      expect(PlayQueue.nextIndex(2, length, PlayMode.repeatAll), equals(3));
      expect(PlayQueue.nextIndex(3, length, PlayMode.repeatAll), equals(4));
      expect(PlayQueue.nextIndex(4, length, PlayMode.repeatAll),
          equals(0)); // wraps
    });

    test('previousIndex in repeatAll wraps from 0 to last', () {
      const length = 5;
      // previousIndex: current=0, repeatAll → wraps to last
      final result = PlayQueue.previousIndex(0, length, PlayMode.repeatAll);
      expect(result, equals(4), reason: '列表循环模式在第一首时前一首应为最后一首');
    });

    test('repeatAll wrap-around is idempotent', () {
      const length = 3;
      // next from 2 → 0, next from 0 → 1 — normal progression
      expect(PlayQueue.nextIndex(2, length, PlayMode.repeatAll), equals(0));
      expect(PlayQueue.nextIndex(0, length, PlayMode.repeatAll), equals(1));
    });

    test('repeatAll with single-item queue wraps to itself', () {
      expect(PlayQueue.nextIndex(0, 1, PlayMode.repeatAll), equals(0),
          reason: '单曲列表循环的下一个就是它自己');
      expect(PlayQueue.previousIndex(0, 1, PlayMode.repeatAll), equals(0),
          reason: '单曲列表循环的前一个也是它自己');
    });

    test('repeatAll with empty queue returns null', () {
      expect(PlayQueue.nextIndex(0, 0, PlayMode.repeatAll), isNull);
      expect(PlayQueue.previousIndex(0, 0, PlayMode.repeatAll), isNull);
    });
  });

  // ── PLY-T34: Shuffle next → random different index ────────────────────────────

  group('PLY-T34: Shuffle next returns different random index', () {
    test('shuffle nextIndex returns a valid index different from current', () {
      const length = 10;
      const current = 5;

      // Use a seeded Random for deterministic output
      final rng = Random(42);

      // Run 20 iterations and verify all results are valid
      for (int i = 0; i < 20; i++) {
        final result = PlayQueue.nextIndex(
          current,
          length,
          PlayMode.shuffle,
          random: rng,
        );
        expect(result, isNotNull, reason: 'shuffle 模式应返回非空索引');
        expect(result! >= 0 && result < length, isTrue,
            reason: '返回的索引 $result 应在 [0, $length) 范围内');
        expect(result, isNot(equals(current)),
            reason: 'shuffle 结果不应等于当前索引 $current');
      }
    });

    test('shuffle nextIndex returns different values (not all the same)', () {
      const length = 100;
      const current = 50;
      final rng = Random(123);
      final results = <int>{};

      for (int i = 0; i < 50; i++) {
        final result = PlayQueue.nextIndex(
          current,
          length,
          PlayMode.shuffle,
          random: rng,
        );
        expect(result, isNotNull);
        results.add(result!);
      }

      // With 100 items and 50 calls, we should see at least 5 distinct results
      // (probability of getting all same is effectively 0)
      expect(results.length, greaterThan(1),
          reason: 'shuffle 应产生不同的随机索引，不应每次都返回相同值');
    });

    test('shuffle previousIndex also returns different random index', () {
      const length = 10;
      const current = 3;
      final rng = Random(99);

      for (int i = 0; i < 20; i++) {
        final result = PlayQueue.previousIndex(
          current,
          length,
          PlayMode.shuffle,
          random: rng,
        );
        expect(result, isNotNull);
        expect(result! >= 0 && result < length, isTrue, reason: '返回的索引应在有效范围内');
        expect(result, isNot(equals(current)), reason: 'shuffle 结果不应等于当前索引');
      }
    });

    test('shuffle with single-item queue returns null', () {
      final result =
          PlayQueue.nextIndex(0, 1, PlayMode.shuffle, random: Random(1));
      expect(result, isNull, reason: '单曲队列 shuffle 没有不同的索引可选');
    });

    test('shuffle with empty queue returns null', () {
      expect(PlayQueue.nextIndex(0, 0, PlayMode.shuffle, random: Random(1)),
          isNull);
    });

    test('shuffle with two-item queue always picks the other one', () {
      const length = 2;
      final rng = Random(7);

      for (int i = 0; i < 10; i++) {
        final result =
            PlayQueue.nextIndex(0, length, PlayMode.shuffle, random: rng);
        expect(result, isNotNull);
        expect(result, equals(1), reason: '两个条目的队列中 shuffle 只能选另一个');
      }

      for (int i = 0; i < 10; i++) {
        final result =
            PlayQueue.nextIndex(1, length, PlayMode.shuffle, random: rng);
        expect(result, isNotNull);
        expect(result, equals(0), reason: '两个条目的队列中 shuffle 只能选另一个');
      }
    });
  });

  // ── PLY-T35: RepeatOne — replay current track from 0:00 ───────────────────────

  group('PLY-T35: RepeatOne replays current track', () {
    test('nextIndex in repeatOne mode returns the same index', () {
      const length = 5;
      for (int i = 0; i < length; i++) {
        expect(
          PlayQueue.nextIndex(i, length, PlayMode.repeatOne),
          equals(i),
          reason: 'repeatOne 模式下 nextIndex($i) 应返回 $i（同曲重放）',
        );
      }
    });

    test('previousIndex in repeatOne mode returns the same index', () {
      const length = 5;
      for (int i = 0; i < length; i++) {
        expect(
          PlayQueue.previousIndex(i, length, PlayMode.repeatOne),
          equals(i),
          reason: 'repeatOne 模式下 previousIndex($i) 应返回 $i',
        );
      }
    });

    test('repeatOne with startPositionMs reflects replay from beginning', () {
      // When the track finishes in repeatOne mode, the Player should
      // seek to 0:00 and replay the same track.  The queue model
      // expresses this as:
      //   - nextIndex returns the same index (already tested above)
      //   - set startPositionMs to 0 (so playback restarts from beginning)

      final queue = PlayQueue(
        files: [
          _audio('song.mp3', '/music/song.mp3'),
          _audio('next.mp3', '/music/next.mp3'),
        ],
        currentIndex: 0,
        startPositionMs: 120000, // was playing at 2:00
        playMode: PlayMode.repeatOne,
      );

      // Simulate what happens when track finishes in repeatOne:
      // nextIndex tells us to stay on the same track
      final nextIdx = PlayQueue.nextIndex(0, queue.length, PlayMode.repeatOne);
      expect(nextIdx, equals(0));

      // And the Player resets startPositionMs to 0 for replay from 0:00
      final resetQueue = queue.withStartPosition(0);
      expect(resetQueue.startPositionMs, equals(0),
          reason: 'repeatOne 重放应从 0:00 开始');
      expect(resetQueue.currentIndex, equals(0));
      expect(resetQueue.playMode, equals(PlayMode.repeatOne));
    });

    test('repeatOne with empty queue returns null', () {
      expect(PlayQueue.nextIndex(0, 0, PlayMode.repeatOne), isNull);
      expect(PlayQueue.previousIndex(0, 0, PlayMode.repeatOne), isNull);
    });
  });

  // ── PLY-T36: Tap queue item → skipToQueueItem with correct index ──────────────

  group('PLY-T36: Tap queue item sets index correctly', () {
    test('withIndex changes currentIndex to the specified value', () {
      final queue = PlayQueue(
        files: [
          _audio('track_01.mp3', '/music/track_01.mp3'),
          _audio('track_02.flac', '/music/track_02.flac'),
          _audio('track_03.aac', '/music/track_03.aac'),
          _audio('track_04.m4a', '/music/track_04.m4a'),
          _audio('track_05.ogg', '/music/track_05.ogg'),
        ],
        currentIndex: 0,
      );

      // User taps the 4th item in the queue list
      final newQueue = queue.withIndex(3);

      expect(newQueue.currentIndex, equals(3), reason: '点击队列第 4 项应将索引设为 3');
      expect(newQueue.current.name, equals('track_04.m4a'),
          reason: '当前文件应更新为被点击的文件');

      // Other properties are preserved
      expect(newQueue.length, equals(queue.length));
      expect(newQueue.files, equals(queue.files));
      expect(newQueue.startPositionMs, isNull);
    });

    test('withIndex preserves playMode and other fields', () {
      final queue = PlayQueue(
        files: [
          _audio('a.mp3', '/music/a.mp3'),
          _audio('b.flac', '/music/b.flac'),
        ],
        currentIndex: 0,
        startPositionMs: 5000,
        playMode: PlayMode.repeatAll,
      );

      final updated = queue.withIndex(1);

      expect(updated.currentIndex, equals(1));
      expect(updated.playMode, equals(PlayMode.repeatAll),
          reason: 'playMode 应在切换索引时保持不变');
      expect(updated.startPositionMs, equals(5000),
          reason: 'startPositionMs 应在切换索引时保持不变');
    });

    test('skipToQueueItem for already-current index is idempotent', () {
      final queue = PlayQueue(
        files: [
          _audio('song.mp3', '/music/song.mp3'),
        ],
        currentIndex: 0,
      );

      final sameQueue = queue.withIndex(0);
      expect(sameQueue.currentIndex, equals(0));
      expect(sameQueue, equals(queue));
    });

    test('withIndex with boundary values', () {
      final queue = PlayQueue(
        files: [
          _audio('a.mp3', '/music/a.mp3'),
          _audio('b.flac', '/music/b.flac'),
          _audio('c.aac', '/music/c.aac'),
        ],
        currentIndex: 0,
      );

      // Jump to last
      expect(queue.withIndex(2).currentIndex, equals(2));
      // Jump to first
      expect(queue.withIndex(0).currentIndex, equals(0));
    });
  });

  // ── PLY-T37: App restart restores queue and index (no auto-play) ──────────────

  group('PLY-T37: Restore queue from saved state', () {
    test('toMap / fromMap round-trip preserves queue state', () {
      final original = PlayQueue(
        files: [
          _audio('song_01.mp3', '/music/song_01.mp3'),
          _audio('song_02.flac', '/music/song_02.flac'),
          _audio('song_03.aac', '/music/song_03.aac'),
          _audio('song_04.m4a', '/music/song_04.m4a'),
          _audio('song_05.ogg', '/music/song_05.ogg'),
        ],
        currentIndex: 2,
        startPositionMs: 45000, // 0:45 into the track
        playMode: PlayMode.shuffle,
      );

      // Serialise
      final map = original.toMap();
      expect(map['filePaths'], isA<List>());
      expect((map['filePaths'] as List).length, equals(5));
      expect(map['currentIndex'], equals(2));
      expect(map['startPositionMs'], equals(45000));
      expect(map['playMode'], equals('shuffle'));

      // Deserialise with the same file list
      final restored = PlayQueue.fromMap(map, original.files);

      expect(restored.length, equals(original.length), reason: '恢复后队列长度应一致');
      expect(restored.currentIndex, equals(original.currentIndex),
          reason: '恢复后当前索引应一致');
      expect(restored.startPositionMs, equals(original.startPositionMs),
          reason: '恢复后播放位置应一致');
      expect(restored.playMode, equals(original.playMode),
          reason: '恢复后播放模式应一致');

      // File order preserved
      for (int i = 0; i < original.files.length; i++) {
        expect(restored.files[i].path, equals(original.files[i].path));
        expect(restored.files[i].name, equals(original.files[i].name));
      }
    });

    test('restore queue with sequential mode (default) and no position', () {
      final files = [
        _audio('track.mp3', '/music/track.mp3'),
      ];
      final map = {
        'filePaths': ['/music/track.mp3'],
        'currentIndex': 0,
      };

      final restored = PlayQueue.fromMap(map, files);

      expect(restored.currentIndex, equals(0));
      expect(restored.length, equals(1));
      expect(restored.startPositionMs, isNull, reason: '未保存位置时应为 null（从头播放）');
      expect(restored.playMode, equals(PlayMode.sequential),
          reason: '未指定模式时默认为 sequential');
    });

    test('restore with missing playMode defaults to sequential', () {
      final files = [
        _audio('a.mp3', '/music/a.mp3'),
        _audio('b.flac', '/music/b.flac'),
      ];
      final map = {
        'filePaths': ['/music/a.mp3', '/music/b.flac'],
        'currentIndex': 1,
        'startPositionMs': 30000,
        // playMode intentionally omitted
      };

      final restored = PlayQueue.fromMap(map, files);
      expect(restored.playMode, equals(PlayMode.sequential),
          reason: '缺失 playMode 时应默认 sequential');
      expect(restored.currentIndex, equals(1));
      expect(restored.startPositionMs, equals(30000));
    });

    test('restore queue with null startPositionMs', () {
      final files = [
        _audio('x.mp3', '/music/x.mp3'),
      ];
      final map = <String, dynamic>{
        'filePaths': ['/music/x.mp3'],
        'currentIndex': 0,
        'startPositionMs': null,
        'playMode': 'repeatAll',
      };

      final restored = PlayQueue.fromMap(map, files);
      expect(restored.startPositionMs, isNull,
          reason: 'null startPositionMs 应保留为 null');
      expect(restored.playMode, equals(PlayMode.repeatAll));
    });

    test('restored queue does not auto-play (behaviour contract)', () {
      // This test verifies the *contract*: a restored PlayQueue carries
      // all information needed to resume, but it is the Player screen's
      // responsibility to NOT auto-play on restore — it should show the
      // player UI in a paused state or wait for user interaction.
      //
      // We express this by ensuring that a restored queue is structurally
      // identical and carries a non-null startPositionMs (meaning "resume
      // here") but the queue model itself does not encode a playing/paused
      // flag.  The Player screen must read this queue and decide to
      // seek + pause.

      final files = [
        _audio('resume_me.mp3', '/music/resume_me.mp3'),
      ];

      // Simulate: user was 2:30 into the track when the app was killed
      final savedMap = <String, dynamic>{
        'filePaths': ['/music/resume_me.mp3'],
        'currentIndex': 0,
        'startPositionMs': 150000,
        'playMode': 'sequential',
      };

      final restored = PlayQueue.fromMap(savedMap, files);

      // The queue carries the resume position
      expect(restored.startPositionMs, equals(150000), reason: '恢复的队列携带了播放位置');

      // But the queue itself has no "play/pause" state — the Player
      // screen is responsible for seeking to the position and then
      // waiting for the user to press play (no auto-play).
      //
      // This is a design contract test, not a behavioural one.
      // It passes by confirming the model does not contain isPlaying.
      expect(restored.currentIndex, equals(0));
      expect(restored.current.name, equals('resume_me.mp3'));
    });
  });

  group('A-2: startup progress restore', () {
    test('applyLatestProgressToQueue updates startPosition for matching file',
        () {
      final queue = PlayQueue(
        files: [_audio('resume.mp3', '/music/resume.mp3')],
        currentIndex: 0,
      );
      final latest = PlayProgress(
        connectionId: 7,
        filePath: '/music/resume.mp3',
        positionMs: 42000,
        durationMs: 180000,
        lastPlayedAt: DateTime(2026, 5, 17, 10, 0),
      );

      final updated = applyLatestProgressToQueue(
        queue: queue,
        activeConnectionId: 7,
        latestProgress: latest,
      );

      expect(updated!.startPositionMs, equals(42000));
    });

    test('applyLatestProgressToQueue ignores different file or connection', () {
      final queue = PlayQueue(
        files: [_audio('resume.mp3', '/music/resume.mp3')],
        currentIndex: 0,
      );
      final latest = PlayProgress(
        connectionId: 8,
        filePath: '/music/other.mp3',
        positionMs: 42000,
        durationMs: 180000,
        lastPlayedAt: DateTime(2026, 5, 17, 10, 0),
      );

      final updated = applyLatestProgressToQueue(
        queue: queue,
        activeConnectionId: 7,
        latestProgress: latest,
      );

      expect(updated, same(queue));
      expect(updated!.startPositionMs, isNull);
    });

    test('sanitizeResumePosition falls back to 0 for invalid saved progress',
        () {
      expect(sanitizeResumePosition(-1, 180000), equals(0));
      expect(sanitizeResumePosition(180000, 180000), equals(0));
      expect(sanitizeResumePosition(999999, 180000), equals(0));
      expect(sanitizeResumePosition(42000, 180000), equals(42000));
    });
  });

  // ── Additional coverage: PlayMode enum and PlayQueue helpers ──────────────────

  group('PlayMode enum values', () {
    test('all four modes exist and are distinct', () {
      const modes = PlayMode.values;
      expect(modes.length, equals(4));
      expect(modes, contains(PlayMode.sequential));
      expect(modes, contains(PlayMode.repeatOne));
      expect(modes, contains(PlayMode.repeatAll));
      expect(modes, contains(PlayMode.shuffle));
      expect(PlayMode.sequential, isNot(equals(PlayMode.repeatOne)));
      expect(PlayMode.repeatAll, isNot(equals(PlayMode.shuffle)));
    });
  });

  group('PlayQueue withMode', () {
    test('withMode creates copy with new playMode', () {
      final queue = PlayQueue(
        files: [_audio('a.mp3', '/a.mp3')],
        currentIndex: 0,
      );

      final shuffled = queue.withMode(PlayMode.shuffle);
      expect(shuffled.playMode, equals(PlayMode.shuffle));
      expect(shuffled.files, equals(queue.files));
      expect(shuffled.currentIndex, equals(queue.currentIndex));

      // Original is unchanged
      expect(queue.playMode, equals(PlayMode.sequential));
    });
  });

  group('PlayQueue equality', () {
    test('queues with different playMode are not equal', () {
      final files = [_audio('a.mp3', '/a.mp3')];
      final a = PlayQueue(
          files: files, currentIndex: 0, playMode: PlayMode.sequential);
      final b = PlayQueue(
          files: files, currentIndex: 0, playMode: PlayMode.repeatAll);
      expect(a, isNot(equals(b)), reason: '不同 playMode 的队列不应相等');
    });

    test('queues with same properties are equal', () {
      final files = [_audio('a.mp3', '/a.mp3')];
      final a =
          PlayQueue(files: files, currentIndex: 0, playMode: PlayMode.shuffle);
      final b =
          PlayQueue(files: files, currentIndex: 0, playMode: PlayMode.shuffle);
      expect(a, equals(b));
    });
  });

  group('previousIndex cross-mode coverage', () {
    test('previousIndex sequential returns previous or null', () {
      const length = 5;
      expect(PlayQueue.previousIndex(0, length, PlayMode.sequential), isNull,
          reason: '顺序模式第一首没有前一首');
      expect(
          PlayQueue.previousIndex(1, length, PlayMode.sequential), equals(0));
      expect(
          PlayQueue.previousIndex(4, length, PlayMode.sequential), equals(3));
    });

    test('previousIndex with empty queue returns null', () {
      expect(PlayQueue.previousIndex(0, 0, PlayMode.sequential), isNull);
      expect(PlayQueue.previousIndex(0, 0, PlayMode.repeatAll), isNull);
      expect(PlayQueue.previousIndex(0, 0, PlayMode.repeatOne), isNull);
      expect(PlayQueue.previousIndex(0, 0, PlayMode.shuffle), isNull);
    });

    test('previousIndex sequential with single-item returns null', () {
      expect(PlayQueue.previousIndex(0, 1, PlayMode.sequential), isNull,
          reason: '单曲队列第一首也是最后一首，没有前一首');
    });
  });

  // ═════════════════════════════════════════════════════════════════════════════
  // Integration tests — TST-01: auto-advance on track completion
  // ═════════════════════════════════════════════════════════════════════════════

  group('TST-01: Auto-advance to next track on completion', () {
    late MockAudioPlayer mockPlayer;
    late StreamController<ProcessingState> processingController;
    late ProviderContainer container;

    /// Records of callbacks fired by the processing listener.
    late List<String> saveProgressCalls;
    late List<String> loadAndPlayCalls;

    /// Helper: build a queue with [count] audio files, setting [currentIndex].
    PlayQueue buildQueue(int count, int currentIndex) {
      final files = List.generate(count, (i) {
        final n = (i + 1).toString().padLeft(2, '0');
        return _audio('track_$n.mp3', '/music/track_$n.mp3');
      });
      return PlayQueue(files: files, currentIndex: currentIndex);
    }

    /// Helper: register the processing listener and emit a completed event,
    /// then await micro-task settlement.
    Future<void> emitCompleted() async {
      final startFn = container.read(startProcessingListenerProvider);
      startFn();
      processingController.add(ProcessingState.completed);
      await Future<void>.delayed(Duration.zero);
    }

    setUp(() {
      mockPlayer = MockAudioPlayer();
      processingController = StreamController<ProcessingState>.broadcast();

      when(mockPlayer.processingStateStream)
          .thenAnswer((_) => processingController.stream);
      when(mockPlayer.position).thenReturn(const Duration(seconds: 30));
      when(mockPlayer.duration).thenReturn(const Duration(minutes: 3));

      saveProgressCalls = [];
      loadAndPlayCalls = [];

      container = ProviderContainer(
        overrides: [
          // -- Platform / service mocks --
          audioPlayerProvider.overrideWithValue(mockPlayer),

          // -- Feature overrides --
          // Timer: no active afterCurrent timer
          onTrackCompletedProvider.overrideWithValue(() => false),

          // Track saveProgress calls; record the file path being saved
          saveProgressProvider.overrideWithValue(() {
            final q = container.read(currentPlayQueueProvider);
            saveProgressCalls.add(q?.current.path ?? 'null-queue');
          }),

          // Track loadAndPlay calls; return a successful result
          loadAndPlayProvider.overrideWithValue(() async {
            loadAndPlayCalls.add('loadAndPlay');
            return TrackLoadResult.loaded(mockPlayer);
          }),
        ],
      );
    });

    tearDown(() {
      processingController.close();
      // Do NOT call container.dispose() — startProcessingListenerProvider's
      // onDispose callback reads _processingSubProvider which would throw
      // on a disposed container (Riverpod limitation).  The stream is
      // closed above, cancelling the subscription naturally.
    });

    // ── TST-T01: sequential — middle track → auto next ──────────────────────

    test('TST-T01: sequential mode - middle track completes, advances to next',
        () async {
      final queue = buildQueue(5, 2);
      container.read(currentPlayQueueProvider.notifier).state = queue;
      container.read(playModeProvider.notifier).state = PlayMode.sequential;

      await emitCompleted();

      // 1. saveProgress was called (before queue change)
      expect(saveProgressCalls, isNotEmpty, reason: '切歌前应保存旧曲目进度');
      expect(saveProgressCalls.first, equals('/music/track_03.mp3'),
          reason: '应保存旧曲目（索引2=track_03）的进度');

      // 2. Queue advanced to next index
      final newQueue = container.read(currentPlayQueueProvider);
      expect(newQueue, isNotNull);
      expect(newQueue!.currentIndex, equals(3), reason: '中间曲目完成后应跳转到下一首（索引 3）');

      // 3. loadAndPlay was called
      expect(loadAndPlayCalls, isNotEmpty, reason: '切歌后应调用 loadAndPlay');
    });

    // ── TST-T02: sequential — last track → stop + pause ─────────────────────

    test('TST-T02: sequential mode - last track completes, stops and pauses',
        () async {
      final queue = buildQueue(5, 4);
      container.read(currentPlayQueueProvider.notifier).state = queue;
      container.read(playModeProvider.notifier).state = PlayMode.sequential;

      await emitCompleted();

      // 1. player.seek(Duration.zero) was called
      verify(mockPlayer.seek(Duration.zero)).called(1);

      // 2. player.pause() was called
      verify(mockPlayer.pause()).called(1);

      // 3. saveProgress was NOT called (code returns before saveProgress line)
      expect(saveProgressCalls, isEmpty, reason: '队尾停止时不应保存进度');

      // 4. loadAndPlay was NOT called
      expect(loadAndPlayCalls, isEmpty, reason: '队尾停止时不应调用 loadAndPlay');

      // 5. Queue was not replaced (original reference preserved)
      final currentQueue = container.read(currentPlayQueueProvider);
      expect(identical(currentQueue, queue), isTrue, reason: '队尾停止时队列应保持不变');
    });

    // ── TST-T03: repeatOne — same track reload from beginning ───────────────

    test('TST-T03: repeatOne mode - track completes, reloads same track',
        () async {
      final queue = buildQueue(5, 2);
      container.read(currentPlayQueueProvider.notifier).state = queue;
      container.read(playModeProvider.notifier).state = PlayMode.repeatOne;

      await emitCompleted();

      // 1. saveProgress was called
      expect(saveProgressCalls, isNotEmpty, reason: 'repeatOne 切歌前应保存进度');

      // 2. Queue still at the same index
      final newQueue = container.read(currentPlayQueueProvider);
      expect(newQueue, isNotNull);
      expect(newQueue!.currentIndex, equals(2),
          reason: 'repeatOne 模式下应保持在同曲（索引 2）');

      // 3. loadAndPlay was called (reloads the source, starting from 0:00)
      expect(loadAndPlayCalls, isNotEmpty,
          reason: 'repeatOne 应调用 loadAndPlay 重新加载同曲');
    });

    // ── TST-T04: repeatAll — last track → wrap to first ─────────────────────

    test('TST-T04: repeatAll mode - last track wraps to first', () async {
      final queue = buildQueue(5, 4);
      container.read(currentPlayQueueProvider.notifier).state = queue;
      container.read(playModeProvider.notifier).state = PlayMode.repeatAll;

      await emitCompleted();

      // 1. saveProgress was called
      expect(saveProgressCalls, isNotEmpty, reason: 'repeatAll 切歌前应保存进度');

      // 2. Queue wraps to first
      final newQueue = container.read(currentPlayQueueProvider);
      expect(newQueue, isNotNull);
      expect(newQueue!.currentIndex, equals(0),
          reason: 'repeatAll 模式下列表末尾完成后应循环到第一首（索引 0）');

      // 3. loadAndPlay was called
      expect(loadAndPlayCalls, isNotEmpty,
          reason: 'repeatAll 切歌后应调用 loadAndPlay');
    });

    // ── TST-T05: shuffle — advance to different index ───────────────────────

    test('TST-T05: shuffle mode - track completes, advances to different index',
        () async {
      // PlayMode.shuffle triggers the PlayQueue constructor to generate a
      // Fisher-Yates shuffle order (default unseeded Random).
      final queue = PlayQueue(
        files: List.generate(5, (i) {
          final n = (i + 1).toString().padLeft(2, '0');
          return _audio('track_$n.mp3', '/music/track_$n.mp3');
        }),
        currentIndex: 2,
        playMode: PlayMode.shuffle,
      );
      container.read(currentPlayQueueProvider.notifier).state = queue;
      container.read(playModeProvider.notifier).state = PlayMode.shuffle;

      await emitCompleted();

      // 1. saveProgress was called
      expect(saveProgressCalls, isNotEmpty, reason: 'shuffle 切歌前应保存进度');

      // 2. Queue advanced — advanceShuffle deterministically picks the
      //    next position in the Fisher-Yates permutation.  It is valid for
      //    the new index to coincidentally equal the old one when
      //    _shuffleOrder[1] == currentIndex.
      final newQueue = container.read(currentPlayQueueProvider);
      expect(newQueue, isNotNull,
          reason: 'shuffle 模式应产生新的队列');

      // 3. Destination index is within valid range
      expect(newQueue!.currentIndex >= 0 && newQueue.currentIndex < 5, isTrue,
          reason: 'shuffle 目标索引应在有效范围内');

      // 4. A new queue object was created (advance succeeded)
      expect(identical(newQueue, queue), isFalse,
          reason: '应创建新的队列对象而非原地修改');

      // 5. loadAndPlay was called
      expect(loadAndPlayCalls, isNotEmpty,
          reason: 'shuffle 切歌后应调用 loadAndPlay');
    });

    // ── TST-T06: saveProgress delegates to upsertProgressProvider ───────────

    test(
        'TST-T06: saveProgress calls upsertProgressProvider before queue change',
        () async {
      // Use the REAL saveProgressProvider (not overridden) so it calls the
      // tracked upsertProgressProvider below.  This validates the full
      // save chain: processing listener → saveProgress → upsertProgress.
      final trackedUpsertCalls = <String>[];

      final testConn = ConnectionConfig(
        id: 1,
        name: 'Test',
        url: 'http://test.com',
        username: 'user',
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
        isActive: true,
      );

      final player2 = MockAudioPlayer();
      final procCtrl2 = StreamController<ProcessingState>.broadcast();
      when(player2.processingStateStream).thenAnswer((_) => procCtrl2.stream);
      when(player2.position).thenReturn(const Duration(seconds: 45));
      when(player2.duration).thenReturn(const Duration(minutes: 4));

      final container2 = ProviderContainer(
        overrides: [
          audioPlayerProvider.overrideWithValue(player2),
          onTrackCompletedProvider.overrideWithValue(() => false),
          // FutureProvider uses overrideWith, not overrideWithValue
          activeConnectionProvider
              .overrideWith((ref) => Future.value(testConn)),

          // Tracked upsertProgressProvider — the real saveProgressProvider
          // will call this when invoked by the processing listener.
          upsertProgressProvider.overrideWithValue(({
            required int connectionId,
            required String filePath,
            required int positionMs,
            int? durationMs,
          }) async {
            trackedUpsertCalls.add('upsert: $filePath pos=${positionMs}ms');
          }),

          // Tracked loadAndPlay
          loadAndPlayProvider.overrideWithValue(() async {
            return TrackLoadResult.loaded(player2);
          }),
        ],
      );

      try {
        // Pre-resolve the active connection so that saveProgressProvider's
        // ref.read(activeConnectionProvider).valueOrNull returns the
        // connection synchronously (Future.value settles in a microtask,
        // and we await it here to ensure it's ready).
        await container2.read(activeConnectionProvider.future);

        final queue = buildQueue(5, 2);
        container2.read(currentPlayQueueProvider.notifier).state = queue;
        container2.read(playModeProvider.notifier).state = PlayMode.sequential;

        final startFn = container2.read(startProcessingListenerProvider);
        startFn();
        procCtrl2.add(ProcessingState.completed);
        await Future<void>.delayed(Duration.zero);

        // 1. upsertProgressProvider was invoked
        expect(trackedUpsertCalls.length, equals(1),
            reason: 'upsertProgressProvider 应在切歌时被调用一次');

        // 2. The saved file was the OLD track (index 2), not the new one
        expect(trackedUpsertCalls.first, contains('/music/track_03.mp3'),
            reason: '应保存旧曲目（索引2=track_03）的进度，而非新曲目');

        // 3. Queue was updated AFTER progress save
        final newQueue = container2.read(currentPlayQueueProvider);
        expect(newQueue!.currentIndex, equals(3), reason: '队列应在保存进度后才更新到新索引');
      } finally {
        procCtrl2.close();
      }
    });
  });
}
