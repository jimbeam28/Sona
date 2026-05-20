// lib/core/database/database_helper.dart
// SQLite database initialisation using sqflite.

import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;

class DatabaseHelper {
  static const _dbName = 'nas_audio_player.db';
  static const _dbVersion = 2;

  DatabaseHelper._();
  static final DatabaseHelper instance = DatabaseHelper._();

  Database? _db;

  Future<Database> get database async {
    _db ??= await _openDatabase();
    return _db!;
  }

  Future<Database> _openDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = p.join(dbPath, _dbName);
    return openDatabase(
      path,
      version: _dbVersion,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('PRAGMA foreign_keys = ON');

    await db.execute('''
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
    ''');

    await db.execute('''
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
    ''');

    await db.execute('''
      CREATE INDEX idx_progress_lookup
      ON play_progress(connection_id, file_path)
    ''');

    await _createPlaylistTables(db);
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await _createPlaylistTables(db);
    }
  }

  Future<void> _createPlaylistTables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS playlists (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS playlist_tracks (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        playlist_id INTEGER NOT NULL,
        file_path TEXT NOT NULL,
        file_name TEXT NOT NULL,
        added_at INTEGER NOT NULL,
        FOREIGN KEY(playlist_id) REFERENCES playlists(id) ON DELETE CASCADE
      )
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_playlist_tracks_playlist_id
      ON playlist_tracks(playlist_id)
    ''');
  }

  // Exposed for testing (e.g. sqflite_ffi in-memory db)
  void overrideDatabase(Database db) {
    _db = db;
  }
}
