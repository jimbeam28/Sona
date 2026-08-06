import 'dart:async';
import 'package:flutter/foundation.dart';

import '../contracts/storage_contract.dart';

/// Thrown when [safeStorageRead] exceeds its timeout.
/// Callers can distinguish "no value" (null) from "timeout" (this exception).
class SecureStorageTimeoutException implements Exception {
  final String key;
  final Duration timeout;
  const SecureStorageTimeoutException(
      {required this.key, required this.timeout});
  @override
  String toString() =>
      'SecureStorageTimeoutException: read($key) exceeded ${timeout.inSeconds}s';
}

/// Reads from [storage] with a 5-second timeout.
/// Returns null when the key does not exist.
/// Throws [SecureStorageTimeoutException] on timeout.
/// Returns null on other errors (logged).
Future<String?> safeStorageRead(
  ISecureStorage storage, {
  required String key,
}) async {
  try {
    return await storage.read(key: key).timeout(const Duration(seconds: 5));
  } on TimeoutException {
    debugPrint('[Storage] safeRead timeout: key=$key');
    throw SecureStorageTimeoutException(
        key: key, timeout: const Duration(seconds: 5));
  } catch (e) {
    debugPrint('[Storage] safeRead failed: $e');
    return null;
  }
}

/// Writes to [storage] with a 5-second timeout.
/// Throws [TimeoutException] on timeout.
Future<void> safeStorageWrite(
  ISecureStorage storage, {
  required String key,
  required String? value,
}) async {
  try {
    await storage
        .write(key: key, value: value)
        .timeout(const Duration(seconds: 5));
  } catch (e) {
    debugPrint('[Storage] safeWrite failed: $e');
    rethrow;
  }
}

/// Deletes from [storage] with a 5-second timeout.
/// Throws [TimeoutException] on timeout.
Future<void> safeStorageDelete(
  ISecureStorage storage, {
  required String key,
}) async {
  try {
    await storage.delete(key: key).timeout(const Duration(seconds: 5));
  } catch (e) {
    debugPrint('[Storage] safeDelete failed: $e');
    rethrow;
  }
}
