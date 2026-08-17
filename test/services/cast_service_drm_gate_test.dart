import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zmedia_player/zmedia_player.dart';

/// Regression tests for M-07 / B-11 on the `CastService.loadMedia` path —
/// the service-layer duplicate of `MediaPlayer.loadMediaOnCastDevice`. Both
/// forward only id/title/url/artwork/duration to the cast receiver with no
/// DRM session at all, so both must independently refuse to cast
/// DRM-protected content, and both must validate the URL before handing it
/// to native. Crucially, both checks must happen *before* the method's own
/// broad try/catch (which otherwise swallows every failure via debugPrint)
/// so a refusal is never silently lost.
const _channel = MethodChannel('zmedia_player');

typedef _HandlerFn = Future<dynamic> Function(MethodCall);

List<MethodCall> _installCapture([_HandlerFn? extra]) {
  final calls = <MethodCall>[];
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_channel, (MethodCall call) async {
    calls.add(call);
    return extra != null ? await extra(call) : null;
  });
  return calls;
}

void _resetHandler() {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_channel, null);
}

/// Simulates the native side pushing an `onCastStatusChanged` event so the
/// backing [MediaPlayer] (and, through its `castStatusStream`, the
/// [CastService] under test) observes `isCasting: true` without needing a
/// real native cast handler.
Future<void> _injectCastStatus(
  String playerId, {
  required bool isCasting,
}) async {
  final codec = const StandardMethodCodec();
  final data = codec.encodeMethodCall(MethodCall('onCastStatusChanged', {
    'playerId': playerId,
    'state': isCasting ? 'casting' : 'disconnected',
    'isAvailable': true,
    'isCasting': isCasting,
  }));

  await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .handlePlatformMessage('zmedia_player', data, (ByteData? reply) {});
}

const _widevineConfig = DrmConfig(
  scheme: DrmScheme.widevine,
  licenseUrl: 'https://license.example.com/widevine',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(_resetHandler);

  test(
      'CastService.loadMedia throws ConfigurationException and never calls '
      'native for a DRM-protected item', () async {
    final calls = _installCapture();
    const playerId = 'cast-service-drm-gate';
    final player = MediaPlayer(playerId: playerId);
    await player.initialize();

    final castService = CastService(const CastConfig(enabled: true));
    await castService.initialize(playerId, player);

    await _injectCastStatus(playerId, isCasting: true);
    // Let the castStatusStream subscription deliver the event.
    await Future<void>.delayed(Duration.zero);
    expect(castService.isCasting, isTrue,
        reason: 'Test setup: CastService must observe isCasting=true');

    calls.clear();

    final drmItem = MediaItem(
      id: 'cast-drm-item',
      title: 'Protected',
      url: 'https://cdn.example.com/protected.mpd',
      drmConfig: _widevineConfig,
    );

    await expectLater(
      () => castService.loadMedia(mediaItem: drmItem, playerId: playerId),
      throwsA(isA<ConfigurationException>()),
    );

    expect(
      calls.where((c) => c.method == 'loadMediaOnCastDevice'),
      isEmpty,
      reason: 'DRM-protected content must never reach the cast channel',
    );

    castService.dispose();
    player.dispose();
  });

  test(
      'CastService.loadMedia throws ConfigurationException and never calls '
      'native for an invalid URL', () async {
    final calls = _installCapture();
    const playerId = 'cast-service-bad-url';
    final player = MediaPlayer(playerId: playerId);
    await player.initialize();

    final castService = CastService(const CastConfig(enabled: true));
    await castService.initialize(playerId, player);

    await _injectCastStatus(playerId, isCasting: true);
    await Future<void>.delayed(Duration.zero);
    expect(castService.isCasting, isTrue);

    calls.clear();

    const badItem = MediaItem(
      id: 'cast-bad-url-item',
      title: 'Bad URL',
      url: 'not-a-url',
    );

    await expectLater(
      () => castService.loadMedia(mediaItem: badItem, playerId: playerId),
      throwsA(isA<ConfigurationException>()),
    );

    expect(calls.where((c) => c.method == 'loadMediaOnCastDevice'), isEmpty);

    castService.dispose();
    player.dispose();
  });

  test(
      'CastService.loadMedia throws ConfigurationException and never calls '
      'native for a file:// (local) URL (C-02 Stage 1)', () async {
    final calls = _installCapture();
    const playerId = 'cast-service-local-file';
    final player = MediaPlayer(playerId: playerId);
    await player.initialize();

    final castService = CastService(const CastConfig(enabled: true));
    await castService.initialize(playerId, player);

    await _injectCastStatus(playerId, isCasting: true);
    await Future<void>.delayed(Duration.zero);
    expect(castService.isCasting, isTrue);

    calls.clear();

    final localItem = MediaItem(
      id: 'cast-local-item',
      title: 'Local file',
      url: LocalMediaUtils.fileUri('/data/user/0/app/files/clip.mp4'),
    );

    await expectLater(
      () => castService.loadMedia(mediaItem: localItem, playerId: playerId),
      throwsA(isA<ConfigurationException>()),
    );

    expect(
      calls.where((c) => c.method == 'loadMediaOnCastDevice'),
      isEmpty,
      reason: 'A local file:// URL must never reach a cast receiver',
    );

    castService.dispose();
    player.dispose();
  });
}
