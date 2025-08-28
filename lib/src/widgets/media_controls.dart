import 'package:flutter/material.dart';
import '../core/media_controller.dart';
import '../models/player_state.dart';
import 'media_player_widget.dart';

/// Default media controls widget with play/pause, seek bar, and additional controls
class MediaControls extends StatefulWidget {
  /// Media controller for this controls widget
  final MediaController controller;

  /// Whether to show the fullscreen button
  final bool allowFullscreen;

  /// Whether to show subtitle controls
  final bool showSubtitleControls;

  /// Whether to show speed controls
  final bool showSpeedControls;

  /// Whether to show volume controls
  final bool showVolumeControls;

  /// Whether to show playlist navigation controls
  final bool showPlaylistControls;

  /// Custom color scheme for the controls
  final MediaControlsTheme? theme;

  const MediaControls({
    super.key,
    required this.controller,
    this.allowFullscreen = true,
    this.showSubtitleControls = true,
    this.showSpeedControls = true,
    this.showVolumeControls = true,
    this.showPlaylistControls = true,
    this.theme,
  });

  @override
  State<MediaControls> createState() => _MediaControlsState();
}

class _MediaControlsState extends State<MediaControls> {
  bool _showVolumeSlider = false;
  bool _showSpeedMenu = false;
  bool _showSubtitleMenu = false;

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme ?? MediaControlsTheme.defaultTheme;

    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, child) {
        return Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.transparent,
                Colors.black.withOpacity(0.3),
                Colors.black.withOpacity(0.7),
              ],
            ),
          ),
          child: Stack(
            children: [
              // Main controls
              _buildMainControls(theme),

              // Top controls
              _buildTopControls(theme),

              // Bottom controls
              _buildBottomControls(theme),

              // Overlays
              if (_showVolumeSlider) _buildVolumeOverlay(theme),
              if (_showSpeedMenu) _buildSpeedMenu(theme),
              if (_showSubtitleMenu) _buildSubtitleMenu(theme),
            ],
          ),
        );
      },
    );
  }

  Widget _buildMainControls(MediaControlsTheme theme) {
    return Center(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Previous track
          if (widget.showPlaylistControls && widget.controller.hasPrevious)
            IconButton(
              onPressed: widget.controller.skipToPrevious,
              icon: Icon(
                Icons.skip_previous,
                color: theme.iconColor,
                size: 32,
              ),
            ),

          const SizedBox(width: 16),

          // Seek backward
          IconButton(
            onPressed: () => widget.controller.seekBackward(),
            icon: Icon(
              Icons.replay_10,
              color: theme.iconColor,
              size: 32,
            ),
          ),

          const SizedBox(width: 16),

          // Play/Pause
          _buildPlayPauseButton(theme),

          const SizedBox(width: 16),

          // Seek forward
          IconButton(
            onPressed: () => widget.controller.seekForward(),
            icon: Icon(
              Icons.forward_10,
              color: theme.iconColor,
              size: 32,
            ),
          ),

          const SizedBox(width: 16),

          // Next track
          if (widget.showPlaylistControls && widget.controller.hasNext)
            IconButton(
              onPressed: widget.controller.skipToNext,
              icon: Icon(
                Icons.skip_next,
                color: theme.iconColor,
                size: 32,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildPlayPauseButton(MediaControlsTheme theme) {
    IconData iconData;
    VoidCallback? onPressed;

    switch (widget.controller.state.state) {
      case PlayerState.playing:
        iconData = Icons.pause_circle_filled;
        onPressed = widget.controller.pause;
        break;
      case PlayerState.paused:
      case PlayerState.ready:
      case PlayerState.completed:
        iconData = Icons.play_circle_filled;
        onPressed = widget.controller.play;
        break;
      case PlayerState.buffering:
        return SizedBox(
          width: 48,
          height: 48,
          child: CircularProgressIndicator(
            color: theme.iconColor,
            strokeWidth: 2,
          ),
        );
      default:
        iconData = Icons.play_circle_filled;
        onPressed = null;
    }

    return IconButton(
      onPressed: onPressed,
      icon: Icon(
        iconData,
        color: theme.iconColor,
        size: 48,
      ),
    );
  }

  Widget _buildTopControls(MediaControlsTheme theme) {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // Back button (for fullscreen)
              if (widget.allowFullscreen)
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: Icon(
                    Icons.arrow_back,
                    color: theme.iconColor,
                  ),
                ),

              const Spacer(),

              // Additional controls
              if (widget.showSubtitleControls &&
                  widget.controller.subtitleTracks.isNotEmpty)
                IconButton(
                  onPressed: _toggleSubtitleMenu,
                  icon: Icon(
                    Icons.subtitles,
                    color: widget.controller.selectedSubtitleTrack != null
                        ? theme.activeIconColor
                        : theme.iconColor,
                  ),
                ),

              if (widget.showSpeedControls)
                IconButton(
                  onPressed: _toggleSpeedMenu,
                  icon: Icon(
                    Icons.speed,
                    color: widget.controller.speed != 1.0
                        ? theme.activeIconColor
                        : theme.iconColor,
                  ),
                ),

              if (widget.showVolumeControls)
                IconButton(
                  onPressed: _toggleVolumeSlider,
                  icon: Icon(
                    widget.controller.isMuted
                        ? Icons.volume_off
                        : Icons.volume_up,
                    color: theme.iconColor,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBottomControls(MediaControlsTheme theme) {
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.transparent,
                Colors.black.withOpacity(0.7),
              ],
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Progress bar - Full width
                SizedBox(
                  width: double.infinity,
                  child: _buildProgressBar(theme),
                ),

                const SizedBox(height: 8),

                // Time and fullscreen controls
                Row(
                  children: [
                    // Current time
                    Text(
                      widget.controller.formattedPosition,
                      style: TextStyle(
                        color: theme.textColor,
                        fontSize: 12,
                      ),
                    ),

                    const Spacer(),

                    // Duration
                    Text(
                      widget.controller.formattedDuration,
                      style: TextStyle(
                        color: theme.textColor,
                        fontSize: 12,
                      ),
                    ),

                    const SizedBox(width: 8),

                    // Fullscreen toggle
                    if (widget.allowFullscreen)
                      IconButton(
                        onPressed: _toggleFullscreen,
                        icon: Icon(
                          Icons.fullscreen,
                          color: theme.iconColor,
                          size: 20,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildProgressBar(MediaControlsTheme theme) {
    return SliderTheme(
      data: SliderTheme.of(context).copyWith(
        trackHeight: 2,
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
        overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
        activeTrackColor: theme.progressColor,
        inactiveTrackColor: theme.progressBackgroundColor,
        thumbColor: theme.progressColor,
        overlayColor: theme.progressColor.withOpacity(0.2),
      ),
      child: Slider(
        value: widget.controller.progress,
        onChanged: (value) {
          final position = widget.controller.duration * value;
          widget.controller.seekTo(position);
        },
        onChangeStart: (value) {
          widget.controller.showControlsTemporarily();
        },
      ),
    );
  }

  Widget _buildVolumeOverlay(MediaControlsTheme theme) {
    return Positioned(
      right: 16,
      top: 60,
      child: Container(
        height: 150,
        width: 40,
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.8),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          children: [
            IconButton(
              onPressed: widget.controller.toggleMute,
              icon: Icon(
                widget.controller.isMuted ? Icons.volume_off : Icons.volume_up,
                color: theme.iconColor,
                size: 20,
              ),
            ),
            Expanded(
              child: RotatedBox(
                quarterTurns: 3,
                child: Slider(
                  value: widget.controller.isMuted
                      ? 0.0
                      : widget.controller.volume,
                  onChanged: (value) {
                    if (widget.controller.isMuted && value > 0) {
                      widget.controller.toggleMute();
                    }
                    widget.controller.setVolume(value);
                  },
                  activeColor: theme.progressColor,
                  inactiveColor: theme.progressBackgroundColor,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSpeedMenu(MediaControlsTheme theme) {
    const speeds = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0];

    return Positioned(
      right: 16,
      top: 60,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.8),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: speeds.map((speed) {
            final isSelected = widget.controller.speed == speed;
            return Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () {
                  widget.controller.setSpeed(speed);
                  _toggleSpeedMenu();
                },
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Text(
                    '${speed}x',
                    style: TextStyle(
                      color:
                          isSelected ? theme.activeIconColor : theme.textColor,
                      fontWeight:
                          isSelected ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildSubtitleMenu(MediaControlsTheme theme) {
    final tracks = [
      null, // Off option
      ...widget.controller.subtitleTracks,
    ];

    return Positioned(
      right: 16,
      top: 60,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.8),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: tracks.map((track) {
            final isSelected = track == null
                ? widget.controller.selectedSubtitleTrack == null
                : widget.controller.selectedSubtitleTrack?.id == track.id;

            return Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () {
                  widget.controller.setSubtitleTrack(track);
                  _toggleSubtitleMenu();
                },
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Text(
                    track?.title ?? 'Off',
                    style: TextStyle(
                      color:
                          isSelected ? theme.activeIconColor : theme.textColor,
                      fontWeight:
                          isSelected ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  void _toggleVolumeSlider() {
    setState(() {
      _showVolumeSlider = !_showVolumeSlider;
      _showSpeedMenu = false;
      _showSubtitleMenu = false;
    });
    widget.controller.showControlsTemporarily();
  }

  void _toggleSpeedMenu() {
    setState(() {
      _showSpeedMenu = !_showSpeedMenu;
      _showVolumeSlider = false;
      _showSubtitleMenu = false;
    });
    widget.controller.showControlsTemporarily();
  }

  void _toggleSubtitleMenu() {
    setState(() {
      _showSubtitleMenu = !_showSubtitleMenu;
      _showVolumeSlider = false;
      _showSpeedMenu = false;
    });
    widget.controller.showControlsTemporarily();
  }

  void _toggleFullscreen() {
    // Navigate to fullscreen player
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => _FullscreenPlayerRoute(
          controller: widget.controller,
        ),
      ),
    );
  }
}

/// Theme configuration for media controls
class MediaControlsTheme {
  /// Primary icon color
  final Color iconColor;

  /// Active/selected icon color
  final Color activeIconColor;

  /// Text color
  final Color textColor;

  /// Progress bar color
  final Color progressColor;

  /// Progress bar background color
  final Color progressBackgroundColor;

  /// Background color for overlays
  final Color overlayBackgroundColor;

  const MediaControlsTheme({
    this.iconColor = Colors.white,
    this.activeIconColor = Colors.blue,
    this.textColor = Colors.white,
    this.progressColor = Colors.blue,
    this.progressBackgroundColor = Colors.white24,
    this.overlayBackgroundColor = Colors.black54,
  });

  /// Default theme
  static const defaultTheme = MediaControlsTheme();

  /// Dark theme
  static const darkTheme = MediaControlsTheme(
    iconColor: Colors.white,
    activeIconColor: Colors.blue,
    textColor: Colors.white,
    progressColor: Colors.blue,
    progressBackgroundColor: Colors.white24,
  );

  /// Light theme
  static const lightTheme = MediaControlsTheme(
    iconColor: Colors.black87,
    activeIconColor: Colors.blue,
    textColor: Colors.black87,
    progressColor: Colors.blue,
    progressBackgroundColor: Colors.black26,
  );
}

/// Route for fullscreen player
class _FullscreenPlayerRoute extends StatefulWidget {
  final MediaController controller;

  const _FullscreenPlayerRoute({
    required this.controller,
  });

  @override
  State<_FullscreenPlayerRoute> createState() => _FullscreenPlayerRouteState();
}

class _FullscreenPlayerRouteState extends State<_FullscreenPlayerRoute> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            // Fullscreen header with exit button
            Container(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon:
                        const Icon(Icons.fullscreen_exit, color: Colors.white),
                    tooltip: 'Exit Fullscreen',
                  ),
                  const Spacer(),
                  const Text(
                    'Fullscreen Mode',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            // Video player in fullscreen
            Expanded(
              child: MediaPlayerWidget(
                controller: widget.controller,
                showControls: true,
                expandToFill: true,
                backgroundColor: Colors.black,
                onTap: () {
                  widget.controller.toggleControls();
                },
                onDoubleTap: () {
                  widget.controller.togglePlayPause();
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
