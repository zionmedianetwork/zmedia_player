import 'dart:ui';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show Colors, Material, MaterialType;
import 'package:flutter/services.dart';
import '../models/player_state.dart';
import 'components/seek_bar.dart';
import 'components/time_display.dart';
import 'fullscreen_controls_base.dart';
import 'menus/settings_menu.dart';

/// Cupertino (iOS) fullscreen media player
///
/// Optimized for fullscreen playback with:
/// - Landscape orientation lock
/// - Immersive system UI mode (iOS)
/// - Cupertino design language
/// - Exit fullscreen button
/// - Translucent blur effects
///
/// Example usage:
/// ```dart
/// Navigator.of(context).push(
///   CupertinoPageRoute(
///     builder: (context) => CupertinoFullscreenPlayer(
///       controller: mediaController,
///       title: 'Video Title',
///     ),
///   ),
/// );
/// ```
class CupertinoFullscreenPlayer extends FullscreenControlsBase {
  /// Custom title to display
  final String? title;

  /// Whether to show settings button
  final bool showSettings;

  /// Whether to show PiP button
  final bool showPip;

  /// Custom iOS brightness (light/dark)
  final Brightness? brightness;

  const CupertinoFullscreenPlayer({
    super.key,
    required super.controller,
    this.title,
    this.showSettings = true,
    this.showPip = true,
    this.brightness,
    super.lockOrientation = true,
    super.preferredOrientations = const [
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ],
    super.systemUiMode = SystemUiMode.immersiveSticky,
    super.hideSystemUI = true,
    super.onExitFullscreen,
  });

  @override
  Widget buildFullscreenControls(BuildContext context, ControlsState state) {
    final brightness = this.brightness ?? Brightness.dark;
    final isDark = brightness == Brightness.dark;

    return AnimatedOpacity(
      opacity: state.animationValue,
      duration: const Duration(milliseconds: 300),
      child: state.isVisible
          ? Container(
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
              child: Stack(
                children: [
                  // Main controls
                  Column(
                    children: [
                      // Top bar with title and exit button
                      _buildTopBar(context, isDark, state),

                      const Spacer(),

                      // Center play/pause button
                      _buildCenterControls(isDark, state),

                      const Spacer(),

                      // Bottom bar with seek and controls
                      _buildBottomBar(isDark, state),
                    ],
                  ),

                  // LIVE badge (lower left corner)
                  AnimatedBuilder(
                    animation: controller,
                    builder: (context, child) {
                      final isLive = controller.currentItem?.isLive ?? false;
                      if (!isLive) return const SizedBox.shrink();

                      return Positioned(
                        left: 16,
                        bottom: 80,
                        child: TimeDisplay(
                          position: Duration.zero,
                          isLive: true,
                          style: TextStyle(
                            color: isDark
                                ? CupertinoColors.white
                                : CupertinoColors.black,
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                          liveColor: CupertinoColors.systemRed,
                        ),
                      );
                    },
                  ),
                ],
              ),
            )
          : const SizedBox.shrink(),
    );
  }

  Widget _buildTopBar(BuildContext context, bool isDark, ControlsState state) {
    final iconColor = isDark ? CupertinoColors.white : CupertinoColors.black;

    return SafeArea(
      child: ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: (isDark ? CupertinoColors.black : CupertinoColors.white)
                  .withValues(alpha: 0.3),
            ),
            child: Row(
              children: [
                // Exit fullscreen button
                _buildCupertinoButton(
                  icon: CupertinoIcons.fullscreen_exit,
                  onPressed: () {
                    final widgetState = context
                        .findAncestorStateOfType<FullscreenControlsBaseState>();
                    widgetState?.exitFullscreen();
                  },
                  color: iconColor,
                ),

                const SizedBox(width: 16),

                // Title
                if (title != null)
                  Expanded(
                    child: Text(
                      title!,
                      style: TextStyle(
                        color: iconColor,
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),

                const Spacer(),

                // PiP button
                if (showPip)
                  _buildCupertinoButton(
                    icon: CupertinoIcons.rectangle_on_rectangle,
                    onPressed: () async {
                      await controller.enterPictureInPicture();
                    },
                    color: iconColor,
                  ),

                const SizedBox(width: 16),

                // Settings button
                if (showSettings)
                  _buildCupertinoButton(
                    icon: CupertinoIcons.settings,
                    onPressed: () {
                      _showSettingsMenu(context);
                    },
                    color: iconColor,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCenterControls(bool isDark, ControlsState state) {
    final iconColor = isDark ? CupertinoColors.white : CupertinoColors.black;

    return AnimatedBuilder(
      animation: controller,
      builder: (context, child) {
        final playerState = controller.state.state;
        final isPlaying = controller.isPlaying;
        final isLoading = playerState == PlayerState.buffering;

        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Skip backward
            _buildCupertinoButton(
              icon: CupertinoIcons.gobackward_10,
              onPressed: () {
                final currentPos = controller.position;
                final newPos = currentPos - const Duration(seconds: 10);
                controller.seekTo(
                  newPos.isNegative ? Duration.zero : newPos,
                );
              },
              color: iconColor,
              size: 40,
            ),

            const SizedBox(width: 32),

            // Play/Pause button
            if (isLoading)
              SizedBox(
                width: 64,
                height: 64,
                child: CupertinoActivityIndicator(
                  color: iconColor,
                  radius: 20,
                ),
              )
            else
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color:
                      (isDark ? CupertinoColors.white : CupertinoColors.black)
                          .withValues(alpha: 0.3),
                ),
                child: ClipOval(
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                    child: CupertinoButton(
                      padding: EdgeInsets.zero,
                      onPressed: controller.togglePlayPause,
                      child: Icon(
                        isPlaying
                            ? CupertinoIcons.pause_fill
                            : CupertinoIcons.play_fill,
                        color: iconColor,
                        size: 36,
                      ),
                    ),
                  ),
                ),
              ),

            const SizedBox(width: 32),

            // Skip forward
            _buildCupertinoButton(
              icon: CupertinoIcons.goforward_10,
              onPressed: () {
                final currentPos = controller.position;
                final duration = controller.duration;
                final newPos = currentPos + const Duration(seconds: 10);
                controller.seekTo(
                  newPos > duration ? duration : newPos,
                );
              },
              color: iconColor,
              size: 40,
            ),
          ],
        );
      },
    );
  }

  Widget _buildBottomBar(bool isDark, ControlsState state) {
    final iconColor = isDark ? CupertinoColors.white : CupertinoColors.black;

    return SafeArea(
      bottom: true,
      child: ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: (isDark ? CupertinoColors.black : CupertinoColors.white)
                  .withValues(alpha: 0.3),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Seek bar
                AnimatedBuilder(
                  animation: controller,
                  builder: (context, child) {
                    final position = controller.position;
                    final duration = controller.duration;
                    final value = duration.inMilliseconds > 0
                        ? position.inMilliseconds / duration.inMilliseconds
                        : 0.0;

                    return SeekBar(
                      value: value.clamp(0.0, 1.0),
                      duration: duration,
                      onChanged: (newValue) {
                        final seekTo = duration * newValue;
                        controller.seekTo(seekTo);
                      },
                      activeColor: CupertinoColors.white,
                      inactiveColor:
                          CupertinoColors.white.withValues(alpha: 0.3),
                      thumbColor: CupertinoColors.white,
                      trackHeight: 3,
                    );
                  },
                ),

                const SizedBox(height: 12),

                // Time and volume controls
                Row(
                  children: [
                    // Time display
                    AnimatedBuilder(
                      animation: controller,
                      builder: (context, child) {
                        return TimeDisplay(
                          position: controller.position,
                          duration: controller.duration,
                          style: TextStyle(
                            color: iconColor,
                            fontSize: 13,
                          ),
                        );
                      },
                    ),

                    const Spacer(),

                    // Volume button
                    AnimatedBuilder(
                      animation: controller,
                      builder: (context, child) {
                        final volume = controller.volume;
                        final isMuted = volume == 0;

                        return _buildCupertinoButton(
                          icon: isMuted
                              ? CupertinoIcons.volume_off
                              : volume < 0.5
                                  ? CupertinoIcons.volume_down
                                  : CupertinoIcons.volume_up,
                          onPressed: () {
                            if (isMuted) {
                              controller.setVolume(1.0);
                            } else {
                              controller.setVolume(0);
                            }
                          },
                          color: iconColor,
                        );
                      },
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

  Widget _buildCupertinoButton({
    required IconData icon,
    required VoidCallback onPressed,
    required Color color,
    double size = 24,
  }) {
    return CupertinoButton(
      padding: const EdgeInsets.all(8),
      minimumSize: Size.zero,
      onPressed: onPressed,
      child: Icon(
        icon,
        color: color,
        size: size,
      ),
    );
  }

  void _showSettingsMenu(BuildContext context) {
    showCupertinoModalPopup(
      context: context,
      builder: (context) => Material(
        type: MaterialType.transparency,
        child: SettingsMenu(
          controller: controller,
        ),
      ),
    );
  }
}
