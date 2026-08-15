// M-19 regression coverage: MediaItem.toString() previously embedded the
// raw `url` verbatim, including any query string — which frequently carries
// signed cookies/auth tokens for authenticated media URLs — and
// `toString()` output routinely ends up in logs this package has no
// control over once emitted (print statements, log frameworks, debugger
// watch expressions).

import 'package:flutter_test/flutter_test.dart';
import 'package:zmedia_player/zmedia_player.dart';

void main() {
  group('MediaItem.toString redaction (M-19)', () {
    test('strips the query string (and its secret) from the output', () {
      const item = MediaItem(
        id: 'item-1',
        title: 'Secret Video',
        url: 'https://cdn.example.com/video.mp4?token=SUPER-SECRET-TOKEN',
      );

      final output = item.toString();

      expect(output, isNot(contains('SUPER-SECRET-TOKEN')),
          reason: 'toString() must never leak the query string');
      expect(output, isNot(contains('?')));
      expect(output, contains('https://cdn.example.com/video.mp4'));
    });

    test('strips a fragment as well', () {
      const item = MediaItem(
        id: 'item-2',
        title: 'Fragment Video',
        url: 'https://cdn.example.com/video.mp4#access_token=SECRET',
      );

      final output = item.toString();

      expect(output, isNot(contains('SECRET')));
      expect(output, isNot(contains('#')));
    });

    test('leaves a URL with no query string unchanged (beyond the path)', () {
      const item = MediaItem(
        id: 'item-3',
        title: 'Plain Video',
        url: 'https://cdn.example.com/plain.mp4',
      );

      final output = item.toString();

      expect(output, contains('https://cdn.example.com/plain.mp4'));
    });

    test('still includes id, title, mediaType, and isLive', () {
      const item = MediaItem(
        id: 'item-4',
        title: 'My Title',
        url: 'https://cdn.example.com/x.mp4?secret=abc',
        mediaType: MediaType.audio,
        isLive: true,
      );

      final output = item.toString();

      expect(output, contains('item-4'));
      expect(output, contains('My Title'));
      expect(output, contains('MediaType.audio'));
      expect(output, contains('isLive: true'));
      expect(output, isNot(contains('abc')));
    });
  });
}
