// test/shared/model_equality_test.dart
// 共享模型值相等性测试（REF-07 ConnectionConfig ==/hashCode；
// TEST-10 各模型 ==/hashCode 缺口也落此文件）。

import 'package:flutter_test/flutter_test.dart';
import 'package:nas_audio_player/shared/models/connection_config.dart';
import 'package:nas_audio_player/shared/models/nas_file.dart';
import 'package:nas_audio_player/shared/models/play_queue.dart';
import 'package:nas_audio_player/shared/models/playlist.dart';

import '../helpers/test_factories.dart';

ConnectionConfig _base({
  int? id = 1,
  String name = 'NAS',
  String url = 'http://nas.local:5005',
  String username = 'admin',
  String basePath = '/dav',
  bool isActive = false,
  DateTime? createdAt,
  DateTime? updatedAt,
}) {
  return ConnectionConfig(
    id: id,
    name: name,
    url: url,
    username: username,
    basePath: basePath,
    isActive: isActive,
    createdAt: createdAt ?? DateTime(2026, 1, 1),
    updatedAt: updatedAt ?? DateTime(2026, 1, 1),
  );
}

void main() {
  group('REF-07: ConnectionConfig ==/hashCode', () {
    test('REF-07-S1: 所有字段相同 → 相等且 hashCode 一致', () {
      final a = _base();
      final b = _base();
      expect(a == b, isTrue);
      expect(a.hashCode, equals(b.hashCode));
      expect(identical(a, b), isFalse, reason: '非同一实例但值相等');
    });

    test('REF-07-S1: 与自身比较相等（identical 短路）', () {
      final a = _base();
      expect(a == a, isTrue);
    });

    test('REF-07-S1: 与非 ConnectionConfig 比较不等', () {
      final a = _base();
      expect(a == 'string', isFalse);
    });

    test('REF-07-S2: id 不同 → 不等', () {
      expect(_base(id: 1) == _base(id: 2), isFalse);
    });

    test('REF-07-S2: id null 与 非null 不等', () {
      expect(_base(id: null) == _base(id: 1), isFalse);
      expect(_base(id: null) == _base(id: null), isTrue);
    });

    test('REF-07-S2: name 不同 → 不等', () {
      expect(_base(name: 'A') == _base(name: 'B'), isFalse);
    });

    test('REF-07-S2: url 不同 → 不等', () {
      expect(_base(url: 'http://a.local') == _base(url: 'http://b.local'),
          isFalse);
    });

    test('REF-07-S2: username 不同 → 不等', () {
      expect(_base(username: 'u1') == _base(username: 'u2'), isFalse);
    });

    test('REF-07-S2: basePath 不同 → 不等', () {
      expect(_base(basePath: '/dav') == _base(basePath: '/'), isFalse);
    });

    test('REF-07-S2: isActive 不同 → 不等', () {
      expect(_base(isActive: false) == _base(isActive: true), isFalse);
    });

    test('REF-07-S2: createdAt 不同 → 不等', () {
      expect(
          _base(createdAt: DateTime(2026, 1, 1)) ==
              _base(createdAt: DateTime(2026, 1, 2)),
          isFalse);
    });

    test('REF-07-S2: updatedAt 不同 → 不等', () {
      expect(
          _base(updatedAt: DateTime(2026, 1, 1)) ==
              _base(updatedAt: DateTime(2026, 1, 2)),
          isFalse);
    });

    test('REF-07-INV2: 相等对象 hashCode 一致，不等对象 hash 一致性自洽', () {
      final a = _base();
      final b = _base();
      final c = _base(name: 'Other');
      expect(a.hashCode, equals(b.hashCode));
      expect(a == b, isTrue);
      expect(a == c, isFalse);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // TEST-10-S2: NasFile == / hashCode 正负测试
  // 字段: name, path, isDirectory, size, modifiedAt, audioType
  // （spec §2.2 + BUG-30 modifiedAt 字段，== :203-210/hashCode :213）
  // ═══════════════════════════════════════════════════════════════════════
  group('TEST-10-S2: NasFile ==/hashCode', () {
    NasFile base() => testAudio('song.mp3', '/music/song.mp3',
        size: 1024, type: AudioFileType.music);

    test('TEST-10-S2: 所有字段相同 → 相等且 hashCode 一致', () {
      final a = base();
      final b = base();
      expect(a == b, isTrue);
      expect(a.hashCode, equals(b.hashCode));
      expect(identical(a, b), isFalse, reason: '非同一实例但值相等');
    });

    test('TEST-10-S2: name 不同 → 不等', () {
      expect(
          base() ==
              testAudio('other.mp3', '/music/song.mp3',
                  size: 1024, type: AudioFileType.music),
          isFalse);
    });

    test('TEST-10-S2: path 不同 → 不等', () {
      expect(
          base() ==
              testAudio('song.mp3', '/music/other.mp3',
                  size: 1024, type: AudioFileType.music),
          isFalse);
    });

    test('TEST-10-S2: isDirectory 不同 → 不等', () {
      // 两侧 audioType 相同（type: music），仅 isDirectory 单独差异
      expect(
          base() ==
              const NasFile(
                name: 'song.mp3',
                path: '/music/song.mp3',
                isDirectory: true,
                audioType: AudioFileType.music,
              ),
          isFalse);
    });

    test('TEST-10-S2: size 不同 → 不等', () {
      expect(
          base() ==
              testAudio('song.mp3', '/music/song.mp3',
                  size: 2048, type: AudioFileType.music),
          isFalse);
    });

    test('TEST-10-S2: audioType 不同 → 不等', () {
      expect(
          base() ==
              testAudio('song.mp3', '/music/song.mp3',
                  size: 1024, type: AudioFileType.audiobook),
          isFalse);
    });

    test('TEST-10-S2: modifiedAt 不同 → 不等', () {
      final other = testAudio('song.mp3', '/music/song.mp3',
          size: 1024,
          type: AudioFileType.music,
          modifiedAt: DateTime(2026, 1, 2));
      expect(base() == other, isFalse,
          reason: 'BUG-30 加入 modifiedAt 字段，负面测试必须锚定（TEST-10-INV1）');
      expect(base().hashCode, isNot(equals(other.hashCode)));
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // TEST-10-S3: PlayProgress == / hashCode 正负测试
  // == 字段: connectionId, filePath, positionMs, durationMs；
  // id 是 DB 自增主键，不参与业务相等性（spec §2.2 + §3.2 否定断言）
  // ═══════════════════════════════════════════════════════════════════════
  group('TEST-10-S3: PlayProgress ==/hashCode', () {
    test('TEST-10-S3: 所有业务字段相同 → 相等且 hashCode 一致', () {
      final a = testProgress();
      final b = testProgress();
      expect(a == b, isTrue);
      expect(a.hashCode, equals(b.hashCode));
      expect(identical(a, b), isFalse, reason: '非同一实例但值相等');
    });

    test('TEST-10-S3: connectionId 不同 → 不等', () {
      expect(testProgress(connectionId: 1) == testProgress(connectionId: 2),
          isFalse);
    });

    test('TEST-10-S3: filePath 不同 → 不等', () {
      expect(
          testProgress(filePath: '/music/a.mp3') ==
              testProgress(filePath: '/music/b.mp3'),
          isFalse);
    });

    test('TEST-10-S3: positionMs 不同 → 不等', () {
      expect(testProgress(positionMs: 30000) == testProgress(positionMs: 999),
          isFalse);
    });

    test('TEST-10-S3: durationMs 不同 → 不等', () {
      expect(
          testProgress(durationMs: 120000) == testProgress(durationMs: 121000),
          isFalse);
    });

    test('TEST-10-S3 否定断言: id 不参与比较——id 不同仍相等', () {
      expect(testProgress(id: 1) == testProgress(id: 2), isTrue,
          reason: 'id 是 DB 自增主键，不参与业务相等性');
      expect(
          testProgress(id: 1).hashCode, equals(testProgress(id: 2).hashCode));
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // TEST-10-S4: Playlist == / hashCode 正负测试
  // == 字段: id, name, trackCount（spec §2.2）
  // ═══════════════════════════════════════════════════════════════════════
  group('TEST-10-S4: Playlist ==/hashCode', () {
    Playlist base({int? id = 1, String name = 'My List', int trackCount = 3}) {
      return Playlist(
        id: id,
        name: name,
        trackCount: trackCount,
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
      );
    }

    test('TEST-10-S4: 所有字段相同 → 相等且 hashCode 一致', () {
      final a = base();
      final b = base();
      expect(a == b, isTrue);
      expect(a.hashCode, equals(b.hashCode));
      expect(identical(a, b), isFalse, reason: '非同一实例但值相等');
    });

    test('TEST-10-S4: id 不同 → 不等', () {
      expect(base(id: 1) == base(id: 2), isFalse);
    });

    test('TEST-10-S4: name 不同 → 不等', () {
      expect(base(name: 'A') == base(name: 'B'), isFalse);
    });

    test('TEST-10-S4: trackCount 不同 → 不等', () {
      expect(base(trackCount: 3) == base(trackCount: 4), isFalse);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // TEST-10-S5: PlaylistTrack == / hashCode 正负测试
  // == 字段: id, playlistId, filePath, fileName；addedAt 不参与（spec §2.2）
  // ═══════════════════════════════════════════════════════════════════════
  group('TEST-10-S5: PlaylistTrack ==/hashCode', () {
    PlaylistTrack base({
      int? id = 1,
      int playlistId = 1,
      String filePath = '/music/song.mp3',
      String fileName = 'song.mp3',
      DateTime? addedAt,
    }) {
      return PlaylistTrack(
        id: id,
        playlistId: playlistId,
        filePath: filePath,
        fileName: fileName,
        addedAt: addedAt ?? DateTime(2026, 1, 1),
      );
    }

    test('TEST-10-S5: 所有字段相同 → 相等且 hashCode 一致', () {
      final a = base();
      final b = base();
      expect(a == b, isTrue);
      expect(a.hashCode, equals(b.hashCode));
      expect(identical(a, b), isFalse, reason: '非同一实例但值相等');
    });

    test('TEST-10-S5: id 不同 → 不等', () {
      expect(base(id: 1) == base(id: 2), isFalse);
    });

    test('TEST-10-S5: playlistId 不同 → 不等', () {
      expect(base(playlistId: 1) == base(playlistId: 2), isFalse);
    });

    test('TEST-10-S5: filePath 不同 → 不等', () {
      expect(base(filePath: '/music/a.mp3') == base(filePath: '/music/b.mp3'),
          isFalse);
    });

    test('TEST-10-S5: fileName 不同 → 不等', () {
      expect(base(fileName: 'a.mp3') == base(fileName: 'b.mp3'), isFalse);
    });

    test('TEST-10-S5 否定断言: addedAt 不参与比较——addedAt 不同仍相等', () {
      expect(
          base(addedAt: DateTime(2026, 1, 1)) ==
              base(addedAt: DateTime(2026, 2, 2)),
          isTrue,
          reason: 'addedAt 不参与相等性（与现有 == 实现一致）');
      expect(base(addedAt: DateTime(2026, 1, 1)).hashCode,
          equals(base(addedAt: DateTime(2026, 2, 2)).hashCode));
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // TEST-10-S6: PlayQueue == / hashCode 负面补全
  // bug_bug01_fixed_test 已覆盖: == 六个字段全部负面 + shuffleOrder/
  // shufflePosition 的 hashCode 负面；此处只补 files/currentIndex/
  // startPositionMs/playMode 的 hashCode 负面（避免重复）。
  // ═══════════════════════════════════════════════════════════════════════
  group('TEST-10-S6: PlayQueue hashCode 负面补全', () {
    List<NasFile> files() => [
          testAudio('a.mp3', '/music/a.mp3'),
          testAudio('b.mp3', '/music/b.mp3'),
        ];

    PlayQueue base() => PlayQueue(
          files: files(),
          currentIndex: 0,
          startPositionMs: 0,
          playMode: PlayMode.sequential,
        );

    test('TEST-10-S6: files 不同 → hashCode 不同', () {
      expect(
          base().hashCode,
          isNot(equals(PlayQueue(
            files: [testAudio('x.mp3', '/music/x.mp3')],
            currentIndex: 0,
            startPositionMs: 0,
            playMode: PlayMode.sequential,
          ).hashCode)));
    });

    test('TEST-10-S6: currentIndex 不同 → hashCode 不同', () {
      expect(
          base().hashCode,
          isNot(equals(PlayQueue(
            files: files(),
            currentIndex: 1,
            startPositionMs: 0,
            playMode: PlayMode.sequential,
          ).hashCode)));
    });

    test('TEST-10-S6: startPositionMs 不同 → hashCode 不同', () {
      expect(
          base().hashCode,
          isNot(equals(PlayQueue(
            files: files(),
            currentIndex: 0,
            startPositionMs: 1000,
            playMode: PlayMode.sequential,
          ).hashCode)));
    });

    test('TEST-10-S6: playMode 不同 → hashCode 不同', () {
      expect(
          base().hashCode,
          isNot(equals(PlayQueue(
            files: files(),
            currentIndex: 0,
            startPositionMs: 0,
            playMode: PlayMode.repeatAll,
          ).hashCode)));
    });

    test('TEST-10-S6: 相等对象 hashCode 一致（基线自洽）', () {
      expect(base().hashCode, equals(base().hashCode));
      expect(base() == base(), isTrue);
    });
  });
}
