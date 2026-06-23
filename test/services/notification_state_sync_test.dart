// Regression tests for the NotificationService Now Playing state-sync fix.
//
// Before the fix, NotificationService.initialize() did not subscribe to the
// player's stateStream, so the platform's lock-screen / Control-Center
// play/pause button became frozen at the state captured by show().
//
// After the fix, initialize(playerId, mediaPlayer: mp) sets up a
// StreamSubscription on mp.stateStream that calls updateState() whenever the
// playback state changes. updateState() in turn issues an
// 'updateNotificationState' MethodChannel call (guarded by _isShowing so it
// is a no-op when the notification is hidden).
//
// dispose() must cancel that subscription so no more channel calls are made.
//
// Harness: same pattern as media_player_channel_test.dart and
// media_player_events_test.dart — TestWidgetsFlutterBinding +
// TestDefaultBinaryMessengerBinding.setMockMethodCallHandler to capture
// outgoing calls + handlePlatformMessage with StandardMethodCodec to inject
// native events that advance the player's internal state.

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zmedia_player/zmedia_player.dart';

// ---------------------------------------------------------------------------
// Helpers
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

void _resetHandler() {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_channel, null);
}

Future<void> _injectEvent(String method, Map<String, dynamic> arguments) async {
  final codec = const StandardMethodCodec();
  final data = codec.encodeMethodCall(MethodCall(method, arguments));
  await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .handlePlatformMessage('zmedia_player', data, (_) {});
}

/// Injects an onStateChanged event for [playerId].
Future<void> _injectState(String playerId, String state) => _injectEvent(
      'onStateChanged',
      {
        'playerId': playerId,
        'state': state,
        'isBuffering': false,
        'bufferPercentage': 0.0,
      },
    );

/// A minimal media item used for show().
const _dummyItem = MediaItem(
  id: 'notif-item-1',
  title: 'Test Track',
  url: 'https://example.com/track.mp4',
);

/// A media item with no artworkUrl — used to verify thumbnail-generation path.
const _dummyItemNoArtwork = MediaItem(
  id: 'notif-item-no-artwork',
  title: 'Test Track No Artwork',
  url: 'https://example.com/video.mp4',
);

/// A media item that carries both a url and an artworkUrl.
const _dummyItemWithArtwork = MediaItem(
  id: 'notif-item-with-artwork',
  title: 'Test Track With Artwork',
  url: 'https://example.com/video2.mp4',
  artworkUrl: 'https://example.com/thumb.jpg',
);

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(_resetHandler);

  // =========================================================================
  group(
      'NotificationService — state sync via stateStream subscription (Fix: Now Playing sync)',
      () {
    // -----------------------------------------------------------------------
    test(
        'after initialize(mediaPlayer:) + show(), a playing state event triggers updateNotificationState',
        () async {
      final calls = _installCapture();

      final player = MediaPlayer(playerId: 'notif-sync-play');
      await player.initialize();

      final service = NotificationService(const NotificationConfig());
      await service.initialize('notif-sync-play', mediaPlayer: player);

      // show() sets _isShowing = true, which gates updateState calls.
      await service.show(
        mediaItem: _dummyItem,
        state: const PlaybackState(state: PlayerState.paused),
        playerId: 'notif-sync-play',
      );

      calls.clear(); // ignore all setup calls so far

      // Inject a 'playing' state event into the player.
      await _injectState('notif-sync-play', 'playing');

      // Give the stateStream listener a microtask turn.
      await Future<void>.delayed(Duration.zero);

      // Assert: updateNotificationState must have been called.
      final updateCalls =
          calls.where((c) => c.method == 'updateNotificationState').toList();

      expect(
        updateCalls,
        isNotEmpty,
        reason:
            'A playing state change while notification is showing must trigger '
            'an updateNotificationState channel call',
      );

      final stateArg =
          (updateCalls.first.arguments['state'] as Map<dynamic, dynamic>);
      expect(
        stateArg['isPlaying'],
        isTrue,
        reason:
            'updateNotificationState must set isPlaying=true when player is playing',
      );
      expect(
        updateCalls.first.arguments['playerId'],
        'notif-sync-play',
        reason: 'updateNotificationState must carry the correct playerId',
      );

      service.dispose();
      await player.dispose();
    });

    // -----------------------------------------------------------------------
    test(
        'paused state event triggers updateNotificationState with isPlaying=false',
        () async {
      final calls = _installCapture();

      final player = MediaPlayer(playerId: 'notif-sync-pause');
      await player.initialize();

      final service = NotificationService(
        const NotificationConfig(showWhenPaused: true),
      );
      await service.initialize('notif-sync-pause', mediaPlayer: player);

      await service.show(
        mediaItem: _dummyItem,
        state: const PlaybackState(state: PlayerState.playing),
        playerId: 'notif-sync-pause',
      );

      calls.clear();

      await _injectState('notif-sync-pause', 'paused');
      await Future<void>.delayed(Duration.zero);

      final updateCalls =
          calls.where((c) => c.method == 'updateNotificationState').toList();

      expect(
        updateCalls,
        isNotEmpty,
        reason: 'A paused state change must trigger updateNotificationState '
            '(showWhenPaused=true)',
      );

      final stateArg =
          (updateCalls.first.arguments['state'] as Map<dynamic, dynamic>);
      expect(
        stateArg['isPlaying'],
        isFalse,
        reason:
            'updateNotificationState must set isPlaying=false when player is paused',
      );

      service.dispose();
      await player.dispose();
    });

    // -----------------------------------------------------------------------
    test(
        'state events before show() do NOT trigger updateNotificationState (_isShowing guard)',
        () async {
      final calls = _installCapture();

      final player = MediaPlayer(playerId: 'notif-sync-no-show');
      await player.initialize();

      final service = NotificationService(const NotificationConfig());
      // Initialize with mediaPlayer but do NOT call show() — _isShowing is false.
      await service.initialize('notif-sync-no-show', mediaPlayer: player);

      calls.clear();

      // Inject a state change.
      await _injectState('notif-sync-no-show', 'playing');
      await Future<void>.delayed(Duration.zero);

      final updateCalls =
          calls.where((c) => c.method == 'updateNotificationState').toList();

      expect(
        updateCalls,
        isEmpty,
        reason: 'updateNotificationState must be gated by _isShowing=true; '
            'no call expected before show() has been called',
      );

      service.dispose();
      await player.dispose();
    });

    // -----------------------------------------------------------------------
    test(
        'dispose() cancels the stateStream subscription: no updateNotificationState after dispose',
        () async {
      final calls = _installCapture();

      final player = MediaPlayer(playerId: 'notif-sync-dispose');
      await player.initialize();

      final service = NotificationService(const NotificationConfig());
      await service.initialize('notif-sync-dispose', mediaPlayer: player);

      await service.show(
        mediaItem: _dummyItem,
        state: const PlaybackState(state: PlayerState.paused),
        playerId: 'notif-sync-dispose',
      );

      calls.clear();

      // Dispose the service (cancels subscription).
      service.dispose();

      // Now inject a state event — should be ignored.
      await _injectState('notif-sync-dispose', 'playing');
      await Future<void>.delayed(Duration.zero);

      final updateCalls =
          calls.where((c) => c.method == 'updateNotificationState').toList();

      expect(
        updateCalls,
        isEmpty,
        reason:
            'After dispose(), the stateStream subscription must be cancelled '
            'so no updateNotificationState calls occur',
      );

      await player.dispose();
    });

    // -----------------------------------------------------------------------
    test(
        'multiple state events after show() each produce an updateNotificationState call',
        () async {
      final calls = _installCapture();

      final player = MediaPlayer(playerId: 'notif-sync-multi');
      await player.initialize();

      final service = NotificationService(
        const NotificationConfig(showWhenPaused: true),
      );
      await service.initialize('notif-sync-multi', mediaPlayer: player);

      await service.show(
        mediaItem: _dummyItem,
        state: const PlaybackState(state: PlayerState.paused),
        playerId: 'notif-sync-multi',
      );

      calls.clear();

      // Three state changes in sequence.
      await _injectState('notif-sync-multi', 'playing');
      await Future<void>.delayed(Duration.zero);
      await _injectState('notif-sync-multi', 'paused');
      await Future<void>.delayed(Duration.zero);
      await _injectState('notif-sync-multi', 'playing');
      await Future<void>.delayed(Duration.zero);

      final updateCalls =
          calls.where((c) => c.method == 'updateNotificationState').toList();

      expect(
        updateCalls.length,
        greaterThanOrEqualTo(3),
        reason:
            'Each state change while showing must trigger an updateNotificationState call',
      );

      service.dispose();
      await player.dispose();
    });

    // -----------------------------------------------------------------------
    test(
        'initialize without mediaPlayer does not throw and service works normally',
        () async {
      final calls = _installCapture();

      final player = MediaPlayer(playerId: 'notif-no-mp');
      await player.initialize();

      final service = NotificationService(const NotificationConfig());
      // No mediaPlayer provided — should still not throw.
      await service.initialize('notif-no-mp');

      await service.show(
        mediaItem: _dummyItem,
        state: const PlaybackState(state: PlayerState.playing),
        playerId: 'notif-no-mp',
      );

      calls.clear();

      // No subscription exists, so injecting a state event should be a no-op
      // for the service (player state still updates internally but no sync).
      await _injectState('notif-no-mp', 'paused');
      await Future<void>.delayed(Duration.zero);

      final updateCalls =
          calls.where((c) => c.method == 'updateNotificationState').toList();

      expect(
        updateCalls,
        isEmpty,
        reason: 'Without a mediaPlayer, no stateStream subscription exists so '
            'no updateNotificationState calls should occur',
      );

      service.dispose();
      await player.dispose();
    });

    // -----------------------------------------------------------------------
    test('state sync sends the correct playerId, position, and duration fields',
        () async {
      final calls = _installCapture();

      final player = MediaPlayer(playerId: 'notif-sync-fields');
      await player.initialize();

      // Inject a duration so currentState.duration is non-zero.
      // Subscribe BEFORE injecting to avoid missing the broadcast emission.
      final durFuture = player.durationStream.first;
      await _injectEvent('onDurationChanged', {
        'playerId': 'notif-sync-fields',
        'duration': 180000, // 3 minutes
      });
      await durFuture.timeout(const Duration(seconds: 2));

      final service = NotificationService(const NotificationConfig());
      await service.initialize('notif-sync-fields', mediaPlayer: player);

      await service.show(
        mediaItem: _dummyItem,
        state: const PlaybackState(state: PlayerState.paused),
        playerId: 'notif-sync-fields',
      );

      calls.clear();

      await _injectState('notif-sync-fields', 'playing');
      await Future<void>.delayed(Duration.zero);

      final updateCall = calls.firstWhere(
        (c) => c.method == 'updateNotificationState',
        orElse: () => fail('No updateNotificationState call found'),
      );

      expect(
        updateCall.arguments['playerId'],
        'notif-sync-fields',
        reason: 'updateNotificationState must include the playerId',
      );

      final stateArg = updateCall.arguments['state'] as Map<dynamic, dynamic>;
      // The 'state' string, position, and isPlaying fields must be present.
      expect(stateArg.containsKey('state'), isTrue);
      expect(stateArg.containsKey('position'), isTrue);
      expect(stateArg.containsKey('duration'), isTrue);
      expect(stateArg.containsKey('isPlaying'), isTrue);
      expect(
        stateArg['state'],
        'playing',
        reason: 'state field must reflect the current player state name',
      );

      service.dispose();
      await player.dispose();
    });
  });

  // =========================================================================
  group(
      'NotificationService — showNotification includes url (Fix: thumbnail generation)',
      () {
    // -----------------------------------------------------------------------
    test('show() sends url in the mediaItem map when artworkUrl is absent',
        () async {
      final calls = _installCapture();

      final player = MediaPlayer(playerId: 'notif-url-no-artwork');
      await player.initialize();

      final service = NotificationService(const NotificationConfig());
      await service.initialize('notif-url-no-artwork', mediaPlayer: player);

      await service.show(
        mediaItem: _dummyItemNoArtwork,
        state: const PlaybackState(state: PlayerState.playing),
        playerId: 'notif-url-no-artwork',
      );

      final showCall = calls.firstWhere(
        (c) => c.method == 'showNotification',
        orElse: () => fail('No showNotification call found'),
      );

      final mediaItemArg =
          showCall.arguments['mediaItem'] as Map<dynamic, dynamic>;

      expect(
        mediaItemArg.containsKey('url'),
        isTrue,
        reason:
            'showNotification mediaItem must include url so native can generate '
            'a thumbnail when artworkUrl is absent',
      );
      expect(
        mediaItemArg['url'],
        _dummyItemNoArtwork.url,
        reason: 'url in mediaItem must equal MediaItem.url',
      );
      expect(
        mediaItemArg['artworkUrl'],
        isNull,
        reason: 'artworkUrl must be null for this test item',
      );

      service.dispose();
      await player.dispose();
    });

    // -----------------------------------------------------------------------
    test('show() sends both url and artworkUrl when artworkUrl is present',
        () async {
      final calls = _installCapture();

      final player = MediaPlayer(playerId: 'notif-url-with-artwork');
      await player.initialize();

      final service = NotificationService(const NotificationConfig());
      await service.initialize('notif-url-with-artwork', mediaPlayer: player);

      await service.show(
        mediaItem: _dummyItemWithArtwork,
        state: const PlaybackState(state: PlayerState.playing),
        playerId: 'notif-url-with-artwork',
      );

      final showCall = calls.firstWhere(
        (c) => c.method == 'showNotification',
        orElse: () => fail('No showNotification call found'),
      );

      final mediaItemArg =
          showCall.arguments['mediaItem'] as Map<dynamic, dynamic>;

      expect(
        mediaItemArg['url'],
        _dummyItemWithArtwork.url,
        reason: 'url must be present even when artworkUrl is set',
      );
      expect(
        mediaItemArg['artworkUrl'],
        _dummyItemWithArtwork.artworkUrl,
        reason: 'artworkUrl must also be passed so native can prefer it',
      );

      service.dispose();
      await player.dispose();
    });

    // -----------------------------------------------------------------------
    test(
        'show() always includes the title, artworkUrl, and url keys in mediaItem',
        () async {
      final calls = _installCapture();

      final player = MediaPlayer(playerId: 'notif-url-keys');
      await player.initialize();

      final service = NotificationService(const NotificationConfig());
      await service.initialize('notif-url-keys', mediaPlayer: player);

      await service.show(
        mediaItem: _dummyItem,
        state: const PlaybackState(state: PlayerState.playing),
        playerId: 'notif-url-keys',
      );

      final showCall = calls.firstWhere(
        (c) => c.method == 'showNotification',
        orElse: () => fail('No showNotification call found'),
      );

      final mediaItemArg =
          showCall.arguments['mediaItem'] as Map<dynamic, dynamic>;

      for (final key in ['title', 'artworkUrl', 'url']) {
        expect(
          mediaItemArg.containsKey(key),
          isTrue,
          reason: 'mediaItem map must always contain the "$key" key',
        );
      }

      expect(
        mediaItemArg['url'],
        _dummyItem.url,
        reason: 'url value must match the MediaItem.url field',
      );

      service.dispose();
      await player.dispose();
    });
  });
}
