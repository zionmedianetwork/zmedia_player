// Regression tests for the playlist-path config staleness fix (issue #82).
//
// `MediaPlayer.load()` has always carried the current `MediaConfig` snapshot
// under a 'config' key on every call, so a rebuilt config (e.g. flipping
// `hlsConfig.enableDvr`) reaches native without a separate `updateConfig()`
// call. The playlist entry points did NOT: 'setPlaylist' sent only
// `{playerId, playlist, startIndex}` and 'skipToIndex' only
// `{playerId, index}`, yet native loads `items[startIndex]` /
// `playlist[index]` through the very same `loadMediaItem` the 'load' path
// uses. The result was silent: playback worked, but against whatever config
// native happened to be holding from `initialize()`/the last explicit
// `updateConfig()` call.
//
// These tests pin the wire contract, which is the only place this class of
// defect is observable from Dart — the native side is mocked here (as it is
// in every test in this suite), so the corresponding Kotlin/Swift reads of
// the key still need on-device verification.
//
// Harness: same pattern as media_player_channel_test.dart /
// playback_completion_test.dart.

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zmedia_player/zmedia_player.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

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

/// Injects a native→Dart event through the test binary messenger.
Future<void> _injectEvent(String method, Map<String, dynamic> arguments) async {
  const codec = StandardMethodCodec();
  final data = codec.encodeMethodCall(MethodCall(method, arguments));
  await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .handlePlatformMessage('zmedia_player', data, (_) {});
}

Future<void> _injectCompleted(String playerId) => _injectEvent(
      'onStateChanged',
      {
        'playerId': playerId,
        'state': 'completed',
        'isBuffering': false,
        'bufferPercentage': 100.0,
      },
    );

const _liveItems = [
  MediaItem(
    id: 'live-0',
    title: 'Live 0',
    url: 'https://cdn.example.com/live0.m3u8',
    isLive: true,
  ),
  MediaItem(
    id: 'live-1',
    title: 'Live 1',
    url: 'https://cdn.example.com/live1.m3u8',
    isLive: true,
  ),
  MediaItem(
    id: 'live-2',
    title: 'Live 2',
    url: 'https://cdn.example.com/live2.m3u8',
    isLive: true,
  ),
];

Playlist _playlist({int currentIndex = 0}) => Playlist(
      id: 'pl-config-snapshot',
      title: 'Config Snapshot Playlist',
      items: _liveItems,
      currentIndex: currentIndex,
      mode: PlaybackMode.sequential,
      repeatMode: MediaRepeatMode.none,
    );

const _dvrOnConfig = MediaConfig(
  hlsConfig: HlsConfig(
    enableDvr: true,
    liveLatency: Duration(seconds: 6),
    maxBitrate: 4000000,
  ),
);

const _dvrOffConfig = MediaConfig(
  hlsConfig: HlsConfig(enableDvr: false),
);

Map _configOf(MethodCall call) => call.arguments['config'] as Map;

Map _hlsOf(MethodCall call) => _configOf(call)['hlsConfig'] as Map;

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(_resetHandler);

  // =========================================================================
  group('setPlaylist carries the current config snapshot', () {
    test('sends "config" alongside playlist/startIndex', () async {
      final calls = _installCapture();
      final player = MediaPlayer(
        playerId: 'pl-cfg-setplaylist-present',
        config: _dvrOnConfig,
      );
      await player.initialize();
      calls.clear();

      await player.setPlaylist(_playlist());

      final call = calls.firstWhere((c) => c.method == 'setPlaylist',
          orElse: () => fail('No "setPlaylist" call found'));

      expect(call.arguments.containsKey('config'), isTrue,
          reason: 'native loads items[startIndex] through the same '
              'loadMediaItem the load path uses, so it must receive the '
              'config that applies to THIS load rather than a stale copy '
              'from initialize()/the last updateConfig() call');

      final hls = _hlsOf(call);
      expect(hls['enableDvr'], isTrue);
      expect(hls['liveLatencyMs'], 6000);
      expect(hls['maxBitrate'], 4000000);

      player.dispose();
    });

    test('config map matches what "load" sends for the same player', () async {
      final calls = _installCapture();
      final player = MediaPlayer(
        playerId: 'pl-cfg-setplaylist-parity',
        config: _dvrOnConfig,
      );
      await player.initialize();

      calls.clear();
      await player.load(_liveItems.first);
      final loadConfig = _configOf(calls.firstWhere((c) => c.method == 'load'));

      calls.clear();
      await player.setPlaylist(_playlist());
      final playlistConfig =
          _configOf(calls.firstWhere((c) => c.method == 'setPlaylist'));

      expect(playlistConfig, equals(loadConfig),
          reason: 'both paths serialize the same MediaPlayer._config field, '
              'so the playlist payload must be byte-for-byte the same '
              'config the load payload carries — one wire shape, not two');

      player.dispose();
    });

    test('still carries "playerId"/"playlist"/"startIndex" unchanged',
        () async {
      final calls = _installCapture();
      final player = MediaPlayer(playerId: 'pl-cfg-setplaylist-shape');
      await player.initialize();
      calls.clear();

      await player.setPlaylist(_playlist(), startIndex: 2);

      final call = calls.firstWhere((c) => c.method == 'setPlaylist');
      expect(call.arguments['playerId'], 'pl-cfg-setplaylist-shape');
      expect(call.arguments['startIndex'], 2);
      expect((call.arguments['playlist'] as Map)['id'], 'pl-config-snapshot');
      expect(call.arguments.containsKey('config'), isTrue,
          reason: 'adding "config" must be purely additive — the pre-existing '
              'keys stay exactly as they were');

      player.dispose();
    });
  });

  // =========================================================================
  group('skipToIndex carries the current config snapshot', () {
    test('sends "config" alongside index', () async {
      final calls = _installCapture();
      final player = MediaPlayer(
        playerId: 'pl-cfg-skiptoindex',
        config: _dvrOnConfig,
      );
      await player.initialize();
      await player.setPlaylist(_playlist());
      calls.clear();

      await player.skipToIndex(1);

      final call = calls.firstWhere((c) => c.method == 'skipToIndex',
          orElse: () => fail('No "skipToIndex" call found'));

      expect(call.arguments['index'], 1);
      expect(call.arguments.containsKey('config'), isTrue,
          reason: 'native loads playlist[index] through the same '
              'loadMediaItem the load path uses');
      expect(_hlsOf(call)['enableDvr'], isTrue);
      expect(_hlsOf(call)['liveLatencyMs'], 6000);

      player.dispose();
    });

    test('skipToNext carries the config snapshot', () async {
      final calls = _installCapture();
      final player = MediaPlayer(
        playerId: 'pl-cfg-skipnext',
        config: _dvrOnConfig,
      );
      await player.initialize();
      await player.setPlaylist(_playlist());
      calls.clear();

      await player.skipToNext();

      final call = calls.firstWhere((c) => c.method == 'skipToIndex',
          orElse: () => fail('No "skipToIndex" call found for skipToNext'));
      expect(call.arguments['index'], 1);
      expect(_hlsOf(call)['enableDvr'], isTrue);

      player.dispose();
    });

    test('skipToPrevious carries the config snapshot', () async {
      final calls = _installCapture();
      final player = MediaPlayer(
        playerId: 'pl-cfg-skipprev',
        config: _dvrOnConfig,
      );
      await player.initialize();
      await player.setPlaylist(_playlist(), startIndex: 2);
      calls.clear();

      await player.skipToPrevious();

      final call = calls.firstWhere((c) => c.method == 'skipToIndex',
          orElse: () => fail('No "skipToIndex" call found for skipToPrevious'));
      expect(call.arguments['index'], 1);
      expect(_hlsOf(call)['enableDvr'], isTrue);

      player.dispose();
    });

    test('playlist auto-advance on completion carries the config snapshot',
        () async {
      final calls = _installCapture();
      final player = MediaPlayer(
        playerId: 'pl-cfg-autoadvance',
        config: _dvrOnConfig,
      );
      await player.initialize();
      await player.setPlaylist(_playlist());
      calls.clear();

      await _injectCompleted('pl-cfg-autoadvance');
      // The auto-advance is async (then chain); let the microtask queue drain.
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      final call = calls.firstWhere((c) => c.method == 'skipToIndex',
          orElse: () => fail('No "skipToIndex" call found for auto-advance'));
      expect(call.arguments['index'], 1);
      expect(call.arguments.containsKey('config'), isTrue,
          reason: 'auto-advance funnels through skipToIndex, so it inherits '
              'the same config snapshot rather than being a third, '
              'config-less load path');
      expect(_hlsOf(call)['enableDvr'], isTrue);

      player.dispose();
    });
  });

  // =========================================================================
  group('a config rebuilt between calls reaches the next playlist payload', () {
    test('toggling hlsConfig.enableDvr changes the next "setPlaylist" payload',
        () async {
      final calls = _installCapture();
      final player = MediaPlayer(
        playerId: 'pl-cfg-toggle-setplaylist',
        config: _dvrOffConfig,
      );
      await player.initialize();

      calls.clear();
      await player.setPlaylist(_playlist());
      expect(
        _hlsOf(calls.firstWhere((c) => c.method == 'setPlaylist'))['enableDvr'],
        isFalse,
        reason: 'DVR off must reach native on the first setPlaylist',
      );

      // Host rebuilds its MediaConfig with DVR on, then sets a playlist
      // again — the exact pattern that used to leave native's config stale
      // for playlist-driven items.
      await player.updateConfig(_dvrOnConfig);

      calls.clear();
      await player.setPlaylist(_playlist());
      expect(
        _hlsOf(calls.firstWhere((c) => c.method == 'setPlaylist'))['enableDvr'],
        isTrue,
        reason: 'DVR on must reach native on the very next setPlaylist() '
            'call, with no stale copy left behind',
      );

      player.dispose();
    });

    test('toggling hlsConfig.enableDvr changes the next "skipToIndex" payload',
        () async {
      final calls = _installCapture();
      final player = MediaPlayer(
        playerId: 'pl-cfg-toggle-skiptoindex',
        config: _dvrOffConfig,
      );
      await player.initialize();
      await player.setPlaylist(_playlist());

      calls.clear();
      await player.skipToIndex(1);
      expect(
        _hlsOf(calls.firstWhere((c) => c.method == 'skipToIndex'))['enableDvr'],
        isFalse,
      );

      await player.updateConfig(_dvrOnConfig);

      calls.clear();
      await player.skipToIndex(2);
      final second = calls.firstWhere((c) => c.method == 'skipToIndex');
      expect(second.arguments['index'], 2);
      expect(_hlsOf(second)['enableDvr'], isTrue,
          reason: 'a config rebuilt between two playlist advances must be '
              'honored by the second one');

      player.dispose();
    });

    test('dashConfig and top-level fields travel on the playlist path too',
        () async {
      final calls = _installCapture();
      final player = MediaPlayer(
        playerId: 'pl-cfg-dash-and-top-level',
        config: const MediaConfig(
          looping: true,
          volume: 0.25,
          dashConfig: DashConfig(enableDvr: true, maxBitrate: 1500000),
        ),
      );
      await player.initialize();
      calls.clear();

      await player.setPlaylist(_playlist());

      final config =
          _configOf(calls.firstWhere((c) => c.method == 'setPlaylist'));
      expect(config['looping'], isTrue);
      expect(config['volume'], 0.25);
      final dash = config['dashConfig'] as Map;
      expect(dash['enableDvr'], isTrue);
      expect(dash['maxBitrate'], 1500000);

      player.dispose();
    });
  });
}
