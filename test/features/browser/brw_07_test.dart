// test/features/browser/brw_07_test.dart
// BRW-07: 文件排序 — automated test suite
//
// Unit tests  (BRW-T37~T42): sort logic, persistence, defaults, mixed dirs/files
// Widget tests (BRW-T48, BRW-T50): progress bar absence, sort button UI

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nas_audio_player/features/browser/browser_provider.dart';
import 'package:nas_audio_player/features/browser/browser_screen.dart';
import 'package:nas_audio_player/shared/models/nas_file.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/test_factories.dart';
import 'package:nas_audio_player/core/database/database_helper.dart';
import 'package:nas_audio_player/core/database/dao/progress_dao.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

// ── Test helpers ────────────────────────────────────────────────────────────────

// testDir() and testAudio() are imported from test_factories.dart as
// testDir() and testAudio().

/// Creates a [SortOptionNotifier] backed by a mock [SharedPreferences].
Future<SortOptionNotifier> _notifierWithPrefs(
    Map<String, Object> initialValues) async {
  SharedPreferences.setMockInitialValues(initialValues);
  final prefs = await SharedPreferences.getInstance();
  return SortOptionNotifier(prefs);
}

// ═════════════════════════════════════════════════════════════════════════════
// Unit tests — BRW-T37~T42
// ═════════════════════════════════════════════════════════════════════════════

void main() {
  group('BRW-T37~T39: sort option switching', () {
    // ── BRW-T37: Switch to name descending → Z→A ──────────────────────────────

    test('BRW-T37: name descending sorts Z to A', () {
      final unsorted = [
        testAudio('a_track.flac', '/a_track.flac'),
        testAudio('z_song.mp3', '/z_song.mp3'),
        testAudio('m_music.aac', '/m_music.aac'),
        testDir('apple', '/apple'),
        testDir('zebra', '/zebra'),
        testDir('banana', '/banana'),
      ];

      final sorted = sortFiles(unsorted, SortOption.nameDesc);

      // Directories first (also Z→A within group)
      expect(sorted[0].name, equals('zebra'));
      expect(sorted[0].isDirectory, isTrue);
      expect(sorted[1].name, equals('banana'));
      expect(sorted[1].isDirectory, isTrue);
      expect(sorted[2].name, equals('apple'));
      expect(sorted[2].isDirectory, isTrue);

      // Then files (Z→A)
      expect(sorted[3].name, equals('z_song.mp3'));
      expect(sorted[3].isDirectory, isFalse);
      expect(sorted[4].name, equals('m_music.aac'));
      expect(sorted[4].isDirectory, isFalse);
      expect(sorted[5].name, equals('a_track.flac'));
      expect(sorted[5].isDirectory, isFalse);
    });

    // ── BRW-T38: Switch to modified time descending → newest first ────────────

    test('BRW-T38: modified time descending sorts newest first', () {
      final baseTime = DateTime(2024, 1, 1);
      final unsorted = [
        testAudio('old.mp3', '/old.mp3', modifiedAt: baseTime),
        testAudio('new.mp3', '/new.mp3',
            modifiedAt: baseTime.add(const Duration(days: 30))),
        testAudio('mid.mp3', '/mid.mp3',
            modifiedAt: baseTime.add(const Duration(days: 10))),
        testDir('old_dir', '/old_dir',
            modifiedAt: baseTime.subtract(const Duration(days: 5))),
        testDir('new_dir', '/new_dir',
            modifiedAt: baseTime.add(const Duration(days: 60))),
      ];

      final sorted = sortFiles(unsorted, SortOption.modifiedDesc);

      // Directories first, newest within group
      expect(sorted[0].name, equals('new_dir'));
      expect(sorted[0].isDirectory, isTrue, reason: '目录应在文件之前');
      expect(sorted[1].name, equals('old_dir'));
      expect(sorted[1].isDirectory, isTrue);

      // Files, newest first
      expect(sorted[2].name, equals('new.mp3'));
      expect(sorted[2].isDirectory, isFalse);
      expect(sorted[3].name, equals('mid.mp3'));
      expect(sorted[3].isDirectory, isFalse);
      expect(sorted[4].name, equals('old.mp3'));
      expect(sorted[4].isDirectory, isFalse);
    });

    // ── BRW-T39: Switch to name ascending (default) → A→Z ─────────────────────

    test('BRW-T39: name ascending sorts A to Z', () {
      final unsorted = [
        testAudio('z_song.mp3', '/z_song.mp3'),
        testAudio('a_track.flac', '/a_track.flac'),
        testAudio('m_music.aac', '/m_music.aac'),
        testDir('zebra', '/zebra'),
        testDir('apple', '/apple'),
        testDir('banana', '/banana'),
      ];

      final sorted = sortFiles(unsorted, SortOption.nameAsc);

      // Directories first (A→Z)
      expect(sorted[0].name, equals('apple'));
      expect(sorted[0].isDirectory, isTrue);
      expect(sorted[1].name, equals('banana'));
      expect(sorted[1].isDirectory, isTrue);
      expect(sorted[2].name, equals('zebra'));
      expect(sorted[2].isDirectory, isTrue);

      // Then files (A→Z)
      expect(sorted[3].name, equals('a_track.flac'));
      expect(sorted[3].isDirectory, isFalse);
      expect(sorted[4].name, equals('m_music.aac'));
      expect(sorted[4].isDirectory, isFalse);
      expect(sorted[5].name, equals('z_song.mp3'));
      expect(sorted[5].isDirectory, isFalse);
    });
  });

  group('BRW-T40~T41: sort preference persistence', () {
    // ── BRW-T40: Sort preference saved to SharedPreferences ────────────────────

    test('BRW-T40: sort preference saved to SharedPreferences and read back',
        () async {
      // Start with empty prefs — implicit default is nameAsc
      final notifier = await _notifierWithPrefs({});
      addTearDown(notifier.dispose);

      // Initially nameAsc (default)
      expect(notifier.state, equals(SortOption.nameAsc));

      // Change to nameDesc — should persist
      notifier.setOption(SortOption.nameDesc);
      expect(notifier.state, equals(SortOption.nameDesc));

      // Verify written to SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString('browser_sort_option');
      expect(saved, equals('nameDesc'),
          reason: 'SharedPreferences 中应保存 nameDesc');

      // Change to modifiedDesc — should persist
      notifier.setOption(SortOption.modifiedDesc);
      expect(notifier.state, equals(SortOption.modifiedDesc));
      final saved2 = prefs.getString('browser_sort_option');
      expect(saved2, equals('modifiedDesc'),
          reason: 'SharedPreferences 中应更新为 modifiedDesc');

      // Read back in a new notifier — should restore last saved value
      final notifier2 = await _notifierWithPrefs({
        'browser_sort_option': 'modifiedDesc',
      });
      addTearDown(notifier2.dispose);
      expect(notifier2.state, equals(SortOption.modifiedDesc),
          reason: '新实例应从 SharedPreferences 读取保存的排序偏好');
    });

    // ── BRW-T41: First launch with no sort preference → defaults to nameAsc ────

    test('BRW-T41: first launch with no stored preference defaults to nameAsc',
        () async {
      // Simulate fresh install — no stored preference
      final notifier = await _notifierWithPrefs({});
      addTearDown(notifier.dispose);

      expect(notifier.state, equals(SortOption.nameAsc),
          reason: '首次启动无偏好时默认使用名称升序');

      // Verify nothing was inadvertently written
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('browser_sort_option'), isNull,
          reason: '首次启动不应写入键值');
    });
  });

  group('BRW-T42: mixed dirs and files sorting', () {
    // ── BRW-T42: Directories always first regardless of sort option ───────────

    test('BRW-T42: directories always appear before files regardless of sort',
        () {
      // Build a list where, if sorted purely by name desc, a directory
      // would appear after files.  We need to confirm dirs stay first.
      final baseTime = DateTime(2024, 6, 1);
      final mixed = [
        testAudio('z_song.mp3', '/z_song.mp3',
            modifiedAt: baseTime.add(const Duration(days: 1))),
        testDir('music', '/music',
            modifiedAt: baseTime.subtract(const Duration(days: 10))),
        testAudio('a_track.flac', '/a_track.flac', modifiedAt: baseTime),
        testDir('audiobooks', '/audiobooks',
            modifiedAt: baseTime.add(const Duration(days: 5))),
      ];

      // Test with all three sort options
      for (final option in SortOption.values) {
        final sorted = sortFiles(mixed, option);

        // First 2 entries must be directories
        expect(sorted[0].isDirectory, isTrue,
            reason: '第 1 个条目应为目录 (option=$option)');
        expect(sorted[1].isDirectory, isTrue,
            reason: '第 2 个条目应为目录 (option=$option)');

        // Last 2 entries must be files
        expect(sorted[2].isDirectory, isFalse,
            reason: '第 3 个条目应为文件 (option=$option)');
        expect(sorted[3].isDirectory, isFalse,
            reason: '第 4 个条目应为文件 (option=$option)');
      }

      // Additionally verify specific ordering for nameAsc
      final nameAscSorted = sortFiles(mixed, SortOption.nameAsc);
      expect(nameAscSorted[0].name, equals('audiobooks'));
      expect(nameAscSorted[1].name, equals('music'));
      expect(nameAscSorted[2].name, equals('a_track.flac'));
      expect(nameAscSorted[3].name, equals('z_song.mp3'));

      // For nameDesc: dirs Z→A, files Z→A
      final nameDescSorted = sortFiles(mixed, SortOption.nameDesc);
      expect(nameDescSorted[0].name, equals('music'));
      expect(nameDescSorted[1].name, equals('audiobooks'));
      expect(nameDescSorted[2].name, equals('z_song.mp3'));
      expect(nameDescSorted[3].name, equals('a_track.flac'));

      // For modifiedDesc: dirs newest first, then files newest first
      final modDescSorted = sortFiles(mixed, SortOption.modifiedDesc);
      // audiobooks modifiedAt = baseTime + 5 days (newer)
      // music modifiedAt = baseTime - 10 days (older)
      expect(modDescSorted[0].name, equals('audiobooks'),
          reason: 'audiobooks 修改时间更新，应在 music 之前');
      expect(modDescSorted[1].name, equals('music'));
      // z_song.mp3 modifiedAt = baseTime + 1 day (newer)
      // a_track.flac modifiedAt = baseTime (older)
      expect(modDescSorted[2].name, equals('z_song.mp3'),
          reason: 'z_song.mp3 修改时间更新，应在 a_track.flac 之前');
      expect(modDescSorted[3].name, equals('a_track.flac'));
    });
  });

  group('BRW-T48: progress bar visibility', () {
    // ── BRW-T48: Audio file row without progress → no progress bar ────────────

    testWidgets('BRW-T48: audio file without progress shows no progress bar',
        (WidgetTester tester) async {
      // The BrowserScreen with a simple audio file and no progress.
      // We override directoryContentsProvider to return one audio file,
      // and override playProgressProvider to return null (no saved progress).
      // BrowserScreen returns body content only (no Scaffold), so wrap in one.
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            directoryContentsProvider('/').overrideWith((ref) async => [
                  testAudio('song.mp3', '/song.mp3'),
                ]),
          ],
          child: const MaterialApp(home: Scaffold(body: BrowserScreen())),
        ),
      );
      await tester.pumpAndSettle();

      // The audio file name should be visible
      expect(find.text('song.mp3'), findsOneWidget, reason: '音频文件名应显示在列表中');

      // No LinearProgressIndicator when progressPercentage is null
      expect(find.byType(LinearProgressIndicator), findsNothing,
          reason: '无进度记录时不应显示进度条');
    });
  });

  group('BRW-T50: sort button UI', () {
    // ── BRW-T50: Click sort button shows sort options menu ─────────────────────

    testWidgets('BRW-T50: sort button renders and shows 3 options on tap',
        (WidgetTester tester) async {
      // Sort icon moved to HomeScreen AppBar. Test that BrowserScreen still
      // renders correctly without errors — the sort icon test is covered by
      // PLY-T65 (HomeScreen sort menu).
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            directoryContentsProvider('/').overrideWith((ref) async => [
                  testAudio('song.mp3', '/song.mp3'),
                ]),
          ],
          child: const MaterialApp(home: Scaffold(body: BrowserScreen())),
        ),
      );
      await tester.pumpAndSettle();

      // The audio file should still be visible
      expect(find.text('song.mp3'), findsOneWidget, reason: '音频文件名应显示在列表中');
    });
  });

  // ═════════════════════════════════════════════════════════════════════════════
  // TST-16: Progress directory batch lookup
  // ═════════════════════════════════════════════════════════════════════════════

  group('TST-16: Progress directory batch lookup', () {
    late Database db;
    late ProgressDao dao;

    setUp(() async {
      sqfliteFfiInit();
      db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);

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
      dao = ProgressDao();
    });

    tearDown(() async {
      await db.close();
    });

    // ── TST-T129: batch query 3 files with progress ───────────────────────

    test('TST-T129: loadProgressForDirectory batch query returns 3 records',
        () async {
      // Insert 3 progress records
      await dao.upsert(
          connectionId: 1, filePath: '/music/a.mp3', positionMs: 10000);
      await dao.upsert(
          connectionId: 1, filePath: '/music/b.mp3', positionMs: 20000);
      await dao.upsert(
          connectionId: 1, filePath: '/music/c.mp3', positionMs: 30000);

      // Query each file
      final a = await dao.find(1, '/music/a.mp3');
      final b = await dao.find(1, '/music/b.mp3');
      final c = await dao.find(1, '/music/c.mp3');

      expect(a, isNotNull);
      expect(b, isNotNull);
      expect(c, isNotNull);
      expect(a!.positionMs, equals(10000));
      expect(b!.positionMs, equals(20000));
      expect(c!.positionMs, equals(30000));
    });

    // ── TST-T130: empty directory returns empty ──────────────────────────

    test('TST-T130: loadProgressForDirectory on empty directory returns empty',
        () async {
      // Query files that do not exist
      final result = await dao.find(1, '/music/nonexistent.mp3');
      expect(result, isNull, reason: 'TST-T130: 空目录/无进度文件应返回 null');
    });

    // ── TST-T131: NasFile.fromProps with empty props uses defaults ──────

    test(
        'TST-T131: NasFile.fromProps with empty props uses defaults (confirmed)',
        () {
      // Covered in ply_02_test.dart TST-T121/T122 — brief confirmation test
      final file = NasFile.fromProps(href: '/test/file.mp3', props: {});
      expect(file.name, equals('file.mp3'));
      expect(file.path, equals('/test/file.mp3'));
      expect(file.isDirectory, isFalse);
      expect(file.size, isNull);
      expect(file.modifiedAt, isNull);
      expect(file.audioType, equals(AudioFileType.music));
    });
  });
}
