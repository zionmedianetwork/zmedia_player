import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zmedia_player/zmedia_player.dart';

/// Regression tests for B-11 and M-07.
///
/// B-11 (BLOCKER): `InputValidator` previously ran on exactly one load path
/// (`MediaPlayer.load()`), so `setPlaylist()` and the cast entry points sent
/// every item's url/drmConfig/httpHeaders to native completely unvalidated —
/// the "DRM requires HTTPS" invariant did not actually hold for
/// playlist-driven or cast-driven playback.
///
/// M-07: the cast path forwards only id/title/url/artwork/duration to the
/// receiver with no DRM session at all, so casting a DRM-protected item must
/// be refused outright rather than silently exposed to an unauthenticated
/// receiver.
// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

const _channel = MethodChannel('zmedia_player');

typedef _HandlerFn = Future<dynamic> Function(MethodCall);

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

const _widevineConfig = DrmConfig(
  scheme: DrmScheme.widevine,
  licenseUrl: 'https://license.example.com/widevine',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(_resetHandler);

  group('setPlaylist validation (B-11)', () {
    test(
        'throws ConfigurationException and never calls native when an item '
        'carries DRM over http://, even when it is not the first item',
        () async {
      final calls = _installCapture();
      final player = MediaPlayer(playerId: 'bulk-playlist-drm-http');
      await player.initialize();
      calls.clear();

      final playlist = Playlist(
        id: 'pl-1',
        title: 'Mixed playlist',
        items: [
          const MediaItem(
            id: 'safe-item',
            title: 'Safe',
            url: 'https://cdn.example.com/safe.mp4',
          ),
          MediaItem(
            id: 'unsafe-drm-item',
            title: 'Unsafe DRM over HTTP',
            url: 'http://media.example.com/protected.mpd',
            drmConfig: _widevineConfig,
          ),
        ],
      );

      await expectLater(
        () => player.setPlaylist(playlist),
        throwsA(isA<ConfigurationException>()),
      );

      expect(
        calls.where((c) => c.method == 'setPlaylist'),
        isEmpty,
        reason: 'An invalid playlist must never reach native',
      );

      player.dispose();
    });

    test('sends setPlaylist when every item passes validation', () async {
      final calls = _installCapture();
      final player = MediaPlayer(playerId: 'bulk-playlist-valid');
      await player.initialize();
      calls.clear();

      final playlist = Playlist(
        id: 'pl-2',
        title: 'Valid playlist',
        items: [
          const MediaItem(
            id: 'item-1',
            title: 'One',
            url: 'https://cdn.example.com/one.mp4',
          ),
          MediaItem(
            id: 'item-2-drm',
            title: 'Two (DRM)',
            url: 'https://cdn.example.com/two.mpd',
            drmConfig: _widevineConfig,
          ),
        ],
      );

      await player.setPlaylist(playlist);

      expect(calls.where((c) => c.method == 'setPlaylist'), isNotEmpty);

      player.dispose();
    });
  });

  group('loadMediaOnCastDevice DRM gate (M-07) and validation (B-11)', () {
    test(
        'throws ConfigurationException and never calls native for a '
        'DRM-protected item', () async {
      final calls = _installCapture();
      final player = MediaPlayer(playerId: 'bulk-cast-drm');
      await player.initialize();
      calls.clear();

      final item = MediaItem(
        id: 'cast-drm-item',
        title: 'Protected',
        url: 'https://cdn.example.com/protected.mpd',
        drmConfig: _widevineConfig,
      );

      await expectLater(
        () => player.loadMediaOnCastDevice(item),
        throwsA(isA<ConfigurationException>()),
      );

      expect(
        calls.where((c) => c.method == 'loadMediaOnCastDevice'),
        isEmpty,
        reason: 'DRM-protected content must never reach the cast channel',
      );

      player.dispose();
    });

    test(
        'throws ConfigurationException and never calls native for an '
        'invalid URL', () async {
      final calls = _installCapture();
      final player = MediaPlayer(playerId: 'bulk-cast-bad-url');
      await player.initialize();
      calls.clear();

      const item = MediaItem(
        id: 'cast-bad-url-item',
        title: 'Bad URL',
        url: 'not-a-url',
      );

      await expectLater(
        () => player.loadMediaOnCastDevice(item),
        throwsA(isA<ConfigurationException>()),
      );

      expect(
        calls.where((c) => c.method == 'loadMediaOnCastDevice'),
        isEmpty,
      );

      player.dispose();
    });

    test('sends loadMediaOnCastDevice for a valid, non-DRM item', () async {
      final calls = _installCapture();
      final player = MediaPlayer(playerId: 'bulk-cast-valid');
      await player.initialize();
      calls.clear();

      const item = MediaItem(
        id: 'cast-valid-item',
        title: 'Valid',
        url: 'https://cdn.example.com/valid.mp4',
      );

      await player.loadMediaOnCastDevice(item);

      expect(
        calls.where((c) => c.method == 'loadMediaOnCastDevice'),
        isNotEmpty,
      );

      player.dispose();
    });
  });
}
