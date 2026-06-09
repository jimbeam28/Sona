// lib/features/settings/about_screen.dart
// About page (SET-05).
//
// Displays the app name, version, and open-source license information.

import 'package:flutter/material.dart';

/// The app version string displayed on the About page.
const appVersion = '1.0.0';

/// The app name displayed on the About page.
const appName = 'NAS 音乐播放器';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('关于'),
        centerTitle: true,
      ),
      body: ListView(
        children: [
          const SizedBox(height: 32),

          // App icon and name
          Center(
            child: Icon(
              Icons.music_note_outlined,
              size: 72,
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(height: 16),
          Center(
            child: Text(
              appName,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Center(
            child: Text(
              '版本 $appVersion',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),

          const SizedBox(height: 32),
          const Divider(),

          // Open-source licenses
          const _SectionHeader(title: '开源许可'),
          const LicenseListTile(
            packageName: 'Flutter',
            packageDescription:
                'Google\'s UI toolkit for building natively compiled applications.',
          ),
          const LicenseListTile(
            packageName: 'just_audio',
            packageDescription: 'Feature-rich audio player for Flutter.',
          ),
          const LicenseListTile(
            packageName: 'flutter_riverpod',
            packageDescription: 'Reactive state-management library.',
          ),
          const LicenseListTile(
            packageName: 'go_router',
            packageDescription: 'Declarative routing package for Flutter.',
          ),
          const LicenseListTile(
            packageName: 'shared_preferences',
            packageDescription: 'Persistent key-value store for simple data.',
          ),
          const LicenseListTile(
            packageName: 'webdav_client',
            packageDescription: 'WebDAV client for Dart.',
          ),
          const LicenseListTile(
            packageName: 'sqflite',
            packageDescription: 'SQLite plugin for Flutter.',
          ),
          const LicenseListTile(
            packageName: 'audio_service',
            packageDescription: 'Background audio playback service.',
          ),

          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;

  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }
}

class LicenseListTile extends StatelessWidget {
  final String packageName;
  final String packageDescription;

  const LicenseListTile({
    super.key,
    required this.packageName,
    required this.packageDescription,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const Icon(Icons.code),
      title: Text(packageName),
      subtitle: Text(
        packageDescription,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      onTap: () {
        showLicensePage(
          context: context,
          applicationName: appName,
          applicationVersion: appVersion,
        );
      },
    );
  }
}
