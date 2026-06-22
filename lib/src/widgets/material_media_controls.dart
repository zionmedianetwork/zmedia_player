import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/media_controller.dart';
import '../models/player_state.dart';
import '../models/buffer_health.dart';
import '../models/streaming_config.dart';
import 'components/seek_bar.dart';
import 'components/time_display.dart';
import 'components/live_badge.dart';
import 'components/quality_badge.dart';
import 'components/buffer_health_badge.dart';
import 'components/volume_slider.dart';
import 'menus/settings_menu.dart';
import 'media_player_widget.dart';

/// Material Design 3 media controls widget
///
/// Implements Material Design 3 design language with:
/// - Filled and tonal buttons
/// - Material color scheme integration
/// - Material motion system (standard easing)
/// - Elevation and shadows
/// - Material typography
/// - State layers for interactive elements
///
/// Example usage:
/// ```dart
/// MaterialMediaControls(
///   controller: mediaController,
///   title: 'Video Title',
/// )
/// ```
class MaterialMediaControls extends StatefulWidget {
  /// Media controller for this controls widget
  final MediaController controller;

  /// Whether to show the fullscreen button
  final bool showFullscreen;

  /// Whether to show settings button
  final bool showSettings;

  /// Whether to show PiP button
  final bool showPip;

  /// Custom title to display
  final String? title;

  /// Custom color scheme (defaults to Theme.of(context).colorScheme)
  final ColorScheme? colorScheme;

  const MaterialMediaControls({
    super.key,
    required this.controller,
    this.showFullscreen = true,
    this.showSettings = true,
    this.showPip = true,
    this.title,
    this.colorScheme,
  });

  @override
  State<MaterialMediaControls> createState() => _MaterialMediaControlsState();
}

class _MaterialMediaControlsState extends State<MaterialMediaControls>
    with SingleTickerProviderStateMixin {
  bool _showControls = true;
  bool _showVolumeSlider = false;
  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;
  BufferHealth? _currentBufferHealth;
  List<QualityTrack>? _qualityTracks;

  /// Local drag value for the position slider.
  /// Non-null while the user is dragging; null otherwise.
  double? _seekDragValue;

  StreamSubscription<BufferHealth>? _bufferHealthSubscription;
  StreamSubscription<List<QualityTrack>>? _qualityTracksSubscription;

  @override
  void initState() {
    super.initState();
    _initializeAnimations();
    _setupListeners();
  }

  void _setupListeners() {
    // Listen to buffer health updates — store subscription for cancellation
    _bufferHealthSubscription =
        widget.controller.player.bufferHealthStream.listen((health) {
      if (mounted) {
        setState(() {
          _currentBufferHealth = health;
        });
      }
    });

    // Listen to quality track updates — store subscription for cancellation
    _qualityTracksSubscription =
        widget.controller.player.qualityTracksStream.listen((tracks) {
      if (mounted) {
        setState(() {
          _qualityTracks = tracks;
        });
      }
    });
  }

  void _initializeAnimations() {
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeInOut, // Material motion: standard easing
    );
    _fadeController.forward();
  }

  @override
  void dispose() {
    _bufferHealthSubscription?.cancel();
    _qualityTracksSubscription?.cancel();
    _fadeController.dispose();
    super.dispose();
  }

  void _toggleControls() {
    setState(() {
      _showControls = !_showControls;
      if (_showControls) {
        _fadeController.forward();
      } else {
        _fadeController.reverse();
      }
    });
  }

  void _toggleSettings() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => SettingsMenu(
        controller: widget.controller,
        onSettingChanged: () {
          // Refresh UI if needed
          if (mounted) {
            setState(() {});
          }
        },
      ),
    );
  }

  void _toggleVolumeSlider() {
    setState(() {
      _showVolumeSlider = !_showVolumeSlider;
    });
    HapticFeedback.lightImpact();
  }

  void _toggleFullscreen() {
    HapticFeedback.mediumImpact();
    Navigator.of(context).push(
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) =>
            _FullscreenPlayerRoute(
          controller: widget.controller,
        ),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
        transitionDuration: const Duration(milliseconds: 300),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = widget.colorScheme ?? theme.colorScheme;
    final textTheme = theme.textTheme;

    return GestureDetector(
      onTap: _toggleControls,
      behavior: HitTestBehavior.opaque,
      child: Stack(
        children: [
          // Status badges (top-left corner)
          AnimatedBuilder(
            animation: widget.controller,
            builder: (context, child) {
              final isLive = widget.controller.currentItem?.isLive ?? false;
              final hasQualityTracks =
                  _qualityTracks != null && _qualityTracks!.isNotEmpty;
              final hasUnhealthyBuffer = _currentBufferHealth != null &&
                  !_currentBufferHealth!.isHealthy;

              // Only show badges if we have something to display
              if (!isLive && !hasQualityTracks && !hasUnhealthyBuffer) {
                return const SizedBox.shrink();
              }

              return Positioned(
                top: 16,
                left: 16,
                child: SafeArea(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // LIVE badge (for live streams)
                      if (isLive) ...[
                        LiveBadge(
                          isLive: isLive,
                          dvrAvailable:
                              false, // DVR info not available in current model
                          showDvrIndicator: false,
                          backgroundColor: Colors.black.withValues(alpha: 0.8),
                        ),
                        const SizedBox(width: 8),
                      ],

                      // Quality badge (show first quality track when available)
                      if (hasQualityTracks) ...[
                        QualityBadge(
                          qualityTrack: _qualityTracks!.first,
                          isAuto:
                              false, // Auto quality info not available in current implementation
                          backgroundColor: Colors.black.withValues(alpha: 0.8),
                          textColor: Colors.white,
                          borderColor: Colors.white.withValues(alpha: 0.3),
                        ),
                        const SizedBox(width: 8),
                      ],

                      // Buffer health badge (when buffering or unhealthy)
                      if (hasUnhealthyBuffer) ...[
                        BufferHealthBadge(
                          bufferHealth: _currentBufferHealth,
                          showPercentage: true,
                          showTooltip: true,
                        ),
                      ],
                    ],
                  ),
                ),
              );
            },
          ),

          // Volume overlay — shown above the bottom bar when toggled
          if (_showVolumeSlider)
            Positioned(
              left: 16,
              bottom: 96,
              child: AnimatedBuilder(
                animation: widget.controller,
                builder: (context, child) => VolumeSlider(
                  value: widget.controller.volume,
                  isMuted: widget.controller.isMuted,
                  onChanged: (value) => widget.controller.setVolume(value),
                  onMuteToggle: () => widget.controller.toggleMute(),
                  orientation: VolumeSliderOrientation.horizontal,
                  activeColor: Theme.of(context).colorScheme.primary,
                  sliderLength: 120,
                  showPercentage: false,
                ),
              ),
            ),

          // Main controls
          AnimatedBuilder(
            animation: _fadeAnimation,
            builder: (context, child) {
              return Opacity(
                opacity: _fadeAnimation.value,
                child: _showControls ? child : const SizedBox.shrink(),
              );
            },
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.7),
                    Colors.transparent,
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.7),
                  ],
                  stops: const [0.0, 0.2, 0.8, 1.0],
                ),
              ),
              child: Column(
                children: [
                  // Top bar with title and actions
                  _buildTopBar(colorScheme, textTheme),

                  const Spacer(),

                  // Center play/pause button
                  _buildCenterControls(colorScheme),

                  const Spacer(),

                  // Bottom bar with seek and controls
                  _buildBottomBar(colorScheme, textTheme),
                ],
              ),
            ),
          ),

          // Settings overlay removed - now using modal bottom sheet
        ],
      ),
    );
  }

  Widget _buildTopBar(ColorScheme colorScheme, TextTheme textTheme) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            // Title
            if (widget.title != null)
              Expanded(
                child: Text(
                  widget.title!,
                  style: textTheme.titleMedium?.copyWith(
                    color: colorScheme.onSurface,
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),

            const Spacer(),

            // PiP button
            if (widget.showPip)
              Semantics(
                button: true,
                label: 'Picture in picture',
                child: _buildM3IconButton(
                  icon: Icons.picture_in_picture_alt,
                  onPressed: () async {
                    await widget.controller.enterPictureInPicture();
                  },
                  tooltip: 'Picture in Picture',
                  colorScheme: colorScheme,
                ),
              ),

            const SizedBox(width: 8),

            // Settings button
            if (widget.showSettings)
              Semantics(
                button: true,
                label: 'Settings',
                child: _buildM3IconButton(
                  icon: Icons.settings,
                  onPressed: _toggleSettings,
                  tooltip: 'Settings',
                  colorScheme: colorScheme,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildCenterControls(ColorScheme colorScheme) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, child) {
        final state = widget.controller.state.state;
        final isPlaying = widget.controller.isPlaying;
        final isLoading = state == PlayerState.buffering;

        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Previous button
            _buildM3FilledButton(
              icon: Icons.skip_previous,
              onPressed: widget.controller.hasPrevious
                  ? () => widget.controller.skipToPrevious()
                  : null,
              colorScheme: colorScheme,
              size: 20,
            ),

            const SizedBox(width: 16),

            // Play/Pause button (large, elevated)
            Semantics(
              button: true,
              label: isPlaying ? 'Pause' : 'Play',
              child: Material(
                elevation: 6, // M3 elevation level 3
                shape: const CircleBorder(),
                color: colorScheme.primaryContainer,
                child: InkWell(
                  onTap: isLoading
                      ? null
                      : () {
                          if (isPlaying) {
                            widget.controller.pause();
                          } else {
                            widget.controller.play();
                          }
                        },
                  customBorder: const CircleBorder(),
                  child: Container(
                    width: 56,
                    height: 56,
                    alignment: Alignment.center,
                    child: isLoading
                        ? SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                              color: colorScheme.onPrimaryContainer,
                              strokeWidth: 2.5,
                            ),
                          )
                        : Icon(
                            isPlaying ? Icons.pause : Icons.play_arrow,
                            size: 32,
                            color: colorScheme.onPrimaryContainer,
                          ),
                  ),
                ),
              ),
            ),

            const SizedBox(width: 16),

            // Next button
            _buildM3FilledButton(
              icon: Icons.skip_next,
              onPressed: widget.controller.hasNext
                  ? () => widget.controller.skipToNext()
                  : null,
              colorScheme: colorScheme,
              size: 20,
            ),
          ],
        );
      },
    );
  }

  Widget _buildBottomBar(ColorScheme colorScheme, TextTheme textTheme) {
    // bottom:true SafeArea only — no top inset needed here.
    // Tighter vertical padding prevents RenderFlex overflow in landscape
    // where available height is ~320px after the top bar consumes ~56px.
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Seek bar with time OR live indicator
            AnimatedBuilder(
              animation: widget.controller,
              builder: (context, child) {
                final isLive = widget.controller.currentItem?.isLive ?? false;

                // For live streams, hide seek bar (LIVE badge shown separately)
                if (isLive) {
                  return const SizedBox.shrink();
                }

                // For non-live content, show seek bar
                final position = widget.controller.position;
                final duration = widget.controller.duration;
                final rawValue = duration.inMilliseconds > 0
                    ? position.inMilliseconds / duration.inMilliseconds
                    : 0.0;
                // While dragging, show the drag position in the time label;
                // after drag ends the controller position updates normally.
                final displayValue =
                    (_seekDragValue ?? rawValue).clamp(0.0, 1.0);
                final displayPosition = _seekDragValue != null
                    ? duration * _seekDragValue!
                    : position;

                return Row(
                  children: [
                    // Current time
                    TimeDisplay(
                      position: displayPosition,
                      format: TimeDisplayFormat.currentOnly,
                      style: textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurface,
                      ),
                    ),

                    const SizedBox(width: 12),

                    // Seek bar — seekTo fires once in onChangeEnd, not per drag frame
                    Expanded(
                      child: Semantics(
                        label: 'Seek',
                        value: widget.controller.formattedPosition,
                        child: SeekBar(
                          value: displayValue,
                          duration: duration,
                          onChanged: (newValue) {
                            // Update local drag state for visual feedback only —
                            // do NOT call seekTo here (would fire 60x/s during drag)
                            setState(() {
                              _seekDragValue = newValue;
                            });
                          },
                          onChangeEnd: (newValue) {
                            // Fire seekTo exactly once when the gesture ends
                            final seekTo = duration * newValue;
                            widget.controller.seekTo(seekTo);
                            setState(() {
                              _seekDragValue = null;
                            });
                          },
                          activeColor: colorScheme.primary,
                          inactiveColor:
                              colorScheme.onSurface.withValues(alpha: 0.3),
                          thumbColor: colorScheme.primary,
                          trackHeight: 4.0,
                          thumbRadius: 8.0,
                        ),
                      ),
                    ),

                    const SizedBox(width: 12),

                    // Total duration
                    TimeDisplay(
                      position: Duration.zero,
                      duration: duration,
                      format: TimeDisplayFormat.totalOnly,
                      style: textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurface,
                      ),
                    ),
                  ],
                );
              },
            ),

            const SizedBox(height: 8),

            // Control buttons row
            AnimatedBuilder(
              animation: widget.controller,
              builder: (context, child) {
                final isMuted = widget.controller.isMuted;
                final vol = widget.controller.volume;
                final IconData volumeIcon;
                if (isMuted || vol == 0.0) {
                  volumeIcon = Icons.volume_off;
                } else if (vol < 0.4) {
                  volumeIcon = Icons.volume_down;
                } else {
                  volumeIcon = Icons.volume_up;
                }
                return Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        // Volume button — toggles a horizontal VolumeSlider
                        // overlay anchored above the bottom bar.
                        _buildM3IconButton(
                          icon: volumeIcon,
                          onPressed: _toggleVolumeSlider,
                          tooltip: isMuted ? 'Unmute' : 'Volume',
                          colorScheme: colorScheme,
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        // Fullscreen button
                        if (widget.showFullscreen)
                          Semantics(
                            button: true,
                            label: 'Fullscreen',
                            child: _buildM3IconButton(
                              icon: Icons.fullscreen,
                              onPressed: _toggleFullscreen,
                              tooltip: 'Fullscreen',
                              colorScheme: colorScheme,
                            ),
                          ),
                      ],
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  /// Material 3 icon button with state layer
  Widget _buildM3IconButton({
    required IconData icon,
    required VoidCallback? onPressed,
    required String tooltip,
    required ColorScheme colorScheme,
  }) {
    return IconButton(
      icon: Icon(icon),
      onPressed: onPressed,
      tooltip: tooltip,
      color: colorScheme.onSurface,
      iconSize: 24,
      style: IconButton.styleFrom(
        backgroundColor:
            colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        foregroundColor: colorScheme.onSurface,
        disabledBackgroundColor:
            colorScheme.surfaceContainerHighest.withValues(alpha: 0.1),
        disabledForegroundColor: colorScheme.onSurface.withValues(alpha: 0.38),
      ),
    );
  }

  /// Material 3 filled button
  Widget _buildM3FilledButton({
    required IconData icon,
    required VoidCallback? onPressed,
    required ColorScheme colorScheme,
    double size = 24,
  }) {
    return Material(
      elevation: 2, // M3 elevation level 1
      shape: const CircleBorder(),
      color: colorScheme.secondaryContainer,
      child: InkWell(
        onTap: onPressed,
        customBorder: const CircleBorder(),
        child: Container(
          width: 48,
          height: 48,
          alignment: Alignment.center,
          child: Icon(
            icon,
            size: size,
            color: onPressed != null
                ? colorScheme.onSecondaryContainer
                : colorScheme.onSecondaryContainer.withValues(alpha: 0.38),
          ),
        ),
      ),
    );
  }
}

/// Private fullscreen route used by [MaterialMediaControls].
///
/// Mirrors the mechanism in MediaControls._toggleFullscreen: pushes a
/// PageRoute that forces landscape, hides system UI, and shows
/// [FullscreenMediaPlayer].  The controls' own top bar (rendered by
/// FullscreenMediaPlayer) owns the single header — no duplicate title or
/// dead PiP button are added here.
class _FullscreenPlayerRoute extends StatefulWidget {
  final MediaController controller;

  const _FullscreenPlayerRoute({required this.controller});

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
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

    _slideController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 1),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _slideController,
      curve: Curves.easeOutCubic,
    ));
    _slideController.forward();
  }

  @override
  void dispose() {
    _restoreSystemSettings();
    _slideController.dispose();
    super.dispose();
  }

  void _restoreSystemSettings() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
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
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (!didPop) await _exitFullscreen();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SlideTransition(
          position: _slideAnimation,
          child: FullscreenMediaPlayer(
            controller: widget.controller,
            backgroundColor: Colors.black,
          ),
        ),
      ),
    );
  }
}
