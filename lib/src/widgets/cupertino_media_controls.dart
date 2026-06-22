import 'dart:async';
import 'dart:ui';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show Colors;
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

/// Cupertino (iOS) media controls widget
///
/// Implements iOS design language with:
/// - Translucent blur effects (BackdropFilter)
/// - iOS-style sliders and buttons
/// - CupertinoActionSheet for menus
/// - SF Pro typography (San Francisco)
/// - Minimal shadows and lightweight design
/// - Smooth iOS animations
///
/// Example usage:
/// ```dart
/// CupertinoMediaControls(
///   controller: mediaController,
///   title: 'Video Title',
/// )
/// ```
class CupertinoMediaControls extends StatefulWidget {
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

  /// Custom iOS brightness (light/dark)
  final Brightness? brightness;

  const CupertinoMediaControls({
    super.key,
    required this.controller,
    this.showFullscreen = true,
    this.showSettings = true,
    this.showPip = true,
    this.title,
    this.brightness,
  });

  @override
  State<CupertinoMediaControls> createState() => _CupertinoMediaControlsState();
}

class _CupertinoMediaControlsState extends State<CupertinoMediaControls>
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
      curve: Curves.easeInOut, // iOS standard easing
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
    showCupertinoModalPopup(
      context: context,
      builder: (context) => Container(
        decoration: const BoxDecoration(
          color: Colors.transparent,
        ),
        child: SettingsMenu(
          controller: widget.controller,
          onSettingChanged: () {
            // Refresh UI if needed
            if (mounted) {
              setState(() {});
            }
          },
        ),
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
            _CupertinoFullscreenPlayerRoute(
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
    final brightness = widget.brightness ?? Brightness.dark;
    final isDark = brightness == Brightness.dark;
    final textColor = isDark ? CupertinoColors.white : CupertinoColors.black;

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
                          backgroundColor:
                              CupertinoColors.black.withValues(alpha: 0.8),
                          textColor: CupertinoColors.white,
                        ),
                        const SizedBox(width: 8),
                      ],

                      // Quality badge (show first quality track when available)
                      if (hasQualityTracks) ...[
                        QualityBadge(
                          qualityTrack: _qualityTracks!.first,
                          isAuto:
                              false, // Auto quality info not available in current implementation
                          backgroundColor:
                              CupertinoColors.black.withValues(alpha: 0.8),
                          textColor: CupertinoColors.white,
                          borderColor:
                              CupertinoColors.white.withValues(alpha: 0.3),
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
                  activeColor: CupertinoColors.white,
                  sliderLength: 120,
                  showPercentage: false,
                ),
              ),
            ),

          // Main controls with blur background
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
                    CupertinoColors.black.withValues(alpha: 0.5),
                    Colors.transparent,
                    Colors.transparent,
                    CupertinoColors.black.withValues(alpha: 0.5),
                  ],
                  stops: const [0.0, 0.2, 0.8, 1.0],
                ),
              ),
              child: Column(
                children: [
                  // Top bar with title and actions
                  _buildTopBar(textColor),

                  const Spacer(),

                  // Center play/pause button
                  _buildCenterControls(),

                  const Spacer(),

                  // Bottom bar with seek and controls
                  _buildBottomBar(textColor),
                ],
              ),
            ),
          ),

          // Settings overlay removed - now using modal popup
        ],
      ),
    );
  }

  Widget _buildTopBar(Color textColor) {
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          decoration: BoxDecoration(
            color: CupertinoColors.black.withValues(alpha: 0.2),
          ),
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              child: Row(
                children: [
                  // Title
                  if (widget.title != null)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: Text(
                          widget.title!,
                          style: TextStyle(
                            color: textColor,
                            fontSize: 17, // iOS standard font size
                            fontWeight: FontWeight.w600, // SF Pro Semibold
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),

                  const Spacer(),

                  // PiP button
                  if (widget.showPip)
                    Semantics(
                      button: true,
                      label: 'Picture in picture',
                      child: _buildIOSButton(
                        icon: CupertinoIcons.rectangle_on_rectangle,
                        onPressed: () async {
                          await widget.controller.enterPictureInPicture();
                        },
                      ),
                    ),

                  const SizedBox(width: 8),

                  // Settings button
                  if (widget.showSettings)
                    Semantics(
                      button: true,
                      label: 'Settings',
                      child: _buildIOSButton(
                        icon: CupertinoIcons.settings,
                        onPressed: _toggleSettings,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCenterControls() {
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
            _buildIOSControlButton(
              icon: CupertinoIcons.backward_fill,
              onPressed: widget.controller.hasPrevious
                  ? () => widget.controller.skipToPrevious()
                  : null,
              size: 24,
            ),

            const SizedBox(width: 16),

            // Play/Pause button (large, with blur)
            Semantics(
              button: true,
              label: isPlaying ? 'Pause' : 'Play',
              child: ClipOval(
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                  child: Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: CupertinoColors.white.withValues(alpha: 0.25),
                      border: Border.all(
                        color: CupertinoColors.white.withValues(alpha: 0.5),
                        width: 1,
                      ),
                    ),
                    child: CupertinoButton(
                      padding: EdgeInsets.zero,
                      onPressed: isLoading
                          ? null
                          : () {
                              if (isPlaying) {
                                widget.controller.pause();
                              } else {
                                widget.controller.play();
                              }
                            },
                      child: isLoading
                          ? const CupertinoActivityIndicator(
                              color: CupertinoColors.white,
                              radius: 12,
                            )
                          : Icon(
                              isPlaying
                                  ? CupertinoIcons.pause_fill
                                  : CupertinoIcons.play_fill,
                              size: 28,
                              color: CupertinoColors.white,
                            ),
                    ),
                  ),
                ),
              ),
            ),

            const SizedBox(width: 16),

            // Next button
            _buildIOSControlButton(
              icon: CupertinoIcons.forward_fill,
              onPressed: widget.controller.hasNext
                  ? () => widget.controller.skipToNext()
                  : null,
              size: 24,
            ),
          ],
        );
      },
    );
  }

  Widget _buildBottomBar(Color textColor) {
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          decoration: BoxDecoration(
            color: CupertinoColors.black.withValues(alpha: 0.2),
          ),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Seek bar with time
                  AnimatedBuilder(
                    animation: widget.controller,
                    builder: (context, child) {
                      final isLive =
                          widget.controller.currentItem?.isLive ?? false;

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
                      // While dragging, show drag position in the time label
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
                            style: TextStyle(
                              color: textColor,
                              fontSize: 13,
                              fontWeight: FontWeight.w400,
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
                                activeColor: CupertinoColors.white,
                                inactiveColor: CupertinoColors.white
                                    .withValues(alpha: 0.3),
                                thumbColor: CupertinoColors.white,
                                trackHeight: 3.0,
                                thumbRadius: 7.0,
                              ),
                            ),
                          ),

                          const SizedBox(width: 12),

                          // Total duration
                          TimeDisplay(
                            position: Duration.zero,
                            duration: duration,
                            format: TimeDisplayFormat.totalOnly,
                            style: TextStyle(
                              color: textColor,
                              fontSize: 13,
                              fontWeight: FontWeight.w400,
                            ),
                          ),
                        ],
                      );
                    },
                  ),

                  const SizedBox(height: 16),

                  // Control buttons row
                  AnimatedBuilder(
                    animation: widget.controller,
                    builder: (context, child) {
                      final isMuted = widget.controller.isMuted;
                      final vol = widget.controller.volume;
                      final IconData volumeIcon;
                      if (isMuted || vol == 0.0) {
                        volumeIcon = CupertinoIcons.speaker_slash_fill;
                      } else if (vol < 0.4) {
                        volumeIcon = CupertinoIcons.speaker_1_fill;
                      } else {
                        volumeIcon = CupertinoIcons.speaker_2_fill;
                      }
                      return Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              // Volume button — toggles a horizontal VolumeSlider
                              // overlay anchored above the bottom bar.
                              _buildIOSButton(
                                icon: volumeIcon,
                                onPressed: _toggleVolumeSlider,
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
                                  child: _buildIOSButton(
                                    icon: CupertinoIcons.fullscreen,
                                    onPressed: _toggleFullscreen,
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
          ),
        ),
      ),
    );
  }

  /// iOS-style button with minimum 48x48 touch target
  Widget _buildIOSButton({
    required IconData icon,
    required VoidCallback? onPressed,
  }) {
    // Padding is sized so the button's tap target is at least 48×48 logical px.
    // The icon is 22px; adding 13px on each side yields 22+26 = 48px.
    // minimumSize: Size.zero is intentionally omitted to restore the default
    // (44pt on iOS / 48dp on Material), ensuring WCAG touch-target compliance.
    return CupertinoButton(
      padding: const EdgeInsets.all(13),
      onPressed: onPressed,
      child: Icon(
        icon,
        color: onPressed != null
            ? CupertinoColors.white
            : CupertinoColors.white.withValues(alpha: 0.4),
        size: 22,
      ),
    );
  }

  /// iOS-style control button with blur background
  Widget _buildIOSControlButton({
    required IconData icon,
    required VoidCallback? onPressed,
    double size = 24,
  }) {
    return ClipOval(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: CupertinoColors.white.withValues(alpha: 0.25),
            border: Border.all(
              color: CupertinoColors.white.withValues(alpha: 0.3),
              width: 1,
            ),
          ),
          child: CupertinoButton(
            padding: EdgeInsets.zero,
            onPressed: onPressed,
            child: Icon(
              icon,
              size: size,
              color: onPressed != null
                  ? CupertinoColors.white
                  : CupertinoColors.white.withValues(alpha: 0.4),
            ),
          ),
        ),
      ),
    );
  }
}

/// Private fullscreen route used by [CupertinoMediaControls].
///
/// Mirrors the mechanism in MediaControls._toggleFullscreen: forces landscape,
/// hides system UI, and delegates rendering to [FullscreenMediaPlayer] whose
/// built-in controls own the single top bar.  No duplicate header or dead
/// buttons are added here.
class _CupertinoFullscreenPlayerRoute extends StatefulWidget {
  final MediaController controller;

  const _CupertinoFullscreenPlayerRoute({required this.controller});

  @override
  State<_CupertinoFullscreenPlayerRoute> createState() =>
      _CupertinoFullscreenPlayerRouteState();
}

class _CupertinoFullscreenPlayerRouteState
    extends State<_CupertinoFullscreenPlayerRoute>
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
      child: CupertinoPageScaffold(
        backgroundColor: CupertinoColors.black,
        child: SlideTransition(
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
