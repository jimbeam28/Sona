import 'dart:async';
import 'package:flutter/services.dart';

const _channel = MethodChannel('com.example.nas_audio_player/background');

void moveTaskToBack() {
  unawaited(_channel.invokeMethod('moveTaskToBack').catchError((_) {}));
}
