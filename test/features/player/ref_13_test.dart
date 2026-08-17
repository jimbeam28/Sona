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
//
// REF-03 (cr-20260816-0802 D1 裁决 A): Notifier 已缩为只读镜像（单入口
// syncFromHandler），驱动方法为死面删除——所有 notifier 驱动用例同步删除，
// 保留纯值对象 / 纯函数锚定。

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nas_audio_player/features/player/background_playback_notifier.dart';
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
        newState: AppLifecyclePhase.resumed,
        backgroundEnabled: true,
        currentPlaybackState: BackgroundPlaybackState.playing,
      );
      expect(after.isInForeground, isTrue);
      expect(after.playbackState, equals(BackgroundPlaybackState.playing));
    });

    test('computePlaybackStateAfterLifecycle: paused keeps playing', () {
      final after = computePlaybackStateAfterLifecycle(
        newState: AppLifecyclePhase.paused,
        backgroundEnabled: true,
        currentPlaybackState: BackgroundPlaybackState.playing,
      );
      expect(after.isInForeground, isFalse);
      expect(after.playbackState, equals(BackgroundPlaybackState.playing));
    });

    test('computePlaybackStateAfterLifecycle: detached stops playback', () {
      final after = computePlaybackStateAfterLifecycle(
        newState: AppLifecyclePhase.detached,
        backgroundEnabled: true,
        currentPlaybackState: BackgroundPlaybackState.playing,
      );
      expect(after.playbackState, equals(BackgroundPlaybackState.stopped));
      expect(after.isInForeground, isFalse);
    });

    test('computePlaybackStateAfterLifecycle: hidden keeps playing', () {
      final after = computePlaybackStateAfterLifecycle(
        newState: AppLifecyclePhase.hidden,
        backgroundEnabled: true,
        currentPlaybackState: BackgroundPlaybackState.playing,
      );
      expect(after.isInForeground, isFalse);
      expect(after.playbackState, equals(BackgroundPlaybackState.playing));
    });

    test('computePlaybackStateAfterLifecycle: paused while paused stays paused',
        () {
      final after = computePlaybackStateAfterLifecycle(
        newState: AppLifecyclePhase.paused,
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
    // REF-03: startPlayback / pausePlayback / stopPlayback /
    // setBackgroundEnabled 为死面驱动方法，已删除，对应测试同步删除。
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
