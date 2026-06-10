// lib/main.dart
// Application entry point.
// Sets up ProviderScope (Riverpod) overrides and launches NasAudioPlayerApp.
//
// Start-up logic:
//   • If no connections are saved → show onboarding splash, then AddConnection.
//   • If at least one connection exists → auto-validate → redirect to browser
//     or connection screen depending on validation result.

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app/app.dart';
import 'core/services/audio_handler.dart';
import 'core/services/log_buffer.dart';
import 'features/browser/browser_provider.dart';
import 'features/player/player_provider.dart';

NasAudioHandler? _audioHandler;

void main() async {
  debugPrint('[Init] app starting');
  WidgetsFlutterBinding.ensureInitialized();
  installLogBufferHook();
  final prefs = await SharedPreferences.getInstance();
  final audioPlayer = AudioPlayer(useProxyForRequestHeaders: false);

  // Initialise the audio service.  On some devices / Android versions this
  // may fail — the app still works without background-playback support.
  try {
    debugPrint('[Init] AudioService.init starting...');
    _audioHandler = await AudioService.init(
      builder: () => NasAudioHandler(audioPlayer),
      config: const AudioServiceConfig(
        androidNotificationChannelId: 'com.example.nas_audio_player.channel',
        androidNotificationChannelName: 'NAS 音乐播放器',
        androidNotificationOngoing: true,
        androidStopForegroundOnPause: true,
      ),
    );
    debugPrint('[Init] AudioService.init succeeded');
  } catch (e) {
    // The error is logged but the app continues — playback still works via
    // just_audio; only lock-screen / notification controls are missing.
    debugPrint('[Init] AudioService.init failed: $e');
    _audioHandler = null;
  }
  debugPrint('[Init] ready, running app');

  runApp(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWith((ref) => prefs),
        audioPlayerProvider.overrideWith((ref) {
          // G-1: clean up both the player and the audio handler on dispose.
          ref.onDispose(() {
            _audioHandler?.dispose();
            audioPlayer.dispose();
          });
          return audioPlayer;
        }),
        audioHandlerProvider.overrideWith((ref) => _audioHandler),
      ],
      child: const NasAudioPlayerApp(),
    ),
  );
}
