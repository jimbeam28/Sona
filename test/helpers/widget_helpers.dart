// test/helpers/widget_helpers.dart
// Shared widget test wrapper functions extracted from multiple test files (REF-07).
//
// Provides common helpers for wrapping widgets in ProviderScope + MaterialApp,
// creating ProviderContainers with overrides, and player/timer-specific wrappers.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:just_audio/just_audio.dart';
import 'package:nas_audio_player/features/timer/domain/timer_service.dart';
import 'package:nas_audio_player/features/browser/browser_provider.dart';
import 'package:nas_audio_player/features/player/player_provider.dart';
import 'package:nas_audio_player/features/timer/timer_provider.dart';
import 'package:nas_audio_player/features/timer/widgets/timer_button.dart';
import 'package:nas_audio_player/shared/models/play_queue.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ── Generic wrappers ─────────────────────────────────────────────────────────

/// Wraps [child] in [ProviderScope] + [MaterialApp] + [Scaffold] with
/// optional [overrides].
///
/// The [Scaffold] wrapper ensures that Material widgets (ListTile, etc.)
/// inside [child] have a Material ancestor.
///
/// Use this for widget tests that do not need GoRouter navigation.
Widget buildTestApp(Widget child, {List<Override>? overrides}) {
  return ProviderScope(
    overrides: overrides ?? [],
    child: MaterialApp(home: Scaffold(body: child)),
  );
}

/// Wraps [child] in [ProviderScope] + [MaterialApp.router] with a single
/// route at `/` and optional [overrides].
///
/// Use this for widget tests that need basic GoRouter context (e.g. for
/// context.go / context.push calls inside the widget under test).
Widget buildTestAppWithRouter(Widget child, {List<Override>? overrides}) {
  final router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        builder: (_, __) => child,
      ),
    ],
  );
  return ProviderScope(
    overrides: overrides ?? [],
    child: MaterialApp.router(routerConfig: router),
  );
}

/// Wraps [child] in [ProviderScope] + [MaterialApp.router] with `/` and
/// `/player` routes plus optional [overrides].
///
/// Use this for widget tests that need a `/player` route destination (e.g.
/// navigation from mini player bar to player screen).
Widget buildTestAppWithPlayerRoute(Widget child, {List<Override>? overrides}) {
  final router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        builder: (_, __) => child,
      ),
      GoRoute(
        path: '/player',
        builder: (_, __) =>
            const Scaffold(body: Center(child: Text('Player'))),
      ),
    ],
  );
  return ProviderScope(
    overrides: overrides ?? [],
    child: MaterialApp.router(routerConfig: router),
  );
}

/// Creates a [ProviderContainer] with the given [overrides].
///
/// Use this for provider-level (non-widget) tests that need a container
/// with custom provider overrides.
ProviderContainer makeContainer(List<Override> overrides) {
  return ProviderContainer(overrides: overrides);
}

// ── Player-specific wrappers ─────────────────────────────────────────────────

/// Wraps [child] in a [ProviderScope] with player-specific overrides for
/// MiniPlayerBar tests.
///
/// Overrides [currentPlayQueueProvider], [audioPlayerProvider], and
/// [playModeProvider].
Widget wrapMiniPlayer({
  required PlayQueue? queue,
  required AudioPlayer player,
  required Widget child,
  PlayMode playMode = PlayMode.sequential,
}) {
  return ProviderScope(
    overrides: [
      currentPlayQueueProvider.overrideWith((ref) => queue),
      audioPlayerProvider.overrideWith((ref) => player),
      playModeProvider.overrideWith((ref) => playMode),
    ],
    child: MaterialApp(
      home: Scaffold(body: Column(children: [Expanded(child: child)])),
    ),
  );
}

/// Creates a [MaterialApp.router] wrapper with `/browser` and `/player`
/// routes for MiniPlayerBar navigation tests.
///
/// Overrides [currentPlayQueueProvider], [audioPlayerProvider], and
/// [playModeProvider] inside the `/browser` route.
Widget wrapWithRouter({
  required PlayQueue? queue,
  required AudioPlayer player,
  required Widget child,
  PlayMode playMode = PlayMode.sequential,
}) {
  final router = GoRouter(
    initialLocation: '/browser',
    routes: [
      GoRoute(
        path: '/browser',
        name: 'browser',
        builder: (context, state) => ProviderScope(
          overrides: [
            currentPlayQueueProvider.overrideWith((ref) => queue),
            audioPlayerProvider.overrideWith((ref) => player),
            playModeProvider.overrideWith((ref) => playMode),
          ],
          child: Scaffold(body: Column(children: [Expanded(child: child)])),
        ),
      ),
      GoRoute(
        path: '/player',
        name: 'player',
        builder: (context, state) => const Scaffold(
          body: Center(child: Text('Player Page')),
        ),
      ),
    ],
  );

  return MaterialApp.router(routerConfig: router);
}

// ── Timer-specific wrappers ──────────────────────────────────────────────────

/// Overrides that suppress the periodic [remainingTimeProvider] stream so
/// that widget tests (which run under [FakeAsync]) do not accumulate pending
/// periodic timers.
///
/// The stream logic is covered by the unit tests on [TimerService] directly.
List<Override> noopRemainingTimeOverride() => [
      remainingTimeProvider.overrideWith((ref) => Stream.value(null)),
    ];

/// Wraps [child] in a [ProviderScope] with a fresh [TimerService] and the
/// no-op remaining-time stream override.
Widget wrapWithTimerProviders(Widget child) {
  return ProviderScope(
    overrides: [
      timerServiceProvider.overrideWith((ref) => TimerService()),
      sharedPreferencesProvider.overrideWith((ref) => null),
      ...noopRemainingTimeOverride(),
    ],
    child: MaterialApp(
      home: Scaffold(body: child),
    ),
  );
}

/// Wraps [child] in a [ProviderScope] with a fresh [TimerService], the
/// no-op remaining-time stream override, and a specific [SharedPreferences]
/// instance.
Widget wrapWithTimerProvidersAndPrefs(
  Widget child, {
  SharedPreferences? prefs,
}) {
  return ProviderScope(
    overrides: [
      timerServiceProvider.overrideWith((ref) => TimerService()),
      sharedPreferencesProvider.overrideWith((ref) => prefs),
      ...noopRemainingTimeOverride(),
    ],
    child: MaterialApp(
      home: Scaffold(body: child),
    ),
  );
}

/// Creates a [ProviderContainer] suitable for timer provider-level tests,
/// with the no-op remaining-time stream override so no periodic timers
/// are created.
ProviderContainer createTimerTestContainer() {
  return ProviderContainer(
    overrides: [
      timerServiceProvider.overrideWith((ref) => TimerService()),
      ...noopRemainingTimeOverride(),
    ],
  );
}

/// Helper to pump a widget with timer providers.
Future<void> pumpTimerWidget(WidgetTester tester, Widget child) async {
  await tester.pumpWidget(wrapWithTimerProviders(child));
}

/// Returns the [ProviderContainer] from the nearest [ProviderScope] ancestor
/// of [TimerButton] in the widget tree.
ProviderContainer timerContainerOf(WidgetTester tester) {
  return ProviderScope.containerOf(tester.element(find.byType(TimerButton)));
}
