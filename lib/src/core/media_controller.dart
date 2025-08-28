import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/media_item.dart';
import '../models/player_state.dart';
import '../models/playlist.dart';
import '../models/subtitle_track.dart';
import 'media_player.dart';
import 'media_config.dart';

/// Controller class that provides a simplified interface for common media player operations
///
/// This class acts as a facade over MediaPlayer, providing commonly used functionality
/// in a more convenient API while following the Observer pattern for state management.
class MediaController extends ChangeNotifier {
  final MediaPlayer _player;

  /// Stream subscriptions for player events
  late final StreamSubscription<PlaybackState> _stateSubscription;
  late final StreamSubscription<Duration> _positionSubscription;
  late final StreamSubscription<Duration> _durationSubscription;
  late final StreamSubscription<List<SubtitleTrack>>
      _subtitleTracksSubscription;

  /// Current playback state
  PlaybackState _currentState = const PlaybackState(state: PlayerState.idle);

  /// Whether controls are currently visible
  bool _controlsVisible = true;

  /// Timer for auto-hiding controls
  Timer? _controlsTimer;

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

  /// Whether controls are visible
  bool get controlsVisible => _controlsVisible;

  /// Player configuration
  MediaConfig get config => _player.config;

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

  /// Initialize the controller and underlying player
  Future<void> initialize() async {
    await _player.initialize();
  }

  /// Load a single media item
  Future<void> load(MediaItem item) async {
    await _player.load(item);
  }

  /// Set and load a playlist
  Future<void> setPlaylist(Playlist playlist, {int? startIndex}) async {
    await _player.setPlaylist(playlist, startIndex: startIndex);
  }

  /// Toggle play/pause
  Future<void> togglePlayPause() async {
    if (isPlaying) {
      await pause();
    } else {
      await play();
    }
  }

  /// Start or resume playback
  Future<void> play() async {
    await _player.play();
    _showControlsTemporarily();
  }

  /// Pause playback
  Future<void> pause() async {
    await _player.pause();
    _showControls();
  }

  /// Stop playback
  Future<void> stop() async {
    await _player.stop();
    _showControls();
  }

  /// Seek to a specific position
  Future<void> seekTo(Duration position) async {
    await _player.seekTo(position);
    _showControlsTemporarily();
  }

  /// Seek forward by a specific duration
  Future<void> seekForward(
      [Duration duration = const Duration(seconds: 10)]) async {
    final newPosition = position + duration;
    final clampedPosition =
        newPosition > this.duration ? this.duration : newPosition;
    await seekTo(clampedPosition);
  }

  /// Seek backward by a specific duration
  Future<void> seekBackward(
      [Duration duration = const Duration(seconds: 10)]) async {
    final newPosition = position - duration;
    final clampedPosition =
        newPosition < Duration.zero ? Duration.zero : newPosition;
    await seekTo(clampedPosition);
  }

  /// Set volume (0.0 to 1.0)
  Future<void> setVolume(double volume) async {
    await _player.setVolume(volume);
    _showControlsTemporarily();
  }

  /// Increase volume by a specific amount
  Future<void> increaseVolume([double amount = 0.1]) async {
    final newVolume = (volume + amount).clamp(0.0, 1.0);
    await setVolume(newVolume);
  }

  /// Decrease volume by a specific amount
  Future<void> decreaseVolume([double amount = 0.1]) async {
    final newVolume = (volume - amount).clamp(0.0, 1.0);
    await setVolume(newVolume);
  }

  /// Toggle mute/unmute
  Future<void> toggleMute() async {
    await _player.setMuted(!isMuted);
    _showControlsTemporarily();
  }

  /// Set playback speed
  Future<void> setSpeed(double speed) async {
    await _player.setSpeed(speed);
    _showControlsTemporarily();
  }

  /// Cycle through common playback speeds
  Future<void> cycleSpeed() async {
    const speeds = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0];
    final currentIndex = speeds.indexOf(speed);
    final nextIndex = (currentIndex + 1) % speeds.length;
    await setSpeed(speeds[nextIndex]);
  }

  /// Skip to next track
  Future<void> skipToNext() async {
    await _player.skipToNext();
    _showControlsTemporarily();
  }

  /// Skip to previous track
  Future<void> skipToPrevious() async {
    await _player.skipToPrevious();
    _showControlsTemporarily();
  }

  /// Skip to specific index in playlist
  Future<void> skipToIndex(int index) async {
    await _player.skipToIndex(index);
    _showControlsTemporarily();
  }

  /// Set subtitle track
  Future<void> setSubtitleTrack(SubtitleTrack? track) async {
    await _player.setSubtitleTrack(track);
    _showControlsTemporarily();
  }

  /// Disable subtitles
  Future<void> disableSubtitles() async {
    await setSubtitleTrack(null);
  }

  /// Cycle through available subtitle tracks
  Future<void> cycleSubtitleTrack() async {
    if (subtitleTracks.isEmpty) return;

    int currentIndex = -1;
    if (selectedSubtitleTrack != null) {
      currentIndex = subtitleTracks
          .indexWhere((track) => track.id == selectedSubtitleTrack!.id);
    }

    final nextIndex = (currentIndex + 1) % (subtitleTracks.length + 1);
    if (nextIndex == subtitleTracks.length) {
      await disableSubtitles();
    } else {
      await setSubtitleTrack(subtitleTracks[nextIndex]);
    }
  }

  /// Show controls
  void showControls() {
    _showControls();
  }

  /// Hide controls
  void hideControls() {
    _hideControls();
  }

  /// Toggle controls visibility
  void toggleControls() {
    if (_controlsVisible) {
      hideControls();
    } else {
      showControls();
    }
  }

  /// Show controls temporarily (auto-hide after timeout)
  void showControlsTemporarily() {
    _showControlsTemporarily();
  }

  /// Force hide controls
  void forceHideControls() {
    _hideControls();
  }

  /// Update player configuration
  Future<void> updateConfig(MediaConfig config) async {
    await _player.updateConfig(config);
  }

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

  /// Setup stream subscriptions
  void _setupSubscriptions() {
    _stateSubscription = _player.stateStream.listen((state) {
      _currentState = state;
      notifyListeners();
    });

    // Position updates - only notify for significant changes to prevent flickering
    _positionSubscription = _player.positionStream.listen((position) {
      final oldPosition = _currentState.position;

      // Only update position if it's significantly different to prevent excessive updates
      if ((position - oldPosition).abs().inSeconds >= 1) {
        _currentState = _currentState.copyWith(position: position);
        notifyListeners();
      }
    });

    _durationSubscription = _player.durationStream.listen((duration) {
      if (_currentState.duration != duration) {
        _currentState = _currentState.copyWith(duration: duration);
        notifyListeners();
      }
    });

    _subtitleTracksSubscription = _player.subtitleTracksStream.listen((_) {
      notifyListeners();
    });
  }

  /// Show controls permanently
  void _showControls() {
    _controlsTimer?.cancel();
    if (!_controlsVisible) {
      _controlsVisible = true;
      notifyListeners();
    }
  }

  /// Hide controls
  void _hideControls() {
    _controlsTimer?.cancel();
    if (_controlsVisible) {
      _controlsVisible = false;
      notifyListeners();
    }
  }

  /// Show controls temporarily with auto-hide
  void _showControlsTemporarily() {
    _controlsTimer?.cancel();

    if (!_controlsVisible) {
      _controlsVisible = true;
      notifyListeners();
    }

    // Always set timer to auto-hide controls
    _controlsTimer = Timer(config.controlsTimeout, () {
      _hideControls();
    });
  }

  @override
  void dispose() {
    _controlsTimer?.cancel();
    _stateSubscription.cancel();
    _positionSubscription.cancel();
    _durationSubscription.cancel();
    _subtitleTracksSubscription.cancel();
    _player.dispose();
    super.dispose();
  }
}
