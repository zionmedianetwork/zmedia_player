import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../models/media_item.dart';
import '../models/notification_config.dart';
import '../models/player_state.dart';
import '../core/media_player.dart';

/// Service for managing media playback notifications
class NotificationService {
  static const MethodChannel _channel = MethodChannel('zmedia_player');

  final NotificationConfig _config;
  final StreamController<String> _actionController =
      StreamController<String>.broadcast();

  bool _isShowing = false;
  MediaItem? _currentMedia;
  StreamSubscription<String>? _notificationActionSubscription;
  StreamSubscription<PlaybackState>? _stateSubscription;

  NotificationService(this._config);

  /// Stream of notification action events
  Stream<String> get actionStream => _actionController.stream;

  /// Whether notification is currently showing
  bool get isShowing => _isShowing;

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

    // Don't show notification when paused if configured
    if (!_config.showWhenPaused && state.state == PlayerState.paused) {
      await dismiss(playerId);
      return;
    }

    try {
      await _channel.invokeMethod('showNotification', {
        'playerId': playerId,
        'mediaItem': {
          'id': mediaItem.id,
          'title': mediaItem.title,
          'artist': mediaItem.artist,
          'album': mediaItem.album,
          'artworkUrl': mediaItem.artworkUrl,
          'duration': mediaItem.duration?.inMilliseconds,
        },
        'state': {
          'state': state.state.name,
          'position': state.position.inMilliseconds,
          'duration': state.duration.inMilliseconds,
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
      await _channel.invokeMethod('updateNotificationState', {
        'playerId': playerId,
        'state': {
          'state': state.state.name,
          'position': state.position.inMilliseconds,
          'duration': state.duration.inMilliseconds,
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
