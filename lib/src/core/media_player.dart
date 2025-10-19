import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/media_item.dart';
import '../models/player_state.dart';
import '../models/playlist.dart';
import '../models/subtitle_track.dart';
import '../models/streaming_config.dart';
import '../models/pip_config.dart';
import '../models/cast_device.dart';
import '../models/drm_config.dart';
import 'media_config.dart';

/// Main media player controller class
///
/// This class provides the primary interface for controlling media playbook,
/// managing playlists, and configuring player behavior.
class MediaPlayer {
  static const MethodChannel _channel = MethodChannel('flutter_media_player');
  static final Map<String, MediaPlayer> _instances = {};

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
  final StreamController<List<QualityTrack>> _qualityTracksController =
      StreamController<List<QualityTrack>>.broadcast();
  final StreamController<List<AudioTrack>> _audioTracksController =
      StreamController<List<AudioTrack>>.broadcast();
  final StreamController<PipStatus> _pipStatusController =
      StreamController<PipStatus>.broadcast();
  final StreamController<CastStatus> _castStatusController =
      StreamController<CastStatus>.broadcast();
  final StreamController<List<CastDevice>> _castDevicesController =
      StreamController<List<CastDevice>>.broadcast();
  final StreamController<DrmSession> _drmSessionController =
      StreamController<DrmSession>.broadcast();

  /// Current playback state
  PlaybackState _currentState = const PlaybackState(state: PlayerState.idle);

  /// Current PiP status
  PipStatus _pipStatus = const PipStatus(
    state: PipState.unavailable,
    isSupported: false,
    isActive: false,
  );

  /// Current cast status
  CastStatus _castStatus = const CastStatus(
    state: CastState.disconnected,
    isAvailable: false,
    isCasting: false,
  );

  /// Available subtitle tracks
  List<SubtitleTrack> _subtitleTracks = [];

  /// Currently selected subtitle track
  SubtitleTrack? _selectedSubtitleTrack;

  /// Available quality tracks
  List<QualityTrack> _qualityTracks = [];

  /// Currently selected quality track
  QualityTrack? _selectedQualityTrack;

  /// Available audio tracks
  List<AudioTrack> _audioTracks = [];

  /// Currently selected audio track
  AudioTrack? _selectedAudioTrack;

  /// Available cast devices
  List<CastDevice> _castDevices = [];

  /// Timer for position updates
  Timer? _positionTimer;

  /// Whether the player has been initialized
  bool _isInitialized = false;

  /// Whether the player has been disposed
  bool _isDisposed = false;

  /// Completer for initialization
  Completer<void>? _initializationCompleter;

  /// Private constructor for factory pattern
  MediaPlayer._(this.playerId, this._config) {
    _instances[playerId] = this;
    _setupMethodCallHandler();
  }

  /// Factory constructor to create a new media player instance
  factory MediaPlayer({
    String? playerId,
    MediaConfig? config,
  }) {
    final id = playerId ?? DateTime.now().millisecondsSinceEpoch.toString();

    // Return existing instance if it exists and hasn't been disposed
    if (_instances.containsKey(id) && !_instances[id]!._isDisposed) {
      return _instances[id]!;
    }

    final playerConfig = config ?? const MediaConfig();
    return MediaPlayer._(id, playerConfig);
  }

  // Getters with validation
  /// Current configuration
  MediaConfig get config {
    _throwIfDisposed();
    return _config;
  }

  /// Current playlist
  Playlist? get currentPlaylist {
    _throwIfDisposed();
    return _currentPlaylist;
  }

  /// Current media item
  MediaItem? get currentItem {
    _throwIfDisposed();
    return _currentItem;
  }

  /// Current playback state
  PlaybackState get currentState {
    _throwIfDisposed();
    return _currentState;
  }

  /// Stream of playbook state changes
  Stream<PlaybackState> get stateStream {
    _throwIfDisposed();
    return _stateController.stream;
  }

  /// Stream of position updates
  Stream<Duration> get positionStream {
    _throwIfDisposed();
    return _positionController.stream;
  }

  /// Stream of duration updates
  Stream<Duration> get durationStream {
    _throwIfDisposed();
    return _durationController.stream;
  }

  /// Stream of volume changes
  Stream<double> get volumeStream {
    _throwIfDisposed();
    return _volumeController.stream;
  }

  /// Stream of speed changes
  Stream<double> get speedStream {
    _throwIfDisposed();
    return _speedController.stream;
  }

  /// Stream of subtitle track updates
  Stream<List<SubtitleTrack>> get subtitleTracksStream {
    _throwIfDisposed();
    return _subtitleTracksController.stream;
  }

  /// Stream of quality track updates
  Stream<List<QualityTrack>> get qualityTracksStream {
    _throwIfDisposed();
    return _qualityTracksController.stream;
  }

  /// Stream of audio track updates
  Stream<List<AudioTrack>> get audioTracksStream {
    _throwIfDisposed();
    return _audioTracksController.stream;
  }

  /// Stream of PiP status updates
  Stream<PipStatus> get pipStatusStream {
    _throwIfDisposed();
    return _pipStatusController.stream;
  }

  /// Stream of cast status updates
  Stream<CastStatus> get castStatusStream {
    _throwIfDisposed();
    return _castStatusController.stream;
  }

  /// Stream of available cast devices
  Stream<List<CastDevice>> get castDevicesStream {
    _throwIfDisposed();
    return _castDevicesController.stream;
  }

  /// Available subtitle tracks
  List<SubtitleTrack> get subtitleTracks {
    _throwIfDisposed();
    return List.unmodifiable(_subtitleTracks);
  }

  /// Currently selected subtitle track
  SubtitleTrack? get selectedSubtitleTrack {
    _throwIfDisposed();
    return _selectedSubtitleTrack;
  }

  /// Available quality tracks
  List<QualityTrack> get qualityTracks {
    _throwIfDisposed();
    return List.unmodifiable(_qualityTracks);
  }

  /// Currently selected quality track
  QualityTrack? get selectedQualityTrack {
    _throwIfDisposed();
    return _selectedQualityTrack;
  }

  /// Available audio tracks
  List<AudioTrack> get audioTracks {
    _throwIfDisposed();
    return List.unmodifiable(_audioTracks);
  }

  /// Currently selected audio track
  AudioTrack? get selectedAudioTrack {
    _throwIfDisposed();
    return _selectedAudioTrack;
  }

  /// Current PiP status
  PipStatus get pipStatus {
    _throwIfDisposed();
    return _pipStatus;
  }

  /// Whether PiP is available
  bool get isPipAvailable => _pipStatus.isSupported;

  /// Whether currently in PiP mode
  bool get isInPipMode => _pipStatus.isActive;

  /// Current cast status
  CastStatus get castStatus {
    _throwIfDisposed();
    return _castStatus;
  }

  /// Whether casting is available
  bool get isCastAvailable => _castStatus.isAvailable;

  /// Whether currently casting
  bool get isCasting => _castStatus.isCasting;

  /// Available cast devices
  List<CastDevice> get castDevices => List.unmodifiable(_castDevices);

  /// Stream of DRM session updates
  Stream<DrmSession> get drmSessionStream {
    _throwIfDisposed();
    return _drmSessionController.stream;
  }

  /// Whether the player is initialized
  bool get isInitialized {
    _throwIfDisposed();
    return _isInitialized;
  }

  /// Whether the player is disposed
  bool get isDisposed => _isDisposed;

  /// Initialize the player
  Future<void> initialize() async {
    _throwIfDisposed();

    if (_isInitialized) return;

    // If initialization is already in progress, wait for it
    if (_initializationCompleter != null) {
      return _initializationCompleter!.future;
    }

    _initializationCompleter = Completer<void>();

    try {
      await _channel.invokeMethod('initialize', {
        'playerId': playerId,
        'config': _configToMap(_config),
      });
      _isInitialized = true;
      _startPositionTimer();
      _initializationCompleter!.complete();
    } catch (e) {
      final exception = MediaPlayerException('Failed to initialize player: $e');
      _initializationCompleter!.completeError(exception);
      _initializationCompleter = null;
      throw exception;
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
    } on PlatformException catch (e) {
      final errorMsg = 'Failed to load media: ${e.message ?? e.code}';
      _handleLoadError(errorMsg);
      throw MediaPlayerException(errorMsg);
    } catch (e) {
      final errorMsg = 'Failed to load media: $e';
      _handleLoadError(errorMsg);
      throw MediaPlayerException(errorMsg);
    }
  }

  /// Set and load a playlist
  Future<void> setPlaylist(Playlist playlist, {int? startIndex}) async {
    await _ensureInitialized();

    if (playlist.items.isEmpty) {
      throw const MediaPlayerException('Playlist cannot be empty');
    }

    final index = (startIndex ?? playlist.currentIndex)
        .clamp(0, playlist.items.length - 1);

    try {
      _currentPlaylist = playlist.copyWith(currentIndex: index);

      await _channel.invokeMethod('setPlaylist', {
        'playerId': playerId,
        'playlist': _playlistToMap(_currentPlaylist!),
        'startIndex': index,
      });

      _currentItem = _currentPlaylist!.items[index];
      _updateState(_currentState.copyWith(state: PlayerState.buffering));
    } on PlatformException catch (e) {
      final errorMsg = 'Failed to set playlist: ${e.message ?? e.code}';
      _handleLoadError(errorMsg);
      throw MediaPlayerException(errorMsg);
    } catch (e) {
      final errorMsg = 'Failed to set playlist: $e';
      _handleLoadError(errorMsg);
      throw MediaPlayerException(errorMsg);
    }
  }

  /// Start or resume playback
  Future<void> play() async {
    await _ensureInitialized();

    try {
      await _channel.invokeMethod('play', {'playerId': playerId});
    } on PlatformException catch (e) {
      throw MediaPlayerException('Failed to play: ${e.message ?? e.code}');
    }
  }

  /// Pause playback
  Future<void> pause() async {
    await _ensureInitialized();

    try {
      await _channel.invokeMethod('pause', {'playerId': playerId});
    } on PlatformException catch (e) {
      throw MediaPlayerException('Failed to pause: ${e.message ?? e.code}');
    }
  }

  /// Stop playback
  Future<void> stop() async {
    await _ensureInitialized();

    try {
      await _channel.invokeMethod('stop', {'playerId': playerId});
      _updateState(_currentState.copyWith(state: PlayerState.idle));
    } on PlatformException catch (e) {
      throw MediaPlayerException('Failed to stop: ${e.message ?? e.code}');
    }
  }

  /// Seek to a specific position
  Future<void> seekTo(Duration position) async {
    await _ensureInitialized();

    if (position.isNegative) {
      throw const MediaPlayerException('Seek position cannot be negative');
    }

    try {
      await _channel.invokeMethod('seekTo', {
        'playerId': playerId,
        'position': position.inMilliseconds,
      });
    } on PlatformException catch (e) {
      throw MediaPlayerException('Failed to seek: ${e.message ?? e.code}');
    }
  }

  /// Set playbook volume (0.0 to 1.0)
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
    } on PlatformException catch (e) {
      throw MediaPlayerException(
          'Failed to set volume: ${e.message ?? e.code}');
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
    } on PlatformException catch (e) {
      throw MediaPlayerException('Failed to set speed: ${e.message ?? e.code}');
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
    } on PlatformException catch (e) {
      throw MediaPlayerException('Failed to set muted: ${e.message ?? e.code}');
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
    } on PlatformException catch (e) {
      throw MediaPlayerException(
          'Failed to set BoxFit: ${e.message ?? e.code}');
    }
  }

  /// Set subtitle track
  Future<void> setSubtitleTrack(SubtitleTrack? track) async {
    await _ensureInitialized();

    // Validate track exists in available tracks
    if (track != null && !_subtitleTracks.any((t) => t.id == track.id)) {
      throw MediaPlayerException('Subtitle track not found: ${track.id}');
    }

    try {
      await _channel.invokeMethod('setSubtitleTrack', {
        'playerId': playerId,
        'subtitleTrack': track?.toMap(),
      });

      _selectedSubtitleTrack = track;
      _updateSubtitleTracksSelection(track?.id);
    } on PlatformException catch (e) {
      throw MediaPlayerException(
          'Failed to set subtitle track: ${e.message ?? e.code}');
    }
  }

  /// Set quality track
  Future<void> setQualityTrack(QualityTrack track) async {
    await _ensureInitialized();

    // Validate track exists in available tracks
    if (!_qualityTracks.any((t) => t.id == track.id)) {
      throw MediaPlayerException('Quality track not found: ${track.id}');
    }

    try {
      await _channel.invokeMethod('setQualityTrack', {
        'playerId': playerId,
        'qualityTrack': _qualityTrackToMap(track),
      });

      _selectedQualityTrack = track;
      _updateQualityTracksSelection(track.id);
    } on PlatformException catch (e) {
      throw MediaPlayerException(
          'Failed to set quality track: ${e.message ?? e.code}');
    }
  }

  /// Set audio track
  Future<void> setAudioTrack(AudioTrack track) async {
    await _ensureInitialized();

    // Validate track exists in available tracks
    if (!_audioTracks.any((t) => t.id == track.id)) {
      throw MediaPlayerException('Audio track not found: ${track.id}');
    }

    try {
      await _channel.invokeMethod('setAudioTrack', {
        'playerId': playerId,
        'audioTrack': _audioTrackToMap(track),
      });

      _selectedAudioTrack = track;
      _updateAudioTracksSelection(track.id);
    } on PlatformException catch (e) {
      throw MediaPlayerException(
          'Failed to set audio track: ${e.message ?? e.code}');
    }
  }

  /// Enable automatic quality selection (adaptive bitrate)
  Future<void> enableAutoQuality() async {
    await _ensureInitialized();

    try {
      await _channel.invokeMethod('enableAutoQuality', {
        'playerId': playerId,
      });

      _selectedQualityTrack = null;
      _updateQualityTracksSelection(null);
    } on PlatformException catch (e) {
      throw MediaPlayerException(
          'Failed to enable auto quality: ${e.message ?? e.code}');
    }
  }

  /// Check if Picture-in-Picture is available
  Future<bool> checkPipAvailability() async {
    await _ensureInitialized();

    try {
      final result = await _channel.invokeMethod<bool>('checkPipAvailability', {
        'playerId': playerId,
      });

      return result ?? false;
    } on PlatformException catch (e) {
      debugPrint('Failed to check PiP availability: ${e.message ?? e.code}');
      return false;
    }
  }

  /// Enter Picture-in-Picture mode
  Future<bool> enterPictureInPicture() async {
    await _ensureInitialized();

    if (!_pipStatus.isSupported) {
      throw const MediaPlayerException(
          'Picture-in-Picture not supported on this device');
    }

    try {
      final result =
          await _channel.invokeMethod<bool>('enterPictureInPicture', {
        'playerId': playerId,
      });

      return result ?? false;
    } on PlatformException catch (e) {
      throw MediaPlayerException(
          'Failed to enter PiP mode: ${e.message ?? e.code}');
    }
  }

  /// Exit Picture-in-Picture mode
  Future<void> exitPictureInPicture() async {
    await _ensureInitialized();

    try {
      await _channel.invokeMethod('exitPictureInPicture', {
        'playerId': playerId,
      });
    } on PlatformException catch (e) {
      throw MediaPlayerException(
          'Failed to exit PiP mode: ${e.message ?? e.code}');
    }
  }

  /// Start cast device discovery
  Future<void> startCastDiscovery() async {
    await _ensureInitialized();

    try {
      await _channel.invokeMethod('startCastDiscovery', {
        'playerId': playerId,
      });
    } on PlatformException catch (e) {
      throw MediaPlayerException(
          'Failed to start cast discovery: ${e.message ?? e.code}');
    }
  }

  /// Stop cast device discovery
  Future<void> stopCastDiscovery() async {
    await _ensureInitialized();

    try {
      await _channel.invokeMethod('stopCastDiscovery', {
        'playerId': playerId,
      });
    } on PlatformException catch (e) {
      throw MediaPlayerException(
          'Failed to stop cast discovery: ${e.message ?? e.code}');
    }
  }

  /// Connect to a cast device
  Future<bool> connectToCastDevice(CastDevice device) async {
    await _ensureInitialized();

    try {
      final result = await _channel.invokeMethod<bool>('connectToCastDevice', {
        'playerId': playerId,
        'deviceId': device.id,
        'deviceType': device.type.name,
      });

      return result ?? false;
    } on PlatformException catch (e) {
      throw MediaPlayerException(
          'Failed to connect to cast device: ${e.message ?? e.code}');
    }
  }

  /// Disconnect from current cast device
  Future<void> disconnectFromCastDevice() async {
    await _ensureInitialized();

    try {
      await _channel.invokeMethod('disconnectFromCastDevice', {
        'playerId': playerId,
      });
    } on PlatformException catch (e) {
      throw MediaPlayerException(
          'Failed to disconnect from cast device: ${e.message ?? e.code}');
    }
  }

  /// Skip to next item in playlist
  Future<void> skipToNext() async {
    _validatePlaylistOperation();

    final nextIndex = _currentPlaylist!.nextIndex;
    if (nextIndex == null) {
      throw const MediaPlayerException('No next item available');
    }

    await skipToIndex(nextIndex);
  }

  /// Skip to previous item in playlist
  Future<void> skipToPrevious() async {
    _validatePlaylistOperation();

    final previousIndex = _currentPlaylist!.previousIndex;
    if (previousIndex == null) {
      throw const MediaPlayerException('No previous item available');
    }

    await skipToIndex(previousIndex);
  }

  /// Skip to specific index in playlist
  Future<void> skipToIndex(int index) async {
    _validatePlaylistOperation();

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
    } on PlatformException catch (e) {
      throw MediaPlayerException(
          'Failed to skip to index: ${e.message ?? e.code}');
    }
  }

  /// Update player configuration
  Future<void> updateConfig(MediaConfig config) async {
    _throwIfDisposed();

    final oldConfig = _config;
    _config = config;

    if (_isInitialized) {
      try {
        await _channel.invokeMethod('updateConfig', {
          'playerId': playerId,
          'config': _configToMap(config),
        });
      } on PlatformException catch (e) {
        // Revert config on failure
        _config = oldConfig;
        throw MediaPlayerException(
            'Failed to update config: ${e.message ?? e.code}');
      }
    }
  }

  /// Dispose the player and release resources
  Future<void> dispose() async {
    if (_isDisposed) return;

    _isDisposed = true;
    _instances.remove(playerId);

    // Cancel timers
    _positionTimer?.cancel();
    _positionTimer = null;

    // Close platform channel
    if (_isInitialized) {
      try {
        await _channel.invokeMethod('dispose', {'playerId': playerId});
      } catch (e) {
        // Ignore disposal errors but log them
        debugPrint('Warning: Error disposing MediaPlayer: $e');
      }
    }

    // Close stream controllers
    await Future.wait([
      _stateController.close(),
      _positionController.close(),
      _durationController.close(),
      _volumeController.close(),
      _speedController.close(),
      _subtitleTracksController.close(),
      _qualityTracksController.close(),
      _audioTracksController.close(),
      _pipStatusController.close(),
      _castStatusController.close(),
      _castDevicesController.close(),
      _drmSessionController.close(),
    ]);

    _isInitialized = false;
  }

  // Private helper methods

  /// Validate playlist operation
  void _validatePlaylistOperation() {
    _throwIfDisposed();
    if (_currentPlaylist == null) {
      throw const MediaPlayerException('No playlist set');
    }
  }

  /// Handle load errors consistently
  void _handleLoadError(String errorMessage) {
    _updateState(_currentState.copyWith(
      state: PlayerState.error,
      errorMessage: errorMessage,
    ));
  }

  /// Update subtitle tracks selection state
  void _updateSubtitleTracksSelection(String? selectedId) {
    _subtitleTracks = _subtitleTracks
        .map((t) => t.copyWith(isSelected: t.id == selectedId))
        .toList();
    _subtitleTracksController.add(_subtitleTracks);
  }

  /// Update quality tracks selection state
  void _updateQualityTracksSelection(String? selectedId) {
    _qualityTracks = _qualityTracks
        .map((t) => t.copyWith(isSelected: t.id == selectedId))
        .toList();
    _qualityTracksController.add(_qualityTracks);
  }

  /// Update audio tracks selection state
  void _updateAudioTracksSelection(String selectedId) {
    _audioTracks = _audioTracks
        .map((t) => t.copyWith(isSelected: t.id == selectedId))
        .toList();
    _audioTracksController.add(_audioTracks);
  }

  /// Throw if disposed
  void _throwIfDisposed() {
    if (_isDisposed) {
      throw const MediaPlayerException('MediaPlayer has been disposed');
    }
  }

  /// Setup method call handler for platform events
  void _setupMethodCallHandler() {
    _channel.setMethodCallHandler(_handleMethodCall);
  }

  /// Handle method calls from platform
  Future<void> _handleMethodCall(MethodCall call) async {
    // Only handle calls for this instance
    final arguments = call.arguments as Map<dynamic, dynamic>?;
    if (arguments?['playerId'] != playerId) return;

    try {
      switch (call.method) {
        case 'onStateChanged':
          _handleStateChanged(arguments!);
          break;
        case 'onPositionChanged':
          _handlePositionChanged(arguments!);
          break;
        case 'onDurationChanged':
          _handleDurationChanged(arguments!);
          break;
        case 'onSubtitleTracksChanged':
          _handleSubtitleTracksChanged(arguments!);
          break;
        case 'onQualityTracksChanged':
          _handleQualityTracksChanged(arguments!);
          break;
        case 'onAudioTracksChanged':
          _handleAudioTracksChanged(arguments!);
          break;
        case 'onPipStatusChanged':
          _handlePipStatusChanged(arguments!);
          break;
        case 'onCastStatusChanged':
          _handleCastStatusChanged(arguments!);
          break;
        case 'onCastDevicesChanged':
          _handleCastDevicesChanged(arguments!);
          break;
        case 'onError':
          _handleError(arguments!);
          break;
        default:
          debugPrint('Unhandled method call: ${call.method}');
      }
    } catch (e) {
      debugPrint('Error handling method call ${call.method}: $e');
    }
  }

  /// Handle state change events from platform
  void _handleStateChanged(Map<dynamic, dynamic> arguments) {
    if (_isDisposed) return;

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
    if (_isDisposed) return;

    final positionMs = arguments['position'] as int;
    final position = Duration(milliseconds: positionMs);

    _updateState(_currentState.copyWith(position: position));

    if (!_positionController.isClosed) {
      _positionController.add(position);
    }
  }

  /// Handle duration change events from platform
  void _handleDurationChanged(Map<dynamic, dynamic> arguments) {
    if (_isDisposed) return;

    final durationMs = arguments['duration'] as int;
    final duration = Duration(milliseconds: durationMs);

    _updateState(_currentState.copyWith(duration: duration));

    if (!_durationController.isClosed) {
      _durationController.add(duration);
    }
  }

  /// Handle subtitle tracks change events from platform
  void _handleSubtitleTracksChanged(Map<dynamic, dynamic> arguments) {
    if (_isDisposed) return;

    try {
      final tracksData = arguments['tracks'] as List<dynamic>;
      _subtitleTracks = tracksData
          .cast<Map<dynamic, dynamic>>()
          .map((data) => SubtitleTrack.fromMap(Map<String, dynamic>.from(data)))
          .toList();

      if (!_subtitleTracksController.isClosed) {
        _subtitleTracksController.add(_subtitleTracks);
      }
    } catch (e) {
      debugPrint('Error processing subtitle tracks: $e');
    }
  }

  /// Handle quality tracks change events from platform
  void _handleQualityTracksChanged(Map<dynamic, dynamic> arguments) {
    if (_isDisposed) return;

    try {
      final tracksData = arguments['tracks'] as List<dynamic>;
      _qualityTracks = tracksData
          .cast<Map<dynamic, dynamic>>()
          .map((data) => _qualityTrackFromMap(Map<String, dynamic>.from(data)))
          .toList();

      if (!_qualityTracksController.isClosed) {
        _qualityTracksController.add(_qualityTracks);
      }
    } catch (e) {
      debugPrint('Error processing quality tracks: $e');
    }
  }

  /// Handle audio tracks change events from platform
  void _handleAudioTracksChanged(Map<dynamic, dynamic> arguments) {
    if (_isDisposed) return;

    try {
      final tracksData = arguments['tracks'] as List<dynamic>;
      _audioTracks = tracksData
          .cast<Map<dynamic, dynamic>>()
          .map((data) => _audioTrackFromMap(Map<String, dynamic>.from(data)))
          .toList();

      if (!_audioTracksController.isClosed) {
        _audioTracksController.add(_audioTracks);
      }
    } catch (e) {
      debugPrint('Error processing audio tracks: $e');
    }
  }

  /// Handle error events from platform
  void _handleError(Map<dynamic, dynamic> arguments) {
    if (_isDisposed) return;

    final errorMessage = arguments['error'] as String;

    _updateState(_currentState.copyWith(
      state: PlayerState.error,
      errorMessage: errorMessage,
    ));
  }

  /// Handle PiP status change events from platform
  void _handlePipStatusChanged(Map<dynamic, dynamic> arguments) {
    if (_isDisposed) return;

    try {
      final statusMap = Map<String, dynamic>.from(arguments);
      _pipStatus = PipStatus.fromMap(statusMap);

      if (!_pipStatusController.isClosed) {
        _pipStatusController.add(_pipStatus);
      }

      debugPrint('PiP status changed: ${_pipStatus.state}');
    } catch (e) {
      debugPrint('Error processing PiP status: $e');
    }
  }

  /// Handle cast status change events from platform
  void _handleCastStatusChanged(Map<dynamic, dynamic> arguments) {
    if (_isDisposed) return;

    try {
      final statusMap = Map<String, dynamic>.from(arguments);
      _castStatus = CastStatus.fromMap(statusMap);

      if (!_castStatusController.isClosed) {
        _castStatusController.add(_castStatus);
      }

      debugPrint('Cast status changed: ${_castStatus.state}');
    } catch (e) {
      debugPrint('Error processing cast status: $e');
    }
  }

  /// Handle cast devices change events from platform
  void _handleCastDevicesChanged(Map<dynamic, dynamic> arguments) {
    if (_isDisposed) return;

    try {
      final devicesData = arguments['devices'] as List<dynamic>;
      _castDevices = devicesData
          .map((data) => CastDevice.fromMap(Map<String, dynamic>.from(data)))
          .toList();

      if (!_castDevicesController.isClosed) {
        _castDevicesController.add(_castDevices);
      }

      debugPrint(
          'Cast devices updated: ${_castDevices.length} device(s) found');
    } catch (e) {
      debugPrint('Error processing cast devices: $e');
    }
  }

  /// Update current state and notify listeners
  void _updateState(PlaybackState newState) {
    if (_isDisposed) return;

    _currentState = newState;

    if (!_stateController.isClosed) {
      _stateController.add(newState);
    }
  }

  /// Start position update timer
  void _startPositionTimer() {
    _positionTimer?.cancel();
    _positionTimer = Timer.periodic(
      const Duration(milliseconds: 500),
      (timer) {
        if (_isDisposed) {
          timer.cancel();
          return;
        }

        // Position updates are primarily handled by platform events
        // This timer serves as a fallback and heartbeat mechanism
        if (_currentState.state == PlayerState.playing) {
          // Could implement fallback position calculation here if needed
        }
      },
    );
  }

  /// Ensure player is initialized
  Future<void> _ensureInitialized() async {
    _throwIfDisposed();

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
      'allowBackgroundPlaybook': config.allowBackgroundPlayback,
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
    return switch (boxFit) {
      BoxFit.contain => 'contain',
      BoxFit.cover => 'cover',
      BoxFit.fill => 'fill',
      BoxFit.fitWidth => 'fitWidth',
      BoxFit.fitHeight => 'fitHeight',
      BoxFit.none => 'none',
      BoxFit.scaleDown => 'scaleDown',
    };
  }

  /// Convert string to PlayerState
  PlayerState _stringToPlayerState(String state) {
    return switch (state) {
      'idle' => PlayerState.idle,
      'buffering' => PlayerState.buffering,
      'ready' => PlayerState.ready,
      'playing' => PlayerState.playing,
      'paused' => PlayerState.paused,
      'completed' => PlayerState.completed,
      'error' => PlayerState.error,
      _ => PlayerState.idle,
    };
  }

  /// Convert QualityTrack to Map
  Map<String, dynamic> _qualityTrackToMap(QualityTrack track) {
    return {
      'id': track.id,
      'name': track.name,
      'bitrate': track.bitrate,
      'width': track.width,
      'height': track.height,
      'frameRate': track.frameRate,
      'isSelected': track.isSelected,
      'isAvailable': track.isAvailable,
      'codec': track.codec,
    };
  }

  /// Convert Map to QualityTrack
  QualityTrack _qualityTrackFromMap(Map<String, dynamic> map) {
    return QualityTrack(
      id: map['id'] as String,
      name: map['name'] as String,
      bitrate: map['bitrate'] as int,
      width: map['width'] as int?,
      height: map['height'] as int?,
      frameRate: (map['frameRate'] as num?)?.toDouble(),
      isSelected: map['isSelected'] as bool? ?? false,
      isAvailable: map['isAvailable'] as bool? ?? true,
      codec: map['codec'] as String?,
    );
  }

  /// Convert AudioTrack to Map
  Map<String, dynamic> _audioTrackToMap(AudioTrack track) {
    return {
      'id': track.id,
      'name': track.name,
      'language': track.language,
      'isSelected': track.isSelected,
      'isAvailable': track.isAvailable,
      'codec': track.codec,
      'channels': track.channels,
      'sampleRate': track.sampleRate,
    };
  }

  /// Convert Map to AudioTrack
  AudioTrack _audioTrackFromMap(Map<String, dynamic> map) {
    return AudioTrack(
      id: map['id'] as String,
      name: map['name'] as String,
      language: map['language'] as String?,
      isSelected: map['isSelected'] as bool? ?? false,
      isAvailable: map['isAvailable'] as bool? ?? true,
      codec: map['codec'] as String?,
      channels: map['channels'] as int?,
      sampleRate: map['sampleRate'] as int?,
    );
  }
}

/// Exception thrown by MediaPlayer operations
class MediaPlayerException implements Exception {
  final String message;

  const MediaPlayerException(this.message);

  @override
  String toString() => 'MediaPlayerException: $message';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MediaPlayerException &&
          runtimeType == other.runtimeType &&
          message == other.message;

  @override
  int get hashCode => message.hashCode;
}
