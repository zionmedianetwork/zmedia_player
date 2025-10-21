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

        // Simulate different error scenarios
        if (call.method == 'initialize') {
          return null; // Success
        }
        if (call.method == 'load') {
          final args = call.arguments as Map;
          final url = (args['mediaItem'] as Map)['url'] as String;

          if (url.contains('network-error')) {
            throw PlatformException(
              code: 'NETWORK_ERROR',
              message: 'Network connection failed',
            );
          }
          if (url.contains('drm-error')) {
            throw PlatformException(
              code: 'DRM_LICENSE_ERROR',
              message: 'License acquisition failed',
            );
          }
          if (url.contains('http-error')) {
            throw PlatformException(
              code: 'HTTP_ERROR',
              message: '404',
            );
          }
          return null;
        }
        if (call.method == 'play') {
          throw PlatformException(
            code: 'PLAYBACK_ERROR',
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

    test('Network error throws NetworkException', () async {
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

    test('DRM error throws DrmException', () async {
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

    test('HTTP error throws MediaLoadException', () async {
      final player = MediaPlayer();
      await player.initialize();

      final mediaItem = MediaItem(
        id: 'test-3',
        url: 'https://example.com/http-error.mp4',
        title: 'Not Found Video',
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
            code: 'PLAYBACK_ERROR',
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
}
