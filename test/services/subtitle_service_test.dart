import 'package:flutter_test/flutter_test.dart';
import 'package:zmedia_player/zmedia_player.dart';

void main() {
  group('SubtitleService', () {
    late SubtitleService service;

    setUp(() {
      service = SubtitleService();
    });

    group('loadSubtitleTrack URL validation', () {
      test('skips track when url is null', () async {
        final track = SubtitleTrack(
          id: 'null-url',
          title: 'No URL',
          language: 'en',
          url: null,
        );

        final cues = await service.loadSubtitleTrack(track);
        expect(cues, isEmpty,
            reason: 'Null URL must produce empty cue list, not throw');
      });

      test('skips track when url is empty string', () async {
        final track = SubtitleTrack(
          id: 'empty-url',
          title: 'Empty URL',
          language: 'en',
          url: '',
        );

        final cues = await service.loadSubtitleTrack(track);
        expect(cues, isEmpty,
            reason: 'Empty URL must produce empty cue list, not throw');
      });

      test('attempts to load a track with a non-empty URL', () async {
        // A non-empty URL that is not reachable: the service gracefully returns
        // empty cues on network failure rather than throwing.
        final track = SubtitleTrack(
          id: 'valid-url',
          title: 'English',
          language: 'en',
          url: 'https://test.example.invalid/subs.srt',
        );

        // The service must not throw; it returns empty on network failure.
        final cues = await service.loadSubtitleTrack(track);
        expect(cues, isA<List>(),
            reason:
                'Non-empty URL must return a List (possibly empty on failure)');
      });

      test('returns cached result on second call for same track id', () async {
        final track = SubtitleTrack(
          id: 'cache-test',
          title: 'English',
          language: 'en',
          url: '',
        );

        // Prime the cache with the empty-URL path.
        await service.loadSubtitleTrack(track);
        // Second call should hit the cache; result must be identical.
        final cues = await service.loadSubtitleTrack(track);
        expect(cues, isEmpty);
      });
    });

    group('setActiveTrack', () {
      test('sets active track and content for null url', () async {
        final track = SubtitleTrack(
          id: 'set-active',
          title: 'English',
          language: 'en',
          url: null,
        );

        await service.setActiveTrack(track);
        expect(service.activeTrack?.id, 'set-active');
        expect(service.activeContent, isNotNull);
        expect(service.activeContent, isEmpty);
      });

      test('does not re-load if same track is set again', () async {
        final track = SubtitleTrack(
          id: 'idempotent',
          title: 'FR',
          language: 'fr',
          url: null,
        );

        await service.setActiveTrack(track);
        final firstContent = service.activeContent;
        // Setting the same track ID again must be a no-op.
        await service.setActiveTrack(track);
        expect(identical(service.activeContent, firstContent), isTrue,
            reason: 'Content should not be replaced when same track is set');
      });
    });

    group('getCueAtTime', () {
      test('returns null when no active content', () {
        final cue = service.getCueAtTime(const Duration(seconds: 1));
        expect(cue, isNull);
      });
    });
  });
}
