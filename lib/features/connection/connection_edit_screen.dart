// lib/features/connection/connection_edit_screen.dart
// CON-05: Edit an existing connection's configuration.
//
// Flow:
//   User arrives from connection list (long-press / popup menu "编辑")
//   → form pre-filled with existing values (password left blank)
//   → "测试连接" validates with current field values
//   → "保存" checks if credentials changed
//     ↳ if URL/username/basePath changed or password provided → validation required
//     ↳ if only display name changed → save directly without re-validation
//   → On save: updates DB + secure storage → pops back to list

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/network/webdav_client.dart';
import '../../shared/models/connection_config.dart';
import 'connection_provider.dart';
import 'widgets/connection_form.dart';

class ConnectionEditScreen extends ConsumerStatefulWidget {
  final int connectionId;

  const ConnectionEditScreen({super.key, required this.connectionId});

  @override
  ConsumerState<ConnectionEditScreen> createState() =>
      _ConnectionEditScreenState();
}

class _ConnectionEditScreenState extends ConsumerState<ConnectionEditScreen> {
  final _formController = ConnectionFormController();
  bool _isSaving = false;
  ConnectionConfig? _originalConfig;

  @override
  void initState() {
    super.initState();
    // After the first frame, capture the original config so we can detect
    // field changes at save time.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _captureOriginalIfNeeded();
    });
  }

  void _captureOriginalIfNeeded() {
    if (_originalConfig != null) return;
    final connections = ref.read(connectionListProvider).valueOrNull;
    if (connections == null) return;
    final match =
        connections.where((c) => c.id == widget.connectionId).firstOrNull;
    if (match != null) {
      _originalConfig = match;
    }
  }

  @override
  Widget build(BuildContext context) {
    final listAsync = ref.watch(connectionListProvider);
    final validationState = ref.watch(connectionValidatorProvider);
    final isValidating = validationState is ValidationLoading;

    return Scaffold(
      appBar: AppBar(
        title: const Text('编辑连接'),
        centerTitle: true,
      ),
      body: listAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              '加载失败：$error',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        ),
        data: (connections) {
          final connection = connections
              .where((c) => c.id == widget.connectionId)
              .firstOrNull;
          if (connection == null) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline,
                      size: 48, color: Colors.grey),
                  const SizedBox(height: 16),
                  Text(
                    '连接不存在',
                    style: TextStyle(
                        fontSize: 16, color: Colors.grey.shade600),
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: () => context.pop(),
                    child: const Text('返回'),
                  ),
                ],
              ),
            );
          }

          // CON-04: _originalConfig is captured in addPostFrameCallback,
          // not here — avoids ambiguous dual-path capture semantics.
          return SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ConnectionForm(
                    controller: _formController,
                    initialUrl: connection.url,
                    initialUsername: connection.username,
                    initialName: connection.name,
                    initialBasePath: connection.basePath,
                    passwordRequired: false,
                    onFieldChanged: _onFieldChanged,
                  ),
                  const SizedBox(height: 24),

                  // Validation result banner
                  _ValidationBanner(state: validationState),
                  if (validationState is! ValidationIdle)
                    const SizedBox(height: 16),

                  // "测试连接" button
                  ElevatedButton.icon(
                    onPressed:
                        isValidating || _isSaving ? null : _onTestConnection,
                    icon: isValidating
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.wifi_find_outlined),
                    label: Text(isValidating ? '连接中…' : '测试连接'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // "保存" button
                  FilledButton.icon(
                    onPressed: (_canSave(validationState) && !_isSaving)
                        ? _onSave
                        : null,
                    icon: _isSaving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.save_outlined),
                    label: Text(_isSaving ? '保存中…' : '保存'),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // ── Field-change handler ────────────────────────────────────────────────────

  void _onFieldChanged() {
    // Reset the validator whenever a credential-related field changes.
    // This ensures the user cannot rely on a stale validation result after
    // modifying URL, username, password, or basePath.
    if (!mounted) return;
    final validator = ref.read(connectionValidatorProvider.notifier);
    validator.reset();
  }

  // ── Validation-gate logic ───────────────────────────────────────────────────

  /// Returns true when the user modified a field that affects connectivity
  /// (URL, username, basePath, or password) and therefore must re-validate
  /// before saving.
  bool _needsValidation() {
    if (_originalConfig == null) return true; // safety net
    if (!_formController.isAttached) return false;
    return _formController.url != _originalConfig!.url ||
        _formController.username != _originalConfig!.username ||
        _formController.basePath != _originalConfig!.basePath ||
        _formController.password.isNotEmpty;
  }

  /// Returns true when the save button should be enabled.
  bool _canSave(ConnectionValidationState validationState) {
    if (_needsValidation()) {
      return validationState is ValidationSuccess;
    }
    // Only the display name changed — no validation required (CON-T30).
    return true;
  }

  // ── Handlers ────────────────────────────────────────────────────────────────

  Future<void> _onTestConnection() async {
    if (!_formController.validate()) return;

    final validator = ref.read(connectionValidatorProvider.notifier);
    await validator.validate(
      url: _formController.url,
      username: _formController.username,
      password: _formController.password,
      basePath: _formController.basePath,
    );
  }

  Future<void> _onSave() async {
    if (!_formController.validate()) return;

    // CON-T28: block save when credentials changed but not re-validated
    if (_needsValidation()) {
      final validationState = ref.read(connectionValidatorProvider);
      if (validationState is! ValidationSuccess) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('请先测试连接后再保存'),
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
          );
        }
        return;
      }
    }

    setState(() => _isSaving = true);
    try {
      final updater = ref.read(connectionUpdaterProvider);

      // Determine display name: use user input or fall back to hostname
      final rawName = _formController.displayName;
      final effectiveName = rawName.isNotEmpty
          ? rawName
          : ConnectionConfig.hostnameFromUrl(_formController.url);

      // Normalise URL before saving
      final normalisedUrl = normaliseWebDavUrl(_formController.url);

      final config = _originalConfig!.copyWith(
        name: effectiveName,
        url: normalisedUrl,
        username: _formController.username,
        basePath: _formController.basePath,
      );

      await updater.update(
        config: config,
        password:
            _formController.password.isNotEmpty ? _formController.password : null,
      );

      // Invalidate dependent providers so they reload
      ref.invalidate(activeConnectionProvider);
      ref.invalidate(connectionListProvider);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('连接已更新'),
            behavior: SnackBarBehavior.floating,
            duration: Duration(seconds: 2),
          ),
        );
        context.pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('保存失败：$e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }
}

// ── Validation banner widget ──────────────────────────────────────────────────

class _ValidationBanner extends StatelessWidget {
  final ConnectionValidationState state;

  const _ValidationBanner({required this.state});

  @override
  Widget build(BuildContext context) {
    if (state is ValidationIdle) return const SizedBox.shrink();

    if (state is ValidationSuccess) {
      return _Banner(
        icon: Icons.check_circle_outline,
        message: '连接成功！',
        backgroundColor: Colors.green.shade50,
        foregroundColor: Colors.green.shade800,
        iconColor: Colors.green,
      );
    }

    if (state is ValidationError) {
      return _Banner(
        icon: Icons.error_outline,
        message: (state as ValidationError).message,
        backgroundColor: Colors.red.shade50,
        foregroundColor: Colors.red.shade900,
        iconColor: Colors.red,
      );
    }

    // Loading — no banner shown (button already shows spinner)
    return const SizedBox.shrink();
  }
}

class _Banner extends StatelessWidget {
  final IconData icon;
  final String message;
  final Color backgroundColor;
  final Color foregroundColor;
  final Color iconColor;

  const _Banner({
    required this.icon,
    required this.message,
    required this.backgroundColor,
    required this.foregroundColor,
    required this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(icon, color: iconColor, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: foregroundColor, fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }
}
