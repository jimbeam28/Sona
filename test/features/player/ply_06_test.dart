// test/features/player/ply_06_test.dart
// PLY-06: 播放模式切换 — automated test suite
//
// Pure-logic tests (PLY-T38~T42, PLY-T61): default mode, mode cycling
// through all four modes, and icon-to-mode mapping.
//
// These tests exercise the playModeProvider and nextPlayModeProvider
// directly using a ProviderContainer, without AudioPlayer or widgets.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nas_audio_player/features/player/player_provider.dart';
import 'package:nas_audio_player/shared/models/play_queue.dart';

// ═════════════════════════════════════════════════════════════════════════════
// Unit tests — PLY-T38~T42, PLY-T61
// ═════════════════════════════════════════════════════════════════════════════

void main() {
  // ── PLY-T38: Default play mode ───────────────────────────────────────────────

  group('PLY-T38: Default play mode', () {
    test('default mode is PlayMode.sequential', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final mode = container.read(playModeProvider);
      expect(mode, equals(PlayMode.sequential),
          reason: '默认播放模式应为 sequential（顺序播放）');
    });
  });

  // ── PLY-T39: sequential → repeatOne ──────────────────────────────────────────

  group('PLY-T39: sequential → repeatOne', () {
    test('cycling once from sequential changes mode to repeatOne', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      // Start from the default
      expect(container.read(playModeProvider), equals(PlayMode.sequential));

      // Cycle once
      final next = container.read(nextPlayModeProvider)();
      expect(next, equals(PlayMode.repeatOne),
          reason: '从 sequential 切换一次应变为 repeatOne');
      expect(container.read(playModeProvider), equals(PlayMode.repeatOne),
          reason: 'provider 状态应更新为 repeatOne');
    });
  });

  // ── PLY-T40: repeatOne → repeatAll ───────────────────────────────────────────

  group('PLY-T40: repeatOne → repeatAll', () {
    test('cycling from repeatOne changes mode to repeatAll', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      // Set to repeatOne first
      container.read(playModeProvider.notifier).state = PlayMode.repeatOne;
      expect(container.read(playModeProvider), equals(PlayMode.repeatOne));

      // Cycle to next
      final next = container.read(nextPlayModeProvider)();
      expect(next, equals(PlayMode.repeatAll),
          reason: '从 repeatOne 切换应变为 repeatAll');
      expect(container.read(playModeProvider), equals(PlayMode.repeatAll),
          reason: 'provider 状态应更新为 repeatAll');
    });
  });

  // ── PLY-T41: repeatAll → shuffle ─────────────────────────────────────────────

  group('PLY-T41: repeatAll → shuffle', () {
    test('cycling from repeatAll changes mode to shuffle', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      // Set to repeatAll first
      container.read(playModeProvider.notifier).state = PlayMode.repeatAll;
      expect(container.read(playModeProvider), equals(PlayMode.repeatAll));

      // Cycle to next
      final next = container.read(nextPlayModeProvider)();
      expect(next, equals(PlayMode.shuffle),
          reason: '从 repeatAll 切换应变为 shuffle');
      expect(container.read(playModeProvider), equals(PlayMode.shuffle),
          reason: 'provider 状态应更新为 shuffle');
    });
  });

  // ── PLY-T42: shuffle → sequential ────────────────────────────────────────────

  group('PLY-T42: shuffle → sequential', () {
    test('cycling from shuffle wraps back to sequential', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      // Set to shuffle first
      container.read(playModeProvider.notifier).state = PlayMode.shuffle;
      expect(container.read(playModeProvider), equals(PlayMode.shuffle));

      // Cycle to next (should wrap to sequential)
      final next = container.read(nextPlayModeProvider)();
      expect(next, equals(PlayMode.sequential),
          reason: '从 shuffle 切换应回到 sequential（完整循环）');
      expect(container.read(playModeProvider), equals(PlayMode.sequential),
          reason: 'provider 状态应回到 sequential');
    });

    test(
        'full cycle: sequential → repeatOne → repeatAll → shuffle → sequential',
        () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final cycle = container.read(nextPlayModeProvider);
      final modes = <PlayMode>[];

      // Record a full cycle of 4 transitions
      for (int i = 0; i < 4; i++) {
        modes.add(cycle());
      }

      expect(
          modes,
          equals([
            PlayMode.repeatOne,
            PlayMode.repeatAll,
            PlayMode.shuffle,
            PlayMode.sequential,
          ]),
          reason: '完整循环应依次经过 repeatOne, repeatAll, shuffle, sequential');
    });
  });

  // ── PLY-T61: Play mode button icon matches current mode ──────────────────────

  group('PLY-T61: Play mode button icon matches current mode', () {
    test('sequential uses playlist_play icon', () {
      expect(
        iconForPlayMode(PlayMode.sequential),
        equals(Icons.playlist_play),
        reason: 'sequential 模式应使用 playlist_play 图标',
      );
    });

    test('repeatOne uses repeat_one icon', () {
      expect(
        iconForPlayMode(PlayMode.repeatOne),
        equals(Icons.repeat_one),
        reason: 'repeatOne 模式应使用 repeat_one 图标',
      );
    });

    test('repeatAll uses repeat icon', () {
      expect(
        iconForPlayMode(PlayMode.repeatAll),
        equals(Icons.repeat),
        reason: 'repeatAll 模式应使用 repeat 图标',
      );
    });

    test('shuffle uses shuffle icon', () {
      expect(
        iconForPlayMode(PlayMode.shuffle),
        equals(Icons.shuffle),
        reason: 'shuffle 模式应使用 shuffle 图标',
      );
    });

    test('all four mode icons are distinct', () {
      final icons = PlayMode.values.map(iconForPlayMode).toSet();
      expect(icons.length, equals(4), reason: '四种播放模式应各有不同的图标');
    });

    test('labelForMode returns distinct labels for each mode', () {
      final labels = PlayMode.values.map(labelForPlayMode).toSet();
      expect(labels.length, equals(4), reason: '四种播放模式应各有不同的标签文字');
    });
  });
}
