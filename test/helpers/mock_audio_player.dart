// test/helpers/mock_audio_player.dart
// Shared hand-written mock of AudioPlayer for all test modules.
//
// Replaces the build_runner-generated `ply_08_test.mocks.dart` so that
// cross-feature imports are no longer needed.  This class extends Mockito's
// [Mock] and implements [AudioPlayer], which preserves `when()`/`verify()`
// semantics without requiring code generation.
//
// Each member is overridden to call super.noSuchMethod with explicit
// returnValue/returnValueForMissingStub, matching the generated mock's
// approach.  This ensures:
//   1. when() calls work (returnValue is returned during stubbing)
//   2. verify() calls work (invocations are tracked)
//   3. Unstubbed calls return sensible defaults (returnValueForMissingStub)

import 'dart:async';

import 'package:audio_session/audio_session.dart';
import 'package:just_audio/just_audio.dart';
import 'package:mockito/mockito.dart';

/// A hand-written mock of [AudioPlayer] that supports Mockito's
/// `when()` and `verify()` APIs.
///
/// Usage:
/// ```dart
/// final player = MockAudioPlayer();
/// when(player.positionStream).thenAnswer((_) => Stream.value(Duration.zero));
/// verify(player.pause()).called(1);
/// ```
// ignore_for_file: unnecessary_overrides
class MockAudioPlayer extends Mock implements AudioPlayer {
  MockAudioPlayer() {
    throwOnMissingStub(this);
  }

  // ── Stream getters ──────────────────────────────────────────────────

  @override
  Stream<PlaybackEvent> get playbackEventStream =>
      super.noSuchMethod(Invocation.getter(#playbackEventStream),
          returnValue: Stream<PlaybackEvent>.empty(),
          returnValueForMissingStub: Stream<PlaybackEvent>.empty())
      as Stream<PlaybackEvent>;

  @override
  Stream<Duration?> get durationStream =>
      super.noSuchMethod(Invocation.getter(#durationStream),
          returnValue: Stream<Duration?>.empty(),
          returnValueForMissingStub: Stream<Duration?>.empty())
      as Stream<Duration?>;

  @override
  Stream<ProcessingState> get processingStateStream =>
      super.noSuchMethod(Invocation.getter(#processingStateStream),
          returnValue: Stream<ProcessingState>.empty(),
          returnValueForMissingStub: Stream<ProcessingState>.empty())
      as Stream<ProcessingState>;

  @override
  Stream<bool> get playingStream =>
      super.noSuchMethod(Invocation.getter(#playingStream),
          returnValue: Stream<bool>.empty(),
          returnValueForMissingStub: Stream<bool>.empty())
      as Stream<bool>;

  @override
  Stream<double> get volumeStream =>
      super.noSuchMethod(Invocation.getter(#volumeStream),
          returnValue: Stream<double>.empty(),
          returnValueForMissingStub: Stream<double>.empty())
      as Stream<double>;

  @override
  Stream<double> get speedStream =>
      super.noSuchMethod(Invocation.getter(#speedStream),
          returnValue: Stream<double>.empty(),
          returnValueForMissingStub: Stream<double>.empty())
      as Stream<double>;

  @override
  Stream<double> get pitchStream =>
      super.noSuchMethod(Invocation.getter(#pitchStream),
          returnValue: Stream<double>.empty(),
          returnValueForMissingStub: Stream<double>.empty())
      as Stream<double>;

  @override
  Stream<bool> get skipSilenceEnabledStream =>
      super.noSuchMethod(Invocation.getter(#skipSilenceEnabledStream),
          returnValue: Stream<bool>.empty(),
          returnValueForMissingStub: Stream<bool>.empty())
      as Stream<bool>;

  @override
  Stream<Duration> get bufferedPositionStream =>
      super.noSuchMethod(Invocation.getter(#bufferedPositionStream),
          returnValue: Stream<Duration>.empty(),
          returnValueForMissingStub: Stream<Duration>.empty())
      as Stream<Duration>;

  @override
  Stream<IcyMetadata?> get icyMetadataStream =>
      super.noSuchMethod(Invocation.getter(#icyMetadataStream),
          returnValue: Stream<IcyMetadata?>.empty(),
          returnValueForMissingStub: Stream<IcyMetadata?>.empty())
      as Stream<IcyMetadata?>;

  @override
  Stream<PlayerState> get playerStateStream =>
      super.noSuchMethod(Invocation.getter(#playerStateStream),
          returnValue: Stream<PlayerState>.empty(),
          returnValueForMissingStub: Stream<PlayerState>.empty())
      as Stream<PlayerState>;

  @override
  Stream<List<IndexedAudioSource>?> get sequenceStream =>
      super.noSuchMethod(Invocation.getter(#sequenceStream),
          returnValue: Stream<List<IndexedAudioSource>?>.empty(),
          returnValueForMissingStub: Stream<List<IndexedAudioSource>?>.empty())
      as Stream<List<IndexedAudioSource>?>;

  @override
  Stream<List<int>?> get shuffleIndicesStream =>
      super.noSuchMethod(Invocation.getter(#shuffleIndicesStream),
          returnValue: Stream<List<int>?>.empty(),
          returnValueForMissingStub: Stream<List<int>?>.empty())
      as Stream<List<int>?>;

  @override
  Stream<int?> get currentIndexStream =>
      super.noSuchMethod(Invocation.getter(#currentIndexStream),
          returnValue: Stream<int?>.empty(),
          returnValueForMissingStub: Stream<int?>.empty())
      as Stream<int?>;

  @override
  Stream<SequenceState?> get sequenceStateStream =>
      super.noSuchMethod(Invocation.getter(#sequenceStateStream),
          returnValue: Stream<SequenceState?>.empty(),
          returnValueForMissingStub: Stream<SequenceState?>.empty())
      as Stream<SequenceState?>;

  @override
  Stream<LoopMode> get loopModeStream =>
      super.noSuchMethod(Invocation.getter(#loopModeStream),
          returnValue: Stream<LoopMode>.empty(),
          returnValueForMissingStub: Stream<LoopMode>.empty())
      as Stream<LoopMode>;

  @override
  Stream<bool> get shuffleModeEnabledStream =>
      super.noSuchMethod(Invocation.getter(#shuffleModeEnabledStream),
          returnValue: Stream<bool>.empty(),
          returnValueForMissingStub: Stream<bool>.empty())
      as Stream<bool>;

  @override
  Stream<int?> get androidAudioSessionIdStream =>
      super.noSuchMethod(Invocation.getter(#androidAudioSessionIdStream),
          returnValue: Stream<int?>.empty(),
          returnValueForMissingStub: Stream<int?>.empty())
      as Stream<int?>;

  @override
  Stream<PositionDiscontinuity> get positionDiscontinuityStream =>
      super.noSuchMethod(Invocation.getter(#positionDiscontinuityStream),
          returnValue: Stream<PositionDiscontinuity>.empty(),
          returnValueForMissingStub: Stream<PositionDiscontinuity>.empty())
      as Stream<PositionDiscontinuity>;

  @override
  Stream<Duration> get positionStream =>
      super.noSuchMethod(Invocation.getter(#positionStream),
          returnValue: Stream<Duration>.empty(),
          returnValueForMissingStub: Stream<Duration>.empty())
      as Stream<Duration>;

  // ── Property getters ────────────────────────────────────────────────

  @override
  PlaybackEvent get playbackEvent =>
      super.noSuchMethod(Invocation.getter(#playbackEvent),
          returnValue: PlaybackEvent(),
          returnValueForMissingStub: PlaybackEvent())
      as PlaybackEvent;

  @override
  ProcessingState get processingState =>
      super.noSuchMethod(Invocation.getter(#processingState),
          returnValue: ProcessingState.idle,
          returnValueForMissingStub: ProcessingState.idle)
      as ProcessingState;

  @override
  bool get playing => super.noSuchMethod(Invocation.getter(#playing),
      returnValue: false, returnValueForMissingStub: false) as bool;

  @override
  double get volume => super.noSuchMethod(Invocation.getter(#volume),
      returnValue: 1.0, returnValueForMissingStub: 1.0) as double;

  @override
  double get speed => super.noSuchMethod(Invocation.getter(#speed),
      returnValue: 1.0, returnValueForMissingStub: 1.0) as double;

  @override
  double get pitch => super.noSuchMethod(Invocation.getter(#pitch),
      returnValue: 1.0, returnValueForMissingStub: 1.0) as double;

  @override
  bool get skipSilenceEnabled =>
      super.noSuchMethod(Invocation.getter(#skipSilenceEnabled),
          returnValue: false, returnValueForMissingStub: false) as bool;

  @override
  Duration get bufferedPosition =>
      super.noSuchMethod(Invocation.getter(#bufferedPosition),
          returnValue: Duration.zero, returnValueForMissingStub: Duration.zero)
      as Duration;

  @override
  PlayerState get playerState =>
      super.noSuchMethod(Invocation.getter(#playerState),
          returnValue: PlayerState(false, ProcessingState.idle),
          returnValueForMissingStub: PlayerState(false, ProcessingState.idle))
      as PlayerState;

  @override
  bool get hasNext => super.noSuchMethod(Invocation.getter(#hasNext),
      returnValue: false, returnValueForMissingStub: false) as bool;

  @override
  bool get hasPrevious => super.noSuchMethod(Invocation.getter(#hasPrevious),
      returnValue: false, returnValueForMissingStub: false) as bool;

  @override
  LoopMode get loopMode => super.noSuchMethod(Invocation.getter(#loopMode),
      returnValue: LoopMode.off, returnValueForMissingStub: LoopMode.off)
      as LoopMode;

  @override
  bool get shuffleModeEnabled =>
      super.noSuchMethod(Invocation.getter(#shuffleModeEnabled),
          returnValue: false, returnValueForMissingStub: false) as bool;

  @override
  bool get automaticallyWaitsToMinimizeStalling =>
      super.noSuchMethod(
          Invocation.getter(#automaticallyWaitsToMinimizeStalling),
          returnValue: false,
          returnValueForMissingStub: false) as bool;

  @override
  bool get canUseNetworkResourcesForLiveStreamingWhilePaused =>
      super.noSuchMethod(
          Invocation.getter(#canUseNetworkResourcesForLiveStreamingWhilePaused),
          returnValue: false,
          returnValueForMissingStub: false) as bool;

  @override
  double get preferredPeakBitRate =>
      super.noSuchMethod(Invocation.getter(#preferredPeakBitRate),
          returnValue: 0.0, returnValueForMissingStub: 0.0) as double;

  @override
  bool get allowsExternalPlayback =>
      super.noSuchMethod(Invocation.getter(#allowsExternalPlayback),
          returnValue: false, returnValueForMissingStub: false) as bool;

  @override
  Duration get position => super.noSuchMethod(Invocation.getter(#position),
      returnValue: Duration.zero, returnValueForMissingStub: Duration.zero)
      as Duration;

  // ── Methods ─────────────────────────────────────────────────────────

  @override
  Future<void> play() => super.noSuchMethod(Invocation.method(#play, []),
      returnValue: Future<void>.value(),
      returnValueForMissingStub: Future<void>.value()) as Future<void>;

  @override
  Future<void> pause() => super.noSuchMethod(Invocation.method(#pause, []),
      returnValue: Future<void>.value(),
      returnValueForMissingStub: Future<void>.value()) as Future<void>;

  @override
  Future<void> stop() => super.noSuchMethod(Invocation.method(#stop, []),
      returnValue: Future<void>.value(),
      returnValueForMissingStub: Future<void>.value()) as Future<void>;

  @override
  Future<void> setVolume(double volume) =>
      super.noSuchMethod(Invocation.method(#setVolume, [volume]),
          returnValue: Future<void>.value(),
          returnValueForMissingStub: Future<void>.value()) as Future<void>;

  @override
  Future<void> setSkipSilenceEnabled(bool enabled) =>
      super.noSuchMethod(
          Invocation.method(#setSkipSilenceEnabled, [enabled]),
          returnValue: Future<void>.value(),
          returnValueForMissingStub: Future<void>.value()) as Future<void>;

  @override
  Future<void> setSpeed(double speed) =>
      super.noSuchMethod(Invocation.method(#setSpeed, [speed]),
          returnValue: Future<void>.value(),
          returnValueForMissingStub: Future<void>.value()) as Future<void>;

  @override
  Future<void> setPitch(double pitch) =>
      super.noSuchMethod(Invocation.method(#setPitch, [pitch]),
          returnValue: Future<void>.value(),
          returnValueForMissingStub: Future<void>.value()) as Future<void>;

  @override
  Future<void> setLoopMode(LoopMode mode) =>
      super.noSuchMethod(Invocation.method(#setLoopMode, [mode]),
          returnValue: Future<void>.value(),
          returnValueForMissingStub: Future<void>.value()) as Future<void>;

  @override
  Future<void> setShuffleModeEnabled(bool enabled) =>
      super.noSuchMethod(Invocation.method(#setShuffleModeEnabled, [enabled]),
          returnValue: Future<void>.value(),
          returnValueForMissingStub: Future<void>.value()) as Future<void>;

  @override
  Future<void> shuffle() => super.noSuchMethod(Invocation.method(#shuffle, []),
      returnValue: Future<void>.value(),
      returnValueForMissingStub: Future<void>.value()) as Future<void>;

  @override
  Future<void> setAutomaticallyWaitsToMinimizeStalling(bool value) =>
      super.noSuchMethod(
          Invocation.method(
              #setAutomaticallyWaitsToMinimizeStalling, [value]),
          returnValue: Future<void>.value(),
          returnValueForMissingStub: Future<void>.value()) as Future<void>;

  @override
  Future<void> setCanUseNetworkResourcesForLiveStreamingWhilePaused(
          bool value) =>
      super.noSuchMethod(
          Invocation.method(
              #setCanUseNetworkResourcesForLiveStreamingWhilePaused, [value]),
          returnValue: Future<void>.value(),
          returnValueForMissingStub: Future<void>.value()) as Future<void>;

  @override
  Future<void> setPreferredPeakBitRate(double value) => super.noSuchMethod(
      Invocation.method(#setPreferredPeakBitRate, [value]),
      returnValue: Future<void>.value(),
      returnValueForMissingStub: Future<void>.value()) as Future<void>;

  @override
  Future<void> setAllowsExternalPlayback(bool value) => super.noSuchMethod(
      Invocation.method(#setAllowsExternalPlayback, [value]),
      returnValue: Future<void>.value(),
      returnValueForMissingStub: Future<void>.value()) as Future<void>;

  @override
  Future<void> seek(Duration? position, {int? index}) => super.noSuchMethod(
      Invocation.method(#seek, [position], {if (index != null) #index: index}),
      returnValue: Future<void>.value(),
      returnValueForMissingStub: Future<void>.value()) as Future<void>;

  @override
  Future<void> seekToNext() =>
      super.noSuchMethod(Invocation.method(#seekToNext, []),
          returnValue: Future<void>.value(),
          returnValueForMissingStub: Future<void>.value()) as Future<void>;

  @override
  Future<void> seekToPrevious() =>
      super.noSuchMethod(Invocation.method(#seekToPrevious, []),
          returnValue: Future<void>.value(),
          returnValueForMissingStub: Future<void>.value()) as Future<void>;

  @override
  Future<void> setAndroidAudioAttributes(
          AndroidAudioAttributes audioAttributes) =>
      super.noSuchMethod(
          Invocation.method(#setAndroidAudioAttributes, [audioAttributes]),
          returnValue: Future<void>.value(),
          returnValueForMissingStub: Future<void>.value()) as Future<void>;

  @override
  Future<void> dispose() => super.noSuchMethod(Invocation.method(#dispose, []),
      returnValue: Future<void>.value(),
      returnValueForMissingStub: Future<void>.value()) as Future<void>;

  @override
  Future<Duration?> setUrl(String url,
          {Map<String, String>? headers,
          Duration? initialPosition,
          bool preload = true,
          dynamic tag}) =>
      super.noSuchMethod(
          Invocation.method(#setUrl, [
            url
          ], {
            if (headers != null) #headers: headers,
            if (initialPosition != null) #initialPosition: initialPosition,
            #preload: preload,
            if (tag != null) #tag: tag,
          }),
          returnValue: Future<Duration?>.value(),
          returnValueForMissingStub: Future<Duration?>.value())
      as Future<Duration?>;

  @override
  Future<Duration?> setAudioSource(AudioSource source,
          {bool preload = true,
          int? initialIndex,
          Duration? initialPosition}) =>
      super.noSuchMethod(
          Invocation.method(#setAudioSource, [
            source
          ], {
            #preload: preload,
            if (initialIndex != null) #initialIndex: initialIndex,
            if (initialPosition != null) #initialPosition: initialPosition,
          }),
          returnValue: Future<Duration?>.value(),
          returnValueForMissingStub: Future<Duration?>.value())
      as Future<Duration?>;

  @override
  Future<Duration?> load() => super.noSuchMethod(Invocation.method(#load, []),
      returnValue: Future<Duration?>.value(),
      returnValueForMissingStub: Future<Duration?>.value()) as Future<Duration?>;

  @override
  Future<Duration?> setFilePath(String filePath,
          {Duration? initialPosition, bool preload = true, dynamic tag}) =>
      super.noSuchMethod(
          Invocation.method(#setFilePath, [
            filePath
          ], {
            if (initialPosition != null) #initialPosition: initialPosition,
            #preload: preload,
            if (tag != null) #tag: tag,
          }),
          returnValue: Future<Duration?>.value(),
          returnValueForMissingStub: Future<Duration?>.value())
      as Future<Duration?>;

  @override
  Future<Duration?> setClip(
          {Duration? start, Duration? end, dynamic tag}) =>
      super.noSuchMethod(
          Invocation.method(#setClip, [], {
            if (start != null) #start: start,
            if (end != null) #end: end,
            if (tag != null) #tag: tag,
          }),
          returnValue: Future<Duration?>.value(),
          returnValueForMissingStub: Future<Duration?>.value())
      as Future<Duration?>;
}
