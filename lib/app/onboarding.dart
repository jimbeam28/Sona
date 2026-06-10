// lib/app/onboarding.dart
// Onboarding page shown when the connection list is empty.
// While checking the DB it shows a loading indicator; once done either
// redirects to /browser (connections exist) or stays to show the CTA.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/connection/connection_provider.dart';
import '../features/player/player_provider.dart';

class OnboardingPage extends ConsumerWidget {
  const OnboardingPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final listAsync = ref.watch(connectionListProvider);

    return listAsync.when(
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      // CON-07: show error page with retry instead of silent fallthrough to CTA
      error: (error, _) => OnboardingErrorView(
        message: '无法读取连接列表：$error',
        onRetry: () => ref.invalidate(connectionListProvider),
      ),
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
              // A-2: restore persisted queue, then patch in the latest
              // saved playback position for the current track.
              // Triggered in post-frame callback to avoid Riverpod assertion:
              // providers must not modify other providers during their build.
              WidgetsBinding.instance.addPostFrameCallback((_) {
                ref.read(restoreStartupProgressProvider);
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
                const Icon(Icons.storage_outlined,
                    size: 80, color: Colors.deepPurple),
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

class OnboardingErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const OnboardingErrorView({
    super.key,
    required this.message,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.error_outline,
                    size: 64, color: Theme.of(context).colorScheme.error),
                const SizedBox(height: 16),
                Text(
                  '数据加载失败',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  message,
                  style: Theme.of(context).textTheme.bodyMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh),
                  label: const Text('重试'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
