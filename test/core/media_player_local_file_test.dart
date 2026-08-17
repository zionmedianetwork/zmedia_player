import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zmedia_player/zmedia_player.dart';

/// C-02 Stage 1 — local file playback.
///
/// `MediaPlayer.load()`/`setPlaylist()` must forward a `file://` media item
/// to native exactly like any other item (native's `DefaultDataSource`
/// (Android) / `AVURLAsset` (iOS) already understand `file://` — see
/// android/.../MediaPlayerManager.kt and ios/.../MediaPlayerManager.swift).
/// `loadMediaOnCastDevice`/`CastService.loadMedia`, on the other hand, must
/// explicitly refuse a `file://` item: a cast receiver is a different device
/// with no access to this device's filesystem.
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(_resetHandler);

  group('MediaPlayer.load — local file media item', () {
    test('forwards a file:// media item to native unmodified', () async {
      final calls = _installCapture();
      final player = MediaPlayer(playerId: 'local-file-load');
      await player.initialize();
      calls.clear();

      final item = MediaItem(
        id: 'local-clip',
        title: 'Local clip',
        url: LocalMediaUtils.fileUri('/data/user/0/app/files/clip.mp4'),
      );

      await player.load(item);

      final loadCall = calls.firstWhere((c) => c.method == 'load');
      final mediaItem = loadCall.arguments['mediaItem'] as Map;
      expect(mediaItem['url'], item.url);
      expect(item.url, startsWith('file:///'));

      player.dispose();
    });

    test('setPlaylist accepts a playlist containing a file:// item', () async {
      final calls = _installCapture();
      final player = MediaPlayer(playerId: 'local-file-playlist');
      await player.initialize();
      calls.clear();

      final playlist = Playlist(
        id: 'pl-local',
        title: 'Mixed playlist',
        items: [
          const MediaItem(
            id: 'remote-item',
            title: 'Remote',
            url: 'https://cdn.example.com/remote.mp4',
          ),
          MediaItem(
            id: 'local-item',
            title: 'Local',
            url: LocalMediaUtils.fileUri('/data/user/0/app/files/clip.mp4'),
          ),
        ],
      );

      await player.setPlaylist(playlist);

      expect(calls.where((c) => c.method == 'setPlaylist'), isNotEmpty);

      player.dispose();
    });
  });

  group('MediaPlayer.loadMediaOnCastDevice — local file must be refused', () {
    test(
        'throws ConfigurationException and never reaches native for a '
        'file:// item', () async {
      final calls = _installCapture();
      final player = MediaPlayer(playerId: 'cast-local-file');
      await player.initialize();
      calls.clear();

      final item = MediaItem(
        id: 'cast-local-item',
        title: 'Local',
        url: LocalMediaUtils.fileUri('/data/user/0/app/files/clip.mp4'),
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
  });
}
