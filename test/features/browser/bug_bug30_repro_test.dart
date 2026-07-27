import 'package:flutter_test/flutter_test.dart';
import 'package:nas_audio_player/shared/models/nas_file.dart';

void main() {
  group('BUG-30', () {
    test('BUG-30-S1: NasFile == includes modifiedAt', () {
      final t = DateTime(2025, 1, 1);
      final a = NasFile(
          name: 'a.mp3',
          path: '/a.mp3',
          isDirectory: false,
          size: 100,
          modifiedAt: t,
          audioType: AudioFileType.music);
      final b = NasFile(
          name: 'a.mp3',
          path: '/a.mp3',
          isDirectory: false,
          size: 100,
          modifiedAt: t.add(const Duration(hours: 1)),
          audioType: AudioFileType.music);
      expect(a == b, isFalse);
    });

    test('BUG-30-S2: NasFile hashCode includes modifiedAt', () {
      final t = DateTime(2025, 1, 1);
      final a = NasFile(
          name: 'a.mp3',
          path: '/a.mp3',
          isDirectory: false,
          size: 100,
          modifiedAt: t,
          audioType: AudioFileType.music);
      final b = NasFile(
          name: 'a.mp3',
          path: '/a.mp3',
          isDirectory: false,
          size: 100,
          modifiedAt: t.add(const Duration(hours: 1)),
          audioType: AudioFileType.music);
      expect(a.hashCode == b.hashCode, isFalse);
    });

    test('BUG-30-INV1: equal NasFile with same modifiedAt', () {
      final t = DateTime(2025, 1, 1);
      final a = NasFile(
          name: 'a.mp3',
          path: '/a.mp3',
          isDirectory: false,
          size: 100,
          modifiedAt: t,
          audioType: AudioFileType.music);
      final b = NasFile(
          name: 'a.mp3',
          path: '/a.mp3',
          isDirectory: false,
          size: 100,
          modifiedAt: t,
          audioType: AudioFileType.music);
      expect(a == b, isTrue);
      expect(a.hashCode, b.hashCode);
    });

    test('BUG-30-INV2: null modifiedAt equality', () {
      final a = NasFile(
          name: 'a.mp3',
          path: '/a.mp3',
          isDirectory: false,
          size: 100,
          audioType: AudioFileType.music);
      final b = NasFile(
          name: 'a.mp3',
          path: '/a.mp3',
          isDirectory: false,
          size: 100,
          audioType: AudioFileType.music);
      expect(a == b, isTrue);
      expect(a.hashCode, b.hashCode);
    });
  });
}
