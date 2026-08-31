import 'package:flutter_test/flutter_test.dart';
import 'package:zmedia_player/zmedia_player.dart';

/// Regression coverage for `toMap()` handing out live references to the
/// model's own collection fields.
///
/// Before this fix, `toMap()` emitted `'headers': headers` (and friends)
/// verbatim, so the returned payload shared the *same* `Map`/`List` instance
/// the model held. A caller who mutated the result mutated the model, and two
/// `toMap()` calls handed out the same mutable inner collection.
///
/// Each field below is checked three ways:
///   1. mutating the collection inside the returned map does not change the
///      model's own field;
///   2. a second `toMap()` returns a collection that is not `identical` to
///      the first, and is unaffected by mutations to the first;
///   3. a `null` field still serializes as a present key with a `null` value
///      — the MethodChannel payload shape must not change.
void main() {
  group('DrmConfig.toMap defensive copies', () {
    test('mutating the returned headers does not touch the config', () {
      final config = DrmConfig(
        scheme: DrmScheme.widevine,
        licenseUrl: 'https://drm.example.com/license',
        headers: {'Authorization': 'Bearer token'},
      );

      final map = config.toMap();
      final headers = map['headers'] as Map<String, String>;

      expect(identical(headers, config.headers), isFalse);

      headers['X-Injected'] = 'nope';
      headers['Authorization'] = 'tampered';

      expect(config.headers, {'Authorization': 'Bearer token'});
      expect(config.headers!.containsKey('X-Injected'), isFalse);
    });

    test('two toMap calls do not share the same headers instance', () {
      final config = DrmConfig(
        scheme: DrmScheme.widevine,
        licenseUrl: 'https://drm.example.com/license',
        headers: {'Authorization': 'Bearer token'},
      );

      final first = config.toMap()['headers'] as Map<String, String>;
      final second = config.toMap()['headers'] as Map<String, String>;

      expect(identical(first, second), isFalse);

      first['X-Injected'] = 'nope';

      expect(second, {'Authorization': 'Bearer token'});
    });

    test('mutating the returned customData does not touch the config', () {
      final config = DrmConfig(
        scheme: DrmScheme.widevine,
        licenseUrl: 'https://drm.example.com/license',
        customData: {'sessionId': 'abc'},
      );

      final customData = config.toMap()['customData'] as Map<String, dynamic>;
      expect(identical(customData, config.customData), isFalse);

      customData['sessionId'] = 'tampered';

      expect(config.customData, {'sessionId': 'abc'});
    });

    test('null headers and customData stay present and null', () {
      final config = DrmConfig(
        scheme: DrmScheme.widevine,
        licenseUrl: 'https://drm.example.com/license',
      );

      final map = config.toMap();

      expect(map.containsKey('headers'), isTrue);
      expect(map['headers'], isNull);
      expect(map.containsKey('customData'), isTrue);
      expect(map['customData'], isNull);
    });

    test('the copy survives a fromMap round trip unchanged', () {
      final config = DrmConfig(
        scheme: DrmScheme.widevine,
        licenseUrl: 'https://drm.example.com/license',
        headers: {'Authorization': 'Bearer token'},
      );

      final map = config.toMap();
      (map['headers'] as Map<String, String>)['X-Injected'] = 'nope';

      final restored = DrmConfig.fromMap(config.toMap());
      expect(restored.headers, {'Authorization': 'Bearer token'});
    });
  });

  group('MediaItem.toMap defensive copies', () {
    MediaItem buildItem() => MediaItem(
          id: 'item-1',
          title: 'Test',
          url: 'https://example.com/video.mp4',
          httpHeaders: {'Cookie': 'signed=1'},
          metadata: {'season': 2},
        );

    test('mutating the returned httpHeaders does not touch the item', () {
      final item = buildItem();
      final headers = item.toMap()['httpHeaders'] as Map<String, String>;

      expect(identical(headers, item.httpHeaders), isFalse);

      headers['Cookie'] = 'tampered';
      headers['X-Injected'] = 'nope';

      expect(item.httpHeaders, {'Cookie': 'signed=1'});
    });

    test('mutating the returned metadata does not touch the item', () {
      final item = buildItem();
      final metadata = item.toMap()['metadata'] as Map<String, dynamic>;

      expect(identical(metadata, item.metadata), isFalse);

      metadata['season'] = 99;

      expect(item.metadata, {'season': 2});
    });

    test('two toMap calls do not share httpHeaders or metadata', () {
      final item = buildItem();

      final firstMap = item.toMap();
      final secondMap = item.toMap();

      expect(
        identical(firstMap['httpHeaders'], secondMap['httpHeaders']),
        isFalse,
      );
      expect(identical(firstMap['metadata'], secondMap['metadata']), isFalse);

      (firstMap['httpHeaders'] as Map<String, String>)['X-Injected'] = 'nope';
      (firstMap['metadata'] as Map<String, dynamic>)['season'] = 99;

      expect(secondMap['httpHeaders'], {'Cookie': 'signed=1'});
      expect(secondMap['metadata'], {'season': 2});
    });

    test('the nested drmConfig headers are copied too', () {
      final item = MediaItem(
        id: 'item-1',
        title: 'Test',
        url: 'https://example.com/video.mp4',
        drmConfig: DrmConfig(
          scheme: DrmScheme.widevine,
          licenseUrl: 'https://drm.example.com/license',
          headers: {'Authorization': 'Bearer token'},
        ),
      );

      final drmMap = item.toMap()['drmConfig'] as Map<String, dynamic>;
      final headers = drmMap['headers'] as Map<String, String>;

      expect(identical(headers, item.drmConfig!.headers), isFalse);

      headers['X-Injected'] = 'nope';

      expect(item.drmConfig!.headers, {'Authorization': 'Bearer token'});
    });

    test('null httpHeaders and metadata stay present and null', () {
      const item = MediaItem(
        id: 'item-1',
        title: 'Test',
        url: 'https://example.com/video.mp4',
      );

      final map = item.toMap();

      expect(map.containsKey('httpHeaders'), isTrue);
      expect(map['httpHeaders'], isNull);
      expect(map.containsKey('metadata'), isTrue);
      expect(map['metadata'], isNull);
    });
  });

  group('SubtitleTrack.toMap defensive copies', () {
    test('mutating the returned metadata does not touch the track', () {
      const track = SubtitleTrack(
        id: 'sub-1',
        title: 'English',
        metadata: {'forced': false},
      );

      final metadata = track.toMap()['metadata'] as Map<String, dynamic>;
      expect(identical(metadata, track.metadata), isFalse);

      metadata['forced'] = true;

      expect(track.metadata, {'forced': false});
    });

    test('null metadata stays present and null', () {
      const track = SubtitleTrack(id: 'sub-1', title: 'English');

      final map = track.toMap();

      expect(map.containsKey('metadata'), isTrue);
      expect(map['metadata'], isNull);
    });
  });

  group('CastDevice.toMap defensive copies', () {
    test('mutating the returned capabilities does not touch the device', () {
      final device = CastDevice(
        id: 'device-1',
        name: 'Living Room',
        type: CastDeviceType.chromecast,
        capabilities: ['video_out', 'audio_out'],
      );

      final capabilities = device.toMap()['capabilities'] as List<String>;
      expect(identical(capabilities, device.capabilities), isFalse);

      capabilities.add('injected');

      expect(device.capabilities, ['video_out', 'audio_out']);
    });

    test('an empty capabilities list still serializes as an empty list', () {
      const device = CastDevice(
        id: 'device-1',
        name: 'Living Room',
        type: CastDeviceType.chromecast,
      );

      final map = device.toMap();

      expect(map.containsKey('capabilities'), isTrue);
      expect(map['capabilities'], isEmpty);
    });
  });

  group('PerformanceMetrics.toMap defensive copies', () {
    test('mutating the returned context does not touch the metrics', () {
      final metrics = PerformanceMetrics(
        operation: 'load',
        duration: 42,
        timestamp: DateTime.utc(2026, 1, 1),
        context: {'playerId': 'p1'},
      );

      final context = metrics.toMap()['context'] as Map<String, dynamic>;
      expect(identical(context, metrics.context), isFalse);

      context['playerId'] = 'tampered';

      expect(metrics.context, {'playerId': 'p1'});
    });

    test('null context stays present and null', () {
      final metrics = PerformanceMetrics(
        operation: 'load',
        duration: 42,
        timestamp: DateTime.utc(2026, 1, 1),
      );

      final map = metrics.toMap();

      expect(map.containsKey('context'), isTrue);
      expect(map['context'], isNull);
    });
  });
}
