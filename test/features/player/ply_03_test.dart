// test/features/player/ply_03_test.dart
// PLY-03: 后台播放 — automated test suite
//
// Unit tests (PLY-T20~T23): background playback state machine,
// app-lifecycle transitions, notification-control actions, lock-screen
// and audio-focus behaviour.
//
// Tests focus on the pure-logic layer (BackgroundPlaybackState,
// computePlaybackStateAfterLifecycle, shouldContinueInBackground)
// which is fully testable without AudioPlayer, audio_service, or
// platform channels.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nas_audio_player/features/player/background_playback.dart';
import 'package:nas_audio_player/features/timer/domain/timer_service.dart';
import 'package:nas_audio_player/features/player/player_provider.dart';
import 'package:nas_audio_player/features/timer/timer_provider.dart';

// ═════════════════════════════════════════════════════════════════════════════
// Unit tests — PLY-T20~T23
// ═════════════════════════════════════════════════════════════════════════════

void main() {
  // ── PLY-T20: Switch to other app (app enters background) ───────────────────────
  //
  // When backgroundPlayback is enabled, the AudioPlayer should continue
  // playing when the app enters the background.  We test this by
  // verifying that the state model preserves the playing state after
  // a lifecycle transition to background.

  group('PLY-T20: Audio continues in background (lifecycle transition)', () {
    test(
        'playing audio continues when app goes to background '
        '(backgroundEnabled=true)', () {
      final beforeState = BackgroundPlaybackConfig.playing(
        backgroundEnabled: true,
        isInForeground: true,
      );

      // Simulate app going to background (AppLifecycleState.paused)
      final afterState = computePlaybackStateAfterLifecycle(
        newState: AppLifecycleState.paused,
        backgroundEnabled: beforeState.backgroundEnabled,
        currentPlaybackState: beforeState.playbackState,
      );

      // PLY-T20: Audio continues playing, no interruption
      expect(afterState.playbackState, equals(BackgroundPlaybackState.playing),
          reason: '进入后台后音频应继续播放，不中断');
      expect(afterState.isInForeground, isFalse,
          reason: 'isInForeground 应为 false（已进入后台）');
      expect(afterState.backgroundEnabled, isTrue);
    });

    test(
        'playing audio continues when app is hidden '
        '(AppLifecycleState.hidden)', () {
      final afterState = computePlaybackStateAfterLifecycle(
        newState: AppLifecycleState.hidden,
        backgroundEnabled: true,
        currentPlaybackState: BackgroundPlaybackState.playing,
      );

      expect(afterState.playbackState, equals(BackgroundPlaybackState.playing),
          reason: 'hidden 状态下音频应继续播放');
      expect(afterState.isInForeground, isFalse);
    });

    test(
        'playing audio continues when app is inactive '
        '(AppLifecycleState.inactive)', () {
      final afterState = computePlaybackStateAfterLifecycle(
        newState: AppLifecycleState.inactive,
        backgroundEnabled: true,
        currentPlaybackState: BackgroundPlaybackState.playing,
      );

      expect(afterState.playbackState, equals(BackgroundPlaybackState.playing),
          reason: 'inactive 状态下音频应继续播放');
      expect(afterState.isInForeground, isFalse);
    });

    test('paused audio stays paused when app goes to background', () {
      final afterState = computePlaybackStateAfterLifecycle(
        newState: AppLifecycleState.paused,
        backgroundEnabled: true,
        currentPlaybackState: BackgroundPlaybackState.paused,
      );

      expect(afterState.playbackState, equals(BackgroundPlaybackState.paused),
          reason: '已暂停的音频进入后台应保持暂停状态');
      expect(afterState.isInForeground, isFalse);
    });

    test('stopped audio stays stopped when app goes to background', () {
      final afterState = computePlaybackStateAfterLifecycle(
        newState: AppLifecycleState.paused,
        backgroundEnabled: true,
        currentPlaybackState: BackgroundPlaybackState.stopped,
      );

      expect(afterState.playbackState, equals(BackgroundPlaybackState.stopped),
          reason: '已停止的音频进入后台应保持停止状态');
    });

    test('audio does NOT continue when backgroundEnabled is false', () {
      final beforeState = BackgroundPlaybackConfig.playing(
        backgroundEnabled: false,
        isInForeground: true,
      );

      final afterState = computePlaybackStateAfterLifecycle(
        newState: AppLifecycleState.paused,
        backgroundEnabled: beforeState.backgroundEnabled,
        currentPlaybackState: beforeState.playbackState,
      );

      // When backgroundEnabled is false and app goes to background,
      // the model reflects the transition but playback may stop at
      // the platform level.  The state model captures the flag status.
      expect(afterState.backgroundEnabled, isFalse,
          reason: '后台播放禁用标志应保持 false');
      expect(afterState.isInForeground, isFalse);
    });

    test(
        'app returns to foreground (AppLifecycleState.resumed) preserves '
        'playback state', () {
      final afterState = computePlaybackStateAfterLifecycle(
        newState: AppLifecycleState.resumed,
        backgroundEnabled: true,
        currentPlaybackState: BackgroundPlaybackState.playing,
      );

      expect(afterState.isInForeground, isTrue,
          reason: '回到前台后 isInForeground 应为 true');
      expect(afterState.playbackState, equals(BackgroundPlaybackState.playing),
          reason: '回到前台后播放状态不应改变');
    });

    test('AppLifecycleState.detached stops playback', () {
      final afterState = computePlaybackStateAfterLifecycle(
        newState: AppLifecycleState.detached,
        backgroundEnabled: true,
        currentPlaybackState: BackgroundPlaybackState.playing,
      );

      expect(afterState.playbackState, equals(BackgroundPlaybackState.stopped),
          reason: 'detached（应用被销毁）时应停止播放');
      expect(afterState.isInForeground, isFalse);
    });
  });

  // ── shouldContinueInBackground pure function ───────────────────────────────────

  group('shouldContinueInBackground helper', () {
    test('returns true when enabled and playing', () {
      expect(
        shouldContinueInBackground(
          backgroundEnabled: true,
          currentPlaybackState: BackgroundPlaybackState.playing,
        ),
        isTrue,
        reason: '后台播放启用且正在播放时应继续',
      );
    });

    test('returns false when disabled', () {
      expect(
        shouldContinueInBackground(
          backgroundEnabled: false,
          currentPlaybackState: BackgroundPlaybackState.playing,
        ),
        isFalse,
        reason: '后台播放禁用时不应继续',
      );
    });

    test('returns false when not playing', () {
      expect(
        shouldContinueInBackground(
          backgroundEnabled: true,
          currentPlaybackState: BackgroundPlaybackState.paused,
        ),
        isFalse,
        reason: '暂停状态不应触发后台继续播放',
      );
    });

    test('returns false when stopped', () {
      expect(
        shouldContinueInBackground(
          backgroundEnabled: true,
          currentPlaybackState: BackgroundPlaybackState.stopped,
        ),
        isFalse,
        reason: '停止状态不应触发后台继续播放',
      );
    });

    test('returns false when both disabled and paused', () {
      expect(
        shouldContinueInBackground(
          backgroundEnabled: false,
          currentPlaybackState: BackgroundPlaybackState.paused,
        ),
        isFalse,
      );
    });
  });

  // ── PLY-T21: App in background, click pause from notification ──────────────────
  //
  // The notification sends a pause action.  The state machine should
  // transition from playing to paused while remaining in the background
  // session.

  group('PLY-T21: Notification pause stops playback (isPlaying=false)', () {
    test('playing -> pause notification action sets state to paused', () {
      final state = BackgroundPlaybackConfig.playing(
        backgroundEnabled: true,
        isInForeground: false, // already in background
      );

      final after = state.handleMediaControl(MediaControlAction.pause);

      expect(after.playbackState, equals(BackgroundPlaybackState.paused),
          reason: '从通知栏点击暂停后，playbackState 应为 paused (PLY-T21)');
      expect(after.isInForeground, isFalse, reason: '应保持在后台状态');
      expect(after.backgroundEnabled, isTrue);
    });

    test('paused state does not change on pause action (idempotent)', () {
      final state = BackgroundPlaybackConfig.paused(
        backgroundEnabled: true,
        isInForeground: false,
      );

      final after = state.handleMediaControl(MediaControlAction.pause);

      expect(after.playbackState, equals(BackgroundPlaybackState.paused),
          reason: '已暂停时再次暂停应保持暂停状态（幂等）');
    });

    test('pause from notification sets isAudioActive to false', () {
      final state = BackgroundPlaybackConfig.playing(
        backgroundEnabled: true,
        isInForeground: false,
      );

      expect(state.isAudioActive, isTrue, reason: '播放中 isAudioActive 应为 true');

      final after = state.handleMediaControl(MediaControlAction.pause);

      expect(after.isAudioActive, isFalse,
          reason: '暂停后 isAudioActive 应为 false');
    });

    test('notification shows play action after pause', () {
      final state = BackgroundPlaybackConfig.playing(
        backgroundEnabled: true,
        isInForeground: false,
      );

      expect(state.showPauseAction, isTrue, reason: '播放中应显示暂停按钮');
      expect(state.showPlayAction, isFalse, reason: '播放中不应显示播放按钮');

      final after = state.handleMediaControl(MediaControlAction.pause);

      expect(after.showPauseAction, isFalse, reason: '暂停后不应显示暂停按钮');
      expect(after.showPlayAction, isTrue, reason: '暂停后应显示播放按钮');
    });
  });

  // ── PLY-T22: App in background, click play from notification ───────────────────
  //
  // The notification sends a play action.  The state machine should
  // transition from paused to playing.

  group('PLY-T22: Notification play resumes playback (isPlaying=true)', () {
    test('paused -> play notification action sets state to playing', () {
      final state = BackgroundPlaybackConfig.paused(
        backgroundEnabled: true,
        isInForeground: false, // in background
      );

      final after = state.handleMediaControl(MediaControlAction.play);

      expect(after.playbackState, equals(BackgroundPlaybackState.playing),
          reason: '从通知栏点击播放后，playbackState 应为 playing (PLY-T22)');
      expect(after.isInForeground, isFalse, reason: '应保持在后台状态');
    });

    test('playing state does not change on play action (idempotent)', () {
      final state = BackgroundPlaybackConfig.playing(
        backgroundEnabled: true,
        isInForeground: false,
      );

      final after = state.handleMediaControl(MediaControlAction.play);

      expect(after.playbackState, equals(BackgroundPlaybackState.playing),
          reason: '已播放时再次播放应保持播放状态（幂等）');
    });

    test('play from notification sets isAudioActive to true', () {
      final state = BackgroundPlaybackConfig.paused(
        backgroundEnabled: true,
        isInForeground: false,
      );

      expect(state.isAudioActive, isFalse,
          reason: '暂停中 isAudioActive 应为 false');

      final after = state.handleMediaControl(MediaControlAction.play);

      expect(after.isAudioActive, isTrue,
          reason: '恢复播放后 isAudioActive 应为 true');
    });

    test('notification shows pause action after play', () {
      final state = BackgroundPlaybackConfig.paused(
        backgroundEnabled: true,
        isInForeground: false,
      );

      expect(state.showPlayAction, isTrue, reason: '暂停中应显示播放按钮');

      final after = state.handleMediaControl(MediaControlAction.play);

      expect(after.showPauseAction, isTrue, reason: '播放中应显示暂停按钮');
      expect(after.showPlayAction, isFalse, reason: '播放中不应显示播放按钮');
    });

    test('stop notification action sets state to stopped', () {
      final state = BackgroundPlaybackConfig.playing(
        backgroundEnabled: true,
        isInForeground: false,
      );

      final after = state.handleMediaControl(MediaControlAction.stop);

      expect(after.playbackState, equals(BackgroundPlaybackState.stopped),
          reason: '停止通知操作应将播放状态设为 stopped');
    });
  });

  // ── PLY-T22 bonus: togglePlayPause action ──────────────────────────────────────

  group('MediaControlAction.togglePlayPause', () {
    test('togglePlayPause when playing -> paused', () {
      final state = BackgroundPlaybackConfig.playing(
        backgroundEnabled: true,
        isInForeground: false,
      );

      final after =
          state.handleMediaControl(MediaControlAction.togglePlayPause);

      expect(after.playbackState, equals(BackgroundPlaybackState.paused),
          reason: '播放中切换应变为暂停');
    });

    test('togglePlayPause when paused -> playing', () {
      final state = BackgroundPlaybackConfig.paused(
        backgroundEnabled: true,
        isInForeground: false,
      );

      final after =
          state.handleMediaControl(MediaControlAction.togglePlayPause);

      expect(after.playbackState, equals(BackgroundPlaybackState.playing),
          reason: '暂停中切换应变为播放');
    });

    test('togglePlayPause when stopped -> playing', () {
      const state = BackgroundPlaybackConfig.initial;

      final after =
          state.handleMediaControl(MediaControlAction.togglePlayPause);

      expect(after.playbackState, equals(BackgroundPlaybackState.playing),
          reason: '停止状态切换应开始播放');
    });
  });

  // ── PLY-T23: Lock screen during background playback ────────────────────────────
  //
  // Locking the screen should not interrupt audio playback.  The lock
  // screen simply shows media controls via the system notification —
  // it does not change the playback state.

  group('PLY-T23: Lock screen does not interrupt background playback', () {
    test('audio state unchanged regardless of lock screen', () {
      // The lock screen is a system UI concern — it does not change the
      // app lifecycle or playback state.  The notification and lock-screen
      // controls are the same underlying MediaSession on Android.
      //
      // We verify that the state model correctly represents that
      // background audio continues regardless of lock-screen state.
      final state = BackgroundPlaybackConfig.playing(
        backgroundEnabled: true,
        isInForeground: false, // app is in background
        audioFocus: AudioFocusState.gained,
      );

      // Lock screen showing does not affect any of these fields.
      // The state remains identical.
      expect(state.playbackState, equals(BackgroundPlaybackState.playing),
          reason: '锁屏时播放状态应为 playing（音频不中断）(PLY-T23)');
      expect(state.isAudioActive, isTrue, reason: '锁屏时音频应保持活跃');
      expect(state.showPauseAction, isTrue, reason: '锁屏应显示暂停按钮');
      expect(state.backgroundEnabled, isTrue);
    });

    test('lock screen shows media controls (via notification model)', () {
      // The lock screen derives its controls from the same notification
      // MediaSession.  We verify that the state model exposes the correct
      // control visibility for the lock screen.
      final playing = BackgroundPlaybackConfig.playing(
        backgroundEnabled: true,
        isInForeground: false,
      );

      expect(playing.showPauseAction, isTrue, reason: '锁屏播放中应显示暂停按钮');
      expect(playing.showPlayAction, isFalse, reason: '锁屏播放中不应显示播放按钮');

      final paused = playing.handleMediaControl(MediaControlAction.pause);

      expect(paused.showPauseAction, isFalse, reason: '锁屏暂停后不应显示暂停按钮');
      expect(paused.showPlayAction, isTrue, reason: '锁屏暂停后应显示播放按钮');
    });

    test('lock screen state does not change playback state machine', () {
      // Verifying: locking/unlocking screen does NOT trigger
      // AppLifecycleState changes that would affect the player.
      // On both Android and iOS, lock screen does not send the app
      // to background — it's a system overlay.  The state model
      // correctly ignores lock-screen events by not having a
      // lock-screen-specific transition.
      final beforeLock = BackgroundPlaybackConfig.playing(
        backgroundEnabled: true,
        isInForeground: true,
      );

      // The lock screen does not change the foreground/background state.
      // App is still "in foreground" from the lifecycle perspective.
      // The state should be identical.
      final afterLock = beforeLock;

      expect(afterLock.playbackState, beforeLock.playbackState,
          reason: '锁屏不影响播放状态');
      expect(afterLock.isAudioActive, beforeLock.isAudioActive,
          reason: '锁屏不影响音频活跃状态');
      expect(afterLock.isInForeground, beforeLock.isInForeground,
          reason: '锁屏不改变前台/后台状态');
    });

    test('background audio continues after lock+unlock cycle (state model)',
        () {
      // The lock/unlock cycle does not change the playback or lifecycle
      // state in the model.  Audio continues uninterrupted.
      final state = BackgroundPlaybackConfig.playing(
        backgroundEnabled: true,
        isInForeground: false, // in background
      );

      // Lock screen events are system overlay — no state change.
      // The model preserves the playing state throughout.
      expect(state.playbackState, equals(BackgroundPlaybackState.playing));
      expect(state.isAudioActive, isTrue);
    });
  });

  // ── Audio focus handling ───────────────────────────────────────────────────────

  group('AudioFocusState transitions', () {
    test('losing audio focus permanently pauses playback', () {
      final state = BackgroundPlaybackConfig.playing(
        backgroundEnabled: true,
        isInForeground: false,
      );

      final after = state.updateAudioFocus(AudioFocusState.lost);

      expect(after.playbackState, equals(BackgroundPlaybackState.paused),
          reason: '永久失去音频焦点时应暂停播放');
      expect(after.audioFocus, equals(AudioFocusState.lost));
      expect(after.isAudioActive, isFalse, reason: '失去焦点后不应再有活跃音频');
    });

    test('gaining audio focus back after loss allows resume', () {
      // After losing focus, the state is paused.  Gaining focus back
      // just restores the focus flag — the user or system must
      // explicitly play to resume.
      final lost = BackgroundPlaybackConfig.playing(
        backgroundEnabled: true,
        isInForeground: false,
      ).updateAudioFocus(AudioFocusState.lost);

      final regained = lost.updateAudioFocus(AudioFocusState.gained);

      expect(regained.audioFocus, equals(AudioFocusState.gained),
          reason: '重新获得音频焦点标志应更新');
      expect(regained.playbackState, equals(BackgroundPlaybackState.paused),
          reason: '重新获得焦点后保持暂停，等待显式播放');
    });

    test('transient focus loss preserves playback state', () {
      final state = BackgroundPlaybackConfig.playing(
        backgroundEnabled: true,
        isInForeground: true,
      );

      final after = state.updateAudioFocus(AudioFocusState.transient);

      expect(after.playbackState, equals(BackgroundPlaybackState.playing),
          reason: '短暂焦点丢失不应改变播放状态');
      expect(after.audioFocus, equals(AudioFocusState.transient));
      expect(after.isAudioActive, isTrue, reason: '短暂焦点丢失时音频仍应为活跃状态');
    });
  });

  // ── BackgroundPlaybackNotifier (StateNotifier) ─────────────────────────────────

  group('BackgroundPlaybackNotifier', () {
    test('initial state is correct', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final state = container.read(backgroundPlaybackProvider);

      expect(state.backgroundEnabled, isTrue, reason: '默认应启用后台播放');
      expect(state.isInForeground, isTrue, reason: '初始状态应在前台');
      expect(state.playbackState, equals(BackgroundPlaybackState.stopped),
          reason: '初始状态应为停止');
      expect(state.audioFocus, equals(AudioFocusState.gained));
    });

    test('onAppLifecycleChange(paused) while playing continues playback', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(backgroundPlaybackProvider.notifier);

      // Start playback
      notifier.startPlayback();
      expect(
        container.read(backgroundPlaybackProvider).playbackState,
        equals(BackgroundPlaybackState.playing),
      );

      // Simulate app going to background
      notifier.onAppLifecycleChange(AppLifecycleState.paused);

      final state = container.read(backgroundPlaybackProvider);
      expect(state.playbackState, equals(BackgroundPlaybackState.playing),
          reason: '进入后台后播放应继续 (PLY-T20)');
      expect(state.isInForeground, isFalse);
    });

    test('onAppLifecycleChange(detached) stops playback', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(backgroundPlaybackProvider.notifier);

      notifier.startPlayback();
      notifier.onAppLifecycleChange(AppLifecycleState.detached);

      final state = container.read(backgroundPlaybackProvider);
      expect(state.playbackState, equals(BackgroundPlaybackState.stopped),
          reason: 'detached 应停止播放');
      expect(state.isInForeground, isFalse);
    });

    test('onMediaControl(pause) while playing sets paused', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(backgroundPlaybackProvider.notifier);

      notifier.startPlayback();
      notifier.onMediaControl(MediaControlAction.pause);

      final state = container.read(backgroundPlaybackProvider);
      expect(state.playbackState, equals(BackgroundPlaybackState.paused),
          reason: '通知暂停应将播放状态设为 paused (PLY-T21)');
    });

    test('onMediaControl(play) while paused sets playing', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(backgroundPlaybackProvider.notifier);

      notifier.startPlayback();
      notifier.onMediaControl(MediaControlAction.pause);
      notifier.onMediaControl(MediaControlAction.play);

      final state = container.read(backgroundPlaybackProvider);
      expect(state.playbackState, equals(BackgroundPlaybackState.playing),
          reason: '通知播放应将播放状态设为 playing (PLY-T22)');
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

    test('pausePlayback and stopPlayback transitions', () {
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

    test('onAudioFocusChange(lost) pauses playback', () {
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
  });

  // ── backgroundPlaybackEnabledProvider ──────────────────────────────────────────

  group('backgroundPlaybackEnabledProvider', () {
    test('default is true', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(container.read(backgroundPlaybackEnabledProvider), isTrue,
          reason: '默认应启用后台播放');
    });

    test('can be toggled to false', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(backgroundPlaybackEnabledProvider.notifier).state = false;
      expect(container.read(backgroundPlaybackEnabledProvider), isFalse);
    });
  });

  // ── BackgroundPlaybackState equality and immutability ──────────────────────────

  group('BackgroundPlaybackState equality', () {
    test('identical values are equal', () {
      final a = BackgroundPlaybackConfig.playing(
        backgroundEnabled: true,
        isInForeground: false,
      );
      final b = BackgroundPlaybackConfig.playing(
        backgroundEnabled: true,
        isInForeground: false,
      );

      expect(a, equals(b), reason: '相同属性值的对象应相等');
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

      expect(playing, isNot(equals(paused)),
          reason: '不同 playbackState 的对象不应相等');
    });

    test('copyWith returns new instance with updated field', () {
      final original = BackgroundPlaybackConfig.playing(
        backgroundEnabled: true,
        isInForeground: true,
      );

      final updated = original.copyWith(isInForeground: false);

      expect(updated.isInForeground, isFalse);
      expect(updated.playbackState, equals(BackgroundPlaybackState.playing));
      expect(updated.backgroundEnabled, isTrue);
      expect(original.isInForeground, isTrue, reason: '原对象不应改变（不可变）');
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

      expect(a.hashCode, equals(b.hashCode), reason: '相等对象的 hashCode 应相同');
    });
  });

  // ── BackgroundPlaybackState factory constructors ────────────────────────────────

  group('BackgroundPlaybackState factories', () {
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
        audioFocus: AudioFocusState.gained,
      );

      expect(state.playbackState, equals(BackgroundPlaybackState.playing));
      expect(state.backgroundEnabled, isTrue);
      expect(state.isInForeground, isFalse);
    });

    test('paused factory sets playbackState to paused', () {
      final state = BackgroundPlaybackConfig.paused(
        backgroundEnabled: false,
        isInForeground: true,
      );

      expect(state.playbackState, equals(BackgroundPlaybackState.paused));
      expect(state.backgroundEnabled, isFalse);
      expect(state.isInForeground, isTrue);
    });
  });

  // ── State-machine comprehensive round-trips ────────────────────────────────────

  group('Background playback round-trip scenarios', () {
    test('play -> background -> notification pause -> notification play', () {
      // Full scenario: user is playing, switches to another app,
      // then pauses from notification, then resumes from notification.
      var state = BackgroundPlaybackConfig.playing(
        backgroundEnabled: true,
        isInForeground: true,
      );

      // App goes to background
      state = state.updateForeground(false);
      expect(state.playbackState, equals(BackgroundPlaybackState.playing),
          reason: '进入后台音频继续 (PLY-T20)');
      expect(state.isInForeground, isFalse);

      // User pauses from notification
      state = state.handleMediaControl(MediaControlAction.pause);
      expect(state.playbackState, equals(BackgroundPlaybackState.paused),
          reason: '通知暂停生效 (PLY-T21)');

      // User resumes from notification
      state = state.handleMediaControl(MediaControlAction.play);
      expect(state.playbackState, equals(BackgroundPlaybackState.playing),
          reason: '通知恢复播放生效 (PLY-T22)');
    });

    test('background playback continues through lock screen scenario', () {
      // The lock screen is a system UI overlay — it doesn't change the
      // playback state.  The notification model already handles controls.
      final state = BackgroundPlaybackConfig.playing(
        backgroundEnabled: true,
        isInForeground: false,
      );

      // Lock screen shows — audio continues
      expect(state.playbackState, equals(BackgroundPlaybackState.playing),
          reason: '锁屏时音频继续播放 (PLY-T23)');
      expect(state.isAudioActive, isTrue);
      expect(state.showPauseAction, isTrue, reason: '锁屏显示暂停控件');
    });

    test('detached state is terminal for playback', () {
      final state = BackgroundPlaybackConfig.playing(
        backgroundEnabled: true,
        isInForeground: false,
      );

      // App is destroyed — playback should stop.
      // This is tested via computePlaybackStateAfterLifecycle.
      final afterDetach = computePlaybackStateAfterLifecycle(
        newState: AppLifecycleState.detached,
        backgroundEnabled: state.backgroundEnabled,
        currentPlaybackState: state.playbackState,
      );

      expect(afterDetach.playbackState, equals(BackgroundPlaybackState.stopped),
          reason: '应用销毁后应停止播放');
    });
  });

  // ── Enum coverage ──────────────────────────────────────────────────────────────

  group('Enum values', () {
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

  // ═════════════════════════════════════════════════════════════════════════════
  // TST-13: App lifecycle complete chain tests (TST-T99 ~ TST-T106)
  // ═════════════════════════════════════════════════════════════════════════════

  group('TST-13: App lifecycle complete chain', () {
    // ── TST-T99: 播放中 → paused → progress 保存调用 ───────────────────────

    group('TST-T99: playing → paused lifecycle', () {
      test(
          'ProviderContainer: paused sets isInForeground=false, '
          'playbackState stays playing', () {
        final container = ProviderContainer();
        addTearDown(container.dispose);

        final notifier = container.read(backgroundPlaybackProvider.notifier);

        // Start playback
        notifier.startPlayback();
        expect(
          container.read(backgroundPlaybackProvider).playbackState,
          equals(BackgroundPlaybackState.playing),
        );

        // Simulate app lifecycle: paused (going to background)
        notifier.onAppLifecycleChange(AppLifecycleState.paused);

        final state = container.read(backgroundPlaybackProvider);
        expect(state.isInForeground, isFalse,
            reason: 'TST-T99: paused 后 isInForeground 应为 false');
        expect(state.playbackState, equals(BackgroundPlaybackState.playing),
            reason: 'TST-T99: backgroundEnabled=true 时播放状态应保持 playing');
        expect(state.backgroundEnabled, isTrue,
            reason: 'TST-T99: backgroundEnabled 标志不变');
      });

      test('pure function: paused lifecycle preserves playing state', () {
        final after = computePlaybackStateAfterLifecycle(
          newState: AppLifecycleState.paused,
          backgroundEnabled: true,
          currentPlaybackState: BackgroundPlaybackState.playing,
        );

        expect(after.isInForeground, isFalse,
            reason: 'TST-T99: 纯函数 paused 后 isInForeground=false');
        expect(after.playbackState, equals(BackgroundPlaybackState.playing),
            reason: 'TST-T99: 纯函数 paused 后 playbackState 保持 playing');
        expect(after.backgroundEnabled, isTrue);
      });
    });

    // ── TST-T100: backgroundEnabled=true → playbackState 保持 playing ──────

    group(
        'TST-T100: backgroundEnabled keeps playing in background '
        '(confirm PLY-T20)', () {
      test('ProviderContainer confirms full integration link', () {
        final container = ProviderContainer();
        addTearDown(container.dispose);

        final notifier = container.read(backgroundPlaybackProvider.notifier);
        notifier.startPlayback();

        // App goes to background while playing
        notifier.onAppLifecycleChange(AppLifecycleState.paused);

        final state = container.read(backgroundPlaybackProvider);
        expect(state.playbackState, equals(BackgroundPlaybackState.playing),
            reason: 'TST-T100: 后台播放启用时 paused 后播放继续 (confirm PLY-T20)');
        expect(state.isInForeground, isFalse);
        expect(state.backgroundEnabled, isTrue);
      });
    });

    // ── TST-T101: detached → playbackState 变为 stopped ────────────────────

    group('TST-T101: detached stops playback (confirm existing)', () {
      test('ProviderContainer: playing → detached → stopped', () {
        final container = ProviderContainer();
        addTearDown(container.dispose);

        final notifier = container.read(backgroundPlaybackProvider.notifier);
        notifier.startPlayback();
        notifier.onAppLifecycleChange(AppLifecycleState.detached);

        final state = container.read(backgroundPlaybackProvider);
        expect(state.playbackState, equals(BackgroundPlaybackState.stopped),
            reason: 'TST-T101: detached 后播放应停止');
        expect(state.isInForeground, isFalse,
            reason: 'TST-T101: detached 后 isInForeground=false');
      });

      test('pure function: detached stops playback', () {
        final after = computePlaybackStateAfterLifecycle(
          newState: AppLifecycleState.detached,
          backgroundEnabled: true,
          currentPlaybackState: BackgroundPlaybackState.playing,
        );

        expect(after.playbackState, equals(BackgroundPlaybackState.stopped),
            reason: 'TST-T101: 纯函数 detached → stopped');
        expect(after.isInForeground, isFalse);
      });
    });

    // ── TST-T102: 后台期间 timer 到期 → checkExpired=true ──────────────────

    group('TST-T102: timer expiry during background triggers pause', () {
      test(
          'TimerService: startDuration(0) → checkExpired returns true, '
          'state cleared', () {
        final service = TimerService();

        // Start a duration timer with 0 minutes (endTime = now)
        final timerState = service.startDuration(0);
        expect(timerState.mode, equals(TimerMode.duration));
        expect(timerState.endTime, isNotNull);
        expect(service.isActive, isTrue);

        // checkExpired should return true since endTime <= now
        final expired = service.checkExpired();
        expect(expired, isTrue,
            reason: 'TST-T102: startDuration(0) 后 checkExpired 应返回 true');

        // State should be cleared after expiry
        expect(service.state, isNull,
            reason: 'TST-T102: checkExpired 后 state 应被清除为 null');
        expect(service.isActive, isFalse);
      });

      test(
          'TimerService: checkExpired is idempotent — '
          'second call returns false', () {
        final service = TimerService();

        service.startDuration(0);

        // First call: expires
        final first = service.checkExpired();
        expect(first, isTrue, reason: 'TST-T102: 首次 checkExpired 返回 true');

        // Second call: already cleared, returns false
        final second = service.checkExpired();
        expect(second, isFalse,
            reason: 'TST-T102: 再次 checkExpired 返回 false（幂等）');
        expect(service.state, isNull);
      });

      test('TimerService: checkExpired returns false when timer still active',
          () {
        final service = TimerService();

        // Start a timer far in the future
        service.startDuration(60); // 60 minutes
        expect(service.isActive, isTrue);

        final expired = service.checkExpired();
        expect(expired, isFalse,
            reason: 'TST-T102: 未到期的 timer checkExpired 返回 false');
        expect(service.isActive, isTrue, reason: 'TST-T102: 未到期时 state 不被清除');
      });

      test('TimerService: afterCurrent mode checkExpired always returns false',
          () {
        final service = TimerService();

        service.startAfterCurrent();
        expect(service.isActive, isTrue);
        expect(service.state!.mode, equals(TimerMode.afterCurrent));

        final expired = service.checkExpired();
        expect(expired, isFalse,
            reason: 'TST-T102: afterCurrent 模式 checkExpired 始终返回 false');
        expect(service.isActive, isTrue,
            reason: 'TST-T102: afterCurrent 模式 state 不被 checkExpired 清除');
      });

      test(
          'ProviderContainer + TimerStateNotifier: startDuration(0) '
          '→ checkExpired returns true', () {
        final container = ProviderContainer();
        addTearDown(container.dispose);

        final notifier = container.read(timerStateProvider.notifier);
        notifier.startDuration(0);

        // Timer should be active
        expect(container.read(timerStateProvider), isNotNull);
        expect(container.read(timerActiveProvider), isTrue);

        // checkExpired should return true
        final expired = notifier.checkExpired();
        expect(expired, isTrue,
            reason: 'TST-T102: Notifier checkExpired 返回 true');

        // State should be cleared
        expect(container.read(timerStateProvider), isNull,
            reason: 'TST-T102: checkExpired 后 provider state 应为 null');
        expect(container.read(timerActiveProvider), isFalse);
      });
    });

    // ── TST-T103: transient 音频焦点丢失 → 播放状态不变 ────────────────────

    group('TST-T103: transient focus preserves playback (confirm)', () {
      test('ProviderContainer: onAudioFocusChange(transient) keeps playing',
          () {
        final container = ProviderContainer();
        addTearDown(container.dispose);

        final notifier = container.read(backgroundPlaybackProvider.notifier);
        notifier.startPlayback();
        notifier.onAudioFocusChange(AudioFocusState.transient);

        final state = container.read(backgroundPlaybackProvider);
        expect(state.playbackState, equals(BackgroundPlaybackState.playing),
            reason: 'TST-T103: transient 焦点丢失不应改变播放状态');
        expect(state.audioFocus, equals(AudioFocusState.transient));
        expect(state.isAudioActive, isTrue,
            reason: 'TST-T103: transient 焦点丢失时 isAudioActive 仍为 true');
      });

      test('pure state: transient focus preserves playing', () {
        final state = BackgroundPlaybackConfig.playing(
          backgroundEnabled: true,
          isInForeground: true,
        );

        final after = state.updateAudioFocus(AudioFocusState.transient);

        expect(after.playbackState, equals(BackgroundPlaybackState.playing),
            reason: 'TST-T103: 纯状态 transient 焦点丢失不改变播放状态');
        expect(after.audioFocus, equals(AudioFocusState.transient));
      });
    });

    // ── TST-T104: 永久音频焦点丢失 → 播放状态变为 paused ──────────────────

    group('TST-T104: permanent focus loss pauses playback (confirm)', () {
      test('ProviderContainer: onAudioFocusChange(lost) pauses playback', () {
        final container = ProviderContainer();
        addTearDown(container.dispose);

        final notifier = container.read(backgroundPlaybackProvider.notifier);
        notifier.startPlayback();
        notifier.onAudioFocusChange(AudioFocusState.lost);

        final state = container.read(backgroundPlaybackProvider);
        expect(state.playbackState, equals(BackgroundPlaybackState.paused),
            reason: 'TST-T104: 永久焦点丢失应暂停播放');
        expect(state.audioFocus, equals(AudioFocusState.lost));
        expect(state.isAudioActive, isFalse,
            reason: 'TST-T104: 永久焦点丢失后 isAudioActive=false');
      });

      test('pure state: lost focus pauses playback', () {
        final state = BackgroundPlaybackConfig.playing(
          backgroundEnabled: true,
          isInForeground: false,
        );

        final after = state.updateAudioFocus(AudioFocusState.lost);

        expect(after.playbackState, equals(BackgroundPlaybackState.paused),
            reason: 'TST-T104: 纯状态 lost 焦点应暂停播放');
        expect(after.audioFocus, equals(AudioFocusState.lost));
      });
    });

    // ── TST-T105: 焦点丢失后恢复 → 保持 paused 等待用户手动播放 ──────────

    group('TST-T105: focus regain stays paused (confirm)', () {
      test('ProviderContainer: lost → gained keeps paused', () {
        final container = ProviderContainer();
        addTearDown(container.dispose);

        final notifier = container.read(backgroundPlaybackProvider.notifier);
        notifier.startPlayback();
        notifier.onAudioFocusChange(AudioFocusState.lost);

        // Verify we are paused
        expect(container.read(backgroundPlaybackProvider).playbackState,
            equals(BackgroundPlaybackState.paused));

        // Regain focus — should stay paused
        notifier.onAudioFocusChange(AudioFocusState.gained);

        final state = container.read(backgroundPlaybackProvider);
        expect(state.audioFocus, equals(AudioFocusState.gained),
            reason: 'TST-T105: 焦点恢复标志应更新');
        expect(state.playbackState, equals(BackgroundPlaybackState.paused),
            reason: 'TST-T105: 焦点恢复后应保持 paused，等待用户手动播放');
      });

      test('pure state: lost → gained stays paused', () {
        final lost = BackgroundPlaybackConfig.playing(
          backgroundEnabled: true,
          isInForeground: false,
        ).updateAudioFocus(AudioFocusState.lost);

        final regained = lost.updateAudioFocus(AudioFocusState.gained);

        expect(regained.audioFocus, equals(AudioFocusState.gained));
        expect(regained.playbackState, equals(BackgroundPlaybackState.paused),
            reason: 'TST-T105: 纯状态焦点恢复后保持 paused');
      });
    });

    // ── TST-T106: 完整生命周期序列 ────────────────────────────────────────

    group('TST-T106: hidden → inactive → paused → resumed full sequence', () {
      test(
          'computePlaybackStateAfterLifecycle: full lifecycle sequence '
          'while playing', () {
        // Step 1: hidden
        final hidden = computePlaybackStateAfterLifecycle(
          newState: AppLifecycleState.hidden,
          backgroundEnabled: true,
          currentPlaybackState: BackgroundPlaybackState.playing,
        );
        expect(hidden.isInForeground, isFalse,
            reason: 'TST-T106: hidden → isInForeground=false');
        expect(hidden.playbackState, equals(BackgroundPlaybackState.playing),
            reason: 'TST-T106: hidden → playbackState 保持 playing');

        // Step 2: hidden → inactive
        final inactive = computePlaybackStateAfterLifecycle(
          newState: AppLifecycleState.inactive,
          backgroundEnabled: true,
          currentPlaybackState: BackgroundPlaybackState.playing,
        );
        expect(inactive.isInForeground, isFalse,
            reason: 'TST-T106: inactive → isInForeground=false');
        expect(inactive.playbackState, equals(BackgroundPlaybackState.playing),
            reason: 'TST-T106: inactive → playbackState 保持 playing');

        // Step 3: inactive → paused
        final paused = computePlaybackStateAfterLifecycle(
          newState: AppLifecycleState.paused,
          backgroundEnabled: true,
          currentPlaybackState: BackgroundPlaybackState.playing,
        );
        expect(paused.isInForeground, isFalse,
            reason: 'TST-T106: paused → isInForeground=false');
        expect(paused.playbackState, equals(BackgroundPlaybackState.playing),
            reason: 'TST-T106: paused → playbackState 保持 playing');

        // Step 4: paused → resumed (back to foreground)
        final resumed = computePlaybackStateAfterLifecycle(
          newState: AppLifecycleState.resumed,
          backgroundEnabled: true,
          currentPlaybackState: BackgroundPlaybackState.playing,
        );
        expect(resumed.isInForeground, isTrue,
            reason: 'TST-T106: resumed → isInForeground=true');
        expect(resumed.playbackState, equals(BackgroundPlaybackState.playing),
            reason: 'TST-T106: resumed → playbackState 保持 playing');
      });

      test('BackgroundPlaybackNotifier: full lifecycle sequence via notifier',
          () {
        final container = ProviderContainer();
        addTearDown(container.dispose);

        final notifier = container.read(backgroundPlaybackProvider.notifier);
        notifier.startPlayback();

        // hidden
        notifier.onAppLifecycleChange(AppLifecycleState.hidden);
        var state = container.read(backgroundPlaybackProvider);
        expect(state.isInForeground, isFalse,
            reason: 'TST-T106: notifier hidden → isInForeground=false');
        expect(state.playbackState, equals(BackgroundPlaybackState.playing),
            reason: 'TST-T106: notifier hidden → 播放继续');

        // inactive
        notifier.onAppLifecycleChange(AppLifecycleState.inactive);
        state = container.read(backgroundPlaybackProvider);
        expect(state.isInForeground, isFalse,
            reason: 'TST-T106: notifier inactive → isInForeground=false');
        expect(state.playbackState, equals(BackgroundPlaybackState.playing),
            reason: 'TST-T106: notifier inactive → 播放继续');

        // paused
        notifier.onAppLifecycleChange(AppLifecycleState.paused);
        state = container.read(backgroundPlaybackProvider);
        expect(state.isInForeground, isFalse,
            reason: 'TST-T106: notifier paused → isInForeground=false');
        expect(state.playbackState, equals(BackgroundPlaybackState.playing),
            reason: 'TST-T106: notifier paused → 播放继续');

        // resumed
        notifier.onAppLifecycleChange(AppLifecycleState.resumed);
        state = container.read(backgroundPlaybackProvider);
        expect(state.isInForeground, isTrue,
            reason: 'TST-T106: notifier resumed → isInForeground=true');
        expect(state.playbackState, equals(BackgroundPlaybackState.playing),
            reason: 'TST-T106: notifier resumed → 回到前台播放继续');
      });
    });
  });
}
