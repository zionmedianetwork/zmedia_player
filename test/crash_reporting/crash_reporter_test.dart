import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zmedia_player/zmedia_player.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Crash Reporter Interface Tests', () {
    test('✅ ConsoleOnlyCrashReporter implements all methods', () {
      final reporter = ConsoleOnlyCrashReporter();

      // Should not throw
      reporter.reportError('Test error', StackTrace.current);
      reporter.reportError('Fatal error', StackTrace.current, fatal: true);
      reporter.reportError('Error with context', StackTrace.current, context: {
        'key1': 'value1',
        'key2': 123,
      });

      reporter.log('Test log');
      reporter.log('Log with context', context: {'data': 'test'});

      reporter.setUserIdentifier('user123');
      reporter.setCustomKey('testKey', 'testValue');
      reporter.setCustomKey('numericKey', 42);

      // If we get here without errors, test passes
    });

    test('✅ NoOpCrashReporter does nothing', () {
      const reporter = NoOpCrashReporter();

      // All methods should execute without throwing
      reporter.reportError('Test error', StackTrace.current);
      reporter.log('Test log');
      reporter.setUserIdentifier('user123');
      reporter.setCustomKey('key', 'value');
    });

    test('✅ Multiple crash reporters can coexist', () {
      final consoleReporter = ConsoleOnlyCrashReporter();
      const noOpReporter = NoOpCrashReporter();

      consoleReporter.log('Console log');
      noOpReporter.log('NoOp log');

      // Both should work independently
    });
  });

  group('MediaPlayer Crash Reporting Integration', () {
    late MockCrashReporter mockReporter;

    setUp(() {
      mockReporter = MockCrashReporter();
      MediaPlayer.enableCrashReporting(mockReporter);

      // Mock platform channel
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('zmedia_player'),
        (MethodCall methodCall) async {
          switch (methodCall.method) {
            case 'initialize':
              return null;
            case 'load':
              // Simulate successful load
              return null;
            case 'play':
              return null;
            case 'pause':
              return null;
            default:
              return null;
          }
        },
      );
    });

    tearDown(() {
      MediaPlayer.disableCrashReporting();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(const MethodChannel('zmedia_player'), null);
    });

    test('✅ Crash reporter is enabled via static method', () {
      expect(MediaPlayer.crashReporter, equals(mockReporter));
      expect(mockReporter.logs.length, greaterThan(0));
      expect(mockReporter.logs.last, contains('enabled'));
    });

    test('✅ Crash reporter can be disabled', () {
      MediaPlayer.disableCrashReporting();
      expect(MediaPlayer.crashReporter, isNull);
    });

    test('✅ Successful operations are logged', () async {
      mockReporter.clear();

      final controller = MediaController.create(playerId: 'success_test');
      await controller.initialize();

      // Should log initialization
      expect(
          mockReporter.logs.any((log) => log.contains('Initializing')), true);
      expect(
          mockReporter.logs
              .any((log) => log.contains('initialized successfully')),
          true);

      controller.dispose();
    });

    test('✅ Media load is logged with context', () async {
      mockReporter.clear();

      final controller = MediaController.create(playerId: 'load_test');
      await controller.initialize();

      final mediaItem = MediaItem(
        id: 'test_media',
        title: 'Test Video',
        url: 'https://example.com/video.mp4',
      );

      await controller.load(mediaItem);

      // Should set custom keys
      expect(mockReporter.customKeys['media_id'], 'test_media');
      expect(mockReporter.customKeys['media_url'],
          'https://example.com/video.mp4');
      expect(mockReporter.customKeys['drm_enabled'], false);

      // Should log success
      expect(
          mockReporter.logs.any((log) => log.contains('loaded successfully')),
          true);

      controller.dispose();
    });

    test('✅ Play/pause operations are logged', () async {
      mockReporter.clear();

      final controller = MediaController.create(playerId: 'playback_test');
      await controller.initialize();

      await controller.play();
      expect(mockReporter.logs.any((log) => log.contains('Playback started')),
          true);

      await controller.pause();
      expect(mockReporter.logs.any((log) => log.contains('Playback paused')),
          true);

      controller.dispose();
    });

    test('✅ User identifier can be set', () {
      mockReporter.clear();

      mockReporter.setUserIdentifier('user_12345');

      expect(mockReporter.userId, 'user_12345');
    });

    test('✅ Custom keys are tracked', () {
      mockReporter.clear();

      mockReporter.setCustomKey('app_version', '1.0.0');
      mockReporter.setCustomKey('user_tier', 'premium');
      mockReporter.setCustomKey('player_count', 3);

      expect(mockReporter.customKeys['app_version'], '1.0.0');
      expect(mockReporter.customKeys['user_tier'], 'premium');
      expect(mockReporter.customKeys['player_count'], 3);
    });
  });

  group('Error Capture Tests', () {
    late MockCrashReporter mockReporter;

    setUp(() {
      mockReporter = MockCrashReporter();
      MediaPlayer.enableCrashReporting(mockReporter);

      // Mock platform channel that sometimes fails
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('zmedia_player'),
        (MethodCall methodCall) async {
          if (methodCall.method == 'initialize') {
            return null;
          }
          if (methodCall.method == 'load') {
            throw PlatformException(
              code: 'LOAD_ERROR',
              message: 'Failed to load media',
            );
          }
          if (methodCall.method == 'play') {
            throw PlatformException(
              code: 'PLAYBACK_ERROR',
              message: 'Failed to start playback',
            );
          }
          return null;
        },
      );
    });

    tearDown(() {
      MediaPlayer.disableCrashReporting();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(const MethodChannel('zmedia_player'), null);
    });

    test('✅ Errors are captured and reported', () async {
      mockReporter.clear();

      final controller = MediaController.create(playerId: 'error_test');
      await controller.initialize();

      final mediaItem = MediaItem(
        id: 'error_media',
        title: 'Error Video',
        url: 'https://example.com/error.mp4',
      );

      try {
        await controller.load(mediaItem);
      } catch (e) {
        // Expected to fail
      }

      // Error should be reported
      expect(mockReporter.errors.length, greaterThan(0));

      final lastError = mockReporter.errors.last;
      expect(lastError['error'], isA<PlatformException>());
      expect(lastError['context']?['operation'], 'load');
      expect(lastError['context']?['playerId'], 'error_test');

      controller.dispose();
    });

    test('✅ Playback errors are captured with context', () async {
      mockReporter.clear();

      final controller =
          MediaController.create(playerId: 'playback_error_test');
      await controller.initialize();

      try {
        await controller.play();
      } catch (e) {
        // Expected to fail
      }

      // Error should be reported
      expect(mockReporter.errors.length, greaterThan(0));

      final lastError = mockReporter.errors.last;
      expect(lastError['context']?['operation'], 'play');
      expect(lastError['context']?['playerId'], 'playback_error_test');

      controller.dispose();
    });

    test('✅ Errors contain context information', () async {
      mockReporter.clear();

      final controller = MediaController.create(playerId: 'context_test');
      await controller.initialize();

      final mediaItem = MediaItem(
        id: 'context_media',
        title: 'Context Test',
        url: 'https://example.com/test.mp4',
      );

      try {
        await controller.load(mediaItem);
      } catch (e) {
        // Expected to fail
      }

      // Verify error has rich context
      expect(mockReporter.errors.length, greaterThan(0));

      final error = mockReporter.errors.last;
      expect(error['context'], isNotNull);
      expect(error['context']?['operation'], 'load');
      expect(error['context']?['playerId'], 'context_test');
      expect(error['context']?['mediaId'], 'context_media');

      controller.dispose();
    });
  });

  group('Crash Reporter Lifecycle Tests', () {
    test('✅ Can swap crash reporters', () {
      final reporter1 = MockCrashReporter();
      final reporter2 = MockCrashReporter();

      MediaPlayer.enableCrashReporting(reporter1);
      expect(MediaPlayer.crashReporter, equals(reporter1));

      MediaPlayer.enableCrashReporting(reporter2);
      expect(MediaPlayer.crashReporter, equals(reporter2));

      MediaPlayer.disableCrashReporting();
      expect(MediaPlayer.crashReporter, isNull);
    });

    test('✅ Operations work without crash reporter', () async {
      MediaPlayer.disableCrashReporting();

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('zmedia_player'),
        (MethodCall methodCall) async => null,
      );

      final controller = MediaController.create(playerId: 'no_reporter_test');
      await controller.initialize();
      await controller.play();
      await controller.pause();

      // Should work fine without crash reporter
      controller.dispose();

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(const MethodChannel('zmedia_player'), null);
    });
  });
}

/// Mock crash reporter for testing
class MockCrashReporter implements CrashReporter {
  final List<Map<String, dynamic>> errors = [];
  final List<String> logs = [];
  final Map<String, dynamic> customKeys = {};
  String? userId;

  void clear() {
    errors.clear();
    logs.clear();
    customKeys.clear();
    userId = null;
  }

  @override
  void reportError(
    dynamic error,
    StackTrace? stackTrace, {
    Map<String, dynamic>? context,
    bool fatal = false,
  }) {
    errors.add({
      'error': error,
      'stackTrace': stackTrace,
      'context': context,
      'fatal': fatal,
      'timestamp': DateTime.now(),
    });
  }

  @override
  void log(String message, {Map<String, dynamic>? context}) {
    logs.add(message);
  }

  @override
  void setUserIdentifier(String userId) {
    this.userId = userId;
  }

  @override
  void setCustomKey(String key, dynamic value) {
    customKeys[key] = value;
  }
}
