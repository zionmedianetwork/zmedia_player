// Regression tests for issue #88 ("No live-edge signal: with DVR enabled, a
// healthy live edge is indistinguishable from a frozen playhead").
//
// These exercise the DATA CONTRACT of the `onPositionChanged` event, which is
// where the fix lives: native now attaches `positionBasis` (String) and, for
// live items, `liveEdgeOffset` (int milliseconds) to the same 500ms event that
// already carried `position`. Per CLAUDE.md, a channel payload key is exactly
// the class of change that `flutter analyze` cannot see, so it is pinned here.
//
// The three cases the issue turns on are covered end to end:
//   - VOD                 -> basis absolute, offset null, isAtLiveEdge false
//   - live WITHOUT DVR    -> offset still reported (a non-DVR live stream is
//                            just as prone to the frozen-playhead ambiguity)
//   - live WITH DVR       -> the reported production case: position stays
//                            constant while the offset is what actually moves
//
// Harness matches media_player_routing_test.dart: events are injected through
// TestDefaultBinaryMessenger.handlePlatformMessage, simulating native firing.

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zmedia_player/zmedia_player.dart';

const _channel = MethodChannel('zmedia_player');

Future<void> _injectPlatformCall(
  String method,
  Map<String, dynamic> arguments,
) async {
  const codec = StandardMethodCodec();
  final data = codec.encodeMethodCall(MethodCall(method, arguments));
  await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .handlePlatformMessage(_channel.name, data, (ByteData? reply) {});
  // Let the async handler settle.
  await Future<void>.delayed(Duration.zero);
}

const _vodItem = MediaItem(
  id: 'vod',
  title: 'VOD',
  url: 'https://cdn.example.com/movie.mp4',
);

const _liveItem = MediaItem(
  id: 'live',
  title: 'Live',
  url: 'https://cdn.example.com/live.m3u8',
  isLive: true,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (MethodCall call) async => null);
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null);
  });

  group('VOD (basis absolute, no live edge)', () {
    test('a VOD position event yields absolute basis and a null offset',
        () async {
      final player = MediaPlayer(playerId: 'le_vod');
      await player.initialize();
      await player.load(_vodItem);

      await _injectPlatformCall('onPositionChanged', {
        'playerId': 'le_vod',
        'position': 12000,
        'positionBasis': 'absolute',
      });

      expect(player.currentState.position, const Duration(seconds: 12));
      expect(player.positionBasis, PositionBasis.absolute);
      expect(player.liveEdgeOffset, isNull);
      expect(player.isAtLiveEdge, isFalse);

      player.dispose();
    });

    test('defaults before any position event are absolute / null', () async {
      final player = MediaPlayer(playerId: 'le_vod_default');
      await player.initialize();
      await player.load(_vodItem);

      expect(player.positionBasis, PositionBasis.absolute);
      expect(player.liveEdgeOffset, isNull);
      expect(player.isAtLiveEdge, isFalse);

      player.dispose();
    });
  });

  group('Live WITHOUT DVR', () {
    test('offset is still reported and drives isAtLiveEdge', () async {
      final player = MediaPlayer(playerId: 'le_live_nodvr');
      await player.initialize();
      // No hlsConfig => enableDvr false => not seekable.
      await player.load(_liveItem);

      expect(player.isLive, isTrue);
      expect(player.dvrEnabled, isFalse);

      await _injectPlatformCall('onPositionChanged', {
        'playerId': 'le_live_nodvr',
        'position': 45000,
        // iOS reports "absolute" for live-without-DVR (position is the
        // AVPlayerItem's own timeline there); the offset is reported either
        // way, which is the point — a non-DVR live stream is not exempt.
        'positionBasis': 'absolute',
        'liveEdgeOffset': 8000,
      });

      expect(player.liveEdgeOffset, const Duration(seconds: 8));
      expect(player.isAtLiveEdge, isTrue);
      expect(player.positionBasis, PositionBasis.absolute);

      player.dispose();
    });

    test('Android reports liveWindow basis for live-without-DVR', () async {
      final player = MediaPlayer(playerId: 'le_live_nodvr_android');
      await player.initialize();
      await player.load(_liveItem);

      // ExoPlayer's getCurrentPosition() is window-relative for ANY live
      // item, DVR enabled or not — so Android's basis differs from iOS's for
      // this same case. Reporting each platform's real basis is exactly what
      // the flag exists for.
      await _injectPlatformCall('onPositionChanged', {
        'playerId': 'le_live_nodvr_android',
        'position': 3000,
        'positionBasis': 'liveWindow',
        'liveEdgeOffset': 4000,
      });

      expect(player.positionBasis, PositionBasis.liveWindow);
      expect(player.currentState.isPositionWindowRelative, isTrue);

      player.dispose();
    });
  });

  group('Live WITH DVR (the reported production case)', () {
    const dvrConfig = MediaConfig(
      hlsConfig: HlsConfig(enableDvr: true),
    );

    test('a constant position with a bounded offset reads as a healthy edge',
        () async {
      final player = MediaPlayer(playerId: 'le_dvr_healthy', config: dvrConfig);
      await player.initialize();
      await player.load(_liveItem);

      expect(player.dvrEnabled, isTrue);
      expect(player.isSeekable, isTrue);

      // Three consecutive ticks with an IDENTICAL window-relative position —
      // exactly what a healthy live edge in a sliding window looks like, and
      // exactly what made the reporter's watchdog escalate forever.
      for (final offsetMs in <int>[6000, 6200, 5900]) {
        await _injectPlatformCall('onPositionChanged', {
          'playerId': 'le_dvr_healthy',
          'position': 120000,
          'positionBasis': 'liveWindow',
          'liveEdgeOffset': offsetMs,
        });
      }

      expect(player.currentState.position, const Duration(seconds: 120),
          reason: 'position must NOT change meaning — DVR scrubbers depend '
              'on it staying window-relative');
      expect(player.positionBasis, PositionBasis.liveWindow);
      expect(player.liveEdgeOffset, const Duration(milliseconds: 5900));
      expect(player.isAtLiveEdge, isTrue,
          reason: 'the whole point: a constant position at a bounded offset '
              'is healthy, not stalled');

      player.dispose();
    });

    test('a frozen playhead shows a growing offset and leaves the live edge',
        () async {
      final player = MediaPlayer(playerId: 'le_dvr_frozen', config: dvrConfig);
      await player.initialize();
      await player.load(_liveItem);

      final observed = <Duration>[];
      // Same constant position as the healthy case above; only the offset
      // distinguishes them.
      for (final offsetMs in <int>[6000, 12000, 20000, 40000]) {
        await _injectPlatformCall('onPositionChanged', {
          'playerId': 'le_dvr_frozen',
          'position': 120000,
          'positionBasis': 'liveWindow',
          'liveEdgeOffset': offsetMs,
        });
        observed.add(player.liveEdgeOffset!);
      }

      expect(observed, [
        const Duration(seconds: 6),
        const Duration(seconds: 12),
        const Duration(seconds: 20),
        const Duration(seconds: 40),
      ]);
      expect(player.isAtLiveEdge, isFalse,
          reason: 'past the 15s tolerance the playhead has demonstrably '
              'fallen behind a sliding window');

      player.dispose();
    });
  });

  group('Payload tolerance and state propagation', () {
    test('a missing positionBasis key falls back to absolute', () async {
      final player = MediaPlayer(playerId: 'le_legacy_basis');
      await player.initialize();
      await player.load(_vodItem);

      // An older cached native build that predates this field.
      await _injectPlatformCall('onPositionChanged', {
        'playerId': 'le_legacy_basis',
        'position': 5000,
      });

      expect(player.positionBasis, PositionBasis.absolute);
      expect(player.liveEdgeOffset, isNull);
      expect(player.currentState.position, const Duration(seconds: 5));

      player.dispose();
    });

    test('an unrecognised positionBasis value falls back to absolute',
        () async {
      final player = MediaPlayer(playerId: 'le_unknown_basis');
      await player.initialize();
      await player.load(_vodItem);

      await _injectPlatformCall('onPositionChanged', {
        'playerId': 'le_unknown_basis',
        'position': 5000,
        'positionBasis': 'someFutureBasis',
      });

      expect(player.positionBasis, PositionBasis.absolute,
          reason: 'a newer native build than this Dart layer must not crash '
              'or invent a basis');

      player.dispose();
    });

    test('an event omitting liveEdgeOffset clears a previously known offset',
        () async {
      final player = MediaPlayer(playerId: 'le_clear');
      await player.initialize();
      await player.load(_liveItem);

      await _injectPlatformCall('onPositionChanged', {
        'playerId': 'le_clear',
        'position': 1000,
        'positionBasis': 'liveWindow',
        'liveEdgeOffset': 4000,
      });
      expect(player.liveEdgeOffset, const Duration(seconds: 4));

      // Native lost the ability to answer (e.g. timeline went empty).
      await _injectPlatformCall('onPositionChanged', {
        'playerId': 'le_clear',
        'position': 1500,
        'positionBasis': 'liveWindow',
      });

      expect(player.liveEdgeOffset, isNull,
          reason: 'a stale offset is worse than no offset — it would report '
              '"at the live edge" for a player that no longer is');
      expect(player.isAtLiveEdge, isFalse);

      player.dispose();
    });

    test('loading a new item drops the previous item live-edge signal',
        () async {
      final player = MediaPlayer(playerId: 'le_reload');
      await player.initialize();
      await player.load(_liveItem);

      await _injectPlatformCall('onPositionChanged', {
        'playerId': 'le_reload',
        'position': 1000,
        'positionBasis': 'liveWindow',
        'liveEdgeOffset': 3000,
      });
      expect(player.isAtLiveEdge, isTrue);

      await player.load(_vodItem);

      expect(player.liveEdgeOffset, isNull,
          reason: 'a stale live offset must not make a freshly-loaded VOD '
              'item read as "at the live edge"');
      expect(player.positionBasis, PositionBasis.absolute);
      expect(player.isAtLiveEdge, isFalse);

      player.dispose();
    });

    test('both fields reach the broadcast state stream', () async {
      final player = MediaPlayer(playerId: 'le_stream');
      await player.initialize();
      await player.load(_liveItem);

      final seen = <PlaybackState>[];
      final sub = player.stateStream.listen(seen.add);

      await _injectPlatformCall('onPositionChanged', {
        'playerId': 'le_stream',
        'position': 7000,
        'positionBasis': 'liveWindow',
        'liveEdgeOffset': 2500,
      });

      expect(seen, isNotEmpty);
      expect(seen.last.liveEdgeOffset, const Duration(milliseconds: 2500));
      expect(seen.last.positionBasis, PositionBasis.liveWindow);
      expect(seen.last.isAtLiveEdge, isTrue);

      await sub.cancel();
      player.dispose();
    });

    test('MediaController surfaces both fields from the same event', () async {
      // The facade is what UI code (a LIVE badge, a "jump to live" button)
      // and most host watchdogs actually hold.
      final controller = MediaController.create(playerId: 'le_controller');
      await controller.initialize();
      await controller.load(_liveItem);

      expect(controller.positionBasis, PositionBasis.absolute);
      expect(controller.liveEdgeOffset, isNull);
      expect(controller.isAtLiveEdge, isFalse);

      await _injectPlatformCall('onPositionChanged', {
        'playerId': 'le_controller',
        'position': 60000,
        'positionBasis': 'liveWindow',
        'liveEdgeOffset': 5000,
      });

      expect(controller.positionBasis, PositionBasis.liveWindow);
      expect(controller.liveEdgeOffset, const Duration(seconds: 5));
      expect(controller.isAtLiveEdge, isTrue);

      await _injectPlatformCall('onPositionChanged', {
        'playerId': 'le_controller',
        // Identical position — a frozen playhead, not a healthy edge, and
        // only the growing offset says so.
        'position': 60000,
        'positionBasis': 'liveWindow',
        'liveEdgeOffset': 65000,
      });

      expect(controller.isAtLiveEdge, isFalse);
      expect(controller.liveEdgeOffset, const Duration(seconds: 65));

      controller.dispose();
    });

    test(
        'an out-of-window liveEdgeOffset is still surfaced faithfully — '
        'issue #109 (validation lives entirely in native)', () async {
      // Issue #109: Android's currentLiveEdgeOffsetMs() now sanity-checks
      // Player.getCurrentLiveOffset() against the live window's own
      // duration before trusting it, rejecting (and falling back for) a
      // reported offset larger than the window itself. That validation is
      // native-only and MUST NOT be duplicated here: MediaPlayer is a pure
      // pass-through for this event (see the class doc), so an event that
      // still carries an out-of-window offset — e.g. from an older/
      // unpatched native build, or any other future case a host needs to
      // detect and handle itself — must reach the Dart layer unmodified
      // rather than being silently clamped or dropped. This is the pinned
      // contract: fix the value in native, don't paper over a bad one in
      // Dart.
      final player = MediaPlayer(playerId: 'le_out_of_window');
      await player.initialize();
      await player.load(_liveItem);

      await _injectPlatformCall('onPositionChanged', {
        'playerId': 'le_out_of_window',
        'position': 57732,
        'positionBasis': 'liveWindow',
        // The exact numbers from issue #109's report: a 61466ms DVR window
        // with a reported offset of ~33 minutes.
        'liveEdgeOffset': 1973165,
      });
      await _injectPlatformCall('onDurationChanged', {
        'playerId': 'le_out_of_window',
        'duration': 61466,
        'isLive': true,
      });

      expect(player.liveEdgeOffset, const Duration(milliseconds: 1973165),
          reason: 'Dart neither validates nor clamps liveEdgeOffset against '
              'duration — that correction is native-only (issue #109)');
      expect(player.currentState.duration, const Duration(milliseconds: 61466));
      expect(player.isAtLiveEdge, isFalse,
          reason: 'an offset this large is correctly read as far from the '
              'edge, whatever produced it');

      player.dispose();
    });

    test('a liveEdgeOffset sent as a double is accepted', () async {
      // StandardMessageCodec preserves int/double distinctly; be lenient.
      final player = MediaPlayer(playerId: 'le_double');
      await player.initialize();
      await player.load(_liveItem);

      await _injectPlatformCall('onPositionChanged', {
        'playerId': 'le_double',
        'position': 1000,
        'positionBasis': 'liveWindow',
        'liveEdgeOffset': 2500.0,
      });

      expect(player.liveEdgeOffset, const Duration(milliseconds: 2500));

      player.dispose();
    });
  });
}
