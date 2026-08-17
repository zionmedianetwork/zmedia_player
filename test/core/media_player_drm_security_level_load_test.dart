import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zmedia_player/zmedia_player.dart';

// ---------------------------------------------------------------------------
// Item 2 (gate item / B-12 wave 2): DrmConfig.minWidevineSecurityLevel is
// wired into MediaPlayer.load()'s existing validation pass
// (InputValidator.validateMediaItemWithDrm -> validateDrmConfig) so a
// misconfigured policy (set on a non-Widevine scheme) is rejected before
// ever reaching the MethodChannel — mirrors the existing "load with http://
// DRM URL throws before any load call" regression test in
// media_player_channel_test.dart.
// ---------------------------------------------------------------------------

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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null);
  });

  test(
      'load() throws ConfigurationException before sending "load" when '
      'minWidevineSecurityLevel is set on a non-widevine scheme', () async {
    final calls = _installCapture();
    final player = MediaPlayer(playerId: 'drm-seclevel-scope');
    await player.initialize();
    calls.clear();

    final item = MediaItem(
      id: 'fairplay-with-widevine-policy',
      title: 'Misconfigured',
      url: 'https://cdn.example.com/protected.m3u8',
      drmConfig: DrmConfig(
        scheme: DrmScheme.fairplay,
        licenseUrl: 'https://license.example.com/fairplay',
        certificateUrl: 'https://license.example.com/cert',
        // Meaningless on FairPlay — must be rejected before any channel call.
        minWidevineSecurityLevel: WidevineSecurityLevel.l1,
      ),
    );

    await expectLater(
      player.load(item),
      throwsA(isA<ConfigurationException>()),
    );

    expect(calls.where((c) => c.method == 'load'), isEmpty,
        reason: 'No "load" call must reach the channel when the '
            'minWidevineSecurityLevel/scheme combination is invalid');

    player.dispose();
  });

  test(
      'load() sends "load" with minWidevineSecurityLevel in the wire '
      'payload when the policy is set on DrmScheme.widevine', () async {
    final calls = _installCapture();
    final player = MediaPlayer(playerId: 'drm-seclevel-ok');
    await player.initialize();
    calls.clear();

    final item = MediaItem(
      id: 'widevine-with-policy',
      title: 'Protected',
      url: 'https://cdn.example.com/protected.mpd',
      drmConfig: DrmConfig.widevine(
        licenseUrl: 'https://license.example.com/widevine',
        minWidevineSecurityLevel: WidevineSecurityLevel.l1,
      ),
    );

    await player.load(item);

    final loadCall = calls.firstWhere((c) => c.method == 'load');
    final mediaItem = loadCall.arguments['mediaItem'] as Map;
    final drmConfig = mediaItem['drmConfig'] as Map;
    expect(drmConfig['minWidevineSecurityLevel'], 'L1',
        reason: 'the security-level policy must reach native code so '
            'DrmHandler.validateDrmConfig can enforce it (fail-closed)');

    player.dispose();
  });

  test('setPlaylist() also rejects an invalid minWidevineSecurityLevel scope',
      () async {
    final calls = _installCapture();
    final player = MediaPlayer(playerId: 'drm-seclevel-playlist');
    await player.initialize();
    calls.clear();

    final item = MediaItem(
      id: 'fairplay-with-widevine-policy-playlist',
      title: 'Misconfigured',
      url: 'https://cdn.example.com/protected.m3u8',
      drmConfig: DrmConfig(
        scheme: DrmScheme.fairplay,
        licenseUrl: 'https://license.example.com/fairplay',
        certificateUrl: 'https://license.example.com/cert',
        minWidevineSecurityLevel: WidevineSecurityLevel.l1,
      ),
    );
    final playlist = Playlist(
      id: 'seclevel-playlist',
      title: 'Playlist',
      items: [item],
    );

    await expectLater(
      player.setPlaylist(playlist),
      throwsA(isA<ConfigurationException>()),
    );
    expect(calls.where((c) => c.method == 'setPlaylist'), isEmpty);

    player.dispose();
  });
}
