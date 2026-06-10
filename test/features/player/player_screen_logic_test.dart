// test/features/player/player_screen_logic_test.dart
// TREF-03: PlayerScreen extracted logic — unit tests
//
// Tests pure functions from player_screen_logic.dart:
//   sourceMatchesQueue, parentDir, classifyLoadFailure,
//   errorMessageForLoadFailure, isAuthError.
// Zero Flutter / Riverpod dependencies — pure Dart unit tests.

import 'package:flutter_test/flutter_test.dart';
import 'package:nas_audio_player/features/player/domain/player_screen_logic.dart';
import 'package:nas_audio_player/shared/models/nas_file.dart';
import 'package:nas_audio_player/shared/models/play_queue.dart';

NasFile _file(String path) => NasFile(
      name: path.split('/').last,
      path: path,
      isDirectory: false,
    );

PlayQueue _queue(String path) => PlayQueue(
      files: [_file(path)],
      currentIndex: 0,
    );

void main() {
  // ── sourceMatchesQueue ───────────────────────────────────────────────────

  group('sourceMatchesQueue', () {
    // TREF-03-T01 (PSL-01): null currentSourcePath → false
    test('PSL-01: null currentSourcePath returns false', () {
      final queue = _queue('/music/song.mp3');
      expect(sourceMatchesQueue(null, queue), isFalse);
    });

    // TREF-03-T02 (PSL-02): URI matches → true
    test('PSL-02: matching URI path returns true', () {
      final queue = _queue('/music/song.mp3');
      expect(
        sourceMatchesQueue('http://nas.local/music/song.mp3', queue),
        isTrue,
      );
    });

    // TREF-03-T03 (PSL-03): URI does not match → false
    test('PSL-03: non-matching URI path returns false', () {
      final queue = _queue('/music/song.mp3');
      expect(
        sourceMatchesQueue('http://nas.local/music/other.mp3', queue),
        isFalse,
      );
    });

    // TREF-03-T04 (PSL-04): empty string path does not match → false
    test('PSL-04: empty source path returns false', () {
      final queue = _queue('/music/song.mp3');
      expect(sourceMatchesQueue('', queue), isFalse);
    });

    // TREF-03-T05 (PSL-05): URL-encoded path matches → true
    test('PSL-05: URL-encoded source endsWith matching queue path', () {
      // sourceMatchesQueue uses endsWith without URL-decoding, so the queue
      // path must also be in its URL-encoded form for the match to succeed.
      final queue = _queue('/music/my%20song.mp3');
      expect(
        sourceMatchesQueue('http://nas.local/music/my%20song.mp3', queue),
        isTrue,
      );
    });
  });

  // ── parentDir ────────────────────────────────────────────────────────────

  group('parentDir', () {
    // TREF-03-T06 (PSL-06): nested path → parent directory
    test('PSL-06: nested path returns parent directory', () {
      expect(parentDir('/music/album/song.mp3'), '/music/album');
    });

    // TREF-03-T07 (PSL-07): root-level file → '/'
    test('PSL-07: root-level file returns "/"', () {
      expect(parentDir('/song.mp3'), '/');
    });

    // TREF-03-T08 (PSL-08): no leading slash → '/'
    test('PSL-08: no leading slash returns "/"', () {
      expect(parentDir('song.mp3'), '/');
    });

    // TREF-03-T09 (PSL-09): trailing slash → stripped by lastIndexOf
    test('PSL-09: trailing slash is the last separator', () {
      // lastIndexOf('/') finds the trailing '/', idx=12 which is > 0,
      // so substring(0,12) returns '/music/album'.
      expect(parentDir('/music/album/'), '/music/album');
    });
  });

  // ── classifyLoadFailure ──────────────────────────────────────────────────

  group('classifyLoadFailure', () {
    // TREF-03-T10 (PSL-10): no connection → noConnection
    test('PSL-10: no active connection returns noConnection', () {
      expect(
        classifyLoadFailure(hasActiveConnection: false, hasPassword: false),
        LoadFailureReason.noConnection,
      );
    });

    // TREF-03-T11 (PSL-11): has connection, no password → noPassword
    test('PSL-11: connection exists but no password returns noPassword', () {
      expect(
        classifyLoadFailure(hasActiveConnection: true, hasPassword: false),
        LoadFailureReason.noPassword,
      );
    });

    // TREF-03-T12 (PSL-12): has connection, has password → generic
    test('PSL-12: connection and password present returns generic', () {
      expect(
        classifyLoadFailure(hasActiveConnection: true, hasPassword: true),
        LoadFailureReason.generic,
      );
    });

    // TREF-03-T13 (PSL-13): no connection, has password → noConnection (priority)
    test('PSL-13: no connection takes priority even with password', () {
      expect(
        classifyLoadFailure(hasActiveConnection: false, hasPassword: true),
        LoadFailureReason.noConnection,
      );
    });
  });

  // ── errorMessageForLoadFailure ───────────────────────────────────────────

  group('errorMessageForLoadFailure', () {
    // TREF-03-T14 (PSL-14): noConnection → '没有活跃的连接'
    test('PSL-14: noConnection returns correct message', () {
      expect(
        errorMessageForLoadFailure(LoadFailureReason.noConnection),
        '没有活跃的连接',
      );
    });

    // TREF-03-T15 (PSL-15): noPassword → '密码未保存'
    test('PSL-15: noPassword returns correct message', () {
      expect(
        errorMessageForLoadFailure(LoadFailureReason.noPassword),
        '密码未保存',
      );
    });

    // TREF-03-T16 (PSL-16): generic → '加载失败'
    test('PSL-16: generic returns correct message', () {
      expect(
        errorMessageForLoadFailure(LoadFailureReason.generic),
        '加载失败',
      );
    });
  });

  // ── isAuthError ──────────────────────────────────────────────────────────

  group('isAuthError', () {
    // TREF-03-T17 (PSL-17): noConnection → true
    test('PSL-17: noConnection is an auth error', () {
      expect(isAuthError(LoadFailureReason.noConnection), isTrue);
    });

    // TREF-03-T18 (PSL-18): noPassword → true
    test('PSL-18: noPassword is an auth error', () {
      expect(isAuthError(LoadFailureReason.noPassword), isTrue);
    });

    // TREF-03-T19 (PSL-19): generic → false
    test('PSL-19: generic is not an auth error', () {
      expect(isAuthError(LoadFailureReason.generic), isFalse);
    });
  });
}
