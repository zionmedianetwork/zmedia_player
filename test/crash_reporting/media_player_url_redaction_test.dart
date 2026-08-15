// M-09 regression coverage: the raw media URL — including its query string,
// where signed cookies/auth tokens for authenticated media URLs commonly
// live — was previously written verbatim into crash-reporter custom keys
// and error context (`media_player.dart`'s `load()`). Crash reports are
// frequently stored/transmitted by a third-party service outside this app's
// control, so the query string (and fragment) must be stripped before any
// URL reaches the crash reporter.

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zmedia_player/zmedia_player.dart';

const _secretUrl =
    'https://cdn.example.com/video.mp4?token=SUPER-SECRET-TOKEN&sig=abc123';
const _secretQueryFragment = 'SUPER-SECRET-TOKEN';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _RecordingCrashReporter reporter;

  setUp(() {
    reporter = _RecordingCrashReporter();
    MediaPlayer.enableCrashReporting(reporter);
  });

  tearDown(() {
    MediaPlayer.disableCrashReporting();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('zmedia_player'), null);
  });

  test(
      'successful load() never writes the query string to the crash '
      'reporter custom key', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('zmedia_player'),
      (MethodCall call) async => null,
    );

    final player = MediaPlayer(playerId: 'redact-success');
    await player.initialize();

    const item = MediaItem(
      id: 'secret-item',
      title: 'Secret',
      url: _secretUrl,
    );
    await player.load(item);

    final mediaUrl = reporter.customKeys['media_url'] as String?;
    expect(mediaUrl, isNotNull);
    expect(mediaUrl, isNot(contains(_secretQueryFragment)),
        reason: 'The token query param must never reach the crash reporter');
    expect(mediaUrl, isNot(contains('?')),
        reason: 'The query string must be stripped entirely');
    expect(mediaUrl, 'https://cdn.example.com/video.mp4');

    player.dispose();
  });

  test(
      'PlatformException during load() never writes the query string to '
      'the crash reporter error context', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('zmedia_player'),
      (MethodCall call) async {
        if (call.method == 'load') {
          throw PlatformException(code: 'LOAD_ERROR', message: 'boom');
        }
        return null;
      },
    );

    final player = MediaPlayer(playerId: 'redact-platform-error');
    await player.initialize();

    const item = MediaItem(
      id: 'secret-item-2',
      title: 'Secret',
      url: _secretUrl,
    );

    try {
      await player.load(item);
      fail('load() should have thrown');
    } catch (_) {
      // expected
    }

    expect(reporter.errors, isNotEmpty);
    final context = reporter.errors.last['context'] as Map?;
    final url = context?['url'] as String?;
    expect(url, isNotNull);
    expect(url, isNot(contains(_secretQueryFragment)));
    expect(url, isNot(contains('?')));

    player.dispose();
  });

  test(
      'a non-PlatformException failure during load() never writes the '
      'query string to the crash reporter error context', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('zmedia_player'),
      (MethodCall call) async {
        if (call.method == 'load') {
          throw StateError('unexpected native failure');
        }
        return null;
      },
    );

    final player = MediaPlayer(playerId: 'redact-generic-error');
    await player.initialize();

    const item = MediaItem(
      id: 'secret-item-3',
      title: 'Secret',
      url: _secretUrl,
    );

    try {
      await player.load(item);
      fail('load() should have thrown');
    } catch (_) {
      // expected
    }

    expect(reporter.errors, isNotEmpty);
    final context = reporter.errors.last['context'] as Map?;
    final url = context?['url'] as String?;
    expect(url, isNotNull);
    expect(url, isNot(contains(_secretQueryFragment)));
    expect(url, isNot(contains('?')));

    player.dispose();
  });
}

/// Minimal [CrashReporter] test double that records every call so tests can
/// assert on exactly what was sent.
class _RecordingCrashReporter implements CrashReporter {
  final List<Map<String, dynamic>> errors = [];
  final Map<String, dynamic> customKeys = {};

  @override
  void reportError(
    dynamic error,
    StackTrace? stackTrace, {
    Map<String, dynamic>? context,
    bool fatal = false,
  }) {
    errors.add({'error': error, 'context': context, 'fatal': fatal});
  }

  @override
  void log(String message, {Map<String, dynamic>? context}) {}

  @override
  void setUserIdentifier(String userId) {}

  @override
  void setCustomKey(String key, dynamic value) {
    customKeys[key] = value;
  }
}
