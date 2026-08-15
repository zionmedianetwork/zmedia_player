import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../models/media_item.dart';
import '../models/notification_config.dart';
import '../models/player_state.dart';
import '../core/media_player.dart';

/// Service for managing media playback notifications
///
/// ## You MUST subscribe to [actionStream]
///
/// This service only renders the lock-screen / Control Center notification and
/// forwards user taps as string events on [actionStream] — it does **not** call
/// `play()`/`pause()`/`skipToNext()`/etc. on any controller itself. If you call
/// [show] without also listening to [actionStream] and routing each action to your
/// `MediaController`, the notification will render completely and correctly while
/// every button on it does nothing when tapped. There is no error or warning from
/// the notification itself in that case — the dead buttons are only apparent from
/// manual, on-device testing. See `docs/api-reference/advanced-features.md` for the
/// wiring example every integrator needs to copy.
class NotificationService {
  static const MethodChannel _channel = MethodChannel('zmedia_player');

  final NotificationConfig _config;
  final StreamController<String> _actionController =
      StreamController<String>.broadcast();

  bool _isShowing = false;
  MediaItem? _currentMedia;
  StreamSubscription<String>? _notificationActionSubscription;
  StreamSubscription<PlaybackState>? _stateSubscription;
  bool _actionStreamListenedTo = false;
  bool _debugNoListenerWarningLogged = false;

  NotificationService(this._config) {
    assert(() {
      // Debug-only: track whether anything ever subscribes to actionStream so
      // `show()` can warn once if a notification is displayed with no listener
      // attached (see class dartdoc). No-op in release builds.
      _actionController.onListen = () => _actionStreamListenedTo = true;
      return true;
    }());
  }

  /// Stream of notification action events.
  ///
  /// You must listen to this and route each action (`"play"`, `"pause"`,
  /// `"next"`, `"previous"`, `"stop"`, `"seekForward"`, `"seekBackward"`) to your
  /// `MediaController`/`MediaPlayer` — see the class-level dartdoc above.
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
  Future<void> initialize(String playerId, {MediaPlayer? mediaPlayer}) async {
    if (!_config.enabled) return;

    try {
      await _channel.invokeMethod('initializeNotification', {
        'playerId': playerId,
        'config': _config.toMap(),
      });

      // Subscribe to notification actions from MediaPlayer if provided
      if (mediaPlayer != null) {
        _notificationActionSubscription =
            mediaPlayer.notificationActionStream.listen((action) {
          if (!_actionController.isClosed) {
            _actionController.add(action);
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

      debugPrint('NotificationService: Initialized successfully');
    } catch (e) {
      debugPrint('NotificationService: Failed to initialize: $e');
    }
  }

  /// Show or update notification
  Future<void> show({
    required MediaItem mediaItem,
    required PlaybackState state,
    required String playerId,
  }) async {
    if (!_config.enabled) return;

    _currentMedia = mediaItem;

    assert(() {
      if (!_actionStreamListenedTo && !_debugNoListenerWarningLogged) {
        _debugNoListenerWarningLogged = true;
        debugPrint(
          'NotificationService: WARNING - showing a notification but nothing '
          'is listening to actionStream. Lock-screen/Control Center buttons '
          '(play/pause/next/previous/etc.) will appear but do nothing when '
          'tapped. Subscribe to actionStream and route actions to your '
          'MediaController — see docs/api-reference/advanced-features.md.',
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
  Future<void> updateState({
    required PlaybackState state,
    required String playerId,
  }) async {
    if (!_isShowing || !_config.enabled || _currentMedia == null) return;

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
    _actionController.close();
  }
}

/// Standard notification actions
class NotificationActions {
  static const String play = 'play';
  static const String pause = 'pause';
  static const String next = 'next';
  static const String previous = 'previous';
  static const String stop = 'stop';
  static const String seekForward = 'seek_forward';
  static const String seekBackward = 'seek_backward';
}
