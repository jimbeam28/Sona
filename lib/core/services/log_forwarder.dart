// lib/core/services/log_forwarder.dart
// Domain 层日志转发器（REF-01）。
//
// Domain 层禁止直接 import Flutter（REF-01-INV1 / cross-imports
// domain-flutter 门禁），但 BUG-19 / BUG-24 的 catch-log 裁决要求日志
// 经 debugPrint 发出（测试 captureLogs 与 LogBuffer 均捕获 debugPrint）。
// 本文件是 core 层唯一允许 import Flutter 的日志出口，domain 通过
// 相对路径 import 本文件后调用 [debugLog]。

import 'package:flutter/foundation.dart';

/// Forwards [message] to [debugPrint] so domain-layer diagnostics are
/// captured by tests (debugPrint hook) and by [LogBuffer] (log viewer).
void debugLog(String message) => debugPrint(message);
