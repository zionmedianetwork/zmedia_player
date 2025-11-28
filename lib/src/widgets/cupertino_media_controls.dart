import 'dart:ui';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show Colors;
import '../core/media_controller.dart';
import '../models/player_state.dart';
import 'components/seek_bar.dart';
import 'components/time_display.dart';
import 'menus/settings_menu.dart';

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
  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;

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
    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeInOut, // iOS standard easing
    );
    _fadeController.forward();
  }

  @override
  void dispose() {
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
          // LIVE badge (lower left corner)
          AnimatedBuilder(
            animation: widget.controller,
            builder: (context, child) {
              final isLive = widget.controller.currentItem?.isLive ?? false;
              if (!isLive) return const SizedBox.shrink();

              return Positioned(
                left: 16,
                bottom: 16,
                child: TimeDisplay(
                  position: Duration.zero,
                  isLive: true,
                  style: const TextStyle(
                    color: CupertinoColors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                  liveColor: Colors.red,
                ),
              );
            },
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
                    _buildIOSButton(
                      icon: CupertinoIcons.rectangle_on_rectangle,
                      onPressed: () async {
                        await widget.controller.enterPictureInPicture();
                      },
                    ),

                  const SizedBox(width: 8),

                  // Settings button
                  if (widget.showSettings)
                    _buildIOSButton(
                      icon: CupertinoIcons.settings,
                      onPressed: _toggleSettings,
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
            ClipOval(
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
                      final value = duration.inMilliseconds > 0
                          ? position.inMilliseconds / duration.inMilliseconds
                          : 0.0;

                      return Row(
                        children: [
                          // Current time
                          TimeDisplay(
                            position: position,
                            format: TimeDisplayFormat.currentOnly,
                            style: TextStyle(
                              color: textColor,
                              fontSize: 13,
                              fontWeight: FontWeight.w400,
                            ),
                          ),

                          const SizedBox(width: 12),

                          // Seek bar
                          Expanded(
                            child: SeekBar(
                              value: value.clamp(0.0, 1.0),
                              duration: duration,
                              onChanged: (newValue) {
                                final seekTo = duration * newValue;
                                widget.controller.seekTo(seekTo);
                              },
                              activeColor: CupertinoColors.white,
                              inactiveColor:
                                  CupertinoColors.white.withValues(alpha: 0.3),
                              thumbColor: CupertinoColors.white,
                              trackHeight: 3.0,
                              thumbRadius: 7.0,
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
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          // Volume button
                          _buildIOSButton(
                            icon: CupertinoIcons.speaker_2_fill,
                            onPressed: () {
                              // Volume control (placeholder)
                            },
                          ),
                        ],
                      ),
                      Row(
                        children: [
                          // Fullscreen button
                          if (widget.showFullscreen)
                            _buildIOSButton(
                              icon: CupertinoIcons.fullscreen,
                              onPressed: () {
                                // Fullscreen toggle (placeholder)
                              },
                            ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// iOS-style button with minimal styling
  Widget _buildIOSButton({
    required IconData icon,
    required VoidCallback? onPressed,
  }) {
    return CupertinoButton(
      padding: const EdgeInsets.all(8),
      minimumSize: Size.zero,
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
