// test/features/coverage/db_migration_test.dart
// TREF-06: DatabaseHelper migration specialist test suite
//
// Tests database schema creation and migration using sqflite_ffi in-memory
// databases.  Each test opens its own database so tests are fully independent.
// Does NOT rely on DatabaseHelper singleton -- exercises raw SQL directly.

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

// ── SQL fragments ─────────────────────────────────────────────────────────────

const _v1Connections = '''
  CREATE TABLE connections (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    name        TEXT NOT NULL,
    url         TEXT NOT NULL,
    username    TEXT NOT NULL,
    password    TEXT NOT NULL,
    base_path   TEXT NOT NULL DEFAULT '/',
    is_active   INTEGER NOT NULL DEFAULT 0,
    created_at  INTEGER NOT NULL,
    updated_at  INTEGER NOT NULL
  )
''';

const _v1PlayProgress = '''
  CREATE TABLE play_progress (
    id             INTEGER PRIMARY KEY AUTOINCREMENT,
    connection_id  INTEGER NOT NULL,
    file_path      TEXT NOT NULL,
    position_ms    INTEGER NOT NULL DEFAULT 0,
    duration_ms    INTEGER,
    last_played_at INTEGER NOT NULL,
    UNIQUE(connection_id, file_path),
    FOREIGN KEY(connection_id) REFERENCES connections(id) ON DELETE CASCADE
  )
''';

const _v1ProgressIndex = '''
  CREATE INDEX idx_progress_lookup
  ON play_progress(connection_id, file_path)
''';

const _v2Playlists = '''
  CREATE TABLE IF NOT EXISTS playlists (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL,
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL
  )
''';

const _v2PlaylistTracks = '''
  CREATE TABLE IF NOT EXISTS playlist_tracks (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    playlist_id INTEGER NOT NULL,
    file_path TEXT NOT NULL,
    file_name TEXT NOT NULL,
    added_at INTEGER NOT NULL,
    FOREIGN KEY(playlist_id) REFERENCES playlists(id) ON DELETE CASCADE
  )
''';

const _v2PlaylistIndex = '''
  CREATE INDEX IF NOT EXISTS idx_playlist_tracks_playlist_id
  ON playlist_tracks(playlist_id)
''';

// ── Helpers ───────────────────────────────────────────────────────────────────

/// Build a v1 schema (connections + play_progress only, no playlists).
Future<Database> _openV1Database() async {
  final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
  await db.execute('PRAGMA foreign_keys = ON');
  await db.execute(_v1Connections);
  await db.execute(_v1PlayProgress);
  await db.execute(_v1ProgressIndex);
  await db.setVersion(1);
  return db;
}

/// Build a full v2 schema (all 4 tables + indexes).
Future<Database> _openV2Database() async {
  final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
  await db.execute('PRAGMA foreign_keys = ON');
  await db.execute(_v1Connections);
  await db.execute(_v1PlayProgress);
  await db.execute(_v1ProgressIndex);
  await db.execute(_v2Playlists);
  await db.execute(_v2PlaylistTracks);
  await db.execute(_v2PlaylistIndex);
  await db.setVersion(2);
  return db;
}

/// Return table names from sqlite_master.
Future<List<String>> _tableNames(Database db) async {
  final rows = await db.rawQuery(
    "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'",
  );
  return rows.map((r) => r['name'] as String).toList();
}

/// Return index names from sqlite_master.
Future<List<String>> _indexNames(Database db) async {
  final rows = await db.rawQuery(
    "SELECT name FROM sqlite_master WHERE type='index'",
  );
  return rows.map((r) => r['name'] as String).toList();
}

/// Run the same upgrade logic as DatabaseHelper._onUpgrade.
Future<void> _runV1ToV2Upgrade(Database db) async {
  // Equivalent to: if (oldVersion < 2) _createPlaylistTables(db);
  await db.execute(_v2Playlists);
  await db.execute(_v2PlaylistTracks);
  await db.execute(_v2PlaylistIndex);
  await db.setVersion(2);
}

// ══════════════════════════════════════════════════════════════════════════════
// TREF-06: DatabaseHelper migration tests
// ══════════════════════════════════════════════════════════════════════════════

void main() {
  setUpAll(() {
    sqfliteFfiInit();
  });

  group('TREF-06 DatabaseHelper migration', () {
    // ── TREF-06-T01 (DB-MIG-01): v1 schema has connections and play_progress,
    //    no playlists tables ──────────────────────────────────────────────────

    test('DB-MIG-01: v1 schema has connections and play_progress, no playlists',
        () async {
      final db = await _openV1Database();
      addTearDown(db.close);

      final tables = await _tableNames(db);

      expect(tables, contains('connections'));
      expect(tables, contains('play_progress'));
      expect(tables, isNot(contains('playlists')));
      expect(tables, isNot(contains('playlist_tracks')));
    });

    // ── TREF-06-T02 (DB-MIG-02): v2 schema has all 4 tables ────────────────

    test('DB-MIG-02: v2 schema has all 4 tables', () async {
      final db = await _openV2Database();
      addTearDown(db.close);

      final tables = await _tableNames(db);

      expect(tables, contains('connections'));
      expect(tables, contains('play_progress'));
      expect(tables, contains('playlists'));
      expect(tables, contains('playlist_tracks'));
    });

    // ── TREF-06-T03 (DB-MIG-03): v1->v2 upgrade preserves connections data ─

    test('DB-MIG-03: v1-to-v2 upgrade preserves connections data', () async {
      final db = await _openV1Database();

      // Insert a connection row into v1 schema.
      final now = DateTime.now().millisecondsSinceEpoch;
      final connId = await db.insert('connections', {
        'name': 'Test NAS',
        'url': 'https://nas.example.com/dav',
        'username': 'admin',
        'password': 'secret',
        'base_path': '/music',
        'is_active': 1,
        'created_at': now,
        'updated_at': now,
      });

      // Perform upgrade.
      await _runV1ToV2Upgrade(db);
      addTearDown(db.close);

      // Verify data survived the migration.
      final rows = await db.query('connections');
      expect(rows.length, 1);
      expect(rows.first['id'], connId);
      expect(rows.first['name'], 'Test NAS');
      expect(rows.first['url'], 'https://nas.example.com/dav');
      expect(rows.first['username'], 'admin');
      expect(rows.first['password'], 'secret');
      expect(rows.first['base_path'], '/music');
      expect(rows.first['is_active'], 1);
    });

    // ── TREF-06-T04 (DB-MIG-04): v1->v2 upgrade creates playlist index ─────

    test('DB-MIG-04: v1-to-v2 upgrade creates playlist index', () async {
      final db = await _openV1Database();

      // Perform upgrade.
      await _runV1ToV2Upgrade(db);
      addTearDown(db.close);

      final indexes = await _indexNames(db);
      expect(indexes, contains('idx_playlist_tracks_playlist_id'));
    });

    // ── TREF-06-T05 (DB-MIG-05): v2 fresh install contains all indexes ─────

    test('DB-MIG-05: v2 fresh install contains all indexes', () async {
      final db = await _openV2Database();
      addTearDown(db.close);

      final indexes = await _indexNames(db);

      expect(indexes, contains('idx_progress_lookup'));
      expect(indexes, contains('idx_playlist_tracks_playlist_id'));
    });

    // ── TREF-06-T06 (DB-MIG-06): foreign_keys is enabled on creation ────────

    test('DB-MIG-06: foreign_keys is enabled on creation', () async {
      final db = await _openV2Database();
      addTearDown(db.close);

      final result = await db.rawQuery('PRAGMA foreign_keys');
      final fkValue = result.first.values.first;
      // PRAGMA foreign_keys returns 1 when enabled.
      expect(fkValue, 1);
    });
  });
}
