import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/media_item.dart';
import '../models/player_state.dart';
import '../models/playlist.dart';
import '../models/subtitle_track.dart';
import 'media_config.dart';

/// Main media player controller class
///
/// This class provides the primary interface for controlling media playback,
/// managing playlists, and configuring player behavior.
class MediaPlayer {
  static const MethodChannel _channel = MethodChannel('flutter_media_player');

  /// Unique identifier for this player instance
  final String playerId;

  /// Configuration for this player instance
  MediaConfig _config;

  /// Current playlist
  Playlist? _currentPlaylist;

  /// Current media item
  MediaItem? _currentItem;

  /// Stream controllers for state management
  final StreamController<PlaybackState> _stateController =
      StreamController<PlaybackState>.broadcast();
  final StreamController<Duration> _positionController =
      StreamController<Duration>.broadcast();
  final StreamController<Duration> _durationController =
      StreamController<Duration>.broadcast();
  final StreamController<double> _volumeController =
      StreamController<double>.broadcast();
  final StreamController<double> _speedController =
      StreamController<double>.broadcast();
  final StreamController<List<SubtitleTrack>> _subtitleTracksController =
      StreamController<List<SubtitleTrack>>.broadcast();

  /// Current playback state
  PlaybackState _currentState = const PlaybackState(state: PlayerState.idle);

  /// Available subtitle tracks
  List<SubtitleTrack> _subtitleTracks = [];

  /// Currently selected subtitle track
  SubtitleTrack? _selectedSubtitleTrack;

  /// Timer for position updates
  Timer? _positionTimer;

  /// Whether the player has been initialized
  bool _isInitialized = false;

  /// Private constructor for factory pattern
  MediaPlayer._(this.playerId, this._config) {
    _setupMethodCallHandler();
  }

  /// Factory constructor to create a new media player instance
  factory MediaPlayer({
    String? playerId,
    MediaConfig? config,
  }) {
    final id = playerId ?? DateTime.now().millisecondsSinceEpoch.toString();
    final playerConfig = config ?? const MediaConfig();
    return MediaPlayer._(id, playerConfig);
  }

  /// Current configuration
  MediaConfig get config => _config;

  /// Current playlist
  Playlist? get currentPlaylist => _currentPlaylist;

  /// Current media item
  MediaItem? get currentItem => _currentItem;

  /// Current playback state
  PlaybackState get currentState => _currentState;

  /// Stream of playback state changes
  Stream<PlaybackState> get stateStream => _stateController.stream;

  /// Stream of position updates
  Stream<Duration> get positionStream => _positionController.stream;

  /// Stream of duration updates
  Stream<Duration> get durationStream => _durationController.stream;

  /// Stream of volume changes
  Stream<double> get volumeStream => _volumeController.stream;

  /// Stream of speed changes
  Stream<double> get speedStream => _speedController.stream;

  /// Stream of subtitle track updates
  Stream<List<SubtitleTrack>> get subtitleTracksStream =>
      _subtitleTracksController.stream;

  /// Available subtitle tracks
  List<SubtitleTrack> get subtitleTracks => _subtitleTracks;

  /// Currently selected subtitle track
  SubtitleTrack? get selectedSubtitleTrack => _selectedSubtitleTrack;

  /// Whether the player is initialized
  bool get isInitialized => _isInitialized;

  /// Initialize the player
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      await _channel.invokeMethod('initialize', {
        'playerId': playerId,
        'config': _configToMap(_config),
      });
      _isInitialized = true;
      _startPositionTimer();
    } catch (e) {
      throw MediaPlayerException('Failed to initialize player: $e');
    }
  }

  /// Load a single media item
  Future<void> load(MediaItem item) async {
    await _ensureInitialized();

    try {
      _currentItem = item;
      await _channel.invokeMethod('load', {
        'playerId': playerId,
        'mediaItem': item.toMap(),
      });

      _updateState(_currentState.copyWith(state: PlayerState.buffering));
    } catch (e) {
      _updateState(_currentState.copyWith(
        state: PlayerState.error,
        errorMessage: 'Failed to load media: $e',
      ));
      throw MediaPlayerException('Failed to load media: $e');
    }
  }

  /// Set and load a playlist
  Future<void> setPlaylist(Playlist playlist, {int? startIndex}) async {
    await _ensureInitialized();

    try {
      _currentPlaylist = playlist;
      final index = startIndex ?? playlist.currentIndex;

      await _channel.invokeMethod('setPlaylist', {
        'playerId': playerId,
        'playlist': _playlistToMap(playlist),
        'startIndex': index,
      });

      if (playlist.items.isNotEmpty && index < playlist.items.length) {
        _currentItem = playlist.items[index];
        _currentPlaylist = playlist.copyWith(currentIndex: index);
      }

      _updateState(_currentState.copyWith(state: PlayerState.buffering));
    } catch (e) {
      _updateState(_currentState.copyWith(
        state: PlayerState.error,
        errorMessage: 'Failed to set playlist: $e',
      ));
      throw MediaPlayerException('Failed to set playlist: $e');
    }
  }

  /// Start or resume playback
  Future<void> play() async {
    await _ensureInitialized();

    try {
      await _channel.invokeMethod('play', {'playerId': playerId});
    } catch (e) {
      throw MediaPlayerException('Failed to play: $e');
    }
  }

  /// Pause playback
  Future<void> pause() async {
    await _ensureInitialized();

    try {
      await _channel.invokeMethod('pause', {'playerId': playerId});
    } catch (e) {
      throw MediaPlayerException('Failed to pause: $e');
    }
  }

  /// Stop playback
  Future<void> stop() async {
    await _ensureInitialized();

    try {
      await _channel.invokeMethod('stop', {'playerId': playerId});
      _updateState(_currentState.copyWith(state: PlayerState.idle));
    } catch (e) {
      throw MediaPlayerException('Failed to stop: $e');
    }
  }

  /// Seek to a specific position
  Future<void> seekTo(Duration position) async {
    await _ensureInitialized();

    try {
      await _channel.invokeMethod('seekTo', {
        'playerId': playerId,
        'position': position.inMilliseconds,
      });
    } catch (e) {
      throw MediaPlayerException('Failed to seek: $e');
    }
  }

  /// Set playback volume (0.0 to 1.0)
  Future<void> setVolume(double volume) async {
    await _ensureInitialized();

    final clampedVolume = volume.clamp(0.0, 1.0);

    try {
      await _channel.invokeMethod('setVolume', {
        'playerId': playerId,
        'volume': clampedVolume,
      });

      _config = _config.copyWith(volume: clampedVolume);
      _volumeController.add(clampedVolume);
      _updateState(_currentState.copyWith(volume: clampedVolume));
    } catch (e) {
      throw MediaPlayerException('Failed to set volume: $e');
    }
  }

  /// Set playback speed
  Future<void> setSpeed(double speed) async {
    await _ensureInitialized();

    final clampedSpeed = speed.clamp(0.25, 4.0);

    try {
      await _channel.invokeMethod('setSpeed', {
        'playerId': playerId,
        'speed': clampedSpeed,
      });

      _config = _config.copyWith(speed: clampedSpeed);
      _speedController.add(clampedSpeed);
      _updateState(_currentState.copyWith(speed: clampedSpeed));
    } catch (e) {
      throw MediaPlayerException('Failed to set speed: $e');
    }
  }

  /// Mute or unmute the player
  Future<void> setMuted(bool muted) async {
    await _ensureInitialized();

    try {
      await _channel.invokeMethod('setMuted', {
        'playerId': playerId,
        'muted': muted,
      });

      _updateState(_currentState.copyWith(isMuted: muted));
    } catch (e) {
      throw MediaPlayerException('Failed to set muted: $e');
    }
  }

  /// Set video BoxFit mode
  Future<void> setBoxFit(BoxFit boxFit) async {
    await _ensureInitialized();

    try {
      await _channel.invokeMethod('setBoxFit', {
        'playerId': playerId,
        'boxFit': _boxFitToString(boxFit),
      });

      _config = _config.copyWith(boxFit: boxFit);
    } catch (e) {
      throw MediaPlayerException('Failed to set BoxFit: $e');
    }
  }

  /// Set subtitle track
  Future<void> setSubtitleTrack(SubtitleTrack? track) async {
    await _ensureInitialized();

    try {
      await _channel.invokeMethod('setSubtitleTrack', {
        'playerId': playerId,
        'subtitleTrack': track?.toMap(),
      });

      _selectedSubtitleTrack = track;

      // Update subtitle tracks to reflect selection
      _subtitleTracks = _subtitleTracks
          .map((t) => t.copyWith(isSelected: t.id == track?.id))
          .toList();

      _subtitleTracksController.add(_subtitleTracks);
    } catch (e) {
      throw MediaPlayerException('Failed to set subtitle track: $e');
    }
  }

  /// Skip to next item in playlist
  Future<void> skipToNext() async {
    if (_currentPlaylist == null) {
      throw MediaPlayerException('No playlist set');
    }

    final nextIndex = _currentPlaylist!.nextIndex;
    if (nextIndex != null) {
      await skipToIndex(nextIndex);
    }
  }

  /// Skip to previous item in playlist
  Future<void> skipToPrevious() async {
    if (_currentPlaylist == null) {
      throw MediaPlayerException('No playlist set');
    }

    final previousIndex = _currentPlaylist!.previousIndex;
    if (previousIndex != null) {
      await skipToIndex(previousIndex);
    }
  }

  /// Skip to specific index in playlist
  Future<void> skipToIndex(int index) async {
    if (_currentPlaylist == null) {
      throw MediaPlayerException('No playlist set');
    }

    if (index < 0 || index >= _currentPlaylist!.items.length) {
      throw MediaPlayerException('Invalid playlist index: $index');
    }

    try {
      await _channel.invokeMethod('skipToIndex', {
        'playerId': playerId,
        'index': index,
      });

      _currentPlaylist = _currentPlaylist!.copyWith(currentIndex: index);
      _currentItem = _currentPlaylist!.items[index];
    } catch (e) {
      throw MediaPlayerException('Failed to skip to index: $e');
    }
  }

  /// Update player configuration
  Future<void> updateConfig(MediaConfig config) async {
    _config = config;

    if (_isInitialized) {
      try {
        await _channel.invokeMethod('updateConfig', {
          'playerId': playerId,
          'config': _configToMap(config),
        });
      } catch (e) {
        throw MediaPlayerException('Failed to update config: $e');
      }
    }
  }

  /// Dispose the player and release resources
  Future<void> dispose() async {
    _positionTimer?.cancel();

    if (_isInitialized) {
      try {
        await _channel.invokeMethod('dispose', {'playerId': playerId});
      } catch (e) {
        // Ignore disposal errors
      }
    }

    await _stateController.close();
    await _positionController.close();
    await _durationController.close();
    await _volumeController.close();
    await _speedController.close();
    await _subtitleTracksController.close();
  }

  /// Setup method call handler for platform events
  void _setupMethodCallHandler() {
    _channel.setMethodCallHandler((call) async {
      if (call.arguments['playerId'] != playerId) return;

      switch (call.method) {
        case 'onStateChanged':
          _handleStateChanged(call.arguments);
          break;
        case 'onPositionChanged':
          _handlePositionChanged(call.arguments);
          break;
        case 'onDurationChanged':
          _handleDurationChanged(call.arguments);
          break;
        case 'onSubtitleTracksChanged':
          _handleSubtitleTracksChanged(call.arguments);
          break;
        case 'onError':
          _handleError(call.arguments);
          break;
      }
    });
  }

  /// Handle state change events from platform
  void _handleStateChanged(Map<dynamic, dynamic> arguments) {
    final stateString = arguments['state'] as String;
    final state = _stringToPlayerState(stateString);

    _updateState(_currentState.copyWith(
      state: state,
      isBuffering: arguments['isBuffering'] as bool? ?? false,
      bufferPercentage:
          (arguments['bufferPercentage'] as num?)?.toDouble() ?? 0.0,
    ));
  }

  /// Handle position change events from platform
  void _handlePositionChanged(Map<dynamic, dynamic> arguments) {
    final positionMs = arguments['position'] as int;
    final position = Duration(milliseconds: positionMs);

    _updateState(_currentState.copyWith(position: position));
    _positionController.add(position);
  }

  /// Handle duration change events from platform
  void _handleDurationChanged(Map<dynamic, dynamic> arguments) {
    final durationMs = arguments['duration'] as int;
    final duration = Duration(milliseconds: durationMs);

    _updateState(_currentState.copyWith(duration: duration));
    _durationController.add(duration);
  }

  /// Handle subtitle tracks change events from platform
  void _handleSubtitleTracksChanged(Map<dynamic, dynamic> arguments) {
    final tracksData = arguments['tracks'] as List<dynamic>;
    _subtitleTracks = tracksData
        .cast<Map<dynamic, dynamic>>()
        .map((data) => SubtitleTrack.fromMap(Map<String, dynamic>.from(data)))
        .toList();

    _subtitleTracksController.add(_subtitleTracks);
  }

  /// Handle error events from platform
  void _handleError(Map<dynamic, dynamic> arguments) {
    final errorMessage = arguments['error'] as String;

    _updateState(_currentState.copyWith(
      state: PlayerState.error,
      errorMessage: errorMessage,
    ));
  }

  /// Update current state and notify listeners
  void _updateState(PlaybackState newState) {
    _currentState = newState;
    _stateController.add(newState);
  }

  /// Start position update timer
  void _startPositionTimer() {
    _positionTimer = Timer.periodic(const Duration(milliseconds: 500), (timer) {
      if (_currentState.state == PlayerState.playing) {
        // Position updates are handled by platform events
        // This timer is kept for fallback purposes
      }
    });
  }

  /// Ensure player is initialized
  Future<void> _ensureInitialized() async {
    if (!_isInitialized) {
      await initialize();
    }
  }

  /// Convert MediaConfig to Map for platform communication
  Map<String, dynamic> _configToMap(MediaConfig config) {
    return {
      'autoPlay': config.autoPlay,
      'looping': config.looping,
      'boxFit': _boxFitToString(config.boxFit),
      'volume': config.volume,
      'speed': config.speed,
      'startMuted': config.startMuted,
      'httpHeaders': config.httpHeaders,
      'showControls': config.showControls,
      'controlsTimeout': config.controlsTimeout.inMilliseconds,
      'allowBackgroundPlayback': config.allowBackgroundPlayback,
      'useHardwareAcceleration': config.useHardwareAcceleration,
    };
  }

  /// Convert Playlist to Map for platform communication
  Map<String, dynamic> _playlistToMap(Playlist playlist) {
    return {
      'id': playlist.id,
      'title': playlist.title,
      'items': playlist.items.map((item) => item.toMap()).toList(),
      'currentIndex': playlist.currentIndex,
      'mode': playlist.mode.name,
      'repeatMode': playlist.repeatMode.name,
    };
  }

  /// Convert BoxFit to string
  String _boxFitToString(BoxFit boxFit) {
    switch (boxFit) {
      case BoxFit.contain:
        return 'contain';
      case BoxFit.cover:
        return 'cover';
      case BoxFit.fill:
        return 'fill';
      case BoxFit.fitWidth:
        return 'fitWidth';
      case BoxFit.fitHeight:
        return 'fitHeight';
      case BoxFit.none:
        return 'none';
      case BoxFit.scaleDown:
        return 'scaleDown';
    }
  }

  /// Convert string to PlayerState
  PlayerState _stringToPlayerState(String state) {
    switch (state) {
      case 'idle':
        return PlayerState.idle;
      case 'buffering':
        return PlayerState.buffering;
      case 'ready':
        return PlayerState.ready;
      case 'playing':
        return PlayerState.playing;
      case 'paused':
        return PlayerState.paused;
      case 'completed':
        return PlayerState.completed;
      case 'error':
        return PlayerState.error;
      default:
        return PlayerState.idle;
    }
  }
}

/// Exception thrown by MediaPlayer operations
class MediaPlayerException implements Exception {
  final String message;

  const MediaPlayerException(this.message);

  @override
  String toString() => 'MediaPlayerException: $message';
}
