// test/features/coverage/bug_bug26_repro_test.dart
// BUG-26 门禁测试（spec docs/features/BUG-26.md §5.4 指定文件）。
//
// 锚定 cr-20260724-0110 DB3+DB4+DB5+DB6（LIST4 与 DB3 同根）：
//   DB3: removeTracks([]) → `WHERE id IN ()` 非法 SQL 直接抛异常。
//        修复：首行 `if (trackIds.isEmpty) return;` 提前返回，不执行任何 SQL。
//   DB4: reorderTrack 无索引越界校验，坏 index 抛 RangeError。
//        修复：在既有守卫后增加 oldIndex/newIndex 边界检查，越界静默返回。
//   DB5: connection_dao.delete 对 play_progress 删除用 `catch (_)` 吞掉一切。
//        修复：收窄为 `on DatabaseException`，仅 isNoSuchTableError() 被忽略，
//        其余 rethrow 向上传播。
//   DB6: DAO 直接 DateTime.now()，"当前时刻"不可注入（P16）。
//        修复：三个 DAO 构造函数注入 clock（默认 DateTime.now，生产不变）。
//
// 双态门禁：修复前 BUG-26-S1/S2/S3/S4 各组用例 FAIL，修复后 PASS。

import 'package:flutter_test/flutter_test.dart';
import 'package:nas_audio_player/core/database/dao/connection_dao.dart';
import 'package:nas_audio_player/core/database/dao/playlist_dao.dart';
import 'package:nas_audio_player/core/database/dao/progress_dao.dart';
import 'package:nas_audio_player/shared/models/play_progress.dart';
import 'package:nas_audio_player/shared/models/playlist.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../helpers/test_database.dart';
import '../../helpers/test_factories.dart';

/// 受控时钟固定时刻（BUG-26-S4）：远离测试运行的真实系统时间，
/// 若实现仍取 DateTime.now()，时间戳断言必然失败。
final _fixedClock = DateTime(2026, 1, 1);
final _fixedMs = _fixedClock.millisecondsSinceEpoch;

/// 2020 年的"旧"时间戳：reorderTrack 前的种子 added_at，
/// 与注入时钟值区分，用于断言越界守卫不改动任何行。
final _seedMs = DateTime(2020, 1, 1).millisecondsSinceEpoch;

void main() {
  setUpAll(() {
    initSqfliteFfi();
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // BUG-26-S1 / INV1: removeTracks 空列表提前返回
  // ═══════════════════════════════════════════════════════════════════════════

  group('BUG-26-S1: removeTracks 空列表提前返回', () {
    late Database db;
    late PlaylistDao dao;
    late int playlistId;
    late List<PlaylistTrack> seeded;

    setUp(() async {
      db = await openTestDatabase(TestSchema.playlist);
      dao = PlaylistDao();
      playlistId = await dao.insertPlaylist(Playlist(
        name: 'P',
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
      ));
      await dao.addTracks([
        PlaylistTrack(
          playlistId: playlistId,
          filePath: '/a.mp3',
          fileName: 'a.mp3',
          addedAt: DateTime.fromMillisecondsSinceEpoch(_seedMs),
        ),
        PlaylistTrack(
          playlistId: playlistId,
          filePath: '/b.mp3',
          fileName: 'b.mp3',
          addedAt: DateTime.fromMillisecondsSinceEpoch(_seedMs + 1),
        ),
        PlaylistTrack(
          playlistId: playlistId,
          filePath: '/c.mp3',
          fileName: 'c.mp3',
          addedAt: DateTime.fromMillisecondsSinceEpoch(_seedMs + 2),
        ),
      ]);
      seeded = await dao.findTracksForPlaylist(playlistId);
      expect(seeded, hasLength(3));
    });

    tearDown(() async {
      await db.close();
    });

    test('U1: removeTracks([]) 静默返回，不抛异常，不删任何行', () async {
      // spec §1.2 U1：程序化调用 removeTracks([]) → 静默返回。
      await expectLater(dao.removeTracks(const []), completes);
      expect(await dao.findTracksForPlaylist(playlistId), hasLength(3),
          reason: 'BUG-26-S1: 空列表不得删除任何曲目');
    });

    test('BUG-26-INV1: 空输入不执行任何 SQL（playlist_tracks 缺失也不触库）', () async {
      // 修复前空列表走到 `WHERE id IN ()` 生成非法 SQL → SQLite 语法错误；
      // 删表后更会 no such table。修复后守卫在取 db 句柄前返回，
      // 即使表不存在也必须无错完成 —— 证明"不执行任何 SQL"。
      await db.execute('DROP TABLE playlist_tracks');
      await expectLater(dao.removeTracks(const []), completes,
          reason: 'BUG-26-INV1: 空列表必须提前返回，不得生成 '
              '`WHERE id IN ()` 非法 SQL / 不得触库');
    });

    test('否定断言：非空列表 [全部] 的正常删除行为不变', () async {
      await dao.removeTracks(seeded.map((t) => t.id!).toList());
      expect(await dao.findTracksForPlaylist(playlistId), isEmpty,
          reason: 'BUG-26-S1: trackIds=[1,2,3] 仍须正确删除');
    });

    test('否定断言：非空列表 [单个] 的正常删除行为不变', () async {
      await dao.removeTracks([seeded[1].id!]);
      final remaining = await dao.findTracksForPlaylist(playlistId);
      expect(remaining.map((t) => t.fileName), ['a.mp3', 'c.mp3'],
          reason: 'BUG-26-S1: trackIds=[1] 行为不变');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // BUG-26-S2 / INV2: reorderTrack 索引越界静默返回
  // ═══════════════════════════════════════════════════════════════════════════

  group('BUG-26-S2: reorderTrack 索引越界静默返回', () {
    late Database db;
    late PlaylistDao dao;
    late int playlistId;

    setUp(() async {
      db = await openTestDatabase(TestSchema.playlist);
      dao = PlaylistDao();
      playlistId = await dao.insertPlaylist(Playlist(
        name: 'P',
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
      ));
      await dao.addTracks([
        for (final (i, name) in ['a.mp3', 'b.mp3', 'c.mp3'].indexed)
          PlaylistTrack(
            playlistId: playlistId,
            filePath: '/$name',
            fileName: name,
            addedAt: DateTime.fromMillisecondsSinceEpoch(_seedMs + i),
          ),
      ]);
    });

    tearDown(() async {
      await db.close();
    });

    Future<List<int>> addedAts() async {
      final rows = await db.query('playlist_tracks',
          columns: ['added_at'], orderBy: 'id ASC');
      return rows.map((r) => r['added_at'] as int).toList();
    }

    test('U2: oldIndex 越界（99）静默返回，不抛 RangeError', () async {
      await expectLater(dao.reorderTrack(playlistId, 99, 0), completes,
          reason: 'BUG-26-S2: 修复前 removeAt(99) 抛 RangeError');
    });

    test('oldIndex/newIndex 负数越界静默返回', () async {
      await expectLater(dao.reorderTrack(playlistId, -1, 0), completes);
      await expectLater(dao.reorderTrack(playlistId, 0, -1), completes);
      await expectLater(dao.reorderTrack(playlistId, -5, -3), completes);
    });

    test('oldIndex == tracks.length 边界静默返回（>= 拦截）', () async {
      // spec §3.1 边界裁决：oldIndex=tracks.length → 守卫 return。
      await expectLater(dao.reorderTrack(playlistId, 3, 0), completes);
    });

    test('newIndex == tracks.length 边界静默返回（>= 拦截）', () async {
      // spec §3.1 边界裁决：newIndex=tracks.length → insert 虽允许 length，
      // 但语义不符预期，交由守卫统一拦截。
      await expectLater(dao.reorderTrack(playlistId, 0, 3), completes);
    });

    test('BUG-26-INV2: 越界不得修改任何 playlist_tracks 行的 added_at', () async {
      final before = await addedAts();
      await dao.reorderTrack(playlistId, 99, 0);
      await dao.reorderTrack(playlistId, 0, 99);
      await dao.reorderTrack(playlistId, -1, 1);
      await dao.reorderTrack(playlistId, 3, 0);
      expect(await addedAts(), equals(before),
          reason: 'BUG-26-INV2: 越界重排不得改动任何行');
    });

    test('oldIndex == newIndex 静默返回且不改动', () async {
      final before = await addedAts();
      await expectLater(dao.reorderTrack(playlistId, 1, 1), completes);
      expect(await addedAts(), equals(before));
    });

    test('否定断言：合法索引重排行为不变（0 → 2）', () async {
      await dao.reorderTrack(playlistId, 0, 2);
      final order = (await dao.findTracksForPlaylist(playlistId))
          .map((t) => t.fileName)
          .toList();
      expect(order, ['b.mp3', 'c.mp3', 'a.mp3'],
          reason: 'BUG-26-S2: [a,b,c] old=0,new=2 → [b,c,a]');
    });

    test('否定断言：合法相邻交换行为不变（0 ↔ 1）', () async {
      await dao.reorderTrack(playlistId, 1, 0);
      final order = (await dao.findTracksForPlaylist(playlistId))
          .map((t) => t.fileName)
          .toList();
      expect(order, ['b.mp3', 'a.mp3', 'c.mp3']);
    });

    test('单曲目播放单（length<2 守卫）任意坏索引不抛', () async {
      final singleId = await dao.insertPlaylist(Playlist(
        name: 'Single',
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
      ));
      await dao.addTracks([
        PlaylistTrack(
          playlistId: singleId,
          filePath: '/only.mp3',
          fileName: 'only.mp3',
          addedAt: DateTime.fromMillisecondsSinceEpoch(_seedMs),
        ),
      ]);
      await expectLater(dao.reorderTrack(singleId, 5, 0), completes);
      await expectLater(dao.reorderTrack(singleId, -1, 9), completes);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // BUG-26-S3 / INV3: connection_dao.delete 收窄 catch 范围
  // ═══════════════════════════════════════════════════════════════════════════

  group('BUG-26-S3: connection_dao.delete 收窄 catch', () {
    late Database db;
    late ConnectionDao dao;

    tearDown(() async {
      await db.close();
    });

    test('play_progress 表不存在（connections-only schema）→ 忽略并继续删除', () async {
      // spec §1.2 U3 的反面场景 + S3 Given/When/Then：表不存在时
      // isNoSuchTableError()=true → 异常被忽略，connections 行照常删除。
      db = await openTestDatabase(TestSchema.connections);
      dao = ConnectionDao();
      final id1 = await dao.insert(testConfig(name: 'A'), passwordKey: 'k1');
      await dao.insert(testConfig(name: 'B'), passwordKey: 'k2');

      final wasActive = await dao.delete(id1);

      expect(wasActive, isFalse);
      expect(await dao.findById(id1), isNull,
          reason: 'BUG-26-S3: 表不存在不得阻断连接删除');
      expect(await dao.count(), 1);
    });

    test('BUG-26-INV3: 非"表不存在"的 DatabaseException 不被吞没，向上传播', () async {
      // 用同名 VIEW 冒充 play_progress：DELETE 命中视图 →
      // "cannot modify play_progress because it is a view"，
      // isNoSuchTableError()=false → 必须 rethrow。
      // 修复前 catch (_) 会吞掉它并继续删连接行 → 本用例 FAIL。
      db = await openTestDatabase(TestSchema.connections);
      dao = ConnectionDao();
      final id1 = await dao.insert(testConfig(name: 'A'), passwordKey: 'k1');
      await dao.insert(testConfig(name: 'B'), passwordKey: 'k2');
      await db.execute('CREATE VIEW play_progress AS SELECT 1 AS id');

      await expectLater(dao.delete(id1), throwsA(isA<DatabaseException>()),
          reason: 'BUG-26-INV3: 真实错误（非 no such table）不得被吞没');

      // 事务回滚：connections 行不得被删除。
      expect(await dao.findById(id1), isNotNull,
          reason: 'BUG-26-INV3: 级联清理失败时连接删除必须整体中止');
      expect(await dao.count(), 2);
    });

    test('否定断言：play_progress 表存在时的正常级联删除行为不变', () async {
      db = await openTestDatabase(TestSchema.full);
      dao = ConnectionDao();
      final id1 = await dao.insert(testConfig(name: 'A'), passwordKey: 'k1');
      final id2 = await dao.insert(testConfig(name: 'B'), passwordKey: 'k2');
      final progressDao = ProgressDao();
      await progressDao.upsert(
          connectionId: id1, filePath: '/a.mp3', positionMs: 60000);
      await progressDao.upsert(
          connectionId: id2, filePath: '/b.mp3', positionMs: 60000);

      await dao.delete(id1);

      expect(await progressDao.findByConnection(id1), isEmpty,
          reason: 'BUG-26-S3: 被删连接的进度须级联清除');
      expect(await progressDao.findByConnection(id2), hasLength(1),
          reason: 'BUG-26-S3: 其它连接的进度不受影响');
    });

    test('否定断言：LastConnectionException 保护逻辑不变', () async {
      db = await openTestDatabase(TestSchema.connections);
      dao = ConnectionDao();
      final onlyId =
          await dao.insert(testConfig(name: 'Only'), passwordKey: 'k1');

      await expectLater(
          dao.delete(onlyId), throwsA(isA<LastConnectionException>()));
      expect(await dao.count(), 1);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // BUG-26-S4 / INV4: DAO 构造函数支持 clock 注入
  // ═══════════════════════════════════════════════════════════════════════════

  group('BUG-26-S4: DAO clock 注入', () {
    late Database db;

    tearDown(() async {
      await db.close();
    });

    test('ProgressDao.upsert 使用注入 clock 的 last_played_at', () async {
      // spec §1.2 U4：受控时钟下验证 upsert，无需 rawInsert 绕过。
      db = await openTestDatabase(TestSchema.progress);
      await seedConnection(db); // FK ON：进度行必须引用已存在连接
      final dao = ProgressDao(clock: () => _fixedClock);

      await dao.upsert(connectionId: 1, filePath: '/a.mp3', positionMs: 60000);

      final saved = await dao.find(1, '/a.mp3');
      expect(saved, isNotNull);
      expect(saved!.lastPlayedAt.millisecondsSinceEpoch, _fixedMs,
          reason: 'BUG-26-S4: 时间戳必须来自注入 clock；'
              '若仍取 DateTime.now() 则与 2026-01-01 固定值不符');
    });

    test('PlaylistDao.updatePlaylist 使用注入 clock 的 updated_at', () async {
      db = await openTestDatabase(TestSchema.playlist);
      final dao = PlaylistDao(clock: () => _fixedClock);
      final id = await dao.insertPlaylist(Playlist(
        name: 'Before',
        createdAt: DateTime(2020, 1, 1),
        updatedAt: DateTime(2020, 1, 1),
      ));

      await dao.updatePlaylist(Playlist(
        id: id,
        name: 'After',
        createdAt: DateTime(2020, 1, 1),
        updatedAt: DateTime(2020, 1, 1),
      ));

      final updated = (await dao.findAllPlaylists()).single;
      expect(updated.updatedAt.millisecondsSinceEpoch, _fixedMs,
          reason: 'BUG-26-S4: updatePlaylist(:41) 须走注入 clock');
    });

    test('PlaylistDao.reorderTrack 使用注入 clock 的 base 时间', () async {
      db = await openTestDatabase(TestSchema.playlist);
      final dao = PlaylistDao(clock: () => _fixedClock);
      final playlistId = await dao.insertPlaylist(Playlist(
        name: 'P',
        createdAt: DateTime(2020, 1, 1),
        updatedAt: DateTime(2020, 1, 1),
      ));
      await dao.addTracks([
        for (final (i, name) in ['a.mp3', 'b.mp3'].indexed)
          PlaylistTrack(
            playlistId: playlistId,
            filePath: '/$name',
            fileName: name,
            addedAt: DateTime.fromMillisecondsSinceEpoch(_seedMs + i),
          ),
      ]);

      await dao.reorderTrack(playlistId, 0, 1);

      final rows = await db.query('playlist_tracks',
          columns: ['file_name', 'added_at'], orderBy: 'added_at ASC');
      // [a,b] old=0,new=1 → [b,a]；added_at = base + i（base 为注入值）。
      expect(rows.map((r) => r['file_name']), ['b.mp3', 'a.mp3']);
      expect(rows[0]['added_at'], _fixedMs,
          reason: 'BUG-26-S4: reorderTrack(:115) base 须来自注入 clock');
      expect(rows[1]['added_at'], _fixedMs + 1);
    });

    test('ConnectionDao.update 使用注入 clock 的 updated_at', () async {
      db = await openTestDatabase(TestSchema.progress);
      final dao = ConnectionDao(clock: () => _fixedClock);
      final id = await dao.insert(testConfig(name: 'A'), passwordKey: 'k1');

      await dao.update(testConfig(id: id, name: 'A2'), passwordKey: 'k1');

      final updated = await dao.findById(id);
      expect(updated!.updatedAt.millisecondsSinceEpoch, _fixedMs,
          reason: 'BUG-26-S4: update(:82) 须走注入 clock');
    });

    test('ConnectionDao.setActive 使用注入 clock 的 updated_at', () async {
      db = await openTestDatabase(TestSchema.progress);
      final dao = ConnectionDao(clock: () => _fixedClock);
      final id1 = await dao.insert(testConfig(name: 'A'), passwordKey: 'k1');
      final id2 = await dao.insert(testConfig(name: 'B'), passwordKey: 'k2');

      await dao.setActive(id2);

      expect(
          (await dao.findById(id2))!.updatedAt.millisecondsSinceEpoch, _fixedMs,
          reason: 'BUG-26-S4: setActive(:94) 须走注入 clock');
      expect((await dao.findById(id1))!.isActive, isFalse);
      expect((await dao.findById(id2))!.isActive, isTrue);
    });

    test('否定断言：默认不注入 clock 时生产行为不变（DateTime.now）', () async {
      db = await openTestDatabase(TestSchema.progress);
      await seedConnection(db);
      final dao = ProgressDao(); // 无注入 → 默认 DateTime.now

      final before = DateTime.now().millisecondsSinceEpoch;
      await dao.upsert(connectionId: 1, filePath: '/a.mp3', positionMs: 60000);
      final after = DateTime.now().millisecondsSinceEpoch;

      final saved = await dao.find(1, '/a.mp3');
      expect(saved!.lastPlayedAt.millisecondsSinceEpoch,
          inInclusiveRange(before, after),
          reason: 'BUG-26-S4: 默认 clock 必须保持生产行为');
    });

    test('否定断言：rawInsert 测试播种能力保持兼容', () async {
      // spec §3.1 S4 否定断言：注入机制与 rawInsert 并存不冲突。
      db = await openTestDatabase(TestSchema.progress);
      await seedConnection(db);
      final dao = ProgressDao(clock: () => _fixedClock);

      await dao.rawInsert(PlayProgress(
        connectionId: 1,
        filePath: '/explicit.mp3',
        positionMs: 30000,
        lastPlayedAt: DateTime(2021, 6, 15),
      ));

      final saved = await dao.find(1, '/explicit.mp3');
      expect(saved!.lastPlayedAt.millisecondsSinceEpoch,
          DateTime(2021, 6, 15).millisecondsSinceEpoch,
          reason: 'BUG-26-S4: rawInsert 显式时间戳不受 clock 注入影响');
    });
  });
}
