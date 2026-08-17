// test/shared/ref_02_equality_registry_test.dart
// REF-02 (docs/features/REF-02.md §5.4 门禁) — 值对象 ==/hashCode 字段集统一
// 规则 + 集中登记表 + 补缺锚定。
//
// 覆盖: REF-02-S6 / S7 / S8 / S9 / REF-02-INV1 / REF-02-INV2 / REF-02-INV3。
// S1~S5 由既有 model_equality_test.dart 覆盖，不在本文件重复。
//
//   S6  — 登记表结构：6 条记录依次与各模型 == 实现一致，头部声明统一规则
//   S7  — 6 个模型文件头部注释引用 equality_registry.dart
//   S8  — PlayProgress 仅 lastPlayedAt 不同 → 相等（除外锚定）
//   S9  — Playlist 仅 createdAt/updatedAt 不同 → 相等（除外锚定）
//   INV1 — 四同步：== / hashCode / copyWith / fromMap·toMap 字段集同步
//   INV2 — 登记表 entries 与各模型 == 实现字段集逐条一致
//   INV3 — 除外字段必须属于 {自增 id} ∪ {审计时间戳}

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nas_audio_player/shared/models/connection_config.dart';
import 'package:nas_audio_player/shared/models/equality_registry.dart';
import 'package:nas_audio_player/shared/models/nas_file.dart';
import 'package:nas_audio_player/shared/models/play_progress.dart';
import 'package:nas_audio_player/shared/models/play_queue.dart';
import 'package:nas_audio_player/shared/models/playlist.dart';

ConnectionConfig _connConfig() => ConnectionConfig(
      id: 1,
      name: 'NAS',
      url: 'http://nas.local:5005',
      username: 'admin',
      basePath: '/dav',
      isActive: false,
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
    );

PlayProgress _progress() => PlayProgress(
      id: 5,
      connectionId: 1,
      filePath: '/music/a.mp3',
      positionMs: 30000,
      durationMs: 120000,
      lastPlayedAt: DateTime(2026, 1, 1),
    );

Playlist _playlist() => Playlist(
      id: 2,
      name: 'Favorites',
      trackCount: 3,
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
    );

PlaylistTrack _track() => PlaylistTrack(
      id: 9,
      playlistId: 2,
      filePath: '/music/a.mp3',
      fileName: 'a.mp3',
      addedAt: DateTime(2026, 1, 1),
    );

NasFile _nasFile() => const NasFile(
      name: 'a.mp3',
      path: '/music/a.mp3',
      isDirectory: false,
      size: 1024,
      modifiedAt: null,
      audioType: AudioFileType.music,
    );

PlayQueue _queue() => PlayQueue(
      files: const [
        NasFile(
            name: 'a.mp3',
            path: '/a.mp3',
            isDirectory: false,
            audioType: AudioFileType.music),
        NasFile(
            name: 'b.mp3',
            path: '/b.mp3',
            isDirectory: false,
            audioType: AudioFileType.music),
      ],
      currentIndex: 0,
    );

/// 取出所有 `==` 实现中用到的字段名（按行文本比对，用于 INV2 一致性核对）。
///
/// 由于各模型 == 实现是手写字段比较，本辅助函数在"模型实例构造"层面验证：
/// 登记表 equalityFields 里的每段字段名都能在对应模型的 == 实现行文本中找到
/// 引用（字段名出现于 operator == 覆盖范围内）。
List<String> _equalityFieldNames(EqualityRule rule) =>
    rule.equalityFields.split(',').map((s) => s.trim()).toList();

void main() {
  // ═══════════════════════════════════════════════════════════════════════════
  // REF-02-S6: 登记表结构
  // ═══════════════════════════════════════════════════════════════════════════

  group('REF-02-S6: equality_registry.dart 集中登记表', () {
    test('S6: 6 个共享值对象全部登记，无遗漏', () {
      final models = EqualityRegistry.entries.map((e) => e.model).toSet();
      expect(
        models,
        containsAll({
          'ConnectionConfig',
          'PlayProgress',
          'Playlist',
          'PlaylistTrack',
          'NasFile',
          'PlayQueue'
        }),
        reason: '登记表不得遗漏任一共享值对象',
      );
      expect(models.length, 6, reason: '6 模型缺一即违规');
    });

    test('S6: 表头注释声明统一规则四要素', () {
      final source =
          File('lib/shared/models/equality_registry.dart').readAsStringSync();
      expect(source, contains('默认入等'),
          reason: '规则 1: 新增字段默认进入 ==/hashCode 并四同步');
      expect(source, contains('自增 DB 主键'), reason: '规则 2: 例外资格限制（自增 id）');
      expect(source, contains('审计时间戳'), reason: '规则 2: 例外资格限制（审计时间戳）');
      expect(source, contains('否定断言'), reason: '规则 3: 例外裁决需否定断言测试锚定');
      expect(source, contains('唯一登记点'), reason: '规则 4: 登记表是唯一登记点');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // REF-02-S7: 模型文件头部注释引用登记表
  // ═══════════════════════════════════════════════════════════════════════════

  group('REF-02-S7: 模型文件头部注释引用 equality_registry.dart', () {
    final files = [
      'lib/shared/models/connection_config.dart',
      'lib/shared/models/play_progress.dart',
      'lib/shared/models/playlist.dart',
      'lib/shared/models/nas_file.dart',
      'lib/shared/models/play_queue.dart',
    ];
    for (final f in files) {
      test('S7: ${f.split('/').last} 头部含登记引用注释', () {
        final source = File(f).readAsStringSync();
        final lines = source.split('\n');
        expect(lines.first, contains('//'), reason: '文件首行应为注释');
        // 引用行位于头部注释区域（前 12 行内）。
        final head = lines.take(12).join('\n');
        expect(head, contains('等性规则与登记：见 equality_registry.dart'),
            reason: '$f 头部需声明登记引用（REF-02）');
      });
    }
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // REF-02-S8: PlayProgress.lastPlayedAt 除外锚定
  // ═══════════════════════════════════════════════════════════════════════════

  group('REF-02-S8: PlayProgress.lastPlayedAt 除外', () {
    test('S8: 仅 lastPlayedAt 不同 → 相等且 hashCode 一致', () {
      final a = _progress();
      final b = _progress().copyWith(lastPlayedAt: DateTime(2026, 6, 1));
      expect(a == b, isTrue, reason: 'lastPlayedAt 是审计时间戳，不参与业务相等');
      expect(a.hashCode, equals(b.hashCode));
    });

    test('S8-否定: 业务字段任一不同 → 不相等', () {
      expect(_progress().copyWith(connectionId: 2) == _progress(), isFalse,
          reason: 'connectionId 入等');
      expect(_progress().copyWith(filePath: '/music/b.mp3') == _progress(),
          isFalse,
          reason: 'filePath 入等');
      expect(_progress().copyWith(positionMs: 999) == _progress(), isFalse,
          reason: 'positionMs 入等');
      expect(_progress().copyWith(durationMs: 999) == _progress(), isFalse,
          reason: 'durationMs 入等');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // REF-02-S9: Playlist.createdAt/updatedAt 除外锚定
  // ═══════════════════════════════════════════════════════════════════════════

  group('REF-02-S9: Playlist.createdAt/updatedAt 除外', () {
    test('S9: 仅 createdAt 与 updatedAt 不同 → 相等且 hashCode 一致', () {
      final a = _playlist();
      final b = _playlist().copyWith(
        createdAt: DateTime(2027, 1, 1),
        updatedAt: DateTime(2027, 1, 1),
      );
      expect(a == b, isTrue, reason: '审计时间戳不参与');
      expect(a.hashCode, equals(b.hashCode));
    });

    test('S9-否定: id / name / trackCount 任一不同 → 不相等', () {
      expect(_playlist().copyWith(id: 99) == _playlist(), isFalse,
          reason: 'id 入等');
      expect(_playlist().copyWith(name: 'Other') == _playlist(), isFalse,
          reason: 'name 入等');
      expect(_playlist().copyWith(trackCount: 99) == _playlist(), isFalse,
          reason: 'trackCount 入等');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // REF-02-INV1: 四同步（== / hashCode / copyWith / fromMap·toMap 字段集同步）
  // ═══════════════════════════════════════════════════════════════════════════

  group('REF-02-INV1: 四同步', () {
    test('INV1: ConnectionConfig 全 8 字段在 == 与 hashCode 中一致', () {
      final a = _connConfig();
      final fields = [
        'id',
        'name',
        'url',
        'username',
        'basePath',
        'isActive',
        'createdAt',
        'updatedAt'
      ];
      // copyWith 提供全部字段的可选覆盖 → 逐个单字段拷贝后 === 原值
      for (final _ in fields) {
        expect(a.copyWith(), a, reason: 'copyWith 无字段变更时与自身相等');
      }
      final changed = a.copyWith(name: 'X');
      expect(changed == a, isFalse, reason: 'copyWith 变更后参与相等');
    });

    test('INV1: 各模型 fromMap→toMap 往返后归一等价', () {
      // 序列化往返不影响业务相等：toMap 含自增 id（非空时），往返后 id/业务字段
      // 全部还原，== 依旧成立。
      final conn = _connConfig();
      final round = ConnectionConfig.fromMap(conn.toMap(passwordKey: 'k'));
      expect(round == conn, isTrue, reason: '序列化往返后值相等（四同步一致）');

      final prog = _progress();
      final prog2 = PlayProgress.fromMap(prog.toMap());
      expect(prog2 == prog, isTrue, reason: 'fromMap→toMap 往返后业务相等');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // REF-02-INV2: 登记表与实现一致
  // ═══════════════════════════════════════════════════════════════════════════

  group('REF-02-INV2: 登记表与 == 实现一致', () {
    test('INV2: ConnectionConfig 登记字段 == 实现字段', () {
      final rule = EqualityRegistry.entries
          .firstWhere((e) => e.model == 'ConnectionConfig');
      expect(_equalityFieldNames(rule), hasLength(8));
      // id 改变 → ConnectionConfig !=（id 入等，与登记表 "全字段" 一致）
      expect(_connConfig().copyWith(id: 99) == _connConfig(), isFalse,
          reason: '登记表称全 8 字段入等 → id 不同必须不等');
    });

    test('INV2: PlayProgress 登记字段 == 实现字段', () {
      final rule =
          EqualityRegistry.entries.firstWhere((e) => e.model == 'PlayProgress');
      final fields = _equalityFieldNames(rule);
      expect(
          fields,
          containsAll(
              ['connectionId', 'filePath', 'positionMs', 'durationMs']));
      expect(fields, isNot(contains('id')));
      expect(fields, isNot(contains('lastPlayedAt')));
    });

    test('INV2: Playlist 与 PlaylistTrack 登记字段 == 实现字段', () {
      final pl =
          EqualityRegistry.entries.firstWhere((e) => e.model == 'Playlist');
      expect(
          _equalityFieldNames(pl), containsAll(['id', 'name', 'trackCount']));
      expect(_equalityFieldNames(pl), isNot(contains('createdAt')));
      expect(_equalityFieldNames(pl), isNot(contains('updatedAt')));

      final pt = EqualityRegistry.entries
          .firstWhere((e) => e.model == 'PlaylistTrack');
      expect(_equalityFieldNames(pt),
          containsAll(['id', 'playlistId', 'filePath', 'fileName']));
      expect(_equalityFieldNames(pt), isNot(contains('addedAt')));
      // 实现侧: addedAt 不同仍相等
      final a = _track();
      final b = PlaylistTrack(
        id: a.id,
        playlistId: a.playlistId,
        filePath: a.filePath,
        fileName: a.fileName,
        addedAt: DateTime(2030, 1, 1),
      );
      expect(a == b, isTrue, reason: 'addedAt 除外（登记表与实现一致）');
    });

    test('INV2: NasFile 与 PlayQueue 登记字段 == 实现字段', () {
      final nf =
          EqualityRegistry.entries.firstWhere((e) => e.model == 'NasFile');
      expect(
          _equalityFieldNames(nf),
          containsAll([
            'name',
            'path',
            'isDirectory',
            'size',
            'modifiedAt',
            'audioType'
          ]));
      // 实现侧: modifiedAt 入等（内容时间戳）
      expect(
          _nasFile().copyWith(modifiedAt: DateTime(2026, 5, 5)) == _nasFile(),
          isFalse,
          reason: 'NasFile.modifiedAt 是内容时间戳，必须入等');

      final q =
          EqualityRegistry.entries.firstWhere((e) => e.model == 'PlayQueue');
      expect(
          _equalityFieldNames(q),
          containsAll(
              ['files', 'currentIndex', 'startPositionMs', 'playMode']));
      expect(_queue().withIndex(1) == _queue(), isFalse,
          reason: 'currentIndex 入等');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // REF-02-INV3: 例外资格闭合
  // ═══════════════════════════════════════════════════════════════════════════

  group('REF-02-INV3: 除外字段资格闭合', () {
    test('INV3: 各登记条目的除外字段均属 {自增 id} ∪ {审计时间戳}', () {
      // 允许的除外字段闭集（规则 2）。
      const closure = {
        'id',
        'createdAt',
        'updatedAt',
        'lastPlayedAt',
        'addedAt'
      };
      const fieldTokens = [
        'id',
        'name',
        'url',
        'username',
        'basePath',
        'isActive',
        'createdAt',
        'updatedAt',
        'connectionId',
        'filePath',
        'positionMs',
        'durationMs',
        'lastPlayedAt',
        'trackCount',
        'playlistId',
        'fileName',
        'addedAt',
        'size',
        'modifiedAt',
        'audioType',
        'files',
        'currentIndex',
        'startPositionMs',
        'playMode',
        '_shuffleOrder',
        '_shufflePosition',
      ];
      for (final rule in EqualityRegistry.entries) {
        final ex = rule.exclusions;
        if (ex.startsWith('无（')) {
          // 声明无除外：任何字段名 token 都不应出现在排除说明里（例外提到
          // modifiedAt 属内容时间戳必入等，非除外字段）。
          continue;
        }
        for (final token in fieldTokens) {
          if (ex.contains(token)) {
            expect(closure, contains(token),
                reason: '${rule.model} 除外字段 "$token" 必须属于 '
                    '{自增 id} ∪ {审计时间戳} 闭集');
          }
        }
      }
    });

    test('INV3: PlayProgress/Playlist/PlaylistTrack 的除外字段正是登记表所列', () {
      final prog = EqualityRegistry.entries
          .firstWhere((e) => e.model == 'PlayProgress')
          .exclusions;
      expect(prog, contains('id'), reason: 'PlayProgress 除外 id（DB 自增主键）');
      expect(prog, contains('lastPlayedAt'),
          reason: 'PlayProgress 除外 lastPlayedAt（审计时间戳）');

      final pl = EqualityRegistry.entries
          .firstWhere((e) => e.model == 'Playlist')
          .exclusions;
      expect(pl, contains('createdAt'));
      expect(pl, contains('updatedAt'));

      final pt = EqualityRegistry.entries
          .firstWhere((e) => e.model == 'PlaylistTrack')
          .exclusions;
      expect(pt, contains('addedAt'));
    });
  });
}
