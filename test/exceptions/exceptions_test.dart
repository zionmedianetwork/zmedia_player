import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:zmedia_player/zmedia_player.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('MediaPlayerException Hierarchy', () {
    test('PlayerDisposedException creates correctly', () {
      const exception = PlayerDisposedException();
      expect(exception, isA<MediaPlayerException>());
      expect(exception.message, 'Player has been disposed');
      expect(exception.toString(), contains('PlayerDisposedException'));
    });

    test('PlayerDisposedException with custom message', () {
      const exception = PlayerDisposedException('Custom disposed message');
      expect(exception.message, 'Custom disposed message');
    });

    test('MediaLoadException creates correctly', () {
      const exception = MediaLoadException(
        'Failed to load video',
        url: 'https://example.com/video.mp4',
        statusCode: 404,
      );

      expect(exception, isA<MediaPlayerException>());
      expect(exception.message, 'Failed to load video');
      expect(exception.url, 'https://example.com/video.mp4');
      expect(exception.statusCode, 404);
      expect(exception.toString(), contains('MediaLoadException'));
      expect(exception.toString(), contains('https://example.com/video.mp4'));
    });

    test('NetworkException for offline scenario', () {
      const exception = NetworkException(
        'No internet connection',
        isOffline: true,
      );

      expect(exception, isA<MediaPlayerException>());
      expect(exception.isOffline, true);
      expect(exception.isTimeout, false);
      expect(exception.toString(), contains('No internet connection'));
    });

    test('NetworkException for timeout scenario', () {
      const exception = NetworkException(
        'Request timed out',
        isTimeout: true,
      );

      expect(exception.isTimeout, true);
      expect(exception.isOffline, false);
      expect(exception.toString(), contains('timed out'));
    });

    test('DrmException with license error', () {
      const exception = DrmException(
        'License acquisition failed',
        drmType: 'Widevine',
        errorCode: 'DRM_LICENSE_ERROR',
        isLicenseError: true,
      );

      expect(exception, isA<MediaPlayerException>());
      expect(exception.drmType, 'Widevine');
      expect(exception.errorCode, 'DRM_LICENSE_ERROR');
      expect(exception.isLicenseError, true);
      expect(exception.isCertificateError, false);
      expect(exception.toString(), contains('License error'));
    });

    test('DrmException with certificate error', () {
      const exception = DrmException(
        'Certificate validation failed',
        drmType: 'FairPlay',
        isCertificateError: true,
      );

      expect(exception.isCertificateError, true);
      expect(exception.isLicenseError, false);
      expect(exception.toString(), contains('Certificate error'));
    });

    test('PlaybackException creates correctly', () {
      const exception = PlaybackException(
        'Playback failed',
        errorCode: 'PLAYBACK_001',
      );

      expect(exception, isA<MediaPlayerException>());
      expect(exception.message, 'Playback failed');
      expect(exception.errorCode, 'PLAYBACK_001');
      expect(exception.category, MediaErrorCategory.unknown,
          reason: 'category defaults to unknown when native sends none');
    });

    test('PlaybackException carries an explicit category', () {
      const exception = PlaybackException(
        'Unsupported codec',
        errorCode: 'ERROR_CODE_DECODING_FORMAT_UNSUPPORTED',
        category: MediaErrorCategory.decoder,
      );

      expect(exception.category, MediaErrorCategory.decoder);
      expect(exception.toString(), contains('DECODER'));
    });

    test('InvalidStateException with state info', () {
      const exception = InvalidStateException(
        'Cannot seek in idle state',
        currentState: 'idle',
        requiredState: 'playing or paused',
      );

      expect(exception, isA<MediaPlayerException>());
      expect(exception.currentState, 'idle');
      expect(exception.requiredState, 'playing or paused');
      expect(exception.toString(), contains('Current: idle'));
      expect(exception.toString(), contains('Required: playing or paused'));
    });

    test('ConfigurationException with parameter details', () {
      const exception = ConfigurationException(
        'Invalid volume value',
        parameter: 'volume',
        value: 1.5,
      );

      expect(exception, isA<MediaPlayerException>());
      expect(exception.parameter, 'volume');
      expect(exception.value, 1.5);
      expect(exception.toString(), contains('Parameter: volume'));
      expect(exception.toString(), contains('Value: 1.5'));
    });

    test('PlatformOperationException creates correctly', () {
      const exception = PlatformOperationException(
        'Platform operation failed',
        platform: 'android',
        code: 'PLATFORM_ERROR',
      );

      expect(exception, isA<MediaPlayerException>());
      expect(exception.platform, 'android');
      expect(exception.code, 'PLATFORM_ERROR');
      expect(exception.toString(), contains('android'));
    });

    test('Exception with details map', () {
      const exception = MediaLoadException(
        'Load failed',
        details: {'reason': 'timeout', 'attemptCount': 3},
      );

      expect(exception.details, isNotNull);
      expect(exception.details!['reason'], 'timeout');
      expect(exception.details!['attemptCount'], 3);
    });
  });

  group('MediaPlayer Exception Throwing', () {
    late MethodChannel channel;
    late List<MethodCall> methodCalls;

    setUp(() {
      methodCalls = [];
      channel = const MethodChannel('zmedia_player');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall call) async {
        methodCalls.add(call);

        // Simulate different error scenarios using the REAL codes/details
        // native actually sends (H-01) — not the fabricated
        // 'NETWORK_ERROR'/'DRM_LICENSE_ERROR'/'HTTP_ERROR' codes the old
        // version of this test asserted against, which no native code path
        // has ever emitted (see ZMediaPlayerPlugin.kt/.swift: every
        // `load` failure uses the `LOAD_ERROR` per-operation code, with a
        // best-effort `category` detail carrying the *why*).
        if (call.method == 'initialize') {
          return {'protocolVersion': MediaPlayer.protocolVersion};
        }
        if (call.method == 'load') {
          final args = call.arguments as Map;
          final url = (args['mediaItem'] as Map)['url'] as String;

          if (url.contains('network-error')) {
            throw PlatformException(
              code: 'LOAD_ERROR',
              message: 'Network connection failed',
              details: {'category': 'NETWORK'},
            );
          }
          if (url.contains('drm-error')) {
            throw PlatformException(
              code: 'LOAD_ERROR',
              message: 'License acquisition failed',
              details: {'category': 'DRM'},
            );
          }
          if (url.contains('http-error')) {
            throw PlatformException(
              code: 'LOAD_ERROR',
              message: 'Not found',
              details: {'category': 'HTTP', 'httpStatusCode': 404},
            );
          }
          if (url.contains('legacy-error')) {
            // Simulates an older cached native build that predates H-01's
            // `category` detail entirely.
            throw PlatformException(
              code: 'LOAD_ERROR',
              message: 'Something went wrong',
            );
          }
          return null;
        }
        if (call.method == 'play') {
          throw PlatformException(
            code: 'PLAY_ERROR',
            message: 'Playback failed',
          );
        }
        if (call.method == 'seekTo') {
          throw PlatformException(
            code: 'SEEK_ERROR',
            message: 'Seek failed',
          );
        }

        return null;
      });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    test('Disposed player throws PlayerDisposedException', () async {
      final player = MediaPlayer();
      await player.initialize();
      await player.dispose();

      expect(
        () => player.config,
        throwsA(isA<PlayerDisposedException>()),
      );
    });

    test('category: NETWORK throws NetworkException', () async {
      final player = MediaPlayer();
      await player.initialize();

      final mediaItem = MediaItem(
        id: 'test-1',
        url: 'https://example.com/network-error.mp4',
        title: 'Test Video',
      );

      expect(
        () => player.load(mediaItem),
        throwsA(isA<NetworkException>()),
      );

      await player.dispose();
    });

    test('category: DRM throws DrmException', () async {
      final player = MediaPlayer();
      await player.initialize();

      final mediaItem = MediaItem(
        id: 'test-2',
        url: 'https://example.com/drm-error.mp4',
        title: 'DRM Video',
        drmConfig: DrmConfig.widevine(
          licenseUrl: 'https://license.example.com',
        ),
      );

      expect(
        () => player.load(mediaItem),
        throwsA(isA<DrmException>()),
      );

      await player.dispose();
    });

    test('category: HTTP throws MediaLoadException carrying statusCode',
        () async {
      final player = MediaPlayer();
      await player.initialize();

      final mediaItem = MediaItem(
        id: 'test-3',
        url: 'https://example.com/http-error.mp4',
        title: 'Not Found Video',
      );

      await expectLater(
        player.load(mediaItem),
        throwsA(
          isA<MediaLoadException>().having(
            (e) => e.statusCode,
            'statusCode',
            404,
          ),
        ),
      );

      await player.dispose();
    });

    test(
        'load failure with no category detail (older cached native build) '
        'still throws MediaLoadException', () async {
      final player = MediaPlayer();
      await player.initialize();

      final mediaItem = MediaItem(
        id: 'test-legacy',
        url: 'https://example.com/legacy-error.mp4',
        title: 'Legacy Error Video',
      );

      expect(
        () => player.load(mediaItem),
        throwsA(isA<MediaLoadException>()),
      );

      await player.dispose();
    });

    test('Playback error throws PlaybackException', () async {
      final player = MediaPlayer();
      await player.initialize();

      // Mock successful load first
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall call) async {
        if (call.method == 'initialize' || call.method == 'load') {
          return null;
        }
        if (call.method == 'play') {
          throw PlatformException(
            code: 'PLAY_ERROR',
            message: 'Playback failed',
          );
        }
        return null;
      });

      final mediaItem = MediaItem(
        id: 'test-4',
        url: 'https://example.com/video.mp4',
        title: 'Test Video',
      );

      await player.load(mediaItem);

      expect(
        () => player.play(),
        throwsA(isA<PlaybackException>()),
      );

      await player.dispose();
    });

    test('Negative seek position throws ConfigurationException', () async {
      final player = MediaPlayer();
      await player.initialize();

      expect(
        () => player.seekTo(const Duration(milliseconds: -100)),
        throwsA(isA<ConfigurationException>()),
      );

      await player.dispose();
    });

    test('Empty playlist throws ConfigurationException', () async {
      final player = MediaPlayer();
      await player.initialize();

      final emptyPlaylist = Playlist(
        id: 'empty-playlist',
        title: 'Empty Playlist',
        items: const [],
      );

      expect(
        () => player.setPlaylist(emptyPlaylist),
        throwsA(isA<ConfigurationException>()),
      );

      await player.dispose();
    });

    test('No playlist skipToNext throws InvalidStateException', () async {
      final player = MediaPlayer();
      await player.initialize();

      expect(
        () => player.skipToNext(),
        throwsA(isA<InvalidStateException>()),
      );

      await player.dispose();
    });
  });

  group('Exception Context and Details', () {
    test('Exception preserves error context', () {
      final details = <String, dynamic>{
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        'userId': 'user123',
        'sessionId': 'session456',
      };

      final exception = NetworkException(
        'Connection failed',
        isOffline: true,
        details: details,
      );

      expect(exception.details, isNotNull);
      expect(exception.details!['userId'], 'user123');
      expect(exception.details!['sessionId'], 'session456');
    });

    test('Multiple exception types have distinct types', () {
      const networkEx = NetworkException('Network error');
      const drmEx = DrmException('DRM error');
      const playbackEx = PlaybackException('Playback error');
      const loadEx = MediaLoadException('Load error');

      expect(networkEx.runtimeType, isNot(equals(drmEx.runtimeType)));
      expect(drmEx.runtimeType, isNot(equals(playbackEx.runtimeType)));
      expect(playbackEx.runtimeType, isNot(equals(loadEx.runtimeType)));
    });

    test('Exception toString provides useful information', () {
      const exception = DrmException(
        'License error',
        drmType: 'Widevine',
        errorCode: 'E_LICENSE_001',
        isLicenseError: true,
      );

      final str = exception.toString();
      expect(str, contains('DrmException'));
      expect(str, contains('Widevine'));
      expect(str, contains('License error'));
      expect(str, contains('E_LICENSE_001'));
    });
  });

  // ---------------------------------------------------------------------
  // H-01: MediaErrorCategory / mapNativeMediaError
  // ---------------------------------------------------------------------
  group('MediaErrorCategory', () {
    test('fromWireValue round-trips every declared category', () {
      for (final category in MediaErrorCategory.values) {
        expect(
          MediaErrorCategory.fromWireValue(category.wireValue),
          category,
        );
      }
    });

    test('fromWireValue defaults to unknown for null/unrecognized input', () {
      expect(
          MediaErrorCategory.fromWireValue(null), MediaErrorCategory.unknown);
      expect(MediaErrorCategory.fromWireValue('NOT_A_REAL_CATEGORY'),
          MediaErrorCategory.unknown);
    });
  });

  group('mapNativeMediaError', () {
    test('NETWORK category maps to NetworkException', () {
      final exception = mapNativeMediaError(
        message: 'offline',
        categoryWireValue: 'NETWORK',
        details: {'isOffline': true},
      );
      expect(exception, isA<NetworkException>());
      expect((exception as NetworkException).isOffline, isTrue);
    });

    test('HTTP category maps to MediaLoadException with statusCode', () {
      final exception = mapNativeMediaError(
        message: 'not found',
        categoryWireValue: 'HTTP',
        details: {'httpStatusCode': 404},
      );
      expect(exception, isA<MediaLoadException>());
      expect((exception as MediaLoadException).statusCode, 404);
    });

    test('DRM category maps to DrmException', () {
      final exception = mapNativeMediaError(
        message: 'license denied',
        categoryWireValue: 'DRM',
        nativeErrorCode: 'ERROR_CODE_DRM_LICENSE_ACQUISITION_FAILED',
      );
      expect(exception, isA<DrmException>());
      expect((exception as DrmException).errorCode,
          'ERROR_CODE_DRM_LICENSE_ACQUISITION_FAILED');
    });

    test('DECODER category maps to PlaybackException with category set', () {
      final exception = mapNativeMediaError(
        message: 'codec unsupported',
        categoryWireValue: 'DECODER',
      );
      expect(exception, isA<PlaybackException>());
      expect((exception as PlaybackException).category,
          MediaErrorCategory.decoder);
    });

    test('SOURCE category maps to PlaybackException with category set', () {
      final exception = mapNativeMediaError(
        message: 'malformed manifest',
        categoryWireValue: 'SOURCE',
      );
      expect(exception, isA<PlaybackException>());
      expect(
          (exception as PlaybackException).category, MediaErrorCategory.source);
    });

    test('missing/unrecognized category maps to PlaybackException.unknown', () {
      final exception = mapNativeMediaError(message: 'something broke');
      expect(exception, isA<PlaybackException>());
      expect((exception as PlaybackException).category,
          MediaErrorCategory.unknown);
    });
  });

  // ---------------------------------------------------------------------
  // M-16: protocol version negotiation / MissingPluginException mapping
  // ---------------------------------------------------------------------
  group('M-16 protocol version negotiation', () {
    late MethodChannel channel;

    setUp(() {
      channel = const MethodChannel('zmedia_player');
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    test('initialize() sends this package\'s protocolVersion', () async {
      MethodCall? initializeCall;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'initialize') {
          initializeCall = call;
          return {'protocolVersion': MediaPlayer.protocolVersion};
        }
        return null;
      });

      final player = MediaPlayer(playerId: 'proto-sends-version');
      await player.initialize();

      expect(initializeCall, isNotNull);
      final args = initializeCall!.arguments as Map;
      expect(args['protocolVersion'], MediaPlayer.protocolVersion);

      await player.dispose();
    });

    test(
        'native PROTOCOL_VERSION_MISMATCH error is mapped to '
        'ProtocolMismatchException', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'initialize') {
          throw PlatformException(
            code: 'PROTOCOL_VERSION_MISMATCH',
            message: 'Dart package protocol v1 is older than required',
            details: {
              'nativeProtocolVersion': 2,
              'minSupportedDartProtocolVersion': 2,
              'dartProtocolVersion': 1,
            },
          );
        }
        return null;
      });

      final player = MediaPlayer(playerId: 'proto-native-rejects');

      await expectLater(
        player.initialize(),
        throwsA(
          isA<ProtocolMismatchException>()
              .having(
                  (e) => e.nativeProtocolVersion, 'nativeProtocolVersion', 2)
              .having((e) => e.dartProtocolVersion, 'dartProtocolVersion', 1),
        ),
      );
    });

    test(
        'native reporting a protocol version below minSupportedNativeProtocolVersion '
        'throws ProtocolMismatchException client-side', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'initialize') {
          // Simulates a native build too old for this Dart package, but
          // one that (hypothetically) still reports its own version.
          return {'protocolVersion': 0};
        }
        return null;
      });

      final player = MediaPlayer(playerId: 'proto-native-too-old');

      await expectLater(
        player.initialize(),
        throwsA(isA<ProtocolMismatchException>().having(
            (e) => e.nativeProtocolVersion, 'nativeProtocolVersion', 0)),
      );
    });

    test(
        'initialize() succeeds when native predates protocol negotiation '
        '(returns null, not a map)', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async => null);

      final player = MediaPlayer(playerId: 'proto-legacy-native');
      await player.initialize();
      expect(player.isInitialized, isTrue);

      await player.dispose();
    });

    test(
        'MissingPluginException from a method native does not implement is '
        'mapped to ProtocolMismatchException', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'initialize') {
          return {'protocolVersion': MediaPlayer.protocolVersion};
        }
        return null;
      });

      final player = MediaPlayer(playerId: 'proto-missing-method');
      await player.initialize();

      // Simulate a stale cached native build that doesn't implement 'play'
      // at all: no handler registered for the channel at this point makes
      // the test binding throw a raw MissingPluginException, exactly like
      // an unimplemented native method would.
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);

      await expectLater(
        player.play(),
        throwsA(
          isA<ProtocolMismatchException>()
              .having((e) => e.missingMethod, 'missingMethod', 'play'),
        ),
      );

      // dispose() swallows its own MissingPluginException (logged, not
      // thrown) — restoring a handler here just keeps teardown quiet.
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async => null);
      await player.dispose();
    });
  });
}
