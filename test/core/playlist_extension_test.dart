// Regression tests for issue #79 — "setPlaylist unconditionally reloads
// items[startIndex], so a playlist cannot be extended without restarting the
// current item".
//
// Native (MediaPlayerManager.kt / MediaPlayerManager.swift) now skips its
// loadMediaItem() call when the item at startIndex is, key for key, the item
// already loaded AND that item is still in progress. That native guard has no
// automated coverage in this repo (a documented gap — there are no Kotlin/Swift
// tests), so what is asserted here is everything the fix makes observable from
// Dart:
//
//  1. setPlaylist still sends the SAME MethodChannel payload in both cases —
//     the playlist contents and startIndex must always reach native, only the
//     *load* is conditional.
//  2. Playlist/index/currentItem state updates correctly when a playlist is
//     extended in place (the sliding-window use case from the issue).
//  3. MediaPlayer mirrors the native guard (MediaPlayer._isPlaylistReloadSkipped)
//     and therefore does NOT perform its own "a load is coming" reset — it keeps
//     the cached quality/audio/subtitle track lists, does not force
//     PlayerState.buffering, and does not send a speed reset.
//  4. The guard still lets a GENUINE reload through: same id but a changed url,
//     changed httpHeaders, or a changed drmConfig (including a rotated
//     drmConfig.headers value, which DrmConfig's own `==` does not compare) all
//     reload, as does a different id, and so does any non-in-progress state
//     (idle / completed / error).
//
// Harness: same pattern as playback_completion_test.dart and
// media_player_channel_test.dart.

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

Future<void> _injectEvent(String method, Map<String, dynamic> arguments) async {
  const codec = StandardMethodCodec();
  final data = codec.encodeMethodCall(MethodCall(method, arguments));
  await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .handlePlatformMessage('zmedia_player', data, (_) {});
}

Future<void> _injectState(String playerId, String state) => _injectEvent(
      'onStateChanged',
      {
        'playerId': playerId,
        'state': state,
        'isBuffering': state == 'buffering',
        'bufferPercentage': 0.0,
      },
    );

Future<void> _injectQualityTracks(String playerId) => _injectEvent(
      'onQualityTracksChanged',
      {
        'playerId': playerId,
        'tracks': <Map<String, dynamic>>[
          {
            'id': 'q-720',
            'name': '720p',
            'bitrate': 2500000,
            'width': 1280,
            'height': 720,
          },
        ],
      },
    );

Future<void> _injectSubtitleTracks(String playerId) => _injectEvent(
      'onSubtitleTracksChanged',
      {
        'playerId': playerId,
        'tracks': <Map<String, dynamic>>[
          {'id': 'sub-en', 'title': 'English', 'language': 'en'},
        ],
      },
    );

const _episode0 = MediaItem(
  id: 'ep-0',
  title: 'Episode 0',
  url: 'https://example.com/ep0.m3u8',
);

const _episode1 = MediaItem(
  id: 'ep-1',
  title: 'Episode 1',
  url: 'https://example.com/ep1.m3u8',
);

const _episode2 = MediaItem(
  id: 'ep-2',
  title: 'Episode 2',
  url: 'https://example.com/ep2.m3u8',
);

Playlist _window(List<MediaItem> items,
        {int currentIndex = 0,
        MediaRepeatMode repeatMode = MediaRepeatMode.none,
        PlaybackMode mode = PlaybackMode.sequential}) =>
    Playlist(
      id: 'pl-window',
      title: 'Sliding window',
      items: items,
      currentIndex: currentIndex,
      mode: mode,
      repeatMode: repeatMode,
    );

/// Brings [player] to the state the issue describes: a playlist is loaded,
/// item 0 is playing, and native has reported track lists for it.
Future<MediaPlayer> _playingFirstItem(String playerId,
    {List<MediaItem> items = const [_episode0, _episode1]}) async {
  final player = MediaPlayer(playerId: playerId);
  await player.initialize();
  await player.setPlaylist(_window(items));
  await _injectState(playerId, 'playing');
  await _injectQualityTracks(playerId);
  await _injectSubtitleTracks(playerId);
  return player;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(_resetHandler);

  // =========================================================================
  group('issue #79 — extending a playlist in place', () {
    test(
        'sends the full setPlaylist payload even when the start item is already playing',
        () async {
      final calls = _installCapture();
      final player = await _playingFirstItem('i79-payload');
      calls.clear();

      // Extend the window: same current item, one more item appended.
      await player.setPlaylist(
        _window(const [_episode0, _episode1, _episode2]),
      );

      final setCalls = calls.where((c) => c.method == 'setPlaylist').toList();
      expect(setCalls, hasLength(1),
          reason: 'the playlist must always reach native, even when the '
              'current item will not be reloaded');

      final args = setCalls.single.arguments as Map<Object?, Object?>;
      expect(args['playerId'], 'i79-payload');
      expect(args['startIndex'], 0);

      final playlistMap = args['playlist'] as Map<Object?, Object?>;
      final itemMaps = playlistMap['items'] as List<Object?>;
      expect(itemMaps, hasLength(3),
          reason: 'the extended playlist contents must be sent in full');
      expect(
        itemMaps
            .map((m) => (m! as Map<Object?, Object?>)['id'] as String)
            .toList(),
        ['ep-0', 'ep-1', 'ep-2'],
      );
      expect(playlistMap['currentIndex'], 0);

      await player.dispose();
    });

    test('keeps currentIndex and currentItem when the window is extended',
        () async {
      _installCapture();
      final player = await _playingFirstItem(
        'i79-index',
        items: const [_episode0, _episode1],
      );

      await player.setPlaylist(
        _window(const [_episode0, _episode1, _episode2]),
      );

      expect(player.currentItem?.id, 'ep-0');
      expect(player.currentPlaylist?.currentIndex, 0);
      expect(player.currentPlaylist?.items, hasLength(3));
      expect(player.currentPlaylist?.items.last.id, 'ep-2');

      await player.dispose();
    });

    test(
        'does not clear the cached track lists or force buffering when the '
        'current item is unchanged', () async {
      _installCapture();
      final player = await _playingFirstItem('i79-tracks');

      expect(player.qualityTracks, hasLength(1));
      expect(player.subtitleTracks, hasLength(1));
      expect(player.currentState.state, PlayerState.playing);

      await player.setPlaylist(
        _window(const [_episode0, _episode1, _episode2]),
      );

      expect(player.qualityTracks, hasLength(1),
          reason: 'no reload happens natively, so native will not re-send '
              'quality tracks — clearing them here would empty the settings '
              'menu for the item still playing');
      expect(player.subtitleTracks, hasLength(1));
      expect(player.currentState.state, PlayerState.playing,
          reason: 'playback is uninterrupted; reporting buffering would be a '
              'lie the native side never corrects');

      await player.dispose();
    });

    test('does not emit an empty track list on the track streams', () async {
      _installCapture();
      final player = await _playingFirstItem('i79-streams');

      final emitted = <List<QualityTrack>>[];
      final sub = player.qualityTracksStream.listen(emitted.add);

      await player.setPlaylist(
        _window(const [_episode0, _episode1, _episode2]),
      );
      await Future<void>.delayed(Duration.zero);

      expect(emitted, isEmpty,
          reason: 'the "clear stale UI" reset must be skipped entirely when '
              'the current item is not being reloaded');

      await sub.cancel();
      await player.dispose();
    });

    test('does not send a speed reset when the current item is unchanged',
        () async {
      final calls = _installCapture();
      final player = await _playingFirstItem('i79-speed');
      await player.setSpeed(1.5);
      calls.clear();

      await player.setPlaylist(
        _window(const [_episode0, _episode1, _episode2]),
      );

      expect(calls.where((c) => c.method == 'setSpeed'), isEmpty,
          reason: 'resetting speed to 1.0x would visibly change the playback '
              'of the item the guard is protecting');
      expect(player.currentState.speed, 1.5);

      await player.dispose();
    });

    test('a repeatMode/mode change alone does not restart the current item',
        () async {
      _installCapture();
      final player = await _playingFirstItem('i79-mode');

      await player.setPlaylist(
        _window(
          const [_episode0, _episode1],
          repeatMode: MediaRepeatMode.all,
          mode: PlaybackMode.shuffle,
        ),
      );

      expect(player.currentState.state, PlayerState.playing);
      expect(player.currentPlaylist?.repeatMode, MediaRepeatMode.all);
      expect(player.currentPlaylist?.mode, PlaybackMode.shuffle);

      await player.dispose();
    });
  });

  // =========================================================================
  group('issue #79 — genuine reloads are preserved', () {
    test('the very first setPlaylist always resets and reports buffering',
        () async {
      _installCapture();
      final player = MediaPlayer(playerId: 'i79-first');
      await player.initialize();

      await player.setPlaylist(_window(const [_episode0, _episode1]));

      expect(player.currentState.state, PlayerState.buffering);

      await player.dispose();
    });

    test('a different item at startIndex resets and reports buffering',
        () async {
      _installCapture();
      final player = await _playingFirstItem('i79-different');

      await player.setPlaylist(
        _window(const [_episode1, _episode2]),
      );

      expect(player.currentState.state, PlayerState.buffering);
      expect(player.qualityTracks, isEmpty);
      expect(player.currentItem?.id, 'ep-1');

      await player.dispose();
    });

    test('same id but a re-signed url is a genuine reload', () async {
      _installCapture();
      final player = await _playingFirstItem('i79-resigned-url');

      await player.setPlaylist(
        _window(const [
          MediaItem(
            id: 'ep-0',
            title: 'Episode 0',
            url: 'https://example.com/ep0.m3u8?sig=refreshed',
          ),
          _episode1,
        ]),
      );

      expect(player.currentState.state, PlayerState.buffering,
          reason: 'the URL actually fetched changed — this must reload');
      expect(player.qualityTracks, isEmpty);

      await player.dispose();
    });

    test('same id and url but refreshed httpHeaders is a genuine reload',
        () async {
      _installCapture();
      final player = await _playingFirstItem(
        'i79-refreshed-headers',
        items: const [
          MediaItem(
            id: 'ep-0',
            title: 'Episode 0',
            url: 'https://example.com/ep0.m3u8',
            httpHeaders: {'Cookie': 'CloudFront-Signature=old'},
          ),
          _episode1,
        ],
      );

      await player.setPlaylist(
        _window(const [
          MediaItem(
            id: 'ep-0',
            title: 'Episode 0',
            url: 'https://example.com/ep0.m3u8',
            httpHeaders: {'Cookie': 'CloudFront-Signature=new'},
          ),
          _episode1,
        ]),
      );

      expect(player.currentState.state, PlayerState.buffering,
          reason: 'refreshed signed-cookie credentials must reach the media '
              'stack, which only happens on a reload');

      await player.dispose();
    });

    test('same id and url but a rotated drmConfig token is a genuine reload',
        () async {
      _installCapture();
      final player = await _playingFirstItem(
        'i79-rotated-drm-token',
        items: const [
          MediaItem(
            id: 'ep-0',
            title: 'Episode 0',
            url: 'https://example.com/ep0.m3u8',
            drmConfig: DrmConfig(
              scheme: DrmScheme.widevine,
              licenseUrl: 'https://drm.example.com/license',
              token: 'token-old-000000',
            ),
          ),
          _episode1,
        ],
      );

      await player.setPlaylist(
        _window(const [
          MediaItem(
            id: 'ep-0',
            title: 'Episode 0',
            url: 'https://example.com/ep0.m3u8',
            drmConfig: DrmConfig(
              scheme: DrmScheme.widevine,
              licenseUrl: 'https://drm.example.com/license',
              token: 'token-new-000000',
            ),
          ),
          _episode1,
        ]),
      );

      expect(player.currentState.state, PlayerState.buffering);

      await player.dispose();
    });

    test(
        'same id and url but rotated drmConfig.headers is a genuine reload '
        '(DrmConfig == does not compare headers)', () async {
      _installCapture();

      const oldConfig = DrmConfig(
        scheme: DrmScheme.widevine,
        licenseUrl: 'https://drm.example.com/license',
        headers: {'Authorization': 'Bearer old'},
      );
      const newConfig = DrmConfig(
        scheme: DrmScheme.widevine,
        licenseUrl: 'https://drm.example.com/license',
        headers: {'Authorization': 'Bearer new'},
      );

      // Guard the premise: the model's own equality cannot see this change,
      // which is exactly why the guard compares the serialized maps.
      expect(oldConfig, equals(newConfig));

      final player = await _playingFirstItem(
        'i79-rotated-drm-headers',
        items: const [
          MediaItem(
            id: 'ep-0',
            title: 'Episode 0',
            url: 'https://example.com/ep0.m3u8',
            drmConfig: oldConfig,
          ),
          _episode1,
        ],
      );

      await player.setPlaylist(
        _window(const [
          MediaItem(
            id: 'ep-0',
            title: 'Episode 0',
            url: 'https://example.com/ep0.m3u8',
            drmConfig: newConfig,
          ),
          _episode1,
        ]),
      );

      expect(player.currentState.state, PlayerState.buffering,
          reason: 'a rotated DRM license header must reach the license '
              'request, which only happens on a reload');

      await player.dispose();
    });

    test('re-issuing the playlist after completion still reloads', () async {
      _installCapture();
      final player = await _playingFirstItem('i79-completed');
      await _injectState('i79-completed', 'completed');
      // Auto-advance runs on completion; let it settle before re-issuing.
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      await player.setPlaylist(_window(const [_episode0, _episode1]));

      expect(player.currentState.state, PlayerState.buffering,
          reason: 'a finished item is not in progress — native reloads it, so '
              'Dart must reset too');

      await player.dispose();
    });

    test('re-issuing the playlist from idle still reloads', () async {
      _installCapture();
      final player = await _playingFirstItem('i79-idle');
      await _injectState('i79-idle', 'idle');

      await player.setPlaylist(_window(const [_episode0, _episode1]));

      expect(player.currentState.state, PlayerState.buffering,
          reason: 'stop() leaves Android in STATE_IDLE with no media items, '
              'so native reloads');

      await player.dispose();
    });
  });

  // =========================================================================
  group('issue #79 — skipToIndex keeps its restart semantics', () {
    test('skipToIndex to the current index still calls native skipToIndex',
        () async {
      final calls = _installCapture();
      final player = await _playingFirstItem('i79-skip-same');
      calls.clear();

      await player.skipToIndex(0);

      expect(
        calls.where((c) => c.method == 'skipToIndex'),
        hasLength(1),
        reason: 'skipToIndex means "(re)start the item at this index"; '
            'MediaRepeatMode.single implements repeat-one through exactly '
            'this call, so it must never be suppressed',
      );

      await player.dispose();
    });
  });
}
