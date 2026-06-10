// test/features/connection/edit_screen_logic_test.dart
// TREF-04: Unit tests for lib/features/connection/domain/edit_screen_logic.dart
//
// Pure Dart tests — no Flutter dependency, no ProviderContainer.

import 'package:flutter_test/flutter_test.dart';
import 'package:nas_audio_player/features/connection/domain/edit_screen_logic.dart';
import 'package:nas_audio_player/shared/models/connection_config.dart';

void main() {
  // Shared helpers
  final now = DateTime(2026, 6, 10);

  ConnectionConfig makeConfig({
    int? id = 1,
    String name = 'Test NAS',
    String url = 'http://192.168.1.100:5005',
    String username = 'admin',
    String basePath = '/',
    bool isActive = false,
  }) {
    return ConnectionConfig(
      id: id,
      name: name,
      url: url,
      username: username,
      basePath: basePath,
      isActive: isActive,
      createdAt: now,
      updatedAt: now,
    );
  }

  EditFieldChanges makeChanges({
    String url = 'http://192.168.1.100:5005',
    String username = 'admin',
    String basePath = '/',
    String password = '',
  }) {
    return EditFieldChanges(
      url: url,
      username: username,
      basePath: basePath,
      password: password,
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // needsValidation
  // ═══════════════════════════════════════════════════════════════════════════

  group('needsValidation', () {
    // ESL-01: null original → true (safety net)
    test('ESL-01: null original returns true', () {
      expect(
        needsValidation(
          original: null,
          current: makeChanges(),
          isAttached: true,
        ),
        isTrue,
      );
    });

    // ESL-02: not attached → false
    test('ESL-02: not attached returns false', () {
      expect(
        needsValidation(
          original: makeConfig(),
          current: makeChanges(),
          isAttached: false,
        ),
        isFalse,
      );
    });

    // ESL-03: no changes → false
    test('ESL-03: no changes returns false', () {
      expect(
        needsValidation(
          original: makeConfig(),
          current: makeChanges(), // all fields match original
          isAttached: true,
        ),
        isFalse,
      );
    });

    // ESL-04: URL changed → true
    test('ESL-04: URL changed returns true', () {
      expect(
        needsValidation(
          original: makeConfig(),
          current: makeChanges(url: 'http://10.0.0.1:8080'),
          isAttached: true,
        ),
        isTrue,
      );
    });

    // ESL-05: username changed → true
    test('ESL-05: username changed returns true', () {
      expect(
        needsValidation(
          original: makeConfig(),
          current: makeChanges(username: 'newuser'),
          isAttached: true,
        ),
        isTrue,
      );
    });

    // ESL-06: basePath changed → true
    test('ESL-06: basePath changed returns true', () {
      expect(
        needsValidation(
          original: makeConfig(),
          current: makeChanges(basePath: '/music'),
          isAttached: true,
        ),
        isTrue,
      );
    });

    // ESL-07: password provided → true
    test('ESL-07: password provided returns true', () {
      expect(
        needsValidation(
          original: makeConfig(),
          current: makeChanges(password: 'newpass'),
          isAttached: true,
        ),
        isTrue,
      );
    });

    // ESL-08: only name changed → false (name is not a credential field)
    test('ESL-08: only name changed returns false', () {
      final original = makeConfig(name: 'Old Name');
      // EditFieldChanges has no name field — only url/username/basePath/password.
      // The original config has url/username/basePath matching the current changes.
      expect(
        needsValidation(
          original: original,
          current: makeChanges(), // matches original's url, username, basePath
          isAttached: true,
        ),
        isFalse,
        reason:
            'name is not checked by needsValidation — only credential fields matter',
      );
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // canSave
  // ═══════════════════════════════════════════════════════════════════════════

  group('canSave', () {
    // ESL-09: no revalidation needed → true (always allowed)
    test('ESL-09: no revalidation returns true', () {
      expect(
        canSave(
          needsRevalidation: false,
          validationStatus: ValidationStatus.idle,
        ),
        isTrue,
      );
    });

    // ESL-10: revalidation + idle → false
    test('ESL-10: revalidation + idle returns false', () {
      expect(
        canSave(
          needsRevalidation: true,
          validationStatus: ValidationStatus.idle,
        ),
        isFalse,
      );
    });

    // ESL-11: revalidation + loading → false
    test('ESL-11: revalidation + loading returns false', () {
      expect(
        canSave(
          needsRevalidation: true,
          validationStatus: ValidationStatus.loading,
        ),
        isFalse,
      );
    });

    // ESL-12: revalidation + success → true
    test('ESL-12: revalidation + success returns true', () {
      expect(
        canSave(
          needsRevalidation: true,
          validationStatus: ValidationStatus.success,
        ),
        isTrue,
      );
    });

    // ESL-13: revalidation + error → false
    test('ESL-13: revalidation + error returns false', () {
      expect(
        canSave(
          needsRevalidation: true,
          validationStatus: ValidationStatus.error,
        ),
        isFalse,
      );
    });

    // ESL-14: no revalidation + error → true (revalidation not needed, so save is allowed)
    test('ESL-14: no revalidation + error returns true', () {
      expect(
        canSave(
          needsRevalidation: false,
          validationStatus: ValidationStatus.error,
        ),
        isTrue,
      );
    });
  });
}
