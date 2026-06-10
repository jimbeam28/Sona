// lib/app/router.dart
// Application-level GoRouter definition.
// All route declarations live here; main.dart only calls createRouter().

import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';

import '../features/connection/connection_edit_screen.dart';
import '../features/connection/connection_list_screen.dart';
import '../features/connection/connection_screen.dart';
import '../features/home/home_screen.dart';
import '../features/playlist/playlist_detail_screen.dart';
import '../features/player/player_screen.dart';
import '../features/settings/settings_screen.dart';
import '../features/settings/about_screen.dart';
import '../features/settings/log_viewer_screen.dart';
import 'onboarding.dart';

GoRouter createRouter() => GoRouter(
      initialLocation: '/onboarding',
      routes: [
        GoRoute(
          path: '/onboarding',
          name: 'onboarding',
          builder: (context, state) => const OnboardingPage(),
        ),
        GoRoute(
          path: '/connection',
          name: 'connection',
          builder: (context, state) => const ConnectionScreen(),
        ),
        GoRoute(
          path: '/connections',
          name: 'connections',
          builder: (context, state) => const ConnectionListScreen(),
        ),
        GoRoute(
          path: '/connections/edit/:id',
          name: 'connection-edit',
          builder: (context, state) {
            final id = int.parse(state.pathParameters['id']!);
            return ConnectionEditScreen(connectionId: id);
          },
        ),
        GoRoute(
          path: '/browser',
          name: 'browser',
          builder: (context, state) => const HomeScreen(),
        ),
        GoRoute(
          path: '/playlist/:id',
          name: 'playlist-detail',
          builder: (context, state) {
            final id = int.parse(state.pathParameters['id']!);
            return PlaylistDetailScreen(playlistId: id);
          },
        ),
        GoRoute(
          path: '/player',
          name: 'player',
          builder: (context, state) => const PlayerScreen(),
        ),
        GoRoute(
          path: '/settings',
          name: 'settings',
          builder: (context, state) => const SettingsScreen(),
        ),
        GoRoute(
          path: '/about',
          name: 'about',
          builder: (context, state) => const AboutScreen(),
        ),
        if (kDebugMode)
          GoRoute(
            path: '/logs',
            name: 'logs',
            builder: (context, state) => const LogViewerScreen(),
          ),
      ],
    );
