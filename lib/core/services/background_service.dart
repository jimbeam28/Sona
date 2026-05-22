import 'package:flutter/services.dart';

const _channel = MethodChannel('com.example.nas_audio_player/background');

/// Moves the Android task to the background without exiting the app.
///
/// On platforms other than Android this is a no-op.  The app stays alive
/// and audio playback continues via the foreground service.
void moveTaskToBack() {
  _channel.invokeMethod('moveTaskToBack');
}
