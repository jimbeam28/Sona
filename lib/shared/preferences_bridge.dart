// lib/shared/preferences_bridge.dart
// REF-01-A1: bridges the shared_preferences plugin type into domain code.
//
// The settings domain layer keeps `SharedPreferences?` parameters (REF-01-S1
// keeps the injection-style API so callers can pass null in tests), but must
// not import the plugin package directly (REF-01-INV1).  This bridge is the
// domain layer's single indirect dependency on the plugin — the same pattern
// the spec endorses for just_audio via core/contracts/audio_player_contract.dart.

export 'package:shared_preferences/shared_preferences.dart'
    show SharedPreferences;
