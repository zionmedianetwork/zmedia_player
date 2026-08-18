import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zmedia_player/zmedia_player.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

const _channel = MethodChannel('zmedia_player');

/// Captures every outgoing MethodCall made on [_channel].
/// Returns a cancel function that restores the previous handler.
typedef _HandlerFn = Future<dynamic> Function(MethodCall);

/// Installs [handler] as the mock handler and returns a list that accumulates
/// every call forwarded to it. Call [reset] in tearDown.
List<MethodCall> _installCapture([_HandlerFn? extra]) {
  final calls = <MethodCall>[];
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_channel, (MethodCall call) async {
    calls.add(call);
    return extra != null ? await extra(call) : null;
  });
  return calls;
}

void _resetHandler() {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_channel, null);
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Reset handler after every test so calls don't bleed.
  tearDown(_resetHandler);

  // -------------------------------------------------------------------------
  group('initialize — outgoing contract', () {
    test('sends method "initialize" with playerId and config keys', () async {
      final calls = _installCapture();
      final player = MediaPlayer(playerId: 'ch-init-1');
      await player.initialize();

      final initCall =
          calls.firstWhere((c) => c.method == 'initialize', orElse: () {
        fail('No "initialize" call found');
      });

      expect(initCall.arguments['playerId'], 'ch-init-1');
      final config = initCall.arguments['config'] as Map;
      expect(config.containsKey('autoPlay'), isTrue);
      expect(config.containsKey('volume'), isTrue);
      expect(config.containsKey('speed'), isTrue);
      expect(config.containsKey('looping'), isTrue);

      player.dispose();
    });

    test('initialize is idempotent — only one call sent', () async {
      final calls = _installCapture();
      final player = MediaPlayer(playerId: 'ch-init-idempotent');
      await player.initialize();
      await player.initialize(); // second call is a no-op

      final initCalls = calls.where((c) => c.method == 'initialize').toList();
      expect(initCalls.length, 1,
          reason: 'initialize must be sent exactly once');

      player.dispose();
    });

    // C-03b: transparent Android-only adaptive-stream segment cache. The
    // native (Kotlin) side reads this key directly off the "initialize" /
    // "updateConfig" config map — see MediaPlayerInstance.loadMediaItem in
    // MediaPlayerManager.kt — so the wire contract itself is the thing worth
    // pinning down at the Dart layer; native behaviour is not exercised by
    // this (pure-Dart) test suite.
    group('adaptiveCacheConfig — outgoing contract', () {
      test('omits "adaptiveCacheConfig" key when not configured', () async {
        final calls = _installCapture();
        final player = MediaPlayer(playerId: 'ch-init-cache-absent');
        await player.initialize();

        final initCall = calls.firstWhere((c) => c.method == 'initialize');
        final config = initCall.arguments['config'] as Map;
        expect(config.containsKey('adaptiveCacheConfig'), isFalse,
            reason: 'no adaptiveCacheConfig on MediaConfig must mean no key at '
                'all is sent, not a null/disabled placeholder — keeps '
                'default behaviour byte-for-byte identical to before this '
                'feature existed');

        player.dispose();
      });

      test(
          'sends "adaptiveCacheConfig" with enabled + maxCacheSizeBytes when '
          'configured', () async {
        final calls = _installCapture();
        final player = MediaPlayer(
          playerId: 'ch-init-cache-enabled',
          config: const MediaConfig(
            adaptiveCacheConfig: AdaptiveCacheConfig(
              enabled: true,
              maxCacheSizeBytes: 42 * 1024 * 1024,
            ),
          ),
        );
        await player.initialize();

        final initCall = calls.firstWhere((c) => c.method == 'initialize');
        final config = initCall.arguments['config'] as Map;
        expect(config.containsKey('adaptiveCacheConfig'), isTrue);
        final cacheConfig = config['adaptiveCacheConfig'] as Map;
        expect(cacheConfig['enabled'], true);
        expect(cacheConfig['maxCacheSizeBytes'], 42 * 1024 * 1024);

        player.dispose();
      });

      test(
          'sends "adaptiveCacheConfig" with enabled: false when explicitly '
          'configured but not opted in', () async {
        final calls = _installCapture();
        final player = MediaPlayer(
          playerId: 'ch-init-cache-explicit-off',
          config: const MediaConfig(
            adaptiveCacheConfig: AdaptiveCacheConfig(enabled: false),
          ),
        );
        await player.initialize();

        final initCall = calls.firstWhere((c) => c.method == 'initialize');
        final config = initCall.arguments['config'] as Map;
        final cacheConfig = config['adaptiveCacheConfig'] as Map;
        expect(cacheConfig['enabled'], false);

        player.dispose();
      });
    });

    // Wave D: HlsConfig/DashConfig were entirely inert (never sent over the
    // platform channel at all) prior to this wiring — pin down that they now
    // actually cross the wire, mirroring the adaptiveCacheConfig contract
    // tests above.
    group('hlsConfig/dashConfig — outgoing contract', () {
      test('omits "hlsConfig"/"dashConfig" keys when not configured', () async {
        final calls = _installCapture();
        final player = MediaPlayer(playerId: 'ch-init-streaming-absent');
        await player.initialize();

        final initCall = calls.firstWhere((c) => c.method == 'initialize');
        final config = initCall.arguments['config'] as Map;
        expect(config.containsKey('hlsConfig'), isFalse);
        expect(config.containsKey('dashConfig'), isFalse);

        player.dispose();
      });

      test('sends "hlsConfig" with its fields when configured', () async {
        final calls = _installCapture();
        final player = MediaPlayer(
          playerId: 'ch-init-hls-config',
          config: const MediaConfig(
            hlsConfig: HlsConfig(
              enableDvr: true,
              liveLatency: Duration(seconds: 4),
              enableAdaptiveBitrate: false,
              maxBitrate: 3000000,
              minBitrate: 500000,
            ),
          ),
        );
        await player.initialize();

        final initCall = calls.firstWhere((c) => c.method == 'initialize');
        final config = initCall.arguments['config'] as Map;
        expect(config.containsKey('hlsConfig'), isTrue);
        expect(config.containsKey('dashConfig'), isFalse);

        final hls = config['hlsConfig'] as Map;
        expect(hls['enableDvr'], isTrue);
        expect(hls['liveLatencyMs'], 4000);
        expect(hls['enableAdaptiveBitrate'], isFalse);
        expect(hls['maxBitrate'], 3000000);
        expect(hls['minBitrate'], 500000);

        player.dispose();
      });

      test('sends "dashConfig" with its fields when configured', () async {
        final calls = _installCapture();
        final player = MediaPlayer(
          playerId: 'ch-init-dash-config',
          config: const MediaConfig(
            dashConfig: DashConfig(
              enableDvr: true,
              liveLatency: Duration(seconds: 6),
            ),
          ),
        );
        await player.initialize();

        final initCall = calls.firstWhere((c) => c.method == 'initialize');
        final config = initCall.arguments['config'] as Map;
        expect(config.containsKey('dashConfig'), isTrue);
        expect(config.containsKey('hlsConfig'), isFalse);

        final dash = config['dashConfig'] as Map;
        expect(dash['enableDvr'], isTrue);
        expect(dash['liveLatencyMs'], 6000);

        player.dispose();
      });

      test('both hlsConfig and dashConfig can be sent together', () async {
        final calls = _installCapture();
        final player = MediaPlayer(
          playerId: 'ch-init-both-streaming-configs',
          config: const MediaConfig(
            hlsConfig: HlsConfig(enableDvr: true),
            dashConfig: DashConfig(enableDvr: false),
          ),
        );
        await player.initialize();

        final initCall = calls.firstWhere((c) => c.method == 'initialize');
        final config = initCall.arguments['config'] as Map;
        expect((config['hlsConfig'] as Map)['enableDvr'], isTrue);
        expect((config['dashConfig'] as Map)['enableDvr'], isFalse);

        player.dispose();
      });
    });
  });

  // -------------------------------------------------------------------------
  group('load — outgoing contract', () {
    test('sends method "load" with playerId and mediaItem fields', () async {
      final calls = _installCapture();
      final player = MediaPlayer(playerId: 'ch-load-1');
      await player.initialize();
      calls.clear(); // ignore initialize calls

      const item = MediaItem(
        id: 'item-abc',
        title: 'Test Video',
        url: 'https://cdn.example.com/video.mp4',
        mediaType: MediaType.video,
      );
      await player.load(item);

      final loadCall = calls.firstWhere((c) => c.method == 'load', orElse: () {
        fail('No "load" call found');
      });

      expect(loadCall.arguments['playerId'], 'ch-load-1');
      final mediaItem = loadCall.arguments['mediaItem'] as Map;
      expect(mediaItem['id'], 'item-abc');
      expect(mediaItem['title'], 'Test Video');
      expect(mediaItem['url'], 'https://cdn.example.com/video.mp4');
      expect(mediaItem['mediaType'], 'video');

      player.dispose();
    });

    test('load serializes drmConfig when present', () async {
      final calls = _installCapture();
      final player = MediaPlayer(playerId: 'ch-load-drm');
      await player.initialize();
      calls.clear();

      final item = MediaItem(
        id: 'drm-item',
        title: 'DRM Video',
        url: 'https://cdn.example.com/protected.mpd',
        drmConfig: DrmConfig.widevine(
          licenseUrl: 'https://license.example.com/widevine',
          headers: {'X-Auth': 'bearer-token'},
        ),
      );
      await player.load(item);

      final loadCall = calls.firstWhere((c) => c.method == 'load');
      final mediaItem = loadCall.arguments['mediaItem'] as Map;
      final drmConfig = mediaItem['drmConfig'] as Map;
      expect(drmConfig['scheme'], 'widevine');
      expect(drmConfig['licenseUrl'], 'https://license.example.com/widevine');
      expect((drmConfig['headers'] as Map)['X-Auth'], 'bearer-token');

      player.dispose();
    });

    test('load serializes certificatePinning when present', () async {
      final calls = _installCapture();
      final player = MediaPlayer(playerId: 'ch-load-pin');
      await player.initialize();
      calls.clear();

      // CertificatePinningConfig uses domain→pins map with 64-char hex pins.
      const fakePin =
          'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
      final pinCfg = CertificatePinningConfig(
        pins: {
          'license.example.com': [fakePin, fakePin],
        },
        minimumPins: 1,
      );
      final item = MediaItem(
        id: 'pin-item',
        title: 'Pinned Video',
        url: 'https://cdn.example.com/video.mpd',
        drmConfig: DrmConfig.widevine(
          licenseUrl: 'https://license.example.com/widevine',
          certificatePinning: pinCfg,
        ),
      );
      await player.load(item);

      final loadCall = calls.firstWhere((c) => c.method == 'load');
      final mediaItem = loadCall.arguments['mediaItem'] as Map;
      final drmConfig = mediaItem['drmConfig'] as Map;
      final pinning = drmConfig['certificatePinning'] as Map?;
      expect(pinning, isNotNull,
          reason: 'certificatePinning must be serialised into drmConfig');
      // The pins map must contain the domain we configured.
      final pinsMap = pinning!['pins'] as Map?;
      expect(pinsMap, isNotNull);

      player.dispose();
    });

    test(
        'load with http:// DRM URL throws ConfigurationException before any load call',
        () async {
      final calls = _installCapture();
      final player = MediaPlayer(playerId: 'ch-load-http-drm');
      await player.initialize();
      calls.clear();

      final insecureItem = MediaItem(
        id: 'insecure-item',
        title: 'Insecure',
        url: 'http://cdn.example.com/protected.mpd', // HTTP, not HTTPS
        drmConfig: DrmConfig.widevine(
          licenseUrl: 'https://license.example.com/widevine',
        ),
      );

      await expectLater(
        player.load(insecureItem),
        throwsA(isA<ConfigurationException>()),
        reason: 'DRM + HTTP URL must throw ConfigurationException',
      );

      final loadCalls = calls.where((c) => c.method == 'load').toList();
      expect(loadCalls, isEmpty,
          reason:
              'No "load" call must reach the channel when validation fails');

      player.dispose();
    });

    test('load with https:// DRM URL sends "load" to the channel', () async {
      final calls = _installCapture();
      final player = MediaPlayer(playerId: 'ch-load-https-drm');
      await player.initialize();
      calls.clear();

      final secureItem = MediaItem(
        id: 'secure-item',
        title: 'Secure DRM',
        url: 'https://cdn.example.com/protected.mpd',
        drmConfig: DrmConfig.widevine(
          licenseUrl: 'https://license.example.com/widevine',
        ),
      );
      await player.load(secureItem);

      expect(calls.any((c) => c.method == 'load'), isTrue,
          reason: 'HTTPS DRM item must produce a "load" channel call');

      player.dispose();
    });
  });

  // -------------------------------------------------------------------------
  group('play / pause / stop — outgoing contract', () {
    test('play sends method "play" with playerId', () async {
      final calls = _installCapture();
      final player = MediaPlayer(playerId: 'ch-play-1');
      await player.initialize();
      calls.clear();

      await player.play();

      final call = calls.firstWhere((c) => c.method == 'play', orElse: () {
        fail('No "play" call found');
      });
      expect(call.arguments['playerId'], 'ch-play-1');

      player.dispose();
    });

    test('pause sends method "pause" with playerId', () async {
      final calls = _installCapture();
      final player = MediaPlayer(playerId: 'ch-pause-1');
      await player.initialize();
      calls.clear();

      await player.pause();

      final call = calls.firstWhere((c) => c.method == 'pause', orElse: () {
        fail('No "pause" call found');
      });
      expect(call.arguments['playerId'], 'ch-pause-1');

      player.dispose();
    });

    test('stop sends method "stop" with playerId', () async {
      final calls = _installCapture();
      final player = MediaPlayer(playerId: 'ch-stop-1');
      await player.initialize();
      calls.clear();

      await player.stop();

      final call = calls.firstWhere((c) => c.method == 'stop', orElse: () {
        fail('No "stop" call found');
      });
      expect(call.arguments['playerId'], 'ch-stop-1');

      player.dispose();
    });
  });

  // -------------------------------------------------------------------------
  group('seekTo — outgoing contract', () {
    test('sends method "seekTo" with position in milliseconds', () async {
      final calls = _installCapture();
      final player = MediaPlayer(playerId: 'ch-seek-1');
      await player.initialize();
      calls.clear();

      await player.seekTo(const Duration(seconds: 30));

      final call = calls.firstWhere((c) => c.method == 'seekTo', orElse: () {
        fail('No "seekTo" call found');
      });
      expect(call.arguments['playerId'], 'ch-seek-1');
      expect(call.arguments['position'], 30000);

      player.dispose();
    });

    test('negative seekTo throws without sending to channel', () async {
      final calls = _installCapture();
      final player = MediaPlayer(playerId: 'ch-seek-neg');
      await player.initialize();
      calls.clear();

      await expectLater(
        player.seekTo(const Duration(seconds: -1)),
        throwsA(isA<ConfigurationException>()),
      );
      expect(calls.where((c) => c.method == 'seekTo'), isEmpty);

      player.dispose();
    });
  });

  // -------------------------------------------------------------------------
  group('setVolume — outgoing contract + clamping', () {
    test('sends method "setVolume" with volume value', () async {
      final calls = _installCapture();
      final player = MediaPlayer(playerId: 'ch-vol-1');
      await player.initialize();
      calls.clear();

      await player.setVolume(0.7);

      final call = calls.firstWhere((c) => c.method == 'setVolume', orElse: () {
        fail('No "setVolume" call found');
      });
      expect(call.arguments['playerId'], 'ch-vol-1');
      expect(call.arguments['volume'], closeTo(0.7, 0.001));

      player.dispose();
    });

    test('volume > 1.0 is clamped to 1.0 before native call', () async {
      final calls = _installCapture();
      final player = MediaPlayer(playerId: 'ch-vol-clamp-high');
      await player.initialize();
      calls.clear();

      await player.setVolume(2.5);

      final call = calls.firstWhere((c) => c.method == 'setVolume');
      expect(call.arguments['volume'], closeTo(1.0, 0.001),
          reason: 'Values above 1.0 must be clamped to 1.0');

      player.dispose();
    });

    test('volume < 0.0 is clamped to 0.0 before native call', () async {
      final calls = _installCapture();
      final player = MediaPlayer(playerId: 'ch-vol-clamp-low');
      await player.initialize();
      calls.clear();

      await player.setVolume(-0.5);

      final call = calls.firstWhere((c) => c.method == 'setVolume');
      expect(call.arguments['volume'], closeTo(0.0, 0.001),
          reason: 'Negative values must be clamped to 0.0');

      player.dispose();
    });
  });

  // -------------------------------------------------------------------------
  group('setSpeed — outgoing contract + clamping', () {
    test('sends method "setSpeed" with speed value', () async {
      final calls = _installCapture();
      final player = MediaPlayer(playerId: 'ch-speed-1');
      await player.initialize();
      calls.clear();

      await player.setSpeed(1.5);

      final call = calls.firstWhere((c) => c.method == 'setSpeed', orElse: () {
        fail('No "setSpeed" call found');
      });
      expect(call.arguments['playerId'], 'ch-speed-1');
      expect(call.arguments['speed'], closeTo(1.5, 0.001));

      player.dispose();
    });

    test('speed above 4.0 is clamped to 4.0', () async {
      final calls = _installCapture();
      final player = MediaPlayer(playerId: 'ch-speed-clamp-high');
      await player.initialize();
      calls.clear();

      await player.setSpeed(10.0);

      final call = calls.firstWhere((c) => c.method == 'setSpeed');
      expect(call.arguments['speed'], closeTo(4.0, 0.001),
          reason: 'Speed above 4.0 must be clamped to 4.0');

      player.dispose();
    });

    test('speed below 0.25 is clamped to 0.25', () async {
      final calls = _installCapture();
      final player = MediaPlayer(playerId: 'ch-speed-clamp-low');
      await player.initialize();
      calls.clear();

      await player.setSpeed(0.0);

      final call = calls.firstWhere((c) => c.method == 'setSpeed');
      expect(call.arguments['speed'], closeTo(0.25, 0.001),
          reason: 'Speed below 0.25 must be clamped to 0.25');

      player.dispose();
    });
  });

  // -------------------------------------------------------------------------
  group('load / setPlaylist — speed reset guard', () {
    // Regression coverage for the iOS "setSpeed defeats autoPlay" bug: the
    // load-time speed reset to 1.0x must be skipped when the tracked speed
    // is already 1.0 (the common case), and must still fire once the tracked
    // speed has genuinely diverged from 1.0.
    const item = MediaItem(
      id: 'speed-guard-item',
      title: 'Speed Guard Video',
      url: 'https://cdn.example.com/video.mp4',
      mediaType: MediaType.video,
    );

    test('load does not send "setSpeed" when speed is already 1.0', () async {
      final calls = _installCapture();
      final player = MediaPlayer(playerId: 'ch-load-speed-noop');
      await player.initialize();
      calls.clear();

      await player.load(item);

      expect(calls.where((c) => c.method == 'setSpeed'), isEmpty,
          reason: 'load() must not reset speed when it is already 1.0x — '
              'the round trip is pure overhead and, on iOS, was what '
              'defeated autoPlay: false');

      player.dispose();
    });

    test('load sends exactly one "setSpeed" after a real speed change',
        () async {
      final calls = _installCapture();
      final player = MediaPlayer(playerId: 'ch-load-speed-reset');
      await player.initialize();
      calls.clear();

      await player.setSpeed(2.0);
      calls.clear(); // ignore the explicit setSpeed(2.0) call itself

      await player.load(item);

      final setSpeedCalls = calls.where((c) => c.method == 'setSpeed').toList();
      expect(setSpeedCalls.length, 1,
          reason: 'load() must reset speed back to 1.0x exactly once when '
              'the tracked speed diverged from 1.0');
      expect(setSpeedCalls.single.arguments['speed'], closeTo(1.0, 0.001));

      player.dispose();
    });

    test('setPlaylist does not send "setSpeed" when speed is already 1.0',
        () async {
      final calls = _installCapture();
      final player = MediaPlayer(playerId: 'ch-playlist-speed-noop');
      await player.initialize();
      calls.clear();

      const playlist = Playlist(
        id: 'speed-guard-playlist',
        title: 'Speed Guard Playlist',
        items: [item],
      );
      await player.setPlaylist(playlist);

      expect(calls.where((c) => c.method == 'setSpeed'), isEmpty,
          reason: 'setPlaylist() must not reset speed when it is already '
              '1.0x');

      player.dispose();
    });

    test('setPlaylist sends exactly one "setSpeed" after a real speed change',
        () async {
      final calls = _installCapture();
      final player = MediaPlayer(playerId: 'ch-playlist-speed-reset');
      await player.initialize();
      calls.clear();

      await player.setSpeed(1.5);
      calls.clear(); // ignore the explicit setSpeed(1.5) call itself

      const playlist = Playlist(
        id: 'speed-guard-playlist-2',
        title: 'Speed Guard Playlist 2',
        items: [item],
      );
      await player.setPlaylist(playlist);

      final setSpeedCalls = calls.where((c) => c.method == 'setSpeed').toList();
      expect(setSpeedCalls.length, 1,
          reason: 'setPlaylist() must reset speed back to 1.0x exactly once '
              'when the tracked speed diverged from 1.0');
      expect(setSpeedCalls.single.arguments['speed'], closeTo(1.0, 0.001));

      player.dispose();
    });
  });

  // -------------------------------------------------------------------------
  group('setQualityTrack / setAudioTrack / enableAutoQuality', () {
    // Inject tracks into the player via the platform event path so the
    // validation in setQualityTrack / setAudioTrack can succeed.
    Future<void> injectQualityTracks(
        String playerId, List<Map<String, dynamic>> tracks) async {
      final codec = const StandardMethodCodec();
      final data = codec.encodeMethodCall(MethodCall(
        'onQualityTracksChanged',
        {'playerId': playerId, 'tracks': tracks},
      ));
      await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .handlePlatformMessage('zmedia_player', data, (_) {});
    }

    Future<void> injectAudioTracks(
        String playerId, List<Map<String, dynamic>> tracks) async {
      final codec = const StandardMethodCodec();
      final data = codec.encodeMethodCall(MethodCall(
        'onAudioTracksChanged',
        {'playerId': playerId, 'tracks': tracks},
      ));
      await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .handlePlatformMessage('zmedia_player', data, (_) {});
    }

    test('setQualityTrack sends "setQualityTrack" with qualityTrack map',
        () async {
      final calls = _installCapture();
      final player = MediaPlayer(playerId: 'ch-qt-1');
      await player.initialize();
      calls.clear();

      const track = QualityTrack(
        id: 'q-1080',
        name: 'Full HD',
        bitrate: 5000000,
        width: 1920,
        height: 1080,
      );

      await injectQualityTracks(
        'ch-qt-1',
        [
          {
            'id': 'q-1080',
            'name': 'Full HD',
            'bitrate': 5000000,
            'width': 1920,
            'height': 1080,
            'isSelected': false,
            'isAvailable': true,
          }
        ],
      );

      await player.setQualityTrack(track);

      final call =
          calls.firstWhere((c) => c.method == 'setQualityTrack', orElse: () {
        fail('No "setQualityTrack" call found');
      });
      expect(call.arguments['playerId'], 'ch-qt-1');
      final qt = call.arguments['qualityTrack'] as Map;
      expect(qt['id'], 'q-1080');
      expect(qt['bitrate'], 5000000);

      player.dispose();
    });

    test('setAudioTrack sends "setAudioTrack" with audioTrack map', () async {
      final calls = _installCapture();
      final player = MediaPlayer(playerId: 'ch-at-1');
      await player.initialize();
      calls.clear();

      const track = AudioTrack(
        id: 'a-en',
        name: 'English',
        language: 'en',
      );

      await injectAudioTracks(
        'ch-at-1',
        [
          {
            'id': 'a-en',
            'name': 'English',
            'language': 'en',
            'isSelected': false,
            'isAvailable': true,
          }
        ],
      );

      await player.setAudioTrack(track);

      final call =
          calls.firstWhere((c) => c.method == 'setAudioTrack', orElse: () {
        fail('No "setAudioTrack" call found');
      });
      expect(call.arguments['playerId'], 'ch-at-1');
      final at = call.arguments['audioTrack'] as Map;
      expect(at['id'], 'a-en');
      expect(at['language'], 'en');

      player.dispose();
    });

    test('enableAutoQuality sends "enableAutoQuality" with playerId', () async {
      final calls = _installCapture();
      final player = MediaPlayer(playerId: 'ch-auto-q');
      await player.initialize();
      calls.clear();

      await player.enableAutoQuality();

      final call =
          calls.firstWhere((c) => c.method == 'enableAutoQuality', orElse: () {
        fail('No "enableAutoQuality" call found');
      });
      expect(call.arguments['playerId'], 'ch-auto-q');

      player.dispose();
    });
  });

  // -------------------------------------------------------------------------
  // Wave B: _ensureCastInitialized previously sent a freshly-constructed
  // `const CastConfig()` default instead of the user's
  // `MediaConfig.castConfig`, silently discarding every field the caller
  // set (chromecastAppId, enableChromecast, enableAirPlay, etc). Pin down
  // that the user's config — not a default — now reaches the channel.
  group('cast — user castConfig reaches initializeCast (not a default)', () {
    test('sends the configured castConfig, including chromecastAppId',
        () async {
      final calls = _installCapture();
      final player = MediaPlayer(
        playerId: 'cast-user-config-1',
        config: const MediaConfig(
          castConfig: CastConfig(
            enabled: true,
            enableChromecast: true,
            enableAirPlay: false,
            showCastButton: false,
            discoveryTimeout: 42,
            chromecastAppId: 'DISTINCTIVE-APP-ID-1234',
          ),
        ),
      );
      await player.initialize();
      calls.clear();

      await player.startCastDiscovery();

      final initCall = calls.firstWhere((c) => c.method == 'initializeCast');
      final config = initCall.arguments['config'] as Map;
      expect(config['chromecastAppId'], 'DISTINCTIVE-APP-ID-1234',
          reason: 'The configured chromecastAppId must reach native code, '
              'not be dropped in favor of a default CastConfig()');
      expect(config['enableAirPlay'], false);
      expect(config['showCastButton'], false);
      expect(config['discoveryTimeout'], 42);

      player.dispose();
    });

    test('sends a default CastConfig when none is configured', () async {
      final calls = _installCapture();
      final player = MediaPlayer(playerId: 'cast-user-config-2');
      await player.initialize();
      calls.clear();

      await player.startCastDiscovery();

      final initCall = calls.firstWhere((c) => c.method == 'initializeCast');
      final config = initCall.arguments['config'] as Map;
      expect(config['chromecastAppId'], isNull);
      expect(config['enabled'], true);
      expect(config['enableChromecast'], true);
      expect(config['enableAirPlay'], true);

      player.dispose();
    });
  });

  group('cast — lazy initializeCast before cast operations', () {
    test(
        'startCastDiscovery sends "initializeCast" before "startCastDiscovery"',
        () async {
      final calls = _installCapture();
      final player = MediaPlayer(playerId: 'cast-lazy-init-1');
      await player.initialize();
      calls.clear(); // ignore initialize calls

      await player.startCastDiscovery();

      final methods = calls.map((c) => c.method).toList();
      expect(methods, contains('initializeCast'),
          reason: 'initializeCast must be called before startCastDiscovery');
      expect(methods, contains('startCastDiscovery'),
          reason: 'startCastDiscovery must be forwarded to the channel');

      final initIdx = methods.indexOf('initializeCast');
      final discIdx = methods.indexOf('startCastDiscovery');
      expect(initIdx < discIdx, isTrue,
          reason: '"initializeCast" must precede "startCastDiscovery"');

      // Verify initializeCast sends the required payload.
      final initCall = calls[initIdx];
      expect(initCall.arguments['playerId'], 'cast-lazy-init-1');
      expect(initCall.arguments['config'], isNotNull,
          reason: '"config" map must be present (native requires it non-null)');

      player.dispose();
    });

    test('second startCastDiscovery does NOT send a second "initializeCast"',
        () async {
      final calls = _installCapture();
      final player = MediaPlayer(playerId: 'cast-lazy-init-2');
      await player.initialize();
      calls.clear();

      await player.startCastDiscovery();
      await player.startCastDiscovery(); // second call — handler already live

      final initCalls =
          calls.where((c) => c.method == 'initializeCast').toList();
      expect(initCalls.length, 1,
          reason: '"initializeCast" must only be sent once regardless of how '
              'many times startCastDiscovery is called');

      player.dispose();
    });

    test(
        'connectToCastDevice also triggers initializeCast when not yet '
        'initialized', () async {
      final calls = _installCapture((call) async {
        if (call.method == 'connectToCastDevice') return true;
        return null;
      });
      final player = MediaPlayer(playerId: 'cast-lazy-connect-1');
      await player.initialize();
      calls.clear();

      const device = CastDevice(
        id: 'd-1',
        name: 'Living Room TV',
        type: CastDeviceType.chromecast,
      );
      await player.connectToCastDevice(device);

      expect(calls.map((c) => c.method), contains('initializeCast'),
          reason: 'connectToCastDevice must also trigger lazy cast init');

      player.dispose();
    });

    test(
        'initializeCast is NOT sent twice when connectToCastDevice follows '
        'startCastDiscovery', () async {
      final calls = _installCapture((call) async {
        if (call.method == 'connectToCastDevice') return true;
        return null;
      });
      final player = MediaPlayer(playerId: 'cast-lazy-no-double');
      await player.initialize();
      calls.clear();

      await player.startCastDiscovery();
      const device = CastDevice(
        id: 'd-2',
        name: 'Bedroom TV',
        type: CastDeviceType.chromecast,
      );
      await player.connectToCastDevice(device);

      final initCalls =
          calls.where((c) => c.method == 'initializeCast').toList();
      expect(initCalls.length, 1,
          reason:
              '"initializeCast" must be sent only once even across different '
              'cast operations on the same player');

      player.dispose();
    });
  });

  // -------------------------------------------------------------------------
  group('dispose — outgoing contract', () {
    test('sends method "dispose" with playerId when initialized', () async {
      final calls = _installCapture();
      final player = MediaPlayer(playerId: 'ch-dispose-1');
      await player.initialize();
      calls.clear();

      await player.dispose();

      final call = calls.firstWhere((c) => c.method == 'dispose', orElse: () {
        fail('No "dispose" call found');
      });
      expect(call.arguments['playerId'], 'ch-dispose-1');
    });

    test('dispose without initialize does NOT send "dispose" to channel',
        () async {
      final calls = _installCapture();
      final player = MediaPlayer(playerId: 'ch-dispose-uninit');
      await player.dispose(); // never initialized

      expect(calls.where((c) => c.method == 'dispose'), isEmpty,
          reason: 'No channel call expected for uninitialized player');
    });

    test('dispose is idempotent — safe to call twice', () async {
      final calls = _installCapture();
      final player = MediaPlayer(playerId: 'ch-dispose-idempotent');
      await player.initialize();
      calls.clear();

      await player.dispose();
      await player.dispose(); // second call is a no-op

      final disposeCalls = calls.where((c) => c.method == 'dispose').toList();
      expect(disposeCalls.length, 1);
    });
  });

  // -------------------------------------------------------------------------
  group('factory — auto-generated playerId uniqueness (B-10 regression)', () {
    test(
        'two MediaPlayer() calls with no explicit id, constructed back-to-back '
        'in a tight loop, are distinct objects with distinct ids', () async {
      // Constructing synchronously in a tight loop is the realistic repro
      // for the collision: the previous implementation generated ids from
      // DateTime.now().millisecondsSinceEpoch, and multiple players built
      // within the same event-loop tick (e.g. a ListView of players in one
      // frame) could receive an identical timestamp-derived id. When that
      // happened, the factory's existing-instance branch silently returned
      // the *first* player for the second caller, aliasing two logically
      // independent players onto one native instance.
      final players = List.generate(50, (_) => MediaPlayer());

      final ids = players.map((p) => p.playerId).toSet();
      expect(ids.length, players.length,
          reason: 'every auto-generated playerId must be unique, even when '
              'constructed synchronously in the same millisecond');

      final identitySet = players.map(identityHashCode).toSet();
      expect(identitySet.length, players.length,
          reason: 'every MediaPlayer() call with no explicit id must return '
              'a distinct object — a collision would alias two players onto '
              'one instance');

      for (final p in players) {
        await p.dispose();
      }
    });

    test(
        'an explicitly-passed playerId still returns the same instance on a '
        'second call', () async {
      final first = MediaPlayer(playerId: 'explicit-reuse-id');
      final second = MediaPlayer(playerId: 'explicit-reuse-id');

      expect(identical(first, second), isTrue,
          reason: 'explicit playerId must keep returning the existing, '
              'non-disposed instance — this is documented singleton-per-'
              'playerId behaviour and must not be broken by the auto-id fix');
      expect(second.playerId, 'explicit-reuse-id');

      await first.dispose();
    });

    test(
        'auto-generated ids remain unique across a create -> dispose -> '
        'create cycle', () async {
      final first = MediaPlayer();
      final firstId = first.playerId;
      await first.dispose();

      final second = MediaPlayer();
      final secondId = second.playerId;

      expect(secondId, isNot(equals(firstId)),
          reason: 'a disposed instance\'s id must never be reissued to a '
              'newly-created instance');
      expect(identical(first, second), isFalse);

      await second.dispose();
    });
  });
}
