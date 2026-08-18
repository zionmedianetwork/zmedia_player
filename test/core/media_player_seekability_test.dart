// Regression tests for live-stream seek gating (Wave A: "notification/lock
// screen exposes seeking on LIVE streams unconditionally"; Wave D: wired
// HlsConfig.enableDvr/DashConfig.enableDvr into MediaPlayer.load()).
//
// MediaPlayer.isSeekable is false only when the current media is live AND
// DVR is not enabled (MediaPlayer.dvrEnabled). dvrEnabled is derived on every
// load() from whichever streaming config applies to the loaded item's URL
// (HlsConfig.enableDvr for a `.m3u8` URL via MediaConfig.hlsConfig,
// DashConfig.enableDvr for a `.mpd` URL via MediaConfig.dashConfig, `false`
// when neither applies) — see MediaPlayer._applyStreamingConfigForLoad.
// MediaPlayer.seekTo must throw InvalidStateException instead of forwarding
// a "seekTo" channel call when not seekable — this is the single choke point
// every seek path (including a host app forwarding a lock-screen/
// notification "seekTo" action) funnels through.
//
// Harness: same pattern as media_player_channel_test.dart —
// TestWidgetsFlutterBinding + TestDefaultBinaryMessengerBinding
// .setMockMethodCallHandler to capture outgoing calls.

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

const _liveItem = MediaItem(
  id: 'live-item',
  title: 'Live Stream',
  url: 'https://cdn.example.com/live.m3u8',
  isLive: true,
);

const _liveDashItem = MediaItem(
  id: 'live-dash-item',
  title: 'Live Dash Stream',
  url: 'https://cdn.example.com/live.mpd',
  isLive: true,
);

const _vodItem = MediaItem(
  id: 'vod-item',
  title: 'VOD Video',
  url: 'https://cdn.example.com/video.mp4',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(_resetHandler);

  group('MediaPlayer.isSeekable / seekTo — live-stream gating', () {
    test('VOD media is always seekable and seekTo reaches the channel',
        () async {
      final calls = _installCapture();
      final player = MediaPlayer(playerId: 'seek-vod');
      await player.initialize();
      await player.load(_vodItem);
      calls.clear();

      expect(player.isLive, isFalse);
      expect(player.isSeekable, isTrue);

      await player.seekTo(const Duration(seconds: 5));

      final seekCalls = calls.where((c) => c.method == 'seekTo').toList();
      expect(seekCalls, hasLength(1),
          reason: 'VOD seekTo must reach the native channel');
      expect(seekCalls.single.arguments['position'], 5000);

      player.dispose();
    });

    test(
        'live stream without DVR is not seekable: seekTo throws '
        'InvalidStateException and never reaches the channel', () async {
      final calls = _installCapture();
      final player = MediaPlayer(playerId: 'seek-live-no-dvr');
      await player.initialize();
      await player.load(_liveItem);
      calls.clear();

      expect(player.isLive, isTrue);
      expect(player.dvrEnabled, isFalse,
          reason: 'DVR defaults to disabled when no HlsConfig/DashConfig is '
              'configured');
      expect(player.isSeekable, isFalse);

      await expectLater(
        player.seekTo(const Duration(seconds: 5)),
        throwsA(isA<InvalidStateException>()),
        reason: 'seekTo on a live stream without DVR must be rejected rather '
            'than silently forwarded to native',
      );

      expect(
        calls.where((c) => c.method == 'seekTo'),
        isEmpty,
        reason: 'A rejected seek must never reach the platform channel — '
            'this is also the path a host app forwarding a lock-screen/'
            'notification "seekTo" action funnels through',
      );

      player.dispose();
    });

    test(
        'live stream with HlsConfig.enableDvr true is seekable and seekTo '
        'reaches the channel', () async {
      final calls = _installCapture();
      final player = MediaPlayer(
        playerId: 'seek-live-dvr',
        config: const MediaConfig(hlsConfig: HlsConfig(enableDvr: true)),
      );
      await player.initialize();
      await player.load(_liveItem);
      calls.clear();

      expect(player.isLive, isTrue);
      expect(player.dvrEnabled, isTrue);
      expect(player.isSeekable, isTrue);

      await player.seekTo(const Duration(seconds: 5));

      final seekCalls = calls.where((c) => c.method == 'seekTo').toList();
      expect(seekCalls, hasLength(1),
          reason: 'A live stream with DVR enabled must allow seeking');

      player.dispose();
    });

    test(
        'live DASH stream with DashConfig.enableDvr true is seekable — the '
        'HLS (.m3u8) config is not consulted for a .mpd URL', () async {
      final calls = _installCapture();
      final player = MediaPlayer(
        playerId: 'seek-live-dash-dvr',
        config: const MediaConfig(
          // Deliberately also set an HLS config with DVR *disabled*, to
          // prove the .mpd URL selects dashConfig, not hlsConfig.
          hlsConfig: HlsConfig(enableDvr: false),
          dashConfig: DashConfig(enableDvr: true),
        ),
      );
      await player.initialize();
      await player.load(_liveDashItem);
      calls.clear();

      expect(player.dvrEnabled, isTrue);
      expect(player.isSeekable, isTrue);

      await player.seekTo(const Duration(seconds: 5));
      expect(calls.where((c) => c.method == 'seekTo'), hasLength(1));

      player.dispose();
    });

    test(
        'dvrEnabled (and therefore isSeekable) is recomputed from the active '
        'config on every load(), not just reset to false', () async {
      _installCapture();
      final player = MediaPlayer(playerId: 'seek-recompute-on-load');
      await player.initialize();

      // No hlsConfig configured yet: DVR defaults to disabled.
      await player.load(_liveItem);
      expect(player.dvrEnabled, isFalse);
      expect(player.isSeekable, isFalse);

      // updateConfig + reload with DVR enabled: recomputed to true.
      await player.updateConfig(
        const MediaConfig(hlsConfig: HlsConfig(enableDvr: true)),
      );
      await player.load(_liveItem);
      expect(player.dvrEnabled, isTrue);
      expect(player.isSeekable, isTrue);

      // updateConfig back to no streaming config + reload: recomputed to
      // false again — not "sticky" from the previous load.
      await player.updateConfig(const MediaConfig());
      await player.load(_liveItem);
      expect(player.dvrEnabled, isFalse);
      expect(player.isSeekable, isFalse);

      player.dispose();
    });

    test('negative seek position is rejected before the live-stream check',
        () async {
      final calls = _installCapture();
      final player = MediaPlayer(playerId: 'seek-negative-live');
      await player.initialize();
      await player.load(_liveItem);
      calls.clear();

      await expectLater(
        player.seekTo(const Duration(seconds: -1)),
        throwsA(isA<ConfigurationException>()),
        reason: 'Negative positions must still throw ConfigurationException, '
            'not InvalidStateException, regardless of seekability',
      );

      expect(calls.where((c) => c.method == 'seekTo'), isEmpty);

      player.dispose();
    });
  });
}
