// Stage 7b (Phase 7) regression tests for [MediaPlayerPool] — the
// package-owned, fixed-capacity player pool that fixes F-01 (eviction must
// release a decoder session, not merely pause a controller nobody is
// watching) and F-02 (the package could not previously pool controllers by
// API shape — MediaListPlayer takes a host-owned MediaController).
//
// These tests exercise the pool entirely through its public surface,
// capturing outgoing MethodChannel calls the same way
// test/widgets/media_list_player_lifecycle_test.dart and
// media_list_player_pause_others_test.dart do, so assertions are made
// against what actually crosses the platform channel rather than against
// private state.

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zmedia_player/zmedia_player.dart';

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

void _resetHandler() {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_channel, null);
}

String? _playerIdOf(MethodCall call) =>
    (call.arguments as Map?)?['playerId'] as String?;

MediaItem _item(String id, {String url = 'https://cdn.example.com/v.mp4'}) =>
    MediaItem(id: id, title: id, url: url);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    // Warm up the static cleanup timer before any test runs, mirroring the
    // other MethodChannel-mocked test files in this suite.
    final calls = _installCapture();
    final warmup = MediaController.create(playerId: 'warmup-pool-static-timer');
    warmup.dispose();
    calls.clear();
    _resetHandler();
  });

  group('capacity and slot creation', () {
    test('acquire creates one slot per distinct key up to maxSize', () async {
      final calls = _installCapture();
      final pool = MediaPlayerPool(maxSize: 3);

      final a = await pool.acquire('a', _item('a'));
      final b = await pool.acquire('b', _item('b'));
      final c = await pool.acquire('c', _item('c'));

      expect(pool.liveCount, 3);
      expect(pool.isActive('a'), isTrue);
      expect(pool.isActive('b'), isTrue);
      expect(pool.isActive('c'), isTrue);
      expect(identical(a, b), isFalse);
      expect(identical(b, c), isFalse);
      expect(pool.freeCapacity, 0);

      await pool.releaseAll();
      calls.clear();
      _resetHandler();
    });

    test('re-acquiring the same key with the same item is a no-op', () async {
      final calls = _installCapture();
      final pool = MediaPlayerPool(maxSize: 2);

      final first = await pool.acquire('a', _item('a'));
      calls.clear();

      final second = await pool.acquire('a', _item('a'));

      expect(identical(first, second), isTrue);
      expect(
        calls,
        isEmpty,
        reason: 're-acquiring the same key/item pair (e.g. a visibility '
            'flicker) must not make any native calls',
      );

      await pool.releaseAll();
      _resetHandler();
    });

    test('acquiring the same key with a different item swaps the source',
        () async {
      final calls = _installCapture();
      final pool = MediaPlayerPool(maxSize: 2);

      final controller = await pool.acquire('a', _item('item-1'));
      calls.clear();

      final again = await pool.acquire('a', _item('item-2'));

      expect(identical(controller, again), isTrue);
      final loadCalls = calls.where((c) => c.method == 'load').toList();
      expect(loadCalls, hasLength(1));
      expect(
        (loadCalls.single.arguments as Map)['mediaItem']['id'],
        'item-2',
      );
      expect(
        calls.where((c) => c.method == 'initialize'),
        isEmpty,
        reason: 'swapping the source on an already-initialized slot must '
            'not re-initialize the underlying player',
      );

      await pool.releaseAll();
      _resetHandler();
    });
  });

  group('F-01 fix: eviction reassigns (swaps), never merely pauses', () {
    test(
        'acquiring beyond maxSize reassigns the least-recently-used slot to '
        'the new key, retaining the controller instance', () async {
      final calls = _installCapture();
      final pool = MediaPlayerPool(maxSize: 2);

      final controllerA = await pool.acquire('a', _item('a'));
      await pool.acquire('b', _item('b'));
      expect(pool.liveCount, 2);

      calls.clear();
      final controllerC = await pool.acquire('c', _item('c'));

      // 'a' was the least-recently-used of the two, so it is the one
      // reassigned to 'c'.
      expect(pool.liveCount, 2, reason: 'the cap must never be exceeded');
      expect(pool.isActive('a'), isFalse,
          reason: 'the evicted key must no longer map to any controller — '
              'its decoder session has been returned to the pool');
      expect(pool.isActive('b'), isTrue);
      expect(pool.isActive('c'), isTrue);
      expect(
        identical(controllerA, controllerC),
        isTrue,
        reason: 'eviction must retain and swap the existing controller '
            'instance rather than disposing it and constructing a new one '
            '(Stage 7a: load() has no already-loaded guard, so swapping is '
            'both cheaper and what actually returns the decoder session)',
      );

      final playerIdOfA = controllerA.playerId;
      expect(
        calls.any((c) => c.method == 'load' && _playerIdOf(c) == playerIdOfA),
        isTrue,
        reason: 'the reassigned slot must receive a fresh load() for the '
            'new item',
      );
      expect(
        calls.any((c) => c.method == 'pause'),
        isFalse,
        reason: 'F-01: eviction must never merely pause the evicted '
            'controller — that is exactly the defect this pool exists to '
            'fix (see MediaListPlayer._evictExcess, which does pause and '
            'is intentionally left unchanged for the host-owned-controller '
            'case)',
      );
      expect(
        calls
            .any((c) => c.method == 'dispose' && _playerIdOf(c) == playerIdOfA),
        isFalse,
        reason: 'eviction via reassignment must not dispose the retained '
            'controller either — only an explicit release()/dispose() of '
            'the whole pool does that (see the release-disposes group '
            'below)',
      );

      await pool.releaseAll();
      _resetHandler();
    });

    test('liveCount never exceeds maxSize across many sequential acquires',
        () async {
      final calls = _installCapture();
      final pool = MediaPlayerPool(maxSize: 2);

      for (var i = 0; i < 10; i++) {
        await pool.acquire('key-$i', _item('item-$i'));
        expect(pool.liveCount, lessThanOrEqualTo(2));
      }

      expect(pool.liveCount, 2);
      // Only the two most-recently-acquired keys should still be active.
      expect(pool.isActive('key-8'), isTrue);
      expect(pool.isActive('key-9'), isTrue);
      expect(pool.isActive('key-0'), isFalse);

      await pool.releaseAll();
      calls.clear();
      _resetHandler();
    });
  });

  group('explicit release actually disposes (hard release)', () {
    test('release() disposes the slot\'s controller and frees capacity',
        () async {
      final calls = _installCapture();
      final pool = MediaPlayerPool(maxSize: 1);

      final controller = await pool.acquire('a', _item('a'));
      final playerId = controller.playerId;
      calls.clear();

      await pool.release('a');

      expect(pool.isActive('a'), isFalse);
      expect(pool.liveCount, 0);
      expect(pool.freeCapacity, 1);
      expect(
        calls.any((c) => c.method == 'dispose' && _playerIdOf(c) == playerId),
        isTrue,
        reason: 'an explicit release must actually dispose the native '
            'player, returning its decoder session (Stage 7a confirmed '
            'dispose() genuinely returns the decoder count to zero, unlike '
            'pause())',
      );
      expect(controller.isDisposed, isTrue);

      _resetHandler();
    });

    test('releaseAll() disposes every live slot', () async {
      final calls = _installCapture();
      final pool = MediaPlayerPool(maxSize: 3);

      final a = await pool.acquire('a', _item('a'));
      final b = await pool.acquire('b', _item('b'));
      calls.clear();

      await pool.releaseAll();

      expect(pool.liveCount, 0);
      expect(a.isDisposed, isTrue);
      expect(b.isDisposed, isTrue);
      expect(
        calls.where((c) => c.method == 'dispose').length,
        2,
      );

      _resetHandler();
    });

    test('dispose() disposes every live slot and rejects further acquires',
        () async {
      final calls = _installCapture();
      final pool = MediaPlayerPool(maxSize: 2);

      final a = await pool.acquire('a', _item('a'));
      calls.clear();

      pool.dispose();

      expect(a.isDisposed, isTrue);
      expect(pool.isDisposed, isTrue);
      expect(pool.liveCount, 0);
      expect(
        calls.any((c) => c.method == 'dispose'),
        isTrue,
      );

      await expectLater(
        () => pool.acquire('b', _item('b')),
        throwsA(isA<StateError>()),
      );

      _resetHandler();
    });
  });

  group('composes with B-11 input validation and B-12 secureSurface', () {
    test(
        'acquire rejects a DRM item whose media URL is not HTTPS, before '
        'any native call', () async {
      final calls = _installCapture();
      final pool = MediaPlayerPool(maxSize: 1);

      final insecureDrmItem = MediaItem(
        id: 'insecure-drm',
        title: 'insecure-drm',
        url: 'http://cdn.example.com/video.mpd', // not https
        drmConfig: DrmConfig.widevine(
          licenseUrl: 'https://license.example.com/widevine',
        ),
      );

      await expectLater(
        () => pool.acquire('drm', insecureDrmItem),
        throwsA(isA<ConfigurationException>()),
      );

      expect(
        calls.any((c) => c.method == 'load'),
        isFalse,
        reason: 'B-11: the pool must not add an alternate load path that '
            'skips InputValidator — the same HTTPS-for-DRM rule enforced by '
            'MediaPlayer.load() must reject this insecure DRM item before '
            'it is ever sent to native as a "load" call (a preceding '
            '"initialize" call is expected and harmless — it carries no '
            'media URL)',
      );
      expect(pool.liveCount, 0,
          reason: 'a rejected acquire must not leave a live slot behind');

      await pool.releaseAll();
      _resetHandler();
    });

    test('per-item MediaConfig is applied when a fresh slot is created',
        () async {
      final calls = _installCapture();
      final pool = MediaPlayerPool(maxSize: 1);

      await pool.acquire(
        'secure',
        _item('secure'),
        config: const MediaConfig(secureSurface: true),
      );

      expect(
        calls.any((c) =>
            c.method == 'setSecureSurface' &&
            (c.arguments as Map)['enabled'] == true),
        isTrue,
        reason: 'B-12: a per-item MediaConfig with secureSurface: true must '
            'reach native the same way it would for any directly-created '
            'MediaController',
      );

      await pool.releaseAll();
      _resetHandler();
    });

    test('per-item MediaConfig is reapplied via updateConfig on a swap',
        () async {
      final calls = _installCapture();
      final pool = MediaPlayerPool(maxSize: 1);

      await pool.acquire('a', _item('a'));
      calls.clear();

      await pool.acquire(
        'a',
        _item('a-v2'),
        config: const MediaConfig(secureSurface: true),
      );

      expect(
        calls.any((c) => c.method == 'updateConfig'),
        isTrue,
        reason: 'a config override supplied alongside a source swap must be '
            'applied via updateConfig, mirroring what a host would do if it '
            'called updateConfig() itself before load()',
      );

      await pool.releaseAll();
      _resetHandler();
    });
  });

  group('touch()', () {
    test('touch marks a key most-recently-used without any native call',
        () async {
      final calls = _installCapture();
      final pool = MediaPlayerPool(maxSize: 2);

      await pool.acquire('a', _item('a'));
      await pool.acquire('b', _item('b'));
      calls.clear();

      // Without touch(), 'a' is the LRU key and would be evicted next.
      pool.touch('a');
      expect(calls, isEmpty);

      final controllerA = pool.controllerFor('a');
      await pool.acquire('c', _item('c'));

      expect(pool.isActive('a'), isTrue,
          reason: 'touch() must protect the touched key from the next '
              'eviction');
      expect(pool.isActive('b'), isFalse);
      expect(identical(pool.controllerFor('a'), controllerA), isTrue);

      await pool.releaseAll();
      _resetHandler();
    });
  });
}
