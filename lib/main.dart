// lib/main.dart
// Application entry point.
// Sets up ProviderScope (Riverpod) and go_router with an onboarding-aware
// initial route.
//
// Start-up logic:
//   • If no connections are saved → show onboarding splash, then AddConnection.
//   • If at least one connection exists → go straight to /connection (add form)
//     for CON-01 scope; Browser landing is wired for BRW-01.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'features/connection/connection_provider.dart';
import 'features/connection/connection_edit_screen.dart';
import 'features/connection/connection_list_screen.dart';
import 'features/connection/connection_screen.dart';
import 'features/browser/browser_screen.dart';
import 'features/player/player_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    const ProviderScope(
      child: NasAudioPlayerApp(),
    ),
  );
}

// ── Router ────────────────────────────────────────────────────────────────────

final _router = GoRouter(
  initialLocation: '/onboarding',
  routes: [
    GoRoute(
      path: '/onboarding',
      name: 'onboarding',
      builder: (context, state) => const _OnboardingPage(),
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
      builder: (context, state) => const BrowserScreen(),
    ),
    GoRoute(
      path: '/player',
      name: 'player',
      builder: (context, state) => const PlayerPlaceholder(),
    ),
  ],
);

// ── App ───────────────────────────────────────────────────────────────────────

class NasAudioPlayerApp extends StatelessWidget {
  const NasAudioPlayerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'NAS 音乐播放器',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      routerConfig: _router,
    );
  }
}

// ── Onboarding page ───────────────────────────────────────────────────────────
// Shown when the connection list is empty.
// While checking the DB it shows a loading indicator; once done either
// redirects to /browser (connections exist) or stays to show the CTA.

class _OnboardingPage extends ConsumerWidget {
  const _OnboardingPage();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final listAsync = ref.watch(connectionListProvider);

    return listAsync.when(
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (_, __) => _onboardingScaffold(context),
      data: (connections) {
        if (connections.isNotEmpty) {
          // Watch startup validation to trigger auto-validation (CON-T15 / CON-T16).
          // If validation fails (e.g. 401), redirect to /connection for reconfiguration
          // instead of /browser.
          final validationAsync = ref.watch(startupValidationProvider);
          // We need to let the validation resolve before deciding the redirect.
          return validationAsync.when(
            loading: () => const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            ),
            error: (_, __) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                context.go('/connection');
              });
              return const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              );
            },
            data: (result) {
              if (result != null && !result.isSuccess) {
                // CON-T16: validation failed — redirect to connection screen
                // so user can reconfigure. Pass the error message as extra.
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  context.go('/connection');
                });
                return const Scaffold(
                  body: Center(child: CircularProgressIndicator()),
                );
              }
              // CON-T15: validation succeeded (or no active connection) — go to browser
              WidgetsBinding.instance.addPostFrameCallback((_) {
                context.go('/browser');
              });
              return const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              );
            },
          );
        }
        return _onboardingScaffold(context);
      },
    );
  }

  Widget _onboardingScaffold(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.storage_outlined, size: 80, color: Colors.deepPurple),
                const SizedBox(height: 24),
                Text(
                  '添加第一个 NAS 连接',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(
                  '连接到您的 WebDAV 服务器，即可浏览并播放 NAS 上的音乐。',
                  style: Theme.of(context).textTheme.bodyMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),
                FilledButton.icon(
                  onPressed: () => context.go('/connection'),
                  icon: const Icon(Icons.add),
                  label: const Text('添加连接'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(200, 48),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
