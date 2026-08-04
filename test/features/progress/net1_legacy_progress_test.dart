// test/features/progress/net1_legacy_progress_test.dart
// cr-20260804-1922 §5 O1: NET1 遗留 play_progress 绝对路径 — 读取时归一化
//
// NET1（431d444）之前保存的 play_progress.file_path 是服务端绝对路径
//（含连接根前缀）。NET1 之后恢复链路（progressForFileProvider 查询 /
// latestPlayedProgressProvider → applyLatestProgressToQueue 对齐
// queue.current.path）都使用相对连接根路径 → 旧记录查不中、对齐失败，
// 进度记忆整体失效。
//
// 本文件验证（ProgressDao / ProgressService 层，连接上下文来自
// play_progress.connection_id → connections 表）：
//   S1 find 按相对根路径能查中 legacy 记录，且返回值的 filePath 已归一
//   S2 findLatest 返回归一 filePath（启动恢复对齐链路）
//   S3 delete 按相对根路径能清掉 legacy 记录（"从头播放"/清除进度）
//   S4 自然写回：下一次 upsert 写归一值，且不产生重复记录
//   否定断言：连接根为 `/` 时旧路径（== 相对根路径）不被改动；
//             不匹配记录不受影响

import 'package:flutter_test/flutter_test.dart';
import 'package:nas_audio_player/core/database/dao/progress_dao.dart';
import 'package:nas_audio_player/features/player/player_provider.dart'
    show applyLatestProgressToQueue;
import 'package:nas_audio_player/features/progress/domain/progress_service.dart';
import 'package:nas_audio_player/shared/models/play_queue.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../helpers/test_database.dart';
import '../../helpers/test_factories.dart';

const _url = 'http://nas.local:5005';
const _basePath = '/dav';
const _legacyPath = '/dav/music/a.mp3'; // NET1 前存储形态（服务端绝对）
const _canonicalPath = '/music/a.mp3'; // NET1 后规范形态（相对连接根）

Future<Database> openWithSubPathConnection() async {
  final db = await openTestDatabase(TestSchema.progress);
  await db.insert('connections', {
    'id': 1,
    'name': 'SubPath NAS',
    'url': _url,
    'username': 'admin',
    'password': 'pw-ref-key',
    'base_path': _basePath,
    'is_active': 1,
    'created_at': 0,
    'updated_at': 0,
  });
  return db;
}

Future<void> insertLegacyProgress(Database db,
    {int positionMs = 30000, int lastPlayedAt = 1000}) async {
  await db.insert('play_progress', {
    'connection_id': 1,
    'file_path': _legacyPath,
    'position_ms': positionMs,
    'duration_ms': 120000,
    'last_played_at': lastPlayedAt,
  });
}

void main() {
  late Database db;
  late ProgressDao dao;
  late ProgressService service;

  setUpAll(initSqfliteFfi);

  setUp(() async {
    db = await openWithSubPathConnection();
    dao = ProgressDao();
    service = ProgressService(dao: dao);
  });

  tearDown(() async {
    await db.close();
  });

  group('O1-S1: find 按相对根路径查中 legacy 记录并归一返回', () {
    test('getProgress(canonical) 命中 legacy 行，filePath 归一返回', () async {
      await insertLegacyProgress(db);

      final found = await service.getProgress(1, _canonicalPath);

      expect(found, isNotNull, reason: 'S1: 旧绝对路径记录必须能被相对根路径查中');
      expect(found!.filePath, equals(_canonicalPath),
          reason: 'S1: 返回值的 filePath 必须已归一');
      expect(found.positionMs, equals(30000));
      expect(found.connectionId, equals(1));
    });

    test('getProgress(legacy 原值) 仍命中（双向兼容）且归一返回', () async {
      await insertLegacyProgress(db);

      final found = await service.getProgress(1, _legacyPath);

      expect(found, isNotNull);
      expect(found!.filePath, equals(_canonicalPath));
    });
  });

  group('O1-S2: 启动恢复对齐链路（findLatest → applyLatestProgressToQueue）', () {
    test('legacy 进度 + 归一队列经 connectionRoot 对齐 → startPosition 生效', () async {
      await insertLegacyProgress(db);

      // findLatest 按存储形态返回最新记录（legacy 绝对路径）
      final latest = await dao.findLatest();
      expect(latest, isNotNull);
      expect(latest!.filePath, equals(_legacyPath),
          reason: '前置: findLatest 返回存储的 legacy 形态');

      // 启动恢复：恢复后的队列已是相对连接根形态（见 browser 归一化），
      // applyLatestProgressToQueue 传入连接根后两侧归一对齐。
      final queue = PlayQueue(
        files: [testAudio('a.mp3', _canonicalPath)],
        currentIndex: 0,
      );
      final applied = applyLatestProgressToQueue(
        queue: queue,
        activeConnectionId: 1,
        latestProgress: latest,
        connectionRoot: '/dav',
      );
      expect(applied!.startPositionMs, equals(30000),
          reason: 'S2: 对齐成功 → startPosition 生效（未修复时 legacy 与 '
              '归一路径不等 → 返回原 queue，startPosition 为 null）');
    });

    test('无 connectionRoot（向后兼容）→ 逐字比较，legacy 与归一不对齐', () async {
      await insertLegacyProgress(db);

      final latest = await dao.findLatest();
      expect(latest, isNotNull);

      final queue = PlayQueue(
        files: [testAudio('a.mp3', _canonicalPath)],
        currentIndex: 0,
      );
      final applied = applyLatestProgressToQueue(
        queue: queue,
        activeConnectionId: 1,
        latestProgress: latest,
      );
      // 否定断言: 不传 root 时保持旧语义（逐字比较），不得误对齐
      expect(applied!.startPositionMs, isNull,
          reason: '否定断言: 缺省 root 时逐字比较，不误对齐');
    });

    test('同形态（均归一）经 connectionRoot 对齐不受影响', () async {
      await insertLegacyProgress(db);
      // 用 canonical 形态再写一条更新的记录
      await dao.upsert(
        connectionId: 1,
        filePath: _canonicalPath,
        positionMs: 45000,
        durationMs: 120000,
      );

      final latest = await dao.findLatest();
      expect(latest, isNotNull);
      expect(latest!.filePath, equals(_canonicalPath));

      final queue = PlayQueue(
        files: [testAudio('a.mp3', _canonicalPath)],
        currentIndex: 0,
      );
      final applied = applyLatestProgressToQueue(
        queue: queue,
        activeConnectionId: 1,
        latestProgress: latest,
        connectionRoot: '/dav',
      );
      expect(applied!.startPositionMs, equals(45000), reason: 'S2: 均归一时对齐仍成立');
    });
  });

  group('O1-S3: delete 按相对根路径清掉 legacy 记录', () {
    test('clearProgress(canonical) 删除后 getProgress 为 null', () async {
      await insertLegacyProgress(db);

      await service.clearProgress(1, _canonicalPath);

      expect(await service.getProgress(1, _canonicalPath), isNull,
          reason: 'S3: legacy 行必须被清除（否则恢复对话框反复出现）');
      expect(await dao.findLatest(), isNull);
    });
  });

  group('O1-S4: 自然写回 — 下次 upsert 写归一值（确认，无需额外代码）', () {
    test('upsert(canonical) 后恢复链路读到归一记录与新位置', () async {
      await insertLegacyProgress(db, lastPlayedAt: 1000);

      // 模拟 NET1 后播放：orchestrator 传入的已是归一路径 → upsert 天然写归一值
      final saved = await service.saveProgress(
        connectionId: 1,
        filePath: _canonicalPath,
        positionMs: 60000,
        durationMs: 120000,
      );
      expect(saved, isTrue);

      // 下次启动恢复：findLatest 命中最新（canonical）记录，路径归一
      final latest = await dao.findLatest();
      expect(latest, isNotNull);
      expect(latest!.filePath, equals(_canonicalPath),
          reason: 'S4: 写回后 findLatest 必须读到归一路径');
      expect(latest.positionMs, equals(60000), reason: 'S4: 最新位置生效');

      // 精确查询同样命中归一记录
      final found = await service.getProgress(1, _canonicalPath);
      expect(found, isNotNull);
      expect(found!.filePath, equals(_canonicalPath));
      expect(found.positionMs, equals(60000));
    });
  });

  group('O1 否定断言', () {
    test('连接根为 `/` → 旧路径（即相对根路径）不被改动', () async {
      await db.update('connections', {'base_path': '/'},
          where: 'id = ?', whereArgs: [1]);
      await db.insert('play_progress', {
        'connection_id': 1,
        'file_path': '/music/b.mp3',
        'position_ms': 15000,
        'duration_ms': 90000,
        'last_played_at': 2000,
      });

      final found = await service.getProgress(1, '/music/b.mp3');

      expect(found, isNotNull);
      expect(found!.filePath, equals('/music/b.mp3'),
          reason: '否定断言: 根挂载时路径不被改动');
    });

    test('其他连接的记录不受影响（跨连接隔离保持）', () async {
      await db.insert('connections', {
        'id': 2,
        'name': 'Other NAS',
        'url': _url,
        'username': 'admin',
        'password': 'pw-ref-key',
        'base_path': '/other',
        'is_active': 0,
        'created_at': 0,
        'updated_at': 0,
      });
      await db.insert('play_progress', {
        'connection_id': 2,
        'file_path': '/other/x.mp3',
        'position_ms': 9000,
        'duration_ms': 60000,
        'last_played_at': 3000,
      });
      await insertLegacyProgress(db);

      final found = await service.getProgress(1, _canonicalPath);
      expect(found, isNotNull);
      expect(found!.filePath, equals(_canonicalPath));

      // 连接 2 的 legacy 行（相对其自身根 /other 存储）不被连接 1 的根误剥
      final other = await service.getProgress(2, '/x.mp3');
      expect(other, isNotNull);
      expect(other!.filePath, equals('/x.mp3'), reason: '各连接按自身根归一');
    });

    // 注：连接行缺失的孤儿记录在生产/测试库中均不可达——
    // play_progress 外键 ON DELETE CASCADE（BUG-16-S2 起 FK 恒开），
    // 删连接即级联删进度。DAO 的 root==null 分支仍作防御保留。
  });

  group('O1 PlayProgress 模型完整性', () {
    test('归一后的记录可构造 PlayProgress 且 copyWith(filePath) 保持语义', () {
      final p = testProgress(filePath: _canonicalPath);
      expect(p.copyWith().filePath, equals(_canonicalPath));
    });
  });
}
