import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zmedia_player/zmedia_player.dart';

// ---------------------------------------------------------------------------
// Helper — inject a native→Dart event through the test messenger
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
    // Default no-op mock so outgoing calls don't throw.
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

  // -------------------------------------------------------------------------
  group('onStateChanged → stateStream', () {
    test('playing state is delivered to stateStream', () async {
      final player = MediaPlayer(playerId: 'ev-state-playing');
      await player.initialize();

      final stateFuture = player.stateStream.first;

      await _injectEvent('onStateChanged', {
        'playerId': 'ev-state-playing',
        'state': 'playing',
        'isBuffering': false,
        'bufferPercentage': 0.0,
      });

      final state = await stateFuture.timeout(const Duration(seconds: 2));
      expect(state.state, PlayerState.playing);

      player.dispose();
    });

    test('paused state is delivered correctly', () async {
      final player = MediaPlayer(playerId: 'ev-state-paused');
      await player.initialize();

      final stateFuture = player.stateStream.first;

      await _injectEvent('onStateChanged', {
        'playerId': 'ev-state-paused',
        'state': 'paused',
        'isBuffering': false,
        'bufferPercentage': 0.0,
      });

      final state = await stateFuture.timeout(const Duration(seconds: 2));
      expect(state.state, PlayerState.paused);

      player.dispose();
    });

    test('buffering state carries isBuffering=true', () async {
      final player = MediaPlayer(playerId: 'ev-state-buffering');
      await player.initialize();

      final stateFuture = player.stateStream.first;

      await _injectEvent('onStateChanged', {
        'playerId': 'ev-state-buffering',
        'state': 'buffering',
        'isBuffering': true,
        'bufferPercentage': 35.0,
      });

      final state = await stateFuture.timeout(const Duration(seconds: 2));
      expect(state.state, PlayerState.buffering);
      expect(state.isBuffering, isTrue);

      player.dispose();
    });

    test('completed state is delivered', () async {
      final player = MediaPlayer(playerId: 'ev-state-completed');
      await player.initialize();

      final stateFuture = player.stateStream.first;

      await _injectEvent('onStateChanged', {
        'playerId': 'ev-state-completed',
        'state': 'completed',
        'isBuffering': false,
        'bufferPercentage': 100.0,
      });

      final state = await stateFuture.timeout(const Duration(seconds: 2));
      expect(state.state, PlayerState.completed);

      player.dispose();
    });

    test('currentState is updated synchronously with stream', () async {
      final player = MediaPlayer(playerId: 'ev-state-current');
      await player.initialize();

      // Await at least one emission so the stream handler has run.
      final stateFuture = player.stateStream.first;

      await _injectEvent('onStateChanged', {
        'playerId': 'ev-state-current',
        'state': 'playing',
        'isBuffering': false,
        'bufferPercentage': 0.0,
      });
      await stateFuture;

      expect(player.currentState.state, PlayerState.playing,
          reason: 'currentState must mirror the last emitted state');

      player.dispose();
    });

    test('event for wrong playerId does NOT update this instance', () async {
      final player = MediaPlayer(playerId: 'ev-state-wrong-id');
      await player.initialize();

      var notified = false;
      player.stateStream.listen((_) => notified = true);

      await _injectEvent('onStateChanged', {
        'playerId': 'DIFFERENT-PLAYER',
        'state': 'playing',
        'isBuffering': false,
        'bufferPercentage': 0.0,
      });
      await Future<void>.delayed(Duration.zero);

      expect(notified, isFalse);
      expect(player.currentState.state, PlayerState.idle);

      player.dispose();
    });
  });

  // -------------------------------------------------------------------------
  group('onPositionChanged → positionStream', () {
    test('delivers position as Duration to positionStream', () async {
      final player = MediaPlayer(playerId: 'ev-pos-1');
      await player.initialize();

      final posFuture = player.positionStream.first;

      await _injectEvent('onPositionChanged', {
        'playerId': 'ev-pos-1',
        'position': 15000, // 15 seconds in ms
      });

      final pos = await posFuture.timeout(const Duration(seconds: 2));
      expect(pos.inMilliseconds, 15000);

      player.dispose();
    });

    test('position is reflected in currentState.position', () async {
      final player = MediaPlayer(playerId: 'ev-pos-state');
      await player.initialize();

      final posFuture = player.positionStream.first;
      await _injectEvent('onPositionChanged', {
        'playerId': 'ev-pos-state',
        'position': 30000,
      });
      await posFuture;

      expect(player.currentState.position.inMilliseconds, 30000);

      player.dispose();
    });

    test('multiple position events are delivered in order', () async {
      final player = MediaPlayer(playerId: 'ev-pos-multi');
      await player.initialize();

      final positions = <int>[];
      player.positionStream.listen((d) => positions.add(d.inMilliseconds));

      await _injectEvent(
          'onPositionChanged', {'playerId': 'ev-pos-multi', 'position': 1000});
      await _injectEvent(
          'onPositionChanged', {'playerId': 'ev-pos-multi', 'position': 2000});
      await _injectEvent(
          'onPositionChanged', {'playerId': 'ev-pos-multi', 'position': 3000});
      await Future<void>.delayed(Duration.zero);

      expect(positions, containsAllInOrder([1000, 2000, 3000]));

      player.dispose();
    });
  });

  // -------------------------------------------------------------------------
  group('onDurationChanged → durationStream', () {
    test('delivers duration to durationStream', () async {
      final player = MediaPlayer(playerId: 'ev-dur-1');
      await player.initialize();

      final durFuture = player.durationStream.first;

      await _injectEvent('onDurationChanged', {
        'playerId': 'ev-dur-1',
        'duration': 120000, // 2 minutes
        'isLive': false,
      });

      final dur = await durFuture.timeout(const Duration(seconds: 2));
      expect(dur.inMilliseconds, 120000);

      player.dispose();
    });

    test('duration updates currentState.duration', () async {
      final player = MediaPlayer(playerId: 'ev-dur-state');
      await player.initialize();

      final durFuture = player.durationStream.first;
      await _injectEvent('onDurationChanged', {
        'playerId': 'ev-dur-state',
        'duration': 60000,
      });
      await durFuture;

      expect(player.currentState.duration.inMilliseconds, 60000);

      player.dispose();
    });
  });

  // -------------------------------------------------------------------------
  group('onQualityTracksChanged → qualityTracksStream', () {
    test('parses track list and emits on qualityTracksStream', () async {
      final player = MediaPlayer(playerId: 'ev-qt-1');
      await player.initialize();

      final tracksFuture = player.qualityTracksStream.first;

      await _injectEvent('onQualityTracksChanged', {
        'playerId': 'ev-qt-1',
        'tracks': [
          {
            'id': 'q-720',
            'name': 'HD',
            'bitrate': 3000000,
            'width': 1280,
            'height': 720,
            'isSelected': false,
            'isAvailable': true,
          },
          {
            'id': 'q-1080',
            'name': 'Full HD',
            'bitrate': 5000000,
            'width': 1920,
            'height': 1080,
            'isSelected': true,
            'isAvailable': true,
          },
        ],
      });

      final tracks = await tracksFuture.timeout(const Duration(seconds: 2));
      expect(tracks.length, 2);
      expect(tracks.map((t) => t.id), containsAll(['q-720', 'q-1080']));

      player.dispose();
    });

    test('qualityTracks getter reflects injected tracks', () async {
      final player = MediaPlayer(playerId: 'ev-qt-getter');
      await player.initialize();

      final tracksFuture = player.qualityTracksStream.first;
      await _injectEvent('onQualityTracksChanged', {
        'playerId': 'ev-qt-getter',
        'tracks': [
          {
            'id': 'q-480',
            'name': 'SD',
            'bitrate': 1500000,
            'isSelected': false,
            'isAvailable': true,
          },
        ],
      });
      await tracksFuture;

      expect(player.qualityTracks.length, 1);
      expect(player.qualityTracks.first.id, 'q-480');

      player.dispose();
    });
  });

  // -------------------------------------------------------------------------
  group('onAudioTracksChanged → audioTracksStream', () {
    test('parses audio track list and emits on audioTracksStream', () async {
      final player = MediaPlayer(playerId: 'ev-at-1');
      await player.initialize();

      final tracksFuture = player.audioTracksStream.first;

      await _injectEvent('onAudioTracksChanged', {
        'playerId': 'ev-at-1',
        'tracks': [
          {
            'id': 'a-en',
            'name': 'English',
            'language': 'en',
            'isSelected': true,
            'isAvailable': true,
          },
          {
            'id': 'a-fr',
            'name': 'French',
            'language': 'fr',
            'isSelected': false,
            'isAvailable': true,
          },
        ],
      });

      final tracks = await tracksFuture.timeout(const Duration(seconds: 2));
      expect(tracks.length, 2);
      expect(tracks.map((t) => t.language), containsAll(['en', 'fr']));

      player.dispose();
    });

    test('audioTracks getter reflects injected tracks', () async {
      final player = MediaPlayer(playerId: 'ev-at-getter');
      await player.initialize();

      final tracksFuture = player.audioTracksStream.first;
      await _injectEvent('onAudioTracksChanged', {
        'playerId': 'ev-at-getter',
        'tracks': [
          {
            'id': 'a-es',
            'name': 'Spanish',
            'language': 'es',
            'isSelected': false,
            'isAvailable': true,
          },
        ],
      });
      await tracksFuture;

      expect(player.audioTracks.length, 1);
      expect(player.audioTracks.first.id, 'a-es');

      player.dispose();
    });
  });

  // -------------------------------------------------------------------------
  group('onError → error state', () {
    test('onError sets PlayerState.error and stores errorMessage', () async {
      final player = MediaPlayer(playerId: 'ev-err-1');
      await player.initialize();

      final stateFuture = player.stateStream.first;

      await _injectEvent('onError', {
        'playerId': 'ev-err-1',
        'error': 'Playback failed: codec not found',
      });

      final state = await stateFuture.timeout(const Duration(seconds: 2));
      expect(state.state, PlayerState.error);
      expect(state.errorMessage, isNotNull);
      expect(state.errorMessage, contains('codec not found'));

      player.dispose();
    });

    test('error state is reflected in currentState', () async {
      final player = MediaPlayer(playerId: 'ev-err-current');
      await player.initialize();

      final stateFuture = player.stateStream.first;
      await _injectEvent('onError', {
        'playerId': 'ev-err-current',
        'error': 'Network unreachable',
      });
      await stateFuture;

      expect(player.currentState.state, PlayerState.error);

      player.dispose();
    });
  });

  // -------------------------------------------------------------------------
  group('onDrmSessionUpdate → drmSessionStream', () {
    test('parses DRM session with state "licensed" and emits', () async {
      final player = MediaPlayer(playerId: 'ev-drm-1');
      await player.initialize();

      final sessionFuture = player.drmSessionStream.first;
      final now = DateTime.now();

      await _injectEvent('onDrmSessionUpdate', {
        'playerId': 'ev-drm-1',
        'id': 'session-xyz',
        'state': 'licensed',
        'license': null,
        'errorMessage': null,
        'createdAt': now.millisecondsSinceEpoch,
        'updatedAt': now.millisecondsSinceEpoch,
      });

      final session = await sessionFuture.timeout(const Duration(seconds: 2));
      expect(session.id, 'session-xyz');
      expect(session.state, DrmSessionState.licensed);

      player.dispose();
    });

    test('parses DRM session with state "error" and errorMessage', () async {
      final player = MediaPlayer(playerId: 'ev-drm-err');
      await player.initialize();

      final sessionFuture = player.drmSessionStream.first;
      final now = DateTime.now();

      await _injectEvent('onDrmSessionUpdate', {
        'playerId': 'ev-drm-err',
        'id': 'session-error-1',
        'state': 'error',
        'license': null,
        'errorMessage': 'License server rejected request',
        'createdAt': now.millisecondsSinceEpoch,
        'updatedAt': now.millisecondsSinceEpoch,
      });

      final session = await sessionFuture.timeout(const Duration(seconds: 2));
      expect(session.state, DrmSessionState.error);
      expect(session.errorMessage, 'License server rejected request');

      player.dispose();
    });

    test('DRM session for wrong playerId is NOT emitted', () async {
      final player = MediaPlayer(playerId: 'ev-drm-wrong');
      await player.initialize();

      var emitted = false;
      player.drmSessionStream.listen((_) => emitted = true);
      final now = DateTime.now();

      await _injectEvent('onDrmSessionUpdate', {
        'playerId': 'COMPLETELY-DIFFERENT',
        'id': 'session-other',
        'state': 'licensed',
        'license': null,
        'errorMessage': null,
        'createdAt': now.millisecondsSinceEpoch,
        'updatedAt': now.millisecondsSinceEpoch,
      });
      await Future<void>.delayed(Duration.zero);

      expect(emitted, isFalse);

      player.dispose();
    });
  });

  // -------------------------------------------------------------------------
  // H-01: onError now also builds and emits a typed MediaPlayerException on
  // errorStream, using the MediaErrorCategory wire vocabulary. See
  // lib/src/core/exceptions.dart (MediaErrorCategory, mapNativeMediaError)
  // and the native categorization functions in MediaPlayerManager.kt/.swift.
  group('onError → errorStream (typed exceptions)', () {
    test('category NETWORK emits NetworkException', () async {
      final player = MediaPlayer(playerId: 'ev-err-network');
      await player.initialize();

      final errorFuture = player.errorStream.first;

      await _injectEvent('onError', {
        'playerId': 'ev-err-network',
        'error': 'Connection failed',
        'category': 'NETWORK',
      });

      final error = await errorFuture.timeout(const Duration(seconds: 2));
      expect(error, isA<NetworkException>());

      player.dispose();
    });

    test('category HTTP with httpStatusCode emits MediaLoadException',
        () async {
      final player = MediaPlayer(playerId: 'ev-err-http');
      await player.initialize();

      final errorFuture = player.errorStream.first;

      await _injectEvent('onError', {
        'playerId': 'ev-err-http',
        'error': 'Not found',
        'category': 'HTTP',
        'httpStatusCode': 404,
      });

      final error = await errorFuture.timeout(const Duration(seconds: 2));
      expect(error, isA<MediaLoadException>());
      expect((error as MediaLoadException).statusCode, 404);

      player.dispose();
    });

    test('category DRM emits DrmException', () async {
      final player = MediaPlayer(playerId: 'ev-err-drm');
      await player.initialize();

      final errorFuture = player.errorStream.first;

      await _injectEvent('onError', {
        'playerId': 'ev-err-drm',
        'error': 'License denied',
        'category': 'DRM',
        'nativeErrorCode': 'ERROR_CODE_DRM_LICENSE_ACQUISITION_FAILED',
      });

      final error = await errorFuture.timeout(const Duration(seconds: 2));
      expect(error, isA<DrmException>());
      expect((error as DrmException).errorCode,
          'ERROR_CODE_DRM_LICENSE_ACQUISITION_FAILED');

      player.dispose();
    });

    test('category DECODER emits PlaybackException with category set',
        () async {
      final player = MediaPlayer(playerId: 'ev-err-decoder');
      await player.initialize();

      final errorFuture = player.errorStream.first;

      await _injectEvent('onError', {
        'playerId': 'ev-err-decoder',
        'error': 'Unsupported codec',
        'category': 'DECODER',
      });

      final error = await errorFuture.timeout(const Duration(seconds: 2));
      expect(error, isA<PlaybackException>());
      expect((error as PlaybackException).category, MediaErrorCategory.decoder);

      player.dispose();
    });

    test(
        'missing category (older cached native build) emits '
        'PlaybackException.unknown, not nothing', () async {
      final player = MediaPlayer(playerId: 'ev-err-legacy');
      await player.initialize();

      final errorFuture = player.errorStream.first;

      await _injectEvent('onError', {
        'playerId': 'ev-err-legacy',
        'error': 'Something went wrong',
      });

      final error = await errorFuture.timeout(const Duration(seconds: 2));
      expect(error, isA<PlaybackException>());
      expect((error as PlaybackException).category, MediaErrorCategory.unknown);

      player.dispose();
    });

    test(
        'errorStream event does not replace the untyped errorMessage on '
        'stateStream', () async {
      final player = MediaPlayer(playerId: 'ev-err-both');
      await player.initialize();

      final stateFuture = player.stateStream.first;
      final errorFuture = player.errorStream.first;

      await _injectEvent('onError', {
        'playerId': 'ev-err-both',
        'error': 'Codec not found',
        'category': 'DECODER',
      });

      final state = await stateFuture.timeout(const Duration(seconds: 2));
      final error = await errorFuture.timeout(const Duration(seconds: 2));

      expect(state.state, PlayerState.error);
      expect(state.errorMessage, contains('Codec not found'));
      expect(error.message, 'Codec not found');

      player.dispose();
    });
  });

  // -------------------------------------------------------------------------
  // H-01: DRM session errors are also bridged onto errorStream as a typed
  // DrmException, not just as an untyped DrmSessionState.error.
  group('onDrmSessionUpdate error state → errorStream', () {
    test('DRM session error also emits a DrmException on errorStream',
        () async {
      final player = MediaPlayer(playerId: 'ev-drm-error-bridge');
      await player.initialize();

      final errorFuture = player.errorStream.first;
      final now = DateTime.now();

      await _injectEvent('onDrmSessionUpdate', {
        'playerId': 'ev-drm-error-bridge',
        'id': 'session-bridge',
        'state': 'error',
        'license': null,
        'errorMessage': 'License server rejected request',
        'createdAt': now.millisecondsSinceEpoch,
        'updatedAt': now.millisecondsSinceEpoch,
      });

      final error = await errorFuture.timeout(const Duration(seconds: 2));
      expect(error, isA<DrmException>());
      expect(error.message, 'License server rejected request');

      player.dispose();
    });

    // C-01: a DRM session error must also flip PlaybackState.state to
    // PlayerState.error (mirroring _handleError), not just emit on
    // errorStream. Before this fix, currentState.state stayed wherever it
    // was — a DRM failure was reachable via errorStream but invisible to
    // anything driven by stateStream/currentState (e.g.
    // MediaController.hasError).
    test('DRM session error also drives PlaybackState.state to error',
        () async {
      final player = MediaPlayer(playerId: 'ev-drm-error-state');
      await player.initialize();

      // Simulate the player having been mid-buffering (the normal state
      // load() leaves it in) when the DRM session fails, so this test can't
      // pass by coincidence of the default idle state already being
      // "error"-like.
      await _injectEvent('onStateChanged', {
        'playerId': 'ev-drm-error-state',
        'state': 'buffering',
        'isBuffering': true,
        'bufferPercentage': 0.0,
      });
      await Future<void>.delayed(Duration.zero);
      expect(player.currentState.state, PlayerState.buffering);

      final stateFuture = player.stateStream.first;
      final now = DateTime.now();

      await _injectEvent('onDrmSessionUpdate', {
        'playerId': 'ev-drm-error-state',
        'id': 'session-state-bridge',
        'state': 'error',
        'license': null,
        'errorMessage': 'License server rejected request',
        'createdAt': now.millisecondsSinceEpoch,
        'updatedAt': now.millisecondsSinceEpoch,
      });

      final state = await stateFuture.timeout(const Duration(seconds: 2));
      expect(state.state, PlayerState.error);
      expect(state.errorMessage, 'License server rejected request');
      expect(player.currentState.state, PlayerState.error);

      player.dispose();
    });
  });

  // -------------------------------------------------------------------------
  // H-01: audio-focus-loss pause reason (Android), surfaced out-of-band via
  // pauseReasonStream since PlaybackState has no field for it.
  group('onStateChanged pauseReason → pauseReasonStream', () {
    test('pauseReason "audioFocusLoss" emits PlayerPauseReason.audioFocusLoss',
        () async {
      final player = MediaPlayer(playerId: 'ev-pause-focus');
      await player.initialize();

      final pauseReasonFuture = player.pauseReasonStream.first;

      await _injectEvent('onStateChanged', {
        'playerId': 'ev-pause-focus',
        'state': 'paused',
        'isBuffering': false,
        'bufferPercentage': 0.0,
        'pauseReason': 'audioFocusLoss',
      });

      final reason =
          await pauseReasonFuture.timeout(const Duration(seconds: 2));
      expect(reason, PlayerPauseReason.audioFocusLoss);

      player.dispose();
    });

    test('a normal pause (no pauseReason) does not emit on pauseReasonStream',
        () async {
      final player = MediaPlayer(playerId: 'ev-pause-user');
      await player.initialize();

      var emitted = false;
      player.pauseReasonStream.listen((_) => emitted = true);

      final stateFuture = player.stateStream.first;
      await _injectEvent('onStateChanged', {
        'playerId': 'ev-pause-user',
        'state': 'paused',
        'isBuffering': false,
        'bufferPercentage': 0.0,
      });
      await stateFuture;
      await Future<void>.delayed(Duration.zero);

      expect(emitted, isFalse);

      player.dispose();
    });
  });

  // -------------------------------------------------------------------------
  group('onBandwidthChanged → bandwidthStream', () {
    test('delivers bandwidth value to bandwidthStream', () async {
      final player = MediaPlayer(playerId: 'ev-bw-1');
      await player.initialize();

      final bwFuture = player.bandwidthStream.first;

      await _injectEvent('onBandwidthChanged', {
        'playerId': 'ev-bw-1',
        'bandwidth': 5000000,
      });

      final bw = await bwFuture.timeout(const Duration(seconds: 2));
      expect(bw, 5000000);

      player.dispose();
    });

    test('currentBandwidth is updated after event', () async {
      final player = MediaPlayer(playerId: 'ev-bw-current');
      await player.initialize();

      final bwFuture = player.bandwidthStream.first;
      await _injectEvent('onBandwidthChanged', {
        'playerId': 'ev-bw-current',
        'bandwidth': 8000000,
      });
      await bwFuture;

      expect(player.currentBandwidth, 8000000);

      player.dispose();
    });
  });
}
