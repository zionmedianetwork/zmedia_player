// Stage 7d (Phase 7) regression tests for [MediaFeed] — F-06: network-aware
// autoplay. [MediaFeedConfig.autoPlayPolicy] lets a host refuse autoplay
// given the device's current [NetworkStatus]; it defaults to `null`
// ("autoplay regardless of network"), preserving every release before
// Stage 7d exactly, since changing that default silently would be a
// behavioural regression for hosts already relying on unconditional
// autoplay.
//
// Mirrors the shared channel/teardown helpers established in
// media_feed_test.dart, plus the native-event injection helper established
// in media_player_network_status_test.dart.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visibility_detector/visibility_detector.dart';
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

String? _playerIdOf(MethodCall call) =>
    (call.arguments as Map?)?['playerId'] as String?;

Future<void> _injectEvent(String method, Map<String, dynamic> arguments) async {
  final codec = const StandardMethodCodec();
  final data = codec.encodeMethodCall(MethodCall(method, arguments));
  await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .handlePlatformMessage('zmedia_player', data, (_) {});
}

MediaItem _item(int index) => MediaItem(
      id: 'feed-network-item-$index',
      title: 'Item $index',
      url: 'https://cdn.example.com/video-$index.mp4',
    );

Future<void> _teardown(WidgetTester tester, {MediaPlayerPool? pool}) async {
  await tester.pump(const Duration(milliseconds: 60));
  await tester.pumpAndSettle();
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 260));
  if (pool != null) {
    await pool.releaseAll();
    await tester.pump();
  }
  _resetHandler();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    final calls = _installCapture();
    final warmup =
        MediaController.create(playerId: 'warmup-feed-network-timer');
    warmup.dispose();
    calls.clear();
    _resetHandler();

    VisibilityDetectorController.instance.updateInterval = Duration.zero;
  });

  group('F-06: MediaFeedConfig.autoPlayPolicy default', () {
    testWidgets(
        'autoPlayPolicy: null (the default) autoplays regardless of '
        'network status -- no behaviour change from every release before '
        'Stage 7d', (tester) async {
      final calls = _installCapture();
      final pool = MediaPlayerPool(maxSize: 2);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 400,
              child: MediaFeed(
                itemCount: 1,
                itemAt: _item,
                pool: pool,
                config: const MediaFeedConfig(
                  autoPlay: true,
                  autoPlayDelay: Duration.zero,
                  pauseOthersOnPlay: false,
                  prewarmWindow: 0,
                  activationDebounce: Duration.zero,
                  // autoPlayPolicy left unset (null) -- the default.
                ),
                itemBuilder: (context, state) => SizedBox(
                  key: ValueKey('feed-item-${state.index}'),
                  height: 400,
                  child: state.videoSurface,
                ),
              ),
            ),
          ),
        ),
      );

      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 10));
      }

      expect(
        calls.any((c) => c.method == 'play'),
        isTrue,
        reason: 'with no policy configured, autoplay must proceed even '
            'though the network status was never reported (stays '
            '"unknown") -- the default must not silently start refusing',
      );

      await _teardown(tester, pool: pool);
      calls.clear();
      _resetHandler();
    });
  });

  group('F-06: an opted-in autoPlayPolicy can hold autoplay', () {
    testWidgets(
        'a policy that refuses holds autoplay entirely, keeps the item '
        'loaded, and MediaFeedItemState.autoPlayBlockedByPolicy reflects '
        'it -- manual play() remains available', (tester) async {
      final calls = _installCapture();
      final pool = MediaPlayerPool(maxSize: 2);
      final states = <int, MediaFeedItemState>{};

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 400,
              child: MediaFeed(
                itemCount: 1,
                itemAt: _item,
                pool: pool,
                config: MediaFeedConfig(
                  autoPlay: true,
                  autoPlayDelay: const Duration(milliseconds: 40),
                  pauseOthersOnPlay: false,
                  prewarmWindow: 0,
                  activationDebounce: Duration.zero,
                  autoPlayPolicy: (status) => false,
                ),
                itemBuilder: (context, state) {
                  states[state.index] = state;
                  return SizedBox(
                    key: ValueKey('feed-item-${state.index}'),
                    height: 400,
                    child: state.videoSurface,
                  );
                },
              ),
            ),
          ),
        ),
      );

      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 10));
      }

      expect(
        calls.any((c) => c.method == 'play'),
        isFalse,
        reason: 'a policy that refuses must hold autoplay entirely',
      );
      expect(
        pool.liveCount,
        1,
        reason: 'the item stays loaded (acquire() still ran) -- only play() '
            'is held back',
      );
      expect(states[0]?.isActive, isTrue);
      expect(
        states[0]?.autoPlayBlockedByPolicy,
        isTrue,
        reason: 'hosts need a way to show a "held for your network" '
            'affordance instead of a silent non-autoplay',
      );
      expect(
        states[0]?.play,
        isNotNull,
        reason: 'manual play must still be available via the action '
            'callback',
      );

      // Exercise the manual play() escape hatch.
      states[0]!.play!();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 20));

      expect(calls.any((c) => c.method == 'play'), isTrue);

      await _teardown(tester, pool: pool);
      calls.clear();
      _resetHandler();
    });

    testWidgets(
        'the policy is consulted with this item\'s own live '
        'MediaPlayer.networkStatus, not a default/unrelated one',
        (tester) async {
      final calls = _installCapture();
      final pool = MediaPlayerPool(maxSize: 2);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 400,
              child: MediaFeed(
                itemCount: 1,
                itemAt: _item,
                pool: pool,
                config: MediaFeedConfig(
                  autoPlay: true,
                  autoPlayDelay: const Duration(milliseconds: 80),
                  pauseOthersOnPlay: false,
                  prewarmWindow: 0,
                  activationDebounce: Duration.zero,
                  autoPlayPolicy: conservativeAutoPlayPolicy,
                ),
                itemBuilder: (context, state) => SizedBox(
                  key: ValueKey('feed-item-${state.index}'),
                  height: 400,
                  child: state.videoSurface,
                ),
              ),
            ),
          ),
        ),
      );

      // Let the item acquire its slot (activationDebounce: 0 -- immediate).
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 10));

      final loadCall = calls.firstWhere((c) => c.method == 'load');
      final playerId = _playerIdOf(loadCall)!;

      // Report a metered connection for THIS item's own player before its
      // autoPlayDelay elapses.
      await _injectEvent('onNetworkStatusChanged', {
        'playerId': playerId,
        'quality': 'excellent',
        'downloadSpeed': 10000000,
        'isMetered': true,
        'connectionType': 'cellular',
      });

      await tester.pump(const Duration(milliseconds: 90));
      await tester.pump();

      expect(
        calls.any((c) => c.method == 'play'),
        isFalse,
        reason: 'conservativeAutoPlayPolicy must refuse on a metered '
            'network, and it must be seeing this item\'s own live network '
            'status (injected above), not a default "unknown" one',
      );

      await _teardown(tester, pool: pool);
      calls.clear();
      _resetHandler();
    });

    testWidgets(
        'the policy allows autoplay on an unmetered, good-quality network',
        (tester) async {
      final calls = _installCapture();
      final pool = MediaPlayerPool(maxSize: 2);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 400,
              child: MediaFeed(
                itemCount: 1,
                itemAt: _item,
                pool: pool,
                config: MediaFeedConfig(
                  autoPlay: true,
                  autoPlayDelay: const Duration(milliseconds: 80),
                  pauseOthersOnPlay: false,
                  prewarmWindow: 0,
                  activationDebounce: Duration.zero,
                  autoPlayPolicy: conservativeAutoPlayPolicy,
                ),
                itemBuilder: (context, state) => SizedBox(
                  key: ValueKey('feed-item-${state.index}'),
                  height: 400,
                  child: state.videoSurface,
                ),
              ),
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 10));

      final loadCall = calls.firstWhere((c) => c.method == 'load');
      final playerId = _playerIdOf(loadCall)!;

      await _injectEvent('onNetworkStatusChanged', {
        'playerId': playerId,
        'quality': 'excellent',
        'downloadSpeed': 10000000,
        'isMetered': false,
        'connectionType': 'wifi',
      });

      await tester.pump(const Duration(milliseconds: 90));
      await tester.pump();

      expect(
        calls.any((c) => c.method == 'play'),
        isTrue,
        reason: 'an unmetered, excellent-quality connection must be '
            'allowed to autoplay under conservativeAutoPlayPolicy',
      );

      await _teardown(tester, pool: pool);
      calls.clear();
      _resetHandler();
    });
  });

  group('conservativeAutoPlayPolicy (unit)', () {
    NetworkStatus status({
      required NetworkQuality quality,
      required bool isMetered,
      required ConnectionType connectionType,
    }) {
      return NetworkStatus(
        quality: quality,
        downloadSpeed: 10000000,
        isMetered: isMetered,
        connectionType: connectionType,
        timestamp: DateTime.now(),
      );
    }

    test('refuses on a metered connection regardless of quality', () {
      expect(
        conservativeAutoPlayPolicy(status(
          quality: NetworkQuality.excellent,
          isMetered: true,
          connectionType: ConnectionType.cellular,
        )),
        isFalse,
      );
    });

    test('refuses on poor/offline/unknown quality even when unmetered', () {
      for (final quality in [
        NetworkQuality.poor,
        NetworkQuality.offline,
        NetworkQuality.unknown,
      ]) {
        expect(
          conservativeAutoPlayPolicy(status(
            quality: quality,
            isMetered: false,
            connectionType: ConnectionType.wifi,
          )),
          isFalse,
          reason: 'quality=$quality',
        );
      }
    });

    test('allows fair/good/excellent quality on an unmetered connection', () {
      for (final quality in [
        NetworkQuality.fair,
        NetworkQuality.good,
        NetworkQuality.excellent,
      ]) {
        expect(
          conservativeAutoPlayPolicy(status(
            quality: quality,
            isMetered: false,
            connectionType: ConnectionType.wifi,
          )),
          isTrue,
          reason: 'quality=$quality',
        );
      }
    });
  });
}
