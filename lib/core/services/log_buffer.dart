// lib/core/services/log_buffer.dart
// In-memory ring buffer for runtime log inspection on device.
//
// Captures everything written through [debugPrint] so the user can
// review it from the Settings → 查看日志 page without a USB connection.

import 'dart:collection';

import 'package:flutter/foundation.dart';

/// A timestamped log line.
class LogEntry {
  final DateTime time;
  final String message;

  const LogEntry(this.time, this.message);

  String get formatted {
    String two(int n) => n.toString().padLeft(2, '0');
    String three(int n) => n.toString().padLeft(3, '0');
    final t =
        '${two(time.hour)}:${two(time.minute)}:${two(time.second)}.${three(time.millisecond)}';
    return '$t  $message';
  }
}

/// Bounded log buffer that the log-viewer screen listens to.
class LogBuffer extends ChangeNotifier {
  LogBuffer._();
  static final LogBuffer instance = LogBuffer._();

  static const int maxEntries = 1000;
  final Queue<LogEntry> _entries = Queue<LogEntry>();

  List<LogEntry> get entries => List.unmodifiable(_entries);

  void add(String message) {
    _entries.addLast(LogEntry(DateTime.now(), message));
    while (_entries.length > maxEntries) {
      _entries.removeFirst();
    }
    notifyListeners();
  }

  void clear() {
    _entries.clear();
    notifyListeners();
  }
}

/// Installs a [debugPrint] hook that mirrors output into [LogBuffer].
///
/// The original synchronous printer is still invoked so console logs
/// continue to work when the device is attached to a host.
void installLogBufferHook() {
  final original = debugPrint;
  debugPrint = (String? message, {int? wrapWidth}) {
    if (message != null) {
      LogBuffer.instance.add(message);
    }
    original(message, wrapWidth: wrapWidth);
  };
}
