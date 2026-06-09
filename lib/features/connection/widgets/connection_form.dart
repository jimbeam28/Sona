// lib/features/connection/widgets/connection_form.dart
// Stateful form widget for WebDAV connection input fields.
// Exposes a [ConnectionFormController] so the parent screen can read values
// and trigger validation without coupling the form internals.

import 'package:flutter/material.dart';
import '../../../shared/models/connection_config.dart';
import '../domain/connection_validator.dart';

// ── Form controller (passed down from screen) ─────────────────────────────────

class ConnectionFormController {
  late _ConnectionFormState _state;
  bool _isAttached = false;

  void _attach(_ConnectionFormState state) {
    _state = state;
    _isAttached = true;
  }

  void _detach() => _isAttached = false;

  // CON-05: use an explicit flag instead of catching LateInitializationError.
  bool get isAttached => _isAttached;

  String get url => _state._urlController.text.trim();
  String get username => _state._usernameController.text.trim();
  String get password => _state._passwordController.text;
  String get displayName => _state._nameController.text.trim();
  String get basePath {
    final v = _state._basePathController.text.trim();
    return v.isEmpty ? '/' : v;
  }

  bool validate() => _state._formKey.currentState?.validate() ?? false;

  /// Resets all text fields to empty.
  void clear() {
    _state._urlController.clear();
    _state._usernameController.clear();
    _state._passwordController.clear();
    _state._nameController.clear();
    _state._basePathController.text = '/';
  }

  void dispose() {} // lifecycle managed by the State
}

// ── Form widget ───────────────────────────────────────────────────────────────

class ConnectionForm extends StatefulWidget {
  final ConnectionFormController controller;
  final String? initialUrl;
  final String? initialUsername;
  final String? initialPassword;
  final String? initialName;
  final String? initialBasePath;
  final bool passwordRequired;
  final VoidCallback? onFieldChanged;

  const ConnectionForm({
    super.key,
    required this.controller,
    this.initialUrl,
    this.initialUsername,
    this.initialPassword,
    this.initialName,
    this.initialBasePath,
    this.passwordRequired = true,
    this.onFieldChanged,
  });

  @override
  State<ConnectionForm> createState() => _ConnectionFormState();
}

class _ConnectionFormState extends State<ConnectionForm> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _urlController;
  late final TextEditingController _usernameController;
  late final TextEditingController _passwordController;
  late final TextEditingController _nameController;
  late final TextEditingController _basePathController;

  bool _obscurePassword = true;

  @override
  void initState() {
    super.initState();
    _urlController = TextEditingController(text: widget.initialUrl);
    _usernameController = TextEditingController(text: widget.initialUsername);
    _passwordController = TextEditingController(text: widget.initialPassword);
    _nameController = TextEditingController(text: widget.initialName);
    _basePathController =
        TextEditingController(text: widget.initialBasePath ?? '/');

    widget.controller._attach(this);

    // Auto-fill display name from URL hostname when user leaves URL field
    _urlController.addListener(_onUrlChanged);

    // Notify parent on field changes (used by edit screen to reset validator)
    if (widget.onFieldChanged != null) {
      _urlController.addListener(widget.onFieldChanged!);
      _usernameController.addListener(widget.onFieldChanged!);
      _passwordController.addListener(widget.onFieldChanged!);
      _basePathController.addListener(widget.onFieldChanged!);
    }
  }

  // CON-06: auto-fill display name from URL hostname on every URL change,
  // not just on focus lost — so users who type a URL then tap test/save
  // without leaving the field still get the name auto-filled.
  void _onUrlChanged() {
    if (_nameController.text.isEmpty) {
      final raw = _urlController.text.trim();
      if (raw.isNotEmpty) {
        final hostname = ConnectionConfig.hostnameFromUrl(raw);
        if (hostname.isNotEmpty && hostname != raw) {
          _nameController.text = hostname;
        }
      }
    }
  }

  @override
  void dispose() {
    widget.controller._detach();
    _urlController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _nameController.dispose();
    _basePathController.dispose();
    super.dispose();
  }

  // ── Validators (delegated to domain/connection_validator.dart) ─────────────

  // ── Build ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Server URL ────────────────────────────────────────────────────
          TextFormField(
            controller: _urlController,
            decoration: const InputDecoration(
              labelText: '服务器地址 *',
              hintText: 'http://192.168.1.100:5005 或 http://nas.example.com',
              prefixIcon: Icon(Icons.dns_outlined),
              border: OutlineInputBorder(),
            ),
            keyboardType: TextInputType.url,
            textInputAction: TextInputAction.next,
            autocorrect: false,
            validator: validateUrl,
          ),
          const SizedBox(height: 16),

          // ── Username ──────────────────────────────────────────────────────
          TextFormField(
            controller: _usernameController,
            decoration: const InputDecoration(
              labelText: '用户名 *',
              prefixIcon: Icon(Icons.person_outline),
              border: OutlineInputBorder(),
            ),
            textInputAction: TextInputAction.next,
            autocorrect: false,
            validator: (v) => validateRequired(v, '用户名'),
          ),
          const SizedBox(height: 16),

          // ── Password ──────────────────────────────────────────────────────
          TextFormField(
            controller: _passwordController,
            decoration: InputDecoration(
              labelText: widget.passwordRequired ? '密码 *' : '密码（留空保持不变）',
              prefixIcon: const Icon(Icons.lock_outline),
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                icon: Icon(
                  _obscurePassword
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                ),
                tooltip: _obscurePassword ? '显示密码' : '隐藏密码',
                onPressed: () =>
                    setState(() => _obscurePassword = !_obscurePassword),
              ),
            ),
            obscureText: _obscurePassword,
            textInputAction: TextInputAction.next,
            autocorrect: false,
            validator: (v) {
              if (!widget.passwordRequired && (v == null || v.trim().isEmpty)) {
                return null;
              }
              return validateRequired(v, '密码');
            },
          ),
          const SizedBox(height: 16),

          // ── Display name (optional) ───────────────────────────────────────
          TextFormField(
            controller: _nameController,
            decoration: const InputDecoration(
              labelText: '显示名称（选填）',
              hintText: '默认取主机名',
              prefixIcon: Icon(Icons.label_outline),
              border: OutlineInputBorder(),
            ),
            textInputAction: TextInputAction.next,
            autocorrect: false,
          ),
          const SizedBox(height: 16),

          // ── Base path (optional) ──────────────────────────────────────────
          TextFormField(
            controller: _basePathController,
            decoration: const InputDecoration(
              labelText: '基础路径（选填）',
              hintText: '/',
              prefixIcon: Icon(Icons.folder_outlined),
              border: OutlineInputBorder(),
            ),
            textInputAction: TextInputAction.done,
            autocorrect: false,
          ),
        ],
      ),
    );
  }
}
