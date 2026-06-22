import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zmedia_player/zmedia_player.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Injects a native→Dart event through the test messenger.
Future<void> _injectEvent(String method, Map<String, dynamic> arguments) async {
  final codec = const StandardMethodCodec();
  final data = codec.encodeMethodCall(MethodCall(method, arguments));
  await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .handlePlatformMessage('zmedia_player', data, (_) {});
}

const _items = [
  MediaItem(
    id: 'item-1',
    title: 'Track 1',
    url: 'https://example.com/track1.mp4',
  ),
  MediaItem(
    id: 'item-2',
    title: 'Track 2',
    url: 'https://example.com/track2.mp4',
  ),
  MediaItem(
    id: 'item-3',
    title: 'Track 3',
    url: 'https://example.com/track3.mp4',
  ),
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
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

  // =========================================================================
  // Playlist model boundary / navigation tests
  // (No channel needed — pure Dart logic.)
  // =========================================================================

  group('Playlist — skipToNext/skipToPrevious boundary via MediaPlayer', () {
    test('skipToNext advances from first to second item', () async {
      final player = MediaPlayer(playerId: 'pl-skip-fwd-1');
      await player.initialize();

      final playlist = Playlist(
        id: 'pl-1',
        title: 'Test Playlist',
        items: _items,
        currentIndex: 0,
      );
      await player.setPlaylist(playlist);

      await player.skipToNext();

      expect(player.currentPlaylist?.currentIndex, 1);
      expect(player.currentItem?.id, 'item-2');

      player.dispose();
    });

    test('skipToPrevious goes from second to first item', () async {
      final player = MediaPlayer(playerId: 'pl-skip-bwd-1');
      await player.initialize();

      final playlist = Playlist(
        id: 'pl-2',
        title: 'Test Playlist',
        items: _items,
        currentIndex: 1,
      );
      await player.setPlaylist(playlist);

      await player.skipToPrevious();

      expect(player.currentPlaylist?.currentIndex, 0);
      expect(player.currentItem?.id, 'item-1');

      player.dispose();
    });

    test('skipToNext at last item throws InvalidStateException', () async {
      final player = MediaPlayer(playerId: 'pl-skip-fwd-last');
      await player.initialize();

      final playlist = Playlist(
        id: 'pl-3',
        title: 'Test Playlist',
        items: _items,
        currentIndex: 2, // last item
        repeatMode: MediaRepeatMode.none,
      );
      await player.setPlaylist(playlist);

      await expectLater(
        player.skipToNext(),
        throwsA(isA<InvalidStateException>()),
        reason: 'skipToNext at last item with MediaRepeatMode.none must throw',
      );

      player.dispose();
    });

    test('skipToPrevious at first item throws InvalidStateException', () async {
      final player = MediaPlayer(playerId: 'pl-skip-bwd-first');
      await player.initialize();

      final playlist = Playlist(
        id: 'pl-4',
        title: 'Test Playlist',
        items: _items,
        currentIndex: 0,
        repeatMode: MediaRepeatMode.none,
      );
      await player.setPlaylist(playlist);

      await expectLater(
        player.skipToPrevious(),
        throwsA(isA<InvalidStateException>()),
        reason: 'skipToPrevious at first item must throw',
      );

      player.dispose();
    });

    test('skipToNext wraps around when MediaRepeatMode.all', () async {
      final player = MediaPlayer(playerId: 'pl-skip-wrap');
      await player.initialize();

      final playlist = Playlist(
        id: 'pl-5',
        title: 'Test Playlist',
        items: _items,
        currentIndex: 2, // last item
        repeatMode: MediaRepeatMode.all,
      );
      await player.setPlaylist(playlist);

      await player.skipToNext();

      expect(player.currentPlaylist?.currentIndex, 0,
          reason: 'MediaRepeatMode.all must wrap to index 0');

      player.dispose();
    });

    test('skipToIndex jumps to arbitrary index', () async {
      final player = MediaPlayer(playerId: 'pl-skip-idx');
      await player.initialize();

      final playlist = Playlist(
        id: 'pl-6',
        title: 'Test Playlist',
        items: _items,
        currentIndex: 0,
      );
      await player.setPlaylist(playlist);

      await player.skipToIndex(2);

      expect(player.currentPlaylist?.currentIndex, 2);
      expect(player.currentItem?.id, 'item-3');

      player.dispose();
    });

    test('skipToIndex with out-of-bounds index throws ConfigurationException',
        () async {
      final player = MediaPlayer(playerId: 'pl-skip-oob');
      await player.initialize();

      final playlist = Playlist(
        id: 'pl-7',
        title: 'Test Playlist',
        items: _items,
        currentIndex: 0,
      );
      await player.setPlaylist(playlist);

      await expectLater(
        player.skipToIndex(99),
        throwsA(isA<ConfigurationException>()),
      );

      player.dispose();
    });

    test('skipToNext/Previous without playlist throws InvalidStateException',
        () async {
      final player = MediaPlayer(playerId: 'pl-skip-no-pl');
      await player.initialize();

      await expectLater(
        player.skipToNext(),
        throwsA(isA<InvalidStateException>()),
      );
      await expectLater(
        player.skipToPrevious(),
        throwsA(isA<InvalidStateException>()),
      );

      player.dispose();
    });
  });

  // =========================================================================
  // Auto-advance on completion: inject onStateChanged 'completed' and verify
  // that the stream reports it (the actual skip is triggered by the UI layer;
  // MediaPlayer itself just exposes the completed state).
  // =========================================================================

  group('Playlist — auto-advance on completion (stream-based)', () {
    test(
        'onStateChanged "completed" is delivered via stateStream when playlist is set',
        () async {
      final player = MediaPlayer(playerId: 'pl-autocomplete-1');
      await player.initialize();

      final playlist = Playlist(
        id: 'pl-auto-1',
        title: 'Auto Advance',
        items: _items,
        currentIndex: 0,
      );
      await player.setPlaylist(playlist);

      final stateFuture = player.stateStream
          .firstWhere((s) => s.state == PlayerState.completed);

      await _injectEvent('onStateChanged', {
        'playerId': 'pl-autocomplete-1',
        'state': 'completed',
        'isBuffering': false,
        'bufferPercentage': 100.0,
      });

      final state = await stateFuture.timeout(const Duration(seconds: 2));
      expect(state.state, PlayerState.completed,
          reason: 'completed event must be delivered when playlist is active');

      player.dispose();
    });

    test('setPlaylist rejects empty playlist', () async {
      final player = MediaPlayer(playerId: 'pl-empty');
      await player.initialize();

      final emptyPlaylist = Playlist(
        id: 'pl-empty-1',
        title: 'Empty',
        items: [],
      );

      await expectLater(
        player.setPlaylist(emptyPlaylist),
        throwsA(isA<ConfigurationException>()),
        reason: 'Empty playlist must be rejected',
      );

      player.dispose();
    });

    test('hasNext/hasPrevious reflect playlist state after skipToIndex',
        () async {
      final player = MediaPlayer(playerId: 'pl-nav-state');
      await player.initialize();

      final playlist = Playlist(
        id: 'pl-nav',
        title: 'Nav Test',
        items: _items,
        currentIndex: 0,
      );
      await player.setPlaylist(playlist);

      // At index 0: hasPrevious = false, hasNext = true
      expect(player.currentPlaylist?.hasPrevious, isFalse);
      expect(player.currentPlaylist?.hasNext, isTrue);

      await player.skipToIndex(2);

      // At last index: hasNext = false (MediaRepeatMode.none)
      expect(player.currentPlaylist?.hasNext, isFalse);
      expect(player.currentPlaylist?.hasPrevious, isTrue);

      player.dispose();
    });
  });

  // =========================================================================
  // Playlist model pure-Dart logic (no channel)
  // =========================================================================

  group('Playlist model — edge cases not covered in playlist_test.dart', () {
    test('MediaRepeatMode.single repeats current item indefinitely', () {
      const playlist = Playlist(
        id: 'pl-single',
        title: 'Single Repeat',
        items: _items,
        currentIndex: 1,
        repeatMode: MediaRepeatMode.single,
      );

      // nextIndex should return the same index.
      expect(playlist.nextIndex, 1,
          reason: 'MediaRepeatMode.single must return the same index on next');
    });

    test('MediaRepeatMode.all wraps previous at first item back to last', () {
      const playlist = Playlist(
        id: 'pl-all-bwd',
        title: 'All Repeat Backwards',
        items: _items,
        currentIndex: 0,
        repeatMode: MediaRepeatMode.all,
      );

      // MediaRepeatMode.all at index 0 going backwards → last index
      expect(playlist.hasPrevious, isTrue);
      expect(playlist.previousIndex, _items.length - 1,
          reason:
              'MediaRepeatMode.all must wrap previousIndex to last when at first item');
    });

    test('currentItem returns correct item at each index', () {
      for (var i = 0; i < _items.length; i++) {
        final playlist = Playlist(
          id: 'pl-ci-$i',
          title: 'CI',
          items: _items,
          currentIndex: i,
        );
        expect(playlist.currentItem?.id, _items[i].id);
      }
    });
  });
}
