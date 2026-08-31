// Issue #87: `MediaItem.streamingFormat` / `StreamingFormat`.
//
// Before this, the streaming config that applied to an item was picked by
// `url.contains('.m3u8')` (tested first) then `url.contains('.mpd')`, with no
// way for a host to state the format explicitly. That mis-classified any URL
// that merely *mentions* `.m3u8` — signed URLs with query parameters, CDN
// rewrites, path segments such as `/hls.m3u8-archive/…/manifest.mpd` — and
// silently left one protocol unconfigured for apps that serve HLS to one
// platform and DASH to another.
//
// These tests pin the replacement: an explicit `streamingFormat` always wins,
// and inference looks only at the URL's *path*, with `endsWith`.

import 'package:flutter_test/flutter_test.dart';
import 'package:zmedia_player/zmedia_player.dart';

MediaItem _item(String url, {StreamingFormat? format}) => MediaItem(
      id: 'item',
      title: 'Item',
      url: url,
      streamingFormat: format,
    );

void main() {
  group('StreamingFormat.fromUrl — path-based inference', () {
    test('plain manifest URLs resolve to their format', () {
      expect(StreamingFormat.fromUrl('https://cdn.example.com/live.m3u8'),
          StreamingFormat.hls);
      expect(StreamingFormat.fromUrl('https://cdn.example.com/live.mpd'),
          StreamingFormat.dash);
      expect(StreamingFormat.fromUrl('https://cdn.example.com/video.mp4'),
          StreamingFormat.progressive);
    });

    test('the query string is ignored', () {
      // A signed HLS URL whose token happens to contain ".mpd".
      expect(
        StreamingFormat.fromUrl(
            'https://cdn.example.com/live.m3u8?token=abc.mpd&exp=1'),
        StreamingFormat.hls,
      );
      // A DASH URL whose query mentions ".m3u8" — the old `contains` rule
      // tested `.m3u8` first and got this wrong.
      expect(
        StreamingFormat.fromUrl(
            'https://cdn.example.com/manifest.mpd?fallback=.m3u8'),
        StreamingFormat.dash,
      );
    });

    test('the fragment is ignored', () {
      expect(
        StreamingFormat.fromUrl('https://cdn.example.com/manifest.mpd#.m3u8'),
        StreamingFormat.dash,
      );
      expect(
        StreamingFormat.fromUrl('https://cdn.example.com/live.m3u8#t=10'),
        StreamingFormat.hls,
      );
    });

    test('the reported /hls.m3u8-archive/…/manifest.mpd case resolves to DASH',
        () {
      expect(
        StreamingFormat.fromUrl(
            'https://cdn.example.com/hls.m3u8-archive/eu/manifest.mpd'),
        StreamingFormat.dash,
      );
    });

    test('a mid-path mention of a manifest extension is not a match', () {
      expect(
        StreamingFormat.fromUrl(
            'https://cdn.example.com/hls.m3u8-archive/eu/manifest'),
        StreamingFormat.progressive,
      );
      expect(
        StreamingFormat.fromUrl(
            'https://cdn.example.com/live.m3u8/segment1.ts'),
        StreamingFormat.progressive,
      );
    });

    test('matching is case-insensitive', () {
      expect(StreamingFormat.fromUrl('https://cdn.example.com/LIVE.M3U8'),
          StreamingFormat.hls);
      expect(StreamingFormat.fromUrl('https://cdn.example.com/Manifest.MPD'),
          StreamingFormat.dash);
    });

    test('relative and file URLs are handled', () {
      expect(StreamingFormat.fromUrl('live.m3u8'), StreamingFormat.hls);
      expect(StreamingFormat.fromUrl('file:///tmp/movie.mp4'),
          StreamingFormat.progressive);
    });

    test('an unparseable URL never throws', () {
      for (final url in <String>[
        '::::not a url',
        '',
        '   ',
        'https://',
        'http://exa mple.com/live.mpd',
        '%%%%',
      ]) {
        expect(() => StreamingFormat.fromUrl(url), returnsNormally,
            reason: 'inference must never throw for input "$url"');
      }
      expect(StreamingFormat.fromUrl('::::not a url'),
          StreamingFormat.progressive);
      expect(StreamingFormat.fromUrl(''), StreamingFormat.progressive);
    });

    test('a host-only URL with no path resolves to progressive', () {
      expect(StreamingFormat.fromUrl('https://cdn.example.com'),
          StreamingFormat.progressive);
    });
  });

  group('StreamingFormat.fromName', () {
    test('decodes every enum name', () {
      for (final format in StreamingFormat.values) {
        expect(StreamingFormat.fromName(format.name), format);
      }
    });

    test('null / non-String / unknown names decode to null (=> infer)', () {
      expect(StreamingFormat.fromName(null), isNull);
      expect(StreamingFormat.fromName(42), isNull);
      expect(StreamingFormat.fromName('smooth-streaming'), isNull);
      expect(StreamingFormat.fromName('HLS'), isNull,
          reason: 'the wire format is the exact lowercase enum name');
    });
  });

  group('MediaItem.resolvedStreamingFormat', () {
    test('falls back to URL inference when streamingFormat is null', () {
      expect(_item('https://cdn.example.com/live.m3u8').resolvedStreamingFormat,
          StreamingFormat.hls);
      expect(_item('https://cdn.example.com/live.mpd').resolvedStreamingFormat,
          StreamingFormat.dash);
      expect(_item('https://cdn.example.com/v.mp4').resolvedStreamingFormat,
          StreamingFormat.progressive);
    });

    test('an explicit format overrides a contradicting URL', () {
      expect(
        _item('https://cdn.example.com/live.m3u8', format: StreamingFormat.dash)
            .resolvedStreamingFormat,
        StreamingFormat.dash,
      );
      expect(
        _item('https://cdn.example.com/live.mpd', format: StreamingFormat.hls)
            .resolvedStreamingFormat,
        StreamingFormat.hls,
      );
      expect(
        _item('https://cdn.example.com/live.m3u8',
                format: StreamingFormat.progressive)
            .resolvedStreamingFormat,
        StreamingFormat.progressive,
      );
    });

    test('an explicit format rescues an extension-less manifest URL', () {
      expect(
        _item('https://cdn.example.com/live/stream?token=abc',
                format: StreamingFormat.hls)
            .resolvedStreamingFormat,
        StreamingFormat.hls,
      );
    });
  });

  group('MediaItem serialization of streamingFormat', () {
    test('toMap carries the enum name, or null when unset', () {
      expect(
        _item('https://cdn.example.com/live.m3u8', format: StreamingFormat.dash)
            .toMap()['streamingFormat'],
        'dash',
      );
      expect(
        _item('https://cdn.example.com/live.m3u8').toMap()['streamingFormat'],
        isNull,
        reason: 'null means "let native run the same inference"',
      );
    });

    test('round-trips through toMap/fromMap with the field set', () {
      for (final format in StreamingFormat.values) {
        final original = MediaItem(
          id: 'round-trip',
          title: 'Round Trip',
          url: 'https://cdn.example.com/live.m3u8',
          isLive: true,
          streamingFormat: format,
        );
        final restored = MediaItem.fromMap(original.toMap());
        expect(restored.streamingFormat, format);
        expect(restored.resolvedStreamingFormat, format);
        expect(restored.isLive, isTrue);
        expect(restored.url, original.url);
      }
    });

    test('round-trips through toMap/fromMap without the field', () {
      final original = MediaItem(
        id: 'round-trip-null',
        title: 'Round Trip',
        url: 'https://cdn.example.com/live.mpd',
      );
      final restored = MediaItem.fromMap(original.toMap());
      expect(restored.streamingFormat, isNull);
      expect(restored.resolvedStreamingFormat, StreamingFormat.dash,
          reason: 'still inferred from the URL after a round trip');
    });

    test('a map from an older producer (no key at all) decodes to null', () {
      final restored = MediaItem.fromMap(<String, dynamic>{
        'id': 'legacy',
        'title': 'Legacy',
        'url': 'https://cdn.example.com/live.m3u8',
      });
      expect(restored.streamingFormat, isNull);
      expect(restored.resolvedStreamingFormat, StreamingFormat.hls);
    });

    test('an unknown format name decodes to null rather than a wrong format',
        () {
      final restored = MediaItem.fromMap(<String, dynamic>{
        'id': 'future',
        'title': 'Future',
        'url': 'https://cdn.example.com/live.mpd',
        'streamingFormat': 'smooth-streaming',
      });
      expect(restored.streamingFormat, isNull);
      expect(restored.resolvedStreamingFormat, StreamingFormat.dash);
    });
  });

  group('MediaItem.copyWith / equality / toString', () {
    test('copyWith carries streamingFormat over when omitted', () {
      final original = _item('https://cdn.example.com/live.m3u8',
          format: StreamingFormat.dash);
      expect(original.copyWith(title: 'New').streamingFormat,
          StreamingFormat.dash);
    });

    test('copyWith can set streamingFormat', () {
      final original = _item('https://cdn.example.com/live.m3u8');
      expect(original.streamingFormat, isNull);
      final updated = original.copyWith(streamingFormat: StreamingFormat.dash);
      expect(updated.streamingFormat, StreamingFormat.dash);
      expect(updated.resolvedStreamingFormat, StreamingFormat.dash);
      expect(original.streamingFormat, isNull,
          reason: 'copyWith must not mutate the original');
    });

    test(
        'equality stays id-based: streamingFormat does not participate, like '
        'every other content field', () {
      final hls = MediaItem(
        id: 'same',
        title: 'A',
        url: 'https://cdn.example.com/live.m3u8',
        streamingFormat: StreamingFormat.hls,
      );
      final dash = MediaItem(
        id: 'same',
        title: 'A',
        url: 'https://cdn.example.com/live.m3u8',
        streamingFormat: StreamingFormat.dash,
      );
      expect(hls, equals(dash));
      expect(hls.hashCode, equals(dash.hashCode));
      expect(hls.copyWith(id: 'other'), isNot(equals(hls)));
    });

    test('toString reports the format, marking an inferred one as auto', () {
      expect(
        _item('https://cdn.example.com/live.m3u8', format: StreamingFormat.dash)
            .toString(),
        contains('streamingFormat: dash'),
      );
      expect(
        _item('https://cdn.example.com/live.m3u8').toString(),
        contains('streamingFormat: auto(hls)'),
      );
    });
  });
}
