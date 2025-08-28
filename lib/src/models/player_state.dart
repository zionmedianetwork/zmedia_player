/// Represents the current state of the media player
enum PlayerState {
  /// Player is idle, no media loaded
  idle,

  /// Player is loading/buffering media
  buffering,

  /// Player is ready to play
  ready,

  /// Player is currently playing
  playing,

  /// Player is paused
  paused,

  /// Player has completed playback
  completed,

  /// Player encountered an error
  error,
}

/// Represents the current playback information
class PlaybackState {
  /// Current player state
  final PlayerState state;

  /// Current playback position
  final Duration position;

  /// Total duration of current media
  final Duration duration;

  /// Current playback speed
  final double speed;

  /// Current volume (0.0 to 1.0)
  final double volume;

  /// Whether the player is muted
  final bool isMuted;

  /// Whether the player is in buffering state
  final bool isBuffering;

  /// Current buffer percentage (0.0 to 1.0)
  final double bufferPercentage;

  /// Error message if state is error
  final String? errorMessage;

  const PlaybackState({
    required this.state,
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.speed = 1.0,
    this.volume = 1.0,
    this.isMuted = false,
    this.isBuffering = false,
    this.bufferPercentage = 0.0,
    this.errorMessage,
  });

  /// Creates a copy of this playback state with updated values
  PlaybackState copyWith({
    PlayerState? state,
    Duration? position,
    Duration? duration,
    double? speed,
    double? volume,
    bool? isMuted,
    bool? isBuffering,
    double? bufferPercentage,
    String? errorMessage,
  }) {
    return PlaybackState(
      state: state ?? this.state,
      position: position ?? this.position,
      duration: duration ?? this.duration,
      speed: speed ?? this.speed,
      volume: volume ?? this.volume,
      isMuted: isMuted ?? this.isMuted,
      isBuffering: isBuffering ?? this.isBuffering,
      bufferPercentage: bufferPercentage ?? this.bufferPercentage,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }

  /// Whether the player can play
  bool get canPlay => state == PlayerState.ready || state == PlayerState.paused;

  /// Whether the player can pause
  bool get canPause => state == PlayerState.playing;

  /// Whether the player can seek
  bool get canSeek =>
      state == PlayerState.ready ||
      state == PlayerState.playing ||
      state == PlayerState.paused;

  /// Progress percentage (0.0 to 1.0)
  double get progress {
    if (duration.inMilliseconds <= 0) return 0.0;
    return (position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0);
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is PlaybackState &&
        other.state == state &&
        other.position == position &&
        other.duration == duration &&
        other.speed == speed &&
        other.volume == volume &&
        other.isMuted == isMuted &&
        other.isBuffering == isBuffering &&
        other.bufferPercentage == bufferPercentage &&
        other.errorMessage == errorMessage;
  }

  @override
  int get hashCode {
    return Object.hash(
      state,
      position,
      duration,
      speed,
      volume,
      isMuted,
      isBuffering,
      bufferPercentage,
      errorMessage,
    );
  }

  @override
  String toString() {
    return 'PlaybackState(state: $state, position: $position, duration: $duration, speed: $speed)';
  }
}
