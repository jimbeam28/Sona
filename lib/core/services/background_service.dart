import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

const _channel = MethodChannel('com.example.nas_audio_player/background');

/// Moves the Android task to the background without exiting the app.
///
/// On platforms other than Android this is a no-op.  The app stays alive
/// and audio playback continues via the foreground service.
void moveTaskToBack() {
  unawaited(_channel.invokeMethod('moveTaskToBack').catchError((Object e) {
    // Fire-and-forget: failure only means the back-to-home gesture did not
    // move the task — but do not swallow silently (catch-log criterion,
    // same as BUG-19/LIST6).
    debugPrint('[Background] moveTaskToBack failed: $e');
  }));
}
