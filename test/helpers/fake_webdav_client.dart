// test/helpers/fake_webdav_client.dart
// Shared mock implementations of [WebDavClientInterface] for tests.
//
// Two variants are provided:
//   [MockWebDavClient]  — full mock with `returnResult()` / `hangUntilCompleted()`
//                         for the `validate` method (used by connection tests).
//                         `listDirectory` throws by default; override via
//                         `returnListResult()` for browser tests.
//   [SpyWebDavClient]   — lightweight spy that tracks `listDirectory` call
//                         count and called paths (used by browser cache tests).

import 'dart:async';

import 'package:nas_audio_player/core/network/webdav_client.dart';
import 'package:nas_audio_player/shared/models/nas_file.dart';

// ── MockWebDavClient: full mock with validate + listDirectory support ────────

/// A full mock of [WebDavClientInterface] supporting both `validate` and
/// `listDirectory`.
///
/// `validate` supports two modes:
///   - `returnResult()` — immediately returns the given result.
///   - `hangUntilCompleted()` — suspends until the supplied [Completer] resolves.
///
/// `listDirectory` is a no-op by default (throws [UnimplementedError]).
/// Use [returnListResult] to provide canned directory listings.
class MockWebDavClient implements WebDavClientInterface {
  // ── validate support ──────────────────────────────────────────────────────

  WebDavValidationResult Function({
    required String url,
    required String username,
    required String password,
    String basePath,
  })? _handler;

  Completer<WebDavValidationResult>? _pendingCompleter;

  /// Configure `validate()` to immediately return [result].
  void returnResult(WebDavValidationResult result) {
    _handler = ({
      required url,
      required username,
      required password,
      basePath = '/',
    }) =>
        result;
    _pendingCompleter = null;
  }

  /// Configure `validate()` to hang until [completer] is completed.
  void hangUntilCompleted(Completer<WebDavValidationResult> completer) {
    _pendingCompleter = completer;
    _handler = null;
  }

  @override
  Future<WebDavValidationResult> validate({
    required String url,
    required String username,
    required String password,
    String basePath = '/',
  }) async {
    if (_pendingCompleter != null) {
      return _pendingCompleter!.future;
    }
    if (_handler != null) {
      return _handler!(
        url: url,
        username: username,
        password: password,
        basePath: basePath,
      );
    }
    return WebDavValidationResult.networkError();
  }

  // ── listDirectory support ─────────────────────────────────────────────────

  List<NasFile> _listResult = const [];

  /// Configure `listDirectory()` to return [result].
  void returnListResult(List<NasFile> result) {
    _listResult = result;
  }

  @override
  Future<List<NasFile>> listDirectory({
    required String url,
    required String username,
    required String password,
    required String path,
  }) async {
    return _listResult;
  }
}

// ── SpyWebDavClient: tracks listDirectory calls for cache tests ─────────────

/// A lightweight spy that tracks [listDirectory] invocations so tests can
/// assert cache behaviour. The `validate` method throws by default.
class SpyWebDavClient implements WebDavClientInterface {
  int listDirectoryCallCount = 0;
  List<String> calledPaths = <String>[];
  List<NasFile> _result = const [];

  /// Configure the result returned by `listDirectory()`.
  void returnResult(List<NasFile> result) {
    _result = result;
  }

  @override
  Future<List<NasFile>> listDirectory({
    required String url,
    required String username,
    required String password,
    required String path,
  }) async {
    listDirectoryCallCount++;
    calledPaths.add(path);
    return _result;
  }

  @override
  Future<WebDavValidationResult> validate({
    required String url,
    required String username,
    required String password,
    String basePath = '/',
  }) async {
    throw UnimplementedError('validate not needed for SpyWebDavClient');
  }
}
