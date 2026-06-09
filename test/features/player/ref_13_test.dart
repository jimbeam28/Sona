// test/features/player/ref_13_test.dart
// REF-13: player/domain/background_playback.dart — extracted state machine
//
// Verifies that BackgroundPlaybackConfig, BackgroundPlaybackNotifier,
// shouldContinueInBackground, and computePlaybackStateAfterLifecycle
// work correctly as extracted domain types.
//
// REF-13-T01: Media control play/pause/stop/toggle state transitions
// REF-13-T02: Audio focus gained/lost/transient transitions
// REF-13-T03: Foreground/background lifecycle transitions
// REF-13-T04: isAudioActive / showPauseAction derived properties

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nas_audio_player/features/player/domain/background_playback.dart';

void main() {
  // ── REF-13-T01: Media control play/pause/stop/toggle state transitions ──

  group('REF-13-T01: Media control state transitions', () {
    test('play action on paused state sets playing', () {
      final state = BackgroundPlaybackConfig.paused(
        backgroundEnabled: true,
        isInForeground: false,
      );
      final after = state.handleMediaControl(MediaControlAction.play);
      expect(after.playbackState, equals(BackgroundPlaybackState.playing));
    });

    test('play action on playing state is idempotent', () {
      final state = BackgroundPlaybackConfig.playing(
        backgroundEnabled: true,
        isInForeground: false,
      );
      final after = state.handleMediaControl(MediaControlAction.play);
      expect(after.playbackState, equals(BackgroundPlaybackState.playing));
    });

    test('pause action on playing state sets paused', () {
      final state = BackgroundPlaybackConfig.playing(
        backgroundEnabled: true,
        isInForeground: false,
      );
      final after = state.handleMediaControl(MediaControlAction.pause);
      expect(after.playbackState, equals(BackgroundPlaybackState.paused));
    });

    test('pause action on paused state is idempotent', () {
      final state = BackgroundPlaybackConfig.paused(
        backgroundEnabled: true,
        isInForeground: false,
      );
      final after = state.handleMediaControl(MediaControlAction.pause);
      expect(after.playbackState, equals(BackgroundPlaybackState.paused));
    });

    test('stop action on playing state sets stopped', () {
      final state = BackgroundPlaybackConfig.playing(
        backgroundEnabled: true,
        isInForeground: false,
      );
      final after = state.handleMediaControl(MediaControlAction.stop);
      expect(after.playbackState, equals(BackgroundPlaybackState.stopped));
    });

    test('stop action on paused state sets stopped', () {
      final state = BackgroundPlaybackConfig.paused(
        backgroundEnabled: true,
        isInForeground: false,
      );
      final after = state.handleMediaControl(MediaControlAction.stop);
      expect(after.playbackState, equals(BackgroundPlaybackState.stopped));
    });

    test('togglePlayPause on playing state sets paused', () {
      final state = BackgroundPlaybackConfig.playing(
        backgroundEnabled: true,
        isInForeground: false,
      );
      final after =
          state.handleMediaControl(MediaControlAction.togglePlayPause);
      expect(after.playbackState, equals(BackgroundPlaybackState.paused));
    });

    test('togglePlayPause on paused state sets playing', () {
      final state = BackgroundPlaybackConfig.paused(
        backgroundEnabled: true,
        isInForeground: false,
      );
      final after =
          state.handleMediaControl(MediaControlAction.togglePlayPause);
      expect(after.playbackState, equals(BackgroundPlaybackState.playing));
    });

    test('togglePlayPause on stopped state sets playing', () {
      const state = BackgroundPlaybackConfig.initial;
      final after =
          state.handleMediaControl(MediaControlAction.togglePlayPause);
      expect(after.playbackState, equals(BackgroundPlaybackState.playing));
    });

    test('media control does not change backgroundEnabled or isInForeground',
        () {
      final state = BackgroundPlaybackConfig.playing(
        backgroundEnabled: true,
        isInForeground: false,
      );
      final after = state.handleMediaControl(MediaControlAction.pause);
      expect(after.backgroundEnabled, isTrue);
      expect(after.isInForeground, isFalse);
    });

    // Notifier integration
    test('Notifier: onMediaControl(play) transitions paused to playing', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(backgroundPlaybackProvider.notifier);

      notifier.startPlayback();
      notifier.onMediaControl(MediaControlAction.pause);
      expect(
        container.read(backgroundPlaybackProvider).playbackState,
        equals(BackgroundPlaybackState.paused),
      );

      notifier.onMediaControl(MediaControlAction.play);
      expect(
        container.read(backgroundPlaybackProvider).playbackState,
        equals(BackgroundPlaybackState.playing),
      );
    });

    test('Notifier: onMediaControl(stop) transitions to stopped', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(backgroundPlaybackProvider.notifier);

      notifier.startPlayback();
      notifier.onMediaControl(MediaControlAction.stop);
      expect(
        container.read(backgroundPlaybackProvider).playbackState,
        equals(BackgroundPlaybackState.stopped),
      );
    });

    test('Notifier: onMediaControl(togglePlayPause) toggles correctly', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(backgroundPlaybackProvider.notifier);

      notifier.startPlayback();
      notifier.onMediaControl(MediaControlAction.togglePlayPause);
      expect(
        container.read(backgroundPlaybackProvider).playbackState,
        equals(BackgroundPlaybackState.paused),
      );

      notifier.onMediaControl(MediaControlAction.togglePlayPause);
      expect(
        container.read(backgroundPlaybackProvider).playbackState,
        equals(BackgroundPlaybackState.playing),
      );
    });
  });

  // ── REF-13-T02: Audio focus gained/lost/transient transitions ────────────

  group('REF-13-T02: Audio focus transitions', () {
    test('lost focus pauses playback', () {
      final state = BackgroundPlaybackConfig.playing(
        backgroundEnabled: true,
        isInForeground: true,
      );
      final after = state.updateAudioFocus(AudioFocusState.lost);
      expect(after.playbackState, equals(BackgroundPlaybackState.paused));
      expect(after.audioFocus, equals(AudioFocusState.lost));
    });

    test('lost focus sets isAudioActive to false', () {
      final state = BackgroundPlaybackConfig.playing(
        backgroundEnabled: true,
        isInForeground: true,
      );
      expect(state.isAudioActive, isTrue);
      final after = state.updateAudioFocus(AudioFocusState.lost);
      expect(after.isAudioActive, isFalse);
    });

    test('gained focus restores focus flag but keeps paused', () {
      final lost = BackgroundPlaybackConfig.playing(
        backgroundEnabled: true,
        isInForeground: false,
      ).updateAudioFocus(AudioFocusState.lost);
      final regained = lost.updateAudioFocus(AudioFocusState.gained);
      expect(regained.audioFocus, equals(AudioFocusState.gained));
      expect(regained.playbackState, equals(BackgroundPlaybackState.paused));
    });

    test('transient focus preserves playing state', () {
      final state = BackgroundPlaybackConfig.playing(
        backgroundEnabled: true,
        isInForeground: true,
      );
      final after = state.updateAudioFocus(AudioFocusState.transient);
      expect(after.playbackState, equals(BackgroundPlaybackState.playing));
      expect(after.audioFocus, equals(AudioFocusState.transient));
    });

    test('transient focus keeps isAudioActive true', () {
      final state = BackgroundPlaybackConfig.playing(
        backgroundEnabled: true,
        isInForeground: true,
      );
      final after = state.updateAudioFocus(AudioFocusState.transient);
      expect(after.isAudioActive, isTrue);
    });

    test('focus transitions do not change backgroundEnabled or isInForeground',
        () {
      final state = BackgroundPlaybackConfig.playing(
        backgroundEnabled: true,
        isInForeground: false,
      );
      final after = state.updateAudioFocus(AudioFocusState.lost);
      expect(after.backgroundEnabled, isTrue);
      expect(after.isInForeground, isFalse);
    });

    // Notifier integration
    test('Notifier: onAudioFocusChange(lost) pauses playback', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(backgroundPlaybackProvider.notifier);

      notifier.startPlayback();
      notifier.onAudioFocusChange(AudioFocusState.lost);

      final state = container.read(backgroundPlaybackProvider);
      expect(state.playbackState, equals(BackgroundPlaybackState.paused));
      expect(state.audioFocus, equals(AudioFocusState.lost));
      expect(state.isAudioActive, isFalse);
    });

    test('Notifier: onAudioFocusChange(transient) keeps playing', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(backgroundPlaybackProvider.notifier);

      notifier.startPlayback();
      notifier.onAudioFocusChange(AudioFocusState.transient);

      final state = container.read(backgroundPlaybackProvider);
      expect(state.playbackState, equals(BackgroundPlaybackState.playing));
      expect(state.audioFocus, equals(AudioFocusState.transient));
    });

    test('Notifier: lost then gained stays paused', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(backgroundPlaybackProvider.notifier);

      notifier.startPlayback();
      notifier.onAudioFocusChange(AudioFocusState.lost);
      notifier.onAudioFocusChange(AudioFocusState.gained);

      final state = container.read(backgroundPlaybackProvider);
      expect(state.audioFocus, equals(AudioFocusState.gained));
      expect(state.playbackState, equals(BackgroundPlaybackState.paused));
    });
  });

  // ── REF-13-T03: Foreground/background lifecycle transitions ──────────────

  group('REF-13-T03: Lifecycle transitions', () {
    test('updateForeground(false) with backgroundEnabled keeps playing', () {
      final state = BackgroundPlaybackConfig.playing(
        backgroundEnabled: true,
        isInForeground: true,
      );
      final after = state.updateForeground(false);
      expect(after.playbackState, equals(BackgroundPlaybackState.playing));
      expect(after.isInForeground, isFalse);
    });

    test('updateForeground(true) restores isInForeground', () {
      final state = BackgroundPlaybackConfig.playing(
        backgroundEnabled: true,
        isInForeground: false,
      );
      final after = state.updateForeground(true);
      expect(after.isInForeground, isTrue);
      expect(after.playbackState, equals(BackgroundPlaybackState.playing));
    });

    test('updateForeground(false) with backgroundEnabled=false', () {
      final state = BackgroundPlaybackConfig.playing(
        backgroundEnabled: false,
        isInForeground: true,
      );
      final after = state.updateForeground(false);
      expect(after.isInForeground, isFalse);
      expect(after.backgroundEnabled, isFalse);
    });

    // computePlaybackStateAfterLifecycle
    test('computePlaybackStateAfterLifecycle: resumed sets foreground', () {
      final after = computePlaybackStateAfterLifecycle(
        newState: AppLifecycleState.resumed,
        backgroundEnabled: true,
        currentPlaybackState: BackgroundPlaybackState.playing,
      );
      expect(after.isInForeground, isTrue);
      expect(after.playbackState, equals(BackgroundPlaybackState.playing));
    });

    test('computePlaybackStateAfterLifecycle: paused keeps playing', () {
      final after = computePlaybackStateAfterLifecycle(
        newState: AppLifecycleState.paused,
        backgroundEnabled: true,
        currentPlaybackState: BackgroundPlaybackState.playing,
      );
      expect(after.isInForeground, isFalse);
      expect(after.playbackState, equals(BackgroundPlaybackState.playing));
    });

    test('computePlaybackStateAfterLifecycle: detached stops playback', () {
      final after = computePlaybackStateAfterLifecycle(
        newState: AppLifecycleState.detached,
        backgroundEnabled: true,
        currentPlaybackState: BackgroundPlaybackState.playing,
      );
      expect(after.playbackState, equals(BackgroundPlaybackState.stopped));
      expect(after.isInForeground, isFalse);
    });

    test('computePlaybackStateAfterLifecycle: hidden keeps playing', () {
      final after = computePlaybackStateAfterLifecycle(
        newState: AppLifecycleState.hidden,
        backgroundEnabled: true,
        currentPlaybackState: BackgroundPlaybackState.playing,
      );
      expect(after.isInForeground, isFalse);
      expect(after.playbackState, equals(BackgroundPlaybackState.playing));
    });

    test('computePlaybackStateAfterLifecycle: paused while paused stays paused',
        () {
      final after = computePlaybackStateAfterLifecycle(
        newState: AppLifecycleState.paused,
        backgroundEnabled: true,
        currentPlaybackState: BackgroundPlaybackState.paused,
      );
      expect(after.playbackState, equals(BackgroundPlaybackState.paused));
      expect(after.isInForeground, isFalse);
    });

    // shouldContinueInBackground
    test('shouldContinueInBackground: true when enabled and playing', () {
      expect(
        shouldContinueInBackground(
          backgroundEnabled: true,
          currentPlaybackState: BackgroundPlaybackState.playing,
        ),
        isTrue,
      );
    });

    test('shouldContinueInBackground: false when disabled', () {
      expect(
        shouldContinueInBackground(
          backgroundEnabled: false,
          currentPlaybackState: BackgroundPlaybackState.playing,
        ),
        isFalse,
      );
    });

    test('shouldContinueInBackground: false when paused', () {
      expect(
        shouldContinueInBackground(
          backgroundEnabled: true,
          currentPlaybackState: BackgroundPlaybackState.paused,
        ),
        isFalse,
      );
    });

    test('shouldContinueInBackground: false when stopped', () {
      expect(
        shouldContinueInBackground(
          backgroundEnabled: true,
          currentPlaybackState: BackgroundPlaybackState.stopped,
        ),
        isFalse,
      );
    });

    // Notifier integration
    test('Notifier: onAppLifecycleChange(paused) keeps playing', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(backgroundPlaybackProvider.notifier);

      notifier.startPlayback();
      notifier.onAppLifecycleChange(AppLifecycleState.paused);

      final state = container.read(backgroundPlaybackProvider);
      expect(state.playbackState, equals(BackgroundPlaybackState.playing));
      expect(state.isInForeground, isFalse);
    });

    test('Notifier: onAppLifecycleChange(resumed) restores foreground', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(backgroundPlaybackProvider.notifier);

      notifier.startPlayback();
      notifier.onAppLifecycleChange(AppLifecycleState.paused);
      notifier.onAppLifecycleChange(AppLifecycleState.resumed);

      final state = container.read(backgroundPlaybackProvider);
      expect(state.isInForeground, isTrue);
      expect(state.playbackState, equals(BackgroundPlaybackState.playing));
    });

    test('Notifier: onAppLifecycleChange(detached) stops playback', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(backgroundPlaybackProvider.notifier);

      notifier.startPlayback();
      notifier.onAppLifecycleChange(AppLifecycleState.detached);

      final state = container.read(backgroundPlaybackProvider);
      expect(state.playbackState, equals(BackgroundPlaybackState.stopped));
      expect(state.isInForeground, isFalse);
    });

    test('Notifier: full lifecycle sequence hidden->inactive->paused->resumed',
        () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(backgroundPlaybackProvider.notifier);

      notifier.startPlayback();

      notifier.onAppLifecycleChange(AppLifecycleState.hidden);
      expect(container.read(backgroundPlaybackProvider).isInForeground, isFalse);
      expect(container.read(backgroundPlaybackProvider).playbackState,
          equals(BackgroundPlaybackState.playing));

      notifier.onAppLifecycleChange(AppLifecycleState.inactive);
      expect(container.read(backgroundPlaybackProvider).isInForeground, isFalse);
      expect(container.read(backgroundPlaybackProvider).playbackState,
          equals(BackgroundPlaybackState.playing));

      notifier.onAppLifecycleChange(AppLifecycleState.paused);
      expect(container.read(backgroundPlaybackProvider).isInForeground, isFalse);
      expect(container.read(backgroundPlaybackProvider).playbackState,
          equals(BackgroundPlaybackState.playing));

      notifier.onAppLifecycleChange(AppLifecycleState.resumed);
      expect(container.read(backgroundPlaybackProvider).isInForeground, isTrue);
      expect(container.read(backgroundPlaybackProvider).playbackState,
          equals(BackgroundPlaybackState.playing));
    });
  });

  // ── REF-13-T04: isAudioActive / showPauseAction derived properties ───────

  group('REF-13-T04: Derived properties', () {
    test('isAudioActive is true when playing and focus is gained', () {
      final state = BackgroundPlaybackConfig.playing(
        backgroundEnabled: true,
        isInForeground: true,
        audioFocus: AudioFocusState.gained,
      );
      expect(state.isAudioActive, isTrue);
    });

    test('isAudioActive is true when playing and focus is transient', () {
      final state = BackgroundPlaybackConfig.playing(
        backgroundEnabled: true,
        isInForeground: true,
        audioFocus: AudioFocusState.transient,
      );
      expect(state.isAudioActive, isTrue);
    });

    test('isAudioActive is false when paused', () {
      final state = BackgroundPlaybackConfig.paused(
        backgroundEnabled: true,
        isInForeground: true,
      );
      expect(state.isAudioActive, isFalse);
    });

    test('isAudioActive is false when stopped', () {
      const state = BackgroundPlaybackConfig.initial;
      expect(state.isAudioActive, isFalse);
    });

    test('isAudioActive is false when focus is lost even if playing', () {
      final state = BackgroundPlaybackConfig.playing(
        backgroundEnabled: true,
        isInForeground: true,
        audioFocus: AudioFocusState.lost,
      );
      expect(state.isAudioActive, isFalse);
    });

    test('showPauseAction is true when playing', () {
      final state = BackgroundPlaybackConfig.playing(
        backgroundEnabled: true,
        isInForeground: true,
      );
      expect(state.showPauseAction, isTrue);
    });

    test('showPauseAction is false when paused', () {
      final state = BackgroundPlaybackConfig.paused(
        backgroundEnabled: true,
        isInForeground: true,
      );
      expect(state.showPauseAction, isFalse);
    });

    test('showPauseAction is false when stopped', () {
      const state = BackgroundPlaybackConfig.initial;
      expect(state.showPauseAction, isFalse);
    });

    test('showPlayAction is true when paused', () {
      final state = BackgroundPlaybackConfig.paused(
        backgroundEnabled: true,
        isInForeground: true,
      );
      expect(state.showPlayAction, isTrue);
    });

    test('showPlayAction is false when playing', () {
      final state = BackgroundPlaybackConfig.playing(
        backgroundEnabled: true,
        isInForeground: true,
      );
      expect(state.showPlayAction, isFalse);
    });

    test('showPlayAction is false when stopped', () {
      const state = BackgroundPlaybackConfig.initial;
      expect(state.showPlayAction, isFalse);
    });

    // Round-trip: playing -> pause -> check derived
    test('derived properties update after media control transitions', () {
      final playing = BackgroundPlaybackConfig.playing(
        backgroundEnabled: true,
        isInForeground: false,
      );
      expect(playing.isAudioActive, isTrue);
      expect(playing.showPauseAction, isTrue);
      expect(playing.showPlayAction, isFalse);

      final paused = playing.handleMediaControl(MediaControlAction.pause);
      expect(paused.isAudioActive, isFalse);
      expect(paused.showPauseAction, isFalse);
      expect(paused.showPlayAction, isTrue);

      final stopped = paused.handleMediaControl(MediaControlAction.stop);
      expect(stopped.isAudioActive, isFalse);
      expect(stopped.showPauseAction, isFalse);
      expect(stopped.showPlayAction, isFalse);
    });

    // Round-trip: focus loss -> check derived
    test('derived properties update after focus loss', () {
      final playing = BackgroundPlaybackConfig.playing(
        backgroundEnabled: true,
        isInForeground: false,
      );
      expect(playing.isAudioActive, isTrue);

      final lost = playing.updateAudioFocus(AudioFocusState.lost);
      expect(lost.isAudioActive, isFalse);
      expect(lost.showPauseAction, isFalse);
      expect(lost.showPlayAction, isTrue);
    });
  });

  // ── Supplementary: equality, copyWith, factories ─────────────────────────

  group('BackgroundPlaybackConfig equality and immutability', () {
    test('identical values are equal', () {
      final a = BackgroundPlaybackConfig.playing(
        backgroundEnabled: true,
        isInForeground: false,
      );
      final b = BackgroundPlaybackConfig.playing(
        backgroundEnabled: true,
        isInForeground: false,
      );
      expect(a, equals(b));
    });

    test('different properties are not equal', () {
      final playing = BackgroundPlaybackConfig.playing(
        backgroundEnabled: true,
        isInForeground: false,
      );
      final paused = BackgroundPlaybackConfig.paused(
        backgroundEnabled: true,
        isInForeground: false,
      );
      expect(playing, isNot(equals(paused)));
    });

    test('copyWith returns new instance with updated field', () {
      final original = BackgroundPlaybackConfig.playing(
        backgroundEnabled: true,
        isInForeground: true,
      );
      final updated = original.copyWith(isInForeground: false);
      expect(updated.isInForeground, isFalse);
      expect(updated.playbackState, equals(BackgroundPlaybackState.playing));
      expect(original.isInForeground, isTrue);
    });

    test('hashCode is consistent with equality', () {
      final a = BackgroundPlaybackConfig.playing(
        backgroundEnabled: true,
        isInForeground: false,
      );
      final b = BackgroundPlaybackConfig.playing(
        backgroundEnabled: true,
        isInForeground: false,
      );
      expect(a.hashCode, equals(b.hashCode));
    });

    test('initial factory returns correct defaults', () {
      const state = BackgroundPlaybackConfig.initial;
      expect(state.backgroundEnabled, isTrue);
      expect(state.isInForeground, isTrue);
      expect(state.audioFocus, equals(AudioFocusState.gained));
      expect(state.playbackState, equals(BackgroundPlaybackState.stopped));
    });

    test('playing factory sets playbackState to playing', () {
      final state = BackgroundPlaybackConfig.playing(
        backgroundEnabled: true,
        isInForeground: false,
      );
      expect(state.playbackState, equals(BackgroundPlaybackState.playing));
    });

    test('paused factory sets playbackState to paused', () {
      final state = BackgroundPlaybackConfig.paused(
        backgroundEnabled: false,
        isInForeground: true,
      );
      expect(state.playbackState, equals(BackgroundPlaybackState.paused));
      expect(state.backgroundEnabled, isFalse);
    });
  });

  group('BackgroundPlaybackNotifier basic operations', () {
    test('initial state is correct', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final state = container.read(backgroundPlaybackProvider);
      expect(state.backgroundEnabled, isTrue);
      expect(state.isInForeground, isTrue);
      expect(state.playbackState, equals(BackgroundPlaybackState.stopped));
      expect(state.audioFocus, equals(AudioFocusState.gained));
    });

    test('startPlayback, pausePlayback, stopPlayback transitions', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(backgroundPlaybackProvider.notifier);

      notifier.startPlayback();
      expect(container.read(backgroundPlaybackProvider).playbackState,
          equals(BackgroundPlaybackState.playing));

      notifier.pausePlayback();
      expect(container.read(backgroundPlaybackProvider).playbackState,
          equals(BackgroundPlaybackState.paused));

      notifier.stopPlayback();
      expect(container.read(backgroundPlaybackProvider).playbackState,
          equals(BackgroundPlaybackState.stopped));
    });

    test('setBackgroundEnabled toggles the flag', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(backgroundPlaybackProvider.notifier);

      expect(
          container.read(backgroundPlaybackProvider).backgroundEnabled, isTrue);
      notifier.setBackgroundEnabled(false);
      expect(container.read(backgroundPlaybackProvider).backgroundEnabled,
          isFalse);
      notifier.setBackgroundEnabled(true);
      expect(
          container.read(backgroundPlaybackProvider).backgroundEnabled, isTrue);
    });
  });

  group('Enum coverage', () {
    test('AudioFocusState has all expected values', () {
      expect(AudioFocusState.values.length, equals(3));
      expect(AudioFocusState.values, contains(AudioFocusState.gained));
      expect(AudioFocusState.values, contains(AudioFocusState.lost));
      expect(AudioFocusState.values, contains(AudioFocusState.transient));
    });

    test('BackgroundPlaybackState has all expected values', () {
      expect(BackgroundPlaybackState.values.length, equals(3));
      expect(BackgroundPlaybackState.values,
          contains(BackgroundPlaybackState.playing));
      expect(BackgroundPlaybackState.values,
          contains(BackgroundPlaybackState.paused));
      expect(BackgroundPlaybackState.values,
          contains(BackgroundPlaybackState.stopped));
    });

    test('MediaControlAction has all expected values', () {
      expect(MediaControlAction.values.length, equals(4));
      expect(MediaControlAction.values, contains(MediaControlAction.play));
      expect(MediaControlAction.values, contains(MediaControlAction.pause));
      expect(MediaControlAction.values, contains(MediaControlAction.stop));
      expect(MediaControlAction.values,
          contains(MediaControlAction.togglePlayPause));
    });
  });

  group('Zero platform dependency verification', () {
    test('all types are importable from domain path', () {
      // Verify that the domain file exports everything needed.
      // If this compiles, the domain file is self-contained.
      expect(AudioFocusState.gained, isNotNull);
      expect(BackgroundPlaybackState.playing, isNotNull);
      expect(MediaControlAction.play, isNotNull);
      expect(BackgroundPlaybackConfig.initial, isNotNull);
      expect(BackgroundPlaybackConfig.playing, isNotNull);
      expect(BackgroundPlaybackConfig.paused, isNotNull);
      expect(shouldContinueInBackground, isNotNull);
      expect(computePlaybackStateAfterLifecycle, isNotNull);
      expect(backgroundPlaybackProvider, isNotNull);
    });
  });
}
