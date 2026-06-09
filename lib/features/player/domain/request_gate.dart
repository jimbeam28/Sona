// lib/features/player/domain/request_gate.dart
// REF-11: Extracted from player_provider.dart
//
// SerializedRequestGate — serializes asynchronous requests so only the
// latest one produces a meaningful result.  Older requests are allowed to
// finish but their completions are discarded once a newer request has been
// scheduled.  This prevents overlapping `stop -> setAudioSource -> play`
// chains on the shared AudioPlayer.
//
// Also contains PlayerLoadStatus, PlayerLoadState, TrackLoadStatus, and
// TrackLoadResult which are used by the gate's callers.

import 'dart:async';

import 'package:just_audio/just_audio.dart';

// ── Player load state ──────────────────────────────────────────────────────────

/// Lifecycle of loading an audio source into the player.
enum PlayerLoadStatus {
  /// No source has been loaded yet.
  idle,

  /// The source is being loaded / buffered.
  loading,

  /// The source is loaded and the player is ready to play.
  ready,

  /// Loading failed.
  error,
}

/// Tracks the current source-loading state of the player.
///
/// Managed by the [PlayerScreen] locally (not a global StateNotifier)
/// because the load cycle is tightly coupled to the screen lifecycle
/// (rebuilding the screen for a different file starts a fresh load).
class PlayerLoadState {
  final PlayerLoadStatus status;
  final String? errorMessage;

  /// Whether the error is an authentication failure (401 / 403).
  final bool isAuthError;

  const PlayerLoadState({
    this.status = PlayerLoadStatus.idle,
    this.errorMessage,
    this.isAuthError = false,
  });

  static const idle = PlayerLoadState();

  static const loading = PlayerLoadState(status: PlayerLoadStatus.loading);

  static const ready = PlayerLoadState(status: PlayerLoadStatus.ready);

  factory PlayerLoadState.error(String message, {bool isAuthError = false}) {
    return PlayerLoadState(
      status: PlayerLoadStatus.error,
      errorMessage: message,
      isAuthError: isAuthError,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PlayerLoadState &&
          status == other.status &&
          errorMessage == other.errorMessage &&
          isAuthError == other.isAuthError;

  @override
  int get hashCode => Object.hash(status, errorMessage, isAuthError);

  @override
  String toString() =>
      'PlayerLoadState(status: $status, errorMessage: $errorMessage, '
      'isAuthError: $isAuthError)';
}

// ── Track load result ──────────────────────────────────────────────────────────

/// Result of attempting to load the current queue entry into the player.
enum TrackLoadStatus {
  loaded,
  failed,
  superseded,
}

/// Outcome wrapper for serialized load requests.
class TrackLoadResult {
  final TrackLoadStatus status;
  final AudioPlayer? player;

  const TrackLoadResult._(this.status, this.player);

  const TrackLoadResult.loaded(AudioPlayer player)
      : this._(TrackLoadStatus.loaded, player);

  const TrackLoadResult.failed() : this._(TrackLoadStatus.failed, null);

  const TrackLoadResult.superseded() : this._(TrackLoadStatus.superseded, null);

  bool get isLoaded => status == TrackLoadStatus.loaded && player != null;
  bool get isSuperseded => status == TrackLoadStatus.superseded;
}

// ── SerializedRequestGate ──────────────────────────────────────────────────────

/// Serializes asynchronous requests and lets the latest one win.
///
/// Older requests are allowed to finish, but their completion is discarded
/// once a newer request has been scheduled. This prevents overlapping
/// `stop -> setAudioSource -> play` chains on the shared [AudioPlayer].
class SerializedRequestGate {
  int _latestRequestId = 0;
  bool _running = false;
  _QueuedRequest<dynamic>? _pendingRequest;

  int beginRequest() => ++_latestRequestId;

  bool isLatest(int requestId) => requestId == _latestRequestId;

  Future<T> schedule<T>({
    required Future<T> Function(int requestId) task,
    required T Function() onSuperseded,
  }) {
    final requestId = beginRequest();
    final completer = Completer<T>();
    final request = _QueuedRequest<T>(
      requestId: requestId,
      task: task,
      onSuperseded: onSuperseded,
      completer: completer,
    );

    if (_running) {
      _pendingRequest?.completeSuperseded();
      _pendingRequest = request;
    } else {
      _start(request);
    }

    return completer.future;
  }

  void _start<T>(_QueuedRequest<T> request) {
    _running = true;
    unawaited(() async {
      try {
        // BUG-05: add 20-second timeout to prevent the gate from getting
        // permanently stuck when the task hangs on an unresolved await.
        final result = await request.task(request.requestId).timeout(
          const Duration(seconds: 20),
          onTimeout: () => throw TimeoutException(
            'SerializedRequestGate: task timed out after 20 seconds',
          ),
        );
        request.complete(
            isLatest(request.requestId) ? result : request.onSuperseded());
      } catch (e) {
        if (isLatest(request.requestId)) {
          request.completer.completeError(e);
        } else {
          request.complete(request.onSuperseded());
        }
      } finally {
        _running = false;
        final next = _pendingRequest;
        _pendingRequest = null;
        if (next != null) {
          _start<dynamic>(next);
        }
      }
    }());
  }
}

class _QueuedRequest<T> {
  final int requestId;
  final Future<T> Function(int requestId) task;
  final T Function() onSuperseded;
  final Completer<T> completer;

  _QueuedRequest({
    required this.requestId,
    required this.task,
    required this.onSuperseded,
    required this.completer,
  });

  void complete(T result) {
    if (!completer.isCompleted) {
      completer.complete(result);
    }
  }

  void completeSuperseded() {
    complete(onSuperseded());
  }
}
