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

import 'package:flutter/foundation.dart';
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

    // -----------------------------------------------------------------------
    test(
        'show() falls back to the MediaItem\'s declared duration when the '
        'live PlaybackState duration is still zero (promoted-notification '
        'progress-bar fix)', () async {
      final calls = _installCapture();

      final player = MediaPlayer(playerId: 'notif-duration-fallback-show');
      await player.initialize();

      final service = NotificationService(const NotificationConfig());
      await service.initialize('notif-duration-fallback-show',
          mediaPlayer: player);

      // A MediaItem with a statically-declared duration, e.g. a fixture like
      // SampleMedia.bigBuckBunny (Duration(seconds: 10)).
      const itemWithDeclaredDuration = MediaItem(
        id: 'declared-duration-item',
        title: 'Has Declared Duration',
        url: 'https://example.com/video.mp4',
        duration: Duration(seconds: 10),
      );

      // The live PlaybackState's duration is still Duration.zero (default) —
      // simulating a non-owner player that never received a native
      // onDurationChanged tick.
      await service.show(
        mediaItem: itemWithDeclaredDuration,
        state: const PlaybackState(state: PlayerState.completed),
        playerId: 'notif-duration-fallback-show',
      );

      final showCall = calls.firstWhere(
        (c) => c.method == 'showNotification',
        orElse: () => fail('No showNotification call found'),
      );
      final stateArg = showCall.arguments['state'] as Map<dynamic, dynamic>;

      expect(
        stateArg['duration'],
        const Duration(seconds: 10).inMilliseconds,
        reason:
            'When the live state duration is unknown (zero), showNotification '
            'must fall back to the MediaItem\'s declared duration so '
            'METADATA_KEY_DURATION is never 0 for a media item whose total '
            'duration is actually known.',
      );

      service.dispose();
      await player.dispose();
    });

    // -----------------------------------------------------------------------
    test(
        'updateState() falls back to the currently-shown MediaItem\'s declared '
        'duration when the live PlaybackState duration is still zero',
        () async {
      final calls = _installCapture();

      final player = MediaPlayer(playerId: 'notif-duration-fallback-update');
      await player.initialize();

      final service = NotificationService(const NotificationConfig());
      await service.initialize('notif-duration-fallback-update',
          mediaPlayer: player);

      const itemWithDeclaredDuration = MediaItem(
        id: 'declared-duration-item-2',
        title: 'Has Declared Duration',
        url: 'https://example.com/video2.mp4',
        duration: Duration(seconds: 10),
      );

      await service.show(
        mediaItem: itemWithDeclaredDuration,
        state: const PlaybackState(state: PlayerState.paused),
        playerId: 'notif-duration-fallback-update',
      );

      calls.clear();

      await service.updateState(
        state: const PlaybackState(state: PlayerState.completed),
        playerId: 'notif-duration-fallback-update',
      );

      final updateCall = calls.firstWhere(
        (c) => c.method == 'updateNotificationState',
        orElse: () => fail('No updateNotificationState call found'),
      );
      final stateArg = updateCall.arguments['state'] as Map<dynamic, dynamic>;

      expect(
        stateArg['duration'],
        const Duration(seconds: 10).inMilliseconds,
        reason: 'updateState must also fall back to the declared MediaItem '
            'duration when the live PlaybackState duration is unknown, not '
            'just show().',
      );

      service.dispose();
      await player.dispose();
    });

    // -----------------------------------------------------------------------
    test(
        'a non-zero live PlaybackState duration always takes priority over '
        'the declared MediaItem duration', () async {
      final calls = _installCapture();

      final player = MediaPlayer(playerId: 'notif-duration-live-priority');
      await player.initialize();

      final service = NotificationService(const NotificationConfig());
      await service.initialize('notif-duration-live-priority',
          mediaPlayer: player);

      const itemWithDeclaredDuration = MediaItem(
        id: 'declared-duration-item-3',
        title: 'Has Declared Duration',
        url: 'https://example.com/video3.mp4',
        duration: Duration(seconds: 10),
      );

      await service.show(
        mediaItem: itemWithDeclaredDuration,
        state: const PlaybackState(
          state: PlayerState.playing,
          duration: Duration(milliseconds: 123456),
        ),
        playerId: 'notif-duration-live-priority',
      );

      final showCall = calls.firstWhere(
        (c) => c.method == 'showNotification',
        orElse: () => fail('No showNotification call found'),
      );
      final stateArg = showCall.arguments['state'] as Map<dynamic, dynamic>;

      expect(
        stateArg['duration'],
        123456,
        reason:
            'A known live duration must never be overridden by the declared '
            'MediaItem duration.',
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

  // =========================================================================
  group('NotificationService — debug-mode "no actionStream listener" warning',
      () {
    late DebugPrintCallback originalDebugPrint;
    late List<String> messages;

    setUp(() {
      originalDebugPrint = debugPrint;
      messages = <String>[];
      debugPrint = (String? message, {int? wrapWidth}) {
        if (message != null) messages.add(message);
      };
    });

    tearDown(() {
      debugPrint = originalDebugPrint;
    });

    // -----------------------------------------------------------------------
    test('show() logs a warning when nothing has ever listened to actionStream',
        () async {
      _installCapture();
      final player = MediaPlayer(playerId: 'notif-warn-no-listener');
      await player.initialize();

      final service = NotificationService(const NotificationConfig());
      await service.initialize('notif-warn-no-listener', mediaPlayer: player);

      await service.show(
        mediaItem: _dummyItem,
        state: const PlaybackState(state: PlayerState.playing),
        playerId: 'notif-warn-no-listener',
      );

      expect(
        messages.any(
          (m) => m.contains('actionStream') && m.contains('WARNING'),
        ),
        isTrue,
        reason: 'show() with no actionStream listener must log a debug '
            'warning explaining that notification buttons will be dead',
      );

      service.dispose();
      await player.dispose();
    });

    // -----------------------------------------------------------------------
    test('show() does NOT log the warning when actionStream has a listener',
        () async {
      _installCapture();
      final player = MediaPlayer(playerId: 'notif-warn-with-listener');
      await player.initialize();

      final service = NotificationService(const NotificationConfig());
      await service.initialize('notif-warn-with-listener', mediaPlayer: player);

      final sub = service.actionStream.listen((_) {});

      await service.show(
        mediaItem: _dummyItem,
        state: const PlaybackState(state: PlayerState.playing),
        playerId: 'notif-warn-with-listener',
      );

      expect(
        messages.any((m) => m.contains('actionStream')),
        isFalse,
        reason: 'No warning should be logged once a listener is attached',
      );

      await sub.cancel();
      service.dispose();
      await player.dispose();
    });

    // -----------------------------------------------------------------------
    test('the warning is only logged once across multiple show() calls',
        () async {
      _installCapture();
      final player = MediaPlayer(playerId: 'notif-warn-once');
      await player.initialize();

      final service = NotificationService(const NotificationConfig());
      await service.initialize('notif-warn-once', mediaPlayer: player);

      await service.show(
        mediaItem: _dummyItem,
        state: const PlaybackState(state: PlayerState.playing),
        playerId: 'notif-warn-once',
      );
      await service.show(
        mediaItem: _dummyItem,
        state: const PlaybackState(state: PlayerState.paused),
        playerId: 'notif-warn-once',
      );
      await service.show(
        mediaItem: _dummyItem,
        state: const PlaybackState(state: PlayerState.playing),
        playerId: 'notif-warn-once',
      );

      final warningCount = messages
          .where((m) => m.contains('actionStream') && m.contains('WARNING'))
          .length;

      expect(
        warningCount,
        1,
        reason: 'The no-listener warning must only be logged once, not on '
            'every show() call',
      );

      service.dispose();
      await player.dispose();
    });
  });

  // =========================================================================
  group(
      'NotificationService — show() carries isLive/dvrEnabled so native can '
      'gate seeking (Wave A: live-stream seek gating)', () {
    const liveItem = MediaItem(
      id: 'notif-live-item',
      title: 'Live Stream',
      url: 'https://example.com/live.m3u8',
      isLive: true,
    );

    // -----------------------------------------------------------------------
    test(
        'show() sends isLive: true and dvrEnabled: false for a live item '
        'with no MediaPlayer supplied to initialize()', () async {
      final calls = _installCapture();

      final player = MediaPlayer(playerId: 'notif-live-no-mp');
      await player.initialize();

      final service = NotificationService(const NotificationConfig());
      // No mediaPlayer passed to initialize() — dvrEnabled must default to
      // false rather than throw or omit the key.
      await service.initialize('notif-live-no-mp');

      await service.show(
        mediaItem: liveItem,
        state: const PlaybackState(state: PlayerState.playing),
        playerId: 'notif-live-no-mp',
      );

      final showCall = calls.firstWhere(
        (c) => c.method == 'showNotification',
        orElse: () => fail('No showNotification call found'),
      );
      final mediaItemArg =
          showCall.arguments['mediaItem'] as Map<dynamic, dynamic>;

      expect(mediaItemArg['isLive'], isTrue);
      expect(mediaItemArg['dvrEnabled'], isFalse);

      service.dispose();
      await player.dispose();
    });

    // -----------------------------------------------------------------------
    test(
        'show() sends dvrEnabled: false for a live item when the supplied '
        'MediaPlayer has DVR disabled (the default)', () async {
      final calls = _installCapture();

      final player = MediaPlayer(playerId: 'notif-live-no-dvr');
      await player.initialize();
      await player.load(liveItem);

      final service = NotificationService(const NotificationConfig());
      await service.initialize('notif-live-no-dvr', mediaPlayer: player);

      await service.show(
        mediaItem: liveItem,
        state: const PlaybackState(state: PlayerState.playing),
        playerId: 'notif-live-no-dvr',
      );

      final showCall = calls.firstWhere(
        (c) => c.method == 'showNotification',
        orElse: () => fail('No showNotification call found'),
      );
      final mediaItemArg =
          showCall.arguments['mediaItem'] as Map<dynamic, dynamic>;

      expect(mediaItemArg['isLive'], isTrue);
      expect(mediaItemArg['dvrEnabled'], isFalse);

      service.dispose();
      await player.dispose();
    });

    // -----------------------------------------------------------------------
    test(
        'show() sends dvrEnabled: true for a live item when the supplied '
        "MediaPlayer's dvrEnabled is true", () async {
      final calls = _installCapture();

      final player = MediaPlayer(
        playerId: 'notif-live-dvr',
        config: const MediaConfig(hlsConfig: HlsConfig(enableDvr: true)),
      );
      await player.initialize();
      await player.load(liveItem);

      final service = NotificationService(const NotificationConfig());
      await service.initialize('notif-live-dvr', mediaPlayer: player);

      await service.show(
        mediaItem: liveItem,
        state: const PlaybackState(state: PlayerState.playing),
        playerId: 'notif-live-dvr',
      );

      final showCall = calls.firstWhere(
        (c) => c.method == 'showNotification',
        orElse: () => fail('No showNotification call found'),
      );
      final mediaItemArg =
          showCall.arguments['mediaItem'] as Map<dynamic, dynamic>;

      expect(mediaItemArg['isLive'], isTrue);
      expect(mediaItemArg['dvrEnabled'], isTrue);

      service.dispose();
      await player.dispose();
    });

    // -----------------------------------------------------------------------
    test('show() sends isLive: false for ordinary VOD media', () async {
      final calls = _installCapture();

      final player = MediaPlayer(playerId: 'notif-vod-isLive');
      await player.initialize();

      final service = NotificationService(const NotificationConfig());
      await service.initialize('notif-vod-isLive', mediaPlayer: player);

      await service.show(
        mediaItem: _dummyItem,
        state: const PlaybackState(state: PlayerState.playing),
        playerId: 'notif-vod-isLive',
      );

      final showCall = calls.firstWhere(
        (c) => c.method == 'showNotification',
        orElse: () => fail('No showNotification call found'),
      );
      final mediaItemArg =
          showCall.arguments['mediaItem'] as Map<dynamic, dynamic>;

      expect(mediaItemArg['isLive'], isFalse);
      expect(mediaItemArg['dvrEnabled'], isFalse);

      service.dispose();
      await player.dispose();
    });
  });

  // =========================================================================
  group(
      'NotificationService — updateState() re-syncs isLive/dvrEnabled '
      '(regression: dvrEnabled going stale on the native side when toggled '
      'while the same item plays — see notification_service.dart updateState doc)',
      () {
    const liveItem = MediaItem(
      id: 'notif-live-toggle-item',
      title: 'Live Stream (toggle)',
      url: 'https://example.com/live-toggle.m3u8',
      isLive: true,
    );

    /// Returns the `'state'` map of the most recent `updateNotificationState`
    /// call, failing the test if there wasn't one.
    Map<dynamic, dynamic> latestUpdateStateArg(List<MethodCall> calls) {
      final updateCalls =
          calls.where((c) => c.method == 'updateNotificationState').toList();
      expect(updateCalls, isNotEmpty,
          reason: 'Expected at least one updateNotificationState call');
      return updateCalls.last.arguments['state'] as Map<dynamic, dynamic>;
    }

    // -----------------------------------------------------------------------
    test(
        'every updateNotificationState call carries isLive/dvrEnabled, not '
        'just the initial showNotification call', () async {
      final calls = _installCapture();

      final player = MediaPlayer(
        playerId: 'notif-updatestate-carries-dvr',
        config: const MediaConfig(hlsConfig: HlsConfig(enableDvr: true)),
      );
      await player.initialize();
      await player.load(liveItem);

      final service = NotificationService(const NotificationConfig());
      await service.initialize('notif-updatestate-carries-dvr',
          mediaPlayer: player);
      await service.show(
        mediaItem: liveItem,
        state: const PlaybackState(state: PlayerState.playing),
        playerId: 'notif-updatestate-carries-dvr',
      );

      calls.clear();

      await service.updateState(
        state: const PlaybackState(
          state: PlayerState.playing,
          position: Duration(seconds: 5),
        ),
        playerId: 'notif-updatestate-carries-dvr',
      );

      final stateArg = latestUpdateStateArg(calls);
      expect(stateArg['isLive'], isTrue);
      expect(stateArg['dvrEnabled'], isTrue);

      service.dispose();
      await player.dispose();
    });

    // -----------------------------------------------------------------------
    test(
        'toggling DVR on the same live item while it keeps playing '
        'propagates dvrEnabled to native in BOTH directions (off->on and '
        'on->off)', () async {
      final calls = _installCapture();
      const playerId = 'notif-dvr-toggle-both-directions';

      final player = MediaPlayer(
        playerId: playerId,
        config: const MediaConfig(hlsConfig: HlsConfig(enableDvr: false)),
      );
      await player.initialize();
      await player.load(liveItem);
      expect(player.dvrEnabled, isFalse);

      final service = NotificationService(const NotificationConfig());
      await service.initialize(playerId, mediaPlayer: player);
      await service.show(
        mediaItem: liveItem,
        state: const PlaybackState(state: PlayerState.playing),
        playerId: playerId,
      );

      // Sanity: showNotification reflects the initial (DVR off) state.
      final showCall = calls.firstWhere(
        (c) => c.method == 'showNotification',
        orElse: () => fail('No showNotification call found'),
      );
      expect(
        (showCall.arguments['mediaItem'] as Map)['dvrEnabled'],
        isFalse,
      );

      calls.clear();

      // --- Direction 1: DVR off -> on -------------------------------------
      // Mirrors how a host app actually flips this: MediaPlayer.updateConfig
      // with a new HlsConfig, then reload the (unchanged) MediaItem — see
      // MediaPlayer._applyStreamingConfigForLoad, which only re-derives
      // dvrEnabled on load().
      await player.updateConfig(
        player.config.copyWith(hlsConfig: const HlsConfig(enableDvr: true)),
      );
      await player.load(liveItem);
      // stateStream is a broadcast StreamController delivering
      // asynchronously; give its listener (NotificationService.updateState)
      // a microtask turn to run before inspecting captured channel calls.
      await Future<void>.delayed(Duration.zero);
      expect(player.dvrEnabled, isTrue);

      var stateArg = latestUpdateStateArg(calls);
      expect(
        stateArg['dvrEnabled'],
        isTrue,
        reason: 'Toggling DVR on and reloading the same item must '
            'propagate dvrEnabled: true to native via '
            'updateNotificationState, not just showNotification',
      );
      expect(stateArg['isLive'], isTrue);

      calls.clear();

      // --- Direction 2: DVR on -> off --------------------------------------
      await player.updateConfig(
        player.config.copyWith(hlsConfig: const HlsConfig(enableDvr: false)),
      );
      await player.load(liveItem);
      await Future<void>.delayed(Duration.zero);
      expect(player.dvrEnabled, isFalse);

      stateArg = latestUpdateStateArg(calls);
      expect(
        stateArg['dvrEnabled'],
        isFalse,
        reason: 'Toggling DVR back off and reloading the same item must '
            'propagate dvrEnabled: false to native via '
            'updateNotificationState',
      );

      service.dispose();
      await player.dispose();
    });
  });

  // =========================================================================
  group(
      'NotificationService — live DVR window duration (Wave E: '
      'HlsConfig.enableDvr granted seek permission with no seekable range — '
      'see MediaPlayerManager.kt/.swift notifyDurationChanged)', () {
    const liveItem = MediaItem(
      id: 'notif-live-dvr-duration-item',
      title: 'Live Stream (DVR window)',
      url: 'https://example.com/live-dvr-duration.m3u8',
      isLive: true,
      // A live item has no statically-declared duration — matches every
      // real live MediaItem. _effectiveDuration's declared-duration
      // fallback (see notification_service.dart) must NOT paper over a
      // missing live duration here; only a real onDurationChanged tick
      // (simulating the native DVR-window fix) may supply one.
    );

    // -----------------------------------------------------------------------
    test(
        'a native-reported DVR window duration (onDurationChanged) flows '
        'through show() as the notification duration, alongside isLive: '
        'true and dvrEnabled: true', () async {
      final calls = _installCapture();
      const playerId = 'notif-live-dvr-duration-show';
      final player = MediaPlayer(
        playerId: playerId,
        config: const MediaConfig(hlsConfig: HlsConfig(enableDvr: true)),
      );
      await player.initialize();
      await player.load(liveItem);
      expect(player.dvrEnabled, isTrue);
      expect(player.isSeekable, isTrue);

      // Simulates the fixed native layer (MediaPlayerManager.kt's
      // Timeline.Window-derived duration / MediaPlayerManager.swift's
      // seekableTimeRanges-derived duration) reporting the DVR window's
      // length — NOT the stream's total unbounded elapsed live duration —
      // once ExoPlayer/AVPlayer has resolved it.
      final durFuture = player.durationStream.first;
      await _injectEvent('onDurationChanged', {
        'playerId': playerId,
        'duration': 3600000, // 1-hour DVR window
        'isLive': true,
      });
      await durFuture.timeout(const Duration(seconds: 2));
      expect(player.currentState.duration, const Duration(hours: 1));

      calls.clear();
      final service = NotificationService(const NotificationConfig());
      await service.initialize(playerId, mediaPlayer: player);

      await service.show(
        mediaItem: liveItem,
        state: PlaybackState(
          state: PlayerState.playing,
          duration: player.currentState.duration,
        ),
        playerId: playerId,
      );

      final showCall = calls.firstWhere(
        (c) => c.method == 'showNotification',
        orElse: () => fail('No showNotification call found'),
      );
      final mediaItemArg =
          showCall.arguments['mediaItem'] as Map<dynamic, dynamic>;
      final stateArg = showCall.arguments['state'] as Map<dynamic, dynamic>;

      expect(mediaItemArg['isLive'], isTrue);
      expect(mediaItemArg['dvrEnabled'], isTrue,
          reason: 'Native derives isSeekable from isLive && dvrEnabled — '
              'both must accompany the duration so it is actually trusted '
              '(NotificationHandler.isSeekable) rather than just present');
      expect(
        stateArg['duration'],
        const Duration(hours: 1).inMilliseconds,
        reason: 'The DVR window length must reach native as the '
            "notification's duration so METADATA_KEY_DURATION / "
            'MPMediaItemPropertyPlaybackDuration has a real value to pair '
            'with the seek permission isSeekable already grants — a '
            'scrubber range, not just permission to scrub',
      );

      service.dispose();
      await player.dispose();
    });

    // -----------------------------------------------------------------------
    test(
        'a growing DVR window duration (repeated onDurationChanged ticks) '
        'reaches updateState on every tick, not just the first', () async {
      final calls = _installCapture();
      const playerId = 'notif-live-dvr-duration-growing';
      final player = MediaPlayer(
        playerId: playerId,
        config: const MediaConfig(hlsConfig: HlsConfig(enableDvr: true)),
      );
      await player.initialize();
      await player.load(liveItem);

      final service = NotificationService(const NotificationConfig());
      await service.initialize(playerId, mediaPlayer: player);
      await service.show(
        mediaItem: liveItem,
        state: const PlaybackState(state: PlayerState.playing),
        playerId: playerId,
      );

      calls.clear();

      // Early in playback the DVR window is still filling up — e.g. only
      // 30s of a target 1-hour window is available yet.
      var durFuture = player.durationStream.first;
      await _injectEvent('onDurationChanged', {
        'playerId': playerId,
        'duration': 30000,
        'isLive': true,
      });
      await durFuture.timeout(const Duration(seconds: 2));
      await service.updateState(
        state: PlaybackState(
          state: PlayerState.playing,
          duration: player.currentState.duration,
        ),
        playerId: playerId,
      );

      var updateCall = calls.lastWhere(
        (c) => c.method == 'updateNotificationState',
        orElse: () => fail('No updateNotificationState call found'),
      );
      expect(
        (updateCall.arguments['state'] as Map)['duration'],
        30000,
      );

      calls.clear();

      // The window has grown as more segments became available.
      durFuture = player.durationStream.first;
      await _injectEvent('onDurationChanged', {
        'playerId': playerId,
        'duration': 3600000,
        'isLive': true,
      });
      await durFuture.timeout(const Duration(seconds: 2));
      await service.updateState(
        state: PlaybackState(
          state: PlayerState.playing,
          duration: player.currentState.duration,
        ),
        playerId: playerId,
      );

      updateCall = calls.lastWhere(
        (c) => c.method == 'updateNotificationState',
        orElse: () => fail('No updateNotificationState call found'),
      );
      expect(
        (updateCall.arguments['state'] as Map)['duration'],
        3600000,
        reason: 'A later, larger DVR window duration must reach native on '
            'its own updateState tick — matching '
            "NotificationHandler.kt's/.swift's guard that only rejects a "
            'later value regressing TO zero/unknown, not one that grows',
      );

      service.dispose();
      await player.dispose();
    });

    // -----------------------------------------------------------------------
    test(
        'live stream without DVR never gets a duration from onDurationChanged '
        '(matches native withholding it), and dvrEnabled: false always '
        'accompanies whatever duration IS present so native still gates it',
        () async {
      final calls = _installCapture();
      const playerId = 'notif-live-no-dvr-duration';
      final player = MediaPlayer(playerId: playerId); // no HlsConfig: DVR off
      await player.initialize();
      await player.load(liveItem);
      expect(player.dvrEnabled, isFalse);
      expect(player.isSeekable, isFalse);

      // The fixed native layer never emits onDurationChanged for a live
      // item without DVR (see MediaPlayerManager.kt's notifyDurationChanged
      // doc: the `isLive && window.isSeekable && ... && currentDvrEnabled()`
      // branch is false, and the non-live branch does not apply either, so
      // durationMs stays 0 and the channel call is skipped entirely) — so
      // PlaybackState.duration legitimately stays Duration.zero here.
      expect(player.currentState.duration, Duration.zero);

      calls.clear();
      final service = NotificationService(const NotificationConfig());
      await service.initialize(playerId, mediaPlayer: player);

      await service.show(
        mediaItem: liveItem,
        state: PlaybackState(
          state: PlayerState.playing,
          duration: player.currentState.duration,
        ),
        playerId: playerId,
      );

      final showCall = calls.firstWhere(
        (c) => c.method == 'showNotification',
        orElse: () => fail('No showNotification call found'),
      );
      final mediaItemArg =
          showCall.arguments['mediaItem'] as Map<dynamic, dynamic>;
      final stateArg = showCall.arguments['state'] as Map<dynamic, dynamic>;

      expect(
        stateArg['duration'],
        0,
        reason: 'A live item without a statically-declared duration and '
            'without a real live duration tick must never have a duration '
            'invented for it by _effectiveDuration\'s declared-duration '
            'fallback',
      );
      expect(mediaItemArg['isLive'], isTrue);
      expect(
        mediaItemArg['dvrEnabled'],
        isFalse,
        reason: 'dvrEnabled: false must accompany the (zero) duration so '
            "NotificationHandler.isSeekable stays false and the "
            'notification never grows a scrubber even if some future '
            'caller starts sending a non-zero duration for this case',
      );

      service.dispose();
      await player.dispose();
    });
  });
}
