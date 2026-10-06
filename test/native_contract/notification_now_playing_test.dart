import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Issues #148 / #149 drift guard (native has no automated tests, so the
/// sources are parsed as text, like `no_stale_reaper_test.dart`).
void main() {
  const androidPath =
      'android/src/main/kotlin/com/zionmedianetwork/zmedia_player/NotificationHandler.kt';
  const iosPath =
      'ios/zmedia_player/Sources/zmedia_player/NotificationHandler.swift';

  String code(String path) {
    final f = File(path);
    expect(f.existsSync(), isTrue, reason: 'missing $path');
    return f
        .readAsStringSync()
        .replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '')
        .replaceAll(RegExp(r'//.*'), '');
  }

  test('Android publishes album and a LIVE affordance', () {
    final src = code(androidPath);
    expect(src, contains('METADATA_KEY_ALBUM,'));
    expect(src, contains('METADATA_KEY_DISPLAY_DESCRIPTION'));
    expect(src, contains('setSubText('));
    expect(src, contains('"LIVE"'));
  });

  test('Android render key (#150) includes album, isLive and dvrEnabled', () {
    final src = code(androidPath);
    final m = RegExp(
      r'fun renderKey\(\).*?\)\n',
      dotAll: true,
    ).firstMatch(src.substring(src.indexOf('fun renderKey()')));
    expect(m, isNotNull);
    final body = m!.group(0)!;
    for (final k in ['currentAlbum', 'isLive', 'dvrEnabled']) {
      expect(body, contains(k), reason: 'renderKey must include $k');
    }
  });

  test('iOS marks live streams and omits elapsed time without DVR', () {
    final src = code(iosPath);
    expect(src, contains('MPNowPlayingInfoPropertyIsLiveStream'));
    final elapsed = src.indexOf(
      'nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime]',
    );
    final gate = src.lastIndexOf('if isSeekable', elapsed);
    expect(gate, greaterThan(0));
    expect(
      elapsed - gate,
      lessThan(200),
      reason: 'elapsed time must sit inside the isSeekable gate',
    );
  });
}
