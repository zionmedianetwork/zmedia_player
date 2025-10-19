import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_media_player/flutter_media_player.dart';

/// Phase 2: Subtitle Track tests
void main() {
  group('SubtitleTrack', () {
    test('creates subtitle track with required fields', () {
      final track = SubtitleTrack(
        id: 'sub1',
        title: 'English',
        language: 'en',
        url: 'https://example.com/subtitles.vtt',
      );

      expect(track.id, 'sub1');
      expect(track.title, 'English');
      expect(track.language, 'en');
      expect(track.url, 'https://example.com/subtitles.vtt');
      expect(track.isSelected, false);
    });

    test('creates subtitle track with all fields', () {
      final track = SubtitleTrack(
        id: 'sub1',
        title: 'Spanish (Spain)',
        language: 'es-ES',
        url: 'https://example.com/subtitles.srt',
        format: SubtitleFormat.srt,
        isSelected: true,
        isDefault: true,
      );

      expect(track.id, 'sub1');
      expect(track.title, 'Spanish (Spain)');
      expect(track.language, 'es-ES');
      expect(track.format, SubtitleFormat.srt);
      expect(track.isSelected, true);
      expect(track.isDefault, true);
    });

    test('serializes and deserializes correctly', () {
      final original = SubtitleTrack(
        id: 'sub1',
        title: 'Italian',
        language: 'it',
        url: 'https://example.com/subtitles.vtt',
        format: SubtitleFormat.webvtt,
        isSelected: false,
        isDefault: true,
      );

      final map = original.toMap();
      final deserialized = SubtitleTrack.fromMap(map);

      expect(deserialized.id, original.id);
      expect(deserialized.title, original.title);
      expect(deserialized.language, original.language);
      expect(deserialized.url, original.url);
      expect(deserialized.isSelected, original.isSelected);
      expect(deserialized.isDefault, original.isDefault);
    });

    test('copyWith updates selected state', () {
      final original = SubtitleTrack(
        id: 'sub1',
        title: 'English',
        language: 'en',
        url: 'https://example.com/subtitles.vtt',
        isSelected: false,
      );

      final updated = original.copyWith(isSelected: true);

      expect(updated.isSelected, true);
      expect(updated.id, original.id);
      expect(updated.title, original.title);
    });
  });

  group('QualityTrack', () {
    test('creates quality track with all fields', () {
      final track = QualityTrack(
        id: 'q1080p',
        name: '1080p',
        bitrate: 5000000,
        width: 1920,
        height: 1080,
        frameRate: 30.0,
        codec: 'h264',
        isSelected: false,
        isAvailable: true,
      );

      expect(track.id, 'q1080p');
      expect(track.name, '1080p');
      expect(track.bitrate, 5000000);
      expect(track.width, 1920);
      expect(track.height, 1080);
    });
  });

  group('AudioTrack', () {
    test('creates audio track with all fields', () {
      final track = AudioTrack(
        id: 'audio1',
        name: 'English (Stereo)',
        language: 'en',
        codec: 'aac',
        channels: 2,
        sampleRate: 48000,
        isSelected: false,
        isAvailable: true,
      );

      expect(track.id, 'audio1');
      expect(track.name, 'English (Stereo)');
      expect(track.language, 'en');
      expect(track.channels, 2);
    });
  });
}
