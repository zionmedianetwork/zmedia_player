// Issue #87: which streaming config MediaPlayer.load() applies to an item,
// and what crosses the channel for it.
//
// The config used to be selected by `url.contains('.m3u8')` (tested first)
// then `url.contains('.mpd')`, so a signed/rewritten DASH URL that merely
// mentioned `.m3u8` picked up hlsConfig — or, with only one of the two
// configs set, silently picked up nothing at all and forced `enableDvr` to
// false. Selection now follows `MediaItem.resolvedStreamingFormat`: an
// explicit `MediaItem.streamingFormat` first, else path-based inference.
//
// Harness: same pattern as media_player_seekability_test.dart.

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zmedia_player/zmedia_player.dart';

const _channel = MethodChannel('zmedia_player');

List<MethodCall> _installCapture() {
  final calls = <MethodCall>[];
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_channel, (MethodCall call) async {
    calls.add(call);
    return null;
  });
  return calls;
}

void _resetHandler() {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_channel, null);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(_resetHandler);

  group('load() config selection follows the resolved streaming format', () {
    test(
        'an explicit streamingFormat overrides a contradicting URL: a .m3u8 '
        'URL declared as DASH reads dashConfig, not hlsConfig', () async {
      _installCapture();
      final player = MediaPlayer(
        playerId: 'fmt-explicit-dash',
        config: const MediaConfig(
          hlsConfig: HlsConfig(enableDvr: false),
          dashConfig: DashConfig(enableDvr: true),
        ),
      );
      await player.initialize();

      await player.load(const MediaItem(
        id: 'explicit-dash',
        title: 'Explicit DASH',
        // URL says HLS; the host says otherwise and must win.
        url: 'https://cdn.example.com/live.m3u8',
        isLive: true,
        streamingFormat: StreamingFormat.dash,
      ));

      expect(player.dvrEnabled, isTrue,
          reason: 'dashConfig.enableDvr must be the one consulted');
      expect(player.isSeekable, isTrue);

      player.dispose();
    });

    test(
        'an explicit streamingFormat overrides a contradicting URL: a .mpd '
        'URL declared as HLS reads hlsConfig, not dashConfig', () async {
      _installCapture();
      final player = MediaPlayer(
        playerId: 'fmt-explicit-hls',
        config: const MediaConfig(
          hlsConfig: HlsConfig(enableDvr: true),
          dashConfig: DashConfig(enableDvr: false),
        ),
      );
      await player.initialize();

      await player.load(const MediaItem(
        id: 'explicit-hls',
        title: 'Explicit HLS',
        url: 'https://cdn.example.com/manifest.mpd',
        isLive: true,
        streamingFormat: StreamingFormat.hls,
      ));

      expect(player.dvrEnabled, isTrue);
      expect(player.isSeekable, isTrue);

      player.dispose();
    });

    test(
        'an explicit streamingFormat rescues an extension-less manifest URL '
        'that would otherwise resolve to progressive', () async {
      _installCapture();
      final player = MediaPlayer(
        playerId: 'fmt-extensionless',
        config: const MediaConfig(hlsConfig: HlsConfig(enableDvr: true)),
      );
      await player.initialize();

      await player.load(const MediaItem(
        id: 'rewritten',
        title: 'CDN-rewritten live',
        url: 'https://cdn.example.com/live/eu/primary?token=abc',
        isLive: true,
        streamingFormat: StreamingFormat.hls,
      ));

      expect(player.dvrEnabled, isTrue);
      expect(player.isSeekable, isTrue);

      player.dispose();
    });

    test(
        'streamingFormat: progressive opts an item out of every streaming '
        'config, even for a .m3u8 URL', () async {
      _installCapture();
      final player = MediaPlayer(
        playerId: 'fmt-explicit-progressive',
        config: const MediaConfig(hlsConfig: HlsConfig(enableDvr: true)),
      );
      await player.initialize();

      await player.load(const MediaItem(
        id: 'explicit-progressive',
        title: 'Explicit progressive',
        url: 'https://cdn.example.com/live.m3u8',
        isLive: true,
        streamingFormat: StreamingFormat.progressive,
      ));

      expect(player.dvrEnabled, isFalse);
      expect(player.isSeekable, isFalse);

      player.dispose();
    });
  });

  group('load() inference uses the URL path, not a substring scan', () {
    Future<bool> dvrForUrl(String url, {required String playerId}) async {
      final player = MediaPlayer(
        playerId: playerId,
        config: const MediaConfig(
          // HLS DVR off, DASH DVR on: dvrEnabled is then a direct readout of
          // "which config did load() pick?".
          hlsConfig: HlsConfig(enableDvr: false),
          dashConfig: DashConfig(enableDvr: true),
        ),
      );
      await player.initialize();
      await player.load(MediaItem(
        id: 'infer',
        title: 'Infer',
        url: url,
        isLive: true,
      ));
      final result = player.dvrEnabled;
      player.dispose();
      return result;
    }

    test('a query string mentioning the other format does not flip the choice',
        () async {
      _installCapture();
      expect(
        await dvrForUrl('https://cdn.example.com/manifest.mpd?fallback=.m3u8',
            playerId: 'infer-query-dash'),
        isTrue,
        reason: 'the path ends in .mpd, so dashConfig applies',
      );
      expect(
        await dvrForUrl('https://cdn.example.com/live.m3u8?next=manifest.mpd',
            playerId: 'infer-query-hls'),
        isFalse,
        reason: 'the path ends in .m3u8, so hlsConfig (DVR off) applies',
      );
    });

    test('a fragment mentioning the other format does not flip the choice',
        () async {
      _installCapture();
      expect(
        await dvrForUrl('https://cdn.example.com/manifest.mpd#.m3u8',
            playerId: 'infer-fragment-dash'),
        isTrue,
      );
    });

    test('the reported /hls.m3u8-archive/…/manifest.mpd case resolves to DASH',
        () async {
      _installCapture();
      expect(
        await dvrForUrl(
            'https://cdn.example.com/hls.m3u8-archive/eu/manifest.mpd',
            playerId: 'infer-archive-path'),
        isTrue,
        reason: 'the old contains(".m3u8") rule picked hlsConfig here',
      );
    });

    test('an unparseable URL does not throw during load()', () async {
      _installCapture();
      final player = MediaPlayer(playerId: 'infer-unparseable');
      await player.initialize();

      await expectLater(
        player.load(const MediaItem(
          id: 'bad-url',
          title: 'Malformed',
          url: '::::not a url',
        )),
        completes,
      );
      expect(player.dvrEnabled, isFalse);

      player.dispose();
    });
  });

  group('mediaItem payload carries the streamingFormat key', () {
    test('load() sends the explicit format name', () async {
      final calls = _installCapture();
      final player = MediaPlayer(playerId: 'payload-explicit');
      await player.initialize();
      calls.clear();

      await player.load(const MediaItem(
        id: 'payload',
        title: 'Payload',
        url: 'https://cdn.example.com/live.m3u8',
        streamingFormat: StreamingFormat.dash,
      ));

      final loadCall = calls.firstWhere((c) => c.method == 'load');
      final mediaItem =
          Map<String, dynamic>.from(loadCall.arguments['mediaItem'] as Map);
      expect(mediaItem['streamingFormat'], 'dash');

      player.dispose();
    });

    test('load() sends null when the host left inference on', () async {
      final calls = _installCapture();
      final player = MediaPlayer(playerId: 'payload-inferred');
      await player.initialize();
      calls.clear();

      await player.load(const MediaItem(
        id: 'payload',
        title: 'Payload',
        url: 'https://cdn.example.com/live.m3u8',
      ));

      final loadCall = calls.firstWhere((c) => c.method == 'load');
      final mediaItem =
          Map<String, dynamic>.from(loadCall.arguments['mediaItem'] as Map);
      expect(mediaItem.containsKey('streamingFormat'), isTrue,
          reason: 'the key is always present so native can distinguish '
              '"unset" from an older Dart build');
      expect(mediaItem['streamingFormat'], isNull);

      player.dispose();
    });

    test('setPlaylist forwards the format for every item', () async {
      final calls = _installCapture();
      final player = MediaPlayer(playerId: 'payload-playlist');
      await player.initialize();
      calls.clear();

      await player.setPlaylist(const Playlist(
        id: 'pl',
        title: 'Playlist',
        items: [
          MediaItem(
            id: 'a',
            title: 'A',
            url: 'https://cdn.example.com/a.m3u8',
            streamingFormat: StreamingFormat.hls,
          ),
          MediaItem(
            id: 'b',
            title: 'B',
            url: 'https://cdn.example.com/b',
            streamingFormat: StreamingFormat.dash,
          ),
        ],
      ));

      final call = calls.firstWhere((c) => c.method == 'setPlaylist');
      final playlist =
          Map<String, dynamic>.from(call.arguments['playlist'] as Map);
      final items = (playlist['items'] as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      expect(items.map((e) => e['streamingFormat']), ['hls', 'dash']);

      player.dispose();
    });

    test('loadMediaOnCastDevice forwards the format hint', () async {
      final calls = _installCapture();
      final player = MediaPlayer(playerId: 'payload-cast');
      await player.initialize();
      calls.clear();

      await player.loadMediaOnCastDevice(const MediaItem(
        id: 'cast',
        title: 'Cast',
        url: 'https://cdn.example.com/live/eu/primary',
        streamingFormat: StreamingFormat.dash,
      ));

      final call = calls.firstWhere((c) => c.method == 'loadMediaOnCastDevice');
      final mediaItem =
          Map<String, dynamic>.from(call.arguments['mediaItem'] as Map);
      expect(mediaItem['streamingFormat'], 'dash');

      player.dispose();
    });
  });

  group('missing-config diagnostic', () {
    test(
        'a live item whose format has no config still loads, with DVR off '
        '(configs are never cross-applied)', () async {
      _installCapture();
      final player = MediaPlayer(
        playerId: 'diag-hls-only',
        // Only hlsConfig is set — the "our case" scenario from issue #87.
        config: const MediaConfig(hlsConfig: HlsConfig(enableDvr: true)),
      );
      await player.initialize();

      await player.load(const MediaItem(
        id: 'dash-live',
        title: 'DASH live',
        url: 'https://cdn.example.com/live.mpd',
        isLive: true,
      ));

      expect(player.dvrEnabled, isFalse,
          reason: 'hlsConfig must NOT be silently reused for a DASH item');
      expect(player.isSeekable, isFalse);

      player.dispose();
    });

    test('the diagnostic is logged once per format, not once per load()',
        () async {
      _installCapture();
      final logs = <String>[];
      final originalDebugPrint = debugPrint;
      debugPrint = (String? message, {int? wrapWidth}) {
        if (message != null) logs.add(message);
      };
      addTearDown(() => debugPrint = originalDebugPrint);

      final player = MediaPlayer(
        playerId: 'diag-once',
        config: const MediaConfig(hlsConfig: HlsConfig(enableDvr: true)),
      );
      await player.initialize();

      const item = MediaItem(
        id: 'dash-live',
        title: 'DASH live',
        url: 'https://cdn.example.com/live.mpd',
        isLive: true,
      );
      await player.load(item);
      await player.load(item);
      await player.load(item);

      final warnings = logs
          .where((l) => l.contains('MediaConfig.dashConfig is null'))
          .toList();
      expect(warnings, hasLength(1),
          reason: 'reloading a misconfigured item must not spam the log');
      expect(warnings.single, contains('enableDvr'));
      expect(warnings.single, contains('not seekable'));
      expect(warnings.single, contains('StreamingFormat.dash'));

      player.dispose();
    });

    test('no diagnostic for a non-live item with no streaming config',
        () async {
      _installCapture();
      final logs = <String>[];
      final originalDebugPrint = debugPrint;
      debugPrint = (String? message, {int? wrapWidth}) {
        if (message != null) logs.add(message);
      };
      addTearDown(() => debugPrint = originalDebugPrint);

      final player = MediaPlayer(playerId: 'diag-vod');
      await player.initialize();
      await player.load(const MediaItem(
        id: 'vod',
        title: 'VOD',
        url: 'https://cdn.example.com/movie.mp4',
      ));

      expect(logs.where((l) => l.contains('falls back to false')), isEmpty);

      player.dispose();
    });

    test('no diagnostic when the matching config IS present', () async {
      _installCapture();
      final logs = <String>[];
      final originalDebugPrint = debugPrint;
      debugPrint = (String? message, {int? wrapWidth}) {
        if (message != null) logs.add(message);
      };
      addTearDown(() => debugPrint = originalDebugPrint);

      final player = MediaPlayer(
        playerId: 'diag-configured',
        config: const MediaConfig(dashConfig: DashConfig(enableDvr: true)),
      );
      await player.initialize();
      await player.load(const MediaItem(
        id: 'dash-live',
        title: 'DASH live',
        url: 'https://cdn.example.com/live.mpd',
        isLive: true,
      ));

      expect(logs.where((l) => l.contains('is null')), isEmpty);

      player.dispose();
    });
  });
}
