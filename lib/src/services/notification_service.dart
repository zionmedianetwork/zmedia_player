import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../models/media_item.dart';
import '../models/notification_config.dart';
import '../models/player_state.dart';
import '../core/media_player.dart';

/// Service for managing media playback notifications
///
/// ## You MUST subscribe to [actionEventStream] (or the deprecated [actionStream])
///
/// This service only renders the lock-screen / Control Center notification and
/// forwards user taps as events on [actionEventStream] — it does **not** call
/// `play()`/`pause()`/`skipToNext()`/`seekTo()`/etc. on any controller itself. If you
/// call [show] without also listening to [actionEventStream] and routing each event to
/// your `MediaController`, the notification will render completely and correctly while
/// every button on it does nothing when tapped. There is no error or warning from
/// the notification itself in that case — the dead buttons are only apparent from
/// manual, on-device testing. See `docs/api-reference/advanced-features.md` for the
/// wiring example every integrator needs to copy.
///
/// [actionEventStream] emits [NotificationActionEvent], which carries the action
/// identifier plus, for [NotificationActions.seekTo] (dragging the lock-screen /
/// Control Center scrub bar), the absolute [NotificationActionEvent.position] the
/// user scrubbed to — something the older [actionStream] (`Stream<String>`) cannot
/// represent. **The host app is responsible for calling `seekTo(event.position)` on
/// its controller when it receives a `seekTo` event** — this service does not do it
/// for you, exactly as it does not call `play()`/`pause()` for you either.
///
/// ## Changing the configuration at runtime
///
/// The [NotificationConfig] passed to the constructor is applied to native at
/// [initialize] time. To change it afterwards — e.g. to start offering the
/// ±[NotificationConfig.seekInterval]s seek controls — call [updateConfig];
/// mutating or re-passing a [NotificationConfig] anywhere else has no effect,
/// and neither does [show], which renders from whatever config native already
/// holds.
class NotificationService {
  static const MethodChannel _channel = MethodChannel('zmedia_player');

  /// Not `final`: [updateConfig] replaces it at runtime. Internal state only —
  /// the config a caller hands in is still deeply immutable.
  NotificationConfig _config;
  final StreamController<String> _actionController =
      StreamController<String>.broadcast();
  final StreamController<NotificationActionEvent> _actionEventController =
      StreamController<NotificationActionEvent>.broadcast();

  bool _isShowing = false;
  MediaItem? _currentMedia;

  /// The most recent [PlaybackState] handed to [show]/[updateState]. Kept so
  /// [updateConfig] can re-render an already-visible notification without the
  /// caller having to supply the state again.
  PlaybackState? _lastState;

  /// `true` once [initialize] has been called at all — including a call that
  /// returned early because [NotificationConfig.enabled] was `false`, which
  /// sends nothing to native. [updateConfig] uses this to decide whether it may
  /// talk to native yet (see its dartdoc).
  bool _initializeCalled = false;
  MediaPlayer? _mediaPlayer;
  StreamSubscription<NotificationActionEvent>? _notificationActionSubscription;
  StreamSubscription<PlaybackState>? _stateSubscription;
  bool _actionStreamListenedTo = false;
  bool _debugNoListenerWarningLogged = false;

  NotificationService(this._config) {
    assert(() {
      // Debug-only: track whether anything ever subscribes to either action
      // stream so `show()` can warn once if a notification is displayed with
      // no listener attached (see class dartdoc). No-op in release builds.
      _actionController.onListen = () => _actionStreamListenedTo = true;
      _actionEventController.onListen = () => _actionStreamListenedTo = true;
      return true;
    }());
  }

  /// Stream of notification action events, typed as [NotificationActionEvent].
  ///
  /// You must listen to this and route each event's [NotificationActionEvent.action]
  /// (`"play"`, `"pause"`, `"next"`, `"previous"`, `"stop"`, `"seekForward"`,
  /// `"seekBackward"`, `"seekTo"`) to your `MediaController`/`MediaPlayer` — see the
  /// class-level dartdoc above. For `"seekTo"`, call
  /// `controller.seekTo(event.position!)` — that is the only action that carries a
  /// [NotificationActionEvent.position].
  Stream<NotificationActionEvent> get actionEventStream =>
      _actionEventController.stream;

  /// Stream of notification action identifiers only (no position).
  ///
  /// You must listen to this and route each action (`"play"`, `"pause"`,
  /// `"next"`, `"previous"`, `"stop"`, `"seekForward"`, `"seekBackward"`) to your
  /// `MediaController`/`MediaPlayer` — see the class-level dartdoc above.
  ///
  /// This stream cannot carry the position the lock-screen / Control Center scrub
  /// bar was dragged to for a `"seekTo"` action — it is emitted here with no
  /// position information, so a `"seekTo"` event is unactionable via this stream.
  /// Prefer [actionEventStream] for new code, which carries the position.
  @Deprecated(
    'Use actionEventStream instead, which carries NotificationActionEvent.position '
    'for "seekTo" — required to make lock-screen/Control Center scrub-bar seeking '
    'work. actionStream is kept for backward compatibility and still receives every '
    'action (including "seekTo", but with no position).',
  )
  Stream<String> get actionStream => _actionController.stream;

  /// Whether notification is currently showing
  bool get isShowing => _isShowing;

  /// The duration value to actually send to the native notification.
  ///
  /// The native side (`NotificationHandler.showNotification`/`updateState`
  /// on Android, the equivalent on iOS) only ever reads whatever is placed
  /// in the `'state'` map's `'duration'` key here — it never falls back to
  /// the media item's own declared duration on its own. [state]'s duration
  /// is the *live*, natively-tracked value (populated from the platform's
  /// `onDurationChanged` callback), which is reliably known for a player
  /// that has been actively playing/ticking, but can still be
  /// `Duration.zero` for a player that has spent most of its life as a
  /// non-owner: Android's position-update loop only calls
  /// `notifyPositionChanged` while `ExoPlayer.isPlaying` is true (see
  /// `MediaPlayerManager.kt`'s `startPositionUpdates`), so a
  /// paused/completed/rarely-playing player gets far fewer natural
  /// opportunities to (re)confirm its duration than a continuously-playing
  /// owner does.
  ///
  /// [declaredDuration] — the [MediaItem]'s own statically-declared
  /// `duration` — has no such dependency: it is known from the moment the
  /// item is loaded, regardless of native playback ticks. Falling back to
  /// it here, once, in the single place both [show] and [updateState] funnel
  /// through, closes that gap for both platforms without native changes:
  /// without this, a promoted (previously non-owner) player's notification
  /// can permanently lack a progress bar, since Android's MediaStyle
  /// notification requires `METADATA_KEY_DURATION > 0` to draw one at all.
  Duration _effectiveDuration(PlaybackState state, Duration? declaredDuration) {
    if (state.duration > Duration.zero) return state.duration;
    return declaredDuration ?? Duration.zero;
  }

  /// Initialize the notification service
  ///
  /// Sends the [NotificationConfig] this service was constructed with to
  /// native (`initializeNotification`), which is the **only** point at which
  /// the initial config crosses the MethodChannel. To change the config after
  /// this, call [updateConfig] — nothing else re-sends it, [show] included.
  ///
  /// Sends nothing at all when [NotificationConfig.enabled] is `false`; the
  /// service is still considered initialized in that case, so a later
  /// [updateConfig] that flips `enabled` back on can complete the native setup
  /// on its own without a second [initialize] call.
  Future<void> initialize(String playerId, {MediaPlayer? mediaPlayer}) async {
    _initializeCalled = true;

    // Kept so show() can read the live isSeekable/dvrEnabled state at the
    // moment it builds the 'mediaItem' payload (see show() below) — those
    // aren't parameters of show() itself. Recorded *before* the `enabled`
    // gate and before the channel call so that a service initialized while
    // disabled (or one whose native call failed) still has the player to wire
    // up if updateConfig later enables notifications.
    _mediaPlayer = mediaPlayer;

    if (!_config.enabled) return;

    try {
      await _sendConfigToNative(playerId);
      _wireMediaPlayer(playerId);

      debugPrint('NotificationService: Initialized successfully');
    } catch (e) {
      debugPrint('NotificationService: Failed to initialize: $e');
    }
  }

  /// Applies a new [NotificationConfig] at runtime.
  ///
  /// [NotificationConfig] is immutable and is only handed to native by
  /// [initialize]; [show] renders from whatever config native already holds and
  /// never re-sends one. This is therefore the only way to change notification
  /// behaviour (which action buttons are offered, [NotificationConfig.seekInterval],
  /// [NotificationConfig.showWhenPaused], ...) without constructing a whole new
  /// [NotificationService].
  ///
  /// What it does, in order:
  ///
  /// 1. **Disabling** (`enabled` goes `true` → `false`) dismisses a currently
  ///    showing notification *before* adopting the new config — every method on
  ///    this service, [dismiss] included, no-ops while disabled, so tearing it
  ///    down afterwards would be impossible.
  /// 2. **Stores** the config. It is used by every subsequent call
  ///    ([show]/[updateState]/[dismiss]) and by the next [initialize].
  /// 3. **Re-sends it to native** via the same `initializeNotification` channel
  ///    call [initialize] uses. Both platforms tolerate this: each rebuilds its
  ///    per-player notification handler from the payload and replaces the
  ///    registered one (`ZMediaPlayerPlugin.handleInitializeNotification` in
  ///    Kotlin and Swift alike). Nothing is sent when the new config is
  ///    disabled, matching [initialize].
  /// 4. **Re-renders**, but only if a notification was showing ([isShowing]):
  ///    the stored [MediaItem] and the most recent [PlaybackState] are replayed
  ///    through [show] so the new config is visible immediately, without the
  ///    caller calling [show] again. This matters beyond convenience on Android,
  ///    where the rebuilt handler has not posted anything yet and the tray still
  ///    holds the notification the *previous* handler posted with the old
  ///    config. If no notification was showing, nothing is displayed — this
  ///    never spuriously pops one up.
  ///
  /// Streams are never re-subscribed: the [MediaPlayer] wiring set up by
  /// [initialize] is reused as-is (and established here only if [initialize]
  /// skipped it because notifications were disabled at the time), so calling
  /// this repeatedly cannot duplicate action events or leak subscriptions.
  ///
  /// **Before [initialize]:** does not throw and does not touch the channel —
  /// the config is simply stored and becomes the one the next [initialize]
  /// sends. (Sending it here would create a native handler for a player that
  /// has no action/state wiring yet.)
  ///
  /// Failures are swallowed and logged, exactly as in [initialize] and [show];
  /// the new config is stored either way.
  Future<void> updateConfig(
    NotificationConfig config, {
    required String playerId,
  }) async {
    final wasShowing = _isShowing;

    // Step 1: dismiss while the *old* (enabled) config still permits it.
    if (_config.enabled && !config.enabled && wasShowing) {
      await dismiss(playerId);
    }

    // Step 2.
    _config = config;

    // Step 3.
    if (!config.enabled) return;
    if (!_initializeCalled) {
      debugPrint(
        'NotificationService: updateConfig called before initialize — config '
        'stored and will be sent by the next initialize() call',
      );
      return;
    }

    try {
      await _sendConfigToNative(playerId);
      // No-op when initialize() already wired things up; covers the case where
      // it could not because notifications were disabled at the time.
      _wireMediaPlayer(playerId);
    } catch (e) {
      debugPrint('NotificationService: Failed to update config: $e');
      return;
    }

    // Step 4.
    final media = _currentMedia;
    if (!wasShowing || media == null) return;

    final state = _lastState ?? _mediaPlayer?.currentState;
    if (state == null) return;

    await show(mediaItem: media, state: state, playerId: playerId);
  }

  /// The one place the config crosses the MethodChannel, shared by [initialize]
  /// and [updateConfig] so the payload can never drift between them.
  Future<void> _sendConfigToNative(String playerId) {
    return _channel.invokeMethod('initializeNotification', {
      'playerId': playerId,
      'config': _config.toMap(),
    });
  }

  /// Subscribes to the [MediaPlayer] recorded by [initialize], if any.
  ///
  /// Idempotent: returns immediately when the subscriptions already exist, so
  /// [updateConfig] can call it freely without duplicating action events or
  /// orphaning a subscription.
  void _wireMediaPlayer(String playerId) {
    final mediaPlayer = _mediaPlayer;
    if (mediaPlayer == null) return;
    if (_notificationActionSubscription != null || _stateSubscription != null) {
      return;
    }

    // Subscribe to notification actions from MediaPlayer if provided. The
    // typed event stream is the source of truth (it carries `position` for
    // "seekTo"); the deprecated string stream is derived from it so both
    // stay in sync and existing `actionStream` consumers keep working.
    _notificationActionSubscription =
        mediaPlayer.notificationActionEventStream.listen((event) {
      if (!_actionEventController.isClosed) {
        _actionEventController.add(event);
      }
      if (!_actionController.isClosed) {
        _actionController.add(event.action);
      }
    });

    // Keep the platform's Now Playing info (lock screen / Control Center)
    // in sync with real playback state. Without this the widget's
    // play/pause button stays frozen at the state captured by show(), so
    // its controls appear dead. updateState is a no-op while not showing.
    _stateSubscription = mediaPlayer.stateStream.listen((state) {
      updateState(state: state, playerId: playerId);
    });
  }

  /// Show or update notification
  Future<void> show({
    required MediaItem mediaItem,
    required PlaybackState state,
    required String playerId,
  }) async {
    if (!_config.enabled) return;

    _currentMedia = mediaItem;
    // Kept for updateConfig, which re-renders from the stored item + state.
    _lastState = state;

    assert(() {
      if (!_actionStreamListenedTo && !_debugNoListenerWarningLogged) {
        _debugNoListenerWarningLogged = true;
        debugPrint(
          'NotificationService: WARNING - showing a notification but nothing '
          'is listening to actionEventStream (or the deprecated actionStream). '
          'Lock-screen/Control Center buttons (play/pause/next/previous/'
          'seekTo/etc.) will appear but do nothing when tapped. Subscribe to '
          'actionEventStream and route each event to your MediaController — '
          'see docs/api-reference/advanced-features.md.',
        );
      }
      return true;
    }());

    // Don't show notification when paused if configured
    if (!_config.showWhenPaused && state.state == PlayerState.paused) {
      await dismiss(playerId);
      return;
    }

    try {
      final effectiveDuration = _effectiveDuration(state, mediaItem.duration);
      await _channel.invokeMethod('showNotification', {
        'playerId': playerId,
        'mediaItem': {
          'id': mediaItem.id,
          'title': mediaItem.title,
          'artist': mediaItem.artist,
          'album': mediaItem.album,
          'artworkUrl': mediaItem.artworkUrl,
          'url': mediaItem.url,
          'duration': mediaItem.duration?.inMilliseconds,
          // Lets native gate seeking (ACTION_SEEK_TO / METADATA_KEY_DURATION
          // on Android, changePlaybackPositionCommand / skipForward/Backward
          // / MPMediaItemPropertyPlaybackDuration on iOS) so the lock-screen/
          // notification surface never offers scrubbing on a live stream
          // that isn't actually seekable. `dvrEnabled` is read from the
          // MediaPlayer this service was initialized with (see
          // MediaPlayer.dvrEnabled), not from mediaItem itself, since DVR is
          // a playback-session concept rather than a static item property;
          // it is `false` when no MediaPlayer was supplied to [initialize].
          // Both are re-sent on every [updateState] call too (see below) —
          // this initial value is only what native has until the first state
          // update arrives.
          'isLive': _mediaPlayer?.isLive ?? mediaItem.isLive,
          'dvrEnabled': _mediaPlayer?.dvrEnabled ?? false,
        },
        'state': {
          'state': state.state.name,
          'position': state.position.inMilliseconds,
          'duration': effectiveDuration.inMilliseconds,
          'isPlaying': state.state == PlayerState.playing,
        },
      });

      _isShowing = true;
      debugPrint(
          'NotificationService: Notification shown for ${mediaItem.title}');
    } catch (e) {
      debugPrint('NotificationService: Failed to show notification: $e');
    }
  }

  /// Update notification with new state
  ///
  /// Also re-sends the current `isLive`/`dvrEnabled` seekability inputs on
  /// every call, not just from [show]. Native caches these values (to gate
  /// lock-screen/Control Center scrubbing — see the `'isLive'`/`'dvrEnabled'`
  /// comment in [show]), but unlike title/artist — which only change when the
  /// media *item* changes — `dvrEnabled` can change while the *same* item
  /// keeps playing (e.g. the host app calls `MediaPlayer.updateConfig` with a
  /// different `HlsConfig.enableDvr` and reloads). [show] alone is not
  /// re-invoked in that case, so without repeating these here native would
  /// keep gating on a stale value forever — see `NotificationHandler.kt`'s
  /// `updateState`/`NotificationHandler.swift`'s `updateState` on the
  /// receiving end, which re-derive `isSeekable` and re-apply gating from
  /// whatever is sent on *this* call.
  Future<void> updateState({
    required PlaybackState state,
    required String playerId,
  }) async {
    if (!_isShowing || !_config.enabled || _currentMedia == null) return;

    // Kept for updateConfig, which re-renders from the stored item + state.
    _lastState = state;

    // Hide notification if paused and configured to do so
    if (!_config.showWhenPaused && state.state == PlayerState.paused) {
      await dismiss(playerId);
      return;
    }

    try {
      final effectiveDuration =
          _effectiveDuration(state, _currentMedia?.duration);
      await _channel.invokeMethod('updateNotificationState', {
        'playerId': playerId,
        'state': {
          'state': state.state.name,
          'position': state.position.inMilliseconds,
          'duration': effectiveDuration.inMilliseconds,
          'isPlaying': state.state == PlayerState.playing,
          'isLive': _mediaPlayer?.isLive ?? _currentMedia?.isLive ?? false,
          'dvrEnabled': _mediaPlayer?.dvrEnabled ?? false,
        },
      });
    } catch (e) {
      debugPrint('NotificationService: Failed to update notification: $e');
    }
  }

  /// Update notification position
  Future<void> updatePosition({
    required Duration position,
    required String playerId,
  }) async {
    if (!_isShowing || !_config.enabled) return;

    try {
      await _channel.invokeMethod('updateNotificationPosition', {
        'playerId': playerId,
        'position': position.inMilliseconds,
      });
    } catch (e) {
      // Position updates can fail silently - not critical
      debugPrint('NotificationService: Failed to update position: $e');
    }
  }

  /// Dismiss notification
  Future<void> dismiss(String playerId) async {
    if (!_isShowing || !_config.enabled) return;

    try {
      await _channel.invokeMethod('dismissNotification', {
        'playerId': playerId,
      });

      _isShowing = false;
      debugPrint('NotificationService: Notification dismissed');
    } catch (e) {
      debugPrint('NotificationService: Failed to dismiss notification: $e');
    }
  }

  /// Dispose the service
  void dispose() {
    _notificationActionSubscription?.cancel();
    _notificationActionSubscription = null;
    _stateSubscription?.cancel();
    _stateSubscription = null;
    _mediaPlayer = null;
    _actionController.close();
    _actionEventController.close();
  }
}

/// Standard notification actions
class NotificationActions {
  static const String play = 'play';
  static const String pause = 'pause';
  static const String next = 'next';
  static const String previous = 'previous';
  static const String stop = 'stop';

  /// Relative seek forward, emitted when the user activates the notification's
  /// seek-forward button (Android) or `skipForwardCommand` (iOS) — see
  /// [NotificationConfig.showSeekForward].
  ///
  /// The wire value is `'seekForward'`, which is what both platforms have
  /// always emitted (`sendActionToFlutter("seekForward")` in
  /// `NotificationHandler.kt` / `NotificationHandler.swift`). This constant
  /// previously read `'seek_forward'`, a value neither platform ever sent, so
  /// any `case NotificationActions.seekForward:` branch was dead code.
  static const String seekForward = 'seekForward';

  /// Relative seek backward — see [seekForward] for the wire-value note and
  /// [NotificationConfig.showSeekBackward] for when it is offered.
  static const String seekBackward = 'seekBackward';

  /// Absolute seek requested via the lock-screen / Control Center scrub bar
  /// (`MPRemoteCommandCenter.changePlaybackPositionCommand` on iOS,
  /// `MediaSessionCompat.Callback.onSeekTo` on Android). Carries a
  /// [NotificationActionEvent.position] — see that class's dartdoc.
  static const String seekTo = 'seekTo';
}
