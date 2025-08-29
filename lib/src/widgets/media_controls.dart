import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/media_controller.dart';
import '../models/player_state.dart';
import 'media_player_widget.dart';

/// Modern media controls widget with enhanced UX and smooth animations
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

class _MediaControlsState extends State<MediaControls>
    with TickerProviderStateMixin {
  bool _showVolumeSlider = false;
  bool _showSpeedMenu = false;
  bool _showSubtitleMenu = false;
  bool _isDraggingProgress = false;
  double _dragValue = 0.0;

  late AnimationController _fadeController;
  late AnimationController _scaleController;
  late AnimationController _overlayController;
  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;
  late Animation<double> _overlayAnimation;

  @override
  void initState() {
    super.initState();
    _initializeAnimations();
  }

  void _initializeAnimations() {
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _scaleController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );
    _overlayController = AnimationController(
      duration: const Duration(milliseconds: 250),
      vsync: this,
    );

    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeInOut,
    );
    _scaleAnimation = CurvedAnimation(
      parent: _scaleController,
      curve: Curves.elasticOut,
    );
    _overlayAnimation = CurvedAnimation(
      parent: _overlayController,
      curve: Curves.easeOutBack,
    );

    _fadeController.forward();
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _scaleController.dispose();
    _overlayController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme ?? MediaControlsTheme.defaultTheme;

    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, child) {
        return FadeTransition(
          opacity: _fadeAnimation,
          child: Container(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment.center,
                radius: 1.5,
                colors: [
                  Colors.transparent,
                  Colors.black.withOpacity(0.1),
                  Colors.black.withOpacity(0.6),
                ],
              ),
            ),
            child: Stack(
              children: [
                // Gesture detector for tap to show/hide controls
                GestureDetector(
                  onTap: () => widget.controller.showControlsTemporarily(),
                  child: Container(
                    width: double.infinity,
                    height: double.infinity,
                    color: Colors.transparent,
                  ),
                ),

                // Main controls with glassmorphism effect
                _buildMainControls(theme),

                // Top controls with modern layout
                _buildTopControls(theme),

                // Bottom controls with enhanced design
                _buildBottomControls(theme),

                // Animated overlays
                if (_showVolumeSlider) _buildVolumeOverlay(theme),
                if (_showSpeedMenu) _buildSpeedMenu(theme),
                if (_showSubtitleMenu) _buildSubtitleMenu(theme),

                // Loading overlay
                if (widget.controller.state.state == PlayerState.buffering)
                  _buildBufferingOverlay(theme),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildMainControls(MediaControlsTheme theme) {
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.3),
          borderRadius: BorderRadius.circular(50),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.3),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Previous track with haptic feedback
            if (widget.showPlaylistControls && widget.controller.hasPrevious)
              _AnimatedIconButton(
                onPressed: () {
                  HapticFeedback.lightImpact();
                  widget.controller.skipToPrevious();
                },
                icon: Icons.skip_previous_rounded,
                color: theme.iconColor,
                size: 28,
                tooltip: 'Previous',
              ),

            if (widget.showPlaylistControls && widget.controller.hasPrevious)
              const SizedBox(width: 20),

            // Seek backward with custom animation
            _AnimatedIconButton(
              onPressed: () {
                HapticFeedback.selectionClick();
                widget.controller.seekBackward();
              },
              icon: Icons.replay_10_rounded,
              color: theme.iconColor,
              size: 32,
              tooltip: 'Rewind 10s',
            ),

            const SizedBox(width: 24),

            // Enhanced play/pause button
            _buildModernPlayPauseButton(theme),

            const SizedBox(width: 24),

            // Seek forward
            _AnimatedIconButton(
              onPressed: () {
                HapticFeedback.selectionClick();
                widget.controller.seekForward();
              },
              icon: Icons.forward_10_rounded,
              color: theme.iconColor,
              size: 32,
              tooltip: 'Forward 10s',
            ),

            if (widget.showPlaylistControls && widget.controller.hasNext)
              const SizedBox(width: 20),

            // Next track
            if (widget.showPlaylistControls && widget.controller.hasNext)
              _AnimatedIconButton(
                onPressed: () {
                  HapticFeedback.lightImpact();
                  widget.controller.skipToNext();
                },
                icon: Icons.skip_next_rounded,
                color: theme.iconColor,
                size: 28,
                tooltip: 'Next',
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildModernPlayPauseButton(MediaControlsTheme theme) {
    return ScaleTransition(
      scale: _scaleAnimation,
      child: GestureDetector(
        onTapDown: (_) => _scaleController.reverse(),
        onTapUp: (_) => _scaleController.forward(),
        onTapCancel: () => _scaleController.forward(),
        child: _buildPlayPauseButton(theme),
      ),
    );
  }

  Widget _buildPlayPauseButton(MediaControlsTheme theme) {
    Widget iconWidget;
    VoidCallback? onPressed;

    switch (widget.controller.state.state) {
      case PlayerState.playing:
        iconWidget = Icon(
          Icons.pause_circle_filled_rounded,
          color: theme.iconColor,
          size: 64,
        );
        onPressed = () {
          HapticFeedback.mediumImpact();
          widget.controller.pause();
        };
        break;
      case PlayerState.paused:
      case PlayerState.ready:
      case PlayerState.completed:
        iconWidget = Icon(
          Icons.play_circle_filled_rounded,
          color: theme.iconColor,
          size: 64,
        );
        onPressed = () {
          HapticFeedback.mediumImpact();
          widget.controller.play();
        };
        break;
      case PlayerState.buffering:
        return Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: theme.iconColor.withOpacity(0.1),
          ),
          child: Center(
            child: SizedBox(
              width: 32,
              height: 32,
              child: CircularProgressIndicator(
                color: theme.iconColor,
                strokeWidth: 3,
                strokeCap: StrokeCap.round,
              ),
            ),
          ),
        );
      default:
        iconWidget = Icon(
          Icons.play_circle_filled_rounded,
          color: theme.iconColor.withOpacity(0.5),
          size: 64,
        );
        onPressed = null;
    }

    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: theme.iconColor.withOpacity(0.3),
            blurRadius: 15,
            spreadRadius: 2,
          ),
        ],
      ),
      child: IconButton(
        onPressed: onPressed,
        icon: iconWidget,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(),
        tooltip: widget.controller.state.state == PlayerState.playing
            ? 'Pause'
            : 'Play',
      ),
    );
  }

  Widget _buildTopControls(MediaControlsTheme theme) {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.black.withOpacity(0.6),
                Colors.transparent,
              ],
            ),
          ),
          child: Row(
            children: [
              // Back button with modern styling
              if (widget.allowFullscreen)
                _ModernIconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: Icons.arrow_back_ios_rounded,
                  color: theme.iconColor,
                  backgroundColor: Colors.black.withOpacity(0.3),
                  tooltip: 'Back',
                ),

              const Spacer(),

              // Control buttons row
              Row(
                children: [
                  if (widget.showSubtitleControls &&
                      widget.controller.subtitleTracks.isNotEmpty)
                    _ModernIconButton(
                      onPressed: _toggleSubtitleMenu,
                      icon: Icons.closed_caption_rounded,
                      color: widget.controller.selectedSubtitleTrack != null
                          ? theme.activeIconColor
                          : theme.iconColor,
                      backgroundColor: Colors.black.withOpacity(0.3),
                      isActive: widget.controller.selectedSubtitleTrack != null,
                      tooltip: 'Subtitles',
                    ),
                  if (widget.showSubtitleControls &&
                      widget.controller.subtitleTracks.isNotEmpty)
                    const SizedBox(width: 12),
                  if (widget.showSpeedControls)
                    _ModernIconButton(
                      onPressed: _toggleSpeedMenu,
                      icon: Icons.speed_rounded,
                      color: widget.controller.speed != 1.0
                          ? theme.activeIconColor
                          : theme.iconColor,
                      backgroundColor: Colors.black.withOpacity(0.3),
                      isActive: widget.controller.speed != 1.0,
                      tooltip: 'Playback Speed',
                      badge: widget.controller.speed != 1.0
                          ? '${widget.controller.speed}x'
                          : null,
                    ),
                  if (widget.showSpeedControls) const SizedBox(width: 12),
                  if (widget.showVolumeControls)
                    _ModernIconButton(
                      onPressed: _toggleVolumeSlider,
                      icon: widget.controller.isMuted
                          ? Icons.volume_off_rounded
                          : _getVolumeIcon(widget.controller.volume),
                      color: theme.iconColor,
                      backgroundColor: Colors.black.withOpacity(0.3),
                      isActive: _showVolumeSlider,
                      tooltip: widget.controller.isMuted ? 'Unmute' : 'Volume',
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  IconData _getVolumeIcon(double volume) {
    if (volume > 0.6) return Icons.volume_up_rounded;
    if (volume > 0.3) return Icons.volume_down_rounded;
    if (volume > 0) return Icons.volume_mute_rounded;
    return Icons.volume_off_rounded;
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
                Colors.black.withOpacity(0.6),
              ],
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Enhanced progress bar
                _buildModernProgressBar(theme),

                const SizedBox(height: 12),

                // Time display and controls
                Row(
                  children: [
                    // Current time with modern styling
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.5),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        _isDraggingProgress
                            ? _formatDuration(
                                widget.controller.duration * _dragValue)
                            : widget.controller.formattedPosition,
                        style: TextStyle(
                          color: theme.textColor,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),

                    const Spacer(),

                    // Duration
                    Text(
                      widget.controller.formattedDuration,
                      style: TextStyle(
                        color: theme.textColor.withOpacity(0.8),
                        fontSize: 12,
                        fontWeight: FontWeight.w400,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),

                    const SizedBox(width: 12),

                    // Fullscreen toggle with modern design
                    if (widget.allowFullscreen)
                      _ModernIconButton(
                        onPressed: _toggleFullscreen,
                        icon: Icons.fullscreen_rounded,
                        color: theme.iconColor,
                        backgroundColor: Colors.black.withOpacity(0.3),
                        size: 20,
                        tooltip: 'Fullscreen',
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

  Widget _buildModernProgressBar(MediaControlsTheme theme) {
    final progress =
        _isDraggingProgress ? _dragValue : widget.controller.progress;

    return Container(
      height: 40,
      child: SliderTheme(
        data: SliderTheme.of(context).copyWith(
          trackHeight: 4,
          thumbShape: CustomSliderThumbShape(
            enabledThumbRadius: 8,
            color: theme.progressColor,
          ),
          overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
          activeTrackColor: theme.progressColor,
          inactiveTrackColor: theme.progressBackgroundColor,
          overlayColor: theme.progressColor.withOpacity(0.2),
          trackShape: CustomTrackShape(),
        ),
        child: Slider(
          value: progress,
          onChanged: (value) {
            setState(() {
              _isDraggingProgress = true;
              _dragValue = value;
            });
          },
          onChangeStart: (value) {
            setState(() => _isDraggingProgress = true);
            widget.controller.showControlsTemporarily();
            HapticFeedback.selectionClick();
          },
          onChangeEnd: (value) {
            final position = widget.controller.duration * value;
            widget.controller.seekTo(position);
            setState(() => _isDraggingProgress = false);
            HapticFeedback.lightImpact();
          },
        ),
      ),
    );
  }

  Widget _buildVolumeOverlay(MediaControlsTheme theme) {
    return SlideTransition(
      position: Tween<Offset>(
        begin: const Offset(1.5, 0),
        end: Offset.zero,
      ).animate(_overlayController),
      child: Positioned(
        right: 16,
        top: 80,
        child: Container(
          height: 180,
          width: 50,
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.8),
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.3),
                blurRadius: 15,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: Column(
            children: [
              const SizedBox(height: 8),
              IconButton(
                onPressed: () {
                  HapticFeedback.lightImpact();
                  widget.controller.toggleMute();
                },
                icon: Icon(
                  widget.controller.isMuted
                      ? Icons.volume_off_rounded
                      : _getVolumeIcon(widget.controller.volume),
                  color: theme.iconColor,
                  size: 20,
                ),
              ),
              Expanded(
                child: Container(
                  margin: const EdgeInsets.symmetric(vertical: 8),
                  child: RotatedBox(
                    quarterTurns: 3,
                    child: SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        trackHeight: 3,
                        thumbShape:
                            const RoundSliderThumbShape(enabledThumbRadius: 6),
                        activeTrackColor: theme.progressColor,
                        inactiveTrackColor: theme.progressBackgroundColor,
                      ),
                      child: Slider(
                        value: widget.controller.isMuted
                            ? 0.0
                            : widget.controller.volume,
                        onChanged: (value) {
                          if (widget.controller.isMuted && value > 0) {
                            widget.controller.toggleMute();
                          }
                          widget.controller.setVolume(value);
                          if (value > 0) HapticFeedback.selectionClick();
                        },
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSpeedMenu(MediaControlsTheme theme) {
    const speeds = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0];

    return FadeTransition(
      opacity: _overlayAnimation,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(1.5, 0),
          end: Offset.zero,
        ).animate(_overlayController),
        child: Positioned(
          right: 16,
          top: 80,
          child: Container(
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.9),
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.3),
                  blurRadius: 15,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: speeds.map((speed) {
                final isSelected = widget.controller.speed == speed;
                return Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () {
                      HapticFeedback.selectionClick();
                      widget.controller.setSpeed(speed);
                      _toggleSpeedMenu();
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 12),
                      decoration: isSelected
                          ? BoxDecoration(
                              color: theme.activeIconColor.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(8),
                            )
                          : null,
                      child: Text(
                        '${speed}x',
                        style: TextStyle(
                          color: isSelected
                              ? theme.activeIconColor
                              : theme.textColor,
                          fontWeight:
                              isSelected ? FontWeight.bold : FontWeight.normal,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSubtitleMenu(MediaControlsTheme theme) {
    final tracks = [
      null, // Off option
      ...widget.controller.subtitleTracks,
    ];

    return FadeTransition(
      opacity: _overlayAnimation,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(1.5, 0),
          end: Offset.zero,
        ).animate(_overlayController),
        child: Positioned(
          right: 16,
          top: 80,
          child: Container(
            constraints: const BoxConstraints(maxWidth: 200),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.9),
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.3),
                  blurRadius: 15,
                  offset: const Offset(0, 5),
                ),
              ],
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
                    borderRadius: BorderRadius.circular(8),
                    onTap: () {
                      HapticFeedback.selectionClick();
                      widget.controller.setSubtitleTrack(track);
                      _toggleSubtitleMenu();
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 12),
                      decoration: isSelected
                          ? BoxDecoration(
                              color: theme.activeIconColor.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(8),
                            )
                          : null,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (isSelected)
                            Icon(
                              Icons.check_circle_rounded,
                              color: theme.activeIconColor,
                              size: 16,
                            ),
                          if (isSelected) const SizedBox(width: 8),
                          Text(
                            track?.title ?? 'Off',
                            style: TextStyle(
                              color: isSelected
                                  ? theme.activeIconColor
                                  : theme.textColor,
                              fontWeight: isSelected
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBufferingOverlay(MediaControlsTheme theme) {
    return Center(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.6),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 32,
              height: 32,
              child: CircularProgressIndicator(
                color: theme.progressColor,
                strokeWidth: 3,
                strokeCap: StrokeCap.round,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Loading...',
              style: TextStyle(
                color: theme.textColor,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
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

    if (_showVolumeSlider) {
      _overlayController.forward();
    } else {
      _overlayController.reverse();
    }

    widget.controller.showControlsTemporarily();
    HapticFeedback.lightImpact();
  }

  void _toggleSpeedMenu() {
    setState(() {
      _showSpeedMenu = !_showSpeedMenu;
      _showVolumeSlider = false;
      _showSubtitleMenu = false;
    });

    if (_showSpeedMenu) {
      _overlayController.forward();
    } else {
      _overlayController.reverse();
    }

    widget.controller.showControlsTemporarily();
    HapticFeedback.lightImpact();
  }

  void _toggleSubtitleMenu() {
    setState(() {
      _showSubtitleMenu = !_showSubtitleMenu;
      _showVolumeSlider = false;
      _showSpeedMenu = false;
    });

    if (_showSubtitleMenu) {
      _overlayController.forward();
    } else {
      _overlayController.reverse();
    }

    widget.controller.showControlsTemporarily();
    HapticFeedback.lightImpact();
  }

  void _toggleFullscreen() {
    HapticFeedback.mediumImpact();
    Navigator.of(context).push(
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) =>
            _FullscreenPlayerRoute(controller: widget.controller),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
        transitionDuration: const Duration(milliseconds: 300),
      ),
    );
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, "0");
    String twoDigitMinutes = twoDigits(duration.inMinutes.remainder(60));
    String twoDigitSeconds = twoDigits(duration.inSeconds.remainder(60));

    if (duration.inHours > 0) {
      return "${twoDigits(duration.inHours)}:$twoDigitMinutes:$twoDigitSeconds";
    }
    return "$twoDigitMinutes:$twoDigitSeconds";
  }
}

// Custom animated icon button widget
class _AnimatedIconButton extends StatefulWidget {
  final VoidCallback? onPressed;
  final IconData icon;
  final Color color;
  final double size;
  final String? tooltip;

  const _AnimatedIconButton({
    required this.onPressed,
    required this.icon,
    required this.color,
    required this.size,
    this.tooltip,
  });

  @override
  State<_AnimatedIconButton> createState() => _AnimatedIconButtonState();
}

class _AnimatedIconButtonState extends State<_AnimatedIconButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 150),
      vsync: this,
    );
    _animation = Tween<double>(begin: 1.0, end: 0.9).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _controller.forward(),
      onTapUp: (_) => _controller.reverse(),
      onTapCancel: () => _controller.reverse(),
      child: ScaleTransition(
        scale: _animation,
        child: IconButton(
          onPressed: widget.onPressed,
          icon: Icon(
            widget.icon,
            color: widget.color,
            size: widget.size,
          ),
          tooltip: widget.tooltip,
        ),
      ),
    );
  }
}

// Modern icon button with background
class _ModernIconButton extends StatefulWidget {
  final VoidCallback? onPressed;
  final IconData icon;
  final Color color;
  final Color backgroundColor;
  final double size;
  final String? tooltip;
  final bool isActive;
  final String? badge;

  const _ModernIconButton({
    required this.onPressed,
    required this.icon,
    required this.color,
    required this.backgroundColor,
    this.size = 24,
    this.tooltip,
    this.isActive = false,
    this.badge,
  });

  @override
  State<_ModernIconButton> createState() => _ModernIconButtonState();
}

class _ModernIconButtonState extends State<_ModernIconButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _glowAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.95).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
    _glowAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _controller.forward(),
      onTapUp: (_) => _controller.reverse(),
      onTapCancel: () => _controller.reverse(),
      child: ScaleTransition(
        scale: _scaleAnimation,
        child: AnimatedBuilder(
          animation: _glowAnimation,
          builder: (context, child) {
            return Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: widget.backgroundColor,
                border: widget.isActive
                    ? Border.all(color: widget.color.withOpacity(0.5), width: 2)
                    : null,
                boxShadow: [
                  if (widget.isActive)
                    BoxShadow(
                      color: widget.color.withOpacity(0.3),
                      blurRadius: 8,
                      spreadRadius: 2,
                    ),
                  BoxShadow(
                    color: Colors.black
                        .withOpacity(0.2 + _glowAnimation.value * 0.1),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  IconButton(
                    onPressed: widget.onPressed,
                    icon: Icon(
                      widget.icon,
                      color: widget.color,
                      size: widget.size,
                    ),
                    tooltip: widget.tooltip,
                  ),
                  if (widget.badge != null)
                    Positioned(
                      right: 0,
                      top: 0,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: widget.color,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          widget.badge!,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

// Custom slider thumb shape
class CustomSliderThumbShape extends SliderComponentShape {
  final double enabledThumbRadius;
  final Color color;

  const CustomSliderThumbShape({
    required this.enabledThumbRadius,
    required this.color,
  });

  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) {
    return Size.fromRadius(enabledThumbRadius);
  }

  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    required bool isDiscrete,
    required TextPainter labelPainter,
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required TextDirection textDirection,
    required double value,
    required double textScaleFactor,
    required Size sizeWithOverflow,
  }) {
    final Canvas canvas = context.canvas;

    // Draw shadow
    final shadowPaint = Paint()
      ..color = Colors.black.withOpacity(0.3)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);

    canvas.drawCircle(
      center + const Offset(0, 2),
      enabledThumbRadius,
      shadowPaint,
    );

    // Draw thumb
    final thumbPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    canvas.drawCircle(center, enabledThumbRadius, thumbPaint);

    // Draw inner circle
    final innerPaint = Paint()
      ..color = Colors.white.withOpacity(0.3)
      ..style = PaintingStyle.fill;

    canvas.drawCircle(center, enabledThumbRadius * 0.4, innerPaint);
  }
}

// Custom track shape
class CustomTrackShape extends RoundedRectSliderTrackShape {
  @override
  void paint(
    PaintingContext context,
    Offset offset, {
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required Animation<double> enableAnimation,
    required TextDirection textDirection,
    required Offset thumbCenter,
    Offset? secondaryOffset,
    bool isDiscrete = false,
    bool isEnabled = true,
    double additionalActiveTrackHeight = 2,
  }) {
    final Rect trackRect = getPreferredRect(
      parentBox: parentBox,
      offset: offset,
      sliderTheme: sliderTheme,
      isEnabled: isEnabled,
      isDiscrete: isDiscrete,
    );

    final Canvas canvas = context.canvas;
    final radius = trackRect.height / 2;

    // Draw inactive track with shadow
    final inactiveTrackPaint = Paint()
      ..color = sliderTheme.inactiveTrackColor ?? Colors.grey
      ..style = PaintingStyle.fill;

    final shadowPaint = Paint()
      ..color = Colors.black.withOpacity(0.1)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2);

    final inactiveRRect = RRect.fromRectAndRadius(
      trackRect.translate(0, 1),
      Radius.circular(radius),
    );

    canvas.drawRRect(inactiveRRect, shadowPaint);
    canvas.drawRRect(
      RRect.fromRectAndRadius(trackRect, Radius.circular(radius)),
      inactiveTrackPaint,
    );

    // Draw active track with gradient
    final activeTrackRect = Rect.fromLTRB(
      trackRect.left,
      trackRect.top,
      thumbCenter.dx,
      trackRect.bottom,
    );

    final gradient = LinearGradient(
      colors: [
        sliderTheme.activeTrackColor ?? Colors.blue,
        (sliderTheme.activeTrackColor ?? Colors.blue).withOpacity(0.8),
      ],
    );

    final activeTrackPaint = Paint()
      ..shader = gradient.createShader(activeTrackRect)
      ..style = PaintingStyle.fill;

    canvas.drawRRect(
      RRect.fromRectAndRadius(activeTrackRect, Radius.circular(radius)),
      activeTrackPaint,
    );
  }
}

/// Enhanced theme configuration for media controls
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

  /// Accent color for highlights
  final Color accentColor;

  /// Surface color for cards and containers
  final Color surfaceColor;

  const MediaControlsTheme({
    this.iconColor = Colors.white,
    this.activeIconColor = const Color(0xFF00C9FF),
    this.textColor = Colors.white,
    this.progressColor = const Color(0xFF00C9FF),
    this.progressBackgroundColor = Colors.white24,
    this.overlayBackgroundColor = Colors.black54,
    this.accentColor = const Color(0xFF0099CC),
    this.surfaceColor = const Color(0xFF1E1E1E),
  });

  /// Default modern theme with gradient accents
  static const defaultTheme = MediaControlsTheme();

  /// Dark theme with blue accents
  static const darkTheme = MediaControlsTheme(
    iconColor: Colors.white,
    activeIconColor: Color(0xFF64B5F6),
    textColor: Colors.white,
    progressColor: Color(0xFF64B5F6),
    progressBackgroundColor: Colors.white24,
    accentColor: Color(0xFF42A5F5),
    surfaceColor: Color(0xFF212121),
  );

  /// Light theme
  static const lightTheme = MediaControlsTheme(
    iconColor: Colors.black87,
    activeIconColor: Color(0xFF1976D2),
    textColor: Colors.black87,
    progressColor: Color(0xFF1976D2),
    progressBackgroundColor: Colors.black26,
    overlayBackgroundColor: Colors.white70,
    accentColor: Color(0xFF1565C0),
    surfaceColor: Colors.white,
  );

  /// Gaming theme with neon accents
  static const gamingTheme = MediaControlsTheme(
    iconColor: Colors.white,
    activeIconColor: Color(0xFF00FF88),
    textColor: Colors.white,
    progressColor: Color(0xFF00FF88),
    progressBackgroundColor: Colors.white24,
    overlayBackgroundColor: Color(0xFF0A0A0A),
    accentColor: Color(0xFF00DD77),
    surfaceColor: Color(0xFF1A1A1A),
  );
}

/// Enhanced fullscreen player route with modern transitions
class _FullscreenPlayerRoute extends StatefulWidget {
  final MediaController controller;

  const _FullscreenPlayerRoute({
    required this.controller,
  });

  @override
  State<_FullscreenPlayerRoute> createState() => _FullscreenPlayerRouteState();
}

class _FullscreenPlayerRouteState extends State<_FullscreenPlayerRoute>
    with TickerProviderStateMixin {
  late AnimationController _slideController;
  late Animation<Offset> _slideAnimation;
  bool _isExiting = false;

  @override
  void initState() {
    super.initState();

    // Force landscape orientation for fullscreen
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);

    // Hide system UI for immersive experience
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersive);

    _slideController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, -1),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _slideController,
      curve: Curves.easeOutCubic,
    ));

    _slideController.forward();
  }

  @override
  void dispose() {
    // Restore system UI and orientation
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);

    _slideController.dispose();
    super.dispose();
  }

  Future<void> _exitFullscreen() async {
    if (_isExiting) return;

    setState(() => _isExiting = true);
    HapticFeedback.lightImpact();

    await _slideController.reverse();
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        await _exitFullscreen();
        return false;
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SlideTransition(
          position: _slideAnimation,
          child: Stack(
            children: [
              // Fullscreen video player
              Positioned.fill(
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
                    HapticFeedback.mediumImpact();
                  },
                ),
              ),

              // Enhanced fullscreen header
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withOpacity(0.7),
                        Colors.transparent,
                      ],
                    ),
                  ),
                  child: SafeArea(
                    child: Row(
                      children: [
                        // Modern exit button
                        Container(
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.5),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: IconButton(
                            onPressed: _exitFullscreen,
                            icon: const Icon(
                              Icons.fullscreen_exit_rounded,
                              color: Colors.white,
                            ),
                            tooltip: 'Exit Fullscreen',
                          ),
                        ),

                        const SizedBox(width: 16),

                        // Enhanced title with media info
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Fullscreen Mode',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              /*if (widget.controller.currentMediaTitle != null)
                                Text(
                                  widget.controller.currentMediaTitle!,
                                  style: TextStyle(
                                    color: Colors.white.withOpacity(0.8),
                                    fontSize: 14,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),*/
                            ],
                          ),
                        ),

                        // Additional controls
                        Row(
                          children: [
                            // Picture-in-picture button (if supported)
                            Container(
                              decoration: BoxDecoration(
                                color: Colors.black.withOpacity(0.5),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: IconButton(
                                onPressed: () {
                                  // Implement PiP functionality
                                  HapticFeedback.lightImpact();
                                },
                                icon: const Icon(
                                  Icons.picture_in_picture_rounded,
                                  color: Colors.white,
                                ),
                                tooltip: 'Picture in Picture',
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              // Gesture detector for swipe to exit
              Positioned.fill(
                child: GestureDetector(
                  onVerticalDragUpdate: (details) {
                    if (details.primaryDelta! > 10) {
                      _exitFullscreen();
                    }
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
