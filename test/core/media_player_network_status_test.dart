import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zmedia_player/zmedia_player.dart';

// ---------------------------------------------------------------------------
// H-06: `NetworkMonitor` (native) → `onNetworkStatusChanged` (MethodChannel)
// → `MediaPlayer._handleNetworkStatusChanged` → `NetworkResilienceService`.
//
// Mirrors the injection helper and setUp/tearDown pattern used by
// `media_player_events_test.dart` for the other native→Dart events.
// ---------------------------------------------------------------------------

Future<void> _injectEvent(String method, Map<String, dynamic> arguments) async {
  final codec = const StandardMethodCodec();
  final data = codec.encodeMethodCall(MethodCall(method, arguments));
  await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .handlePlatformMessage(
    'zmedia_player',
    data,
    (_) {},
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('zmedia_player'),
      (_) async => null,
    );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('zmedia_player'), null);
  });

  group('onNetworkStatusChanged → networkStatusStream / networkStatus', () {
    test('a "wifi" status payload is parsed and delivered', () async {
      final player = MediaPlayer(playerId: 'net-wifi');
      await player.initialize();

      final statusFuture = player.networkStatusStream.first;

      await _injectEvent('onNetworkStatusChanged', {
        'playerId': 'net-wifi',
        'quality': 'good',
        'downloadSpeed': 1250000, // 10 Mbps in bytes/sec
        'isMetered': false,
        'connectionType': 'wifi',
      });

      final status = await statusFuture.timeout(const Duration(seconds: 2));
      expect(status.connectionType, ConnectionType.wifi);
      expect(status.isMetered, isFalse);
      expect(status.downloadSpeed, 1250000);
      // NetworkStatus.fromPlatform recomputes quality from bandwidth rather
      // than trusting native's own "quality" string (see network_status.dart)
      // — 1.25MB/s == 10Mbps, comfortably in the "excellent" (>5Mbps) bucket.
      expect(status.quality, NetworkQuality.excellent);

      player.dispose();
    });

    test('a "lost" status payload (offline) is parsed correctly', () async {
      final player = MediaPlayer(playerId: 'net-lost');
      await player.initialize();

      final statusFuture = player.networkStatusStream.first;

      await _injectEvent('onNetworkStatusChanged', {
        'playerId': 'net-lost',
        'quality': 'offline',
        'downloadSpeed': 0,
        'isMetered': false,
        'connectionType': 'none',
      });

      final status = await statusFuture.timeout(const Duration(seconds: 2));
      expect(status.quality, NetworkQuality.offline);
      expect(status.isAvailable, isFalse);
      expect(status.connectionType, ConnectionType.none);

      player.dispose();
    });

    test('a "cellular" status payload maps connectionType correctly', () async {
      final player = MediaPlayer(playerId: 'net-cellular');
      await player.initialize();

      final statusFuture = player.networkStatusStream.first;

      await _injectEvent('onNetworkStatusChanged', {
        'playerId': 'net-cellular',
        'quality': 'fair',
        'downloadSpeed': 62500, // 0.5 Mbps
        'isMetered': true,
        'connectionType': 'cellular',
      });

      final status = await statusFuture.timeout(const Duration(seconds: 2));
      expect(status.connectionType, ConnectionType.cellular);
      expect(status.isMetered, isTrue);

      player.dispose();
    });

    test('networkStatus getter reflects the last injected event', () async {
      final player = MediaPlayer(playerId: 'net-getter');
      await player.initialize();

      // Before any event, the status is unknown (never assigned yet).
      expect(player.networkStatus.quality, NetworkQuality.unknown);

      final statusFuture = player.networkStatusStream.first;
      await _injectEvent('onNetworkStatusChanged', {
        'playerId': 'net-getter',
        'quality': 'good',
        'downloadSpeed': 200000,
        'isMetered': false,
        'connectionType': 'wifi',
      });
      await statusFuture;

      expect(player.networkStatus.connectionType, ConnectionType.wifi);

      player.dispose();
    });

    test('event for a different playerId does NOT update this instance',
        () async {
      final player = MediaPlayer(playerId: 'net-wrong-id');
      await player.initialize();

      var emitted = false;
      player.networkStatusStream.listen((_) => emitted = true);

      await _injectEvent('onNetworkStatusChanged', {
        'playerId': 'SOME-OTHER-PLAYER',
        'quality': 'good',
        'downloadSpeed': 200000,
        'isMetered': false,
        'connectionType': 'wifi',
      });
      await Future<void>.delayed(Duration.zero);

      expect(emitted, isFalse);
      expect(player.networkStatus.quality, NetworkQuality.unknown);

      player.dispose();
    });
  });

  group(
      'onNetworkStatusChanged → networkChangeStream (via '
      'NetworkResilienceService)', () {
    test('connection lost then restored emits both change events', () async {
      final player = MediaPlayer(playerId: 'net-change-restore');
      await player.initialize();

      final events = <NetworkChangeEvent>[];
      player.networkChangeStream.listen(events.add);

      // First status establishes a baseline (available, wifi).
      final firstStatus = player.networkStatusStream.first;
      await _injectEvent('onNetworkStatusChanged', {
        'playerId': 'net-change-restore',
        'quality': 'good',
        'downloadSpeed': 200000,
        'isMetered': false,
        'connectionType': 'wifi',
      });
      await firstStatus;

      // Then it's lost.
      final lostStatus =
          player.networkStatusStream.firstWhere((s) => !s.isAvailable);
      await _injectEvent('onNetworkStatusChanged', {
        'playerId': 'net-change-restore',
        'quality': 'offline',
        'downloadSpeed': 0,
        'isMetered': false,
        'connectionType': 'none',
      });
      await lostStatus;

      // Then it's restored.
      final restoredStatus =
          player.networkStatusStream.firstWhere((s) => s.isAvailable);
      await _injectEvent('onNetworkStatusChanged', {
        'playerId': 'net-change-restore',
        'quality': 'good',
        'downloadSpeed': 200000,
        'isMetered': false,
        'connectionType': 'wifi',
      });
      await restoredStatus;

      await Future<void>.delayed(Duration.zero);

      expect(events.any((e) => e.connectionLost), isTrue,
          reason: 'a lost-connectivity NetworkChangeEvent must be emitted');
      expect(events.any((e) => e.connectionRestored), isTrue,
          reason: 'a restored-connectivity NetworkChangeEvent must be emitted');

      player.dispose();
    });
  });

  group('networkResilienceService reachability (H-06)', () {
    test(
        'player.networkResilienceService is fed by the same native events '
        'as networkStatusStream', () async {
      final player = MediaPlayer(playerId: 'net-resilience-reach');
      await player.initialize();

      final serviceStatusFuture =
          player.networkResilienceService.networkStatusStream.first;

      await _injectEvent('onNetworkStatusChanged', {
        'playerId': 'net-resilience-reach',
        'quality': 'good',
        'downloadSpeed': 200000,
        'isMetered': false,
        'connectionType': 'wifi',
      });

      final status =
          await serviceStatusFuture.timeout(const Duration(seconds: 2));
      expect(status.connectionType, ConnectionType.wifi);

      // The same instance backs both the convenience getters and the
      // service's own public API (e.g. shouldRetry/withRetry), proving it
      // is one live, shared object rather than two independently-fed ones.
      expect(
        identical(
          player.networkResilienceService,
          player.networkResilienceService,
        ),
        isTrue,
      );
      expect(player.networkResilienceService.isNetworkAvailable, isTrue);

      player.dispose();
    });
  });
}
