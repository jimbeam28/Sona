// test/helpers/fake_webdav_client.dart
// Shared mock implementations of [WebDavClientInterface] for tests.
//
// Two variants are provided:
//   [MockWebDavClient]  — full mock with `returnResult()` / `hangUntilCompleted()`
//                         for the `validate` method (used by connection tests).
//                         `listDirectory` returns an empty list by default;
//                         override via `returnListResult()`, or set
//                         `listDirectoryError` to inject a failure.
//   [SpyWebDavClient]   — lightweight spy that tracks `listDirectory` call
//                         count and called paths (used by browser cache tests).
//
// DL-01：接口新增 `downloadFile` 后两个类各自补齐 override（不改既有签名）。
// Mock 版经 [downloadFileHandler] 钩子编程，null 时抛 UnimplementedError；
// Spy 版记录调用并默认抛 UnimplementedError。

import 'dart:async';

import 'package:nas_audio_player/core/network/webdav_client.dart';
import 'package:nas_audio_player/shared/models/nas_file.dart';

/// `downloadFile` 的可编程处理器签名（DL-01）。
typedef DownloadFileHandler = Future<void> Function({
  required String url,
  required String filePath,
  required String username,
  required String password,
  required String saveTo,
  void Function(int received, int? total)? onProgress,
});

// ── MockWebDavClient: full mock with validate + listDirectory support ────────

/// A full mock of [WebDavClientInterface] supporting both `validate` and
/// `listDirectory`.
///
/// `validate` supports two modes:
///   - `returnResult()` — immediately returns the given result.
///   - `hangUntilCompleted()` — suspends until the supplied [Completer] resolves.
///
/// `listDirectory` returns an empty list by default.
/// Use [returnListResult] to provide canned directory listings, or set
/// [listDirectoryError] to inject a failure.
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

  /// When set, `listDirectory()` throws this exception instead of returning
  /// a result (error-injection mode, TEST-07-S6). Mutually exclusive with
  /// [returnListResult] only in the sense that the error takes precedence.
  WebDavException? listDirectoryError;

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
    final error = listDirectoryError;
    if (error != null) {
      throw error;
    }
    return _listResult;
  }

  // ── downloadFile support（DL-01）──────────────────────────────────────────

  /// 可编程钩子；null 时抛 [UnimplementedError]。
  DownloadFileHandler? downloadFileHandler;

  @override
  Future<void> downloadFile({
    required String url,
    required String filePath,
    required String username,
    required String password,
    required String saveTo,
    void Function(int received, int? total)? onProgress,
  }) async {
    final handler = downloadFileHandler;
    if (handler == null) {
      throw UnimplementedError(
          'downloadFile not configured: set downloadFileHandler');
    }
    return handler(
      url: url,
      filePath: filePath,
      username: username,
      password: password,
      saveTo: saveTo,
      onProgress: onProgress,
    );
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

  // ── downloadFile support（DL-01）──────────────────────────────────────────

  int downloadFileCallCount = 0;
  final List<String> calledDownloadUrls = <String>[];
  final List<String> calledDownloadPaths = <String>[];
  final List<String> calledDownloadSaveTos = <String>[];

  /// 可选编程钩子；null 时默认抛 [UnimplementedError]（仅记录调用）。
  DownloadFileHandler? downloadFileHandler;

  @override
  Future<void> downloadFile({
    required String url,
    required String filePath,
    required String username,
    required String password,
    required String saveTo,
    void Function(int received, int? total)? onProgress,
  }) async {
    downloadFileCallCount++;
    calledDownloadUrls.add(url);
    calledDownloadPaths.add(filePath);
    calledDownloadSaveTos.add(saveTo);
    final handler = downloadFileHandler;
    if (handler == null) {
      throw UnimplementedError(
          'downloadFile not needed for SpyWebDavClient by default');
    }
    return handler(
      url: url,
      filePath: filePath,
      username: username,
      password: password,
      saveTo: saveTo,
      onProgress: onProgress,
    );
  }
}
