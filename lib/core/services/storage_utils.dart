import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Reads from [storage] with a 5-second timeout.
/// Returns null on timeout or error.
Future<String?> safeStorageRead(
  FlutterSecureStorage storage, {
  required String key,
}) async {
  try {
    return await storage.read(key: key).timeout(const Duration(seconds: 5));
  } catch (e) {
    debugPrint('[Storage] safeRead failed: $e');
    return null;
  }
}

/// Writes to [storage] with a 5-second timeout.
/// Throws [TimeoutException] on timeout.
Future<void> safeStorageWrite(
  FlutterSecureStorage storage, {
  required String key,
  required String? value,
}) async {
  try {
    await storage.write(key: key, value: value).timeout(const Duration(seconds: 5));
  } catch (e) {
    debugPrint('[Storage] safeWrite failed: $e');
    rethrow;
  }
}

/// Deletes from [storage] with a 5-second timeout.
/// Throws [TimeoutException] on timeout.
Future<void> safeStorageDelete(
  FlutterSecureStorage storage, {
  required String key,
}) async {
  try {
    await storage.delete(key: key).timeout(const Duration(seconds: 5));
  } catch (e) {
    debugPrint('[Storage] safeDelete failed: $e');
    rethrow;
  }
}
