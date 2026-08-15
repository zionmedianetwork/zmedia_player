import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/media_item.dart';
import '../models/player_state.dart';
import '../models/playlist.dart';
import '../models/subtitle_track.dart';
import '../models/streaming_config.dart';
import '../models/pip_config.dart';
import '../models/cast_device.dart';
import 'media_player.dart';
import 'media_config.dart';
import 'exceptions.dart';

/// Controller class that provides a simplified interface for common media player operations
///
/// This class acts as a facade over MediaPlayer, providing commonly used functionality
/// in a more convenient API while following the Observer pattern for state management.
class MediaController extends ChangeNotifier {
  final MediaPlayer _player;

  /// Stream subscriptions for player events
  final List<StreamSubscription> _subscriptions = [];

  /// Current playback state
  PlaybackState _currentState = const PlaybackState(state: PlayerState.idle);

  /// Whether controls are currently visible
  bool _controlsVisible = false; // Start hidden, show on user interaction

  /// Timer for auto-hiding controls
  Timer? _controlsTimer;

  /// Whether the controller is disposed
  bool _isDisposed = false;

  /// Whether an operation is in progress (for preventing race conditions)
  bool _operationInProgress = false;

  /// When the current operation lock was acquired (used for staleness detection)
  DateTime? _operationStartedAt;

  /// How long before a held lock is considered stale (matches the
  /// .timeout() inside _executeOperation so they agree)
  static const Duration _operationTimeout = Duration(seconds: 10);

  /// Last position update time to prevent excessive notifications
  DateTime _lastPositionUpdate = DateTime.now();

  /// Minimum interval between position updates (in milliseconds)
  static const int _positionUpdateInterval = 500;

  /// Scoped, throttled position signal that fires independently of
  /// [notifyListeners].
  ///
  /// Position updates arrive from two native-event paths -- the dedicated
  /// `positionStream` and, because the native "position changed" bridge
  /// pushes an updated `PlaybackState` through `stateStream` on every tick
  /// too (see [MediaPlayer]'s `_handlePositionChanged`), also `stateStream`
  /// itself. Neither path calls [notifyListeners] for a position-only
  /// change (see [_isPositionOnlyChange]); both instead update this
  /// notifier, throttled the same way `_currentState.position` is (see
  /// [_shouldUpdatePosition]).
  ///
  /// Widgets that only need to react to playback position (seek bar, time
  /// display, subtitle cues) should listen to [positionListenable] instead
  /// of the whole controller, so that per-tick position updates (~2/sec)
  /// don't rebuild every listener attached to the controller (play/pause
  /// button, top bar, settings affordances, etc.) that has nothing to do
  /// with position.
  final ValueNotifier<Duration> _positionNotifier =
      ValueNotifier<Duration>(Duration.zero);

  /// See [_positionNotifier].
  ValueListenable<Duration> get positionListenable => _positionNotifier;

  /// Create a media controller with the given player instance
  MediaController(this._player) {
    _setupSubscriptions();
  }

  /// Create a media controller with optional configuration
  factory MediaController.create({
    String? playerId,
    MediaConfig? config,
  }) {
    final player = MediaPlayer(playerId: playerId, config: config);
    return MediaController(player);
  }

  /// Access to the underlying media player
  MediaPlayer get player => _player;

  /// Current playback state
  PlaybackState get state => _currentState;

  /// Current media item
  MediaItem? get currentItem => _player.currentItem;

  /// Current playlist
  Playlist? get currentPlaylist => _player.currentPlaylist;

  /// Available subtitle tracks
  List<SubtitleTrack> get subtitleTracks => _player.subtitleTracks;

  /// Currently selected subtitle track
  SubtitleTrack? get selectedSubtitleTrack => _player.selectedSubtitleTrack;

  /// Available quality tracks
  List<QualityTrack> get qualityTracks => _player.qualityTracks;

  /// Currently selected quality track
  QualityTrack? get selectedQualityTrack => _player.selectedQualityTrack;

  /// Available audio tracks
  List<AudioTrack> get audioTracks => _player.audioTracks;

  /// Currently selected audio track
  AudioTrack? get selectedAudioTrack => _player.selectedAudioTrack;

  /// Whether controls are visible
  bool get controlsVisible => _controlsVisible;

  /// Player configuration
  MediaConfig get config => _player.config;

  /// Whether the controller is disposed
  bool get isDisposed => _isDisposed;

  // Computed properties for common states
  /// Whether the player is currently playing
  bool get isPlaying => _currentState.state == PlayerState.playing;

  /// Whether the player is paused
  bool get isPaused => _currentState.state == PlayerState.paused;

  /// Whether the player is buffering
  bool get isBuffering => _currentState.isBuffering;

  /// Whether the player has an error
  bool get hasError => _currentState.state == PlayerState.error;

  /// Current position
  Duration get position => _currentState.position;

  /// Total duration
  Duration get duration => _currentState.duration;

  /// Current volume (0.0 to 1.0)
  double get volume => _currentState.volume;

  /// Current playback speed
  double get speed => _currentState.speed;

  /// Whether the player is muted
  bool get isMuted => _currentState.isMuted;

  /// Progress percentage (0.0 to 1.0)
  double get progress => _currentState.progress;

  /// Whether there's a next track available
  bool get hasNext => _player.currentPlaylist?.hasNext ?? false;

  /// Whether there's a previous track available
  bool get hasPrevious => _player.currentPlaylist?.hasPrevious ?? false;

  /// Whether the player is ready to play
  bool get isReady =>
      _currentState.state == PlayerState.ready ||
      _currentState.state == PlayerState.playing ||
      _currentState.state == PlayerState.paused;

  // Phase 3: Additional getters
  /// Player ID
  String get playerId => _player.playerId;

  /// Whether the player is initialized
  bool get isInitialized => _player.isInitialized;

  // Phase 3: PiP getters
  /// Stream of PiP status changes
  Stream<PipStatus> get pipStatusStream => _player.pipStatusStream;

  /// Current PiP status
  PipStatus get pipStatus => _player.pipStatus;

  /// Whether PiP is available on this device
  bool get isPipAvailable => _player.isPipAvailable;

  /// Whether currently in PiP mode
  bool get isInPipMode => _player.isInPipMode;

  // Phase 3: Cast getters
  /// Stream of cast status changes
  Stream<CastStatus> get castStatusStream => _player.castStatusStream;

  /// Current cast status
  CastStatus get castStatus => _player.castStatus;

  /// Whether casting is available
  bool get isCastAvailable => _player.isCastAvailable;

  /// Whether currently casting
  bool get isCasting => _player.isCasting;

  /// Initialize the controller and underlying player
  Future<void> initialize() async {
    if (_isDisposed) {
      throw StateError('Cannot initialize disposed MediaController');
    }

    try {
      await _executeOperation(() => _player.initialize());
    } catch (e) {
      debugPrint('MediaController: Error initializing player: $e');
      rethrow;
    }
  }

  /// Load a single media item
  Future<void> load(MediaItem item) async {
    if (_isDisposed) return;

    try {
      await _executeOperation(() => _player.load(item));
      // Don't show controls on load - let user interaction trigger them
    } catch (e) {
      debugPrint('MediaController: Error loading media item: $e');
      rethrow;
    }
  }

  /// Set and load a playlist
  Future<void> setPlaylist(Playlist playlist, {int? startIndex}) async {
    if (_isDisposed) return;

    try {
      await _executeOperation(
          () => _player.setPlaylist(playlist, startIndex: startIndex));
      // Don't show controls on load - let user interaction trigger them
    } catch (e) {
      debugPrint('MediaController: Error setting playlist: $e');
      rethrow;
    }
  }

  /// Toggle play/pause
  Future<void> togglePlayPause() async {
    if (_isDisposed) return;

    try {
      if (isPlaying) {
        await pause();
      } else {
        await play();
      }
    } catch (e) {
      debugPrint('MediaController: Error toggling play/pause: $e');
      // Reset operation state on error to prevent getting stuck
      _resetOperationState();
      rethrow;
    }
  }

  /// Start or resume playback
  Future<void> play() async {
    if (_isDisposed) return;

    try {
      await _executeOperation(() => _player.play());
      _showControlsTemporarily();
    } catch (e) {
      debugPrint('MediaController: Error starting playback: $e');
      // Reset operation state on error to prevent getting stuck
      _resetOperationState();
      rethrow;
    }
  }

  /// Pause playback
  Future<void> pause() async {
    if (_isDisposed) return;

    try {
      await _executeOperation(() => _player.pause());
      _showControls();
    } catch (e) {
      debugPrint('MediaController: Error pausing playback: $e');
      // Reset operation state on error to prevent getting stuck
      _resetOperationState();
      rethrow;
    }
  }

  /// Stop playback
  Future<void> stop() async {
    if (_isDisposed) return;

    try {
      await _executeOperation(() => _player.stop());
      _showControls();
    } catch (e) {
      debugPrint('MediaController: Error stopping playback: $e');
      rethrow;
    }
  }

  /// Seek to a specific position
  Future<void> seekTo(Duration position) async {
    if (_isDisposed) return;

    // Clamp position to valid range
    final clampedPosition = clampDuration(position, Duration.zero, duration);

    try {
      await _executeOperation(() => _player.seekTo(clampedPosition));
      _showControlsTemporarily();
    } catch (e) {
      debugPrint('MediaController: Error seeking to position: $e');
      rethrow;
    }
  }

  /// Seek forward by a specific duration
  Future<void> seekForward(
      [Duration duration = const Duration(seconds: 10)]) async {
    if (_isDisposed) return;

    final newPosition = position + duration;
    final clampedPosition =
        newPosition > this.duration ? this.duration : newPosition;
    await seekTo(clampedPosition);
  }

  /// Seek backward by a specific duration
  Future<void> seekBackward(
      [Duration duration = const Duration(seconds: 10)]) async {
    if (_isDisposed) return;

    final newPosition = position - duration;
    final clampedPosition =
        newPosition < Duration.zero ? Duration.zero : newPosition;
    await seekTo(clampedPosition);
  }

  /// Set volume (0.0 to 1.0)
  Future<void> setVolume(double volume) async {
    if (_isDisposed) return;

    // Clamp volume to valid range
    final clampedVolume = volume.clamp(0.0, 1.0);

    try {
      await _executeOperation(
        () => _player.setVolume(clampedVolume),
        isCritical: false,
      );
      _showControlsTemporarily();
    } catch (e) {
      debugPrint('MediaController: Error setting volume: $e');
      rethrow;
    }
  }

  /// Increase volume by a specific amount
  Future<void> increaseVolume([double amount = 0.1]) async {
    if (_isDisposed) return;

    final newVolume = (volume + amount).clamp(0.0, 1.0);
    await setVolume(newVolume);
  }

  /// Decrease volume by a specific amount
  Future<void> decreaseVolume([double amount = 0.1]) async {
    if (_isDisposed) return;

    final newVolume = (volume - amount).clamp(0.0, 1.0);
    await setVolume(newVolume);
  }

  /// Toggle mute/unmute
  Future<void> toggleMute() async {
    if (_isDisposed) return;

    try {
      await _executeOperation(
        () => _player.setMuted(!isMuted),
        isCritical: false,
      );
      _showControlsTemporarily();
    } catch (e) {
      debugPrint('MediaController: Error toggling mute: $e');
      rethrow;
    }
  }

  /// Set playback speed
  Future<void> setSpeed(double speed) async {
    if (_isDisposed) return;

    // Clamp speed to reasonable range
    final clampedSpeed = speed.clamp(0.1, 4.0);

    try {
      await _executeOperation(
        () => _player.setSpeed(clampedSpeed),
        isCritical: false,
      );
      _showControlsTemporarily();
    } catch (e) {
      debugPrint('MediaController: Error setting speed: $e');
      rethrow;
    }
  }

  /// Cycle through common playback speeds
  Future<void> cycleSpeed() async {
    if (_isDisposed) return;

    const speeds = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0];
    final currentIndex = speeds.indexOf(speed);
    final nextIndex =
        currentIndex == -1 ? 0 : (currentIndex + 1) % speeds.length;
    await setSpeed(speeds[nextIndex]);
  }

  /// Skip to next track
  Future<void> skipToNext() async {
    if (_isDisposed || !hasNext) return;

    try {
      await _executeOperation(() => _player.skipToNext());
      _showControlsTemporarily();
    } catch (e) {
      debugPrint('MediaController: Error skipping to next: $e');
      rethrow;
    }
  }

  /// Skip to previous track
  Future<void> skipToPrevious() async {
    if (_isDisposed || !hasPrevious) return;

    try {
      await _executeOperation(() => _player.skipToPrevious());
      _showControlsTemporarily();
    } catch (e) {
      debugPrint('MediaController: Error skipping to previous: $e');
      rethrow;
    }
  }

  /// Skip to specific index in playlist
  Future<void> skipToIndex(int index) async {
    if (_isDisposed) return;

    final playlist = currentPlaylist;
    if (playlist == null || index < 0 || index >= playlist.items.length) {
      throw ArgumentError('Invalid playlist index: $index');
    }

    try {
      await _executeOperation(() => _player.skipToIndex(index));
      _showControlsTemporarily();
    } catch (e) {
      debugPrint('MediaController: Error skipping to index: $e');
      rethrow;
    }
  }

  /// Set subtitle track
  Future<void> setSubtitleTrack(SubtitleTrack? track) async {
    if (_isDisposed) return;

    try {
      await _executeOperation(
        () => _player.setSubtitleTrack(track),
        isCritical: false,
      );
      _showControlsTemporarily();
    } catch (e) {
      debugPrint('MediaController: Error setting subtitle track: $e');
      rethrow;
    }
  }

  /// Disable subtitles
  Future<void> disableSubtitles() async {
    await setSubtitleTrack(null);
  }

  /// Cycle through available subtitle tracks
  Future<void> cycleSubtitleTrack() async {
    if (_isDisposed || subtitleTracks.isEmpty) return;

    try {
      int currentIndex = -1;
      if (selectedSubtitleTrack != null) {
        currentIndex = subtitleTracks.indexWhere(
          (track) => track.id == selectedSubtitleTrack!.id,
        );
      }

      final nextIndex = (currentIndex + 1) % (subtitleTracks.length + 1);
      if (nextIndex == subtitleTracks.length) {
        await disableSubtitles();
      } else {
        await setSubtitleTrack(subtitleTracks[nextIndex]);
      }
    } catch (e) {
      debugPrint('MediaController: Error cycling subtitle track: $e');
      rethrow;
    }
  }

  /// Set video quality track
  Future<void> setQualityTrack(QualityTrack track) async {
    if (_isDisposed) return;

    try {
      await _executeOperation(() => _player.setQualityTrack(track));
      _showControlsTemporarily();
    } catch (e) {
      debugPrint('MediaController: Error setting quality track: $e');
      rethrow;
    }
  }

  /// Enable automatic quality selection (adaptive bitrate)
  Future<void> enableAutoQuality() async {
    if (_isDisposed) return;

    try {
      await _executeOperation(() => _player.enableAutoQuality());
      _showControlsTemporarily();
    } catch (e) {
      debugPrint('MediaController: Error enabling auto quality: $e');
      rethrow;
    }
  }

  /// Set audio track
  Future<void> setAudioTrack(AudioTrack track) async {
    if (_isDisposed) return;

    try {
      await _executeOperation(() => _player.setAudioTrack(track));
      _showControlsTemporarily();
    } catch (e) {
      debugPrint('MediaController: Error setting audio track: $e');
      rethrow;
    }
  }

  // Control visibility methods
  /// Show controls
  void showControls() {
    if (_isDisposed) return;
    _showControls();
  }

  /// Hide controls
  void hideControls() {
    if (_isDisposed) return;
    _hideControls();
  }

  /// Toggle controls visibility
  void toggleControls() {
    if (_isDisposed) return;

    if (_controlsVisible) {
      hideControls();
    } else {
      showControlsTemporarily(); // Show with auto-hide
    }
  }

  /// Show controls temporarily (auto-hide after timeout)
  void showControlsTemporarily() {
    if (_isDisposed) return;
    _showControlsTemporarily();
  }

  /// Force hide controls
  void forceHideControls() {
    if (_isDisposed) return;
    _hideControls();
  }

  /// Update player configuration
  Future<void> updateConfig(MediaConfig config) async {
    if (_isDisposed) return;

    try {
      await _executeOperation(() => _player.updateConfig(config));
    } catch (e) {
      debugPrint('MediaController: Error updating config: $e');
      rethrow;
    }
  }

  // Utility methods
  /// Get formatted time string
  String formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);

    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:'
          '${minutes.toString().padLeft(2, '0')}:'
          '${seconds.toString().padLeft(2, '0')}';
    } else {
      return '${minutes.toString().padLeft(2, '0')}:'
          '${seconds.toString().padLeft(2, '0')}';
    }
  }

  /// Get current position as formatted string
  String get formattedPosition => formatDuration(position);

  /// Get total duration as formatted string
  String get formattedDuration => formatDuration(duration);

  /// Get remaining time as formatted string
  String get formattedRemainingTime => formatDuration(duration - position);

  /// Get buffered percentage (0.0 to 1.0)
  double get bufferedProgress {
    try {
      return _currentState.bufferedPosition.inMilliseconds /
          duration.inMilliseconds.clamp(1, double.maxFinite.toInt());
    } catch (e) {
      return 0.0;
    }
  }

  // Private methods

  /// Execute an operation with race condition protection.
  ///
  /// The lock is acquired before the operation starts and is ALWAYS released
  /// in a [finally] block — it can never get permanently stuck.  If the lock
  /// is already held we first check whether the holder has exceeded
  /// [_operationTimeout] (stale lock), and treat it as expired only if so.
  /// Non-critical operations ([isCritical] == false) that arrive while a
  /// fresh lock is held are rejected immediately with [OperationBusyException]
  /// rather than waiting; critical ones wait briefly.
  Future<T> _executeOperation<T>(
    Future<T> Function() operation, {
    bool isCritical = true,
  }) async {
    if (_operationInProgress) {
      // Check if the current lock is stale (exceeded the operation timeout).
      final started = _operationStartedAt;
      final isStale = started != null &&
          DateTime.now().difference(started) > _operationTimeout;

      if (isStale) {
        // The timeout handler inside the operation body already cleared the
        // flag, but defensively reset both fields here.
        debugPrint(
            'MediaController: Clearing stale lock (held > ${_operationTimeout.inSeconds}s)');
        _operationInProgress = false;
        _operationStartedAt = null;
      } else {
        // Lock is held by a live operation.
        await Future.delayed(const Duration(milliseconds: 100));

        if (_operationInProgress) {
          debugPrint(
              'MediaController: Operation in progress, skipping non-critical or queuing critical');
          if (!isCritical) {
            throw const OperationBusyException(
              'Non-critical operation skipped - another operation in progress',
            );
          }
          await Future.delayed(const Duration(milliseconds: 200));
          if (_operationInProgress) {
            throw StateError('Another operation is already in progress');
          }
        }
      }
    }

    _operationInProgress = true;
    _operationStartedAt = DateTime.now();
    try {
      return await operation().timeout(
        _operationTimeout,
        onTimeout: () {
          // Timeout handler clears the lock so subsequent calls are not
          // blocked; the finally below will also run and is a no-op.
          _operationInProgress = false;
          _operationStartedAt = null;
          throw TimeoutException(
              'Operation timed out after ${_operationTimeout.inSeconds} seconds');
        },
      );
    } catch (e) {
      debugPrint('MediaController: Operation failed: $e');
      rethrow;
    } finally {
      _operationInProgress = false;
      _operationStartedAt = null;
    }
  }

  /// Reset operation state (useful for recovery from stuck operations)
  void _resetOperationState() {
    if (_operationInProgress) {
      debugPrint('MediaController: Resetting stuck operation state');
      _operationInProgress = false;
    }
  }

  /// Public method to reset operation state (useful for recovery from stuck operations)
  void resetOperationState() {
    _resetOperationState();
  }

  /// Check if an operation is currently in progress
  bool get isOperationInProgress => _operationInProgress;

  /// Setup stream subscriptions with proper error handling
  void _setupSubscriptions() {
    try {
      // State stream subscription
      _subscriptions.add(
        _player.stateStream.listen(
          (state) {
            if (_isDisposed) return;

            // The native "position changed" bridge pushes an updated
            // PlaybackState through this same stateStream on every position
            // tick, not just on genuine state transitions (see MediaPlayer's
            // _handlePositionChanged). If every one of those pushes called
            // notifyListeners(), every listener on this controller
            // (play/pause button, top bar, settings affordances, etc.) would
            // rebuild on every ~500ms tick even though none of those fields
            // actually changed. Detect a position-only push and route it
            // through the throttled positionListenable instead of the
            // broad notifyListeners() sweep; only genuine state changes
            // notify listeners.
            if (_isPositionOnlyChange(state)) {
              if (_shouldUpdatePosition(state.position)) {
                _currentState = state;
                _positionNotifier.value = state.position;
              }
              return;
            }

            _currentState = state;
            _notifyListeners();
          },
          onError: (error) {
            debugPrint('MediaController: State stream error: $error');
          },
        ),
      );

      // Position stream subscription with throttling. Deliberately does NOT
      // call notifyListeners() -- see positionListenable's doc comment for
      // why position-only updates are scoped to their own listenable.
      _subscriptions.add(
        _player.positionStream.listen(
          (position) {
            if (!_isDisposed && _shouldUpdatePosition(position)) {
              _currentState = _currentState.copyWith(position: position);
              _positionNotifier.value = position;
            }
          },
          onError: (error) {
            debugPrint('MediaController: Position stream error: $error');
          },
        ),
      );

      // Duration stream subscription
      _subscriptions.add(
        _player.durationStream.listen(
          (duration) {
            if (!_isDisposed && _currentState.duration != duration) {
              _currentState = _currentState.copyWith(duration: duration);
              _notifyListeners();
            }
          },
          onError: (error) {
            debugPrint('MediaController: Duration stream error: $error');
          },
        ),
      );

      // Subtitle tracks stream subscription
      _subscriptions.add(
        _player.subtitleTracksStream.listen(
          (_) {
            if (!_isDisposed) {
              _notifyListeners();
            }
          },
          onError: (error) {
            debugPrint('MediaController: Subtitle tracks stream error: $error');
          },
        ),
      );

      // Quality tracks stream subscription
      _subscriptions.add(
        _player.qualityTracksStream.listen(
          (_) {
            if (!_isDisposed) {
              _notifyListeners();
            }
          },
          onError: (error) {
            debugPrint('MediaController: Quality tracks stream error: $error');
          },
        ),
      );

      // Audio tracks stream subscription
      _subscriptions.add(
        _player.audioTracksStream.listen(
          (_) {
            if (!_isDisposed) {
              _notifyListeners();
            }
          },
          onError: (error) {
            debugPrint('MediaController: Audio tracks stream error: $error');
          },
        ),
      );

      // Volume stream subscription
      _subscriptions.add(
        _player.volumeStream.listen(
          (_) {
            if (!_isDisposed) {
              _notifyListeners();
            }
          },
          onError: (error) {
            debugPrint('MediaController: Volume stream error: $error');
          },
        ),
      );

      // Speed stream subscription
      _subscriptions.add(
        _player.speedStream.listen(
          (_) {
            if (!_isDisposed) {
              _notifyListeners();
            }
          },
          onError: (error) {
            debugPrint('MediaController: Speed stream error: $error');
          },
        ),
      );
    } catch (e) {
      debugPrint('MediaController: Error setting up subscriptions: $e');
      rethrow;
    }
  }

  /// Returns true if [newState] differs from the current cached state only
  /// in its [PlaybackState.position] field.
  ///
  /// Used to detect the native "position changed" bridge riding through
  /// `stateStream` (see [MediaPlayer]'s `_handlePositionChanged`) so those
  /// pushes can be routed through [positionListenable] instead of a full
  /// [notifyListeners] sweep. Relies on [PlaybackState]'s field-wise `==`.
  bool _isPositionOnlyChange(PlaybackState newState) {
    return _currentState.copyWith(position: newState.position) == newState;
  }

  /// Check if position should be updated based on throttling
  bool _shouldUpdatePosition(Duration newPosition) {
    final now = DateTime.now();
    final timeDiff = now.difference(_lastPositionUpdate).inMilliseconds;
    final positionDiff =
        (newPosition - _currentState.position).abs().inMilliseconds;

    // Update if enough time has passed or if there's a significant position change
    if (timeDiff >= _positionUpdateInterval || positionDiff >= 1000) {
      _lastPositionUpdate = now;
      return true;
    }

    return false;
  }

  /// Notify listeners with error handling
  void _notifyListeners() {
    try {
      if (!_isDisposed) {
        notifyListeners();
      }
    } catch (e) {
      debugPrint('MediaController: Error notifying listeners: $e');
    }
  }

  /// Show controls permanently
  void _showControls() {
    _cancelControlsTimer();
    if (!_controlsVisible) {
      _controlsVisible = true;
      _notifyListeners();
    }
  }

  /// Hide controls
  void _hideControls() {
    _cancelControlsTimer();
    if (_controlsVisible) {
      _controlsVisible = false;
      _notifyListeners();
    }
  }

  /// Show controls temporarily with auto-hide
  void _showControlsTemporarily() {
    _cancelControlsTimer();

    if (!_controlsVisible) {
      _controlsVisible = true;
      _notifyListeners();
    }

    // Set timer to auto-hide controls
    _controlsTimer = Timer(config.controlsTimeout, () {
      if (!_isDisposed) {
        _hideControls();
      }
    });
  }

  /// Cancel controls timer safely
  void _cancelControlsTimer() {
    _controlsTimer?.cancel();
    _controlsTimer = null;
  }

  // Phase 3: PiP methods
  /// Check if Picture-in-Picture is available
  Future<bool> checkPipAvailability() async {
    return await _player.checkPipAvailability();
  }

  /// Enter Picture-in-Picture mode
  Future<void> enterPictureInPicture() async {
    await _player.enterPictureInPicture();
  }

  /// Exit Picture-in-Picture mode
  Future<void> exitPictureInPicture() async {
    await _player.exitPictureInPicture();
  }

  // Phase 3: Cast methods
  /// Start discovering cast devices
  Future<void> startCastDiscovery() async {
    await _player.startCastDiscovery();
  }

  /// Stop discovering cast devices
  Future<void> stopCastDiscovery() async {
    await _player.stopCastDiscovery();
  }

  /// Connect to a cast device
  Future<void> connectToCastDevice(CastDevice device) async {
    await _player.connectToCastDevice(device);
  }

  /// Connect to a cast device and automatically load current media
  Future<void> connectAndLoadMedia(CastDevice device) async {
    debugPrint('=== MediaController: Connecting and loading media ===');

    // Store current playback position before pausing
    final currentPosition = position;
    final wasPlaying = isPlaying;

    debugPrint(
        'Current position: ${currentPosition.inSeconds}s, was playing: $wasPlaying');

    // Pause local playback before casting
    if (wasPlaying) {
      debugPrint('Pausing local playback...');
      await pause();
    }

    // Connect to the device
    debugPrint('Connecting to Cast device: ${device.name}');
    await _player.connectToCastDevice(device);

    // Load and play current media if available
    if (currentItem != null) {
      try {
        // Wait for Cast session to fully establish (session connects asynchronously)
        debugPrint('Waiting for Cast session to establish...');
        await Future.delayed(const Duration(milliseconds: 2000));

        debugPrint('Loading media on Cast device: ${currentItem!.title}');
        // Native code will wait for remote media client to be ready
        // Autoplay is enabled, so no need to call castPlay()
        await _player.loadMediaOnCastDevice(currentItem!);

        debugPrint('✓ Media successfully cast to ${device.name}');
      } catch (e) {
        debugPrint('✗ Failed to load media on Cast device: $e');
        // Resume local playback if casting fails
        if (wasPlaying) {
          await play();
        }
      }
    } else {
      debugPrint('No media item to cast');
    }

    debugPrint('=== Cast connection completed ===');
  }

  /// Disconnect from cast device
  Future<void> disconnectFromCastDevice() async {
    await _player.disconnectFromCastDevice();
  }

  /// Clean up all subscriptions with error handling
  void _cleanupSubscriptions() {
    final errors = <int, dynamic>{};

    for (var i = 0; i < _subscriptions.length; i++) {
      try {
        _subscriptions[i].cancel();
      } catch (e, stackTrace) {
        errors[i] = e.toString();
        debugPrint('MediaController: Error canceling subscription $i: $e');

        // Report to crash reporter if available (non-fatal)
        MediaPlayer.crashReporter?.reportError(
          e,
          stackTrace,
          context: {
            'controller': 'MediaController',
            'subscriptionIndex': i,
            'operation': 'subscription_cleanup',
          },
          fatal: false,
        );
      }
    }

    _subscriptions.clear();

    // Log summary if there were errors
    if (errors.isNotEmpty) {
      debugPrint(
        'MediaController: Failed to cancel ${errors.length}/${_subscriptions.length} subscriptions',
      );
    }
  }

  @override
  void dispose() {
    if (_isDisposed) return;

    _isDisposed = true;

    // Reset operation state
    _resetOperationState();

    // Cancel timers
    _cancelControlsTimer();

    // Cancel all subscriptions
    _cleanupSubscriptions();

    // Dispose the scoped position listenable
    _positionNotifier.dispose();

    // Dispose player
    try {
      _player.dispose();
    } catch (e) {
      debugPrint('MediaController: Error disposing player: $e');
    }

    super.dispose();
  }
}

Duration clampDuration(Duration duration, Duration min, Duration max) {
  if (duration.compareTo(min) < 0) {
    return min;
  }
  if (duration.compareTo(max) > 0) {
    return max;
  }
  return duration;
}
