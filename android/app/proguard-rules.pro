# Flutter / Dart platform-channel methods — keep all classes referenced by JNI / MethodChannel.
-keep class io.flutter.** { *; }
-keep class com.example.nas_audio_player.** { *; }

# Kotlin metadata — required for reflection-based serialization and coroutines.
-keepattributes *Annotation*,EnclosingMethod,InnerClasses,Signature,Exceptions
-keep class kotlin.Metadata { *; }
-keep class kotlin.coroutines.** { *; }

# flutter_secure_storage (EncryptedSharedPreferences + Tink).
-keep class com.it_nomads.fluttersecurestorage.** { *; }
-keep class com.google.crypto.tink.** { *; }
-dontwarn com.google.crypto.tink.**

# audio_service — keep the AudioService class so AndroidManifest can find it.
-keep class com.ryanheise.audioservice.** { *; }

# just_audio — keep platform-channel handlers.
-keep class com.ryanheise.just_audio.** { *; }
-keep class com.ryanheise.audio_session.** { *; }

# sqflite — keep database helper.
-keep class com.tekartik.sqflite.** { *; }

# Flutter engine references Play Core classes that aren't bundled.
# The app doesn't use deferred components, so missing classes are safe to ignore.
-dontwarn com.google.android.play.core.**
