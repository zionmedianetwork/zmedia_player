import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'
    show MethodCall, MethodChannel, PlatformException;
import '../models/media_item.dart';
import '../models/player_state.dart';
import '../models/playlist.dart';
import '../models/subtitle_track.dart';
import '../models/streaming_config.dart';
import '../models/pip_config.dart';
import '../models/cast_device.dart';
import '../models/drm_config.dart';
import '../models/buffering_config.dart';
import '../models/buffer_health.dart';
import '../models/network_status.dart';
import '../services/buffering_service.dart';
import '../security/input_validation.dart';
import 'media_config.dart';
import 'crash_reporter.dart';
import 'exceptions.dart';

/// Main media player controller class
///
/// This class provides the primary interface for controlling media playbook,
/// managing playlists, and configuring player behavior.
class MediaPlayer {
  static const MethodChannel _channel = MethodChannel('zmedia_player');
  static final Map<String, MediaPlayer> _instances = {};

  /// Guard that ensures the static method call handler is registered only once.
  static bool _channelHandlerRegistered = false;

  /// Activity tracking for memory leak prevention
  static final Map<String, DateTime> _lastActivity = {};
  static Timer? _cleanupTimer;

  /// Global crash reporter (set once at app startup)
  static CrashReporter? crashReporter;

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
  final StreamController<String> _notificationActionController =
      StreamController<String>.broadcast();
  final StreamController<int> _bandwidthController =
      StreamController<int>.broadcast();
  final StreamController<BufferHealth> _bufferHealthController =
      StreamController<BufferHealth>.broadcast();

  /// Buffering service for adaptive buffer management
  late final BufferingService _bufferingService;

  /// Current playback state
  PlaybackState _currentState = const PlaybackState(state: PlayerState.idle);

  /// Current bandwidth estimate in bits per second
  int _currentBandwidth = 0;

  /// Whether current media is live
  bool _isLive = false;

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
    _markActivity();
    _ensureCleanupTimer();
    _setupMethodCallHandler();
    _initializeBufferingService();
  }

  /// Initialize buffering service with configuration
  void _initializeBufferingService() {
    // Convert old BufferConfig to new BufferingConfig if provided
    final bufferingConfig = _config.bufferConfig != null
        ? BufferingConfig(
            minBufferMs: _config.bufferConfig!.minBufferDuration.inMilliseconds,
            maxBufferMs: _config.bufferConfig!.maxBufferDuration.inMilliseconds,
            targetBufferMs:
                _config.bufferConfig!.targetBufferDuration.inMilliseconds,
            rebufferMs: _config.bufferConfig!.rebufferDuration.inMilliseconds,
          )
        : const BufferingConfig(); // Use default config

    _bufferingService = BufferingService(
      config: bufferingConfig,
      platformBufferStatusCallback: _getPlatformBufferStatus,
    );

    // Listen to buffer health updates and forward to public stream
    _bufferingService.bufferHealthStream.listen((health) {
      if (!_bufferHealthController.isClosed) {
        _bufferHealthController.add(health);
      }
    });
  }

  /// Get buffer status from platform
  Future<Map<String, dynamic>> _getPlatformBufferStatus() async {
    try {
      final result = await _channel.invokeMethod<Map<dynamic, dynamic>>(
        'getBufferHealth',
        {'playerId': playerId},
      );

      if (result == null) {
        return {};
      }

      // Convert dynamic map to String map
      return result.map((key, value) => MapEntry(key.toString(), value));
    } catch (e) {
      debugPrint('Error getting buffer status: $e');
      return {};
    }
  }

  /// Enable crash reporting (call once at app startup)
  ///
  /// [reporter] - The crash reporter implementation to use
  ///
  /// Example:
  /// ```dart
  /// MediaPlayer.enableCrashReporting(ConsoleOnlyCrashReporter());
  /// ```
  static void enableCrashReporting(CrashReporter reporter) {
    crashReporter = reporter;
    crashReporter?.log('MediaPlayer crash reporting enabled');
  }

  /// Disable crash reporting
  static void disableCrashReporting() {
    crashReporter?.log('MediaPlayer crash reporting disabled');
    crashReporter = null;
  }

  /// Track activity to prevent premature cleanup
  void _markActivity() {
    _lastActivity[playerId] = DateTime.now();
  }

  /// Ensure cleanup timer is running
  static void _ensureCleanupTimer() {
    _cleanupTimer ??= Timer.periodic(
      const Duration(minutes: 5),
      (_) => _cleanupStaleInstances(),
    );
  }

  /// Clean up stale player instances (thread-safe)
  static void _cleanupStaleInstances() {
    final now = DateTime.now();
    const staleThreshold = Duration(minutes: 15);

    // Create defensive copy of entries to avoid concurrent modification
    final activitySnapshot = Map<String, DateTime>.from(_lastActivity);
    final staleKeys = <String>[];

    for (final entry in activitySnapshot.entries) {
      if (now.difference(entry.value) > staleThreshold) {
        staleKeys.add(entry.key);
      }
    }

    // Process stale instances
    for (final key in staleKeys) {
      // Check instance still exists before cleanup
      final instance = _instances[key];
      if (instance != null && !instance.isPlaying && !instance._isDisposed) {
        debugPrint('MediaPlayer: Auto-cleaning stale instance: $key');

        // Atomic removal pattern: remove from tracking first
        _lastActivity.remove(key);
        _instances.remove(key);

        // Then dispose (this may take time)
        instance.dispose().catchError((e) {
          debugPrint('Error during auto-cleanup of $key: $e');
          crashReporter?.reportError(
            e,
            StackTrace.current,
            context: {'playerId': key, 'operation': 'auto_cleanup'},
            fatal: false,
          );
        });
      }
    }

    // Stop timer if no instances
    if (_instances.isEmpty) {
      _cleanupTimer?.cancel();
      _cleanupTimer = null;
    }
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

  /// Whether the player is currently playing
  bool get isPlaying {
    if (_isDisposed) return false;
    return _currentState.state == PlayerState.playing;
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

  /// Stream of bandwidth updates (in bits per second)
  Stream<int> get bandwidthStream {
    _throwIfDisposed();
    return _bandwidthController.stream;
  }

  /// Stream of buffer health updates
  Stream<BufferHealth> get bufferHealthStream {
    _throwIfDisposed();
    return _bufferHealthController.stream;
  }

  /// Current network quality based on bandwidth measurements
  NetworkQuality get networkQuality {
    _throwIfDisposed();
    return _bufferingService.networkQuality;
  }

  /// Buffer statistics for the current session
  BufferStatistics get bufferStatistics {
    _throwIfDisposed();
    return _bufferingService.statistics;
  }

  /// Last known buffer health status
  BufferHealth? get lastBufferHealth {
    _throwIfDisposed();
    return _bufferingService.lastBufferHealth;
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

  /// Current bandwidth estimate in bits per second
  int get currentBandwidth {
    _throwIfDisposed();
    return _currentBandwidth;
  }

  /// Whether the current media is a live stream
  bool get isLive {
    _throwIfDisposed();
    return _isLive;
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

  /// Stream of notification action events
  Stream<String> get notificationActionStream {
    _throwIfDisposed();
    return _notificationActionController.stream;
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
      crashReporter?.log('Initializing MediaPlayer', context: {
        'playerId': playerId,
        'autoPlay': _config.autoPlay,
      });

      await _channel.invokeMethod('initialize', {
        'playerId': playerId,
        'config': _configToMap(_config),
      });
      _isInitialized = true;
      _startPositionTimer();
      _initializationCompleter!.complete();

      crashReporter?.log('MediaPlayer initialized successfully', context: {
        'playerId': playerId,
      });
    } catch (e, stack) {
      crashReporter?.reportError(e, stack,
          context: {
            'operation': 'initialize',
            'playerId': playerId,
            'config': _config.toString(),
          },
          fatal: true);

      final exception = ConfigurationException(
        'Failed to initialize player: $e',
        parameter: 'initialization',
        value: playerId,
      );
      _initializationCompleter!.completeError(exception);
      _initializationCompleter = null;
      throw exception;
    }
  }

  /// Load a single media item
  Future<void> load(MediaItem item) async {
    await _ensureInitialized();
    _markActivity();

    // Enforce HTTPS for DRM-protected media URLs before touching any state.
    InputValidator.validateMediaItemWithDrm(item);

    try {
      crashReporter?.setCustomKey('media_id', item.id);
      crashReporter?.setCustomKey('media_url', item.url);
      crashReporter?.setCustomKey('drm_enabled', item.drmConfig != null);

      _currentItem = item;

      // Initialize isLive flag from the media item
      _isLive = item.isLive;

      // Clear previous track data immediately to prevent stale UI
      _subtitleTracks = [];
      _audioTracks = [];
      _qualityTracks = [];
      if (!_subtitleTracksController.isClosed) {
        _subtitleTracksController.add(_subtitleTracks);
      }
      if (!_audioTracksController.isClosed) {
        _audioTracksController.add(_audioTracks);
      }
      if (!_qualityTracksController.isClosed) {
        _qualityTracksController.add(_qualityTracks);
      }

      // Reset playback speed to normal (1.0x) when loading new media
      try {
        await setSpeed(1.0);
      } catch (e) {
        // Ignore errors from speed reset - don't block media loading
        debugPrint('Failed to reset speed: $e');
      }

      await _channel.invokeMethod('load', {
        'playerId': playerId,
        'mediaItem': item.toMap(),
      });

      _updateState(_currentState.copyWith(state: PlayerState.buffering));

      crashReporter?.log('Media loaded successfully', context: {
        'mediaId': item.id,
        'duration': item.duration?.inSeconds,
        'mediaType': item.mediaType.name,
      });
    } on PlatformException catch (e, stack) {
      crashReporter?.reportError(e, stack, context: {
        'operation': 'load',
        'mediaId': item.id,
        'url': item.url,
        'playerId': playerId,
        'errorCode': e.code,
      });

      _handleLoadError('Failed to load media: ${e.message ?? e.code}');

      // Convert platform exceptions to typed exceptions
      if (e.code == 'NETWORK_ERROR' || e.code == 'CONNECTIVITY_ERROR') {
        final isOffline = e.message?.toLowerCase().contains('offline') ?? false;
        final isTimeout = e.message?.toLowerCase().contains('timeout') ?? false;
        throw NetworkException(
          e.message ?? 'Network error occurred',
          isOffline: isOffline,
          isTimeout: isTimeout,
          details: e.details as Map<String, dynamic>?,
        );
      } else if (e.code.startsWith('DRM_')) {
        throw DrmException(
          e.message ?? 'DRM error occurred',
          drmType: item.drmConfig?.scheme.toString().split('.').last,
          errorCode: e.code,
          isLicenseError: e.code.contains('LICENSE'),
          isCertificateError:
              e.code.contains('CERTIFICATE') || e.code.contains('PROVISIONING'),
          details: e.details as Map<String, dynamic>?,
        );
      } else {
        throw MediaLoadException(
          e.message ?? 'Failed to load media',
          url: item.url,
          statusCode:
              e.code == 'HTTP_ERROR' ? int.tryParse(e.message ?? '') : null,
          details: e.details as Map<String, dynamic>?,
        );
      }
    } catch (e, stack) {
      crashReporter?.reportError(e, stack, context: {
        'operation': 'load',
        'mediaId': item.id,
        'url': item.url,
        'playerId': playerId,
      });

      _handleLoadError('Failed to load media: $e');

      // Re-throw if it's already a MediaPlayerException
      if (e is MediaPlayerException) rethrow;

      throw MediaLoadException(
        'Failed to load media: $e',
        url: item.url,
      );
    }
  }

  /// Set and load a playlist
  Future<void> setPlaylist(Playlist playlist, {int? startIndex}) async {
    await _ensureInitialized();
    _markActivity();

    if (playlist.items.isEmpty) {
      throw const ConfigurationException(
        'Playlist cannot be empty',
        parameter: 'playlist.items',
        value: [],
      );
    }

    final index = (startIndex ?? playlist.currentIndex)
        .clamp(0, playlist.items.length - 1);

    try {
      _currentPlaylist = playlist.copyWith(currentIndex: index);

      // Clear previous track data immediately to prevent stale UI
      _subtitleTracks = [];
      _audioTracks = [];
      _qualityTracks = [];
      if (!_subtitleTracksController.isClosed) {
        _subtitleTracksController.add(_subtitleTracks);
      }
      if (!_audioTracksController.isClosed) {
        _audioTracksController.add(_audioTracks);
      }
      if (!_qualityTracksController.isClosed) {
        _qualityTracksController.add(_qualityTracks);
      }

      // Reset playback speed to normal (1.0x) when loading new playlist
      try {
        await setSpeed(1.0);
      } catch (e) {
        // Ignore errors from speed reset - don't block playlist loading
        debugPrint('Failed to reset speed: $e');
      }

      await _channel.invokeMethod('setPlaylist', {
        'playerId': playerId,
        'playlist': _playlistToMap(_currentPlaylist!),
        'startIndex': index,
      });

      _currentItem = _currentPlaylist!.items[index];
      _updateState(_currentState.copyWith(state: PlayerState.buffering));
    } on PlatformException catch (e) {
      _handleLoadError('Failed to set playlist: ${e.message ?? e.code}');
      throw MediaLoadException(
        'Failed to set playlist: ${e.message ?? e.code}',
        details: {
          'itemCount': playlist.items.length,
          ...?e.details as Map<String, dynamic>?
        },
      );
    } catch (e) {
      _handleLoadError('Failed to set playlist: $e');

      // Re-throw if it's already a MediaPlayerException
      if (e is MediaPlayerException) rethrow;

      throw MediaLoadException(
        'Failed to set playlist: $e',
        details: {'itemCount': playlist.items.length},
      );
    }
  }

  /// Start or resume playback
  Future<void> play() async {
    await _ensureInitialized();
    _markActivity();

    try {
      // If playback has finished, restart from the beginning so that calling
      // play() (e.g. from a lock-screen control or the play button) resumes
      // instead of no-opping at the end of the media.
      if (_currentState.state == PlayerState.completed) {
        await _channel.invokeMethod('seekTo', {
          'playerId': playerId,
          'position': 0,
        });
      }

      await _channel.invokeMethod('play', {'playerId': playerId});

      // Start buffer health monitoring
      _bufferingService.startMonitoring();

      crashReporter?.log('Playback started', context: {
        'playerId': playerId,
        'mediaId': _currentItem?.id,
      });
    } on PlatformException catch (e, stack) {
      crashReporter?.reportError(e, stack, context: {
        'operation': 'play',
        'playerId': playerId,
        'state': _currentState.state.name,
        'mediaId': _currentItem?.id,
      });

      throw PlaybackException(
        'Failed to start playback: ${e.message ?? e.code}',
        errorCode: e.code,
        details: e.details as Map<String, dynamic>?,
      );
    }
  }

  /// Pause playback
  Future<void> pause() async {
    await _ensureInitialized();
    _markActivity();

    try {
      await _channel.invokeMethod('pause', {'playerId': playerId});

      // Stop buffer health monitoring when paused
      _bufferingService.stopMonitoring();

      crashReporter?.log('Playback paused', context: {
        'playerId': playerId,
        'position': _currentState.position.inSeconds,
      });
    } on PlatformException catch (e, stack) {
      crashReporter?.reportError(e, stack, context: {
        'operation': 'pause',
        'playerId': playerId,
        'state': _currentState.state.name,
      });

      throw PlaybackException(
        'Failed to pause: ${e.message ?? e.code}',
        errorCode: e.code,
        details: e.details as Map<String, dynamic>?,
      );
    }
  }

  /// Stop playback
  Future<void> stop() async {
    await _ensureInitialized();

    try {
      await _channel.invokeMethod('stop', {'playerId': playerId});
      _updateState(_currentState.copyWith(state: PlayerState.idle));
    } on PlatformException catch (e) {
      throw PlaybackException(
        'Failed to stop: ${e.message ?? e.code}',
        errorCode: e.code,
        details: e.details as Map<String, dynamic>?,
      );
    }
  }

  /// Seek to a specific position
  Future<void> seekTo(Duration position) async {
    await _ensureInitialized();

    if (position.isNegative) {
      throw ConfigurationException(
        'Seek position cannot be negative',
        parameter: 'position',
        value: position,
      );
    }

    try {
      await _channel.invokeMethod('seekTo', {
        'playerId': playerId,
        'position': position.inMilliseconds,
      });
    } on PlatformException catch (e) {
      throw PlaybackException(
        'Failed to seek: ${e.message ?? e.code}',
        errorCode: e.code,
        details: e.details as Map<String, dynamic>?,
      );
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
      throw ConfigurationException(
        'Failed to set volume: ${e.message ?? e.code}',
        parameter: 'volume',
        value: volume,
        details: e.details as Map<String, dynamic>?,
      );
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
      throw ConfigurationException(
        'Failed to set speed: ${e.message ?? e.code}',
        parameter: 'speed',
        value: speed,
        details: e.details as Map<String, dynamic>?,
      );
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
      throw ConfigurationException(
        'Failed to set muted: ${e.message ?? e.code}',
        parameter: 'muted',
        value: muted,
        details: e.details as Map<String, dynamic>?,
      );
    }
  }

  /// Notify the native layer that a new platform-view host has been attached
  /// and that it should re-assert the player onto the newly-active surface.
  ///
  /// Call this from [MediaPlayerWidget]'s [_onPlatformViewCreated] callback
  /// (and from [didChangeDependencies] when returning from a fullscreen route)
  /// so the newest host always wins the surface.
  ///
  /// On iOS this is a no-op: AVPlayer supports multiple AVPlayerLayers
  /// simultaneously, and each new [UiKitView] host already creates its own
  /// [MediaPlayerView] with a fresh [AVPlayerLayer] wired to the shared
  /// [AVPlayer].  The call succeeds silently even on iOS because the native
  /// handler returns `nil` for unknown methods gracefully.
  ///
  /// On Android the native handler calls `playerView?.setPlayer(exoPlayer)`
  /// so that the newest [PlayerView] (created by [getPlayerView()]) has the
  /// ExoPlayer reference re-attached after it was detached from the old host.
  Future<void> reclaimVideoSurface() async {
    if (!isInitialized) return;
    _markActivity();

    try {
      await _channel.invokeMethod('reclaimVideoSurface', {
        'playerId': playerId,
      });
    } on PlatformException catch (e) {
      // Non-fatal: log and continue.  A failure here means the native side
      // did not handle the call (e.g. older plugin version).
      debugPrint(
          'MediaPlayer.reclaimVideoSurface: ignored PlatformException: ${e.message}');
    } catch (e) {
      debugPrint('MediaPlayer.reclaimVideoSurface: ignored error: $e');
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
      throw ConfigurationException(
        'Failed to set BoxFit: ${e.message ?? e.code}',
        parameter: 'boxFit',
        value: boxFit.toString(),
        details: e.details as Map<String, dynamic>?,
      );
    }
  }

  /// Set subtitle track
  Future<void> setSubtitleTrack(SubtitleTrack? track) async {
    await _ensureInitialized();

    // Validate track exists in available tracks
    if (track != null && !_subtitleTracks.any((t) => t.id == track.id)) {
      throw InvalidStateException(
        'Subtitle track not found: ${track.id}',
        currentState:
            'Available tracks: ${_subtitleTracks.map((t) => t.id).join(", ")}',
        requiredState: 'Valid track ID',
      );
    }

    try {
      await _channel.invokeMethod('setSubtitleTrack', {
        'playerId': playerId,
        'subtitleTrack': track?.toMap(),
      });

      _selectedSubtitleTrack = track;
      _updateSubtitleTracksSelection(track?.id);
    } on PlatformException catch (e) {
      throw ConfigurationException(
        'Failed to set subtitle track: ${e.message ?? e.code}',
        parameter: 'subtitleTrack',
        value: track?.id,
        details: e.details as Map<String, dynamic>?,
      );
    }
  }

  /// Set quality track
  Future<void> setQualityTrack(QualityTrack track) async {
    await _ensureInitialized();

    // Validate track exists in available tracks
    if (!_qualityTracks.any((t) => t.id == track.id)) {
      throw InvalidStateException(
        'Quality track not found: ${track.id}',
        currentState:
            'Available tracks: ${_qualityTracks.map((t) => t.id).join(", ")}',
        requiredState: 'Valid track ID',
      );
    }

    try {
      await _channel.invokeMethod('setQualityTrack', {
        'playerId': playerId,
        'qualityTrack': _qualityTrackToMap(track),
      });

      _selectedQualityTrack = track;
      _updateQualityTracksSelection(track.id);
    } on PlatformException catch (e) {
      throw ConfigurationException(
        'Failed to set quality track: ${e.message ?? e.code}',
        parameter: 'qualityTrack',
        value: track.id,
        details: e.details as Map<String, dynamic>?,
      );
    }
  }

  /// Set audio track
  Future<void> setAudioTrack(AudioTrack track) async {
    await _ensureInitialized();

    // Validate track exists in available tracks
    if (!_audioTracks.any((t) => t.id == track.id)) {
      throw InvalidStateException(
        'Audio track not found: ${track.id}',
        currentState:
            'Available tracks: ${_audioTracks.map((t) => t.id).join(", ")}',
        requiredState: 'Valid track ID',
      );
    }

    try {
      await _channel.invokeMethod('setAudioTrack', {
        'playerId': playerId,
        'audioTrack': _audioTrackToMap(track),
      });

      _selectedAudioTrack = track;
      _updateAudioTracksSelection(track.id);
    } on PlatformException catch (e) {
      throw ConfigurationException(
        'Failed to set audio track: ${e.message ?? e.code}',
        parameter: 'audioTrack',
        value: track.id,
        details: e.details as Map<String, dynamic>?,
      );
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
      throw ConfigurationException(
        'Failed to enable auto quality: ${e.message ?? e.code}',
        parameter: 'autoQuality',
        value: true,
        details: e.details as Map<String, dynamic>?,
      );
    }
  }

  /// Check if Picture-in-Picture is available
  Future<bool> checkPipAvailability() async {
    await _ensureInitialized();

    try {
      debugPrint(
          'MediaPlayer: Checking PiP availability for player: $playerId');
      final result = await _channel.invokeMethod<bool>('checkPipAvailability', {
        'playerId': playerId,
        if (_config.pipConfig != null) 'config': _config.pipConfig!.toMap(),
      });

      debugPrint('MediaPlayer: PiP availability check result: $result');
      return result ?? false;
    } on PlatformException catch (e) {
      debugPrint(
          'MediaPlayer: Failed to check PiP availability: ${e.message ?? e.code}');
      debugPrint('MediaPlayer: Error details: ${e.details}');
      return false;
    }
  }

  /// Enter Picture-in-Picture mode
  Future<bool> enterPictureInPicture() async {
    await _ensureInitialized();

    if (!_pipStatus.isSupported) {
      throw const ConfigurationException(
        'Picture-in-Picture not supported on this device',
        parameter: 'pip',
        value: 'unavailable',
      );
    }

    try {
      final result =
          await _channel.invokeMethod<bool>('enterPictureInPicture', {
        'playerId': playerId,
        if (_config.pipConfig != null) 'config': _config.pipConfig!.toMap(),
      });

      return result ?? false;
    } on PlatformException catch (e) {
      throw PlatformOperationException(
        'Failed to enter PiP mode: ${e.message ?? e.code}',
        code: e.code,
        details: e.details as Map<String, dynamic>?,
      );
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
      throw PlatformOperationException(
        'Failed to exit PiP mode: ${e.message ?? e.code}',
        code: e.code,
        details: e.details as Map<String, dynamic>?,
      );
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
      throw PlatformOperationException(
        'Failed to start cast discovery: ${e.message ?? e.code}',
        code: e.code,
        details: e.details as Map<String, dynamic>?,
      );
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
      throw PlatformOperationException(
        'Failed to stop cast discovery: ${e.message ?? e.code}',
        code: e.code,
        details: e.details as Map<String, dynamic>?,
      );
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
      throw PlatformOperationException(
        'Failed to connect to cast device: ${e.message ?? e.code}',
        code: e.code,
        details: e.details as Map<String, dynamic>?,
      );
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
      throw PlatformOperationException(
        'Failed to disconnect from cast device: ${e.message ?? e.code}',
        code: e.code,
        details: e.details as Map<String, dynamic>?,
      );
    }
  }

  /// Load media on cast device
  Future<void> loadMediaOnCastDevice(MediaItem mediaItem) async {
    await _ensureInitialized();

    try {
      await _channel.invokeMethod('loadMediaOnCastDevice', {
        'playerId': playerId,
        'mediaItem': {
          'id': mediaItem.id,
          'title': mediaItem.title,
          'url': mediaItem.url,
          'artworkUrl': mediaItem.artworkUrl,
          'duration': mediaItem.duration?.inMilliseconds,
        },
      });
    } on PlatformException catch (e) {
      throw PlatformOperationException(
        'Failed to load media on cast device: ${e.message ?? e.code}',
        code: e.code,
        details: e.details as Map<String, dynamic>?,
      );
    }
  }

  /// Play on cast device
  Future<void> castPlay() async {
    await _ensureInitialized();

    try {
      await _channel.invokeMethod('castPlay', {
        'playerId': playerId,
      });
    } on PlatformException catch (e) {
      throw PlatformOperationException(
        'Failed to play on cast device: ${e.message ?? e.code}',
        code: e.code,
        details: e.details as Map<String, dynamic>?,
      );
    }
  }

  /// Pause on cast device
  Future<void> castPause() async {
    await _ensureInitialized();

    try {
      await _channel.invokeMethod('castPause', {
        'playerId': playerId,
      });
    } on PlatformException catch (e) {
      throw PlatformOperationException(
        'Failed to pause on cast device: ${e.message ?? e.code}',
        code: e.code,
        details: e.details as Map<String, dynamic>?,
      );
    }
  }

  /// Skip to next item in playlist
  Future<void> skipToNext() async {
    _validatePlaylistOperation();

    final nextIndex = _currentPlaylist!.nextIndex;
    if (nextIndex == null) {
      throw const InvalidStateException(
        'No next item available',
        currentState: 'At last item',
        requiredState: 'More items in playlist',
      );
    }

    await skipToIndex(nextIndex);
  }

  /// Skip to previous item in playlist
  Future<void> skipToPrevious() async {
    _validatePlaylistOperation();

    final previousIndex = _currentPlaylist!.previousIndex;
    if (previousIndex == null) {
      throw const InvalidStateException(
        'No previous item available',
        currentState: 'At first item',
        requiredState: 'More items in playlist',
      );
    }

    await skipToIndex(previousIndex);
  }

  /// Skip to specific index in playlist
  Future<void> skipToIndex(int index) async {
    _validatePlaylistOperation();

    if (index < 0 || index >= _currentPlaylist!.items.length) {
      throw ConfigurationException(
        'Invalid playlist index: $index',
        parameter: 'index',
        value: index,
        details: {'playlistLength': _currentPlaylist!.items.length},
      );
    }

    try {
      await _channel.invokeMethod('skipToIndex', {
        'playerId': playerId,
        'index': index,
      });

      _currentPlaylist = _currentPlaylist!.copyWith(currentIndex: index);
      _currentItem = _currentPlaylist!.items[index];
    } on PlatformException catch (e) {
      throw PlaybackException(
        'Failed to skip to index: ${e.message ?? e.code}',
        errorCode: e.code,
        details: e.details as Map<String, dynamic>?,
      );
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
        throw ConfigurationException(
          'Failed to update config: ${e.message ?? e.code}',
          parameter: 'config',
          value: config,
          details: e.details as Map<String, dynamic>?,
        );
      }
    }
  }

  /// Dispose the player and release resources
  Future<void> dispose() async {
    if (_isDisposed) return;

    _isDisposed = true;
    _instances.remove(playerId);
    _lastActivity.remove(playerId);

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

    // Dispose buffering service
    _bufferingService.dispose();

    // Close stream controllers safely
    await _safeCloseStreams();

    _isInitialized = false;
  }

  /// Safely close all stream controllers
  Future<void> _safeCloseStreams() async {
    final controllers = [
      _stateController,
      _positionController,
      _durationController,
      _volumeController,
      _speedController,
      _subtitleTracksController,
      _qualityTracksController,
      _audioTracksController,
      _bandwidthController,
      _bufferHealthController,
      _pipStatusController,
      _castStatusController,
      _castDevicesController,
      _drmSessionController,
      _notificationActionController,
    ];

    final errors = <String, dynamic>{};

    for (var i = 0; i < controllers.length; i++) {
      final controller = controllers[i];
      try {
        if (!controller.isClosed) {
          await controller.close();
        }
      } catch (e, stackTrace) {
        final controllerName = _getControllerName(i);
        errors[controllerName] = e.toString();
        debugPrint('Error closing $controllerName: $e');

        // Report to crash reporter if available (non-fatal)
        crashReporter?.reportError(
          e,
          stackTrace,
          context: {
            'playerId': playerId,
            'controller': controllerName,
            'operation': 'stream_cleanup',
          },
          fatal: false,
        );
      }
    }

    // Log summary if there were errors
    if (errors.isNotEmpty) {
      debugPrint(
        'MediaPlayer($playerId): Failed to close ${errors.length}/${controllers.length} controllers: ${errors.keys.join(", ")}',
      );
    }
  }

  /// Helper method for error reporting in stream cleanup
  String _getControllerName(int index) {
    const names = [
      'stateController',
      'positionController',
      'durationController',
      'volumeController',
      'speedController',
      'subtitleTracksController',
      'qualityTracksController',
      'audioTracksController',
      'bandwidthController',
      'pipStatusController',
      'castStatusController',
      'castDevicesController',
      'drmSessionController',
      'notificationActionController',
    ];
    return index < names.length ? names[index] : 'unknownController';
  }

  // Private helper methods

  /// Validate playlist operation
  void _validatePlaylistOperation() {
    _throwIfDisposed();
    if (_currentPlaylist == null) {
      throw const InvalidStateException(
        'No playlist set',
        currentState: 'No playlist',
        requiredState: 'Playlist loaded',
      );
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
      throw const PlayerDisposedException();
    }
  }

  /// Setup method call handler for platform events.
  ///
  /// Registers the static dispatch handler once at the class level, then
  /// routes each incoming call to the correct instance via playerId.
  void _setupMethodCallHandler() {
    if (!_channelHandlerRegistered) {
      _channelHandlerRegistered = true;
      _channel.setMethodCallHandler(_staticMethodCallHandler);
    }
  }

  /// Static handler registered once on the channel.
  /// Dispatches each call to the matching MediaPlayer instance.
  static Future<void> _staticMethodCallHandler(MethodCall call) async {
    final arguments = call.arguments as Map<dynamic, dynamic>?;
    final playerId = arguments?['playerId'] as String?;

    if (playerId == null) {
      debugPrint(
          'MediaPlayer: incoming call "${call.method}" missing playerId');
      return;
    }

    final instance = _instances[playerId];
    if (instance == null) {
      debugPrint(
          'MediaPlayer: no instance for playerId "$playerId" (call: ${call.method})');
      return;
    }

    await instance._handleMethodCall(call);
  }

  /// Handle method calls from platform for THIS instance.
  Future<void> _handleMethodCall(MethodCall call) async {
    final arguments = call.arguments as Map<dynamic, dynamic>?;

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
        case 'onNotificationAction':
          _handleNotificationAction(arguments!);
          break;
        case 'onBandwidthChanged':
          _handleBandwidthChanged(arguments!);
          break;
        case 'onDrmSessionUpdate':
          _handleDrmSessionUpdate(arguments!);
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
    final wasCompleted = _currentState.state == PlayerState.completed;

    _updateState(_currentState.copyWith(
      state: state,
      isBuffering: arguments['isBuffering'] as bool? ?? false,
      bufferPercentage:
          (arguments['bufferPercentage'] as num?)?.toDouble() ?? 0.0,
    ));

    // Auto-advance the playlist (respecting repeat/shuffle) when an item
    // finishes, or loop the current item when looping is enabled. Guarded by
    // wasCompleted so repeated 'completed' events don't advance more than once.
    if (state == PlayerState.completed && !wasCompleted) {
      _handlePlaybackCompleted();
    }
  }

  /// Called once when playback transitions into [PlayerState.completed].
  ///
  /// If a playlist is loaded and has a next index (per its repeat/shuffle
  /// rules), advances to it and plays. Otherwise, if [MediaConfig.looping] is
  /// enabled, restarts the current item.
  void _handlePlaybackCompleted() {
    if (_isDisposed) return;

    final playlist = _currentPlaylist;
    final nextIndex = playlist?.nextIndex;
    if (playlist != null && nextIndex != null) {
      skipToIndex(nextIndex).then((_) => play()).catchError(
            (Object e) => debugPrint('MediaPlayer: auto-advance failed: $e'),
          );
      return;
    }

    if (_config.looping) {
      seekTo(Duration.zero).then((_) => play()).catchError(
            (Object e) => debugPrint('MediaPlayer: loop restart failed: $e'),
          );
    }
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

    // Update isLive flag if provided
    if (arguments.containsKey('isLive')) {
      _isLive = arguments['isLive'] as bool? ?? false;
      debugPrint(
          'MediaPlayer: Duration changed - duration: ${duration.inMilliseconds}ms, isLive: $_isLive');
    } else {
      debugPrint(
          'MediaPlayer: Duration changed - duration: ${duration.inMilliseconds}ms, isLive key not found in arguments');
    }

    _updateState(_currentState.copyWith(duration: duration));

    if (!_durationController.isClosed) {
      _durationController.add(duration);
    }
  }

  /// Handle bandwidth change events from platform
  void _handleBandwidthChanged(Map<dynamic, dynamic> arguments) {
    if (_isDisposed) return;

    final bandwidth = arguments['bandwidth'] as int? ?? 0;
    _currentBandwidth = bandwidth;

    // Update buffering service with bandwidth measurement
    _bufferingService.updateFromBandwidth(bandwidth);

    if (!_bandwidthController.isClosed) {
      _bandwidthController.add(bandwidth);
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
      debugPrint(
          'MediaPlayer: Received ${tracksData.length} quality tracks from native');

      _qualityTracks = tracksData
          .cast<Map<dynamic, dynamic>>()
          .map((data) => _qualityTrackFromMap(Map<String, dynamic>.from(data)))
          .toList();

      debugPrint('MediaPlayer: Parsed quality tracks:');
      for (var track in _qualityTracks) {
        debugPrint(
            '  - ${track.name}: ${track.width}x${track.height}, ${track.bitrate} bps');
      }

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

  /// Handle DRM session update events from platform
  void _handleDrmSessionUpdate(Map<dynamic, dynamic> arguments) {
    if (_isDisposed) return;

    try {
      final session = DrmSession.fromMap(Map<String, dynamic>.from(arguments));

      if (!_drmSessionController.isClosed) {
        _drmSessionController.add(session);
      }
    } catch (e) {
      debugPrint('Error processing DRM session update: $e');
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
      debugPrint('MediaPlayer: Received PiP status from native: $statusMap');

      _pipStatus = PipStatus.fromMap(statusMap);

      if (!_pipStatusController.isClosed) {
        _pipStatusController.add(_pipStatus);
      }

      debugPrint(
          'PiP status changed: ${_pipStatus.state}, isSupported: ${_pipStatus.isSupported}, isActive: ${_pipStatus.isActive}, error: ${_pipStatus.errorMessage ?? "none"}');
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

  /// Handle notification action events from platform
  void _handleNotificationAction(Map<dynamic, dynamic> arguments) {
    if (_isDisposed) return;

    try {
      final action = arguments['action'] as String;

      if (!_notificationActionController.isClosed) {
        _notificationActionController.add(action);
      }

      debugPrint('Notification action received: $action');
    } catch (e) {
      debugPrint('Error processing notification action: $e');
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
